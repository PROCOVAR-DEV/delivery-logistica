import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/sincro/vigia.dart';

/// EL VIGIA, con la red y el reloj inyectados.
///
/// Ni un `sleep` ni un `Future.delayed`: el temporizador es de mentira y la
/// prueba lo dispara a mano. Un `Timer.periodic` de verdad en una prueba es un
/// temporizador colgado que falla por lo que no es — y aqui lo que se comprueba
/// es justamente que no quede ninguno vivo.
class TemporizadorFalso implements Timer {
  TemporizadorFalso(this.periodo, this.alTocar);

  final Duration periodo;
  final void Function(Timer) alTocar;

  bool cancelado = false;
  int _tics = 0;

  /// Un tic, como si hubiera pasado el periodo.
  void tocar() {
    if (cancelado) {
      throw StateError('un temporizador cancelado no puede tocar');
    }
    _tics++;
    alTocar(this);
  }

  @override
  void cancel() => cancelado = true;

  @override
  bool get isActive => !cancelado;

  @override
  int get tick => _tics;
}

void main() {
  late StreamController<bool> red;
  late List<String> disparos;
  late List<TemporizadorFalso> temporizadores;

  setUp(() {
    red = StreamController<bool>.broadcast();
    disparos = <String>[];
    temporizadores = <TemporizadorFalso>[];
  });

  tearDown(() => red.close());

  /// El reloj de las pruebas, quieto. Lo que se mueve es la marca de la bajada,
  /// que es mas facil de leer que mover la hora.
  final ahora = DateTime(2026, 9, 15, 10);

  VigiaDeSincronizacion montar({
    Future<void> Function(String, String?)? ciclo,
    Duration periodo = const Duration(minutes: 5),
    EstadoDeLoQueHay? hay,
  }) => VigiaDeSincronizacion(
    ciclo:
        ciclo ??
        (motivo, _) async {
          disparos.add(motivo);
        },
    avisosDeRed: () => red.stream,
    periodo: periodo,
    crearTemporizador: (cuanto, alTocar) {
      final t = TemporizadorFalso(cuanto, alTocar);
      temporizadores.add(t);
      return t;
    },
    loQueHay: () async => hay ?? EstadoDeLoQueHay.noSeSabe,
    reloj: () => ahora,
  );

  /// Deja correr las microtareas pendientes. No avanza el reloj: no hace falta.
  Future<void> asentar() => Future<void>.delayed(Duration.zero);

  group('el aviso de red', () {
    test('volvio la red: se dispara un ciclo', () async {
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      red.add(true);
      await asentar();

      expect(disparos, ['volvio la red']);
    });

    test('se FUE la red: no se dispara nada', () async {
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      red.add(false);
      await asentar();

      expect(
        disparos,
        isEmpty,
        reason:
            'sin red no hay nada que intentar; la aplicacion ya se comporta '
            'igual siempre',
      );
    });

    test('el aviso es una PISTA: dos avisos son dos intentos', () async {
      // El vigia no decide si hay red ni se acuerda de nada: dispara intentos.
      // Quien impide que se solapen es el candado del ciclo, no esto — asi un
      // primer intento que fallo porque el wifi mentia se vuelve a intentar.
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      red
        ..add(true)
        ..add(true);
      await asentar();

      expect(disparos, ['volvio la red', 'volvio la red']);
    });

    test('un error del plugin no tumba la vigilancia', () async {
      // Un destino sin soporte, o una prueba sin canales de plugin. Queda el
      // reloj, que es justamente para esto.
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      red.addError(StateError('el canal no existe'));
      await asentar();
      red.add(true);
      await asentar();

      expect(vigia.andando, isTrue);
      expect(disparos, ['volvio la red']);
    });
  });

  group('el reloj', () {
    test('toca y dispara un ciclo, por si el aviso no llega nunca', () async {
      // En web es lo normal: no hay aviso de connectivity y sin el reloj el dia
      // no subiria jamas.
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      expect(temporizadores, hasLength(1));
      expect(temporizadores.single.periodo, const Duration(minutes: 5));

      temporizadores.single.tocar();
      await asentar();

      expect(disparos, ['toco el reloj']);
    });

    test('arrancar dos veces no monta dos relojes', () async {
      final vigia = montar()
        ..arrancar()
        ..arrancar();
      addTearDown(vigia.parar);

      expect(temporizadores, hasLength(1));
    });
  });

  group('primer plano', () {
    test('detras se para el reloj; delante vuelve y se intenta ya', () async {
      // Sin decirle nada de lo que hay, o sea `noSeSabe`: ante la duda se
      // sincroniza. Es el defecto seguro.
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      vigia.enPrimerPlano(false);
      expect(vigia.hayTemporizador, isFalse);
      expect(temporizadores.single.cancelado, isTrue);
      expect(disparos, isEmpty);

      vigia.enPrimerPlano(true);
      await asentar();

      expect(vigia.hayTemporizador, isTrue);
      expect(
        disparos,
        ['la aplicacion volvio delante'],
        reason:
            'es el momento en que alguien saca el telefono del bolsillo '
            'despues de la mannana entera sin cobertura',
      );
    });

    /// ACOTAR EL VOLVER DELANTE — 15/09/2026.
    ///
    /// Queja de Jose: con alt-tab la barra superior decia «actualizando…» sin
    /// parar, porque cambiar de ventana y volver disparaba un ciclo entero cada
    /// vez. La regla nueva vale para los TRES destinos, no solo para la web.
    group('acotado: volver delante no es siempre un ciclo', () {
      test('alt-tab con los datos recien traidos: NO se dispara nada', () async {
        final vigia = montar(
          hay: EstadoDeLoQueHay(
            bajadaAt: ahora.subtract(const Duration(seconds: 20)),
          ),
        )..arrancar();
        addTearDown(vigia.parar);

        vigia.enPrimerPlano(false);
        vigia.enPrimerPlano(true);
        await asentar();

        expect(
          disparos,
          isEmpty,
          reason:
              'veinte segundos de alt-tab no son motivo para un ciclo entero; '
              'un «actualizando…» encendido siempre deja de leerse',
        );
        // Pero el reloj vuelve a correr: lo que se acota es el disparo, no la
        // vigilancia.
        expect(vigia.hayTemporizador, isTrue);
      });

      test('con la edad de un periodo SI se dispara: es el tic que se comio la '
          'pestanna en segundo plano', () async {
        final vigia = montar(
          hay: EstadoDeLoQueHay(
            bajadaAt: ahora.subtract(const Duration(minutes: 5)),
          ),
        )..arrancar();
        addTearDown(vigia.parar);

        vigia.enPrimerPlano(false);
        vigia.enPrimerPlano(true);
        await asentar();

        expect(disparos, ['la aplicacion volvio delante']);
      });

      test(
        'con algo SIN SUBIR se dispara aunque los datos sean de hace nada',
        () async {
          // Lo unico que se puede perder de verdad es el trabajo hecho: una
          // parada marcada a las cuatro que nunca subio no se vuelve a hacer
          // sola. Ahi molestar es barato.
          final vigia = montar(
            hay: EstadoDeLoQueHay(
              bajadaAt: ahora.subtract(const Duration(seconds: 5)),
              sinSubir: 23,
            ),
          )..arrancar();
          addTearDown(vigia.parar);

          vigia.enPrimerPlano(false);
          vigia.enPrimerPlano(true);
          await asentar();

          expect(disparos, ['la aplicacion volvio delante']);
        },
      );

      test('sin bajar NUNCA se dispara: null no es «hace poco»', () async {
        final vigia = montar(hay: const EstadoDeLoQueHay())..arrancar();
        addTearDown(vigia.parar);

        vigia.enPrimerPlano(false);
        vigia.enPrimerPlano(true);
        await asentar();

        expect(disparos, ['la aplicacion volvio delante']);
      });

      test('una bajada en el FUTURO se trata como edad desconocida', () async {
        // El reloj del aparato se mueve —se cambia a mano, se va con la
        // bateria, salta de zona horaria (`sincronizacion.md` §1)—. Con la
        // marca por delante del reloj la edad no se sabe, y ante la duda se
        // sincroniza.
        final vigia = montar(
          hay: EstadoDeLoQueHay(bajadaAt: ahora.add(const Duration(hours: 3))),
        )..arrancar();
        addTearDown(vigia.parar);

        vigia.enPrimerPlano(false);
        vigia.enPrimerPlano(true);
        await asentar();

        expect(disparos, ['la aplicacion volvio delante']);
      });

      test(
        'el umbral es EL PERIODO, asi que en web se acota mas corto',
        () async {
          // Con el periodo de la web, dato de hace tres minutos ya tiene edad.
          final vigia = montar(
            periodo: VigiaDeSincronizacion.periodoEnWeb,
            hay: EstadoDeLoQueHay(
              bajadaAt: ahora.subtract(const Duration(minutes: 3)),
            ),
          )..arrancar();
          addTearDown(vigia.parar);

          vigia.enPrimerPlano(false);
          vigia.enPrimerPlano(true);
          await asentar();

          expect(disparos, ['la aplicacion volvio delante']);

          // Y con el de la APK, el MISMO dato todavia no la tiene. Es la misma
          // regla leida con dos relojes, no dos reglas.
          final enLaApk = montar(
            hay: EstadoDeLoQueHay(
              bajadaAt: ahora.subtract(const Duration(minutes: 3)),
            ),
          );
          expect(
            enLaApk.valeLaPenaAlVolver(
              EstadoDeLoQueHay(
                bajadaAt: ahora.subtract(const Duration(minutes: 3)),
              ),
            ),
            isFalse,
          );
        },
      );

      test('si se cierra la sesion mientras se mira que hay, no se dispara', () async {
        // Entre la pregunta a la base y la respuesta cabe una salida. Un ciclo
        // disparado ahi correria sobre una sesion muerta.
        final vigia = montar(hay: const EstadoDeLoQueHay())..arrancar();

        vigia.enPrimerPlano(false);
        vigia.enPrimerPlano(true);
        vigia.parar();
        await asentar();

        expect(disparos, isEmpty);
      });
    });
  });

  group('el ritmo de cada destino', () {
    test('en web el reloj va mas seguido, porque es lo UNICO que trae los '
        'cambios', () {
      // En la web no queda ni un gesto para traer el dia a mano: se le quitaron
      // la pieza del Panel y la franja de estado. Si este numero se sube, la
      // oficina mira pedidos viejos sin ningun sitio donde darle.
      expect(
        VigiaDeSincronizacion.periodoEnWeb,
        lessThan(VigiaDeSincronizacion.periodoPorDefecto),
      );
      expect(VigiaDeSincronizacion.periodoEnWeb, const Duration(minutes: 2));
      expect(
        VigiaDeSincronizacion.periodoPorDefecto,
        const Duration(minutes: 5),
      );
    });
  });

  group('al cerrar sesion', () {
    test('NO queda ningun temporizador vivo ni nadie escuchando', () async {
      final vigia = montar()..arrancar();

      expect(vigia.hayTemporizador, isTrue);
      expect(red.hasListener, isTrue);

      vigia.parar();

      expect(vigia.andando, isFalse);
      expect(vigia.hayTemporizador, isFalse);
      expect(
        temporizadores.single.cancelado,
        isTrue,
        reason:
            'un temporizador vivo despues de salir es trabajo corriendo '
            'sobre una sesion muerta',
      );

      await asentar();
      expect(red.hasListener, isFalse);
    });

    test('despues de parar, ni el aviso de red despierta nada', () async {
      final vigia = montar()..arrancar();
      vigia.parar();
      await asentar();

      red.add(true);
      await asentar();

      expect(disparos, isEmpty);
    });

    test('se puede volver a arrancar al entrar otra vez', () async {
      final vigia = montar()
        ..arrancar()
        ..parar();
      await asentar();

      vigia.arrancar();
      addTearDown(vigia.parar);
      red.add(true);
      await asentar();

      expect(disparos, ['volvio la red']);
      expect(temporizadores, hasLength(2));
      expect(temporizadores.last.cancelado, isFalse);
    });
  });
}
