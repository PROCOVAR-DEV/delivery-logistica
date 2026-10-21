// INACTIVAR Y ACTIVAR ZONAS — issue 15 de Amado, 16/10/2026.
//
// Amado: «si es que se han usado en rutas anteriores, entonces debería
// implementarse la inactivación/activación y que solo salgan las activas». Jose
// lo pidió expresamente. Contrato con el servidor (migración 00022):
//
//  * `PATCH /board/columns/{id}` con `{"activa": false|true}`; al inactivar, el
//    servidor devuelve a «Sin colocar» los pedidos puestos y marca la zona;
//  * `GET /board` trae `activa` en cada zona y, con `incluirInactivas=1`, TAMBIÉN
//    las inactivas (la bajada lo pide así y filtra en local);
//  * colocar o armar en una inactiva: 409 «La zona «X» está inactiva».
//
// Cada guarda va en pareja: la que sale cuando toca y la que NO sale cuando no.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';
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
const _vieja = 'Z9_Vieja';

/// Versalles con 3 puestos (sólo `p1` está aquí), Centro vacía y «Vieja»
/// INACTIVA, que el servidor manda porque la bajada pide `incluirInactivas=1`.
Map<String, Object?> _foto() => <String, Object?>{
  'columnas': [
    for (final (i, (id, nombre, activa)) in [
      ('z1', _versalles, true),
      ('z2', _centro, true),
      ('z9', _vieja, false),
    ].indexed)
      {
        'id': id,
        'branchId': sucursalStg,
        'nombre': nombre,
        'posicion': i + 1,
        'activa': activa,
      },
  ],
  'colocados': [
    for (final (i, p) in ['p1', 'p2', 'p3'].indexed)
      {'pedidoId': p, 'columnaId': 'z1', 'posicion': i + 1},
  ],
};

