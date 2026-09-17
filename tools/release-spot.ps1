<#
.SYNOPSIS
  Publish a TECHO5 Spot release: the signed manifest an Echo Spot's updater reads, the Spot daemon, and
  the root filesystem it installs into its spare slot.

.DESCRIPTION
  The Spot's daemon follows this repository's releases (TECHO5 echod internal/update/releases_spot.go),
  apart from the Show's and the Dot's, so a Spot release never becomes another device's latest.

  The root filesystem is built first with TECHO5's deploy-rootfs.sh on the spot/daemon branch
  (BUILD_TAGS=spot, this repository's tools/linux/rootfs overlay and the Spot's vendor tarball; see
  docs/porting-plan.md), ideally installed on a unit and seen to commit. This script publishes that
  tarball as it is, and the daemon inside it, so the two cannot differ:
    echod-arm-spot             the daemon, taken out of the root filesystem
    techo5-spot-rootfs.tar.gz  the whole root filesystem for a slot
    manifest.json              versions, URLs, sizes and sha256 of both (TECHO5 cmd/mkmanifest)
    manifest.json.sig          the release key's ed25519 signature over manifest.json

  Nothing unit-specific is in any of them: no vendor firmware beyond what the root filesystem carries for
  every Spot, no keys, Wi-Fi or Home Assistant identity, and no boot image.

.EXAMPLE
  .\tools\release-spot.ps1 -Version v0.1.0 -Rootfs bin\release\v0.1.0\techo5-spot-rootfs.tar.gz -Notes "..." -DryRun
#>
param(
    [Parameter(Mandatory)][ValidatePattern('^v\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$')][string]$Version,
    [Parameter(Mandatory)][string]$Notes,
    [Parameter(Mandatory)][string]$Rootfs,
    [string]$Techo5 = 'E:\projects\techo5-wt-spot',
    [string]$SignKey = 'D:\platform-tools\keys\techo5-release.key',
    [string]$Go = 'go',
    [switch]$Prerelease,
    # Sign everything into bin\release\<version>, publish nothing.
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$repo = 'HuskerMinion/techo5-spot'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$out = Join-Path $root "bin\release\$Version"
New-Item -ItemType Directory -Force $out | Out-Null
if (-not (Test-Path $SignKey)) { throw "no release signing key at $SignKey" }
if (-not (Test-Path $Rootfs)) { throw "no root filesystem at $Rootfs" }

$branch = (git -C $Techo5 branch --show-current).Trim()
if ($branch -ne 'spot/daemon') { throw "$Techo5 is on '$branch', not spot/daemon" }

Write-Host "== root filesystem"
$tarball = Join-Path $out 'techo5-spot-rootfs.tar.gz'
if ((Resolve-Path $Rootfs).Path -ne (Resolve-Path -ErrorAction SilentlyContinue $tarball).Path) {
    Copy-Item $Rootfs $tarball -Force
}
# The release it was built as, and the daemon in it: both must be this version.
$release = (& tar -xzOf $tarball ./etc/techo5-release) -join ''
if ($release -notmatch "rootfs $([regex]::Escape($Version)) .*daemon echod version $([regex]::Escape($Version)) ") {
    throw "the root filesystem says '$release', not $Version"
}
Write-Host $release
$daemon = Join-Path $out 'echod-arm-spot'
Push-Location $out
try {
    & tar -xzf $tarball ./usr/local/bin/techo5
    if ($LASTEXITCODE -ne 0) { throw 'no daemon at /usr/local/bin/techo5 in the root filesystem' }
    Move-Item -Force (Join-Path $out 'usr\local\bin\techo5') $daemon
    Remove-Item -Recurse -Force (Join-Path $out 'usr')
} finally { Pop-Location }

Write-Host "== signed manifest"
Push-Location (Join-Path $Techo5 'echod')
$from = "https://github.com/$repo/releases/download/$Version"
& $Go run ./cmd/mkmanifest -version $Version -title "TECHO5 Spot $Version" -notes $Notes `
    -release-url "https://github.com/$repo/releases/tag/$Version" -from $from `
    -arm-spot $daemon -rootfs-arm-spot $tarball `
    -out (Join-Path $out 'manifest.json') -sign-key $SignKey
if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'mkmanifest failed' }
Pop-Location
Get-Content (Join-Path $out 'manifest.json')

$assets = @('echod-arm-spot', 'techo5-spot-rootfs.tar.gz', 'manifest.json', 'manifest.json.sig') | ForEach-Object { Join-Path $out $_ }
if ($DryRun) {
    Write-Host "Dry run: release files are in $out; nothing published."
    return
}
Write-Host "== release $Version on $repo"
$ghArgs = @('release', 'create', $Version) + $assets + @('--repo', $repo, '--title', "TECHO5 Spot $Version", '--notes', $Notes)
if ($Prerelease) { $ghArgs += '--prerelease' }
& gh @ghArgs
if ($LASTEXITCODE -ne 0) { throw 'gh release create failed' }
Write-Host "published: https://github.com/$repo/releases/tag/$Version"
