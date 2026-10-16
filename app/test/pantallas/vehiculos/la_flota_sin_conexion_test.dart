import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/pantallas/distribuidores/estado/proveedores_distribuidores.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';
import 'package:reparto/pantallas/vehiculos/estado/estado_vehiculos.dart';
import 'package:reparto/pantallas/vehiculos/vista/pantalla_vehiculos.dart';

import 'apoyo_vehiculos.dart';

/// ISSUE 14 DE AMADO (16/10/2026): «los vehículos no le funcionan offline: no se le
/// muestran ni los tipos, ni los distribuidores, ni los vehículos. No pudo crearlos
/// tampoco. Eso es en la aplicación de Windows.»
///
/// La causa: las tres pantallas pedian la lista al servidor y no tenian cola. Aqui, el
/// APARATO (APK / escritorio, que es lo que es un test en la VM) lee de su base y
/// escribe en su cola SIN RED. Y su pareja: la WEB sigue sin cola ni base
/// (`sin_conexion_test.dart`, con `trabajaSinConexionProvider` en falso).
void main() {
  late Banco banco;
  late ProviderContainer c;

  setUp(() {
    banco = Banco.sinRed();
    c = ProviderContainer(
      overrides: [
        baseProvider.overrideWithValue(banco.base),
        clienteApiProvider.overrideWithValue(
          banco.contenedor.read(clienteApiProvider),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(sesionDePrueba),
        ),
      ],
    );
  });
  tearDown(() async {
    c.dispose();
    await banco.cerrar();
  });

  /// Mantiene vivo un provider `autoDispose` mientras dura la prueba: sin la
  /// suscripcion se tira mientras carga.
  void mantener(ProviderContainer cont, dynamic p) {
    // ignore: avoid_dynamic_calls
    final sub = (cont as dynamic).listen(p, (_, _) {});
    addTearDown(() => (sub as dynamic).close());
  }

  Future<void> laSucursal() => banco.base
      .into(banco.base.branches)
      .insert(BranchesCompanion.insert(id: 's1', name: 'Santiago', lat: 0, lng: 0));

  Future<void> sembrarTipo(String id, String nombre, {String sucursal = 's1'}) =>
      banco.base
          .into(banco.base.vehicleTypes)
          .insert(
            VehicleTypesCompanion.insert(
              id: id,
              nombre: nombre,
              branchId: Value(sucursal),
            ),
          );

  Future<List<String>> cola() async => [
    for (final a in await banco.base.select(banco.base.apuntes).get())
      '${a.metodo} ${a.ruta}',
  ];

  test('SIN RED, el aparato lee la flota, los tipos y los distribuidores de su base', () async {
    await sembrarFlotaBajada(banco.base, cuantos: 2);
    await sembrarTipo('t1', 'truck');
    await banco.base
        .into(banco.base.distribuidores)
        .insert(
          DistribuidoresCompanion.insert(id: 'd1', nombre: 'Juan', branchId: const Value('s1')),
        );

    mantener(c, vehiculosProvider);
    mantener(c, ajustesVehiculosProvider);
    mantener(c, distribuidoresDelServidorProvider);
    final flota = await c.read(vehiculosProvider.future);
    final ajustes = await c.read(ajustesVehiculosProvider.future);
    final distribuidores = await c.read(distribuidoresDelServidorProvider.future);

    expect(flota.map((v) => v.id).toSet(), {'v0', 'v1'});
    expect(ajustes.tipos.map((t) => t.nombre), ['truck']);
    expect(distribuidores.map((d) => d.nombre), ['Juan']);
    expect(banco.servidor.vistas, isEmpty, reason: 'sin una sola peticion');
  });

  test('SIN RED, crear un tipo y un camion de ese tipo entra en la cola EN ORDEN', () async {
    await laSucursal();
    await sembrarTipo('t1', 'truck');

    final control = c.read(controlVehiculosProvider.notifier);
    expect(await control.crearTipo(const TipoDeVehiculo(nombre: 'triciclo', costoKmUsd: 0.4)), isTrue);
    expect(
      await control.crear(
        const DatosVehiculo(nombre: 'Triciclo 1', tipo: 'triciclo', capacidad: 200),
      ),
      isTrue,
    );

    // El camion apunta al tipo por NOMBRE: no depende de que el tipo ya haya subido,
    // pero el tipo tiene que subir ANTES (la cola es FIFO).
    expect(await cola(), ['POST /vehicle-types', 'POST /vehicles']);
    final apuntes = await banco.base.select(banco.base.apuntes).get();
    expect(apuntes.every((a) => a.provisional?.startsWith('local-') ?? false), isTrue);
    expect((await banco.base.select(banco.base.vehicles).get()).single.name, 'Triciclo 1');
    expect(banco.servidor.vistas, isEmpty);
    // Y se ve al momento en la flota del aparato.
    mantener(c, vehiculosProvider);
    expect((await c.read(vehiculosProvider.future)).single.tipo, 'triciclo');
  });

  test('SIN RED, un camion de un tipo que no existe se rechaza con las palabras del servidor', () async {
    await laSucursal();
    await sembrarTipo('t1', 'truck');
    final control = c.read(controlVehiculosProvider.notifier);

    expect(await control.crear(const DatosVehiculo(nombre: 'X', tipo: 'nave')), isFalse);
    expect(
      c.read(controlVehiculosProvider)!.texto,
      "No existe el tipo de vehículo 'nave'",
    );
    expect(await cola(), isEmpty, reason: 'un «no» local no deja un apunte que el servidor rechazaria horas despues');
  });

  test('SIN RED, un distribuidor se da de alta, se renombra y se quita; repetido se rechaza', () async {
    await banco.base
        .into(banco.base.branches)
        .insert(BranchesCompanion.insert(id: 's1', name: 'Santiago', lat: 0, lng: 0));
    final repo = c.read(repositorioDistribuidoresProvider);

    final d = await repo.crear('  Juan   Pérez ');
    expect(d.nombre, 'Juan Pérez', reason: 'espacios limpios como en el servidor');
    await expectLater(
      repo.crear('juan pérez'),
      throwsA(isA<Rechazo>().having((e) => e.mensaje, 'mensaje', contains('Ya existe un distribuidor'))),
    );
    await repo.cambiar(d.id, nombre: 'Juan P.');
    expect(await repo.quitar(d.id), isNotNull);

    expect(await cola(), [
      'POST /distribuidores',
      'PATCH /distribuidores/${d.id}',
      'DELETE /distribuidores/${d.id}',
    ]);
    expect(await banco.base.select(banco.base.distribuidores).get(), isEmpty);
  });

  test('SIN RED, un camion con rutas no se borra, y uno sin rutas si', () async {
    await sembrarFlotaBajada(banco.base, cuantos: 2);
    await banco.base.update(banco.base.vehicles).write(
      const VehiclesCompanion(branchId: Value('s1')),
    );
    await banco.base
        .into(banco.base.routes)
        .insert(RoutesCompanion.insert(id: 'r1', vehicleId: const Value('v0')));
    final control = c.read(controlVehiculosProvider.notifier);

    expect(await control.eliminar('v0'), isFalse);
    expect(c.read(controlVehiculosProvider)!.texto, contains('tiene rutas asociadas'));
    expect(await control.eliminar('v1'), isTrue);
    expect(await cola(), ['DELETE /vehicles/v1']);
  });

  test('quien ve las ocho sucursales NO encola un alta: sin sucursal propia saldria compartido', () async {
    final todas = ProviderContainer(
      overrides: [
        baseProvider.overrideWithValue(banco.base),
        clienteApiProvider.overrideWithValue(
          banco.contenedor.read(clienteApiProvider),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 'tok',
              refresh: 'r0',
              sub: 'u1',
              roles: ['SUPER ADMIN'],
            ),
          ),
        ),
      ],
    );
    addTearDown(todas.dispose);

    // Hay un tipo «de todas»: sin la excepcion el alta se encolaria y nacería COMPARTIDA.
    await banco.base.into(banco.base.vehicleTypes).insert(
      VehicleTypesCompanion.insert(id: 'tt', nombre: 'truck'),
    );
    // Sin red: el alta va al servidor y NO se guarda en ningun sitio.
    expect(
      await todas
          .read(controlVehiculosProvider.notifier)
          .crear(const DatosVehiculo(nombre: 'Camión SA')),
      isFalse,
    );
    expect(await cola(), isEmpty);
    expect(await banco.base.select(banco.base.vehicles).get(), isEmpty);
  });

  test('PAREJA: en la WEB no hay cola ni base: sin red no guarda nada', () async {
    final web = ProviderContainer(
      overrides: [
        baseProvider.overrideWithValue(banco.base),
        clienteApiProvider.overrideWithValue(
          banco.contenedor.read(clienteApiProvider),
        ),
        trabajaSinConexionProvider.overrideWithValue(false),
      ],
    );
    addTearDown(web.dispose);

    expect(
      await web
          .read(controlVehiculosProvider.notifier)
          .crear(const DatosVehiculo(nombre: 'Camión web')),
      isFalse,
    );
    expect(await cola(), isEmpty);
    expect(web.read(flotaLocalProvider), isNull, reason: 'la web no tiene base ni cola');
    await expectLater(
      web.read(repositorioVehiculosProvider).listar(),
      throwsA(isA<FalloDeRed>()),
    );
  });

  testWidgets('con la base RECIEN CREADA y sin bajar, dice «no ha descargado», no «Sin vehículos»', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(banco.base),
          clienteApiProvider.overrideWithValue(
            banco.contenedor.read(clienteApiProvider),
          ),
          almacenSesionProvider.overrideWithValue(AlmacenEnMemoria(sesionDePrueba)),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaVehiculos())),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));

    expect(find.textContaining('no ha descargado la flota todavía'), findsOneWidget);
    expect(find.text('Sin vehículos'), findsNothing);
    expect(find.textContaining('Sin conexión.'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('con la flota bajada y SIN red, la pantalla la enseña', (tester) async {
    await sembrarFlotaBajada(banco.base, cuantos: 2);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(banco.base),
          clienteApiProvider.overrideWithValue(
            banco.contenedor.read(clienteApiProvider),
          ),
          almacenSesionProvider.overrideWithValue(AlmacenEnMemoria(sesionDePrueba)),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaVehiculos())),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));

    expect(find.text('Camión #0'), findsOneWidget);
    expect(find.text('Camión #1'), findsOneWidget);
    expect(find.textContaining('Sin conexión.'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
