import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

/// LA CABECERA DE LA RUTA DICE LO MISMO QUE SUS PARADAS — 28/09/2026.
///
/// Medido en la APK 1.0.13: `RT-20260928-003`, dos pedidos del MISMO cliente y la
/// MISMA dirección, cabecera «420 kg» encima de dos paradas de 419,7 y 96,8 kg.
/// 516,5 contra 420, que es justo el peso de la primera.
///
/// Y sólo falla el peso porque el peso es el ÚNICO número de esa cabecera que
/// sale de la columna guardada (`routes.total_weight`): el importe y la carga
/// los suma la pantalla de las paradas que tiene delante. Un total guardado que
/// nadie contrasta con su detalle es el §3-bis del `CLAUDE.md`, y eso se ata con
/// una prueba, no con un comentario.
void main() {
  late BaseLocal base;
  late ConsultasTablero consultas;
  late ColaDeSalida cola;
  late RepositorioTablero repo;
  late AlmacenOrigen origen;
  late String centro;

  const cliente = 'KIOSKO HABANA CLUB OMAR JIMENEZ MONTOYA L2';
  const direccion = 'Aguilera/ San Agustín y Baranda';

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    cola = ColaDeSalida(base);
    repo = RepositorioTablero(base, cola);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarCamion(base, id: 'v1', capacidad: 1000);
    origen = await consultas.almacenDe(sucursalStg);
    centro = await repo.crearColumna(
      sucursalId: sucursalStg,
      nombre: 'Centro',
      vehiculoId: 'v1',
    );
  });

  tearDown(() => base.close());

  /// Los dos pedidos del mismo cliente, en la misma dirección y por tanto en el
  /// MISMO punto de entrega: es lo único que los separa del caso que ya salía
  /// bien (dos clientes distintos, 48 + 371 = 419, cabecera 420 kg).
  Future<void> sembrarLosDosDelMismoCliente() async {
    await sembrarPedido(
      base,
      id: 'a',
      cliente: cliente,
      direccion: direccion,
      operacion: 'POR26-260927-3733',
      peso: 419.7,
      costo: 2.51,
    );
    await sembrarPedido(
      base,
      id: 'b',
      cliente: cliente,
      direccion: direccion,
      operacion: 'POR26-260925-3700',
      peso: 96.8,
      costo: 0.59,
    );
    await repo.colocar(pedidoId: 'a', columnaId: centro);
    await repo.colocar(pedidoId: 'b', columnaId: centro);
  }

  test('el peso de la ruta cuenta los DOS pedidos del mismo cliente', () async {
    await sembrarLosDosDelMismoCliente();

    final rutaId = await repo.armarRuta(
      columnaId: centro,
      origen: origen,
      sucursalId: sucursalStg,
    );

    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();
    expect(
      ruta.totalWeight,
      closeTo(516.5, 0.0001),
      reason:
          'la cabecera cuenta el peso de una sola de las dos paradas: el camión '
          'parece más vacío de lo que sale del almacén',
    );
  });

  test('la cabecera y sus paradas dicen el mismo peso (§3-bis)', () async {
    await sembrarLosDosDelMismoCliente();

    final rutaId = await repo.armarRuta(
      columnaId: centro,
      origen: origen,
      sucursalId: sucursalStg,
    );

    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();
    // Las paradas de la hoja: las mismas que lee `ConsultasRutas.paradasDe`,
    // por `ultima_ruta_id`, que es lo que la pantalla tiene delante.
    final paradas =
        await (base.select(
          base.orders,
        )..where((o) => o.ultimaRutaId.equals(rutaId))).get();
    final deLasParadas = paradas.fold<double>(0, (s, p) => s + p.weight);

    expect(paradas, hasLength(2));
    expect(
      ruta.totalWeight,
      closeTo(deLasParadas, 0.0001),
      reason:
          'la cabecera dice ${ruta.totalWeight} kg y sus paradas suman '
          '$deLasParadas kg: son dos preguntas sobre lo mismo y tienen que '
          'contestar igual',
    );
  });

}
