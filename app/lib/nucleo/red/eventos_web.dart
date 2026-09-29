import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../registro/registro.dart';
import 'eventos.dart' show PulsoDelCanal, avisoDeQueVolvimos;

/// EL CANAL EN VIVO DE LA WEB, por `EventSource`.
///
/// Se usa el del navegador y no una lectura en streaming a mano porque **el
/// navegador ya sabe reconectar**: si la conexion se cae, vuelve a abrirla sola
/// con su espera creciente. Escribir eso a mano es reescribir algo que ya
/// funciona, y peor.
///
/// `withCredentials` va puesto: en la web la sesion es la cookie del acceso
/// unico, no un token guardado (`docs/identidad.md`). Sin eso el servidor
/// contesta 401 y el canal no abre.
///
/// ## UN 401 NO MATA EL CANAL PARA TODA LA SESION — 17/09/2026
///
/// Esto cerraba el control en cuanto el navegador daba la conexion por fallida, y
/// de ahi no se volvia: el canal se acababa para lo que quedara de pestaña. Y
/// pasa de verdad — hay `401 GET /api/eventos` en el registro de produccion—,
/// porque el token de acceso dura **quince minutos** y aqui tambien se guarda el
/// par (`almacen_sesion_web.dart`), asi que caduca igual que en la APK.
///
/// Se renueva una vez y se vuelve a abrir, con los mismos dos frenos que la APK
/// (ver `eventos_io.dart`): **una sola renovacion por canal**, y **ninguna si la
/// sesion no cambia**.
///
/// ## AQUI EL LATIDO NO SE PUEDE VER, y hay que saberlo — 29/09/2026
///
/// El servidor manda un latido cada veinte segundos, pero lo manda como
/// **comentario SSE** (`: latido`, en `api/internal/api/eventos.go`), y
/// `EventSource` **descarta los comentarios**: no hay evento, no hay retrollamada,
/// no hay forma de pedirlos. Asi que aqui el [PulsoDelCanal] no se puede marcar
/// con el latido como en la APK; se marca con lo que SI se ve: el `listo` de cada
/// (re)conexion y cada `cambio`.
///
/// **Y no se inventa uno con `readyState`**, que era lo facil. Un `EventSource`
/// medio muerto —el socket que se queda abierto de este lado y por el que no
/// llega nada, el portatil que sale de la suspension, el NAT que tira el flujo sin
/// avisar— se queda en `OPEN` **para siempre**: el navegador no le pone plazo
/// ninguno. Un pulso sacado de ahi diria «el canal vive» eternamente, el reloj se
/// callaria eternamente, y la web se quedaria **ciega sin ninguna forma de
/// volver** — porque aqui no hay aviso de `connectivity_plus` que sirva ni un
/// gesto para traer el dia a mano. El reloj usa una peticion HTTP aparte, que es
/// justo lo que sigue funcionando cuando ese socket ya no.
///
/// Lo que sostiene el silencio del reloj en la web es entonces el `listo`: **el
/// proxy corta el canal cada 300 s exactos** —medido en el registro de la api— y
/// cada reconexion trae uno. Eso cabe de sobra en los seis minutos de
/// `VigiaDeSincronizacion.elCanalSeDaPorVivo`. Si algun dia ese corte se alarga, la
/// web vuelve a pedir por el reloj: molesta, pero es el lado seguro del fallo —
/// pide de mas, no se queda ciega—.
///
/// ## Lo que aqui NO se puede saber, y por que aun asi compensa
///
/// `EventSource` no dice el codigo. Un `readyState == CLOSED` puede ser un 401 o
/// un `Content-Type` que no es `text/event-stream`. Con lo de abajo, el caso del
/// `Content-Type` cuesta **una renovacion y una peticion** de mas y despues se
/// cierra igual que antes; el caso del 401 —el que esta pasando— recupera el
/// canal. Y el canal importa: Vehiculos y Almacenes piden a la red y no viven de
/// la base local, asi que sin canal se quedan clavadas con lo que pintaron al
/// abrirse, temporizador o no.
/// A partir de cuantos fallos seguidos se espera el minuto entero.
///
/// Es el mismo numero que la APK (`eventos_io.dart`): 1, 2, 4, 8, 16, 32, 64 ->
/// tope. Se nombra para poder saltar directo al tope cuando ya se sabe que
/// insistir rapido no va a servir de nada — un rechazo con la sesion sin cambiar.
const _intentosParaEsperarElTope = 8;

