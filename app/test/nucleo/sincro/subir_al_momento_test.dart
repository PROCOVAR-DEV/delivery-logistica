import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/sincro/vigia.dart';

/// LO QUE SE ACABA DE HACER SE INTENTA SUBIR YA. No se espera al reloj.
///
/// La cola de salida es el aparato de **no tener** señal. Con señal no hay ninguna razón
/// para que arrastrar una tarjeta se quede cinco minutos esperando al temporizador, ni para
/// que alguien tenga que pulsar un botón.
///
/// Jose, 16/09/2026: «cuando hay conexión trabajaría sin estar dándole a subir todo el
/// tiempo y hiciera todo solo; el problema es cuando se trabaja sin conexión y hay que
/// traer el trabajo que se hizo sin conexión».
///
/// Se escucha LA TABLA de apuntes y no se avisa desde quien encola, a propósito: así entra
/// cualquier gesto lo escriba quien lo escriba, y la cola no tiene que saber nada del
/// ciclo — que además sería un ciclo de dependencias, porque el ciclo necesita la cola.
void main() {
  late StreamController<void> cola;
  late List<String> ciclos;
  late VigiaDeSincronizacion vigia;

  setUp(() {
    cola = StreamController<void>.broadcast();
    ciclos = <String>[];
    vigia = VigiaDeSincronizacion(
      ciclo: (motivo, _) async => ciclos.add(motivo),
      avisosDeRed: Stream<bool>.empty,
      avisosDeLaCola: () => cola.stream,
      // Sin temporizador: lo que se comprueba es el aviso, no el reloj.
      crearTemporizador: (_, _) => Timer(const Duration(days: 1), () {}),
    );
  });

  tearDown(() async {
    vigia.parar();
    await cola.close();
  });

  test('un apunte nuevo dispara el ciclo, sin esperar al reloj', () async {
    vigia.arrancar();
    cola.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(
      ciclos,
      ['se hizo algo'],
      reason:
          'sin esto, lo que se hace con señal espera al temporizador o a que '
          'alguien pulse un botón',
    );
  });

  test('sin arrancar no escucha nada', () async {
    cola.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(ciclos, isEmpty);
  });

  test('al parar se suelta la cola: nada vivo sin sesión', () async {
    vigia.arrancar();
    vigia.parar();
    cola.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(
      ciclos,
      isEmpty,
      reason:
          'un aviso vivo después de salir es trabajo corriendo sobre una '
          'sesión muerta',
    );
  });

  test('un fallo en el aviso no tumba la vigilancia', () async {
    // El reloj es justamente el respaldo de esto: si el aviso se cae, se sigue
    // sincronizando cada pocos minutos.
    vigia.arrancar();
    cola.addError(Exception('se rompió'));
    await Future<void>.delayed(Duration.zero);

    cola.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(ciclos, ['se hizo algo']);
  });

  /// EL CANAL EN VIVO: lo que cambia en el servidor se sabe en cuanto cambia.
  ///
  /// Hasta hoy, lo que hacía una persona no aparecía en la pantalla de otra hasta que
  /// pasaba el temporizador —dos minutos en la web, cinco en la APK—. Con dos personas
  /// trabajando el mismo tablero eso no es trabajar juntos, es trabajar por turnos sin
  /// saberlo. Jose, 16/09/2026: «hice un tablero en el móvil, moví cosas, y en la web no
  /// salió en tiempo real».
  ///
  /// El canal existía en el servidor desde el principio y **no lo escuchaba nadie**.
  group('el canal en vivo', () {
    late StreamController<String> servidor;

    setUp(() {
      servidor = StreamController<String>.broadcast();
      vigia = VigiaDeSincronizacion(
        ciclo: (motivo, _) async => ciclos.add(motivo),
        avisosDeRed: Stream<bool>.empty,
        avisosDelServidor: () => servidor.stream,
        crearTemporizador: (_, _) => Timer(const Duration(days: 1), () {}),
      );
    });

    tearDown(() async => servidor.close());

    test('un cambio en el servidor dispara el ciclo, y se dice cuál', () async {
      vigia.arrancar();
      servidor.add('tablero');
      await Future<void>.delayed(Duration.zero);

      expect(ciclos, ['cambió tablero en el servidor']);
    });

    test('al parar se suelta: nada vivo sin sesión', () async {
      vigia.arrancar();
      vigia.parar();
      servidor.add('tablero');
      await Future<void>.delayed(Duration.zero);

      expect(ciclos, isEmpty);
    });

    test('si el canal se cae, el reloj sigue: no se pierde el trabajo', () async {
      // El canal es una MEJORA, no un cimiento. Un proxy que corta o una red que se va no
      // pueden dejar a nadie sin sincronizar — sólo hacen que llegue más tarde.
      vigia.arrancar();
      servidor.addError(Exception('el proxy cortó'));
      await Future<void>.delayed(Duration.zero);

      expect(vigia.andando, isTrue, reason: 'la vigilancia sigue en pie');
      servidor.add('pedidos');
      await Future<void>.delayed(Duration.zero);
      expect(ciclos, ['cambió pedidos en el servidor']);
    });

    test('sin canal —la APK— no pasa nada: manda el temporizador', () async {
      final sinCanal = VigiaDeSincronizacion(
        ciclo: (motivo, _) async => ciclos.add(motivo),
        avisosDeRed: Stream<bool>.empty,
        crearTemporizador: (_, _) => Timer(const Duration(days: 1), () {}),
      );
      addTearDown(sinCanal.parar);

      sinCanal.arrancar();
      await Future<void>.delayed(Duration.zero);

      expect(ciclos, isEmpty);
      expect(sinCanal.andando, isTrue);
    });
  });
}
