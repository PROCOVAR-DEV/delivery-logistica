import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';

/// LA SALUD DE LA RED SE CUENTA POR INTENTO, NO POR CICLO.
///
/// El 16/09/2026, con el teléfono SIN salida a internet —medido desde el propio
/// aparato: 100 % de paquetes perdidos a 8.8.8.8 y ni siquiera resolvía el
/// nombre del servidor—, la aplicación seguía sin decirlo. Palabras de Jose:
/// «ahora mismo estoy sin conexion y el movil me dice q tengo internet por q
/// razon».
///
/// La causa: hacían falta TRES CICLOS caídos, y un ciclo tarda. Contando
/// intentos, los tres caben dentro de uno solo —cada petición reintenta a 1 s,
/// 4 s y 10 s—, así que el aviso sale en menos de medio minuto.
///
/// El motivo de que sean tres y no uno sigue en pie: un aviso que parpadea con
/// cada paquete perdido deja de leerse.
///
/// ## Y LA PRUEBA SE ENGANCHA A `LaSalud.anotarIntento` — 24/09/2026
///
/// Esta prueba comprobaba el interceptor y despues **reimplementaba la
/// transicion de estado en su propio cuerpo** (`salud = llego ? … : …`). O sea,
/// copiaba el codigo que venia a probar, que es la trampa del `CLAUDE.md` §5:
/// el auditor puso `anotarIntento` a contar SIEMPRE como caida de red y las
/// 1.520 pruebas salieron verdes, con la franja diciendo «sin conexión» a la
/// cuarta peticion aunque las cuatro contestaran 200.
///
/// Ahora el cable esta entero y es el de produccion: la peticion llama a
/// `alIntentar`, `alIntentar` llama a `anotarIntento`, y lo que se mira es
/// `saludDeLaRedProvider`. Nadie repite la cuenta a mano.
void main() {
  late List<bool> avisos;
  late ProviderContainer contenedor;

  /// El contenedor con la salud de verdad, sin tocar el sistema.
  ///
  /// Las dos pistas del aparato se sustituyen porque `connectivity_plus` no
  /// existe en una prueba: si dijeran «no hay ni interfaz», `vaMal` saldria
  /// `true` sin haber contado un solo intento y esto no probaria nada.
  ProviderContainer laSalud() {
    final c = ProviderContainer.test(
      overrides: [
        pistaDeRedProvider.overrideWithValue(() async => true),
        avisosDeRedProvider.overrideWithValue(() => const Stream<bool>.empty()),
      ],
    );
    // Se arranca el notifier ANTES de la primera peticion: asi la pista de red
    // ya paso y lo que se cuente despues son intentos, no el nacimiento.
    expect(c.read(saludDeLaRedProvider).vaMal, isFalse);
    return c;
  }

  ClienteApi clienteQue(Future<Response<Object?>> Function() responde) {
    avisos = [];
    contenedor = laSalud();
    addTearDown(contenedor.dispose);
    final dio = Dio();
    dio.httpClientAdapter = _AdaptadorFalso(responde);
    return ClienteApi(
      dio: dio,
      esperas: const [Duration.zero, Duration.zero, Duration.zero],
      esperar: (_) async {},
      // EL CABLE DE PRODUCCION, tal cual lo monta `nucleo/proveedores.dart`.
      alIntentar: ({required bool llego}) {
        avisos.add(llego);
        contenedor.read(saludDeLaRedProvider.notifier).anotarIntento(
          llego: llego,
        );
      },
    );
  }

  test('una petición que no sale avisa de CADA intento, no de uno', () async {
    final cliente = clienteQue(
      () => throw DioException.connectionError(
        requestOptions: RequestOptions(),
        reason: 'sin red',
      ),
    );

    await expectLater(cliente.pedir<Object?>('/loquesea'), throwsA(anything));

    expect(
      avisos.length,
      4,
      reason:
          'el intento y sus tres reintentos: cuatro avisos dentro de UNA '
          'petición, que es lo que hace que el aviso salga en segundos',
    );
    expect(avisos.every((llego) => !llego), isTrue);

    // Y con esos cuatro, la salud ya da la red por mala. **Se le pregunta a
    // `anotarIntento`**, que es quien lo decide en la aplicación: repetir aquí
    // la cuenta a mano era copiar el código que se estaba probando.
    expect(
      contenedor.read(saludDeLaRedProvider).vaMal,
      isTrue,
      reason: 'sin esto habría que esperar a tres CICLOS, o sea minutos',
    );
  });

  test('CUATRO peticiones que contestan 200 NO dicen «sin conexión»', () async {
    // LA OTRA MITAD DE LA PAREJA, y la que faltaba entera.
    //
    // `anotarIntento` puesto a contar siempre como caída de red deja la suite
    // verde y pone la franja en «Sin conexión» a la cuarta petición con la red
    // perfecta. Un aviso que sale siempre deja de leerse (§3-quinquies), y
    // entonces tampoco se lee el día que de verdad no hay señal.
    final cliente = clienteQue(
      () async => Response<Object?>(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: const <String, Object?>{},
      ),
    );

    for (var i = 0; i < 4; i++) {
      await cliente.pedir<Object?>('/loquesea');
    }

    expect(avisos, [true, true, true, true]);
    expect(
      contenedor.read(saludDeLaRedProvider).vaMal,
      isFalse,
      reason:
          'cuatro respuestas del servidor son cuatro pruebas de que la red '
          'va: decir «sin conexión» aquí manda a mirar donde no es',
    );
  });

  test('un 4xx NO cuenta como red mala: la petición sí llegó', () async {
    final cliente = clienteQue(
      () async => Response<Object?>(
        requestOptions: RequestOptions(),
        statusCode: 404,
        data: const <String, Object?>{},
      ),
    );

    await expectLater(cliente.pedir<Object?>('/loquesea'), throwsA(anything));

    expect(
      avisos,
      [true],
      reason:
          'que el servidor conteste «no existe» significa que contestó: la '
          'red está bien y decir lo contrario manda a mirar donde no es',
    );
    expect(contenedor.read(saludDeLaRedProvider).vaMal, isFalse);
  });

  _elInterceptor();

  test('una que llega da la red por sana al momento', () async {
    final cliente = clienteQue(
      () async => Response<Object?>(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: const <String, Object?>{},
      ),
    );

    // Nueve caídas seguidas: la franja lleva rato diciendo «Sin conexión».
    final salud = contenedor.read(saludDeLaRedProvider.notifier);
    for (var i = 0; i < 9; i++) {
      salud.anotarIntento(llego: false);
    }
    expect(contenedor.read(saludDeLaRedProvider).vaMal, isTrue);

    await cliente.pedir<Object?>('/loquesea');

    expect(avisos, [true]);
    expect(
      contenedor.read(saludDeLaRedProvider).vaMal,
      isFalse,
      reason:
          'basta UNA buena: dejar el aviso puesto delante de alguien que ya '
          'tiene señal es mentir en la otra dirección',
    );
  });
}

