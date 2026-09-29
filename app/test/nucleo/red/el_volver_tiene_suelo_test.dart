// UN SERVIDOR QUE SE CAE EN BUCLE NO PUEDE COSTAR CIENTOS DE PETICIONES.
//
// El aviso de «volví» (`avisoDeQueVolvimos`) no es gratis: cada uno dispara un
// ciclo de sincronización entero, un `GET /api/board` por tablero abierto y un
// `GET /vehicles` + `GET /settings` por pantalla de flota abierta. Con el corte
// normal del proxy —cada 300 s— está bien pagado y es justo lo que evita que una
// pantalla se quede vieja para siempre.
//
// El caso que hay que cerrar es otro, y lo encontró la auditoría del arreglo el
// 29/09/2026: **un servidor que acepta, manda el `listo` y se muere**. Es lo que
// pasa en un reinicio, o con un contenedor que no levanta. El `listo` reinicia
// la espera creciente del canal (`eventos_io.dart`, `intentos = 0`), así que la
// reconexión siguiente va al segundo — y sin suelo, cada vuelta sería un ciclo
// completo. Desde cada aparato a la vez, por la conexión de allá, contra un
// servidor que ya se está cayendo.
//
// No se midió pasando: la ruta estaba abierta y cerrarla es barato. Lo que NO se
// hace es callarlo — lo que se salta queda en el registro.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/eventos.dart'
    show avisoDeQueVolvimos, sueloEntreVolver;
import 'package:reparto/nucleo/refresco_en_vivo.dart';

void main() {
  late StreamController<String> delCanal;
  late DateTime ahora;

  setUp(() {
    delCanal = StreamController<String>.broadcast();
    ahora = DateTime(2026, 9, 29, 13, 0);
  });

  tearDown(() => delCanal.close());

  ProviderContainer montar() {
    final caja = ProviderContainer.test(
      overrides: [
        relojProvider.overrideWithValue(() => ahora),
        escuchaDeEventosProvider.overrideWithValue(
          (_, _, {renovarSesion, pulso}) => delCanal.stream,
        ),
      ],
    );
    return caja;
  }

  /// Escucha lo que sale del proveedor de verdad, que es donde vive el suelo.
  Future<List<String>> loQueSale(
    ProviderContainer caja,
    Future<void> Function() empujar,
  ) async {
    final salida = <String>[];
    final sub = caja.read(avisosDelServidorProvider).listen(salida.add);
    await Future<void>.delayed(Duration.zero);
    await empujar();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    return salida;
  }

  test('dos reconexiones seguidas son UN aviso, no dos', () async {
    final caja = montar();
    addTearDown(caja.dispose);

    final salida = await loQueSale(caja, () async {
      delCanal.add(avisoDeQueVolvimos);
      await Future<void>.delayed(Duration.zero);
      // Un segundo después, que es lo que tarda en reconectar cuando el
      // servidor acepta y se muere.
      ahora = ahora.add(const Duration(seconds: 1));
      delCanal.add(avisoDeQueVolvimos);
    });

    expect(
      salida,
      [avisoDeQueVolvimos],
      reason:
          'un servidor cayéndose reconecta al segundo, y cada «volví» cuesta un '
          'ciclo entero más un GET por cada pantalla abierta. Sin suelo, eso '
          'son cientos de peticiones por minuto contra un servidor que ya está '
          'mal, desde todos los aparatos a la vez',
    );
  });

  // Y LA OTRA MITAD, sin la cual el suelo tapa el arreglo entero: la reconexión
  // de verdad —cada 300 s, que es lo que corta el proxy— SIEMPRE pasa.
  test('la reconexión normal del proxy sí pasa', () async {
    final caja = montar();
    addTearDown(caja.dispose);

    final salida = await loQueSale(caja, () async {
      delCanal.add(avisoDeQueVolvimos);
      await Future<void>.delayed(Duration.zero);
      // Los 300 s del corte del proxy, que es el caso normal.
      ahora = ahora.add(const Duration(seconds: 300));
      delCanal.add(avisoDeQueVolvimos);
    });

    expect(
      salida,
      [avisoDeQueVolvimos, avisoDeQueVolvimos],
      reason:
          'el suelo se comió la reconexión de verdad. El proxy corta cada 300 s '
          'y ése es el único momento en que las pantallas se ponen al día: '
          'tragárselo deja el agujero que esto vino a cerrar',
    );
  });

  test('y el suelo está entre el bucle y el corte normal, no fuera', () {
    // Si alguien lo sube a más de 300 s, se come la reconexión buena; si lo baja
    // a menos de un segundo, no frena el bucle. Los dos fallos son silenciosos.
    expect(
      sueloEntreVolver,
      greaterThan(const Duration(seconds: 5)),
      reason: 'tan corto que no frena el bucle de un servidor reiniciándose',
    );
    expect(
      sueloEntreVolver,
      lessThan(const Duration(seconds: 300)),
      reason:
          'tan largo que se come la reconexión de los 300 s, que es la que pone '
          'las pantallas al día',
    );
  });

  test('un cambio de verdad NO lo frena el suelo', () async {
    final caja = montar();
    addTearDown(caja.dispose);

    final salida = await loQueSale(caja, () async {
      delCanal.add(CambioEnVivo.tablero);
      await Future<void>.delayed(Duration.zero);
      delCanal.add(CambioEnVivo.tablero);
    });

    expect(
      salida,
      [CambioEnVivo.tablero, CambioEnVivo.tablero],
      reason:
          'el suelo es sólo del «volví». Frenar los cambios de verdad es perder '
          'trabajo de alguien: dos tarjetas movidas seguidas son dos avisos',
    );
  });
}
