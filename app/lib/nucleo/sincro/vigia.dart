import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../registro/registro.dart';
import '../reloj.dart';

/// El aviso de `connectivity_plus`, reducido a lo unico que se puede creer: que
/// el aparato **CREE** que hay red.
///
/// `pubspec.yaml` lo dice al lado de la dependencia y es literal: «PISTA de que
/// hay red, nunca la verdad». En Cuba el telefono ensena el wifi conectado y no
/// sale un paquete — el portal cautivo del hotel, la antena que responde al ARP
/// y a nada mas, la linea que se cayo aguas arriba. Por eso esto no dice «hay
/// red»: dice «vale la pena intentarlo», y quien decide si habia red es la
/// peticion, que o va o da `FalloDeRed`.
///
/// Se queda sólo con el flanco de subida. «Se fue la red» no dispara nada:
/// no hay nada que hacer sin red, y la aplicacion ya se comporta igual siempre.
Stream<bool> avisosDeConnectivityPlus() => Connectivity().onConnectivityChanged
    .map((resultados) => resultados.any((r) => r != ConnectivityResult.none));

/// La MISMA pista, preguntada una vez en vez de escuchada.
///
/// Hace falta para el boton: quien le da y no tiene senal no puede quedarse
/// cuarenta segundos mirando una rueda para acabar leyendo «no se pudo». Si el
/// aparato dice que no hay red, se dice **antes** de intentarlo y no se toca
/// nada.
///
/// **Y solo sirve para eso.** Si contesta que SI hay red, no se da por buena:
/// se intenta de verdad, porque en Cuba el telefono ensena el wifi conectado y
/// no sale un paquete. La pista sirve para ahorrar la espera cuando dice que no,
/// nunca para dar por hecho que la hay.
typedef PistaDeRed = Future<bool> Function();

Future<bool> hayPistaDeRed() async {
  try {
    final resultados = await Connectivity().checkConnectivity();
    return resultados.any((r) => r != ConnectivityResult.none);
  } on Object catch (e) {
    // Un destino sin soporte o un canal que no contesta **no es «no hay red»**:
    // es «no lo se», y ante la duda se intenta. Rendirse aqui dejaria sin
    // sincronizar a quien si tiene senal.
    Registro.aviso('no se pudo preguntar por la red, se intenta igual: $e');
    return true;
  }
}

/// Como se crea el temporizador. Se inyecta para poder probarlo: un
/// `Timer.periodic` suelto en una prueba es un temporizador colgado que hace
/// fallar por un motivo que no tiene nada que ver con lo que se estaba probando.
typedef CrearTemporizador = Timer Function(Duration, void Function(Timer));

/// LO QUE HAY EN EL APARATO AHORA MISMO, reducido a las dos cosas que deciden si
/// vale la pena un ciclo al volver delante.
///
/// Es una pieza sola y no dos parametros porque las dos se preguntan juntas y en
/// el mismo momento: una respuesta de cada una, tomadas con un segundo de
/// diferencia, decidirian sobre un aparato que no existio nunca.
class EstadoDeLoQueHay {
  const EstadoDeLoQueHay({this.bajadaAt, this.sinSubir = 0});

  /// Lo que se supone antes de preguntar: **ni idea**, y ante la duda se
  /// sincroniza. Un aparato del que no se sabe nada es indistinguible de uno
  /// virgen, y no bajar ahi es dejar a alguien con la pantalla en ceros.
  static const noSeSabe = EstadoDeLoQueHay();

  /// De cuando es la bajada MAS VIEJA de todas las colecciones. `null` es
  /// **nunca**, que no es «hace mucho»: es un aparato sin estrenar.
  final DateTime? bajadaAt;

  /// Cuantos apuntes quedan en la cola sin subir.
  final int sinSubir;

  @override
  String toString() =>
      'EstadoDeLoQueHay(bajadaAt: $bajadaAt, sinSubir: $sinSubir)';
}

/// Como se le pregunta a la base por [EstadoDeLoQueHay]. Se inyecta: el vigia no
/// sabe que existe Drift y no tiene por que.
typedef LoQueHayAhora = Future<EstadoDeLoQueHay> Function();

