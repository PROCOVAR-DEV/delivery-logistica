import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/distribuidor/enlaces.dart';
import 'package:reparto/distribuidor/parada_actual.dart';
import 'package:reparto/nucleo/base/base.dart';

import '../pantallas/rutas/rutas_a_mano.dart';

Pedido p(
  String id, {
  int? orden,
  String? resultado,
  DateTime? at,
  double? lat,
  double? lng,
}) => paradaAMano(id: id, cliente: 'C$id', lat: lat, lng: lng).copyWith(
  stopOrder: Value(orden),
  resultado: Value(resultado),
  resultadoAt: Value(at),
);

void main() {
  group('la parada actual', () {
    test('es la primera SIN resultado por el orden de la ruta', () {
      final paradas = [
        p('c', orden: 3),
        p('a', orden: 1, resultado: ResultadoParada.entregado),
        p('b', orden: 2),
      ];
      expect(siguienteParada(paradas)!.id, 'b');
      expect(paradasHechas(paradas), 1);
      expect(todasMarcadas(paradas), isFalse);
    });

    test('las sin numero de orden van al final', () {
      final paradas = [p('x'), p('a', orden: 5)];
      expect(siguienteParada(paradas)!.id, 'a');
    });

    test('una devuelta cuenta como hecha (tiene resultado)', () {
      final paradas = [
        p('a', orden: 1, resultado: ResultadoParada.devuelto),
        p('b', orden: 2, resultado: ResultadoParada.entregado),
      ];
      expect(siguienteParada(paradas), isNull);
      expect(todasMarcadas(paradas), isTrue);
    });

    test('una ruta SIN paradas no se da por marcada', () {
      expect(todasMarcadas(const []), isFalse);
      expect(siguienteParada(const []), isNull);
    });
  });

  group('el cronometro de la parada', () {
    test('arranca en la ultima marca, o en la salida si no hay ninguna', () {
      final salida = DateTime(2026, 11, 4, 8);
      final a = DateTime(2026, 11, 4, 9);
      final b = DateTime(2026, 11, 4, 10);
      expect(inicioDeLaParada([p('a'), p('b')], salida), salida);
      expect(
        inicioDeLaParada([
          p('a', resultado: 'entregado', at: a),
          p('b', resultado: 'entregado', at: b),
        ], salida),
        b,
      );
    });

    test('se escribe 12:03 y 1:05:09, y nunca en negativo', () {
      expect(cronometro(const Duration(minutes: 12, seconds: 3)), '12:03');
      expect(
        cronometro(const Duration(hours: 1, minutes: 5, seconds: 9)),
        '1:05:09',
      );
      expect(cronometro(const Duration(seconds: -5)), '00:00');
    });
  });

  group('los enlaces', () {
    test('navegar es el de Google Maps, solo a ese punto, en coche', () {
      expect(
        enlaceParaNavegar(p('a', lat: 21.38, lng: -77.91)).toString(),
        'https://www.google.com/maps/dir/?api=1&destination=21.38,-77.91&travelmode=driving',
      );
    });

    test('sin punto no hay enlace', () {
      expect(enlaceParaNavegar(p('a')), isNull);
    });

    test('llamar deja digitos y un + inicial', () {
      expect(
        enlaceParaLlamar(' +53 5 123-4567 ').toString(),
        'tel:+5351234567',
      );
      expect(enlaceParaLlamar('5123 4567').toString(), 'tel:51234567');
      expect(enlaceParaLlamar(''), isNull);
      expect(enlaceParaLlamar(null), isNull);
    });
  });
}
