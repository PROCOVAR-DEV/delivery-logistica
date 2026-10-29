// «VER ACTIVIDAD» DE ACCESOS — 29/10/2026.
//
// Se llega con `/dispositivos?aparato=<X-Aparato-Id>`. Se ata: que encuentra el aparato por ese id (sin importar mayúsculas), que dice
// la verdad cuando el sincronizador aún no lo conoce (sin inventar), que lo que no se ha subido nunca no sale como «0 horas», y que sus
// rechazos salen con el motivo literal y SOLO los suyos.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/actividad_de_aparato/estado/proveedores_actividad.dart';
import 'package:reparto/pantallas/actividad_de_aparato/vista/pantalla_actividad_de_aparato.dart';
import 'package:reparto/pantallas/sincronizacion/datos/panel_sincronizacion.dart';

const _instalacion = '0192f3c4-8a3b-7d0e-9d62-6a1f3b6f2c10';

EstadoDelSincronizador _estado({bool nunca = false}) =>
    EstadoDelSincronizador.deJson({
      'aparatos': [
        {
          'aparato': 'aaaaaaaa-0000-0000-0000-000000000001',
          'persona': 'persona-1',
          'sucursal': 'bbbbbbbb-0000-0000-0000-000000000001',
          'nombre': 'Samsung de Palma',
          'instalacion': _instalacion,
          'visto': '2026-10-29T14:00:00Z',
          'bajada': '2026-10-29T14:00:00Z',
          'subida': nunca ? null : '2026-10-29T13:00:00Z',
          'pendientes': 3,
          'rechazados': 1,
          'horas_sin_subir': nunca ? null : 2,
        },
        {
          'aparato': 'aaaaaaaa-0000-0000-0000-000000000002',
          'persona': 'persona-2',
          'sucursal': 'bbbbbbbb-0000-0000-0000-000000000001',
          'nombre': 'Otro aparato',
          'instalacion': '0192f3c4-8a3b-7d0e-9d62-6a1f3b6f2c99',
          'pendientes': 0,
          'rechazados': 1,
          'horas_sin_subir': 1,
        },
      ],
      'bandeja': [
        {
          'rechazo': 'r1',
          'aparato': 'aaaaaaaa-0000-0000-0000-000000000001',
          'persona': 'persona-1',
          'sucursal': 'bbbbbbbb-0000-0000-0000-000000000001',
          'clave': 'k1',
          'motivo': 'Ese pedido ya va en otra ruta',
          'metodo': 'POST',
          'ruta': '/routes',
          'rechazado': '2026-10-29T13:30:00Z',
        },
        {
          'rechazo': 'r2',
          'aparato': 'aaaaaaaa-0000-0000-0000-000000000002',
          'persona': 'persona-2',
          'sucursal': 'bbbbbbbb-0000-0000-0000-000000000001',
          'clave': 'k2',
          'motivo': 'MOTIVO DE OTRO APARATO',
          'metodo': 'POST',
          'ruta': '/board',
        },
      ],
      'sin_atender': <Object?>[],
    });

Future<void> _montar(
  WidgetTester t, {
  required String? instalacion,
  EstadoDelSincronizador? estado,
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        actividadDeAparatosProvider.overrideWith(
          (ref) async => estado ?? _estado(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PantallaActividadDeAparato(instalacion: instalacion),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'encuentra el aparato por su id de Accesos, sin importar mayúsculas',
    (t) async {
      await _montar(t, instalacion: _instalacion.toUpperCase());
      expect(find.text('Samsung de Palma'), findsWidgets);
      expect(find.text('Pendientes de subir'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    },
  );

  testWidgets(
    'enseña SOLO los rechazos de ese aparato, con su motivo literal',
    (t) async {
      await _montar(t, instalacion: _instalacion);
      expect(
        find.textContaining('Ese pedido ya va en otra ruta'),
        findsOneWidget,
      );
      expect(find.textContaining('MOTIVO DE OTRO APARATO'), findsNothing);
    },
  );

  testWidgets('quien nunca ha subido NO sale como «0 horas»', (t) async {
    await _montar(t, instalacion: _instalacion, estado: _estado(nunca: true));
    expect(find.text('Nunca ha subido'), findsOneWidget);
    expect(find.text('0 h'), findsNothing);
  });

  testWidgets(
    'un id que el sincronizador no conoce lo dice, sin inventar datos',
    (t) async {
      await _montar(t, instalacion: '0192f3c4-8a3b-7d0e-9d62-6a1f3b6f2c55');
      expect(
        find.textContaining('todavía no conoce este aparato'),
        findsOneWidget,
      );
      expect(find.text('Samsung de Palma'), findsNothing);
    },
  );

  testWidgets('sin ?aparato= pide el enlace de Accesos y no lee nada', (
    t,
  ) async {
    await _montar(t, instalacion: null);
    expect(find.textContaining('Falta el aparato'), findsOneWidget);
  });
}
