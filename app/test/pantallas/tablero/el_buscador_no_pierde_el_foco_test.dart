// EL BUSCADOR DEL TABLERO PERDÍA EL FOCO EN CADA LETRA — issue 10 de Amado, punto 2,
// 15/10/2026: «en el filtro del tablero cada vez que se teclea un carácter pierde el foco,
// hay que volver a coger foco por cada carácter».
//
// La causa: `TableroDelDia.build` MIRABA `filtrosTableroProvider`. Cada búsqueda (a los
// 400 ms de la última letra) volvía a ejecutar `build`, el tablero pasaba a «cargando» y
// `pantalla_tablero.dart` pintaba la rueda EN LUGAR del tablero entero: la caja de buscar
// se desmontaba con su foco, y volvía nueva y sin él. Quien teclea despacio —una letra,
// mira, otra letra— lo pagaba en cada letra.
//
// Por eso esta prueba va con la pantalla ENTERA, sus proveedores de verdad y el enrutador
// (el buscador escribe el `?q=` en la dirección), y teclea como se teclea: una letra, la
// pausa del buscador, otra letra. Una prueba con la lista ya filtrada a mano (como la de
// `el_buscador_no_pide_intro_test.dart`) no puede verlo, porque el fallo no estaba en la
// caja sino en lo que se hacía encima de ella al filtrar.
//
// Y con la lectura LENTA a propósito ([_ConsultasLentas]). La base de prueba es en memoria
// y contesta antes del siguiente fotograma: la rueda no llegaba a pintarse y la prueba salía
// verde con el fallo puesto. En el teléfono y en la web la lectura tarda, y ese fotograma
// con la rueda es justo el que se lleva el foco.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reparto/diseno/caja_de_busqueda.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/estado/filtros_en_la_url.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// La lista de «sin colocar» tarda lo que tarda una base de verdad.
class _ConsultasLentas extends ConsultasTablero {
  _ConsultasLentas(super.base);

  @override
  Future<MitadIzquierda> sinColocar(
    String sucursalId,
    AlmacenOrigen origen, {
    FiltrosSinColocar filtros = const FiltrosSinColocar(),
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return super.sinColocar(sucursalId, origen, filtros: filtros);
  }
}

void main() {
  late BaseLocal base;

  // Aquí SÓLO se abre la base: sembrar en el `setUp` de un `testWidgets` cuelga (§5).
  setUp(() => base = BaseLocal.con(NativeDatabase.memory()));
  tearDown(() => base.close());

  Future<void> pasadasCortas(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('se teclea letra a letra y el campo NO pierde el foco', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(
      base,
      id: 'p1',
      cliente: 'Bodega La Esquina',
      operacion: 'PTB25-261005-1479',
      facturaNumero: '47061, 47062',
    );
    await sembrarPedido(
      base,
      id: 'p2',
      cliente: 'Kiosco El Sol',
      operacion: 'PTB25-261005-1480',
      facturaNumero: '50000',
      aGrados: 0.02,
    );

    final contenedor = ProviderContainer(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        consultasTableroProvider.overrideWith(
          (ref) => _ConsultasLentas(ref.watch(baseProvider)),
        ),
        clienteApiProvider.overrideWithValue(
          ClienteApi(
            dio: Dio()
              ..httpClientAdapter = ServidorFalso((peticion) async => null),
            esperas: const <Duration>[],
          ),
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
    );
    addTearDown(contenedor.dispose);
    final enrutador = GoRouter(
      initialLocation: FiltrosEnLaUrl.camino,
      routes: [
        GoRoute(
          path: FiltrosEnLaUrl.camino,
          builder: (contexto, estado) => Scaffold(
            body: PantallaTablero(
              lectura: FiltrosEnLaUrl.leer(estado.uri.queryParameters),
            ),
          ),
        ),
      ],
    );
    addTearDown(enrutador.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: contenedor,
        child: MaterialApp.router(routerConfig: enrutador),
      ),
    );
    await pasadasCortas(tester);
    expect(find.text('Kiosco El Sol'), findsOneWidget);

    final caja = find.descendant(
      of: find.byType(CajaDeBusqueda),
      matching: find.byType(EditableText),
    );
    await tester.showKeyboard(caja);

    var tecleado = '';
    for (final letra in '47062'.split('')) {
      tecleado += letra;
      // Por la conexión del teclado, como un teclado de verdad: si el campo ya no
      // tiene el foco, esta letra no llega a ninguna parte.
      tester.testTextInput.enterText(tecleado);
      // La pausa del buscador, la búsqueda, y que la lista se repinte.
      await tester.pump(CajaDeBusqueda.esperaPorDefecto);
      await pasadasCortas(tester);

      final campo = tester.widget<EditableText>(caja);
      expect(
        campo.focusNode.hasPrimaryFocus,
        isTrue,
        reason:
            'tras teclear «$tecleado» y buscar, el campo perdió el foco '
            '(lo tiene ${FocusManager.instance.primaryFocus}): hay que volver '
            'a pinchar en él por cada letra',
      );
      expect(
        campo.controller.text,
        tecleado,
        reason: 'las letras tienen que irse sumando en el campo',
      );
    }

    // Y la búsqueda hizo su trabajo: «47062» es la segunda factura de la bodega.
    expect(find.text('Bodega La Esquina'), findsOneWidget);
    expect(find.text('Kiosco El Sol'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
