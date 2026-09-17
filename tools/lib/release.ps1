# Shared by install-spot-linux.ps1 and release-spot.ps1: the signed release and the boot image built from it.
# Dot-sourced; the caller has set $ErrorActionPreference = 'Stop'.

$Script:SpotRepo = (Resolve-Path (Join-Path $PSScriptRoot (Join-Path '..' '..'))).Path
$Script:SpotReleases = 'https://github.com/HuskerMinion/techo5-spot/releases'

# Alpine's base image, pinned: the boot image's initramfs is built on it.
$Script:AlpineUrl = 'https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/armv7/alpine-minirootfs-3.24.1-armv7.tar.gz'
$Script:AlpineSha256 = '50942d567e6ee422c16cb46d5c282ed9d8adc9007c2a483faf4148a18c64ce32'

# The release's extra files, next to the manifest's daemon and root filesystem.
$Script:SpotKernelAsset = 'techo5-spot-kernel-bt.Image.gz-dtb'
$Script:SpotRescueAsset = 'techo5-spot-rescue.tar'

function Sha256File([string]$path) { (Get-FileHash -Algorithm SHA256 $path).Hash.ToLower() }

# A path built with the platform's own separator.
function JoinParts([string]$base, [string[]]$parts) { $p = $base; foreach ($x in $parts) { $p = Join-Path $p $x }; $p }
function RepoPath([string[]]$parts) { JoinParts $Script:SpotRepo $parts }

# tar: on Windows, its own (bsdtar). A GNU tar from Git or MSYS earlier on the PATH reads C:\... as a
# remote host.
function Get-Tar {
    if (-not $IsLinux -and -not $IsMacOS -and $env:SystemRoot) {
        $own = Join-Path (Join-Path $env:SystemRoot 'System32') 'tar.exe'
        if (Test-Path $own) { return $own }
    }
    'tar'
}

# The Python to run the image tools with.
function Get-Python { if ($IsLinux -or $IsMacOS) { 'python3' } else { 'python' } }

# A download kept only once its sha256 is the one expected; one already there and right is not fetched again.
function Get-Checked([string]$url, [string]$out, [string]$sha256) {
    if ((Test-Path $out) -and (Sha256File $out) -eq $sha256) { return }
    $partial = "$out.partial"
    Invoke-WebRequest -Uri $url -OutFile $partial -UseBasicParsing
    $got = Sha256File $partial
    if ($got -ne $sha256) { Remove-Item -Force $partial; throw "$url does not match its checksum ($got, wanted $sha256)" }
    Move-Item -Force $partial $out
}

# The release's files, downloaded into $WorkDir and checked: the signed manifest names the root filesystem
# and its checksum, and SHA256SUMS covers the Bluetooth kernel and the rescue bundle. Returns where each is.
function Get-SpotRelease([string]$WorkDir, [string]$Release = 'latest') {
    $tar = Get-Tar
    $dl = if ($Release -eq 'latest') { "$Script:SpotReleases/latest/download" } else { "$Script:SpotReleases/download/$Release" }
    $manifest = Invoke-RestMethod -Uri "$dl/manifest.json" -UseBasicParsing
    $rel = Join-Path $WorkDir "release-$($manifest.version)"
    New-Item -ItemType Directory -Force $rel | Out-Null

    $sums = @{}
    $text = (Invoke-WebRequest -Uri "$dl/SHA256SUMS" -UseBasicParsing).Content
    if ($text -is [byte[]]) { $text = [Text.Encoding]::ASCII.GetString($text) }
    foreach ($line in ($text -split "`n")) {
        if ($line -match '^([0-9a-f]{64})\s+\*?(\S+)') { $sums[$Matches[2]] = $Matches[1] }
    }
    foreach ($want in $Script:SpotKernelAsset, $Script:SpotRescueAsset) {
        if (-not $sums[$want]) { throw "release $($manifest.version) has no $want in SHA256SUMS; pick another with -Release" }
    }

    $rootfs = Join-Path $rel 'techo5-spot-rootfs.tar.gz'
    Get-Checked $manifest.rootfs.'arm-spot'.url $rootfs $manifest.rootfs.'arm-spot'.sha256

    $kernel = Join-Path $rel $Script:SpotKernelAsset
    Get-Checked "$dl/$Script:SpotKernelAsset" $kernel $sums[$Script:SpotKernelAsset]

    $rescueTar = Join-Path $rel $Script:SpotRescueAsset
    Get-Checked "$dl/$Script:SpotRescueAsset" $rescueTar $sums[$Script:SpotRescueAsset]
    $rescue = Join-Path $rel 'rescue'
    if (Test-Path $rescue) { Remove-Item -Recurse -Force $rescue }
    New-Item -ItemType Directory -Force $rescue | Out-Null
    & $tar -xf $rescueTar -C $rescue
    if ($LASTEXITCODE -ne 0) { throw "unpacking the rescue bundle failed" }

    $alpine = Join-Path $WorkDir 'alpine-minirootfs-3.24.1-armv7.tar.gz'
    Get-Checked $Script:AlpineUrl $alpine $Script:AlpineSha256

    [pscustomobject]@{
        Version = $manifest.version
        Rootfs  = $rootfs
        Kernel  = $kernel
        Rescue  = $rescue
        Alpine  = $alpine
    }
}

# The rescue bundle's layout, which New-SpotBootImage reads and release-spot.ps1 writes:
#   apks/*.apk                 the initramfs packages (TECHO5's packages.txt for the Spot, plus libgcc)
#   busybox.static
#   bin/fbprobe bin/audioprobe bin/rebootto        armv7, from TECHO5's cmd/
#   scripts/slotctl scripts/techo5-lib.sh           from TECHO5's tools/linux
#   host/mkimage.py host/patch-lk-logo.py          run on this computer
#
# A unit's boot image: its own LineageOS boot image's header (and kernel, when $Kernel is empty) and the
# rescue initramfs on Alpine's base.
function New-SpotBootImage {
    param(
        [Parameter(Mandatory)][string]$LineageBoot,
        [Parameter(Mandatory)][string]$Rescue,
        [Parameter(Mandatory)][string]$Alpine,
        [Parameter(Mandatory)][string]$Out,
        [string]$Kernel,
        [string]$Python = (Get-Python)
    )
    $mk = @((JoinParts $Rescue 'host', 'mkimage.py'), '--kernel-image', $LineageBoot, '--rootfs', $Alpine,
        '--init', (RepoPath 'tools', 'linux', 'init'),
        '--add', "$(Join-Path $Rescue 'busybox.static')=/bin/busybox.static")
    if ($Kernel) { $mk += @('--kernel', $Kernel) }
    foreach ($t in 'fbprobe', 'audioprobe', 'rebootto') { $mk += @('--add', "$(JoinParts $Rescue 'bin', $t)=/usr/local/bin/$t") }
    $mk += @('--script', "$(JoinParts $Rescue 'scripts', 'slotctl')=/usr/local/sbin/slotctl")
    $mk += @('--script', "$(JoinParts $Rescue 'scripts', 'techo5-lib.sh')=/lib/techo5-lib.sh")
    Get-ChildItem (JoinParts $Rescue 'apks', '*.apk') | Sort-Object Name | ForEach-Object { $mk += @('--apk', $_.FullName) }
    $mk += @('--compress', 'xz', '--cmdline-append', 'techo5=linux', '-o', $Out)
    & $Python @mk
    if ($LASTEXITCODE -ne 0) { throw "building the boot image failed" }
}
