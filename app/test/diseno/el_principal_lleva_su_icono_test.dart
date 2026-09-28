// EL BOTÓN PRINCIPAL LLEVA SU ICONO, Y NO SE LE PUEDE OLVIDAR — 28/09/2026.
//
// Jose, el mismo día que se quitaron los rellenos:
//
//     «te dije bien claro q sin background y de colores y los bordes y iconos lo
//      difrerenciaban»
//
// Son **tres** rasgos. El tema (`lib/diseno/tema.dart`, `Botones`) sabe poner
// dos: el color y el borde. El tercero no puede ponerlo un `ButtonStyle` —el
// icono es un hijo del widget, no una propiedad del estilo—, así que dependía de
// que cada pantalla escribiera `.icon(...)`. Contado esa tarde: **25
// `FilledButton(` sin icono contra 9 `FilledButton.icon(`**. O sea que la
// mayoría de las acciones principales de la aplicación se quedaban con dos
// rasgos de los tres, y el que faltaba es justo el que se lee de reojo, con sol
// y sin distinguir colores.
//
// Se arregla como se arregló lo destructivo: con un widget, no con un estilo.
// `BotonPrincipal` pide el icono en el constructor y no tiene valor por defecto.
//
// # LAS DOS COSAS QUE ESTA PRUEBA MIDE, Y POR QUÉ SON DOS
//
//  1. **Que el widget lo pone.** Un `BotonPrincipal` montado enseña un icono y
//     es el que se le pidió. Esto se mira sobre el árbol de verdad, no sobre el
//     estilo: el estilo no sabe nada de iconos.
//  2. **Que nadie se lo salta.** Lo anterior no vale de nada si mañana alguien
//     escribe `FilledButton(...)` a secas en una pantalla: saldría un botón oro,
//     con su borde de 2 px y sin glifo, y ninguna prueba de widget lo vería
//     porque nadie monta esa pantalla aquí. Por eso la segunda parte **barre
//     `lib/` entero** y cuenta los ficheros que leyó.
//
// # Y CUENTA CUÁNTAS COSAS MIDIÓ
//
// Es la lección cara del mismo día, escrita en `botones_sin_fondo_test.dart`:
// `find.byType(ButtonStyleButton)` compara el `runtimeType` exacto y encuentra
// **cero** botones, así que el bucle no da una vuelta y la prueba pasa en verde
// sin medir nada. Aquí, cada bucle dice antes cuántas cosas esperaba encontrar.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/diseno/tema.dart';

Widget _banco(Widget hijo) => MaterialApp(
  theme: temaDeReparto(),
  home: FondoDePapel(child: Scaffold(body: Center(child: hijo))),
);

