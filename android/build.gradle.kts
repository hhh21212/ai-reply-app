allprojects {
    repositories {
        maven { url = uri("https://dl.google.com/dl/android/maven2/") }
        mavenCentral()
    }
}

// 强制所有 Android 子模块(插件)用 compileSdk 36，规避旧插件硬编码低 compileSdk 导致的新依赖报错
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (androidExt != null) {
            androidExt.compileSdkVersion(36)
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
