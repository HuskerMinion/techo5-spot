<#
.SYNOPSIS
  One command from an unlocked Echo Spot running LineageOS 18.1 to TECHO5 Linux running from a slot,
  named, keyed for Home Assistant, on the Wi-Fi LineageOS already had, with Bluetooth.

.DESCRIPTION
  What was done by hand on the first unit (docs/porting-plan.md, M2 and M3), in order, each step checked
  before the next:

    1. checks    adb sees the unit as rook with root; the Fire OS and LineageOS partition backups are
                 on this computer (tools/backup-spot.ps1); adb, fastboot and python are there
    2. capture   from this unit: its LineageOS boot image (the kernel header) and its /system/vendor,
                 kept in inputs/<serial>/ and backups/<serial>/, never published
    3. release   the latest signed release (or -Release): root filesystem, Bluetooth kernel and rescue
                 bundle, each checked against its checksum; this unit's boot image built from them
    4. provision name and ESPHome key into /data/misc/techo5 (and an SSH key with -SshKey), the root
                 filesystem and the logo onto userdata, each checked by md5 on the unit
    5. flash     the boot image, from the bootloader's fastboot
    6. store     in the rescue initramfs, over the USB serial console: the LineageOS system partition
                 becomes the slot store (THIS ERASES LINEAGEOS), the root filesystem goes into slot a,
                 and with -Logo the bootloader picture is written (only if the partition still matches
                 its backup)
    7. watch     the first boot from slot a to a running daemon; the slot is marked good

  Runs on Windows, Linux and macOS with PowerShell 7 (pwsh). Nothing is compiled: -FromSource builds the
  kernel and root filesystem locally instead (WSL and Git Bash on Windows, and a TECHO5 checkout; see
  docs/building.md).

  Wi-Fi comes from LineageOS's saved network (the rescue initramfs reads it from userdata). The API key
  is kept in backups/<serial>/api.psk (git-ignored), and an existing one is reused, so Home Assistant
  keeps the device.

  Undo: fastboot flash boot backups/<serial>/boot-lineage-18.1.img and restore system from TWRP, or the
  Fire OS backups. The bootloader picture: backups/<serial>/expdb.img back to expdb.

.EXAMPLE
  ./tools/install-spot-linux.ps1 -Serial <serial> -Name Kitchen -Logo

.EXAMPLE
  # Only build the boot image, touching no unit (after one run has captured this unit's files).
  ./tools/install-spot-linux.ps1 -Serial <serial> -Name Kitchen -BuildOnly
#>
param(
    [Parameter(Mandatory)][string]$Serial,
    [Parameter(Mandatory)][string]$Name,
    # A release tag, or latest.
    [string]$Release = 'latest',
    [string]$KeyFile,
    # An SSH public key (e.g. ~/.ssh/id_ed25519.pub) the unit accepts from the start.
    [string]$SshKey,
    # Keep LineageOS's kernel: no Bluetooth.
    [switch]$NoBluetooth,
    # Replace the Amazon picture the bootloader shows with TECHO5's (logo/spot-boot-480.png; needs Pillow).
    [switch]$Logo,
    # Build the boot image and stop; nothing is written to the unit.
    [switch]$BuildOnly,
    # Do not ask before erasing LineageOS's system partition.
    [switch]$Force,
    # Build the kernel and root filesystem here rather than taking the release's (Windows: WSL, Git Bash).
    [switch]$FromSource,
    # -FromSource only: a TECHO5 checkout on main.
    [string]$Techo5 = $(if ($env:TECHO5) { $env:TECHO5 } else { Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'techo5' }),
    [string]$Version,
    [string]$BackupRoot = $(if ($env:TECHO5_BACKUPS) { $env:TECHO5_BACKUPS } else { Join-Path (Join-Path $PSScriptRoot '..') 'backups' }),
    [string]$WorkDir = $(if ($env:TECHO5_WORK) { $env:TECHO5_WORK } else { Join-Path (Join-Path $PSScriptRoot '..') 'build' }),
    [string]$Adb = 'adb',
    [string]$Fastboot = 'fastboot',
    [string]$Python,
    [string]$Bash = 'C:\Program Files\Git\bin\bash.exe',
    [string]$WslDistro = 'Ubuntu'
)
$ErrorActionPreference = 'Stop'
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'release.ps1')
if (-not $Python) { $Python = Get-Python }
$BackupRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BackupRoot)
$WorkDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkDir)
$repo = $Script:SpotRepo
$backup = Join-Path $BackupRoot $Serial
$inputs = JoinParts $repo 'inputs', $Serial
$console = Join-Path $PSScriptRoot 'serial-console.ps1'
if (-not $KeyFile) { $KeyFile = Join-Path $backup 'api.psk' }
$bootOut = Join-Path $backup 'techo5-spot-linux-boot.img'
$logoChunk = Join-Path $inputs 'expdb-logo-chunk.bin'
# The bootloader picture's slot in the kaeru copy of LK (expdb), found on the first unit
# (docs/hardware.md, "Boot logo"): 480x480, 12096 bytes at this offset.
$logoOffset = 431416
$logoSlot = 12096

