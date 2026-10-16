// UN ENLACE AL TABLERO FILTRADO TIENE QUE LLEVAR AL TABLERO FILTRADO.
//
// Y cuando no puede, tiene que DECIRLO. Las dos mitades, en pareja, porque un
// aviso que sale siempre deja de leerse (`CLAUDE.md` §3-quinquies):
//
//  * lo que se entiende se aplica y NO saca ningún aviso;
//  * lo que no se entiende no se aplica y **sale nombrado, con su valor**.
//
// El molde es el de Pedidos —`pantallas/pedidos/datos/filtros_en_la_url.dart` y
// su prueba—, hecho el 24/09/2026 por lo mismo. Aquí el agujero era igual de
// grande y con dos trampas propias:
//
//  * `?dia=31-12-2026` dejaba el tablero **sin acotar por día** y nada lo decía;
//  * `?kmMax=NaN` dejaba una columna vacía que se lee como «no hay nada que
//    colocar», y un `NaN` no es igual ni a sí mismo, así que ninguna comparación
//    lo deja pasar nunca.
//
// Y la de manual: `DateTime.tryParse('1900-02-31')` **no falla** — desborda y
// devuelve el 3 de marzo de 1900. Una fecha imposible se convertía en un día de
// verdad que nadie pidió.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart'
    show sucursalDeLaSesionProvider;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/estado/filtros_en_la_url.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  // ---------------------------------------------------------------------------
  // LEER Y ESCRIBIR, sin pintar nada.
  // ---------------------------------------------------------------------------

  group('leer la dirección', () {
    test('sin parámetros, el tablero de siempre y ningún aviso', () {
      final l = FiltrosEnLaUrl.leer(const {});
      expect(l.noSePudieron, isEmpty);
      expect(l.todoEntro, isTrue);
      expect(l.filtros.hayAlguno, isFalse);
    });

    test('VARIOS vendedores: un `vendedor` por cada uno, y el enlace viejo con UNO se lee', () {
      // Issue 18 de Amado (16/10/2026).
      final direccion = Uri(
        path: FiltrosEnLaUrl.camino,
        queryParameters: FiltrosEnLaUrl.escribir(
          const FiltrosSinColocar(vendedores: ['Ana', 'Pérez, Juan']),
        ),
      );
      expect(direccion.toString(), contains('vendedor=Ana&vendedor=P'));
      expect(direccion.queryParametersAll['vendedor'], ['Ana', 'Pérez, Juan']);
      expect(
        FiltrosEnLaUrl.leerDeUri(direccion).filtros.vendedores,
        ['Ana', 'Pérez, Juan'],
        reason: 'un nombre con coma viaja entero',
      );
      // El enlace de antes, con UN vendedor, sigue valiendo.
      expect(
        FiltrosEnLaUrl.leerDeUri(Uri.parse('/tablero?vendedor=Ana')).filtros.vendedores,
        ['Ana'],
      );
      // Sin repetidos ni vacíos; y sin el parámetro, ninguno (= todos).
      expect(
        FiltrosEnLaUrl.leerDeUri(Uri.parse('/tablero?vendedor=Ana&vendedor=&vendedor=Ana')).filtros.vendedores,
        ['Ana'],
      );
      expect(FiltrosEnLaUrl.leerDeUri(Uri.parse('/tablero')).filtros.vendedores, isEmpty);
    });

    test('lo que se entiende, se aplica', () {
      final l = FiltrosEnLaUrl.leer(const {
        'q': 'malta',
        'municipio': 'Songo',
        'vendedor': 'Ana',
        'desde': '2026-09-12',
        'hasta': '2026-09-14',
        'kmMax': '10',
        'cobro': 'si',
      });
      expect(l.noSePudieron, isEmpty);
      expect(l.filtros.q, 'malta');
      expect(l.filtros.municipio, 'Songo');
      expect(l.filtros.vendedores, ['Ana']);
      expect(l.filtros.desde, DateTime(2026, 9, 12));
      expect(l.filtros.hasta, DateTime(2026, 9, 14));
      expect(l.filtros.kmMax, 10);
      expect(l.filtros.conCobroDeDomicilio, isTrue);
    });

    test(
      'un enlace viejo con `?dia=` lleva a ese día: desde y hasta iguales',
      () {
        // Hasta el 15/10/2026 el filtro era UN día (issue 13 de Amado). Los
        // enlaces que ya circulan no pueden dejar de llevar a donde llevaban.
        final l = FiltrosEnLaUrl.leer(const {'dia': '2026-09-14'});
        expect(l.noSePudieron, isEmpty);
        expect(l.filtros.desde, DateTime(2026, 9, 14));
        expect(l.filtros.hasta, DateTime(2026, 9, 14));
      },
    );

    test('una fecha que no es una fecha SE DICE, con su valor', () {
      for (final clave in ['dia', 'desde', 'hasta']) {
        final l = FiltrosEnLaUrl.leer({clave: '31-12-2026'});
        expect(
          [l.filtros.desde, l.filtros.hasta],
          [null, null],
          reason: 'no se inventa un día; lo que se hace es decirlo',
        );
        expect(l.noSePudieron, ['$clave=31-12-2026']);
      }
    });

    test('el 31 de febrero tampoco es una fecha, aunque `tryParse` lo trague', () {
      // `DateTime.tryParse('1900-02-31')` devuelve el 3 de marzo de 1900. Sin
      // esta comprobación, el tablero salía acotado por un día que nadie pidió.
      expect(DateTime.tryParse('1900-02-31'), DateTime(1900, 3, 3));
      final l = FiltrosEnLaUrl.leer(const {'desde': '1900-02-31'});
      expect(l.filtros.desde, isNull);
      expect(l.noSePudieron, ['desde=1900-02-31']);
    });

    test('`kmMax` que no es un tope: NaN, Infinity y los negativos', () {
      for (final malo in ['NaN', 'Infinity', '-Infinity', '-5', 'diez', '']) {
        final l = FiltrosEnLaUrl.leer({'kmMax': malo});
        expect(
          l.filtros.kmMax,
          isNull,
          reason:
              '`$malo` dejaba la columna vacía, y una columna vacía se lee '
              'como «no hay nada que colocar»',
        );
        if (malo.isNotEmpty) expect(l.noSePudieron, ['kmMax=$malo']);
      }
      // Y el cero SÍ es un tope: lo escribió alguien y se ve en el filtro.
      final cero = FiltrosEnLaUrl.leer(const {'kmMax': '0'});
      expect(cero.filtros.kmMax, 0);
      expect(cero.noSePudieron, isEmpty);
    });

    test('un valor de `cobro` que no está entre los del filtro se dice', () {
      final l = FiltrosEnLaUrl.leer(const {'cobro': 'quizas'});
      expect(l.filtros.conCobroDeDomicilio, isNull);
      expect(l.noSePudieron, ['cobro=quizas']);
    });

    test('LA OTRA MITAD: el ruido de un enlace pegado NO es un filtro fallido', () {
      // `?utm_source=whatsapp` no lo pidió nadie. Avisar de eso sería el aviso
      // que sale siempre, y entonces tampoco se lee el día que importa.
      final l = FiltrosEnLaUrl.leer(const {
        'municipio': 'Songo',
        'utm_source': 'whatsapp',
        'fbclid': 'xxxx',
      });
      expect(l.noSePudieron, isEmpty);
      expect(l.filtros.municipio, 'Songo');
    });

    test('varios a la vez salen todos, no sólo el primero', () {
      final l = FiltrosEnLaUrl.leer(const {
        'dia': '31-12-2026',
        'kmMax': 'NaN',
      });
      expect(l.noSePudieron, containsAll(['dia=31-12-2026', 'kmMax=NaN']));
    });
  });

  group('escribir la dirección', () {
    test('el rango va entero al enlace, cada extremo con su clave', () {
      // La ida y vuelta de abajo compara lo ESCRITO de los dos lados, así que
      // un extremo que no se escribiera se perdería en los dos y saldría igual.
      expect(
        FiltrosEnLaUrl.escribir(
          FiltrosSinColocar(
            desde: DateTime(2026, 9, 12),
            hasta: DateTime(2026, 9, 14),
          ),
        ),
        {'desde': '2026-09-12', 'hasta': '2026-09-14'},
      );
    });

    test(
      'ida y vuelta: lo que la pantalla escribe sabe leerlo la pantalla',
      () {
        final casos = <FiltrosSinColocar>[
          const FiltrosSinColocar(),
          const FiltrosSinColocar(
            q: 'malta',
            municipio: 'Songo',
            vendedores: ['Ana', 'Pérez, Juan'],
            kmMax: 12.5,
            conCobroDeDomicilio: false,
          ),
          FiltrosSinColocar(
            desde: DateTime(2026, 9, 12),
            hasta: DateTime(2026, 9, 14),
          ),
          FiltrosSinColocar(desde: DateTime(2026, 9, 12)),
          FiltrosSinColocar(hasta: DateTime(2026, 9, 14)),
        ];
        for (final f in casos) {
          final ida = FiltrosEnLaUrl.escribir(f);
          // Por una dirección DE VERDAD (con su codificación), no por el mapa.
          final vuelta = FiltrosEnLaUrl.leerDeUri(
            Uri(path: FiltrosEnLaUrl.camino, queryParameters: ida),
          );
          expect(vuelta.noSePudieron, isEmpty, reason: '$ida');
          // `iguales` compara lo que ESCRIBE `escribir`: si éste olvidara un campo, los
          // dos lados lo olvidarían igual. Los vendedores se miran de frente.
          expect(vuelta.filtros.vendedores, f.vendedores, reason: '$ida');
          expect(
            FiltrosEnLaUrl.iguales(vuelta.filtros, f),
            isTrue,
            reason: '$ida',
          );
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Y EN LA PANTALLA, que es donde se lee.
  // ---------------------------------------------------------------------------

  group('la pantalla', () {
    late BaseLocal base;
    late ServidorFalso servidor;

    setUp(() {
      base = baseDePrueba();
      servidor = ServidorFalso((peticion) async => null);
    });

    tearDown(() => base.close());

    Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    /// El tablero ya bajado, dentro del cuerpo y NUNCA en el `setUp`
    /// (`CLAUDE.md` §5).
    Future<void> bajada() async {
      await sembrarSucursal(base);
      await sembrarAlmacen(base);
      await sembrarPedido(base, id: 'cerca', operacion: 'SC06-1257');
      await sembrarPedido(base, id: 'lejos', operacion: 'SC06-0431');
    }

    Future<void> pintar(
      WidgetTester tester,
      Map<String, String> consulta,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dio = Dio()..httpClientAdapter = servidor;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWith((ref) => base),
            // SIN ESPERAS: el tablero pide la foto al abrirse y aquí no hay
            // servidor. Con esperas de verdad, `pumpAndSettle` se cuelga en vez
            // de fallar (`CLAUDE.md` §5).
            clienteApiProvider.overrideWithValue(
              ClienteApi(dio: dio, esperas: const <Duration>[]),
            ),
            almacenSesionProvider.overrideWithValue(
              AlmacenEnMemoria(
                const Sesion(
                  token: 't',
                  refresh: 'r',
                  sub: 'logistico',
                  sucursalId: sucursalStg,
                ),
              ),
            ),
            sucursalDeLaSesionProvider.overrideWithValue(sucursalStg),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PantallaTablero(lectura: FiltrosEnLaUrl.leer(consulta)),
            ),
          ),
        ),
      );
      await asentar(tester);
    }

    testWidgets('lo que no se pudo aplicar SE DICE, con su clave y su valor', (
      tester,
    ) async {
      await bajada();
      await pintar(tester, const {'dia': '31-12-2026'});

      expect(
        find.textContaining(FiltrosEnLaUrl.noSePudieronAplicar),
        findsOneWidget,
      );
      expect(
        find.textContaining('dia=31-12-2026'),
        findsOneWidget,
        reason: '«no se pudo aplicar un filtro» no le dice nada a nadie',
      );
      expect(
        find.text(FiltrosEnLaUrl.yPorEsoLaListaNoEstaAcotada),
        findsOneWidget,
      );

      await desmontar(tester);
    });

    testWidgets('y la franja va ENCIMA del conteo, no debajo', (tester) async {
      // Quien abrió el enlace tiene que enterarse de que el tablero NO está
      // acotado **antes** de leer «Sin colocar (2)» y creérselo.
      await bajada();
      await pintar(tester, const {'kmMax': 'NaN'});

      final franja = tester.getRect(
        find.textContaining(FiltrosEnLaUrl.noSePudieronAplicar),
      );
      final conteo = tester.getRect(find.text('Sin colocar (2)'));
      expect(franja.bottom, lessThanOrEqualTo(conteo.top));

      await desmontar(tester);
    });

    testWidgets('LA OTRA MITAD: con un enlace bueno NO sale ningún aviso', (
      tester,
    ) async {
      await bajada();
      await pintar(tester, const {'municipio': 'Santiago de Cuba'});

      expect(
        find.textContaining(FiltrosEnLaUrl.noSePudieronAplicar),
        findsNothing,
      );
      await desmontar(tester);
    });

    testWidgets('ni con el ruido de un enlace pegado por WhatsApp', (
      tester,
    ) async {
      await bajada();
      await pintar(tester, const {'utm_source': 'whatsapp'});

      expect(
        find.textContaining(FiltrosEnLaUrl.noSePudieronAplicar),
        findsNothing,
        reason: 'un aviso que sale siempre deja de leerse (§3-quinquies)',
      );
      await desmontar(tester);
    });

    testWidgets('y sin enlace tampoco, que es lo que pasa 99 veces de 100', (
      tester,
    ) async {
      await bajada();
      await pintar(tester, const {});

      expect(
        find.textContaining(FiltrosEnLaUrl.noSePudieronAplicar),
        findsNothing,
      );
      await desmontar(tester);
    });
  });
}
