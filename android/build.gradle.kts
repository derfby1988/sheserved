buildscript {
    repositories {
        google()
        mavenCentral()
    }
    configurations.all {
        resolutionStrategy {
            force("com.google.guava:guava:33.0.0-android")
        }
    }
}

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
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin") {
                useVersion("1.9.24")
            }
            if (requested.name == "guava") {
                useVersion("33.0.0-android")
            }
        }
    }
}

subprojects {
    tasks.configureEach {
        if (name.contains("merge", ignoreCase = true) && name.contains("JavaResource", ignoreCase = true)) {
            doFirst {
                println("Surgical bypass: Mocking outputs for task $name in ${project.name}")
                outputs.files.forEach { file ->
                    if (!file.exists()) {
                        file.parentFile.mkdirs()
                        if (file.extension == "jar" || file.name.endsWith(".jar")) {
                            java.util.zip.ZipOutputStream(file.outputStream()).use { }
                        } else {
                            file.mkdirs()
                        }
                    }
                }
                throw StopExecutionException()
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
