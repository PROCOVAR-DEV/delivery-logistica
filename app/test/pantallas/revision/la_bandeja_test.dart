// LA BANDEJA DEL REVISOR, montada de verdad sobre el armazon y contra un `sync`
// de mentira CON ESTADO (`apoyo_revision.dart`).
//
// Lo que ata, y por que cada cosa (docs/bandeja-de-revision.md, B.2-B.4):
//
//  * se ve QUIEN entrego, desde QUE aparato, y por apunte el metodo, la ruta, la
//    hora del aparato y el cuerpo EXACTO (colapsado);
//  * "Aplicado" NO se pinta antes de la respuesta del servidor;
//  * el "no" del reparto sale con su LITERAL y el apunte sigue esperando
//    decision;
//  * descartar exige motivo, en un cajon, y no sale ni una peticion sin el;
//  * nadie revisa lo suyo; un logistico no revisa;
//  * un error NO es una bandeja vacia.
//
// Las pruebas van EN PAREJA (CLAUDE.md §3-quinquies): cada "no aparece" tiene su
// gemela de "si aparece cuando toca". Y se siembra DENTRO del cuerpo, no en
// `setUp` (§5).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/insignia.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/menu_de_cuenta.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/revision/datos/bandeja.dart';
import 'package:reparto/pantallas/revision/datos/que_hace.dart';
import 'package:reparto/pantallas/revision/datos/quien_revisa.dart';
import 'package:reparto/pantallas/revision/estado/proveedores_revision.dart';
import 'package:reparto/pantallas/revision/registro.dart';
import 'package:reparto/pantallas/revision/vista/pantalla_revision.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo_revision.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  late SyncDeRevisionFalso servidor;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Map<String, Object?> dosApuntes({String persona = 'yasmani'}) => entregaJson(
    persona: persona,
    apuntes: [
      apunteJson(clave: 'c1', orden: 1),
      apunteJson(
        clave: 'c2',
        orden: 2,
        ruta: '/api/routes/r-2/results',
        cuerpo: '{"x":1}',
      ),
    ],
  );

  Future<void> montar(
    WidgetTester tester, {
    required SyncDeRevisionFalso con,
    Sesion quien = revisora,
    Size tamano = const Size(1440, 1600),
  }) async {
    servidor = con;
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 10, 9, 9, 0)),
          clienteDeRevisionProvider.overrideWithValue(clienteDeRevision(con)),
          sesionParaElMenuProvider.overrideWith((ref) async => quien),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarRevision()],
            // La constante, no el literal (§5).
            inicial: PantallaRevision.ruta,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Future<void> abrirLaEntrega(WidgetTester tester) async {
    await tester.tap(find.text('Yasmani Cruz'));
    await tester.pumpAndSettle();
  }

  /// El boton de confirmar del recuento de «Aplicar todo en orden» («Aplicar N
  /// cambios»); se pulsa despues de abrir el cajon.
  Future<void> confirmarTodo(WidgetTester tester) async {
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            (w is BotonPrincipal &&
                w.texto.startsWith('Aplicar ') &&
                w.texto.contains('cambio')) ||
            (w is BotonDestructivo &&
                w.texto.startsWith('Aplicar ') &&
                w.texto.contains('cambio')),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder boton(Type tipo, String texto) => find.widgetWithText(
    tipo == BotonPrincipal ? BotonPrincipal : BotonDestructivo,
    texto,
  );

  bool habilitado(WidgetTester tester, Finder f) {
    final boton = find.descendant(
      of: f,
      matching: find.byWidgetPredicate(
        (w) => w is FilledButton || w is OutlinedButton,
      ),
    );
    final w = tester.widget(boton.first);
    return (w is FilledButton
            ? w.onPressed
            : (w as OutlinedButton).onPressed) !=
        null;
  }

  bool hayInsignia(WidgetTester tester, String texto) => tester
      .widgetList<Insignia>(find.byType(Insignia))
      .any((i) => i.texto == texto);

  String hora(String iso) =>
      DateFormat('d/M, H:mm', 'es').format(DateTime.parse(iso).toLocal());

  group('lo que se ve', () {
    testWidgets('la lista dice quien entrego, desde que aparato, por sucursal '
        'y cuantos esperan', (tester) async {
      await montar(tester, con: SyncDeRevisionFalso([dosApuntes()]));

      // `sync` no manda el nombre de la sucursal: sin su copia, el uuid corto.
      expect(find.text('5d6e7f80'), findsOneWidget);
      expect(find.text('Yasmani Cruz'), findsOneWidget);
      expect(find.textContaining('Teléfono de Yasmani'), findsOneWidget);
      expect(find.textContaining(hora('2026-10-08T20:10:00Z')), findsOneWidget);
      // El contador: apuntes que esperan una decision.
      expect(find.text('Esperan una decisión'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      // Los apuntes NO se piden hasta abrir la entrega (pueden ser cientos de KB).
      expect(servidor.cuantas('GET', '/sync/revision/e-1'), 0);
      expect(servidor.cuantas('GET', '/sync/revision'), 1);

      await desmontar(tester);
    });

    testWidgets('abierta: metodo, ruta, hora del aparato; el cuerpo, colapsado '
        'y EXACTO', (tester) async {
      await montar(tester, con: SyncDeRevisionFalso([dosApuntes()]));
      await abrirLaEntrega(tester);

      expect(find.text('POST /api/routes/r-1/results'), findsOneWidget);
      expect(find.text('POST /api/routes/r-2/results'), findsOneWidget);
      expect(
        find.text('Hecho en el aparato el ${hora('2026-10-08T14:32:00Z')}'),
        findsNWidgets(2),
      );

      // Colapsado: el cuerpo no esta en pantalla.
      expect(find.text(cuerpoExacto), findsNothing);
      await tester.tap(find.text('Cuerpo exacto').first);
      await tester.pumpAndSettle();
      // Y al abrirlo es el texto que llego, con sus espacios dobles: no un JSON
      // vuelto a serializar.
      expect(find.text(cuerpoExacto), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('a 390 px no desborda con la entrega abierta', (tester) async {
      await montar(
        tester,
        con: SyncDeRevisionFalso([dosApuntes()]),
        tamano: const Size(390, 1600),
      );
      await abrirLaEntrega(tester);
      await tester.tap(find.text('Cuerpo exacto').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Aplicar todo en orden'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('un ERROR no es una bandeja vacia, y vacia dice que esta '
        'vacia', (tester) async {
      final sinRed = SyncDeRevisionFalso([dosApuntes()])..sinRed = true;
      await montar(tester, con: sinRed);
      expect(find.text(TextosDeRevision.sinConexion), findsOneWidget);
      expect(find.text(TextosDeRevision.vacia), findsNothing);
      await desmontar(tester);

      await montar(tester, con: SyncDeRevisionFalso(const []));
      expect(find.text(TextosDeRevision.vacia), findsOneWidget);
      expect(find.text(TextosDeRevision.sinConexion), findsNothing);
      await desmontar(tester);
    });
  });

  group('aplicar', () {
    testWidgets('«Aplicado» NO se pinta antes de la respuesta del servidor', (
      tester,
    ) async {
      final con = SyncDeRevisionFalso([dosApuntes()])
        ..puerta = Completer<void>();
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicar).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // La orden SALIO, el servidor aun no ha contestado…
      expect(con.cuantas('POST', '/revision/ap-1/c1/aplicar'), 1);
      // …y la pantalla NO dice que esta aplicado: dice que se esta aplicando.
      expect(hayInsignia(tester, 'Aplicado'), isFalse);
      expect(find.textContaining('Aplicado por'), findsNothing);
      expect(find.text(TextosDeRevision.aplicando), findsOneWidget);
      // Y no se puede pulsar otra vez (doble clic = dos ordenes).
      expect(
        habilitado(
          tester,
          find.widgetWithText(BotonPrincipal, TextosDeRevision.aplicando),
        ),
        isFalse,
      );

      con.puerta!.complete();
      await tester.pumpAndSettle();

      // Ahora si: sale de lo que el servidor dice al releer.
      expect(hayInsignia(tester, 'Aplicado'), isTrue);
      expect(find.textContaining('Aplicado por Marta Pérez'), findsOneWidget);
      expect(con.cuantas('POST', '/revision/ap-1/c1/aplicar'), 1);
      // Lo aplicado ya no se ofrece otra vez: solo queda «Aplicar» en c2.
      expect(boton(BotonPrincipal, TextosDeRevision.aplicar), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('el «no» del reparto llega como 200 `rechazado`: sale con su '
        'LITERAL y el apunte sigue esperando decision', (tester) async {
      const literal = 'Ese pedido ya va en otra ruta (conduce 1480).';
      final con = SyncDeRevisionFalso([dosApuntes()])
        ..rechazaConElLiteral['c1'] = literal;
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicar).first);
      await tester.pumpAndSettle();

      expect(find.text(literal), findsOneWidget);
      expect(hayInsignia(tester, 'Rechazado'), isTrue);
      expect(hayInsignia(tester, 'Aplicado'), isFalse);
      expect(find.text(TextosDeRevision.sigueEsperando), findsOneWidget);
      // Sigue esperando decision: se puede reintentar o descartar.
      expect(
        boton(BotonPrincipal, TextosDeRevision.reintentar),
        findsOneWidget,
      );
      expect(boton(BotonDestructivo, TextosDeRevision.descartar), findsWidgets);

      await desmontar(tester);
    });

    testWidgets(
      'un 409 `ya_se_esta_aplicando` se dice con su literal (quien lo '
      'tiene) y el apunte no cambia',
      (tester) async {
        final con = SyncDeRevisionFalso([dosApuntes()]);
        await montar(tester, con: con);
        await abrirLaEntrega(tester);
        // Otro revisor se adelanta: cuando llega nuestra orden, c1 ya se esta
        // aplicando (el servidor no deja aplicarlo dos veces a la vez).
        ((con.entregas.first['apuntes']! as List<Object?>).first!
                as Map<String, Object?>)['estado'] =
            'aplicando';

        await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicar).first);
        await tester.pumpAndSettle();

        expect(
          find.text('Lo está aplicando Marta Pérez desde las 8:50.'),
          findsOneWidget,
        );
        expect(hayInsignia(tester, 'Aplicado'), isFalse);
        expect(hayInsignia(tester, 'Rechazado'), isFalse);

        await desmontar(tester);
      },
    );

    testWidgets(
      'un 502 `reparto_no_disponible` es una CAIDA, no un rechazo: se '
      'dice que el reparto no contesto, el apunte sigue en revision y no se '
      'repite solo',
      (tester) async {
        final con = SyncDeRevisionFalso([dosApuntes()])..repartoCaido.add('c1');
        await montar(tester, con: con);
        await abrirLaEntrega(tester);

        await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicar).first);
        await tester.pumpAndSettle();

        expect(find.textContaining('El reparto no contestó'), findsOneWidget);
        expect(find.textContaining('Inténtalo de nuevo'), findsOneWidget);
        // NO esta rechazado: sigue «En revisión», con su boton «Aplicar» de siempre.
        expect(hayInsignia(tester, 'Rechazado'), isFalse);
        expect(hayInsignia(tester, 'En revisión'), isTrue);
        expect(find.text(TextosDeRevision.sigueEsperando), findsNothing);
        expect(
          boton(BotonPrincipal, TextosDeRevision.aplicar),
          findsNWidgets(2),
        );
        // Y la red NO repitio la orden a escondidas (un 5xx se reintenta por
        // defecto): UNA sola peticion.
        expect(con.cuantas('POST', '/c1/aplicar'), 1);

        await desmontar(tester);
      },
    );

    testWidgets('un 500 `no_se_pudo_anotar` dice que no se sabe si se aplico: '
        'comprueba la ruta a mano, y tampoco se repite solo', (tester) async {
      final con = SyncDeRevisionFalso([dosApuntes()])..noSePudoAnotar.add('c1');
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicar).first);
      await tester.pumpAndSettle();

      expect(find.textContaining('No se sabe si se aplicó'), findsOneWidget);
      expect(
        find.textContaining('Se aplicó en el reparto pero no se pudo anotar.'),
        findsOneWidget,
      );
      expect(con.cuantas('POST', '/c1/aplicar'), 1);

      await desmontar(tester);
    });

    testWidgets('aplicar todo en orden SE DETIENE en el primer fallo, y la '
        'pantalla dice donde, por que (literal) y cuantos quedan', (
      tester,
    ) async {
      const literal = 'El pedido ya no esta en esa ruta.';
      final con = SyncDeRevisionFalso([
        entregaJson(
          apuntes: [
            apunteJson(clave: 'c1', orden: 1),
            apunteJson(clave: 'c2', orden: 2, ruta: '/api/routes/r-2/results'),
            apunteJson(clave: 'c3', orden: 3, ruta: '/api/routes/r-3/results'),
            apunteJson(clave: 'c4', orden: 4, ruta: '/api/routes/r-4/results'),
          ],
        ),
      ])..rechazaConElLiteral['c2'] = literal;
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicarTodo));
      await tester.pumpAndSettle();
      await confirmarTodo(tester);

      expect(con.cuantas('POST', '/sync/revision/e-1/aplicar'), 1);
      expect(
        con.cuantas('POST', '/ap-1/'),
        0,
        reason: 'fue UNA orden en orden',
      );
      // c1 aplicado; c2 rechazado con su literal; c3 y c4 SIN TOCAR.
      expect(hayInsignia(tester, 'Aplicado'), isTrue);
      expect(hayInsignia(tester, 'Rechazado'), isTrue);
      expect(find.text(literal), findsWidgets);
      expect(
        tester
            .widgetList<Insignia>(find.byType(Insignia))
            .where((i) => i.texto == 'En revisión'),
        hasLength(2),
        reason: 'c3 y c4 no se procesaron',
      );
      // Y se DICE: donde se paro, por que y cuantos quedan.
      expect(
        find.textContaining(
          'Aplicar todo se detuvo en POST /api/routes/r-2/results',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Quedan 2 apuntes sin procesar'),
        findsOneWidget,
      );
      expect(find.textContaining('Motivo: $literal'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('EN PAREJA: si no falla nada, aplicar todo aplica todo y no '
        'dice que se detuvo', (tester) async {
      final con = SyncDeRevisionFalso([dosApuntes()]);
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicarTodo));
      await tester.pumpAndSettle();
      await confirmarTodo(tester);

      expect(find.textContaining('Aplicar todo se detuvo'), findsNothing);
      expect(find.textContaining('sin procesar'), findsNothing);
      expect(
        tester
            .widgetList<Insignia>(find.byType(Insignia))
            .where((i) => i.texto == 'Aplicado'),
        hasLength(2),
      );
      // Y ya no queda nada que aplicar: el boton de «todo» se va.
      expect(find.text(TextosDeRevision.aplicarTodo), findsNothing);

      await desmontar(tester);
    });
  });

  group('un apunte interrumpido', () {
    SyncDeRevisionFalso conInterrumpido({required bool interrumpido}) =>
        SyncDeRevisionFalso([
          entregaJson(
            apuntes: [
              apunteJson(
                clave: 'c1',
                estado: 'aplicando',
                interrumpido: interrumpido,
              ),
            ],
          ),
        ]);

    testWidgets(
      '`interrumpido` dice «comprueba a mano» y ofrece reintentar CON '
      'confirmacion; la peticion lleva la bandera',
      (tester) async {
        final con = conInterrumpido(interrumpido: true);
        await montar(tester, con: con);
        await abrirLaEntrega(tester);

        expect(find.text(TextosDeRevision.interrumpido), findsOneWidget);
        // Aplicar normal, ni se ofrece: el apunte no espera decision.
        expect(find.text(TextosDeRevision.aplicar), findsNothing);

        await tester.tap(
          boton(BotonPrincipal, TextosDeRevision.reintentarInterrumpido),
        );
        await tester.pumpAndSettle();
        // Primero se EXPLICA, y mientras no se confirme no sale nada.
        expect(find.text(TextosDeRevision.reintentarTitulo), findsOneWidget);
        expect(con.cuantas('POST', 'aplicar'), 0);

        await tester.tap(
          boton(BotonDestructivo, TextosDeRevision.reintentarConfirma),
        );
        await tester.pumpAndSettle();

        final pedida = con.quePidieron.singleWhere((p) => p.metodo == 'POST');
        expect(pedida.ruta, '/sync/revision/ap-1/c1/aplicar');
        expect(pedida.cuerpo, {'reintentarInterrumpido': true});
        expect(hayInsignia(tester, 'Aplicado'), isTrue);

        await desmontar(tester);
      },
    );

    testWidgets('cerrar la confirmacion sin contestar es NO: no sale nada', (
      tester,
    ) async {
      final con = conInterrumpido(interrumpido: true);
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await tester.tap(
        boton(BotonPrincipal, TextosDeRevision.reintentarInterrumpido),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextosDeRevision.reintentarNo));
      await tester.pumpAndSettle();

      expect(con.cuantas('POST', 'aplicar'), 0);
      expect(hayInsignia(tester, 'Aplicado'), isFalse);

      await desmontar(tester);
    });

    testWidgets(
      'cerrar el cajon con Escape (sin contestar) es NO: no sale nada',
      (tester) async {
        final con = conInterrumpido(interrumpido: true);
        await montar(tester, con: con);
        await abrirLaEntrega(tester);

        await tester.tap(
          boton(BotonPrincipal, TextosDeRevision.reintentarInterrumpido),
        );
        await tester.pumpAndSettle();
        expect(find.text(TextosDeRevision.reintentarTitulo), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.text(TextosDeRevision.reintentarTitulo), findsNothing);
        expect(con.cuantas('POST', 'aplicar'), 0);

        await desmontar(tester);
      },
    );

    testWidgets(
      'EN PAREJA: un `aplicando` que NO esta interrumpido no se puede '
      'reintentar: se esta aplicando ahora',
      (tester) async {
        final con = conInterrumpido(interrumpido: false);
        await montar(tester, con: con);
        await abrirLaEntrega(tester);

        expect(find.text(TextosDeRevision.aplicandoAhora), findsOneWidget);
        expect(find.text(TextosDeRevision.interrumpido), findsNothing);
        expect(
          find.text(TextosDeRevision.reintentarInterrumpido),
          findsNothing,
        );
        expect(find.text(TextosDeRevision.aplicar), findsNothing);

        await desmontar(tester);
      },
    );

    testWidgets('el «Aplicar» de siempre NUNCA manda la bandera', (
      tester,
    ) async {
      final con = SyncDeRevisionFalso([dosApuntes()]);
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicar).first);
      await tester.pumpAndSettle();

      expect(
        con.quePidieron.singleWhere((p) => p.metodo == 'POST').cuerpo,
        isNull,
      );

      await desmontar(tester);
    });
  });

  group('la lista', () {
    testWidgets('truncada: avisa de que hay mas de las que se ven', (
      tester,
    ) async {
      final con = SyncDeRevisionFalso([dosApuntes()])..listaTruncada = true;
      await montar(tester, con: con);
      expect(find.text(TextosDeRevision.truncada), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('EN PAREJA: sin truncar, no avisa', (tester) async {
      await montar(tester, con: SyncDeRevisionFalso([dosApuntes()]));
      expect(find.text(TextosDeRevision.truncada), findsNothing);
      await desmontar(tester);
    });

    testWidgets('la sucursal sale con el nombre que la app ya conoce, cuando '
        'lo conoce', (tester) async {
      await montar(tester, con: SyncDeRevisionFalso([dosApuntes()]));
      Finder encabezado() => find.descendant(
        of: find.byType(PantallaRevision),
        matching: find.text('Camagüey'),
      );
      expect(encabezado(), findsNothing);

      // La copia de sucursales llega DESPUES de montar (§3-ter): la cabecera se
      // entera sin volver a montar nada.
      await base
          .into(base.branches)
          .insert(
            BranchesCompanion.insert(
              id: sucursalDePrueba,
              name: 'Camagüey',
              lat: 21.38,
              lng: -77.91,
            ),
          );
      await tester.pumpAndSettle();

      // (el selector de sucursal de la barra tambien la nombra: se mira SOLO
      // dentro de la pantalla)
      expect(encabezado(), findsOneWidget);
      await desmontar(tester);
    });
  });

  group('descartar', () {
    testWidgets('el motivo es OBLIGATORIO: sin el no sale ni una peticion', (
      tester,
    ) async {
      final con = SyncDeRevisionFalso([dosApuntes()]);
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await tester.tap(
        boton(BotonDestructivo, TextosDeRevision.descartar).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(TextosDeRevision.descartarTitulo), findsOneWidget);

      final confirmar = boton(
        BotonDestructivo,
        TextosDeRevision.descartarConMotivo,
      );
      expect(habilitado(tester, confirmar), isFalse, reason: 'vacio');
      await tester.tap(confirmar);
      await tester.pump();
      expect(con.cuantas('POST', 'descartar'), 0);

      // Cuatro caracteres no son un motivo (el servidor exige 5), ni los
      // espacios de relleno.
      await tester.enterText(find.byType(TextField), '  ab c  ');
      await tester.pump();
      expect(habilitado(tester, confirmar), isFalse, reason: 'corto');
      await tester.tap(confirmar);
      await tester.pump();
      expect(con.cuantas('POST', 'descartar'), 0);

      await tester.enterText(find.byType(TextField), 'Ya lo hizo Marta a mano');
      await tester.pump();
      expect(habilitado(tester, confirmar), isTrue);
      await tester.tap(confirmar);
      await tester.pumpAndSettle();

      expect(con.cuantas('POST', 'descartar'), 1);
      final pedida = con.quePidieron.firstWhere(
        (p) => p.ruta.endsWith('descartar'),
      );
      expect(pedida.ruta, '/sync/revision/ap-1/c1/descartar');
      expect(pedida.cuerpo, {'motivo': 'Ya lo hizo Marta a mano'});
      // El cajon se cerro y el apunte NO se borro: queda descartado, con motivo.
      expect(find.text(TextosDeRevision.descartarTitulo), findsNothing);
      expect(hayInsignia(tester, 'Descartado'), isTrue);
      expect(
        find.textContaining('Motivo: Ya lo hizo Marta a mano'),
        findsOneWidget,
      );

      await desmontar(tester);
    });

    testWidgets('si el servidor dice que no, el cajon sigue abierto y lo dice '
        'con su literal', (tester) async {
      final con = SyncDeRevisionFalso(
        [dosApuntes()],
      )..noDejaDescartar = 'No puedes descartar lo que otro ya está aplicando.';
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await tester.tap(
        boton(BotonDestructivo, TextosDeRevision.descartar).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'No corresponde a esta ruta',
      );
      await tester.pump();
      await tester.tap(
        boton(BotonDestructivo, TextosDeRevision.descartarConMotivo),
      );
      await tester.pumpAndSettle();

      expect(find.text(TextosDeRevision.descartarTitulo), findsOneWidget);
      expect(
        find.text('No puedes descartar lo que otro ya está aplicando.'),
        findsOneWidget,
      );
      expect(hayInsignia(tester, 'Descartado'), isFalse);

      await desmontar(tester);
    });
  });

  group('quien puede decidir', () {
    testWidgets('NADIE REVISA LO SUYO: el autor no ve Aplicar ni Descartar, y '
        'se le dice por que', (tester) async {
      await montar(
        tester,
        con: SyncDeRevisionFalso([dosApuntes(persona: 'marta')]),
      );
      await abrirLaEntrega(tester);

      expect(find.text(TextosDeRevision.esLoTuyo), findsOneWidget);
      expect(find.text(TextosDeRevision.aplicar), findsNothing);
      expect(find.text(TextosDeRevision.aplicarTodo), findsNothing);
      expect(find.text(TextosDeRevision.descartar), findsNothing);
      // Lo ve (para saber que pasa con lo suyo): solo que no decide.
      expect(find.text('POST /api/routes/r-1/results'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('EN PAREJA: si la entrega es de OTRA persona, las tres '
        'acciones estan', (tester) async {
      await montar(tester, con: SyncDeRevisionFalso([dosApuntes()]));
      await abrirLaEntrega(tester);

      expect(find.text(TextosDeRevision.esLoTuyo), findsNothing);
      expect(boton(BotonPrincipal, TextosDeRevision.aplicar), findsNWidgets(2));
      expect(
        boton(BotonPrincipal, TextosDeRevision.aplicarTodo),
        findsOneWidget,
      );
      expect(
        boton(BotonDestructivo, TextosDeRevision.descartar),
        findsNWidgets(2),
      );

      await desmontar(tester);
    });

    testWidgets('sin saber QUIEN eres no se decide (falla cerrado): el sub '
        'vacio no puede cumplir «nadie revisa lo suyo»', (tester) async {
      await montar(
        tester,
        con: SyncDeRevisionFalso([dosApuntes()]),
        quien: conRol('ADMINISTRADOR', sub: ''),
      );
      await abrirLaEntrega(tester);

      expect(find.text(TextosDeRevision.noSeQuienEres), findsOneWidget);
      expect(find.text(TextosDeRevision.aplicar), findsNothing);
      expect(find.text(TextosDeRevision.descartar), findsNothing);

      await desmontar(tester);
    });

    for (final rol in ['LOGISTICO', 'GESTOR', 'OPERADOR']) {
      testWidgets('un $rol NO revisa: lo dice y no pide nada al servidor', (
        tester,
      ) async {
        final con = SyncDeRevisionFalso([dosApuntes()]);
        await montar(tester, con: con, quien: conRol(rol));

        expect(find.text(TextosDeRevision.noRevisas), findsOneWidget);
        expect(find.text(TextosDeRevision.aplicar), findsNothing);
        expect(find.text('Yasmani Cruz'), findsNothing);
        expect(con.quePidieron, isEmpty);

        await desmontar(tester);
      });
    }

    for (final rol in ['ADMINISTRADOR', 'SUPER ADMIN', 'DESARROLLADOR']) {
      testWidgets('EN PAREJA: un $rol SI ve la bandeja', (tester) async {
        final con = SyncDeRevisionFalso([dosApuntes()]);
        await montar(tester, con: con, quien: conRol(rol));

        expect(find.text('Yasmani Cruz'), findsOneWidget);
        expect(find.text(TextosDeRevision.noRevisas), findsNothing);
        expect(con.cuantas('GET', '/sync/revision'), 1);

        await desmontar(tester);
      });
    }

    test('segunda cerradura: el controlador tampoco aplica si quien llama es '
        'el autor o no revisa, aunque alguien le pulse un boton que no '
        'debia estar', () async {
      for (final quien in [
        conRol('LOGISTICO'),
        conRol('ADMINISTRADOR', sub: 'yasmani'),
      ]) {
        final con = SyncDeRevisionFalso([dosApuntes()]);
        final c = ProviderContainer(
          overrides: [
            clienteDeRevisionProvider.overrideWithValue(clienteDeRevision(con)),
            sesionParaElMenuProvider.overrideWith((ref) async => quien),
          ],
        );
        addTearDown(c.dispose);
        final e = await c.read(repositorioRevisionProvider).detalle('e-1');
        final notifier = c.read(decisionesDelRevisorProvider.notifier);

        await notifier.aplicar(e, e.apuntes.first);
        await notifier.aplicarTodo(e);
        expect(
          await notifier.descartar(e, e.apuntes.first, 'un motivo valido'),
          isNotNull,
        );

        expect(
          con.cuantas('POST', '/revision'),
          0,
          reason: '${quien.rol} / ${quien.sub}',
        );
      }
    });
  });

  group('lo que hace cada ruta, en palabras', () {
    const id = 'c3a1f0d2-7b1e-4a53-9a64-0e2f5d8b9c11';

    test('la tabla: lo que la cola emite de verdad, y lo que no se reconoce '
        'se queda crudo (null, nada inventado)', () {
      const casos = <(String, String, String?)>[
        ('POST', '/routes', 'Crear una ruta'),
        ('PATCH', '/routes/$id', 'Modificar una ruta'),
        ('DELETE', '/routes/$id', 'Borrar una ruta'),
        ('DELETE', '/routes/$id/stops/o-1', 'Quitar una parada de una ruta'),
        ('POST', '/routes/$id/results', 'Registrar el resultado de una ruta'),
        ('POST', '/board/columns?branchId=b1', 'Crear una zona'),
        ('PATCH', '/board/columns/$id', 'Modificar una zona'),
        ('DELETE', '/board/columns/$id?destino=x', 'Borrar una zona'),
        ('PUT', '/board/columns/orden?branchId=b1', 'Reordenar las zonas'),
        ('POST', '/board/columns/$id/route', 'Crear una ruta desde una zona'),
        ('PUT', '/board/placements/o-1', 'Mover un pedido a una zona'),
        ('DELETE', '/board/placements/o-1', 'Sacar un pedido de una zona'),
        // Con `/api` delante y el metodo en minusculas: igual.
        ('delete', '/api/routes/$id', 'Borrar una ruta'),
        // NO se reconoce: ni se inventa.
        ('DELETE', '/routes', null),
        ('POST', '/routes/$id/otra-cosa', null),
        ('GET', '/routes/$id', null),
        ('DELETE', '/admin/recompute', null),
        ('POST', '/routes/$id/results/extra', null),
      ];
      for (final (metodo, ruta, esperado) in casos) {
        expect(queHace(metodo, ruta), esperado, reason: '$metodo $ruta');
      }
    });

    test('el recuento cuenta bien: por metodo, por tipo y rutas distintas, y '
        'salta lo ya decidido', () {
      final r = ResumenDeAplicar.de([
        for (var i = 0; i < 3; i++)
          ApunteEnRevision.deJson(
            apunteJson(clave: 'd$i', metodo: 'DELETE', ruta: '/routes/r$i'),
          ),
        for (var i = 0; i < 12; i++)
          ApunteEnRevision.deJson(
            apunteJson(clave: 'p$i', ruta: '/routes/r${i % 4}/results'),
          ),
        // Estos tres NO cuentan: ya estan decididos o aplicandose.
        ApunteEnRevision.deJson(apunteJson(clave: 'x1', estado: 'aplicado')),
        ApunteEnRevision.deJson(apunteJson(clave: 'x2', estado: 'descartado')),
        ApunteEnRevision.deJson(apunteJson(clave: 'x3', estado: 'aplicando')),
        // Un rechazado SI: «aplicar todo» lo reintenta.
        ApunteEnRevision.deJson(apunteJson(clave: 'x4', estado: 'rechazado')),
      ]);

      expect(r.total, 16);
      expect(r.porMetodo, {'DELETE': 3, 'POST': 13});
      expect(r.borrados, 3);
      expect(r.porTipo['DELETE|Borrar una ruta'], 3);
      expect(r.porTipo['POST|Registrar el resultado de una ruta'], 13);
      // Rutas exactas distintas: 3 DELETE + 4 de resultados + la del rechazado.
      expect(r.rutas.length, 8);
      expect(
        r.metodosOrdenados.first.key,
        'DELETE',
        reason: 'lo que borra, primero',
      );
    });

    test(
      'el segundo paso: cualquier DELETE, o mas de 25; hasta 25 de POST no',
      () {
        ResumenDeAplicar de(int posts, {int deletes = 0}) =>
            ResumenDeAplicar.de([
              for (var i = 0; i < posts; i++)
                ApunteEnRevision.deJson(apunteJson(clave: 'p$i')),
              for (var i = 0; i < deletes; i++)
                ApunteEnRevision.deJson(
                  apunteJson(
                    clave: 'd$i',
                    metodo: 'DELETE',
                    ruta: '/routes/r$i',
                  ),
                ),
            ]);

        expect(de(25).exigeEscribirElNumero, isFalse, reason: '25 no exige');
        expect(de(26).exigeEscribirElNumero, isTrue, reason: '26 si');
        expect(
          de(5, deletes: 1).exigeEscribirElNumero,
          isTrue,
          reason: '1 DELETE',
        );
        expect(de(1).exigeEscribirElNumero, isFalse);
      },
    );

    testWidgets('la fila dice QUE HACE ademas del crudo; lo que no reconoce, '
        'solo el crudo', (tester) async {
      final con = SyncDeRevisionFalso([
        entregaJson(
          apuntes: [
            apunteJson(clave: 'c1', metodo: 'DELETE', ruta: '/routes/$id'),
            apunteJson(clave: 'c2', orden: 2, ruta: '/routes/$id/otra-cosa'),
          ],
        ),
      ]);
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      expect(find.text('Borrar una ruta'), findsOneWidget);
      expect(find.text('DELETE /routes/$id'), findsOneWidget);
      // El desconocido: crudo y nada mas (ni «Crear…», ni «Registrar…»).
      expect(find.text('POST /routes/$id/otra-cosa'), findsOneWidget);
      for (final texto in [
        'Crear una ruta',
        'Registrar el resultado de una ruta',
        'Modificar una ruta',
      ]) {
        expect(find.text(texto), findsNothing, reason: texto);
      }

      await desmontar(tester);
    });
  });

  group('aplicar en bloque pide confirmar', () {
    const id = 'c3a1f0d2-7b1e-4a53-9a64-0e2f5d8b9c11';

    SyncDeRevisionFalso conApuntes({int posts = 0, int deletes = 0}) =>
        SyncDeRevisionFalso([
          entregaJson(
            apuntes: [
              for (var i = 0; i < deletes; i++)
                apunteJson(
                  clave: 'd$i',
                  orden: i + 1,
                  metodo: 'DELETE',
                  ruta: '/routes/$id',
                ),
              for (var i = 0; i < posts; i++)
                apunteJson(
                  clave: 'p$i',
                  orden: deletes + i + 1,
                  ruta: '/routes/$id/results',
                ),
            ],
          ),
        ]);

    Finder botonDeConfirmar() => find.byWidgetPredicate(
      (w) =>
          (w is BotonPrincipal || w is BotonDestructivo) &&
          ((w is BotonPrincipal &&
                  w.texto.startsWith('Aplicar ') &&
                  w.texto.contains('cambio')) ||
              (w is BotonDestructivo &&
                  w.texto.startsWith('Aplicar ') &&
                  w.texto.contains('cambio'))),
    );

    Future<void> pulsarAplicarTodo(WidgetTester tester) async {
      await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicarTodo));
      await tester.pumpAndSettle();
    }

    testWidgets('«Aplicar todo» NO aplica: abre el recuento, y solo aplica si '
        'se confirma', (tester) async {
      final con = conApuntes(posts: 2);
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await pulsarAplicarTodo(tester);

      expect(
        find.text(
          'Vas a aplicar 2 cambios: 2 POST. Se ejecutan con tu autoridad, en '
          'orden, y se detiene en el primero que falle.',
        ),
        findsOneWidget,
      );
      expect(con.cuantas('POST', 'aplicar'), 0, reason: 'sin confirmar, nada');

      // «No» tampoco.
      await tester.tap(find.text(TextosDeRevision.noAplicarTodo));
      await tester.pumpAndSettle();
      expect(con.cuantas('POST', 'aplicar'), 0);

      // Hasta 25 sin DELETE: sin segundo paso (no hay campo para escribir).
      await pulsarAplicarTodo(tester);
      expect(find.byType(TextField), findsNothing);
      expect(habilitado(tester, botonDeConfirmar()), isTrue);
      await tester.tap(botonDeConfirmar());
      await tester.pumpAndSettle();

      expect(con.cuantas('POST', '/sync/revision/e-1/aplicar'), 1);

      await desmontar(tester);
    });

    testWidgets('cerrar el recuento sin contestar (Escape) es NO', (
      tester,
    ) async {
      final con = conApuntes(posts: 2);
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await pulsarAplicarTodo(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text(TextosDeRevision.aplicarTodoTitulo), findsNothing);
      expect(con.cuantas('POST', 'aplicar'), 0);

      await desmontar(tester);
    });

    testWidgets('con DELETE: el recuento los cuenta y destaca, y hay que '
        'ESCRIBIR el numero', (tester) async {
      final con = conApuntes(posts: 12, deletes: 3);
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await pulsarAplicarTodo(tester);

      expect(
        find.text(
          'Vas a aplicar 15 cambios: 3 DELETE, 12 POST. Se ejecutan con tu '
          'autoridad, en orden, y se detiene en el primero que falle.',
        ),
        findsOneWidget,
      );
      expect(find.text(TextosDeRevision.avisoDeBorrados), findsOneWidget);
      expect(find.text('3 × Borrar una ruta (DELETE)'), findsOneWidget);
      expect(
        find.text('12 × Registrar el resultado de una ruta (POST)'),
        findsOneWidget,
      );
      // Las rutas exactas, plegadas.
      expect(find.text('Ver las 2 rutas exactas'), findsOneWidget);
      expect(find.text('DELETE /routes/$id  (×3)'), findsNothing);
      await tester.tap(find.text('Ver las 2 rutas exactas'));
      await tester.pumpAndSettle();
      expect(find.text('DELETE /routes/$id  (×3)'), findsOneWidget);

      // SEGUNDO PASO: el boton no se enciende hasta escribir EXACTAMENTE 15.
      final confirmar = botonDeConfirmar();
      expect(habilitado(tester, confirmar), isFalse);
      await tester.tap(confirmar);
      await tester.pump();
      expect(con.cuantas('POST', 'aplicar'), 0);

      await tester.enterText(find.byType(TextField), '14');
      await tester.pump();
      expect(habilitado(tester, confirmar), isFalse, reason: '14 != 15');
      await tester.enterText(find.byType(TextField), '150');
      await tester.pump();
      expect(habilitado(tester, confirmar), isFalse, reason: '150 != 15');

      await tester.enterText(find.byType(TextField), '15');
      await tester.pump();
      expect(habilitado(tester, confirmar), isTrue);
      await tester.tap(confirmar);
      await tester.pumpAndSettle();

      expect(con.cuantas('POST', '/sync/revision/e-1/aplicar'), 1);

      await desmontar(tester);
    });

    testWidgets('mas de 25 (sin DELETE) tambien exige escribir el numero; '
        'exactamente 25, no', (tester) async {
      final con26 = conApuntes(posts: 26);
      await montar(tester, con: con26);
      await abrirLaEntrega(tester);
      await pulsarAplicarTodo(tester);
      expect(find.byType(TextField), findsOneWidget);
      expect(habilitado(tester, botonDeConfirmar()), isFalse);
      await tester.enterText(find.byType(TextField), '26');
      await tester.pump();
      expect(habilitado(tester, botonDeConfirmar()), isTrue);
      await desmontar(tester);

      await montar(tester, con: conApuntes(posts: 25));
      await abrirLaEntrega(tester);
      await pulsarAplicarTodo(tester);
      expect(find.byType(TextField), findsNothing);
      expect(habilitado(tester, botonDeConfirmar()), isTrue);
      await desmontar(tester);
    });
  });

  group('un apunte suelto que borra o modifica pide confirmar', () {
    const id = 'c3a1f0d2-7b1e-4a53-9a64-0e2f5d8b9c11';

    for (final (metodo, ruta, texto) in [
      ('DELETE', '/routes/$id', 'Borrar una ruta'),
      ('PATCH', '/routes/$id', 'Modificar una ruta'),
    ]) {
      testWidgets('$metodo: pregunta con el metodo y la ruta; sin confirmar no '
          'sale nada', (tester) async {
        final con = SyncDeRevisionFalso([
          entregaJson(
            apuntes: [apunteJson(clave: 'c1', metodo: metodo, ruta: ruta)],
          ),
        ]);
        await montar(tester, con: con);
        await abrirLaEntrega(tester);

        await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicar));
        await tester.pumpAndSettle();

        expect(
          find.text(TextosDeRevision.sueltoTitulo(metodo)),
          findsOneWidget,
        );
        expect(find.text('$metodo $ruta'), findsWidgets);
        expect(find.text(texto), findsWidgets);
        expect(con.cuantas('POST', 'aplicar'), 0);

        // «No»: nada.
        await tester.tap(find.text(TextosDeRevision.sueltoNo));
        await tester.pumpAndSettle();
        expect(con.cuantas('POST', 'aplicar'), 0);

        // «Si»: una orden.
        await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicar));
        await tester.pumpAndSettle();
        await tester.tap(find.text(TextosDeRevision.sueltoConfirma));
        await tester.pumpAndSettle();
        expect(con.cuantas('POST', '/ap-1/c1/aplicar'), 1);

        await desmontar(tester);
      });
    }

    testWidgets('EN PAREJA: un POST (registrar resultados, crear) se aplica '
        'con un toque, sin preguntar', (tester) async {
      final con = SyncDeRevisionFalso([dosApuntes()]);
      await montar(tester, con: con);
      await abrirLaEntrega(tester);

      await tester.tap(boton(BotonPrincipal, TextosDeRevision.aplicar).first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Aplicar un '), findsNothing);
      expect(con.cuantas('POST', '/c1/aplicar'), 1);

      await desmontar(tester);
    });
  });

  group('las dos cerraduras de dentro', () {
    ProviderContainer contenedor(SyncDeRevisionFalso con) {
      final c = ProviderContainer(
        overrides: [
          clienteDeRevisionProvider.overrideWithValue(clienteDeRevision(con)),
          sesionParaElMenuProvider.overrideWith((ref) async => revisora),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('dos pulsaciones seguidas son UNA orden (el doble clic no aplica dos '
        'veces)', () async {
      final con = SyncDeRevisionFalso([dosApuntes()])
        ..puerta = Completer<void>();
      final c = contenedor(con);
      final e = await c.read(repositorioRevisionProvider).detalle('e-1');
      final n = c.read(decisionesDelRevisorProvider.notifier);

      final primera = n.aplicar(e, e.apuntes.first);
      final segunda = n.aplicar(e, e.apuntes.first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      con.puerta!.complete();
      await Future.wait([primera, segunda]);

      expect(con.cuantas('POST', '/c1/aplicar'), 1);
    });

    test('descartar sin motivo no sale ni aunque se llame al repositorio '
        'directamente', () async {
      final con = SyncDeRevisionFalso([dosApuntes()]);
      final c = contenedor(con);

      for (final corto in ['', '    ', 'ab', '  ab c  ']) {
        await expectLater(
          c.read(repositorioRevisionProvider).descartar('ap-1', 'c1', corto),
          throwsArgumentError,
          reason: '«$corto»',
        );
      }
      expect(con.cuantas('POST', 'descartar'), 0);
    });
  });
}
