import dev.silenium.libs.jni.NativePlatform
import dev.silenium.libs.jni.Platform

buildscript {
    repositories {
        maven("https://reposilite.silenium.dev/releases") {
            name = "silenium-releases"
        }
    }
    dependencies {
        classpath(libs.jni.utils)
    }
}

plugins {
    base
    `maven-publish`
}

group = "dev.silenium.libs.mpv"
version = findProperty("deploy.version") as String? ?: "0.0.0-SNAPSHOT"

val deployNative = (findProperty("deploy.native") as String?)?.toBoolean() ?: true

val platformString = findProperty("deploy.platform")?.toString()
val platform = platformString?.let { Platform(it) } ?: NativePlatform.platform()
val compileDir = layout.buildDirectory.dir("${platform}/output").get()

val compileNative = if (deployNative) {
    tasks.register<Exec>("compileNative") {
        enabled = deployNative
        commandLine("bash", rootProject.layout.projectDirectory.file("build.sh").asFile.absolutePath)
        environment("CI_DEPLOY_PLATFORM", platform.full)
        workingDir(rootProject.layout.projectDirectory.asFile)

        inputs.property("platform", platform)
        inputs.files(layout.projectDirectory.files("build.sh"))
        outputs.dir(compileDir.dir("bin"))
        outputs.dir(compileDir.dir("etc"))
        outputs.dir(compileDir.dir("include"))
        outputs.dir(compileDir.dir("lib"))
        outputs.dir(compileDir.dir("share"))
        outputs.cacheIf { true }
    }
} else null

fun AbstractCopyTask.licenses() {
    from(layout.projectDirectory) {
        include("LICENSE.*", "COPYING.*", "COPYRIGHT.*", "Copyright.*")
    }
}

val zipBuild = if (deployNative) {
    tasks.register<Zip>("zipBuild") {
        dependsOn(compileNative)
        from(compileDir) {
            include("bin/**/*")
            include("etc/**/*")
            include("include/**/*")
            include("lib/**/*")
            include("share/**/*")
        }
        licenses()
    }
} else null

publishing {
    publications {
        create<MavenPublication>("native${platform.capitalized}") {
            artifact(zipBuild)
            artifactId = "mpv-natives-${platform}"
        }
    }
}
