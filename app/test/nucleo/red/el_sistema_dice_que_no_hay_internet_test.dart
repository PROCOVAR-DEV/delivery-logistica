import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/salud.dart';
import 'package:reparto/nucleo/red/veredicto_del_sistema.dart';

/// EL «!» DEL ICONO DEL WIFI — 28/09/2026.
///
/// Jose, con el teléfono enganchado a un wifi sin salida y los datos móviles
/// puestos:
///
/// > «me esta diciendo eso q tengo conexion y no tengo conexion ahora mismo q
/// > mierda es eso por q la wifi no esta dando internet»
/// > «si sale la wifi ahora mismo cuando no tiene conexion sale un icono de wifi
/// > con ! este simbolo diciendo q no hay internet»
///
/// Ese «!» es `NET_CAPABILITY_VALIDATED` en falso: Android probó la red y no
/// llegó. Es un dato del sistema y es instantáneo. La aplicación no lo
/// preguntaba —miraba si había interfaz, que la había— y se quedaba esperando a
/// que se cayeran tres ciclos: **dos minutos y medio diciendo «Todo al día» con
/// el teléfono sin internet.**
///
/// Todo lo de aquí va en pareja (`CLAUDE.md` §3-quinquies), y las dos mitades
/// son igual de caras:
///
///  * que el aviso salga en segundos cuando el sistema dice que no hay salida;
///  * que **no salga** cuando el sistema no dice nada, cuando dice que sí, o
///    cuando todavía está probando la red.
void main() {
  // Hace falta para los dos canales: `setMockMethodCallHandler` pasa por el
  // mensajero de la prueba, y sin binding no hay mensajero.
  TestWidgetsFlutterBinding.ensureInitialized();

  _laVentanaDeSondeo();
  _laBanderaEnLaSalud();
  _elCableEntero();
  _dondeNoHayVeredictoQuePreguntar();
}

/// La espera que impide que el aviso parpadee en cada cambio de red.
void _laVentanaDeSondeo() {
  group('la ventana de sondeo', () {
    late _Esperas esperas;
    late StreamController<Veredicto> crudos;
    late List<Veredicto> salieron;

    setUp(() {
      esperas = _Esperas();
      crudos = StreamController<Veredicto>();
      salieron = [];
      losQueSePuedenCreer(
        crudos.stream,
        crearEspera: esperas.crear,
      ).listen(salieron.add);
    });

    tearDown(() => crudos.close());

    test('son cinco segundos, y con nombre', () {
      // El número está por medir en el teléfono de Jose y por eso tiene nombre:
      // para cambiarlo en un sitio cuando se mida, no en cinco.
      expect(ventanaDeSondeo, const Duration(seconds: 5));
    });

    test('un «no valida» que se MANTIENE sí sale', () async {
      crudos.add(Veredicto.noValida);
      await pumpEventQueue();

      expect(
        salieron,
        isEmpty,
        reason:
            'todavía no: el primer instante de una red recién enganchada '
            'siempre dice «no valida» mientras Android la está probando',
      );
      expect(esperas.creadas.single.duracion, ventanaDeSondeo);

      esperas.ultima.sonar();
      // `add` de un StreamController reparte en el turno siguiente, no ahora.
      await pumpEventQueue();
      expect(salieron, [Veredicto.noValida]);
    });

    test('un «no valida» que se CAE dentro de la ventana no sale nunca', () async {
      // LA OTRA MITAD, y la que evita el parpadeo: al saltar de wifi a datos, o
      // al entrar en el patio del almacén, Android tarda un momento en validar
      // la red nueva. Si ese momento encendiera el aviso, el aviso parpadearía
      // todo el día y a los diez minutos nadie lo lee.
      crudos.add(Veredicto.noValida);
      await pumpEventQueue();
      crudos.add(Veredicto.valida);
      await pumpEventQueue();

      expect(
        esperas.ultima.cancelada,
        isTrue,
        reason: 'el veredicto nuevo tumba la espera que hubiera',
      );
      esperas.creadas.first.sonar();

      expect(
        salieron,
        [Veredicto.valida],
        reason: 'el «no valida» de hace un segundo no se publica jamás',
      );
    });

    test('«valida» y «sin red» salen al momento, sin esperar nada', () async {
      crudos
        ..add(Veredicto.valida)
        ..add(Veredicto.sinRed);
      await pumpEventQueue();

      expect(salieron, [Veredicto.valida, Veredicto.sinRed]);
      expect(
        esperas.creadas,
        isEmpty,
        reason:
            'apagar un aviso no puede esperar, y «no hay red» no tiene nada '
            'que sondear: es el mismo trato que el «no hay ni interfaz»',
      );
    });
  });
}

