// LOS CONDUCES, LADO APARATO (`docs/conduces.md`, 27/10/2026): datos y acciones, sin pintar nada.
//
// Un conduce junta varias FACTURAS del mismo cliente en UNA parada. La principal es la primera que se
// marcó; los miembros bajan al aparato con `conducePrincipalId` y NO salen como filas propias en
// ninguna lista, contador, Panel ni armado. Lo que se ata aquí:
//
//  1. VISIBILIDAD (regla 3): la lista de Facturas y su contador (§3-bis: se comparan), las facetas,
//     «Sin colocar», los disponibles, el Panel. La principal dice «Conduce 47313 + 47314» y suma.
//  2. ORDEN DE MARCADO: la primera marcada es la principal, aunque la base las devuelva al revés.
//  3. ARMAR / QUITAR / CERRAR: elegir la principal mueve a los miembros; una parada por conduce;
//     quitar la principal quita a los miembros; marcar la principal marca a los miembros.
//  4. CREAR / DESHACER / SACAR en las tres formas (CLAUDE.md §1 y §3-quinquies): APK y escritorio
//     escriben la base y encolan; la web va al servidor y un rechazo se DICE con su motivo literal.
//
// Todo se siembra DENTRO de cada prueba (CLAUDE.md §5).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/conduce.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/panel/datos/consultas_panel.dart';
import 'package:reparto/pantallas/pedidos/datos/acciones_de_conduce.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';
import 'sembrar.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late ServidorFalso servidor;
  late AccionesDeConduce enElAparato;
  late AccionesDeConduce enLaWeb;
  late Future<RespuestaFalsa?> Function(PeticionVista) contesta;

  setUp(() {
    base = baseDePrueba();
    final reloj = RelojFalso(DateTime.utc(2026, 10, 27, 9));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    enElAparato = AccionesDeConduce(base, cola, reloj: reloj.leer);
    contesta = (_) async => RespuestaFalsa(200, const <String, Object?>{});
    servidor = ServidorFalso((p) => contesta(p));
    enLaWeb = AccionesDeConduce(
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

  /// Tres facturas del mismo cliente (47313 la principal) y una de otro, todas libres y con punto.
  Future<void> sembrarFacturas({bool conduceHecho = false}) async {
    await sembrarCatalogo(base);
    // El almacén de la sucursal con coordenadas de verdad (el del catálogo está en 0,0).
    await (base.update(base.warehouses)..where((w) => w.id.equals('W1'))).write(
      const WarehousesCompanion(lat: Value(21.0), lng: Value(-77.0)),
    );
    for (final (id, numero, cliente, peso, costo) in [
      ('a', '47313', 'Bodega La Rica', 100.0, 2.0),
      ('b', '47314', 'Bodega La Rica', 50.0, 1.0),
      ('c', '47315', 'Bodega La Rica', 25.0, 0.5),
      ('d', '47400', 'Otro Cliente', 10.0, 3.0),
    ]) {
      await sembrarPedido(
        base,
        id: id,
        cliente: cliente,
        facturaNumero: numero,
        peso: peso,
        pedidoCosto: costo,
        endLat: 21.38,
        endLng: -77.91,
        conducePrincipalId: conduceHecho && id == 'b' ? 'a' : null,
      );
    }
  }

  Future<Pedido> fila(String id) =>
      (base.select(base.orders)..where((o) => o.id.equals(id))).getSingle();

  Matcher rechazoCon(Object literal) =>
      throwsA(isA<RechazoLocal>().having((r) => r.mensaje, 'mensaje', literal));

  group('regla 3: los miembros no son filas', () {
    test('la lista de Facturas y SU CONTADOR dicen lo mismo y no llevan al miembro', () async {
      await sembrarFacturas(conduceHecho: true);
      final consultas = ConsultasPedidos(base);
      const filtros = FiltrosPedidos.sinNada();

      final lista = await consultas.pagina(filtros).first;
      final cuenta = await consultas.contar(filtros).first;

      expect([for (final p in lista) p.id]..sort(), ['a', 'c', 'd']);
      expect(
        cuenta,
        lista.length,
        reason: 'la lista y su contador se atan aquí, no con un comentario (§3-bis)',
      );
      expect(await consultas.contarYa(filtros), lista.length);
    });

    test('buscar el número de un MIEMBRO encuentra la fila de su principal', () async {
      await sembrarFacturas(conduceHecho: true);
      final lista = await ConsultasPedidos(base)
          .pagina(const FiltrosPedidos.sinNada().copiarCon(q: '47314'))
          .first;
      expect([for (final p in lista) p.id], ['a']);
    });

    test('las facetas (municipio y vendedor) no cuentan al miembro', () async {
      await sembrarFacturas(conduceHecho: true);
      final facetas = await ConsultasPedidos(base).facetas();
      expect(facetas.municipios.single.pedidos, 3);
      expect(facetas.vendedores.single.pedidos, 3);
    });

    test('«Sin colocar» y los disponibles ofrecen la principal, no el miembro', () async {
      await sembrarFacturas(conduceHecho: true);
      final tablero = ConsultasTablero(base);
      final origen = await tablero.almacenDe('B1');
      final izquierda = await tablero.sinColocar('B1', origen);
      expect([for (final t in izquierda.pedidos) t.pedidoId]..sort(), ['a', 'c', 'd']);
      expect(izquierda.total, 3, reason: 'su contador es el de la lista');

      final disponibles = await ConsultasRutas(base).disponibles(sucursalId: 'B1');
      expect([for (final p in disponibles) p.id]..sort(), ['a', 'c', 'd']);
    });

    test('la principal dice «Conduce 47313 + 47314» y suma peso y domicilio', () async {
      await sembrarFacturas(conduceHecho: true);
      final tablero = ConsultasTablero(base);
      final origen = await tablero.almacenDe('B1');
      final izquierda = await tablero.sinColocar('B1', origen);
      final a = izquierda.pedidos.firstWhere((t) => t.pedidoId == 'a');
      expect(a.conduce!.etiqueta, 'Conduce 47313 + 47314');
      expect(a.weight, 150, reason: 'la tarjeta pesa lo de TODO el conduce');
      expect(a.conduce!.domicilioUsd, 3);
      // La suelta no se toca.
      expect(izquierda.pedidos.firstWhere((t) => t.pedidoId == 'c').conduce, isNull);
    });

    test('el Panel cuenta facturas, no miembros, y pesa el conduce entero', () async {
      await sembrarFacturas(conduceHecho: true);
      final cifras = await ConsultasPanel(base).cifras(sucursalId: 'B1').first;
      expect(cifras.totalPedidos, 3);
      expect(cifras.sinRuta, 3);
      expect(cifras.pesoPendiente, 100 + 50 + 25 + 10);
    });

    test('mirarConduces: un STREAM que se entera de lo que se siembra DESPUÉS', () async {
      // Montado con la base VACÍA y sembrado después, sin volver a montar (§3-ter).
      final visto = <int>[];
      final suscripcion = mirarConduces(base).listen((m) => visto.add(m.length));
      await Future<void>.delayed(Duration.zero);
      await sembrarFacturas(conduceHecho: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await suscripcion.cancel();
      expect(visto.first, 0);
      expect(visto.last, 1);
    });
  });

  group('el orden de marcado es la principal', () {
    test('lo primero que se marca es la principal, y la base no lo reordena', () async {
      await sembrarFacturas();
      final contenedor = ProviderContainer.test(
        overrides: [baseProvider.overrideWith((ref) => base)],
      );
      addTearDown(contenedor.dispose);
      final marcas = contenedor.read(seleccionPedidosProvider.notifier);
      // En la base 'a' va antes que 'c', y se marca AL REVÉS.
      marcas.alternar('c');
      marcas.alternar('a');
      marcas.alternar('b');
      expect(contenedor.read(seleccionPedidosProvider).toList(), ['c', 'a', 'b']);

      final escucha = contenedor.listen(facturasMarcadasProvider, (_, _) {});
      addTearDown(escucha.close);
      for (var i = 0; i < 50 && escucha.read().value == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        [for (final p in escucha.read().value!.elegidas) p.id],
        ['c', 'a', 'b'],
        reason: 'si se reordena, la principal deja de ser la primera que marcó la persona',
      );
    });

    test('marcar una página entera no reordena lo que ya estaba marcado', () async {
      final contenedor = ProviderContainer.test();
      addTearDown(contenedor.dispose);
      final marcas = contenedor.read(seleccionPedidosProvider.notifier);
      marcas.alternar('c');
      marcas.marcarPagina(['a', 'b', 'c'], marcar: true);
      expect(contenedor.read(seleccionPedidosProvider).first, 'c');
    });
  });

  group('por qué NO se pueden juntar (los mismos motivos que el servidor)', () {
    Future<List<Pedido>> elegir(List<String> ids) async => [
      for (final id in ids) await fila(id),
    ];

    test('de la misma sucursal y del mismo cliente se puede', () async {
      await sembrarFacturas();
      expect(porQueNoSePuedeJuntar(await elegir(['a', 'b', 'c'])), isNull);
    });

    test('con una sola factura no hay conduce', () async {
      await sembrarFacturas();
      expect(
        porQueNoSePuedeJuntar(await elegir(['a'])),
        'Marca al menos una factura, además de la principal, para el conduce',
      );
    });

    test('clientes distintos: lo dice y no deja', () async {
      await sembrarFacturas();
      expect(
        porQueNoSePuedeJuntar(await elegir(['a', 'd'])),
        'La factura 47400 es de otro cliente (Bodega La Rica): un conduce junta '
        'facturas de un solo cliente',
      );
    });

    test('el nombre del cliente se compara sin mayúsculas ni blancos de más', () async {
      await sembrarFacturas();
      await (base.update(base.orders)..where((o) => o.id.equals('b'))).write(
        const OrdersCompanion(customerName: Value('  bodega   la RICA ')),
      );
      expect(porQueNoSePuedeJuntar(await elegir(['a', 'b'])), isNull);
    });

    test('una en ruta, una entregada y una de otra sucursal tampoco', () async {
      await sembrarFacturas();
      await sembrarRuta(base, id: 'R1');
      await (base.update(base.orders)..where((o) => o.id.equals('b'))).write(
        const OrdersCompanion(routeId: Value('R1')),
      );
      expect(
        porQueNoSePuedeJuntar(
          await elegir(['a', 'b']),
          codigosDeRuta: {'R1': 'RT-R1'},
        ),
        'La factura 47314 ya va en la ruta RT-R1',
      );
      expect(
        porQueNoSePuedeJuntar(await elegir(['a', 'b'])),
        'La factura 47314 ya va en la ruta otra ruta',
      );
      await (base.update(base.orders)..where((o) => o.id.equals('b'))).write(
        const OrdersCompanion(routeId: Value(null), resultado: Value('entregado')),
      );
      expect(
        porQueNoSePuedeJuntar(await elegir(['a', 'b'])),
        'La factura 47314 ya está entregada',
      );
      await (base.update(base.orders)..where((o) => o.id.equals('b'))).write(
        const OrdersCompanion(resultado: Value(null), branchId: Value('B2')),
      );
      expect(
        porQueNoSePuedeJuntar(await elegir(['a', 'b'])),
        'La factura 47314 es de otra sucursal: un conduce no mezcla sucursales',
      );
    });

    test('un miembro de OTRO conduce no se junta; la principal de uno sí puede crecer', () async {
      await sembrarFacturas(conduceHecho: true);
      // 'b' ya es miembro de 'a': no puede ir con 'c'.
      expect(
        porQueNoSePuedeJuntar(
          await elegir(['c', 'b']),
          numerosDePrincipal: {'a': '47313'},
        ),
        'La factura 47314 ya es miembro del conduce 47313',
      );
      // 'a' es principal con miembros: se le añade 'c'.
      expect(
        porQueNoSePuedeJuntar(
          await elegir(['a', 'c']),
          principalesDeConduce: const {'a'},
        ),
        isNull,
      );
      // Pero como MIEMBRO de otra principal no.
      expect(
        porQueNoSePuedeJuntar(
          await elegir(['c', 'a']),
          principalesDeConduce: const {'a'},
        ),
        'La factura 47313 ya es la principal de otro conduce',
      );
    });
  });

  group('APK y escritorio: crear, deshacer y sacar son apuntes de la cola', () {
    test('crear escribe la base, encola UN apunte y no sale ninguna petición', () async {
      await sembrarFacturas();
      await enElAparato.crear(['a', 'b', 'c']);

      expect((await fila('a')).conducePrincipalId, isNull);
      expect((await fila('b')).conducePrincipalId, 'a');
      expect((await fila('c')).conducePrincipalId, 'a');
      expect(
        [for (final a in await cola.lote()) '${a.metodo} ${a.ruta} ${a.cuerpo}'],
        ['POST /conduces {"principalId":"a","ids":["b","c"]}'],
      );
      expect(servidor.vistas, isEmpty);
    });

    test('la PRIMERA de la lista es la principal, sea cual sea el orden de la base', () async {
      await sembrarFacturas();
      await enElAparato.crear(['c', 'a']);
      expect((await fila('a')).conducePrincipalId, 'c');
      expect((await cola.lote()).single.cuerpo, '{"principalId":"c","ids":["a"]}');
    });

    test('con clientes distintos DICE por qué y no escribe ni encola nada', () async {
      await sembrarFacturas();
      await expectLater(
        () => enElAparato.crear(['a', 'd']),
        rechazoCon(
          'La factura 47400 es de otro cliente (Bodega La Rica): un conduce junta '
          'facturas de un solo cliente',
        ),
      );
      expect((await fila('d')).conducePrincipalId, isNull);
      expect(await cola.lote(), isEmpty);
    });

    test('una factura que no existe: «No encontrado»', () async {
      await sembrarFacturas();
      await expectLater(
        () => enElAparato.crear(['a', 'nadie']),
        rechazoCon(MotivosDeConduce.noExiste),
      );
    });

    test('deshacer suelta a los miembros y encola DELETE', () async {
      await sembrarFacturas(conduceHecho: true);
      await enElAparato.deshacer('a');
      expect((await fila('b')).conducePrincipalId, isNull);
      expect(
        [for (final a in await cola.lote()) '${a.metodo} ${a.ruta}'],
        ['DELETE /conduces/a'],
      );
    });

    test('deshacer algo que no es un conduce: el literal', () async {
      await sembrarFacturas();
      await expectLater(
        () => enElAparato.deshacer('c'),
        rechazoCon('La factura 47315 no encabeza ningún conduce'),
      );
      expect(await cola.lote(), isEmpty);
    });

    test('no se deshace si la principal ya va en una ruta', () async {
      await sembrarFacturas(conduceHecho: true);
      await sembrarRuta(base, id: 'R1');
      await (base.update(base.orders)..where((o) => o.id.equals('a'))).write(
        const OrdersCompanion(routeId: Value('R1')),
      );
      await expectLater(
        () => enElAparato.deshacer('a'),
        rechazoCon('La factura 47313 ya va en la ruta RT-R1'),
      );
      expect((await fila('b')).conducePrincipalId, 'a');
      expect(await cola.lote(), isEmpty);
    });

    test('sacar quita UN miembro y deja a los demás', () async {
      await sembrarFacturas();
      await enElAparato.crear(['a', 'b', 'c']);
      await enElAparato.sacar('a', 'b');
      expect((await fila('b')).conducePrincipalId, isNull);
      expect((await fila('c')).conducePrincipalId, 'a');
      expect(
        [for (final a in await cola.lote()) '${a.metodo} ${a.ruta}'],
        ['POST /conduces', 'DELETE /conduces/a/miembros/b'],
      );
    });

    test('sacar a quien no es de ese conduce: el literal', () async {
      await sembrarFacturas(conduceHecho: true);
      await expectLater(
        () => enElAparato.sacar('a', 'c'),
        rechazoCon('La factura 47315 no es miembro de ese conduce'),
      );
    });
  });

  group('web: directo al servidor, y un rechazo se dice LITERAL', () {
    test('crear va DIRECTO y se refleja lo que el servidor devolvió', () async {
      await sembrarFacturas();
      contesta = (_) async => RespuestaFalsa(201, {
        'principalId': 'a',
        'miembros': ['b', 'c'],
      });
      await enLaWeb.crear(['a', 'b', 'c']);

      final vista = servidor.vistas.single;
      expect('${vista.metodo} ${vista.ruta}', 'POST /conduces');
      expect(vista.cuerpo, {
        'principalId': 'a',
        'ids': ['b', 'c'],
      });
      expect((await fila('b')).conducePrincipalId, 'a');
      expect(await cola.lote(), isEmpty, reason: 'la web no tiene cola');
    });

    for (final (codigo, motivo) in const [
      (409, 'La factura 47314 ya va en una ruta'),
      (422, 'Un conduce junta facturas del mismo cliente'),
    ]) {
      test('un $codigo se dice con su motivo LITERAL y no escribe nada', () async {
        await sembrarFacturas();
        contesta = (_) async => RespuestaFalsa(codigo, {'error': motivo});
        await expectLater(() => enLaWeb.crear(['a', 'b']), rechazoCon(motivo));
        expect((await fila('b')).conducePrincipalId, isNull);
        expect(await cola.lote(), isEmpty);
      });
    }

    test('deshacer y sacar van DIRECTO', () async {
      await sembrarFacturas(conduceHecho: true);
      contesta = (_) async => RespuestaFalsa(200, {
        'principalId': 'a',
        'liberados': ['b'],
      });
      await enLaWeb.deshacer('a');
      expect((await fila('b')).conducePrincipalId, isNull);
      expect(servidor.vistas.map((v) => '${v.metodo} ${v.ruta}'), [
        'DELETE /conduces/a',
      ]);
    });
  });

  group('armar, quitar y cerrar: la parada es el conduce', () {
    late AccionesDeRuta rutas;
    late ConsultasRutas consultas;

    setUp(() {
      final reloj = RelojFalso(DateTime.utc(2026, 10, 27, 9));
      rutas = AccionesDeRuta(base, cola, reloj: reloj.leer);
      consultas = ConsultasRutas(base);
    });

    Future<String> armar(List<String> ids) => rutas.armar(
      vehiculoId: 'V1',
      pedidoIds: ids,
      origenLat: 21.0,
      origenLng: -77.0,
      sucursalId: 'B1',
    );

    test('elegir la principal lleva a los miembros a la ruta, sin parada propia', () async {
      await sembrarFacturas(conduceHecho: true);
      final rutaId = await armar(['a', 'c']);

      final a = await fila('a');
      final b = await fila('b');
      expect((a.routeId, b.routeId), (rutaId, rutaId));
      expect(b.ultimaRutaId, rutaId);
      expect(b.stopOrder, isNull, reason: 'el miembro no recibe parada propia');
      expect(a.stopOrder, isNotNull);

      final ruta = await (base.select(base.routes)..where((r) => r.id.equals(rutaId))).getSingle();
      expect(ruta.totalWeight, 100 + 50 + 25, reason: 'el camión lleva TODAS las facturas');
    });

    test('hay UNA parada por conduce, con el peso de todo el conduce', () async {
      await sembrarFacturas(conduceHecho: true);
      final rutaId = await armar(['a', 'c']);

      final paradas = await consultas.mirarParadasDe(rutaId).first;
      expect([for (final p in paradas) p.id]..sort(), ['a', 'c']);
      expect(paradas.firstWhere((p) => p.id == 'a').weight, 150);
      expect((await consultas.paradasPorRuta().first)[rutaId], 2);
      // Los conduces de la ruta, para mostrar sus facturas.
      final conduces = await mirarConduces(base, principales: ['a', 'c']).first;
      expect(conduces['a']!.etiqueta, 'Conduce 47313 + 47314');
    });

    test('un miembro suelto NO se puede elegir', () async {
      await sembrarFacturas(conduceHecho: true);
      await expectLater(
        () => armar(['b']),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Esa factura va dentro del conduce 47313: arma el conduce entero',
          ),
        ),
      );
      expect((await fila('b')).routeId, isNull);
    });

    test('quitar la principal de la ruta quita a los miembros', () async {
      await sembrarFacturas(conduceHecho: true);
      final rutaId = await armar(['a', 'c']);
      await rutas.quitarParada(rutaId, 'a');
      final b = await fila('b');
      expect((b.routeId, b.ultimaRutaId), (null, null));
      expect((await fila('a')).routeId, isNull);
    });

    test('marcar la principal marca a los miembros, cada fila con su resultado', () async {
      await sembrarFacturas(conduceHecho: true);
      final rutaId = await armar(['a', 'c']);
      await rutas.cerrar(rutaId, const [
        MarcaDeParada(pedidoId: 'a', resultado: 'devuelto', nota: 'Cerrado'),
      ]);
      for (final id in ['a', 'b']) {
        final f = await fila(id);
        expect(f.resultado, 'devuelto', reason: 'la fila $id');
        expect(f.resultadoNota, 'Cerrado', reason: 'la fila $id');
        expect(f.resultadoAt, isNotNull, reason: 'la fila $id');
      }
      expect((await fila('c')).resultado, isNull);
      // Sólo viaja el cierre de la principal: el servidor cascadea.
      final cierre = (await cola.lote()).last;
      expect(cierre.ruta, '/routes/$rutaId/results');
      expect(cierre.cuerpo, contains('"a"'));
      expect(cierre.cuerpo, isNot(contains('"b"')));
    });
  });
}
