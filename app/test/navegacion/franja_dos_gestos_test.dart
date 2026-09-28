import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/franja_de_estado.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/salud.dart';
import 'package:reparto/nucleo/sincro/huerfanos.dart';

/// LOS DOS GESTOS DEL DÍA SE VEN, Y SUBIR NO DEPENDE DE QUE HAYA PENDIENTES.
///
/// Jose, 16/09/2026: «necesito tambien via rapida para enviar los datos y los
/// recibirlos q tengo q ir a panel y revisarlos por ahi».
///
/// Los dos gestos ya existían y ninguno se veía: traer el día se pulsaba tocando
/// la franja entera, y entregarlo tocando el número de «`<n>` sin subir». Y ahí
/// había un hueco de verdad: **cuando el número era cero, desaparecía la única
/// puerta a entregar el día**. Quien acaba de cerrar una ruta y quiere
/// asegurarse de que subió no tenía dónde darle.
void main() {
  Future<void> montar(
    WidgetTester tester, {
    required int pendientes,
    bool sinConexion = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          frescuraGlobalProvider.overrideWith(
            (ref) => Stream<DateTime?>.value(
              DateTime.now().subtract(const Duration(hours: 2)),
            ),
          ),
          sinSubirProvider.overrideWith((ref) => Stream<int>.value(pendientes)),
          // Igual que `sinSubirProvider`: se sustituye el proveedor de hoja
          // para no abrir una base de verdad en una prueba de widget. Lo que
          // pinta va en `la_franja_dice_lo_que_no_sube_test.dart`.
          trabajoHuerfanoProvider.overrideWith(
            (ref) =>
                Stream<List<TrabajoHuerfano>>.value(const <TrabajoHuerfano>[]),
          ),
          // Y lo mismo con los descartados —lo que subió y salió con menos de
          // lo que se puso—, por la misma razón: es un proveedor de hoja que
          // lee la cola. Lo que pinta va en
          // `la_franja_dice_lo_que_no_subio_al_camion_test.dart`.
          descartadosProvider.overrideWith(
            (ref) => Stream<List<Apunte>>.value(const <Apunte>[]),
          ),
          if (sinConexion) saludDeLaRedProvider.overrideWith(_SaludMala.new),
        ],
        child: MaterialApp(
          theme: temaDeReparto(),
          home: const Scaffold(body: FranjaDeEstado()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('los dos botones están, con nada pendiente', (tester) async {
    await montar(tester, pendientes: 0);

    expect(
      find.byIcon(Icons.cloud_download_outlined),
      findsOneWidget,
      reason: 'traer el día tiene que verse desde cualquier pantalla',
    );
    expect(
      find.byIcon(Icons.cloud_upload_outlined),
      findsOneWidget,
      reason:
          'ESTE es el hueco que había: con cero pendientes no quedaba ninguna '
          'puerta para subir, y quien cierra una ruta quiere asegurarse',
    );
    // En cero no se pinta el globo: un cero dentro de una insignia es ruido que
    // enseña a no mirar las insignias.
    expect(find.text('0'), findsNothing);
  });

  testWidgets('con pendientes, el número va sobre el botón de subir', (
    tester,
  ) async {
    await montar(tester, pendientes: 23);

    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    expect(
      find.text('23'),
      findsWidgets,
      reason: 'el número y el botón que lo baja a cero van juntos',
    );
  });

  testWidgets('SIN CONEXIÓN la franja lo dice, en las siete pantallas', (
    tester,
  ) async {
    await montar(tester, pendientes: 6, sinConexion: true);

    expect(
      find.text('Sin conexión'),
      findsOneWidget,
      reason:
          'palabras de Jose: «tienes q notificar q estas sin conexion ok la '
          'aplicacion tiene q informar eso». La tarjeta del Panel sólo se ve '
          'en una pantalla; esta franja está en las siete',
    );
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });

  testWidgets('CON conexión no se nombra: no hay nada que avisar', (
    tester,
  ) async {
    await montar(tester, pendientes: 6);

    expect(find.text('Sin conexión'), findsNothing);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('sin conexión NO se gira: el giro diría que algo avanza', (
    tester,
  ) async {
    await montar(tester, pendientes: 6, sinConexion: true);

    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason:
          'el ciclo sigue reintentando por detrás —y eso está bien—, pero un '
          'giro al lado de «Sin conexión» se contradice: uno dice que avanza y '
          'el otro que no hay por dónde',
    );
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });
}

/// Una salud de red que siempre dice que va mal, para la mitad de «sin
/// conexión» de la pareja.
class _SaludMala extends LaSalud {
  @override
  SaludDeLaRed build() =>
      const SaludDeLaRed(fallosSeguidos: SaludDeLaRed.fallosParaDarlaPorMala);
}
