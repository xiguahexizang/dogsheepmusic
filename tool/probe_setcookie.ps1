$urls = @(
  "http://127.0.0.1:8888/p/api.bilibili.com/x/web-interface/nav",
  "http://127.0.0.1:8888/p/www.bilibili.com/",
  "http://127.0.0.1:8888/p/passport.bilibili.com/x/passport-login/web/qrcode/generate",
  "http://127.0.0.1:8888/p/passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=test123"
)

foreach ($u in $urls) {
  try {
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -Headers @{ "Origin" = "http://localhost:7070" } -TimeoutSec 20
    $sc = $r.Headers["x-proxy-set-cookie"]
    $s = ""
    if ($null -ne $sc) { $s = ($sc -join " ||| ") }
    if ($s.Length -gt 220) { $s = $s.Substring(0, 220) + "..." }
    $aca = $r.Headers["Access-Control-Allow-Origin"]
    $exp = $r.Headers["Access-Control-Expose-Headers"]
    Write-Output "---- $u"
    Write-Output ("  status   : " + $r.StatusCode)
    Write-Output ("  ACAO     : " + $aca)
    Write-Output ("  EXPOSE   : " + $exp)
    if ($s -eq "") { Write-Output "  set-cookie: (none)" } else { Write-Output ("  set-cookie: " + $s) }
  } catch {
    Write-Output "---- $u"
    Write-Output ("  ERROR    : " + $_.Exception.Message)
  }
}
