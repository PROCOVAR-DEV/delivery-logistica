// BORRAR UNA ZONA CON PEDIDOS PUESTOS QUE ESTE APARATO NO VE — issue 15 de Amado,
// 16/10/2026.
//
// Lo que se vio en producción: `DELETE /api/board/columns/{id}` contestó 409
// «tiene 9 pedidos puestos» cuatro veces en doce minutos, para tres zonas. En la
// app de escritorio la zona se quitaba de la pantalla, el servidor decía que no,
// la zona volvía con la siguiente bajada y a la persona sólo le quedaba una
// etiqueta «rechazada» sin motivo ni acción. «Se eliminan en la interfaz pero no
// se borran en el backend. No hay mensaje de error.»
//
// La causa: el aparato SÍ comprobaba «¿tiene pedidos?», pero contando sus
// tarjetas, y una tarjeta sólo se guarda si su pedido está en la base local. Los
// pedidos que PEDIDO archivó (o que aún no han bajado) siguen puestos arriba y el
// servidor los cuenta; aquí no hay fila, así que la zona se veía «(0)», se
// ofrecía borrarla en seco y el servidor la defendía. Ahora la bajada APUNTA esas
// tarjetas (`board_sin_pedido`) y borrar las cuenta.
//
// Cuatro cosas, y cada una con su pareja:
//
//  1. zona con pedidos que no se ven → no se quita, motivo literal, opciones;
//     zona de verdad vacía → se borra y se encola como siempre;
//  2. mover/devolver y borrar → los apuntes que el servidor entiende;
//  3. rechazo del servidor → el motivo SE VE en la zona, con Reintentar y
//     Descartar, y descartar deja la zona como está arriba, sin atasco;
//  4. la web (sin cola) → el 409 se dice con su motivo y la zona no se mueve.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/datos/servicio.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

const _telefono = Size(390, 844);
const _escritorio = Size(1400, 900);

const _versalles = 'Z1_Versalles';
const _centro = 'Z2_Centro Ciudad';
const _vacia = 'Z3_Quintero';

