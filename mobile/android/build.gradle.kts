allprojects {
    repositories {
        google()
        mavenCentral()
    }
    extra["flutter"] = mapOf(
        "compileSdkVersion" to 34,
        "minSdkVersion" to 21,
        "targetSdkVersion" to 34
    )
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
