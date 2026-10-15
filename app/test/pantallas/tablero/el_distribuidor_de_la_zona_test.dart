// QUIEN REPARTE SE ELIGE AL ARMAR LA ZONA — issue 7 de Amado, 14/10/2026.
//
// Armar una zona del tablero es POR DONDE SE ARMA EL DIA DE VERDAD, asi que el distribuidor se elige
// aqui y no solo en el asistente de «Nueva ruta». La zona NO lo guarda (como guarda el camion
// previsto): el distribuidor es de la ruta que sale hoy, no de la zona.
//
// Dos mitades, y las dos hacen falta:
//
//  * el REPOSITORIO: el apunte `POST /board/columns/{id}/route` lleva `distribuidorId`, la ruta local
//    lo apunta, y lo que el servidor rechazaria (retirado, de otra sucursal, desconocido) se dice
//    ANTES con sus palabras y sin escribir nada;
//  * la PANTALLA, con el dedo: el cajon de la zona ofrece el selector justo encima del boton que
//    arma, y lo elegido llega a la ruta.
//
// TODO EN PAREJA.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
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
import 'package:reparto/pantallas/distribuidores/datos/distribuidor_valido.dart';
import 'package:reparto/pantallas/distribuidores/vista/selector_de_distribuidor.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  /// Los apuntes pendientes que arman una ruta (los de crear la zona y colocar la tarjeta no cuentan).
  Future<List<Apunte>> apuntesDeArmar(ColaDeSalida cola) async => [
    for (final a in await cola.pendientes().first)
      if (a.ruta.endsWith('/route')) a,
  ];

  group('el repositorio', () {
    late BaseLocal base;
    late ConsultasTablero consultas;
    late ColaDeSalida cola;
    late RepositorioTablero repo;
    late String centro;

    setUp(() async {
      base = baseDePrueba();
      consultas = ConsultasTablero(base);
      cola = ColaDeSalida(base);
      repo = RepositorioTablero(base, cola);
      await sembrarSucursal(base);
      await sembrarAlmacen(base);
      await sembrarCamion(base, id: 'v1', capacidad: 2000);
      centro = await repo.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
        vehiculoId: 'v1',
      );
      for (final (id, nombre, sucursal, activo) in const [
        ('d-juan', 'Juan Pérez', sucursalStg, true),
        ('d-pedro', 'Pedro Gil', sucursalStg, false),
        ('d-luis', 'Luis Gómez', 'suc-hol', true),
      ]) {
        await base.into(base.distribuidores).insert(
          DistribuidoresCompanion.insert(
            id: id,
            nombre: nombre,
            activo: Value(activo),
            branchId: Value(sucursal),
          ),
        );
      }
      await sembrarPedido(base, id: 'p1', peso: 100);
      await repo.colocar(pedidoId: 'p1', columnaId: centro);
    });

    tearDown(() => base.close());

    Future<String> armar({String? distribuidorId}) => repo.armarRuta(
      columnaId: centro,
      sucursalId: sucursalStg,
      distribuidorId: distribuidorId,
    );

    test('con distribuidor: la ruta local lo apunta y el apunte lo lleva', () async {
      final rutaId = await armar(distribuidorId: 'd-juan');

      final ruta = await (base.select(base.routes)..where((r) => r.id.equals(rutaId))).getSingle();
      expect(ruta.distribuidorId, 'd-juan');
      final apunte = (await apuntesDeArmar(cola)).single;
      expect((ColaDeSalida.cuerpoDe(apunte)! as Map)['distribuidorId'], 'd-juan',
          reason: 'sin el en el cuerpo, la ruta del servidor sale sin quien la reparte');
    });

    test('la pareja: sin distribuidor, la ruta sale sin el y el cuerpo no inventa la clave', () async {
      final rutaId = await armar();

      final ruta = await (base.select(base.routes)..where((r) => r.id.equals(rutaId))).getSingle();
      expect(ruta.distribuidorId, isNull);
      final apunte = (await apuntesDeArmar(cola)).single;
      expect((ColaDeSalida.cuerpoDe(apunte)! as Map).containsKey('distribuidorId'), isFalse);
    });

    for (final (nombre, id, mensaje) in [
      ('retirado', 'd-pedro', msgDistribuidorRetirado),
      ('de otra sucursal', 'd-luis', "El distribuidor 'd-luis' no es de la sucursal de esta ruta"),
      ('que el aparato no conoce', 'd-fantasma', "No existe el distribuidor 'd-fantasma'"),
    ]) {
      test('uno $nombre: se dice ahora con las palabras del servidor y no se escribe nada', () async {
        Object? error;
        try {
          await armar(distribuidorId: id);
        } on Object catch (e) {
          error = e;
        }
        expect((error! as RechazoDelTablero).mensaje, mensaje);
        expect(await base.select(base.routes).get(), isEmpty, reason: 'el «no» llego DESPUES de crear la ruta');
        expect(await apuntesDeArmar(cola), isEmpty, reason: 'un apunte que el servidor va a rechazar no se encola');
        expect((await consultas.columnas(sucursalStg)).single.pedidos, 1,
            reason: 'y la zona se queda con lo que tenia: no se vacia por un «no»');
      });
    }
  });

  group('la pantalla, con el dedo', () {
    late BaseLocal base;
    late ProviderContainer contenedor;

    setUp(() => base = BaseLocal.con(NativeDatabase.memory()));
    tearDown(() => base.close());

    Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    Future<void> pasadasCortas(WidgetTester tester) async {
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
      final dio = Dio()..httpClientAdapter = ServidorFalso((peticion) async => null);
      contenedor = ProviderContainer(
        overrides: [
          baseProvider.overrideWith((ref) => base),
          clienteApiProvider.overrideWithValue(ClienteApi(dio: dio, esperas: const <Duration>[])),
          almacenSesionProvider.overrideWithValue(
            AlmacenEnMemoria(
              const Sesion(token: 't', refresh: 'r', sub: 'logistico', sucursalId: sucursalStg),
            ),
          ),
        ],
      );
      addTearDown(contenedor.dispose);
      return UncontrolledProviderScope(
        container: contenedor,
        child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
      );
    }

    Future<void> abrirElCajonDeArmar(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await sembrarSucursal(base);
      await sembrarAlmacen(base);
      await sembrarCamion(base, id: 'v1', nombre: 'F-350', capacidad: 1500);
      await RepositorioTablero(base, ColaDeSalida(base))
          .crearColumna(sucursalId: sucursalStg, nombre: 'Centro', vehiculoId: 'v1');
      await tester.pumpWidget(montar());
      await asentar(tester);
      await sembrarPedido(base, id: 'p1', cliente: 'Bodega La Esquina');
      await pasadasCortas(tester);
      await tester.tap(find.text('Bodega La Esquina'));
      await pasadasCortas(tester);
      await tester.tap(find.text('Colocar en «Centro»'));
      await pasadasCortas(tester);
      await tester.tap(find.byTooltip('Opciones de la columna'));
      await asentar(tester);
    }

    Future<void> sembrarDistribuidores() async {
      for (final (id, nombre, activo) in const [
        ('d-juan', 'Juan Pérez', true),
        ('d-pedro', 'Pedro Gil', false),
      ]) {
        await base.into(base.distribuidores).insert(
          DistribuidoresCompanion.insert(
            id: id,
            nombre: nombre,
            activo: Value(activo),
            branchId: const Value(sucursalStg),
          ),
        );
      }
    }

    testWidgets('el cajon de la zona ofrece el selector, y lo elegido llega a la ruta', (tester) async {
      await abrirElCajonDeArmar(tester);
      await sembrarDistribuidores();
      await pasadasCortas(tester);

      expect(find.byKey(SelectorDeDistribuidor.claveDelSelector), findsOneWidget,
          reason: 'armar una zona es por donde se arma el dia: el distribuidor se elige AQUI');

      await tester.tap(find.byKey(SelectorDeDistribuidor.claveDelSelector));
      await pasadasCortas(tester);
      expect(find.text('Pedro Gil'), findsNothing, reason: 'un retirado no se ofrece');
      await tester.tap(find.text('Juan Pérez'));
      await pasadasCortas(tester);

      await tester.tap(find.text('Armar la ruta de esta zona'));
      await pasadasCortas(tester);

      // Con la pantalla viva (sus streams de Drift) una lectura suelta cuelga la prueba en vez
      // de fallarla: se hace en tiempo real.
      final rutas = (await tester.runAsync(() => base.select(base.routes).get()))!;
      expect(rutas.single.distribuidorId, 'd-juan');
      final apunte = (await tester.runAsync(() => apuntesDeArmar(ColaDeSalida(base))))!.single;
      expect((ColaDeSalida.cuerpoDe(apunte)! as Map)['distribuidorId'], 'd-juan');
      await desmontar(tester);
    });

    testWidgets('la pareja: sin tocar el selector la ruta se arma igual, sin distribuidor', (tester) async {
      await abrirElCajonDeArmar(tester);
      await sembrarDistribuidores();
      await pasadasCortas(tester);

      await tester.tap(find.text('Armar la ruta de esta zona'));
      await pasadasCortas(tester);

      expect((await tester.runAsync(() => base.select(base.routes).get()))!.single.distribuidorId, isNull,
          reason: 'es opcional: no se le impone uno a quien no lo eligio');
      await desmontar(tester);
    });

    testWidgets('sin distribuidores en la sucursal, el cajon lo dice y la ruta se arma igual', (tester) async {
      await abrirElCajonDeArmar(tester);
      expect(find.text('Crear distribuidores'), findsOneWidget);

      await tester.tap(find.text('Armar la ruta de esta zona'));
      await pasadasCortas(tester);
      expect((await tester.runAsync(() => base.select(base.routes).get())), hasLength(1));
      await desmontar(tester);
    });
  });
}
