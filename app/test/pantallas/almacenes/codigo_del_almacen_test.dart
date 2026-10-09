import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/almacenes/datos/almacen_api.dart';
import 'package:reparto/pantallas/almacenes/datos/coordenadas.dart';
import 'package:reparto/pantallas/almacenes/datos/geocodificar.dart';
import 'package:reparto/pantallas/almacenes/vista/editor_almacen.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';

/// EL CÓDIGO DEL ALMACÉN (el `objectCode` de Ventra).
///
/// Sin él Reparto mide todos los pedidos desde el almacén principal
/// (`accesos-sin-codigos`, 9.000 pedidos el 09/10/2026). Lo delicado no es
/// guardarlo: es **no borrarlo sin querer**. El PUT a Accesos manda la lista
/// ENTERA, así que un almacén que no conoce su código y lo manda vacío se lo
/// quita a quien lo puso entre medias.
///
/// Regla del modelo: `codigo == null` NO viaja (Accesos conserva el que tenga);
/// `codigo == ''` viaja y lo quita; cualquier otro texto lo pone.
class _SinRed implements Geocodificador {
  @override
  Future<BusquedaDeDireccion> buscarDireccion(String texto) async =>
      const NoSePudoPreguntar('sin red');

  @override
  Future<BusquedaDePunto> comoSeLlamaEstePunto(PuntoEnElMapa punto) async =>
      const NoSePudoPreguntarElPunto('sin red');
}

void main() {
  group('el modelo', () {
    test('lee el código que devuelve Accesos', () {
      final a = AlmacenDeAccesos.deJson({
        'id': 'a1',
        'nombre': 'AURORA',
        'codigo': '2',
      });
      expect(a.codigo, '2');
    });

    test('sin código en el JSON queda null (no "")', () {
      final a = AlmacenDeAccesos.deJson({'id': 'a1', 'nombre': 'AURORA'});
      expect(a.codigo, isNull);
    });

    test('null NO se manda: no puede borrar el código de otro', () {
      const a = AlmacenDeAccesos(id: 'a1', nombre: 'AURORA');
      expect(a.aJson().containsKey('codigo'), isFalse);
    });

    test('"" SÍ se manda (es quitarlo a propósito) y un texto también', () {
      expect(
        const AlmacenDeAccesos(nombre: 'A', codigo: '').aJson()['codigo'],
        '',
      );
      expect(
        const AlmacenDeAccesos(nombre: 'A', codigo: '13').aJson()['codigo'],
        '13',
      );
    });

    test('copiar conserva el código; copiar(codigo: x) lo cambia', () {
      const a = AlmacenDeAccesos(nombre: 'A', codigo: '2');
      expect(a.copiar(principal: true).codigo, '2');
      expect(a.copiar(codigo: '7').codigo, '7');
    });
  });

  group('el editor', () {
    Future<List<AlmacenDeAccesos>> pintar(
      WidgetTester tester, {
      AlmacenDeAccesos? almacen,
    }) async {
      final guardados = <AlmacenDeAccesos>[];
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorAlmacen(
              almacen: almacen,
              sucursal: 'Santiago',
              guardando: false,
              geocodificador: _SinRed(),
              fondoDelMapa: const SinCalles(),
              alGuardar: guardados.add,
            ),
          ),
        ),
      );
      await tester.pump();
      return guardados;
    }

    Finder cajaDe(String rotulo) =>
        find.ancestor(of: find.text(rotulo), matching: find.byType(TextField));

    Future<void> escribirYGuardar(
      WidgetTester tester, {
      String? nombre,
      String? codigo,
    }) async {
      if (nombre != null) {
        await tester.enterText(cajaDe('Nombre del almacén'), nombre);
      }
      if (codigo != null) {
        await tester.enterText(cajaDe('Código en Ventra'), codigo);
      }
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }

    testWidgets('enseña el código que ya tiene', (tester) async {
      await pintar(
        tester,
        almacen: const AlmacenDeAccesos(
          id: 'a1',
          nombre: 'AURORA',
          codigo: '2',
        ),
      );
      final campo = tester.widget<TextField>(cajaDe('Código en Ventra'));
      expect(campo.controller!.text, '2');
    });

    testWidgets('poner un código nuevo lo guarda, sin espacios', (
      tester,
    ) async {
      final guardados = await pintar(
        tester,
        almacen: const AlmacenDeAccesos(id: 'a1', nombre: 'AURORA'),
      );
      await escribirYGuardar(tester, codigo: '  13 ');
      expect(guardados.single.codigo, '13');
    });

    testWidgets('sin código antes y sin escribir nada: null (no toca)', (
      tester,
    ) async {
      final guardados = await pintar(
        tester,
        almacen: const AlmacenDeAccesos(id: 'a1', nombre: 'AURORA'),
      );
      await escribirYGuardar(tester, nombre: 'AURORA 2');
      expect(guardados.single.codigo, isNull);
      expect(guardados.single.aJson().containsKey('codigo'), isFalse);
    });

    testWidgets('vaciar un código que tenía lo QUITA ("" viaja)', (
      tester,
    ) async {
      final guardados = await pintar(
        tester,
        almacen: const AlmacenDeAccesos(
          id: 'a1',
          nombre: 'AURORA',
          codigo: '2',
        ),
      );
      await escribirYGuardar(tester, codigo: '');
      expect(guardados.single.codigo, '');
      expect(guardados.single.aJson()['codigo'], '');
    });

    testWidgets('cambiar solo el nombre conserva el código tal cual', (
      tester,
    ) async {
      final guardados = await pintar(
        tester,
        almacen: const AlmacenDeAccesos(
          id: 'a1',
          nombre: 'AURORA',
          codigo: '2',
        ),
      );
      await escribirYGuardar(tester, nombre: 'AURORA NUEVA');
      expect(guardados.single.codigo, '2');
    });

    testWidgets('un almacén nuevo puede llevar código desde el principio', (
      tester,
    ) async {
      final guardados = await pintar(tester);
      await escribirYGuardar(tester, nombre: 'NUEVO', codigo: '9');
      expect(guardados.single.codigo, '9');
    });
  });
}
