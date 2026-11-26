import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release 签名配置（读取 android/key.properties，缺失时回退 debug 签名保证可构建）
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
// keystore 路径相对 android/ 解析；仅当文件真实存在时启用 release 签名
val releaseKeystoreFile =
    if (keystorePropertiesFile.exists() && keystoreProperties.getProperty("storeFile") != null) {
        rootProject.file(keystoreProperties.getProperty("storeFile"))
    } else {
        null
    }
val useReleaseSigning = releaseKeystoreFile != null && releaseKeystoreFile.exists()

android {
    namespace = "com.dogsheep.player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dogsheep.player"
        // 目标设备为 Z Fold 7（ARM64），minSdk 31
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // Z Fold 7 仅 ARM64
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            if (useReleaseSigning) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // keystore 可用时使用 release 签名，否则回退 debug 签名
            signingConfig = if (useReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Z Fold 折叠屏三态检测（Jetpack WindowManager）
    implementation("androidx.window:window:1.2.0")
    implementation("androidx.window:window-java:1.2.0")
}
