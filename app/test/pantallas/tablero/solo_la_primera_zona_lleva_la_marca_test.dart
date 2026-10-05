// EN LA TIRA DE ZONAS, SOLO LA PRIMERA LLEVA LAS MARCAS DE LA GUIA.
//
// Es la misma regla que la lista de Clientes
// (`pantallas/ayuda/solo_la_primera_fila_lleva_la_marca_test.dart`) y hace falta
// aquí por lo mismo: `ControlSenalado` no es un `GlobalKey`, así que dos montados
// con el mismo nombre **no revientan nada**. `RegistroDeControles.donde` devuelve
// `null`, la columna se pinta igual, las pruebas del Tablero siguen verdes, y el
// único síntoma es un paso de la Guía sin foco.
//
// Lo que se vigila son los TRES nombres que existen una vez por zona, y los tres
// los nombra el camino principal del día:
//
//  * `tablero-menu-de-la-zona` — el ⋮, que es por donde se pone el camión y se
//    arma la ruta;
//  * `tablero-cabecera-de-la-zona` — lo que se agarra para reordenar las zonas;
//  * `tablero-zona-donde-soltar` — la columna entera, que es donde se suelta lo
//    que se arrastra.
//
// Los dos últimos nacieron el 05/10/2026 con las tareas del día de la web y del
// escritorio, donde se reparte ARRASTRANDO: un arrastre tiene dos sitios —de
// dónde se coge y dónde se deja— y antes sólo estaba marcado el primero.
//
// DOS ZONAS Y NO UNA: con una sola, la prueba sale verde aunque la marca esté en
// todas, que es exactamente la avería que se viene a cazar.
//
// Sin Drift: las `ColumnaTablero` se construyen a mano. Dentro de un
// `testWidgets` una consulta de Drift cuelga la prueba en vez de fallar
// (`CLAUDE.md` §5).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/vista/columna.dart';

void main() {
  ColumnaTablero zona(String id, String nombre) => ColumnaTablero(
    id: id,
    branchId: 'b-stg',
    nombre: nombre,
    posicion: 1,
    pedidos: 3,
    pesoKg: 200,
    costoUsd: 0,
  );

  /// La tira de verdad: la primera marcada y la segunda no, que es lo que hace
  /// `_Zona` en `pantalla_tablero.dart` con `esLaPrimera: cual == 0`.
  Future<void> pintarDos(WidgetTester tester) async {
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monedaEfectivaProvider.overrideWithValue('USD'),
          tasaDeLaMiradaProvider.overrideWithValue(
            const TasaDeLaMirada.no('sin tasa en las pruebas'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: Row(
                children: [
                  for (final (cual, columna) in [
                    zona('z1', 'Centro'),
                    zona('z2', 'Carretera'),
                  ].indexed)
                    ColumnaDelTablero(
                      columna: columna,
                      ancho: 300,
                      esLaPrimera: cual == 0,
                      tarjetas: const [],
                      alSoltar: (_, _) {},
                      alPulsarTarjeta: (_) {},
                      alAbrirMenu: () {},
                      alSoltarColumna: (_) {},
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Que la marca se pueda señalar **y caiga DENTRO de la primera zona**.
  ///
  /// Se mira contra el rectángulo de cada columna y no contra su nombre, porque
  /// los tres controles son de tamaños muy distintos —el ⋮ es un icono a la
  /// derecha de la cabecera, y la zona es la columna entera— y lo único que
  /// tienen en común es de QUÉ columna son. Y las dos mitades hacen falta: sin
  /// la segunda, una marca puesta en la zona equivocada pasaría igual.
  void cae(WidgetTester tester, String nombre) {
    final puesto = RegistroDeControles.donde(nombre);
    expect(
      puesto,
      isNotNull,
      reason:
          'con dos zonas a la vista «$nombre» no se puede señalar: está marcado '
          'en más de una y las dos a la vez no se distinguen, así que el paso de '
          'la Guía sale SIN FOCO y nada falla.',
    );
    final columnas = find.byType(ColumnaDelTablero);
    final primera = tester.getRect(columnas.at(0));
    final segunda = tester.getRect(columnas.at(1));
    final donde = puesto!.rect.center;
    expect(
      primera.contains(donde),
      isTrue,
      reason:
          'el foco de «$nombre» cae en ${puesto.rect}, y la primera zona ocupa '
          '$primera: se está señalando algo de otra columna.',
    );
    expect(
      segunda.contains(donde),
      isFalse,
      reason:
          'el foco de «$nombre» cae dentro de la SEGUNDA zona ($segunda), que es '
          'peor que no señalar ninguna.',
    );
  }

  testWidgets('el ⋮ de la zona se señala una vez, en la primera', (
    tester,
  ) async {
    await pintarDos(tester);
    cae(tester, Senalado.tableroMenuDeLaZona);
  });

  testWidgets('la cabecera que se agarra para reordenar, también', (
    tester,
  ) async {
    await pintarDos(tester);
    cae(tester, Senalado.tableroCabeceraDeLaZona);
  });

  testWidgets('y la zona entera, que es donde se suelta', (tester) async {
    await pintarDos(tester);
    cae(tester, Senalado.tableroZonaDondeSoltar);
  });

  /// Y LA CONTRAPARTE: con las dos marcadas no se señala ninguna.
  ///
  /// Sin esto, las tres de arriba se cumplirían con `senalable: true` en una
  /// tira de UNA zona, y nadie estaría comprobando el `cual == 0`. Aquí se
  /// monta la avería a mano y se mira que el registro la detecta en vez de
  /// elegir una a cara o cruz.
  testWidgets('con las dos marcadas, el registro no elige: dice que no', (
    tester,
  ) async {
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monedaEfectivaProvider.overrideWithValue('USD'),
          tasaDeLaMiradaProvider.overrideWithValue(
            const TasaDeLaMirada.no('sin tasa en las pruebas'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: Row(
                children: [
                  for (final columna in [
                    zona('z1', 'Centro'),
                    zona('z2', 'Carretera'),
                  ])
                    ColumnaDelTablero(
                      columna: columna,
                      ancho: 300,
                      esLaPrimera: true,
                      tarjetas: const [],
                      alSoltar: (_, _) {},
                      alPulsarTarjeta: (_) {},
                      alAbrirMenu: () {},
                      alSoltarColumna: (_) {},
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final nombre in [
      Senalado.tableroMenuDeLaZona,
      Senalado.tableroCabeceraDeLaZona,
      Senalado.tableroZonaDondeSoltar,
    ]) {
      expect(
        RegistroDeControles.donde(nombre),
        isNull,
        reason:
            '«$nombre» está marcado en las dos zonas y el registro ha elegido '
            'una: el recorrido señalaría la que no era.',
      );
    }
  });
}
