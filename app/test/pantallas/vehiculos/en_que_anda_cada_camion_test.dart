// EN QUÉ ANDA CADA CAMIÓN — 28/09/2026.
//
// Jose: «si la idea es q salga el vehiculo y ese vehiculo se ponga su estado
// para q saber como anda ese vehiculo y saber de la flota».
//
// Hasta hoy, la pantalla de Vehículos listaba camiones y no decía en qué andaba
// ninguno. La caja azul «Ruta activa» estaba escrita en `tarjeta_vehiculo.dart`
// desde el principio y **no salía nunca**, porque `GET /api/vehicles` no mandaba
// el campo `routes` que ella lee: un camión podía estar rodando y su tarjeta no
// lo decía por ningún sitio.
//
// Lo que aquí se fija es de DÓNDE sale el estado: de las RUTAS del camión, no de
// `vehicles.status`. Ese campo es uno que alguien pone y alguien tiene que
// quitar, y se queda en `in_use` en cuanto una ruta se cierra por otro camino.
// El servidor ya lo tenía escrito desde antes en `ContarVehiculosEnRuta`.
//
// LAS PRUEBAS VAN EN PAREJA: que el estado salga cuando toca y que **no salga**
// cuando no. Y hay una tercera pareja que es la que más se paga: `planned` e
// `in_progress` NO son lo mismo. Un camión con ruta planificada está cogido para
// mañana pero no ha salido; juntar los dos en «ocupado» manda a buscar otro
// camión a quien tenía uno disponible.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';

void main() {
  VehiculoDeLaApi camion({
    String estadoGuardado = 'available',
    Map<String, Object?>? ruta,
  }) => VehiculoDeLaApi.deJson(<String, Object?>{
    'id': 'v1',
    'name': 'Camión 1',
    'capacity': 1000,
    'status': estadoGuardado,
    'plate': 'P-001',
    'routes': ruta == null ? <Object?>[] : <Object?>[ruta],
  });

  test('sin ruta abierta está LIBRE, aunque el campo guardado diga otra cosa', () {
    final v = camion(estadoGuardado: 'in_use');

    expect(
      v.andar,
      AndarDelCamion.libre,
      reason:
          '`vehicles.status` se queda en `in_use` en cuanto una ruta se cierra '
          'por otro camino: creerse ese campo es pintar «ocupado» sobre un '
          'camión que está en el patio',
    );
    expect(v.libre, isTrue);
    expect(v.etiquetaEstado, 'Disponible');

    // Pero NO se calla que el campo guardado miente: ese campo lo siguen
    // mirando el desplegable del asistente y el del tablero, así que mientras no
    // se limpie este camión sale como ocupado al elegir camión.
    expect(v.estadoGuardadoMiente, isTrue);
  });

  test('con una ruta EN CURSO está en ruta, y se dice cuál', () {
    final v = camion(
      ruta: {'id': 'r1', 'routeCode': 'RT-20260928-001', 'status': 'in_progress'},
    );

    expect(v.andar, AndarDelCamion.enRuta);
    expect(v.libre, isFalse);
    expect(v.etiquetaEstado, 'En ruta');
    expect(v.rutaActiva!.titulo, 'RT-20260928-001');
    expect(v.rutaActiva!.enCurso, isTrue);
  });

  test('con una ruta PLANIFICADA está cogido, que no es lo mismo', () {
    // El propio servidor lo dice en `db/queries/vehicles.sql`: el camión se
    // marca ocupado al DESPACHAR la ruta, no al armarla, «entre que se arma la
    // noche anterior y sale por la mañana el camión sigue disponible para otra
    // cosa». Así que ni libre ni en ruta: la tercera respuesta.
    final v = camion(
      ruta: {'id': 'r1', 'routeCode': 'RT-20260929-004', 'status': 'planned'},
    );

    expect(v.andar, AndarDelCamion.asignado);
    expect(
      v.andar,
      isNot(AndarDelCamion.enRuta),
      reason:
          'juntar «cogido para mañana» con «está fuera ahora» manda a buscar '
          'otro camión a quien tenía uno disponible hasta que salga esa ruta',
    );
    expect(v.libre, isFalse);
    expect(v.etiquetaEstado, 'Con ruta');
    expect(v.rutaActiva!.enCurso, isFalse);
  });

  test('un camión libre y limpio no tiene nada que avisar', () {
    // La mitad que caza un aviso que sale siempre: si `estadoGuardadoMiente`
    // fuera cierto para todos, la tarjeta llevaría un cartel ámbar permanente y
    // dejaría de leerse (`CLAUDE.md` §3-quinquies).
    final v = camion();

    expect(v.andar, AndarDelCamion.libre);
    expect(v.estadoGuardadoMiente, isFalse);
    expect(v.rutaActiva, isNull);
  });

  test('un camión EN RUTA con el campo en `in_use` no avisa de nada raro', () {
    // El caso normal: el campo y la realidad coinciden. Tampoco aquí hay nada
    // que decir.
    final v = camion(
      estadoGuardado: 'in_use',
      ruta: {'id': 'r1', 'routeCode': 'RT-20260928-001', 'status': 'in_progress'},
    );

    expect(v.andar, AndarDelCamion.enRuta);
    expect(v.estadoGuardadoMiente, isFalse);
  });

  test('`maintenance` se reconoce, aunque hoy el servidor no lo pueda mandar', () {
    // El enum `vehicle_status` de la base sólo tiene `available` e `in_use`, y
    // `estadoValido` del servidor rechaza cualquier otra cosa con un 400. Se
    // deja reconocido porque es lo ÚNICO que no se puede deducir —un camión en
    // el taller no tiene ruta, igual que uno libre— y el día que se guarde de
    // verdad esta pantalla ya sabe pintarlo. Mientras tanto no miente: no sale.
    final v = camion(estadoGuardado: 'maintenance');

    expect(v.andar, AndarDelCamion.enMantenimiento);
    expect(v.etiquetaEstado, 'Mantenimiento');
    expect(
      v.libre,
      isFalse,
      reason: 'un camión en el taller no cuenta como flota disponible',
    );
  });

  test('sin el campo `routes` —un servidor viejo— no se inventa nada', () {
    // Las APK y los navegadores hablan con el servidor que haya. Si `routes` no
    // viene, la respuesta honesta es «no hay ruta abierta que yo sepa», no un
    // estado inventado.
    final v = VehiculoDeLaApi.deJson(const <String, Object?>{
      'id': 'v1',
      'name': 'Camión 1',
      'capacity': 1000,
      'status': 'available',
    });

    expect(v.rutaActiva, isNull);
    expect(v.andar, AndarDelCamion.libre);
  });
}
