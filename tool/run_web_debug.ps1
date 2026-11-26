# One-command launcher for debugging the Bilibili QR login in Chrome.
#
# It starts the local dev proxy (bypasses CORS + supplies Referer/Cookie that
# browsers refuse to set) and then runs `flutter run -d chrome` with
# DEV_PROXY_BASE injected, so every *.bilibili.com request goes through 127.0.0.1.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tool\run_web_debug.ps1
#   powershell -ExecutionPolicy Bypass -File tool\run_web_debug.ps1 -WebPort 8080 -ProxyPort 8899
#   powershell -ExecutionPolicy Bypass -File tool\run_web_debug.ps1 -NoProxyWindow   # proxy hidden
#   powershell -ExecutionPolicy Bypass -File tool\run_web_debug.ps1 -NoProxy         # direct requests (CORS will fail)
#
# Stop: close the proxy window, or run  Get-Process dart | Stop-Process  (careful).

param(
    [int]$ProxyPort = 9090,
    [int]$WebPort = 7070,
    [string]$Device = 'chrome',
    [switch]$NoProxyWindow,
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'
$env:Path = "C:\flutter\bin;" + $env:Path

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot
Write-Host "Project: $projectRoot"

$dartExe = (Get-Command dart.exe -ErrorAction SilentlyContinue)
if (-not $dartExe) {
    Write-Host "ERROR: dart.exe not found. Is C:\flutter\bin in PATH?" -ForegroundColor Red
    exit 1
}

$proxyBase = "http://127.0.0.1:$ProxyPort"

if (-not $NoProxy) {
    # Already running? Then reuse it.
    $running = Get-NetTCPConnection -LocalPort $ProxyPort -State Listen -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "Dev proxy already listening on $ProxyPort, reusing it." -ForegroundColor Green
    } else {
        $proxyArgs = "run tool/dev_proxy.dart --port $ProxyPort"
        if ($NoProxyWindow) {
            Start-Process -FilePath $dartExe.Source -ArgumentList "run","tool/dev_proxy.dart","--port","$ProxyPort" -WindowStyle Hidden
        } else {
            Start-Process -FilePath $env:ComSpec -ArgumentList "/k",$proxyArgs
        }
        Write-Host "Waiting for dev proxy on $proxyBase ..." -NoNewline
        $ok = $false
        for ($i = 0; $i -lt 40; $i++) {
            Start-Sleep -Milliseconds 500
            try {
                $ping = Invoke-WebRequest -Uri "$proxyBase/health" -UseBasicParsing -TimeoutSec 2
                if ($ping.StatusCode -eq 200) { $ok = $true; break }
            } catch { }
            Write-Host "." -NoNewline
        }
        Write-Host ""
        if (-not $ok) {
            Write-Host "ERROR: dev proxy did not come up on port $ProxyPort." -ForegroundColor Red
            Write-Host "Start it manually:  dart run tool/dev_proxy.dart --port $ProxyPort"
            exit 1
        }
        Write-Host "Dev proxy ready: $proxyBase" -ForegroundColor Green
    }
} else {
    Write-Host "Skipping dev proxy (-NoProxy): Bilibili requests will hit CORS errors." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Starting: flutter run -d $Device --web-port=$WebPort --dart-define=DEV_PROXY_BASE=$proxyBase"
Write-Host "Then scan the QR code with the Bilibili mobile app."
Write-Host ""

if ($NoProxy) {
    # Explicitly disable the in-app proxy (Web builds enable 127.0.0.1:9090 by default)
    flutter run -d $Device --web-port=$WebPort "--dart-define=DEV_PROXY_BASE=off"
} else {
    flutter run -d $Device --web-port=$WebPort "--dart-define=DEV_PROXY_BASE=$proxyBase"
}
