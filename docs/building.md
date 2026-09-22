# Building TECHO5 Spot yourself

You don't need any of this to install or update a Spot. `tools/install-spot.py` and Home Assistant's
update card use the signed releases. This page is for changing the daemon, the kernel or the images.
The Spot's daemon is TECHO5's, built with `-tags spot`.

## 1. Set up your computer

Everything is Go, Python 3 and bash. Two builds need Linux: the root filesystem (it runs Alpine's
package manager under QEMU) and the kernel.

**Linux** (Ubuntu or Debian; other distributions have the same packages under similar names):

```
sudo apt install git python3 qemu-user-static binfmt-support uidmap \
    build-essential bc bison flex libssl-dev curl xz-utils
```

and Go 1.26 or later from [go.dev/dl](https://go.dev/dl/) (distribution packages are often older).

**Windows:** install [Git for Windows](https://git-scm.com/download/win) (Git Bash runs the `.sh`
scripts), [Go](https://go.dev/dl/) and [Python 3](https://www.python.org/downloads/). Then install WSL
with Ubuntu (`wsl --install -d Ubuntu`) and, inside Ubuntu, the Linux packages above. The root
filesystem build runs in WSL on its own when you start it from Git Bash; the kernel build is run inside
Ubuntu. On Windows, type `python` where this page says `python3`.

**macOS:** `xcode-select --install` (git, bash, Python 3), then `brew install go`. The daemon and the
boot image build on macOS; the root filesystem is built on a running Spot instead (step 5 does that over
SSH), and the kernel needs a Linux machine or virtual machine.

Get the code, both repositories side by side:

```
git clone https://github.com/HuskerMinion/techo5
git clone https://github.com/HuskerMinion/techo5-spot
```

## 2. Fetch the inputs

```
cd techo5
python3 tools/fetch-inputs.py --device spot --out ../techo5-spot/inputs
```

That fills techo5-spot's `inputs/` (git-ignored) with Alpine's base image, `busybox.static`,
`apk.static`, the rescue initramfs's packages and the wake word models. The root filesystem build
looks for `apk.static` in your home directory, so on Linux (or inside WSL's Ubuntu) also run:

```
mkdir -p ~/apk && cp ../techo5-spot/inputs/apk.static ~/apk/apk.static
```

**From your own Spot, for a boot image only:** its LineageOS boot image, as
`techo5-spot/inputs/boot-lineage-18.1-20251108-rook.img`. The installer keeps one in `backups/<serial>/`,
or with LineageOS running and Rooted debugging on: `adb pull /dev/block/mmcblk0p9 <that path>`.

No vendor tree (the `bcmdhd` Wi-Fi driver, Broadcom firmware and Bluetooth patch) is needed or
published: each Spot keeps its own in the slot store, copied there by the installer before LineageOS is
erased, and mounted at `/vendor` (TECHO5's `tools/linux/rootfs/etc/techo5/boot.sh`).

## 3. The daemon

From techo5:

```
cd echod
GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -tags spot -o ../bin/echod-arm-spot ./cmd/echod
cd ..
```

To try it on a Spot already running TECHO5 (SSH switch on in Home Assistant, with a key sent through
`ssh_keys`), bind it in place until the next reboot:

```
scp bin/echod-arm-spot root@<address>:/tmp/echod-test
ssh root@<address> 'mount --bind /tmp/echod-test /usr/local/bin/techo5 && killall techo5'
```

## 4. The Bluetooth kernel (Linux)

[tools/linux/build-kernel.sh](../tools/linux/build-kernel.sh) rebuilds LineageOS's rook kernel at the
commit the boot image came from (so `amzn-bcmdhd.ko` still loads), with the running kernel's
configuration from [docs/dumps](dumps) and Bluetooth added. Its header lists the source and the
toolchain (Arm's GCC 8.3, downloaded without root). From techo5-spot, on Linux or inside WSL's Ubuntu:

```
bash tools/linux/build-kernel.sh -o inputs/Image.gz-dtb-rook-bt
```

## 5. The root filesystem

From techo5, with this repository's overlay and inputs:

```
export BUILD_TAGS=spot DEVICE_OVERLAY=../techo5-spot/tools/linux/rootfs TECHO5_INPUTS=../techo5-spot/inputs
bash tools/linux/deploy-rootfs.sh --out build/spot-rootfs.tar.gz --version v0.0.0-test         # Linux, or Git Bash on Windows
HOST=<address> bash tools/linux/deploy-rootfs.sh --version v0.0.0-test --install              # build and install on a running Spot
```

The first keeps the tarball. The second sends it to a Spot (SSH on) and installs it into the spare slot,
where it boots on trial and falls back if it doesn't settle; on macOS only the second works, and the
build runs on the Spot itself.

## 6. The boot image

From techo5-spot:

```
KERNEL=inputs/Image.gz-dtb-rook-bt bash tools/linux/build-image.sh -o build/techo5-spot-boot.img
```

It builds TECHO5's armv7 tools and packs the kernel, [tools/linux/init](../tools/linux/init), the
packages, `slotctl` and busybox into the rescue initramfs. With `inputs/techo5_ed25519.pub` present the
rescue environment also accepts that SSH key.

## 7. Install your build

On a Spot still running LineageOS (backed up first with `tools/backup-spot.py`), the installer takes
your files in place of the release's:

```
python3 tools/install-spot.py --serial <serial> --name Kitchen --kernel inputs/Image.gz-dtb-rook-bt --rootfs ../techo5/build/spot-rootfs.tar.gz
```

On a Spot already running TECHO5, step 5's `--install` puts a root filesystem in the spare slot, and a
boot image goes on with `fastboot flash boot build/techo5-spot-boot.img` (Volume Down at power-on).

## Package versions

TECHO5's package lists name exact Alpine versions. Alpine keeps only the newest build of each package,
so an old version eventually disappears from its mirror; `fetch-inputs.py` then takes the newest and says
so. Releases don't depend on this: the rescue bundle carries every package the installer needs, and the
lists are brought up to date (and tested) before a release.

## Releases (maintainer)

```
pwsh ./tools/release-spot.ps1 -Version v0.3.0 -Rootfs <root filesystem tarball> -Notes "..." -DryRun
```

A PowerShell script for the maintainer's Windows machine: it checks the tarball's version and that it
carries no vendor tree, takes the daemon out of it, and publishes the Bluetooth kernel and the rescue
bundle (packages, busybox, TECHO5's tools and `mkimage.py`), from which the installer builds each
Spot's boot image. The manifest names all of them, with their sha256 and size, and is signed with
`TECHO5_SIGN_KEY`: that signature is the installer's only check on what it downloads — it unpacks the
rescue bundle and runs scripts out of it on your machine. `SHA256SUMS` is published too, for checking
a file by hand; nothing signs it, so no installer reads it.

## Where things default

Everything goes into git-ignored folders in the checkout, and each can be moved with an environment
variable: `inputs/` (`TECHO5_INPUTS`), `build/` (`TECHO5_WORK`), `backups/` (`TECHO5_BACKUPS`).
`TECHO5` points at the TECHO5 checkout when it isn't beside this one.
