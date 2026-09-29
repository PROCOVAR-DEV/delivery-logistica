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
// # Y no hace falta que el canal mande ningún CAMBIO para saber que vive
//
// El canal late cada veinte segundos (`api/internal/api/eventos.go`,
// `latidoSSE`), y en la web, donde `EventSource` tira los latidos, el proxy corta
// cada 300 segundos exactos y cada reconexión manda `al-volver`.
//
// # LO QUE FALTABA, y por qué el polling seguía ahí — 29/09/2026
//
// El vigía sólo se enteraba del canal cuando llegaba un aviso **para una
// pantalla**: un `cambio`, o el `al-volver`. El latido no viajaba hasta aquí.
//
// Resultado: un canal perfectamente sano por el que no había cambiado nada en
// seis minutos —una oficina en calma— se leía como canal muerto, y el reloj pedía
// la vuelta entera. El polling seguía puesto, sólo que más espaciado.
//
// El latido llega ahora por `PulsoDelCanal`, que NO es un stream: por el stream
// de los avisos cada cosa cuesta una bajada, y un latido cada veinte segundos ahí
// sería exactamente lo contrario de lo que se viene a arreglar.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/eventos.dart'
    show PulsoDelCanal, avisoDeQueVolvimos;
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

  VigiaDeSincronizacion montar({PulsoDelCanal? pulso}) => VigiaDeSincronizacion(
    ciclo: (motivo, _) async => disparos.add(motivo),
    avisosDeRed: () => const Stream<bool>.empty(),
    avisosDelServidor: () => delCanal.stream,
    pulso: pulso,
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

  // ## LA PRUEBA DE QUE EL POLLING SE FUE DEL TODO — 29/09/2026
  //
  // Es el caso normal de una oficina en calma: el canal está abierto y sano, late
  // cada veinte segundos, y en el servidor no cambia nada durante diez minutos.
  //
  // Hasta hoy el vigía no se enteraba de esos latidos —sólo de los avisos que van
  // a una pantalla— y a los seis minutos daba el canal por muerto: el reloj pedía
  // la vuelta entera, y en la web cada dos minutos a partir de ahí.
  test('un canal que sólo late, sin un cambio en diez minutos, calla al reloj', () async {
    final pulso = PulsoDelCanal(reloj: () => ahora);
    final vigia = montar(pulso: pulso)..arrancar();
    addTearDown(vigia.parar);
    await Future<void>.delayed(Duration.zero);

    // Diez minutos de canal sano. NI UN aviso por el stream: nadie tocó nada en
    // el servidor, que es justamente el caso.
    for (var i = 0; i < 30; i++) {
      ahora = ahora.add(const Duration(seconds: 20));
      pulso.latio();
    }
    relojes.last.tocar();

    expect(
      disparos,
      isEmpty,
      reason:
          'el canal lleva diez minutos latiendo cada veinte segundos y el reloj '
          'pidió igual, porque no ha cambiado nada en seis minutos. Eso es el '
          'polling que Jose no quiere, sólo que más espaciado: con el canal sano '
          'el aparato hace CERO peticiones, nunca',
    );
  });

  // LA OTRA MITAD, sin la cual se cambia el polling por un aparato ciego: el
  // latido vale mientras haya latido.
  test('pero si el canal deja de latir, el reloj vuelve', () async {
    final pulso = PulsoDelCanal(reloj: () => ahora);
    final vigia = montar(pulso: pulso)..arrancar();
    addTearDown(vigia.parar);
    await Future<void>.delayed(Duration.zero);

    pulso.latio();
    // Más que el plazo: dieciocho latidos perdidos seguidos no son un canal.
    ahora = ahora.add(
      VigiaDeSincronizacion.elCanalSeDaPorVivo + const Duration(minutes: 1),
    );
    relojes.last.tocar();

    expect(
      disparos,
      contains('toco el reloj'),
      reason:
          'el canal dejó de latir y el reloj se fió del último latido para '
          'siempre. Un canal muerto no avisa de que está muerto: ese aparato se '
          'queda mudo y nadie se entera',
    );
  });
}
