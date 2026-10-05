import java.util.Properties

// LA CLAVE CON LA QUE SE FIRMA EL APK.
//
// Sale de `android/key.properties`, que NO está en el repositorio y no puede estarlo:
// lleva la contraseña del almacén de claves. Es un fichero del equipo de quien compila, y
// la copia de seguridad del `.jks` vive en `procovar/.secretos/`
// (`docs/actualizaciones.md` §4 dice cómo se crea; aquí no se genera ninguna clave).
//
// Si no está, el APK de release se firma con la clave de DEPURACIÓN, que Android genera
// sola en cada máquina. Eso sirve para `flutter run --release` y NO sirve para publicar:
// un APK firmado con otra clave Android NO lo acepta como actualización — obliga a
// desinstalar, y desinstalar borra la base local, o sea el trabajo del día sin subir.
// Por eso el caso se avisa a gritos en la salida del build en vez de pasar callando.
val clavesDeFirma = Properties().apply {
    val fichero = rootProject.file("key.properties")
    if (fichero.exists()) fichero.inputStream().use { load(it) }
}
val hayClaveDeVerdad = clavesDeFirma.getProperty("storeFile")?.isNotBlank() == true

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cloud.procovar.reparto"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cloud.procovar.reparto"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 23 fijo, no `flutter.minSdkVersion`: lo pide `sqlite3_flutter_libs`,
        // que es quien mete SQLite dentro del APK. Sin esto la base local no
        // abre en los aparatos viejos y no hay aviso hasta que alguien lo
        // instala.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Sólo existe si hay clave de verdad. Declararla siempre y dejarla a medias daría
        // un error de Gradle en cualquiera que se baje el repositorio.
        if (hayClaveDeVerdad) {
            create("release") {
                storeFile = file(clavesDeFirma.getProperty("storeFile") as String)
                storePassword = clavesDeFirma.getProperty("storePassword") as String
                keyAlias = clavesDeFirma.getProperty("keyAlias") as String
                keyPassword = clavesDeFirma.getProperty("keyPassword") as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hayClaveDeVerdad) {
                signingConfigs.getByName("release")
            } else {
                // Se puede compilar sin clave —hace falta para `flutter run --release` y
                // para que cualquiera pueda clonar esto y compilar— pero lo que sale NO se
                // reparte a nadie.
                logger.warn(
                    "\n  AVISO: no hay android/key.properties, así que este APK va firmado con la\n" +
                    "  clave de DEPURACIÓN. Android NO lo acepta como actualización de uno firmado\n" +
                    "  con otra clave: obliga a desinstalar, y desinstalar BORRA LA BASE LOCAL (el\n" +
                    "  trabajo del día sin subir). No se reparte. Ver docs/actualizaciones.md.\n"
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // `FileProvider`, y solo eso: es lo que deja entregarle el APK bajado al
    // instalador de Android sin un `file://` (prohibido desde Android 7) y sin
    // permisos de almacenamiento. Ver `InstaladorDeApk.kt`.
    //
    // POR QUE EXPLICITA Y NO DE REBOTE: `share_plus` y `printing` traen
    // `androidx.core` dentro, pero como `implementation` de SUS modulos — o sea que
    // no esta en el classpath de compilacion de este. Sin esta linea el Kotlin de
    // aqui no compila, y el error habla de un `import` que «no existe» teniendo la
    // biblioteca dentro del APK.
    //
    // La version, EXACTA como todas las del `pubspec.yaml` (PLAN.md §1), y la 1.13.1
    // a proposito: es la ultima que no sube el `compileSdk` que pide Flutter.
    implementation("androidx.core:core:1.13.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