function Step([string]$what) { Write-Host "== $what" -ForegroundColor Cyan }
function Note([string]$what) { Write-Host "   $what" }
function Need([string]$exe) { if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { throw "$exe not found" } }
function AdbSh([string]$cmd) { (& $Adb -s $Serial shell $cmd) -join "`n" }
function Md5Of([string]$path) { (Get-FileHash -Algorithm MD5 $path).Hash.ToLower() }
function Spot([string]$cmd, [int]$waitMs = 8000) {
    $o = & $console -Serial $Serial -Cmd $cmd -WaitMs $waitMs -Port $global:SpotConsolePort
    if ($null -eq $o) { return $null }
    return [string]$o
}
function WaitFor([string]$what, [int]$seconds, [scriptblock]$test) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (& $test) { return }
        Start-Sleep -Seconds 5
    }
    throw "timed out after $seconds s waiting for $what"
}
# SetEnv sets or removes a variable. PowerShell hands $null to .NET as "", which leaves the variable
# there, empty; an empty MSYS_NO_PATHCONV still turns off Git Bash's path conversion.
function SetEnv([string]$k, $v) {
    if ([string]::IsNullOrEmpty($v)) { Remove-Item "Env:\$k" -ErrorAction SilentlyContinue }
    else { Set-Item "Env:\$k" $v }
}
function Unix([string]$winPath) { '/' + $winPath.Substring(0, 1).ToLower() + ($winPath.Substring(2) -replace '\\', '/') }

# ------------------------------------------------------------------------------------------ 1. checks
Step 'checks'
Need $Python
if ($FromSource) {
    if ($IsLinux -or $IsMacOS) { throw '-FromSource is written for Windows (WSL and Git Bash); on Linux follow docs/building.md' }
    Need 'wsl'
    if (-not (Test-Path $Bash)) { throw "Git Bash not found at $Bash" }
    if (-not (Test-Path (JoinParts $Techo5 'tools', 'linux', 'deploy-rootfs.sh'))) { throw "$Techo5 is not a TECHO5 checkout (set TECHO5 or pass -Techo5)" }
    if (-not $Version) { throw '-FromSource needs -Version (the version the root filesystem is built as)' }
}
if ($Logo) {
    & $Python -c 'import PIL' 2>$null
    if ($LASTEXITCODE -ne 0) { throw "-Logo needs Pillow: $Python -m pip install pillow" }
}
foreach ($b in 'expdb.img', 'lk.img', 'recovery.img', 'system.img') {
    if (-not (Test-Path (Join-Path $backup $b))) {
        throw "$(Join-Path $backup $b) is missing: back the unit up first (tools/backup-spot.ps1 -IncludeSystem from TWRP)"
    }
}
Note "backups present in $backup"
if ($SshKey -and -not (Test-Path $SshKey)) { throw "no SSH public key at $SshKey" }
if (-not $BuildOnly) {
    foreach ($exe in $Adb, $Fastboot) { Need $exe }
    $state = (& $Adb -s $Serial get-state 2>$null)
    if ($state -ne 'device') { throw "adb does not see $Serial running LineageOS (state '$state')" }
    $dev = (AdbSh 'getprop ro.product.device').Trim()
    if ($dev -ne 'rook') { throw "$Serial reports '$dev', not rook" }
    & $Adb -s $Serial root | Out-Null; Start-Sleep -Seconds 3; & $Adb -s $Serial wait-for-device
    if ((AdbSh 'id') -notmatch '^uid=0') { throw 'adb is not root: turn on Rooted debugging in Developer options' }
    $ssid = (AdbSh 'grep -c PreSharedKey /data/misc/apexdata/com.android.wifi/WifiConfigStore.xml 2>/dev/null').Trim()
    if ($ssid -eq '' -or $ssid -eq '0') { throw 'LineageOS has no saved Wi-Fi network with a password: join one first' }
    Note "rook, adb root, a saved Wi-Fi network"
}

