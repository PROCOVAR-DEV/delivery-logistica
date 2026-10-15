// DESDE QUÉ ALMACÉN SE MIDE: LA CABECERA DEL TABLERO SE TOCA Y SE ELIGE.
//
// Jose, 26/09/2026, mirando la cabecera que decía «Camaguey · desde PV
// CAMAGUEY»: «¿aquí me aparecerá lo de escoger los otros almacenes sólo cuando
// tenga más almacenes? Porque hace falta que aparezca por lo menos y diga que no
// está configurado el que no tiene la ubicación puesta».
//
// EL CONTEXTO, que es de ese mismo día y explica por qué esto no existía antes:
// hasta esa tarde cada sucursal tenía UN almacén en Accesos y se llamaba como la
// sucursal. Jose dio de alta los 14 de verdad, leídos de Ventra, y cinco
// sucursales tienen más de uno —Camagüey tiene tres: PV CAMAGUEY, ALM CAMAGUEY y
// FLORIDA—. Cuál se usa deja de ser evidente.
//
// Y SEIS DE LOS CATORCE ESTÁN SIN COORDENADAS A PROPÓSITO: las ponen los
// logísticos de cada sucursal. O sea que «existe pero le falta la ubicación» es
// el estado normal de estos días, no una avería, y es justo lo que hay que
// enseñar.
//
// LAS CUATRO GUARDAS, y van EN PAREJA porque es la regla de la casa: una que
// pase cuando toca y otra que NO pase cuando no toca.
//
//  1. Con **un** almacén la cabecera NO se puede tocar. Un desplegable de un
//     elemento no elige nada: promete algo y abre una lista de uno.
//  2. Con **varios** sí, y en la lista están TODOS — también los que no tienen
//     ubicación. Esconderlos es descartar en silencio (`CLAUDE.md` §4), y quien
//     mira se queda sin saber que su sucursal tiene un almacén a medio dar de
//     alta.
//  3. El que no tiene ubicación sale **marcado y no se puede elegir**, con el
//     motivo en palabras de la casa. Y la otra mitad de la pareja: el que sí la
//     tiene **sí** se puede, y elegirlo cambia de verdad desde dónde se mide.
//  4. La ✕ de cerrar está, a los dos anchos. Regla para todos los proyectos de
//     Procovar, y aquí es lo único que queda para salir cuando el teclado tapa
//     media pantalla.
//
// POR QUÉ LO DE «NO SE PUEDE ELEGIR» NO ES UN DETALLE DE INTERFAZ: de los
// kilómetros desde el almacén sale lo que se le cobra al cliente por el
// domicilio. Medir desde un punto que no existe da un número creíble y
// equivocado, que es el fallo que más caro sale aquí (`CLAUDE.md` §4).
//
// LAS DOS TRAMPAS DE LA CASA, respetadas: la base se ABRE en el `setUp` y se
// ESCRIBE dentro del cuerpo de cada prueba —el `setUp` corre fuera del reloj
// falso y lo que Drift deja empezado allí no avanza dentro—, y no hay ni un
// `await` sobre el primer valor de un stream de Drift: se bombean fotogramas.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/diseno/anchos.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// Los dos anchos que deciden la forma del cajón: por debajo de 1024 px ocupa la
/// pantalla entera, por encima es un panel lateral. **Cajón en los dos** — es la
/// excepción aprobada de este proyecto (05/09/2026, `CLAUDE.md` §4): aquí no hay
/// variante modal, y lo que se conserva de la regla general es que la ✕ no
/// desaparece nunca.
const anchoTelefono = Size(390, 844);
const anchoEscritorio = Size(1400, 900);

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  setUp(() {
    base = baseDePrueba();
    servidor = ServidorFalso((_) async => null);
  });
  tearDown(() => base.close());

  /// `pumpAndSettle` no vale: el tablero pide la foto al abrirse y mientras algo
  /// está en vuelo hay una rueda girando, que es una animación sin fin.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Los almacenes de Camagüey, con los nombres de verdad de Ventra.
  ///
  /// `conUbicacion` es la lista de los que tienen el punto puesto. Los demás se
  /// siembran **sin lat ni lng**, que es como están hoy en Accesos los seis que
  /// esperan a que su logístico les ponga la ubicación.
  Future<void> sembrarAlmacenes(
    List<String> nombres, {
    required Set<String> conUbicacion,
    String principal = 'PV CAMAGUEY',
  }) async {
    for (final nombre in nombres) {
      final tiene = conUbicacion.contains(nombre);
      await base
          .into(base.warehouses)
          .insert(
            WarehousesCompanion.insert(
              id: 'w-$nombre',
              sucursalCodigo: codigoStg,
              nombre: nombre,
              lat: Value(tiene ? almacenLat : null),
              lng: Value(tiene ? almacenLng : null),
              principal: Value(nombre == principal),
            ),
          );
    }
  }

  Future<void> montar(WidgetTester tester, {required Size pantalla}) async {
    tester.view.physicalSize = pantalla;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dio = Dio()..httpClientAdapter = servidor;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWith((ref) => base),
          // SIN ESPERAS: el tablero pide la foto al abrirse y aquí no hay
          // servidor. Con las esperas de verdad la prueba se cuelga en vez de
          // fallar, que es la trampa del `CLAUDE.md` §5.
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
          sucursalDeLaSesionProvider.overrideWithValue(sucursalStg),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
      ),
    );
    await asentar(tester);
  }

  // ---------------------------------------------------------------------------
  // 1 · CON UNO SOLO NO SE OFRECE ELEGIR
  // ---------------------------------------------------------------------------

  testWidgets('con UN almacén la cabecera no se toca', (tester) async {
    await sembrarSucursal(base);
    await sembrarAlmacenes(
      const ['PV CAMAGUEY'],
      conUbicacion: const {'PV CAMAGUEY'},
    );
    await sembrarPedido(base, id: 'p1', operacion: 'SC06-1257');

    await montar(tester, pantalla: anchoEscritorio);

    final cabecera = tester.widget<CabeceraDelTablero>(
      find.byType(CabeceraDelTablero),
    );
    expect(
      cabecera.sePuedeElegir,
      isFalse,
      reason:
          'con un solo almacén la cabecera ofrece elegir, y no hay nada que '
          'elegir: se abriría una lista de un elemento. Tres de las ocho '
          'sucursales están así hoy (Granma, Holguín y Las Tunas)',
    );
    expect(
      find.byIcon(Icons.expand_more),
      findsNothing,
      reason:
          'y no puede salir la flecha: una flecha que no abre nada enseña a '
          'desconfiar de las que sí abren',
    );

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------------
  // 2 y 3 · CON VARIOS, SE ELIGE — Y LOS QUE NO TIENEN UBICACIÓN SALEN IGUAL
  // ---------------------------------------------------------------------------

  for (final pantalla in const [anchoTelefono, anchoEscritorio]) {
    final px = pantalla.width.toInt();
    final enMovil = pantalla.width < Anchos.escritorio;

    testWidgets('a $px px: con TRES almacenes se abre la lista y están los '
        'tres, también los que no tienen ubicación', (tester) async {
      await sembrarSucursal(base);
      // Los tres de Camagüey de verdad. Sólo PV CAMAGUEY tiene el punto puesto.
      await sembrarAlmacenes(
        const ['PV CAMAGUEY', 'ALM CAMAGUEY', 'FLORIDA'],
        conUbicacion: const {'PV CAMAGUEY'},
      );
      await sembrarPedido(base, id: 'p1', operacion: 'SC06-1257');

      await montar(tester, pantalla: pantalla);

      expect(
        tester
            .widget<CabeceraDelTablero>(find.byType(CabeceraDelTablero))
            .sePuedeElegir,
        isTrue,
        reason:
            'con tres almacenes la cabecera TIENE que ofrecer elegir: de ese '
            'punto salen los kilómetros de cada tarjeta y el domicilio que se '
            'cobra con ellos, así que cuál se usa no puede quedar escondido',
      );

      await tester.tap(find.byType(CabeceraDelTablero));
      await asentar(tester);

      // LOS TRES. El que falla aquí es el silencio: los que no tienen ubicación
      // se saltaban y nadie se enteraba de que su sucursal los tiene a medias.
      for (final nombre in const [
        'PV CAMAGUEY',
        'ALM CAMAGUEY',
        'FLORIDA',
      ]) {
        expect(
          find.text(nombre),
          findsWidgets,
          reason:
              'a $px px falta «$nombre» en la lista de almacenes. Los que no '
              'tienen la ubicación puesta NO se esconden: hoy son seis de los '
              'catorce y es un estado normal —la pone el logístico de cada '
              'sucursal—, así que esconderlos deja a quien mira sin saber que '
              'tiene un almacén a medio dar de alta. Nada se descarta en '
              'silencio (`CLAUDE.md` §4)',
        );
      }

      // Y CADA UNO DICE EN QUÉ ESTADO ESTÁ. Dos, porque dos les faltan.
      expect(
        find.text(AlmacenDeLaSucursal.sinUbicacion),
        findsNWidgets(2),
        reason:
            'a $px px los dos almacenes sin punto tienen que decir «'
            '${AlmacenDeLaSucursal.sinUbicacion}», y cada uno en su fila. Un '
            'nombre a secas, o un icono sin palabras, deja a quien mira '
            'preguntándose qué le pasa — y lo que le pasa tiene arreglo',
      );

      // LA ✕, que no puede faltar a ningún ancho.
      expect(
        find.byTooltip('Cerrar'),
        findsWidgets,
        reason:
            'el cajón de «desde qué almacén se mide» no tiene ✕ a $px px. Es '
            'regla para todos los proyectos de Procovar, y en un teléfono con '
            'el teclado fuera es la única salida garantizada. Aquí va en cajón '
            '${enMovil ? 'a pantalla entera' : 'también en escritorio: es la '
                'excepción aprobada el 05/09/2026'}',
      );

      await desmontar(tester);
    });

    testWidgets('a $px px: el que no tiene ubicación NO se puede elegir, y el '
        'que sí SÍ', (tester) async {
      await sembrarSucursal(base);
      // Dos almacenes con coordenadas de verdad y uno sin ellas: así la pareja
      // se comprueba entera en una sola pasada.
      await sembrarAlmacenes(
        const ['PV CAMAGUEY', 'ALM CAMAGUEY', 'FLORIDA'],
        conUbicacion: const {'PV CAMAGUEY', 'FLORIDA'},
      );
      await sembrarPedido(base, id: 'p1', operacion: 'SC06-1257');

      await montar(tester, pantalla: pantalla);
      await tester.tap(find.byType(CabeceraDelTablero));
      await asentar(tester);

      // MITAD 1 · EL QUE NO TIENE UBICACIÓN ESTÁ APAGADO.
      final sinPunto = tester.widget<ListTile>(
        find.byKey(const ValueKey('almacen-w-ALM CAMAGUEY')),
      );
      expect(
        sinPunto.enabled,
        isFalse,
        reason:
            'a $px px «ALM CAMAGUEY» no tiene ubicación y la fila está viva. '
            'Elegirlo mediría desde un punto que no existe, y de esos '
            'kilómetros sale lo que se le cobra al cliente por el domicilio: '
            'saldría un importe creíble y equivocado, que es el fallo más caro '
            'de este proyecto',
      );
      expect(
        sinPunto.onTap,
        isNull,
        reason:
            'y no puede tener gesto: una fila que se ve apagada y responde al '
            'dedo es peor que una que no se ve apagada, porque entonces nadie '
            'se cree lo apagado',
      );

      // Y pulsarla no cambia nada: la cabecera sigue midiendo desde el mismo.
      await tester.tap(
        find.byKey(const ValueKey('almacen-w-ALM CAMAGUEY')),
        warnIfMissed: false,
      );
      await asentar(tester);
      expect(
        find.byTooltip('Cerrar'),
        findsWidgets,
        reason:
            'pulsar un almacén sin ubicación ha cerrado el cajón, así que por '
            'fuera se lee como si se hubiera elegido',
      );

      // MITAD 2 · EL QUE SÍ LA TIENE SE ELIGE, Y SE MIDE DESDE ÉL.
      //
      // Sin esta mitad, «no se puede elegir» se cumpliría apagándolos todos.
      await tester.tap(find.text('FLORIDA'));
      await asentar(tester);

      expect(
        find.byTooltip('Cerrar'),
        findsNothing,
        reason: 'al elegir uno que sirve, el cajón se cierra',
      );
      expect(
        find.textContaining('desde FLORIDA'),
        findsWidgets,
        reason:
            'a $px px se eligió «FLORIDA» y la cabecera sigue diciendo otra '
            'cosa. La elección no es un adorno de la cabecera: es DESDE DÓNDE '
            'SE MIDE, así que si la cabecera no cambia, o no se guardó o el '
            'tablero no volvió a leerse — y en el segundo caso los kilómetros '
            'de las tarjetas siguen siendo los del almacén anterior mientras '
            'la pantalla dice el nuevo, que es lo peor de los dos mundos',
      );

      await desmontar(tester);
    });
  }
}
