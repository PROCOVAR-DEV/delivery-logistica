// LAS PANTALLAS DE «REPARTO DISTRIBUIDOR»: el modo (qué se esconde), la ruta guiada
// (la parada de ahora, navegar, llamar, marcar, completar sola), y el historial.
//
// La base se siembra DENTRO del cuerpo de cada prueba, nunca en el `setUp` (§5 del
// CLAUDE.md: lo que Drift empieza fuera del reloj falso no avanza dentro).
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart' show BotonDestructivo;
import 'package:reparto/distribuidor/dispositivo/vinculo.dart';
import 'package:reparto/distribuidor/gps/servicio_de_ubicacion.dart';
import 'package:reparto/distribuidor/modo_distribuidor.dart';
import 'package:reparto/distribuidor/vista_historial.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/abrir_y_compartir.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/lista_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';

import '../apoyo/base_de_prueba.dart';
import '../pantallas/pedidos/sembrar.dart';
import 'apoyo_distribuidor.dart';

void main() {
  late BaseLocal base;
  late AparatoFalso aparato;
  final ahora = DateTime(2026, 11, 4, 10, 30);

  setUp(() {
    base = baseDePrueba();
    aparato = AparatoFalso();
  });
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> sembrarRutaEnCurso({
    String estado = EstadoRuta.enCurso,
    int paradas = 3,
  }) async {
    await sembrarCatalogo(base);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
    await sembrarRuta(
      base,
      id: 'R1',
      estado: estado,
      codigo: 'RT-001',
      creada: ahora,
    );
    await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
      RoutesCompanion(
        startedAt: Value(ahora.subtract(const Duration(minutes: 20))),
      ),
    );
    for (final (i, c) in ['Ana', 'Beto', 'Carla'].take(paradas).indexed) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: c,
        rutaId: 'R1',
        orden: i + 1,
        facturaNumero: 'FA-100${i + 1}',
        endLat: 21.38 + i,
        endLng: -77.91,
      );
      await sembrarRenglon(
        base,
        id: 'ri${i + 1}',
        pedidoId: 'p${i + 1}',
        producto: 'Arroz',
        unidades: 10,
        empaques: 2,
      );
    }
    await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
      const OrdersCompanion(customerPhone: Value('+53 5 123 4567')),
    );
  }

  Widget app(Widget hijo, {bool distribuidor = true}) => ProviderScope(
    overrides: [
      baseProvider.overrideWithValue(base),
      relojProvider.overrideWithValue(() => ahora),
      modoDistribuidorProvider.overrideWithValue(distribuidor),
      abrirYCompartirProvider.overrideWithValue(aparato),
      servicioDeUbicacionProvider.overrideWithValue(UbicacionFalsa()),
    ],
    child: MaterialApp(
      localizationsDelegates: delegacionesDeIdioma,
      supportedLocales: idiomas,
      home: Scaffold(body: hijo),
    ),
  );

  Future<void> pintar(
    WidgetTester tester,
    Widget hijo, {
    bool distribuidor = true,
  }) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(hijo, distribuidor: distribuidor));
    await asentar(tester);
  }

  group('el modo distribuidor esconde lo de planificar', () {
    testWidgets(
      'sin el modo, «+ Nueva Ruta» y «Eliminar» siguen donde estaban',
      (tester) async {
        await sembrarRutaEnCurso();
        await pintar(tester, const PantallaRutas(), distribuidor: false);
        expect(find.text('+ Nueva Ruta'), findsOneWidget);
        expect(find.text('Planificador de Rutas'), findsOneWidget);
        await desmontar(tester);
      },
    );

    testWidgets('con el modo: «Mis rutas», sin nueva ruta ni filtros', (
      tester,
    ) async {
      await sembrarRutaEnCurso();
      await pintar(tester, const PantallaRutas());
      expect(find.text('Mis rutas'), findsOneWidget);
      expect(find.text('+ Nueva Ruta'), findsNothing);
      expect(find.textContaining('Filtros'), findsNothing);
      // Abre en lo que esta haciendo: la pestaña «En curso».
      expect(find.byKey(const ValueKey('siguiente-parada-R1')), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets(
      '«Mis rutas» dice a que vehiculo y distribuidor esta ligado el telefono',
      (tester) async {
        await sembrarRutaEnCurso();
        await base.anotarPreferencia(
          claveDelVinculo,
          const VinculoDelTelefono(
            vehiculo: 'Triciclo-Juan',
            placa: 'P-77',
            distribuidor: 'Juan',
          ).aJson(),
        );
        await pintar(tester, const PantallaRutas());
        expect(find.text('Triciclo-Juan (P-77) · Juan'), findsOneWidget);
        await desmontar(tester);
      },
    );

    testWidgets(
      'la tarjeta de una ruta en curso dice la siguiente parada, sin Eliminar ni importes',
      (tester) async {
        await sembrarRutaEnCurso();
        await pintar(
          tester,
          const ListaDeRutas(deLaPestana: PestanaRutas.enCurso),
        );
        expect(find.byType(BotonDestructivo), findsNothing);
        expect(find.text('Eliminar'), findsNothing);
        expect(
          find.byKey(const ValueKey('siguiente-parada-R1')),
          findsOneWidget,
        );
        expect(
          find.textContaining('0 de 3 hechas · Siguiente: Ana'),
          findsOneWidget,
        );
        await desmontar(tester);
      },
    );

    testWidgets('varias rutas en curso: cada una con SU siguiente parada', (
      tester,
    ) async {
      await sembrarRutaEnCurso();
      await sembrarRuta(
        base,
        id: 'R2',
        estado: EstadoRuta.enCurso,
        codigo: 'RT-002',
        creada: ahora,
      );
      await sembrarPedido(
        base,
        id: 'q1',
        cliente: 'Zoe',
        rutaId: 'R2',
        orden: 1,
      );
      await pintar(
        tester,
        const ListaDeRutas(deLaPestana: PestanaRutas.enCurso),
      );
      expect(find.textContaining('Siguiente: Ana'), findsOneWidget);
      expect(find.textContaining('Siguiente: Zoe'), findsOneWidget);
      await desmontar(tester);
    });
  });

  group('la ruta guiada', () {
    testWidgets(
      'enseña la parada de ahora con factura, cliente, telefono, direccion y productos',
      (tester) async {
        await sembrarRutaEnCurso();
        await pintar(tester, const DetalleDeRuta(rutaId: 'R1'));

        expect(find.text('Parada 1 de 3'), findsOneWidget);
        expect(find.textContaining('FA-1001'), findsWidgets);
        expect(find.text('Ana'), findsWidgets);
        expect(find.text('Entrega p1'), findsOneWidget);
        expect(find.text('Tel. +53 5 123 4567'), findsOneWidget);
        expect(find.text('Arroz'), findsOneWidget);
        expect(find.text('2×'), findsOneWidget);
        // Los dos cronometros: la parada y la ruta (salio hace 20 minutos).
        expect(find.byKey(const ValueKey('cronometro-parada')), findsOneWidget);
        expect(find.text('Ruta: 20:00'), findsOneWidget);
        // El distribuidor no completa a mano ni ve importes.
        expect(find.byKey(claveDeCompletar), findsNothing);
        expect(find.textContaining(r'$'), findsNothing);
        await desmontar(tester);
      },
    );

    testWidgets(
      '«Navegar a esta parada» y «Llamar al cliente» abren los enlaces exactos',
      (tester) async {
        await sembrarRutaEnCurso();
        await pintar(tester, const DetalleDeRuta(rutaId: 'R1'));

        await tester.ensureVisible(find.byKey(const ValueKey('guia-navegar')));
        await tester.tap(find.byKey(const ValueKey('guia-navegar')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('guia-llamar')));
        await tester.pump();
        expect(aparato.abiertos.map((u) => u.toString()), [
          'https://www.google.com/maps/dir/?api=1&destination=21.38,-77.91&travelmode=driving',
          'tel:+5351234567',
        ]);
        await desmontar(tester);
      },
    );

    testWidgets(
      'marcar pasa SOLA a la siguiente; «No entregada» pide motivo; la ultima completa la ruta',
      (tester) async {
        await sembrarRutaEnCurso();
        await pintar(tester, const DetalleDeRuta(rutaId: 'R1'));

        Future<void> toca(String clave) async {
          final f = find.byKey(ValueKey(clave));
          await tester.ensureVisible(f);
          await tester.tap(f);
          await asentar(tester);
        }

        bool guardarActivo() =>
            tester
                .widget<FilledButton>(
                  find.descendant(
                    of: find.byKey(const ValueKey('guia-guardar')),
                    matching: find.byType(FilledButton),
                  ),
                )
                .onPressed !=
            null;

        // 1. «No entregada» SIN motivo no deja guardar.
        expect(guardarActivo(), isFalse, reason: 'no hay resultado elegido');
        await toca('guia-noEntregada');
        expect(guardarActivo(), isFalse, reason: 'falta el motivo');
        await tester.enterText(
          find.byKey(const ValueKey('guia-nota')),
          'cerrado',
        );
        await tester.pump();
        expect(guardarActivo(), isTrue);
        await toca('guia-guardar');

        // Pasa sola a la 2.
        expect(find.text('Parada 2 de 3'), findsOneWidget);
        expect(find.text('Beto'), findsWidgets);

        // 2. Entregado + cobrado.
        await toca('guia-entregado');
        await toca('guia-cobrado');
        await toca('guia-guardar');
        expect(find.text('Parada 3 de 3'), findsOneWidget);
        expect(find.text('Guardar y terminar la ruta'), findsOneWidget);

        // 3. La ultima: la ruta se completa SOLA.
        await toca('guia-entregado');
        await toca('guia-guardar');

        final ruta = await (base.select(
          base.routes,
        )..where((r) => r.id.equals('R1'))).getSingle();
        expect(ruta.status, EstadoRuta.completada);
        final cobros = {
          for (final c in await base.select(base.cobrosDeEntrega).get())
            c.pedidoId: c.cobrado,
        };
        expect(cobros, {'p1': false, 'p2': true, 'p3': false});
        // (`.get()` y no un `.first` sobre un stream de Drift: cuelga el reloj falso, §5.)
        final apuntes = await base.select(base.apuntes).get();
        expect(apuntes.map((a) => '${a.metodo} ${a.ruta}').toList(), [
          'POST /routes/R1/results',
          'POST /routes/R1/results',
          'POST /routes/R1/results',
          'PATCH /routes/R1',
        ]);
        await desmontar(tester);
      },
    );

    testWidgets('cancelar la ruta pide motivo y confirmacion', (tester) async {
      await sembrarRutaEnCurso();
      await pintar(tester, const DetalleDeRuta(rutaId: 'R1'));

      final boton = find.byKey(const ValueKey('guia-cancelar-ruta'));
      await tester.ensureVisible(boton);
      await tester.tap(boton);
      await asentar(tester);
      final si = find.byKey(const ValueKey('guia-confirmar-cancelar'));
      expect(
        tester
            .widget<OutlinedButton>(
              find.descendant(of: si, matching: find.byType(OutlinedButton)),
            )
            .onPressed,
        isNull,
        reason: 'sin motivo no confirma',
      );
      await tester.enterText(
        find.byKey(const ValueKey('guia-motivo-de-cancelar')),
        'se averió',
      );
      await tester.pump();
      await tester.tap(si);
      await asentar(tester);

      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals('R1'))).getSingle();
      expect(ruta.status, EstadoRuta.cancelada);
      await desmontar(tester);
    });

    testWidgets('con una entregada ya no se ofrece cancelar', (tester) async {
      await sembrarRutaEnCurso();
      await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
        const OrdersCompanion(resultado: Value(ResultadoParada.entregado)),
      );
      await pintar(tester, const DetalleDeRuta(rutaId: 'R1'));
      expect(find.byKey(const ValueKey('guia-cancelar-ruta')), findsNothing);
      await desmontar(tester);
    });

    testWidgets('una ruta planificada se inicia desde el detalle', (
      tester,
    ) async {
      await sembrarRutaEnCurso(estado: EstadoRuta.planificada);
      await pintar(tester, const DetalleDeRuta(rutaId: 'R1'));
      expect(find.text('Iniciar ruta'), findsOneWidget);
      expect(
        find.text('Parada 1 de 3'),
        findsNothing,
        reason: 'aun no esta en curso',
      );
      await tester.tap(find.text('Iniciar ruta'));
      await asentar(tester);
      expect(find.text('Parada 1 de 3'), findsOneWidget);
      await desmontar(tester);
    });
  });

  group('el historial', () {
    Future<void> sembrarCerrada({
      DateTime? revisada,
      String estado = EstadoRuta.completada,
    }) async {
      await sembrarCatalogo(base);
      await sembrarRuta(
        base,
        id: 'H1',
        estado: estado,
        codigo: 'RT-H1',
        creada: ahora,
      );
      await (base.update(base.routes)..where((r) => r.id.equals('H1'))).write(
        RoutesCompanion(
          startedAt: Value(DateTime(2026, 11, 3, 8)),
          finishedAt: Value(DateTime(2026, 11, 3, 11, 30)),
          revisadaAt: Value(revisada),
        ),
      );
      await sembrarPedido(
        base,
        id: 'h1',
        cliente: 'Ana',
        rutaId: 'H1',
        orden: 1,
        resultado: ResultadoParada.entregado,
      );
      await sembrarPedido(
        base,
        id: 'h2',
        cliente: 'Beto',
        rutaId: 'H1',
        ultimaRutaId: 'H1',
        orden: 2,
        resultado: ResultadoParada.devuelto,
      );
      await (base.update(base.orders)..where((o) => o.id.equals('h1'))).write(
        OrdersCompanion(resultadoAt: Value(DateTime(2026, 11, 3, 9, 15))),
      );
      await (base.update(base.orders)..where((o) => o.id.equals('h2'))).write(
        OrdersCompanion(
          routeId: const Value(null),
          resultadoAt: Value(DateTime(2026, 11, 3, 10)),
          resultadoNota: const Value('cerrado'),
        ),
      );
      await base
          .into(base.cobrosDeEntrega)
          .insert(
            CobrosDeEntregaCompanion.insert(pedidoId: 'h1', cobrado: true),
          );
    }

    testWidgets(
      'la lista cuenta paradas, entregadas, no entregadas, cobradas y la duracion',
      (tester) async {
        await sembrarCerrada();
        await pintar(tester, const ListaDelHistorial());
        expect(
          find.byKey(const ValueKey('historial-cuentas-H1')),
          findsOneWidget,
        );
        expect(
          find.text('2 paradas · 1 entregadas · 1 no entregadas · 1 cobradas'),
          findsOneWidget,
        );
        expect(find.textContaining('3h 30min'), findsOneWidget);
        expect(find.text('Completada'), findsOneWidget);
        expect(find.text('Enviada ✓'), findsOneWidget);
        expect(find.text('Pendiente de revisión de logística'), findsOneWidget);
        await desmontar(tester);
      },
    );

    testWidgets('«Revisada ✓» cuando el servidor baja revisadaAt', (
      tester,
    ) async {
      await sembrarCerrada(revisada: DateTime(2026, 11, 4, 8));
      await pintar(tester, const ListaDelHistorial());
      expect(find.text('Revisada ✓'), findsOneWidget);
      expect(find.text('Pendiente de revisión de logística'), findsNothing);
      await desmontar(tester);
    });

    testWidgets('con algo sin enviar en la cola, «Pendiente de enviar»', (
      tester,
    ) async {
      await sembrarCerrada();
      await ColaDeSalida(base, reloj: () => ahora).encolar(
        metodo: 'PATCH',
        ruta: '/routes/H1',
        cuerpo: const {'status': 'completed'},
      );
      await pintar(tester, const ListaDelHistorial());
      expect(find.text('Pendiente de enviar'), findsOneWidget);
      expect(find.text('Enviada ✓'), findsNothing);
      await desmontar(tester);
    });

    testWidgets('una cancelada sale como cancelada y sin estado de revision', (
      tester,
    ) async {
      await sembrarCerrada(estado: EstadoRuta.cancelada);
      await pintar(tester, const ListaDelHistorial());
      expect(find.text('Cancelada'), findsOneWidget);
      expect(find.byKey(const ValueKey('historial-revision-H1')), findsNothing);
      await desmontar(tester);
    });

    testWidgets(
      'al abrir una ruta cerrada: sus paradas, lo que marco y a que hora',
      (tester) async {
        await sembrarCerrada();
        await pintar(tester, const DetalleDeRuta(rutaId: 'H1'));
        expect(
          find.byKey(const ValueKey('historial-parada-h1')),
          findsOneWidget,
        );
        // La etiqueta de estado de la casa (issue 26) y, debajo, la hora y la nota.
        final h1 = find.byKey(const ValueKey('historial-parada-h1'));
        final h2 = find.byKey(const ValueKey('historial-parada-h2'));
        expect(
          find.descendant(of: h1, matching: find.text('Entregada · cobrada')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: h1, matching: find.text('3/11/2026, 9:15')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: h2, matching: find.text('No entregada')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: h2, matching: find.text('3/11/2026, 10:00')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: h2, matching: find.text('cerrado')),
          findsOneWidget,
        );
        expect(find.textContaining('cerrado'), findsOneWidget);
        await desmontar(tester);
      },
    );
  });
}
