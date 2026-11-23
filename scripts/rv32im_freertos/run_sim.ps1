# ============================================================================
# VRM21 Studios - VRM21-CPU-RISC-V-Series
#
# Script      : scripts/rv32im_freertos/run_sim.ps1
# Purpose     : Run every self-checking testbench of the rv32im_freertos variant
#               in the Vivado simulator (xvlog / xelab / xsim) and report
#               PASS or FAIL per test. Exit code 0 only if all tests pass.
# Tests       : freertos_autoboot      tb_freertos_autoboot (full suite)
#               freertos_host_overlap  tb_freertos_autoboot +host_overlap
#               wfi_store, byte_enable, wfi_timer, wfi_timer_masked
#                                      tb_rv32im_regression +test=<name>
# Run         : pwsh scripts/rv32im_freertos/run_sim.ps1 [-VivadoBin <dir>] [-Test <name>,...]
#               (Windows PowerShell 7 or newer; Vivado 2025.2 was used for the
#               published results)
# Vivado path : resolved in this order: -VivadoBin, $VivadoBin in the ignored
#               file scripts/rv32im_freertos/local_paths.ps1, the environment
#               variable XILINX_VIVADO (\bin is appended), then xvlog on PATH.
# Layout      : rtl/rv32im_freertos/*.v, include/rv32im_freertos/ (header and
#               FreeRTOS firmware.mem), tb/rv32im_freertos/*.sv, and
#               tb/rv32im_freertos/mem/<test>.mem for the directed programs.
# Output      : build/rv32im_freertos/ (logs per step, summary.txt).
# Pass rule   : the run log contains ">>> TEST PASSED <<<" and no "Fatal",
#               "FATAL", "[FAIL]", "ERROR:", "watchdog", or "readmem" line.
#               The xsim exit code alone is not used, because xsim returns 0
#               after $fatal.
# ============================================================================
[CmdletBinding()]
param(
    [string]$VivadoBin = '',
    [string[]]$Test = @(),
    [int]$TimeoutSec = 1800
)
$ErrorActionPreference = 'Stop'

$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Rtl   = Join-Path $Repo 'rtl\rv32im_freertos'
$Inc   = Join-Path $Repo 'include\rv32im_freertos'
$Tb    = Join-Path $Repo 'tb\rv32im_freertos'
$Build = Join-Path $Repo 'build\rv32im_freertos'

# ---------------------------------------------------------------- tool path
if (-not $VivadoBin) {
    $local = Join-Path $PSScriptRoot 'local_paths.ps1'
    if (Test-Path -LiteralPath $local) { . $local }
}
if (-not $VivadoBin -and $env:XILINX_VIVADO) { $VivadoBin = Join-Path $env:XILINX_VIVADO 'bin' }
if (-not $VivadoBin) {
    $cmd = Get-Command xvlog -ErrorAction SilentlyContinue
    if ($cmd) { $VivadoBin = Split-Path $cmd.Source }
}
if (-not $VivadoBin -or -not (Test-Path -LiteralPath (Join-Path $VivadoBin 'xvlog.bat'))) {
    Write-Error "Vivado bin folder with xvlog.bat not found. Use -VivadoBin, local_paths.ps1, or XILINX_VIVADO."
}

