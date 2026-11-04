import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/codigo_de_ruta.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';
import 'package:reparto/nucleo/sincro/cuadre.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// EL SERVIDOR CAMBIÓ EL CÓDIGO DE UNA RUTA HECHA EN ESTE APARATO (04/11/2026, Jose: «si coincide, ahí sí le otorgas uno nuevo, notificas
/// qué pasó y se lo cambias al local»). La ruta es la misma (mismo id); la fila local se actualiza con la bajada y la persona lo lee.
/// Solo cuenta cuando el código que guardaba el aparato ERA el derivado de su id: lo demás no es un choque.
void main() {
  const idDeLaRuta = '01a1a72e-6cc0-7abc-8def-0123456789ab'; // su código es 261104-2PF2DB (docs/codigo-de-ruta.casos.json)
  late BaseLocal base;
  late RegistroDeFrescura frescura;
  final ahora = DateTime.utc(2026, 11, 4, 12);
  late List<ResultadoDelCuadre> avisos;

  setUp(() async {
    base = baseDePrueba();
    frescura = RegistroDeFrescura(base, reloj: () => ahora);
    avisos = [];
    await frescura.rebajarLosPedidosUnaVez();
    await frescura.rebajarLasRutasUnaVez();
  });
  tearDown(() => base.close());

  Future<void> bajaLaRuta(String id, String? codigoDelServidor) => Bajada(
    cliente: clienteFalso(
      (p) async => RespuestaFalsa(200, <String, Object?>{
        'hasta': '2026-11-04T12:00:00.000Z',
        'completa': false,
        'truncado': false,
        'cambios': <String, Object?>{
          'routes': <String, Object?>{
            'puestos': [
              {
                'id': id,
                'routeCode': codigoDelServidor,
                'status': 'planned',
                'name': 'x',
              },
            ],
            'quitados': <String>[],
          },
        },
      }),
    ),
    base: base,
    frescura: frescura,
    reloj: () => ahora,
    cola: ColaDeSalida(base),
    alCuadrar: avisos.add,
  ).ciclo();

  Future<void> rutaLocal(String id, String? codigo) => base.customStatement(
    'INSERT INTO routes (id, route_code) VALUES (?1, ?2)',
    [id, codigo],
  );

  Future<String?> codigoLocal(String id) async => (await (base.select(
    base.routes,
  )..where((r) => r.id.equals(id))).getSingle()).routeCode;

  test('el código que guardaba el aparato era el de su id y llega otro: se actualiza la fila y se AVISA', () async {
    expect(codigoDeRutaDe(idDeLaRuta), '261104-2PF2DB');
    await rutaLocal(idDeLaRuta, '261104-2PF2DB');

    await bajaLaRuta(idDeLaRuta, '261104-9ZZZZZ');

    expect(
      await codigoLocal(idDeLaRuta),
      '261104-9ZZZZZ',
      reason: 'el local se queda con el del servidor',
    );
    final c = avisos.expand((r) => r.codigosCambiados).single;
    expect(
      (c.rutaId, c.antes, c.ahora),
      (idDeLaRuta, '261104-2PF2DB', '261104-9ZZZZZ'),
    );
    expect(avisos.single.hayQueDecir, isTrue);
  });

  test(
    'si el servidor respetó el código del aparato, no hay nada que decir',
    () async {
      await rutaLocal(idDeLaRuta, '261104-2PF2DB');
      await bajaLaRuta(idDeLaRuta, '261104-2PF2DB');
      expect(avisos, isEmpty);
    },
  );

  test('una ruta de antes (código RT-…) o hecha en otra parte no es un choque: no se avisa', () async {
    await rutaLocal(idDeLaRuta, 'RT-20261103-004');
    await bajaLaRuta(idDeLaRuta, 'RT-20261103-004-X');
    expect(avisos, isEmpty);
  });

  test(
    'un id que no es UUID (de antes de la 1.0.51) no rompe la bajada ni avisa',
    () async {
      await rutaLocal('cm2xlegacy', 'RT-20261001-001');
      await bajaLaRuta('cm2xlegacy', 'RT-20261001-002');
      expect(avisos, isEmpty);
      expect(await codigoLocal('cm2xlegacy'), 'RT-20261001-002');
    },
  );

  test(
    'una ruta que el aparato no tenía simplemente entra: no se avisa',
    () async {
      await bajaLaRuta(idDeLaRuta, '261104-2PF2DB');
      expect(avisos, isEmpty);
      expect(await codigoLocal(idDeLaRuta), '261104-2PF2DB');
    },
  );
}
