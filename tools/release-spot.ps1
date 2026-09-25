<#
.SYNOPSIS
  Publish a TECHO5 Spot release: the signed manifest an Echo Spot's updater reads, the Spot daemon, the
  root filesystem it installs into its spare slot, and what the installer builds a boot image from.

.DESCRIPTION
  The Spot's daemon follows this repository's releases (TECHO5 echod internal/update/releases_spot.go),
  apart from the Show's and the Dot's, so a Spot release never becomes another device's latest.

  The root filesystem is built first with TECHO5's deploy-rootfs.sh on main (BUILD_TAGS=spot and this
  repository's tools/linux/rootfs overlay, with no vendor tree; see docs/building.md), ideally
  installed on a unit and seen to commit. This script publishes that tarball as it is, and the daemon
  inside it, so the two cannot differ:
    echod-arm-spot                        the daemon, taken out of the root filesystem
    techo5-spot-rootfs.tar.gz             the whole root filesystem for a slot
    manifest.json, manifest.json.sig      versions, URLs, sizes and sha256 of all of these
                                          (TECHO5 cmd/mkmanifest), signed with the release key
    techo5-spot-kernel-bt.Image.gz-dtb    the LineageOS rook kernel rebuilt with Bluetooth (GPL-2.0)
    techo5-spot-rescue.tar                the rescue initramfs's packages, busybox, tools and image scripts
    SHA256SUMS                            the same checksums, unsigned, for checking by hand

  No boot image is published: each unit's is built by tools/install-spot.py from its own LineageOS boot image.
  Nothing unit-specific is in any of them: no keys, Wi-Fi or Home Assistant identity, and no LineageOS
  vendor tree (drivers, firmware): each Spot keeps its own, and a tarball carrying one is refused.

.EXAMPLE
  ./tools/release-spot.ps1 -Version v0.3.0 -Rootfs build/rootfs.tar.gz -Notes "..." -DryRun
#>
param(
    [Parameter(Mandatory)][ValidatePattern('^v\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$')][string]$Version,
    [string]$Notes,
    [string]$Rootfs,
    # A TECHO5 checkout on main: $env:TECHO5, else ../techo5 beside this repository.
    [string]$Techo5 = $(if ($env:TECHO5) { $env:TECHO5 } else { Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'techo5' }),
    # The release signing key (ed25519 seed, base64); only the maintainer has it: $env:TECHO5_SIGN_KEY.
    [string]$SignKey = $env:TECHO5_SIGN_KEY,
    # The Bluetooth kernel (tools/linux/build-kernel.sh).
    [string]$Kernel = $(Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'inputs') 'Image.gz-dtb-rook-bt'),
    # The build inputs (docs/building.md): $env:TECHO5_INPUTS, else inputs/ in this repository.
    [string]$Inputs = $(if ($env:TECHO5_INPUTS) { $env:TECHO5_INPUTS } else { Join-Path (Join-Path $PSScriptRoot '..') 'inputs' }),
    [string]$Go = 'go',
    [switch]$Prerelease,
    # Attaching the kernel and rescue bundle to a release published before them: no longer possible,
    # kept so anyone who reaches for it is told why rather than left guessing.
    [switch]$AddTo,
    # Sign everything into bin/release/<version>, publish nothing.
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
# -AddTo used to upload the kernel and the rescue bundle to a release that went out before they
# existed. It cannot work now: install-spot.py takes those two files only when the release's signed
# manifest names them, and the manifest of a published release was signed without them. Re-signing one
# would mean replacing a file people have already downloaded and verified, which this script will not
# do. Publish a new version instead.
if ($AddTo) {
    throw "-AddTo is gone: the kernel and the rescue bundle are named in the signed manifest now, and a release already published was signed without them. Publish a new version."
}
# The tag says which device a release is for; the version says which build it is. They are not the same
# string and must not be swapped: the tag names the release, while $Version is what the daemon is
# stamped with and the only thing that belongs in the manifest. A manifest naming the tag differs
# forever from what a Spot reports as running, and Home Assistant offers an update whenever the two
# differ - which is how spot-v0.4.9 and spot-v0.4.10 shipped with a card nobody could clear.
$tag = "spot-$Version"
$Script:SpotKernelAsset = 'techo5-spot-kernel-bt.Image.gz-dtb'
$Script:SpotRescueAsset = 'techo5-spot-rescue.tar'
function Sha256File([string]$path) { (Get-FileHash -Algorithm SHA256 $path).Hash.ToLower() }
function JoinParts([string]$base, [string[]]$parts) { $p = $base; foreach ($x in $parts) { $p = Join-Path $p $x }; $p }
# tar: on Windows its own (bsdtar); a GNU tar from Git earlier on the PATH reads C:\... as a remote host.
function Get-Tar {
    if (-not $IsLinux -and -not $IsMacOS -and $env:SystemRoot) {
        $own = Join-Path (Join-Path $env:SystemRoot 'System32') 'tar.exe'
        if (Test-Path $own) { return $own }
    }
    'tar'
}
$repo = 'HuskerMinion/techo5-spot'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$out = JoinParts $root 'bin', 'release', $Version
New-Item -ItemType Directory -Force $out | Out-Null
$tar = Get-Tar
if (-not (Test-Path $Kernel)) { throw "no Bluetooth kernel at ${Kernel}: build it (tools/linux/build-kernel.sh) or pass -Kernel" }
if (-not (Test-Path (JoinParts $Techo5 'tools', 'linux', 'slotctl'))) { throw "no TECHO5 checkout at ${Techo5}: set TECHO5 or pass -Techo5" }

