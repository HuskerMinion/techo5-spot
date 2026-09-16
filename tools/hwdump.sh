#!/system/bin/sh
# TECHO5 Spot hardware ground-truth dump for rook. Read-only: nothing is written, no audio device is
# opened, no module is loaded.
#
# Works as root in Fire OS 5, LineageOS 18.1 or TWRP (sections a shell does not support print nothing).
#   adb -s <serial> push tools/hwdump.sh /tmp/hwdump.sh          (TWRP; /data/local/tmp/ in Android)
#   adb -s <serial> shell sh /tmp/hwdump.sh > docs/dumps/rook-<os>-<serial>.txt
#
# Adapted from TECHO5's tools/hwdump.sh (cronos). The open questions it answers are listed at the end
# of docs/hardware.md.

sec() { echo; echo "===== $1"; }
have() { command -v "$1" >/dev/null 2>&1; }

sec "identity"
for p in ro.product.device ro.product.model ro.build.display.id ro.build.version.release \
         ro.build.version.fireos ro.build.version.incremental ro.hardware ro.board.platform \
         ro.bootloader ro.boot.hardware ro.twrp.version; do
  have getprop && echo "$p=$(getprop $p)"
done
uname -a
cat /proc/version 2>/dev/null
id

sec "cpu"
grep -E 'processor|model name|Features|Hardware|CPU part' /proc/cpuinfo | sort | uniq -c
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies 2>/dev/null

sec "memory (open question 1)"
grep -E 'MemTotal|MemFree|MemAvailable|SwapTotal|CmaTotal' /proc/meminfo
grep -iE 'memory|reserved' /proc/iomem 2>/dev/null | head -20

sec "storage / partitions (open question 2)"
cat /proc/partitions
for d in /dev/block/platform/*/by-name /dev/block/by-name; do
  [ -d "$d" ] && { echo "--- $d"; ls -l "$d"; }
done
for b in /sys/block/mmcblk0 /sys/block/mmcblk0boot0 /sys/block/mmcblk0rpmb; do
  [ -d "$b" ] && echo "$b: size=$(cat $b/size) name=$(cat $b/device/name 2>/dev/null) cid=$(cat $b/device/cid 2>/dev/null)"
done
df 2>/dev/null | grep -vE 'tmpfs'
cat /proc/mounts

sec "kernel cmdline (open question 3)"
cat /proc/cmdline

sec "kernel config (if built in)"
if [ -r /proc/config.gz ]; then
  zcat /proc/config.gz 2>/dev/null | grep -E '^CONFIG_(DEVTMPFS|OVERLAY_FS|SQUASHFS|F2FS_FS|BT|BT_HCIUART|BT_HCIUART_BCM|USB_CONFIGFS|USB_G_ANDROID|MODVERSIONS|IKCONFIG|MTK_CAMERA_ISP|SND_SOC_4_MICS|LCM_WIDTH|LCM_HEIGHT|CUSTOM_KERNEL_LCM|CUSTOM_KERNEL_IMGSENSOR|PSTORE|MTK_RAM_CONSOLE)='
else
  echo "no /proc/config.gz"
fi

sec "previous boot's kernel log"
ls -l /proc/last_kmsg /sys/fs/pstore 2>/dev/null

sec "modules"
cat /proc/modules 2>/dev/null
for d in /system/lib/modules /vendor/lib/modules /lib/modules; do [ -d "$d" ] && { echo "--- $d"; ls -l "$d"; }; done

sec "idme / factory data"
ls /proc/idme 2>/dev/null
for f in board_id product_name productid productid2 serial mac_addr bt_mac_addr bootcount dev_flags; do
  [ -r /proc/idme/$f ] && echo "$f=$(cat /proc/idme/$f)"
done

sec "audio: /proc/asound (open question 6)"
cat /proc/asound/cards /proc/asound/devices /proc/asound/pcm 2>/dev/null
ls -l /dev/snd 2>/dev/null
for d in /proc/asound/card*/pcm*; do
  [ -d "$d" ] || continue
  echo "--- $d: $(tr '\n' ' ' < $d/info 2>/dev/null)"
  for sub in $d/sub*; do [ -d "$sub" ] && sed 's/^/    hw_params: /' $sub/hw_params 2>/dev/null; done
done

sec "audio: mixer controls"
TM=""
for c in tinymix /system/bin/tinymix /vendor/bin/tinymix; do have $c && { TM=$c; break; }; done
if [ -n "$TM" ]; then $TM 2>/dev/null | head -400
else
  for c in /proc/asound/card*/id; do echo "$c: $(cat $c)"; done
  echo "tinymix not available"
fi