/// LA FOTO DEL SERVIDOR: Versalles con tres puestos (sólo `p1` está en este
/// aparato), una zona de destino y otra de verdad vacía.
/// En el teléfono las zonas son páginas y la flecha sólo va a la VECINA: se llega
/// a una pasando por las anteriores.
Future<void> _irALaZona(WidgetTester tester, String nombre) async {
  for (final z in const [_versalles, _centro, _vacia]) {
    await tester.tap(find.byTooltip('Ir a «$z»'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    if (z == nombre) return;
  }
}

Map<String, Object?> _foto() => <String, Object?>{
  'columnas': [
    for (final (i, (id, nombre)) in [
      ('z1', _versalles),
      ('z2', _centro),
      ('z3', _vacia),
    ].indexed)
      {
        'id': id,
        'branchId': sucursalStg,
        'nombre': nombre,
        'posicion': i + 1,
      },
  ],
  'colocados': [
    for (final (i, p) in ['p1', 'p2', 'p3'].indexed)
      {'pedidoId': p, 'columnaId': 'z1', 'posicion': i + 1},
    // «Centro»: DOS puestos y NINGUNA tarjeta que ver. Es el caso del issue 15:
    // la zona se lee «(0)» y arriba no está vacía.
    for (final (i, p) in ['p4', 'p5'].indexed)
      {'pedidoId': p, 'columnaId': 'z2', 'posicion': i + 1},
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  late ColaDeSalida cola;
  late RepositorioTablero repo;
  late ServidorFalso servidor;
  late Future<RespuestaFalsa?> Function(PeticionVista) contesta;

  setUp(() {
    base = BaseLocal.con(NativeDatabase.memory());
    cola = ColaDeSalida(base);
    repo = RepositorioTablero(base, cola);
    contesta = (p) async => p.metodo == 'GET' && p.ruta.endsWith('/board')
        ? RespuestaFalsa(200, _foto())
        : RespuestaFalsa(200, const <String, Object?>{});
    servidor = ServidorFalso((p) => contesta(p));
  });

  tearDown(() => base.close());

  ServicioTablero servicio() => ServicioTablero(
    base,
    ClienteApi(
      dio: Dio()..httpClientAdapter = servidor,
      esperas: const <Duration>[],
    ),
    RegistroDeFrescura(base),
  );

  Future<void> sembrar() async {
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'p1');
  }

  /// Lo que el aparato ve de una zona.
  Future<({int pedidos, int sinPedido})> zona(String id) async {
    final c = (await ConsultasTablero(
      base,
    ).columnas(sucursalStg)).firstWhere((c) => c.id == id);
    return (pedidos: c.pedidos, sinPedido: c.sinPedido);
  }

  Future<List<String>> encolado() async => [
    for (final a in await cola.lote()) '${a.metodo} ${a.ruta}',
  ];

  // ---------------------------------------------------------------------------
  group('el aparato cuenta lo mismo que el servidor', () {
    test('la bajada apunta las tarjetas cuyo pedido no está aquí', () async {
      await sembrar();
      await servicio().descargar(sucursalStg);

      expect(await zona('z1'), (pedidos: 1, sinPedido: 2));
      expect(await zona('z3'), (pedidos: 0, sinPedido: 0));
    });

    test('borrar sin decir qué hacer: no se quita, con el motivo literal y el '
        'número del servidor', () async {
      await sembrar();
      await servicio().descargar(sucursalStg);

      await expectLater(
        () => repo.borrarColumna('z1'),
        throwsA(
          isA<RechazoDelTablero>()
              .having(
                (r) => r.mensaje,
                'mensaje',
                '«$_versalles» tiene 3 pedidos puestos',
              )
              .having((r) => r.pedidos, 'pedidos', 3),
        ),
      );
      expect(await encolado(), isEmpty, reason: 'nada sale hacia arriba');
      expect(
        (await ConsultasTablero(base).columnas(sucursalStg)).map((c) => c.id),
        contains('z1'),
        reason: 'la zona no se quita de la pantalla',
      );
    });

    test('PAREJA: la zona de verdad vacía se borra y se encola', () async {
      await sembrar();
      await servicio().descargar(sucursalStg);

      await repo.borrarColumna('z3');

      expect(await encolado(), ['DELETE /board/columns/z3']);
      expect(
        (await ConsultasTablero(base).columnas(sucursalStg)).map((c) => c.id),
        ['z1', 'z2'],
      );
    });

    test('mover a otra zona: mueve lo suyo, manda el destino y borra', () async {
      await sembrar();
      await servicio().descargar(sucursalStg);

      await repo.borrarColumna('z1', destinoId: 'z2');

      expect(await encolado(), [
        'PUT /board/placements/p1',
        'DELETE /board/columns/z1?destino=z2',
      ]);
      expect((await zona('z2')).pedidos, 1);
      final apuntadas = await base
          .customSelect(
            "SELECT count(*) AS n FROM board_sin_pedido WHERE column_id = 'z1'",
          )
          .getSingle();
      expect(
        apuntadas.read<int>('n'),
        0,
        reason: 'la zona se fue y con ella lo apuntado: el servidor las mueve',
      );
    });

    test('devolver a «Sin colocar»: quita lo suyo, manda vaciar y borra', () async {
      await sembrar();
      await servicio().descargar(sucursalStg);

      await repo.borrarColumna('z1', vaciar: true);

      expect(await encolado(), [
        'DELETE /board/placements/p1',
        'DELETE /board/columns/z1?vaciar=1',
      ]);
    });

    test('NO se cuenta dos veces: la que ya tiene su pedido aquí deja de estar '
        'sin pedido', () async {
      await sembrar();
      await servicio().descargar(sucursalStg);
      // El pedido p2 llega por el ciclo y la tarjeta se guarda, pero lo apuntado
      // de la bajada anterior sigue ahí hasta la próxima.
      await sembrarPedido(base, id: 'p2');
      await base.customStatement(
        'INSERT INTO board_placements (order_id, column_id, posicion) '
        "VALUES ('p2', 'z1', 2)",
      );

      expect(await zona('z1'), (pedidos: 2, sinPedido: 1));
      await expectLater(
        () => repo.borrarColumna('z1'),
        throwsA(
          isA<RechazoDelTablero>().having((r) => r.pedidos, 'pedidos', 3),
        ),
      );
    });

    test('cada bajada vuelve a contar entera: lo que ya no está puesto arriba '
        'deja de contar', () async {
      await sembrar();
      await servicio().descargar(sucursalStg);
      expect((await zona('z1')).sinPedido, 2);

      contesta = (p) async => RespuestaFalsa(200, <String, Object?>{
        ..._foto(),
        'colocados': <Object?>[],
      });
      await servicio().descargar(sucursalStg);

      expect(await zona('z1'), (pedidos: 0, sinPedido: 0));
      await repo.borrarColumna('z1');
      expect(await encolado(), ['DELETE /board/columns/z1']);
    });
  });

  // ---------------------------------------------------------------------------
  group('el rechazo del servidor se ve en la zona y se decide ahí', () {
    const elNo = '«$_vacia» tiene 4 pedidos puestos';

    Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    Widget montar() => ProviderScope(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        clienteApiProvider.overrideWithValue(
          ClienteApi(
            dio: Dio()..httpClientAdapter = servidor,
            esperas: const <Duration>[],
          ),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: sucursalStg,
            ),
          ),
        ),
        sucursalDeLaSesionProvider.overrideWithValue(sucursalStg),
      ],
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );

    /// LO QUE PASÓ: se borró «Quintero» creyéndola vacía, el servidor dijo 409 y
    /// el apunte quedó `rechazado`. Con la siguiente bajada la zona vuelve.
    Future<String> abrirConElBorradoRechazado(
      WidgetTester tester,
      Size tamano,
    ) async {
      await tester.binding.setSurfaceSize(tamano);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await sembrar();
      final clave = await cola.encolar(
        metodo: 'DELETE',
        ruta: '/board/columns/z3',
        cuerpo: const <String, Object?>{},
      );
      await cola.resolver(
        clave,
        const ResultadoApunte(estado: EstadoResultado.rechazado, motivo: elNo),
      );
      await tester.pumpWidget(montar());
      await asentar(tester);
      if (tamano == _telefono) {
        await _irALaZona(tester, _vacia);
      }
      return clave;
    }

    for (final (nombre, tamano) in const [
      ('el teléfono', _telefono),
      ('el escritorio', _escritorio),
    ]) {
      testWidgets('en $nombre: tocar «rechazada» dice el motivo LITERAL y '
          'ofrece Reintentar y Descartar', (tester) async {
        await abrirConElBorradoRechazado(tester, tamano);

        expect(find.text('rechazada: ver por qué'), findsOneWidget);
        // Mudo no: el motivo no sale hasta tocar, pero la etiqueta lo promete.
        expect(find.text(elNo), findsNothing);

        await tester.tap(find.byKey(const ValueKey('zona-rechazada')));
        await asentar(tester);

        expect(find.text('Lo que el servidor no aceptó de «$_vacia»'), findsOneWidget);
        expect(
          find.text(elNo),
          findsOneWidget,
          reason: 'el motivo es el literal del servidor, sin tocar',
        );
        expect(find.text('Borrar la zona'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.text('Descartar'), findsOneWidget);

        await desmontar(tester);
      });
    }

    testWidgets('PAREJA: sin nada rechazado no hay etiqueta', (tester) async {
      await tester.binding.setSurfaceSize(_escritorio);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await sembrar();
      await tester.pumpWidget(montar());
      await asentar(tester);

      expect(find.text(_vacia, skipOffstage: false), findsNothing);
      expect(find.textContaining('$_vacia (0)'), findsOneWidget);
      expect(find.byKey(const ValueKey('zona-rechazada')), findsNothing);
      expect(find.textContaining('rechazada'), findsNothing);

      await desmontar(tester);
    });

    testWidgets('Descartar deja la zona como está en el servidor, sin atasco', (
      tester,
    ) async {
      final clave = await abrirConElBorradoRechazado(tester, _escritorio);
      await tester.tap(find.byKey(const ValueKey('zona-rechazada')));
      await asentar(tester);

      await tester.tap(find.text('Descartar'));
      await asentar(tester);

      // Se ESCRIBE, no se borra (§4): el apunte queda `descartado` con su motivo.
      final apunte = await (base.select(
        base.apuntes,
      )..where((a) => a.clave.equals(clave))).getSingle();
      expect(apunte.estado, EstadoApunte.descartado);
      expect(apunte.motivo, elNo);
      expect(find.text('No queda nada rechazado en esta zona.'), findsOneWidget);

      // Y la zona está, como arriba, y la bajada no se niega.
      expect(
        (await ConsultasTablero(base).columnas(sucursalStg)).map((c) => c.id),
        ['z1', 'z2', 'z3'],
      );
      expect(
        (await tester.runAsync(() => servicio().descargar(sucursalStg)))!.porQue,
        isNull,
        reason: 'descartar no deja nada protegiendo una fila que no existe',
      );

      await desmontar(tester);
    });

    testWidgets('Reintentar devuelve el apunte a la cola', (tester) async {
      final clave = await abrirConElBorradoRechazado(tester, _escritorio);
      await tester.tap(find.byKey(const ValueKey('zona-rechazada')));
      await asentar(tester);

      await tester.tap(find.text('Reintentar'));
      await asentar(tester);

      final apunte = await (base.select(
        base.apuntes,
      )..where((a) => a.clave.equals(clave))).getSingle();
      expect(apunte.estado, EstadoApunte.pendiente);

      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  group('el cajón de borrar una zona', () {
    Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    Widget montar() => ProviderScope(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        clienteApiProvider.overrideWithValue(
          ClienteApi(
            dio: Dio()..httpClientAdapter = servidor,
            esperas: const <Duration>[],
          ),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: sucursalStg,
            ),
          ),
        ),
        sucursalDeLaSesionProvider.overrideWithValue(sucursalStg),
      ],
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );

    /// Abre «Borrar la columna» de la zona [nombre] por la pantalla.
    Future<void> borrarDesdeLaPantalla(
      WidgetTester tester,
      Size tamano,
      String nombre,
    ) async {
      await tester.binding.setSurfaceSize(tamano);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await sembrar();
      await tester.pumpWidget(montar());
      await asentar(tester);
      if (tamano == _telefono) {
        await _irALaZona(tester, nombre);
      }
      // La cabecera de la zona que se mira, y no la de otra: en escritorio hay
      // tres «Opciones de la columna».
      final cabecera = find.ancestor(
        of: find.textContaining('$nombre ('),
        matching: find.byType(Row),
      );
      await tester.tap(
        find
            .descendant(
              of: cabecera.first,
              matching: find.byTooltip('Opciones de la columna'),
            ),
      );
      await asentar(tester);
      await tester.tap(find.text('Borrar la columna'));
      await asentar(tester);
    }

    for (final (donde, tamano) in const [
      ('el teléfono', _telefono),
      ('el escritorio', _escritorio),
    ]) {
      testWidgets('en $donde: con pedidos que no se ven NO se quita; dice el '
          'motivo y ofrece mover o devolver', (tester) async {
        await borrarDesdeLaPantalla(tester, tamano, _versalles);

        expect(
          find.text('«$_versalles» tiene 3 pedidos puestos'),
          findsOneWidget,
        );
        expect(find.text('Mover los 3 pedidos a otra zona y borrar'), findsOneWidget);
        expect(
          find.text('Devolver los 3 pedidos a «Sin colocar» y borrar'),
          findsOneWidget,
        );
        expect(
          find.textContaining('2 de ellos no se ven en este aparato'),
          findsOneWidget,
          reason: 'la zona enseña 1 tarjeta y el servidor cuenta 3: se explica',
        );
        expect(find.textContaining('Sí, borrar'), findsNothing);
        expect(await encolado(), isEmpty, reason: 'no se ha encolado nada');

        await desmontar(tester);
      });

      testWidgets('en $donde: PAREJA, la zona vacía pregunta y se borra', (
        tester,
      ) async {
        await borrarDesdeLaPantalla(tester, tamano, _vacia);

        expect(find.text('Sí, borrar «$_vacia»'), findsOneWidget);
        expect(find.textContaining('tiene'), findsNothing);
        await tester.tap(find.text('Sí, borrar «$_vacia»'));
        await asentar(tester);

        expect(await encolado(), ['DELETE /board/columns/z3']);

        await desmontar(tester);
      });
    }

    testWidgets('una zona que se lee «(0)» y arriba tiene 2: NO se borra en '
        'seco, dice el motivo literal', (tester) async {
      await borrarDesdeLaPantalla(tester, _escritorio, _centro);

      expect(find.text('«$_centro» tiene 2 pedidos puestos'), findsOneWidget);
      expect(find.textContaining('Sí, borrar'), findsNothing);
      expect(find.text('Mover los 2 pedidos a otra zona y borrar'), findsOneWidget);
      expect(await encolado(), isEmpty);

      await desmontar(tester);
    });

    testWidgets('mover los pedidos: elige destino y el servidor recibe el '
        'destino', (tester) async {
      await borrarDesdeLaPantalla(tester, _escritorio, _versalles);

      await tester.tap(find.text('Mover los 3 pedidos a otra zona y borrar'));
      await asentar(tester);
      await tester.tap(find.text(_centro));
      await asentar(tester);

      expect(await encolado(), [
        'PUT /board/placements/p1',
        'DELETE /board/columns/z1?destino=z2',
      ]);

      await desmontar(tester);
    });

    testWidgets('devolver a «Sin colocar»: el servidor recibe vaciar', (
      tester,
    ) async {
      await borrarDesdeLaPantalla(tester, _escritorio, _versalles);

      await tester.tap(
        find.text('Devolver los 3 pedidos a «Sin colocar» y borrar'),
      );
      await asentar(tester);

      expect((await encolado()).last, 'DELETE /board/columns/z1?vaciar=1');

      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  group('en la web el 409 se dice con su motivo y la zona no se mueve', () {
    test('el no del servidor llega literal, con su número, y la zona sigue',
        () async {
      await sembrar();
      final enLaWeb = RepositorioTablero(
        base,
        cola,
        enVivo: _enVivoContra(servidor),
      );
      await servicio().descargar(sucursalStg);
      contesta = (p) async => p.metodo == 'DELETE'
          ? RespuestaFalsa(409, <String, Object?>{
              'error': '«$_vacia» tiene 4 pedidos puestos',
              'pedidos': 4,
            })
          : RespuestaFalsa(200, _foto());

      // Una zona que aquí se ve vacía y arriba no lo está: la web también se
      // entera sólo por el 409.
      await expectLater(
        () => enLaWeb.borrarColumna('z3'),
        throwsA(
          isA<RechazoDelTablero>()
              .having(
                (r) => r.mensaje,
                'mensaje',
                '«$_vacia» tiene 4 pedidos puestos',
              )
              .having((r) => r.pedidos, 'pedidos', 4),
        ),
      );
      expect(
        (await ConsultasTablero(base).columnas(sucursalStg)).map((c) => c.id),
        contains('z3'),
        reason: 'la zona no se mueve de la pantalla',
      );
      expect(await encolado(), isEmpty, reason: 'la web no tiene cola');
    });
  });
}

/// Lo que en la web manda cada gesto al servidor en el acto.
EscrituraEnVivo _enVivoContra(ServidorFalso servidor) => EscrituraEnVivo(
  ClienteApi(
    dio: Dio()..httpClientAdapter = servidor,
    esperas: const <Duration>[],
  ),
);
