// QUIEN REPARTE VA EN LAS DOS HOJAS IMPRESAS DE UNA RUTA (issue 7, 15/10/2026).
//
// POST-DESPACHO: el cierre leia el nombre con `ref.read(distribuidoresDeLaBarraProvider).value`,
// un `StreamProvider` que el cierre no observa. Abierto SOLO (sin pasar antes por el detalle, que si
// lo observa) `.value` era null y el papel que firma el chofer salia sin el distribuidor. Las pruebas
// que habia montaban el cierre sin distribuidor y no lo veian. Aqui se monta el cierre SOLO.
//
// PRE-DESPACHO (decision de Jose): el almacen tiene que saber a quien entrega la carga, asi que su
// hoja lo lleva en el mismo renglon y con las mismas palabras que la del post-despacho.
//
// EN PAREJA: con distribuidor el papel lo dice; sin el (o sin bajar) no inventa nada.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/impresion/vista_previa.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../impresion/los_dos_pesos_del_pre_despacho_test.dart'
    show leerElPapel;
import '../pedidos/sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 10, 15, 9);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Una ruta en curso con dos paradas y un renglon cada una, y [distribuidorId] en la ruta.
  /// [bajado] = el aparato tiene la fila de `distribuidores`.
  Future<void> sembrar({String? distribuidorId, bool bajado = true}) async {
    await sembrarCatalogo(base);
    await sembrarRuta(
      base,
      id: 'R1',
      estado: EstadoRuta.enCurso,
      codigo: 'RT-20261015-001',
      distribuidorId: distribuidorId,
    );
    for (final (i, nombre) in <String>['Ana', 'Beto'].indexed) {
      await sembrarPedido(base, id: 'p$i', cliente: nombre, rutaId: 'R1', orden: i + 1);
      await sembrarRenglon(
        base,
        id: 'ri$i',
        pedidoId: 'p$i',
        producto: 'Arroz',
        unidades: 10,
        empaques: 2,
      );
    }
    if (bajado) {
      await base.into(base.distribuidores).insert(
        DistribuidoresCompanion.insert(
          id: 'd-juan',
          nombre: 'Juan Pérez',
          activo: const Value(true),
          branchId: const Value('B1'),
        ),
      );
    }
  }

  Future<void> pintar(WidgetTester tester, Widget pantalla) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
          // Sin calles: el detalle no va de mapas, y la prueba no sale a la red.
          fondoDeCallesProvider.overrideWithValue(const SinCalles()),
          recorridoPorCallesProvider.overrideWithValue(const SinCallesQueSeguir()),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: Scaffold(body: pantalla),
        ),
      ),
    );
    await asentar(tester);
  }

  /// Lo que dice el papel que abre [boton], renglon a renglon.
  Future<String> elPapel(WidgetTester tester, Finder boton) async {
    await tester.tap(boton);
    await asentar(tester);
    final vista = tester.widget<VistaPreviaPdf>(find.byType(VistaPreviaPdf));
    final bytes = await vista.armar(PdfPageFormat.a4);
    return leerElPapel(bytes).renglones.map((r) => r.texto).join('\n');
  }

  final postDespacho = find.widgetWithText(OutlinedButton, 'Post-despacho');
  final preDespacho = find.byKey(claveDeVerEImprimirElPreDespacho);
  const cierreSolo = CierreDeRuta(rutaId: 'R1', modo: ModoDelCierre.marcar);

  group('POST-DESPACHO, con el cierre montado SOLO', () {
    testWidgets('con distribuidor, la cabecera lo dice', (tester) async {
      await sembrar(distribuidorId: 'd-juan');
      await pintar(tester, cierreSolo);

      final papel = await elPapel(tester, postDespacho);
      expect(
        papel,
        contains('RT-20261015-001 · Camagüey · Camión 1 · Distribuidor Juan Pérez'),
        reason: 'el papel que firma el chofer salio SIN quien reparte: el nombre se leyo de un '
            'StreamProvider que nadie observaba',
      );
      await desmontar(tester);
    });

    for (final (caso, id, bajado) in const [
      ('la ruta no tiene', null, true),
      ('el aparato no lo ha bajado', 'd-juan', false),
    ]) {
      testWidgets('sin distribuidor ($caso) no inventa nada', (tester) async {
        await sembrar(distribuidorId: id, bajado: bajado);
        await pintar(tester, cierreSolo);

        final papel = await elPapel(tester, postDespacho);
        expect(papel, contains('RT-20261015-001'), reason: 'no se leyo la cabecera');
        expect(papel, isNot(contains('Distribuidor')));
        await desmontar(tester);
      });
    }
  });

  group('PRE-DESPACHO de la ruta (detalle)', () {
    testWidgets('con distribuidor, la cabecera lo dice', (tester) async {
      await sembrar(distribuidorId: 'd-juan');
      await pintar(tester, const DetalleDeRuta(rutaId: 'R1'));

      final papel = await elPapel(tester, preDespacho);
      expect(
        papel,
        contains('Camagüey · Camión 1 · Distribuidor Juan Pérez'),
        reason: 'el almacen tiene que saber a quien entrega la carga',
      );
      await desmontar(tester);
    });

    for (final (caso, id, bajado) in const [
      ('la ruta no tiene', null, true),
      ('el aparato no lo ha bajado', 'd-juan', false),
    ]) {
      testWidgets('sin distribuidor ($caso) no inventa nada', (tester) async {
        await sembrar(distribuidorId: id, bajado: bajado);
        await pintar(tester, const DetalleDeRuta(rutaId: 'R1'));

        final papel = await elPapel(tester, preDespacho);
        expect(papel, contains('Pre-despacho'), reason: 'no se leyo la cabecera');
        expect(papel, isNot(contains('Distribuidor')));
        await desmontar(tester);
      });
    }
  });
}
