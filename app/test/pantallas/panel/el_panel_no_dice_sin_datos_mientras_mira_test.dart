// «NO HAY NADA» Y «TODAVÍA NO HE MIRADO» SON DOS COSAS — §3-ter del CLAUDE.md.
//
// El Panel abría diciendo **«sin datos todavía»** encima de una base llena. No
// era un fallo de la consulta: era que mientras el conteo corre —abrir el
// fichero, las migraciones y nueve conteos sobre tablas con decenas de miles de
// renglones, que en un teléfono de gama baja son varios segundos— el
// `AsyncLoading` se colapsaba en `null` con `.value`, y aquí `null` significaba
// «este aparato no tiene nada».
//
// Y es justo el momento que importa: alguien abre la aplicación por la mañana
// para ver si le hace falta traer el día antes de salir al reparto, y lee que no
// tiene nada. Ya estaba arreglado en la franja de Pedidos y de Rutas
// (`SinMirarTodavia`, en `nucleo/frescura/reloj_de_datos.dart`, con estas mismas
// palabras) y aquí se había quedado el literal viejo.
//
// LA FORMA DE ESTA PRUEBA ES LA DEL §3-ter, y no es negociable: **se monta con
// la base VACÍA y se siembra DESPUÉS, sin volver a montar la pantalla.** Sembrar
// en el `setUp` es justo el caso que una sola respuesta resuelve bien, así que
// una prueba escrita así se queda verde con el fallo puesto.
//
// Los tres momentos, en una sola pasada y con la pantalla delante:
//
//   1. mientras cuenta        → «mirando qué hay…», nunca «sin datos todavía»;
//   2. ya contó y no hay nada → «sin datos todavía», que ahí SÍ es verdad;
//   3. entra la bajada        → «datos de las 8:30», sin remontar nada.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/panel/registro.dart';
import 'package:reparto/pantallas/panel/vista/estado_del_dia.dart';

import '../../apoyo/base_de_prueba.dart';

/// Nada de `pumpAndSettle` aqui: la aplicacion entera trae temporizadores que
/// no paran solos —el vigia del ciclo, entre otros— y esperar a que no quede
/// ninguno **cuelga la prueba en vez de fallarla**, que es lo peor que puede
/// hacer una prueba (CLAUDE.md §5). Se le dan vueltas contadas al reloj, como en
/// `pedidos/llega_la_bajada_test.dart`.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final ahora = DateTime(2026, 9, 14, 8, 30);

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  testWidgets('mientras cuenta lo que hay NO dice que no hay nada', (
    tester,
  ) async {
    // Alto de sobra a propósito: lo que se mide aquí es el TEXTO, no dónde cae.
    // El Panel es una lista, y en cuanto el aparato tiene datos le sale encima
    // el paso a paso de la configuración; en 844 px de alto eso empuja la pieza
    // del estado del día fuera del hueco visible, y lo que no se pinta no se
    // puede leer. Lo estrecho tiene su propia prueba
    // (`navegacion/a_390_no_sale_la_cebra_test.dart`).
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // La base entra VACÍA. Todo lo que se siembre, se siembra abajo, con la
    // pantalla ya montada.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarPanel()],
            inicial: '/dashboard',
          ),
        ),
      ),
    );

    // --- 1. El primer fotograma: el conteo todavía no ha contestado ----------
    await tester.pump();
    expect(find.byType(EstadoDelDia), findsOneWidget);
    expect(
      find.text('sin datos todavía'),
      findsNothing,
      reason:
          'El Panel está acusando a la base de estar vacía sin haberla mirado '
          'todavía. Es el §3-ter: el `AsyncLoading` se ha vuelto a colapsar en '
          '`null` (ver `TextosDelDia.datosDeLas`).',
    );
    expect(find.text('mirando qué hay…'), findsOneWidget);

    // --- 2. Ya contó, y de verdad no hay nada. ESO sí se dice ----------------
    await asentar(tester);
    expect(find.text('mirando qué hay…'), findsNothing);
    expect(
      find.text('sin datos todavía'),
      findsOneWidget,
      reason:
          'Contado y vacío: aquí «sin datos todavía» es la verdad y tiene que '
          'salir. Callarlo sería el fallo contrario.',
    );

    // --- 3. Y ahora llega la bajada, CON LA PANTALLA DELANTE -----------------
    //
    // Nada de volver a montar: lo que se comprueba es que la pieza se entera de
    // lo que pasa después de pintarse, que es el caso que un `Future` que se
    // pide una sola vez no cubre.
    final registro = RegistroDeFrescura(base, reloj: () => ahora);
    for (final coleccion in Colecciones.todas) {
      await registro.marcar(coleccion, hasta: null, bajadaAt: ahora);
    }
    await asentar(tester);

    expect(
      find.text('datos de las 8:30'),
      findsOneWidget,
      reason:
          'La bajada entró con la pantalla abierta y el Panel se quedó con la '
          'foto de cuando se pintó.',
    );
    expect(find.text('sin datos todavía'), findsNothing);

    await desmontar(tester);
  });
}
