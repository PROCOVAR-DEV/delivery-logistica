// EL SERVIDOR DE MENTIRA PARA LA PRUEBA DE NAVEGADOR de `eventos_web.dart`.
//
// No es un `_test.dart`, así que `flutter test` no lo ejecuta: es un programa
// suelto que hay que levantar ANTES de correr `eventos_web_test.dart`, porque
// ese vive dentro de Chrome y ahí no hay `dart:io` con el que abrir un puerto.
//
//     dart test/apoyo/servidor_sse_del_navegador.dart 8123 &
//     timeout 300 flutter test --platform chrome test/nucleo/red/eventos_web_test.dart
//     kill %1
//
// Va en `127.0.0.1` y NUNCA contra un dominio de Procovar: la regla de la casa
// prohíbe cualquier petición a `*.procovar.cloud` desde el ordenador de Jose —a
// la oficina le bloquearon la IP por eso el 04/08/2026—.
//
// El CORS devuelve el origen que pide, y no `*`, porque el canal de la web abre
// con `withCredentials: true` y con un comodín el navegador tira la conexión.
// El origen del banco de pruebas es `http://localhost:<puerto al azar>`, así que
// hay que hacerle eco: no se puede escribir a mano.
import 'dart:io';

Future<void> main(List<String> args) async {
  final puerto = int.parse(args.isEmpty ? '8123' : args.first);
  final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, puerto);
  stderr.writeln('sse de mentira escuchando en 127.0.0.1:$puerto');

  var yaRechazo = false;
  await for (final p in servidor) {
    final origen = p.headers.value('origin') ?? '*';
    p.response.headers
      ..set('Access-Control-Allow-Origin', origen)
      ..set('Access-Control-Allow-Credentials', 'true');

    if (p.method == 'OPTIONS') {
      p.response.statusCode = 204;
      await p.response.close();
      continue;
    }
    // EL CAMINO QUE RECHAZA LA PRIMERA VEZ Y LUEGO ABRE — 29/09/2026.
    //
    // Sirve para una sola pregunta, y es la que costo la noche del 29: **un 401
    // NO puede matar el canal para siempre**. El servidor de verdad contesto uno
    // a las 21:30:50 y la web se quedo muda cinco minutos, justo cuando Jose creo
    // una zona desde el telefono. Aqui se reproduce: el primer intento se rechaza
    // y el segundo abre, asi que si el cliente no reintenta, la prueba se queda
    // sin su `cambio` y falla.
    if (p.uri.path.contains('/rechaza-una-vez/')) {
      if (!yaRechazo) {
        yaRechazo = true;
        stderr.writeln('rechazando el primer intento de ${p.uri}');
        p.response.statusCode = 401;
        p.response.headers.contentType = ContentType.text;
        p.response.write('Unauthorized');
        await p.response.close();
        continue;
      }
      stderr.writeln('segundo intento de ${p.uri}: ahora si');
    }
    if (!p.uri.path.endsWith('/eventos')) {
      p.response.statusCode = 404;
      await p.response.close();
      continue;
    }

    p.response.headers
      ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..set('Cache-Control', 'no-cache');
    // Sin esto Dart junta las dos tramas en un solo paquete y la prueba no
    // distingue si el `listo` salió antes que el `cambio`, que es justo lo que
    // comprueba.
    p.response.bufferOutput = false;

    stderr.writeln('abierto ${p.uri} desde $origen');
    // El mismo orden que el servidor de verdad (`api/internal/api/eventos.go`):
    // el `listo` va SIEMPRE el primero.
    p.response.write('event: listo\ndata: {"vivo":true}\n\n');
    await p.response.flush();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    p.response.write('event: cambio\ndata: {"tipo":"tablero"}\n\n');
    await p.response.flush();
    // Se queda abierta. La cierra el navegador al acabar la prueba.
  }
}
