# Porting plan

Target: an unlocked Echo Spot (`rook`) boots the TECHO5 Linux image. That means an arm64 4.9 kernel,
an Alpine armv7 root filesystem in trial slots, and one daemon (`echod`, `spot` build) that owns the
microphones, the speaker, the round screen and touch, the buttons, Wi-Fi and the ESPHome API. No Fire
OS or Android processes. As in TECHO5 and TECHO5 Dot, every milestone leaves a usable device and
recovery is proven before the first flash.

Facts and sources for everything below are in [hardware.md](hardware.md).

## How this relates to TECHO5 and TECHO5 Dot

The Spot is the Show 5's sibling more than the Dot's, with twice its memory and a different radio.

| | Show 5 (`cronos`) | Dot 2 (`biscuit`) | Spot (`rook`) |
|---|---|---|---|
| Kernel for the image | LineageOS 4.9.337 arm64 | Amazon 3.18 32-bit (Fire OS 6) | **LineageOS 4.9.337 arm64, `rook_defconfig`** (same tree as cronos) |
| Partitions | single `boot` | A/B, image in `recovery` | single `boot` |
| RAM | 1 GB | 512 MB | **2 GB** |
| Screen | 960×480 | none | 480×480 round |
| Microphones | TLV320AIC3101 + FPGA over SPI | 4× TLV320ADC3101, TDM | TLV320AIC3101 + FPGA over SPI, 4 mics |
| Wi-Fi | MT7668 SDIO, `mt76x8_wlan.ko` | CONSYS WMT, `wmtup` | **BCM43569 USB, `bcmdhd.ko`** |
| Bluetooth | MT7668, BlueZ via `btbridge` | raw H4 on `/dev/stpbt` | **BCM43569, H4 on `/dev/ttyMT1`** |

What carries over:

- **Kernel**: TECHO5's `tools/linux/build-kernel.sh` with `rook_defconfig` in place of
  `cronos_defconfig`, pinned to the commit the LineageOS rook boot image was built from so its
  `amzn-bcmdhd.ko` still loads (`CONFIG_MODVERSIONS`, the same rule cronos has). The Bluetooth
  additions become simpler: the chip speaks H4 on a real UART, so `CONFIG_BT` + `CONFIG_BT_HCIUART`
  (+ `BT_HCIUART_BCM`) and BlueZ's `btattach`/`hciattach` with the `.hcd` patch replace `btbridge`.
- **Image**: TECHO5's layout as it is. Kernel + initramfs rescue in `boot`, rootfs slots as directories
  on the `system` partition, TWRP left in `recovery`, state on `userdata`. `slotctl`, trial boots and
  the rescue environment unchanged. With 2 GB of RAM there is no memory pressure to design around.
- **Daemon**: one source. TECHO5's `echod` today has two builds, the default (cronos, screen) and
  `dot` (no screen). The Spot needs a third, `spot`: the screen, touch and camera code of the default
  build, with its own microphone device and channel map, button codes, backlight path and mixer
  sequences. The display code learns a round 480×480 canvas (see "The round screen"). Changes land in
  TECHO5's `echod`, not here.
- **Microphones**: cronos already reads the TLV320AIC3101 through the FPGA; its capture code and the
  "a bare Linux boot leaves the codec unconfigured" lessons are the starting point. The Spot's
  bitstream is 6-channel, so the channel map is new work.

What does not carry over: `mt76x8` modules, `wmtup`, `btbridge`, the MAX98396 speaker notes, the
Dot's `recovery`-partition boot and its cache-partition store.

## M0 — Know the unit (first time it is plugged in)

Before anything is written:

1. Inspect the screen for the flicker/shake fault. Note the Fire OS version (Settings → Device Options
   → Device Software Version) and whether it is one amonet-rook supports (5.5.6.9, 5.5.5.2, 5.5.3.4).
2. Unlock with amonet-rook v2.0.0: fastboot (Volume Up + Volume Down + Mute at power-on), then
   `fastbrick.bat` from Windows. It leaves TWRP in `recovery`; on the bench unit userdata survived.
   **Done on the bench unit 2026-09-16.**
3. From TWRP's adb: `tools/hwdump.sh`, saved as `docs/dumps/rook-twrp-<serial>.txt`. **Done.**
4. `tools/backup-spot.ps1 -Serial <serial> -IncludeSystem`: every partition that boots the unit plus
   Fire OS's system and cache, md5-checked, kept off the device. **Done.**
5. **Prove recovery before anything is written**: restore `boot` from its backup in TWRP and boot it.
   **Done**: `boot` written back and Fire OS booted; `system` restored from its backup after a
   dm-verity hang (hardware.md, "Fire OS puts its own recovery back").
