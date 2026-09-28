import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../registro/registro.dart';

/// LO QUE EL SISTEMA OPERATIVO SABE Y NOSOTROS NO: si esta red llega a internet.
///
/// ## El «!» del icono del wifi — 28/09/2026
///
/// Jose, con el teléfono enganchado a un wifi sin salida:
///
/// > «me esta diciendo eso q tengo conexion y no tengo conexion ahora mismo q
/// > mierda es eso por q la wifi no esta dando internet»
/// > «si sale la wifi ahora mismo cuando no tiene conexion sale un icono de wifi
/// > con ! este simbolo diciendo q no hay internet»
///
/// Ese «!» no es una suposición de nadie: es Android, que probó la red y no
/// llegó (`NET_CAPABILITY_VALIDATED`). El dato existe, es del sistema y es
/// instantáneo. La aplicación no se lo preguntaba —sólo miraba si había interfaz
/// enganchada, que contestaba que sí— y a partir de ahí se quedaba esperando a
/// que se cayeran tres ciclos: **un par de minutos diciendo «Todo al día» con el
/// teléfono sin internet.**
///
/// ## Por qué no vale `connectivity_plus`
///
/// Porque son dos banderas distintas de Android y el plugin sólo mira la que no
/// sirve. Leído de su código (`connectivity_plus-7.3.1`,
/// `android/.../connectivity/Connectivity.java:51`), consulta
/// `NET_CAPABILITY_INTERNET` y los transportes, y `VALIDATED` no aparece ni una
/// vez en todo el paquete:
///
///  * `NET_CAPABILITY_INTERNET` — la red **dice** que sirve para salir. **La
///    wifi del «!» también la tiene.** Por eso `hayRedProvider` contestaba que
///    sí.
///  * `NET_CAPABILITY_VALIDATED` — Android **lo probó** y llegó. Es la que
///    enciende el «!», y es la que lee el canal de `VeredictoDeRed.kt`.
enum Veredicto {
  /// La red por defecto está validada: el sistema probó y llegó.
  ///
  /// **No significa que la conexión sirva.** Significa que los paquetes de
  /// prueba de Android llegaron a algún sitio, no que nuestro servidor conteste
  /// ni que la línea aguante una bajada — que es el caso de allá, y el de
  /// Starlink con su latencia. Lo único que hace este valor es **apagar** la
  /// bandera; que la conexión sirva lo sigue diciendo una petición que llegue.
  valida,

  /// Hay red, y el sistema dice que NO llega. Es el «!» del icono.
  noValida,

  /// No hay red por defecto: modo avión, o nada enganchado.
  sinRed,

  /// **Aquí no hay veredicto que preguntar.** No es «va mal»: es «no lo sé».
  ///
  /// Contestan esto Windows, Linux, macOS y la web, **siempre**, porque ninguno
  /// expone nada parecido a `NET_CAPABILITY_VALIDATED`. Convertirlo en un `false`
  /// dejaría el escritorio con el aviso de «sin conexión» puesto para siempre,
  /// que es exactamente el aviso que deja de leerse del `CLAUDE.md`
  /// §3-quinquies. Por eso esto es un estado y no un `bool`.
  noLoSe,
}

/// CUÁNTO TIENE QUE MANTENERSE UN «NO VALIDA» PARA CREÉRSELO.
///
/// **Este número está por medir en el teléfono de Jose. No es una verdad, es un
/// punto de partida.** Lo que sí está medido es el porqué: al engancharse a una
/// red, Android todavía no ha terminado su comprobación y la bandera está en
/// falso un rato. En una wifi de oficina es un instante; con la conexión de allá
/// —lenta y con pérdidas— puede ser varios segundos.
///
/// Creerse ese falso al momento haría parpadear el aviso en CADA cambio de red:
/// al salir del almacén, al entrar en el patio, cada vez que el teléfono salta
/// de wifi a datos. Y un aviso que parpadea deja de leerse a los diez minutos,
/// que es justo lo que no puede pasarle al ámbar de esta casa.
///
/// Cinco segundos es el trato: suficiente para que el sondeo de Android termine,
/// y **treinta veces más rápido** que los dos minutos y medio que se tardaba
/// antes esperando a que se cayeran tres ciclos.
///
/// Lo que NO espera nada es el «no hay red» —ni interfaz, ni veredicto que
/// sondear—, que se sigue creyendo al momento como antes.
const ventanaDeSondeo = Duration(seconds: 5);

/// La pregunta de una vez, para el arranque.
typedef VeredictoAhora = Future<Veredicto> Function();

/// Los avisos en vivo.
typedef AvisosDeVeredicto = Stream<Veredicto> Function();

/// Cómo se crea el temporizador de la ventana. Se inyecta para poder probarlo:
/// un `Timer` de verdad en una prueba es una prueba que depende del reloj de la
/// máquina, y esas se cuelgan en vez de fallar (`CLAUDE.md` §5).
typedef CrearEspera = Timer Function(Duration, void Function());

const _avisos = EventChannel('cloud.procovar.reparto/veredicto_de_red');
const _pregunta = MethodChannel(
  'cloud.procovar.reparto/veredicto_de_red_ahora',
);

