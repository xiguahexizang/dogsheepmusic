# 狗羊播放器 Release APK 构建脚本
# 用法：在 PowerShell 中执行  .\build_apk.ps1
Write-Host "=== 狗羊播放器 Release APK 构建 ===" -ForegroundColor Cyan

# 切到脚本所在目录，保证相对路径正确
Set-Location $PSScriptRoot

# 检查 Flutter
$flutterVersion = flutter --version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "错误：Flutter SDK 未安装或不在 PATH 中" -ForegroundColor Red
    Write-Host "请先安装 Flutter SDK (>= 3.0)：https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Red
    exit 1
}

# 检查签名文件（放在 android/ 目录，与 key.properties 的 storeFile=./dogsheep-release.keystore 对应）
if (-not (Test-Path "android/dogsheep-release.keystore")) {
    Write-Host "警告：签名文件不存在，尝试生成 debug keystore 用于测试..." -ForegroundColor Yellow
    $keytool = Get-Command keytool -ErrorAction SilentlyContinue
    if ($keytool) {
        & keytool -genkey -v -keystore android/dogsheep-release.keystore -alias dogsheep -keyalg RSA -keysize 2048 -validity 10000 -storepass dogsheep123 -keypass dogsheep123 -dname "CN=DogSheep, OU=Dev, O=DogSheep, L=City, ST=State, C=CN"
        if ($LASTEXITCODE -eq 0) {
            # 更新 key.properties（注意：必须用 ASCII/无 BOM 编码，否则 Java Properties 解析失败）
@"
storePassword=dogsheep123
keyPassword=dogsheep123
keyAlias=dogsheep
storeFile=./dogsheep-release.keystore
"@ | Out-File -FilePath android/key.properties -Encoding ascii
            Write-Host "已生成测试 keystore 并写入 android/key.properties" -ForegroundColor Green
        } else {
            Write-Host "keytool 执行失败，将以 debug 签名构建" -ForegroundColor Yellow
        }
    } else {
        Write-Host "未找到 keytool（需 JDK），将以 debug 签名构建（仅测试用，不可上架）" -ForegroundColor Yellow
    }
}

# 清理并获取依赖
Write-Host "正在获取依赖..." -ForegroundColor Cyan
flutter clean
flutter pub get

# 可选：生成正式启动图标（若已安装 flutter_launcher_icons 配置）
if (Test-Path "assets/logo.png") {
    Write-Host "正在生成启动图标（flutter_launcher_icons）..." -ForegroundColor Cyan
    dart run flutter_launcher_icons
}

# 构建 APK
Write-Host "正在构建 Release APK (arm64-v8a)..." -ForegroundColor Cyan
flutter build apk --release --target-platform android-arm64

# 输出结果
$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkPath) {
    $size = (Get-Item $apkPath).Length / 1MB
    Write-Host "构建成功！" -ForegroundColor Green
    Write-Host "APK 路径: $((Get-Item $apkPath).FullName)" -ForegroundColor Green
    Write-Host ("APK 大小: {0:F1} MB" -f $size) -ForegroundColor Green
} else {
    Write-Host "构建失败，请检查错误日志" -ForegroundColor Red
    exit 1
}
