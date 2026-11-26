# 狗羊播放器

基于 Bilibili 大会员的音乐播放器（Flutter）

## 功能
- Bilibili 音乐区 + 视频音频提取
- Hi-Res 无损音质（大会员）
- 个性化推荐
- 后台播放 + 通知栏控制
- Z Fold 7 折叠屏适配

## 构建
1. 安装 Flutter SDK (>= 3.0)
2. 配置签名：创建 `android/dogsheep-release.keystore` 并编辑 `android/key.properties`
   （keystore 放在 `android/` 目录；未配置时自动回退 debug 签名，仅供测试）
3. 生成图标：`dart run flutter_launcher_icons`（详见 `android/ICON_SETUP.md`）
4. 构建：`flutter build apk --release --target-platform android-arm64`
   或运行：`.\build_apk.ps1`（自动检查环境、生成测试 keystore、生成图标并构建）

## 首次使用
安装 APK 后首次启动需要输入 Bilibili 账号密码（手机号已内置）。
如果密码登录被验证码拦截，可在设置页手动导入 Cookie。

## 注意
仅供个人学习使用，不公开分发。
