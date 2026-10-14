plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.universalshare.receiver"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.universalshare.receiver"
        minSdk = 24          // Android 7.0+ (WebView WebRTC desteği için güvenli taban)
        targetSdk = 34
        versionCode = 1
        versionName = "0.3.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // Sideload edilebilir APK için debug anahtarıyla imzala (mağaza öncesi MVP).
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions { jvmTarget = "1.8" }
}
