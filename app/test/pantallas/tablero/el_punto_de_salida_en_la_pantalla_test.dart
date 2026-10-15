// EL «PUNTO DE SALIDA» DE UNA ZONA, POR LA PANTALLA Y CON EL DEDO — 15/10/2026.
//
// Lo que se mira aquí es lo que ve quien arma el día, en el teléfono y en el
// escritorio: el menú de la zona lo ofrece con el punto actual debajo, la lista
// sólo trae los almacenes DE ESA SUCURSAL (los sin ubicación, apagados), elegir
// uno cambia la cabecera de la zona («desde AURORA») y sale por la cola; y las
// zonas van agrupadas por su punto, de modo que cambiarlo mueve la zona de grupo.
// La regla y el camino de la web están en `el_punto_de_salida_de_la_zona_test.dart`.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

const _telefono = Size(390, 844);
const _escritorio = Size(1400, 900);

void main() {
  late BaseLocal base;

  // Sólo se abre la base: sembrar en el `setUp` de un `testWidgets` cuelga (§5).
  setUp(() => base = BaseLocal.con(NativeDatabase.memory()));
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  Widget montar() {
    final dio = Dio()
      ..httpClientAdapter = ServidorFalso((peticion) async => null);
    return ProviderScope(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        clienteApiProvider.overrideWithValue(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
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
      ],
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  /// Santiago con PV-STGO (principal), AURORA y uno sin ubicación; Holguín con
  /// el suyo. Tres zonas creadas en este orden: Centro, Aurora (desde AURORA) y
  /// Vista.
  Future<void> sembrar() async {
    await sembrarSucursal(base);
    await sembrarAlmacen(base, id: 'alm-pv', nombre: 'PV-STGO');
    await sembrarAlmacen(
      base,
      id: 'alm-aurora',
      nombre: 'AURORA',
      lat: 20.0311,
      lng: -75.7902,
      principal: false,
    );
    await sembrarAlmacen(
      base,
      id: 'alm-sin-punto',
      nombre: 'Parranda Oferta',
      lat: null,
      lng: null,
      principal: false,
    );
    await sembrarAlmacen(
      base,
      id: 'alm-holguin',
      nombre: 'ALM HOLGUIN',
      codigo: 'HOL',
    );
    final repo = RepositorioTablero(base, ColaDeSalida(base));
    await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
    await repo.crearColumna(
      sucursalId: sucursalStg,
      nombre: 'Aurora',
      almacenId: 'alm-aurora',
    );
    await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Vista');
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  for (final (nombre, tamano) in const [
    ('el teléfono', _telefono),
    ('el escritorio', _escritorio),
  ]) {
    testWidgets('en $nombre: el menú enseña y cambia el punto de la zona', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(tamano);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await sembrar();
      await tester.pumpWidget(montar());
      await asentar(tester);
      if (tamano == _telefono) {
        await tester.tap(find.byTooltip('Ir a «Centro»'));
        await asentar(tester);
      }

      // La cabecera de la zona dice de dónde sale: sin punto, del principal.
      expect(find.text('desde PV-STGO'), findsWidgets);

      // «Centro» es la primera zona en los dos tamaños (grupo del principal).
      await tester.tap(find.byTooltip('Opciones de la columna').first);
      await asentar(tester);
      expect(find.text('Punto de salida'), findsOneWidget);
      expect(find.text('El principal: PV-STGO'), findsOneWidget);
      await tester.tap(find.text('Punto de salida'));
      await asentar(tester);

      expect(find.text('Punto de salida de «Centro»'), findsOneWidget);
      expect(find.text('El principal'), findsOneWidget);
      expect(find.text('AURORA'), findsOneWidget);
      expect(find.text('PV-STGO'), findsOneWidget);
      expect(
        find.text('Parranda Oferta'),
        findsOneWidget,
        reason: 'el que no tiene ubicación SALE, apagado y con su motivo',
      );
      expect(
        find.text('ALM HOLGUIN'),
        findsNothing,
        reason: 'sólo los almacenes de la sucursal de la zona',
      );

      // El sin ubicación no se puede elegir: tocarlo no hace nada.
      await tester.tap(find.text('Parranda Oferta'));
      await asentar(tester);
      expect(find.text('Punto de salida de «Centro»'), findsOneWidget);

      await tester.tap(find.text('AURORA'));
      await asentar(tester);

      expect(find.text('Punto de salida de «Centro»'), findsNothing);
      final ultimo = (await ColaDeSalida(base).lote()).last;
      expect(ultimo.metodo, 'PATCH');
      expect(jsonDecode(ultimo.cuerpo), {'almacenId': 'alm-aurora'});
      if (tamano == _telefono) {
        // En el teléfono «Centro» se fue al grupo de AURORA, o sea a otra
        // página: se va a buscarla (el carrusel no la sigue, ver el informe).
        await tester.tap(find.byTooltip('Ir a «Centro»'));
        await asentar(tester);
      }
      expect(find.text('desde AURORA'), findsWidgets);

      await desmontar(tester);
    });
  }

  testWidgets('en el escritorio las zonas van agrupadas por su punto, y '
      'cambiarlo mueve la zona a su grupo', (tester) async {
    await tester.binding.setSurfaceSize(_escritorio);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await sembrar();
    await tester.pumpWidget(montar());
    await asentar(tester);

    double x(String zona) => tester.getTopLeft(find.text('$zona (0)')).dx;

    // Creadas Centro, Aurora, Vista; salen Centro y Vista (PV-STGO) y luego
    // Aurora (AURORA): las de un mismo punto, juntas.
    expect(x('Centro'), lessThan(x('Vista')));
    expect(x('Vista'), lessThan(x('Aurora')));

    // Centro pasa a AURORA sin tocar la pantalla: se va con Aurora y, dentro
    // del grupo, delante (su orden de siempre).
    await RepositorioTablero(base, ColaDeSalida(base)).elegirPuntoDeSalida(
      (await base
              .customSelect(
                "SELECT id FROM board_columns WHERE nombre = 'Centro'",
              )
              .getSingle())
          .read<String>('id'),
      'alm-aurora',
    );
    await asentar(tester);

    expect(x('Vista'), lessThan(x('Centro')));
    expect(x('Centro'), lessThan(x('Aurora')));

    await desmontar(tester);
  });

  // El nombre lo da la copia de `warehouses`: si AURORA cambia de nombre en
  // Accesos y baja, la cabecera lo dice sin volver a montar nada (§3-ter).
  testWidgets('el «desde» sigue al almacén cuando baja con otro nombre', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_escritorio);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await sembrar();
    await tester.pumpWidget(montar());
    await asentar(tester);
    expect(find.text('desde AURORA'), findsOneWidget);

    await (base.update(base.warehouses)
          ..where((w) => w.id.equals('alm-aurora')))
        .write(const WarehousesCompanion(nombre: Value('AURORA NUEVO')));
    await asentar(tester);

    expect(find.text('desde AURORA NUEVO'), findsOneWidget);
    await desmontar(tester);
  });
}
