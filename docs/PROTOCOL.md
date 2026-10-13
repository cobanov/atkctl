# ATK / VXE "BitMouse" protocol

What `atkctl` sends, as read from ATK Hub 3.2.27 (`hub.atk.pro`) and checked against an ATK A9 Plus NK and its NK NANO dongle. ATK Hub calls this family's driver `bitmouse`.

## Transport

- USB vendor ID `0x373B`. The control channel is the HID collection with usage page `0xFF05`, usage `1`.
- Requests are **output report 8**, 63 bytes after the report ID. Replies come back as **input report 8** in the same layout.
- A reply belongs to the request whose command byte it echoes. ATK Hub waits 500 ms and retries three times.

## Packet

| Byte | Field | Notes |
|---|---|---|
| 0 | checksum | sum of bytes 1–62, low byte |
| 1 | class | always `0x72` |
| 2 | param length | see the table below; in a reply, `0xFF` means error |
| 3 | sequence | `0` |
| 4 | target | `0` the device itself, `1` the mouse behind a receiver |
| 5 | command | |
| 6 | payload length | |
| 7… | payload | request arguments, or the reply's values |

Through a receiver, mouse commands are sent with target `1` and the receiver forwards them. Receiver commands (`0x81`–`0x88`, and `0x1A`) use target `0`.

## Commands

| Code | Command | param / payload | Request payload | Reply value (from byte 7) |
|---|---|---|---|---|
| `0x01` | set report rate | 3 / 1 | rate code | |
| `0x02` | set DPI stage | 12 / 10 | index, x u16, y u16, blue, green, red, 0, active | |
| `0x07` | battery level | 2 / 1 | | percent |
| `0x09` | current config | 19 / 17 | | see below |
| `0x0B` | angle snapping | 3 / 1 | 0 / 1 | |
| `0x0C` | ripple control | 3 / 1 | 0 / 1 | |
| `0x0D` | motion sync | 3 / 1 | 0 / 1 | |
| `0x0F` | charging status | 2 / 1 | | `1` charging |
| `0x15` | sleep time | 5 / 2 | seconds u16 | |
| `0x16` | debounce | 3 / 1 | milliseconds | |
| `0x17` | read settings memory | 10 / 13 | address u16, length | data from byte 10 |
| `0x1A` | connection type | 2 / 1 | | see below |
| `0x1C` | mouse firmware | 5 / 3 | | major, minor, patch |
| `0x81` | receiver link | 3 / 1 | | `1` mouse connected |
| `0x82` | start pairing | 3 / 0 | | |
| `0x83` | forget pairing | 3 / 0 | | |
| `0x84` | pair status | 3 / 1 | | `1` paired |
| `0x88` | receiver firmware | 5 / 3 | | major, minor, patch |

All integers are little-endian.

**Report rate codes:** 1000 Hz `0`, 500 `1`, 250 `2`, 125 `3`, 8000 `4`, 4000 `5`, 2000 `6`.

**Connection type:** `0` receiver 1K, `1` receiver 4K, `2` cable 1K, `3` cable 8K, `4` receiver 2K, `5` receiver 8K, `6` cable 2K, `7` cable 4K.

**Current config (`0x09`)**, offsets from byte 7: `0` profile, `1` version, `2` report rate code, `3–4` DPI, `5` lift-off level − 1, `6` motion sync, `7` angle snapping, `8` ripple control, `9–10` sleep seconds, `11` debounce ms, `12–16` button types.

**DPI table:** 70 bytes of settings memory from address `1`, read in seven 10-byte blocks. Byte `0` is the active stage, `1` the number of stages, then up to eight 8-byte stages: x u16, y u16, blue, green, red, alpha.

**Pairing:** ATK Hub sends forget (`0x83`) then start (`0x82`) to the receiver, then polls `0x81` until the mouse connects. The mouse enters pairing mode when left, right and wheel are held together.

## Not covered

Firmware updates use a separate bootloader channel (usage pages `0xFFB1` / `0xFFB3`, report 9) and encrypted images. `atkctl` does not touch them.
