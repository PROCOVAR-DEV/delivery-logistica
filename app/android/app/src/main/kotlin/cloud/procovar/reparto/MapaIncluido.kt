package cloud.procovar.reparto

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import kotlin.concurrent.thread

/**
 * EL MAPA DE CUBA QUE VIENE DENTRO DEL APK del distribuidor (assets nativos, ver
 * `build.gradle.kts`). Dart decide QUE copiar y comprueba el sha256; esto solo mueve
 * bytes: abre el asset con `context.assets.open`, se salta los [desde] bytes que ya
 * estan copiados (reanudar) y los anade al fichero parcial POR TROZOS, sin cargar los 97 MB
 * en memoria. Avisa a Dart del progreso con `avance` (bytes copiados en ESTA llamada).
 *
 * En el APK de siempre no hay asset: `leerTexto` contesta `null` y nadie lo llama.
 */
class MapaIncluido(private val contexto: Context) {
    private val principal = Handler(Looper.getMainLooper())

    fun registrar(mensajero: BinaryMessenger) {
        val canal = MethodChannel(mensajero, "cloud.procovar.reparto/mapa_incluido")
        canal.setMethodCallHandler { llamada, resultado ->
            when (llamada.method) {
                "leerTexto" -> {
                    val asset = llamada.argument<String>("asset")
                    if (asset == null) {
                        resultado.error("sin_asset", "falta el nombre del asset", null)
                    } else {
                        try {
                            contexto.assets.open(asset).use {
                                resultado.success(it.readBytes().toString(Charsets.UTF_8))
                            }
                        } catch (e: IOException) {
                            resultado.success(null) // el APK no lo trae
                        }
                    }
                }
                "copiar" -> {
                    val asset = llamada.argument<String>("asset")
                    val destino = llamada.argument<String>("destino")
                    val desde = (llamada.argument<Number>("desde") ?: 0).toLong()
                    if (asset == null || destino == null) {
                        resultado.error("faltan_datos", "asset o destino sin poner", null)
                    } else {
                        thread(name = "mapa-incluido") {
                            try {
                                copiar(canal, asset, File(destino), desde)
                                principal.post { resultado.success(null) }
                            } catch (e: Exception) {
                                principal.post { resultado.error("copia_fallida", e.message, null) }
                            }
                        }
                    }
                }
                else -> resultado.notImplemented()
            }
        }
    }

    private fun copiar(canal: MethodChannel, asset: String, destino: File, desde: Long) {
        destino.parentFile?.mkdirs()
        contexto.assets.open(asset).use { entrada ->
            var saltado = 0L
            while (saltado < desde) {
                val n = entrada.skip(desde - saltado)
                if (n <= 0) throw IOException("el asset es mas corto que lo ya copiado")
                saltado += n
            }
            // `append = true`: el parcial ya tiene [desde] bytes.
            FileOutputStream(destino, true).use { salida ->
                val buffer = ByteArray(256 * 1024)
                var copiados = 0L
                var ultimoAviso = 0L
                while (true) {
                    val n = entrada.read(buffer)
                    if (n < 0) break
                    salida.write(buffer, 0, n)
                    copiados += n
                    if (copiados - ultimoAviso >= 1024 * 1024) {
                        ultimoAviso = copiados
                        val hasta = copiados
                        principal.post { canal.invokeMethod("avance", hasta) }
                    }
                }
                salida.fd.sync()
                val hasta = copiados
                principal.post { canal.invokeMethod("avance", hasta) }
            }
        }
    }
}
