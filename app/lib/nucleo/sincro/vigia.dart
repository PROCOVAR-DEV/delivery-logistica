import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../red/eventos.dart' show PulsoDelCanal;
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
    PulsoDelCanal? pulso,
    Duration periodo = periodoPorDefecto,
    CrearTemporizador crearTemporizador = Timer.periodic,
    LoQueHayAhora loQueHay = noSeSabeLoQueHay,
    Reloj reloj = relojDelAparato,
  }) : _ciclo = ciclo,
       _avisosDeRed = avisosDeRed,
       _avisosDeLaCola = avisosDeLaCola,
       _avisosDelServidor = avisosDelServidor,
       _pulso = pulso,
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

  /// DOS MINUTOS EN WEB. El numero se queda; **lo que significa ha cambiado**.
  ///
  /// ## Se eligio para otra cosa — y por eso hay que releerlo, 29/09/2026
  ///
  /// Aqui ponia que este reloj «es lo unico que trae los cambios» en la web, y
  /// eso ya no es verdad: lo que los trae es el canal en vivo, y desde
  /// [elCanalSeDaPorVivo] el tic **no dispara nada mientras el canal viva**. O
  /// sea que con el canal sano estos dos minutos cuestan exactamente cero
  /// peticiones: una linea en el registro y volver a dormir.
  ///
  /// Asi que este periodo ya no decide cada cuanto se pide. Decide **cuanto
  /// tarda en volver el trabajo cuando el canal esta muerto de verdad**, que es
  /// lo unico para lo que queda el reloj.
  ///
  /// ## Y para ESO dos minutos siguen siendo el numero
  ///
  /// Con el canal caido la web no tiene ninguna otra forma de enterarse: no hay
  /// aviso de `connectivity_plus` que valga en un navegador y no queda ni un
  /// gesto para traer el dia a mano —se le quitaron la pieza del Panel y la
  /// franja de estado, porque ahi no hay dia que traer—. La cuenta entera de lo
  /// que se puede quedar viendo alguien es **el plazo de [elCanalSeDaPorVivo]
  /// mas un periodo**: 6 + 2 = **ocho minutos** en el peor caso. Con los cinco de
  /// la APK serian once, y once minutos de tablero viejo en la oficina es
  /// justamente la queja de la que salio todo esto.
  ///
  /// Mas corto tampoco: cada ciclo enciende el giro y el `actualizando…` de la
  /// barra superior, y con el canal caido eso si sale en cada tic. Un minuto
  /// seria el doble de peticiones contra un servidor que, si el canal no abre,
  /// probablemente ya tenga algun problema.
  ///
  /// Lo que costaba antes, y ya no: 240 ciclos en una jornada de ocho horas,
  /// **todos**, con el canal bueno o malo. Hoy, con el canal bueno, cero.
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
  /// No hace falta que el canal mande ningun **cambio** para saber que vive, y
  /// eso se sabe por dos caminos distintos segun el destino:
  ///
  ///  * **APK y escritorio**: el servidor late cada **20 s** (`latidoSSE`) y ese
  ///    latido marca el pulso (`PulsoDelCanal`). Seis minutos son dieciocho
  ///    latidos: si no llego ni uno, ese canal no existe.
  ///  * **La web**: `EventSource` tira los latidos —son comentarios SSE— y alli
  ///    lo que marca el pulso es el `listo` de cada reconexion. **El proxy corta
  ///    el canal cada 300 s exactos** —medido en el registro de la api—, asi que
  ///    llega uno cada cinco minutos como mucho. El porque de no inventarse un
  ///    pulso con `readyState`, en `eventos_web.dart`.
  ///
  /// Seis minutos es el numero que le deja margen al peor de los dos —los 300 s
  /// del proxy, mas lo que tarde en reconectar una linea mala— sin que un canal
  /// de verdad muerto tarde mas de una vuelta en notarse.
  ///
  /// ## Lo que se apuntaba antes, y por que no bastaba — 29/09/2026
  ///
  /// Esto se apuntaba **solo con los avisos que le llegan a una pantalla**: un
  /// `cambio` o el `al-volver`. Con eso, un canal perfectamente sano por el que no
  /// habia cambiado nada en seis minutos se leia como canal muerto y el reloj
  /// pedia la vuelta entera — o sea que el polling seguia ahi, solo que mas
  /// espaciado. Medido en la web ese dia, clavado al periodo: 20:07:42 → 20:09:40
  /// → 20:11:41 → 20:13:40.
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

  /// EL LATIDO DEL CANAL, que **no** viaja por [_avisosDelServidor] — 29/09/2026.
  ///
  /// Es la otra mitad de [elCanalSeDaPorVivo], y sin ella el reloj seguia pidiendo
  /// contra un canal sano: por el stream de arriba sólo llega lo que le dice algo
  /// a una pantalla —un `cambio`, o el `al-volver` de cada reconexion—, asi que un
  /// canal por el que no ha cambiado nada en seis minutos se leia como muerto.
  ///
  /// El canal late cada veinte segundos. Ese latido **no puede** meterse por el
  /// stream de los avisos: alli cada aviso cuesta un ciclo de sincronizacion, un
  /// `GET /api/board` por tablero abierto y la flota por cada pantalla de
  /// vehiculos, o sea una bajada cada veinte segundos — lo contrario de lo que se
  /// viene a arreglar. Por eso llega por aqui, donde no hay nada que disparar: el
  /// transporte apunta la hora y ya. Todo el detalle, en [PulsoDelCanal].
  ///
  /// Es opcional: sin el, el vigia se queda con lo que ya sabia y el reloj se
  /// comporta como antes. Peor, pero nunca ciego.
  final PulsoDelCanal? _pulso;

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
    final ultimo = _ultimaSenalDelCanal();
    if (ultimo == null) return false;
    return _reloj().difference(ultimo) < elCanalSeDaPorVivo;
  }

  /// LA ULTIMA SEÑAL DEL CANAL, venga por donde venga.
  ///
  /// Son dos fuentes porque son dos caminos distintos y ninguno sobra:
  ///
  ///  * [_pulso] — **cualquier** cosa que llegue por el canal, latido incluido.
  ///    Es la buena, y es la que faltaba.
  ///  * [_ultimoDelCanal] — lo que llega por el stream de los avisos. Se sigue
  ///    apuntando porque quien monte el vigia sin pasarle el pulso —una prueba, un
  ///    destino sin canal— no puede quedarse peor que antes.
  ///
  /// Se coge la mas reciente de las dos: las dos dicen lo mismo —«se supo del
  /// canal»— y quedarse con la vieja seria darlo por muerto teniendolo vivo.
  DateTime? _ultimaSenalDelCanal() {
    final delPulso = _pulso?.ultimo;
    final delStream = _ultimoDelCanal;
    if (delPulso == null) return delStream;
    if (delStream == null) return delPulso;
    return delPulso.isAfter(delStream) ? delPulso : delStream;
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
