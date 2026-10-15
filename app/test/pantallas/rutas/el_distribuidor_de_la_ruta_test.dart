// QUIEN REPARTE SE ELIGE AL CREAR LA RUTA, TAMBIEN SIN SEÑAL — issue 7 de Amado, 14/10/2026.
//
// El distribuidor es la persona responsable de la entrega y de devolver las facturas entregadas.
// Se asocia AL CREAR LA RUTA, y la APK y el escritorio la crean sin conexion: el apunte que se
// encola lleva `distribuidorId`, la ruta local lo apunta, y el aparato comprueba antes lo que el
// servidor comprobaria despues —de la sucursal de la ruta, en activo— con SUS mismas palabras,
// para que el «no» salga ahora y no horas despues en la bandeja.
//
// TODO EN PAREJA: cada «no» tiene su «sí» al lado.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/distribuidores/datos/distribuidor_valido.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late AccionesDeRuta acciones;

  setUp(() async {
    base = baseDePrueba();
    final reloj = RelojFalso(DateTime.utc(2026, 10, 14, 9));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    acciones = AccionesDeRuta(base, cola, reloj: reloj.leer, sufijoAparato: 'MSI');
    await sembrarCatalogo(base);
    await sembrarPedido(
      base, id: 'q1', cliente: 'Ana', folio: 'F-001', peso: 10, endLat: 0, endLng: 0.1,
    );
    // Dos de Camagüey (B1) —uno retirado— y uno de Holguín (B2).
    for (final (id, nombre, sucursal, activo) in const [
      ('d-juan', 'Juan Pérez', 'B1', true),
      ('d-pedro', 'Pedro Gil', 'B1', false),
      ('d-luis', 'Luis Gómez', 'B2', true),
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
  });

  tearDown(() => base.close());

  Future<String> armar({String? distribuidorId}) => acciones.armar(
    vehiculoId: 'V1',
    pedidoIds: const ['q1'],
    origenLat: 0,
    origenLng: 0,
    sucursalId: 'B1',
    distribuidorId: distribuidorId,
  );

  Future<Ruta> laRuta(String id) => (base.select(base.routes)..where((r) => r.id.equals(id))).getSingle();

  Future<Map<String, Object?>> elApunte() async =>
      ColaDeSalida.cuerpoDe((await cola.pendientes().first).single)! as Map<String, Object?>;

  test('con distribuidor: la ruta local lo apunta Y el apunte lo lleva', () async {
    final rutaId = await armar(distribuidorId: 'd-juan');

    expect((await laRuta(rutaId)).distribuidorId, 'd-juan');
    expect(
      (await elApunte())['distribuidorId'],
      'd-juan',
      reason: 'sin el en el cuerpo, la ruta sube sin quien la reparte aunque en el aparato lo diga',
    );
  });

  for (final vacio in <String?>[null, '', '  ']) {
    test('sin distribuidor (${vacio == null ? 'null' : "'$vacio'"}): la ruta sale sin el, y el apunte no inventa la clave', () async {
      final rutaId = await armar(distribuidorId: vacio);

      expect((await laRuta(rutaId)).distribuidorId, isNull);
      expect(
        (await elApunte()).containsKey('distribuidorId'),
        isFalse,
        reason: 'el servidor lee la ausencia como «sin distribuidor», que es lo que esta ruta es',
      );
    });
  }

  group('lo que el servidor rechazaria, el aparato lo dice antes y con sus palabras', () {
    Future<void> sinEscribirNada(Object? error) async {
      expect(error, isA<RechazoLocal>());
      expect(await base.select(base.routes).get(), isEmpty,
          reason: 'el «no» llego DESPUES de crear la ruta');
      expect(await cola.pendientes().first, isEmpty,
          reason: 'un apunte que el servidor va a rechazar no se encola');
    }

    test('uno RETIRADO', () async {
      Object? error;
      try {
        await armar(distribuidorId: 'd-pedro');
      } on Object catch (e) {
        error = e;
      }
      expect((error! as RechazoLocal).mensaje, msgDistribuidorRetirado);
      expect(msgDistribuidorRetirado, 'El distribuidor está retirado y no se puede asignar a una ruta.');
      await sinEscribirNada(error);
    });

    test('uno que el aparato no conoce', () async {
      Object? error;
      try {
        await armar(distribuidorId: 'd-fantasma');
      } on Object catch (e) {
        error = e;
      }
      expect((error! as RechazoLocal).mensaje, "No existe el distribuidor 'd-fantasma'");
      await sinEscribirNada(error);
    });

    test('uno de OTRA sucursal (si el aparato lo tiene)', () async {
      Object? error;
      try {
        await armar(distribuidorId: 'd-luis');
      } on Object catch (e) {
        error = e;
      }
      expect(
        (error! as RechazoLocal).mensaje,
        "El distribuidor 'd-luis' no es de la sucursal de esta ruta",
      );
      await sinEscribirNada(error);
    });

    // Falla cerrado, como el servidor: una ruta sin sucursal no admite a nadie.
    // La pareja: con la sucursal de la ruta, el mismo distribuidor pasa.
    test('sin sucursal de la ruta no vale ninguno; con la suya, si', () async {
      await expectLater(
        distribuidorParaUnaRuta(base, id: 'd-juan', sucursalDeLaRuta: null),
        throwsA(isA<DistribuidorNoValido>()),
      );
      final d = await distribuidorParaUnaRuta(
        base,
        id: 'd-juan',
        sucursalDeLaRuta: 'B1',
      );
      expect(d?.id, 'd-juan');
    });
  });

  group('en la web la ruta la crea el servidor, y el distribuidor viaja y vuelve', () {
    late ServidorFalso servidor;
    late AccionesDeRuta enLaWeb;
    final vistas = <PeticionVista>[];

    setUp(() {
      vistas.clear();
      servidor = ServidorFalso((p) async {
        vistas.add(p);
        return RespuestaFalsa(201, <String, Object?>{
          'id': 'r-de-verdad',
          'routeCode': 'RT-20261014-001',
          'status': EstadoRuta.planificada,
          'vehicleId': 'V1',
          'branchId': 'B1',
          'distribuidorId': 'd-juan',
          'orders': <Object?>[
            <String, Object?>{'id': 'q1', 'stopOrder': 1, 'tripLeg': Tramo.ida},
          ],
        });
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
        ..httpClientAdapter = servidor;
      enLaWeb = AccionesDeRuta(
        base,
        cola,
        reloj: RelojFalso(DateTime.utc(2026, 10, 14, 9)).leer,
        enVivo: EscrituraEnVivo(ClienteApi(dio: dio, esperas: const <Duration>[])),
      );
    });

    test('el cuerpo lleva `distribuidorId` y la fila refleja lo que guardo el servidor', () async {
      final id = await enLaWeb.armar(
        vehiculoId: 'V1',
        pedidoIds: const ['q1'],
        origenLat: 0,
        origenLng: 0,
        sucursalId: 'B1',
        distribuidorId: 'd-juan',
      );

      expect(id, 'r-de-verdad');
      expect((vistas.single.cuerpo! as Map<Object?, Object?>)['distribuidorId'], 'd-juan');
      expect((await laRuta(id)).distribuidorId, 'd-juan',
          reason: 'la lista tiene que decir quien reparte con lo que el servidor guardo');
      expect(await cola.pendientes().first, isEmpty, reason: 'en la web no se encola nada');
    });

    test('uno retirado no sale ni a la red', () async {
      Object? error;
      try {
        await enLaWeb.armar(
          vehiculoId: 'V1',
          pedidoIds: const ['q1'],
          origenLat: 0,
          origenLng: 0,
          sucursalId: 'B1',
          distribuidorId: 'd-pedro',
        );
      } on Object catch (e) {
        error = e;
      }
      expect((error! as RechazoLocal).mensaje, msgDistribuidorRetirado);
      expect(vistas, isEmpty, reason: 'el aparato ya sabe que el servidor diria que no');
    });
  });
}
