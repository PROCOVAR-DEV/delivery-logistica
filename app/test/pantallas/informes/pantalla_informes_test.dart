import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/estado_vacio.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/informes/estado/informes_estado.dart';
import 'package:reparto/pantallas/informes/registro.dart';
import 'package:reparto/pantallas/informes/vista/pantalla_informes.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final ahora = DateTime(2026, 9, 14, 10, 0);

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Deja TODAS las colecciones marcadas como bajadas a [cuando]. Hacen falta
  /// todas: la barra se queda con la mas vieja, y una sin bajar es «sin
  /// descargar» aunque las otras ocho esten al dia.
  Future<void> bajadaEntera(DateTime cuando) async {
    for (final coleccion in Colecciones.todas) {
      await base
          .into(base.frescura)
          .insert(
            FrescuraCompanion.insert(
              coleccion: coleccion,
              bajadaAt: Value(cuando),
              hasta: Value(cuando.toIso8601String()),
            ),
          );
    }
  }

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarInformes()],
            inicial: '/reports',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  /// `precio: null` es una orden **sin cotizar**, que es de lo que van las dos
  /// ultimas pruebas de este fichero.
  Future<void> pedido(String id, {double? precio = 10}) => base
      .into(base.orders)
      .insert(
        OrdersCompanion.insert(
          id: id,
          customerName: 'Cliente $id',
          address: 'Calle $id',
          price: Value(precio),
          createdAt: Value(DateTime(2026, 9, 13)),
        ),
      );

  testWidgets('sin nada descargado NO se pinta ninguna tabla de ceros', (
    tester,
  ) async {
    await montar(tester);

    // Una tabla de ceros se leeria como «no hubo ventas», que es lo contrario
    // de lo que pasa.
    expect(find.text(TextosNuevosDeInformes.sinNadaQueCuadrar), findsOneWidget);
    expect(find.byType(PantallaSinDescargar), findsOneWidget);
    expect(find.text('Resumen'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('con datos de hace mas de un dia lo dice: no sirve para cerrar', (
    tester,
  ) async {
    await bajadaEntera(DateTime(2026, 9, 12, 7, 0));
    await pedido('a');
    await montar(tester);

    expect(
      find.textContaining(TextosNuevosDeInformes.noSirveSinEstarAlDia),
      findsOneWidget,
    );
    // Aun asi se puede mirar: se avisa, no se esconde.
    expect(find.text('Resumen'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('al dia, dice de cuando son los datos y de donde salen', (
    tester,
  ) async {
    await bajadaEntera(DateTime(2026, 9, 14, 7, 42));
    await pedido('a');
    await montar(tester);

    expect(
      find.text(TextosNuevosDeInformes.cuadradoConElAparato('14/9/2026, 7:42')),
      findsOneWidget,
    );
    expect(
      find.textContaining(TextosNuevosDeInformes.noSirveSinEstarAlDia),
      findsNothing,
    );

    await desmontar(tester);
  });

  testWidgets('las pestanas y los filtros son los literales del pliego', (
    tester,
  ) async {
    await bajadaEntera(DateTime(2026, 9, 14, 7, 42));
    await pedido('a');
    await montar(tester);

    expect(find.text('Filtros'), findsOneWidget);
    expect(find.text('Desde'), findsOneWidget);
    expect(find.text('Hasta'), findsOneWidget);
    expect(find.text('Todos los vehículos'), findsOneWidget);
    // LAS TRES PESTANAS DEL PLIEGO, Y AQUI SALEN LAS TRES: esto se monta a
    // 1440, o sea un monitor. El carrusel —el rotulo de una y unas bolitas— es
    // del telefono, donde tres etiquetas no caben. Jose, 17/09/2026: «los tabs
    // así como están eran para el móvil, que casi no tiene espacio».
    expect(find.text('Resumen'), findsOneWidget);
    expect(find.text('Por Vehículo'), findsOneWidget);
    expect(find.text('Detalle de Órdenes'), findsOneWidget);
    // Las cuatro tarjetas del resumen, que es la pestana en la que se entra.
    expect(find.text('Total Órdenes'), findsOneWidget);
    expect(find.text('Ingresos Totales'), findsOneWidget);
    expect(find.text('Precio Promedio'), findsOneWidget);
    expect(find.text('Peso Total'), findsOneWidget);
    // `Limpiar` no sale si no hay ningun filtro puesto.
    expect(find.text('Limpiar'), findsNothing);
    // Y se cambia pulsandolas, que es lo que se hace en un monitor.
    for (final siguiente in ['Por Vehículo', 'Detalle de Órdenes']) {
      await tester.tap(find.widgetWithText(OutlinedButton, siguiente));
      await tester.pumpAndSettle();
      // La marcada es la que se acaba de pulsar.
      expect(find.widgetWithText(FilledButton, siguiente), findsOneWidget);
    }

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------
  // HASTA EL PIXEL: que la consulta devuelva `null` no sirve de nada si la
  // vista lo convierte en un `0` con un `?? 0`. Eso dejaria el fallo igual de
  // vivo, solo que una capa mas abajo. Estas dos miran lo que se PINTA.
  // ---------------------------------------------------------------------
  testWidgets('con todo cotizado, Ingresos Totales es una CIFRA', (
    tester,
  ) async {
    await bajadaEntera(DateTime(2026, 9, 14, 7, 42));
    await pedido('a', precio: 30);
    await montar(tester);

    expect(
      find.text('30,00 USD'),
      findsWidgets,
      reason:
          'Con la unica orden cotizada el total se sabe, y un total que se '
          'sabe se pinta como cifra, no como rotulo.',
    );
    expect(find.textContaining('sin cotizar'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('con UNA orden sin cotizar sale un ROTULO, nunca un importe', (
    tester,
  ) async {
    await bajadaEntera(DateTime(2026, 9, 14, 7, 42));
    await pedido('a', precio: 30);
    await pedido('b', precio: null); // sin cotizar
    await montar(tester);

    // El rotulo dice CUANTAS faltan: un guion mudo no se puede arreglar.
    expect(
      find.text('— (1 sin cotizar)'),
      // DOS: `Ingresos Totales` y `Precio Promedio`. Con `findsWidgets` a
      // secas, quitarle la guarda a UNA de las dos seguia saliendo verde.
      findsNWidgets(2),
      reason:
          'Ingresos Totales y Precio Promedio tenian que pintar el rotulo de '
          'total incompleto y no lo hacen: la pantalla se esta inventando una '
          'cifra sobre una suma a la que le falta una orden.',
    );
    // Y el subtexto dice QUE HACER.
    expect(
      find.text('Falta cotizar 1 orden: sin ella no hay total.'),
      findsOneWidget,
    );

    // LO QUE NO PUEDE SALIR NUNCA, y son las dos formas del mismo fallo:
    //  * `30.00 USD` = el total a medias, el de la orden que SI se sabe
    //    puesto donde va el total del dia;
    //  * `0.00 USD` = el `?? 0` de la vista, que es el mismo cero que se vio
    //    en produccion el 22/09/2026 sobre 10,4 km de reparto.
    expect(
      find.text('30,00 USD'),
      findsNothing,
      reason:
          'Salio `30,00 USD` con una orden sin cotizar: es el total de la OTRA '
          'ocupando el sitio del total del dia. Se lee redondo y creible, y '
          'ninguna pantalla lo desmiente.',
    );
    expect(
      find.text('0,00 USD'),
      findsNothing,
      reason:
          'Salio `0,00 USD`: un `?? 0` convirtio el hueco en un cero. Eso no '
          'dice «no hay tarifa», dice que el reparto fue gratis.',
    );

    await desmontar(tester);
  });

  testWidgets('en Detalle de Órdenes la fila sin cotizar lo DICE', (
    tester,
  ) async {
    await bajadaEntera(DateTime(2026, 9, 14, 7, 42));
    await pedido('a', precio: 30);
    await pedido('b', precio: null);
    await montar(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Detalle de Órdenes'));
    await tester.pumpAndSettle();

    // Las MISMAS palabras que `Pedidos` y que la hoja de paradas de la ruta,
    // para que la misma cifra no se llame de dos maneras segun la pantalla.
    expect(
      find.text('sin cotizar'),
      findsOneWidget,
      reason:
          'La columna que alguien copia al Excel y suma fuera no dice que esa '
          'orden no tiene importe.',
    );
    // Y el pie tampoco puede parecer completo.
    expect(find.text('Totales: (1 sin cotizar)'), findsOneWidget);
    expect(
      find.text('0,00 USD'),
      findsNothing,
      reason: 'La fila sin cotizar salio como `0,00 USD` en el detalle.',
    );

    await desmontar(tester);
  });

  testWidgets('sin ordenes salen los tres vacios, cada uno con su texto', (
    tester,
  ) async {
    await bajadaEntera(DateTime(2026, 9, 14, 7, 42));
    await montar(tester);

    expect(
      find.text('No hay órdenes para los filtros seleccionados.'),
      findsOneWidget,
    );

    // A 1440 las tres pestañas están a la vista, así que se pulsa la suya. El
    // carrusel con flechas es del teléfono.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Por Vehículo'));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay datos de vehículos para los filtros seleccionados.'),
      findsOneWidget,
    );

    await desmontar(tester);
  });

  // LAS FECHAS DE INFORMES: SE PONEN, Y SE QUITAN A LA VISTA.
  //
  // Dos cosas cambiaron aqui el 25/09/2026 y ninguna la sujetaba nada:
  //
  // 1. El calendario dejo de ser `showDatePicker` —una ventana modal, prohibida
  //    en esta aplicacion desde el 05/09/2026— y paso al `CampoDeFecha` anclado
  //    de la casa.
  // 2. La fecha ya NO se quita con `onLongPress`. Antes esa era la unica forma,
  //    sin una sola pista en pantalla: en un telefono nadie la descubre, se
  //    pone una fecha por probar y no hay manera de volver a «todas».
  //
  // El auditor comprobo el mismo dia que, poniendo `alElegir: (d) {}` en los
  // cuatro campos de fecha nuevos y quitando las dos ✕, las 1.656 pruebas del
  // proyecto seguian en verde. O sea: el boton se pinta, el calendario se abre,
  // se toca un dia y no pasa nada, y nadie se entera.
  testWidgets('poner una fecha la aplica, y la ✕ la quita', (tester) async {
    await bajadaEntera(ahora);
    await montar(tester);

    expect(
      find.text('Desde'),
      findsOneWidget,
      reason: 'no esta el campo «Desde» de los filtros de informes',
    );

    await tester.tap(find.text('Desde'));
    await tester.pumpAndSettle();

    // El calendario sale ANCLADO, no en una ventana modal.
    expect(
      find.byType(CalendarDatePicker),
      findsOneWidget,
      reason:
          'el calendario no se abrio. Si aparecio un dialogo centrado, es que '
          'volvio `showDatePicker`, que esta prohibido aqui',
    );

    // Se elige el 20 de septiembre de 2026 —el reloj de la prueba es el 14—.
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();

    expect(
      find.text('20/9/2026'),
      findsOneWidget,
      reason:
          'se toco un dia en el calendario y el filtro no se entero: el campo '
          'sigue sin fecha. Es el cableado de `alElegir`.',
    );
    expect(
      find.text('Desde'),
      findsNothing,
      reason: 'el boton sigue diciendo «Desde» con una fecha ya puesta',
    );

    // Y ahora la ✕, que es la que no existia.
    await tester.tap(find.byTooltip('Quitar Desde'));
    await tester.pumpAndSettle();

    expect(
      find.text('Desde'),
      findsOneWidget,
      reason:
          'la ✕ no quito la fecha. Sin ella la unica salida era el '
          '`onLongPress` invisible del que se venia.',
    );
    expect(find.text('20/9/2026'), findsNothing);

    await desmontar(tester);
  });

  // Issue 27: los tres campos nuevos llegan al filtro, y «Limpiar» los vacía.
  testWidgets(
    'escribir factura y ruta las aplica, y Limpiar vacía los campos',
    (tester) async {
      await bajadaEntera(ahora);
      await pedido('a');
      await montar(tester);

      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(PantallaInformes)),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Factura desde'),
        ' 1000 ',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Factura hasta'),
        '1300',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Ruta'), 'stg');
      await tester.pumpAndSettle();

      final f = contenedor.read(filtroDeInformesProvider);
      expect(
        f.facturaDesde,
        '1000',
        reason: 'el campo «Factura desde» no llega al filtro',
      );
      expect(f.facturaHasta, '1300');
      expect(f.ruta, 'stg');

      await tester.tap(find.text('Limpiar'));
      await tester.pumpAndSettle();

      expect(contenedor.read(filtroDeInformesProvider).hayAlgoPuesto, isFalse);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Factura desde'))
            .controller!
            .text,
        isEmpty,
        reason: '«Limpiar» vació el filtro pero el campo sigue con el texto',
      );

      await desmontar(tester);
    },
  );
}
