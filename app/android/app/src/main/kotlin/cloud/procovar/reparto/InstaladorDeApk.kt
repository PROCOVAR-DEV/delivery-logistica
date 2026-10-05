package cloud.procovar.reparto

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * INSTALAR LA ACTUALIZACION SIN SALIR DE LA APLICACION — 05/10/2026.
 *
 * Jose, con la 1.0.22 en el telefono:
 *
 *   «el mapa si me funciona dentro de la aplicacion, pero la APK me manda a
 *    descargarla al navegador en vez de actualizar ahi mismo en la aplicacion sin
 *    necesidad de salir»
 *
 * La descarga la hace Dart (`lib/nucleo/actualizacion/bajada_de_la_actualizacion.dart`,
 * con el mismo motor que el mapa: reanudable y comprobada por `sha256`). Lo unico
 * que este lado hace es **llevar el fichero ya comprobado a la pantalla de
 * instalar de Android**.
 *
 * ## Lo que NO se puede hacer, y por eso la interfaz lo avisa antes
 *
 * **Instalar.** Android ensena SU pantalla de «¿quieres instalar esta
 * aplicacion?» y ahi confirma la persona. Eso no se puede saltar desde una
 * aplicacion que no es del sistema, con FileProvider o sin el. Lo que se gana es
 * todo lo demas: la descarga con su barra, reanudable, y un toque al final en vez
 * de ir a buscar el fichero a la carpeta de Descargas.
 *
 * ## Los dos permisos, que no son el mismo
 *
 *  1. `REQUEST_INSTALL_PACKAGES` en el manifiesto. Es de instalacion: se concede
 *     al instalar esta APK y no se le pide a nadie.
 *  2. **El ajuste por aplicacion** de «instalar aplicaciones desconocidas», desde
 *     Android 8. Lo da la persona y **la primera vez NO esta dado en ningun
 *     telefono**: por eso [sePuede] existe y se pregunta ANTES de ofrecer el
 *     boton. Un boton que lleva a una pantalla que no sale ensena a no fiarse del
 *     boton.
 *
 * ## Por que un canal propio y no un plugin
 *
 * Lo mismo que [VeredictoDeRed]: son veinte lineas que queremos leer, y un plugin
 * traeria otro `FileProvider`, otro permiso y otra version que mantener.
 */
