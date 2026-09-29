import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../registro/registro.dart';
import 'eventos.dart' show PulsoDelCanal, avisoDeQueVolvimos;

/// EL CANAL EN VIVO DE LA APK Y DEL ESCRITORIO, por SSE a mano sobre `dio`.
///
/// ## Por que existe, si ya estaba el temporizador
///
/// Jose, 17/09/2026: «pero por q no tiene canal si la idea era eso, para
/// comprobar los lados, q son varios dispositivos q van a estar desconectados y
/// eso debe funcionar sin problema y perfecto».
///
/// El aparato iba a golpe de reloj: **cinco minutos**. Con dos personas mirando
/// el mismo tablero —una arma zonas en el telefono, otra las ve en la web— eso
/// no es trabajar juntas. La web ya tenia canal desde el 17/09; el aparato no, y
/// el aparato es justamente el lado que mas cambia de estado.
///
/// ## Por que a mano y no `EventSource`
///
/// `EventSource` es del navegador. Aqui hay que leer el flujo y trocearlo, y a
/// cambio se gana lo que en la web no se podia: **el token va en la cabecera
/// `Authorization`**. En la web hubo que meterlo en una cookie porque
/// `EventSource` no sabe mandar cabeceras; aqui no hace falta ese rodeo.
///
/// Lo que sale de perder `EventSource` es su reconexion, que la trae de serie.
/// Eso hay que escribirlo, y esta abajo: espera creciente con tope, y **un 403 o
/// un 404 no se reintentan nunca** (`memory/no-revalidar-al-origen-de-verdad.md`:
/// un reintentador contra un rechazo permanente es un bucle, no una defensa).
///
/// ## EL 401 NO ES UN RECHAZO PERMANENTE — 17/09/2026
///
/// Esto trataba el 401 como los otros: cerraba el canal para toda la sesion. Y
/// estaba pasando de verdad — dos `401 GET /api/eventos` en el registro de dos
/// horas—, con la consecuencia de que el aparato se quedaba sin canal hasta que
/// alguien cerrara y volviera a abrir la aplicacion.
///
/// **El token de acceso dura quince minutos y el aparato sabe renovarlo.** Un
/// 401 ahi no dice «tu no entras», dice «ese token ya caduco». Un 403 y un 404 si
/// son permanentes y se siguen tratando como antes.
///
/// Y el consuelo que habia escrito —«queda el temporizador, el reloj sigue
/// trayendo el trabajo»— **es falso para dos pantallas, y lo dice su propio
/// codigo**: Vehiculos (`pantallas/vehiculos/estado/estado_vehiculos.dart`) y
/// Almacenes (`pantallas/almacenes/estado/estado_almacenes.dart`) piden a la red
/// y no viven de la base local, asi que el ciclo no las repinta. Sin canal se
/// quedan clavadas con lo que pintaron al abrirse.
///
/// Renovar se le pide a [renovarSesion], que por dentro es el `Renovador` con su
/// candado de una sola renovacion en vuelo: **aqui no se reimplementa nada de
/// eso**. Y hay DOS frenos para que esto no se convierta en el bucle que la regla
/// de arriba prohibe:
///
///  1. **Una sola renovacion por canal**, como el `reparto.reintentada` del
///     interceptor de sesion. Se suelta cuando llega el `listo`, o sea cuando la
///     sesion nueva ya demostro que vale.
///  2. **Si la sesion no cambio, no se vuelve a pedir.** Si tras renovar el token
///     es el mismo que se comio el 401, se cierra sin gastar ni una peticion mas.
///
/// Y si la renovacion falla —`SesionMuerta`, o la red—, se cierra tambien.
///
/// ## Lo que NO hace
///
/// **No sustituye al temporizador del vigia.** Si el canal no abre, o se cae, o
/// el servidor lo rechaza, esto se calla y cierra el stream: el reloj sigue
/// siendo el suelo y el trabajo llega igual, sólo que mas tarde. Por eso aqui
/// **no se lanza nunca**: un aviso que no llega no puede dejar a nadie sin
/// sincronizar.

/// La primera espera antes de reintentar. Corta a proposito: lo normal es un
/// corte de un segundo, y quien esta delante del tablero no tiene por que
/// esperar medio minuto a que vuelvan los avisos.
const esperaInicialDeEventos = Duration(seconds: 1);

