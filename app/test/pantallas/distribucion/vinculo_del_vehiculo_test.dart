// EL VEHÍCULO Y SU TELÉFONO: ver el vínculo, desvincular (con motivo, con confirmación), el 409 de «no está vinculado», las rutas
// que quedan sueltas con «Enviar enlace nuevo», y la historia de vínculos.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/distribucion/datos/api_distribucion.dart';
import 'package:reparto/pantallas/distribucion/vista/vinculo_del_vehiculo.dart';
import 'package:reparto/pantallas/rutas/datos/abrir_y_compartir.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';

import '../../apoyo/aparato_espia.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  VehiculoDeLaApi vehiculo({String? dispositivoId = 'T1'}) => VehiculoDeLaApi(
    id: 'V1',
    nombre: 'Triciclo-Felix',
    capacidad: 300,
    estado: 'available',
    dispositivoId: dispositivoId,
    dispositivoNombre: dispositivoId == null ? null : 'Samsung A16',
    vinculadoAt: dispositivoId == null
        ? null
        : DateTime.utc(2026, 11, 3, 14).toLocal(),
  );

  late AparatoEspia aparato;
  setUp(() => aparato = AparatoEspia());

  Future<void> montarVinculo(
    WidgetTester tester,
    ApiDePrueba api, {
    VehiculoDeLaApi? v,
    bool compacto = false,
  }) async {
    final elVehiculo = v ?? vehiculo();
    await montar(
      tester,
      SingleChildScrollView(
        child: VinculoDelVehiculo(
          vehiculoId: 'V1',
          nombre: 'Triciclo-Felix',
          compacto: compacto,
        ),
      ),
      api,
      mas: [
        vehiculosEnVivoProvider.overrideWith((ref) async => {'V1': elVehiculo}),
        abrirYCompartirProvider.overrideWithValue(aparato),
      ],
    );
  }

  Map<String, Object?> ruta(String id, String codigo) => {
    'id': id,
    'routeCode': codigo,
    'name': 'Ruta $codigo',
    'status': 'planned',
    'deliveryDate': '2026-11-05T00:00:00Z',
    'orders': [
      {'id': 'o1'},
      {'id': 'o2'},
    ],
  };

  group('el vínculo actual', () {
    testWidgets(
      'dice a qué teléfono está vinculado, desde cuándo, y ofrece desvincular',
      (tester) async {
        final api = ApiDePrueba(
          (_) async => RespuestaFalsa(200, <String, Object?>{}),
        );
        await montarVinculo(tester, api);
        expect(
          find.textContaining('Vinculado al teléfono Samsung A16 desde'),
          findsOneWidget,
        );
        expect(find.byKey(claveDeDesvincular), findsOneWidget);
      },
    );

    testWidgets(
      'sin teléfono: en la tarjeta no dice nada; en el historial, que no hay',
      (tester) async {
        final api = ApiDePrueba(
          (_) async => RespuestaFalsa(200, <String, Object?>{}),
        );
        await montarVinculo(
          tester,
          api,
          v: vehiculo(dispositivoId: null),
          compacto: true,
        );
        expect(find.byKey(claveDelVinculoActual), findsNothing);
        expect(find.byKey(claveDeDesvincular), findsNothing);

        await montarVinculo(tester, api, v: vehiculo(dispositivoId: null));
        expect(find.text(TextosDelVinculo.sinTelefono), findsOneWidget);
        expect(find.byKey(claveDeDesvincular), findsNothing);
      },
    );
  });

  group('desvincular', () {
    testWidgets(
      'pregunta con la explicación, deja decir el motivo, y NO manda nada si se dice que no',
      (tester) async {
        final api = ApiDePrueba(
          (_) async => RespuestaFalsa(200, <String, Object?>{}),
        );
        await montarVinculo(tester, api);
        await tester.tap(find.byKey(claveDeDesvincular));
        await tester.pumpAndSettle();

        expect(find.text(TextosDelVinculo.explicacion), findsOneWidget);
        expect(find.byKey(claveDelMotivo), findsOneWidget);
        await tester.tap(find.text('No, dejarlo vinculado'));
        await tester.pumpAndSettle();
        expect(api.servidor.vistas.where((p) => p.metodo == 'POST'), isEmpty);
      },
    );

    testWidgets(
      'al confirmar manda el motivo, y las rutas que quedaron sueltas ofrecen un enlace nuevo',
      (tester) async {
        final api = ApiDePrueba((p) async {
          if (p.ruta == '/vehicles/V1/desvincular') {
            return RespuestaFalsa(200, {
              'desvinculado': true,
              'dispositivoId': 'T1',
              'rutasSueltas': ['R1', 'R2'],
            });
          }
          if (p.ruta == '/routes') {
            return RespuestaFalsa(200, [
              ruta('R1', 'RT-001'),
              ruta('R2', 'RT-002'),
            ]);
          }
          if (p.ruta == '/routes/R1/enlace') {
            return RespuestaFalsa(200, {
              'token': 'nuevo',
              'url': 'https://reparto.procovar.cloud/r/nuevo',
              'estado': 'sin_reclamar',
            });
          }
          return RespuestaFalsa(200, <String, Object?>{});
        });
        await montarVinculo(tester, api);
        await tester.tap(find.byKey(claveDeDesvincular));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(claveDelMotivo),
          'Se rompió el teléfono',
        );
        await tester.tap(find.byKey(claveDeConfirmarDesvinculo));
        await tester.pumpAndSettle();
        await asentar(tester);

        final post = api.servidor.vistas.singleWhere(
          (p) => p.ruta == '/vehicles/V1/desvincular',
        );
        expect(post.metodo, 'POST');
        expect(post.cuerpo, {'motivo': 'Se rompió el teléfono'});

        // Salen las dos rutas libres, con su nombre.
        expect(find.byKey(claveDeLasRutasSueltas), findsOneWidget);
        expect(find.text('RT-001 · Ruta RT-001'), findsOneWidget);
        expect(find.byKey(claveDeEnviarEnlaceNuevo('R2')), findsOneWidget);

        // «Enviar enlace nuevo»: enlace fresco (renovar) y a WhatsApp con el mensaje de siempre.
        await tester.tap(find.byKey(claveDeEnviarEnlaceNuevo('R1')));
        await asentar(tester);
        final enlace = api.servidor.vistas.singleWhere(
          (p) => p.ruta == '/routes/R1/enlace',
        );
        expect(enlace.metodo, 'POST');
        expect(enlace.cuerpo, {'renovar': true});
        final texto = aparato.abiertos.single.queryParameters['text']!;
        expect(texto, contains('Tu ruta RT-001 · Ruta RT-001 ·'));
        expect(texto, contains('2 paradas'));
        expect(texto, contains('\nhttps://reparto.procovar.cloud/r/nuevo\n'));
      },
    );

    testWidgets(
      'sin motivo no manda la clave, y sin rutas sueltas solo avisa',
      (tester) async {
        final api = ApiDePrueba(
          (_) async => RespuestaFalsa(200, {
            'desvinculado': true,
            'dispositivoId': 'T1',
            'rutasSueltas': <Object?>[],
          }),
        );
        await montarVinculo(tester, api);
        await tester.tap(find.byKey(claveDeDesvincular));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(claveDeConfirmarDesvinculo));
        await tester.pumpAndSettle();
        await asentar(tester);

        expect(
          api.servidor.vistas.singleWhere((p) => p.metodo == 'POST').cuerpo,
          isEmpty,
        );
        expect(find.text(TextosDelVinculo.desvinculado), findsOneWidget);
        expect(find.byKey(claveDeLasRutasSueltas), findsNothing);
      },
    );

    testWidgets(
      '409: ese vehículo no estaba vinculado, y sale la frase del servidor',
      (tester) async {
        final api = ApiDePrueba(
          (_) async => RespuestaFalsa(409, {
            'error': 'Ese vehículo no está vinculado a ningún teléfono.',
          }),
        );
        await montarVinculo(tester, api);
        await tester.tap(find.byKey(claveDeDesvincular));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(claveDeConfirmarDesvinculo));
        await tester.pumpAndSettle();
        await asentar(tester);

        expect(find.byKey(claveDelAvisoDelVinculo), findsOneWidget);
        expect(
          find.text('Ese vehículo no está vinculado a ningún teléfono.'),
          findsOneWidget,
        );
        expect(find.byKey(claveDeLasRutasSueltas), findsNothing);
      },
    );

    testWidgets('sin red no se da por hecho: se dice por qué', (tester) async {
      final api = ApiDePrueba((_) async => null);
      await montarVinculo(tester, api);
      await tester.tap(find.byKey(claveDeDesvincular));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(claveDeConfirmarDesvinculo));
      await tester.pumpAndSettle();
      await asentar(tester);
      expect(find.text('Sin conexión con el servidor.'), findsOneWidget);
    });
  });

  group('la historia de vínculos', () {
    testWidgets('lista los teléfonos, el más reciente primero, con su motivo', (
      tester,
    ) async {
      final api = ApiDePrueba(
        (_) async => RespuestaFalsa(200, [
          {
            'id': 'a',
            'dispositivoId': 'T0',
            'dispositivo': 'Xiaomi viejo',
            'desde': utc(10, 0).replaceFirst('2026-11-04', '2026-10-01'),
            'hasta': utc(10, 0).replaceFirst('2026-11-04', '2026-11-03'),
            'vinculadoPor': 'maikel',
            'desvinculadoPor': 'maikel',
            'motivo': 'Se rompió',
          },
          {
            'id': 'b',
            'dispositivoId': 'T1',
            'dispositivo': 'Samsung A16',
            'desde': utc(10, 0),
            'hasta': null,
          },
        ]),
      );
      await montar(
        tester,
        SingleChildScrollView(child: HistorialDeVinculos(vehiculoId: 'V1')),
        api,
      );

      expect(api.servidor.vistas.single.ruta, '/vehicles/V1/vinculos');
      final orden = tester
          .widgetList(
            find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey &&
                  '${(w.key! as ValueKey).value}'.startsWith(
                    'vinculo-historia-',
                  ),
            ),
          )
          .map((w) => '${(w.key! as ValueKey).value}')
          .toList();
      expect(orden, ['vinculo-historia-b', 'vinculo-historia-a']);
      expect(find.text('Vinculado ahora'), findsOneWidget);
      expect(find.text('Desvinculado'), findsOneWidget);
      expect(find.text('Motivo: Se rompió'), findsOneWidget);
      expect(find.text('Lo desvinculó maikel'), findsOneWidget);
    });

    testWidgets('sin vínculos y sin red lo dicen', (tester) async {
      var api = ApiDePrueba((_) async => RespuestaFalsa(200, <Object?>[]));
      await montar(tester, HistorialDeVinculos(vehiculoId: 'V1'), api);
      expect(find.text(TextosDelVinculo.sinVinculos), findsOneWidget);

      api = ApiDePrueba((_) async => null);
      await montar(tester, HistorialDeVinculos(vehiculoId: 'V1'), api);
      expect(
        find.textContaining(
          'No se pudo leer la historia de teléfonos: Sin conexión',
        ),
        findsOneWidget,
      );
    });
  });

  test(
    'el vehículo de la API trae su teléfono vinculado, y sin él queda nulo',
    () {
      final con = VehiculoDeLaApi.deJson({
        'id': 'V',
        'name': 'X',
        'dispositivoId': 'T1',
        'dispositivoNombre': 'Samsung',
        'vinculadoAt': '2026-11-03T14:00:00Z',
      });
      expect(con.dispositivoId, 'T1');
      expect(con.dispositivoNombre, 'Samsung');
      expect(con.vinculadoAt, DateTime.utc(2026, 11, 3, 14).toLocal());
      expect(
        VehiculoDeLaApi.deJson({'id': 'V', 'name': 'X', 'dispositivoId': null})
            .dispositivoId,
        isNull,
      );
    },
  );
}