# ---------------------------------------------------------------- helpers
function Invoke-Logged {
    param([string]$Log, [string]$Cwd, [string]$Exe, [string[]]$ArgList)
    # cmd.exe splits unquoted .bat arguments at '=', so such arguments are quoted.
    $quoted = ($ArgList | ForEach-Object { if ($_ -match '[\s=,;]') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $out = "$Log.out.tmp"; $err = "$Log.err.tmp"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/s', '/c', "`"`"$Exe`" $quoted`"") `
         -WorkingDirectory $Cwd -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
        $rc = 'TIMEOUT'
    } else { $p.WaitForExit(); $rc = $p.ExitCode }
    $sw.Stop()
    $body = (Get-Content -Raw -LiteralPath $out -ErrorAction SilentlyContinue) + (Get-Content -Raw -LiteralPath $err -ErrorAction SilentlyContinue)
    Remove-Item -LiteralPath $out, $err -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $Log -Value ("cwd $Cwd`ncommand $Exe $quoted`n`n$body`nelapsed_s=$([math]::Round($sw.Elapsed.TotalSeconds,1))`nexit=$rc")
    return $rc
}

function Test-RunLog([string]$Log) {
    $text = Get-Content -Raw -LiteralPath $Log
    $bad = $text -match '(?m)Fatal|FATAL|\[FAIL\]|ERROR:|watchdog|readmem'
    return ($text.Contains('>>> TEST PASSED <<<') -and -not $bad)
}

# ---------------------------------------------------------------- build
if (Test-Path -LiteralPath $Build) { Remove-Item -LiteralPath $Build -Recurse -Force }
New-Item -ItemType Directory -Force $Build | Out-Null
$logs = Join-Path $Build 'logs'
New-Item -ItemType Directory -Force $logs | Out-Null

$rtlFiles = Get-ChildItem -LiteralPath $Rtl -Filter *.v | ForEach-Object FullName
$steps = @(
    @{ n = 'xvlog_rtl';  e = 'xvlog.bat'; a = @('-i', $Inc) + $rtlFiles },
    @{ n = 'xvlog_tb';   e = 'xvlog.bat'; a = @('--sv', '-i', $Inc,
            (Join-Path $Tb 'tb_freertos_axi.sv'), (Join-Path $Tb 'tb_freertos_autoboot.sv'),
            (Join-Path $Tb 'tb_rv32im_regression.sv')) },
    @{ n = 'xelab_autoboot';   e = 'xelab.bat'; a = @('-debug', 'off', '-s', 'freertos_autoboot', 'work.tb_freertos_autoboot') },
    @{ n = 'xelab_regression'; e = 'xelab.bat'; a = @('-debug', 'off', '-s', 'rv32im_regression', 'work.tb_rv32im_regression') }
)
$results = [ordered]@{}
foreach ($s in $steps) {
    $rc = Invoke-Logged (Join-Path $logs "$($s.n).log") $Build (Join-Path $VivadoBin $s.e) $s.a
    if ($rc -ne 0) {
        Write-Host "COMPILE_FAIL at $($s.n) (see $logs\$($s.n).log)"
        Set-Content (Join-Path $Build 'summary.txt') "COMPILE_FAIL $($s.n)"
        exit 1
    }
}

# ---------------------------------------------------------------- run
$runs = [ordered]@{
    'freertos_autoboot'     = @{ snap = 'freertos_autoboot'; mem = (Join-Path $Inc 'firmware.mem'); args = @() }
    'freertos_host_overlap' = @{ snap = 'freertos_autoboot'; mem = (Join-Path $Inc 'firmware.mem'); args = @('-testplusarg', 'host_overlap') }
}
foreach ($t in 'wfi_store', 'byte_enable', 'wfi_timer', 'wfi_timer_masked') {
    $runs[$t] = @{ snap = 'rv32im_regression'; mem = (Join-Path $Tb "mem\$t.mem"); args = @('-testplusarg', "test=$t") }
}
if ($Test.Count -gt 0) {
    foreach ($k in @($runs.Keys)) { if ($Test -notcontains $k) { $runs.Remove($k) } }
}

$fail = 0
foreach ($name in $runs.Keys) {
    $r = $runs[$name]
    # The bootloader reads ./firmware.mem from the xsim run directory.
    Copy-Item -LiteralPath $r.mem (Join-Path $Build 'firmware.mem') -Force
    $log = Join-Path $logs "$name.run.log"
    $rc = Invoke-Logged $log $Build (Join-Path $VivadoBin 'xsim.bat') (@($r.snap, '-R') + $r.args)
    $status = if ($rc -eq 'TIMEOUT') { 'TIMEOUT' } elseif (Test-RunLog $log) { 'PASS' } else { 'FAIL' }
    if ($status -ne 'PASS') { $fail++ }
    $results[$name] = $status
    Write-Host ('{0,-24} {1}' -f $name, $status)
}
Remove-Item -LiteralPath (Join-Path $Build 'firmware.mem') -ErrorAction SilentlyContinue

$summary = ($results.Keys | ForEach-Object { '{0,-24} {1}' -f $_, $results[$_] }) -join "`n"
Set-Content (Join-Path $Build 'summary.txt') $summary
if ($fail -gt 0) { Write-Host "$fail test(s) did not pass"; exit 1 }
Write-Host 'All tests passed'
exit 0