/// La bandera nueva dentro de `SaludDeLaRed`, a solas.
void _laBanderaEnLaSalud() {
  group('sinSalida en la salud', () {
    test('basta ella sola para decir que va mal', () {
      const salud = SaludDeLaRed(sinSalida: true);
      expect(salud.fallosSeguidos, 0);
      expect(
        salud.vaMal,
        isTrue,
        reason:
            'el sistema ya lo sabe: esperar a tres intentos caídos para decir '
            'lo que el icono de la barra dice desde hace rato es el fallo',
      );
    });

    test('y sin ella el umbral de tres NO se toca', () {
      // LA OTRA MITAD. Bajar el umbral «ya que estamos» sería cambiar un aviso
      // lento y fiable por uno que parpadea.
      var salud = const SaludDeLaRed();
      for (var i = 0; i < 2; i++) {
        salud = salud.conUnaMala();
      }
      expect(salud.vaMal, isFalse);
      expect(salud.conUnaMala().vaMal, isTrue);
      expect(SaludDeLaRed.fallosParaDarlaPorMala, 3);
    });

    test('una petición NUESTRA que llega manda sobre el veredicto', () {
      const salud = SaludDeLaRed(sinSalida: true, sinInterfaz: true);
      final despues = salud.conUnaBuena(DateTime(2026, 9, 28, 10));
      expect(
        despues.vaMal,
        isFalse,
        reason:
            'si el sistema decía que esta red no llega y resulta que llegamos, '
            'manda lo que pasó: dejar el aviso ahí es mentir en la otra '
            'dirección',
      );
    });

    test('un intento caído NO borra lo que dijo el sistema', () {
      // El agujero que había: con el modo avión puesto, `sinInterfaz` ponía
      // `vaMal` en true; el primer intento que alguien hiciera lo devolvía a
      // false, porque `conUnaMala` construía una salud limpia con un fallo. **Un
      // fallo MÁS apagaba el aviso.**
      const salud = SaludDeLaRed(sinInterfaz: true, sinSalida: true);
      final despues = salud.conUnaMala();

      expect(despues.sinInterfaz, isTrue);
      expect(despues.sinSalida, isTrue);
      expect(despues.fallosSeguidos, 1);
      expect(despues.vaMal, isTrue);
    });

    test('volver la interfaz no dice que haya salida, ni al revés', () {
      const salud = SaludDeLaRed(sinInterfaz: true, sinSalida: true);
      expect(
        salud.conInterfaz().sinSalida,
        isTrue,
        reason: 'que haya cable no dice que el cable llegue a algún sitio',
      );
      expect(
        salud.conSalidaAInternet().sinInterfaz,
        isTrue,
        reason: 'y cada bandera la apaga quien la encendió, no la vecina',
      );
    });
  });
}