/// Lo que se contesta cuando nadie inyecto nada: **no se sabe**, o sea, se
/// sincroniza. El defecto seguro es el que trabaja de mas, no el que se calla.
Future<EstadoDeLoQueHay> noSeSabeLoQueHay() async => EstadoDeLoQueHay.noSeSabe;

/// EL VIGIA. Lo que dispara el ciclo cuando nadie se lo pide.
///
/// Tres ocasiones, y las tres hacen falta:
///
///  1. **Al entrar** — no es cosa de esta clase: lo dispara el portero en cuanto
///     hay sesion.
///  2. **Cuando vuelve la red** — el aviso de `connectivity_plus`. Es el camino
///     bueno en la APK: el logistico sale del almacen, coge cobertura y el dia
///     sube solo sin que toque nada.
///  3. **Cada tanto, mientras la aplicacion este delante** — porque el aviso de
///     arriba **puede no llegar nunca**. En web es lo normal, y en Android
///     tampoco esta garantizado despues de una siesta larga del proceso. Sin el
///     reloj, un aviso perdido es un dia perdido.
///
/// **Nada de esto corre sin sesion.** Quien lo comprueba es el ciclo, que le
/// pregunta al portero; aqui lo que se hace es no tener nada vivo cuando se sale:
/// al cerrar sesion se llama a [parar] y no queda ni suscripcion ni
/// temporizador. Un temporizador vivo despues de salir es trabajo corriendo
/// sobre una sesion muerta, y en las pruebas es un fallo que no dice nada.
class VigiaDeSincronizacion {
  VigiaDeSincronizacion({
    required Future<void> Function(String motivo, String? avisoDe) ciclo,
    Stream<bool> Function() avisosDeRed = avisosDeConnectivityPlus,
    Stream<void> Function()? avisosDeLaCola,
    Stream<String> Function()? avisosDelServidor,
    Duration periodo = periodoPorDefecto,
    CrearTemporizador crearTemporizador = Timer.periodic,
    LoQueHayAhora loQueHay = noSeSabeLoQueHay,
    Reloj reloj = relojDelAparato,
  }) : _ciclo = ciclo,
       _avisosDeRed = avisosDeRed,
       _avisosDeLaCola = avisosDeLaCola,
       _avisosDelServidor = avisosDelServidor,
       _periodo = periodo,
       _crearTemporizador = crearTemporizador,
       _loQueHay = loQueHay,
       _reloj = reloj;

  /// Cinco minutos, y el numero esta pensado.
  ///
  /// Corto no puede ser: cada tic es una renovacion, una subida y una bajada por
  /// la conexion de alla, y hacerlo cada minuto es gastarle los datos y la
  /// bateria al logistico todo el dia para nada.
  ///
  /// Largo tampoco: esto es la unica red de seguridad de quien trabaja en web,
  /// donde el aviso de connectivity no llega. Media hora significa que alguien
  /// entra en la oficina, deja el dia arriba y se va antes de que suba.
  ///
  /// Cinco minutos son unos noventa ciclos en una jornada de ocho horas, y cada
  /// uno es una bajada por diferencias que casi siempre vuelve vacia.
  static const periodoPorDefecto = Duration(minutes: 5);

  /// DOS MINUTOS EN WEB, y el numero tambien esta pensado.
  ///
  /// En la web no queda ni un gesto para traer el dia a mano: se le quitaron la
  /// pieza del Panel y la franja de estado, porque ahi no hay dia que traer —se
  /// sincroniza solo. Eso sube el liston de este reloj: **es lo unico que trae
  /// los cambios**, y si se queda corto la oficina mira pedidos de hace cinco
  /// minutos sin tener ningun sitio donde darle.
  ///
  /// Los dos motivos que alargan el periodo en la APK aqui no aplican: no hay
  /// bateria que gastar ni datos que pagar, y la conexion no es la del patio de
  /// un almacen en Palma sino la de un navegador en una oficina. Lo que si
  /// aplica es lo contrario — cada tic es una bajada **por diferencias** que
  /// casi siempre vuelve vacia, o sea una peticion pequena.
  ///
  /// Y corto del todo tampoco: cada ciclo enciende el giro y el `actualizando…`
  /// de la barra superior, asi que medio minuto seria un parpadeo constante
  /// arriba — que es justo la queja que se viene a arreglar. Dos minutos son
  /// unos 240 ciclos en una jornada de ocho horas, quietos entre uno y otro.
  static const periodoEnWeb = Duration(minutes: 2);

