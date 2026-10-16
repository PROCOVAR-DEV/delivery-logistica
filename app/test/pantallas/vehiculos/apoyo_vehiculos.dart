import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

const sesionDePrueba = Sesion(
  token: 'tok',
  refresh: 'r0',
  sub: 'u1',
  sucursalId: 'STG',
);

/// Un banco de pruebas con la base local de verdad y la API en un servidor
/// falso.
///
/// La base va de verdad —no un doble— porque lo que hay que demostrar es que
/// **NO se escribe nada en ella**, y eso no se puede demostrar contra un doble
/// que no sabe escribir.
class Banco {
  Banco(this.responder) {
    base = baseDePrueba();
    servidor = ServidorFalso(responder);
    final almacen = AlmacenEnMemoria(sesionDePrueba);
    final auth = Dio(BaseOptions(baseUrl: 'https://auth.test'))
      ..httpClientAdapter = servidor;
    final cliente = ClienteApi.montar(
      baseUrl: 'https://api.test',
      almacen: almacen,
      renovador: Renovador(auth, almacen),
      // Sin esperas: lo que se prueba es la politica, no el reloj.
      esperar: (_) async {},
    );
    cliente.dio.httpClientAdapter = servidor;

    contenedor = ProviderContainer(
      overrides: [
        baseProvider.overrideWithValue(base),
        // LA WEB: sin base local ni cola (el aparato: la_flota_sin_conexion_test.dart).
        trabajaSinConexionProvider.overrideWithValue(false),
        clienteApiProvider.overrideWithValue(cliente),
      ],
    );
  }

  /// Un banco **sin red**: ninguna peticion llega a ningun sitio.
  factory Banco.sinRed() => Banco((_) async => null);

  final Future<RespuestaFalsa?> Function(PeticionVista) responder;
  late final BaseLocal base;
  late final ServidorFalso servidor;
  late final ProviderContainer contenedor;

  Future<void> cerrar() async {
    contenedor.dispose();
    await base.close();
  }
}

/// Deja en la base la COPIA BAJADA de la flota, con su marca de frescura.
///
/// Es lo que la bajada del dia habria dejado. Sirve para distinguir en pantalla
/// «este aparato no ha descargado la flota» de «el aparato la tiene y ahora no
/// hay red», que son dos situaciones distintas y se arreglan al reves.
Future<void> sembrarFlotaBajada(
  BaseLocal base, {
  int cuantos = 1,
  DateTime? cuando,
}) async {
  for (var i = 0; i < cuantos; i++) {
    await base
        .into(base.vehicles)
        .insertOnConflictUpdate(
          VehiclesCompanion.insert(id: 'v$i', name: 'Camión #$i'),
        );
  }
  await base
      .into(base.frescura)
      .insertOnConflictUpdate(
        FrescuraCompanion.insert(
          coleccion: Colecciones.vehiculos,
          bajadaAt: Value(cuando ?? DateTime(2026, 9, 15, 8)),
          completa: const Value(true),
        ),
      );
}
