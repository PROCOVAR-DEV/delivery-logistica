import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Lo que cuenta el flujo al abrirse: llegó el 200. No es un evento del servidor.
const sucesoAbierto = 'abierto';

/// El evento que el servidor manda cuando se DECIDE un apunte de esta persona
/// (`event: revision` + `data: {"v":1}`). El `data` no se lee: dice «mira», no
/// «qué», igual que `eventos.dart` (quien lo recibe vuelve a preguntar, y la
/// respuesta va acotada a esa persona).
const sucesoRevision = 'revision';

/// CUANTO SILENCIO SE AGUANTA antes de dar la conexión por muerta.
///
/// El servidor manda un comentario `: ka` cada 25 s. Dos y pico perdidos son un
/// móvil que cambió de antena: el socket sigue abierto de SU lado y no llega
/// nada nunca más. Un flujo en streaming no tiene plazo de recepción, así que sin
/// esto el aviso en vivo se queda mudo y nadie se entera
/// (`red/eventos_io.dart`, `silencioMaximoDeEventos`, que aprendió lo mismo).
const silencioMaximoDeRevision = Duration(seconds: 60);

/// Cómo se abre el flujo. Es lo que se cambia en una prueba: la de verdad es
/// [abrirFlujoDeRevision].
///
/// El stream cuenta [sucesoAbierto] y el nombre de cada evento; se cierra cuando
/// el servidor corta (a los 10 minutos, al caducar el token de entrega) y
/// termina con [RechazoDelFlujo] si no abrió. Cancelarlo suelta el socket.
typedef AbridorDeFlujoDeRevision = Stream<String> Function(Uri url, String token);

/// El servidor (o la red) no dejó abrir el flujo. `401` token, `403` aparato
/// ajeno, `429` demasiados flujos a la vez (con `Retry-After` en [esperar]);
/// `null` es que ni se llegó a hablar con él.
class RechazoDelFlujo implements Exception {
  const RechazoDelFlujo(this.codigo, {this.esperar});

  final int? codigo;
  final Duration? esperar;

  @override
  String toString() => 'RechazoDelFlujo($codigo, esperar: $esperar)';
}

