// EL RECORRIDO REAL (tarea 3) Y EL HISTORIAL POR VEHICULO (tarea 4), contra un servidor de mentira.
//
// Se vigila lo que la oficina lee: que cada estado diga lo suyo con palabras (cargando, sin puntos, sin red), que las horas sean las
// REALES de cada parada, que el cobro y el resultado salgan, que el aviso de marca lejana se vea, y que desde el historial de un
// vehículo se llegue al recorrido de una ruta.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/distribucion/vista/historial_del_vehiculo.dart';
import 'package:reparto/pantallas/distribucion/vista/recorrido_real.dart';
import 'package:reparto/pantallas/rutas/vista/croquis_de_ruta.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  group('el recorrido real', () {
    testWidgets(
      'con puntos: resumen, mapa con la traza y cada parada con su hora, resultado y cobro',
      (tester) async {
        final api = ApiDePrueba(
          (_) async => RespuestaFalsa(200, trackDeEjemplo()),
        );
        await montar(
          tester,
          const SingleChildScrollView(
            child: RecorridoRealDeLaRuta(rutaId: 'R1'),
          ),
          api,
        );

        expect(api.servidor.vistas.single.ruta, '/routes/R1/track');
        expect(find.byKey(claveDelResumenDelRecorrido), findsOneWidget);
        expect(find.text('3 h'), findsOneWidget); // duración total
        expect(find.text('Paradas marcadas'), findsOneWidget);
        expect(find.text('2 de 3'), findsOneWidget);
        // el mapa se dibuja SOLO con la traza: no hay leyenda del plan.
        expect(find.byKey(CroquisDeRuta.clave), findsOneWidget);
        expect(find.textContaining('Línea morada'), findsOneWidget);

        // Parada 1: la hora REAL (la del aparato), entregada y cobrada, con sus tiempos y su nota.
        final p1 = find.byKey(claveDeLaParadaReal(1));
        expect(
          find.descendant(
            of: p1,
            matching: find.textContaining(
              'Entregada · ${horaDe(DateTime.utc(2026, 11, 4, 13, 40).toLocal())}',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: p1, matching: find.text('Cobrada')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: p1,
            matching: find.textContaining('Desde la anterior: 40 min'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: p1,
            matching: find.textContaining('En la parada: 20 min'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: p1,
            matching: find.textContaining('Dejado en la puerta'),
          ),
          findsOneWidget,
        );
        // Parada 2: devuelta, no cobrada, y marcada lejos de su punto.
        final p2 = find.byKey(claveDeLaParadaReal(2));
        expect(
          find.descendant(of: p2, matching: find.textContaining('Devuelta')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: p2, matching: find.text('No cobrada')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: p2,
            matching: find.textContaining(
              'puede que se marcara sin estar allí',
            ),
          ),
          findsOneWidget,
        );
        // Parada 3: sin marcar, y sin aviso inventado.
        final p3 = find.byKey(claveDeLaParadaReal(3));
        expect(
          find.descendant(of: p3, matching: find.textContaining('Sin marcar')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: p3,
            matching: find.textContaining('puede que se marcara'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'una ruta en curso dice que sigue en ruta y no inventa la duración',
      (tester) async {
        final api = ApiDePrueba(
          (_) async =>
              RespuestaFalsa(200, trackDeEjemplo(estado: 'in_progress')),
        );
        await montar(
          tester,
          const SingleChildScrollView(
            child: RecorridoRealDeLaRuta(rutaId: 'R1'),
          ),
          api,
        );
        expect(find.text('Sigue en ruta'), findsOneWidget);
      },
    );

    testWidgets('si el servidor la recortó, se dice', (tester) async {
      final api = ApiDePrueba(
        (_) async => RespuestaFalsa(200, trackDeEjemplo(truncado: true)),
      );
      await montar(
        tester,
        const SingleChildScrollView(child: RecorridoRealDeLaRuta(rutaId: 'R1')),
        api,
      );
      expect(find.textContaining('el servidor la recortó'), findsOneWidget);
    });

    testWidgets('sin puntos: lo dice con palabras y no dibuja un mapa vacío', (
      tester,
    ) async {
      final api = ApiDePrueba(
        (_) async => RespuestaFalsa(200, trackDeEjemplo(conPuntos: false)),
      );
      await montar(tester, const RecorridoRealDeLaRuta(rutaId: 'R1'), api);
      expect(find.byKey(claveDelRecorridoVacio), findsOneWidget);
      expect(
        find.textContaining('todavía no tiene recorrido del GPS'),
        findsOneWidget,
      );
      expect(find.byKey(CroquisDeRuta.clave), findsNothing);
    });

    testWidgets('sin red: dice el motivo y ofrece reintentar', (tester) async {
      final api = ApiDePrueba((_) async => null);
      await montar(tester, const RecorridoRealDeLaRuta(rutaId: 'R1'), api);
      expect(
        find.textContaining(
          'No se pudo leer el recorrido: Sin conexión con el servidor.',
        ),
        findsOneWidget,
      );

      api.contesta = (_) async => RespuestaFalsa(200, trackDeEjemplo());
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);
      expect(find.byKey(claveDelResumenDelRecorrido), findsOneWidget);
    });

    testWidgets('un 403 (no es de la oficina) sale con la frase del servidor', (
      tester,
    ) async {
      final api = ApiDePrueba(
        (_) async => RespuestaFalsa(403, {'error': 'sin_permiso_reparto'}),
      );
      await montar(tester, const RecorridoRealDeLaRuta(rutaId: 'R1'), api);
      expect(find.textContaining('sin_permiso_reparto'), findsOneWidget);
    });
  });

  group('la entrada desde el detalle de la ruta', () {
    testWidgets('con puntos sale el botón', (tester) async {
      final api = ApiDePrueba(
        (_) async => RespuestaFalsa(200, trackDeEjemplo()),
      );
      await montar(
        tester,
        const EntradaAlRecorridoReal(rutaId: 'R1', titulo: 'RT-001'),
        api,
      );
      expect(find.byKey(EntradaAlRecorridoReal.claveDelBoton), findsOneWidget);

      await tester.tap(find.byKey(EntradaAlRecorridoReal.claveDelBoton));
      await tester.pumpAndSettle();
      expect(find.text('Recorrido real · RT-001'), findsOneWidget);
      expect(find.byKey(claveDelResumenDelRecorrido), findsOneWidget);
    });

    testWidgets('SIN puntos no hay botón, hay una frase', (tester) async {
      final api = ApiDePrueba(
        (_) async => RespuestaFalsa(200, trackDeEjemplo(conPuntos: false)),
      );
      await montar(
        tester,
        const EntradaAlRecorridoReal(rutaId: 'R1', titulo: 'RT-001'),
        api,
      );
      expect(find.byKey(EntradaAlRecorridoReal.claveDelBoton), findsNothing);
      expect(
        find.text('Todavía no hay recorrido del GPS de esta ruta.'),
        findsOneWidget,
      );
    });
  });

  group('el historial de un vehículo', () {
    Map<String, Object?> historial() => {
      'vehiculoId': 'V1',
      'rutas': [
        {
          'id': 'R1',
          'codigo': 'RT-001',
          'nombre': 'Vieja',
          'estado': 'completed',
          'fecha': utc(12, 0).replaceFirst('2026-11-04', '2026-11-01'),
          'inicio': utc(13, 0),
          'fin': utc(15, 30),
          'km': 21.5,
          'distribuidorId': 'D1',
          'distribuidor': 'Felix',
          'paradas': 5,
          'entregadas': 3,
          'devueltas': 2,
          'cobradas': 3,
          'puntos': 120,
        },
        {
          'id': 'R2',
          'codigo': 'RT-002',
          'estado': 'completed',
          'fecha': utc(12, 0),
          'km': 8.0,
          'paradas': 1,
          'entregadas': 1,
          'devueltas': 0,
          'cobradas': 0,
          'puntos': 0,
        },
      ],
    };

    testWidgets(
      'lista cada ruta con quién la hizo, sus cuentas, km y duración, la más reciente primero',
      (tester) async {
        final api = ApiDePrueba(
          (p) async => RespuestaFalsa(
            200,
            p.ruta.endsWith('/historial') ? historial() : trackDeEjemplo(),
          ),
        );
        await montar(tester, const HistorialDelVehiculo(vehiculoId: 'V1'), api);

        expect(api.servidor.vistas.first.ruta, '/vehicles/V1/historial');
        final filas = tester
            .widgetList(
              find.byWidgetPredicate(
                (w) =>
                    w.key is ValueKey &&
                    '${(w.key! as ValueKey).value}'.startsWith(
                      'historial-ruta-',
                    ),
              ),
            )
            .toList();
        expect(
          [for (final f in filas) '${(f.key! as ValueKey).value}'],
          ['historial-ruta-R2', 'historial-ruta-R1'],
        );

        final r1 = find.byKey(claveDeLaRutaDelHistorial('R1'));
        expect(
          find.descendant(of: r1, matching: find.text('Lo hizo Felix')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: r1,
            matching: find.textContaining(
              '5 paradas · 3 entregadas · 2 devueltas · 3 cobradas',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: r1,
            matching: find.textContaining('21.50 km · 2 h 30 min'),
          ),
          findsOneWidget,
        );
        // La que no tiene puntos lo dice y no se puede abrir.
        expect(
          find.descendant(
            of: find.byKey(claveDeLaRutaDelHistorial('R2')),
            matching: find.text('Sin recorrido del GPS'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('al tocar una ruta con GPS se abre su recorrido real', (
      tester,
    ) async {
      final api = ApiDePrueba(
        (p) async => RespuestaFalsa(
          200,
          p.ruta.endsWith('/historial') ? historial() : trackDeEjemplo(),
        ),
      );
      await montar(
        tester,
        const SingleChildScrollView(
          child: HistorialDelVehiculo(vehiculoId: 'V1'),
        ),
        api,
      );

      await tester.tap(find.byKey(claveDeLaRutaDelHistorial('R1')));
      await tester.pumpAndSettle();
      await asentar(tester);
      expect(api.servidor.vistas.last.ruta, '/routes/R1/track');
      expect(find.byKey(claveDelResumenDelRecorrido), findsOneWidget);
    });

    testWidgets('un vehículo sin rutas lo dice', (tester) async {
      final api = ApiDePrueba(
        (_) async =>
            RespuestaFalsa(200, {'vehiculoId': 'V1', 'rutas': <Object?>[]}),
      );
      await montar(tester, const HistorialDelVehiculo(vehiculoId: 'V1'), api);
      expect(find.text(TextosDelHistorial.vacio), findsOneWidget);
    });

    testWidgets('sin red dice por qué', (tester) async {
      final api = ApiDePrueba((_) async => null);
      await montar(tester, const HistorialDelVehiculo(vehiculoId: 'V1'), api);
      expect(
        find.textContaining(
          'No se pudo leer el historial: Sin conexión con el servidor.',
        ),
        findsOneWidget,
      );
    });
  });
}
