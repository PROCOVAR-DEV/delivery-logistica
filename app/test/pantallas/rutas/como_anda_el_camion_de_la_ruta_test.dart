// CÓMO ANDA EL CAMIÓN DE UNA RUTA — 28/09/2026.
//
// Jose: «si la idea es q salga el vehiculo y ese vehiculo se ponga su estado
// para q saber como anda ese vehiculo y saber de la flota».
//
// La cabecera del detalle y la tarjeta de la lista pintaban «Camión 1 · P-001» y
// se acababa ahí. Ahora dicen además en qué anda, y lo dicen a partir de las
// RUTAS —no de `vehicles.status`, que es un campo que alguien pone y nadie
// quita—: `ConsultasRutas.camionesOcupados`.
//
// Lo que se mide aquí son las CUATRO respuestas, y las cuatro hacen falta:
//
//   1. la consulta no ha llegado → **no se dice nada**. Escribir «libre» sin
//      haberlo comprobado es el cero creíble de siempre con otra cara.
//   2. no lo tiene nadie → «libre», que es la respuesta a «¿puedo despachar
//      ésta ya?».
//   3. lo tiene ESTA ruta → **no se dice nada**. Ya se está mirando, y repetirlo
//      en cada tarjeta es ruido que tapa el caso 4.
//   4. lo tiene OTRA → se dice cuál. Ése es el conflicto: dos rutas con el mismo
//      camión el mismo día, que hasta hoy no se veía por ningún sitio.
//
// El 3 y el 4 son la pareja que importa: un aviso que sale siempre deja de
// leerse, y entonces tampoco se lee el día que importa (`CLAUDE.md`
// §3-quinquies).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';
import 'rutas_a_mano.dart';

