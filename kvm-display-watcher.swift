// kvm-display-watcher
// Sleeps until macOS reports that the Gigabyte M32U's USB control device
// (Realtek HID Device, 0x0BDA:0x1100) connected or disconnected.
// The M32U KVM pairs its USB-C upstream with HDMI 1, so:
//   device connected    -> monitor shows the HDMI 1 device -> mirror to the MacBook
//   device disconnected -> monitor shows the Mac           -> restore the extended layout
// Usage: kvm-display-watcher [path/to/toggle-mirror.sh]   (default: ~/bin/toggle-mirror.sh)
import Foundation
import IOKit

let vendorID = 0x0BDA
let productID = 0x1100
let script = CommandLine.arguments.count > 1
  ? CommandLine.arguments[1]
  : NSString(string: "~/bin/toggle-mirror.sh").expandingTildeInPath
let debounceSeconds = 1.5

let fmt = DateFormatter()
fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
func log(_ s: String) { print("\(fmt.string(from: Date()))  \(s)"); fflush(stdout) }

func matching() -> CFMutableDictionary {
  let d = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
  d["idVendor"] = vendorID
  d["idProduct"] = productID
  return d as CFMutableDictionary
}

func drain(_ it: io_iterator_t) -> Int {
  var n = 0
  while case let s = IOIteratorNext(it), s != 0 { n += 1; IOObjectRelease(s) }
  return n
}

func devicePresent() -> Bool {
  var it: io_iterator_t = 0
  guard IOServiceGetMatchingServices(kIOMainPortDefault, matching(), &it) == KERN_SUCCESS else { return false }
  defer { IOObjectRelease(it) }
  return drain(it) > 0
}

func describe(_ present: Bool) -> String {
  "M32U USB control device \(present ? "present (HDMI 1)" : "absent (Mac)")"
}

func run(_ mode: String) {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/bin/bash")
  p.arguments = [script, mode]
  let pipe = Pipe()
  p.standardOutput = pipe
  p.standardError = pipe
  do { try p.run() } catch { log("Failed to run script: \(error)"); return }
  p.waitUntilExit()
  let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  log("toggle-mirror.sh \(mode): \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
}

// Wait until USB events stop for a moment, then act on the current state.
var pending: DispatchWorkItem?
func scheduleSync(reason: String) {
  log("USB event: \(reason)")
  pending?.cancel()
  let work = DispatchWorkItem {
    let present = devicePresent()
    log(describe(present))
    run(present ? "mirror" : "extend")
  }
  pending = work
  DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
}

let port = IONotificationPortCreate(kIOMainPortDefault)
CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)

var addIter: io_iterator_t = 0
var removeIter: io_iterator_t = 0
IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching(),
  { _, it in if drain(it) > 0 { scheduleSync(reason: "connected") } }, nil, &addIter)
IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching(),
  { _, it in if drain(it) > 0 { scheduleSync(reason: "disconnected") } }, nil, &removeIter)

// Arm the notifications. At startup, only act if the monitor is already on HDMI 1.
let presentAtStart = drain(addIter) > 0
_ = drain(removeIter)
log("Started. \(describe(presentAtStart))")
if presentAtStart { run("mirror") }

RunLoop.main.run()
