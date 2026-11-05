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

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cancelada.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/informes/datos/hoja_de_calculo.dart';
import 'package:reparto/pantallas/panel/datos/consultas_panel.dart';
import 'package:reparto/pantallas/pedidos/datos/acciones_de_pedido.dart';
import 'package:reparto/pantallas/pedidos/datos/canceladas.dart';
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
import '../../apoyo/servidor_falso.dart';
import 'sembrar.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  late BaseLocal base;
  late ColaDeSalida cola;
  late RelojFalso reloj;
  late AccionesDePedido enElAparato;
  late AccionesDePedido enLaWeb;
  late ServidorFalso servidor;
  late Future<RespuestaFalsa?> Function(PeticionVista) contesta;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime.utc(2026, 11, 5, 15));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    enElAparato = AccionesDePedido(base, cola, reloj: reloj.leer);
    contesta = (_) async => RespuestaFalsa(200, const <String, Object?>{});
    servidor = ServidorFalso((p) => contesta(p));
    enLaWeb = AccionesDePedido(
      base,
      cola,
      reloj: reloj.leer,
      enVivo: EscrituraEnVivo(
        ClienteApi(
          dio: Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
            ..httpClientAdapter = servidor,
          esperas: const <Duration>[],
        ),
      ),
    );
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

  group('3. la vista «Canceladas»', () {
    test('lista = contador, con la nota y la fecha; la devuelta y la nueva no salen', () async {
      await sembrar();
      final consultas = ConsultasCanceladas(base);
      final lista = await consultas.lista().first;
      expect([for (final p in lista) p.id], ['c']);
      expect(await consultas.contar().first, lista.length);
      expect(lista.single.resultadoNota, 'El cliente se arrepintió');
    });

    test('Desde/Hasta por la fecha de la cancelación en HORA DE CUBA: los bordes del día', () async {
      // 03:30 UTC del 5/11 es el 4/11 a las 22:30 en Cuba (UTC-5, el horario de verano acabó el 1/11).
      await sembrar(canceladaEl: DateTime.utc(2026, 11, 5, 3, 30));
      final consultas = ConsultasCanceladas(base);
      Future<List<String>> ids(DateTime? d, DateTime? h) async {
        final lista = await consultas.lista(desde: d, hasta: h).first;
        expect(
          await consultas.contar(desde: d, hasta: h).first,
          lista.length,
          reason: 'contador = lista',
        );
        return [for (final p in lista) p.id];
      }

      expect(await ids(DateTime(2026, 11, 4), DateTime(2026, 11, 4)), [
        'c',
      ], reason: 'es del 4 en Cuba');
      expect(
        await ids(DateTime(2026, 11, 5), DateTime(2026, 11, 5)),
        isEmpty,
        reason: 'no es del 5 en Cuba',
      );
      expect(await ids(DateTime(2026, 11, 5), null), isEmpty);
      expect(await ids(null, DateTime(2026, 11, 3)), isEmpty);
      expect(await ids(null, DateTime(2026, 11, 4)), ['c']);
      expect(await ids(null, null), ['c']);
    });

    test('una cancelada SIN fecha sale sin periodo, queda fuera en cuanto hay uno y cae a updatedAt si lo trae', () async {
      await sembrar();
      await (base.update(base.orders)..where((o) => o.id.equals('c'))).write(
        const OrdersCompanion(resultadoAt: Value(null)),
      );
      final consultas = ConsultasCanceladas(base);
      expect((await consultas.lista().first).length, 1);
      expect(
        await consultas.lista(desde: DateTime(2026, 1, 1)).first,
        isEmpty,
        reason: 'sin fecha no se puede decir que cae en el periodo',
      );
      expect(fechaDeLaCancelacion(null), '—');

      // Una cancelada de antes de esta versión, sin `resultadoAt`, cae a la última vez que el servidor
      // tocó la fila: no se pierde de su periodo.
      await (base.update(base.orders)..where((o) => o.id.equals('c'))).write(
        OrdersCompanion(updatedAt: Value(DateTime.utc(2026, 11, 3, 15))),
      );
      final dia3 = DateTime(2026, 11, 3);
      expect(
        [
          for (final p in await consultas.lista(desde: dia3, hasta: dia3).first)
            p.id,
        ],
        ['c'],
      );
      expect(await consultas.contar(desde: dia3, hasta: dia3).first, 1);
      expect(
        await consultas.lista(desde: DateTime(2026, 11, 4)).first,
        isEmpty,
      );
    });

    test('la sucursal manda: la cancelada de otra no sale', () async {
      await sembrar();
      expect(
        (await ConsultasCanceladas(base).lista(sucursalId: 'B1').first).length,
        1,
      );
      expect(
        await ConsultasCanceladas(base).lista(sucursalId: 'B2').first,
        isEmpty,
      );
    });

    test('las que cancelaron el chofer o la logística al cerrar la ruta salen igual que las de oficina', () async {
      await sembrar();
      await sembrarPedido(
        base,
        id: 'k',
        cliente: 'Otro',
        facturaNumero: '47010',
        rutaId: 'R-cerrada',
        resultado: ResultadoParada.cancelado,
        endLat: 21.38,
        endLng: -77.91,
      );
      expect(
        [for (final p in await ConsultasCanceladas(base).lista().first) p.id]
          ..sort(),
        ['c', 'k'],
      );
    });

    test('el Excel: cabecera, una fila por cancelada con fecha en Cuba y nota, y el total', () async {
      await sembrar(canceladaEl: DateTime.utc(2026, 11, 5, 3, 30));
      final todas = await ConsultasCanceladas(base).todas();
      final hoja = hojaDeCanceladas(todas, periodo: '4/11/2026 - 4/11/2026');
      expect(hoja.filas, [
        ['Periodo', '4/11/2026 - 4/11/2026'],
        ['Factura', 'Cliente', 'Fecha de cancelación (hora de Cuba)', 'Nota'],
        ['47003', 'Cliente c', '4/11/2026 22:30', 'El cliente se arrepintió'],
        ['Total canceladas', 1],
      ]);
      // Y el libro se arma de verdad (un .xlsx roto no se nota al generarlo).
      expect(armarXlsx([hoja]), isNotEmpty);
      expect(
        nombreDelExcelDeCanceladas(DateTime(2026, 11, 5)),
        'canceladas-2026-11-05.xlsx',
      );
    });
  });

  group('4. cancelar una devuelta', () {
    test('APK / escritorio: la fila queda cancelada YA (con su hora y su nota) y el apunte espera en la cola', () async {
      await sembrar();
      await enElAparato.cancelar('d', nota: '  El cliente se arrepintió  ');

      final d = await fila('d');
      expect(d.resultado, ResultadoParada.cancelado);
      expect(
        d.resultadoAt!.isAtSameMomentAs(DateTime.utc(2026, 11, 5, 15)),
        isTrue,
      );
      expect(d.resultadoNota, 'El cliente se arrepintió');

      final apuntes = await cola.lote();
      expect(apuntes.length, 1);
      expect(
        (apuntes.single.metodo, apuntes.single.ruta),
        ('POST', '/orders/d/cancelar'),
      );
      expect(jsonDecode(apuntes.single.cuerpo), {
        'nota': 'El cliente se arrepintió',
      });

      // Y al instante sale del pool local, sin esperar al servidor.
      final origen = await ConsultasTablero(base).almacenDe('B1');
      final izquierda = await ConsultasTablero(base).sinColocar('B1', origen);
      expect([for (final t in izquierda.pedidos) t.pedidoId], ['n']);
    });

    test('sin nota: el cuerpo va vacío y la nota de la devolución se va (la nota de ahora es la de la cancelación)', () async {
      await sembrar();
      await enElAparato.cancelar('d');
      expect((await fila('d')).resultadoNota, isNull);
      expect(jsonDecode((await cola.lote()).single.cuerpo), isEmpty);
    });

    test('lo que no es una devuelta se rechaza AQUÍ, con la frase del servidor, sin escribir ni encolar', () async {
      await sembrar();
      await sembrarRuta(base, id: 'R1');
      await sembrarPedido(
        base,
        id: 'r',
        cliente: 'En ruta',
        facturaNumero: '47020',
        rutaId: 'R1',
        resultado: ResultadoParada.devuelto,
      );
      await expectLater(
        enElAparato.cancelar('n'),
        rechazoCon(MotivosDeCancelar.noDevuelta),
      );
      await expectLater(
        enElAparato.cancelar('c'),
        rechazoCon(MotivosDeCancelar.yaCancelada),
      );
      await expectLater(
        enElAparato.cancelar('r'),
        rechazoCon(MotivosDeCancelar.enUnaRuta),
      );
      await expectLater(
        enElAparato.cancelar('zz'),
        rechazoCon(MotivosDeCancelar.noExiste),
      );
      await expectLater(
        enElAparato.cancelar('d', nota: 'x' * 501),
        rechazoCon(MotivosDeCancelar.notaLarga),
      );
      expect(await cola.lote(), isEmpty, reason: 'ninguno dejó un apunte');
      expect((await fila('n')).resultado, isNull);
      expect((await fila('d')).resultado, ResultadoParada.devuelto);
    });

    test('cancelar la principal de un conduce cancela también a sus miembros; un miembro suelto se rechaza', () async {
      await sembrar();
      await sembrarPedido(
        base,
        id: 'm',
        cliente: 'Cliente d',
        facturaNumero: '47004',
        resultado: ResultadoParada.devuelto,
        conducePrincipalId: 'd',
      );
      await expectLater(
        enElAparato.cancelar('m'),
        rechazoCon(MotivosDeCancelar.enUnConduce),
      );
      await enElAparato.cancelar('d');
      expect((await fila('m')).resultado, ResultadoParada.cancelado);
      expect(
        (await cola.lote()).length,
        1,
        reason: 'UN apunte: el servidor cascadea',
      );
    });

    test('un doble clic manda UNA sola cancelación', () async {
      await sembrar();
      final a = enElAparato.cancelar('d', nota: 'a');
      final b = enElAparato.cancelar('d', nota: 'a');
      await Future.wait([a, b]);
      expect((await cola.lote()).length, 1);
    });

    test('WEB: va al servidor y ESPERA; con su 200 se refleja lo que guardó y no hay cola', () async {
      await sembrar();
      contesta = (_) async => RespuestaFalsa(200, {
        'id': 'd',
        'resultado': 'cancelado',
        'resultadoAt': '2026-11-05T15:01:00Z',
        'resultadoNota': 'Cancelada por el cliente',
      });
      await enLaWeb.cancelar('d', nota: 'Cancelada por el cliente');

      expect(servidor.vistas.single.metodo, 'POST');
      expect(servidor.vistas.single.ruta, endsWith('/orders/d/cancelar'));
      expect(servidor.vistas.single.cuerpo, {
        'nota': 'Cancelada por el cliente',
      });
      final d = await fila('d');
      expect(d.resultado, ResultadoParada.cancelado);
      expect(
        d.resultadoAt!.isAtSameMomentAs(DateTime.utc(2026, 11, 5, 15, 1)),
        isTrue,
      );
      expect(d.resultadoNota, 'Cancelada por el cliente');
      expect(
        await cola.lote(),
        isEmpty,
        reason: 'la web no tiene cola (CLAUDE.md §1)',
      );
    });

    test('WEB: si el servidor dice que no, sale su motivo LITERAL y no se escribe nada', () async {
      await sembrar();
      contesta = (_) async =>
          RespuestaFalsa(409, {'error': 'La factura ya está cancelada'});
      await expectLater(
        enLaWeb.cancelar('d'),
        rechazoCon('La factura ya está cancelada'),
      );
      final d = await fila('d');
      expect(
        d.resultado,
        ResultadoParada.devuelto,
        reason: 'la pantalla no miente: sigue devuelta',
      );
      expect(await cola.lote(), isEmpty);
    });

    test('WEB: la validación local va ANTES de molestar al servidor', () async {
      await sembrar();
      await expectLater(
        enLaWeb.cancelar('n'),
        rechazoCon(MotivosDeCancelar.noDevuelta),
      );
      expect(servidor.vistas, isEmpty);
    });
  });

  group('5. el rechazo del servidor y la cola', () {
    Future<String> encolarYRechazar(String id, String motivo) async {
      await enElAparato.cancelar(id);
      final clave = (await cola.lote()).single.clave;
      await cola.resolver(
        clave,
        ResultadoApunte(estado: EstadoResultado.rechazado, motivo: motivo),
      );
      return clave;
    }

    test('un rechazo se queda a la vista con su motivo y pide la copia entera de los pedidos', () async {
      await sembrar();
      final frescura = RegistroDeFrescura(base, reloj: reloj.leer);
      await frescura.marcar(
        Colecciones.pedidos,
        hasta: '2026-11-04T00:00:00.000Z',
      );
      final clave = await encolarYRechazar('d', 'La factura va en una ruta');

      final a = (await cola.porClave(clave))!;
      expect(
        (a.estado, a.motivo),
        (EstadoApunte.rechazado, 'La factura va en una ruta'),
      );
      expect(
        await frescura.desde(Colecciones.pedidos),
        isNull,
        reason: 'sin esto la fila cancelada que sólo existe aquí se queda mintiendo hasta que el servidor la toque',
      );
    });

    test('«ya está cancelada»: se CIERRA sola cuando la fila local ya está cancelada…', () async {
      await sembrar();
      final clave = await encolarYRechazar('d', 'La factura ya está cancelada');
      expect(await cola.cerrarLasCancelacionesYaHechas(), 1);
      final a = (await cola.porClave(clave))!;
      expect(
        a.estado,
        EstadoApunte.descartado,
        reason: 'se ESCRIBE, no se borra',
      );
      expect(
        a.motivo,
        'La factura ya está cancelada',
        reason: 'el motivo no se toca',
      );
    });

    test('…y NO se cierra cuando la fila local volvió a ser devuelta (el rechazo era de verdad)', () async {
      await sembrar();
      final clave = await encolarYRechazar('d', 'La factura va en una ruta');
      // La bajada entera dejó la fila como la tiene el servidor: devuelta.
      await (base.update(base.orders)..where((o) => o.id.equals('d'))).write(
        const OrdersCompanion(resultado: Value(ResultadoParada.devuelto)),
      );
      expect(await cola.cerrarLasCancelacionesYaHechas(), 0);
      expect((await cola.porClave(clave))!.estado, EstadoApunte.rechazado);
    });

    test('y no toca los rechazos de otras cosas', () async {
      await sembrar();
      final otro = await cola.encolar(
        metodo: 'PUT',
        ruta: '/orders/c/punto',
        cuerpo: const {},
      );
      await cola.resolver(
        otro,
        const ResultadoApunte(estado: EstadoResultado.rechazado, motivo: 'no'),
      );
      expect(await cola.cerrarLasCancelacionesYaHechas(), 0);
      expect((await cola.porClave(otro))!.estado, EstadoApunte.rechazado);
    });
  });
}