void main() {
  Future<void> pintar(
    WidgetTester tester, {
    RutaQueOcupa? ocupa,
    bool seSabe = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LineaDeDatosDeLaRuta(
          ruta: rutaAMano(
            paradas: [paradaAMano(id: 'p1', cliente: 'Ana', costo: 8.0)],
            vehiculo: camionAMano(),
          ),
          ocupacionDelCamion: ocupa,
          seSabeLaOcupacion: seSabe,
        ),
      ),
    ),
  );

  testWidgets('mientras no se sabe, no se dice nada del camión', (tester) async {
    await pintar(tester, seSabe: false);

    // El camión y su matrícula, que ya se pintaban.
    expect(find.textContaining('Camión 1'), findsOneWidget);
    expect(find.textContaining('P-001'), findsOneWidget);
    // Y NADA más: ni «libre» ni «en ruta».
    expect(
      find.textContaining('libre'),
      findsNothing,
      reason:
          'decir «libre» sin haber mirado las rutas es inventarse un dato: el '
          'mismo cero creíble de siempre con otra cara',
    );
  });

  testWidgets('sin ninguna ruta abierta, el camión está libre', (tester) async {
    await pintar(tester);

    expect(find.textContaining('Camión 1 · P-001 · libre'), findsOneWidget);
  });

  testWidgets('si lo tiene ESTA ruta, no se repite', (tester) async {
    // `rutaAMano` es `R1`.
    await pintar(
      tester,
      ocupa: const RutaQueOcupa(
        rutaId: 'R1',
        estado: EstadoRuta.enCurso,
        codigo: 'RT-001',
      ),
    );

    expect(find.textContaining('Camión 1 · P-001 · '), findsOneWidget);
    expect(
      find.textContaining('EN RUTA en'),
      findsNothing,
      reason:
          'es la ruta que se está mirando: decirlo aquí es el aviso que sale '
          'siempre y que por eso deja de leerse',
    );
    expect(find.textContaining('libre'), findsNothing);
  });

  testWidgets('si lo tiene OTRA ruta EN CURSO, se dice cuál', (tester) async {
    await pintar(
      tester,
      ocupa: const RutaQueOcupa(
        rutaId: 'R9',
        estado: EstadoRuta.enCurso,
        codigo: 'RT-20260928-001',
      ),
    );

    expect(
      find.textContaining('EN RUTA en RT-20260928-001'),
      findsOneWidget,
      reason:
          'el camión de esta ruta está fuera con otra: despacharla ahora es '
          'mandar el mismo camión a dos sitios, y eso no se veía por ningún '
          'sitio',
    );
  });

  testWidgets('si otra lo tiene PLANIFICADO, se dice distinto', (tester) async {
    // No es lo mismo: esa otra ruta no ha salido. Se avisa igual —dos rutas con
    // el mismo camión el mismo día— pero con otras palabras, porque se arregla
    // de otra manera: ahí todavía se puede cambiar el camión de una de las dos.
    await pintar(
      tester,
      ocupa: const RutaQueOcupa(
        rutaId: 'R9',
        estado: EstadoRuta.planificada,
        codigo: 'RT-20260929-004',
      ),
    );

    expect(find.textContaining('ya va en RT-20260929-004'), findsOneWidget);
    expect(find.textContaining('EN RUTA en'), findsNothing);
  });

  test('una ruta sin código se nombra por su nombre, y si no, genérica', () {
    expect(
      const RutaQueOcupa(
        rutaId: 'R9',
        estado: EstadoRuta.planificada,
        nombre: 'Centro',
      ).titulo,
      'Centro',
    );
    expect(
      const RutaQueOcupa(
        rutaId: 'R9',
        estado: EstadoRuta.planificada,
      ).titulo,
      'otra ruta',
      reason:
          'sin código ni nombre se dice «otra ruta»: el aviso vale igual, y un '
          'hueco ahí lo dejaría sin sentido',
    );
  });

  // EL ORDEN DE `camionesOcupados`, ATADO CON UNA PRUEBA Y NO CON UN COMENTARIO.
  //
  // Si un camión tuviera DOS rutas abiertas, la que manda es la que está EN
  // CURSO: ésa es la que lo tiene fuera ahora mismo. Una planificada de la
  // semana que viene no puede tapar la que está rodando hoy.
  //
  // El orden se consigue ordenando por el TEXTO del estado (`in_progress` <
  // `planned` en alfabético), que es un apaño que funciona y que se rompe solo si
  // alguien añade un estado abierto nuevo. Por eso esto es una prueba: el
  // comentario del código ya lo avisa, y un comentario no falla (§3-bis).
  test('la ruta EN CURSO manda sobre la planificada del mismo camión', () async {
    final base = baseDePrueba();
    addTearDown(base.close);

    // La planificada se siembra PRIMERO y con fecha anterior, para que sólo el
    // orden por estado pueda dar el resultado bueno.
    await sembrarRuta(
      base,
      id: 'R-plan',
      codigo: 'RT-PLAN',
      estado: EstadoRuta.planificada,
      vehiculoId: 'V1',
      creada: DateTime(2026, 9, 1),
    );
    await sembrarRuta(
      base,
      id: 'R-curso',
      codigo: 'RT-CURSO',
      estado: EstadoRuta.enCurso,
      vehiculoId: 'V1',
      creada: DateTime(2026, 9, 28),
    );
    // Y una CERRADA, que no puede salir por ningún lado.
    await sembrarRuta(
      base,
      id: 'R-fin',
      codigo: 'RT-FIN',
      estado: EstadoRuta.completada,
      vehiculoId: 'V1',
    );

    final porCamion = await ConsultasRutas(base).camionesOcupados().first;

    expect(porCamion.keys, ['V1']);
    expect(
      porCamion['V1']!.rutaId,
      'R-curso',
      reason:
          'la planificada tapó a la que está rodando: la tarjeta diría que el '
          'camión está cogido para mañana cuando en realidad está fuera hoy',
    );
    expect(porCamion['V1']!.enCurso, isTrue);
  });

  test('una ruta cerrada no ocupa a nadie, y una sin camión tampoco', () async {
    final base = baseDePrueba();
    addTearDown(base.close);

    await sembrarRuta(
      base,
      id: 'R-fin',
      estado: EstadoRuta.completada,
      vehiculoId: 'V1',
    );
    await sembrarRuta(
      base,
      id: 'R-cancel',
      estado: EstadoRuta.cancelada,
      vehiculoId: 'V2',
    );
    await sembrarRuta(
      base,
      id: 'R-sinCamion',
      estado: EstadoRuta.enCurso,
      vehiculoId: null,
    );

    expect(
      await ConsultasRutas(base).camionesOcupados().first,
      isEmpty,
      reason:
          'un camión que volvió está libre; y una ruta sin camión no puede '
          'ocupar a ninguno —ni con una clave nula en el mapa, que reventaría al '
          'buscarla',
    );
  });
}