6. Answer the open questions in hardware.md.

## M1 — LineageOS as the known-good baseline

**Installed and verified 2026-09-16** (hardware.md, "On LineageOS 18.1"): Wi-Fi on 5 GHz, the sound card
with the AIC3101 capture and AIC3204 playback PCMs, the round 480×480 display, touch. Still to do here:
the daemon beside Android and a voice turn.

**M1 done 2026-09-16.** `tools/install-spot.ps1` installed the `spot` build (TECHO5 branch `spot/daemon`) beside
LineageOS with the null audio HAL; Home Assistant added it from its zeroconf discovery with the key (adding
by address fails: Home Assistant opens a plaintext connection first and the daemon refuses it). Verified on
the unit: wake word, a voice turn answered through the speaker, software mute on and off from the button.
The entity names match the Echo it replaced in the house, so automations kept working after the old
Alexa Media Player device was removed and the new speaker entity renamed to the old one's id; Alexa-only
actions (announcements, "play … on" commands) were moved to `assist_satellite.announce` and the house's
radio script.

Install the unofficial LineageOS 18.1 for rook (XDA thread in hardware.md). It proves the display,
touch, Wi-Fi and audio on the 4.9 kernel, supplies the boot image whose kernel the Linux image reuses
and the `vendor` tree (the `bcmdhd` module and firmware, audio tuning), and gives a second
`hwdump` with Android's view of the hardware (`tinymix`, `getevent`, `dumpsys`).

Then, as on cronos, run the daemon beside Android as an init service with Android's audio HAL set
to null, and complete a voice turn with Home Assistant. That is the `spot` build's first test and it
needs no Linux image.

## M2 — First Linux boot (initramfs)

TECHO5's initramfs with the LineageOS rook kernel, flashed to `boot` (LineageOS's boot image is the
backup). Success is a root shell on the USB ACM gadget (the 4.9 kernel has configfs gadgets:
`CONFIG_USB_CONFIGFS_ACM`), then:

- Wi-Fi: `insmod amzn-bcmdhd.ko` with `firmware_path`/`nvram_path` pointing at the copied firmware,
  `wlan0`, Alpine's `wpa_supplicant` and `udhcpc`. No patch-download dance: that is the chip's own
  driver's job here.
- The clock (NTP, then `hwclock -w`) and dropbear.

**First boot done 2026-09-16.** `tools/linux/build-image.sh` builds the LineageOS rook kernel with TECHO5's
rescue initramfs (`tools/linux/init`: the Spot's partitions, `amzn-bcmdhd.ko`), flashed to `boot`. With
LineageOS still on `system` it runs as the rescue environment and takes everything from there: from power
to the Kitchen daemon in 16 s (USB console at 4 s, `wlan0` up at 8 s, an address at 12 s, dropbear, NTP,
the daemon from `/system/bin/techo5`), Home Assistant reconnected, no Android running. One fix it needed,
in TECHO5's `techo5-lib.sh`: the USB `bcmdhd` re-enumerates after its firmware download, so `wlan0` exists
a moment before it can be opened; `t5_wifi_up` now retries the link-up instead of starting the supplicant
on an interface that is down. wpa_supplicant 2.9 (the Show's) associates on 5 GHz with WPA2.

Back to LineageOS at any time: `fastboot flash boot backups/<serial>/boot-lineage-18.1.img`.

Watch out when several TECHO5 Linux units share a PC: every image offers the same USB serial console
(`1d6b:0104`, serial "techo5"). Identify a console by what the unit says (its serial in `/proc/cmdline`),
never by the COM port.

## M3 — Persistent rootfs with trial slots

TECHO5's store on `system`, its `slotctl`, `mkrootfs.sh` and `deploy-rootfs.sh`, with the LineageOS
`vendor` tree copied into the slot. Verified the TECHO5 way: slot a boots, the daemon runs five
minutes and commits, slot b installs from the running system, switch and commit.

**Done 2026-09-16.** `system` (p11) is the store (`slotctl mkstore`), slot a holds `v0.0.1-spot`, built
in WSL by TECHO5's `deploy-rootfs.sh` with `BUILD_TAGS=spot`, the Spot's vendor tarball and this
repository's `tools/linux/rootfs` overlay (`etc/techo5/device.conf`: partitions, `amzn-bcmdhd.ko`, no
Bluetooth module, the USB name). From power: slot a at 4.5 s, `wlan0` at 8 s, an address at 17 s, the daemon
at 22 s, Home Assistant connected. LineageOS is gone from the Spot; `boot` stays the rescue image.

Two things the first install met: the rescue initramfs has no `scp` receiver, so the tarball went over
`ssh … "cat > file"`; and its `mkfs.ext4` needed `libgcc_s` (libeconf), now added to the image by
`tools/linux/build-image.sh` (the first mkstore borrowed the library from the rootfs tarball).

## M4 — Audio

1. Capture: find the PCM and format, map the four microphones and the loopback, prove it with
   `audioprobe` and a WAV off the device.
2. Speaker: the AIC32x4 path, `Right Channel Only`, amp enable and the fault GPIO, volume curve.
3. Wake word and a full voice turn from the Linux image.
4. Echo cancellation: the WebRTC helper (`tools/aec`) on the loopback; measure before tuning, the way
   TECHO5 Dot's `microphones.md` does.

## M5 — The round screen, touch and camera

Covered in "The round screen" below; the daemon draws it, as on cronos. Camera last, and only if the
4.9 kernel exposes the GC0312.

## M6 — Bluetooth

Kernel with `CONFIG_BT`, `CONFIG_BT_HCIUART`, `CONFIG_BT_HCIUART_BCM`; `btattach -B /dev/ttyMT1 -P bcm`
with the `.hcd` patch, rfkill unblocked. Then BlueZ and bluez-alsa as on cronos, for earbuds or a
speaker, and a BLE proxy for Home Assistant. Wi-Fi and Bluetooth share one chip and antenna, so keep
the coexistence rule from cronos (pause idle A2DP).

## M6b — TECHO5 boot logos

Replace Amazon's boot screens with TECHO5's, as the Show got: the bootloader's logo partition (`logo`,
p5, 1 MB, backed up) and the image kaeru draws in hacked fastboot, then the Linux initramfs's own
splash. TECHO5's `tools/linux/patch-lk-logo.py` and its kaeru rebuild are the starting point; the
Spot's images are 480×480 and have to read inside the circle. The originals stay in `backups/`.

