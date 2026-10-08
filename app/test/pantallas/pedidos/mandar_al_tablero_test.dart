// MANDAR LO MARCADO A UNA ZONA DEL TABLERO.
//
// El gesto que cierra el flujo: se marca en Pedidos lo que se va a repartir y se
// manda de golpe a una zona. Lo que esta prueba vigila es lo que no se ve:
//
//  * que escriba en la base del aparato **y** deje un apunte por pedido en la
//    cola, que es el mismo camino del arrastre (`RepositorioTablero.colocar`);
//  * que **no llame a nadie**, porque esto se hace en el patio y sin señal;
//  * que lo que no se puede repartir salga NOMBRADO y con su motivo, y que los
//    demás vayan igual (`CLAUDE.md` §4: nada se descarta en silencio);
//  * y el ALCANCE: los pedidos y las zonas son de la sucursal que se está
//    mirando. Un pedido de La Habana en una zona de Holguín no puede ocurrir.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/pedidos/datos/mandar_al_tablero.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'sembrar.dart';

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;
  late ProviderContainer contenedor;

  setUp(() async {
    base = baseDePrueba();
    // SIN RED. Cualquier petición que se escape falla como en la calle, y
    // además queda apuntada — que es lo que se comprueba.
    servidor = ServidorFalso((peticion) async => null);
    await sembrarCatalogo(base);
  });

  tearDown(() async {
    contenedor.dispose();
    await base.close();
  });

  /// Monta el contenedor con la sesión de un logístico de Camagüey (`B1`).
  ///
  /// Sin espera entre reintentos: si algo llamara al servidor, la prueba tiene
  /// que fallar rápido y no quemar quince segundos esperando a una red que no
  /// existe.
  void montar({String? sucursalDeLaSesion = 'B1', String? mirando}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.invalido'))
      ..httpClientAdapter = servidor;
    contenedor = ProviderContainer.test(
      overrides: [
        baseProvider.overrideWithValue(base),
        clienteApiProvider.overrideWithValue(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: sucursalDeLaSesion,
            ),
          ),
        ),
      ],
    );
    if (mirando != null) {
      contenedor.read(sucursalMiradaProvider.notifier).mirar(mirando);
    }
  }

  /// Las zonas que vería el cajón AHORA MISMO.
  ///
  /// Con `listen` y no con un `read` pelado: en un contenedor de prueba, un
  /// provider sin nadie escuchando se tira en cuanto se lee, y un
  /// `StreamProvider` se queda sin emitir ni un valor. Y con `invalidate`
  /// delante para que la respuesta sea la de ahora y no la primera que dio.
  Future<List<ColumnaTablero>> zonasQueSeVerian() async {
    contenedor.invalidate(zonasDelTableroProvider);
    final quita = contenedor.listen(zonasDelTableroProvider, (_, _) {});
    try {
      return await contenedor.read(zonasDelTableroProvider.future);
    } finally {
      quita.close();
    }
  }

  /// Los pedidos que hay puestos en una zona, en su orden de visita.
  Future<List<String>> enLaZona(String columnaId) async {
    final filas = await base
        .customSelect(
          'SELECT order_id FROM ${EsquemaTablero.colocaciones} '
          'WHERE column_id = ?1 ORDER BY posicion ASC',
          variables: [Variable<String>(columnaId)],
        )
        .get();
    return filas.map((f) => f.read<String>('order_id')).toList();
  }

  /// Tres pedidos repartibles de Camagüey, con coordenadas.
  Future<void> sembrarTresBuenos() async {
    for (final id in const ['o1', 'o2', 'o3']) {
      await sembrarPedido(
        base,
        id: id,
        cliente: 'Cliente $id',
        endLat: 21.38,
        endLng: -77.91,
      );
    }
  }

  // ---------------------------------------------------------------------------

  test(
    'marcar tres y mandarlos: los tres acaban en la zona y hay un apunte por '
    'cada uno en la cola',
    () async {
      await sembrarTresBuenos();
      montar();

      final zona = await contenedor
          .read(envioAlTableroProvider.notifier)
          .crearZona('Centro');
      contenedor.read(seleccionPedidosProvider.notifier).marcarPagina(const [
        'o1',
        'o2',
        'o3',
      ], marcar: true);

      final resultado = await contenedor
          .read(envioAlTableroProvider.notifier)
          .mandarLoMarcado(zona);

      expect(resultado.cuantos, 3);
      expect(resultado.zona, 'Centro');
      expect(resultado.alguienSeQuedo, isFalse);

      // 1. Están puestos, y en el orden en que se marcaron: es el orden de
      //    visita con el que nacen dentro de la zona.
      expect(await enLaZona(zona), ['o1', 'o2', 'o3']);

      // 2. UN APUNTE POR CADA UNO, con el cuerpo del contrato. Sin esto, las
      //    tarjetas se habrían movido en el aparato y no habría nadie que lo
      //    fuera a subir nunca.
      final lote = await ColaDeSalida(base).lote();
      expect(lote.map((a) => a.ruta).toList(), [
        '/board/columns?branchId=B1',
        '/board/placements/o1',
        '/board/placements/o2',
        '/board/placements/o3',
      ]);
      expect(jsonDecode(lote[1].cuerpo), {'columnaId': zona, 'posicion': 1});
      expect(jsonDecode(lote[3].cuerpo), {'columnaId': zona, 'posicion': 3});
    },
  );

  test('sin conexión funciona igual y no llama a nadie', () async {
    await sembrarTresBuenos();
    montar();

    final zona = await contenedor
        .read(envioAlTableroProvider.notifier)
        .crearZona('Centro');
    contenedor.read(seleccionPedidosProvider.notifier).marcarPagina(const [
      'o1',
      'o2',
      'o3',
    ], marcar: true);
    await contenedor
        .read(envioAlTableroProvider.notifier)
        .mandarLoMarcado(zona);

    expect(await enLaZona(zona), ['o1', 'o2', 'o3']);
    // Sobre TODAS las peticiones y no sólo las de `/board`: lo que se vigila es
    // que el gesto no hable con nadie, ni siquiera de rebote.
    expect(
      servidor.vistas,
      isEmpty,
      reason:
          'el gesto escribe aquí; la subida va por detrás, cuando haya señal',
    );
  });

  test(
    'lo que no se puede repartir va NOMBRADO en el aviso y los otros sí van',
    () async {
      // Cada uno cae por un motivo distinto, y los cuatro son los del armador.
      await sembrarPedido(
        base,
        id: 'bueno',
        cliente: 'Ana',
        folio: 'F-2992',
        endLat: 21.38,
        endLng: -77.91,
      );
      await sembrarPedido(
        base,
        id: 'archivado',
        cliente: 'Eva',
        folio: 'F-ARCH',
        archivado: true,
        endLat: 21.38,
        endLng: -77.91,
      );
      await sembrarRuta(base, id: 'R1');
      await sembrarPedido(
        base,
        id: 'enruta',
        cliente: 'Fito',
        folio: 'F-RUTA',
        rutaId: 'R1',
        endLat: 21.38,
        endLng: -77.91,
      );
      await sembrarPedido(
        base,
        id: 'sinfactura',
        cliente: 'Carla',
        folio: 'F-SF',
        facturaEstado: EstadoFactura.sinFactura,
        endLat: 21.38,
        endLng: -77.91,
      );
      // Sin `endLat`/`endLng`: no se puede ordenar por cercanía ni medir el
      // recorrido de la ruta que salga de la zona.
      await sembrarPedido(base, id: 'sincoord', cliente: 'Hugo', folio: 'F-SC');

      montar();
      final zona = await contenedor
          .read(envioAlTableroProvider.notifier)
          .crearZona('Centro');
      contenedor.read(seleccionPedidosProvider.notifier).marcarPagina(const [
        'bueno',
        'archivado',
        'enruta',
        'sinfactura',
        'sincoord',
      ], marcar: true);

      final resultado = await contenedor
          .read(envioAlTableroProvider.notifier)
          .mandarLoMarcado(zona);

      // El bueno va. Que uno esté archivado no deja a los demás sin colocar.
      expect(resultado.fueron, ['bueno']);
      expect(await enLaZona(zona), ['bueno']);

      // Y los cuatro que no, NOMBRADOS y con su motivo. Una lista de cinco que
      // produce una zona de uno sin explicación es la manera más rápida de que
      // el logístico deje de fiarse.
      expect(resultado.noFueron.map((q) => q.linea).toList(), [
        'F-ARCH · Eva: ${MarcaTarjeta.archivado.texto}',
        // El de la ruta es EL DEL SERVIDOR (`porQueNoSePudoColocar`), no la
        // marca de la tarjeta: en la web un 409 y aqui tienen que leerse igual.
        'F-RUTA · Fito: Ese pedido ya está en una ruta',
        'F-SF · Carla: ${MarcaTarjeta.sinFactura.texto}',
        'F-SC · Hugo: ${MotivoDeQuedarse.sinCoordenadas}',
      ]);
    },
  );

  test(
    'sin domicilio cobrado, sin cotizar o ya entregado: se quedan con el '
    'literal del servidor y los demás van',
    () async {
      await sembrarPedido(
        base,
        id: 'bueno',
        cliente: 'Ana',
        folio: 'F-OK',
        endLat: 21.38,
        endLng: -77.91,
      );
      await sembrarPedido(
        base,
        id: 'sindom',
        cliente: 'Dora',
        folio: 'F-DOM',
        facturaDomicilio: 0,
        endLat: 21.38,
        endLng: -77.91,
      );
      await sembrarPedido(
        base,
        id: 'sincot',
        cliente: 'Cira',
        folio: 'F-COT',
        pedidoCosto: null,
        endLat: 21.38,
        endLng: -77.91,
      );
      // Un entregado cuya ruta se borro: sin `route_id`, solo le queda el
      // resultado. No es «ya esta en una ruta»: ya se repartio.
      await sembrarPedido(
        base,
        id: 'entregado',
        cliente: 'Eli',
        folio: 'F-ENT',
        resultado: 'entregado',
        endLat: 21.38,
        endLng: -77.91,
      );

      montar();
      final zona = await contenedor
          .read(envioAlTableroProvider.notifier)
          .crearZona('Centro');
      contenedor.read(seleccionPedidosProvider.notifier).marcarPagina(const [
        'bueno',
        'sindom',
        'sincot',
        'entregado',
      ], marcar: true);

      final resultado = await contenedor
          .read(envioAlTableroProvider.notifier)
          .mandarLoMarcado(zona);

      expect(resultado.fueron, ['bueno']);
      expect(await enLaZona(zona), ['bueno']);
      expect(resultado.noFueron.map((q) => q.linea).toList(), [
        'F-DOM · Dora: No se puede asociar al tablero: la factura no tiene un '
            'cobro de domicilio registrado.',
        'F-COT · Cira: No se puede asociar al tablero: primero cotiza el '
            'domicilio del pedido.',
        'F-ENT · Eli: Ese pedido ya se entregó',
      ]);
    },
  );

  test(
    'se puede crear una zona nueva desde ahí y los pedidos caen en ella',
    () async {
      await sembrarTresBuenos();
      montar();

      // No hay ninguna zona todavía: es el caso del primer día.
      expect(await zonasQueSeVerian(), isEmpty);

      final zona = await contenedor
          .read(envioAlTableroProvider.notifier)
          .crearZona('Vista Alegre');
      contenedor.read(seleccionPedidosProvider.notifier).marcarPagina(const [
        'o1',
        'o2',
      ], marcar: true);
      final resultado = await contenedor
          .read(envioAlTableroProvider.notifier)
          .mandarLoMarcado(zona);

      expect(resultado.zona, 'Vista Alegre');
      expect(await enLaZona(zona), ['o1', 'o2']);
      // Y la zona nueva es de la sucursal que se está mirando, no de otra.
      final zonas = await zonasQueSeVerian();
      expect(zonas.single.nombre, 'Vista Alegre');
      expect(zonas.single.branchId, 'B1');
    },
  );

  // ---------------------------------------------------------------------------
  // EL ALCANCE
  // ---------------------------------------------------------------------------

  test('con una sucursal mirada no salen las zonas de otra', () async {
    montar(mirando: 'B1');
    final deCamaguey = await contenedor
        .read(envioAlTableroProvider.notifier)
        .crearZona('Centro');

    // La misma base tiene una zona de Holguín: la escribe otro logístico y baja
    // en la foto del tablero. No puede salir en el cajón de Camagüey.
    await base.customStatement(
      'INSERT INTO ${EsquemaTablero.columnas} '
      '(id, branch_id, nombre, posicion) VALUES (?1, ?2, ?3, 1)',
      ['zona-hol', 'B2', 'Reparto Peralta'],
    );

    final zonas = await zonasQueSeVerian();
    expect(zonas.map((z) => z.id).toList(), [deCamaguey]);
    expect(
      zonas.map((z) => z.nombre),
      isNot(contains('Reparto Peralta')),
      reason: 'las zonas son de la sucursal que se está mirando',
    );
  });

  test('un pedido de otra sucursal no entra en una zona de ésta', () async {
    await sembrarPedido(
      base,
      id: 'de-camaguey',
      cliente: 'Ana',
      folio: 'F-CAM',
      endLat: 21.38,
      endLng: -77.91,
    );
    // `o10` del juego de datos es de Holguín. Con el Super Admin mirando
    // «todas», la página de Pedidos enseña las ocho a la vez y marcar de dos
    // sucursales es un gesto de un segundo.
    await sembrarPedido(
      base,
      id: 'de-holguin',
      cliente: 'Juan',
      folio: 'F-HOL',
      sucursal: 'B2',
      endLat: 20.88,
      endLng: -76.26,
    );

    montar(mirando: 'B1');
    final zona = await contenedor
        .read(envioAlTableroProvider.notifier)
        .crearZona('Centro');
    contenedor.read(seleccionPedidosProvider.notifier).marcarPagina(const [
      'de-camaguey',
      'de-holguin',
    ], marcar: true);

    final resultado = await contenedor
        .read(envioAlTableroProvider.notifier)
        .mandarLoMarcado(zona);

    expect(await enLaZona(zona), ['de-camaguey']);
    expect(
      resultado.noFueron.single.linea,
      'F-HOL · Juan: ${MotivoDeQuedarse.deOtraSucursal}',
    );
    // Y no se encoló nada suyo: si se encolara, el servidor lo rechazaría y el
    // aparato se quedaría enseñando una tarjeta que allí no existe.
    final lote = await ColaDeSalida(base).lote();
    expect(
      lote.map((a) => a.ruta),
      isNot(contains('/board/placements/de-holguin')),
    );
  });

  test('mandar a una zona de otra sucursal se rechaza entero', () async {
    await sembrarTresBuenos();
    // Las tablas del tablero las crea la primera llamada suya; aquí se escribe
    // a mano antes de que haya habido ninguna.
    await EsquemaTablero.asegurar(base);
    await base.customStatement(
      'INSERT INTO ${EsquemaTablero.columnas} '
      '(id, branch_id, nombre, posicion) VALUES (?1, ?2, ?3, 1)',
      ['zona-hol', 'B2', 'Reparto Peralta'],
    );

    montar(mirando: 'B1');
    contenedor.read(seleccionPedidosProvider.notifier).marcarPagina(const [
      'o1',
    ], marcar: true);

    // La guarda de la pantalla —que sólo enseña las zonas de B1— no basta: se
    // cae el día que alguien cambie de sucursal con el cajón abierto.
    await expectLater(
      contenedor
          .read(envioAlTableroProvider.notifier)
          .mandarLoMarcado('zona-hol'),
      throwsA(
        isA<RechazoDelTablero>().having(
          (e) => e.mensaje,
          'mensaje',
          'Esa zona es de otra sucursal',
        ),
      ),
    );
    expect(await enLaZona('zona-hol'), isEmpty);
  });

  // ---------------------------------------------------------------------------
  // LA MARCA
  // ---------------------------------------------------------------------------

  test('la marca se quita al terminar', () async {
    await sembrarTresBuenos();
    montar();

    final zona = await contenedor
        .read(envioAlTableroProvider.notifier)
        .crearZona('Centro');
    contenedor.read(seleccionPedidosProvider.notifier).marcarPagina(const [
      'o1',
      'o2',
      'o3',
    ], marcar: true);
    expect(contenedor.read(seleccionPedidosProvider), hasLength(3));

    await contenedor
        .read(envioAlTableroProvider.notifier)
        .mandarLoMarcado(zona);

    expect(contenedor.read(seleccionPedidosProvider), isEmpty);
  });

  test(
    'los que NO pudieron ir se quedan marcados: decirlo y borrarlos a la vez '
    'sería descartarlos en silencio',
    () async {
      await sembrarPedido(
        base,
        id: 'bueno',
        cliente: 'Ana',
        endLat: 21.38,
        endLng: -77.91,
      );
      await sembrarPedido(
        base,
        id: 'archivado',
        cliente: 'Eva',
        archivado: true,
        endLat: 21.38,
        endLng: -77.91,
      );
      montar();

      final zona = await contenedor
          .read(envioAlTableroProvider.notifier)
          .crearZona('Centro');
      contenedor.read(seleccionPedidosProvider.notifier).marcarPagina(const [
        'bueno',
        'archivado',
      ], marcar: true);

      await contenedor
          .read(envioAlTableroProvider.notifier)
          .mandarLoMarcado(zona);

      expect(
        contenedor.read(seleccionPedidosProvider),
        {'archivado'},
        reason:
            'el que no pudo ir sigue a mano para arreglarlo o mandarlo a otra '
            'zona, sin volver a buscarlo entre doce mil',
      );
    },
  );
}
