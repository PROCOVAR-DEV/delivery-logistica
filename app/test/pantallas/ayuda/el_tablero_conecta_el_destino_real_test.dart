import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';
import 'package:reparto/pantallas/tablero/vista/columna.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

class TableroFalso extends TableroDelDia {
  @override
  Future<Tablero> build() async => const Tablero(
    sucursalId: 'b-stg',
    sucursalNombre: 'Santiago',
    almacen: AlmacenOrigen(id: 'a-stg', nombre: 'Santiago', lat: 20, lng: -75),
    columnas: [
      ColumnaTablero(
        id: 'z0',
        branchId: 'b-stg',
        nombre: 'Centro',
        posicion: 0,
        pedidos: 0,
        pesoKg: 0,
        costoUsd: 0,
      ),
      ColumnaTablero(
        id: 'z1',
        branchId: 'b-stg',
        nombre: 'Carretera',
        posicion: 1,
        pedidos: 0,
        pesoKg: 0,
        costoUsd: 0,
      ),
    ],
    colocados: [],
    avisos: AvisosTablero(),
    sinColocar: MitadIzquierda(pedidos: [], total: 0),
    desaparecidos: [],
  );
}

void main() {
  test('dos marcas en el mismo renglon y la duplicada se leen una vez', () {
    final pasos = pasosDelCuerpo(
      '1. Arrastra. <!-- señala: origen --> <!-- señala: destino --> <!-- señala: destino -->',
    );
    expect(
      pasos.single.controles,
      ['origen', 'destino'],
      reason: 'todas las marcas del mismo paso y renglón deben sobrevivir, sin duplicados',
    );
  });
  testWidgets('PantallaTablero conecta el foco al destino de la segunda zona', (
    tester,
  ) async {
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tableroProvider.overrideWith(TableroFalso.new),
          monedaEfectivaProvider.overrideWithValue('USD'),
          tasaDeLaMiradaProvider.overrideWithValue(
            const TasaDeLaMirada.no('sin tasa en prueba'),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
      ),
    );
    await tester.pumpAndSettle();
    final columnas = find.byType(ColumnaDelTablero);
    expect(
      columnas,
      findsNWidgets(2),
      reason: 'el fixture sólo entrega datos; las columnas y _Zona las monta la pantalla real',
    );
    final destino = RegistroDeControles.donde(
      Senalado.tableroSegundaZonaDondeSoltar,
    );
    expect(
      destino,
      isNotNull,
      reason: 'el wiring de _Zona debe marcar un solo destino',
    );
    expect(
      tester.getRect(columnas.at(1)).contains(destino!.rect.center),
      isTrue,
      reason: '_Zona debe marcar como destino la segunda zona real',
    );
    expect(
      tester.getRect(columnas.at(0)).contains(destino.rect.center),
      isFalse,
      reason: 'el destino debe ser distinto del origen',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
