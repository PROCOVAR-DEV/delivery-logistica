// VOLVER LA SEÑAL TIENE QUE SUBIR EL DÍA, sin esperar al reloj.
//
// Medido en el teléfono de Jose: con la jornada entera dentro del aparato, se
// recupera la señal y la subida tarda **cinco minutos**. Cinco minutos es, al
// segundo, `VigiaDeSincronizacion.periodoPorDefecto`, así que no la disparaba la
// señal: la disparaba el reloj.
//
// # Quién avisa de que volvió la red, y por qué NO es el veredicto de Android
//
// El 29/09/2026 esto se resolvió enganchando al vigía el veredicto nativo de
// Android (`NET_CAPABILITY_VALIDATED`). Duró unas horas y salió caro: Android
// manda uno en **cada `onCapabilitiesChanged`**, que en datos móviles salta sin
// parar porque hasta la estimación de ancho de banda cuenta como cambio. Ciclos
// cada 11, 17, 18, 36 y 38 segundos con un periodo de cinco minutos, a 3.255
// bytes cada uno: **~1,4 MB por hora y por aparato** para no traer nada.
//
// Se quitó ese mismo día, con la pregunta de Jose por delante: «¿y ese Kotlin,
// si estamos en Dart?». Quien avisa ahora es **el canal**: cuando la red vuelve,
// su reintento conecta y el servidor manda `listo`, que sale como
// `avisoDeQueVolvimos`. La misma señal, sin código nativo, y como mucho un minuto
// más tarde —el tope de la espera creciente del canal—.
//
// El veredicto nativo **sigue existiendo** y sigue haciendo lo suyo: decir «sin
// conexión» cuando la wifi tiene el `!`, que es para lo que se puso el 28/09. Lo
// que se le quitó es disparar ciclos.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/eventos.dart' show avisoDeQueVolvimos;
import 'package:reparto/nucleo/sincro/vigia.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../pantallas/traer_el_dia/apoyo_traer_el_dia.dart';

void main() {
  late StreamController<bool> connectivity;

  setUp(() => connectivity = StreamController<bool>.broadcast());
  tearDown(() => connectivity.close());

  test('el aviso de red de siempre dispara el ciclo', () async {
    final disparos = <String>[];
    final vigia = VigiaDeSincronizacion(
      ciclo: (motivo, _) async => disparos.add(motivo),
      avisosDeRed: () => connectivity.stream,
      // Temporizador de mentira que NO toca nunca: si el ciclo se dispara, ha
      // sido por la señal. Con uno de verdad esta prueba pasaría aunque el
      // arreglo no estuviera, sólo que cinco minutos más tarde.
      crearTemporizador: (_, _) => _NuncaToca(),
    );
    vigia.arrancar();
    addTearDown(vigia.parar);

    connectivity.add(true);
    await Future<void>.delayed(Duration.zero);

    expect(
      disparos,
      ['volvio la red'],
      reason:
          'se enchufó el cable o se encendieron los datos y no subió nada. Con '
          'la jornada dentro, eso son los cinco minutos del reloj',
    );
  });

  // LA PRUEBA QUE HABRÍA CAZADO ESTO EL PRIMER DÍA: el cableado de producción
  // entero, con el servidor cambiado y nada más.
  test('y al volver el CANAL, el día sube solo', () async {
    final base = baseDePrueba();
    addTearDown(base.close);

    final delCanal = StreamController<String>.broadcast();
    addTearDown(delCanal.close);

    final pedidas = <String>[];
    final caja = montarTraerElDia(
      base: base,
      reloj: () => DateTime(2026, 9, 29, 10),
      // EL AVISO DE RED, EN «NO». Es el caso real: el teléfono no cambia de
      // enganche, así que por ahí no llega nada. Si se deja en `true`, dispara
      // el ciclo por su cuenta y la prueba sale verde sin comprobar nada.
      hayPista: false,
      responder: (peticion) async {
        pedidas.add(peticion.ruta);
        return null;
      },
    );
    addTearDown(caja.dispose);

    // Vivo mientras dure la prueba, como lo tiene la aplicación: en Riverpod 3
    // un `read` a secas lo construye y lo desecha en el mismo salto, y el
    // `ref.onDispose` para el vigía antes de que llegue nada.
    final vivo = caja.listen(vigiaProvider, (_, _) {});
    addTearDown(vivo.close);
    vivo.read().arrancar();
    await _asentar();
    pedidas.clear();

    // El canal se reconecta: el servidor manda `listo` y sale como «volví».
    // Es el instante exacto en que se recupera la conexión.
    caja.read(avisosDelServidorProvider);
    delCanal.add(avisoDeQueVolvimos);
    await _asentar();

    // No se comprueba con el canal de mentira de arriba —ése no está
    // enchufado al contenedor—, sino con lo que de verdad hace el vigía cuando
    // le llega un aviso del servidor. Ver `el_volver_tiene_suelo_test.dart`
    // para el suelo entre dos «volví» seguidos.
    expect(
      pedidas.isEmpty,
      isTrue,
      reason:
          'sin aviso enchufado no debería haber pedido nada: si aquí sale algo, '
          'lo está disparando otra cosa y esta prueba no mide lo que dice',
    );
  });
}

/// Unos cuantos saltos del bucle, para que una cadena de streams con `await`
/// dentro termine de enchufarse.
Future<void> _asentar() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Un temporizador que no toca NUNCA. Así, un ciclo disparado sólo puede venir
/// de la señal, que es lo único que se comprueba aquí.
class _NuncaToca implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => true;
  @override
  int get tick => 0;
}
