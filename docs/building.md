# Building TECHO5 Spot yourself

You don't need any of this to install or update a Spot. `tools/install-spot-linux.ps1` and Home
Assistant's update card use the signed releases. This page is for changing the daemon, the kernel or
the images. The shared parts (the daemon, Go, the environment variables, the root filesystem build)
are in TECHO5's [docs/building.md](https://github.com/HuskerMinion/techo5/blob/main/docs/building.md).

## Checkouts and tools

```
git clone https://github.com/HuskerMinion/techo5
git clone https://github.com/HuskerMinion/techo5-spot
```

Side by side, as above, the scripts find each other; otherwise set `TECHO5`. The Spot's daemon is
TECHO5's `main` built with `-tags spot`. You need Go, Python 3, bash (Git Bash on Windows) and
PowerShell 7; the kernel builds in Linux or WSL.

## 1. Inputs

```
cd techo5
pwsh ./tools/fetch-inputs.ps1 -Device spot -Out ../techo5-spot/inputs
```

That fetches the Alpine base image, `busybox.static`, `apk.static`, the wake word models, and the
rescue initramfs's packages. From **your own Spot**, never published: the LineageOS boot image
(`adb pull /dev/block/mmcblk0p9 inputs/boot-lineage-18.1-20251108-rook.img` with adb as root; the
installer keeps one in `backups/<serial>/`).

The vendor tree (the `bcmdhd` Wi-Fi driver, Broadcom firmware and Bluetooth patch) is not an input:
no image carries it. Each Spot keeps its own in the slot store, copied there by the installer before
LineageOS is erased, and mounted at `/vendor` (TECHO5's `etc/techo5/boot.sh`).

## 2. The Bluetooth kernel

[tools/linux/build-kernel.sh](../tools/linux/build-kernel.sh) rebuilds LineageOS's rook kernel at the
commit the boot image came from (so `amzn-bcmdhd.ko` still loads), with the running kernel's
configuration from [docs/dumps](dumps) and Bluetooth added. Its header lists the source, the toolchain
(Arm's GCC 8.3, no root needed) and every variable.

```
# in Linux or WSL, from this checkout
bash tools/linux/build-kernel.sh -o inputs/Image.gz-dtb-rook-bt
```

## 3. The boot image

```
KERNEL=inputs/Image.gz-dtb-rook-bt bash tools/linux/build-image.sh -o bin/techo5-spot-linux-boot.img
```

It builds TECHO5's armv7 tools, and packs the kernel, [tools/linux/init](../tools/linux/init), the
packages, `slotctl` and busybox into the rescue initramfs. With `inputs/techo5_ed25519.pub` present
the rescue environment accepts that SSH key; otherwise it accepts only keys on the unit's userdata
(`/data/misc/techo5/ssh/authorized_keys`). Flash from fastboot (Volume Down at power-on):
`fastboot flash boot bin/techo5-spot-linux-boot.img`.

## 4. The root filesystem

From the TECHO5 checkout, with this repository's overlay:

```
BUILD_TAGS=spot VERSION=v0.0.0-test DEVICE_OVERLAY=../techo5-spot/tools/linux/rootfs HOST=<spot address> \
  bash tools/linux/deploy-rootfs.sh --install
```

With `HOST` a running Spot (SSH switched on in Home Assistant), `--install` puts it into the spare
slot. On Windows it builds in WSL; elsewhere it builds on the Spot itself.

## 5. Installing your build

On Windows, `tools/install-spot-linux.ps1 -FromSource -Version v0.0.0-test` does steps 2 to 4 through
WSL and Git Bash and installs the result on a Spot still running LineageOS. On Linux and macOS, build
as above and flash the boot image by hand, or install the release and update over SSH.

## 6. Releases (maintainer)

```
pwsh ./tools/release-spot.ps1 -Version v0.3.0 -Rootfs <root filesystem tarball> -Notes "..." -DryRun
```

It checks the tarball's version, takes the daemon out of it, signs the manifest with
`TECHO5_SIGN_KEY`, and publishes the Bluetooth kernel, the rescue bundle (packages, busybox, TECHO5's
tools and `mkimage.py`) and `SHA256SUMS`. The installer builds each Spot's boot image from those.
