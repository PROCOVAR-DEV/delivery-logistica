// «ELIMINAR» TIENE QUE VERSE QUE BORRA, Y TIENE QUE CABERLE EL DEDO —
// 28/09/2026.
//
// Dos cosas que salieron de quitarle el fondo a los botones, y las dos son de
// verdad y no estéticas:
//
//  1. **Se veía igual que cualquier otra cosa.** Era un `TextButton` pelado: la
//     palabra «Eliminar», en el mismo oro con el que está escrito «Editar» y
//     todo lo demás. Borra una ruta entera y no lo decía por ningún lado. Ahora
//     es un `BotonDestructivo` — rojo, con contorno y con papelera —, que es la
//     regla de la casa: sin relleno, lo que diferencia un botón es **el color,
//     el borde y el icono**.
//
//  2. **Medía 32 px de alto de toque.** El renglón del importe era un
//     `SizedBox(height: 32)` y el botón de dentro heredaba esos 32: dieciséis
//     por debajo del mínimo de Material, en la pantalla que se usa de pie en un
//     almacén, y con el importe de la ruta justo al lado para quedárselo. Se
//     daba por bueno como algo que «viene de antes y no es cosa de esto». Hoy sí
//     lo es: sin relleno detrás, apuntar a la palabra es lo único que hay.
//
// Y esta prueba existe porque una mutación enseñó que **no había ninguna**:
// devolver el renglón a `height: 32` dejaba las 359 pruebas de rutas en verde.
// Las de `botones_sin_fondo_test.dart` miden un botón suelto, y un botón suelto
// se agranda solo; lo que encoge es el botón metido en una caja de alto fijo, y
// eso hay que medirlo **aquí dentro**, sobre la tarjeta de verdad.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/lista_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 28, 10, 30);

  setUp(() => base = baseDePrueba());
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

  /// Monta la lista con UNA ruta en curso. La base se siembra **dentro del
  /// cuerpo** y no en el `setUp`: lo que Drift deja empezado fuera del reloj
  /// falso no avanza dentro, y la prueba se cuelga en vez de fallar (§5 del
  /// `CLAUDE.md`).
  Future<void> pintar(WidgetTester tester, double ancho) async {
    await sembrarCatalogo(base);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
    await sembrarRuta(
      base,
      id: 'R1',
      codigo: 'RT-20260928-001',
      estado: EstadoRuta.enCurso,
      creada: ahora,
    );

    tester.view.physicalSize = Size(ancho, 844);
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
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(
            body: ListaDeRutas(deLaPestana: PestanaRutas.enCurso),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  for (final ancho in [390.0, 1400.0]) {
    testWidgets(
      'a ${ancho.toInt()} px el botón de eliminar una ruta admite el dedo',
      (tester) async {
        await pintar(tester, ancho);

        final boton = find.byType(BotonDestructivo);
        expect(
          boton,
          findsOneWidget,
          reason:
              'la tarjeta de una ruta en curso tiene que llevar su botón de '
              'eliminar, y tiene que ser el destructivo: rojo, con borde y con '
              'papelera. Un TextButton pelado se lee igual que «Editar»',
        );

        // El rectángulo que recibe el dedo, no el que se dibuja.
        final caja = tester.getRect(boton);
        expect(
          caja.height,
          greaterThanOrEqualTo(Botones.altoTactilMinimo),
          reason:
              'el botón de eliminar mide ${caja.height.toStringAsFixed(1)} px '
              'de alto tocable a ${ancho.toInt()} px, por debajo de los '
              '${Botones.altoTactilMinimo.toInt()} de Material. El renglón que '
              'lo contiene lo está achicando: mira el SizedBox del importe en '
              'lista_rutas.dart. Sin relleno detrás, apuntar a la palabra es lo '
              'único que hay',
        );
        expect(
          caja.width,
          greaterThanOrEqualTo(48),
          reason:
              'el botón de eliminar mide ${caja.width.toStringAsFixed(1)} px '
              'de ancho tocable a ${ancho.toInt()} px',
        );

        // Y NO SE COME NI TAPA AL IMPORTE DE AL LADO. Los dos van en el mismo
        // renglón, y el importe es el dato que se mira de la tarjeta.
        final importe = find.text('—');
        if (importe.evaluate().isNotEmpty) {
          final cajaImporte = tester.getRect(importe.first);
          expect(
            cajaImporte.right,
            lessThanOrEqualTo(caja.left + 1),
            reason:
                'el botón de eliminar se monta encima del importe de la ruta',
          );
        }

        await desmontar(tester);
      },
    );
  }

  testWidgets('borrar una ruta se ve que borra: rojo, con borde y con papelera', (
    tester,
  ) async {
    await pintar(tester, 390);

    final dentro = find.descendant(
      of: find.byType(BotonDestructivo),
      matching: find.byType(Icon),
    );
    expect(
      dentro,
      findsOneWidget,
      reason:
          'el botón de eliminar se quedó sin icono. Con el fondo quitado, el '
          'icono es uno de los tres rasgos que dicen que esto destruye algo',
    );
    expect(
      tester.widget<Icon>(dentro).icon,
      Icons.delete_outline,
      reason: 'el icono de borrar tiene que ser una papelera y no otra cosa',
    );

    // El color se lee de lo que se PINTA, no del `Text`: el color de un rótulo
    // de botón lo pone el `ButtonStyle`, así que mirar el `TextStyle` del `Text`
    // devuelve null y la prueba pasaría sin comprobar nada.
    final estilo = tester
        .widget<OutlinedButton>(
          find.descendant(
            of: find.byType(BotonDestructivo),
            matching: find.byType(OutlinedButton),
          ),
        )
        .style!;
    expect(
      estilo.foregroundColor?.resolve(const {}),
      Colores.rojo,
      reason:
          'el botón de eliminar no va en rojo: se lee igual que «Editar» y que '
          'cualquier otro enlace de la tarjeta',
    );
    final borde = estilo.side?.resolve(const {});
    expect(
      borde?.color,
      Colores.rojo,
      reason: 'el botón de eliminar se quedó sin su contorno rojo',
    );
    expect(
      borde!.width,
      Botones.grosorFuerte,
      reason:
          'el contorno del botón de eliminar es fino: se confunde con un botón '
          'secundario cualquiera',
    );
    final fondo = estilo.backgroundColor?.resolve(const {});
    expect(
      fondo == null || fondo.a == 0,
      isTrue,
      reason:
          'el botón de eliminar volvió a llevar fondo. Los botones de esta '
          'aplicación van SIN FONDO (§4 del CLAUDE.md de la raíz)',
    );

    await desmontar(tester);
  });
}
