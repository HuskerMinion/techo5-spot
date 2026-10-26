<p align="center">
  <img src="images/rook.png" alt="ROOK" width="160">
</p>

# TECHO5 Spot

**TECHO5 for the Echo Spot**: the TECHO5 Linux image, brought to the Amazon Echo Spot 1st
generation (2017, codename `rook`, model VN94DQ / `AEORK`).

The goal is the same end state [TECHO5](https://github.com/HuskerMinion/techo5) reached on the
Echo Show 5 2nd gen and TECHO5 Dot reached on the Echo Dot 2. No Fire OS userspace: a small Alpine
root filesystem and one daemon that owns the microphones, the speaker, the round screen, wake word
and the Home Assistant connection (ESPHome native API), with nothing leaving the house.

The daemon is TECHO5's `echod`, which is built on **[EchoLocal](https://github.com/ygelfand/echolocal)**
by Yuri Gelfand (MIT): EchoLocal's Echo Dot 2 daemon, vendored and developed further, much of it
still EchoLocal's code. See [NOTICE](NOTICE).

**Installing:** [Getting started](https://github.com/HuskerMinion/techo5/blob/main/docs/getting-started.md)
has every step from a stock Spot, in order: the Fire OS version, the amonet-rook unlock and LineageOS
(both linked), the installer, and Home Assistant. The installer is a Python 3 script that runs the same
on Windows, Linux and macOS and builds nothing: it downloads the signed release, Bluetooth kernel
included.
Building it yourself: [docs/building.md](docs/building.md).

## Status

First unit, 2026-09-16: unlocked and backed up (M0), then TECHO5 Linux from trial slots on the old
`system` partition (M2, M3): voice turns with Home Assistant, the round screen with a touch ring menu,
weather, timers and night dimming (M5), Bluetooth audio through a rebuilt kernel (M6), and TECHO5's
mark in place of Amazon's boot logo (M6b). `tools/install-spot.py` (M7) does it in one command from
LineageOS. What exists:

- [docs/hardware.md](docs/hardware.md): what is known about `rook` from the unlock, TWRP, LineageOS
  and kernel sources and a stock firmware dump, each fact with its source, and what the first unit
  confirmed or corrected.
- [docs/porting-plan.md](docs/porting-plan.md): milestones from a stock Spot to the Linux image, and
  what carries over from the Show and the Dot and what does not.
- [tools/hwdump.sh](tools/hwdump.sh): the read-only hardware inventory for the first time a unit is
  plugged in (Fire OS with root, or TWRP).
- [tools/backup-spot.py](tools/backup-spot.py): pulls every partition that boots the unit to the
  computer and checks each copy against an md5 read on the device. Writes nothing to the unit.
- [tools/install-spot.py](tools/install-spot.py): LineageOS to TECHO5 Linux in one command.
  [tools/techo5lib.py](tools/techo5lib.py) holds what it shares with TECHO5's and TECHO5 Dot's installers,
  including the USB serial console on Windows, Linux and macOS.
- [tools/linux/](tools/linux/): the kernel with Bluetooth (`build-kernel.sh`), the boot image
  (`build-image.sh`, `init`) and the root filesystem overlay (`rootfs/etc/techo5/device.conf`). The
  daemon and image tooling are TECHO5's (`spot` build).
- **Phone calls** (v0.1.0): through your own SIP provider, from Home Assistant or by voice, with an
  incoming-call face on the round screen (tap to answer, swipe to decline, tap to hang up). Setup is in
  TECHO5's [docs/phone.md](https://github.com/HuskerMinion/techo5/blob/main/docs/phone.md).
- **AirPlay and Spotify Connect** (spot-v1.4.8): the Spot can be a speaker an iPhone, iPad or Mac
  plays to over AirPlay 2, grouped with other AirPlay 2 speakers, or the Spotify app over Spotify
  Connect. Both are off until you turn them on, in Home Assistant or on the setup page. Setup is in
  TECHO5's [docs/setup.md](https://github.com/HuskerMinion/techo5/blob/main/docs/setup.md#5-music).
- **Updates** come from this repository's
  [releases](https://github.com/HuskerMinion/techo5-spot/releases), signed, through Home Assistant's
  update card into the spare slot; [tools/release-spot.ps1](tools/release-spot.ps1) publishes one
  (maintainer). The daemon's source is [TECHO5](https://github.com/HuskerMinion/techo5)'s `main`, built
  with `-tags spot`.
- [docs/dumps/](docs/dumps/): the LineageOS kernel's `rook_defconfig` and running config, and the
  difference from `cronos_defconfig`.

## The short version

The Spot is the Show 5's closest relative, not the Dot's: same MT8163, same LineageOS 4.9 kernel
tree (`rook_defconfig` beside `cronos_defconfig`), a screen, a camera, a single `boot` partition
rather than A/B slots. It differs in the radio: Wi-Fi and Bluetooth are a **Broadcom BCM43569**, Wi-Fi
over USB with the `bcmdhd` driver and Bluetooth over a UART, so neither the Show's `mt76x8` modules nor
the Dot's `wmtup` apply. It has about 2 GB of RAM, more than either.

## Using it

The Spot has no swipe-down settings or swipe-in camera like the Show. Everything is on the ring menu.

- **Press and hold** the clock to open the ring menu.
- **Turn your finger around the ring** to bring an item to the top, then lift your finger and tap the
  middle. A tap on any item goes straight to it.
- The menu closes by itself after a few seconds if you leave it alone.

The items, clockwise from the top:

| Item | What it does |
|---|---|
| Talk | Starts Assist, the same as a tap on the clock |
| Call | Your devices and contacts to call |
| Mute | Turns the microphones off or back on |
| Music | Radio stations, and Stop |
| Volume | Tap, then turn your finger around the ring |
| Weather | The forecast; swipe sideways for the rain map |
| Calendar | Today and what's next (only when a calendar is chosen) |
| Camera | This Spot's own camera. While a camera is up, swipe sideways for the next one, or press and hold for the list |
| Dashboard | Your Home Assistant dashboard, or back to the clock |
| Timers | Stops a timer that is ringing |
| Announce | Talk to every device in the house |
| Settings | Display, sound, alarms and the rest |
| Sleep | Turns the screen off; tap to wake it |

Other gestures on the clock: a tap starts Assist, swipe up or down for the volume, and swipe left or
right for the next clock style (when **Swipe between clock styles** is on).

### Night

At night the Spot can dim, as it always has, show the night clock, or turn the screen off. The night
clock is the time alone in dim red on black, with the backlight turned down to almost nothing, like
the Show's.

- **Settings → Display → Night hours**: when the night starts and ends. 10 PM to 7 AM unless you
  change it.
- **At night**: *Dim*, *Night clock* or *Screen off*.
- **Night clock**: the look. *Red*, *Red LED* or *Flip*.
- **Night clock brightness**: shown when At night is *Night clock*. 1 to 10; the lowest step is a
  faint glow. At night, changes show on the screen as you make them.

The night clock comes about 10 seconds after Settings or the ring menu closes, when the night starts
and when Night clock is chosen, and otherwise once the Spot has been left alone for a minute and a
half. With Screen off, the screen always waits for that minute and a
half alone. A tap lights the screen, dimmed, and the night clock comes back (or the screen goes off
again) a minute and a half after the last touch. Press and hold to light it and open the ring menu in
one go.

With the night clock, an alarm or a timer rings over it, and a tap anywhere stops it. Calls, Assist
answers, announcements, reminders and cameras show over it at the same low light, and the clock comes
back after. With Screen off, alarms, timers, calls, reminders, announcements and the light before an
alarm turn the screen on, dimmed, and it goes off again once they're done. When the night ends the
screen comes back on, unless you turned it off yourself with Sleep.

In Home Assistant these are **Night hours**, **Night starts**, **Night ends**, **Screen at night**,
**Night clock style**, **Night light brightness** (1 to 10, how bright the night clock is: the same
setting as Night clock brightness on the Spot) and the **Night mode** switch, the same names as on
the Show, so automations made for a Show work on a Spot.

## Lineage

- [TECHO5](https://github.com/HuskerMinion/techo5) (MIT): the daemon (`echod`), the Linux image
  tooling, the rootfs slot design and the kernel build recipe this port starts from.
- [TECHO5 Dot](https://github.com/HuskerMinion/techo5-dot) (MIT): the 512 MB image, the hand-made `/dev`, the installer pattern.
- [EchoLocal](https://github.com/ygelfand/echolocal) (MIT, Yuri Gelfand): the daemon TECHO5's `echod`
  is built on (see above).
- amonet, kaeru and the Echo TWRP trees ([R0rt1z2](https://github.com/R0rt1z2), k4y0z): the unlock.
- [amazon-oss](https://github.com/amazon-oss): the LineageOS 18.1 `rook` device tree and the 4.9
  kernel it builds.

## Image credits

- The ROOK badge: a white chess rook. Photo by MichaelMaggs,
  [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Chess_piece_-_White_rook.JPG),
  [CC BY-SA 2.5](https://creativecommons.org/licenses/by-sa/2.5/); the cropped badge is CC BY-SA 2.5 too.

## License

MIT. See [LICENSE](LICENSE), and [NOTICE](NOTICE) for the other projects this builds on and the
GPL-2.0 kernel every release ships.

TECHO5 is not affiliated with Amazon. Echo, Echo Spot and Alexa are trademarks of Amazon.com, Inc.
