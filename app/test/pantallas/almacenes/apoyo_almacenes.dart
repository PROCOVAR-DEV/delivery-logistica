import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// El mismo banco que el de Vehiculos y por el mismo motivo: la base local va de
/// verdad para poder demostrar que **no se toca**. La pantalla es de SOLO
/// LECTURA (los almacenes se editan en el CRM): `servidor.vistas` sirve para
/// demostrar que nunca sale nada que no sea un GET.
///
/// Es una copia deliberada de `../vehiculos/apoyo_vehiculos.dart`: las pruebas
/// de una pantalla no dependen de las de otra, para que borrar una pantalla no
/// deje las pruebas de la de al lado sin compilar.
class Banco {
  Banco(this.responder) {
    base = baseDePrueba();
    servidor = ServidorFalso(responder);
    const sesion = Sesion(
      token: 'tok',
      refresh: 'r0',
      sub: 'u1',
      sucursalId: 'STG',
    );
    final almacen = AlmacenEnMemoria(sesion);
    final auth = Dio(BaseOptions(baseUrl: 'https://auth.test'))
      ..httpClientAdapter = servidor;
    final cliente = ClienteApi.montar(
      baseUrl: 'https://api.test',
      almacen: almacen,
      renovador: Renovador(auth, almacen),
      esperar: (_) async {},
    );
    cliente.dio.httpClientAdapter = servidor;

    contenedor = ProviderContainer(
      overrides: [
        baseProvider.overrideWithValue(base),
        clienteApiProvider.overrideWithValue(cliente),
      ],
    );
  }

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