# Built before the manifest, because the manifest names them: install-spot.py unpacks the rescue
# bundle and runs scripts out of it on the maintainer's own machine, and flashes the kernel to a unit,
# so both have to be measured into the file the release key signs.
Write-Host "== Bluetooth kernel and rescue bundle"
Copy-Item -Force $Kernel (Join-Path $out $Script:SpotKernelAsset)
$stage = Join-Path $out 'rescue-stage'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
foreach ($d in 'apks', 'bin', 'scripts', 'host') { New-Item -ItemType Directory -Force (Join-Path $stage $d) | Out-Null }
# The packages TECHO5's rescue initramfs lists, from the same places tools/linux/build-image.sh takes them.
foreach ($line in Get-Content (JoinParts $Techo5 'tools', 'linux', 'packages.txt')) {
    $a = ($line -replace '#.*', '').Trim()
    if (-not $a -or $a -like 'busybox-static-*') { continue }
    $dir = if ($a -match '^(wpa_supplicant-2\.9|libssl1\.1|libcrypto1\.1|libnl3-3\.5)') { 'apks312' } else { 'apks' }
    Copy-Item (JoinParts $Inputs $dir, $a) (Join-Path $stage 'apks')
}
# mkfs.ext4 (slotctl mkstore) needs libgcc_s through libeconf, which TECHO5's package list does not carry.
Copy-Item (Get-ChildItem (JoinParts $Inputs 'apks', 'libgcc-*.apk') | Select-Object -First 1).FullName (Join-Path $stage 'apks')
Copy-Item (Join-Path $Inputs 'busybox.static') $stage
$env:GOOS = 'linux'; $env:GOARCH = 'arm'; $env:GOARM = '7'; $env:CGO_ENABLED = '0'
try {
    foreach ($c in 'fbprobe', 'audioprobe', 'rebootto') {
        # audioprobe lives in the daemon's module, beside the ALSA code it shares.
        $module = if (Test-Path (JoinParts $Techo5 'echod', 'cmd', $c)) { Join-Path $Techo5 'echod' } else { $Techo5 }
        Push-Location $module
        & $Go build -trimpath -ldflags '-s -w' -o (JoinParts $stage 'bin', $c) "./cmd/$c"
        $ok = $LASTEXITCODE -eq 0
        Pop-Location
        if (-not $ok) { throw "building $c failed" }
    }
} finally { Remove-Item Env:GOOS, Env:GOARCH, Env:GOARM, Env:CGO_ENABLED -ErrorAction SilentlyContinue }
Copy-Item (JoinParts $Techo5 'tools', 'linux', 'slotctl'), (JoinParts $Techo5 'tools', 'linux', 'techo5-lib.sh') (Join-Path $stage 'scripts')
Copy-Item (JoinParts $Techo5 'tools', 'linux', 'mkimage.py'), (JoinParts $Techo5 'tools', 'linux', 'patch-lk-logo.py') (Join-Path $stage 'host')
# Shell scripts reach the unit with LF endings whatever the checkout did.
foreach ($s in Get-ChildItem (Join-Path $stage 'scripts')) {
    [IO.File]::WriteAllText($s.FullName, ([IO.File]::ReadAllText($s.FullName) -replace "`r`n", "`n"))
}
Push-Location $stage
& $tar -cf (Join-Path $out $Script:SpotRescueAsset) apks bin scripts host busybox.static
$ok = $LASTEXITCODE -eq 0
Pop-Location
if (-not $ok) { throw 'packing the rescue bundle failed' }
Remove-Item -Recurse -Force $stage

if (-not $Notes) { throw '-Notes is needed for a new release' }
if (-not $Rootfs -or -not (Test-Path $Rootfs)) { throw "no root filesystem at '$Rootfs'" }
if (-not $SignKey -or -not (Test-Path $SignKey)) { throw "no release signing key: set TECHO5_SIGN_KEY or pass -SignKey" }
$branch = (git -C $Techo5 branch --show-current).Trim()
if ($branch -notin 'main', 'spot/daemon') { throw "$Techo5 is on '$branch', not main" }

