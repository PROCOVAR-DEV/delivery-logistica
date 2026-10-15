// «ELIGE UNA SUCURSAL PARA VER SU TABLERO» CON SANTIAGO ELEGIDO ARRIBA — 15/10/2026.
//
// El logístico de Santiago, escritorio Windows 1.0.35. Accesos le cerró la sesión a
// media tarde (el incidente del refresh perdido); volvió a entrar y el tablero dijo
// «Elige una sucursal para ver su tablero», con la pastilla de arriba diciendo
// «Santiago (STG)». Y ya le había pasado la primera vez que entró.
//
// La causa: `sucursalDelTableroProvider` era un `FutureProvider` que leía la sesión
// del ALMACÉN (`ref.watch(almacenSesionProvider).leer()`, un objeto que no cambia
// nunca) y traducía el código contra `branches` UNA vez:
//
//  * si se calculaba sin sesión —la sesión muere con el tablero delante: el
//    renovador borra el par y el portero cambia de copia—, devolvía `null` ANTES de
//    llegar a `ref.watch(baseProvider)`, así que se quedaba sin mirar nada que
//    pudiera cambiar: volver a entrar, misma persona, y seguía en `null`;
//  * si se calculaba con las sucursales aún sin bajar, `null` y congelado (§3-ter):
//    la barra, que es un `Stream`, sí se enteraba.
//
// Las dos con el molde del §3-ter: se monta, y lo que falta llega DESPUÉS sin volver a
// montar. Un provider escuchado hace de pantalla abierta.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/apoyo_accesos.dart';
import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

const _bajadaVacia = <String, Object?>{
  'hasta': '2026-10-15T16:00:00Z',
  'completa': true,
  'truncado': false,
  'cambios': <String, Object?>{},
  'sucursales': <Object?>[],
};

Future<RespuestaFalsa?> _todoBien(PeticionVista p) async =>
    RespuestaFalsa(200, _bajadaVacia);