Future<void> _irALaZona(WidgetTester tester, String nombre) async {
  for (final z in const [_versalles, _centro]) {
    await tester.tap(find.byTooltip('Ir a «$z»'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    if (z == nombre) return;
  }
}

void main() {
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

  ClienteApi cliente() => ClienteApi(
    dio: Dio()..httpClientAdapter = servidor,
    esperas: const <Duration>[],
  );

  ServicioTablero servicio() =>
      ServicioTablero(base, cliente(), RegistroDeFrescura(base));

  Future<void> sembrar() async {
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'p1');
  }

  Future<List<String>> activas() async => [
    for (final c in await ConsultasTablero(base).columnas(sucursalStg)) c.id,
  ];

  Future<List<String>> inactivas() async => [
    for (final c in await ConsultasTablero(
      base,
    ).columnas(sucursalStg, inactivas: true))
      c.id,
  ];

  Future<List<String>> encolado() async => [
    for (final a in await cola.lote()) '${a.metodo} ${a.ruta}',
  ];

  // ---------------------------------------------------------------------------
  group('la bajada y las lecturas', () {
    test('la bajada PIDE las inactivas, las guarda y el tablero no las enseña',
        () async {
      await sembrar();
      await servicio().descargar(sucursalStg);

      final peticion = servidor.vistas.firstWhere((p) => p.ruta.endsWith('/board'));
      expect(peticion.parametros['incluirInactivas'], '1');
      expect(await activas(), ['z1', 'z2'], reason: 'Vieja no sale en el tablero');
      expect(await inactivas(), ['z9']);
    });

    test('PAREJA: un servidor sin el campo `activa` deja todas activas',
        () async {
      await sembrar();
      contesta = (p) async => RespuestaFalsa(200, <String, Object?>{
        'columnas': [
          {'id': 'z1', 'branchId': sucursalStg, 'nombre': 'A', 'posicion': 1},
        ],
        'colocados': <Object?>[],
      });
      await servicio().descargar(sucursalStg);

      expect(await activas(), ['z1']);
      expect(await inactivas(), isEmpty);
    });

    test('una base de ANTES (sin la columna `activa`) la gana a 1 sin perder '
        'la zona', () async {
      await base.customStatement(
        'CREATE TABLE board_columns (id TEXT NOT NULL PRIMARY KEY, '
        'branch_id TEXT NOT NULL, nombre TEXT NOT NULL, posicion INTEGER NOT NULL, '
        'vehicle_id TEXT, almacen_id TEXT, creado_por TEXT, created_at TEXT, '
        'updated_at TEXT, nacio_aqui INTEGER NOT NULL DEFAULT 0)',
      );
      await base.customStatement(
        "INSERT INTO board_columns (id, branch_id, nombre, posicion) "
        "VALUES ('vieja', '$sucursalStg', 'De antes', 1)",
      );

      await EsquemaTablero.asegurar(base);

      final f = await base
          .customSelect("SELECT activa FROM board_columns WHERE id = 'vieja'")
          .getSingle();
      expect(f.read<int>('activa'), 1);
    });
  });

  // ---------------------------------------------------------------------------
  group('inactivar y activar', () {
    test('inactivar: la zona sale, sus pedidos vuelven y sube UN apunte',
        () async {
      await sembrar();
      await servicio().descargar(sucursalStg);

      final volvieron = await repo.inactivarColumna('z1');

      expect(volvieron, 1, reason: 'las tarjetas que este aparato tenía');
      expect(await activas(), ['z2']);
      expect(await inactivas(), ['z1', 'z9']);
      final puestas = await base
          .customSelect('SELECT count(*) AS n FROM board_placements')
          .getSingle();
      expect(puestas.read<int>('n'), 0, reason: 'vuelven a «Sin colocar»');
      expect(await encolado(), ['PATCH /board/columns/z1']);
      expect((await cola.lote()).single.cuerpo, '{"activa":false}');
    });

    test('activar: vuelve, VACÍA, y sube su apunte', () async {
      await sembrar();
      await servicio().descargar(sucursalStg);

      await repo.activarColumna('z9');

      expect(await activas(), ['z1', 'z2', 'z9']);
      expect(await inactivas(), isEmpty);
      expect(await encolado(), ['PATCH /board/columns/z9']);
      expect((await cola.lote()).single.cuerpo, '{"activa":true}');
      final c = (await ConsultasTablero(base).columnas(sucursalStg))
          .firstWhere((c) => c.id == 'z9');
      expect(c.pedidos, 0);
    });

    test('colocar en una zona inactiva: el literal del servidor y no se '
        'encola', () async {
      await sembrar();
      await sembrarPedido(base, id: 'p7');
      await servicio().descargar(sucursalStg);

      await expectLater(
        () => repo.colocar(pedidoId: 'p7', columnaId: 'z9'),
        throwsA(
          isA<RechazoDelTablero>().having(
            (r) => r.mensaje,
            'mensaje',
            'La zona «$_vieja» está inactiva',
          ),
        ),
      );
      expect(await encolado(), isEmpty);
    });

    test('PAREJA: colocar en una activa sigue funcionando', () async {
      await sembrar();
      await sembrarPedido(base, id: 'p7');
      await servicio().descargar(sucursalStg);

      await repo.colocar(pedidoId: 'p7', columnaId: 'z2');

      expect(await encolado(), ['PUT /board/placements/p7']);
    });

    test('armar la ruta de una inactiva: el literal, sin encolar', () async {
      await sembrar();
      await servicio().descargar(sucursalStg);

      await expectLater(
        () => repo.armarRuta(columnaId: 'z9', sucursalId: sucursalStg),
        throwsA(
          isA<RechazoDelTablero>().having(
            (r) => r.mensaje,
            'mensaje',
            'La zona «$_vieja» está inactiva',
          ),
        ),
      );
      expect(await encolado(), isEmpty);
    });

    test('en la web el no del servidor llega literal y la zona SIGUE activa',
        () async {
      await sembrar();
      await servicio().descargar(sucursalStg);
      final enLaWeb = RepositorioTablero(
        base,
        cola,
        enVivo: EscrituraEnVivo(cliente()),
      );
      contesta = (p) async => p.metodo == 'PATCH'
          ? RespuestaFalsa(409, const <String, Object?>{
              'error': 'No se puede inactivar ahora',
            })
          : RespuestaFalsa(200, _foto());

      await expectLater(
        () => enLaWeb.inactivarColumna('z2'),
        throwsA(
          isA<RechazoDelTablero>().having(
            (r) => r.mensaje,
            'mensaje',
            'No se puede inactivar ahora',
          ),
        ),
      );
      expect(await activas(), ['z1', 'z2']);
      expect(await encolado(), isEmpty, reason: 'la web no tiene cola');
    });
  });

  // ---------------------------------------------------------------------------
  group('en la pantalla', () {
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
        clienteApiProvider.overrideWithValue(cliente()),
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

    Future<void> abrirBorrar(WidgetTester tester, Size tamano, String zona) async {
      await tester.binding.setSurfaceSize(tamano);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await sembrar();
      await tester.pumpWidget(montar());
      await asentar(tester);
      if (tamano == _telefono) await _irALaZona(tester, zona);
      final cabecera = find.ancestor(
        of: find.textContaining('$zona ('),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(
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
      testWidgets('en $donde: una zona con pedidos ofrece INACTIVAR junto a '
          'mover, y la inactiva', (tester) async {
        await abrirBorrar(tester, tamano, _versalles);

        expect(find.text('Inactivar la zona'), findsOneWidget);
        expect(
          find.text('Mover las 3 facturas a otra zona y borrar'),
          findsOneWidget,
        );
        await tester.tap(find.text('Inactivar la zona'));
        await asentar(tester);

        expect(await encolado(), contains('PATCH /board/columns/z1'));
        expect(await activas(), ['z2']);

        await desmontar(tester);
      });

      testWidgets('en $donde: una zona VACÍA ofrece borrar o inactivar',
          (tester) async {
        await abrirBorrar(tester, tamano, _centro);

        expect(find.text('Sí, borrar «$_centro»'), findsOneWidget);
        expect(find.text('Inactivar en vez de borrar'), findsOneWidget);
        await tester.tap(find.text('Inactivar en vez de borrar'));
        await asentar(tester);

        expect(await encolado(), ['PATCH /board/columns/z2']);
        expect(await activas(), ['z1']);

        await desmontar(tester);
      });
    }

    testWidgets('el cajón «Zonas inactivas» lista las inactivas y las ACTIVA',
        (tester) async {
      await tester.binding.setSurfaceSize(_escritorio);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await sembrar();
      await tester.pumpWidget(montar());
      await asentar(tester);

      // En el tablero no está…
      expect(find.textContaining('$_vieja ('), findsNothing);

      await tester.tap(find.byTooltip('Zonas inactivas'));
      await asentar(tester);
      expect(find.text(_vieja), findsOneWidget);
      await tester.tap(find.text('Activar'));
      await asentar(tester);

      // …se activa: sale de la lista y entra al tablero, vacía.
      expect(await encolado(), ['PATCH /board/columns/z9']);
      expect(await activas(), contains('z9'));
      expect(
        find.text('No hay ninguna zona inactiva.', findRichText: true),
        findsNothing,
      );

      await desmontar(tester);
    });

    testWidgets('PAREJA: sin zonas inactivas el cajón lo dice y no ofrece '
        'activar nada', (tester) async {
      await tester.binding.setSurfaceSize(_escritorio);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await sembrar();
      contesta = (p) async => RespuestaFalsa(200, <String, Object?>{
        ..._foto(),
        'columnas': [
          for (final c in (_foto()['columnas']! as List).cast<Map<String, Object?>>())
            if (c['activa'] == true) c,
        ],
      });
      await tester.pumpWidget(montar());
      await asentar(tester);

      await tester.tap(find.byTooltip('Zonas inactivas'));
      await asentar(tester);

      expect(find.textContaining('No hay ninguna zona inactiva'), findsOneWidget);
      expect(find.text('Activar'), findsNothing);

      await desmontar(tester);
    });
  });
}
