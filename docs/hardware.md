# Echo Spot 1st gen (2017) — `rook`

This file started as what the unlock, the TWRP and LineageOS device trees, the 4.9 kernel sources and
a stock firmware dump say, each fact with its source. The first unit has since been read: see
"Confirmed on the bench unit" directly below, which wins wherever it disagrees with the rest.

## Confirmed on the bench unit

The bench unit, unlocked 2026-09-16 with amonet-rook v2.0.0 from Windows, read in TWRP
3.7.0 with `tools/hwdump.sh`. Raw output:
[dumps/rook-twrp-bench-unit.txt](dumps/rook-twrp-bench-unit.txt). Backups (md5-checked,
off the device): kept outside the repository.

| Item | Value |
|---|---|
| Stock firmware | Fire OS **5.5.6.9** (`304.6.9.0_user_690918020`, Android 5.1.1 `LVY48F`) |
| RAM | **2 GB, verified.** MemTotal 1 959 632 kB (TWRP 3.18), 1 958 192 kB (LineageOS 4.9). The bootloader writes a `memory` node with `0x40000000`+1024 MB and `0x80000000`+942 MB (the source tree's 512 MB `memory@00000000` node is stale); `/proc/iomem` System RAM runs `0x40000000`–`0xBADFFFFF`. With Android stopped and zram off, 1600 MB of random data was written to a RAM-backed tmpfs (Shmem 1 639 312 kB, 95 MB left free) and read back twice with the same md5 |
| eMMC | **7.28 GiB**, `H8G4a2` (15 269 888 sectors); boot0 1 MB, boot1 4 MB, RPMB 4 MB |
| CPU | 4× Cortex-A53 (`0xd03`), 600 MHz – 1.3 GHz, AArch64 kernel |
| Kernel in TWRP | **3.18.19 aarch64** (r0rt1z2's build of Amazon's tree, 2026-08-16), not the 4.9 LineageOS kernel |
| Display | `mtkfb` 480×480, 32 bpp, `fb0` virtual 480×960 (two pages); LCM `hx8379c_dsi_wvga_vdo_rook`, "resolution: 480 x 480", 2 DSI lanes, sync-pulse video mode, panel id 1; backlight `/sys/class/leds/lcd-backlight` 0–255. The defconfig's 400×800 does not describe the panel |
| Touch | input `mtk-tpd` (GT5668 firmware patch `020108`, sensor id 03), ABS X/Y and MT positions 0–480, 10 tracking ids |
| Buttons | input `keys` (gpio-keys: `KEY_VOLUMEDOWN`, `KEY_VOLUMEUP`); input `mtk-kpd` (`KEY_POWER`, `KEY_VOLUMEDOWN`, `KEY_HELP`) |
| Mute | `/sys/devices/soc/10010000.keypad/privacy_state`, `privacy_trigger`, `privacy_timer_on` (the Fire OS 6 Dot's layout) |
| Other inputs | `ACCDET` (jack), `m_alsps_input` and `hwmdata` (sensor hubs) |
| I²C | 0-0018 and 0-001a `tlv320aic3101`, 0-0021 `camera_sub`, 0-003c `camera_main`, 0-0044 `alsps` (OPT3001 found), 0-005d `goodix_touch`, 1-0060 `sym827-regulator`, 2-0018 `tlv320aic32x4`, 2-0019 `gsensor`, 2-0070/71/72 `tmp103_temp_sensor` — all as the device tree says |
| SPI | `spi32766.0`: `spi-audio-pltfm` (the microphone FPGA) |
| USB | `usb1` MUSB host, `usb2` MUSBFSH host (the Wi-Fi bus). No Wi-Fi device enumerated in TWRP: `bcmdhd` is not loaded and the chip is not powered |
| Bluetooth | `rfkill0` bluetooth; `/dev/ttyMT0`, `/dev/ttyMT1` |
| Camera | `/dev/camera-isp` present on the 3.18 kernel |
| Audio | no sound card on TWRP's kernel (`/proc/asound` absent) |
| Fire OS modules | `system/lib/modules/bcmdhd.ko` (9.9 MB), `br_netfilter.ko`, `xt_physdev.ko`, `perfinfo.ko` |
| Fire OS firmware | `vendor/firmware/BCM43569A2_001.003.004.0167.0215.hcd`, `vendor/firmware/brcm/bcm43569a2-firmware.bin`, `bcm43569a2-firmware-test.bin`, `bcm43569a2.nvm`; `etc/firmware/gt9xx_fw.bin` |
| Thermal | `mtktscpu`, `mtkts1/3/4/5`, `mtktspmic`, `tmp103.0`, `tmp103.1` |
| idme | serial, `mac_addr`, `bt_mac_addr`, `board_id=<board-id>`, `bootcount=297`, `miccal.0`–`3`, `alscal`, `sensorcal`, `unlock_code` |
| RTC | `/dev/rtc0`, reads 2010-01-01 at boot |
| Preloader / LK | `pl_build_desc=8ec9006-20170927_201132`, `lk_build_desc=c1c79aa-20220824_171625` |

### Partition table (eMMC user area)

| p | Name | Size |
|---|---|---|
| 1 | kb | 1 MB |
| 2 | dkb | 1 MB |
| 3 | lk (TWRP links `lk` to `/dev/null`, real one is `lk_real`) | 1 MB |
| 4 | tee1 (decoy, `tee1_real`) | 4 MB |
| 5 | logo | 1 MB |
| 6 | tee2 (decoy, `tee2_real`) | 4 MB |
| 7 | expdb (kaeru lives here) | 16 MB |
| 8 | MISC | 512 KB |
| 9 | boot | 16 MB |
| 10 | recovery (TWRP) | 16 MB |
| 11 | system | 1.66 GB |
| 12 | cache | 256 MB |
| 13 | userdata | 5.35 GB |

The eMMC boot area carries `boot0hdr0`, `boot0hdr1`, `boot0img0`, `boot0img1` (mmcblk0boot0p1–p4).
There is no `persist`, `metadata`, `nvram`, `proinfo`, `seccfg`, `frp` or `para` on this unit. By-name
links exist under `bootdevice`, `mtk-msdc.0`, `soc` and `/dev/block/by-name`, all the same directory.

### Boot images (from the backups)

| | kernel | loaded at | ramdisk at | tags | cmdline |
|---|---|---|---|---|---|
| `boot` (Fire OS 5.5.6.9) | 6.45 MB | `0x40080000` | `0x44000000` | `0x48000000` | `bootopt=64S3,32N2,64N2 firmware_class.path=/system/vendor/firmware` |
| `recovery` (TWRP) | 5.32 MB | `0x40080000` | `0x69244e00` | `0x48000000` | the same plus `buildvariant=eng` |

Page size 2048 for both. Running TWRP, `/proc/cmdline` has `root=/dev/ram`, `androidboot.unlocked_kernel=true`,
`lcm=1-hx8379c_wvga_dsi_vdo`, `vmalloc=496M` and no `skip_initramfs`. A normal (Fire OS) boot's
command line is still to be read.

### What the unlock did and did not do

- From Windows: power off, hold Volume Up + Volume Down + Mute while powering on until fastboot shows,
  `fastboot getvar product` = `ROOK`, `unlock_status: false`, `secure: yes`, `version: 0.5`; then
  `fastbrick.bat`. It came back in TWRP. No Linux, no Python, no BootROM step.
- **userdata was not wiped**: 1.65 GB of Fire OS data is still there, including one saved Wi-Fi
  network (`WPA-PSK`) in `/data/misc/wifi/wpa_supplicant.conf`, which the Linux image can reuse as the
  Show's and the Dot's did.
- TWRP swaps `lk`, `tee1`, `tee2` for `/dev/null` decoys (`*_real` are the partitions), as on the
  other amonet Echos.

### Buttons at power-on, and getting between modes

- **Volume Down** alone: kaeru's hacked fastboot. Holding all three buttons did nothing on this unit.
- **Volume Up**: recovery.
- From fastboot, `fastboot reboot recovery` works (kaeru 2.0.0), and `fastboot flash recovery` too.
  `max-download-size` is 109 MB.
- From TWRP, `adb reboot` boots Fire OS.

### Fire OS puts its own recovery back, and verifies system

- Every Fire OS boot runs `/system/bin/install-recovery.sh`: if `recovery` is not Amazon's image it
  rebuilds it with `applypatch` from `boot` and `/system/recovery-from-boot.p`. The first Fire OS boot
  after the unlock replaced TWRP with "Amazon system recovery <3e>".
- **Do not change the system partition to stop it.** Fire OS's `fstab.mt8163` mounts `system` with
  `wait,verify` and the ramdisk carries `verity_key`: dm-verity checks every block. Renaming
  `recovery-from-boot.p` (a read-write mount in TWRP) left Fire OS stuck at the Amazon logo. Writing
  `system` back from its backup, byte for byte, fixed it.
- The way to live with it until Fire OS is gone: after any Fire OS boot, Volume Down, then
  `fastboot flash recovery <TWRP backup>` and `fastboot reboot recovery`. Seconds, and nothing of
  Fire OS changes.
- Large images go to the unit with `adb push` to `/data` and `dd` from there (1.66 GB `system`: push
  at 17.5 MB/s, dd at 38 MB/s); TWRP's `/tmp` is RAM.

### On LineageOS 18.1 (M1)

`lineage-18.1-20251108-UNOFFICIAL-rook` installed from TWRP 2026-09-16 (its script writes only
`system` and `boot`; data formatted first). Raw output, redacted:
[dumps/rook-lineage-18.1-bench-unit.txt](dumps/rook-lineage-18.1-bench-unit.txt); the running kernel's
config: [dumps/rook-lineage-kernel-4.9.337.config](dumps/rook-lineage-kernel-4.9.337.config).

| Item | Value |
|---|---|
| Kernel | **4.9.337-g4174e0b4d0e2** arm64, built 2025-11-08, userspace 32-bit (`armv8l`). `CONFIG_LOCALVERSION_AUTO=y` and `CONFIG_MODVERSIONS=y`: a rebuilt kernel must match that release string for `amzn-bcmdhd.ko` to load, as on cronos |
| Kernel options | `CONFIG_IKCONFIG` (config readable at `/proc/config.gz`), `CONFIG_USB_CONFIGFS_ACM`, `CONFIG_CFG80211`, `CONFIG_ZRAM`, `CONFIG_MTK_CAMERA_ISP=y` (the running build has it although `rook_defconfig` does not list it); **`# CONFIG_BT is not set`**, so Bluetooth needs the kernel rebuild, as cronos did |
| Wi-Fi | `amzn_bcmdhd` module from `/vendor/lib/modules/amzn-bcmdhd.ko` (3.5 MB). USB `2-1: 0a5c:bd27 Broadcom Remote Download Wireless Adapter` on the MUSBFSH bus. Joined a WPA2/WPA3 network on **5 GHz** (5180 MHz, 802.11ac, 780 Mbps link) at first try |
| Sound card | `mt-snd-card`. **PCM 22: `TLV320AIC3101 Capture`** (the microphones), **PCM 23: `TLV320AIC3204 Playback`** (the speaker), plus the MediaTek AFE's usual set (`MultiMedia1`, `DL1_AWB_Record`, `TDM_Debug_Record`, `I2S0AWB_Capture`, …) |
| Display | Android: "Built-in Screen" 480×480 at 59.82 Hz, 160 dpi, **`FLAG_ROUND`**; `fb0` virtual 480×1440 (three pages); backlight 102/255 at the default setting |
| Touch, buttons | as in TWRP: `mtk-tpd` 0–480, `keys` volume up/down, `mtk-kpd` power/volume down/help |
| Camera | `/dev/camera-isp` and `/dev/kd_camera_hw` present |
| adb root | Developer options → Rooted debugging must be on (off by default) |
| On-screen keyboard | would not enter digits on the Wi-Fi password page; the network was added from the PC with `cmd wifi connect-network` |

---

The rest of this file is the pre-unit research, kept for its sources.

Sources, short names used below:

- **DT**: `arch/arm64/boot/dts/mediatek/rook.dtsi`, `rook_evt.dts`, `rook_hvt.dts` in
  https://github.com/amazon-oss/android_kernel_amazon_mt8163, branch `lineage-18.1` (4.9.337). The
  same tree and branch TECHO5 builds the cronos kernel from.
- **defconfig**: `arch/arm64/configs/rook_defconfig` from that tree, copied to
  [dumps/rook_defconfig-lineage-18.1](dumps/rook_defconfig-lineage-18.1);
  [dumps/rook-vs-cronos-defconfig.diff](dumps/rook-vs-cronos-defconfig.diff) is its difference from
  `cronos_defconfig`. It is a minimal (savedefconfig) file: an option that is not listed is at its
  Kconfig default, not necessarily off.
- **Lineage**: https://github.com/amazon-oss/android_device_amazon_rook (`lineage-18.1`,
  `BoardConfig.mk`, `device.mk`, `init/init.target.rook.rc`, `proprietary-files.txt`,
  `configs/vnd_rook.txt`), and `android_kernel_amazon_amzn-bcmdhd` for the Wi-Fi driver.
- **TWRP**: https://github.com/R0rt1z2/twrp_device_amazon_echo-mt8163 `rook/` (2026) and the older
  https://github.com/R0rt1z2/twrp_device_amazon_rook (`twrp-5.1`, `recovery.fstab`).
- **amonet**: https://github.com/R0rt1z2/amonet branch `mt8163-rook` (release amonet-rook-v1.1.1,
  last commit 2026-08-17 "Port rook to the new exploit").
