# M32U KVM display switch

Press the KVM button on a Gigabyte M32U and your MacBook switches its screens automatically:

- **Monitor switches to HDMI 1 (for example a PS5):** the Mac mirrors everything onto the MacBook's built-in screen, optimized for the MacBook.
- **Monitor switches back to the Mac:** the Mac restores your normal extended layout, with the same resolution and refresh rate as before. A fixed 144 Hz setting stays 144 Hz and does not change to "Variable".

Your keyboard and mouse stay with the Mac the whole time.

## Why this is needed

When the M32U switches to another input, the DisplayPort connection stays active, so macOS still sees two screens. Windows and the cursor can end up on a screen you cannot see. macOS gets no signal when the KVM button is pressed.

## How it works

1. The M32U's KVM moves the monitor's built-in USB hub between its two upstream ports. In this setup, **USB-C is paired with HDMI 1**.
2. A USB-C cable connects the monitor's USB-C port to the Mac (through the dock). When the monitor switches to HDMI 1, the monitor's USB control device (Realtek `0x0BDA:0x1100`) appears on the Mac. When it switches back, the device disappears.
3. `kvm-display-watcher` asks macOS to wake it when that USB device connects or disconnects. It sleeps the rest of the time, using 0% CPU and about 9 MB of memory.
4. When it wakes up, it waits 1.5 s for USB activity to settle, then runs `toggle-mirror.sh mirror` or `toggle-mirror.sh extend`.
5. `toggle-mirror.sh` uses `displayplacer` to change the layout. Before it mirrors, it saves the current extended layout by exact mode number, then restores that layout later.

## Requirements

- A Mac with a built-in screen (MacBook). The lid must be open; the script does nothing while the built-in screen is off.
- Exactly **one** external display: a Gigabyte M32U. The script does nothing if two or more external displays are connected.
- [displayplacer](https://github.com/jakehilborn/displayplacer): `brew install displayplacer`
- Xcode Command Line Tools, for `swiftc`: `xcode-select --install`
- The M32U connected to the Mac for video (DisplayPort or a dock).
- A **USB-C to USB-C cable** from the M32U's USB-C port to a **plain USB-C data port** on the Mac or dock. Do not use a Thunderbolt port, because the monitor's USB-C port also accepts video.
- M32U KVM setting (OSD → KVM): `USB-B : DisplayPort <--> Type-C : HDMI 1`.

## Setup this was built and tested on

| Part | Details |
|---|---|
| Computer | MacBook Pro (Apple Silicon), lid open |
| Dock | CalDigit TS4 |
| Monitor | Gigabyte M32U, 1920×1080 HiDPI at fixed 144 Hz |
| Video to the monitor | TS4 DisplayPort → M32U DisplayPort |
| USB to the monitor | TS4 plain USB-C port → M32U USB-C port |
| Other input | PS5 on M32U HDMI 1 |
| Keyboard and mouse | Plugged into the TS4, so they always stay with the Mac |

## Install

```bash
./install.sh
```

This installs:

- `~/bin/toggle-mirror.sh`
- `~/bin/kvm-display-watcher` (compiled from `kvm-display-watcher.swift`)
- `~/Library/LaunchAgents/local.m32u-kvm-display-watcher.plist`, which starts the watcher at login and restarts it if it stops

The watcher logs each switch to `~/Library/Logs/m32u-kvm-display-watcher.log`. The saved extended layout is kept in `~/.config/display-toggle/extended-layout`.

## Manual use

```bash
~/bin/toggle-mirror.sh          # toggle
~/bin/toggle-mirror.sh mirror   # mirror, optimized for the MacBook screen
~/bin/toggle-mirror.sh extend   # restore the saved extended layout
```

To use a keyboard shortcut, create a shortcut in the Shortcuts app with a **Run Shell Script** action that runs `~/bin/toggle-mirror.sh`, then add a keyboard shortcut to it. The watcher only acts on KVM switches, so it does not undo a manual change.

## Limits

- **Other inputs (HDMI 2, for example a Nintendo Switch):** this has not been tested. The watcher only reacts if the monitor moves its USB hub to USB-C for that input. If it does not, use the manual shortcut.
- **Mode numbers** can change if the monitor is connected through a different port or cable. If the monitor comes back at the wrong refresh rate, set it in System Settings → Displays, then switch once with the KVM button. The new layout is saved the next time the Mac mirrors.
- **Other monitors:** the USB IDs in `kvm-display-watcher.swift` are for the M32U. For another KVM monitor, find the USB device that appears when the monitor switches away from the Mac (`ioreg -p IOUSB -l -w0`), then change `vendorID` and `productID`.

## Uninstall

```bash
./uninstall.sh
```
