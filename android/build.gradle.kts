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

subprojects {
    afterEvaluate {
        extensions.findByType(LibraryExtension::class.java)?.apply {
            if ((compileSdk ?: 0) < 36) {
                compileSdk = 36
            }
        }
    }
}