/// ¿Hay alguien al otro lado del canal?
///
/// Sólo Android: en Windows, Linux, macOS y la web no existe nada parecido a
/// `NET_CAPABILITY_VALIDATED`, y preguntar sólo serviría para llenar el registro
/// de excepciones.
///
/// ## Y hace falta que haya un mensajero, no sólo la plataforma — 28/09/2026
///
/// En una prueba de unidad `defaultTargetPlatform` **es Android** y no hay
/// ningún binding, así que sin esta segunda mitad el primer `LaSalud` que se
/// construyera en un `test()` corriente reventaba con «Binding has not yet been
/// initialized» al tocar el canal. Y no es un problema de la prueba: es que sin
/// mensajero **no hay aparato al que preguntarle**, y la respuesta correcta a eso
/// ya está escrita ahí abajo — no se sabe.
///
/// Con esto, una prueba que no sustituya nada se comporta como el escritorio:
/// no hay veredicto, y el aviso sigue saliendo por el camino largo de los tres
/// intentos. Que es exactamente lo que había antes de hoy.
bool get hayVeredictoDelSistema =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android && _hayMensajero;

bool get _hayMensajero {
  try {
    ServicesBinding.instance;
    return true;
  } on Object {
    return false;
  }
}

/// El veredicto de ahora mismo, preguntado una vez.
Future<Veredicto> veredictoDelSistemaAhora() async {
  if (!hayVeredictoDelSistema) return Veredicto.noLoSe;
  try {
    final respuesta = await _pregunta.invokeMethod<String>('veredicto');
    return _deLaPalabra(respuesta);
  } on Object catch (e) {
    // Un canal que no contesta **no es «no hay salida»**: es «no lo sé», y ante
    // la duda no se enciende ningún aviso. Rendirse aquí pintaría «sin conexión»
    // delante de alguien que está trabajando.
    Registro.aviso('no se pudo preguntar el veredicto de la red: $e');
    return Veredicto.noLoSe;
  }
}

/// Los avisos del sistema, en crudo y sin ventana de sondeo.
Stream<Veredicto> avisosDelVeredictoDelSistema() {
  if (!hayVeredictoDelSistema) return const Stream<Veredicto>.empty();
  return _avisos
      .receiveBroadcastStream()
      .map((valor) => _deLaPalabra(valor is String ? valor : null))
      .handleError((Object e) {
        Registro.aviso('el canal del veredicto de la red se cayó: $e');
      });
}

Veredicto _deLaPalabra(String? palabra) => switch (palabra) {
  'valida' => Veredicto.valida,
  'noValida' => Veredicto.noValida,
  'sinRed' => Veredicto.sinRed,
  // Una palabra que no conocemos es una versión del canal que no es ésta. No se
  // adivina: no se sabe.
  _ => Veredicto.noLoSe,
};

/// LOS VEREDICTOS QUE SE PUEDEN CREER, con la ventana de sondeo puesta.
///
/// Todo pasa tal cual **menos [Veredicto.noValida]**, que espera
/// [ventanaDeSondeo] antes de salir y se cae si en ese rato llega cualquier otra
/// cosa. El motivo, entero, está en [ventanaDeSondeo]: el primer instante de una
/// red recién enganchada siempre dice «no valida» porque Android todavía no ha
/// terminado de probarla.
///
/// Los demás salen al momento y a propósito:
///
///  * [Veredicto.valida] **apaga** el aviso, y apagar un aviso nunca puede
///    esperar: dejarlo puesto delante de alguien que ya tiene señal es mentir en
///    la otra dirección.
///  * [Veredicto.sinRed] no tiene nada que sondear. Es la misma regla que el
///    «no hay ni interfaz» de `salud.dart`, que se cree al momento desde el
///    22/09/2026.
Stream<Veredicto> losQueSePuedenCreer(
  Stream<Veredicto> crudos, {
  Duration ventana = ventanaDeSondeo,
  CrearEspera crearEspera = Timer.new,
}) {
  final salida = StreamController<Veredicto>.broadcast();
  Timer? esperando;
  StreamSubscription<Veredicto>? enchufe;

  void olvidarLaEspera() {
    esperando?.cancel();
    esperando = null;
  }

  salida.onListen = () {
    enchufe = crudos.listen(
      (veredicto) {
        // Cualquier veredicto nuevo tumba la espera que hubiera: si el sondeo
        // acabó bien, el «no valida» de hace tres segundos no se publica jamás.
        olvidarLaEspera();
        if (veredicto != Veredicto.noValida) {
          salida.add(veredicto);
          return;
        }
        esperando = crearEspera(ventana, () {
          esperando = null;
          if (!salida.isClosed) salida.add(Veredicto.noValida);
        });
      },
      onError: salida.addError,
      onDone: () {
        olvidarLaEspera();
        salida.close();
      },
    );
  };

  salida.onCancel = () async {
    olvidarLaEspera();
    await enchufe?.cancel();
    enchufe = null;
  };

  return salida.stream;
}
