import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` —el tipo de lo que lleva `ProviderScope.overrides`— NO lo exporta
// `flutter_riverpod`; vive aqui. `riverpod` llega igualmente como dependencia de
// `flutter_riverpod`, asi que el aviso es de forma, no de fondo.
// ignore: depend_on_referenced_packages
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/navegacion/aviso_de_version_nueva.dart';
import 'package:reparto/nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'package:reparto/navegacion/pantalla_registrada.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/actualizacion/comprobador.dart';
import 'package:reparto/nucleo/actualizacion/version_publicada.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../apoyo/base_de_prueba.dart';

/// EL AVISO DE VERSION NUEVA, en el armazon.
///
/// Las pruebas van **en pareja** a proposito (`CLAUDE.md` §3-quinquies): por cada
/// una que comprueba que el aviso sale cuando toca hay otra que comprueba que
/// **no sale** cuando no. Un aviso que sale siempre deja de leerse, y entonces
/// tampoco se lee el dia que importa.
///
/// Y el otro par es el de los destinos: **en la web se recarga, en el aparato se
/// instala**. La palabra «recargar» en la pantalla de un chofer le manda a
/// buscar un boton que no existe.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  const publicada = VersionPublicada(
    version: '1.5.0',
    compilacion: 12,
    notas: 'El cierre de ruta ya no pierde las fotos.',
    descargas: {'android': 'https://descargas.test/reparto-1.5.0.apk'},
  );

  /// Dos pantallas de mentira: lo que se prueba es el armazon, no el Panel.
  List<PantallaRegistrada> pantallas() => <PantallaRegistrada>[
    PantallaRegistrada(
      ruta: '/uno',
      titulo: 'Uno',
      icono: Icons.looks_one_outlined,
      enElMenu: true,
      colecciones: ColeccionesDePantalla.panel,
      construir: (contexto, estado) => const Text('cuerpo de uno'),
    ),
    PantallaRegistrada(
      ruta: '/dos',
      titulo: 'Dos',
      icono: Icons.looks_two_outlined,
      enElMenu: true,
      colecciones: ColeccionesDePantalla.panel,
      construir: (contexto, estado) => const Text('cuerpo de dos'),
    ),
  ];

  /// Deja que Drift y los providers se pongan al dia.
  ///
  /// `pumpAndSettle` NO vale: la franja de estado deja ruedas girando y el vigia
  /// de la web deja un temporizador de cinco minutos, y para `pumpAndSettle` las
  /// dos cosas son animaciones sin fin — se colgaria en vez de fallar, que es lo
  /// peor que puede hacer una prueba (`CLAUDE.md` §5). Varias pasadas cortas
  /// hacen lo mismo y terminan siempre.
  ///
  /// Hacen falta VARIAS y no dos: entre que la comprobacion contesta y que el
  /// stream de la cola trae el numero nuevo hay mas de un fotograma, y el aviso
  /// necesita las dos cosas a la vez.
  Future<void> asentar(WidgetTester tester, [int pasadas = 12]) async {
    for (var i = 0; i < pasadas; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> montar(
    WidgetTester tester, {
    required List<Override> overrides,
    Size tamano = const Size(390, 900),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 21, 8, 30)),
          ...overrides,
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(pantallas: pantallas(), inicial: '/uno'),
        ),
      ),
    );
    await asentar(tester);
  }

  /// Desmontar no es ceremonia: Drift suelta un temporizador al cancelar sus
  /// consultas y `flutter_test` lo comprueba ANTES de los `tearDown`.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  final elAviso = find.textContaining('versión nueva');
  final recargar = find.text('Recargar ahora');
  final ahoraNo = find.text('Ahora no');

  // ══════════════════════════════════════════════════════════ LA WEB: recargar

  group('la web: lo que hace falta es RECARGAR', () {
    /// Un lector de huella que va contestando la lista, y repite la ultima.
    ({List<Override> overrides, int Function() lecturas}) conHuellas(
      List<String?> respuestas,
    ) {
      var i = 0;
      return (
        overrides: [
          trabajaSinConexionProvider.overrideWithValue(false),
          lectorDeLaHuellaProvider.overrideWithValue(() async {
            final cual =
                respuestas[i < respuestas.length - 1
                    ? i
                    : respuestas.length - 1];
            i++;
            return cual;
          }),
        ],
        lecturas: () => i,
      );
    }

    testWidgets('SALE cuando el servidor sirve un paquete distinto', (
      tester,
    ) async {
      await montar(
        tester,
        overrides: conHuellas(['aaa111', 'bbb222']).overrides,
      );

      // La PRIMERA respuesta es la referencia, no una novedad.
      expect(elAviso, findsNothing);

      await tester.pump(cadaCuantoSeMiraElPaquete);
      await asentar(tester);

      expect(
        elAviso,
        findsOneWidget,
        reason:
            'el servidor sirve otra huella que la que cargo esta pestaña y el '
            'aviso no salio: quien la tenga abierta desde ayer seguira viendo '
            'un filtro que no esta o un arreglo que no llego',
      );
      expect(recargar, findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('NO SALE mientras el servidor sirve el mismo paquete', (
      tester,
    ) async {
      await montar(tester, overrides: conHuellas(['aaa111']).overrides);

      for (var vuelta = 0; vuelta < 4; vuelta++) {
        await tester.pump(cadaCuantoSeMiraElPaquete);
        await asentar(tester);
      }

      expect(
        elAviso,
        findsNothing,
        reason:
            'la huella servida no ha cambiado ni una vez y el aviso salio '
            'igual: un aviso que sale siempre deja de leerse, y entonces '
            'tampoco se lee el dia que importa (CLAUDE.md §3-quinquies)',
      );
      await desmontar(tester);
    });

    testWidgets('NO SALE cuando no se pudo preguntar: no saber no es noticia', (
      tester,
    ) async {
      // `null` es sin red, un 4xx, o un `index.html` sin huella —el servidor de
      // desarrollo no la lleva—. Ninguno de los tres es una version nueva.
      await montar(tester, overrides: conHuellas([null]).overrides);

      for (var vuelta = 0; vuelta < 3; vuelta++) {
        await tester.pump(cadaCuantoSeMiraElPaquete);
        await asentar(tester);
      }

      expect(
        elAviso,
        findsNothing,
        reason:
            'no se pudo leer la huella ni una vez y aun asi se aviso de una '
            'version nueva que nadie sabe si existe',
      );
      await desmontar(tester);
    });

    testWidgets('detectado una vez, deja de preguntar', (tester) async {
      final lector = conHuellas(['aaa111', 'bbb222']);
      await montar(tester, overrides: lector.overrides);

      await tester.pump(cadaCuantoSeMiraElPaquete);
      await asentar(tester);
      expect(elAviso, findsOneWidget);
      final trasDetectar = lector.lecturas();

      await tester.pump(cadaCuantoSeMiraElPaquete * 3);
      await asentar(tester);

      expect(
        lector.lecturas(),
        trasDetectar,
        reason:
            'con el aviso ya puesto no queda nada que descubrir y se siguio '
            'preguntando cada cinco minutos',
      );
      await desmontar(tester);
    });

    testWidgets('«Ahora no» lo calla media hora, y VUELVE', (tester) async {
      await montar(
        tester,
        overrides: conHuellas(['aaa111', 'bbb222']).overrides,
      );
      await tester.pump(cadaCuantoSeMiraElPaquete);
      await asentar(tester);
      expect(elAviso, findsOneWidget);

      await tester.tap(ahoraNo);
      await asentar(tester);
      expect(elAviso, findsNothing);

      await tester.pump(cuantoCallaElAhoraNo - const Duration(minutes: 1));
      await asentar(tester);
      expect(
        elAviso,
        findsNothing,
        reason: 'el «Ahora no» tiene que durar la media hora entera',
      );

      await tester.pump(const Duration(minutes: 2));
      await asentar(tester);
      expect(
        elAviso,
        findsOneWidget,
        reason:
            'el aviso no se puede matar, solo aplazar: una ✕ definitiva la '
            'pulsa todo el mundo el primer dia sin leer y ya nunca avisa',
      );
      await desmontar(tester);
    });
  });

  // ═══════════════════════════════════════════════════ EL APARATO: instalar

  group('la APK y el escritorio: hay que INSTALAR', () {
    List<Override> conEstado(EstadoDeActualizacion estado) => [
      trabajaSinConexionProvider.overrideWithValue(true),
      actualizacionProvider.overrideWith((ref) async => estado),
    ];

    testWidgets('SALE con la version publicada, y NO dice recargar', (
      tester,
    ) async {
      await montar(
        tester,
        overrides: conEstado(
          const SePuedeActualizar(
            publicada: publicada,
            enlace: 'https://descargas.test/reparto-1.5.0.apk',
          ),
        ),
      );

      expect(find.textContaining('1.5.0'), findsOneWidget);
      expect(find.text('Cómo instalarla'), findsOneWidget);
      expect(
        find.textContaining('ecarga'),
        findsNothing,
        reason:
            'en el aparato no hay nada que recargar: la version nueva es un '
            'fichero que hay que bajarse e instalar, y mandar a un chofer a '
            'recargar es mandarle a buscar un boton que no existe',
      );
      await desmontar(tester);
    });

    testWidgets('NO SALE cuando esta al dia', (tester) async {
      await montar(tester, overrides: conEstado(const AlDia()));
      expect(elAviso, findsNothing);
      await desmontar(tester);
    });

    testWidgets('NO SALE cuando NO SE SUPO: no saber no es una noticia', (
      tester,
    ) async {
      await montar(tester, overrides: conEstado(const NoSeSupo()));
      expect(
        elAviso,
        findsNothing,
        reason:
            'no se pudo mirar la version —sin red, o el servidor contesto algo '
            'raro— y se pinto como si hubiera una nueva',
      );
      await desmontar(tester);
    });

    testWidgets('NO SALE cuando no hay descarga para esta plataforma', (
      tester,
    ) async {
      await montar(
        tester,
        overrides: conEstado(const NoAplica('no hay descarga para linux')),
      );
      expect(elAviso, findsNothing);
      await desmontar(tester);
    });
  });

  // ══════════════════════════ LA COLA MANDA: primero sube, después actualiza

  group('con trabajo sin subir manda la cola', () {
    /// LA COMPROBACION DE VERDAD, con una PUERTA para poder abrirla DESPUES de
    /// sembrar. Lee la cola en la base, como hace `ComprobadorDeActualizacion`.
    ///
    /// Asi se monta con la base VACIA y se siembra dentro del cuerpo
    /// (`CLAUDE.md` §3-ter): sembrar antes es justo el caso que un `Future`
    /// resuelve bien, y entonces la prueba no comprueba nada.
    ///
    /// **La puerta se crea AQUI, o sea dentro del cuerpo de la prueba, y NUNCA
    /// en el `setUp`.** Es la trampa de §5 con otra cara: el `setUp` corre fuera
    /// del reloj falso del `tester`, y lo que espera a un `Completer` nacido
    /// alli no despierta dentro. Con la puerta en el `setUp`, la comprobacion se
    /// quedaba cargando para siempre, el aviso no salia nunca y la prueba fallaba
    /// diciendo «no encuentro el texto» — que apunta a la pantalla y no al sitio
    /// donde estaba el problema.
    ({List<Override> overrides, Completer<void> puerta, int Function() vueltas})
    laComprobacion() {
      final puerta = Completer<void>();
      var vueltas = 0;
      return (
        puerta: puerta,
        vueltas: () => vueltas,
        overrides: [
          trabajaSinConexionProvider.overrideWithValue(true),
          actualizacionProvider.overrideWith((ref) async {
            vueltas++;
            await puerta.future;
            final pendientes = await base.cuantosPendientes();
            return pendientes > 0
                ? PrimeroSube(publicada: publicada, pendientes: pendientes)
                : const SePuedeActualizar(
                    publicada: publicada,
                    enlace: 'https://descargas.test/reparto-1.5.0.apk',
                  );
          }),
        ],
      );
    }

    Future<List<String>> sembrarLaCola(int cuantos) async {
      final cola = ColaDeSalida(base);
      return [
        for (var i = 0; i < cuantos; i++)
          await cola.encolar(
            metodo: 'POST',
            ruta: '/api/routes/r$i/close',
            cuerpo: {'entregados': i},
          ),
      ];
    }

    /// Lo que deja una subida que salio bien: el servidor acepta y la cola marca.
    Future<void> subir(Iterable<String> claves) async {
      final cola = ColaDeSalida(base);
      for (final clave in claves) {
        await cola.resolver(
          clave,
          const ResultadoApunte(estado: EstadoResultado.aplicado),
        );
      }
    }

    testWidgets('dice CUANTOS quedan y NO ofrece instalar', (tester) async {
      final comprobacion = laComprobacion();
      await montar(tester, overrides: comprobacion.overrides);
      await sembrarLaCola(3);
      comprobacion.puerta.complete();
      await asentar(tester);

      expect(find.textContaining('Te quedan 3'), findsOneWidget);
      expect(
        find.text('Cómo instalarla'),
        findsNothing,
        reason:
            'con la cola pendiente NO se ofrece instalar: si la firma no '
            'coincide, Android obliga a desinstalar y desinstalar borra la base '
            'local, que es el trabajo del dia sin subir '
            '(docs/actualizaciones.md §1.1 y §4)',
      );
      await desmontar(tester);
    });

    testWidgets(
      'AL TERMINAR LA SUBIDA el aviso viejo se va y queda el que aplica',
      (tester) async {
        final comprobacion = laComprobacion();
        await montar(tester, overrides: comprobacion.overrides);
        final claves = await sembrarLaCola(2);
        comprobacion.puerta.complete();
        await asentar(tester);
        expect(find.textContaining('Te quedan 2'), findsOneWidget);

        await subir(claves);
        await asentar(tester);

        expect(
          find.textContaining('Te quedan'),
          findsNothing,
          reason:
              'la cola ya esta vacia y el aviso sigue diciendo «primero sube»: '
              'la persona hizo justo lo que se le pidio y el aviso no se entero '
              '(docs/integracion-pendiente.md, el invalidate que falta)',
        );
        expect(
          find.text('Cómo instalarla'),
          findsOneWidget,
          reason:
              'sin volver a preguntar, el «primero sube» se queda puesto hasta '
              'el siguiente arranque y nunca aparece el aviso que SI se puede '
              'atender',
        );
        expect(
          comprobacion.vueltas(),
          2,
          reason: 'se tenia que haber vuelto a preguntar exactamente una vez',
        );
        await desmontar(tester);
      },
    );

    testWidgets(
      'NO vuelve a preguntar si la cola se mueve pero no llega a cero',
      (tester) async {
        final comprobacion = laComprobacion();
        await montar(tester, overrides: comprobacion.overrides);
        final claves = await sembrarLaCola(3);
        comprobacion.puerta.complete();
        await asentar(tester);
        expect(comprobacion.vueltas(), 1);

        // Sube UNO de los tres. Quedan dos: la respuesta no ha cambiado.
        await subir([claves.first]);
        await asentar(tester);

        expect(
          comprobacion.vueltas(),
          1,
          reason:
              'se volvio a preguntar por cada apunte que sube: eso es una '
              'peticion de red por movimiento de la cola para preguntar algo '
              'cuya respuesta no ha cambiado',
        );
        expect(
          find.textContaining('Te quedan 2'),
          findsOneWidget,
          reason:
              'el numero sale de la cola en vivo, no del que traia el estado: un '
              '«te quedan 3» encima de una cola de 2 es un numero creible y '
              'equivocado',
        );
        await desmontar(tester);
      },
    );
  });

  // ═══════════════════════════════════════════════ la huella, letra por letra

  group('la huella del paquete', () {
    test('sale del index.html que sirve el despliegue', () {
      expect(
        huellaDe(
          '<body><script src="flutter_bootstrap.js?v=1a2b3c4d5e6f" async>'
          '</script></body>',
        ),
        '1a2b3c4d5e6f',
      );
    });

    test('un index.html SIN huella no es una version nueva', () {
      // El que sale de `flutter build web` tal cual, y el del servidor de
      // desarrollo. La huella se la pega `deploy/Dockerfile.app`.
      expect(
        huellaDe('<body><script src="flutter_bootstrap.js" async></script>'),
        isNull,
        reason:
            'sin huella no hay nada que comparar, y comparar `null` con `null` '
            'avisaria en cada vuelta o no avisaria nunca — las dos mal',
      );
    });
  });
}
