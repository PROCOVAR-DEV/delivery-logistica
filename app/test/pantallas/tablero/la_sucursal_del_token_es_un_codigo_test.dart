// EL TOKEN TRAE EL CODIGO DE LA SUCURSAL, NO EL ID — 24/09/2026.
//
// Accesos firma `sucursal: "CAM"` (`apk-tokens.ts`), y aqui todo va por
// `branches.id`, que es un uuid del reparto. `sucursalDelTableroProvider`
// devolvia el codigo tal cual, y con eso:
//
//   * `GET /api/board?branchId=CAM` contesta **404** —«un id que ni siquiera es
//     un uuid es el mismo caso que uno que ya no esta»—;
//   * y las lecturas locales —columnas, nombre de la sucursal, almacen,
//     camiones— no encontraban nada, porque buscaban por id.
//
// Desde la silla de quien trabaja: **pulsas «Tablero» y no pasa nada**. Ni error
// ni aviso ni rueda. Se vio el primer dia que se pudo entrar en el portatil con
// el Accesos de verdad levantado.
//
// Las pruebas van EN PAREJA, y hacen falta las dos: la primera exige que el
// codigo se traduzca, y la segunda que un codigo que no esta **no se devuelva
// tal cual**. Sin la segunda, «devolver siempre lo que venga» pasaria la
// primera y el fallo seguiria vivo para una sucursal que el aparato todavia no
// bajo.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

/// La sucursal que trae la sesion vigente, tal cual la firma Accesos. Desde el
/// 15/10/2026 sale del portero (`sucursalDeLaSesionProvider`), no del almacen.
String? _sesionCon(String? sucursal) =>
    (sucursal == null || sucursal.isEmpty) ? null : sucursal;

ProviderContainer _contenedor(BaseLocal base, String? sucursalDeLaSesion) =>
    ProviderContainer(
      overrides: [
        baseProvider.overrideWithValue(base),
        sucursalDeLaSesionProvider.overrideWithValue(sucursalDeLaSesion),
      ],
    );

void main() {
  late BaseLocal base;

  setUp(() async {
    base = baseDePrueba();
    await sembrarSucursal(base); // id `suc-stg`, externalId `STG`
  });

  tearDown(() => base.close());

  test('el codigo del token se traduce al id del reparto', () async {
    final c = _contenedor(base, _sesionCon(codigoStg));
    addTearDown(c.dispose);

    final id = await c.read(sucursalDelTableroProvider.future);

    expect(
      id,
      sucursalStg,
      reason:
          'el tablero tiene que mirar la sucursal por su id; con el codigo, '
          '/api/board contesta 404 y la base local no encuentra ni las columnas',
    );
  });

  test('un codigo que el aparato no tiene NO se devuelve tal cual', () async {
    final c = _contenedor(base, _sesionCon('HOL'));
    addTearDown(c.dispose);

    final id = await c.read(sucursalDelTableroProvider.future);

    expect(
      id,
      isNull,
      reason:
          'sin con que traducir no se inventa un id: null es «todavia no se '
          'sabe cual», y devolver el codigo seria un id falso que el servidor '
          'rechaza con 404',
    );
  });

  test('un id del reparto se respeta: es lo que elige arriba un Super Admin',
      () async {
    final c = _contenedor(base, _sesionCon(sucursalStg));
    addTearDown(c.dispose);

    expect(await c.read(sucursalDelTableroProvider.future), sucursalStg);
  });

  // LA OTRA MITAD, y hace falta: la traduccion es SOLO para lo de la sesion. Lo
  // que elige arriba un Super Admin ya es un id del reparto y sale de la lista
  // del servidor, asi que va tal cual aunque el aparato no tenga esa sucursal
  // bajada — si se tradujera contra la copia, cambiar de sucursal dejaria el
  // tablero mudo en vez de ir a pedir la foto. Lo caza tambien
  // `el_filtro_no_pide_al_servidor_test.dart`.
  test('la que se elige ARRIBA va tal cual, aunque no este en la copia', () async {
    final c = _contenedor(base, _sesionCon(codigoStg));
    addTearDown(c.dispose);
    c.read(sucursalMiradaProvider.notifier).mirar('suc-hol');

    expect(
      await c.read(sucursalDelTableroProvider.future),
      'suc-hol',
      reason:
          'la sucursal elegida arriba no se traduce: ya es un id, y si el '
          'aparato no la tiene hay que ir a pedirla, no quedarse callado',
    );
  });

  test('sin sucursal en la sesion no se mira ninguna', () async {
    final c = _contenedor(base, _sesionCon(''));
    addTearDown(c.dispose);

    expect(
      await c.read(sucursalDelTableroProvider.future),
      isNull,
      reason:
          'un Super Admin sin sucursal propia elige arriba; un tablero de las '
          'ocho mezcladas ordenaria los pedidos de Holguin por su distancia al '
          'almacen de Santiago',
    );
  });
}
