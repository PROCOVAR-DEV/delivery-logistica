import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/de_quien_viene.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/red/interceptor_fallos.dart';
import 'package:reparto/nucleo/sincro/ciclo.dart';

/// UN CÓDIGO HTTP NO DICE DE QUIÉN ES — 28/09/2026.
///
/// Entre el teléfono y nuestra API hay cacharros que contestan por su cuenta:
/// el propio router, un proxy transparente, un filtro de la red del cliente,
/// una redirección a cualquier sitio. Como todos devuelven un código HTTP, la
/// aplicación lo leía como «la petición llegó»: daba la red por buena, contaba
/// el intento como bueno y —lo más caro— dejaba que un 401 que no había escrito
/// nuestro servidor echara a alguien a la pantalla de acceso.
///
/// **Todas las pruebas de aquí van en pareja** (`CLAUDE.md` §3-quinquies): la
/// mitad que dice que el fallo se ve cuando la respuesta no es nuestra, y la
/// mitad que dice que NO pasa nada cuando nuestro servidor contesta lo mismo.
/// Sin la segunda, poner `contestoLoNuestro` a devolver `false` a secas deja
/// esta suite verde y la franja diciendo «sin conexión» con la red perfecta,
/// que es el fallo de al lado y sale igual de caro.
///
/// Esto NO es el aviso de «el sistema dice que esta red no da internet»: eso es
/// otra cosa, la sabe Android y va por `salud.dart`.
void main() {
  _laFirmaDeLaRespuesta();
  _elClienteConAlgoEnMedio();
  _laTraduccionDelFallo();
  _elCicloYLaPruebaDeQueLlego();
}

/// Lo que decide de quién viene una respuesta, a solas.
void _laFirmaDeLaRespuesta() {
  group('de quién viene la respuesta', () {
    test('la cabecera manda: JSON es de la casa, HTML no', () {
      expect(loNuestro(tipo: 'application/json; charset=utf-8'), isTrue);
      expect(loNuestro(tipo: 'application/json'), isTrue);
      expect(loNuestro(tipo: 'application/problem+json'), isTrue);
      expect(loNuestro(tipo: 'TEXT/JSON'), isTrue);

      expect(
        loNuestro(tipo: 'text/html; charset=UTF-8', cuerpo: '{"a":1}'),
        isFalse,
        reason:
            'la cabecera manda sobre el cuerpo: algo que mandara JSON dentro '
            'de un text/html seguiría sin ser nuestro servidor',
      );
      expect(loNuestro(tipo: 'text/plain'), isFalse);
    });

    test('sin cabecera se mira la forma del cuerpo', () {
      expect(loNuestro(cuerpo: const <String, Object?>{}), isTrue);
      expect(loNuestro(cuerpo: const <Object?>[]), isTrue);
      expect(loNuestro(cuerpo: '{"pedidos":[]}'), isTrue);
      expect(loNuestro(cuerpo: '  [1,2]'), isTrue);

      expect(
        loNuestro(cuerpo: '<!DOCTYPE html><html>Acceso a la red</html>'),
        isFalse,
        reason: 'es una página, no nuestra API',
      );
      expect(loNuestro(cuerpo: 'Gateway Timeout'), isFalse);
    });

    test('una respuesta SIN CUERPO se da por nuestra, y es a propósito', () {
      // La única puerta que se deja abierta. Quien se cruza en medio contesta
      // para que alguien lea algo, así que el silencio total no es su forma de
      // fallar; sí es la de una respuesta nuestra sin cuerpo. Cerrarla aquí
      // sería inventarse un «sin conexión» donde no lo hay.
      expect(loNuestro(), isTrue);
      expect(loNuestro(cuerpo: ''), isTrue);
      expect(loNuestro(tipo: 'application/json', cuerpo: null), isTrue);
    });

    test('sin respuesta ninguna no hay nada que firmar', () {
      expect(contestoLoNuestro(null), isFalse);
    });

    test('el Content-Type se saca para poder contarlo', () {
      final respuesta = Response<Object?>(
        requestOptions: RequestOptions(),
        statusCode: 200,
        headers: Headers.fromMap({
          'content-type': ['text/html; charset=UTF-8'],
        }),
      );
      expect(
        tipoDeContenido(respuesta),
        'text/html; charset=UTF-8',
        reason: 'saber QUÉ llegó en vez de lo nuestro es media investigación',
      );
      expect(tipoDeContenido(null), isNull);
    });
  });
}

