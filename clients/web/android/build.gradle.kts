allprojects {
    repositories {
        google()
        mavenCentral()
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

subprojects {
    val configureSubproject: (Project) -> Unit = { p ->
        if (p.hasProperty("android")) {
            val androidExt = p.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            androidExt?.compileSdkVersion(36)
        }
    }
    if (state.executed) {
        configureSubproject(this)
    } else {
        afterEvaluate {
            configureSubproject(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
