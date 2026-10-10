// EL AVISO EN VIVO DE LA REVISIÓN: la escucha (`EscuchaDeRevision`), sin red.
//
// Jose, 09/10/2026: el administrador aplicó el cambio y el teléfono seguía diciendo
// «Todavía no se ha aplicado nada». «Nada de polling: para eso tenemos SSE».
//
// Aquí está lo que decide la escucha por sí sola: cuándo abre, qué hace con cada
// evento, cuánto espera para volver y cuándo se rinde. El flujo es un DOBLE (un
// controlador por conexión, que la prueba abre, corta o rechaza a mano) y el tiempo lo
// manda `tester.pump`: ninguna prueba espera de verdad ni sale un byte. El transporte
// de verdad tiene su fichero (`flujo_de_revision_test.dart`) y el panel el suyo
// (`pantallas/acceso/aviso_en_vivo_de_revision_test.dart`).
//
// Cada regla tiene su pareja: lo que se reintenta y lo que NO.
//
// Cuándo se PREGUNTA (`alAviso`): con cada `revision` y con cada `abierto` —también la
// primera—, y nunca más. El servidor no guarda eventos: lo decidido con el flujo cerrado
// (el token de entrega caduca cada 10 minutos) solo se sabe preguntando al abrir.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/sincro/entrega_a_revision.dart'
    show RechazoConEspera;
import 'package:reparto/nucleo/sincro/escucha_de_revision.dart';
import 'package:reparto/nucleo/sincro/flujo_de_revision.dart';

/// Una conexión que la prueba maneja.
class _Conexion {
  _Conexion(this.url, this.token);

  final Uri url;
  final String token;
  final control = StreamController<String>();
  bool cancelada = false;

  void abierto() => control.add(sucesoAbierto);
  void revision() => control.add(sucesoRevision);
  void evento(String nombre) => control.add(nombre);
  void cortaElServidor() => unawaited(control.close());
  void rechaza(int? codigo, {Duration? esperar}) =>
      control.addError(RechazoDelFlujo(codigo, esperar: esperar));
}