class InstaladorDeApk(private val contexto: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CANAL = "cloud.procovar.reparto/instalar_apk"

        // Los metodos. Tienen que ser los mismos que en `CanalDelInstalador`
        // (Dart), y eso **no se deja a un comentario**: lo comprueba
        // `test/nucleo/actualizacion/el_lado_de_android_cuadra_test.dart`, que abre
        // este fichero. Un comentario no falla.
        const val SE_PUEDE = "sePuede"
        const val INSTALAR = "instalar"
        const val AJUSTE_DEL_PERMISO = "ajusteDelPermiso"

        // Lo que contesta `instalar`.

        /** El instalador de Android esta delante. Lo que pase ya no es nuestro. */
        const val ABIERTO = "abierto"

        /** Falta el ajuste por aplicacion. */
        const val SIN_PERMISO = "sinPermiso"

        /** El fichero no esta, esta vacio, o no es de esta aplicacion. */
        const val NO_ESTA_EL_FICHERO = "noEstaElFichero"

        /** No se pudo ofrecer el fichero al instalador, o no hubo quien lo abriera. */
        const val NO_SE_COMPARTIO = "noSeCompartio"

        /**
         * La autoridad del `FileProvider`, que es `${applicationId}.ficheros`.
         *
         * **Es la del manifiesto, y es un sufijo y no un literal** porque el
         * manifiesto la escribe con `${applicationId}`: dejarla escrita entera
         * aqui es el fallo que aparece el dia que alguien cambie el
         * `applicationId` —el `FileProvider` no se encuentra, y el unico sintoma
         * es que la instalacion no arranca.
         */
        const val SUFIJO_DE_LA_AUTORIDAD = ".ficheros"

        /** El tipo de un APK. Es lo que hace que Android ofrezca el instalador. */
        const val TIPO_DE_APK = "application/vnd.android.package-archive"
    }

    fun registrar(mensajero: BinaryMessenger) {
        MethodChannel(mensajero, CANAL).setMethodCallHandler(this)
    }

    override fun onMethodCall(llamada: MethodCall, respuesta: MethodChannel.Result) {
        when (llamada.method) {
            SE_PUEDE -> respuesta.success(sePuede())
            INSTALAR -> respuesta.success(instalar(llamada.argument<String>("ruta")))
            AJUSTE_DEL_PERMISO -> {
                abrirElAjuste()
                respuesta.success(null)
            }
            else -> respuesta.notImplemented()
        }
    }

    /**
     * ¿Puede esta aplicacion pedir una instalacion?
     *
     * En Android 7 y anteriores no hay ajuste por aplicacion —lo hay para todo el
     * telefono— asi que se contesta `true` y, si estuviera cerrado, el sistema lo
     * dira el en su pantalla. Mentir hacia el otro lado dejaria sin boton a
     * telefonos que si pueden.
     */
    private fun sePuede(): Boolean =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            true
        } else {
            contexto.packageManager.canRequestPackageInstalls()
        }

    private fun instalar(ruta: String?): String {
        val fichero = ruta?.let { File(it) } ?: return NO_ESTA_EL_FICHERO
        // Un fichero que no esta o que esta vacio NO se le pasa al instalador: lo
        // que se ve entonces es «no se pudo instalar la aplicacion», que no dice
        // de que va. Esto se dice con su nombre y se vuelve a bajar.
        if (!fichero.isFile || fichero.length() == 0L) return NO_ESTA_EL_FICHERO

        // SOLO FICHEROS NUESTROS. La ruta viene de Dart, y aunque hoy la escribe
        // esta misma aplicacion, lo que hay al otro lado de un canal se trata como
        // lo que viene de fuera: dar permiso de lectura sobre cualquier ruta del
        // telefono es justo lo que un `FileProvider` existe para no hacer.
        if (!esNuestro(fichero)) return NO_SE_COMPARTIO

        // EL PERMISO SE MIRA AQUI TAMBIEN, y no solo en Dart: entre que se
        // pregunto y que se pulso, la persona puede haber ido a quitarlo.
        if (!sePuede()) return SIN_PERMISO

        val uri: Uri = try {
            FileProvider.getUriForFile(
                contexto,
                contexto.packageName + SUFIJO_DE_LA_AUTORIDAD,
                fichero,
            )
        } catch (e: IllegalArgumentException) {
            // El fichero no cae bajo ninguna de las raices declaradas en
            // `res/xml/ficheros_de_la_actualizacion.xml`. Pasa si alguien cambia
            // la carpeta en Dart y se olvida del XML, y el unico sintoma seria que
            // no arranca: se dice.
            return NO_SE_COMPARTIO
        }

        val intencion = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, TIPO_DE_APK)
            // El primero es el que deja al instalador LEER el fichero: sin el,
            // Android abre su pantalla y falla al leerlo. El segundo hace falta
            // porque esto sale del contexto de la aplicacion y no de una Activity.
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            contexto.startActivity(intencion)
            ABIERTO
        } catch (e: Exception) {
            NO_SE_COMPARTIO
        }
    }

    /** Dentro de las carpetas de esta aplicacion, y ninguna otra. */
    private fun esNuestro(fichero: File): Boolean {
        val suyo = try {
            fichero.canonicalPath
        } catch (e: Exception) {
            return false
        }
        val nuestras = listOfNotNull(
            contexto.filesDir,
            contexto.cacheDir,
            contexto.getExternalFilesDir(null),
        )
        return nuestras.any { carpeta ->
            val raiz = try {
                carpeta.canonicalPath
            } catch (e: Exception) {
                return@any false
            }
            suyo == raiz || suyo.startsWith(raiz + File.separator)
        }
    }

    /**
     * Lleva al ajuste del sistema. **No concede nada**: lo concede la persona.
     *
     * La pantalla por aplicacion es de Android 8. Por debajo se abre la de
     * seguridad, que es donde esta el interruptor de todo el telefono; y si
     * ninguna de las dos existe —hay fabricantes que las cambian de sitio— se
     * anota y no se revienta: la interfaz sigue ofreciendo el navegador.
     */
    private fun abrirElAjuste() {
        val porAplicacion = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
        val intencion = if (porAplicacion) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + contexto.packageName),
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        intencion.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            contexto.startActivity(intencion)
        } catch (e: Exception) {
            try {
                contexto.startActivity(
                    Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (otro: Exception) {
                // Sin ajustes a los que ir. No se cae: el navegador sigue ahi.
            }
        }
    }
}

/**
 * EL PROVEEDOR DE FICHEROS de esta aplicacion.
 *
 * Es una subclase de [FileProvider] y no el `androidx.core.content.FileProvider` a
 * secas **porque Android exige que cada `<provider>` tenga una clase distinta**, y
 * en este APK ya hay dos que son `FileProvider`: el de `share_plus` (compartir la
 * ruta con el chofer) y el de `printing` (la hoja del almacen). Declarar la misma
 * clase otra vez rompe la union de los manifiestos, y el error no se parece en
 * nada a la causa.
 */
class FicherosDelReparto : FileProvider()
