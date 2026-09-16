<#
.SYNOPSIS
  Back up every partition that boots an Echo Spot (rook) to the PC, each copy checked against an md5
  read on the device. Writes nothing to the unit.

.DESCRIPTION
  Porting plan M0, step 4. Run it with the unit in TWRP (where amonet-rook leaves it) or in Fire OS or
  LineageOS with adb as root.

  What it copies:
    - the GPT (the first 34 sectors of the eMMC), for amonet's gpt-fix and for comparing layouts
    - the preloader (eMMC boot area, mmcblk0boot0)
    - the bootloader, TEE, factory and boot partitions: lk, tee1, tee2, expdb, MISC, para, kb, dkb,
      nvram, proinfo, seccfg, persistbackup, frp, persist, metadata, boot, recovery
    - with -IncludeSystem, also system and cache (large; userdata is never copied)

  The partition list comes from TWRP's recovery.fstab and is not confirmed on a unit yet: a name the
  unit does not have is reported and skipped, not treated as an error.

  An existing backup is never overwritten. If a partition has changed since its backup (MISC does on
  every boot), the new copy is saved beside the old one with a timestamp. Every copy is written to a
  .partial file first and kept only when its md5 matches the device.

.EXAMPLE
  .\tools\backup-spot.ps1 -Serial G0B0XXXXXXXXXXXX
  .\tools\backup-spot.ps1 -Serial G0B0XXXXXXXXXXXX -IncludeSystem
#>
param(
    [Parameter(Mandatory)][string]$Serial,
    [string]$Adb = 'adb',
    [string]$BackupRoot = 'D:\platform-tools\echospot',
    [switch]$IncludeSystem
)
$ErrorActionPreference = 'Stop'

function Step([string]$what) { Write-Host "== $what" }
function Note([string]$what) { Write-Host "   $what" }
function Sh([string]$cmd) { (& $Adb -s $Serial shell $cmd) -join "`n" }
function Md5File([string]$path) { (Get-FileHash -Algorithm MD5 $path).Hash.ToLower() }

# ---------------------------------------------------------------------------------------------- device
Step "device $Serial"
$state = (& $Adb -s $Serial get-state 2>$null)
if ($state -ne 'device' -and $state -ne 'recovery') {
    throw "adb does not see $Serial (state: '$state'). Boot it into TWRP, or Fire OS/LineageOS with root adb, with USB connected."
}
$product = (Sh 'getprop ro.product.device; getprop ro.build.product').Trim()
if ($product -notmatch 'rook') { throw "$Serial reports '$product', not rook" }
$id = (Sh 'id').Trim()
if ($id -notmatch '^uid=0') { throw "adb is not root on $Serial ($id). Use TWRP, or enable rooted debugging." }

# By-name links: TWRP names bootdevice or mtk-msdc.0, Fire OS names soc.
$BN = (Sh 'for d in /dev/block/platform/bootdevice/by-name /dev/block/platform/mtk-msdc.0/by-name /dev/block/platform/soc/by-name /dev/block/by-name; do [ -e $d/boot ] && { echo $d; break; }; done').Trim()
if (-not $BN) { throw "no by-name partition links with a boot partition on $Serial" }
Note "rook in $state, partitions under $BN"

$unit = Join-Path $BackupRoot $Serial
New-Item -ItemType Directory -Force $unit | Out-Null
Step "backups to $unit"

# The unit's own view of its partitions, kept with the images.
Sh "cat /proc/partitions; echo; ls -l $BN" | Set-Content -Encoding ascii (Join-Path $unit 'partitions.txt')

# ---------------------------------------------------------------------------------------------- copy
function Backup([string]$name, [string]$src, [string]$readCmd) {
    $out = Join-Path $unit "$name.img"
    # dd reports its record counts on stderr, and adb shell folds stderr into the output.
    $dev = ((Sh "$readCmd 2>/dev/null | md5sum").Trim() -split "`n")[-1].Split(' ')[0].Trim()
    if ($dev -notmatch '^[0-9a-f]{32}$') { throw "could not read $name ($src) on $Serial" }
    if ((Test-Path $out) -and (Md5File $out) -eq $dev) { Note "$name already backed up"; return }
    $same = Get-ChildItem (Join-Path $unit "$name-*.img") -ErrorAction SilentlyContinue |
        Where-Object { (Md5File $_.FullName) -eq $dev } | Select-Object -First 1
    if ($same) { Note "$name already backed up as $($same.Name)"; return }
    $dest = $out
    if (Test-Path $out) { $dest = Join-Path $unit ("$name-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.img') }
    # exec-out, not shell: no tty translation. The command prints nothing but the data, so stderr is
    # sent to /dev/null on the device rather than into the image.
    $tmp = "$dest.partial"
    $proc = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'exec-out', "$readCmd 2>/dev/null") `
        -RedirectStandardOutput $tmp -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) { Remove-Item -Force $tmp -ErrorAction SilentlyContinue; throw "reading $name failed" }
    $got = Md5File $tmp
    if ($got -ne $dev) { Remove-Item -Force $tmp; throw "$name copy does not match the device ($got vs $dev)" }
    Move-Item -Force $tmp $dest
    Note "$name $((Get-Item $dest).Length) bytes, md5 ok$(if ($dest -ne $out) { " (changed since $name.img; saved as $(Split-Path -Leaf $dest))" })"
}

Backup 'gpt' '/dev/block/mmcblk0' 'dd if=/dev/block/mmcblk0 bs=512 count=34'

if ((Sh 'test -e /dev/block/mmcblk0boot0 && echo yes').Trim() -eq 'yes') {
    Backup 'preloader' '/dev/block/mmcblk0boot0' 'cat /dev/block/mmcblk0boot0'
} else {
    Note "no /dev/block/mmcblk0boot0 on this kernel; preloader not copied"
}

$parts = 'lk', 'tee1', 'tee2', 'expdb', 'MISC', 'para', 'kb', 'dkb', 'nvram', 'proinfo', 'seccfg',
         'persistbackup', 'frp', 'persist', 'metadata', 'boot', 'recovery'
if ($IncludeSystem) { $parts += 'system', 'cache' }

foreach ($p in $parts) {
    # amonet's TWRP on other Echos points bootloader partitions at decoy files so an OTA zip cannot
    # overwrite the unlock; the real partition is then the *_real link. A copy of a decoy restores nothing.
    $src = (Sh "s=$BN/$p; [ -e `$s ] || { echo missing; exit; }; [ -e `${s}_real ] && s=`${s}_real; case `$(readlink -f `$s) in /tmp/*) echo decoy;; *) echo `$s;; esac").Trim()
    if ($src -eq 'missing') { Note "${p}: not on this unit, skipped"; continue }
    if ($src -eq 'decoy') { throw "$p on $Serial points at a decoy with no real partition beside it" }
    Backup $p $src "cat $src"
}

Step "done"
Note "keep $unit off the device; boot.img and recovery.img are the way back (porting plan M0, step 5)"
