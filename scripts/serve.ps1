# Runs `rojo serve` and starts it again whenever it exits.
# Rojo 7.7 can crash when an editor or tool saves a file atomically (writes a temp file, then renames it):
# https://github.com/rojo-rbx/rojo/issues/1314. After a restart, press Connect again in the Studio plugin.
# Press Ctrl+C to stop for good.

$rojo = Join-Path $env:USERPROFILE ".rokit\bin\rojo.exe"
Set-Location (Join-Path $PSScriptRoot "..")

while ($true) {
    & $rojo serve
    Write-Host "rojo serve stopped (exit code $LASTEXITCODE). Restarting in 2 seconds; reconnect the Studio plugin afterwards." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
}
