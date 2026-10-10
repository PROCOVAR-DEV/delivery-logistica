// EL FLUJO `GET /sync/revision/eventos` DE VERDAD, contra un servidor en 127.0.0.1.
//
// El doble de `escucha_de_revision_test.dart` no ve lo que ve esto: que la trama
// partida en dos trozos de red se entiende igual, que el token y la dirección viajan
// como el contrato dice, que un 429 trae su `Retry-After`, y sobre todo que CANCELAR
// suelta el socket de verdad (cancelar la suscripción de `dio` no lo hace; ver
// `abrirFlujoDeRevision`). Mismo método que `red/eventos_io_test.dart`: un `HttpServer`
// con puerto 0, que es local; no sale un paquete de esta máquina.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/sincro/flujo_de_revision.dart';

/// El servidor, tal como lo describe el contrato: `: abierto`, `event: revision` +
/// `data: {"v":1}`, `: ka`.
class _Servidor {
  _Servidor._(this._http);

  final HttpServer _http;
  final peticiones = <HttpRequest>[];
  final autorizaciones = <String?>[];
  final _respuestas = <HttpResponse>[];

  static Future<_Servidor> abrir(
    FutureOr<void> Function(HttpRequest, int) atender,
  ) async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = _Servidor._(http);
    http.listen((p) {
      final n = s.peticiones.length;
      s.peticiones.add(p);
      s.autorizaciones.add(p.headers.value(HttpHeaders.authorizationHeader));
      s._respuestas.add(p.response);
      unawaited(Future<void>.sync(() => atender(p, n)));
    });
    return s;
  }

  Uri url([String ruta = '/sync/revision/eventos?aparato=ap-1']) =>
      Uri.parse('http://127.0.0.1:${_http.port}$ruta');

  int get conexionesVivas => _http.connectionsInfo().total;

  /// Escribe a lo bestia hasta que el cliente se haya ido (un socket que el otro lado
  /// cerró no se nota hasta que se escribe).
  Future<void> sacudir() async {
    for (final r in _respuestas) {
      for (var i = 0; i < 60; i++) {
        try {
          r.write('x' * 65536);
          await r.flush().timeout(const Duration(milliseconds: 200));
        } on Object {
          break;
        }
      }
    }
    for (var i = 0; i < 20 && conexionesVivas > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> cerrar() => _http.close(force: true);
}

HttpResponse _sse(HttpRequest p) {
  final r = p.response;
  r.statusCode = HttpStatus.ok;
  r.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
  r.headers.set(HttpHeaders.cacheControlHeader, 'no-store, no-transform');
  // Sin esto el servidor de la prueba junta los trozos y la trama partida no prueba nada.
  r.bufferOutput = false;
  return r;
}

Future<void> _escribe(HttpResponse r, String trozo) async {
  try {
    r.write(trozo);
    await r.flush();
  } on Object {
    // El cliente se fue: a veces es justo lo que la prueba provoca.
  }
}

/// Lo que sale del flujo durante [durante], y cómo terminó.
Future<({List<String> sucesos, Object? error, bool cerrado})> _recoge(
  Stream<String> flujo, {
  Duration durante = const Duration(milliseconds: 400),
}) async {
  final sucesos = <String>[];
  Object? error;
  var cerrado = false;
  final fin = Completer<void>();
  final sub = flujo.listen(
    sucesos.add,
    onError: (Object e) => error = e,
    onDone: () {
      cerrado = true;
      fin.complete();
    },
  );
  // Si el flujo se cierra antes (un rechazo), no hace falta esperar al plazo.
  await Future.any<void>([Future<void>.delayed(durante), fin.future]);
  await sub.cancel();
  return (sucesos: sucesos, error: error, cerrado: cerrado);
}

void main() {
  test('abre con el token de ENTREGA en el Authorization, pide SSE y lleva '
      '?aparato= en la dirección', () async {
    final s = await _Servidor.abrir((p, n) async {
      final r = _sse(p);
      await _escribe(r, ': abierto\n\n');
    });
    addTearDown(s.cerrar);

    await _recoge(abrirFlujoDeRevision(s.url(), 'tok-entrega'));

    expect(s.autorizaciones, ['Bearer tok-entrega']);
    final p = s.peticiones.single;
    expect(p.uri.path, '/sync/revision/eventos');
    expect(p.uri.queryParameters, {'aparato': 'ap-1'});
    expect(p.headers.value(HttpHeaders.acceptHeader), 'text/event-stream');
  });

  test('cuenta `abierto` al llegar el 200 y `revision` por cada evento; los '
      'comentarios (`: abierto`, `: ka`) y el `data` no cuentan', () async {
    final s = await _Servidor.abrir((p, n) async {
      final r = _sse(p);
      await _escribe(r, ': abierto\n\n');
      await _escribe(r, ': ka\n\n');
      await _escribe(r, 'event: revision\ndata: {"v":1}\n\n');
      await _escribe(r, 'event: otra-cosa\ndata: {}\n\n');
      await _escribe(r, ': ka\n\n');
      await _escribe(r, 'event: revision\r\ndata: {"v":1}\r\n\r\n');
    });
    addTearDown(s.cerrar);

    final r = await _recoge(abrirFlujoDeRevision(s.url(), 't'));

    expect(r.sucesos, [
      sucesoAbierto,
      sucesoRevision,
      'otra-cosa',
      sucesoRevision,
    ]);
  });

  test(
    'una trama partida a mitad de palabra por la red se entiende igual',
    () async {
      final s = await _Servidor.abrir((p, n) async {
        final r = _sse(p);
        await _escribe(r, 'event: revi');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await _escribe(r, 'sion\ndata: {"v"');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await _escribe(r, ':1}\n\n');
      });
      addTearDown(s.cerrar);

      final r = await _recoge(abrirFlujoDeRevision(s.url(), 't'));

      expect(r.sucesos, [sucesoAbierto, sucesoRevision]);
    },
  );

  test('el servidor cierra (caducó el token de entrega): el stream se CIERRA '
      'sin error, para que quien escucha pida otro token', () async {
    final s = await _Servidor.abrir((p, n) async {
      final r = _sse(p);
      await _escribe(r, ': abierto\n\n');
      await r.close();
    });
    addTearDown(s.cerrar);

    final r = await _recoge(abrirFlujoDeRevision(s.url(), 't'));

    expect(r.cerrado, isTrue);
    expect(r.error, isNull);
    expect(r.sucesos, [sucesoAbierto]);
  });

  group('lo que contesta cuando no abre', () {
    Future<RechazoDelFlujo> rechazo(
      int codigo, {
      Map<String, String> cabeceras = const {},
    }) async {
      final s = await _Servidor.abrir((p, n) async {
        p.response.statusCode = codigo;
        cabeceras.forEach((k, v) => p.response.headers.set(k, v));
        p.response.headers.contentType = ContentType.json;
        p.response.write('{"error":"no"}');
        await p.response.close();
      });
      addTearDown(s.cerrar);
      final r = await _recoge(abrirFlujoDeRevision(s.url(), 't'));
      expect(r.sucesos, isEmpty, reason: 'un $codigo no es un flujo abierto');
      expect(r.cerrado, isTrue);
      return r.error! as RechazoDelFlujo;
    }

    test('401, 403 y 404: el código, sin espera', () async {
      for (final c in [401, 403, 404]) {
        final e = await rechazo(c);
        expect(e.codigo, c);
        expect(e.esperar, isNull);
      }
    });

    test('429 con Retry-After: el código y cuánto esperar', () async {
      final e = await rechazo(429, cabeceras: {'Retry-After': '45'});
      expect(e.codigo, 429);
      expect(e.esperar, const Duration(seconds: 45));
    });

    test(
      'PAREJA: 429 sin Retry-After, o con uno que no es un número, no inventa '
      'una espera',
      () async {
        expect((await rechazo(429)).esperar, isNull);
        expect(
          (await rechazo(429, cabeceras: {'Retry-After': 'pronto'})).esperar,
          isNull,
        );
      },
    );

    test(
      'un 503: el código (quien escucha lo trata como del momento)',
      () async {
        expect((await rechazo(503)).codigo, 503);
      },
    );

    test('nadie escuchando en esa dirección: sin código', () async {
      final s = await _Servidor.abrir((p, n) {});
      final url = s.url();
      await s.cerrar();

      // En Windows un puerto cerrado tarda ~2 s en rechazar la conexión (reintenta el SYN) y en
      // Linux es inmediato: con los 400 ms de siempre el CI de Windows veía el error todavía vacío
      // (10/10/2026). Si el flujo termina antes, `_recoge` no espera al plazo.
      final r = await _recoge(
        abrirFlujoDeRevision(url, 't'),
        durante: const Duration(seconds: 15),
      );

      expect(
        r.error,
        isNotNull,
        reason: 'la conexión rechazada se dice, no se calla',
      );
      expect((r.error! as RechazoDelFlujo).codigo, isNull);
    });
  });

  group('soltar', () {
    test('CANCELAR suelta el socket de verdad (no queda ninguna conexión)', () async {
      final s = await _Servidor.abrir((p, n) async {
        final r = _sse(p);
        await _escribe(r, ': abierto\n\n');
      });
      addTearDown(s.cerrar);

      final sub = abrirFlujoDeRevision(s.url(), 't').listen((_) {});
      for (var i = 0; i < 20 && s.conexionesVivas == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(s.conexionesVivas, 1, reason: 'abierta');

      await sub.cancel();
      await s.sacudir();

      expect(
        s.conexionesVivas,
        0,
        reason:
            'sin esto cada apertura deja un flujo vivo, y a la tercera da 429',
      );
    });

    test(
      'cancelar MIENTRAS se espera la respuesta tampoco deja nada',
      () async {
        final s = await _Servidor.abrir((p, n) async {
          // No contesta: el cliente está esperando las cabeceras.
        });
        addTearDown(s.cerrar);

        final sub = abrirFlujoDeRevision(s.url(), 't').listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await sub.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await s.sacudir();

        expect(s.conexionesVivas, 0);
      },
    );

    test('un flujo que se queda MUDO se da por muerto y se cierra (móvil que '
        'cambió de antena)', () async {
      final s = await _Servidor.abrir((p, n) async {
        final r = _sse(p);
        await _escribe(r, ': abierto\n\n');
        // y no escribe nada más
      });
      addTearDown(s.cerrar);

      final r = await _recoge(
        abrirFlujoDeRevision(
          s.url(),
          't',
          silencioMaximo: const Duration(milliseconds: 150),
        ),
        durante: const Duration(milliseconds: 700),
      );

      expect(r.cerrado, isTrue);
      expect(r.sucesos, [sucesoAbierto]);
    });

    test('PAREJA: un `: ka` de vez en cuando lo mantiene abierto', () async {
      final s = await _Servidor.abrir((p, n) async {
        final r = _sse(p);
        for (var i = 0; i < 8; i++) {
          await _escribe(r, ': ka\n\n');
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      });
      addTearDown(s.cerrar);

      final r = await _recoge(
        abrirFlujoDeRevision(
          s.url(),
          't',
          silencioMaximo: const Duration(milliseconds: 250),
        ),
        durante: const Duration(milliseconds: 500),
      );

      expect(r.cerrado, isFalse, reason: 'el servidor sigue ahí, hablando');
    });
  });

  test(
    'desde una prueba NO se abre contra nada que no sea local (producción es '
    'el valor por defecto de SYNC_URL)',
    () async {
      // `.invalid` no existe nunca (RFC 2606): si la guarda no estuviera, esto fallaría
      // por red y NO con el 403 que la guarda pone.
      final r = await _recoge(
        abrirFlujoDeRevision(
          Uri.parse(
            'https://aviso-no-local.invalid/sync/revision/eventos?aparato=a',
          ),
          't',
        ),
      );

      expect((r.error! as RechazoDelFlujo).codigo, 403);
      expect(r.sucesos, isEmpty);
    },
  );
}