# ----------------------------------------------------------------------------------------- 2. capture
Step 'capture'
New-Item -ItemType Directory -Force $inputs, $WorkDir | Out-Null
$vendorTgz = Join-Path $inputs 'system-vendor.tgz'
$losBoot = Join-Path $backup 'boot-lineage-18.1.img'
if (-not (Test-Path $vendorTgz)) {
    if ($BuildOnly) { throw "no $vendorTgz captured yet; run without -BuildOnly first" }
    AdbSh 'rm -f /data/local/tmp/vendor.tgz; tar -czf /data/local/tmp/vendor.tgz -C /system vendor && md5sum /data/local/tmp/vendor.tgz' | Out-Null
    & $Adb -s $Serial pull /data/local/tmp/vendor.tgz "$vendorTgz.partial" | Out-Null
    $want = (AdbSh 'md5sum /data/local/tmp/vendor.tgz').Split(' ')[0]
    if ((Md5Of "$vendorTgz.partial") -ne $want) { throw 'vendor tarball md5 mismatch' }
    Move-Item "$vendorTgz.partial" $vendorTgz
    AdbSh 'rm -f /data/local/tmp/vendor.tgz' | Out-Null
}
if (-not (Test-Path $losBoot)) {
    if ($BuildOnly) { throw "no $losBoot yet; run without -BuildOnly first" }
    & $Adb -s $Serial pull /dev/block/mmcblk0p9 "$losBoot.partial" | Out-Null
    $want = (AdbSh 'md5sum /dev/block/mmcblk0p9').Split(' ')[0]
    if ((Md5Of "$losBoot.partial") -ne $want) { throw 'LineageOS boot image md5 mismatch' }
    $head = [byte[]]::new(8)
    $fs = [IO.File]::OpenRead("$losBoot.partial"); try { [void]$fs.Read($head, 0, 8) } finally { $fs.Close() }
    if ([Text.Encoding]::ASCII.GetString($head) -ne 'ANDROID!') { throw 'the boot partition holds no Android boot image (not LineageOS?)' }
    Move-Item "$losBoot.partial" $losBoot
}
Note "LineageOS boot image: $losBoot"
$tgzList = & (Get-Tar) -tzf $vendorTgz
foreach ($f in 'vendor/lib/modules/amzn-bcmdhd.ko', 'vendor/firmware/BCM43569A2_001.003.004.0142.0191.hcd') {
    if (-not ($tgzList -contains $f)) { throw "the captured vendor tree has no $f (a different LineageOS build?)" }
}
Note "vendor tree: $vendorTgz"

