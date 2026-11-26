$ErrorActionPreference = 'Stop'
$procs = Get-CimInstance Win32_Process -Filter "Name='chrome.exe'"
$hit = $null
foreach ($p in $procs) {
  if ($p.CommandLine -match '--remote-debugging-port=(\d+)' -and $p.CommandLine -match 'chrome-debug') {
    $hit = $p
    break
  }
}
if ($null -eq $hit) {
  Write-Output 'NO_CHROME_DEBUG_PORT'
  exit 1
}
$port = [regex]::Match($hit.CommandLine, '--remote-debugging-port=(\d+)').Groups[1].Value
Write-Output ("debug_port=" + $port)
$targets = Invoke-RestMethod ("http://127.0.0.1:" + $port + "/json")
foreach ($t in $targets) {
  if ($t.type -eq 'page') {
    Write-Output ("ws=" + $t.webSocketDebuggerUrl)
    Write-Output ("page_url=" + $t.url)
    break
  }
}