- **dump**: https://github.com/el-vertedero/amazon_rook_dump, a Fire OS 5.5.2.5 userdebug build
  (`304.6.1.8_userdebug_618515610`): `boot.img` parameters, `system/`.
- **field**: owners' reports (r/amazonecho, 2026-09; https://github.com/afrugalpenguin/spotdash,
  MIT). Anecdotal, and marked so.

## Board

| Item | Value | Source |
|---|---|---|
| SoC | MediaTek MT8163, 4× Cortex-A53 | DT, defconfig |
| RAM | DT memory node `0x20000000` = 512 MB; **the unit reports about 2 GB** (see above) | DT; unit |
| Storage | 7.28 GiB eMMC `H8G4a2` (unit) | unit |
| Display | 2.5-inch round, **480×480** in TWRP and LineageOS; LCM driver `hx8379c_dsi_wvga_vdo_rook` (DSI video mode), backlight `mediatek,lcd-backlight` (`led6`), panel-id GPIOs 32 and 44, power GPIOs 85/125, reset 83. The defconfig's `CONFIG_LCM_WIDTH/HEIGHT` say 400×800; the unit's LCM driver reports 480×480 | TWRP, Lineage, defconfig, DT |
| Touch | Goodix **GT5668** (`CONFIG_TOUCHSCREEN_MTK_GT5668`), I²C 0 `0x5d`, IRQ GPIO 49, firmware `system/etc/firmware/gt9xx_fw.bin` on Fire OS; the DT's `tpd-resolution` (720×1280) is a template value | defconfig, DT, dump |
| Camera | GalaxyCore **GC0312** VGA MIPI (`CONFIG_CUSTOM_KERNEL_IMGSENSOR="gc0312_mipi_raw"`); DT names main at I²C 0 `0x3c` and sub at `0x21` ("Fix me to right reg val"). `rook_defconfig` does not set `CONFIG_MTK_CAMERA_ISP`, which `cronos_defconfig` does | defconfig, DT |
| Mic ADCs | TI **TLV320AIC3101** at I²C 0, two register sets `0x18` (adc0) and `0x1a` (adc1), enable GPIO 35, 26 MHz clock. `CONFIG_SND_SOC_4_MICS=y`: four microphones on two stereo ADCs | DT, defconfig |
| Mic transport | An FPGA between the ADCs and the SoC over SPI (`amzn-mtk,spi-audio-pltfm`, 100 MHz, FPGA supplies `vcamaf`/`vgp3`, GPIO 43), bitstream built into the kernel: `CONFIG_EXTRA_FIRMWARE="i2s_to_spi_6ch_v183.bin"`. cronos has the same arrangement with `i2s_to_spi_4ch_*` | DT, defconfig |
| Playback | TI **TLV320AIC32x4** DAC (`CONFIG_SND_SOC_TLV320AIC32X4_AMZN`), I²C 2 `0x18`, reset GPIO 22; external speaker amp enable through the `extamp` pinctrl states, amp fault GPIO 121; `audiosys` `channel-type = 2` (mono right) at MCLK 24.576 MHz | DT, defconfig |
| Stock mixer | Fire OS `system/etc/audio_device.xml`: speaker path sets `Right Channel Only` On, `HP Driver Gain Volume` 9, `PCM Playback Volume` 127, `Amp Fault Enable` On; capture sets `ADC_A/B Left/Right Ip Select ADC_x DIF1_L/R switch` 1 and `ADC_A/B MICPGA Volume Ctrl` 40; `Ext_Speaker_Amp_Switch` Off at start. Line out: `Audio_LineOut_Setting`, `biquad coefficients`, `DRC Control` | dump |
| Headphone / line out | 3.5 mm jack, `accdet` on GPIO 26 (EINT 4) | DT |
| Wi-Fi | **Broadcom BCM43569A2** over **USB** (`BCMDHD_DEVICE_PLAT := USB` for rook), driver `bcmdhd` as a module: `amzn-bcmdhd.ko` (Lineage), `system/lib/modules/bcmdhd.ko` (Fire OS). `WL_REG_ON` regulator on GPIO 27, host-wake GPIO 29. Firmware `brcm/bcm43569a2-firmware.bin` + `brcm/bcm43569a2.nvm` under `/system/vendor/firmware`. The USB host port is `usb1` (`CONFIG_MTK_USBFSH`) | Lineage, DT, dump, defconfig |
| Bluetooth | Same BCM43569A2, H4 over **UART** `/dev/ttyMT1` at 3 Mbps; rfkill GPIO 28 (`rfkill-gpio`, default blocked); patch file `BCM43569A2_001.003.004.0142.0191.hcd` (Lineage) or `…0126.0178_Rook.hcd` (Fire OS 5.5.2.5) | Lineage `vnd_rook.txt`, DT, dump |
| Buttons | volume up 115 (GPIO 37), volume down 114 (GPIO 50), `gpio-keys` | DT |
| Mute | `amz_privacy`, GPIO 87 (active low in `rook_hvt.dts`, with `hw_latch = <0>`); microphone and camera off together, as far as the product goes | DT |
| Sensors | ambient light TI **OPT3001** (I²C 0 `0x44`, exposed as MTK `alsps`, `m_alsps_misc`), accelerometer **BMA222E** (I²C 2 `0x19`), three **TMP103** temperature sensors (I²C 2 `0x70`–`0x72`), auxadc thermistors | DT, Lineage |
| PMIC | MT6323; CPU rail on a Silergy SYM827 (I²C 1 `0x60`) | DT |
| Debug UART | `console=ttyMT0,921600n1` in the DT's chosen node | DT |
| USB | micro-USB behind the rubber cover on the back, between the power jack and the audio jack; `usb0` (MUSB, OTG ID on GPIO 38) | field, DT |
| LEDs | none besides the backlight (`led0`–`led5` deleted in the DT) | DT |

