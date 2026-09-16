#!/usr/bin/env bash
# build-image.sh — the Echo Spot's boot image: the LineageOS rook kernel with TECHO5's rescue/boot
# initramfs (tools/linux/init here, adapted for the Spot's partitions and Broadcom Wi-Fi).
#
#   tools/linux/build-image.sh [-o out.img]
#
# What comes from where:
#   TECHO5       a TECHO5 checkout (the spot/daemon worktree): mkimage.py, techo5-lib.sh, slotctl and
#                the Go tools, built here for armv7
#   SPOT_INPUTS  this repository's inputs/ (git-ignored): the LineageOS rook boot image
#   INPUTS       the Show's shared inputs: Alpine minirootfs, busybox.static, the apks in TECHO5's
#                tools/linux/packages.txt, and the rescue SSH public key
#
# Flash from fastboot (Volume Down at power-on):  fastboot flash boot <out.img>; fastboot reboot
# Back to LineageOS:                             fastboot flash boot backups/<serial>/boot-lineage-18.1.img
set -euo pipefail

HERE=$(cd "$(dirname "$0")/../.." && pwd)
TECHO5=${TECHO5:-E:/Projects/techo5-wt-spot}
SPOT_INPUTS=${SPOT_INPUTS:-$HERE/inputs}
INPUTS=${TECHO5_INPUTS:-D:/platform-tools/echoshow/linux-image}
KERNEL_IMAGE=${KERNEL_IMAGE:-$SPOT_INPUTS/boot-lineage-18.1-20251108-rook.img}
GO=${GO:-/c/Program Files/Go/bin/go.exe}
OUT=$HERE/bin/techo5-spot-linux-boot.img
while [ $# -gt 0 ]; do
	case "$1" in
	-o) OUT=$2; shift 2;;
	*) echo "unknown argument: $1" >&2; exit 1;;
	esac
done
W() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
mkdir -p "$HERE/bin"

echo "== building tools for armv7 (from $TECHO5)"
export GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0
for c in fbprobe audioprobe rebootto; do
	(cd "$TECHO5" && "$GO" build -trimpath -ldflags "-s -w" -o "$HERE/bin/$c-arm" "./cmd/$c")
done
unset GOOS GOARCH GOARM CGO_ENABLED

apks=()
for a in $(sed 's/#.*//' "$TECHO5/tools/linux/packages.txt"); do
	case "$a" in
	busybox-static-*) continue;;
	wpa_supplicant-2.9*|libssl1.1*|libcrypto1.1*|libnl3-3.5*) apks+=(--apk "$(W "$INPUTS/apks312/$a")");;
	*) apks+=(--apk "$(W "$INPUTS/apks/$a")");;
	esac
done

echo "== mkimage"
export MSYS_NO_PATHCONV=1
H=$(W "$HERE"); T=$(W "$TECHO5"); I=$(W "$INPUTS")
mini=$(ls "$INPUTS"/alpine-minirootfs-*-armv7.tar.gz | head -1)
python "$T/tools/linux/mkimage.py" --kernel-image "$(W "$KERNEL_IMAGE")" \
	--rootfs "$(W "$mini")" \
	"${apks[@]}" \
	--init "$H/tools/linux/init" \
	--add "$I/busybox.static=/bin/busybox.static" \
	--add "$H/bin/fbprobe-arm=/usr/local/bin/fbprobe" \
	--add "$H/bin/audioprobe-arm=/usr/local/bin/audioprobe" \
	--add "$H/bin/rebootto-arm=/usr/local/bin/rebootto" \
	--script "$T/tools/linux/slotctl=/usr/local/sbin/slotctl" \
	--script "$T/tools/linux/techo5-lib.sh=/lib/techo5-lib.sh" \
	--copy "$I/techo5_ed25519.pub=/root/.ssh/authorized_keys" \
	--compress xz --cmdline-append techo5=linux -o "$(W "$OUT")"
echo "built: $OUT"
