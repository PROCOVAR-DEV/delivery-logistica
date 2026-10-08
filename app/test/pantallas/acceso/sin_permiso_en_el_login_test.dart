// EL LOGIN DE LA APK / EL ESCRITORIO CON UNA CUENTA SIN PERMISO DE REPARTO.
//
// Accesos contesta a `POST /api/auth/token` con
// `403 {"error":"sin_permiso","codigo":"sin_permiso","message":"No tienes permiso para
// entrar a Reparto."}` cuando la cuenta no tiene `delivery.entrar`. Antes salía por el
// 403 genérico: «el servidor no dejó pasar la petición, avisa a la oficina», que manda a
// preguntar por algo que no es un fallo.
//
// Ahora: el mismo mensaje y la misma salida que la pantalla «sin permiso» (texto de
// «Reparto es para el personal de logística…» y «Ir a Accesos» al inicio de Accesos), y
// **no se deja nada**: ni sesión guardada, ni portero movido, ni la cola de nadie tocada.
//
// Como `sin_sucursal` (mismo patrón: un `MotivoDeAcceso` propio, aviso ámbar), en pareja
// con él y con los demás 403: ninguno de ellos ofrece «Ir a Accesos».

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/aviso_de_version_nueva.dart'
    show abridorDeLaDescargaProvider;
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/acceso/datos/servicio_acceso.dart';
import 'package:reparto/pantallas/acceso/vista/pantalla_acceso.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

const _sinPermisoDeAccesos = <String, Object?>{
  'error': 'sin_permiso',
  'codigo': 'sin_permiso',
  'message': 'No tienes permiso para entrar a Reparto.',
};