/// El cliente de verdad con el cable de producción enganchado a la salud.
void _elClienteConAlgoEnMedio() {
  group('el cliente con algo en medio', () {
    late List<bool> avisos;
    late ProviderContainer contenedor;

    /// El contenedor con la salud de verdad, sin tocar el sistema.
    ///
    /// Las dos pistas del aparato se sustituyen porque `connectivity_plus` no
    /// existe en una prueba: si dijeran «no hay ni interfaz», `vaMal` saldría
    /// `true` sin haber contado un solo intento y esto no probaría nada — que
    /// es justo el caso contrario al de Jose, con las cuatro rayas puestas.
    ProviderContainer laSalud() {
      final c = ProviderContainer.test(
        overrides: [
          pistaDeRedProvider.overrideWithValue(() async => true),
          avisosDeRedProvider.overrideWithValue(
            () => const Stream<bool>.empty(),
          ),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 28, 10)),
        ],
      );
      expect(c.read(saludDeLaRedProvider).vaMal, isFalse);
      return c;
    }

    /// Un cliente que contesta lo que se le diga, con el cable de producción:
    /// la petición llama a `alIntentar`, `alIntentar` llama a `anotarIntento` y
    /// lo que se mira después es `saludDeLaRedProvider`. **Nadie repite la
    /// cuenta a mano**: reimplementar aquí la transición de estado es la trampa
    /// del §5 y ya dejó pasar una mutación entera.
    ClienteApi clienteQue(
      int codigo,
      String cuerpo, {
      String? tipo,
    }) {
      avisos = [];
      contenedor = laSalud();
      addTearDown(contenedor.dispose);
      final dio = Dio()
        ..httpClientAdapter = _Adaptador(codigo, cuerpo, tipo)
        ..interceptors.add(const InterceptorFallos());
      return ClienteApi(
        dio: dio,
        esperas: const [Duration.zero, Duration.zero, Duration.zero],
        esperar: (_) async {},
        alIntentar: ({required bool llego}) {
          avisos.add(llego);
          contenedor
              .read(saludDeLaRedProvider.notifier)
              .anotarIntento(llego: llego);
        },
      );
    }

    test('un 200 con una página dentro NO es una escritura hecha', () async {
      // ESTE ES EL PEOR DE TODOS, y va con la llamada de verdad:
      // `escritura_en_vivo.dart` hace `mandar<Object?>`, o sea que NO obliga al
      // cuerpo a ser un mapa. La página de quien contestara entra como
      // `String`, el `as Object?` la acepta sin rechistar, y hasta hoy eso era
      // una escritura dada por buena: el gesto desaparece de la pantalla, el
      // aviso dice «Todo al día» y arriba no llegó nada. El §4 entero.
      final cliente = clienteQue(
        200,
        '<!DOCTYPE html><html><body>Configuración del router</body></html>',
        tipo: 'text/html; charset=UTF-8',
      );

      await expectLater(
        cliente.mandar<Object?>('POST', '/api/paradas/7/entregada', null),
        throwsA(isA<ContestoOtroServidor>()),
      );

      expect(
        avisos,
        [false, false, false, false],
        reason: 'el intento y sus tres reintentos, ninguno llegó a la API',
      );
      expect(
        contenedor.read(saludDeLaRedProvider).vaMal,
        isTrue,
        reason:
            'contestó algo, pero no nuestra API: dar eso por bueno es lo que '
            'dejaba la franja en «Todo al día» sin que subiera nada',
      );
    });

    test('y la misma página pedida como mapa tampoco cuela', () async {
      // La otra forma de llamar, `pedir<Map<String, Object?>>`. Aquí el HTML se
      // estrella antes, en el `as T` de dentro de Dio, y sale un `FalloDeRed`
      // sin código. Se prueba igual porque lo que importa no es qué tipo sale,
      // es que **ninguna de las dos formas le diga a nadie que hay conexión**.
      final cliente = clienteQue(
        200,
        '<!DOCTYPE html><html><body>Conéctate</body></html>',
        tipo: 'text/html; charset=UTF-8',
      );

      await expectLater(
        cliente.pedir<Map<String, Object?>>('/api/rutas'),
        throwsA(isA<FalloDeRed>()),
      );

      expect(avisos, [false, false, false, false]);
      expect(contenedor.read(saludDeLaRedProvider).vaMal, isTrue);
    });

    test('un 200 de NUESTRA API sí lo es, y no se avisa de nada', () async {
      // LA OTRA MITAD. Sin esto, `contestoLoNuestro` puesto a `false` a secas
      // deja la suite verde y pone «sin conexión» delante de alguien que está
      // trabajando con la red perfecta.
      final cliente = clienteQue(
        200,
        '{"rutas":[]}',
        tipo: 'application/json; charset=utf-8',
      );

      final datos = await cliente.pedir<Map<String, Object?>>('/api/rutas');

      expect(datos, {'rutas': <Object?>[]});
      expect(avisos, [true]);
      expect(contenedor.read(saludDeLaRedProvider).vaMal, isFalse);
    });

    test('el 403 de un proxy por medio cuenta como red caída', () async {
      final cliente = clienteQue(
        403,
        '<html>Acceso restringido</html>',
        tipo: 'text/html',
      );

      await expectLater(
        cliente.pedir<Map<String, Object?>>('/api/rutas'),
        throwsA(isA<ContestoOtroServidor>()),
      );

      expect(avisos, [false, false, false, false]);
      expect(contenedor.read(saludDeLaRedProvider).vaMal, isTrue);
    });

    test('el 403 de NUESTRO servidor no dice nada malo de la red', () async {
      final cliente = clienteQue(
        403,
        '{"error":"Esta sucursal no es la tuya."}',
        tipo: 'application/json; charset=utf-8',
      );

      await expectLater(
        cliente.pedir<Map<String, Object?>>('/api/rutas'),
        throwsA(
          isA<Rechazo>().having(
            (r) => r.mensaje,
            'mensaje',
            'Esta sucursal no es la tuya.',
          ),
        ),
      );

      expect(
        avisos,
        [true],
        reason:
            'que el servidor conteste «no» significa que contestó: la red '
            'está bien y decir lo contrario manda a mirar donde no es',
      );
      expect(contenedor.read(saludDeLaRedProvider).vaMal, isFalse);
    });

    test('ni sin cuerpo NI sin cabecera, que es el caso ambiguo', () async {
      // LA PUERTA QUE SE DEJA ABIERTA A PROPOSITO, y la mitad que vigila que no
      // se cierre por celo. Cero bytes y ninguna cabecera no es la forma de
      // fallar de quien se cruza en medio, que contesta para que alguien lea
      // algo; si puede ser, en cambio, una respuesta nuestra que paso por algo
      // que le quito la cabecera. Darla por caida es inventarse un «sin
      // conexion» delante de alguien que esta trabajando, y un aviso que salta
      // en falso deja de leerse (parrafo 3-quinquies).
      final cliente = clienteQue(200, '');

      for (var i = 0; i < 4; i++) {
        await cliente.pedir<Object?>('/api/ping');
      }

      expect(avisos, [true, true, true, true]);
      expect(contenedor.read(saludDeLaRedProvider).vaMal, isFalse);
    });

    test('una respuesta nuestra SIN CUERPO no enciende el aviso', () async {
      // `httpx.JSON` con `cuerpo == nil` manda la cabecera y cero bytes. Cuatro
      // de esas seguidas no pueden acabar en «sin conexión».
      final cliente = clienteQue(200, '', tipo: 'application/json');

      for (var i = 0; i < 4; i++) {
        await cliente.pedir<Object?>('/api/ping');
      }

      expect(avisos, [true, true, true, true]);
      expect(contenedor.read(saludDeLaRedProvider).vaMal, isFalse);
    });
  });
}