/// El tope de la espera. Un minuto es menos que el temporizador del vigia (cinco
/// minutos en el aparato), asi que ni en el peor caso el canal reconectado llega
/// mas tarde que el reloj que ya habia.
const esperaMaximaDeEventos = Duration(minutes: 1);

/// CUANTOS INTENTOS HAY QUE FINGIR PARA QUE LA ESPERA SEA LA MAXIMA.
///
/// La espera crece al doble desde un segundo con tope de un minuto, asi que a
/// partir del sexto intento ya se espera el tope. Se usa cuando un 401 se repite:
/// ahi no se quiere la espera corta del principio —seria insistirle a un
/// servidor que acaba de decir que no dos veces— sino la larga, sin matar el
/// canal.
const _intentosParaEsperarElTope = 8;

/// CUANTO SILENCIO SE AGUANTA antes de dar la conexion por muerta.
///
/// El servidor manda un latido cada veinte segundos (`api/internal/api/
/// eventos.go`, `latidoSSE`). Tres latidos perdidos son una conexion que ya no
/// existe: pasa con el movil que cambia de antena o sale del wifi, donde el
/// socket se queda abierto del lado del aparato y no llega nunca nada. Sin esto
/// el canal se queda mudo para siempre y nadie se entera, porque un flujo en
/// streaming **no tiene plazo de recepcion**: `dio` sólo se lo aplica a la
/// espera de las cabeceras.
const silencioMaximoDeEventos = Duration(seconds: 60);

/// CUANTOS TEMPORIZADORES TIENE VIVOS EL CANAL ahora mismo.
///
/// Esta en el codigo y no en la prueba porque no hay otra forma de comprobar lo
/// que pide `vigia.parar()`: que al cerrar sesion **no quede nada vivo**. Sin
/// esto, una prueba sólo puede ver que no se reconecta —y no se reconecta
/// tampoco dejandose el temporizador puesto un minuto entero, que es
/// exactamente el fallo que hay que cazar—.
int temporizadoresDeEventos = 0;

Timer _poner(Duration cuanto, void Function() que) {
  temporizadoresDeEventos++;
  return Timer(cuanto, () {
    temporizadoresDeEventos--;
    que();
  });
}

Timer? _apagar(Timer? t) {
  if (t != null && t.isActive) temporizadoresDeEventos--;
  t?.cancel();
  return null;
}

/// La espera del reintento numero [intento] (el primero es el 0).
///
/// Suelta y sin nada asincrono para poder probarla: 1 s, 2 s, 4 s… hasta el
/// tope.
Duration esperaDeReintento(
  int intento, {
  Duration inicial = esperaInicialDeEventos,
  Duration tope = esperaMaximaDeEventos,
}) {
  if (intento <= 0) return inicial > tope ? tope : inicial;
  // El desplazamiento se acota: sin esto, un canal que lleve horas cayendose
  // desborda el entero y la espera sale negativa —o sea, un bucle—.
  final veces = intento > 20 ? 20 : intento;
  final ms = inicial.inMilliseconds * (1 << veces);
  return ms >= tope.inMilliseconds ? tope : Duration(milliseconds: ms);
}