/// El cable de producción entero: veredicto → providers → `LaSalud`.
void _elCableEntero() {
  group('el cable entero', () {
    late _Esperas esperas;
    late StreamController<Veredicto> avisos;

    /// El contenedor con la salud de verdad. `connectivity_plus` dice que SÍ hay
    /// interfaz —que es lo que decía en el teléfono de Jose, con las rayas
    /// puestas—, así que lo único que puede encender el aviso aquí es el
    /// veredicto o los intentos caídos.
    ProviderContainer contenedorCon(Veredicto alArrancar) {
      esperas = _Esperas();
      avisos = StreamController<Veredicto>.broadcast();
      addTearDown(avisos.close);
      final c = ProviderContainer.test(
        overrides: [
          pistaDeRedProvider.overrideWithValue(() async => true),
          avisosDeRedProvider.overrideWithValue(
            () => const Stream<bool>.empty(),
          ),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 28, 10)),
          veredictoAhoraProvider.overrideWithValue(() async => alArrancar),
          avisosDeVeredictoProvider.overrideWithValue(() => avisos.stream),
          crearEsperaDelSondeoProvider.overrideWithValue(esperas.crear),
        ],
      );
      addTearDown(c.dispose);
      // HAY QUE DEJAR UN OYENTE PUESTO, y no es un detalle de la prueba.
      //
      // Sin esto, Riverpod tira `LaSalud` en cuanto el `read` devuelve, y con
      // ella el `ref.listen` del veredicto: el temporizador de la ventana de
      // sondeo se creaba, sonaba, y el aviso no llegaba a ninguna parte — lo
      // mismo que pasaria en la aplicacion si nadie estuviera mirando la franja.
      // En la aplicacion siempre hay una pantalla mirandola; en una prueba hay
      // que ponerlo a mano o se prueba un notifier que ya no existe.
      c.listen(saludDeLaRedProvider, (_, _) {});
      expect(c.read(saludDeLaRedProvider).vaMal, isFalse);
      return c;
    }

    test('abrir con la red ya muerta lo dice en segundos', () async {
      // El caso del repartidor no es «se va la red con la aplicación abierta»:
      // es abrir la aplicación con la red ya sin salida. Ahí no hay ningún
      // cambio que avisar, así que si esto sólo escuchara los cambios nacería
      // «bien» y se quedaría así.
      final c = contenedorCon(Veredicto.noValida);
      await pumpEventQueue();
      esperas.ultima.sonar();
      // `add` de un StreamController reparte en el turno siguiente, no ahora.
      await pumpEventQueue();

      expect(
        c.read(saludDeLaRedProvider).vaMal,
        isTrue,
        reason:
            'sin esto hacían falta tres ciclos caídos: dos minutos y medio de '
            '«Todo al día» con el teléfono sin internet',
      );
      expect(
        c.read(saludDeLaRedProvider).fallosSeguidos,
        0,
        reason: 'y sin haber tirado una sola petición contra una red muerta',
      );
    });

    test('abrir con la red buena no enciende nada', () async {
      // LA OTRA MITAD. Poner `sinSalida` a `true` de salida deja esta suite
      // verde y la franja diciendo «sin conexión» a todo el mundo, siempre.
      final c = contenedorCon(Veredicto.valida);
      await pumpEventQueue();

      expect(esperas.creadas, isEmpty);
      expect(c.read(saludDeLaRedProvider).vaMal, isFalse);
    });

    test('se apaga en cuanto el sistema dice que ya se sale', () async {
      final c = contenedorCon(Veredicto.noValida);
      await pumpEventQueue();
      esperas.ultima.sonar();
      // `add` de un StreamController reparte en el turno siguiente, no ahora.
      await pumpEventQueue();
      expect(c.read(saludDeLaRedProvider).vaMal, isTrue);

      avisos.add(Veredicto.valida);
      await pumpEventQueue();

      expect(
        c.read(saludDeLaRedProvider).vaMal,
        isFalse,
        reason:
            'dejar el aviso puesto delante de alguien que ya tiene salida es '
            'mentir en la otra dirección',
      );
    });

    test('una petición que llega lo apaga aunque el sistema siga diciendo que no', () async {
      final c = contenedorCon(Veredicto.noValida);
      await pumpEventQueue();
      esperas.ultima.sonar();
      // `add` de un StreamController reparte en el turno siguiente, no ahora.
      await pumpEventQueue();
      expect(c.read(saludDeLaRedProvider).vaMal, isTrue);

      c.read(saludDeLaRedProvider.notifier).anotarIntento(llego: true);

      expect(
        c.read(saludDeLaRedProvider).vaMal,
        isFalse,
        reason:
            'el veredicto es del sistema, pero una respuesta de NUESTRO '
            'servidor es mejor prueba que cualquier sondeo suyo',
      );
    });

    test('«sin red» no apaga la bandera de salida', () async {
      // Si la apagara, quedaría un hueco —el instante entre perder la red y que
      // `connectivity_plus` se entere— con el aviso quitado y sin salida.
      final c = contenedorCon(Veredicto.noValida);
      await pumpEventQueue();
      esperas.ultima.sonar();
      // `add` de un StreamController reparte en el turno siguiente, no ahora.
      await pumpEventQueue();

      avisos.add(Veredicto.sinRed);
      await pumpEventQueue();

      expect(c.read(saludDeLaRedProvider).vaMal, isTrue);
    });
  });
}

