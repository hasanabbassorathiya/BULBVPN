import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
        // ics-openvpn AAR shipped inside openvpn_dart (network.mysterium.openvpn:icsopenvpn).
        val openVpnAndroid = rootProject.findProject(":openvpn_dart")?.projectDir
        if (openVpnAndroid != null) {
            maven { url = uri(openVpnAndroid.resolve("localmaven")) }
        }
    }
}

// Flutter reads its artifacts from <project>/build. Keep every Gradle module
// writing there too; without this the APK lands in android/app/build and
// `flutter run` reports that no APK was produced.
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    afterEvaluate {
        extensions.findByType(LibraryExtension::class.java)?.apply {
            if ((compileSdk ?: 0) < 36) {
                compileSdk = 36
            }
        }
    }
}
