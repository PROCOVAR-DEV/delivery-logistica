package cloud.procovar.reparto

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    /**
     * Aqui se engancha lo unico que este lado sabe y Dart no: si Android probo la
     * red por defecto y llego. Ver [VeredictoDeRed] — el «!» del icono del wifi.
     *
     * Va con `applicationContext` y no con la Activity a proposito: el vigilante
     * de red vive mientras viva el canal, y atarlo a una Activity que se recrea
     * al girar el telefono es la forma de quedarse con un callback registrado
     * contra una pantalla que ya no existe.
     */
    override fun configureFlutterEngine(motor: FlutterEngine) {
        super.configureFlutterEngine(motor)
        VeredictoDeRed(applicationContext).registrar(motor.dartExecutor.binaryMessenger)
        // Y lo otro que este lado sabe y Dart no: pedirle al sistema que instale el
        // APK que la aplicacion acaba de bajar y comprobar. Ver [InstaladorDeApk] —
        // «actualizar ahi mismo en la aplicacion sin necesidad de salir».
        //
        // `applicationContext` por lo mismo de arriba: el `Intent` sale con
        // `FLAG_ACTIVITY_NEW_TASK` y no necesita la Activity, asi que atarlo a una
        // que se recrea al girar el telefono solo trae un callback contra una
        // pantalla que ya no existe.
        InstaladorDeApk(applicationContext).registrar(motor.dartExecutor.binaryMessenger)
    }
}
