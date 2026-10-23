# HADİ Crew: web derlemesi (+ isteğe bağlı Cloudflare Pages'e yükleme).
#   powershell -ExecutionPolicy Bypass -File tools\build.ps1            → yalnızca derle (build\web)
#   powershell -ExecutionPolicy Bypass -File tools\build.ps1 -Deploy    → derle + Cloudflare Pages'e yükle
# Yüklemeden önce bir kez: npx wrangler login  (tarayıcıda Cloudflare hesabınla onay verirsin)
param([switch]$Deploy, [string]$Flutter = "")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
if (-not $Flutter) {
  $cmd = Get-Command flutter -ErrorAction SilentlyContinue
  $Flutter = if ($cmd) { $cmd.Source } else { "D:\flutter\flutter\bin\flutter.bat" }
}
if (-not (Test-Path "..\hadimobile\pubspec.yaml")) { throw "..\hadimobile bulunamadı: iki klasör yan yana olmalı (D:\hadimobile, D:\hadicrew)." }
if (-not (Test-Path "web_config.json")) { & (Join-Path $PSScriptRoot "make_web_config.ps1") }
$wc = Get-Content -Raw -Encoding UTF8 "web_config.json" | ConvertFrom-Json
if (-not $wc.FB_API_KEY -or -not $wc.FB_APP_ID -or -not $wc.FB_SENDER_ID) { throw "web_config.json boş: README › Kurulum › 0" }
& $Flutter pub get
if ($LASTEXITCODE -ne 0) { throw "pub get başarısız" }
$stamp = Get-Date -Format "yyyyMMddHHmmss"
& $Flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --dart-define-from-file=web_config.json --dart-define=HADI_BUILD=$stamp
if ($LASTEXITCODE -ne 0) { throw "web derlemesi başarısız" }
# Sürüm etiketi: index.html içindeki __HADI_BUILD__ yerine yazılır; hadi_build.txt açık panelin yeni sürümü fark etmesi için.
$ix = Join-Path $root "build\web\index.html"; [IO.File]::WriteAllText($ix, [IO.File]::ReadAllText($ix).Replace("__HADI_BUILD__", $stamp))
[IO.File]::WriteAllText((Join-Path $root "build\web\hadi_build.txt"), $stamp)
if (Test-Path (Join-Path $root "build\web\flutter_service_worker.js")) { Remove-Item (Join-Path $root "build\web\flutter_service_worker.js") }
Write-Host "Derleme hazır: $root\build\web"
if ($Deploy) {
  npx --yes wrangler pages deploy build/web --project-name=hadi-crew --branch=main --commit-dirty=true
  if ($LASTEXITCODE -ne 0) { throw "Cloudflare yüklemesi başarısız" }
}