/// Abre el canal y devuelve el TIPO de cada cambio: `pedidos`, `rutas`,
/// `tablero`, `catalogo`, `clientes`.
///
/// Los latidos no salen por aqui, y no por lo que ponia antes —«son del
/// transporte»—: es que **cada aviso que sale de aqui cuesta una bajada**, y un
/// latido cada veinte segundos seria el polling que esto vino a quitar. Lo que
/// hacen es marcar [pulso]: «sigo vivo», sin disparar nada. El `listo` SI sale,
/// como `avisoDeQueVolvimos`.
///
/// [token] se pide AL ABRIR y en cada reintento, no antes: el par de tokens se
/// renueva cada quince minutos, y uno cogido al construir el proveedor estaria
/// caducado a la tercera reconexion.
///
/// Los tres plazos se pueden cambiar sólo para las pruebas: esperar un minuto de
/// verdad a que reintente es una prueba que nadie ejecuta.
Stream<String> escucharEventos(
  String urlBase,
  Future<String?> Function() token, {
  Future<void> Function()? renovarSesion,
  PulsoDelCanal? pulso,
  Duration esperaInicial = esperaInicialDeEventos,
  Duration esperaMaxima = esperaMaximaDeEventos,
  Duration silencioMaximo = silencioMaximoDeEventos,
}) {
  final control = StreamController<String>();

  var vivo = false;
  var intentos = 0;

  /// LOS DOS FRENOS DEL 401. Ver el aviso de arriba del fichero.
  ///
  /// [yaSeRenovoPorUn401] es la marca de «esta apertura ya gasto su renovacion»,
  /// igual que `reparto.reintentada` en `InterceptorSesion`. Sin ella, un
  /// servidor que conteste 401 pase lo que pase hace girar la rueda de renovar
  /// para siempre — despacio, porque cada vuelta es una ida y vuelta a Accesos,
  /// pero para siempre.
  ///
  /// [tokenRechazado] es el otro: si la renovacion devuelve el MISMO token que
  /// se acaba de comer el 401, la sesion no cambio y volver a pedir es regalar
  /// una peticion rechazada. Se corta antes de abrir nada.
  ///
  /// Los dos se sueltan con el `listo`, que es la unica señal de que el canal
  /// esta bueno de verdad.
  var yaSeRenovoPorUn401 = false;
  String? tokenRechazado;

  // ## UN `Dio` POR CONEXION, Y SE CIERRA AL SOLTARLA
  //
  // Comprobado el 17/09/2026 con un servidor de verdad: **cancelar la
  // suscripcion del flujo NO cierra el socket**. `dio` envuelve la respuesta en
  // un `StreamController` suyo, asi que la cancelacion se queda en esa capa y la
  // conexion sigue abierta contra el servidor; el `CancelToken` tampoco la
  // cierra una vez que la respuesta ya llego. Lo unico que la suelta de verdad
  // es cerrar el cliente (`close(force: true)`), y un cliente cerrado no admite
  // peticiones nuevas —el adaptador lanza `StateError`—, asi que cada conexion
  // se lleva el suyo.
  //
  // Sin esto, cerrar sesion dejaba una conexion viva contra el servidor por cada
  // vez que se hubiera entrado, y eso en el aparato es la bateria y el contador
  // de abonados del servidor.
  Dio? cliente;
  CancelToken? corte;
  // Mientras se esta abriendo, el `CancelToken` SI vale: es lo que corta la
  // espera entre pedir y que contesten.
  var abriendo = false;
  StreamSubscription<List<int>>? suscripcion;
  Timer? reintento;
  Timer? vigilanteDeSilencio;

  void pararTemporizadores() {
    reintento = _apagar(reintento);
    vigilanteDeSilencio = _apagar(vigilanteDeSilencio);
  }

  /// Cierra la conexion de ahora. No cierra el stream: puede haber reintento.
  Future<void> cerrarConexion() async {
    vigilanteDeSilencio = _apagar(vigilanteDeSilencio);
    final s = suscripcion;
    suscripcion = null;
    final c = corte;
    corte = null;
    final d = cliente;
    cliente = null;
    // El `CancelToken` sólo se toca si todavia no hay respuesta: cancelarlo
    // despues mete un error en el flujo que ya no escucha nadie.
    if (abriendo && c != null && !c.isCancelled) {
      c.cancel('canal de eventos cerrado');
    }
    abriendo = false;
    await s?.cancel();
    d?.close(force: true);
  }

  /// Se acabo para siempre: ni conexion, ni temporizador, ni stream.
  Future<void> cerrarDelTodo(String motivo) async {
    if (!vivo && control.isClosed) return;
    vivo = false;
    Registro.aviso('canal de eventos: $motivo; se sigue con el temporizador');
    pararTemporizadores();
    await cerrarConexion();
    if (!control.isClosed) await control.close();
  }

  late Future<void> Function() abrir;

  void programarReintento(String motivo) {
    if (!vivo) return;
    final espera = esperaDeReintento(
      intentos,
      inicial: esperaInicial,
      tope: esperaMaxima,
    );
    intentos++;
    Registro.info(
      'canal de eventos: $motivo; se reintenta en ${espera.inMilliseconds} ms',
    );
    reintento = _apagar(reintento);
    reintento = _poner(espera, () {
      reintento = null;
      unawaited(abrir());
    });
  }

  abrir = () async {
    if (!vivo) return;

    // ## EL CANAL NO SE ABRE DESDE UNA PRUEBA CONTRA NADA QUE NO SEA LOCAL
    //
    // `Entorno.apiUrl` trae PRODUCCION como valor por defecto, y la aplicacion
    // entera se monta en los widget tests (`test/widget_test.dart`). Sin esto,
    // ejecutar las pruebas abriria una conexion de verdad contra
    // `reparto.procovar.cloud` desde el ordenador de quien las ejecuta — que es
    // exactamente lo que le costo a la oficina que le bloquearan la IP
    // (`procovar/CLAUDE.md` §2). Las pruebas de este fichero levantan su
    // servidor en `127.0.0.1`, asi que pasan por aqui.
    if (Platform.environment['FLUTTER_TEST'] == 'true' && !_esLocal(urlBase)) {
      await cerrarDelTodo('en pruebas no se abre contra $urlBase');
      return;
    }

    final String? t;
    try {
      t = await token();
    } on Object catch (e) {
      programarReintento('no se pudo leer la sesión ($e)');
      return;
    }
    if (!vivo) return;
    if (t == null || t.isEmpty) {
      // Sin sesion no hay canal, y tampoco hay nada que reintentar: el proveedor
      // se vuelve a construir cuando se entra.
      await cerrarDelTodo('sin sesión todavía');
      return;
    }
    // FRENO 2. La renovacion termino y la sesion es la MISMA que se comio el
    // 401: no hay nada nuevo que presentar, asi que no se gasta ni una peticion.
    if (t == tokenRechazado) {
      // FRENO 2, y aqui NO se gasta ni una peticion: presentar el mismo token que
      // acaban de rechazar es regalar un 401.
      //
      // Pero tampoco se muere el canal —eso era lo de antes y dejaba al aparato
      // ciego toda la jornada—: se mira otra vez dentro de un minuto. El ciclo
      // renueva la sesion cada quince por su cuenta, asi que en cuanto el token
      // cambie esta misma comprobacion deja pasar la apertura, sola y sin que
      // nadie toque nada.
      //
      // O sea que mientras la sesion no cambie esto cuesta **cero peticiones y
      // cero renovaciones**: solo un temporizador que se despierta y se vuelve a
      // dormir.
      intentos = _intentosParaEsperarElTope;
      programarReintento('el 401 se repite y la sesión no ha cambiado');
      return;
    }

    final miCorte = CancelToken();
    corte = miCorte;
    final dio = Dio(
      BaseOptions(
        // Establecer la conexion con la senal de alla tarda; leer no tiene
        // plazo, que es justamente lo que hace falta en un flujo que se pasa
        // veinte segundos callado entre latido y latido.
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: Duration.zero,
      ),
    );
    cliente = dio;
    abriendo = true;
    final Response<ResponseBody> respuesta;
    try {
      respuesta = await dio.get<ResponseBody>(
        '$urlBase/eventos',
        cancelToken: miCorte,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            // AQUI SI SE PUEDEN MANDAR CABECERAS. Es la diferencia con la web,
            // donde `EventSource` obliga a la cookie.
            'Authorization': 'Bearer $t',
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
          },
          // Un flujo en vivo no tiene plazo de recepcion: quien vigila que siga
          // vivo es el latido, abajo.
          receiveTimeout: Duration.zero,
          validateStatus: (codigo) => codigo == 200,
        ),
      );
    } on Object catch (e) {
      abriendo = false;
      if (!vivo) {
        await cerrarConexion();
        return;
      }
      final codigo = e is DioException ? e.response?.statusCode : null;
      if (e is DioException) await _soltarCuerpo(e.response);
      // ## UN 401 SE RENUEVA. UN 403 Y UN 404 NO.
      //
      // El token de acceso dura quince minutos: un 401 aqui es, casi siempre, un
      // token caducado, y eso el aparato lo sabe arreglar. Cerrar el canal por
      // eso deja a Vehiculos y a Almacenes clavadas hasta salir y volver a
      // entrar, porque esas dos no viven de la base y el ciclo no las repinta.
      //
      // Los frenos estan arriba del fichero: una sola renovacion por canal, y ni
      // esa si la sesion no cambia.
      if (codigo == 401) {
        await cerrarConexion();
        if (!vivo) return;
        if (renovarSesion == null) {
          // Nadie nos dio con que renovar (el stub, o una prueba). Entonces si
          // es permanente para nosotros.
          await cerrarDelTodo('401 y aquí no hay con qué renovar la sesión');
          return;
        }
        if (yaSeRenovoPorUn401) {
          // FRENO 1. Ya se renovo una vez en esta tanda y el servidor sigue
          // diciendo que no.
          //
          // ## ESTO MATABA EL CANAL PARA TODA LA SESION, y estaba mal — 29/09/2026
          //
          // Aqui habia un `cerrarDelTodo` con este razonamiento: «la sesion murio
          // de verdad, quien saca a la persona es el ciclo». Medido ese dia en el
          // telefono de Jose, justo despues de reinstalar la APK:
          //
          //     18:59:40  GET /api/eventos  401  0 ms
          //
          // **Y no hubo un segundo intento en media hora.** Un 401 en un mal
          // momento —la sesion recien cargada, una renovacion que se cruza con la
          // del ciclo, la red que se va a mitad— y ese aparato se queda sin
          // tiempo real **hasta que alguien cierre y vuelva a abrir la
          // aplicacion**. Nadie se entera: no hay error en pantalla, y el ciclo
          // sigue trayendo datos, solo que tarde.
          //
          // Y con el arreglo del canal de hoy es peor todavia: sin canal no hay
          // `listo`, y sin `listo` no hay «volvi», asi que las pantallas que
          // piden a la red se quedan clavadas.
          //
          // Un 401 **no es permanente**. Lo dice el aviso de arriba de este
          // fichero y lo dice el propio protocolo: el token de acceso dura quince
          // minutos. Repetirse dos veces seguidas significa «ahora no», no «nunca
          // mas».
          //
          // Asi que se espera lo maximo —un minuto— y se vuelve a intentar CON
          // derecho a renovar otra vez. Un minuto no es insistir: es una peticion
          // por minuto en el peor caso, contra las que costaria tener a un
          // repartidor con la pantalla vieja toda la jornada. El freno sigue
          // haciendo su trabajo dentro de cada tanda, que es para lo que esta.
          // NO se vuelve a renovar aqui, y es a proposito: eso seria una ida y
          // vuelta a Accesos por minuto, por aparato, durante toda la jornada.
          // **Quien recupera esto es el ciclo**, que renueva la sesion por su
          // cuenta cada quince minutos. Cuando lo haga, el token sera otro y el
          // freno de abajo dejara pasar la apertura sola.
          await cerrarConexion();
          if (!vivo) return;
          tokenRechazado = t;
          intentos = _intentosParaEsperarElTope;
          programarReintento('401 otra vez con la sesión ya renovada');
          return;
        }
        yaSeRenovoPorUn401 = true;
        tokenRechazado = t;
        try {
          // El candado de «una sola renovacion en vuelo» es del `Renovador` y
          // aqui NO se reimplementa: si el ciclo esta renovando en este mismo
          // instante, esta llamada reutiliza su resultado.
          await renovarSesion();
        } on Object catch (e) {
          await cerrarDelTodo('el 401 no se pudo renovar ($e)');
          return;
        }
        if (!vivo) return;
        Registro.info(
          'canal de eventos: 401, sesión renovada; se vuelve a abrir',
        );
        // Sin espera: el token nuevo ya esta en la mano y la espera creciente
        // sirve para un servidor caido, que no es el caso.
        unawaited(abrir());
        return;
      }
      // 403, 404 —la direccion no es esa—, y cualquier otro 4xx: el servidor ya
      // dijo que no y volver a preguntarle cada segundo no lo va a cambiar. Lo
      // que hace es una tanda de peticiones rechazadas durante toda la jornada.
      // Un 5xx si se reintenta: eso es el servidor reiniciandose, y vuelve.
      if (codigo != null && codigo >= 400 && codigo < 500) {
        await cerrarDelTodo('el servidor rechaza el canal ($codigo)');
        return;
      }
      await cerrarConexion();
      programarReintento('no se pudo abrir ($e)');
      return;
    }
    abriendo = false;
    if (!vivo) {
      await cerrarConexion();
      return;
    }

    final flujo = respuesta.data;
    if (flujo == null) {
      await cerrarConexion();
      programarReintento('respuesta sin cuerpo');
      return;
    }

    // ## EL TROCEADO
    //
    // Lo que llega son TROZOS DE RED, no lineas: un trozo puede acabar en mitad
    // de `event: cam` y el resto venir en el siguiente. Por eso se acumula hasta
    // el salto de linea en vez de tratar cada trozo como una linea — que es el
    // fallo clasico de los SSE escritos a mano y sólo se ve con la conexion
    // mala, que es la de alla.
    //
    // Se acumulan BYTES y se corta por el 10 (`\n`): un salto de linea nunca
    // aparece dentro de un caracter UTF-8 de varios bytes, asi que cortar aqui
    // no parte ninguna letra. Cortar por texto si las parte.
    final resto = <int>[];
    var evento = '';
    final datos = StringBuffer();

    void reiniciarVigilante() {
      vigilanteDeSilencio = _apagar(vigilanteDeSilencio);
      if (silencioMaximo <= Duration.zero) return;
      vigilanteDeSilencio = _poner(silencioMaximo, () {
        vigilanteDeSilencio = null;
        unawaited(
          cerrarConexion().then((_) {
            programarReintento('sin latido en ${silencioMaximo.inSeconds} s');
          }),
        );
      });
    }

    void cerrarTrama() {
      final queEs = evento;
      final cuerpo = datos.toString();
      evento = '';
      datos.clear();
      switch (queEs) {
        case 'cambio':
          // Lo unico que le dice algo a una pantalla. Se manda el tipo tal cual
          // lo entiende `_tipoDe`, igual que en la web: un `data` que no se
          // entiende sale como cadena vacia y NO se descarta, porque el cambio
          // en el servidor paso igual y quien escucha va a pedir su lista de
          // todas formas.
          control.add(_tipoDe(cuerpo));
        case 'listo':
          // La conexion esta buena de verdad: desde aqui se vuelve a contar la
          // espera desde cero. Se hace con el `listo` y no con el 200 a
          // proposito — un proxy que acepta y no entrega nada devuelve 200
          // tambien, y ahi lo que hace falta es que la espera siga creciendo.
          intentos = 0;
          // Y SALE HACIA LAS PANTALLAS — 29/09/2026.
          //
          // Aqui ponia que el `listo` «no le dice nada a una pantalla». Si le
          // dice: **estuve desconectado**. Lo que pasara en el servidor mientras
          // tanto no lo vio nadie, y sin esto la pantalla se queda con lo de
          // antes para siempre. El porque entero, en `avisoDeQueVolvimos`.
          control.add(avisoDeQueVolvimos);
          // Y con el `listo` se sueltan los dos frenos del 401: la sesion que
          // tenemos en la mano acaba de demostrar que vale, asi que el proximo
          // 401 —dentro de quince minutos— vuelve a tener derecho a su
          // renovacion.
          yaSeRenovoPorUn401 = false;
          tokenRechazado = null;
          Registro.info('canal de eventos: abierto');
        case 'sin-vivo':
          // El servidor se esta parando. Cerrara el, y el reintento con espera
          // le da tiempo a volver.
          Registro.info('canal de eventos: el servidor se está parando');
        case '':
          break;
        default:
          // Un evento que esta version no conoce se ignora: el contrato dice que
          // anadir tipos no rompe a nadie.
          break;
      }
    }

    void linea(String cruda) {
      final l = cruda.endsWith('\r')
          ? cruda.substring(0, cruda.length - 1)
          : cruda;
      // Linea en blanco: se acabo la trama.
      if (l.isEmpty) {
        cerrarTrama();
        return;
      }
      // Un comentario SSE. El latido es esto (`: latido`) y por eso NO sale por
      // el stream: sirve para que el proxy no corte la conexion por callada, y
      // no le dice nada a ninguna pantalla.
      if (l.startsWith(':')) return;
      final corte = l.indexOf(':');
      final campo = corte < 0 ? l : l.substring(0, corte);
      var valor = corte < 0 ? '' : l.substring(corte + 1);
      if (valor.startsWith(' ')) valor = valor.substring(1);
      switch (campo) {
        case 'event':
          evento = valor;
        case 'data':
          if (datos.isNotEmpty) datos.write('\n');
          datos.write(valor);
        default:
          // `id`, `retry` y lo que venga: no se usan aqui.
          break;
      }
    }

    suscripcion = flujo.stream.listen(
      (trozo) {
        // EL PULSO SE MARCA CON **CUALQUIER BYTE**, no con los avisos — 29/09/2026.
        //
        // Aqui es donde se sabe de verdad que el canal esta: si llegan bytes, hay
        // socket y hay servidor al otro lado. El latido de cada veinte segundos
        // (`api/internal/api/eventos.go`, `latidoSSE`) entra por aqui igual que un
        // `cambio`, y es justamente el que faltaba.
        //
        // Va en el mismo sitio que el vigilante del silencio a proposito: son la
        // misma pregunta contestada en los dos sentidos —«¿llego algo?»—, y
        // tenerlas separadas seria tener dos ideas de cuando vive el canal.
        //
        // Lo que costaba no tenerlo: el vigia solo se enteraba del canal cuando
        // llegaba un aviso PARA UNA PANTALLA, asi que un canal sano por el que no
        // habia cambiado nada en seis minutos se leia como muerto y el reloj pedia
        // la vuelta entera. El detalle, en `PulsoDelCanal`.
        pulso?.latio();
        reiniciarVigilante();
        for (final b in trozo) {
          if (b == 10) {
            linea(utf8.decode(resto, allowMalformed: true));
            resto.clear();
          } else {
            resto.add(b);
          }
        }
      },
      onError: (Object e) {
        // Se cayo la red. Nunca sale por el stream: quien escucha no puede hacer
        // nada con esto, y un error en el stream del vigia es ruido en el
        // registro cada vez que el ascensor se come la cobertura.
        unawaited(
          cerrarConexion().then((_) {
            if (vivo) programarReintento('se cortó ($e)');
          }),
        );
      },
      onDone: () {
        unawaited(
          cerrarConexion().then((_) {
            if (vivo) programarReintento('el servidor cerró el canal');
          }),
        );
      },
      cancelOnError: true,
    );
    reiniciarVigilante();
  };

  control.onListen = () {
    vivo = true;
    unawaited(abrir());
  };

  // AL CERRAR SESION NO QUEDA NADA VIVO: ni la conexion, ni el temporizador del
  // reintento, ni el vigilante del latido, ni el cliente HTTP con su socket
  // guardado. Un temporizador vivo despues de salir es trabajo corriendo sobre
  // una sesion muerta (`vigia.parar()`).
  control.onCancel = () async {
    vivo = false;
    pararTemporizadores();
    await cerrarConexion();
  };

  return control.stream;
}

bool get hayCanalDeEventos => true;

/// `true` si la direccion apunta a esta misma maquina. Ver el aviso de arriba.
bool _esLocal(String urlBase) {
  final u = Uri.tryParse(urlBase);
  if (u == null) return false;
  return u.host == '127.0.0.1' || u.host == 'localhost' || u.host == '::1';
}

/// Vacia el cuerpo de una respuesta rechazada. En streaming `dio` no lo lee, y
/// un cuerpo sin leer es un socket que se queda cogido.
Future<void> _soltarCuerpo(Response<Object?>? respuesta) async {
  final cuerpo = respuesta?.data;
  if (cuerpo is! ResponseBody) return;
  try {
    await cuerpo.stream.drain<void>();
  } on Object {
    // Da igual por que no se pudo vaciar: se estaba tirando.
  }
}

/// El tipo que viene dentro del `data`. Si no se entiende, se devuelve vacio y
/// quien escuche decidira —un aviso raro no puede tumbar la pantalla—.
String _tipoDe(String datos) {
  try {
    final m = jsonDecode(datos);
    if (m is Map && m['tipo'] is String) return m['tipo'] as String;
  } on Object {
    // Un cuerpo que no es JSON es un aviso perdido, no un fallo.
  }
  return '';
}