Write-Host "== root filesystem"
$tarball = Join-Path $out 'techo5-spot-rootfs.tar.gz'
if ((Resolve-Path $Rootfs).Path -ne (Resolve-Path -ErrorAction SilentlyContinue $tarball).Path) {
    Copy-Item $Rootfs $tarball -Force
}
# The release it was built as, and the daemon in it: both must be this version.
$release = (& $tar -xzOf $tarball ./etc/techo5-release) -join ''
if ($release -notmatch "rootfs $([regex]::Escape($Version)) .*daemon echod version $([regex]::Escape($Version)) ") {
    throw "the root filesystem says '$release', not $Version"
}
Write-Host $release
# LineageOS's vendor tree is Amazon's and Broadcom's, not ours to publish: each Spot mounts its own.
if (& $tar -tzf $tarball | Where-Object { $_ -match '^(\./)?vendor/.' } | Select-Object -First 1) { throw "$tarball carries a vendor tree; build it without VENDOR_TGZ" }
$daemon = Join-Path $out 'echod-arm-spot'
Push-Location $out
try {
    & $tar -xzf $tarball ./usr/local/bin/techo5
    if ($LASTEXITCODE -ne 0) { throw 'no daemon at /usr/local/bin/techo5 in the root filesystem' }
    Move-Item -Force (JoinParts $out 'usr', 'local', 'bin', 'techo5') $daemon
    Remove-Item -Recurse -Force (Join-Path $out 'usr')
} finally { Pop-Location }

Write-Host "== signed manifest"
Push-Location (Join-Path $Techo5 'echod')
$from = "https://github.com/$repo/releases/download/$tag"
& $Go run ./cmd/mkmanifest -version $Version -title "TECHO5 Spot $Version" -notes $Notes `
    -release-url "https://github.com/$repo/releases/tag/$tag" -from $from `
    -arm-spot $daemon -rootfs-arm-spot $tarball `
    -asset (Join-Path $out $Script:SpotKernelAsset) -asset (Join-Path $out $Script:SpotRescueAsset) `
    -out (Join-Path $out 'manifest.json') -sign-key $SignKey
if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'mkmanifest failed' }
Pop-Location
Get-Content (Join-Path $out 'manifest.json')
foreach ($f in 'echod-arm-spot', 'techo5-spot-rootfs.tar.gz', 'manifest.json', 'manifest.json.sig') {
    if (-not (Test-Path (Join-Path $out $f))) { throw "no $f in $out" }
}

$names = 'echod-arm-spot', 'techo5-spot-rootfs.tar.gz', 'manifest.json', 'manifest.json.sig', $Script:SpotKernelAsset, $Script:SpotRescueAsset
# SHA256SUMS: for checking a download by hand. The installer reads the signed manifest instead, which
# names the kernel and the rescue bundle too; nothing signs this file, so it says nothing about who
# served the files it describes.
$sums = $names | ForEach-Object { "$(Sha256File (Join-Path $out $_))  $_" }
[IO.File]::WriteAllText((Join-Path $out 'SHA256SUMS'), ($sums -join "`n") + "`n")
Get-Content (Join-Path $out 'SHA256SUMS')

$gplNote = "The Bluetooth kernel ($Script:SpotKernelAsset, Linux 4.9, GPL-2.0) is built by tools/linux/build-kernel.sh from the LineageOS rook kernel source (amazon-oss) with the configuration in tools/linux. The rescue bundle carries Alpine Linux packages (their sources: https://gitlab.alpinelinux.org/alpine/aports) and TECHO5's own tools."
if ($DryRun) {
    Write-Host "Dry run: release files are in $out; nothing published."
    return
}
Write-Host "== release $tag on $repo"
$assets = ($names + 'SHA256SUMS') | ForEach-Object { Join-Path $out $_ }
$ghArgs = @('release', 'create', $tag) + $assets + @('--repo', $repo, '--title', "TECHO5 Spot $Version", '--notes', ($Notes + "`n`n" + $gplNote))
# A version with a suffix (-rc.1, -beta) is a prerelease whether or not -Prerelease was given: GitHub
# otherwise makes it /releases/latest, which is what the installers and every unit's updater follow.
if ($Prerelease -or $Version -match '-') { $ghArgs += '--prerelease' }
& gh @ghArgs
if ($LASTEXITCODE -ne 0) { throw 'gh release create failed' }
# The dev channel follows every release, stable ones too, so it never offers something older than a
# unit already runs: Install then refuses it and the card never clears (techo5 issue #42). Its
# manifest names this release's own files, so only the manifest and its signature move.
& gh release upload dev (Join-Path $out 'manifest.json') (Join-Path $out 'manifest.json.sig') --repo $repo --clobber
if ($LASTEXITCODE -ne 0) { throw "published, but the dev channel was not updated: upload manifest.json and manifest.json.sig to the dev release by hand" }
Write-Host "published: https://github.com/$repo/releases/tag/$tag"
