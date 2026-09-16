# TECHO5 Spot

**TECHO5 for the Echo Spot**: the TECHO5 Linux image, brought to the Amazon Echo Spot 1st
generation (2017, codename `rook`, model VN94DQ / `AEORK`).

The goal is the same end state [TECHO5](https://github.com/HuskerMinion/techo5) reached on the
Echo Show 5 2nd gen and TECHO5 Dot reached on the Echo Dot 2. No Fire OS userspace: a small Alpine
root filesystem and one daemon that owns the microphones, the speaker, the round screen, wake word
and the Home Assistant connection (ESPHome native API), with nothing leaving the house.

## Status

M0 under way on the first unit (<serial>, Fire OS 5.5.6.9): unlocked 2026-09-16, TWRP in
`recovery`, hardware read and every partition backed up. What exists:

- [docs/hardware.md](docs/hardware.md): what is known about `rook` from the unlock, TWRP, LineageOS
  and kernel sources and a stock firmware dump, each fact with its source, and what the first unit
  confirmed or corrected.
- [docs/porting-plan.md](docs/porting-plan.md): milestones from a stock Spot to the Linux image, and
  what carries over from the Show and the Dot and what does not.
- [tools/hwdump.sh](tools/hwdump.sh): the read-only hardware inventory for the first time a unit is
  plugged in (Fire OS with root, or TWRP).
- [tools/backup-spot.ps1](tools/backup-spot.ps1): pulls every partition that boots the unit to the PC
  and checks each copy against an md5 read on the device. Writes nothing to the unit.
- [docs/dumps/](docs/dumps/): the LineageOS kernel's `rook_defconfig`, and its difference from
  `cronos_defconfig`.

## The short version

The Spot is the Show 5's closest relative, not the Dot's: same MT8163, same LineageOS 4.9 kernel
tree (`rook_defconfig` beside `cronos_defconfig`), a screen, a camera, a single `boot` partition
rather than A/B slots. It differs in the radio: Wi-Fi and Bluetooth are a **Broadcom BCM43569**, Wi-Fi
over USB with the `bcmdhd` driver and Bluetooth over a UART, so neither the Show's `mt76x8` modules nor
the Dot's `wmtup` apply. It has about 2 GB of RAM, more than either.

## Lineage

- [TECHO5](https://github.com/HuskerMinion/techo5) (MIT): the daemon (`echod`), the Linux image
  tooling, the rootfs slot design and the kernel build recipe this port starts from.
- TECHO5 Dot (MIT): the 512 MB image, the hand-made `/dev`, the installer pattern.
- [EchoLocal](https://github.com/ygelfand/echolocal) (MIT, Yuri Gelfand): the daemon TECHO5's `echod`
  was ported from.
- amonet, kaeru and the Echo TWRP trees ([R0rt1z2](https://github.com/R0rt1z2), k4y0z): the unlock.
- [amazon-oss](https://github.com/amazon-oss): the LineageOS 18.1 `rook` device tree and the 4.9
  kernel it builds.

## License

MIT. See [LICENSE](LICENSE).

TECHO5 is not affiliated with Amazon. Echo, Echo Spot and Alexa are trademarks of Amazon.com, Inc.
