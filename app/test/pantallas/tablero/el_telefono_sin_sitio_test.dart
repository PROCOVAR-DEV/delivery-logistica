import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// EL TELÉFONO SE QUEDA SIN SITIO Y EL GESTO NO SE GUARDA.
///
/// El aparato de un repartidor lleva el día dentro y un paquete de mapa de 100
/// MB al lado; que se llene a media mañana no es el caso raro. Cuando SQLite no
/// puede escribir contesta siempre lo mismo —`SqliteException(13): database or
/// disk is full`, o el `(8) attempt to write a readonly database` de una copia
/// que se quedó sin permisos— y eso sale **de la base, no del servidor**.
///
/// Aquí no hay rechazo de nadie: hay un gesto que no se guardó. Y hasta hoy el
/// tablero sólo sabía contar los rechazos:
///
///  * `AccionesTablero._hacer` atrapaba `on RechazoDelTablero` y nada más, así
///    que un `SqliteException` se le escapaba: ni cartel, ni una palabra. Se
///    toca «Colocar en «Centro»», la tarjeta se queda donde estaba y **no se
///    dice nada**.
///  * El arrastre era peor: `unawaited(...colocar(...))` sin ningún `try`, o
///    sea un error asíncrono sin dueño que en la APK no acaba en ningún sitio
///    (`nucleo/red/eventos_io.dart` lo dice de otro caso igual).
///
/// Es el §4 entero: «si algo falla, la pantalla **no se queda verde**». Un
/// gesto que se cree hecho y no está en ninguna parte es lo que este proyecto
/// no puede permitirse, porque el repartidor sigue la jornada creyendo que la
/// zona quedó armada.
///
/// El fallo se inyecta en el repositorio y no llenando un disco de verdad: lo
/// que hay que comprobar es **qué hace la pantalla con un error que no es un
/// rechazo**, y un disco lleno de verdad rompe además la apertura de la base,
/// que es otro caso y no éste.
void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  setUp(() async {
    base = baseDePrueba();
    servidor = ServidorFalso((peticion) async => null);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
  });

  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget montar({bool sinSitio = false}) {
    final dio = Dio()..httpClientAdapter = servidor;
    return ProviderScope(
      overrides: [
        baseProvider.overrideWith((ref) => base),
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
        if (sinSitio)
          repositorioTableroProvider.overrideWith(
            (ref) => _SinSitioEnElDisco(base, ColaDeSalida(base)),
          ),
      ],
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  /// La mañana normal: una zona y un pedido sin colocar.
  Future<void> laMananaNormal() async {
    await RepositorioTablero(
      base,
      ColaDeSalida(base),
    ).crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
    await sembrarPedido(base, id: 'cerca', operacion: 'SC06-1257');
  }

  testWidgets('el teléfono sin sitio: el gesto no se guarda y SE DICE, con el '
      'motivo y con qué hacer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await laMananaNormal();
    await tester.pumpWidget(montar(sinSitio: true));
    await asentar(tester);
    expect(find.text('SC06-1257'), findsOneWidget, reason: 'el pedido está');

    // EL GESTO: tocar la tarjeta y elegir la zona. Es el camino que usa quien
    // lleva un teléfono en la mano.
    await tester.tap(find.text('SC06-1257'));
    await asentar(tester);
    await tester.tap(find.text('Colocar en «Centro»'));
    await asentar(tester);

    // 1 · NO SE GUARDÓ. Eso es cierto y no se arregla desde aquí.
    expect(
      (await ColaDeSalida(base).lote())
          .where((a) => a.ruta.startsWith('/board/placements/')),
      isEmpty,
      reason: 'sin sitio en el disco no hay apunte que valga',
    );
    expect(find.text('Centro (0)'), findsOneWidget);

    // 2 · PERO SE DICE. Ésta es la parte que faltaba: sin ella el repartidor
    // sigue su jornada creyendo que la zona quedó armada.
    expect(
      find.byType(SnackBar),
      findsOneWidget,
      reason:
          'un gesto que no se guardó y no dice nada es trabajo perdido en '
          'silencio, que es el §4 de la casa',
    );
    expect(
      find.textContaining('No se pudo guardar en este aparato'),
      findsOneWidget,
    );
    expect(
      find.textContaining('espacio'),
      findsOneWidget,
      reason:
          'y se dice QUÉ HACER. «Ha ocurrido un error» no le sirve a nadie en '
          'el patio de un almacén',
    );

    await desmontar(tester);
  });

  testWidgets('con sitio de sobra el gesto se guarda y NO sale ningún cartel', (
    tester,
  ) async {
    // La pareja del §3-quinquies: un aviso que sale siempre deja de leerse, y
    // entonces tampoco se lee el día que importa.
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await laMananaNormal();
    await tester.pumpWidget(montar());
    await asentar(tester);
    await tester.tap(find.text('SC06-1257'));
    await asentar(tester);
    await tester.tap(find.text('Colocar en «Centro»'));
    await asentar(tester);

    expect(find.text('Centro (1)'), findsOneWidget);
    expect(
      (await ColaDeSalida(base).lote()).last.ruta,
      '/board/placements/cerca',
    );
    expect(find.byType(SnackBar), findsNothing);

    await desmontar(tester);
  });
}

/// El repositorio de un teléfono al que no le cabe un byte más.
///
/// Lee igual que siempre —el tablero se pinta— y **al escribir revienta con lo
/// que reviente SQLite de verdad**. Eso es lo que distingue este caso de un
/// rechazo del servidor: no hay motivo que enseñar, hay un aparato que no puede
/// guardar.
class _SinSitioEnElDisco extends RepositorioTablero {
  _SinSitioEnElDisco(super.base, super.cola);

  static Never _lleno() => throw SqliteException(
    13,
    'database or disk is full',
    'database or disk is full',
  );

  @override
  Future<void> colocar({
    required String pedidoId,
    required String columnaId,
    int? posicion,
  }) async => _lleno();

  @override
  Future<void> quitar(String pedidoId) async => _lleno();
}
