// UN ENLACE A LA LISTA FILTRADA TIENE QUE LLEVAR A LA LISTA FILTRADA.
//
// Y cuando no puede, tiene que DECIRLO. Las dos mitades, en pareja, porque un
// aviso que sale siempre deja de leerse (`CLAUDE.md` §3-quinquies):
//
//  * lo que se entiende se aplica y NO saca ningún aviso;
//  * lo que no se entiende no se aplica y **sale nombrado, con su valor**.
//
// De dónde sale: la QA de la API vio que `?dia=31-12-2026` el servidor la
// ignora y contesta con todos los días —decisión suya, y es la segura—. El
// agujero es de pantalla: si la web se come el parámetro callando, la lista
// sale sin acotar con el enlace diciendo lo contrario. El caso 1 del encargo:
// un resultado creíble y equivocado que ninguna pantalla desmiente.
//
// Y de paso lo que no estaba y el contrato de `pantalla_registrada.dart` pedía:
// Pedidos tiraba el `GoRouterState` entero, así que `/orders?municipio=Centro`
// abría la lista sin filtrar y recargar la vaciaba de filtros.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_en_la_url.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

void main() {
  // ---------------------------------------------------------------------------
  // LEER Y ESCRIBIR, sin pintar nada.
  // ---------------------------------------------------------------------------

  group('leer la dirección', () {
    test('sin parámetros, el arranque acotado de siempre', () {
      final l = FiltrosEnLaUrl.leer(const {});
      expect(l.filtros, const FiltrosPedidos());
      expect(l.noSePudieron, isEmpty);
      expect(l.todoEntro, isTrue);
    });

    test('lo que se entiende, se aplica', () {
      final l = FiltrosEnLaUrl.leer(const {
        'q': 'Cisneros',
        'municipio': 'Centro',
        'reparto': 'en_ruta',
        'desde': '2026-09-01',
        'hasta': '2026-09-15',
        'pagina': '3',
      });
      expect(l.noSePudieron, isEmpty);
      expect(l.filtros.q, 'Cisneros');
      expect(l.filtros.municipio, 'Centro');
      expect(l.filtros.reparto, RepartoFiltro.enRuta);
      expect(l.filtros.desde, DateTime(2026, 9, 1));
      expect(l.filtros.hasta, DateTime(2026, 9, 15));
      expect(l.filtros.pagina, 3);
    });

    test('una fecha que no es una fecha SE DICE, con su valor', () {
      // El caso que trajo la QA de la API, en la forma que le toca a la web.
      final l = FiltrosEnLaUrl.leer(const {'desde': '31-12-2026'});
      expect(l.filtros.desde, isNull, reason: 'no se inventa una fecha');
      expect(l.noSePudieron, ['desde=31-12-2026']);
    });

    test('el 31 de febrero tampoco es una fecha', () {
      final l = FiltrosEnLaUrl.leer(const {'hasta': '1900-02-31'});
      expect(l.filtros.hasta, isNull);
      expect(l.noSePudieron, ['hasta=1900-02-31']);
    });

    test('un rango AL REVÉS se dice, no se arregla a escondidas', () {
      // Darle la vuelta enseñaría pedidos que nadie pidió; aplicarlo tal cual
      // devuelve cero y se lee como «no hubo pedidos esos días».
      final l = FiltrosEnLaUrl.leer(const {
        'desde': '2026-09-20',
        'hasta': '2026-09-10',
      });
      expect(l.filtros.desde, isNull);
      expect(l.filtros.hasta, isNull);
      expect(l.noSePudieron, ['desde=2026-09-20 > hasta=2026-09-10']);
    });

    test('un valor que no está entre los del filtro se dice', () {
      final l = FiltrosEnLaUrl.leer(const {'reparto': 'volando'});
      expect(l.filtros.reparto, RepartoFiltro.cualquiera);
      expect(l.noSePudieron, ['reparto=volando']);
    });

    test('una página que no existe se dice', () {
      expect(FiltrosEnLaUrl.leer(const {'pagina': '0'}).noSePudieron, [
        'pagina=0',
      ]);
      expect(FiltrosEnLaUrl.leer(const {'pagina': '-3'}).noSePudieron, [
        'pagina=-3',
      ]);
      expect(FiltrosEnLaUrl.leer(const {'pagina': 'abc'}).noSePudieron, [
        'pagina=abc',
      ]);
      expect(
        FiltrosEnLaUrl.leer(const {'pagina': '0'}).filtros.pagina,
        1,
        reason: 'y se cae en la primera, no en una consulta con offset negativo',
      );
    });

    test('LA OTRA MITAD: el ruido de un enlace pegado NO es un filtro fallido', () {
      // `?utm_source=whatsapp` no lo pidió nadie. Avisar de eso sería el aviso
      // que sale siempre, y entonces tampoco se lee el día que importa.
      final l = FiltrosEnLaUrl.leer(const {
        'municipio': 'Centro',
        'utm_source': 'whatsapp',
        'fbclid': 'xxxx',
      });
      expect(l.noSePudieron, isEmpty);
      expect(l.filtros.municipio, 'Centro');
    });
  });

  group('escribir la dirección', () {
    test('sólo lo que está puesto de verdad', () {
      expect(FiltrosEnLaUrl.direccion(const FiltrosPedidos()), '/orders');
    });

    test('ida y vuelta: lo escrito se vuelve a leer igual', () {
      final casos = <FiltrosPedidos>[
        const FiltrosPedidos(),
        const FiltrosPedidos.sinNada(),
        const FiltrosPedidos(
          q: 'Doña Rosa',
          municipio: 'Centro Habana',
          vendedores: ['Ana Pérez', 'Pérez, Juan'],
          reparto: RepartoFiltro.enDespacho,
          cotizado: CotizadoFiltro.sinCotizar,
          factura: FacturaFiltro.cuadra,
          archivado: ArchivadoFiltro.si,
          orden: OrdenLocal.pesoDesc,
          pagina: 4,
        ),
        FiltrosPedidos(desde: DateTime(2026, 9, 1), hasta: DateTime(2026, 9, 9)),
      ];
      for (final f in casos) {
        final ida = FiltrosEnLaUrl.escribir(f);
        // Por una dirección DE VERDAD (con su codificación), no por el mapa.
        final uri = Uri(path: FiltrosEnLaUrl.camino, queryParameters: ida);
        final vuelta = FiltrosEnLaUrl.leer(
          uri.queryParameters,
          vendedores: uri.queryParametersAll[FiltrosEnLaUrl.claveVendedor],
        );
        expect(
          vuelta.filtros,
          f,
          reason: 'lo que la pantalla escribe tiene que saber leerlo: $ida',
        );
        expect(vuelta.noSePudieron, isEmpty, reason: '$ida');
      }
    });

    test('«Ver todos los pedidos» viaja en el enlace', () {
      // `factura=` y `archivado=` vacíos son `cualquiera`, no «no venía». Es el
      // enlace que uno manda cuando quiere que el otro lo vea TODO.
      const todos = FiltrosPedidos.sinNada();
      final url = FiltrosEnLaUrl.escribir(todos);
      expect(url['factura'], '');
      expect(url['archivado'], '');
      expect(
        FiltrosEnLaUrl.leer({
          for (final e in url.entries) e.key: '${e.value}',
        }).filtros.arranqueAcotado,
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Y EN LA PANTALLA, que es donde se lee.
  // ---------------------------------------------------------------------------

  group('la pantalla', () {
    late BaseLocal base;
    final ahora = DateTime(2026, 9, 14, 16, 5);

    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    Future<void> pintar(
      WidgetTester tester,
      Map<String, String> consulta,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
          ],
          child: MaterialApp(
            home: Scaffold(body: PantallaPedidos(consulta: consulta)),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }

    /// La base ya bajada, dentro del cuerpo y NUNCA en el `setUp`
    /// (`CLAUDE.md` §5): lo que Drift deja empezado en el `setUp` no avanza
    /// dentro del reloj falso y la prueba se cuelga en vez de fallar.
    Future<void> bajada() async {
      await sembrarLosOnce(base);
      final registro = RegistroDeFrescura(base, reloj: () => ahora);
      for (final c in const [
        Colecciones.pedidos,
        Colecciones.renglones,
        Colecciones.productos,
      ]) {
        await registro.marcar(
          c,
          hasta: '2026-09-14T16:00:00Z',
          bajadaAt: ahora.subtract(const Duration(minutes: 20)),
        );
      }
    }

    testWidgets('el enlace acota la lista de verdad', (tester) async {
      await bajada();
      // Sin filtro son 8 con el arranque acotado; sólo uno es de Camagüey.
      await pintar(tester, const {'municipio': 'Camagüey'});

      final conteo = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((t) => t.contains('pedidos, del más nuevo'));
      expect(
        conteo,
        '4 pedidos, del más nuevo al más viejo',
        reason:
            'el enlace llevaba a la lista acotada; sin él son 8. Antes del '
            '24/09/2026 salían los 8 y nada lo decía.',
      );
      await desmontar(tester);
    });

    testWidgets('lo que no se pudo aplicar SE DICE, con su valor', (
      tester,
    ) async {
      await bajada();
      await pintar(tester, const {'desde': '31-12-2026'});

      expect(
        find.textContaining(FiltrosEnLaUrl.noSePudieronAplicar),
        findsOneWidget,
      );
      expect(
        find.textContaining('desde=31-12-2026'),
        findsOneWidget,
        reason: '«no se pudo aplicar un filtro» no le dice nada a nadie',
      );
      expect(
        find.text(FiltrosEnLaUrl.yPorEsoLaListaNoEstaAcotada),
        findsOneWidget,
      );
      await desmontar(tester);
    });

    testWidgets('LA OTRA MITAD: con un enlace bueno NO sale ningún aviso', (
      tester,
    ) async {
      await bajada();
      await pintar(tester, const {'municipio': 'Camagüey'});

      expect(
        find.textContaining(FiltrosEnLaUrl.noSePudieronAplicar),
        findsNothing,
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
