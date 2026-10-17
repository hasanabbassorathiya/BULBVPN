
allprojects {
    repositories {
        google()
        mavenCentral()
        // openvpn_dart ships the ics-openvpn AAR from a local Maven repo inside the
        // plugin checkout (pub cache). Point Gradle at the plugin's android/localmaven.
        maven {
            url = uri("${System.getProperty("user.home")}/.pub-cache/git/openvpn_dart-260c4445c4180af04f9a8bf2752d485b0b113a63/android/localmaven")
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
