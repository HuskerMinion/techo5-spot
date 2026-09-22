#!/bin/bash
# build-kernel.sh — the Echo Spot's kernel (LineageOS 18.1 rook, 4.9.337 arm64) with Bluetooth added,
# at the commit the LineageOS boot image was built from, so its vendor module (amzn-bcmdhd.ko, built
# with CONFIG_MODVERSIONS) still loads. Run inside WSL/Linux. Modeled on TECHO5's build-kernel.sh.
#
#   tools/linux/build-kernel.sh [-o Image.gz-dtb]
#
# Environment: KREPO (a clone of github.com/amazon-oss/android_kernel_amazon_mt8163; ~/kernel),
# KSRC (a clean worktree made from it at KCOMMIT; ~/kernel-rook), KCOMMIT (4174e0b4d0e2: `uname -r` on
# LineageOS is 4.9.337-g<KCOMMIT>), KCONFIG (the running kernel's /proc/config.gz, saved in
# docs/dumps: it is the one the modules were built with, and differs from rook_defconfig),
# CROSS_COMPILE (an aarch64 GCC; Arm's 8.3-2019.03 release), KOUT (build directory; ~/kout-rook).
#
# Bluetooth: core, BR/EDR, LE, RFCOMM and the virtual HCI driver. TECHO5's btbridge talks to the
# BCM43569A2 on /dev/ttyMT1 itself (firmware patch, baud rate, address) and hands the kernel a
# ready controller through /dev/vhci, as it does for the Show's and the Dot's MediaTek radios.
set -euo pipefail

HERE=$(cd "$(dirname "$0")/../.." && pwd)
KREPO=${KREPO:-$HOME/kernel}
KSRC=${KSRC:-$HOME/kernel-rook}
KCOMMIT=${KCOMMIT:-4174e0b4d0e2}
KOUT=${KOUT:-$HOME/kout-rook}
KCONFIG=${KCONFIG:-$HERE/docs/dumps/rook-lineage-kernel-4.9.337.config}
CROSS_COMPILE=${CROSS_COMPILE:-$HOME/toolchain/gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu/bin/aarch64-linux-gnu-}
OUT=
while [ $# -gt 0 ]; do
	case "$1" in
	-o) OUT=$2; shift 2;;
	*) echo "unknown argument: $1" >&2; exit 1;;
	esac
done

if [ ! -d "$KSRC" ]; then
	git -C "$KREPO" cat-file -e "$KCOMMIT^{commit}" 2>/dev/null || git -C "$KREPO" fetch origin
	git -C "$KREPO" worktree add --detach "$KSRC" "$KCOMMIT"
fi
cd "$KSRC"
head=$(git rev-parse --short=12 HEAD)
case "$head" in "$KCOMMIT"*) ;; *) echo "kernel tree is at $head, not $KCOMMIT" >&2; exit 1;; esac
if [ -n "$(git status --porcelain)" ]; then
	echo "kernel tree is not clean (LOCALVERSION would get -dirty):" >&2
	git status --short >&2
	exit 1
fi
# Keep the builder's account, host and zone out of the image.
export KBUILD_BUILD_USER=techo5 KBUILD_BUILD_HOST=techo5 TZ=UTC
export ARCH=arm64 CROSS_COMPILE
mkdir -p "$KOUT"
cp "$KCONFIG" "$KOUT/.config"
scripts/config --file "$KOUT/.config" \
	-e BT -e BT_BREDR -e BT_LE -e BT_RFCOMM -e BT_RFCOMM_TTY \
	-e BT_HCIVHCI -d BT_DEBUGFS
make -s O="$KOUT" olddefconfig
grep -E "^CONFIG_(BT|BT_HCIVHCI|LOCALVERSION_AUTO|MODVERSIONS)=" "$KOUT/.config"
make -j"$(nproc)" O="$KOUT" Image.gz-dtb
echo "release: $(cat "$KOUT/include/config/kernel.release")"
ls -la "$KOUT/arch/arm64/boot/Image.gz-dtb"
if [ -n "$OUT" ]; then
	cp "$KOUT/arch/arm64/boot/Image.gz-dtb" "$OUT"
	echo "copied to $OUT"
fi
