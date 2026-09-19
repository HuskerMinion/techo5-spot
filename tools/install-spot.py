#!/usr/bin/env python3
"""Install TECHO5 on an Echo Spot (rook) running LineageOS 18.1, in one command.

    python3 tools/backup-spot.py --serial <serial> --include-system      (from TWRP, first)
    python3 tools/install-spot.py --serial <serial> --name Kitchen --build-only
    python3 tools/install-spot.py --serial <serial> --name Kitchen

Windows, Linux and macOS alike; needs Python 3, adb and fastboot. Nothing is compiled: the release's root
filesystem, Bluetooth kernel and rescue bundle are downloaded and checked, and this unit's boot image is
built from them and its own LineageOS boot image. Each step is checked before the next:

  1. checks    adb sees the unit as rook with root; its partition backups are on this computer
  2. release   the root filesystem, the Bluetooth kernel and the rescue bundle, checked against their
               checksums; this unit's LineageOS boot image kept in backups/<serial>/; the boot image built
  3. provision name, Home Assistant key and an SSH key (--ssh-key) onto userdata, and the root
               filesystem, each checked by md5
  4. flash     the boot image, from the bootloader's fastboot
  5. store     over the USB serial console: this unit's own vendor tree (Wi-Fi and Bluetooth drivers,
               firmware) is kept, LineageOS's system partition becomes the slot store (THIS ERASES
               LINEAGEOS), the root filesystem goes into slot a, and with --logo the bootloader picture
               is replaced (only if the partition still matches its backup)
  6. watch     the first boot from slot a to a running daemon; the slot is marked good

The Home Assistant key is kept in backups/<serial>/home-assistant.key (api.psk on a unit installed
before that name) and reused, so Home Assistant keeps the device. Undo: fastboot flash boot backups/<serial>/boot-lineage-18.1.img and restore system from TWRP
or the backups; the bootloader picture: backups/<serial>/expdb.img back to expdb.
"""
import argparse
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from techo5lib import (CONSOLE_TECHO5, Adb, Console, Fastboot, Release, alpine, default_dir, fail,  # noqa: E402
                       head_is_android, md5, need, new_api_key, note, repo_root, run_main, step,
                       tar_extract_all, valid_api_key, wait_for)

REPO = 'HuskerMinion/techo5-spot'
WIFI_MODULE = 'vendor/lib/modules/amzn-bcmdhd.ko'
# The bootloader picture's slot in the kaeru copy of LK (expdb), found on the first unit
# (docs/hardware.md, "Boot logo"): 480x480, 12096 bytes at this offset.
LOGO_OFFSET = 431416
LOGO_SLOT = 12096


def build_boot_image(rescue, lineage_boot, alpine_tgz, kernel, out):
    """This unit's boot image: its LineageOS boot image's header (and kernel, without --kernel), and the
    rescue initramfs on Alpine's base, from the release's rescue bundle."""
    j = os.path.join
    mk = [sys.executable, j(rescue, 'host', 'mkimage.py'), '--kernel-image', lineage_boot, '--rootfs', alpine_tgz,
          '--init', j(repo_root(), 'tools', 'linux', 'init'), '--add', j(rescue, 'busybox.static') + '=/bin/busybox.static']
    if kernel:
        mk += ['--kernel', kernel]
    for t in ('fbprobe', 'audioprobe', 'rebootto'):
        mk += ['--add', j(rescue, 'bin', t) + '=/usr/local/bin/' + t]
    mk += ['--script', j(rescue, 'scripts', 'slotctl') + '=/usr/local/sbin/slotctl',
           '--script', j(rescue, 'scripts', 'techo5-lib.sh') + '=/lib/techo5-lib.sh']
    for apk in sorted(os.listdir(j(rescue, 'apks'))):
        if apk.endswith('.apk'):
            mk += ['--apk', j(rescue, 'apks', apk)]
    mk += ['--compress', 'xz', '--cmdline-append', 'techo5=linux', '-o', out]
    if subprocess.run(mk).returncode != 0:
        fail('building the boot image failed')


