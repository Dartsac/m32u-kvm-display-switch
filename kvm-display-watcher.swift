// kvm-display-watcher
// Sleeps until macOS reports that the Gigabyte M32U's USB control device
// (Realtek HID Device, 0x0BDA:0x1100) connected or disconnected, or that the
// MacBook's built-in screen turned on (lid opened, or the Mac woke up).
// The M32U KVM pairs its USB-C upstream with HDMI 1, so:
//   device connected    -> monitor shows the HDMI 1 device -> mirror to the MacBook
//   device disconnected -> monitor shows the Mac           -> restore the extended layout
// When the built-in screen turns on without the device present, the extended layout is
// restored only if this watcher made the current mirror, so a manual mirror is left alone.
// Usage: kvm-display-watcher [path/to/toggle-mirror.sh]   (default: ~/bin/toggle-mirror.sh)
import AppKit
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

// Returns true when the layout is now in the requested mode.
@discardableResult
func run(_ mode: String) -> Bool {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/bin/bash")
  p.arguments = [script, mode]
  let pipe = Pipe()
  p.standardOutput = pipe
  p.standardError = pipe
  do { try p.run() } catch { log("Failed to run script: \(error)"); return false }
  p.waitUntilExit()
  let out = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    .trimmingCharacters(in: .whitespacesAndNewlines)
  log("toggle-mirror.sh \(mode): \(out)")
  return p.terminationStatus == 0 && (out.contains("Switched to") || out.contains("Already in"))
}

// True while the current mirror was made by this watcher (not by a manual shortcut).
var watcherMirrored = false

func mirror() { if run("mirror") { watcherMirrored = true } }
func extend() { if run("extend") { watcherMirrored = false } }

// Wait until events stop for a moment, then act on the current state.
var pending: DispatchWorkItem?
var pendingUSB = false
func scheduleSync(reason: String, usb: Bool) {
  log("Event: \(reason)")
  pending?.cancel()
  pendingUSB = pendingUSB || usb
  let work = DispatchWorkItem {
    let usbEvent = pendingUSB
    pendingUSB = false
    let present = devicePresent()
    log(describe(present))
    if present {
      mirror()
    } else if usbEvent || watcherMirrored {
      extend()
    } else {
      log("Leaving the layout alone (not mirrored by this watcher)")
    }
  }
  pending = work
  DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
}

let port = IONotificationPortCreate(kIOMainPortDefault)
CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)

var addIter: io_iterator_t = 0
var removeIter: io_iterator_t = 0
IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching(),
  { _, it in if drain(it) > 0 { scheduleSync(reason: "USB connected", usb: true) } }, nil, &addIter)
IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching(),
  { _, it in if drain(it) > 0 { scheduleSync(reason: "USB disconnected", usb: true) } }, nil, &removeIter)

// The lid can open while the monitor shows HDMI 1, without any USB event.
// React only when the built-in screen is added or enabled, so manual layout changes are left alone.
CGDisplayRegisterReconfigurationCallback({ display, flags, _ in
  guard CGDisplayIsBuiltin(display) != 0,
        !flags.contains(.beginConfigurationFlag),
        flags.contains(.addFlag) || flags.contains(.enabledFlag) else { return }
  DispatchQueue.main.async { scheduleSync(reason: "MacBook screen turned on", usb: false) }
}, nil)

// Arm the notifications. At startup, only act if the monitor is already on HDMI 1.
let presentAtStart = drain(addIter) > 0
_ = drain(removeIter)
log("Started. \(describe(presentAtStart))")
if presentAtStart { mirror() }

// Display reconfiguration callbacks are only delivered to a running NSApplication.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)  // no Dock icon, no menu bar
app.run()