Future<void> _aAncho(WidgetTester tester, double ancho) async {
  tester.view.physicalSize = Size(ancho, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Todos los `.dart` de `lib/`, ya **sin comentarios**.
///
/// Sin quitarlos, el barrido de abajo se caza a sí mismo: la cabecera de
/// `tema.dart` escribe `FilledButton(...)` cuatro veces para contar esta misma
/// historia, y una prueba que falla por lo que dice un comentario es una prueba
/// que se acaba desactivando.
Map<String, String> _elCodigoDeLib() {
  final raiz = Directory('lib');
  expect(
    raiz.existsSync(),
    isTrue,
    reason:
        'esta prueba se lee a sí misma desde `lib/` y no la encuentra: se está '
        'ejecutando desde otra carpeta que `app/`, y así no barre nada',
  );
  final fuera = RegExp(r'/\*.*?\*/', dotAll: true);
  final deLinea = RegExp(r'//.*');
  return {
    for (final f in raiz.listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart'))
        f.path: f
            .readAsStringSync()
            .replaceAll(fuera, '')
            .split('\n')
            .map((l) => l.replaceAll(deLinea, ''))
            .join('\n'),
  };
}

/// Lo que se le pasó a `icono:` en cada `BotonPrincipal(...)` de `lib/`.
///
/// Se lee del código y no del árbol montado a propósito: montar las veintitantas
/// pantallas aquí es imposible, y lo que hay que vigilar —que cada acción tenga
/// **el suyo**— se ve en la llamada.
List<({String fichero, String expresion})> _losIconosPedidos(
  Map<String, String> codigo,
) {
  final llamada = RegExp(r'\bBotonPrincipal\s*\(');
  final elCampo = RegExp(r'\bicono:');
  final salida = <({String fichero, String expresion})>[];

  for (final MapEntry(key: fichero, value: fuente) in codigo.entries) {
    // El widget se define en `tema.dart`; ahí no hay llamadas que contar.
    if (fichero.endsWith('diseno/tema.dart')) continue;
    for (final m in llamada.allMatches(fuente)) {
      // Los argumentos: desde el paréntesis hasta el que lo cierra.
      var hondo = 1;
      var i = m.end;
      while (i < fuente.length && hondo > 0) {
        if (fuente[i] == '(') hondo++;
        if (fuente[i] == ')') hondo--;
        i++;
      }
      final cuerpo = fuente.substring(m.end, i - 1);
      final campo = elCampo.firstMatch(cuerpo);
      expect(
        campo,
        isNotNull,
        reason:
            'un BotonPrincipal de $fichero no dice `icono:`. Eso no debería '
            'compilar siquiera —es obligatorio en el constructor—, así que si '
            'esto salta es que a alguien le dieron un valor por defecto y el '
            'nivel principal volvió a quedarse con dos rasgos de los tres',
      );
      // Hasta la coma de su nivel: un ternario cuenta entero.
      var j = campo!.end;
      var dentro = 0;
      final expresion = StringBuffer();
      while (j < cuerpo.length) {
        final c = cuerpo[j];
        if ('([{'.contains(c)) dentro++;
        if (')]}'.contains(c)) dentro--;
        if (c == ',' && dentro == 0) break;
        expresion.write(c);
        j++;
      }
      salida.add((fichero: fichero, expresion: expresion.toString().trim()));
    }
  }
  return salida;
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // 1. EL WIDGET LO PONE, Y PONE EL QUE SE LE PIDIÓ.
  // ───────────────────────────────────────────────────────────────────────────

  for (final ancho in [390.0, 1400.0]) {
    testWidgets('a ${ancho.toInt()} px un boton principal ensena su icono', (
      tester,
    ) async {
      await _aAncho(tester, ancho);
      await tester.pumpWidget(
        _banco(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BotonPrincipal(
                texto: 'Guardar',
                icono: Icons.save_outlined,
                alPulsar: () {},
              ),
              BotonPrincipal(
                texto: 'Imprimir',
                icono: Icons.print_outlined,
                alPulsar: () {},
              ),
              // Apagado: el icono no se va con el `onPressed`.
              const BotonPrincipal(
                texto: 'Reintentar',
                icono: Icons.refresh,
                alPulsar: null,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final botones = find.byType(BotonPrincipal).evaluate();
      expect(
        botones.length,
        3,
        reason:
            'esta prueba tiene que medir los tres botones del banco y ha '
            'encontrado ${botones.length}: si no encuentra ninguno pasa en '
            'verde sin haber medido nada',
      );

      // Y CADA UNO CON EL SUYO, no «hay un icono por ahí».
      for (final (esperado, rotulo) in [
        (Icons.save_outlined, 'Guardar'),
        (Icons.print_outlined, 'Imprimir'),
        (Icons.refresh, 'Reintentar'),
      ]) {
        final elBoton = find.widgetWithText(BotonPrincipal, rotulo);
        final iconos = find
            .descendant(of: elBoton, matching: find.byType(Icon))
            .evaluate();
        expect(
          iconos.length,
          1,
          reason:
              'el boton «$rotulo» ensena ${iconos.length} iconos y tiene que '
              'ensenar exactamente uno. Sin relleno detras, el icono es uno de '
              'los TRES rasgos que separan un nivel de otro (§4 del CLAUDE.md '
              'de la raiz): sin el, este boton se lee igual que cualquier otro '
              'mando de color',
        );
        expect(
          (iconos.single.widget as Icon).icon,
          esperado,
          reason:
              'el boton «$rotulo» ensena un glifo que no es el que se le pidio. '
              'El icono dice QUE HACE la accion: uno igual para todos no '
              'diferencia nada, que es justo lo que se vino a arreglar',
        );
      }

      // EL DEDO SIGUE CABIENDO. Meterle un icono a un boton no puede encogerlo.
      for (final elemento in botones) {
        final caja = tester.getRect(find.byWidget(elemento.widget));
        expect(
          caja.height,
          greaterThanOrEqualTo(Botones.altoTactilMinimo),
          reason:
              'un boton principal mide ${caja.height.toStringAsFixed(1)} px de '
              'alto tactil a ${ancho.toInt()} px, por debajo de los '
              '${Botones.altoTactilMinimo.toInt()} de Material',
        );
      }
    });
  }

  testWidgets('el icono va del color de la palabra, y el boton es el principal', (
    tester,
  ) async {
    await _aAncho(tester, 390);
    await tester.pumpWidget(
      _banco(
        BotonPrincipal(
          texto: 'Guardar',
          icono: Icons.save_outlined,
          alPulsar: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // El estilo que de verdad tiene el boton montado: el del tema, porque
    // `BotonPrincipal` NO escribe ningun `style:` — si lo escribiera, habria dos
    // sitios donde mirar y esta comparacion es lo que lo caza.
    final tema = Theme.of(tester.element(find.byType(FilledButton)));
    final puesto = tema.filledButtonTheme.style!;
    final esperado = Botones.principal();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).style,
      isNull,
      reason:
          'BotonPrincipal se escribio un `style:` propio: el nivel lo decide el '
          'tema (diseno/tema.dart, Botones) y un estilo suelto es el segundo '
          'sitio donde mirar, que es lo que Botones existe para no tener',
    );
    expect(
      puesto.side?.resolve(const {})?.width,
      esperado.side?.resolve(const {})?.width,
      reason: 'el boton principal no lleva el borde de su nivel',
    );
    expect(
      puesto.foregroundColor?.resolve(const {}),
      Colores.primario,
      reason: 'el boton principal no lleva el color de su nivel',
    );
    expect(
      puesto.iconColor?.resolve(const {}),
      puesto.foregroundColor?.resolve(const {}),
      reason:
          'el glifo sale de otro color que la palabra: se esta pintando con el '
          'iconTheme de la aplicacion —tinta suave— y no con el del boton, asi '
          'que el rasgo que tenia que separar niveles sale gris en los tres',
    );
  });

  testWidgets('con `iconoAlFinal` la flecha va DETRAS de la palabra', (
    tester,
  ) async {
    await _aAncho(tester, 390);
    await tester.pumpWidget(
      _banco(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BotonPrincipal(
              texto: 'Siguiente',
              icono: Icons.arrow_forward,
              iconoAlFinal: true,
              alPulsar: () {},
            ),
            BotonPrincipal(
              texto: 'Volver',
              icono: Icons.arrow_back,
              alPulsar: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Se MIDE con `getRect`, no se mira el orden de los `children`: lo que se lee
    // es donde cae el glifo en la pantalla.
    double x(String rotulo, Type que) => tester
        .getRect(
          find.descendant(
            of: find.widgetWithText(BotonPrincipal, rotulo),
            matching: find.byType(que),
          ),
        )
        .center
        .dx;

    expect(
      x('Siguiente', Icon),
      greaterThan(x('Siguiente', Text)),
      reason:
          'la flecha de «Siguiente» esta a la IZQUIERDA de la palabra: una '
          'flecha que apunta a la derecha puesta delante se lee como «volver», '
          'que es lo contrario de lo que hace el boton',
    );
    expect(
      x('Volver', Icon),
      lessThan(x('Volver', Text)),
      reason: 'la flecha de «Volver» se fue detras de la palabra',
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. NADIE SE LO SALTA. Esto barre `lib/` entero.
  // ───────────────────────────────────────────────────────────────────────────

  test('no queda ni un boton de nivel principal pedido a pelo en lib/', () {
    final codigo = _elCodigoDeLib();
    expect(
      codigo.length,
      greaterThan(100),
      reason:
          'el barrido ha leido ${codigo.length} ficheros de lib/ y la '
          'aplicacion tiene muchos mas: si lee cuatro, pasa en verde sin haber '
          'mirado donde estan los botones',
    );

    // `FilledButton(` y `ElevatedButton(` a secas. Los dos cuelgan del MISMO
    // nivel principal en el tema (`filledButtonTheme` y `elevatedButtonTheme`
    // toman `Botones.principal()`), asi que los dos salen oro, con borde de 2 px
    // y sin glifo. `FilledButton.icon(` no casa con esto: lleva punto en medio.
    final aPelo = RegExp(r'\b(FilledButton|ElevatedButton)\s*\(');
    final encontrados = <String>[];
    for (final MapEntry(key: fichero, value: fuente) in codigo.entries) {
      // `tema.dart` es donde vive `BotonPrincipal`, que por dentro SI construye
      // un `FilledButton.icon`. Aqui no hay nada que prohibir.
      if (fichero.endsWith('diseno/tema.dart')) continue;
      for (final (numero, linea) in fuente.split('\n').indexed) {
        if (aPelo.hasMatch(linea)) {
          encontrados.add('$fichero:${numero + 1}  ${linea.trim()}');
        }
      }
    }

    expect(
      encontrados,
      isEmpty,
      reason:
          'estos mandos son de nivel principal y se piden a pelo, asi que el '
          'tema les pone el color y el borde y el icono no se lo pone nadie:\n'
          '  ${encontrados.join('\n  ')}\n'
          'Se piden con `BotonPrincipal(texto:, icono:, alPulsar:)`, que obliga '
          'a decir el icono de ESA accion. Si el mando no es una accion —una '
          'pestana, por ejemplo— tampoco es un boton principal: eso se escribe '
          'aparte y se explica, como `_Pestana` en diseno/pestanas.dart',
    );
  });

  test('cada accion lleva SU icono, y no el mismo veinticinco veces', () {
    final pedidos = _losIconosPedidos(_elCodigoDeLib());

    expect(
      pedidos.length,
      greaterThanOrEqualTo(20),
      reason:
          'el barrido ha encontrado ${pedidos.length} llamadas a BotonPrincipal '
          'y el dia que esto se escribio habia 27: si encuentra dos, el '
          'recuento de abajo no comprueba nada',
    );

    // Los que se escriben con un glifo literal. Los tres que lo reciben por
    // parametro —el vacio con invitacion, el paso a paso del panel, el aviso de
    // version— lo cogen de quien los usa, y ahi el recuento se hace solo.
    final glifo = RegExp(r'Icons\.\w+');
    final cuenta = <String, int>{};
    for (final p in pedidos) {
      for (final m in glifo.allMatches(p.expresion)) {
        cuenta[m.group(0)!] = (cuenta[m.group(0)!] ?? 0) + 1;
      }
    }

    expect(
      cuenta.length,
      greaterThanOrEqualTo(10),
      reason:
          'toda la aplicacion usa ${cuenta.length} glifos distintos para sus '
          'acciones principales. Jose nombro el icono como uno de los tres '
          'rasgos que diferencian un boton: un puñado de glifos repartidos '
          'entre ${pedidos.length} acciones no diferencia nada. Guardar, '
          'Anadir, Armar, Imprimir, Traer, Entregar, Reintentar — cada uno el '
          'suyo',
    );

    final elMasRepetido = cuenta.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    final total = cuenta.values.reduce((a, b) => a + b);
    expect(
      elMasRepetido.value * 2,
      lessThan(total),
      reason:
          '${elMasRepetido.key} sale ${elMasRepetido.value} veces de $total: es '
          'mas de la mitad de las acciones principales de la aplicacion con el '
          'mismo dibujo. Eso es un icono generico con otro nombre',
    );
  });
}
