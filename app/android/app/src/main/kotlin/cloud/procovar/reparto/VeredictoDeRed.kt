package cloud.procovar.reparto

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * EL VEREDICTO DEL SISTEMA: si la red que se esta usando LLEGA A INTERNET.
 *
 * ## El «!» del icono del wifi — 28/09/2026
 *
 * Jose, con el telefono enganchado a un wifi que no daba salida:
 *
 *   «me esta diciendo eso q tengo conexion y no tengo conexion ahora mismo q
 *    mierda es eso por q la wifi no esta dando internet»
 *   «si sale la wifi ahora mismo cuando no tiene conexion sale un icono de wifi
 *    con ! este simbolo diciendo q no hay internet»
 *
 * Ese «!» no es una suposicion de nadie: es Android, que probo la red y no
 * llego. El dato existe, es instantaneo y es del sistema. La aplicacion no se lo
 * preguntaba, asi que se quedaba esperando a que se cayeran tres ciclos — un par
 * de minutos diciendo «Todo al dia» con el telefono sin internet.
 *
 * ## Y por que no bastaba `connectivity_plus`
 *
 * Porque son DOS banderas distintas de Android y el plugin solo mira la que no
 * sirve (leido de su codigo, `connectivity_plus-7.3.1`,
 * `.../connectivity/Connectivity.java:51`):
 *
 *  * `NET_CAPABILITY_INTERNET`  — la red **dice** que sirve para salir.
 *    **La wifi del «!» TAMBIEN la tiene.**
 *  * `NET_CAPABILITY_VALIDATED` — Android **lo probo** y llego. Esta es la que
 *    enciende y apaga el «!», y la que se lee aqui.
 *
 * ## SOBRE LA RED POR DEFECTO, NO SOBRE LA WIFI
 *
 * `registerDefaultNetworkCallback` y no un `NetworkRequest` de wifi, y esto es
 * el caso literal de Jose: tenia **datos moviles Y la wifi enganchada** a una
 * red muerta. Cuando la wifi no valida, Android deja de usarla y saca el trafico
 * por los datos; mirar la wifi diria «sin conexion» mientras la aplicacion
 * funciona perfectamente. Lo que importa es el veredicto de la red que de verdad
 * se esta usando, que es justo la que devuelve este callback.
 *
 * ## Lo que NO hace
 *
 * No dice que la conexion sirva. Que Android valide una red significa que sus
 * paquetes de prueba llegaron a algun sitio, no que nuestro servidor conteste ni
 * que la linea aguante una bajada. Eso lo sigue diciendo una peticion que llegue
 * (`lib/nucleo/red/salud.dart`). Aqui solo se contesta la mitad que el sistema
 * sabe y nosotros no: **que NO hay salida**.
 *
 * Permisos: `ACCESS_NETWORK_STATE`, que ya estaba en el manifiesto desde el
 * 16/09/2026. No hace falta ninguno nuevo ni aparece nada en la ficha de Play.
 */
class VeredictoDeRed(contexto: Context) : EventChannel.StreamHandler {

    companion object {
        /** La red por defecto validada: Android probo y llego. */
        const val VALIDA = "valida"

        /** Hay red, pero Android probo y NO llego. Es el «!» del icono. */
        const val NO_VALIDA = "noValida"

        /** No hay red por defecto ninguna: modo avion, o nada enganchado. */
        const val SIN_RED = "sinRed"

        const val CANAL_AVISOS = "cloud.procovar.reparto/veredicto_de_red"
        const val CANAL_PREGUNTA = "cloud.procovar.reparto/veredicto_de_red_ahora"
    }

    private val gestor =
        contexto.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    /**
     * Los avisos llegan en un hilo de binder y Flutter solo admite el principal.
     * Sin esto revienta con «Methods marked with @UiThread must be executed on
     * the main thread», y revienta EN EL APARATO, no aqui.
     */
    private val hiloPrincipal = Handler(Looper.getMainLooper())

    private var haciaFlutter: EventChannel.EventSink? = null
    private var vigilante: ConnectivityManager.NetworkCallback? = null

    fun registrar(mensajero: BinaryMessenger) {
        EventChannel(mensajero, CANAL_AVISOS).setStreamHandler(this)
        MethodChannel(mensajero, CANAL_PREGUNTA).setMethodCallHandler { llamada, respuesta ->
            if (llamada.method == "veredicto") {
                respuesta.success(veredictoDeAhora())
            } else {
                respuesta.notImplemented()
            }
        }
    }

    /**
     * La misma pregunta, hecha una vez.
     *
     * Hace falta para el arranque: el caso del repartidor no es «se va la red con
     * la aplicacion abierta», es **abrir la aplicacion con la red ya muerta**. Ahi
     * no hay ningun cambio que avisar, porque el sistema ya lo estaba diciendo
     * antes de que nadie preguntara.
     */
    private fun veredictoDeAhora(): String {
        val red = gestor.activeNetwork ?: return SIN_RED
        return leer(gestor.getNetworkCapabilities(red))
    }

    private fun leer(capacidades: NetworkCapabilities?): String {
        if (capacidades == null) return SIN_RED
        // Las dos juntas: una red que ni dice servir para salir tampoco es salida.
        val sirve = capacidades.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capacidades.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        return if (sirve) VALIDA else NO_VALIDA
    }

    private fun mandar(veredicto: String) {
        hiloPrincipal.post { haciaFlutter?.success(veredicto) }
    }

    override fun onListen(argumentos: Any?, salida: EventChannel.EventSink?) {
        haciaFlutter = salida
        val vigia = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(red: Network, capacidades: NetworkCapabilities) {
                mandar(leer(capacidades))
            }

            override fun onLost(red: Network) {
                // Se fue la red por defecto. Si entra otra, `onCapabilitiesChanged`
                // lo dira enseguida; mientras tanto, no hay por donde salir.
                mandar(SIN_RED)
            }

            override fun onUnavailable() {
                mandar(SIN_RED)
            }
        }
        vigilante = vigia
        gestor.registerDefaultNetworkCallback(vigia)
        // El de ahora, sin esperar a que cambie nada.
        mandar(veredictoDeAhora())
    }

    override fun onCancel(argumentos: Any?) {
        vigilante?.let { gestor.unregisterNetworkCallback(it) }
        vigilante = null
        haciaFlutter = null
    }
}
