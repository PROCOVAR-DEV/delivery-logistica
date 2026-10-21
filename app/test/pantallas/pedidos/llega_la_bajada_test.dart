// LA WEB ABRE CON LA BASE VACIA, Y LA PANTALLA TIENE QUE ENTERARSE DESPUES.
//
// Jose, 17/09/2026, mirando `reparto.procovar.cloud/orders` en el navegador:
// arriba «299 pedidos», abajo «Mostrando 1-50 de 299», y en medio «Esta
// pantalla no se ha descargado todavia». Tres consultas sobre la misma tabla
// diciendo cosas distintas.
//
// El motivo: `pedidosDescargadosProvider` era un `FutureProvider`, o sea UNA
// sola respuesta, la del instante en que la pantalla se pinta. En la APK eso no
// se nota —se entra con el aparato ya configurado y la marca esta puesta desde
// antes—, pero **la web arranca con la base en memoria y vacia en cada carga**,
// asi que esa unica respuesta era siempre «no se descargo», y no se volvia a
// preguntar nunca. El total y la pagina son `Stream` y si se enteraban de la
// bajada; el cartel de en medio, no.
//
// Por eso esta prueba no monta la pantalla con los datos ya puestos: los pone
// DESPUES, con la pantalla delante y sin volver a montarla, que es justo el
// orden en que pasa en un navegador.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/cajon_detalle_pedido.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<ProviderContainer> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: PantallaPedidos()),
        ),
      ),
    );
    await asentar(tester);
    return ProviderScope.containerOf(
      tester.element(find.byType(PantallaPedidos)),
    );
  }

  testWidgets(
    'la bajada llega con la pantalla ya abierta: el cartel de «sin descargar» '
    'se va solo y salen los pedidos, sin recargar',
    (tester) async {
      // 1. Como abre la web: base vacia, nada bajado todavia.
      final contenedor = await pintar(tester);
      expect(
        find.text(SinDescargar.textoDeLaPantallaVacia),
        findsOneWidget,
        reason: 'con la base vacia y sin marca, esto es lo correcto',
      );

      // 2. Llega la bajada. Nadie recarga ni vuelve a montar la pantalla: es lo
      //    que hace el ciclo por detras un segundo despues de entrar.
      await sembrarLosOnce(base);
      await RegistroDeFrescura(
        base,
        reloj: () => ahora,
      ).marcar(Colecciones.pedidos, hasta: null, bajadaAt: ahora);
      await asentar(tester);

      // 3. Y la pantalla se entera.
      expect(
        find.text(SinDescargar.textoDeLaPantallaVacia),
        findsNothing,
        reason:
            'los pedidos ya estan aqui: dejar el cartel puesto es acusar al '
            'servidor de algo que no pasa, y es lo que se veia en produccion',
      );
      expect(
        find.textContaining('8 facturas'),
        findsOneWidget,
        reason: 'el mismo arranque acotado que ve la pantalla ya sembrada',
      );

      // 4. Y LOS DESPLEGABLES TAMBIEN.
      //
      // Esto es el hallazgo del auditor: se arreglo el cartel y se dejo
      // congelado, a doce lineas, el proveedor que llena «Municipio del
      // cliente» y «Vendedor del pedido». Era el MISMO fallo en la MISMA
      // pantalla: la lista salia y los dos desplegables se quedaban vacios para
      // siempre, sin forma de filtrar sin recargar.
      //
      // Se mira el TEXTO del boton, que es lo que ve quien esta delante: con
      // facetas, el desplegable de municipio deja de decir «Todos los
      // municipios» y pasa a decir cuantos hay.
      final facetas = contenedor.read(facetasPedidosProvider);
      expect(
        facetas.value?.municipios,
        isNotEmpty,
        reason:
            'sin esto los filtros de la pantalla se quedan vacios aunque los '
            'pedidos ya esten: es el mismo fallo que el cartel, al lado',
      );
      expect(facetas.value?.vendedores, isNotEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'en la WEB no sale NI UNA de las frases del aparato: dice «Cargando» y '
    'punto',
    (tester) async {
      // La pantalla que Jose nombró. En la web salía «Esta pantalla no se ha
      // descargado todavía. Con conexión baja sola» en CADA carga —su base nace
      // vacía— y ahí hay dos de las frases que lleva todo el día pidiendo que
      // desaparezcan: «se ha descargado» y «con conexión baja sola».
      //
      // «No sé cuántas veces tengo que decirte que la web siempre está en
      // línea, nunca se desconecta. Quita todo lo que tenga que ver con eso.»
      await Destino.comoSiFueraWeb(() async {
        await pintar(tester);

        expect(
          find.text(SinDescargar.textoDeLaPantallaVacia),
          findsNothing,
          reason: 'la frase entera, que es la que él vio',
        );
        // Y palabra por palabra, por si alguien la reescribe con otras letras.
        for (final delAparato in const [
          'Con conexión baja sola',
          'no se ha descargado',
          'aparato',
        ]) {
          expect(
            find.textContaining(delAparato),
            findsNothing,
            reason: '«$delAparato» es del mundo del teléfono, no del navegador',
          );
        }
        expect(find.textContaining('Cargando'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
      });
    },
  );

  testWidgets('y en la FICHA de un pedido que no está tampoco: era el último sitio con '
      'la frase suelta', (tester) async {
    // «No está en el aparato» + «Con conexión baja sola», sin ninguna guarda
    // de plataforma. Camino estrecho —se abre la ficha de un pedido que ya no
    // está en la base en ese instante— pero es la frase literal que Jose lleva
    // seis veces pidiendo que desaparezca, y la encontró el auditor
    // enumerando pantalla por pantalla.
    await Destino.comoSiFueraWeb(() async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
          ],
          child: MaterialApp(
            localizationsDelegates: delegacionesDeIdioma,
            supportedLocales: idiomas,
            // Un id que no existe: la ficha no encuentra nada.
            home: const Scaffold(
              body: CajonDetallePedido(pedidoId: 'no-existe'),
            ),
          ),
        ),
      );
      await asentar(tester);

      for (final delAparato in const [
        'No está en el aparato',
        'Con conexión baja sola',
        'no se ha descargado',
      ]) {
        expect(
          find.textContaining(delAparato),
          findsNothing,
          reason: '«$delAparato» no puede salir en un navegador',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