void main() {
  late AlmacenEnMemoria almacen;
  late List<String> abiertos;

  setUp(() {
    almacen = AlmacenEnMemoria();
    abiertos = <String>[];
  });

  /// La puerta de la APK con dos cierres sin subir en la cola.
  Future<(ProviderContainer, ColaDeSalida)> montar(
    WidgetTester tester,
    Future<RespuestaFalsa?> Function(PeticionVista) auth,
  ) async {
    final base = baseDePrueba();
    addTearDown(base.close);
    await aparatoYaConfigurado(base);
    // Sembrado DENTRO del cuerpo (CLAUDE.md §5).
    final cola = ColaDeSalida(
      base,
      reloj: RelojFalso(DateTime(2026, 10, 8, 9)).leer,
    );
    for (var i = 0; i < 2; i++) {
      await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r-$i',
        cuerpo: <String, Object?>{'status': 'completed'},
      );
    }

    final contenedor = ProviderContainer(
      overrides: [
        baseProvider.overrideWithValue(base),
        almacenSesionProvider.overrideWithValue(almacen),
        dioAuthProvider.overrideWithValue(dioFalso(auth)),
        abridorDeLaDescargaProvider.overrideWithValue(
          (enlace) async => abiertos.add(enlace),
        ),
      ],
    );
    addTearDown(contenedor.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: contenedor,
        child: const MaterialApp(home: Scaffold(body: PantallaAcceso())),
      ),
    );
    return (contenedor, cola);
  }

  Future<void> escribirYEntrar(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).first, 'yasmani');
    await tester.enterText(find.byType(TextFormField).last, 'la-buena');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
  }

  Future<void> colaIntacta(ColaDeSalida cola) async {
    final lote = await cola.lote();
    expect(lote.map((a) => a.ruta), ['/routes/r-0', '/routes/r-1']);
  }

  testWidgets('403 sin_permiso: el mensaje, el qué hacer y «Ir a Accesos»; no '
      'se guarda sesión, el portero no se mueve y la cola sigue entera', (
    tester,
  ) async {
    final (contenedor, cola) = await montar(
      tester,
      (p) async => RespuestaFalsa(403, _sinPermisoDeAccesos),
    );
    final portero = contenedor.read(porteroProvider);
    final estadoAntes = portero.estado;

    await escribirYEntrar(tester);

    expect(
      find.text('No tienes permiso para entrar a Reparto.'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Reparto es para el personal de logística y la administración. '
        'Si crees que es un error, pídele acceso a un administrador.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ir a Accesos'), findsOneWidget);
    expect(
      find.textContaining('avisa a la oficina'),
      findsNothing,
      reason: 'ya no sale como un 403 genérico',
    );

    // NADA A MEDIAS.
    expect(await almacen.leer(), isNull, reason: 'ninguna sesión guardada');
    expect(portero.estado, estadoAntes, reason: 'el portero no se movió');
    expect(portero.estado, isNot(EstadoDeAcceso.dentro));
    await colaIntacta(cola);
    expect(await contenedor.read(baseProvider).cuantosPendientes(), 2);

    // Y la salida: el inicio de Accesos, en el navegador del sistema.
    await tester.tap(find.text('Ir a Accesos'));
    await tester.pump();
    expect(abiertos, ['https://auth.procovar.cloud/']);
    // El formulario se queda: se puede probar con otra cuenta.
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('la marca vale venga en `error` o en `codigo`', (tester) async {
    for (final cuerpo in <Map<String, Object?>>[
      {
        'error': 'sin_permiso',
        'message': 'No tienes permiso para entrar a Reparto.',
      },
      {
        'codigo': 'sin_permiso',
        'message': 'No tienes permiso para entrar a Reparto.',
      },
    ]) {
      await montar(tester, (p) async => RespuestaFalsa(403, cuerpo));
      await escribirYEntrar(tester);
      expect(find.text('Ir a Accesos'), findsOneWidget, reason: '$cuerpo');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  group('PAREJA — los demás fallos de la puerta NO ofrecen «Ir a Accesos»', () {
    testWidgets('403 sin_sucursal sigue con su explicación', (tester) async {
      final (_, cola) = await montar(
        tester,
        (p) async => RespuestaFalsa(403, <String, Object?>{
          'error': 'sin_sucursal',
          'message':
              'La cuenta no está dada de alta en ninguna sucursal, o la '
              'sucursal pedida no es suya.',
        }),
      );

      await escribirYEntrar(tester);

      expect(
        find.textContaining('no está dada de alta en ninguna sucursal'),
        findsOneWidget,
      );
      expect(find.text('Ir a Accesos'), findsNothing);
      expect(find.textContaining('personal de logística'), findsNothing);
      await colaIntacta(cola);
    });

    testWidgets('403 revoked (cuenta de baja) sigue con la suya', (
      tester,
    ) async {
      await montar(
        tester,
        (p) async => RespuestaFalsa(403, <String, Object?>{
          'error': 'revoked',
          'message': 'La cuenta está dada de baja.',
        }),
      );

      await escribirYEntrar(tester);

      expect(find.textContaining('dada de baja'), findsWidgets);
      expect(find.text('Ir a Accesos'), findsNothing);
    });

    testWidgets('un 403 cualquiera sigue siendo «avisa a la oficina»', (
      tester,
    ) async {
      await montar(
        tester,
        (p) async => RespuestaFalsa(403, <String, Object?>{'error': 'otra'}),
      );

      await escribirYEntrar(tester);

      expect(find.textContaining('avisa a la oficina'), findsOneWidget);
      expect(find.text('Ir a Accesos'), findsNothing);
    });

    testWidgets('un 401 sigue siendo «usuario o contraseña incorrectos»', (
      tester,
    ) async {
      await montar(tester, (p) async => RespuestaFalsa(401, const {}));

      await escribirYEntrar(tester);

      expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
      expect(find.text('Ir a Accesos'), findsNothing);
    });
  });

  test('ServicioDeAcceso.entrar lanza el motivo sinPermiso con el mensaje '
      'del servidor, y no guarda nada', () async {
    final servicio = ServicioDeAcceso(
      auth: dioFalso((p) async => RespuestaFalsa(403, _sinPermisoDeAccesos)),
      almacen: almacen,
    );

    await expectLater(
      servicio.entrar(usuario: 'yasmani', contrasena: 'la-buena'),
      throwsA(
        isA<FalloDeAcceso>()
            .having((f) => f.motivo, 'motivo', MotivoDeAcceso.sinPermiso)
            .having(
              (f) => f.mensaje,
              'mensaje',
              'No tienes permiso para entrar a Reparto.',
            ),
      ),
    );
    expect(await almacen.leer(), isNull);
  });
}