void main() {
  final aparato = Uri.parse('https://sync.test/revision/eventos?aparato=ap-1');

  late List<_Conexion> conexiones;
  late int avisos;
  late int tokensPedidos;
  // Lo que pasa al pedir el token: por defecto, uno nuevo cada vez.
  late Future<CredencialesDelAviso?> Function() credenciales;
  late EscuchaDeRevision escucha;

  setUp(() {
    conexiones = <_Conexion>[];
    avisos = 0;
    tokensPedidos = 0;
    credenciales = () async => (url: aparato, token: 'tok-${++tokensPedidos}');
  });

  EscuchaDeRevision montar() {
    escucha = EscuchaDeRevision(
      abrir: (url, token) {
        final c = _Conexion(url, token);
        c.control.onCancel = () => c.cancelada = true;
        conexiones.add(c);
        return c.control.stream;
      },
      credenciales: () => credenciales(),
      alAviso: () => avisos++,
    );
    return escucha;
  }

  void arrancar() => escucha.iniciar();

  /// Un `testWidgets` que al acabar SUELTA la escucha: el binding comprueba que no
  /// queda ningún `Timer` ANTES de los `tearDown`, y la «conexión buena» de 30 s es
  /// uno. Soltar es lo que haría quien la tiene (el panel, al desmontarse).
  void prueba(String descripcion, Future<void> Function(WidgetTester) cuerpo) =>
      testWidgets(descripcion, (tester) async {
        await cuerpo(tester);
        escucha.parar();
        await tester.pump();
      });

  Future<void> pasan(WidgetTester tester, Duration cuanto) =>
      tester.pump(cuanto);

  group('abrir', () {
    prueba('pide el token y abre con ÉL y con la dirección del aparato, '
        'UNA vez aunque se llame dos', (tester) async {
      montar();
      arrancar();
      escucha.iniciar(); // idempotente
      await tester.pump();

      expect(conexiones, hasLength(1));
      expect(conexiones.single.url, aparato);
      expect(conexiones.single.token, 'tok-1');
      expect(tokensPedidos, 1);
      expect(avisos, 0, reason: 'abrir no es un aviso');
    });

    prueba('espera al token: nada se abre antes de tenerlo', (tester) async {
      final token = Completer<CredencialesDelAviso?>();
      credenciales = () => token.future;
      montar();
      arrancar();
      await tester.pump();
      expect(conexiones, isEmpty);

      token.complete((url: aparato, token: 'tarde'));
      await tester.pump();
      expect(conexiones.single.token, 'tarde');
    });
  });

  group('lo que avisa', () {
    prueba('`revision` avisa UNA vez cada vez; los eventos que no conoce, no', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();
      final c = conexiones.single;
      c.abierto();
      await tester.pump();
      expect(avisos, 1, reason: 'solo la apertura');

      c.evento('latido');
      c.evento('algo-del-futuro');
      await tester.pump();
      expect(avisos, 1);

      c.revision();
      await tester.pump();
      expect(avisos, 2);
      c.revision();
      await tester.pump();
      expect(avisos, 3);
    });

    prueba('NO HAY SONDEO: diez minutos abierta sin eventos son UNA consulta (la de '
        'la apertura) y UNA conexión', (tester) async {
      montar();
      arrancar();
      await tester.pump();
      conexiones.single.abierto();

      await pasan(tester, const Duration(minutes: 10));

      expect(avisos, 1, reason: 'la de abrir; ninguna más sin que el servidor avise');
      expect(conexiones, hasLength(1));
      expect(tokensPedidos, 1, reason: 'ni se pide otro token por su cuenta');
    });
  });

  group('ponerse al día al (re)abrir', () {
    // El servidor no guarda eventos y no hay Last-Event-ID: lo decidido con el flujo
    // cerrado solo se sabe preguntando. Sin esto, `/sin-permiso` (donde el ciclo está
    // parado y nadie más pregunta) se quedaba en «Todavía no se ha aplicado nada» con el
    // apunte ya aplicado.
    prueba('consulta exactamente UNA vez por apertura, también la primera', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();
      expect(avisos, 0, reason: 'abrir la petición no es estar abierto');

      conexiones.single.abierto();
      await tester.pump();

      expect(avisos, 1);
    });

    prueba('dos aperturas son dos consultas: la de después de un corte también', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();
      conexiones.single.abierto();
      await tester.pump();
      expect(avisos, 1);

      // Cae el token de entrega (10 min) y, entre el corte y la reapertura, el revisor decide.
      await pasan(tester, const Duration(minutes: 10));
      conexiones.single.cortaElServidor();
      await tester.pump();
      expect(avisos, 1, reason: 'el corte no pregunta: todavía no hay conexión');
      await pasan(tester, const Duration(seconds: 2));
      expect(conexiones, hasLength(2));
      expect(avisos, 1, reason: 'abrir la petición tampoco');

      conexiones.last.abierto();
      await tester.pump();
      expect(avisos, 2);
    });

    prueba('NO consulta si no llega `abierto`: ni abriendo, ni rechazada, ni en una hora', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();
      expect(conexiones, hasLength(1));

      // Se abre la petición, pero el servidor dice que no (un 401, luego un 429).
      conexiones.last.rechaza(401);
      await tester.pump();
      await pasan(tester, const Duration(seconds: 2));
      conexiones.last.rechaza(429, esperar: const Duration(seconds: 30));
      await tester.pump();
      await pasan(tester, const Duration(seconds: 30));
      expect(conexiones, hasLength(3));

      // La tercera queda esperando la respuesta, sin llegar a abrir.
      await pasan(tester, const Duration(hours: 1));
      expect(avisos, 0);
    });

    prueba('después de parar, un `abierto` que llega tarde no consulta', (tester) async {
      montar();
      arrancar();
      await tester.pump();
      final c = conexiones.single;

      escucha.parar();
      c.abierto();
      await tester.pump();

      expect(avisos, 0);
    });

    prueba('PAREJA: el `abierto` y un `revision` seguidos son dos avisos (el candado '
        'contra pisarse está en quien consulta, no aquí)', (tester) async {
      montar();
      arrancar();
      await tester.pump();

      conexiones.single
        ..abierto()
        ..revision();
      await tester.pump();

      expect(avisos, 2);
    });
  });

  group('cuando el servidor cierra (caduca el token de entrega, a los 10 minutos)', () {
    prueba('tras una conexión buena reabre a los 2 s PIDIENDO OTRO token', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();
      conexiones.single.abierto();
      await pasan(tester, const Duration(minutes: 10));

      conexiones.single.cortaElServidor();
      await tester.pump();
      expect(conexiones, hasLength(1), reason: 'no al instante');

      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(1));
      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(2));
      expect(conexiones.last.token, 'tok-2', reason: 'el de antes caducó');
      expect(tokensPedidos, 2);
    });
  });

  group('la espera crece y no martillea', () {
    prueba('si cada conexión se cae enseguida: 2, 4, 8, 16, 32, 60, 60 s', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();

      for (final segundos in [2, 4, 8, 16, 32, 60, 60]) {
        final antes = conexiones.length;
        conexiones.last.cortaElServidor();
        await tester.pump();
        await pasan(tester, Duration(seconds: segundos) - const Duration(milliseconds: 1));
        expect(
          conexiones,
          hasLength(antes),
          reason: 'a $segundos s menos un instante todavía no',
        );
        await pasan(tester, const Duration(milliseconds: 1));
        expect(conexiones, hasLength(antes + 1), reason: 'a los $segundos s sí');
      }
    });

    prueba('PAREJA: una conexión que SÍ duró (30 s) reinicia la espera a 2 s', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();
      // Tres caídas seguidas: la espera llega a 8 s.
      for (final s in [2, 4]) {
        conexiones.last.cortaElServidor();
        await tester.pump();
        await pasan(tester, Duration(seconds: s));
      }
      expect(conexiones, hasLength(3));

      // Esta abre y aguanta.
      conexiones.last.abierto();
      await pasan(tester, const Duration(seconds: 30));
      conexiones.last.cortaElServidor();
      await tester.pump();
      await pasan(tester, const Duration(seconds: 2));
      expect(conexiones, hasLength(4), reason: 'vuelve a esperar 2 s, no 8');
    });

    prueba('PAREJA: un 200 que se corta al instante NO reinicia la espera', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();

      // Abre, y a los 5 s el servidor corta: «aceptó y se murió».
      for (final esperado in [2, 4, 8]) {
        conexiones.last.abierto();
        await pasan(tester, const Duration(seconds: 5));
        final antes = conexiones.length;
        conexiones.last.cortaElServidor();
        await tester.pump();
        await pasan(tester, Duration(seconds: esperado) - const Duration(milliseconds: 1));
        expect(conexiones, hasLength(antes), reason: 'espera $esperado s');
        await pasan(tester, const Duration(milliseconds: 1));
        expect(conexiones, hasLength(antes + 1));
      }
    });

    prueba('un fallo de red al abrir (sin código) y un 5xx: espera creciente', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();

      conexiones.last.rechaza(null);
      await tester.pump();
      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(1));
      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(2));

      conexiones.last.rechaza(503);
      await tester.pump();
      await pasan(tester, const Duration(seconds: 3));
      expect(conexiones, hasLength(2), reason: 'la segunda espera es de 4 s');
      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(3));
    });
  });

  group('401, 403 y 429 no se martillean', () {
    prueba('401: NO se reintenta al instante; a los 2 s sí, con OTRO token', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();

      conexiones.last.rechaza(401);
      await tester.pump();
      expect(conexiones, hasLength(1), reason: 'ni un segundo intento en el mismo instante');
      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(1));
      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(2));
      expect(conexiones.last.token, 'tok-2');

      // Y si sigue dando 401, la espera crece: 4 s.
      conexiones.last.rechaza(401);
      await tester.pump();
      await pasan(tester, const Duration(seconds: 3));
      expect(conexiones, hasLength(2));
      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(3));
    });

    prueba('403 (aparato ajeno): se acaba, ni a la hora', (tester) async {
      montar();
      arrancar();
      await tester.pump();

      conexiones.last.rechaza(403);
      await tester.pump();
      await pasan(tester, const Duration(hours: 1));

      expect(conexiones, hasLength(1));
      expect(tokensPedidos, 1, reason: 'ni un token más para algo que no cambia');
      expect(escucha.viva, isFalse);
    });

    prueba('PAREJA del 403: un 404 (servidor sin el flujo) y otro 4xx también '
        'se acaban', (tester) async {
      for (final codigo in [404, 400]) {
        conexiones.clear();
        tokensPedidos = 0;
        montar();
        arrancar();
        await tester.pump();
        conexiones.last.rechaza(codigo);
        await tester.pump();
        await pasan(tester, const Duration(minutes: 30));
        expect(conexiones, hasLength(1), reason: '$codigo no se reintenta');
        expect(escucha.viva, isFalse);
      }
    });

    prueba('429 con Retry-After: espera ESO (120 s), no la espera corta', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();

      conexiones.last.rechaza(429, esperar: const Duration(seconds: 120));
      await tester.pump();
      await pasan(tester, const Duration(seconds: 119));
      expect(conexiones, hasLength(1), reason: 'antes de lo que pidió el servidor, nada');
      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(2));
    });

    prueba('PAREJA: un Retry-After más corto que la espera creciente no la '
        'acorta, y sin Retry-After manda la creciente', (tester) async {
      montar();
      arrancar();
      await tester.pump();

      // Primero una caída para subir la espera a 4 s.
      conexiones.last.rechaza(null);
      await tester.pump();
      await pasan(tester, const Duration(seconds: 2));
      expect(conexiones, hasLength(2));

      conexiones.last.rechaza(429, esperar: const Duration(seconds: 1));
      await tester.pump();
      await pasan(tester, const Duration(seconds: 3));
      expect(conexiones, hasLength(2), reason: '1 s de Retry-After no baja los 4 s');
      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(3));

      conexiones.last.rechaza(429); // sin cabecera
      await tester.pump();
      await pasan(tester, const Duration(seconds: 7));
      expect(conexiones, hasLength(3));
      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(4), reason: 'sin Retry-After, 8 s');
    });

    prueba('un Retry-After disparatado se acota (10 minutos)', (tester) async {
      montar();
      arrancar();
      await tester.pump();

      conexiones.last.rechaza(429, esperar: const Duration(days: 1));
      await tester.pump();
      await pasan(tester, const Duration(minutes: 10) - const Duration(seconds: 1));
      expect(conexiones, hasLength(1));
      await pasan(tester, const Duration(seconds: 1));
      expect(conexiones, hasLength(2));
    });
  });

  group('al pedir el token a Accesos', () {
    prueba('sin red: espera creciente y vuelve a pedir', (tester) async {
      var intentos = 0;
      credenciales = () async {
        intentos++;
        if (intentos == 1) throw const FalloDeRed(detalle: 'sin señal');
        return (url: aparato, token: 'tok-$intentos');
      };
      montar();
      arrancar();
      await tester.pump();
      expect(conexiones, isEmpty);

      await pasan(tester, const Duration(seconds: 1));
      expect(intentos, 1);
      await pasan(tester, const Duration(seconds: 1));
      expect(intentos, 2);
      expect(conexiones.single.token, 'tok-2');
    });

    prueba('429 de Accesos con Retry-After: se respeta', (tester) async {
      var intentos = 0;
      credenciales = () async {
        intentos++;
        if (intentos == 1) {
          throw RechazoConEspera(const Rechazo(429, 'rate_limited'), 90);
        }
        return (url: aparato, token: 'tok');
      };
      montar();
      arrancar();
      await tester.pump();

      await pasan(tester, const Duration(seconds: 89));
      expect(intentos, 1);
      await pasan(tester, const Duration(seconds: 1));
      expect(intentos, 2);
      expect(conexiones, hasLength(1));
    });

    prueba('sin sesión, con permiso otra vez, sin sucursal o sin alta: se '
        'acaba y no vuelve a pedir token', (tester) async {
      final casos = <String, Future<CredencialesDelAviso?> Function()>{
        'sesión muerta': () async => throw const SesionMuerta('no hay sesion'),
        'ya tiene permiso': () async =>
            throw const Rechazo(409, 'tiene_permiso', marca: 'tiene_permiso'),
        'sin sucursal': () async => throw const Rechazo(403, 'sin_sucursal'),
        'aparato sin alta': () async => null,
      };
      for (final MapEntry(:key, :value) in casos.entries) {
        var pedidos = 0;
        credenciales = () {
          pedidos++;
          return value();
        };
        montar();
        arrancar();
        await tester.pump();
        await pasan(tester, const Duration(minutes: 30));
        expect(pedidos, 1, reason: key);
        expect(conexiones, isEmpty, reason: key);
        expect(escucha.viva, isFalse, reason: key);
      }
    });
  });

  group('se suelta TODO al parar', () {
    prueba('cancela la conexión abierta y no deja ningún temporizador', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();
      conexiones.single.abierto(); // lleva su temporizador de «conexión buena»
      await tester.pump();

      escucha.parar();
      await tester.pump();

      expect(conexiones.single.cancelada, isTrue);
      expect(escucha.viva, isFalse);
      // El test falla solo si queda un Timer vivo (y la conexión buena lo era).
    });

    prueba('cancela el reintento que estaba esperando: no abre después', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();
      conexiones.single.cortaElServidor();
      await tester.pump(); // ahora espera 2 s

      escucha.parar();
      await pasan(tester, const Duration(minutes: 5));

      expect(conexiones, hasLength(1));
      expect(tokensPedidos, 1);
    });

    prueba('un token que llega TARDE, cuando ya se paró, no abre nada', (
      tester,
    ) async {
      final token = Completer<CredencialesDelAviso?>();
      credenciales = () => token.future;
      montar();
      arrancar();
      await tester.pump();

      escucha.parar();
      token.complete((url: aparato, token: 'tarde'));
      await tester.pump();

      expect(conexiones, isEmpty);
    });

    prueba('parar dos veces no rompe nada, y un aviso posterior no avisa', (
      tester,
    ) async {
      montar();
      arrancar();
      await tester.pump();
      final c = conexiones.single;

      escucha.parar();
      escucha.parar();
      c.revision();
      await tester.pump();

      expect(avisos, 0);
    });
  });
}
