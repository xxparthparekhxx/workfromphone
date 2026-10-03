import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = mutableMapOf<String, String>()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.forEachLine { line ->
        val trimmed = line.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("#")) return@forEachLine
        val separator = trimmed.indexOf('=')
        if (separator <= 0) return@forEachLine
        keystoreProperties[trimmed.substring(0, separator).trim()] =
            trimmed.substring(separator + 1).trim()
    }
    // A partially-filled key.properties would otherwise fail later with a
    // confusing NoSuchElementException in getValue().
    val requiredKeystoreKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
    val missingKeys = requiredKeystoreKeys.filterNot { keystoreProperties.containsKey(it) }
    if (missingKeys.isNotEmpty()) {
        throw GradleException("key.properties is present but missing: ${missingKeys.joinToString(", ")}")
    }
}

android {
    namespace = "com.example.workfromphone"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.workfromphone"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getValue("keyAlias")
                keyPassword = keystoreProperties.getValue("keyPassword")
                storeFile = file(keystoreProperties.getValue("storeFile"))
                storePassword = keystoreProperties.getValue("storePassword")
            }
        }
    }

    packaging {
        // Force-extract .so files (libproot.so + talloc/shmem/loader) into
        // nativeLibraryDir: ProotRunner execs the binary, which requires a
        // real file (W^X forbids exec under filesDir, and unextracted libs
        // stay inside the APK so the status screen reports Missing).
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // Use a dedicated release keystore when key.properties is present.
            // Local `flutter run --release` still falls back to the debug keystore.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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

// proot + libtalloc + libandroid-shmem + loader are fetched, not checked in.
// Pull them before packaging so a plain `flutter run` / CI APK can actually
// exec the on-device container (the linker error is "libtalloc.so.2 not found"
// when this step is skipped).
val repoRoot = rootProject.projectDir.parentFile
// Pinned proot version from scripts/fetch-proot.sh. A marker file under
// jniLibs records the version of the binaries currently present, so bumping
// the pin re-fetches even when all four files already exist.
val pinnedProotVersion = Regex("""PROOT_VERSION="([^"]+)""")
    .find(repoRoot.resolve("scripts/fetch-proot.sh").readText())
    ?.groupValues?.get(1)
    .orEmpty()
val prootVersionMarker = file("src/main/jniLibs/.proot-fetched-version")
val fetchProot = tasks.register<Exec>("fetchProot") {
    workingDir = repoRoot
    commandLine("bash", repoRoot.resolve("scripts/fetch-proot.sh").absolutePath)
    onlyIf {
        val filesMissing = listOf("arm64-v8a", "x86_64").any { abi ->
            !file("src/main/jniLibs/$abi/libproot.so").isFile ||
                !file("src/main/jniLibs/$abi/libtalloc.so").isFile ||
                !file("src/main/jniLibs/$abi/libandroid-shmem.so").isFile ||
                !file("src/main/jniLibs/$abi/libproot-loader.so").isFile
        }
        if (filesMissing) true
        else !prootVersionMarker.isFile ||
            (pinnedProotVersion.isNotEmpty() &&
                prootVersionMarker.readText().trim() != pinnedProotVersion)
    }
    doLast {
        prootVersionMarker.parentFile?.mkdirs()
        if (pinnedProotVersion.isNotEmpty()) {
            prootVersionMarker.writeText(pinnedProotVersion)
        }
    }
}

// Always rewrite DT_NEEDED even when fetch is skipped: an already-fetched
// libproot.so still NEEDs libtalloc.so.2, which Android will not load.
// Pure-JVM on purpose: no bash/python3 dependency, so Windows hosts and
// offline CI can build. Mirrors scripts/patch-proot-dtneeded.py (kept in the
// repo because scripts/fetch-proot.sh still uses it).
val patchProotNeeded = tasks.register("patchProotNeeded") {
    dependsOn(fetchProot)
    onlyIf {
        listOf("arm64-v8a", "x86_64").any { abi ->
            file("src/main/jniLibs/$abi/libproot.so").isFile
        }
    }
    doLast {
        val oldAliases = listOf("libtalloc.so.2", "libtalloc2.so").map {
            it.encodeToByteArray() + byteArrayOf(0)
        }
        val newName = "libtalloc.so".encodeToByteArray() + byteArrayOf(0)

        fun containsPattern(data: ByteArray, pattern: ByteArray): Boolean {
            if (data.size < pattern.size) return false
            for (i in 0..data.size - pattern.size) {
                var found = true
                for (j in pattern.indices) {
                    if (data[i + j] != pattern[j]) {
                        found = false
                        break
                    }
                }
                if (found) return true
            }
            return false
        }

        fun replacePattern(data: ByteArray, from: ByteArray): ByteArray {
            // NUL-pad the replacement to the alias length so the ELF string
            // table size is unchanged.
            val replacement = newName + ByteArray(from.size - newName.size)
            val out = java.io.ByteArrayOutputStream()
            var i = 0
            while (i < data.size) {
                var match = -1
                if (data.size - i >= from.size) {
                    for (j in 0..data.size - i - from.size) {
                        var found = true
                        for (k in from.indices) {
                            if (data[i + j + k] != from[k]) {
                                found = false
                                break
                            }
                        }
                        if (found) {
                            match = j
                            break
                        }
                    }
                }
                if (match < 0) {
                    out.write(data[i].toInt() and 0xFF)
                    i++
                } else {
                    out.write(replacement)
                    i += match + from.size
                }
            }
            return out.toByteArray()
        }

        for (abi in listOf("arm64-v8a", "x86_64")) {
            val lib = file("src/main/jniLibs/$abi/libproot.so")
            if (!lib.isFile) continue
            val data = ByteArray(lib.length().toInt())
            lib.inputStream().use { it.readFully(data) }
            val hasAlias = oldAliases.any { containsPattern(data, it) }
            if (!hasAlias && containsPattern(data, newName)) {
                logger.lifecycle("$lib: already patched (NEEDs libtalloc.so), skipping")
                continue
            }
            if (!hasAlias) {
                throw GradleException(
                    "$lib: neither libtalloc.so.2 nor libtalloc2.so found in DT_NEEDED; " +
                        "refusing to package an unpatched proot",
                )
            }
            val patched = oldAliases.fold(data) { acc, alias -> replacePattern(acc, alias) }
            lib.outputStream().use { it.write(patched) }
            logger.lifecycle("$lib: rewrote DT_NEEDED -> libtalloc.so")
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn(patchProotNeeded)
}