/// La tabla de la regla 5, con algo metido en medio.
void _laTraduccionDelFallo() {
  group('traducir con algo en medio', () {
    FalloApi traducir(int codigo, String cuerpo, {String? tipo}) =>
        InterceptorFallos.traducir(
          DioException(
            requestOptions: RequestOptions(path: '/api/rutas'),
            response: Response<Object?>(
              requestOptions: RequestOptions(path: '/api/rutas'),
              statusCode: codigo,
              data: cuerpo,
              headers: tipo == null
                  ? Headers()
                  : Headers.fromMap({
                      'content-type': [tipo],
                    }),
            ),
          ),
        );

    test('un 401 NUESTRO sigue matando la sesión', () {
      // ESTO NO SE PUEDE PERDER. Está documentado en `fallos.dart`: el 401 es
      // lo único que manda a alguien a la pantalla de acceso, y un 401 de
      // nuestro servidor SÍ es prueba de que la petición llegó.
      final fallo = traducir(
        401,
        '{"error":"No autorizado"}',
        tipo: 'application/json; charset=utf-8',
      );
      expect(fallo, isA<SesionMuerta>());
      expect(fallo, isNot(isA<FalloDeRed>()));
    });

    test('un 401 que no es nuestro NO echa a nadie de la aplicación', () {
      // La otra mitad, y la que cierra la puerta por el lado caro: algo que
      // se cruce en medio y conteste 401 no puede tener el poder de borrar la
      // sesión y dejar a un repartidor fuera, con el día dentro, en la calle.
      final fallo = traducir(
        401,
        '<html>Acceso a la red restringido</html>',
        tipo: 'text/html',
      );
      expect(fallo, isNot(isA<SesionMuerta>()));
      expect(fallo, isA<ContestoOtroServidor>());
      expect(
        fallo,
        isA<FalloDeRed>(),
        reason:
            'hereda de FalloDeRed para que los tokens se conserven y se '
            'reintente, sin tener que tocar nada de lo ya escrito',
      );
    });

    test('un 502 con la página de nginx sigue siendo el servidor, no la red', () {
      // El 5xx se mira ANTES de preguntar quién firma: el 502 de nginx y el 503
      // de Traefik son HTML, y decir «esta red no llega al servidor» cuando la
      // red va perfecta manda a mirar donde no es. Los dos acaban en
      // `FalloDeRed`; lo que cambia es la frase.
      final fallo = traducir(502, '<html>Bad Gateway</html>', tipo: 'text/html');
      expect(fallo, isA<FalloDeRed>());
      expect(fallo, isNot(isA<ContestoOtroServidor>()));
    });

    test('el mensaje nombra la red, no la antena', () {
      final fallo = traducir(200, '<html>no es lo nuestro</html>', tipo: 'text/html');
      expect(
        fallo.mensaje.toLowerCase(),
        contains('contestó otra cosa'),
        reason:
            '«sin conexión con el servidor» manda a mirar la señal, y la '
            'señal puede estar perfecta: lo que falla está entre medias',
      );
    });
  });
}

