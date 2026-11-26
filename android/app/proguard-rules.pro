# ─── Flutter ─────────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter embedding 引用了 Play Core 延迟组件类（本项目未用 deferred components，
# 也不依赖 play-services-core-unity），R8 缺类警告直接忽略。
-dontwarn com.google.android.play.core.**

# ─── 应用代码（JSON 解析 / 反射安全）────────────────────────────────────────
-keep class com.dogsheep.player.** { *; }

# ─── just_audio ──────────────────────────────────────────────────────────────
-keep class com.ryanheise.just_audio.** { *; }

# ─── audio_service ───────────────────────────────────────────────────────────
-keep class com.ryanheise.audioservice.** { *; }
