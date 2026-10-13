# atkctl

Configure ATK and VXE mice on macOS from the terminal, without ATK Hub. It reads firmware versions, battery and settings, changes polling rate, DPI, sleep time and the sensor options, pairs the mouse with its receiver, and finds the macOS problems that make the receiver look dead.

```
$ atkctl
NK mouse NANO dongle      firmware 1.0.19   connected
mouse (via receiver)      firmware 1.0.14   battery 100%   receiver, 1K

  polling         1000 Hz
  dpi             1600   (stage 3 of 4)
  lift-off        1.2 mm
  sleep           2 min
  debounce        4 ms
  motion-sync     on
  ripple          off
  angle-snapping  off
```

## Quick start

```bash
git clone https://github.com/cobanov/atkctl && cd atkctl
swift build -c release
cp .build/release/atkctl ~/.local/bin/
atkctl doctor
```

Needs macOS 13 or later and the Swift toolchain that comes with Xcode or the Command Line Tools. The mouse works through its receiver or its cable; with both plugged in, `atkctl` talks over the cable.

## Commands

| Command | Does |
|---|---|
| `atkctl` / `atkctl status [--json]` | Firmware of mouse and receiver, battery, connection, current settings |
| `atkctl dpi` | DPI stages, the active one starred |
| `atkctl set <setting> <value>` | Changes a setting, then reads it back from the mouse |
| `atkctl pair [--yes]` | Pairs the mouse with the plugged-in receiver (forgets the old pairing) |
| `atkctl doctor [--fix-karabiner]` | Finds what stops the mouse or ATK Hub from working |
| `atkctl list` | Connected ATK / VXE devices |
| `atkctl raw <command> [payload…]` | Sends one request and prints the reply in hex, for working out other models |

| Setting | Values |
|---|---|
| `sleep` | `30s` `1m` `2m` `3m` `5m` `20m` `25m` `30m` |
| `polling` | `125` `250` `500` `1000` `2000` `4000` `8000` (what the mouse and receiver support) |
| `debounce` | `0` `1` `2` `4` `8` `15` `20` (ms) |
| `motion-sync`, `ripple`, `angle-snapping` | `on` / `off` |
| `lift-off` | `0.7` to `1.7` (mm, in 0.1 steps) |
| `dpi` | `<stage> <value>`, for example `atkctl set dpi 2 1600` (both axes, multiples of 50) |

Every setting is one ATK Hub can also change, and can be changed back from ATK Hub. Firmware updates are left to ATK Hub on purpose: they go through the bootloader, and a failed one can brick the mouse.

## When the receiver looks dead

`atkctl doctor` checks for these:

- **Karabiner-Elements grabs the receiver.** The receiver reports itself as a keyboard as well as a mouse, so Karabiner takes it over and nothing else can talk to it. ATK Hub then fails with *Device initialization failed* and pairing never starts. `atkctl doctor --fix-karabiner` adds an ignore rule for it (and backs up `karabiner.json`); unplug and replug the receiver afterwards.
- **Secure Input is on.** While the screen is locked, or a password field has focus, macOS refuses to send reports to devices that act as keyboards, the receiver included. Unlock and run the command again.
- **Input Monitoring is not allowed.** macOS asks before a program may open input devices. If `atkctl` reports that access was denied, allow your terminal app under System Settings › Privacy & Security › Input Monitoring.
- **The receiver has no mouse.** The receiver answers, but no mouse is paired or connected: run `atkctl pair`.
- **Firmware mismatch.** Mouse and receiver need the same major firmware version to pair.

## Supported devices

The device list is the one ATK Hub drives with this protocol: about seventy ATK and VXE mice and receivers, NearLink (NK) and 2.4 GHz alike. It has been tested with an **ATK A9 Plus NK** (`0x1263`) and its **NK mouse NANO dongle** (`0x1216`); `atkctl list` marks the others `[untested]`. Reports from other models are welcome.

## How it works

ATK Hub is a web app that talks to the mouse over WebHID. `atkctl` speaks the same protocol through IOKit: 63-byte requests on HID output report 8 of the vendor usage page `0xFF05`, answered on input report 8. The receiver forwards anything addressed to the mouse. The format and the commands are written up in [docs/PROTOCOL.md](docs/PROTOCOL.md).

The library part, `ATKKit`, can be used on its own:

```swift
import ATKKit

let session = Session()
print(try session.firmwareVersion(), try session.battery().percent)
print(try session.dpiTable().active?.x ?? 0)
try session.setSleep(seconds: 120)
```

## Build from source

```bash
swift build          # debug build in .build/debug/atkctl
swift test           # protocol tests, using replies recorded from a real mouse
```

## License

MIT. Not affiliated with ATK or VXE; the names are used only to say which devices this works with.