/// Windows, Linux y la web: aquí no hay veredicto que preguntar.
void _dondeNoHayVeredictoQuePreguntar() {
  group('donde no hay veredicto', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('en escritorio se contesta «no lo sé», nunca «va mal»', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(hayVeredictoDelSistema, isFalse);
      expect(await veredictoDelSistemaAhora(), Veredicto.noLoSe);
      expect(await avisosDelVeredictoDelSistema().isEmpty, isTrue);
    });

    test('y «no lo sé» no enciende ni apaga nada', () async {
      final avisos = StreamController<Veredicto>.broadcast();
      addTearDown(avisos.close);
      final c = ProviderContainer.test(
        overrides: [
          pistaDeRedProvider.overrideWithValue(() async => true),
          avisosDeRedProvider.overrideWithValue(
            () => const Stream<bool>.empty(),
          ),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 28, 10)),
          veredictoAhoraProvider.overrideWithValue(
            () async => Veredicto.noLoSe,
          ),
          avisosDeVeredictoProvider.overrideWithValue(() => avisos.stream),
        ],
      );
      addTearDown(c.dispose);
      c.listen(saludDeLaRedProvider, (_, _) {});

      await pumpEventQueue();

      expect(
        c.read(saludDeLaRedProvider).vaMal,
        isFalse,
        reason:
            'convertir «no lo sé» en «no hay salida» dejaría el escritorio con '
            'el aviso puesto para siempre, que es el aviso que deja de leerse',
      );
      // Y el camino largo sigue entero donde no hay veredicto: tres caídas.
      final salud = c.read(saludDeLaRedProvider.notifier);
      for (var i = 0; i < 3; i++) {
        salud.anotarIntento(llego: false);
      }
      expect(c.read(saludDeLaRedProvider).vaMal, isTrue);
    });

    test('en Android sí se pregunta, y se entiende lo que contesta', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(hayVeredictoDelSistema, isTrue);

      const canal = MethodChannel(
        'cloud.procovar.reparto/veredicto_de_red_ahora',
      );
      final mensajero =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => mensajero.setMockMethodCallHandler(canal, null));

      for (final caso in {
        'valida': Veredicto.valida,
        'noValida': Veredicto.noValida,
        'sinRed': Veredicto.sinRed,
        // Una palabra que no conocemos es una versión del canal que no es ésta.
        // No se adivina, y sobre todo no se adivina hacia «va mal».
        'lo_que_sea': Veredicto.noLoSe,
      }.entries) {
        mensajero.setMockMethodCallHandler(canal, (_) async => caso.key);
        expect(await veredictoDelSistemaAhora(), caso.value);
      }
    });

    test('un canal que revienta es «no lo sé», no «no hay salida»', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const canal = MethodChannel(
        'cloud.procovar.reparto/veredicto_de_red_ahora',
      );
      final mensajero =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => mensajero.setMockMethodCallHandler(canal, null));
      mensajero.setMockMethodCallHandler(
        canal,
        (_) async => throw PlatformException(code: 'roto'),
      );

      expect(
        await veredictoDelSistemaAhora(),
        Veredicto.noLoSe,
        reason:
            'rendirse aquí pintaría «sin conexión» delante de alguien que está '
            'trabajando, por un fallo nuestro que no tiene nada que ver',
      );
    });
  });
}

/// Un temporizador que no corre: lo dispara la prueba cuando quiere.
///
/// Un `Timer` de verdad dentro de una prueba la hace depender del reloj de la
/// máquina, y esas se cuelgan en vez de fallar (`CLAUDE.md` §5).
class _Esperas {
  final List<_EsperaFalsa> creadas = [];

  Timer crear(Duration duracion, void Function() alSonar) {
    final espera = _EsperaFalsa(duracion, alSonar);
    creadas.add(espera);
    return espera;
  }

  _EsperaFalsa get ultima => creadas.last;
}

class _EsperaFalsa implements Timer {
  _EsperaFalsa(this.duracion, this._alSonar);

  final Duration duracion;
  final void Function() _alSonar;
  bool cancelada = false;

  void sonar() {
    if (!cancelada) _alSonar();
  }

  @override
  void cancel() => cancelada = true;

  @override
  bool get isActive => !cancelada;

  @override
  int get tick => 0;
}
