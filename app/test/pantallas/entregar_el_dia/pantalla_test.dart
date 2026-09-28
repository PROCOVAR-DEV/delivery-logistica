import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/cajon.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/panel/registro.dart';
import 'package:reparto/pantallas/sincronizacion/vista/fila_de_rechazo.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';
import '../traer_el_dia/apoyo_traer_el_dia.dart';

/// EL BOTON DE ENTREGAR EL DIA en la pantalla, a las dos anchuras.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  late RelojFalso reloj;
  late ColaDeSalida cola;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 15, 17, 40));
    cola = ColaDeSalida(base, reloj: reloj.leer);
  });

  tearDown(() => base.close());

  Future<void> encolar(int cuantos) async {
    for (var i = 1; i <= cuantos; i++) {
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/r-$i/results',
        cuerpo: <String, Object?>{'resultado': 'entregado'},
      );
    }
  }

  Future<RespuestaFalsa?> Function(PeticionVista) servidorQueAcepta({
    Set<String> rechazarRutas = const <String>{},
    // LO QUE EL SERVIDOR DEJA FUERA aunque el apunte entre, por ruta del
    // apunte. Es lo que contesta `POST /api/board/columns/{id}/route` en su 201
    // y lo que `sync/internal/sincro/subida.go` reenvía en el resultado.
    Map<String, List<Object?>> descartaEn = const <String, List<Object?>>{},
  }) {
    return (p) async {
      if (!p.ruta.endsWith('/subida')) return servidorQueTraeElDia(p);
      final cuerpo = p.cuerpo! as Map<String, Object?>;
      final apuntes = (cuerpo['apuntes']! as List<Object?>)
          .cast<Map<String, Object?>>();
      return RespuestaFalsa(200, <String, Object?>{
        'resultados': [
          for (final a in apuntes)
            if (rechazarRutas.contains(a['ruta']))
              <String, Object?>{
                'clave': a['clave'],
                'estado': 'rechazado',
                'motivo':
                    '3 de los 8 pedidos ya están en otra ruta. Vuelve a '
                    'elegirlos.',
              }
            else
              <String, Object?>{
                'clave': a['clave'],
                'estado': 'aplicado',
                'descartados': ?descartaEn[a['ruta']],
              },
        ],
      });
    };
  }

  Future<ProviderContainer> montar(
    WidgetTester tester, {
    required Future<RespuestaFalsa?> Function(PeticionVista) responder,
    double ancho = 1440,
    double alto = 1000,
    bool hayPista = true,
  }) async {
    tester.view.physicalSize = Size(ancho, alto);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final caja = montarTraerElDia(
      base: base,
      reloj: reloj.leer,
      responder: responder,
      hayPista: hayPista,
    );
    addTearDown(caja.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: caja,
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarPanel()],
            inicial: '/dashboard',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return caja;
  }

  /// Sin `pumpAndSettle`: mientras corre hay una rueda girando y un cronometro
  /// por segundos, y con eso delante `pumpAndSettle` no vuelve nunca.
  Future<void> dejarCorrer(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  testWidgets('con trabajo dentro, la pieza dice ENVIAR y cuantos', (
    tester,
  ) async {
    await encolar(23);
    await montar(tester, responder: servidorQueAcepta());

    // **Una sola pieza**, no dos botones: con veintitres apuntes dentro del
    // telefono no hay nada que elegir, y lo que se puede perder es eso.
    expect(find.text('Tienes trabajo sin enviar'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Enviar datos (23)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Traer el día'),
      findsNothing,
      reason: 'traer el dia no es lo que toca ahora y no se ofrece',
    );
    await desmontar(tester);

    await montar(tester, responder: servidorQueAcepta(), ancho: 390, alto: 800);
    expect(
      find.widgetWithText(FilledButton, 'Enviar datos (23)'),
      findsOneWidget,
      reason: 'la misma pieza, en el mismo sitio, en el telefono del almacen',
    );
    await desmontar(tester);
  });

  testWidgets('sin nada dentro, lo que toca es TRAER', (tester) async {
    await montar(tester, responder: servidorQueAcepta());

    expect(find.text('Traer el día'), findsWidgets);
    expect(
      find.textContaining('Enviar datos'),
      findsNothing,
      reason:
          'un boton de enviar sin nada que enviar ensena a desconfiar del '
          'que si hace algo',
    );
    await desmontar(tester);
  });

  testWidgets('CON LA CONEXION MALA no se ofrece un boton que va a fallar', (
    tester,
  ) async {
    await encolar(23);
    final caja = await montar(tester, responder: servidorQueAcepta());

    // El estado NO sale de `connectivity_plus`: sale de si las peticiones estan
    // llegando. Con una conexion inestable el aparato CREE que esta conectado, y
    // eso es lo que deja al logistico mirando una rueda sin saber si va a
    // funcionar.
    darLaConexionPorMala(caja);
    await tester.pumpAndSettle();

    expect(find.text('Trabajando sin conexión'), findsOneWidget);
    expect(
      find.byType(FilledButton),
      findsNothing,
      reason:
          'en el patio del almacen no hay nada que elegir: se dice el '
          'estado y de que hora son los datos',
    );
    // Y se dice lo unico que hace falta saber ahi: de cuando son los datos y
    // que queda dentro.
    expect(find.textContaining('23 sin subir'), findsWidgets);
    await desmontar(tester);
  });

  testWidgets('se le da, sube, y al acabar dice CUANTOS subieron', (
    tester,
  ) async {
    await encolar(23);
    await montar(tester, responder: servidorQueAcepta());

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar datos (23)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Cajon, tambien en escritorio.
    expect(find.byType(Cajon), findsOneWidget);
    await dejarCorrer(tester);

    expect(find.text('Subieron 23 apuntes'), findsWidgets);
    expect(find.text('Todo entregado'), findsWidgets);
    await desmontar(tester);
  });

  testWidgets('un rechazo NO deja el dia entregado, y se ve con su motivo', (
    tester,
  ) async {
    await encolar(3);
    await montar(
      tester,
      responder: servidorQueAcepta(rechazarRutas: {'/api/routes/r-2/results'}),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar datos (3)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await dejarCorrer(tester);

    expect(
      find.text('1 rechazado esperando a que alguien decida'),
      findsWidgets,
    );
    // El motivo LITERAL del servidor, en la misma pieza que usa la pantalla de
    // Sincronizacion.
    expect(find.byType(FilaDeRechazo), findsOneWidget);
    expect(
      find.textContaining('ya están en otra ruta'),
      findsOneWidget,
      reason:
          'un apunte rechazado que desaparece en silencio es trabajo '
          'perdido que nadie sabe que perdio',
    );
    await desmontar(tester);
  });

  testWidgets('se cae la subida: dice cuantos quedan y no se pone verde', (
    tester,
  ) async {
    await encolar(23);
    await montar(
      tester,
      responder: (p) async {
        if (p.ruta.endsWith('/subida')) return null;
        return servidorQueTraeElDia(p);
      },
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar datos (23)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await dejarCorrer(tester);

    expect(find.text('Quedan 23 sin subir'), findsWidgets);
    expect(find.text('Todo entregado'), findsNothing);
    expect(
      find.textContaining('lo que no subió sigue entero'),
      findsOneWidget,
      reason: 'y se dice que hacer y que nada se ha perdido',
    );
    await desmontar(tester);
  });

  testWidgets('LO QUE NO VA A SUBIR SOLO sale en el cajón, con su nombre y con '
      'qué hacer', (tester) async {
    // Una ruta armada sin señal que se quedó sin su apunte. No sale en «N sin
    // subir» —no le queda apunte—, ni en la bandeja —nadie la rechazó—, y el
    // desatasco de `huerfanos.dart` sólo sabe rehacer el tablero: **no la sube
    // nadie**. Hasta el 24/09/2026 tampoco la nombraba nadie, y el cajón podía
    // decir «Todo entregado» en verde encima.
    await base
        .into(base.routes)
        .insert(
          RoutesCompanion.insert(
            id: 'local-9f3a2b7c',
            status: const Value('planned'),
          ),
        );
    await encolar(1);
    await montar(tester, responder: servidorQueAcepta());

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar datos (1)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await dejarCorrer(tester);

    expect(
      find.text('Sólo en este aparato: 1 ruta'),
      // DOS: la franja de arriba y el cajón. Los dos sitios donde se mira lo
      // que queda por entregar, que es la misma pregunta.
      findsNWidgets(2),
      reason:
          'se NOMBRA lo que es. Sin esto, el cajón dice «Todo entregado» en '
          'verde con una ruta entera que no existe en el servidor',
    );
    expect(
      find.textContaining('entregar el día no se lo lleva'),
      findsOneWidget,
      reason: 'y se dice por qué: no le queda ningún apunte que lo suba',
    );
    expect(
      find.textContaining('hay que volver a hacerlo con conexión'),
      findsOneWidget,
      reason: 'qué hacer. Sin esto el aviso es una queja',
    );
    await desmontar(tester);
  });

  testWidgets('y SIN nada colgado el cajón no lo nombra: un aviso que sale '
      'siempre deja de leerse', (tester) async {
    await encolar(1);
    await montar(tester, responder: servidorQueAcepta());

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar datos (1)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await dejarCorrer(tester);

    expect(find.textContaining('Sólo en este aparato'), findsNothing);
    expect(
      find.text('Todo entregado'),
      findsWidgets,
      reason: 'lo normal: subió, y no hay nada colgado que contradiga el verde',
    );
    await desmontar(tester);
  });

  testWidgets('el armado que SUBIÓ dejando pedidos fuera sale en el cajón, con '
      'el pedido nombrado y con qué hacer — y sin ofrecer reintentar', (
    tester,
  ) async {
    // El apunte ENTRÓ: la ruta existe arriba. Lo que falta son dos de sus
    // paradas, y el servidor dice cuáles y por qué. Antes esto se tiraba en
    // `ColaDeSalida.resolver` y el cajón decía «Todo entregado» encima.
    await cola.encolar(
      metodo: 'POST',
      ruta: '/api/board/columns/z-vista/route',
      cuerpo: const <String, Object?>{'optimizar': false},
      provisional: 'local-9f3a2b7c',
    );
    await montar(
      tester,
      responder: servidorQueAcepta(
        descartaEn: {
          '/api/board/columns/z-vista/route': [
            <String, Object?>{
              'pedidoId': '0199a1b2-0000-7000-8000-00000000000a',
              'operationNumber': 'X-2992',
              'customerName': 'Ana Pérez',
              'motivo': 'ya no estaba en esa zona cuando llegó tu apunte',
              'queHacer':
                  'comprueba si se entregó igual y míralo antes de que '
                  'salga en otra ruta',
            },
          ],
        },
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar datos (1)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await dejarCorrer(tester);

    // Subió, y eso no se discute: decir que no subió sería mentir al revés.
    expect(find.text('Subieron 1 apunte'), findsWidgets);
    // Y AUN ASÍ se dice que salió con menos.
    expect(find.text('No subió todo al camión'), findsOneWidget);
    expect(
      find.textContaining('X-2992 · Ana Pérez'),
      findsOneWidget,
      reason:
          'se nombra por el FOLIO y el cliente: un uuid no le dice nada a '
          'nadie y no se puede buscar en PEDIDO',
    );
    expect(
      find.textContaining('comprueba si se entregó igual'),
      findsOneWidget,
      reason: 'un aviso sin qué hacer es una queja',
    );
    // NO es un rechazo y no se le ofrece reintentar: el apunte entró y volver a
    // mandarlo armaría una SEGUNDA ruta con el mismo camión.
    expect(find.byType(FilaDeRechazo), findsNothing);
    expect(find.text('Reintentar'), findsNothing);

    // Y una persona puede darlo por leído.
    await tester.tap(find.text('Ya lo he visto'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('No subió todo al camión'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('LO NORMAL NO AVISA: un armado que subió entero no saca nada en '
      'el cajón', (tester) async {
    await cola.encolar(
      metodo: 'POST',
      ruta: '/api/board/columns/z-vista/route',
      cuerpo: const <String, Object?>{'optimizar': false},
      provisional: 'local-9f3a2b7c',
    );
    await montar(tester, responder: servidorQueAcepta());

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar datos (1)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await dejarCorrer(tester);

    expect(find.text('Subieron 1 apunte'), findsWidgets);
    expect(
      find.text('No subió todo al camión'),
      findsNothing,
      reason:
          'nadie se cayó. Un aviso que sale en cada armado deja de leerse, y '
          'entonces tampoco se lee el día que importa (§3-quinquies)',
    );

    await desmontar(tester);
  });
}
