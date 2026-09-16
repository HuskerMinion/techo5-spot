<#
.SYNOPSIS
  Run one shell command on an Echo Spot's TECHO5 USB serial console and print what it wrote.

.DESCRIPTION
  The TECHO5 Linux image (rescue initramfs and running slots alike) offers a root shell on a USB
  serial port (USB ID 1d6b:0104, "TECHO5"). Other TECHO5 devices on the same PC show up with the same
  ID, so the port is chosen by the unit's serial number (androidboot.serialno in /proc/cmdline), and
  the command only runs where that matches.

  Output is everything the shell printed before an end marker, without the echoed command. Returns
  nothing when no port answers for that serial.

.EXAMPLE
  .\tools\serial-console.ps1 -Serial <serial> -Cmd 'slotctl status'
#>
param(
    [Parameter(Mandatory)][string]$Serial,
    [string]$Cmd = 'true',
    [int]$WaitMs = 5000,
    # A port to try first (the last one that answered), before looking at the others.
    [string]$Port
)
$ErrorActionPreference = 'Stop'

function Invoke-Console([string]$name, [string]$line, [int]$wait) {
    $sp = New-Object IO.Ports.SerialPort $name, 115200
    $sp.NewLine = "`n"; $sp.ReadTimeout = 500
    $sp.Open()
    try {
        $sp.Write("`n"); Start-Sleep -Milliseconds 400; $null = $sp.ReadExisting()
        $marker = "__T5END$(Get-Random)__"
        # The marker is printed from a variable, so the echoed command line never matches it.
        $sp.Write("$line; m=$marker; echo `$m`n")
        $buf = ''; $deadline = (Get-Date).AddMilliseconds($wait)
        while ((Get-Date) -lt $deadline) {
            $buf += $sp.ReadExisting()
            if ($buf -match "(?m)^$marker") { break }
            Start-Sleep -Milliseconds 150
        }
        $buf = $buf -replace "`r", ''
        $out = @(); $started = $false
        foreach ($l in ($buf -split "`n")) {
            if ($l -match "^$marker") { break }
            if ($started) { $out += $l }
            elseif ($l -match [regex]::Escape("m=$marker")) { $started = $true }
        }
        return ($out -join "`n")
    } finally { $sp.Close() }
}

$ports = @(Get-CimInstance Win32_PnPEntity | Where-Object {
        $_.PNPDeviceID -match 'VID_1D6B&PID_0104&MI_00' -and $_.Name -match '\((COM\d+)\)'
    } | ForEach-Object { [regex]::Match($_.Name, 'COM\d+').Value })
if ($Port -and ($ports -contains $Port)) { $ports = @($Port) + @($ports | Where-Object { $_ -ne $Port }) }
# Never `exit` on a mismatch: that would end the port's login shell.
$pathLine = 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
foreach ($p in $ports) {
    try {
        $who = Invoke-Console $p "grep -q androidboot.serialno=$Serial /proc/cmdline && echo IS-THE-UNIT" 3000
    } catch { continue }
    if ($who -notmatch 'IS-THE-UNIT') { continue }
    $global:SpotConsolePort = $p
    return (Invoke-Console $p "if grep -q androidboot.serialno=$Serial /proc/cmdline; then $pathLine; ( $Cmd ); fi" $WaitMs)
}