  /// CUANTO SE DA POR VIVO EL CANAL DESDE LO ULTIMO QUE LLEGO POR EL.
  ///
  /// ## Esto es lo que quita el polling — 29/09/2026
  ///
  /// Jose: «el reloj no lo quiero, la verdad, porque eso es una pinga». Y tenia
  /// razon: con el canal en vivo funcionando, un reloj que pide cada pocos
  /// minutos es preguntar por si acaso algo que ya te van a contar.
  ///
  /// Pero quitarlo del todo deja al aparato **ciego** si el canal se cae, y eso
  /// se vio ese mismo dia: un 401 dejo el canal muerto y el telefono no volvio a
  /// abrirlo en media hora. Sin reloj detras, nadie se entera nunca.
  ///
  /// Asi que el reloj deja de ser el mecanismo y pasa a ser **la red de
  /// seguridad**: mientras se sepa del canal, el tic **no dispara nada**. Con el
  /// canal vivo, un aparato en reposo hace **cero peticiones**.
  ///
  /// ## De donde sale el numero
  ///
  /// No hace falta que el canal mande nada para saber que vive: **el proxy lo
  /// corta cada 300 segundos exactos** —medido en el registro de la api— y cada
  /// reconexion manda `al-volver`. O sea que por el canal llega algo cada cinco
  /// minutos como mucho, aunque no cambie nada en el servidor.
  ///
  /// Seis minutos deja margen a ese corte sin que un canal de verdad muerto
  /// tarde mas de una vuelta en notarse.
  static const elCanalSeDaPorVivo = Duration(minutes: 6);

  final Future<void> Function(String motivo, String? avisoDe) _ciclo;
  final Stream<bool> Function() _avisosDeRed;

  /// Avisa cuando ENTRA algo en la cola, para intentar subirlo ya. `null` en las
  /// pruebas que no van de esto.
  final Stream<void> Function()? _avisosDeLaCola;

  /// LO QUE CAMBIO EN EL SERVIDOR, en cuanto cambia. Trae el TIPO —`pedidos`,
  /// `tablero`, `rutas`…— y con eso se dispara un ciclo.
  ///
  /// Es una mejora sobre el reloj, no un sustituto: donde no hay canal esto es
  /// `null` o un stream vacio, y el temporizador sigue trayendo el trabajo. Un
  /// aviso que no llega no puede dejar a nadie sin sincronizar.
  final Stream<String> Function()? _avisosDelServidor;
  final Duration _periodo;
  final CrearTemporizador _crearTemporizador;
  final LoQueHayAhora _loQueHay;
  final Reloj _reloj;

  StreamSubscription<bool>? _suscripcion;
  StreamSubscription<void>? _suscripcionCola;
  StreamSubscription<String>? _suscripcionServidor;
  Timer? _temporizador;

  /// CUANDO SE SUPO DEL CANAL POR ULTIMA VEZ.
  ///
  /// Se apunta con **cualquier** cosa que llegue por el —un cambio, o el
  /// `al-volver` de cada reconexion—. Ver [elCanalSeDaPorVivo].
  DateTime? _ultimoDelCanal;
  bool _andando = false;
  bool _delante = true;

  bool get andando => _andando;

  /// `true` mientras haya un temporizador vivo. Es lo que mira la prueba de que
  /// al cerrar sesion no queda nada corriendo.
  bool get hayTemporizador => _temporizador != null;

