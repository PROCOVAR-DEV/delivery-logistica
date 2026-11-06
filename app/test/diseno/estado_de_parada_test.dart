// EL ESTADO DE UNA PARADA (issue 26 de Amado, 06/11/2026): la regla que decide el estado vive en un
// sitio (`estadoDeParada`) y la etiqueta que lo pinta en otro (`EtiquetaDeEstadoDeParada`); esto ata
// las dos. Que el texto sea SIEMPRE visible, que cada estado tenga su icono y que se lea con sol
// (7 de contraste sobre el papel) se mide, no se mira.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/diseno/estado_de_parada.dart';
import 'package:reparto/diseno/tema.dart';

void main() {
  group('la regla: (resultado, cobroEntrega) -> estado', () {
    const casos = <(String?, String?, EstadoDeParada)>[
      (null, null, EstadoDeParada.pendiente),
      // Sin resultado no hay cobro que valga, venga lo que venga.
      (null, 'cobrado', EstadoDeParada.pendiente),
      ('entregado', 'cobrado', EstadoDeParada.entregadaCobrada),
      ('entregado', 'no_cobrado', EstadoDeParada.entregadaSinCobrar),
      // Entregada y nadie anoto el cobro: NO se inventa un «sin cobrar».
      ('entregado', null, EstadoDeParada.entregada),
      ('entregado', 'otra-cosa', EstadoDeParada.entregada),
      // Un devuelto no muestra cobro, ni siquiera si el servidor trae uno.
      ('devuelto', null, EstadoDeParada.noEntregada),
      ('devuelto', 'cobrado', EstadoDeParada.noEntregada),
      ('devuelto', 'no_cobrado', EstadoDeParada.noEntregada),
      ('no_entregada', null, EstadoDeParada.noEntregada),
      ('cancelado', null, EstadoDeParada.cancelada),
      ('cancelado', 'cobrado', EstadoDeParada.cancelada),
    ];
    for (final (resultado, cobro, esperado) in casos) {
      test('($resultado, $cobro) -> ${esperado.name}', () {
        expect(estadoDeParada(resultado, cobro), esperado);
      });
    }

    test('las palabras son las que pidio Amado', () {
      expect(
        {for (final e in EstadoDeParada.values) e.name: e.texto},
        {
          'pendiente': 'Pendiente',
          'entregadaCobrada': 'Entregada · cobrada',
          'entregadaSinCobrar': 'Entregada · sin cobrar',
          'entregada': 'Entregada',
          'noEntregada': 'No entregada',
          'cancelada': 'Cancelada',
        },
      );
    });
  });

  group('lo que se ve', () {
    test('cada estado tiene SU icono: ninguno se repite', () {
      final iconos = EstadoDeParada.values.map((e) => e.icono).toSet();
      expect(iconos.length, EstadoDeParada.values.length);
    });

    test('el color de cada estado se lee con sol: 7 de contraste sobre el papel Y el blanco', () {
      for (final e in EstadoDeParada.values) {
        expect(
          contrasteEntre(e.color, Colores.papel),
          greaterThanOrEqualTo(7),
          reason: '${e.texto} sobre el papel',
        );
        expect(
          contrasteEntre(e.color, Colores.blanco),
          greaterThanOrEqualTo(7),
          reason: '${e.texto} sobre el blanco',
        );
      }
    });

    testWidgets('la etiqueta lleva TEXTO, icono y borde, y ningun relleno', (
      tester,
    ) async {
      for (final e in EstadoDeParada.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: temaDeReparto(),
            home: Scaffold(body: Center(child: EtiquetaDeEstadoDeParada(e))),
          ),
        );
        expect(find.text(e.texto), findsOneWidget, reason: 'el texto SIEMPRE');
        expect(find.byIcon(e.icono), findsOneWidget, reason: e.texto);
        final caja = tester.widget<Container>(
          find
              .ancestor(
                of: find.byIcon(e.icono),
                matching: find.byType(Container),
              )
              .first,
        );
        final dec = caja.decoration! as BoxDecoration;
        expect(dec.color, isNull, reason: 'sin fondo relleno');
        expect(dec.border, isNotNull, reason: 'con borde');
        final texto = tester.widget<Text>(find.text(e.texto));
        expect(texto.style!.color, e.color);
      }
    });

    testWidgets('el motivo sale debajo solo si lo hay', (tester) async {
      Future<void> pinta(String? motivo) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EtiquetaDeEstadoDeParada(
              EstadoDeParada.noEntregada,
              motivo: motivo,
            ),
          ),
        ),
      );
      await pinta('El cliente cerró');
      expect(find.text('El cliente cerró'), findsOneWidget);
      await pinta('   ');
      expect(find.byType(Text), findsOneWidget);
      await pinta(null);
      expect(find.byType(Text), findsOneWidget);
    });
  });
}
