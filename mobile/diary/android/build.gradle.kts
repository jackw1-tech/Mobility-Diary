allprojects {
    repositories {
        google()
        mavenCentral()
        // Repository privato Mapbox per scaricare il Maps SDK nativo.
        // Il token SECRET (sk....) va in android/gradle.properties come
        // MAPBOX_DOWNLOADS_TOKEN oppure nella variabile d'ambiente omonima.
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication { create<BasicAuthentication>("basic") }
            credentials {
                username = "mapbox"
                password = (project.findProperty("MAPBOX_DOWNLOADS_TOKEN")
                    ?: System.getenv("MAPBOX_DOWNLOADS_TOKEN")
                    ?: "") as String
            }
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