  /// Hay sesion: a vigilar. Llamarlo dos veces no monta dos vigilancias.
  void arrancar() {
    if (_andando) return;
    _andando = true;

    _suscripcion = _avisosDeRed().listen(
      (hayPista) {
        if (!hayPista) return;
        _disparar('volvio la red');
      },
      // Que el plugin no conteste —un destino sin soporte, una prueba sin
      // canales— no puede tumbar la vigilancia: queda el reloj, que es
      // justamente para esto.
      onError: (Object e) =>
          Registro.aviso('vigia: el aviso de red no se pudo escuchar: $e'),
      cancelOnError: false,
    );

    // LO QUE SE ACABA DE HACER SE INTENTA SUBIR YA, sin esperar al reloj.
    //
    // La cola es el aparato de **no tener** senal. Con senal no hay ninguna razon
    // para que arrastrar una tarjeta se quede cinco minutos esperando a que pase
    // el temporizador, ni para que alguien tenga que pulsar nada. Jose:
    // «cuando hay conexion trabajaria sin estar dandole a subir todo el tiempo y
    // hiciera todo solo».
    //
    // Se escucha LA TABLA y no se avisa desde quien encola, a proposito: asi
    // entra cualquier gesto, lo escriba quien lo escriba, y no hace falta que la
    // cola sepa nada del ciclo —que ademas es un ciclo de dependencias, porque el
    // ciclo necesita la cola—.
    //
    // Si no hay red el ciclo falla, la cola se queda entera y el temporizador lo
    // reintenta: exactamente lo de antes, sin nada que perder. Y el candado de
    // «un solo ciclo en vuelo» vive dentro del ciclo, asi que arrastrar doce
    // tarjetas seguidas no lanza doce.
    _suscripcionServidor = _avisosDelServidor?.call().listen(
      // EL TIPO VIAJA, no solo el texto del registro: el ciclo lo necesita para
      // decidir si tiene que pedir los almacenes al momento en vez de esperar a
      // su plazo. Ver `CicloDeSincronizacion.avisoQueFuerzaLosAlmacenes`.
      (tipo) {
        // SE APUNTA QUE EL CANAL VIVE, con cualquier cosa que llegue por el.
        // Es lo que deja al reloj callarse mientras haya canal.
        _ultimoDelCanal = _reloj();
        _disparar('cambió $tipo en el servidor', avisoDe: tipo);
      },
      onError: (Object e) =>
          Registro.aviso('vigia: el canal de eventos se cayó: $e'),
      cancelOnError: false,
    );

    _suscripcionCola = _avisosDeLaCola?.call().listen(
      (_) => _disparar('se hizo algo'),
      onError: (Object e) =>
          Registro.aviso('vigia: no se pudo escuchar la cola: $e'),
      cancelOnError: false,
    );

    _ponerTemporizador();
    Registro.info('vigia: en marcha (cada ${_periodo.inMinutes} min)');
  }

  /// Se cerro la sesion, o se para la aplicacion. **No queda nada vivo.**
  void parar() {
    if (!_andando &&
        _temporizador == null &&
        _suscripcion == null &&
        _suscripcionCola == null &&
        _suscripcionServidor == null) {
      return;
    }
    _andando = false;
    unawaited(_suscripcionCola?.cancel());
    _suscripcionCola = null;
    unawaited(_suscripcionServidor?.cancel());
    _suscripcionServidor = null;
    _quitarTemporizador();
    unawaited(_suscripcion?.cancel());
    _suscripcion = null;
    Registro.info('vigia: parado');
  }

  /// El reloj sólo corre con la aplicacion delante.
  ///
  /// Detras no se gasta: en la APK el sistema congela el proceso de todas formas
  /// y en web la pestanna en segundo plano estrangula los temporizadores. Lo que
  /// no puede pasar es quedarse con un tic a medias de por vida, asi que al
  /// volver **se mira si hace falta** y, si hace falta, se dispara ya.
  ///
  /// ## Por que «si hace falta» y no siempre — 15/09/2026
  ///
  /// Antes volver delante disparaba un ciclo entero, sin mas. Queja de Jose: con
  /// alt-tab la barra superior decia «actualizando…» **sin parar**, porque
  /// cambiar de ventana y volver es un ciclo completo cada vez. En un escritorio
  /// eso pasa treinta veces en una mannana y en la web, con la pestanna al lado
  /// del correo, mas. Un indicador que esta encendido siempre no informa de
  /// nada: se deja de leer, y entonces tampoco se lee el dia que si importa.
  ///
  /// La regla que lo acota, y **vale para los tres destinos**:
  ///
  ///  * **Si queda algo sin subir, se dispara siempre.** Lo unico que se puede
  ///    perder de verdad es el trabajo hecho; una parada marcada a las cuatro
  ///    que nunca subio no se vuelve a hacer sola. Ahi molestar es barato.
  ///  * **Si no, solo cuando lo que hay ya tiene la edad de un periodo.** Ese
  ///    es el umbral y no otro porque es exactamente lo que el reloj iba a hacer
  ///    de todas formas: volver delante no adelanta ningun ciclo, **recupera el
  ///    tic que la pestanna en segundo plano se comio**. Un alt-tab de diez
  ///    segundos no dispara nada; volver despues de la mannana entera sin
  ///    cobertura, si.
  ///  * **Si no se sabe de cuando son los datos, se dispara.** `null` no es
  ///    «hace poco»: es un aparato sin estrenar.
  void enPrimerPlano(bool si) {
    if (_delante == si) return;
    _delante = si;
    if (!_andando) return;
    if (si) {
      _ponerTemporizador();
      unawaited(_alVolverDelante());
    } else {
      _quitarTemporizador();
    }
  }

