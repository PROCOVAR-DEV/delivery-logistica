// LA PESTAÑA «TELÉFONOS» de Distribución: la lista de dispositivos, su filtro y su buscador, «Desvincular» (el mismo cajón que el del
// vehículo), el 409, el estado sin red, y los dos anchos (tarjetas a 390 px, tabla a 1440).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/distribucion/datos/modelos.dart';
import 'package:reparto/pantallas/distribucion/vista/pantalla_distribucion.dart';
import 'package:reparto/pantallas/distribucion/vista/telefonos_de_distribuidores.dart';
import 'package:reparto/pantallas/distribucion/vista/vinculo_del_vehiculo.dart';
import 'package:reparto/pantallas/rutas/datos/abrir_y_compartir.dart';

import '../../apoyo/aparato_espia.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  final ahora = DateTime.utc(2026, 11, 4, 12).toLocal();
  final reloj = relojProvider.overrideWithValue(() => ahora);

  Map<String, Object?> telefono(
    String id, {
    String? nombre,
    String sucursalId = 'S1',
    String sucursal = 'La Habana',
    bool activo = true,
    String? visto,
    String? vehiculo,
    String? placa,
    String? distribuidor,
    int rutas = 0,
  }) => {
    'id': id,
    'nombre': nombre,
    'sucursalId': sucursalId,
    'sucursal': sucursal,
    'activo': activo,
    'creadoAt': utc(8, 0),
    'ultimaVezAt': visto,
    'vehiculo': vehiculo == null
        ? null
        : {'id': 'V-$id', 'nombre': vehiculo, 'placa': placa},
    'vinculadoAt': vehiculo == null ? null : utc(9, 30),
    'distribuidor': distribuidor == null
        ? null
        : {'id': 'D-$id', 'nombre': distribuidor},
    'rutasAbiertas': rutas,
  };

  List<Map<String, Object?>> lista() => [
    telefono(
      'T1',
      nombre: 'Samsung A16',
      visto: utc(11, 57),
      vehiculo: 'Triciclo-Felix',
      placa: 'P123456',
      distribuidor: 'Felix',
      rutas: 2,
    ),
    telefono('T2', nombre: 'Xiaomi', visto: utc(11, 0), vehiculo: 'Camioneta'),
    telefono('T3', nombre: 'Viejo', activo: false, visto: utc(7, 0)),
    telefono('T4', visto: null),
  ];

  late AparatoEspia aparato;
  setUp(() => aparato = AparatoEspia());

  Future<void> montarLista(
    WidgetTester tester,
    ApiDePrueba api, {
    Size tamano = const Size(900, 1400),
  }) => montar(
    tester,
    const TelefonosDeDistribuidores(),
    api,
    tamano: tamano,
    mas: [reloj, abrirYCompartirProvider.overrideWithValue(aparato)],
  );

  RespuestaFalsa? contestaLista(PeticionVista p, [List<Object?>? datos]) =>
      p.ruta == '/dispositivos' ? RespuestaFalsa(200, datos ?? lista()) : null;

  Future<void> elegirTodos(WidgetTester tester) async {
    await tester.tap(find.byKey(claveDelFiltroDeTelefonos));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos').last);
    await tester.pumpAndSettle();
  }

  group('la lista', () {
    testWidgets(
      'por defecto solo los vinculados, con vehículo, placa, desde cuándo, distribuidor, rutas y "visto hace"',
      (tester) async {
        final api = ApiDePrueba((p) async => contestaLista(p));
        await montarLista(tester, api);

        expect(api.servidor.vistas.single.ruta, '/dispositivos');
        expect(find.byKey(claveDelTelefono('T1')), findsOneWidget);
        expect(find.byKey(claveDelTelefono('T2')), findsOneWidget);
        expect(find.byKey(claveDelTelefono('T3')), findsNothing);
        expect(find.byKey(claveDelTelefono('T4')), findsNothing);

        expect(find.text('Samsung A16'), findsOneWidget);
        expect(find.text('Triciclo-Felix · P123456'), findsOneWidget);
        expect(find.text('Camioneta'), findsOneWidget);
        expect(find.textContaining('Vinculado desde'), findsNWidgets(2));
        expect(find.text('Felix'), findsOneWidget);
        expect(find.text('2 rutas abiertas'), findsOneWidget);
        expect(find.text('0 rutas abiertas'), findsOneWidget);
        expect(find.text('Visto hace 3 min'), findsOneWidget);
        expect(find.text('Visto hace 1 h'), findsOneWidget);
        // Una sola sucursal: no se repite en cada tarjeta.
        expect(find.text('La Habana'), findsNothing);

        // Ámbar solo pasados 10 minutos.
        expect(find.byKey(claveDelAvisoSinSenalTelefono('T1')), findsNothing);
        expect(find.byKey(claveDelAvisoSinSenalTelefono('T2')), findsOneWidget);

        expect(find.byKey(claveDeDesvincularTelefono('T1')), findsOneWidget);
        expect(find.byKey(claveDeDesvincularTelefono('T2')), findsOneWidget);
      },
    );

    testWidgets(
      '«Todos» enseña también los desvinculados y los de baja, sin botón de desvincular',
      (tester) async {
        final api = ApiDePrueba((p) async => contestaLista(p));
        await montarLista(tester, api);
        await elegirTodos(tester);

        expect(find.byKey(claveDelTelefono('T3')), findsOneWidget);
        expect(find.byKey(claveDelTelefono('T4')), findsOneWidget);
        expect(find.text('Dado de baja'), findsOneWidget);
        expect(find.text('Teléfono sin nombre'), findsOneWidget);
        expect(find.text('Sin vehículo'), findsNWidgets(2));
        expect(find.text('Nunca visto'), findsOneWidget);
        expect(find.byKey(claveDeDesvincularTelefono('T3')), findsNothing);
        expect(find.byKey(claveDeDesvincularTelefono('T4')), findsNothing);
        // Uno sin vincular no avisa de falta de señal aunque lleve horas sin verse.
        expect(find.byKey(claveDelAvisoSinSenalTelefono('T3')), findsNothing);
      },
    );

    testWidgets('el buscador mira nombre, vehículo y distribuidor', (
      tester,
    ) async {
      final api = ApiDePrueba((p) async => contestaLista(p));
      await montarLista(tester, api);

      await tester.enterText(find.byType(TextField).first, 'felix');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(claveDelTelefono('T1')), findsOneWidget);
      expect(find.byKey(claveDelTelefono('T2')), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'camion');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(claveDelTelefono('T2')), findsOneWidget);
      expect(find.byKey(claveDelTelefono('T1')), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(TextosDeLosTelefonos.nadaDeEsto), findsOneWidget);
    });

    testWidgets('con teléfonos de varias sucursales dice de cuál es cada uno', (
      tester,
    ) async {
      final api = ApiDePrueba(
        (p) async => contestaLista(p, [
          telefono('T1', nombre: 'A', vehiculo: 'V1'),
          telefono(
            'T2',
            nombre: 'B',
            vehiculo: 'V2',
            sucursalId: 'S2',
            sucursal: 'Granma',
          ),
        ]),
      );
      await montarLista(tester, api);
      expect(find.text('La Habana'), findsOneWidget);
      expect(find.text('Granma'), findsOneWidget);
    });

    testWidgets(
      'sin teléfonos, y sin ninguno vinculado, lo dice con palabras',
      (tester) async {
        await montarLista(
          tester,
          ApiDePrueba((p) async => contestaLista(p, <Object?>[])),
        );
        expect(find.text(TextosDeLosTelefonos.ninguno), findsOneWidget);

        await montarLista(
          tester,
          ApiDePrueba(
            (p) async => contestaLista(p, [telefono('T3', nombre: 'Viejo')]),
          ),
        );
        expect(
          find.text(TextosDeLosTelefonos.ningunoVinculado),
          findsOneWidget,
        );
      },
    );

    testWidgets('sin red lo dice y "Reintentar" vuelve a pedir', (
      tester,
    ) async {
      var hayRed = false;
      final api = ApiDePrueba((p) async => hayRed ? contestaLista(p) : null);
      await montarLista(tester, api);
      expect(
        find.textContaining('No se pudieron leer los teléfonos: Sin conexión'),
        findsOneWidget,
      );
      hayRed = true;
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);
      expect(find.byKey(claveDelTelefono('T1')), findsOneWidget);
    });

    testWidgets('el error del servidor sale con su motivo literal', (
      tester,
    ) async {
      final api = ApiDePrueba(
        (_) async => RespuestaFalsa(403, {'error': 'Solo la oficina.'}),
      );
      await montarLista(tester, api);
      expect(find.textContaining('Solo la oficina.'), findsOneWidget);
    });
  });

  group('desvincular', () {
    testWidgets(
      'el mismo cajón; al confirmar manda el motivo al vehículo, refresca la lista y avisa de las rutas sueltas',
      (tester) async {
        var desvinculado = false;
        final api = ApiDePrueba((p) async {
          if (p.ruta == '/vehicles/V-T1/desvincular') {
            desvinculado = true;
            return RespuestaFalsa(200, {
              'desvinculado': true,
              'dispositivoId': 'T1',
              'rutasSueltas': ['R1'],
            });
          }
          if (p.ruta == '/routes') {
            return RespuestaFalsa(200, [
              {
                'id': 'R1',
                'routeCode': 'RT-001',
                'name': 'Ruta uno',
                'status': 'planned',
              },
            ]);
          }
          return contestaLista(
            p,
            desvinculado
                ? [telefono('T1', nombre: 'Samsung A16', visto: utc(11, 57))]
                : null,
          );
        });
        await montarLista(tester, api);

        await tester.tap(find.byKey(claveDeDesvincularTelefono('T1')));
        await tester.pumpAndSettle();
        expect(find.text(TextosDelVinculo.explicacion), findsOneWidget);
        await tester.enterText(
          find.byKey(claveDelMotivo),
          'Cambia de teléfono',
        );
        await tester.tap(find.byKey(claveDeConfirmarDesvinculo));
        await tester.pumpAndSettle();
        await asentar(tester);

        final post = api.servidor.vistas.singleWhere((p) => p.metodo == 'POST');
        expect(post.ruta, '/vehicles/V-T1/desvincular');
        expect(post.cuerpo, {'motivo': 'Cambia de teléfono'});
        expect(
          api.servidor.vistas.where((p) => p.ruta == '/dispositivos').length,
          2,
        );

        // Las rutas sueltas, con su «Enviar enlace nuevo».
        expect(find.byKey(claveDeLasRutasSueltas), findsOneWidget);
        expect(find.byKey(claveDeEnviarEnlaceNuevo('R1')), findsOneWidget);
      },
    );

    testWidgets('si se dice que no, no se manda nada', (tester) async {
      final api = ApiDePrueba((p) async => contestaLista(p));
      await montarLista(tester, api);
      await tester.tap(find.byKey(claveDeDesvincularTelefono('T1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No, dejarlo vinculado'));
      await tester.pumpAndSettle();
      expect(api.servidor.vistas.where((p) => p.metodo == 'POST'), isEmpty);
    });

    testWidgets(
      '409: lo enseña con la frase del servidor y refresca la lista',
      (tester) async {
        final api = ApiDePrueba(
          (p) async => p.metodo == 'POST'
              ? RespuestaFalsa(409, {
                  'error': 'Ese vehículo no está vinculado a ningún teléfono.',
                })
              : contestaLista(p),
        );
        await montarLista(tester, api);
        await tester.tap(find.byKey(claveDeDesvincularTelefono('T1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(claveDeConfirmarDesvinculo));
        await tester.pumpAndSettle();
        await asentar(tester);

        expect(
          find.text('Ese vehículo no está vinculado a ningún teléfono.'),
          findsOneWidget,
        );
        expect(find.byKey(claveDeLasRutasSueltas), findsNothing);
        expect(
          api.servidor.vistas.where((p) => p.ruta == '/dispositivos').length,
          2,
        );
      },
    );
  });

  group('los dos anchos', () {
    for (final (ancho, tabla) in [(390.0, false), (1440.0, true)]) {
      testWidgets('a ${ancho.toInt()} px ${tabla ? 'tabla' : 'tarjetas'}, sin '
          'desbordes', (tester) async {
        final api = ApiDePrueba(
          (p) async => contestaLista(p, [
            ...lista(),
            telefono(
              'T5',
              nombre: 'Otro',
              vehiculo: 'Moto',
              sucursalId: 'S2',
              sucursal: 'Granma',
            ),
          ]),
        );
        await montarLista(tester, api, tamano: Size(ancho, 900));
        expect(tester.takeException(), isNull);
        expect(find.byType(DataTable), tabla ? findsOneWidget : findsNothing);
        expect(find.byKey(claveDelTelefono('T1')), findsOneWidget);
        expect(find.text('Granma'), findsOneWidget);
        expect(find.text('Samsung A16'), findsOneWidget);
        expect(find.byKey(claveDeDesvincularTelefono('T5')), findsOneWidget);
      });
    }
  });

  testWidgets('la pantalla Distribución tiene la pestaña «Teléfonos (N)»', (
    tester,
  ) async {
    final api = ApiDePrueba(
      (p) async => p.ruta == '/routes'
          ? RespuestaFalsa(200, <Object?>[])
          : p.ruta == '/dispositivos'
          ? RespuestaFalsa(200, lista())
          : RespuestaFalsa(200, {'distribuidores': <Object?>[]}),
    );
    await montar(
      tester,
      const PantallaDistribucion(),
      api,
      mas: [reloj],
      tamano: const Size(390, 900),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Teléfonos (2)'), findsOneWidget);
    await tester.tap(find.text('Teléfonos (2)'));
    await tester.pumpAndSettle();
    expect(find.byKey(claveDelTelefono('T1')), findsOneWidget);
  });

  test('el modelo lee el contrato y filtrarTelefonos lo recorta', () {
    final t = [for (final j in lista()) TelefonoDeDistribuidor.deJson(j)];
    expect(t[0].vinculado, isTrue);
    expect(t[0].vehiculoId, 'V-T1');
    expect(t[0].placa, 'P123456');
    expect(t[2].vinculado, isFalse);
    expect(t[2].activo, isFalse);
    expect(t[3].ultimaVezAt, isNull);
    expect(t[3].vistoHace(ahora), isNull);
    expect(cuantosVinculados(t), 2);
    expect(filtrarTelefonos(t).map((x) => x.id), ['T1', 'T2']);
    expect(filtrarTelefonos(t, filtro: FiltroDeTelefonos.todos).length, 4);
    expect(
      filtrarTelefonos(
        t,
        filtro: FiltroDeTelefonos.todos,
        q: 'p123',
      ).map((x) => x.id),
      ['T1'],
    );
  });
}
