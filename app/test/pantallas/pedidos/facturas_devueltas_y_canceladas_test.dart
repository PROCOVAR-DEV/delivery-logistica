// FACTURAS DEVUELTAS Y CANCELADAS — issue 25 de Amado, 05/11/2026. Datos y acciones, sin pintar nada.
//
// «Cancelada» es el resultado `cancelado` de siempre (Jose: «la cancelada es el cancelado ese»): SIN columna
// nueva ni esquema nuevo. Lo que se ata aquí, siempre EN PAREJA (CLAUDE.md §3-bis):
//
//  1. LA REGLA: una cancelada sin ruta ya NO es repartible (Sin colocar, disponibles, Panel, armar, colocar,
//     tarjeta del tablero) y una devuelta SÍ. Cada lista con su contador.
//  2. LOS FILTROS «Devueltas / Nuevas» de Facturas y de Sin colocar, con su contador atado a la lista.
//  3. LA VISTA «CANCELADAS»: Desde/Hasta por la fecha de cancelación en hora de Cuba (los bordes del día),
//     contador = lista, y la hoja del Excel.
//  4. CANCELAR en las tres formas: APK/escritorio escriben la fila y encolan; la web va al servidor y un
//     rechazo se DICE con su motivo literal sin escribir nada.
//  5. LOS RECHAZOS DEL SYNC: piden la copia entera y se cierran solos sólo cuando la fila YA está cancelada.
//
// Todo se siembra DENTRO de cada prueba (CLAUDE.md §5).

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cancelada.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/panel/datos/consultas_panel.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/estado/filtros_en_la_url.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import 'sembrar.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  late BaseLocal base;
  late ColaDeSalida cola;
  late RelojFalso reloj;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime.utc(2026, 11, 5, 15));
    cola = ColaDeSalida(base, reloj: reloj.leer);
  });
  tearDown(() => base.close());

  /// n = nueva, d = devuelta (sin ruta), c = cancelada (sin ruta). Todas libres y con punto.
  Future<void> sembrar({DateTime? canceladaEl}) async {
    await sembrarCatalogo(base);
    await (base.update(base.warehouses)..where((w) => w.id.equals('W1'))).write(
      const WarehousesCompanion(lat: Value(21.0), lng: Value(-77.0)),
    );
    for (final (id, numero, resultado, peso) in [
      ('n', '47001', null, 10.0),
      ('d', '47002', ResultadoParada.devuelto, 20.0),
      ('c', '47003', ResultadoParada.cancelado, 40.0),
    ]) {
      await sembrarPedido(
        base,
        id: id,
        cliente: 'Cliente $id',
        facturaNumero: numero,
        peso: peso,
        resultado: resultado,
        ultimaRutaId: resultado == null ? null : 'R-vieja',
        endLat: 21.38,
        endLng: -77.91,
      );
    }
    await (base.update(base.orders)..where((o) => o.id.equals('c'))).write(
      OrdersCompanion(
        resultadoAt: Value(canceladaEl ?? DateTime.utc(2026, 11, 3, 15)),
        resultadoNota: const Value('El cliente se arrepintió'),
      ),
    );
    await (base.update(base.orders)..where((o) => o.id.equals('d'))).write(
      OrdersCompanion(
        resultadoAt: Value(DateTime.utc(2026, 11, 2, 15)),
        resultadoNota: const Value('No estaba en casa'),
      ),
    );
  }

  Future<Pedido> fila(String id) =>
      (base.select(base.orders)..where((o) => o.id.equals(id))).getSingle();

  Matcher rechazoCon(Object literal) =>
      throwsA(isA<RechazoLocal>().having((r) => r.mensaje, 'mensaje', literal));

  group('1. la cancelada ya no se reparte; la devuelta sí', () {
    test(
      '«Sin colocar» y su contador: la nueva y la devuelta, NO la cancelada',
      () async {
        await sembrar();
        final tablero = ConsultasTablero(base);
        final origen = await tablero.almacenDe('B1');
        final izquierda = await tablero.sinColocar('B1', origen);
        expect([for (final t in izquierda.pedidos) t.pedidoId]..sort(), [
          'd',
          'n',
        ]);
        expect(
          izquierda.total,
          2,
          reason: 'el contador es el de la lista (§3-bis)',
        );
      },
    );

    test('los disponibles del asistente: igual', () async {
      await sembrar();
      final disponibles = await ConsultasRutas(base)
          .disponibles(sucursalId: 'B1');
      expect([for (final p in disponibles) p.id]..sort(), ['d', 'n']);
    });

    test(
      'el Panel cuenta lo mismo que ofrece la lista, y no pesa la cancelada',
      () async {
        await sembrar();
        final cifras = await ConsultasPanel(base)
            .cifras(sucursalId: 'B1')
            .first;
        expect(cifras.sinRuta, 2);
        expect(
          cifras.pesoPendiente,
          10 + 20,
          reason: 'los 40 kg de la cancelada no se cargan',
        );
      },
    );

    test('«Sin ubicar» tampoco ofrece una cancelada sin punto', () async {
      await sembrar();
      await (base.update(
        base.orders,
      )..where((o) => o.id.isIn(['c', 'd']))).write(
        const OrdersCompanion(endLat: Value(null), endLng: Value(null)),
      );
      final sinUbicar = await ConsultasTablero(base).sinUbicar('B1').first;
      expect([for (final f in sinUbicar) f.pedidoId], ['d']);
    });

    test('armar una ruta: la devuelta entra (y suelta su resultado), la cancelada se rechaza con su motivo', () async {
      await sembrar();
      final acciones = AccionesDeRuta(base, cola, reloj: reloj.leer);

      await expectLater(
        acciones.armar(
          vehiculoId: 'V1',
          pedidoIds: ['c'],
          origenLat: 21.0,
          origenLng: -77.0,
        ),
        rechazoCon(
          '1 de las facturas elegidas ESTÁ CANCELADA y no puede volver a un camión: F-c.',
        ),
      );
      expect((await fila('c')).routeId, isNull);

      final rutaId = await acciones.armar(
        vehiculoId: 'V1',
        pedidoIds: ['d'],
        origenLat: 21.0,
        origenLng: -77.0,
      );
      final d = await fila('d');
      expect(d.routeId, rutaId);
      expect(d.resultado, isNull, reason: 'una devuelta es un intento nuevo');
    });

    test('armar con varias canceladas: el plural del servidor, y mezcladas con otras razones se nombra cada una', () async {
      await sembrar();
      await sembrarPedido(
        base,
        id: 'k',
        cliente: 'Otro',
        facturaNumero: '47010',
        resultado: ResultadoParada.cancelado,
        endLat: 21.38,
        endLng: -77.91,
      );
      final acciones = AccionesDeRuta(base, cola, reloj: reloj.leer);
      await expectLater(
        acciones.armar(
          vehiculoId: 'V1',
          pedidoIds: ['c', 'k'],
          origenLat: 21.0,
          origenLng: -77.0,
        ),
        rechazoCon(
          '2 de las facturas elegidas ESTÁN CANCELADAS y no pueden volver a un camión: F-c, F-k.',
        ),
      );
      // Con una cancelada y una archivada ya no es «sólo canceladas»: el «no» detallado dice cada motivo.
      await (base.update(base.orders)..where((o) => o.id.equals('k'))).write(
        const OrdersCompanion(archivado: Value(true), resultado: Value(null)),
      );
      await expectLater(
        acciones.armar(
          vehiculoId: 'V1',
          pedidoIds: ['c', 'k'],
          origenLat: 21.0,
          origenLng: -77.0,
        ),
        rechazoCon(
          contains('F-c (está cancelada y no puede volver a un camión)'),
        ),
      );
    });

    test('colocar en una zona: la cancelada dice «Esa factura está cancelada», la devuelta puede', () async {
      await sembrar();
      expect(
        porQueNoSePuedeColocar(await fila('c')),
        'Esa factura está cancelada',
      );
      expect(porQueNoSePuedeColocar(await fila('d')), isNull);
      expect(porQueNoSePuedeColocar(await fila('n')), isNull);
    });

    test('la tarjeta ya colocada: una cancelada no sube a la ruta de su zona y se marca; la devuelta lleva «Devuelta»', () {
      TarjetaPedido tarjeta({String? resultado, String? rutaId}) =>
          TarjetaPedido(
            pedidoId: 'x',
            customerName: 'X',
            address: 'A',
            weight: 1,
            kmAlAlmacen: 1,
            mismoCliente: 1,
            facturaEstado: EstadoFactura.igual,
            resultado: resultado,
            rutaId: rutaId,
          );
      final cancelada = tarjeta(resultado: ResultadoParada.cancelado);
      expect(cancelada.motivoDeNoSubir, 'Está cancelada');
      expect(cancelada.repartible, isFalse);
      expect(cancelada.devuelta, isFalse);

      final devuelta = tarjeta(resultado: ResultadoParada.devuelto);
      expect(
        devuelta.motivoDeNoSubir,
        isNull,
        reason: 'una devuelta vuelve a salir',
      );
      expect(devuelta.devuelta, isTrue);

      expect(tarjeta().devuelta, isFalse, reason: 'una nueva no es devuelta');
    });

    test('esDevuelta / esCancelada / porQueNoSePuedeCancelar', () async {
      await sembrar();
      expect(esDevuelta(await fila('d')), isTrue);
      expect(esDevuelta(await fila('n')), isFalse);
      expect(esDevuelta(await fila('c')), isFalse);
      expect(esCancelada(await fila('c')), isTrue);
      expect(porQueNoSePuedeCancelar(await fila('d')), isNull);
      expect(
        porQueNoSePuedeCancelar(await fila('n')),
        MotivosDeCancelar.noDevuelta,
      );
      expect(
        porQueNoSePuedeCancelar(await fila('c')),
        MotivosDeCancelar.yaCancelada,
      );
    });
  });

  group('2. «Devueltas / Nuevas»', () {
    test(
      'Facturas: cada opción de reparto con su contador atado a la lista',
      () async {
        await sembrar();
        final consultas = ConsultasPedidos(base);
        final esperado = <RepartoFiltro, List<String>>{
          RepartoFiltro.cualquiera: ['c', 'd', 'n'],
          // Sin entregar es lo que aún puede repartirse: la cancelada ya no.
          RepartoFiltro.sinEntregar: ['d', 'n'],
          RepartoFiltro.devuelto: ['d'],
          RepartoFiltro.nuevas: ['n'],
          RepartoFiltro.entregado: [],
          RepartoFiltro.enDespacho: [],
          RepartoFiltro.enRuta: [],
        };
        expect(
          esperado.keys.toSet(),
          RepartoFiltro.values.toSet(),
          reason: 'ninguna opción sin cubrir',
        );
        for (final e in esperado.entries) {
          final f = const FiltrosPedidos.sinNada().copiarCon(reparto: e.key);
          final lista = await consultas.pagina(f).first;
          expect(
            [for (final p in lista) p.id]..sort(),
            e.value,
            reason: e.key.param,
          );
          expect(
            await consultas.contarYa(f),
            lista.length,
            reason: 'contador de ${e.key.param}',
          );
          expect(await consultas.contar(f).first, lista.length);
        }
      },
    );

    test('Sin colocar: Devueltas / Nuevas / las dos, con su total', () async {
      await sembrar();
      final tablero = ConsultasTablero(base);
      final origen = await tablero.almacenDe('B1');
      for (final (filtro, ids) in [
        (const FiltrosSinColocar(soloDevueltas: true), ['d']),
        (const FiltrosSinColocar(soloDevueltas: false), ['n']),
        (const FiltrosSinColocar(), ['d', 'n']),
      ]) {
        final m = await tablero.sinColocar('B1', origen, filtros: filtro);
        expect(
          [for (final t in m.pedidos) t.pedidoId]..sort(),
          ids,
          reason: '${filtro.soloDevueltas}',
        );
        expect(m.total, ids.length);
      }
    });

    test(
      'Sin colocar: el filtro viaja en la dirección (y un valor raro se DICE)',
      () {
        const f = FiltrosSinColocar(soloDevueltas: true);
        expect(FiltrosEnLaUrl.escribir(f)['origen'], 'devueltas');
        expect(
          FiltrosEnLaUrl.escribir(
            const FiltrosSinColocar(soloDevueltas: false),
          )['origen'],
          'nuevas',
        );
        expect(
          FiltrosEnLaUrl.escribir(const FiltrosSinColocar())
              .containsKey('origen'),
          isFalse,
        );

        expect(
          FiltrosEnLaUrl.leer({'origen': 'devueltas'}).filtros.soloDevueltas,
          isTrue,
        );
        expect(
          FiltrosEnLaUrl.leer({'origen': 'nuevas'}).filtros.soloDevueltas,
          isFalse,
        );
        final rara = FiltrosEnLaUrl.leer({'origen': 'quizas'});
        expect(rara.filtros.soloDevueltas, isNull);
        expect(rara.noSePudieron, [
          'origen=quizas',
        ], reason: 'nada se descarta en silencio');
        expect(const FiltrosSinColocar(soloDevueltas: true).hayAlguno, isTrue);
      },
    );
  });
  //@@MAS@@
}
