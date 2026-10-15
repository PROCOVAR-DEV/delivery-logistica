// EL DESLIZAMIENTO NO SE PUEDE COMER EL ARRASTRE, NI AL REVÉS.
//
// Es lo delicado de todo esto. El arrastre se acababa de arreglar el 17/09/2026
// —con ratón o lápiz se tira del tirón, con el dedo hace falta pulsación larga,
// y lo decide `ArrastrableSegunPuntero` por el `PointerDeviceKind`—, y meter un
// deslizamiento horizontal por debajo es justo la manera de cambiar un fallo por
// otro: el `PageView` y el arrastre piden el mismo dedo yendo en la misma
// dirección.
//
// No se pisan porque son dos gestos DISTINTOS y la arena de Flutter los
// desempata sola:
//
//  * si el dedo se queda quieto los 200 ms de `retardoDelDedo`, gana el
//    arrastre y el `PageView` ni se entera;
//  * si el dedo se mueve antes, gana el deslizamiento y no se levanta nada.
//
// Y ese equilibrio se apoya en una sola cosa: que `punterosQueArrastranDelTiron`
// NO lleve `touch`. El día que alguien lo meta, el dedo arrastraría del tirón,
// ganaría la arena antes de que el `PageView` se mueva, y no se podría cambiar
// de zona deslizando. Por eso las dos mitades van en el mismo fichero: por
// separado, cada una se cumpliría rompiendo la otra.
//
// Se prueba sobre la CABECERA DE UNA COLUMNA y no sobre una tarjeta a propósito:
// en el móvil las tarjetas no se arrastran (`sin_arrastre_en_movil_test.dart`),
// y la cabecera sí — es la única cosa arrastrable que de verdad vive dentro del
// `PageView`.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/diseno/pestanas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/vista/columna.dart';
import 'package:reparto/pantallas/tablero/vista/kit.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  setUp(() async {
    base = BaseLocal.con(_enMemoria());
    servidor = ServidorFalso((peticion) async => null);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
  });

  tearDown(() => base.close());

  /// Para la carga: el tablero pide su foto y hay que dejarle terminar, o no
  /// hay ni `PageView` sobre el que deslizar.
  Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  /// Para DESPUÉS de un gesto: fotogramas contados, no `pumpAndSettle`.
  ///
  /// Un arrastre vivo tiene algo pegado al dedo repintándose en cada fotograma,
  /// así que esperar a que todo se pare no termina nunca y la prueba muere por
  /// tiempo sin contar nada. Un segundo de fotogramas es lo que ve una persona.
  Future<void> fotogramas(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget montar() {
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
      ],
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  /// Un teléfono, y puestos en la primera zona: es donde conviven el
  /// deslizamiento y el arrastre de la cabecera.
  Future<void> enLaPrimeraZona(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // SE SIEMBRA AQUÍ, DENTRO DE LA PRUEBA, y no en el `setUp`. Sembrado fuera,
    // el tablero se quedaba en el `CircularProgressIndicator` para siempre y
    // `pumpAndSettle` moría por tiempo sin decir nada: la escritura en Drift se
    // queda a medias fuera del reloj falso del test. El mismo molde que usa
    // `pantalla_test.dart`.
    final repo = RepositorioTablero(base, ColaDeSalida(base));
    await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
    await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Vedado');
    await sembrarPedido(base, id: 'p1', operacion: 'SC06-1257');
    await tester.pumpWidget(montar());
    await asentar(tester);
    // Con la flecha, no deslizando: llegar a la zona es cosa de
    // `deslizar_entre_pestanas_test.dart`; lo que se mide aquí es lo que pasa
    // una vez dentro.
    await tester.tap(find.byKey(ClavesDePestanas.adelante));
    await fotogramas(tester);
    expect(find.text('Centro (0)'), findsOneWidget);
  }

  testWidgets('con el dedo, la PULSACIÓN LARGA sigue levantando la cabecera', (
    tester,
  ) async {
    await enLaPrimeraZona(tester);

    final gesto = await tester.startGesture(
      tester.getCenter(find.text('Centro (0)')),
      kind: PointerDeviceKind.touch,
    );
    // Quieto los 200 ms de `retardoDelDedo`, que es lo que significa
    // «agarrar»: ahí el arrastre gana la arena y el `PageView` se retira.
    await tester.pump(retardoDelDedo + const Duration(milliseconds: 50));
    await gesto.moveBy(const Offset(0, -40));
    await tester.pump();

    // El feedback del arrastre es otra cabecera igual pegada al dedo: si hay
    // dos, la columna está levantada.
    expect(
      find.text('Centro (0)'),
      findsNWidgets(2),
      reason:
          'mantener pulsado y mover tiene que seguir levantando la columna: '
          'si el deslizamiento se comiera el gesto, no habría feedback',
    );
    expect(
      find.text('Vedado (0)'),
      findsNothing,
      reason: 'y desde luego no se cambia de zona mientras se arrastra',
    );

    await gesto.up();
    await fotogramas(tester);

    await desmontar(tester);
  });

  testWidgets(
    'y un deslizamiento RÁPIDO sobre esa misma cabecera cambia de zona',
    (tester) async {
      await enLaPrimeraZona(tester);

      // Sin esperar: el dedo se mueve enseguida, así que el que gana es el
      // deslizamiento. Es el otro lado de la misma moneda — si un día el dedo
      // arrastrara del tirón, esto se quedaría clavado en `Centro`.
      await tester.fling(find.text('Centro (0)'), const Offset(-250, 0), 1000);
      await fotogramas(tester);

      expect(
        find.text('Vedado (0)'),
        findsOneWidget,
        reason:
            'empezar el deslizamiento encima de algo arrastrable no puede '
            'dejarte encerrado en la zona',
      );
      expect(find.byType(ColumnaDelTablero), findsOneWidget);

      await desmontar(tester);
    },
  );
}

QueryExecutor _enMemoria() => NativeDatabase.memory();
