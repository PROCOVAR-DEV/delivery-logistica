import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/estado/proveedores_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());
  Future<void> asentar(WidgetTester t) async {
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pintar(
    WidgetTester t,
    Stream<RutaConTodo?> cabecera,
    ModoDelCierre modo,
  ) async {
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
    });
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          rutaConTodoProvider.overrideWith((ref, id) => cabecera),
          paradasDeRutaProvider.overrideWith(
            (ref, id) => Stream.value(const []),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CierreDeRuta(rutaId: 'R1', modo: modo),
          ),
        ),
      ),
    );
    await asentar(t);
  }

  testWidgets(
    'cabecera pendiente, inexistente o con error no permite completar',
    (t) async {
      await sembrarCatalogo(base);
      await sembrarRuta(base, id: 'R1', estado: EstadoRuta.enCurso);
      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals('R1'))).getSingle();
      final llegan = StreamController<RutaConTodo?>();
      await pintar(t, llegan.stream, ModoDelCierre.alCompletar);
      FilledButton guardar() => t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Guardar y completar'),
      );
      expect(
        guardar().onPressed,
        isNull,
        reason: 'cargar paradas vacías no confirma que la ruta exista',
      );
      llegan.add(null);
      await asentar(t);
      expect(guardar().onPressed, isNull);
      llegan.add(RutaConTodo(ruta: ruta, paradas: const []));
      await asentar(t);
      expect(guardar().onPressed, isNotNull);
      llegan.addError(StateError('Error al leer la cabecera'));
      await asentar(t);
      expect(
        guardar().onPressed,
        isNull,
        reason: 'no usar la última cabecera como éxito de una consulta fallida',
      );
      expect(find.textContaining('Error al leer la cabecera'), findsOneWidget);
      expect(await base.select(base.apuntes).get(), isEmpty);
      llegan.add(RutaConTodo(ruta: ruta, paradas: const []));
      await asentar(t);
      await t.tap(find.widgetWithText(FilledButton, 'Guardar y completar'));
      await asentar(t);
      final despues = await (base.select(
        base.routes,
      )..where((r) => r.id.equals('R1'))).getSingle();
      expect(despues.status, EstadoRuta.completada);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      await t.runAsync(llegan.close);
    },
  );
  testWidgets('Ver cierre nunca ofrece marcas mientras llega el histórico', (
    t,
  ) async {
    await pintar(
      t,
      const Stream<RutaConTodo?>.empty(),
      ModoDelCierre.soloLectura,
    );
    expect(find.text(CierreDeRuta.cabeceraSoloLectura), findsOneWidget);
    expect(find.text('Todas:'), findsNothing);
    expect(find.textContaining('Guardar'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  });
}