/// EL FLUJO `GET /sync/revision/eventos` de verdad, por SSE a mano sobre `dio`.
///
/// ## Por qué no es `escucharEventos` (red/eventos_io.dart)
///
/// Se miró primero, y no encaja sin tocar un cliente que sostiene el canal
/// principal y que ya costó varios incidentes: pide siempre `…/eventos` y no
/// admite la `?aparato=`; solo entiende `cambio`/`listo`/`sesion-invalidada`; su
/// `listo` (que reinicia la espera) aquí no existe —el servidor abre con el
/// comentario `: abierto`—; trata el 401 con una renovación inmediata (aquí no hay
/// nada que renovar: otro token se pide a Accesos); cierra el canal para siempre
/// con cualquier 4xx, el 429 incluido, y no lee el `Retry-After`. Cambiar todo eso
/// es retocar el canal de los pedidos para una pantalla. Se reutiliza lo que sí
/// vale tal cual (la espera creciente, `esperaDeReintento`; y las lecciones, que
/// están aquí abajo con su porqué) y el resto es esto, que no sabe nada de
/// políticas: abre, cuenta y se suelta. Quién reintenta y cuándo lo decide
/// `EscuchaDeRevision`.
///
/// ## Lo que sí copia de aquel
///
///  * **Un `Dio` por conexión, y se cierra al soltarla** (`close(force: true)`).
///    Cancelar la suscripción NO cierra el socket (comprobado el 17/09/2026): se
///    quedaría una conexión viva por cada apertura, en el contador de «más de 3
///    flujos a la vez» del servidor, que es justo lo que da el 429.
///  * El flujo se trocea por LÍNEAS, no por trozos de red: un trozo puede acabar
///    en mitad de `event: revi`. `utf8.decoder` + `LineSplitter` guardan el resto.
///  * **Nunca se abre contra algo que no sea local desde una prueba**
///    (`FLUTTER_TEST`): `Entorno.syncUrl` trae producción de valor por defecto, y
///    una prueba que monte `/sin-permiso` con cola en revisión abriría una
///    conexión de verdad desde el ordenador de quien la ejecute
///    (`procovar/CLAUDE.md` §2).
Stream<String> abrirFlujoDeRevision(
  Uri url,
  String token, {
  Duration silencioMaximo = silencioMaximoDeRevision,
}) {
  final control = StreamController<String>();
  final dio = Dio(
    BaseOptions(
      // Conectar con la señal de allá tarda; leer no tiene plazo, que es lo que
      // hace falta en un flujo que se pasa 25 s callado entre `ka` y `ka`.
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: Duration.zero,
    ),
  );
  final corte = CancelToken();
  StreamSubscription<String>? lectura;
  Timer? vigilante;
  var abriendo = false;
  var soltado = false;

  Future<void> soltar() async {
    if (soltado) return;
    soltado = true;
    vigilante?.cancel();
    // El `CancelToken` solo vale mientras se espera la respuesta: después mete un
    // error en un flujo que ya no escucha nadie.
    if (abriendo && !corte.isCancelled) corte.cancel('flujo de revisión cerrado');
    await lectura?.cancel();
    dio.close(force: true);
  }

  Future<void> cerrar() async {
    await soltar();
    if (!control.isClosed) unawaited(control.close());
  }

  Future<void> abrir() async {
    if (!kIsWeb &&
        Platform.environment['FLUTTER_TEST'] == 'true' &&
        !_esLocal(url)) {
      // Ni una petición desde una prueba hacia fuera. Un 403 para que no se
      // reintente: es un "no" que no cambia.
      control.addError(const RechazoDelFlujo(403));
      await cerrar();
      return;
    }
    abriendo = true;
    final Response<ResponseBody> respuesta;
    try {
      respuesta = await dio.getUri<ResponseBody>(
        url,
        cancelToken: corte,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
          },
          receiveTimeout: Duration.zero,
          validateStatus: (codigo) => codigo == 200,
        ),
      );
    } on Object catch (e) {
      abriendo = false;
      if (soltado) return;
      int? codigo;
      Duration? esperar;
      if (e is DioException) {
        codigo = e.response?.statusCode;
        final segundos = int.tryParse(
          e.response?.headers.value('retry-after') ?? '',
        );
        if (segundos != null && segundos > 0) {
          esperar = Duration(seconds: segundos);
        }
        await _soltarCuerpo(e.response);
      }
      control.addError(RechazoDelFlujo(codigo, esperar: esperar));
      await cerrar();
      return;
    }
    abriendo = false;
    final cuerpo = respuesta.data;
    if (soltado || cuerpo == null) {
      await cerrar();
      return;
    }

    void vigilar() {
      vigilante?.cancel();
      if (silencioMaximo <= Duration.zero) return;
      // Sin nada en [silencioMaximo]: se da por muerta y se cierra; quien escucha
      // reconecta con su espera.
      vigilante = Timer(silencioMaximo, () => unawaited(cerrar()));
    }

    control.add(sucesoAbierto);
    var evento = '';
    lectura = cuerpo.stream
        // CUALQUIER byte (el `ka` incluido) prueba que hay socket y servidor.
        .map((trozo) {
          vigilar();
          return trozo;
        })
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          (linea) {
            if (linea.isEmpty) {
              // Línea en blanco: se acabó la trama.
              if (evento.isNotEmpty) control.add(evento);
              evento = '';
            } else if (linea.startsWith('event:')) {
              evento = linea.substring(6).trim();
            }
            // `data:` y los comentarios (`: abierto`, `: ka`) no dicen nada aquí.
          },
          onError: (Object _) => unawaited(cerrar()),
          onDone: () => unawaited(cerrar()),
          cancelOnError: true,
        );
    vigilar();
  }

  control.onListen = () => unawaited(abrir());
  control.onCancel = soltar;
  return control.stream;
}

/// `true` si la dirección apunta a esta misma máquina.
bool _esLocal(Uri url) =>
    url.host == '127.0.0.1' || url.host == 'localhost' || url.host == '::1';

/// Vacía el cuerpo de una respuesta rechazada: en streaming `dio` no lo lee, y un
/// cuerpo sin leer es un socket que se queda cogido.
Future<void> _soltarCuerpo(Response<Object?>? respuesta) async {
  final cuerpo = respuesta?.data;
  if (cuerpo is! ResponseBody) return;
  try {
    await cuerpo.stream.drain<void>();
  } on Object {
    // Da igual por qué no se pudo vaciar: se estaba tirando.
  }
}