void main() {
  // `tokenDePrueba` firma `sucursal: STG` y `sub: u-1`: el logístico de Santiago.
  final sesion = sesionDePrueba();
  late AlmacenEnMemoria almacen;
  late BaseLocal suya;
  late BaseLocal neutra;

  setUp(() {
    almacen = AlmacenEnMemoria();
    suya = baseDePrueba();
    neutra = baseDePrueba();
  });
  tearDown(() async {
    await suya.close();
    await neutra.close();
  });

  /// El portero de verdad y una base POR DUEÑO, como en el aparato: la de la persona
  /// sobrevive a que su sesión muera, y al volver a entrar se abre la misma.
  ProviderContainer montar({required BaseLocal Function(String?) baseDe}) {
    final c = ProviderContainer.test(
      overrides: [
        trabajaSinConexionProvider.overrideWithValue(true),
        navegadorProvider.overrideWithValue(NavegadorFalso()),
        entradaPorAccesosProvider.overrideWithValue(
          entradaFalsa(
            NavegadorFalso(),
            (p) async => RespuestaFalsa(401, const <String, Object?>{}),
          ),
        ),
        almacenSesionProvider.overrideWithValue(almacen),
        baseProvider.overrideWith(
          (ref) => baseDe(ref.watch(duenoDeLaBaseProvider)),
        ),
        relojProvider.overrideWithValue(() => DateTime(2026, 10, 15, 16)),
        dioAuthProvider.overrideWithValue(
          dioFalso((p) async => RespuestaFalsa(200, parDeTokens())),
        ),
        escuchaDeEventosProvider.overrideWithValue(
          (_, _, {renovarSesion, pulso}) => const Stream<String>.empty(),
        ),
      ],
    );
    c.read(clienteApiProvider).dio.httpClientAdapter = ServidorFalso(_todoBien);
    c.read(clienteSyncProvider).dio.httpClientAdapter = ServidorFalso(
      _todoBien,
    );
    return c;
  }

  Future<void> respirar() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// La pantalla del tablero, abierta: lo último que dijo su sucursal.
  AsyncValue<String?> Function() abrirElTablero(ProviderContainer c) {
    final sub = c.listen(sucursalDelTableroProvider, (_, _) {});
    addTearDown(sub.close);
    return () => c.read(sucursalDelTableroProvider);
  }

  test('la sesión muere con el tablero delante y la MISMA persona vuelve a '
      'entrar: el tablero vuelve a ser de Santiago', () async {
    await sembrarSucursal(suya); // `suc-stg`, código `STG`
    final c = montar(baseDe: (dueno) => dueno == null ? neutra : suya);
    addTearDown(c.dispose);

    await almacen.guardar(sesion);
    await c.read(porteroProvider).entro(sesion);
    final tablero = abrirElTablero(c);
    await respirar();
    expect(tablero().value, sucursalStg, reason: 'al entrar, su sucursal');

    // ACCESOS CIERRA LA SESIÓN: el renovador borra el par (401 al renovar) y el
    // portero echa a la persona y cambia de copia. El tablero sigue montado.
    await almacen.borrar();
    c.read(porteroProvider).murio();
    await respirar();

    // Vuelve a entrar, con señal, la misma persona: el par nuevo se guarda y el
    // portero la deja pasar. Nadie toca el selector (con una sola sucursal es una
    // pastilla, no hay nada que tocar).
    await almacen.guardar(sesion);
    await c.read(porteroProvider).entro(sesion);
    await respirar();

    expect(
      tablero().value,
      sucursalStg,
      reason:
          'volver a entrar tiene que devolverle su sucursal al tablero; con `null` '
          'dice «Elige una sucursal para ver su tablero» mientras la barra dice '
          'Santiago, y no hay nada que elegir',
    );
  });

  test('primera entrada: las sucursales llegan DESPUÉS de abrir el tablero, y '
      'el tablero se entera sin volver a montarlo', () async {
    final c = montar(baseDe: (_) => suya); // VACÍA: no ha bajado nada
    addTearDown(c.dispose);

    await almacen.guardar(sesion);
    await c.read(porteroProvider).entro(sesion);
    final tablero = abrirElTablero(c);
    await respirar();
    expect(
      tablero().value,
      isNull,
      reason: 'sin sucursales bajadas no se inventa un id: todavía no se sabe',
    );

    // Llega la bajada.
    await sembrarSucursal(suya);
    await respirar();

    expect(
      tablero().value,
      sucursalStg,
      reason:
          'la sucursal llegó con la pantalla abierta: tiene que resolverse sola, '
          'como la barra de arriba (§3-ter)',
    );
  });

  // EL MISMO PATRÓN UN PISO MÁS ABAJO: la lista de «Camión previsto» leía la
  // sucursal UNA vez por cambio de la flota. Sin sucursal todavía, ofrecía la flota
  // de todas, y así se quedaba hasta que cambiara un camión.
  test('los camiones de la zona se enteran cuando llega la sucursal', () async {
    final c = montar(baseDe: (_) => suya); // VACÍA
    addTearDown(c.dispose);
    await sembrarCamion(suya, id: 'cam-stg');
    await suya
        .into(suya.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: 'cam-hol',
            name: 'De Holguín',
            branchId: const Value('suc-hol'),
          ),
        );

    await almacen.guardar(sesion);
    await c.read(porteroProvider).entro(sesion);
    final sub = c.listen(camionesProvider, (_, _) {});
    addTearDown(sub.close);
    await respirar();

    await sembrarSucursal(suya);
    await respirar();

    expect(
      c.read(camionesProvider).value?.map((v) => v.id),
      ['cam-stg'],
      reason: 'con la sucursal ya resuelta, sólo los camiones de Santiago',
    );
  });

  // LA PAREJA: con la sesión muerta el tablero NO puede seguir enseñando la sucursal
  // de quien se fue (en el aparato pueden entrar dos personas por turnos).
  test('sin sesión no hay sucursal de la sesión', () async {
    await sembrarSucursal(suya);
    final c = montar(baseDe: (_) => suya);
    addTearDown(c.dispose);

    await almacen.guardar(sesion);
    await c.read(porteroProvider).entro(sesion);
    final tablero = abrirElTablero(c);
    await respirar();
    expect(tablero().value, sucursalStg);

    await almacen.borrar();
    c.read(porteroProvider).murio();
    await respirar();

    expect(tablero().value, isNull);
  });
}