/// El ciclo entero: qué cuenta como prueba de que la petición llegó.
void _elCicloYLaPruebaDeQueLlego() {
  group('anotar el ciclo', () {
    ProviderContainer conLaSaludMalaYa() {
      final c = ProviderContainer.test(
        overrides: [
          pistaDeRedProvider.overrideWithValue(() async => true),
          avisosDeRedProvider.overrideWithValue(
            () => const Stream<bool>.empty(),
          ),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 28, 10)),
        ],
      );
      addTearDown(c.dispose);
      final salud = c.read(saludDeLaRedProvider.notifier);
      for (var i = 0; i < 3; i++) {
        salud.anotarIntento(llego: false);
      }
      expect(c.read(saludDeLaRedProvider).vaMal, isTrue);
      return c;
    }

    test('un fallo que NO es de red no borra el aviso', () {
      // Aquí estaba el agujero: `fallo is FalloDeRed ? mala : buena`. El `else`
      // se tragaba todo lo demás —un parseo reventado, un TypeError, una
      // excepción de la base— y todos decían «la conexión sirve», borrando un
      // aviso puesto por tres caídas de verdad. Ninguno de ellos ha visto
      // llegar un paquete.
      final c = conLaSaludMalaYa();

      c.read(saludDeLaRedProvider.notifier).anotar(
        const ResumenDelCiclo(fallo: FormatException('cuerpo raro')),
      );

      expect(
        c.read(saludDeLaRedProvider).vaMal,
        isTrue,
        reason:
            'una excepción de programación no es prueba de que la red vaya: '
            'dar la conexión por buena con eso es la mentira de Jose',
      );
    });

    test('un ciclo que salió entero SÍ lo borra, al momento', () {
      // LA OTRA MITAD. Sin esto, poner `anotar` a no dar nunca la red por buena
      // deja la suite verde y el aviso pegado en la pantalla de alguien que ya
      // tiene señal, que es mentir en la otra dirección.
      final c = conLaSaludMalaYa();

      c.read(saludDeLaRedProvider.notifier).anotar(const ResumenDelCiclo());

      expect(c.read(saludDeLaRedProvider).vaMal, isFalse);
      expect(
        c.read(saludDeLaRedProvider).ultimaBuena,
        DateTime(2026, 9, 28, 10),
      );
    });

    test('un rechazo y una sesión muerta también: el servidor contestó', () {
      for (final fallo in <Object>[
        const Rechazo(409, 'Ese pedido ya va en otra ruta.'),
        const SesionMuerta('401 tras renovar'),
      ]) {
        final c = conLaSaludMalaYa();
        c.read(saludDeLaRedProvider.notifier).anotar(
          ResumenDelCiclo(fallo: fallo),
        );
        expect(
          c.read(saludDeLaRedProvider).vaMal,
          isFalse,
          reason: '$fallo es prueba de que la petición llegó al servidor',
        );
      }
    });

    test('un fallo de red sigue contando en contra', () {
      final c = conLaSaludMalaYa();
      // Se parte de limpio para contar de cero.
      c.read(saludDeLaRedProvider.notifier).anotar(const ResumenDelCiclo());
      expect(c.read(saludDeLaRedProvider).vaMal, isFalse);

      for (var i = 0; i < 3; i++) {
        c.read(saludDeLaRedProvider.notifier).anotar(
          const ResumenDelCiclo(fallo: ContestoOtroServidor(codigo: 200)),
        );
      }

      expect(
        c.read(saludDeLaRedProvider).vaMal,
        isTrue,
        reason:
            '`ContestoOtroServidor` hereda de `FalloDeRed`, así que entra por '
            'la rama de siempre sin que nadie tenga que nombrarlo',
      );
    });

    test('sin sesión no se toca nada: no se intentó nada', () {
      final c = conLaSaludMalaYa();
      c.read(saludDeLaRedProvider.notifier).anotar(
        ResumenDelCiclo.sinNadaQueHacer,
      );
      expect(c.read(saludDeLaRedProvider).vaMal, isTrue);
    });
  });
}

/// Un adaptador que contesta siempre lo mismo, con su `Content-Type`.
///
/// Se contesta con `ResponseBody` y no con `Response` a propósito: así pasa por
/// el transformador de Dio de verdad, que es quien decide si el cuerpo se
/// decodifica a `Map` o se queda en texto según la cabecera. Un `Response`
/// montado a mano se salta justo la pieza que esto viene a probar.
class _Adaptador implements HttpClientAdapter {
  _Adaptador(this.codigo, this.cuerpo, this.tipo);

  final int codigo;
  final String cuerpo;
  final String? tipo;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    cuerpo,
    codigo,
    headers: tipo == null
        ? const {}
        : {
            Headers.contentTypeHeader: [tipo!],
          },
  );
}
