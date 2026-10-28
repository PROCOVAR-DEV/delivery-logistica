import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';
import 'package:reparto/nucleo/sincro/cuadre.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// EL CUADRE DIARIO DENTRO DE LA BAJADA (28/10/2026): una vez cada 20 horas, sólo con la bajada ENTERA y sólo en la
/// APK y el escritorio (los que arrastran copia propia: sin cola no hay cuadre). Si falla, no tumba la bajada.
void main() {
  late BaseLocal base;
  late RegistroDeFrescura frescura;
  var ahora = DateTime.utc(2026, 10, 28, 12);
  late int pedidosAlCuadre;
  late List<ResultadoDelCuadre> avisos;
  late bool cuadreFalla;
  late List<String> idsDelServidor;

  setUp(() async {
    base = baseDePrueba();
    ahora = DateTime.utc(2026, 10, 28, 12);
    frescura = RegistroDeFrescura(base, reloj: () => ahora);
    pedidosAlCuadre = 0;
    avisos = [];
    cuadreFalla = false;
    idsDelServidor = ['viva'];
    await frescura.rebajarLosPedidosUnaVez();
    await frescura.rebajarLasRutasUnaVez();
    await frescura.rebajarLosPedidosPorSuAlmacen();
    await frescura.rebajarLosPedidosPorSuFolio();
    await frescura.rebajarLosPedidosPorLaFacturaDeSusRenglones();
    await frescura.rebajarLasFacturasAnuladas();
    await frescura.rebajarLosPedidosPorSuConduce();
    await base.customStatement(
      'INSERT INTO orders (id, customer_name, address, weight, archivado, factura_numero) '
      "VALUES ('viva', 'A', 'x', 1, 0, '1'), ('fantasma', 'B', 'x', 1, 0, '2')",
    );
  });
  tearDown(() => base.close());

  Bajada bajada({bool conCola = true, bool truncada = false}) => Bajada(
    cliente: clienteFalso((p) async {
      if (p.ruta.contains('/sync/cuadre')) {
        pedidosAlCuadre++;
        if (cuadreFalla)
          return RespuestaFalsa(500, <String, Object?>{'error': 'x'});
        return RespuestaFalsa(200, <String, Object?>{
          'colecciones': <String, Object?>{'orders': idsDelServidor},
          'truncado': <String>[],
          'faltan': <String>[],
        });
      }
      return RespuestaFalsa(200, <String, Object?>{
        'hasta': '2026-10-28T12:00:00.000Z',
        'completa': false,
        'truncado': truncada,
        'cambios': <String, Object?>{},
      });
    }),
    base: base,
    frescura: frescura,
    reloj: () => ahora,
    cola: conCola ? ColaDeSalida(base) : null,
    alCuadrar: avisos.add,
  );

  Future<int> cuantas() async => (await base.select(base.orders).get()).length;

  test('cuadra, quita el fantasma y AVISA; la segunda vuelta del mismo día no vuelve a preguntar', () async {
    await bajada().ciclo();
    expect(pedidosAlCuadre, 1);
    expect(await cuantas(), 1);
    expect(
      avisos.single.facturas,
      1,
      reason: 'la persona se entera de lo que pasó',
    );

    ahora = ahora.add(const Duration(hours: 3));
    await bajada().ciclo();
    expect(
      pedidosAlCuadre,
      1,
      reason: 'una vez cada 20 horas, no en cada vuelta',
    );

    ahora = ahora.add(const Duration(hours: 18));
    await bajada().ciclo();
    expect(pedidosAlCuadre, 2, reason: 'al día siguiente toca otra vez');
  });

  test(
    'sin cola (la web) no cuadra: su copia nace vacía y no arrastra fantasmas',
    () async {
      await bajada(conCola: false).ciclo();
      expect(pedidosAlCuadre, 0);
      expect(await cuantas(), 2);
    },
  );

  test('con la bajada a medias (truncada sin marca) NO cuadra: la copia no está al día', () async {
    await bajada(truncada: true).ciclo();
    expect(pedidosAlCuadre, 0);
    expect(await cuantas(), 2);
  });

  test('si el cuadre falla, la bajada sigue bien y se reintenta en la vuelta siguiente', () async {
    cuadreFalla = true;
    final resumen = await bajada().ciclo();
    expect(
      resumen.quedoPor,
      isNull,
      reason: 'el cuadre es una ayuda: no tumba la bajada',
    );
    expect(await cuantas(), 2, reason: 'no se quitó nada');

    cuadreFalla = false;
    await bajada().ciclo();
    expect(pedidosAlCuadre, 2, reason: 'no se marcó como hecho: se reintenta');
    expect(await cuantas(), 1);
  });

  test('si al aparato le FALTAN facturas, olvida la marca: la próxima bajada es completa', () async {
    await frescura.marcar(Colecciones.pedidos, hasta: '2026-10-27T10:00:00Z');
    idsDelServidor = ['viva', 'fantasma', 'la-que-nunca-llego'];

    await bajada().ciclo();

    expect(
      await frescura.desde(Colecciones.pedidos),
      isNull,
      reason: 'sin marca, la siguiente vuelta pide todo y la fila que faltaba llega',
    );
    expect(avisos.single.totalQueFaltaba, 1);
  });
}
