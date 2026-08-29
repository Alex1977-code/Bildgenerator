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

// desktop_drop 0.8.2 wendet auf AGP 9 kein eigenes Kotlin-Plugin an und
// erwartet AGPs "built-in Kotlin"; das Flutter-Template deaktiviert
// built-in Kotlin jedoch (android.builtInKotlin=false). Ohne diesen Block
// schlägt die Auswertung von desktop_drop/android/build.gradle fehl
// ("Could not find method kotlin()").
subprojects {
    if (name == "desktop_drop") {
        beforeEvaluate {
            apply(plugin = "org.jetbrains.kotlin.android")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
