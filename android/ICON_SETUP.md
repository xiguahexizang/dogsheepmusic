# 应用图标生成

使用 `assets/logo.png`（1024x1024，深蓝底 + 米白狼羊音符剪影）生成各尺寸 Android 图标。

> 当前 `android/app/src/main/res/mipmap-*/ic_launcher.png` 为直接复制 logo.png 的**占位图**，
> 构建不会失败，但体积偏大且未按密度裁剪。正式发版前请用以下任一方法重新生成。

## 方法 1：Android Studio
1. 右键 `res/mipmap` 目录 → New → Image Asset
2. Source Asset 选择 `assets/logo.png`
3. Background 选择 `#1E2A3A` 纯色
4. 生成即可

## 方法 2：命令行（需 ImageMagick）
```powershell
magick assets/logo.png -resize 48x48 android/app/src/main/res/mipmap-mdpi/ic_launcher.png
magick assets/logo.png -resize 72x72 android/app/src/main/res/mipmap-hdpi/ic_launcher.png
magick assets/logo.png -resize 96x96 android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
magick assets/logo.png -resize 144x144 android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
magick assets/logo.png -resize 192x192 android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
```

## 方法 3：Flutter 包（推荐，已在本项目 pubspec.yaml 中配置）
`dev_dependencies` 已包含 `flutter_launcher_icons`，且已写入 `flutter_launcher_icons:` 配置段：

```yaml
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/logo.png"
  adaptive_icon_background: "#1E2A3A"
  adaptive_icon_foreground: "assets/logo.png"
```

一条命令生成全部密度图标 + 自适应图标（Android 8.0+）：

```powershell
flutter pub get
dart run flutter_launcher_icons
```