Stream<String> escucharEventos(
  String urlBase,
  Future<String?> Function() token, {
  Future<void> Function()? renovarSesion,
  PulsoDelCanal? pulso,
}) {
  final control = StreamController<String>();
  web.EventSource? fuente;

  // Los dos frenos. Se sueltan con el `listo`, que es la unica señal de que la
  // sesion que llevamos vale de verdad.
  var yaSeRenovoPorUn401 = false;
  String? tokenRechazado;

  late Future<void> Function() abrir;

  /// Cuantas veces seguidas no se ha podido abrir. Se pone a cero con el `listo`.
  var intentos = 0;
  Timer? espera;

  // AQUI VIVIA `cerrarDelTodo`, Y YA NO EXISTE — 29/09/2026.
  //
  // Cerraba el canal para toda la pestaña, y **no queda ni un camino que haga
  // eso**: lo unico que lo cierra ahora es que se vaya el ultimo oyente
  // (`onCancel`), que es el cierre legitimo. Todo lo demas reintenta.
  //
  // Se quita entero en vez de dejarlo sin usar porque una funcion que cierra el
  // canal, ahi a mano, es una invitacion a volver a llamarla la proxima vez que
  // alguien vea un rechazo raro. El porque esta en `programarReintento`.

  /// VUELVE A INTENTARLO, CON ESPERA CRECIENTE Y TOPE DE UN MINUTO.
  ///
  /// # POR QUE ESTO NO PUEDE CERRAR EL CANAL PARA SIEMPRE — 29/09/2026
  ///
  /// Aqui se llamaba a [cerrarDelTodo] y **se acababa el canal para toda la
  /// pestaña**. Sin error en consola, sin aviso en pantalla y sin un solo
  /// reintento: la web se quedaba muda y nadie se enteraba hasta que alguien
  /// recargaba.
  ///
  /// Pasó esa misma noche, y esta en el registro del servidor:
  ///
  /// ```
  /// 21:30:45  GET /api/eventos  200
  /// 21:30:47  GET /api/eventos  200
  /// 21:30:50  GET /api/eventos  401   <- se murio aqui
  ///           ... CINCO MINUTOS SIN UNA SOLA PETICION ...
  /// 21:35:49  GET /api/eventos  200
  /// ```
  ///
  /// Jose creo una zona desde el telefono a las **21:32:10**, o sea dentro de ese
  /// agujero, y en la web no aparecio. No es que el aviso llegara tarde: **no
  /// habia nadie escuchando**. Sus palabras: «la aplicacion hace cosas y no sale
  /// en la web».
  ///
  /// La APK ya lo tenia arreglado desde esa misma tarde (`eventos_io.dart`,
  /// `programarReintento`) y **este lado se quedo con el camino viejo**. Es el
  /// mismo fallo dos veces, y por eso ahora los dos hacen lo mismo.
  ///
  /// # Y por que se reintenta aunque pueda ser un 403
  ///
  /// `EventSource` **no dice el codigo**: un `CLOSED` puede ser un 401, un 403 o
  /// un `Content-Type` que no es `text/event-stream`. Antes eso se usaba para
  /// justificar cerrar —«si no es un 401, insistir no arregla nada»—, y el precio
  /// de equivocarse resulto ser mucho mas caro que el de insistir: con el tope de
  /// un minuto, un 403 cuesta sesenta peticiones a la hora, y un canal muerto
  /// cuesta que la oficina entera no vea lo que hace el reparto.
  void programarReintento(String motivo) {
    if (control.isClosed) return;
    espera?.cancel();
    // 1, 2, 4, 8… segundos, con tope de un minuto. El mismo perfil que la APK.
    final segundos = intentos >= _intentosParaEsperarElTope
        ? 60
        : 1 << intentos;
    final cuanto = Duration(seconds: segundos.clamp(1, 60));
    intentos++;
    Registro.aviso(
      'canal de eventos: $motivo; se reintenta en ${cuanto.inSeconds} s',
    );
    espera = Timer(cuanto, () {
      espera = null;
      if (!control.isClosed) unawaited(abrir());
    });
  }

  abrir = () async {
    // EL TOKEN VA POR COOKIE, no por la direccion.
    //
    // `EventSource` no sabe mandar cabeceras, asi que no hay `Authorization`
    // posible. Quedaban dos formas y esta es la buena: el token en la URL
    // (`?token=…`) acaba escrito en el registro del servidor, en el del proxy y
    // en el historial del navegador, y ahi se queda; la cookie no sale en
    // ninguno de los tres.
    //
    // Se llama `token` porque es el nombre que ya lee `auth.DelaPeticion` del
    // reparto — la misma puerta que usan la APK y la web, sin inventar otra.
    //
    // ## SIN TOKEN **TAMBIEN** SE ABRE — 29/09/2026, y hasta hoy no
    //
    // Aqui habia un `if (t == null) { no se abre; return; }` con un comentario
    // que daba por hecho que «en la web el token ya vive en localStorage». **Eso
    // sólo es verdad por la puerta de respaldo** (usuario y contraseña). Por la
    // puerta normal se entra por Accesos, y esa sesion es una cookie `httpOnly`
    // que el JavaScript no puede leer: `localStorage` esta VACIO, `token()`
    // devuelve `null`, y ese `if` mataba el canal **siempre**, ademas cerrando el
    // control para toda la pestaña.
    //
    // O sea que la web nunca abrio el canal. Ni una vez. Medido el 29/09/2026 en
    // produccion por tres caminos: `/api/eventos` no aparece en el panel de red,
    // `performance.getEntriesByType('resource')` no tiene ni una entrada, y un
    // espia puesto sobre el constructor `EventSource` registro **cero intentos**
    // en hora y media. Cero errores en consola: fallaba en silencio absoluto, y
    // lo unico que traia cambios era el temporizador — el «pollings» que este
    // trabajo venia justamente a quitar.
    //
    // Y lo que duele: **no hacia ninguna falta ese token**. El servidor acepta
    // `Authorization: Bearer` **o la cookie `token`** (`internal/auth/auth.go`,
    // `DelaPeticion`), y esa cookie es la que ya deja puesta el login unico
    // (`internal/api/auth_web.go`, `cookieDeLaWeb`). Con `withCredentials: true`
    // el navegador la manda solo. Estaba todo puesto; se plantaba en el `if` de
    // antes de intentarlo.
    //
    // Asi que el token, si lo hay, se escribe en la cookie como siempre —es la
    // puerta de respaldo, donde no hay cookie de Accesos— y si no lo hay **se
    // abre igual** y que conteste el servidor. Un 401 se sigue tratando abajo
    // con sus dos frenos; lo que no puede pasar es no preguntar.
    if (control.isClosed) return;
    final t = await token();
    final hayToken = t != null && t.isNotEmpty;
    // FRENO 2: la renovacion no cambio la sesion, asi que no se insiste.
    //
    // Sólo aplica **cuando hay token que comparar**. Sin el, `t` y
    // `tokenRechazado` son los dos `null` y el freno se dispararia solo en el
    // segundo intento, que es cambiar un canal muerto por otro.
    if (hayToken && t == tokenRechazado) {
      // FRENO 2: la renovacion no cambio la sesion, asi que no se insiste **con
      // peticiones seguidas** — pero tampoco se cierra. Se espera al tope y se
      // vuelve a probar: mientras el token no cambie no cuesta nada, y el dia que
      // cambie el canal vuelve solo.
      intentos = _intentosParaEsperarElTope;
      programarReintento('el canal se rechaza y la sesión no ha cambiado');
      return;
    }
    if (hayToken) {
      web.document.cookie = 'token=$t; Path=/; Secure; SameSite=Strict';
    } else {
      Registro.info(
        'canal de eventos: sin token guardado; se abre con la cookie del '
        'acceso único',
      );
    }

    try {
      fuente = web.EventSource(
        '$urlBase/eventos',
        web.EventSourceInit(withCredentials: true),
      );
    } on Object catch (e) {
      // Que el canal no abra NO puede dejar a nadie sin sincronizar: queda el
      // temporizador, que es lo que habia antes de esto.
      Registro.aviso('no se pudo abrir el canal de eventos: $e');
      unawaited(control.close());
      return;
    }

    // EL `listo` SI SE REENVIA — 29/09/2026, y hasta ese dia no.
    //
    // Sirve para dos cosas. La de siempre: es la señal de que la sesion que
    // llevamos vale, y con ella se sueltan los dos frenos del 401, igual que en
    // la APK. Y la que faltaba: **decirle a las pantallas que estuvimos
    // desconectados**.
    //
    // Aqui ponia que el `listo` es del transporte y no le dice nada a una
    // pantalla. Le dice lo mas importante de todo: lo que pasara en el servidor
    // mientras el canal estuvo caido **no lo vio nadie**. En esta web eso es
    // especialmente caro: el canal tarda ~50 s en abrirse desde que carga la
    // pantalla, y el proxy lo corta cada 300 s. El porque entero y lo que se
    // midio, en `avisoDeQueVolvimos`.
    fuente!.addEventListener(
      'listo',
      (web.Event _) {
        // Se supo del canal. En la web esto es lo mas parecido a un latido que
        // hay —el de verdad lo tira `EventSource`—, y llega cada vez que el proxy
        // corta y el navegador reconecta.
        pulso?.latio();
        intentos = 0;
        yaSeRenovoPorUn401 = false;
        tokenRechazado = null;
        if (!control.isClosed) control.add(avisoDeQueVolvimos);
      }.toJS,
    );

    // EL LATIDO, que desde el 29/09/2026 SI se ve desde aqui.
    //
    // Salia como comentario SSE (`: latido`) y `EventSource` descarta los
    // comentarios por especificacion, asi que en la web era invisible. Ahora el
    // servidor lo manda como evento con nombre —`event: latido` con su
    // `data: {}`, que una trama con el buffer de datos vacio el navegador
    // tampoco la entrega— y aqui se escucha igual que en la APK.
    //
    // **Marca el pulso y NO se reenvia.** Un latido no es un cambio: si saliera
    // por el stream costaria un ciclo, un `GET /api/board` por cada tablero
    // abierto y la flota por cada pantalla de vehiculos, cada veinte segundos.
    // Eso es peor que el temporizador que esto viene a quitar.
    //
    // El nombre esta atado del otro lado por `TestElNombreDelLatidoNoSeRenombraSolo`
    // (`api/internal/api/eventos_test.go`), que fija el literal y la trama entera
    // y nombra este fichero en su mensaje. Sin esa prueba, renombrarlo alli
    // dejaba toda la api en verde y la web muda otra vez.
    fuente!.addEventListener(
      'latido',
      (web.Event _) {
        pulso?.latio();
      }.toJS,
    );

    // El `cambio` es el unico que le dice algo a una pantalla. El `listo` del
    // principio y el latido son del transporte: sirven para que el navegador
    // de la conexion por abierta y para que un proxy no la cierre por callada,
    // y no se reenvian.
    fuente!.addEventListener(
      'cambio',
      (web.Event e) {
        pulso?.latio();
        final datos = (e as web.MessageEvent).data.dartify();
        control.add(_tipoDe(datos));
      }.toJS,
    );

    fuente!.onerror = (web.Event _) {
      // ## Hay DOS errores distintos y se parecen en nada
      //
      // Un corte de red: `readyState` queda en `CONNECTING` y **el navegador
      // reconecta solo**, con su espera creciente. Ahi no hay nada que hacer.
      //
      // Un 401, o un `Content-Type` que no es `text/event-stream`: por la
      // especificacion de HTML el navegador hace *fail the connection* —
      // `readyState` pasa a `CLOSED` y **no reintenta nunca mas**. Sin
      // distinguirlo, el `StreamController` se quedaba abierto y muerto: no
      // emitia, no cerraba, nadie se enteraba, y la aplicacion caia al
      // temporizador en silencio. El comentario decia que reconectaba solo, y
      // para ese caso era mentira.
      if (fuente?.readyState == web.EventSource.CLOSED) {
        // Aqui es donde caia el 401. Se renueva UNA vez y se vuelve a abrir; si
        // vuelve a caer, ya si se cierra para siempre.
        fuente?.close();
        fuente = null;
        if (renovarSesion == null) {
          programarReintento('el navegador cerró el canal y no hay con qué renovar');
          return;
        }
        if (yaSeRenovoPorUn401) {
          // FRENO 1: ya gasto su renovacion y sigue sin abrir. Puede ser un 403,
          // un 404 o una cabecera mala — algo que renovar no arregla—, asi que no
          // se gasta otra renovacion. **Pero no se cierra**: se espera al tope de
          // un minuto y se vuelve a probar, que es lo que hace la APK.
          intentos = _intentosParaEsperarElTope;
          programarReintento('el canal se rechaza con la sesión ya renovada');
          return;
        }
        yaSeRenovoPorUn401 = true;
        tokenRechazado = t;
        unawaited(
          renovarSesion()
              .then((_) async {
                if (control.isClosed) return;
                Registro.info(
                  'canal de eventos: rechazado, sesión renovada; se vuelve a '
                  'abrir',
                );
                await abrir();
              })
              .catchError((Object _) async {
                programarReintento('no se pudo renovar la sesión');
              }),
        );
        return;
      }
      Registro.info('canal de eventos: corte, el navegador reconecta solo');
    }.toJS;
  };

  control.onListen = () => unawaited(abrir());

  control.onCancel = () {
    espera?.cancel();
    espera = null;
    fuente?.close();
    fuente = null;
  };

  return control.stream;
}

bool get hayCanalDeEventos => true;

/// El tipo que viene dentro del `data`. Si no se entiende, se devuelve vacio y
/// quien escuche decidira —un aviso raro no puede tumbar la pantalla—.
String _tipoDe(Object? datos) {
  if (datos is! String) return '';
  try {
    final m = jsonDecode(datos);
    if (m is Map && m['tipo'] is String) return m['tipo'] as String;
  } on Object {
    // Un cuerpo que no es JSON es un aviso perdido, no un fallo.
  }
  return '';
}