/// EL OTRO CONTADOR, el del Dio crudo de auth. Tampoco lo nombraba nadie.
///
/// `InterceptorDeSalud` es el que cuenta la peticion de RENOVAR, que es el
/// primer paso del ciclo: sin conexion el ciclo muere ahi y las peticiones de
/// `ClienteApi` —las unicas que contaban— no se llegan a hacer nunca.
void _elInterceptor() {
  group('InterceptorDeSalud, el del cliente de auth', () {
    late List<bool> avisos;

    /// Un Dio con el interceptor puesto, como lo monta `dioAuthProvider`.
    ///
    /// Se prueba POR EL CLIENTE y no llamando a `onError` a pelo: un handler
    /// suelto no tiene a quien seguirle y revienta por detrás, y además esto es
    /// el camino de verdad — el de renovar, que es el primer paso del ciclo.
    Dio authQue(Future<ResponseBody> Function() responde) {
      avisos = [];
      return Dio()
        ..httpClientAdapter = _AdaptadorCrudo(responde)
        ..interceptors.add(
          InterceptorDeSalud(
            alIntentar: ({required bool llego}) => avisos.add(llego),
          ),
        );
    }

    test('una respuesta cuenta como que la red va', () async {
      final dio = authQue(() async => ResponseBody.fromString('{}', 200));
      await dio.get<Object?>('https://auth.prueba/refresh');
      expect(avisos, [true]);
    });

    test('un 401 TAMBIEN: el servidor contestó', () async {
      final dio = authQue(() async => ResponseBody.fromString('{}', 401));
      await expectLater(
        dio.get<Object?>('https://auth.prueba/refresh'),
        throwsA(anything),
      );
      expect(
        avisos,
        [true],
        reason:
            'una sesión muerta no es una red muerta; contarla como caída '
            'mandaría a mirar el wifi por un problema de la puerta',
      );
    });

    // Y «UNA RESPUESTA» NO BASTA: TIENE QUE SER LA NUESTRA — 28/09/2026.
    //
    // Renovar es la PRIMERA petición del ciclo y la primera al abrir la
    // aplicación. Si algo por el camino —un router, un proxy, un filtro de la
    // red— contesta a ésta en vez de auth, «hay Response» bastaba para anotar
    // que la red iba: el contador de fallos se ponía a cero solo cada pocos
    // minutos y nunca llegaba a tres. Las dos mitades van juntas — el detalle
    // de la regla, en `de_quien_viene.dart`.
    test('una página que no es de auth NO cuenta como que la red va', () async {
      final dio = authQue(
        () async => ResponseBody.fromString(
          '<html>Acceso a la red restringido</html>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
          },
        ),
      );
      await dio.get<Object?>('https://auth.prueba/refresh');
      expect(
        avisos,
        [false],
        reason:
            'contestó algo, pero no auth: dar esto por bueno es lo que dejaba '
            'el contador de fallos a cero sin que llegara una sola petición',
      );
    });

    test('y una respuesta de auth de verdad SÍ cuenta', () async {
      final dio = authQue(
        () async => ResponseBody.fromString(
          '{"access":"x"}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json; charset=utf-8'],
          },
        ),
      );
      await dio.get<Object?>('https://auth.prueba/refresh');
      expect(avisos, [true]);
    });

    test('sin respuesta, la petición no salió', () async {
      final dio = authQue(
        () => throw DioException.connectionError(
          requestOptions: RequestOptions(),
          reason: 'sin red',
        ),
      );
      await expectLater(
        dio.get<Object?>('https://auth.prueba/refresh'),
        throwsA(anything),
      );
      expect(
        avisos,
        [false],
        reason:
            'renovar es el PRIMER paso del ciclo: sin esto, sin conexión el '
            'ciclo muere aquí y no se cuenta un solo intento',
      );
    });
  });
}

/// Un adaptador crudo, para el Dio de auth: contesta lo que se le diga.
class _AdaptadorCrudo implements HttpClientAdapter {
  _AdaptadorCrudo(this.responde);

  final Future<ResponseBody> Function() responde;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) => responde();
}

/// Un adaptador que contesta lo que se le diga, sin tocar la red.
class _AdaptadorFalso implements HttpClientAdapter {
  _AdaptadorFalso(this.responde);

  final Future<Response<Object?>> Function() responde;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final r = await responde();
    return ResponseBody.fromString('{}', r.statusCode ?? 200);
  }
}