Compared with the Show 5 (`cronos`): no MT7668 SDIO combo and so no `mt76x8_*` modules; no MAX98396
amp; half the RAM; a round panel; a VGA camera instead of the OV02B10; the same TLV320AIC3101 + FPGA
microphone path, with a 6-channel bitstream instead of a 4-channel one.

### Known hardware fault (field)

Many Spots develop a flickering, shaking or blanking screen with age, reported widely by owners.
Check the panel on a unit before putting work into it, and note it in the unit's log.

## Firmware and kernels

| | Fire OS 5 (stock) | LineageOS 18.1 (unofficial) |
|---|---|---|
| Android | 5.1.1 (`LVY48F`) | 11 |
| Kernel | 3.18, **arm64** (`bootopt=64S3,32N2,64N2`); GPL source https://github.com/bengris32/android_kernel_amazon_rook | **4.9.337 arm64**, `rook_defconfig`, the tree cronos uses |
| Userspace | 32- and 64-bit (`lib/`, `lib64/`) | 32-bit ARM (`armeabi-v7a`) per the Echo builds |
| Wi-Fi module | `system/lib/modules/bcmdhd.ko` | `vendor/lib/modules/amzn-bcmdhd.ko`, loaded from `init.insmod.cfg` |
| Partitions | not A/B | not A/B |