## M7 — Installer

`tools/install-spot.ps1`: one command from an unlocked, TWRP'd Spot to a running image, on the model
of TECHO5 Dot's `install-dot.ps1` (backups verified, the boot image built from this unit's own
backup, the rootfs slot laid down, name/key/Wi-Fi provisioned, read back and verified, the first boot
watched to healthy).

## The round screen

Everything drawn has to live in a 480×480 circle: the corners are not visible. Rules for the `spot`
layouts:

- Content in the inscribed circle; the safe rectangle for text is about 340×340 centred.
- Radial elements first: progress, volume, timers and "listening" as arcs around the rim, the way the
  stock Alexa UI does.
- One face at a time, changed by horizontal swipe; the settings sheet from a swipe down, as on cronos.
- Screen off at night on a schedule and on the ambient light sensor (cronos's night screen-off).

### Face ideas

From TECHO5's existing pages, and from owners who have already put a Spot on their desk (Reddit
r/amazonecho, 2026-09; spotdash). None of these need Android; each is a daemon page fed by Home
Assistant or by the house's own services, never the cloud:

- **Clock**: analogue and digital faces, the weather on it, the next calendar event under it.
- **Weather**: now and forecast; a radar frame from Home Assistant's camera proxy.
- **Timer / countdown**: goes full screen as a ring that empties, with the alarm on the speaker.
- **Now playing**: album art in the circle, play/pause/skip, volume on the rim (Music Assistant or
  any `media_player` in Home Assistant).
- **Radio / news**: one tap for a station or the latest news podcast, as the cronos radio page does.
- **Cameras**: a doorbell or driveway camera in the circle, from Home Assistant's camera proxy.
- **Photo frame**: family photos from a local share when idle.
- **Home controls**: a handful of toggles and scenes in a ring.
- **Pop-up ring menu**: press and hold (or tap the rim) and the choices fan out around the edge of the
  circle — volume, mute, timers, the faces — picked by touching one or sliding a finger around the
  ring. Seen on an owner's Spot in the r/amazonecho thread; the round screen's most natural menu.
- **Doorbell / intercom**: the Spot's camera and speaker as a room-to-room intercom through Home
  Assistant, once the camera works (M5).

## Ground rules

- Everything stays local; no cloud services.
- Upstream projects (TECHO5, EchoLocal, amonet/kaeru/TWRP, amazon-oss) are used under their licenses
  and credited in `NOTICE`. Nothing is proposed upstream without the owner's OK.
- Never distribute a boot image or Amazon's firmware: images are assembled from each unit's own
  backup and its own LineageOS install.
- No adb or fastboot command runs without an explicit `-s <serial>`, since other MT8163 devices share
  the host.
