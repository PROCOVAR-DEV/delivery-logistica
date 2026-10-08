// COLOCAR UNA TARJETA SIN SENAL DICE LO MISMO QUE DIRIA EL SERVIDOR — 07/10/2026.
//
// Amado, incidencia 2: no se asocia al tablero una factura sin domicilio
// cobrado ni sin cotizar. El servidor lo rechaza con un 409, y en la web eso
// basta. Pero en la APK arrastrar no llama a nadie: la tarjeta se colocaba, el
// apunte se encolaba y el 409 llegaba horas despues a la bandeja. Ahora el
// aparato lo dice ANTES y no coloca ni encola nada.
//
// Los textos van escritos a mano: son los de `porQueNoSePudoColocar`
// (`api/internal/api/tablero.go`). Una prueba que los importara del codigo no
// comprobaria que digan lo mismo que el servidor.
//
// Y la lista de «Sin colocar» aplica las MISMAS dos condiciones, que es lo que
// ata la ultima prueba: lo que se ofrece es lo que se puede colocar.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late RepositorioTablero repo;
  late String zona;

  setUp(() {
    base = baseDePrueba();
    cola = ColaDeSalida(base);
    repo = RepositorioTablero(base, cola);
  });
  tearDown(() => base.close());

  /// Siembra DENTRO de la prueba (CLAUDE.md §5.2).
  Future<void> sembrar() async {
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    zona = await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
  }

  Future<void> rechaza(String pedido, String motivo) async {
    final antes = (await cola.lote()).length;
    await expectLater(
      () => repo.colocar(pedidoId: pedido, columnaId: zona),
      throwsA(
        isA<RechazoDelTablero>().having((r) => r.mensaje, 'mensaje', motivo),
      ),
    );
    final colocadas = await base
        .customSelect('SELECT count(*) AS n FROM board_placements')
        .getSingle();
    expect(colocadas.read<int>('n'), 0, reason: 'la tarjeta NO se coloca');
    expect((await cola.lote()).length, antes, reason: 'ni se encola nada');
  }

  test('sin domicilio cobrado en la factura', () async {
    await sembrar();
    await sembrarPedido(base, id: 'cero', facturaDomicilio: 0);
    await sembrarPedido(base, id: 'nulo', facturaDomicilio: null);
    const motivo =
        'No se puede asociar al tablero: la factura no tiene un cobro de '
        'domicilio registrado.';
    await rechaza('cero', motivo);
    await rechaza('nulo', motivo);
  });

  test('sin cotizar el domicilio en Entrega', () async {
    await sembrar();
    await sembrarPedido(base, id: 'sin', costo: null);
    await rechaza(
      'sin',
      'No se puede asociar al tablero: primero cotiza el domicilio del pedido.',
    );
  });

  test('ya entregado: antes que «ya está en una ruta»', () async {
    await sembrar();
    await sembrarPedido(base, id: 'ent');
    await base.customStatement(
      "UPDATE orders SET resultado = 'entregado', route_id = 'R9' "
      "WHERE id = 'ent'",
    );
    await rechaza('ent', 'Ese pedido ya se entregó');
  });

  test('ya va en una ruta', () async {
    await sembrar();
    await sembrarPedido(base, id: 'ruta');
    await base.customStatement(
      "UPDATE orders SET route_id = 'R9' WHERE id = 'ruta'",
    );
    await rechaza('ruta', 'Ese pedido ya está en una ruta');
  });

  test('la pareja: cotizado en CERO y cobrado SÍ se coloca', () async {
    await sembrar();
    await sembrarPedido(base, id: 'cero', costo: 0);
    await repo.colocar(pedidoId: 'cero', columnaId: zona);
    final n = await base
        .customSelect('SELECT count(*) AS n FROM board_placements')
        .getSingle();
    expect(n.read<int>('n'), 1);
    expect(await cola.lote(), isNotEmpty, reason: 'se encola para subir');
  });

  test('«Sin colocar» NO ofrece lo que colocar rechazaría', () async {
    await sembrar();
    await sembrarPedido(base, id: 'bueno');
    await sembrarPedido(base, id: 'cero', costo: 0);
    await sembrarPedido(base, id: 'sin-domicilio', facturaDomicilio: 0);
    await sembrarPedido(base, id: 'sin-cotizar', costo: null);
    final consultas = ConsultasTablero(base);
    final origen = await consultas.almacenDe(sucursalStg);
    final lista = await consultas.sinColocar(sucursalStg, origen);
    expect(lista.pedidos.map((p) => p.pedidoId).toList()..sort(), [
      'bueno',
      'cero',
    ]);
    expect(lista.total, 2);
    // Y lo que ofrece, lo coloca.
    for (final p in lista.pedidos) {
      await repo.colocar(pedidoId: p.pedidoId, columnaId: zona);
    }
  });
}