Stock boot image (dump): base `0x40078000`, kernel offset `0x8000`, ramdisk offset `0x03f88000`, tags
`0x07f88000`, page 2048, cmdline `bootopt=64S3,32N2,64N2 firmware_class.path=/system/vendor/firmware`.
TWRP builds with the same base and a ramdisk offset of `0x291cce00`.

Fire OS 5 is not system-as-root, so the reason the Dot's Linux image had to live in `recovery`
(the bootloader adding `skip_initramfs` to normal boots on Fire OS 6) should not apply. **Open** until
`/proc/cmdline` is read on a unit.

cronos found that its `recovery` slot only boots 32-bit kernels. rook's current TWRP is an arm64
`Image.gz-dtb` in `recovery`, so that limit does not seem to hold here. **Open.**

## Partitions

From the TWRP `recovery.fstab` (by-name under `/dev/block/platform/mtk-msdc.0/by-name/` in the older
tree, `/dev/block/platform/bootdevice/by-name/` in the current one; Fire OS itself used
`/dev/block/platform/soc/by-name/` per amonet's `return-to-stock.sh`):

`boot0hdr0`, `boot0img0`, `boot0hdr1`, `boot0img1` (preloader in eMMC boot area), `lk`, `tee1`, `tee2`,
`nvram`, `proinfo`, `seccfg`, `persistbackup`, `dkb`, `kb`, `frp`, `boot`, `recovery`, `system`,
`userdata`, `cache`, `MISC`, `para`, `expdb`, and in the current tree `persist` and `metadata`.

Sizes from the Lineage and TWRP board configs: `boot` 16 MB, `recovery` 16 MB, `cache` 256 MB,
`system` 1.66 GB (the LineageOS image size; the partition may be larger). **Full table: open**, the
first `hwdump` fills it.

## Unlock (amonet-rook, R0rt1z2 and k4y0z)

- Supported Fire OS versions, from `brick.sh`'s LK build table: **5.5.6.9** (`c1c79aa-20220824`),
  **5.5.5.2** (`beb022a-20211202`), **5.5.3.4** (`d9a2246-20180702`). Anything else is refused. Update
  first if the unit is older.
- Everything goes through the micro-USB port; nothing is shorted. `brick.sh` (from fastboot) or
  `fastbrick.sh`/`fastbrick.ps1` corrupt the boot so the SoC falls into BootROM download mode.
- `bootrom-step.sh` (`modules/main.py`, Linux with python3 and no ModemManager): handshake, loads the
  BROM or preloader payload, checks the GPT (restores it if an old `boot_x`/`recovery_x` patch is
  present), checks BOOT0 and RPMB (`AMZN` magic), **zeroes RPMB** to allow the downgrade, writes
  `tz.img` to `tee2`, a stock `lk.bin` to `lk`, `rook-kaeru.bin` to `expdb`, `tee-payload.bin` to
  `tee1`, a downgraded `preloader.img` to BOOT0 (unless it came in through the preloader), then
  `FASTBOOT_PLEASE` in `MISC` and reboots.
- `fastboot-step.sh`: `fastboot flash recovery bin/twrp.img`, `fastboot reboot recovery`.
- `boot-fastboot.sh` / `boot-recovery.sh`: from BROM, boot straight to fastboot (`FACTFACT`) or
  recovery (`FACTORYM`).
- The partition table changes and userdata is wiped (XDA thread title, amonet notes).
- `gpt-fix.sh` rewrites the GPT from `bin/gpt-rook.bin`; `return-to-stock.sh` restores Amazon's
  recovery and the unpatched GPT from Fire OS with root.
- kaeru's behaviour on the other MT8163 Echos (from TECHO5 and TECHO5 Dot, **unverified on rook**):
  no `fastboot boot`, so every test image is flashed; `fastboot continue` boots normally; a volume
  key at power-on picks recovery or fastboot.

## Open questions for M0

Answered on the bench unit (see the top of this file): 1, 2, 5 and 9. Still open: 3, 4, 6, 7, 8.

1. `MemTotal`: 512 MB or 1 GB? **About 2 GB.**
2. eMMC size and the full partition table with sizes. **7.28 GiB, 13 partitions.**
3. `/proc/cmdline` on a normal boot: any `skip_initramfs`, `root=`, verity arguments added by LK?
4. Does `recovery` boot the arm64 LineageOS kernel (the cronos 32-bit-only limit)?
5. Panel geometry as the kernel reports it (`fb0` virtual size) against the defconfig's 400×800.
   **480×480, virtual 480×960.**
6. Capture format of the microphone PCM (channels, rate, bit depth) and which channels carry the
   four microphones and the loopback. **PCM 22 is the capture device; format still open.**
7. The camera: does the 4.9 kernel register it at all without `CONFIG_MTK_CAMERA_ISP`?
   **The running LineageOS kernel has `CONFIG_MTK_CAMERA_ISP=y` and `/dev/kd_camera_hw`.**
8. Is `bcmdhd` happy with a plain nl80211 `wpa_supplicant` (it has cfg80211 support) once the module
   and firmware paths are right? **Works under Android's supplicant on 5 GHz; Alpine's is M2.**
9. The screen fault: does the unit have it? **No; the owner reports years of clean use.**
