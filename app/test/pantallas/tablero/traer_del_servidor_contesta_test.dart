// «TRAER LO DEL SERVIDOR» SIN SEÑAL NO DECÍA NADA — 28/09/2026.
//
// Jose, en el teléfono y sin conexión, pulsando el botón de la barra del
// Tablero: «ni error, ni aviso, ni nada. Los datos se quedan como estaban y
// quien lo pulsó no tiene forma de saber si pasó algo». Y se vuelve a pulsar,
// porque no hay nada que diga lo contrario.
//
// Estaba escrito a propósito —«sin señal no hay nada que avisar»—, y era verdad
// a medias: lo que no hay que avisar es el ciclo que corre solo cada dos
// minutos. Un gesto es otra cosa, porque hay alguien esperando. §4 de la casa:
// si algo falla, la pantalla no se queda verde.
//
// # LAS PRUEBAS VAN EN PAREJA, como manda el §3-quinquies
//
// «Un aviso que sale siempre deja de leerse, y entonces tampoco se lee el día
// que importa.» Así que aquí hay las dos mitades:
//
//  * que el aviso SALGA, con su motivo literal, cuando el gesto no trajo nada
//    —sin señal, y también cuando la aplicación se niega para no pisar lo que
//    aún no ha subido—;
//  * y que NO salga cuando no toca: ni al abrir la pantalla sin señal (eso es
//    el ciclo, no un gesto), ni cuando la bajada sí funcionó.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  late BaseLocal base;

  // Sólo se abre la base: sembrar en el `setUp` de un `testWidgets` cuelga la
  // prueba en vez de fallarla (§5).
  setUp(() => base = BaseLocal.con(NativeDatabase.memory()));

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

  /// El servidor que contesta bien: el tablero baja vacío y sin quejarse.
  Future<RespuestaFalsa?> contesta(PeticionVista _) async =>
      RespuestaFalsa(200, const <String, Object?>{
        'columnas': <Object?>[],
        'colocados': <Object?>[],
      });

  /// Y el que no contesta: es lo que ve el teléfono de Jose sin señal.
  Future<RespuestaFalsa?> sinSenal(PeticionVista _) async => null;

  Widget montar(ServidorFalso servidor) {
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
      ],
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  /// Pulsa el botón y espera al aviso **con tope**.
  ///
  /// Nada de `pumpAndSettle` aquí: un `SnackBar` vive con un temporizador, así
  /// que asentar del todo lo que hace es esperar a que se vaya y mirar un sitio
  /// vacío. Y la rueda del botón gira sola mientras trae. Se pumpa a pasos
  /// cortos y contados: si no sale, la prueba FALLA en medio segundo, no se
  /// cuelga (§5).
  Future<void> pulsarYEsperar(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Traer lo del servidor'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(SnackBar).evaluate().isNotEmpty) return;
    }
  }

  Future<void> abrir(WidgetTester tester, ServidorFalso servidor) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await tester.pumpWidget(montar(servidor));
    await asentar(tester);
  }

  testWidgets('sin señal lo dice, y dice que se sigue con lo de aquí', (
    tester,
  ) async {
    final servidor = ServidorFalso(sinSenal);
    await abrir(tester, servidor);

    // LA MITAD QUE **NO** SALTA: la bajada de al abrir también falló —el mismo
    // servidor mudo— y de eso no se avisa. Nadie la pidió.
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason:
          'el ciclo que corre solo no avisa: un aviso que sale siempre deja de '
          'leerse (§3-quinquies)',
    );

    await pulsarYEsperar(tester);

    expect(
      find.textContaining('No se trajo nada'),
      findsOneWidget,
      reason: 'pulsar y que no pase nada es el fallo que se está arreglando',
    );
    expect(
      find.textContaining('no hay conexión con el servidor'),
      findsOneWidget,
      reason: 'con el motivo: «no se pudo» no le dice a nadie qué hacer',
    );
    expect(
      find.textContaining('lo que hay en este aparato'),
      findsOneWidget,
      reason: 'y qué pasa mientras: los datos de la pantalla no son de ahora',
    );

    await desmontar(tester);
  });

  testWidgets('negarse para no pisar lo que falta por subir también se dice', (
    tester,
  ) async {
    // La protección que no se negocia: la foto del servidor no puede borrar lo
    // que se hizo sin señal. Eso ya salía en la franja de arriba; lo que
    // faltaba es que contestara al dedo que acaba de pulsar.
    final servidor = ServidorFalso(contesta);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await RepositorioTablero(
      base,
      ColaDeSalida(base),
    ).crearColumna(sucursalId: sucursalStg, nombre: 'Centro');

    await tester.pumpWidget(montar(servidor));
    await asentar(tester);

    await pulsarYEsperar(tester);

    expect(find.textContaining('No se trajo nada'), findsOneWidget);
    // El texto EXACTO del aviso, no un `textContaining`: la franja de arriba
    // dice también «hay 1 cambio sin subir», así que un contiene se pone verde
    // con la franja sola y la reparación entera se cuela sin hacerse.
    expect(
      find.text('No se trajo nada: hay 1 cambio sin subir.'),
      findsOneWidget,
      reason: 'el motivo literal, que es el que dice qué hacer: subir primero',
    );

    await desmontar(tester);
  });

  testWidgets('cuando sí se trae NO sale el aviso de fallo', (tester) async {
    // La otra mitad de la pareja. Sin esto, la manera fácil de pasar las dos
    // primeras es avisar siempre, y entonces el aviso no lo lee nadie el día
    // que importa.
    final servidor = ServidorFalso(contesta);
    await abrir(tester, servidor);

    await pulsarYEsperar(tester);

    expect(
      find.textContaining('No se trajo nada'),
      findsNothing,
      reason: 'no se puede gritar «no se trajo nada» sobre una bajada que fue',
    );
    expect(
      find.text('Tablero al día con el servidor.'),
      findsOneWidget,
      reason:
          'y algo tiene que decir: un botón mudo que funciona se lee igual que '
          'uno roto, que es de donde viene todo esto',
    );

    await desmontar(tester);
  });
}
