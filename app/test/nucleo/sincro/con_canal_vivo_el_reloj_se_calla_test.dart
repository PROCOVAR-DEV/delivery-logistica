// CON EL CANAL VIVO, UN APARATO EN REPOSO HACE CERO PETICIONES.
//
// Jose, 29/09/2026: «el reloj no lo quiero, la verdad, porque eso es una
// pinga». Y tenía razón: con el canal en vivo funcionando, un reloj que pide
// cada pocos minutos es preguntar por si acaso algo que ya te van a contar.
//
// Lo que costaba: medido ese día en su teléfono, con la aplicación abierta y sin
// tocar nada, cada vuelta eran 3.255 bytes por la conexión de allá para traer
// exactamente nada.
//
// # Por qué el reloj no se quita del todo
//
// Porque sin él, un aparato que pierda el canal se queda **ciego para siempre y
// nadie se entera**. Y eso no es hipotético: ese mismo día un 401 dejó el canal
// muerto y el teléfono no volvió a abrirlo en media hora.
//
// Así que el reloj deja de ser el mecanismo y pasa a ser la red de seguridad:
// **mientras se sepa del canal, el tic no dispara nada.**
//
// # Y no hace falta que el canal mande nada para saber que vive
//
// El proxy lo corta cada 300 segundos exactos —medido en el registro de la api—
// y cada reconexión manda `al-volver`. O sea que por el canal llega algo cada
// cinco minutos como mucho, aunque no cambie nada en el servidor.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/eventos.dart' show avisoDeQueVolvimos;
import 'package:reparto/nucleo/sincro/vigia.dart';

/// Un temporizador de mentira que la prueba dispara a mano. Ni un `sleep`: un
/// `Timer.periodic` de verdad dentro de una prueba es un temporizador colgado
/// que falla por lo que no es.
class _ATiempo implements Timer {
  _ATiempo(this.alTocar);

  final void Function(Timer) alTocar;
  bool cancelado = false;

  void tocar() => alTocar(this);

  @override
  void cancel() => cancelado = true;
  @override
  bool get isActive => !cancelado;
  @override
  int get tick => 0;
}

void main() {
  late StreamController<String> delCanal;
  late List<String> disparos;
  late List<_ATiempo> relojes;
  late DateTime ahora;

  setUp(() {
    delCanal = StreamController<String>.broadcast();
    disparos = <String>[];
    relojes = <_ATiempo>[];
    ahora = DateTime(2026, 9, 29, 16, 0);
  });

  tearDown(() => delCanal.close());

  VigiaDeSincronizacion montar() => VigiaDeSincronizacion(
    ciclo: (motivo, _) async => disparos.add(motivo),
    avisosDeRed: () => const Stream<bool>.empty(),
    avisosDelServidor: () => delCanal.stream,
    reloj: () => ahora,
    crearTemporizador: (_, alTocar) {
      final t = _ATiempo(alTocar);
      relojes.add(t);
      return t;
    },
  );

  test('sin canal, el reloj SÍ dispara: es la red de seguridad', () async {
    final vigia = montar()..arrancar();
    addTearDown(vigia.parar);
    await Future<void>.delayed(Duration.zero);

    // Nunca llegó nada por el canal: es el aparato al que no le abre.
    relojes.last.tocar();

    expect(
      disparos,
      contains('toco el reloj'),
      reason:
          'sin canal y sin reloj, ese aparato se queda ciego para siempre y '
          'nadie se entera. Pasó de verdad el 29/09/2026 con un 401',
    );
  });

  test('con el canal vivo, el reloj NO pide nada', () async {
    final vigia = montar()..arrancar();
    addTearDown(vigia.parar);
    await Future<void>.delayed(Duration.zero);

    // El canal se reconecta —el proxy lo corta cada 300 s— y avisa.
    delCanal.add(avisoDeQueVolvimos);
    await Future<void>.delayed(Duration.zero);
    disparos.clear();

    // Un minuto después toca el reloj.
    ahora = ahora.add(const Duration(minutes: 1));
    relojes.last.tocar();

    expect(
      disparos,
      isEmpty,
      reason:
          'tocó el reloj con el canal vivo y pidió igual. Eso son 3.255 bytes '
          'por la conexión de allá para traer nada, y es exactamente el polling '
          'que Jose no quiere: con canal, un aparato en reposo hace CERO '
          'peticiones',
    );
  });

  // LA MITAD QUE EVITA CAMBIAR EL POLLING POR UN APARATO MUDO.
  test('pero si el canal lleva rato callado, el reloj vuelve a disparar', () async {
    final vigia = montar()..arrancar();
    addTearDown(vigia.parar);
    await Future<void>.delayed(Duration.zero);

    delCanal.add(avisoDeQueVolvimos);
    await Future<void>.delayed(Duration.zero);
    disparos.clear();

    // Más de lo que tarda el proxy en cortar y reconectar: si en todo ese rato
    // no ha llegado nada, el canal está muerto aunque nadie lo haya dicho.
    ahora = ahora.add(
      VigiaDeSincronizacion.elCanalSeDaPorVivo + const Duration(minutes: 1),
    );
    relojes.last.tocar();

    expect(
      disparos,
      contains('toco el reloj'),
      reason:
          'el canal lleva más de su plazo sin decir nada y el reloj se calló '
          'igual. Un canal muerto no avisa de que está muerto: si el reloj se '
          'fía de él para siempre, el aparato se queda mudo y sin señal ninguna',
    );
  });

  test('y un cambio de verdad también cuenta como que el canal vive', () async {
    final vigia = montar()..arrancar();
    addTearDown(vigia.parar);
    await Future<void>.delayed(Duration.zero);

    delCanal.add('pedidos');
    await Future<void>.delayed(Duration.zero);
    disparos.clear();

    ahora = ahora.add(const Duration(minutes: 1));
    relojes.last.tocar();

    expect(
      disparos,
      isEmpty,
      reason:
          'sólo se da por vivo con el «volví» y no con un cambio de verdad. '
          'Cualquier cosa que llegue por el canal demuestra que el canal está',
    );
  });
}
