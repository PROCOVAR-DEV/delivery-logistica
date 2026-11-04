// «DÓNDE ESTÁN AHORA» (tarea 5) Y LA REVISIÓN (tarea 6).
//
// Dónde están: el aviso en ámbar sale pasados 10 minutos (y no antes), se dice si no hay nadie y si no hay red.
// Revisión: «Pendiente de revisión» con su botón «Confirmar revisión» (POST con {"confirmar":true}); «Revisada ✓» después; y si el
// servidor no manda el campo, NO se pinta nada. La lista se filtra y se busca.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/distribucion/vista/donde_estan_ahora.dart';
import 'package:reparto/pantallas/distribucion/vista/pantalla_distribucion.dart';
import 'package:reparto/pantallas/distribucion/vista/revision_de_rutas.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  final ahora = DateTime.utc(2026, 11, 4, 15, 0);

  Map<String, Object?> distribuidor(
    String id,
    String nombre,
    DateTime recibido,
  ) => {
    'distribuidorId': id,
    'distribuidor': nombre,
    'lat': 23.1,
    'lng': -82.4,
    'hora': recibido.toIso8601String(),
    'recibidoAt': recibido.toIso8601String(),
    'rutaIds': ['R-$id'],
  };

  group('dónde están ahora', () {
    List<Override> reloj() => [
      relojProvider.overrideWithValue(() => ahora.toLocal()),
    ];

    testWidgets(
      'cada uno con hace cuánto mandó su punto; el aviso ámbar SOLO pasados 10 minutos',
      (tester) async {
        final api = ApiDePrueba(
          (_) async => RespuestaFalsa(200, {
            'distribuidores': [
              distribuidor(
                'D1',
                'Felix',
                ahora.subtract(const Duration(minutes: 2)),
              ),
              distribuidor(
                'D2',
                'Juan',
                ahora.subtract(const Duration(minutes: 25)),
              ),
            ],
          }),
        );
        await montar(tester, const DondeEstanAhora(), api, mas: reloj());

        expect(api.servidor.vistas.first.ruta, '/tracking/ahora');
        expect(
          find.descendant(
            of: find.byKey(claveDelDistribuidorAhora('D1')),
            matching: find.textContaining('Último aviso hace 2 min'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(claveDelAvisoSinSenal('D1')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(claveDelDistribuidorAhora('D2')),
            matching: find.textContaining('hace 25 min'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(claveDelAvisoSinSenal('D2')), findsOneWidget);
        expect(
          find.textContaining('Más de 10 minutos sin noticias'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a los 9 minutos no hay aviso', (tester) async {
      final api = ApiDePrueba(
        (_) async => RespuestaFalsa(200, {
          'distribuidores': [
            distribuidor(
              'D1',
              'Felix',
              ahora.subtract(const Duration(minutes: 9)),
            ),
          ],
        }),
      );
      await montar(tester, const DondeEstanAhora(), api, mas: reloj());
      expect(find.byKey(claveDelAvisoSinSenal('D1')), findsNothing);
    });

    testWidgets('si nadie tiene ruta en curso, lo dice', (tester) async {
      final api = ApiDePrueba(
        (_) async => RespuestaFalsa(200, {'distribuidores': <Object?>[]}),
      );
      await montar(tester, const DondeEstanAhora(), api, mas: reloj());
      expect(
        find.textContaining('Ningún distribuidor tiene una ruta en curso'),
        findsOneWidget,
      );
    });

    testWidgets('sin red dice el motivo, y "Actualizar" vuelve a pedir', (
      tester,
    ) async {
      final api = ApiDePrueba((_) async => null);
      await montar(tester, const DondeEstanAhora(), api, mas: reloj());
      expect(
        find.textContaining(
          'No se pudo saber dónde están: Sin conexión con el servidor.',
        ),
        findsOneWidget,
      );

      api.contesta = (_) async => RespuestaFalsa(200, {
        'distribuidores': [distribuidor('D1', 'Felix', ahora)],
      });
      await tester.tap(find.byKey(claveDeActualizarDonde));
      await asentar(tester);
      expect(find.byKey(claveDelDistribuidorAhora('D1')), findsOneWidget);
    });

    testWidgets(
      'se vuelve a pedir solo, y si falla se sigue viendo lo último',
      (tester) async {
        final api = ApiDePrueba(
          (_) async => RespuestaFalsa(200, {
            'distribuidores': [distribuidor('D1', 'Felix', ahora)],
          }),
        );
        await montar(
          tester,
          const DondeEstanAhora(cada: Duration(seconds: 5)),
          api,
          mas: reloj(),
        );
        expect(api.servidor.vistas, hasLength(1));

        api.contesta = (_) async => null;
        await tester.pump(const Duration(seconds: 6));
        await asentar(tester);
        expect(api.servidor.vistas.length, greaterThan(1));
        expect(find.byKey(claveDelDistribuidorAhora('D1')), findsOneWidget);
        expect(
          find.textContaining('Se ve lo último que se supo'),
          findsOneWidget,
        );
      },
    );
  });

  group('la revisión', () {
    Map<String, Object?> ruta(
      String id, {
      Object? revisada = 'no',
      String estado = 'completed',
      String? por,
      String? distribuidor,
    }) => {
      'id': id,
      'routeCode': 'RT-$id',
      'name': 'Ruta $id',
      'status': estado,
      'finishedAt': utc(14, 0),
      if (revisada != 'no') 'revisadaAt': revisada,
      'revisadaPor': ?por,
      if (distribuidor != null)
        'distribuidor': {'id': 'd', 'nombre': distribuidor},
    };

    testWidgets(
      'pendiente: insignia y botón; al confirmar manda la segunda llave y pasa a «Revisada ✓»',
      (tester) async {
        var revisada = false;
        final api = ApiDePrueba((p) async {
          if (p.metodo == 'POST') {
            revisada = true;
            return RespuestaFalsa(
              200,
              ruta('R1', revisada: utc(15, 0), por: 'maikel'),
            );
          }
          return RespuestaFalsa(200, [
            ruta(
              'R1',
              revisada: revisada ? utc(15, 0) : null,
              por: revisada ? 'maikel' : null,
            ),
          ]);
        });
        await montar(tester, const RevisionDeLaRuta(rutaId: 'R1'), api);

        expect(find.byKey(claveDeLaRevisionPendiente), findsOneWidget);
        expect(find.text('Pendiente de revisión'), findsOneWidget);
        await tester.tap(find.byKey(claveDeConfirmarRevision));
        await asentar(tester);

        final post = api.servidor.vistas.singleWhere((p) => p.metodo == 'POST');
        expect(post.ruta, '/routes/R1/revision');
        expect(post.cuerpo, {'confirmar': true});
        expect(find.byKey(claveDeLaRevisionHecha), findsOneWidget);
        expect(find.textContaining('Revisada ✓ por maikel'), findsOneWidget);
        expect(find.byKey(claveDeConfirmarRevision), findsNothing);
      },
    );

    testWidgets(
      'si el servidor rechaza la confirmación, sale su frase y el botón sigue',
      (tester) async {
        final api = ApiDePrueba(
          (p) async => p.metodo == 'POST'
              ? RespuestaFalsa(409, {'error': 'La ruta no está completada'})
              : RespuestaFalsa(200, [ruta('R1', revisada: null)]),
        );
        await montar(tester, const RevisionDeLaRuta(rutaId: 'R1'), api);
        await tester.tap(find.byKey(claveDeConfirmarRevision));
        await asentar(tester);
        expect(find.text('La ruta no está completada'), findsOneWidget);
        expect(find.byKey(claveDeConfirmarRevision), findsOneWidget);
      },
    );

    testWidgets('si el servidor NO manda revisadaAt, no se pinta nada', (
      tester,
    ) async {
      final api = ApiDePrueba((_) async => RespuestaFalsa(200, [ruta('R1')]));
      await montar(tester, const RevisionDeLaRuta(rutaId: 'R1'), api);
      expect(find.byKey(claveDeLaRevisionPendiente), findsNothing);
      expect(find.byKey(claveDeLaRevisionHecha), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    Future<ApiDePrueba> conLista(WidgetTester tester) async {
      final api = ApiDePrueba(
        (_) async => RespuestaFalsa(200, [
          ruta('R1', revisada: null, distribuidor: 'Felix'),
          ruta('R2', revisada: null, distribuidor: 'Juan'),
          ruta(
            'R3',
            revisada: utc(15, 0),
            por: 'maikel',
            distribuidor: 'Felix',
          ),
          ruta('R4'),
        ]),
      );
      await montar(tester, const ListaPorRevisar(), api);
      return api;
    }

    testWidgets('la lista enseña SOLO las pendientes por defecto', (
      tester,
    ) async {
      await conLista(tester);
      expect(find.byKey(claveDeLaFilaPorRevisar('R1')), findsOneWidget);
      expect(find.byKey(claveDeLaFilaPorRevisar('R2')), findsOneWidget);
      expect(find.byKey(claveDeLaFilaPorRevisar('R3')), findsNothing);
      expect(find.byKey(claveDeLaFilaPorRevisar('R4')), findsNothing);
    });

    testWidgets('el buscador filtra por distribuidor', (tester) async {
      await conLista(tester);
      await tester.enterText(find.byType(TextField).first, 'juan');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(claveDeLaFilaPorRevisar('R2')), findsOneWidget);
      expect(find.byKey(claveDeLaFilaPorRevisar('R1')), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(TextosDeLaRevision.nadaDeEsto), findsOneWidget);
    });

    testWidgets('tocar una fila abre su revisión y su recorrido juntos', (
      tester,
    ) async {
      final api = ApiDePrueba((p) async {
        if (p.ruta.endsWith('/track')) {
          return RespuestaFalsa(200, trackDeEjemplo());
        }
        return RespuestaFalsa(200, [
          ruta('R1', revisada: null, distribuidor: 'Felix'),
        ]);
      });
      await montar(tester, const ListaPorRevisar(), api);
      await tester.tap(find.byKey(claveDeLaFilaPorRevisar('R1')));
      await tester.pumpAndSettle();
      await asentar(tester);
      expect(find.byKey(claveDeConfirmarRevision), findsOneWidget);
      expect(
        api.servidor.vistas.any((p) => p.ruta == '/routes/R1/track'),
        isTrue,
      );
    });

    testWidgets('sin ninguna ruta revisable explica de dónde saldrían', (
      tester,
    ) async {
      final api = ApiDePrueba((_) async => RespuestaFalsa(200, [ruta('R4')]));
      await montar(tester, const ListaPorRevisar(), api);
      expect(
        find.textContaining('Ninguna ruta pasa por revisión todavía'),
        findsOneWidget,
      );
    });

    testWidgets('sin red: el motivo y reintentar', (tester) async {
      final api = ApiDePrueba((_) async => null);
      await montar(tester, const ListaPorRevisar(), api);
      expect(
        find.textContaining(
          'No se pudo leer la lista: Sin conexión con el servidor.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets(
    'la pantalla Distribución lleva las dos pestañas y cuenta las pendientes',
    (tester) async {
      final api = ApiDePrueba(
        (p) async => p.ruta == '/routes'
            ? RespuestaFalsa(200, [
                {'id': 'R1', 'status': 'completed', 'revisadaAt': null},
                {'id': 'R2', 'status': 'completed', 'revisadaAt': null},
              ])
            : RespuestaFalsa(200, {'distribuidores': <Object?>[]}),
      );
      await montar(
        tester,
        const PantallaDistribucion(),
        api,
        mas: [relojProvider.overrideWithValue(() => DateTime(2026, 11, 4, 12))],
      );
      expect(find.textContaining('Dónde están'), findsWidgets);
      expect(find.textContaining('Por revisar (2)'), findsWidgets);
    },
  );
}