# ----------------------------------------------------------------------------------- 3. release, boot image
if (-not $FromSource) {
    Step 'the release, and this unit''s boot image'
    $rel = Get-SpotRelease -WorkDir $WorkDir -Release $Release
    $Version = $rel.Version
    Note "TECHO5 Spot ${Version}: root filesystem, Bluetooth kernel and rescue bundle checked"
    $rootfsOut = $rel.Rootfs
    $kernel = if ($NoBluetooth) { $null } else { $rel.Kernel }
    New-SpotBootImage -LineageBoot $losBoot -Rescue $rel.Rescue -Alpine $rel.Alpine -Kernel $kernel -Out $bootOut -Python $Python
    $logoTool = JoinParts $rel.Rescue 'host', 'patch-lk-logo.py'
} else {
    Step 'build from source'
    $bin = Join-Path $repo 'bin'
    New-Item -ItemType Directory -Force $bin | Out-Null
    $rootfsOut = Join-Path $bin "techo5-rootfs-$Version.tar.gz"
    $kernelOut = JoinParts $repo 'inputs', 'Image.gz-dtb-rook-bt'
    $kernel = ''
    if (-not $NoBluetooth) {
        if (-not (Test-Path $kernelOut)) {
            Note 'kernel with Bluetooth (WSL; the first build takes a while)'
            $w = "/mnt/" + $repo.Substring(0, 1).ToLower() + ($repo.Substring(2) -replace '\\', '/')
            wsl -d $WslDistro -e bash "$w/tools/linux/build-kernel.sh" -o "$w/inputs/Image.gz-dtb-rook-bt"
            if ($LASTEXITCODE -ne 0) { throw 'kernel build failed' }
        }
        $kernel = $kernelOut -replace '\\', '/'
    }
    Note 'boot image'
    $saved = @{}
    $envs = @{ TECHO5 = ($Techo5 -replace '\\', '/'); KERNEL_IMAGE = ($losBoot -replace '\\', '/'); KERNEL = $kernel }
    foreach ($k in $envs.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); SetEnv $k $envs[$k] }
    try {
        & $Bash -c "cd '$(Unix $repo)' && bash tools/linux/build-image.sh -o '$(Unix $bootOut)' 2>&1" | ForEach-Object { Note $_ }
        if ($LASTEXITCODE -ne 0) { throw 'build-image.sh failed' }
    } finally { foreach ($k in $saved.Keys) { SetEnv $k $saved[$k] } }
    Note "root filesystem $Version"
    $started = Get-Date
    $wslHome = (wsl -d $WslDistro -e sh -c 'echo $HOME').Trim()
    $wslTar = "\\wsl.localhost\$WslDistro" + ($wslHome -replace '/', '\') + '\techo5-build\rootfs.tar.gz'
    # deploy-rootfs.sh builds in WSL and then ships to HOST; with no unit on the network (127.0.0.1) the
    # shipping step fails, and the tarball it leaves behind is what is installed here.
    $envs = @{
        HOST = '127.0.0.1'; BUILD_TAGS = 'spot'; VERSION = $Version
        VENDOR_TGZ = ($vendorTgz -replace '\\', '/'); DEVICE_OVERLAY = (Unix (JoinParts $repo 'tools', 'linux', 'rootfs'))
    }
    foreach ($k in $envs.Keys) { SetEnv $k $envs[$k] }
    # Its warnings go to stderr, which PowerShell would take for errors: bash merges them into stdout.
    $ErrorActionPreference = 'Continue'
    $buildLog = Join-Path $bin "install-$Serial-rootfs.log"
    try { & $Bash -c "cd '$(Unix $Techo5)' && bash tools/linux/deploy-rootfs.sh 2>&1" | Tee-Object -FilePath $buildLog | Where-Object { $_ -match '^== ' } | ForEach-Object { Note $_ } }
    finally {
        $ErrorActionPreference = 'Stop'
        foreach ($k in $envs.Keys) { SetEnv $k $null }
    }
    if (-not (Test-Path $wslTar) -or (Get-Item $wslTar).LastWriteTime -lt $started) { throw "no new root filesystem at $wslTar (log: $buildLog)" }
    Copy-Item $wslTar $rootfsOut -Force
    $logoTool = JoinParts $Techo5 'tools', 'linux', 'patch-lk-logo.py'
}
$release = (& (Get-Tar) -xzOf $rootfsOut ./etc/techo5-release) -join ''
if ($release -notmatch [regex]::Escape($Version)) { throw "the root filesystem says '$release', not $Version" }
Note $release
Note "boot image $((Get-Item $bootOut).Length) bytes"
if ($Logo) {
    Note 'bootloader picture'
    $patched = Join-Path $inputs 'expdb-techo5.img'
    & $Python $logoTool (Join-Path $backup 'expdb.img') $patched (JoinParts $repo 'logo', 'spot-boot-480.png') `
        --bundle $logoOffset --size 480x480 --in-place --colors 24
    if ($LASTEXITCODE -ne 0) { throw 'patch-lk-logo.py failed' }
    $bytes = [IO.File]::ReadAllBytes($patched)
    [IO.File]::WriteAllBytes($logoChunk, $bytes[$logoOffset..($logoOffset + $logoSlot - 1)])
}
if ($BuildOnly) {
    Note "boot image  $bootOut"
    Note "rootfs      $rootfsOut"
    if ($Logo) { Note "logo chunk  $logoChunk" }
    return
}

# --------------------------------------------------------------------------------------- 4. provision
Step 'provision'
New-Item -ItemType Directory -Force (Split-Path $KeyFile) | Out-Null
if (Test-Path $KeyFile) {
    $psk = (Get-Content $KeyFile -Raw).Trim()
    Note "using the existing key in $KeyFile"
} else {
    $rnd = [byte[]]::new(32); [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($rnd)
    $psk = [Convert]::ToBase64String($rnd)
    [IO.File]::WriteAllText($KeyFile, $psk)
    Note "new key in $KeyFile (Home Assistant asks for it)"
}
AdbSh 'mkdir -p /data/misc/techo5/models /data/misc/techo5/ssh /data/techo5-linux; chmod 700 /data/misc/techo5 /data/misc/techo5/ssh' | Out-Null
$tmp = [IO.Path]::GetTempPath()
$tmpName = Join-Path $tmp 'techo5-spot-name'; [IO.File]::WriteAllText($tmpName, $Name)
$tmpKey = Join-Path $tmp 'techo5-spot-psk'; [IO.File]::WriteAllText($tmpKey, $psk)
try {
    & $Adb -s $Serial push $tmpName /data/misc/techo5/name | Out-Null
    & $Adb -s $Serial push $tmpKey /data/misc/techo5/psk | Out-Null
} finally { Remove-Item $tmpName, $tmpKey -Force -ErrorAction SilentlyContinue }
AdbSh 'chmod 600 /data/misc/techo5/name /data/misc/techo5/psk' | Out-Null
if ($SshKey) {
    & $Adb -s $Serial push $SshKey /data/misc/techo5/ssh/authorized_keys | Out-Null
    AdbSh 'chmod 600 /data/misc/techo5/ssh/authorized_keys' | Out-Null
    Note 'SSH key in /data/misc/techo5/ssh/authorized_keys'
}
$tarName = "techo5-spot-rootfs-$Version.tar.gz"
$uploads = @(, @($rootfsOut, "/data/techo5-linux/$tarName"))
if ($Logo) { $uploads += , @($logoChunk, '/data/techo5-linux/expdb-logo-chunk.bin') }
foreach ($u in $uploads) {
    & $Adb -s $Serial push $u[0] $u[1] | Out-Null
    $got = (AdbSh "md5sum $($u[1])").Split(' ')[0]
    if ($got -ne (Md5Of $u[0])) { throw "md5 mismatch after pushing $($u[0])" }
    Note "$($u[1]) ok"
}

# ------------------------------------------------------------------------------------------- 5. flash
Step 'flash the boot image'
& $Adb -s $Serial reboot bootloader
WaitFor 'fastboot' 90 { (& $Fastboot devices) -match [regex]::Escape($Serial) }
& $Fastboot -s $Serial flash boot $bootOut
if ($LASTEXITCODE -ne 0) { throw 'fastboot flash boot failed' }
& $Fastboot -s $Serial reboot
Note 'rebooting into the rescue initramfs (no slot store yet)'
# After `adb reboot bootloader`, kaeru can stop in fastboot once more on the next boot; `continue` goes on.
$nudged = $false
WaitFor 'the rescue console' 300 {
    $o = Spot 'test -e /run/techo5/slot || echo RESCUE-UP' 4000
    if ($o -match 'RESCUE-UP') { return $true }
    if (-not $nudged -and ((& $Fastboot devices) -match [regex]::Escape($Serial))) {
        Start-Sleep -Seconds 20
        if ((& $Fastboot devices) -match [regex]::Escape($Serial)) {
            & $Fastboot -s $Serial continue | Out-Null
            $script:nudged = $true
        }
    }
    return $false
}
if ((Spot 'uname -r') -notmatch '4\.9\.337') { throw 'the unit came up on an unexpected kernel' }
Note "rescue console on $global:SpotConsolePort"

# ------------------------------------------------------------------------------------------- 6. store
Step 'slot store'
if (-not $Force) {
    Write-Host "   Next: LineageOS's system partition (mmcblk0p11) is erased and becomes the slot store." -ForegroundColor Yellow
    if ((Read-Host '   Type ERASE to go on') -ne 'ERASE') { throw 'stopped before erasing; the unit stays in rescue (fastboot flash boot the LineageOS image to go back)' }
}
$tar = "/data/techo5-linux/$tarName"
$o = Spot "touch /tmp/stay; killall techo5 fbprobe 2>/dev/null; sleep 2; umount /android 2>/dev/null; mountpoint -q /android && echo STILL-MOUNTED; slotctl mkstore /dev/mmcblk0p11 --i-know-this-erases-it >/tmp/mkstore.log 2>&1 && echo MKSTORE-OK; tail -3 /tmp/mkstore.log" 300000
if ($o -notmatch 'MKSTORE-OK') { throw "mkstore failed:`n$o" }
$o = Spot "STORE=/store slotctl install $tar >/tmp/install.log 2>&1 && echo INSTALL-OK; tail -2 /tmp/install.log; STORE=/store slotctl status" 900000
if ($o -notmatch 'INSTALL-OK') { throw "slot install failed:`n$o" }
Note ($o -split "`n" | Where-Object { $_ -match '^slot a' })
if ($Logo) {
    $wantOld = Md5Of (Join-Path $backup 'expdb.img')
    $bytes = [IO.File]::ReadAllBytes((Join-Path $backup 'expdb.img'))
    [Array]::Copy([IO.File]::ReadAllBytes($logoChunk), 0, $bytes, $logoOffset, $logoSlot)
    $md5 = [Security.Cryptography.MD5]::Create()
    $wantNew = -join ($md5.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
    $chunkMd5 = Md5Of $logoChunk
    $o = Spot ("cd /data/techo5-linux; " +
        "[ `"`$(md5sum /dev/mmcblk0p7 | cut -d' ' -f1)`" = $wantOld ] || { echo EXPDB-CHANGED; exit; }; " +
        "[ `"`$(md5sum expdb-logo-chunk.bin | cut -d' ' -f1)`" = $chunkMd5 ] || { echo CHUNK-BAD; exit; }; " +
        "dd if=expdb-logo-chunk.bin of=/dev/mmcblk0p7 bs=4096 seek=$logoOffset oflag=seek_bytes conv=notrunc,fsync 2>/dev/null; sync; " +
        "echo 3 > /proc/sys/vm/drop_caches; [ `"`$(md5sum /dev/mmcblk0p7 | cut -d' ' -f1)`" = $wantNew ] && echo LOGO-OK; rm -f expdb-logo-chunk.bin") 60000
    if ($o -match 'LOGO-OK') { Note 'bootloader picture written' }
    elseif ($o -match 'EXPDB-CHANGED') { Note 'expdb differs from its backup: bootloader picture left alone' }
    else { throw "writing the bootloader picture failed (restore $(Join-Path $backup 'expdb.img') to expdb from fastboot):`n$o" }
}
Spot 'sync; (sleep 2; /bin/busybox.static reboot -f) >/dev/null 2>&1 &' 3000 | Out-Null

# ------------------------------------------------------------------------------------------- 7. watch
Step 'first boot'
WaitFor 'slot a with the daemon running' 300 {
    $o = Spot 'echo slot=$(cat /run/techo5/slot 2>/dev/null)- daemon=$(pidof techo5)-' 4000
    return ($o -match 'slot=a- daemon=\d')
}
Note 'slot a booted, daemon running; giving it a minute'
Start-Sleep -Seconds 60
$o = Spot 'pidof techo5 >/dev/null && slotctl commit; slotctl status | head -5; ip -4 addr show wlan0 | grep -c inet; ls /sys/class/bluetooth 2>/dev/null' 15000
Note ($o -replace "`n", "`n   ")
if ($o -notmatch 'committed|already good') { throw 'the slot was not marked good: check the daemon log (/data/techo5-linux/techo5.log)' }

Write-Host ''
Write-Host "Done. '$Name' runs TECHO5 Linux $Version from slot a." -ForegroundColor Green
Write-Host "Home Assistant finds it as an ESPHome device; the key is in $KeyFile."
Write-Host "Later versions arrive through Home Assistant's update card."
