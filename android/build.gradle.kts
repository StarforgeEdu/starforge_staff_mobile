allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter 3.44 keeps AGP 9's built-in Kotlin disabled while plugins migrate.
// file_picker 11 skips applying legacy KGP on AGP 9, so apply the compatibility
// plugin when its Android library is configured. Remove this once Flutter 3.47+
// built-in Kotlin is enabled for the whole project.
subprojects {
    if (name == "file_picker") {
        pluginManager.withPlugin("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
}

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
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
