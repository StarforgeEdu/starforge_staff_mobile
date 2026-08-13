import java.io.FileInputStream
import java.security.KeyStore
import java.security.cert.X509Certificate
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
if (releasePropertiesFile.exists()) {
    FileInputStream(releasePropertiesFile).use(releaseProperties::load)
}
val releaseStorePath = System.getenv("STARFORGE_UPLOAD_STORE_FILE")
    ?: releaseProperties.getProperty("storeFile")
val releaseStorePassword = System.getenv("STARFORGE_UPLOAD_STORE_PASSWORD")
    ?: releaseProperties.getProperty("storePassword")
val releaseKeyAlias = System.getenv("STARFORGE_UPLOAD_KEY_ALIAS")
    ?: releaseProperties.getProperty("keyAlias")
val releaseKeyPassword = System.getenv("STARFORGE_UPLOAD_KEY_PASSWORD")
    ?: releaseProperties.getProperty("keyPassword")
val releaseStoreType = System.getenv("STARFORGE_UPLOAD_STORE_TYPE")
    ?: releaseProperties.getProperty("storeType")
val hasReleaseSigning = listOf(
    releaseStorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val releaseStoreFile = releaseStorePath?.takeIf(String::isNotBlank)?.let(rootProject::file)

android {
    namespace = "com.starforge.staff"
    // Keep the store boundary explicit. New Play submissions and updates must
    // target Android 16 (API 36) from 31 August 2026.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.starforge.staff"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                if (!releaseStoreType.isNullOrBlank()) {
                    storeType = releaseStoreType
                }
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = true
            }
        }
    }

    buildTypes {
        release {
            // Store builds are never signed with Flutter's shared debug key.
            // CI/release owners provide key.properties or the STARFORGE_UPLOAD_*
            // environment variables. A release build fails closed when they are
            // absent instead of emitting an easily misidentified unsigned file.
            isDebuggable = false
            isJniDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
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

val verifyReleaseSigning by tasks.registering {
    group = "verification"
    description = "Fails release builds unless a usable non-debug signing identity is configured."
    doLast {
        check(hasReleaseSigning) {
            "Release signing is not configured. Supply android/key.properties or all STARFORGE_UPLOAD_* environment variables."
        }
        val storeFile = requireNotNull(releaseStoreFile) {
            "A release keystore path is required."
        }
        check(storeFile.isFile) {
            "The configured release keystore does not exist or is not a regular file."
        }
        val certificate = sequenceOf(releaseStoreType, "PKCS12", "JKS")
            .filterNotNull()
            .filter(String::isNotBlank)
            .distinct()
            .mapNotNull { type ->
                runCatching {
                    val keyStore = KeyStore.getInstance(type)
                    FileInputStream(storeFile).use { input ->
                        keyStore.load(input, releaseStorePassword!!.toCharArray())
                    }
                    keyStore.getCertificate(releaseKeyAlias) as? X509Certificate
                }.getOrNull()
            }
            .firstOrNull()
        check(certificate != null) {
            "The release signing certificate could not be loaded with the configured alias and password."
        }
        check(
            !certificate.subjectX500Principal.name.contains(
                "CN=Android Debug",
                ignoreCase = true,
            ),
        ) {
            "The Android debug certificate cannot be used to sign production releases."
        }
    }
}

tasks.configureEach {
    if (name == "preReleaseBuild") {
        dependsOn(verifyReleaseSigning)
    }
}