def default_key_file(backup):
    """backups/<serial>/home-assistant.key, as on the Dot; a unit installed while it was api.psk keeps
    that file, so a later run reuses the key Home Assistant already has."""
    new = os.path.join(backup, 'home-assistant.key')
    old = os.path.join(backup, 'api.psk')
    return old if os.path.exists(old) and not os.path.exists(new) else new


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--serial', required=True, help="the unit's adb serial (adb devices)")
    ap.add_argument('--name', required=True, help='the name Home Assistant shows, e.g. Kitchen')
    ap.add_argument('--release', default='latest', help='a release tag, or latest')
    ap.add_argument('--key-file', help='where the Home Assistant key is kept (default backups/<serial>/home-assistant.key)')
    ap.add_argument('--ssh-key', help='an SSH public key the unit accepts from the start')
    ap.add_argument('--no-bluetooth', action='store_true', help="keep LineageOS's kernel, which has no Bluetooth")
    ap.add_argument('--kernel', help='a kernel you built (tools/linux/build-kernel.sh) instead of the release\'s')
    ap.add_argument('--rootfs', help='a root filesystem you built instead of the release\'s')
    ap.add_argument('--logo', action='store_true', help="replace the bootloader's Amazon picture with TECHO5's (needs Pillow)")
    ap.add_argument('--build-only', action='store_true', help='build the boot image and stop; write nothing to the unit')
    ap.add_argument('--force', action='store_true', help='do not ask before erasing LineageOS')
    ap.add_argument('--backups', default=default_dir('TECHO5_BACKUPS', 'backups'))
    ap.add_argument('--work', default=default_dir('TECHO5_WORK', 'build'))
    ap.add_argument('--adb', default='adb')
    ap.add_argument('--fastboot', default='fastboot')
    a = ap.parse_args()

    backup = os.path.join(a.backups, a.serial)
    key_file = a.key_file or default_key_file(backup)
    boot_out = os.path.join(backup, 'techo5-spot-linux-boot.img')
    los_boot = os.path.join(backup, 'boot-lineage-18.1.img')
    adb = Adb(a.serial, a.adb)
    fastboot = Fastboot(a.serial, a.fastboot)
    console = Console(a.serial, CONSOLE_TECHO5)

    # ------------------------------------------------------------------------------------ 1. checks
    step('checks')
    if len(a.name) > 31 or '\n' in a.name:
        fail('the name must be one line of at most 31 characters')
    if a.logo and subprocess.run([sys.executable, '-c', 'import PIL'], stderr=subprocess.DEVNULL).returncode != 0:
        fail('--logo needs Pillow: %s -m pip install pillow' % os.path.basename(sys.executable))
    for b in ('expdb.img', 'lk.img', 'recovery.img', 'system.img'):
        if not os.path.exists(os.path.join(backup, b)):
            fail('%s is missing: back the unit up first (tools/backup-spot.py --serial %s --include-system, from TWRP)'
                 % (os.path.join(backup, b), a.serial))
    note('backups present in %s' % backup)
    pub = None
    if a.ssh_key:
        with open(os.path.expanduser(a.ssh_key)) as f:
            pub = f.read().strip()
    for f in (a.kernel, a.rootfs):
        if f and not os.path.exists(f):
            fail('no file at %s' % f)
    if not a.build_only:
        need(a.adb, 'install the Android platform tools (adb and fastboot)')
        need(a.fastboot, 'install the Android platform tools (adb and fastboot)')
        state = adb.state()
        if state != 'device':
            fail("adb does not see %s running LineageOS (state '%s')" % (a.serial, state))
        dev = adb.sh('getprop ro.product.device')
        if dev != 'rook':
            fail("%s reports '%s', not rook" % (a.serial, dev))
        adb.root()
        if not adb.sh('id').startswith('uid=0'):
            fail('adb is not root: turn on Rooted debugging in Developer options')
        wifi = adb.sh('grep -c PreSharedKey /data/misc/apexdata/com.android.wifi/WifiConfigStore.xml 2>/dev/null')
        if wifi in ('', '0'):
            fail('LineageOS has no saved Wi-Fi network with a password: join one first')
        note('rook, adb root, a saved Wi-Fi network')

    # ------------------------------------------------------------------------------------ 2. release
    step("the release, and this unit's boot image")
    os.makedirs(a.work, exist_ok=True)
    if not os.path.exists(los_boot):
        if a.build_only:
            fail('no %s yet; run once without --build-only' % los_boot)
        if not adb.pull('/dev/block/mmcblk0p9', los_boot + '.partial'):
            fail('reading the LineageOS boot partition failed')
        if md5(los_boot + '.partial') != adb.sh('md5sum /dev/block/mmcblk0p9').split(' ')[0]:
            fail('LineageOS boot image md5 mismatch')
        if not head_is_android(los_boot + '.partial'):
            fail('the boot partition holds no Android boot image (not LineageOS?)')
        os.replace(los_boot + '.partial', los_boot)
    note('LineageOS boot image: %s' % los_boot)
    rel = Release(REPO, a.release, a.work)
    version = rel.version
    rootfs = os.path.abspath(a.rootfs) if a.rootfs else rel.rootfs('arm-spot')
    kernel = None if a.no_bluetooth else (os.path.abspath(a.kernel) if a.kernel else rel.asset('techo5-spot-kernel-bt.Image.gz-dtb'))
    rescue = os.path.join(rel.dir, 'rescue')
    tar_extract_all(rel.asset('techo5-spot-rescue.tar'), rescue)
    note('TECHO5 Spot %s: root filesystem, %s and rescue bundle checked'
         % (version, 'Bluetooth kernel' if kernel else "LineageOS's kernel (no Bluetooth)"))
    build_boot_image(rescue, los_boot, alpine(a.work), kernel, boot_out)
    note('boot image %d bytes' % os.path.getsize(boot_out))
    logo_chunk = os.path.join(backup, 'expdb-logo-chunk.bin')
    if a.logo:
        patched = os.path.join(backup, 'expdb-techo5.img')
        r = subprocess.run([sys.executable, os.path.join(rescue, 'host', 'patch-lk-logo.py'), os.path.join(backup, 'expdb.img'), patched,
                            os.path.join(repo_root(), 'logo', 'spot-boot-480.png'), '--bundle', str(LOGO_OFFSET),
                            '--size', '480x480', '--in-place', '--colors', '24'])
        if r.returncode != 0:
            fail('patch-lk-logo.py failed')
        with open(patched, 'rb') as f:
            f.seek(LOGO_OFFSET)
            chunk = f.read(LOGO_SLOT)
        with open(logo_chunk, 'wb') as f:
            f.write(chunk)
        note('bootloader picture prepared')
    if a.build_only:
        print('\nBuild only: boot image %s and root filesystem %s; nothing written to the unit.' % (boot_out, rootfs))
        return

    # ------------------------------------------------------------------------------------ 3. provision
    step('provision')
    if os.path.exists(key_file):
        with open(key_file) as f:
            psk = f.read().strip()
        if not valid_api_key(psk):
            fail('the key in %s is not 32 bytes of base64' % key_file)
        note('Home Assistant key: the existing one in %s' % key_file)
    else:
        psk = new_api_key()
        with open(key_file, 'w') as f:
            f.write(psk)
        note('Home Assistant key: new, in %s' % key_file)
    adb.sh('mkdir -p /data/misc/techo5/models /data/misc/techo5/ssh /data/techo5-linux; chmod 700 /data/misc/techo5 /data/misc/techo5/ssh')
    tmp = os.path.join(a.work, 'provision-' + a.serial)
    os.makedirs(tmp, exist_ok=True)
    try:
        files = [('name', a.name), ('psk', psk)] + ([('ssh/authorized_keys', pub + '\n')] if pub else [])
        for remote, text in files:
            local = os.path.join(tmp, remote.replace('/', '_'))
            with open(local, 'w', newline='\n') as f:
                f.write(text)
            adb.push(local, '/data/misc/techo5/' + remote)
            os.remove(local)
    finally:
        os.rmdir(tmp)
    adb.sh('chmod 600 /data/misc/techo5/name /data/misc/techo5/psk /data/misc/techo5/ssh/authorized_keys 2>/dev/null')
    tar_name = 'techo5-spot-rootfs-%s.tar.gz' % version
    uploads = [(rootfs, '/data/techo5-linux/' + tar_name)]
    if a.logo:
        uploads.append((logo_chunk, '/data/techo5-linux/expdb-logo-chunk.bin'))
    for local, remote in uploads:
        adb.push(local, remote)
        if adb.sh('md5sum ' + remote).split(' ')[0] != md5(local):
            fail('md5 mismatch after pushing ' + local)
        note(remote + ' ok')

    # ------------------------------------------------------------------------------------ 4. flash
    step('flash the boot image')
    adb.reboot('bootloader')
    wait_for('fastboot', 90, fastboot.present, 3)
    code, out = fastboot.run('flash', 'boot', boot_out)
    if code != 0:
        fail('fastboot flash boot failed: ' + out)
    fastboot.run('reboot')
    note('rebooting into the rescue initramfs (no slot store yet)')
    nudged = [False]

    def rescue_up():
        if 'RESCUE-UP' in (console.run('test -e /run/techo5/slot || echo RESCUE-UP', 4) or ''):
            return True
        # After `adb reboot bootloader`, kaeru can stop in fastboot once more; `continue` goes on.
        if not nudged[0] and fastboot.present():
            time.sleep(20)
            if fastboot.present():
                fastboot.run('continue')
                nudged[0] = True
        return False
    wait_for('the rescue console on USB', 300, rescue_up)
    if '4.9.337' not in (console.run('uname -r') or ''):
        fail('the unit came up on an unexpected kernel')
    note('rescue console on %s' % console.port)

    # ------------------------------------------------------------------------------------ 5. store
    step('slot store')
    if not a.force:
        print("   Next: LineageOS's system partition (mmcblk0p11) is erased and becomes the slot store.")
        if input('   Type ERASE to go on: ').strip() != 'ERASE':
            fail('stopped before erasing; the unit stays in rescue (fastboot flash boot the LineageOS image to go back)')
    tar = '/data/techo5-linux/' + tar_name
    # The vendor tree is this unit's own, from LineageOS: releases don't carry it. Kept on userdata
    # before the system partition is erased, then in the store.
    o = console.run('touch /tmp/stay; tar -cf /data/techo5-linux/vendor.tar -C /android/system vendor && '
                    'tar -tf /data/techo5-linux/vendor.tar %s >/dev/null && echo VENDOR-SAVED' % WIFI_MODULE, 180)
    if 'VENDOR-SAVED' not in (o or ''):
        fail("saving LineageOS's vendor tree failed (nothing was erased):\n%s" % o)
    o = console.run('killall techo5 fbprobe 2>/dev/null; sleep 2; umount /android 2>/dev/null; mountpoint -q /android && echo STILL-MOUNTED; '
                    'slotctl mkstore /dev/mmcblk0p11 --i-know-this-erases-it >/tmp/mkstore.log 2>&1 && echo MKSTORE-OK; tail -3 /tmp/mkstore.log', 300)
    if 'MKSTORE-OK' not in (o or ''):
        fail('mkstore failed:\n%s' % o)
    o = console.run('tar -xf /data/techo5-linux/vendor.tar -C /store && [ -e /store/%s ] && echo VENDOR-OK' % WIFI_MODULE, 180)
    if 'VENDOR-OK' not in (o or ''):
        fail('putting the vendor tree into the store failed (it is kept in /data/techo5-linux/vendor.tar):\n%s' % o)
    o = console.run('STORE=/store slotctl install %s >/tmp/install.log 2>&1 && echo INSTALL-OK; tail -2 /tmp/install.log; '
                    '[ -e /store/slots/a/%s ] || { mkdir -p /store/slots/a/vendor && cp -a /store/vendor/. /store/slots/a/vendor/; }; '
                    '[ -e /store/slots/a/%s ] && rm -f /data/techo5-linux/vendor.tar && echo SLOT-VENDOR-OK; STORE=/store slotctl status'
                    % (tar, WIFI_MODULE, WIFI_MODULE), 900)
    if 'INSTALL-OK' not in (o or ''):
        fail('slot install failed:\n%s' % o)
    if 'SLOT-VENDOR-OK' not in o:
        fail('the vendor tree did not reach slot a:\n%s' % o)
    for line in o.split('\n'):
        if line.startswith('slot a'):
            note(line)
    if a.logo:
        with open(os.path.join(backup, 'expdb.img'), 'rb') as f:
            old = bytearray(f.read())
        import hashlib
        want_old = hashlib.md5(old).hexdigest()
        with open(logo_chunk, 'rb') as f:
            chunk = f.read()
        new = old[:LOGO_OFFSET] + chunk + old[LOGO_OFFSET + LOGO_SLOT:]
        want_new = hashlib.md5(new).hexdigest()
        o = console.run(
            'cd /data/techo5-linux; '
            '[ "$(md5sum /dev/mmcblk0p7 | cut -d" " -f1)" = %s ] || { echo EXPDB-CHANGED; exit; }; '
            '[ "$(md5sum expdb-logo-chunk.bin | cut -d" " -f1)" = %s ] || { echo CHUNK-BAD; exit; }; '
            'dd if=expdb-logo-chunk.bin of=/dev/mmcblk0p7 bs=4096 seek=%d oflag=seek_bytes conv=notrunc,fsync 2>/dev/null; sync; '
            'echo 3 > /proc/sys/vm/drop_caches; [ "$(md5sum /dev/mmcblk0p7 | cut -d" " -f1)" = %s ] && echo LOGO-OK; rm -f expdb-logo-chunk.bin'
            % (want_old, md5(logo_chunk), LOGO_OFFSET, want_new), 60) or ''
        if 'LOGO-OK' in o:
            note('bootloader picture written')
        elif 'EXPDB-CHANGED' in o:
            note('expdb differs from its backup: bootloader picture left alone')
        else:
            fail('writing the bootloader picture failed (restore %s to expdb from fastboot):\n%s' % (os.path.join(backup, 'expdb.img'), o))
    console.run('sync; (sleep 2; /bin/busybox.static reboot -f) >/dev/null 2>&1 &', 3)

    # ------------------------------------------------------------------------------------ 6. watch
    step('first boot')
    wait_for('slot a with the daemon running', 300,
             lambda: bool(re.search(r'slot=a- daemon=\d', console.run('echo slot=$(cat /run/techo5/slot 2>/dev/null)- daemon=$(pidof techo5)-', 4) or '')))
    note('slot a booted, daemon running; giving it a minute')
    time.sleep(60)
    o = console.run('pidof techo5 >/dev/null && slotctl commit; slotctl status | head -5; ip -4 addr show wlan0 | grep -c inet; ls /sys/class/bluetooth 2>/dev/null', 15) or ''
    for line in o.split('\n'):
        note(line)
    if 'committed' not in o and 'already good' not in o:
        fail('the slot was not marked good: check the daemon log (/data/techo5-linux/techo5.log)')

    print("\nDone. '%s' runs TECHO5 Spot %s from slot a." % (a.name, version))
    print('Home Assistant finds it as an ESPHome device. When it asks for the encryption key, paste:\n\n    %s\n\n(kept in %s)' % (psk, key_file))
    print("Later versions arrive through Home Assistant's update card.")


if __name__ == '__main__':
    run_main(main)
