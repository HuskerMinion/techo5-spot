# Echo Spot 1st gen (2017) — `rook`

Nothing in this file has been confirmed on a unit by this project yet. It collects what the unlock,
the TWRP and LineageOS device trees, the 4.9 kernel sources and a stock firmware dump already say.
Each fact names its source. Treat everything as *unverified here* until the first `tools/hwdump.sh`
on a real Spot.

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
| RAM | DT memory node `0x20000000` = **512 MB**, like the Dot. A field report says "about 1 GB"; **open** until `MemTotal` is read | DT; field |
| Storage | eMMC, size **open** (a field report: ~4 GB free after LineageOS) | field |
| Display | 2.5-inch round, **480×480** in TWRP and LineageOS; LCM driver `hx8379c_dsi_wvga_vdo_rook` (DSI video mode), backlight `mediatek,lcd-backlight` (`led6`), panel-id GPIOs 32 and 44, power GPIOs 85/125, reset 83. The defconfig's `CONFIG_LCM_WIDTH/HEIGHT` say 400×800, which does not match; **open** | TWRP, Lineage, defconfig, DT |
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

1. `MemTotal`: 512 MB or 1 GB?
2. eMMC size and the full partition table with sizes.
3. `/proc/cmdline` on a normal boot: any `skip_initramfs`, `root=`, verity arguments added by LK?
4. Does `recovery` boot the arm64 LineageOS kernel (the cronos 32-bit-only limit)?
5. Panel geometry as the kernel reports it (`fb0` virtual size) against the defconfig's 400×800.
6. Capture format of the microphone PCM (channels, rate, bit depth) and which channels carry the
   four microphones and the loopback.
7. The camera: does the 4.9 kernel register it at all without `CONFIG_MTK_CAMERA_ISP`?
8. Is `bcmdhd` happy with a plain nl80211 `wpa_supplicant` (it has cfg80211 support) once the module
   and firmware paths are right?
9. The screen fault: does the unit have it?
