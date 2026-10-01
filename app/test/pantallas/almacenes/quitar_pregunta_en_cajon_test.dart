import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/cajon.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/almacenes/datos/geocodificar.dart';
import 'package:reparto/pantallas/almacenes/vista/pantalla_almacenes.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo_almacenes.dart';

/// QUITAR UN ALMACEN PREGUNTA **EN UN CAJON**, y lo que se contesta manda.
///
/// Preguntar ya lo hacía; lo hacía con un `AlertDialog` centrado, que es la
/// regla que rompe (`CLAUDE.md` §4: **cajón siempre, también en escritorio**,
/// excepción aprobada el 05/09/2026). Las tres cosas que esto no deja pasar:
///
///  1. que el «Quitar» vuelva a ser un modal centrado en vez de la pieza de la
///     casa, [preguntarAntesDeBorrar];
///  2. que la pregunta no diga **qué se pierde** — desde el almacén se mide lo
///     que se le cobra por el domicilio, y la lista que se guarda es la de la
///     sucursal ENTERA sin él: no se recupera dando atrás;
///  3. **y la que de verdad cuesta dinero: que contestar «No» o cerrar sin
///     contestar borre igual.** Las dos tienen que dejar el almacén donde
///     estaba, y eso se mide en el único sitio donde se nota: que NO salga el
///     `PUT /almacenes` con la lista sin él.
///
/// Se prueba desde la pantalla y no con el editor suelto a propósito: el camino
/// completo —tocar «Quitar», contestar, y que la lista salga o no salga hacia
/// Accesos— es el que tenía el fallo. El geocodificador y el fondo del mapa
/// entran falsos, que es regla de la casa en este PC: **no sale ni una
/// petición** a Nominatim ni a las teselas.
void main() {
  /// Una sucursal con dos almacenes. Dos y no uno porque el de abajo tiene que
  /// seguir estando cuando se conteste «No», y con uno solo no se distingue
  /// «no se borró» de «la lista no se repintó».
  Banco bancoConDosAlmacenes() => Banco((p) async {
    if (p.metodo == 'PUT') {
      return RespuestaFalsa(200, const <String, Object?>{
        'almacenes': <Object?>[],
      });
    }
    return RespuestaFalsa(200, const <String, Object?>{
      'sucursales': [
        {
          'codigo': 'STG',
          'nombre': 'Santiago',
          'almacenes': [
            {
              'id': 'w1',
              'nombre': 'Almacén central',
              'latitud': 20.0247,
              'longitud': -75.8219,
              'principal': true,
            },
            {
              'id': 'w2',
              'nombre': 'Patio sur',
              'latitud': 20.03,
              'longitud': -75.83,
            },
          ],
        },
      ],
    });
  });

  /// El mismo asentado que el resto de las pruebas de esta pantalla: hay
  /// `Stream` de Drift por debajo (la franja de la última bajada).
  Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  Future<void> pintar(WidgetTester tester, Banco banco) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(banco.base),
          clienteApiProvider.overrideWithValue(
            banco.contenedor.read(clienteApiProvider),
          ),
          // NI UNA PETICION FUERA. Sin estos dos, abrir el editor pide teselas
          // a OSM y direcciones a Nominatim desde este PC.
          geocodificadorProvider.overrideWithValue(const SinGeocodificar()),
          fondoDeCallesProvider.overrideWithValue(const SinCalles()),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaAlmacenes())),
      ),
    );
    await asentar(tester);
  }

  /// Los `Stream` de Drift dejan un temporizador de cero al cerrarse: se
  /// desmonta dentro de la prueba para que se apague aquí y no después.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Abre el editor del «Almacén central» y toca su «Quitar».
  Future<void> tocarQuitar(WidgetTester tester) async {
    await tester.tap(find.text('Almacén central'));
    await asentar(tester);
    await tester.tap(find.byTooltip('Quitar'));
    await asentar(tester);
  }

  testWidgets('tocar «Quitar» NO quita: pregunta EN UN CAJON, nombra el '
      'almacén y dice qué se pierde', (tester) async {
    final banco = bancoConDosAlmacenes();
    addTearDown(banco.cerrar);
    await pintar(tester, banco);
    await tocarQuitar(tester);

    expect(
      banco.servidor.cuantas('PUT', '/almacenes'),
      0,
      reason: 'un almacén no se va de un toque',
    );

    // 1. ES UN CAJON Y NO UN MODAL CENTRADO. Dos cajones: el editor y la
    // pregunta encima.
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason:
          'cajón siempre, también en escritorio (§4): un `AlertDialog` '
          'centrado no es lo que usa el resto de la aplicación y en un '
          'teléfono se comporta distinto',
    );
    expect(find.byType(Cajon), findsNWidgets(2));

    // 2. Y LA ✕ DEL CAJON DE LA PREGUNTA ESTA. Regla de todos los proyectos de
    // Procovar: nunca puede desaparecer.
    expect(find.byTooltip('Cerrar'), findsNWidgets(2));

    // 3. EL BOTON NOMBRA LO QUE SE VA. «Aceptar» no dice nada.
    expect(find.text('Borrar «Almacén central»'), findsOneWidget);
    expect(find.text('Sí, borrar «Almacén central»'), findsOneWidget);
    expect(find.text('No, dejarlo'), findsOneWidget);

    // 4. Y DICE QUE SE PIERDE DE VERDAD, que es la mitad que sirve: la lista de
    // la sucursal se guarda sin él, se deja de medir desde ahí, y los aparatos
    // que ya lo bajaron siguen cobrando desde él.
    expect(find.textContaining('se guarda la lista de Santiago sin él'),
        findsOneWidget);
    expect(find.textContaining('Deja de poder medirse desde ahí'),
        findsOneWidget);
    expect(
      find.textContaining('no se ve hasta cuadrar la caja'),
      findsOneWidget,
      reason:
          'lo caro de quitar un almacén es que el domicilio se siga cobrando '
          'desde un punto que ya no está, y eso no se nota hasta la caja',
    );

    await desmontar(tester);
  });

  testWidgets('«No, dejarlo» deja el almacén donde estaba: NI UN PUT', (
    tester,
  ) async {
    final banco = bancoConDosAlmacenes();
    addTearDown(banco.cerrar);
    await pintar(tester, banco);
    await tocarQuitar(tester);

    await tester.tap(find.text('No, dejarlo'));
    await asentar(tester);

    expect(
      banco.servidor.cuantas('PUT', '/almacenes'),
      0,
      reason:
          'contestar «No» tiene que dejar el almacén donde estaba: el guardado '
          'manda la lista de la sucursal SIN él, y eso no se deshace',
    );
    // La pregunta se fue y el editor sigue abierto, no cerrado a medias.
    expect(find.text('Sí, borrar «Almacén central»'), findsNothing);
    expect(find.text('Guardar'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('cerrar la pregunta con la ✕ es NO, no un sí por descuido', (
    tester,
  ) async {
    // `abrirCajon` devuelve `null` al cerrar sin contestar, y `null` tiene que
    // ser NO. Si fuera «sí», el almacén se iría por cerrar un cajón: peor que
    // no haber preguntado.
    final banco = bancoConDosAlmacenes();
    addTearDown(banco.cerrar);
    await pintar(tester, banco);
    await tocarQuitar(tester);

    // La ✕ de la pregunta, que es la de arriba: la otra es la del editor.
    await tester.tap(find.byTooltip('Cerrar').last);
    await asentar(tester);

    expect(
      banco.servidor.cuantas('PUT', '/almacenes'),
      0,
      reason: 'cerrar sin contestar no puede quitar nada',
    );
    expect(find.text('Sí, borrar «Almacén central»'), findsNothing);
    // Y el almacén sigue en la lista de la pantalla.
    expect(find.text('Guardar'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('tocar fuera del cajón tampoco quita', (tester) async {
    final banco = bancoConDosAlmacenes();
    addTearDown(banco.cerrar);
    await pintar(tester, banco);
    await tocarQuitar(tester);

    // El velo, a la izquierda del panel. Es la otra forma de «cerrar sin
    // contestar» y tiene que valer lo mismo que la ✕.
    await tester.tapAt(const Offset(8, 8));
    await asentar(tester);

    expect(
      banco.servidor.cuantas('PUT', '/almacenes'),
      0,
      reason: 'tocar fuera es cerrar sin contestar, y eso es NO',
    );
    expect(find.text('Sí, borrar «Almacén central»'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('y al contestar «Sí» sale la lista de la sucursal SIN ése', (
    tester,
  ) async {
    final banco = bancoConDosAlmacenes();
    addTearDown(banco.cerrar);
    await pintar(tester, banco);
    await tocarQuitar(tester);

    await tester.tap(find.text('Sí, borrar «Almacén central»'));
    await asentar(tester);

    expect(
      banco.servidor.cuantas('PUT', '/almacenes'),
      1,
      reason: 'contestar «Sí» quita, y una sola vez',
    );
    // QUITAR ES GUARDAR LA LISTA SIN ESE, no un borrado suelto: lo que sale
    // tiene que llevar el OTRO almacén dentro, o quitar uno se lleva los dos.
    final mandada = banco.servidor.vistas.lastWhere((p) => p.metodo == 'PUT');
    final cuerpo = mandada.cuerpo! as Map<String, Object?>;
    expect(cuerpo['codigo'], 'STG');
    final lista = (cuerpo['almacenes']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      [for (final a in lista) a['nombre']],
      ['Patio sur'],
      reason:
          'se manda la lista completa de la sucursal menos el quitado: si se '
          'mandara vacía, quitar uno borraría todos los de Santiago',
    );

    await desmontar(tester);
  });
}