sec "audio: configuration files"
ls -l /system/etc/audio_device.xml /vendor/etc/audio_device.xml /vendor/etc/audio_policy_configuration.xml \
      /vendor/etc/mixer_paths*.xml /system/etc/audio_policy* 2>/dev/null
ls /system/lib/hw /vendor/lib/hw 2>/dev/null | grep -i audio

sec "input devices"
have getevent && getevent -pl 2>/dev/null
cat /proc/bus/input/devices 2>/dev/null

sec "buttons and mute (GPIO 37, 50, 87)"
ls /sys/devices/platform/*privacy* /sys/devices/soc/*privacy* 2>/dev/null
find /sys/devices -maxdepth 4 -name '*privacy*' 2>/dev/null
cat /sys/kernel/debug/gpio 2>/dev/null | grep -E 'gpio-(37|50|87|26|27|28|29) '

sec "display (open question 5)"
for f in modes virtual_size bits_per_pixel name; do echo "fb0/$f: $(cat /sys/class/graphics/fb0/$f 2>/dev/null)"; done
for b in /sys/class/leds/lcd-backlight /sys/class/backlight/*; do
  [ -d "$b" ] && echo "$b: brightness=$(cat $b/brightness 2>/dev/null) max=$(cat $b/max_brightness 2>/dev/null)"
done
have dumpsys && dumpsys display 2>/dev/null | grep -iE 'mBaseDisplayInfo|DisplayDeviceInfo' | head -4
grep -iE 'lcm|hx8379|panel' /proc/cmdline 2>/dev/null

sec "camera (open question 7)"
ls -l /dev/video* /dev/camera-isp /dev/kd_camera_hw /dev/MAINAF 2>/dev/null
ls /sys/class/video4linux 2>/dev/null

sec "i2c"
for d in /sys/bus/i2c/devices/*; do [ -d "$d" ] && echo "$(basename $d): $(cat $d/name 2>/dev/null)"; done

sec "spi (microphone FPGA)"
for d in /sys/bus/spi/devices/*; do [ -d "$d" ] && echo "$(basename $d): $(cat $d/modalias 2>/dev/null)"; done

sec "usb (Wi-Fi chip on usb1)"
for d in /sys/bus/usb/devices/*; do
  [ -r "$d/idVendor" ] && echo "$(basename $d): $(cat $d/idVendor):$(cat $d/idProduct) $(cat $d/manufacturer 2>/dev/null) $(cat $d/product 2>/dev/null)"
done
ls /sys/class/udc 2>/dev/null
ls /sys/kernel/config/usb_gadget 2>/dev/null

sec "wi-fi and bluetooth (open question 8)"
ls /sys/class/net
cat /sys/class/net/wlan0/address 2>/dev/null
for r in /sys/class/rfkill/*; do [ -d "$r" ] && echo "$r: $(cat $r/name) $(cat $r/type) state=$(cat $r/state)"; done
ls -l /dev/ttyMT* 2>/dev/null
for d in /system/vendor/firmware /vendor/firmware /system/etc/firmware; do [ -d "$d" ] && { echo "--- $d"; ls -lR "$d" | head -40; }; done
have getprop && getprop | grep -iE 'wifi|wlan|bluetooth|bt\.' | head -20
[ -r /data/misc/wifi/wpa_supplicant.conf ] && echo "saved networks: $(grep -c 'ssid=' /data/misc/wifi/wpa_supplicant.conf)"

sec "sensors"
for d in /sys/bus/iio/devices/*; do [ -d "$d" ] && echo "$d: $(cat $d/name 2>/dev/null)"; done
ls /sys/class/misc 2>/dev/null | grep -iE 'als|ps|gsensor|acc'

sec "thermal"
for t in /sys/class/thermal/thermal_zone*; do [ -d "$t" ] && echo "$(basename $t): $(cat $t/type 2>/dev/null) $(cat $t/temp 2>/dev/null)"; done

sec "rtc"
ls /dev/rtc* 2>/dev/null
cat /sys/class/rtc/rtc0/date /sys/class/rtc/rtc0/time 2>/dev/null

sec "processes"
(ps -A 2>/dev/null || ps) | grep -vE 'kworker|ksoftirq|migration|rcu_|irq/|cpuhp|watchdog' | head -150

sec "init services (Android)"
have getprop && getprop | grep -E '^\[init\.svc\.' | sed 's/\[init\.svc\.//' | head -120

sec "selinux"
have getenforce && getenforce

sec "kernel log (hardware lines)"
dmesg 2>/dev/null | grep -iE 'bcmdhd|dhd|wlan|brcm|bluetooth|hci|aic3101|aic32x4|spi-audio|fpga|lcm|hx8379|gt5668|goodix|gc0312|opt3001|bma222|privacy|musb|usb1|firmware|mmc0' | head -200