  /// La pregunta a la base y, si toca, el disparo.
  ///
  /// Nunca lanza: quien llama es un aviso del sistema y no hay nadie esperando
  /// el resultado. Una base que no contesta se trata como «no se sabe», que es
  /// el lado que trabaja de mas.
  Future<void> _alVolverDelante() async {
    EstadoDeLoQueHay hay;
    try {
      hay = await _loQueHay();
    } on Object catch (e) {
      Registro.aviso(
        'vigia: no se pudo mirar que hay, se sincroniza igual: $e',
      );
      hay = EstadoDeLoQueHay.noSeSabe;
    }
    // Entre la pregunta y la respuesta puede haberse cerrado la sesion. Un ciclo
    // disparado aqui correria sobre una sesion muerta.
    if (!_andando || !_delante) return;
    if (!valeLaPenaAlVolver(hay)) {
      Registro.info('vigia: volvio delante y no hacia falta sincronizar');
      return;
    }
    _disparar('la aplicacion volvio delante');
  }

  /// La regla de arriba, suelta y sin nada asincrono, para poder probarla.
  bool valeLaPenaAlVolver(EstadoDeLoQueHay hay) {
    if (hay.sinSubir > 0) return true;
    final cuando = hay.bajadaAt;
    if (cuando == null) return true;
    final edad = _reloj().difference(cuando);
    // Una bajada en el FUTURO es el reloj del aparato movido —se cambia a mano,
    // se va con la bateria, salta de zona horaria (`sincronizacion.md` §1)—, y
    // entonces la edad no se sabe. Se sincroniza, que es el lado seguro.
    if (edad.isNegative) return true;
    return edad >= _periodo;
  }

  void _ponerTemporizador() {
    if (!_delante || _temporizador != null) return;
    _temporizador = _crearTemporizador(_periodo, (_) {
      // EL RELOJ NO DISPARA NADA SI EL CANAL VIVE. Ver [elCanalSeDaPorVivo]:
      // con canal, un aparato en reposo hace CERO peticiones.
      if (_elCanalVive()) {
        Registro.info('tocó el reloj, pero el canal está vivo: no se pide nada');
        return;
      }
      _disparar('toco el reloj');
    });
  }

  /// ¿Se ha sabido del canal hace poco?
  ///
  /// Sin ninguna noticia suya —nunca llego nada— **no** se da por vivo: eso es
  /// justo el caso del aparato al que el canal no le abre, y es cuando mas falta
  /// hace el reloj.
  bool _elCanalVive() {
    final ultimo = _ultimoDelCanal;
    if (ultimo == null) return false;
    return _reloj().difference(ultimo) < elCanalSeDaPorVivo;
  }

  void _quitarTemporizador() {
    _temporizador?.cancel();
    _temporizador = null;
  }

  /// Un intento. Si falla no se marca nada como hecho: se vuelve a la espera.
  ///
  /// No se espera al resultado a proposito —quien dispara es un aviso o un tic,
  /// no hay nadie escuchando— pero el ciclo no lanza nunca, asi que aqui no se
  /// pierde ningun error.
  void _disparar(String motivo, {String? avisoDe}) {
    if (!_andando) return;
    _ciclo(motivo, avisoDe).ignore();
  }
}
