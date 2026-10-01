// LA FRANJA DE ARRIBA PUEDE MENTIR 59 MINUTOS — 01/10/2026.
//
// En el teléfono, la franja decía **«Datos de las 8:46»** toda la mañana
// mientras el Tablero, dos centímetros más abajo, decía **«Visto por última vez
// a las 9:07»** y estaba al día. Veintiún minutos de diferencia, y puede llegar a
// cincuenta y nueve.
//
// Ninguna de las dos mentía, y eso es lo que lo hacía difícil de ver:
//
//  * la franja salía de `laMasVieja` sobre las **NUEVE** colecciones, con el
//    motivo —bueno— de que «una pantalla no está al día si una de las colecciones
//    que usa no lo está»;
//  * y dentro de las nueve va `almacenes`, que se refresca sola **una vez por
//    hora a propósito** (`nucleo/sincro/bajada.dart`: son el 82 % de lo que se
//    gasta en reposo);
//  * el Tablero ya preguntaba sólo por las dos colecciones que ÉL usa.
//
// Con el umbral del ámbar en una hora justa, eso hacía que la franja rozara el
// borde **cada hora por diseño**. Es el §3-quinquies tal cual: un aviso que sale
// siempre deja de leerse, y entonces tampoco se lee el día que importa.
//
// LA FORMA DE ESTAS PRUEBAS es la del §3-ter, y es lo que las hace servir: se
// monta con la base **VACÍA** y se siembra **DESPUÉS**, sin volver a montar.
// Sembrar en el `setUp` es justo el caso que pasa igual sin el arreglo.
//
// Y van en pareja, porque las dos direcciones importan y sólo una es peligrosa:
//
//  1. una colección que esta pantalla NO usa no puede arrastrarla hacia atrás;
//  2. una colección que esta pantalla SÍ usa **tiene que** arrastrarla. Ésta es
//     la que no se puede perder nunca: la franja puede quedarse corta —hoy lo
//     hace—, lo que no puede es decirse **más fresca** de lo que está.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/franja_de_estado.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  // Las horas del caso real, al minuto.
  final ahora = DateTime(2026, 10, 1, 9, 10);
  final deLosAlmacenes = DateTime(2026, 10, 1, 8, 46);
  final deTodoLoDemas = DateTime(2026, 10, 1, 9, 7);

  late BaseLocal base;

  // La base se ABRE aquí y se ESCRIBE dentro del cuerpo (§5): lo que Drift deja
  // empezado en el `setUp` corre fuera del reloj falso y no avanza dentro, y eso
  // no falla — se cuelga, que es peor.
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> montar(WidgetTester tester, List<String> colecciones) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp(
          theme: temaDeReparto(),
          home: Scaffold(body: FranjaDeEstado(colecciones: colecciones)),
        ),
      ),
    );
    await tester.pump();
  }

  /// La mañana del caso: todo bajó a las 9:07 y los almacenes a las 8:46,
  /// porque sólo se piden una vez por hora.
  Future<void> sembrarLaManana() async {
    final frescura = RegistroDeFrescura(base, reloj: () => ahora);
    for (final coleccion in Colecciones.todas) {
      await frescura.marcar(
        coleccion,
        hasta: null,
        bajadaAt: coleccion == Colecciones.almacenes
            ? deLosAlmacenes
            : deTodoLoDemas,
      );
    }
  }

  testWidgets(
    'en Pedidos dice la hora de Pedidos, no la de los almacenes de hace media hora',
    (tester) async {
      await montar(tester, ColeccionesDePantalla.pedidos);

      // Base vacía y ya mirada: «sin descargar» es un estado de verdad.
      await asentar(tester);
      expect(find.text('Sin descargar todavía'), findsOneWidget);

      // Y ahora la mañana entera, con la franja ya delante y sin volver a montar.
      await sembrarLaManana();
      await asentar(tester);

      expect(
        find.text('Datos de las 9:07'),
        findsOneWidget,
        reason:
            'Pedidos no pinta ni un almacén: la hora a la que bajaron los '
            'almacenes no dice nada de si estos pedidos están al día',
      );
      expect(
        find.text('Datos de las 8:46'),
        findsNothing,
        reason:
            'ÉSTE es el caso del 01/10/2026: la franja decía 8:46 encima de una '
            'pantalla al día a las 9:07, y rozaba el ámbar cada hora por diseño '
            'porque los almacenes se piden una vez por hora a propósito',
      );

      await base.close();
      await tester.pump();
    },
  );

  testWidgets(
    'en Rutas SÍ manda el almacén: es su dato, y la franja no puede decirse '
    'más fresca de lo que está',
    (tester) async {
      // Rutas declara `almacenes` porque de ellos sale el punto de partida de
      // cada ruta. Aquí la hora vieja es la verdad, y hay que decirla.
      await montar(tester, ColeccionesDePantalla.rutas);
      await asentar(tester);
      await sembrarLaManana();
      await asentar(tester);

      expect(
        find.text('Datos de las 8:46'),
        findsOneWidget,
        reason:
            'sin esto el arreglo cambiaría de sentido: una pantalla que SÍ usa '
            'una colección vieja diría estar más fresca de lo que está, y eso es '
            'lo único que esta franja no puede hacer. Hoy se queda corta, que es '
            'el lado seguro',
      );
      expect(find.text('Datos de las 9:07'), findsNothing);

      await base.close();
      await tester.pump();
    },
  );

  testWidgets(
    'una pantalla que no pinta nada de la copia no inventa una hora, y NO dice '
    '«sin descargar»',
    (tester) async {
      // Sincronización, el canal con PEDIDO y el mapa leen en vivo del servidor
      // o de disco. Ahí una hora de bajada no significa nada — y caerse a «Sin
      // descargar todavía» sería acusar de vacía una copia que está entera, en
      // ámbar, encendiendo el gesto de traer un día que ya está dentro.
      await montar(tester, ColeccionesDePantalla.ninguna);
      await asentar(tester);

      expect(find.text('Sin descargar todavía'), findsNothing);
      expect(find.text('Datos de las 9:07'), findsNothing);
      expect(find.text('Datos de las 8:46'), findsNothing);

      // Y la franja sigue estando: lo que se quita es la hora, no la pieza.
      expect(
        find.byType(FranjaDeEstado),
        findsOneWidget,
        reason:
            'la nube tachada, «N sin subir» y lo huérfano no dependen de '
            'ninguna colección y tienen que seguir saliendo',
      );

      await base.close();
      await tester.pump();
    },
  );
}
