// LOS BOTONES VAN SIN FONDO — 28/09/2026.
//
// Jose, y no era la primera vez:
//
//     «y arregla los botones te dije bien claro q sin background y de colores y
//      los bordes y iconos lo difrerenciaban»
//
// La regla esta en el §4 del `CLAUDE.md` de la raiz y la decision en
// `lib/diseno/tema.dart`, en [Botones]. Esto es lo que la vigila.
//
// # POR QUE ESTE FICHERO MIDE Y NO MIRA
//
// La forma tentadora de probar esto es `expect(find.byType(FilledButton),
// findsOneWidget)`, y **no prueba nada**: encuentra el boton estando relleno,
// estando sin borde y estando sin icono. Un `findsOneWidget` sobre un boton dice
// que el boton existe, que es lo unico que nadie ha dudado nunca.
//
// Asi que aqui se resuelve el `ButtonStyle` de verdad —el que sale de mezclar el
// tema con lo que ponga la pantalla, leido del `ButtonStyleButton` ya montado— y
// se le pregunta por cada estado de Material: reposo, encima, pulsado, enfocado
// y apagado. Si en alguno de los cinco contesta un color con alfa, hay fondo.
//
// Y lo que no se puede resolver de un estilo —los 48 px del dedo, el icono de un
// destructivo— se mide sobre el arbol montado con `tester.getRect` y
// `tester.widget`, a 390 y a 1400.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/diseno/tema.dart';

/// Los cinco estados en los que Material puede pintar un boton. Probar solo el
/// de reposo es como no probarlo: el `backgroundColor` de un `FilledButton` es
/// un `WidgetStateProperty`, y lo facil es dejarlo transparente en calma y que
/// vuelva a rellenarse al pasarle el dedo por encima.
const _estados = <String, Set<WidgetState>>{
  'en reposo': <WidgetState>{},
  'con el raton encima': {WidgetState.hovered},
  'pulsado': {WidgetState.pressed},
  'con el foco': {WidgetState.focused},
  'apagado': {WidgetState.disabled},
};

/// Los tres niveles, tal y como los sirve el tema. Si manana alguien anade un
/// cuarto, se anade aqui y las cinco pruebas de abajo lo cubren solas.
Map<String, ButtonStyle> _losTresNiveles() => {
  'principal': Botones.principal(),
  'secundario': Botones.secundario(),
  'destructivo': Botones.destructivo(),
};

/// Y los que salen del `ThemeData`, que es lo que de verdad reciben los 51
/// `FilledButton` de la aplicacion. Se leen del tema y no de [Botones] a
/// proposito: entre uno y otro esta el cable, y el cable se puede desenchufar.
Map<String, ButtonStyle> _losDelTema() {
  final tema = temaDeReparto();
  return {
    'filledButtonTheme': tema.filledButtonTheme.style!,
    'elevatedButtonTheme': tema.elevatedButtonTheme.style!,
    'outlinedButtonTheme': tema.outlinedButtonTheme.style!,
    'textButtonTheme': tema.textButtonTheme.style!,
  };
}

/// El estilo que de verdad tiene un boton YA MONTADO: el del tema mezclado con
/// el que le haya puesto la pantalla encima. Es lo unico que dice como se pinta;
/// mirar solo el tema deja pasar cualquier `style:` suelto.
ButtonStyle _estiloDe(WidgetTester tester, Finder boton) {
  final w = tester.widget<ButtonStyleButton>(boton);
  final tema = Theme.of(tester.element(boton));
  // El tema del que cuelga cada clase de boton. Se busca a mano y no con
  // `themeStyleOf`, que es de la propia clase y el analizador no deja llamar
  // desde fuera.
  final delTema = switch (w) {
    FilledButton() => tema.filledButtonTheme.style,
    ElevatedButton() => tema.elevatedButtonTheme.style,
    OutlinedButton() => tema.outlinedButtonTheme.style,
    TextButton() => tema.textButtonTheme.style,
    _ => null,
  };
  final suyo = w.style;
  // EL ORDEN IMPORTA Y AQUI YA ESTUVO AL REVES. `a.merge(b)` se queda con lo de
  // `a` y solo rellena con `b` lo que `a` deja en blanco, asi que lo del widget
  // va DELANTE: es lo que manda sobre el tema, igual que en la pantalla. Escrito
  // al reves, esta prueba leia el tema creyendo que leia el boton — o sea, no
  // habria cazado ni un `style:` suelto, que es la mitad de lo que viene a
  // vigilar.
  return suyo == null
      ? (delTema ?? const ButtonStyle())
      : (delTema == null ? suyo : suyo.merge(delTema));
}

/// EL COLOR QUE DE VERDAD SE PINTA DETRAS DE UN BOTON.
///
/// Esto ya no es el estilo: es el `Material` que el boton monta por dentro, con
/// el `backgroundColor` **ya resuelto** para el estado en el que esta ahora
/// mismo. Un estilo se puede leer bien y pintarse mal —basta con que algo lo
/// pise por debajo—, y esta es la unica lectura que no se puede discutir.
Color? _loQueSePinta(WidgetTester tester, Element boton) {
  final material = find.descendant(
    of: find.byWidget(boton.widget),
    matching: find.byType(Material),
  );
  return tester.widget<Material>(material.first).color;
}

Color? _fondoEn(ButtonStyle estilo, Set<WidgetState> estado) =>
    estilo.backgroundColor?.resolve(estado);

BorderSide? _bordeEn(ButtonStyle estilo, Set<WidgetState> estado) =>
    estilo.side?.resolve(estado);

Color? _letraEn(ButtonStyle estilo, Set<WidgetState> estado) =>
    estilo.foregroundColor?.resolve(estado);

/// Una pantalla de mentira con el tema de la casa y el papel debajo, que es
/// sobre lo que se ven estos botones de verdad.
Widget _banco(Widget hijo) => MaterialApp(
  theme: temaDeReparto(),
  home: FondoDePapel(
    child: Scaffold(body: Center(child: hijo)),
  ),
);

Future<void> _aAncho(WidgetTester tester, double ancho) async {
  tester.view.physicalSize = Size(ancho, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // 1. NINGUNO LLEVA FONDO. Es la regla, dicha con numeros.
  // ───────────────────────────────────────────────────────────────────────────

  test('ningun nivel de boton lleva fondo, en ninguno de los cinco estados', () {
    for (final MapEntry(key: nivel, value: estilo) in {
      ..._losTresNiveles(),
      ..._losDelTema(),
    }.entries) {
      for (final MapEntry(key: cuando, value: estado) in _estados.entries) {
        final fondo = _fondoEn(estilo, estado);
        expect(
          fondo == null || fondo.a == 0,
          isTrue,
          reason:
              'el boton «$nivel» se pinta con un fondo $cuando. Los botones de '
              'esta aplicacion van SIN FONDO: lo que los diferencia es el '
              'color, el borde y el icono. Esta en el §4 del CLAUDE.md de la '
              'raiz y la decision vive en lib/diseno/tema.dart, en Botones — '
              'no se arregla poniendo un style: en la pantalla',
        );
      }
    }
  });

  testWidgets('un boton montado de verdad no pinta ningun rectangulo de color', (
    tester,
  ) async {
    await _aAncho(tester, 390);
    await tester.pumpWidget(
      _banco(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(onPressed: () {}, child: const Text('Guardar')),
            OutlinedButton(onPressed: () {}, child: const Text('Cancelar')),
            const BotonDestructivo(texto: 'Eliminar', alPulsar: null),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Se lee del arbol montado, no de [Botones]: aqui ya esta aplicado el tema
    // entero y cualquier `style:` que hubiera puesto la pantalla encima.
    for (final tipo in [FilledButton, OutlinedButton]) {
      for (final elemento in find.byType(tipo).evaluate()) {
        final estilo = _estiloDe(tester, find.byWidget(elemento.widget));
        for (final MapEntry(key: cuando, value: estado) in _estados.entries) {
          final fondo = _fondoEn(estilo, estado);
          expect(
            fondo == null || fondo.a == 0,
            isTrue,
            reason:
                'un $tipo ya montado se pinta con fondo $cuando: el tema dice '
                'una cosa y la pantalla otra',
          );
        }

        // Y LO QUE DE VERDAD SE PINTA, que es otra lectura y no la misma dos
        // veces: el `Material` de dentro del boton, con el color ya resuelto.
        final pintado = _loQueSePinta(tester, elemento);
        expect(
          pintado == null || pintado.a == 0,
          isTrue,
          reason:
              'un $tipo se DIBUJA con el rectangulo relleno de $pintado, diga '
              'lo que diga su estilo',
        );
      }
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. EL BORDE. Es la mitad de lo que se ve de un boton sin relleno.
  // ───────────────────────────────────────────────────────────────────────────

  test('los tres niveles tienen borde, y el principal mas grueso que el otro', () {
    final principal = _bordeEn(Botones.principal(), const {});
    final secundario = _bordeEn(Botones.secundario(), const {});
    final destructivo = _bordeEn(Botones.destructivo(), const {});

    for (final MapEntry(key: nivel, value: borde) in {
      'principal': principal,
      'secundario': secundario,
      'destructivo': destructivo,
    }.entries) {
      expect(
        borde,
        isNotNull,
        reason:
            'el boton «$nivel» se quedo SIN BORDE. Sin relleno y sin borde, de '
            'un boton no queda mas que una palabra suelta: no se ve que sea '
            'pulsable',
      );
      expect(
        borde!.width,
        greaterThan(0),
        reason: 'el borde de «$nivel» mide 0, que es no tener borde',
      );
      expect(
        borde.color.a,
        greaterThan(0),
        reason: 'el borde de «$nivel» es transparente, que es no tener borde',
      );
    }

    // EL GROSOR ES LO QUE SEPARA LA JERARQUIA SIN MIRAR EL COLOR. Quien no
    // distingue el oro del gris tiene que seguir viendo cual es el importante.
    expect(
      principal!.width,
      greaterThan(secundario!.width),
      reason:
          'el principal y el secundario tienen el mismo grosor de borde: sin '
          'relleno, el grosor es lo unico que los separa para quien no separa '
          'los colores',
    );
    expect(
      destructivo!.width,
      greaterThan(secundario.width),
      reason: 'el destructivo tiene el borde de un secundario cualquiera',
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. EL DESTRUCTIVO NO PUEDE PARECERSE A LOS OTROS DOS.
  // ───────────────────────────────────────────────────────────────────────────

  test('el destructivo no se confunde con el principal ni con el secundario', () {
    final rojo = _letraEn(Botones.destructivo(), const {})!;
    final oro = _letraEn(Botones.principal(), const {})!;
    final tinta = _letraEn(Botones.secundario(), const {})!;

    // LA VARA, y es pariente de la que `paleta_test.dart` le pide a dos
    // insignias. Comparar con `!=` no vale: dos rojos a un grado de distancia
    // son distintos para Dart y el mismo rojo para quien mira.
    //
    // Dos colores se separan por una de tres cosas, cualquiera de ellas sola:
    // 30 grados de tono, 0,20 de luz, o 0,25 de saturacion. La tercera es la que
    // sostiene el principal contra el secundario, y no es un apano: el oro de
    // texto y la tinta comparten tono —los dos salen del mismo calido, eso es lo
    // que hace que sean una paleta— y lo que los separa de verdad es que uno es
    // un color con fuerza y el otro es casi neutro. Un oro y un gris oscuro no
    // se confunden por mucho que la rueda los ponga cerca.
    void separados(
      String a,
      Color ca,
      String b,
      Color cb, {
      bool soloTono = false,
    }) {
      final ha = HSLColor.fromColor(ca);
      final hb = HSLColor.fromColor(cb);
      final bruta = (ha.hue - hb.hue).abs();
      final tono = bruta > 180 ? 360 - bruta : bruta;
      final luz = (ha.lightness - hb.lightness).abs();
      final sat = (ha.saturation - hb.saturation).abs();
      expect(
        soloTono ? tono > 30 : (tono > 30 || luz > 0.20 || sat > 0.25),
        isTrue,
        reason:
            'el boton «$a» y el boton «$b» se ven igual: '
            '${tono.toStringAsFixed(0)} grados de tono, '
            '${luz.toStringAsFixed(2)} de luz y '
            '${sat.toStringAsFixed(2)} de saturacion. Sin relleno, el color es '
            'uno de los tres rasgos que los separan, y borrar una ruta no puede '
            'parecerse a guardarla',
      );
    }

    // El principal y el destructivo son los dos que COMPARTEN GROSOR DE BORDE,
    // asi que a esos dos el grosor no los separa y el color tiene que hacerlo
    // solo — y por tono, que es lo unico que se lee de reojo. Por eso van con
    // `soloTono`: que el rojo sea un poco mas claro que el oro no vale de nada
    // en un patio con sol.
    separados('destructivo', rojo, 'principal', oro, soloTono: true);
    separados('destructivo', rojo, 'secundario', tinta);
    separados('principal', oro, 'secundario', tinta);

    // Y el borde va del mismo color que la letra en los dos que mandan: si el
    // destructivo tuviera la letra roja y el contorno del color del principal,
    // de lejos seria el principal.
    expect(
      _bordeEn(Botones.destructivo(), const {})!.color,
      rojo,
      reason: 'el destructivo lleva un borde que no es el suyo',
    );
    expect(
      _bordeEn(Botones.principal(), const {})!.color,
      oro,
      reason: 'el principal lleva un borde que no es el suyo',
    );
  });

  testWidgets('un boton destructivo SIEMPRE ensena su icono', (tester) async {
    await _aAncho(tester, 390);
    await tester.pumpWidget(
      _banco(const BotonDestructivo(texto: 'Eliminar', alPulsar: null)),
    );
    await tester.pumpAndSettle();

    final iconos = find.descendant(
      of: find.byType(BotonDestructivo),
      matching: find.byType(Icon),
    );
    expect(
      iconos,
      findsOneWidget,
      reason:
          'un boton de borrar sin icono se queda con un rasgo menos de los '
          'tres. El icono es lo que se lee cuando el boton se ve de reojo, con '
          'sol, o cuando quien mira no separa el rojo del oro',
    );

    // Y del color del boton, no del gris del `iconTheme` de la aplicacion.
    final estilo = _estiloDe(tester, find.byType(OutlinedButton));
    expect(
      estilo.iconColor?.resolve(const {}),
      Colores.rojo,
      reason:
          'la papelera sale de otro color que la palabra: el icono se pinta con '
          'el iconTheme de la aplicacion en vez de con el del boton',
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. EL CONTRASTE. Esto se usa en la calle, con sol y con un telefono barato.
  // ───────────────────────────────────────────────────────────────────────────

  test('los tres se leen sobre el papel y sobre el blanco de una tarjeta', () {
    // Un boton sin fondo es texto y una linea. Si el color es flojo, el boton no
    // existe — y «no vale por bonito» es literalmente lo que hay que aplicar
    // aqui. Texto: 4.5. Contorno: 3, que es lo que WCAG le pide a algo que no es
    // texto.
    for (final fondo in {
      'papel': Colores.papel,
      'tarjeta': Colores.blanco,
    }.entries) {
      for (final MapEntry(key: nivel, value: estilo)
          in _losTresNiveles().entries) {
        final letra = _letraEn(estilo, const {})!;
        expect(
          contrasteEntre(letra, fondo.value),
          greaterThanOrEqualTo(4.5),
          reason:
              'el texto del boton «$nivel» no se lee sobre ${fondo.key}. Sin '
              'relleno detras, el color del texto es el boton entero',
        );
        final borde = _bordeEn(estilo, const {})!.color;
        expect(
          contrasteEntre(borde, fondo.value),
          greaterThanOrEqualTo(3),
          reason:
              'el contorno del boton «$nivel» no se ve sobre ${fondo.key}: al '
              'sol es una raya que hay que adivinar',
        );
      }
    }
  });

  test('un boton apagado se sigue viendo, y se ve que esta apagado', () {
    for (final MapEntry(key: nivel, value: estilo)
        in _losTresNiveles().entries) {
      final vivo = _letraEn(estilo, const {})!;
      final muerto = _letraEn(estilo, {WidgetState.disabled})!;
      expect(
        muerto,
        isNot(vivo),
        reason:
            'el boton «$nivel» apagado se pinta igual que encendido: invita a '
            'pulsar algo que no hace nada',
      );
      expect(
        contrasteEntre(muerto, Colores.papel),
        greaterThanOrEqualTo(2.5),
        reason:
            'el boton «$nivel» apagado desaparece del papel: quien lo mira no '
            'sabe si esta apagado o si no esta',
      );
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5. EL AREA DE TOQUE NO ENCOGE. Quitar el relleno no puede quitar sitio.
  // ───────────────────────────────────────────────────────────────────────────

  for (final ancho in [390.0, 1400.0]) {
    testWidgets('a ${ancho.toInt()} px todos los botones miden 48 de alto', (
      tester,
    ) async {
      await _aAncho(tester, ancho);
      await tester.pumpWidget(
        _banco(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Guardar')),
              OutlinedButton(onPressed: () {}, child: const Text('Cancelar')),
              BotonDestructivo(texto: 'Eliminar', alPulsar: () {}),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Nueva Ruta'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // `getRect` sobre el boton da el rectangulo que de verdad recibe el dedo,
      // que es el que Material agranda con `tapTargetSize: padded` — no el que
      // se dibuja. Esa diferencia es justo la que se pierde de vista al quitar
      // fondos.
      //
      // SE BUSCAN LOS TIPOS CONCRETOS Y NO `ButtonStyleButton`, y esto lo cazo
      // una mutacion: `find.byType` compara el `runtimeType` exacto, asi que
      // pedir la clase padre encuentra **cero** botones y el bucle no da ni una
      // vuelta. La prueba pasaba en verde midiendo nada, y con
      // `VisualDensity.compact` metido a proposito en el tema —que deja el
      // objetivo en 40— seguia pasando. De ahi sale tambien el recuento de
      // abajo: una prueba que mide tiene que decir **cuantas cosas midio**.
      final botones = [
        ...find.byType(FilledButton).evaluate(),
        ...find.byType(OutlinedButton).evaluate(),
        ...find.byType(ElevatedButton).evaluate(),
      ];
      expect(
        botones.length,
        4,
        reason:
            'esta prueba tiene que medir los cuatro botones del banco y ha '
            'encontrado ${botones.length}: si no encuentra ninguno pasa en '
            'verde sin haber medido nada',
      );
      for (final elemento in botones) {
        final caja = tester.getRect(find.byWidget(elemento.widget));
        final texto = find
            .descendant(
              of: find.byWidget(elemento.widget),
              matching: find.byType(Text),
            )
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .join();
        expect(
          caja.height,
          greaterThanOrEqualTo(Botones.altoTactilMinimo),
          reason:
              'el boton «$texto» mide ${caja.height.toStringAsFixed(1)} px de '
              'alto tactil a ${ancho.toInt()} px, por debajo de los '
              '${Botones.altoTactilMinimo.toInt()} de Material. Quitar el '
              'relleno no puede encoger donde cae el dedo: mira que nadie le '
              'haya puesto VisualDensity.compact ni lo haya metido en un '
              'SizedBox mas bajo',
        );
        expect(
          caja.width,
          greaterThanOrEqualTo(48),
          reason:
              'el boton «$texto» mide ${caja.width.toStringAsFixed(1)} px de '
              'ancho tactil a ${ancho.toInt()} px',
        );
      }
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 6. EL CABLE. Que [Botones] este bien no sirve de nada si el tema no lo usa.
  // ───────────────────────────────────────────────────────────────────────────

  test('el tema enchufa los tres niveles y no una copia suya', () {
    final tema = temaDeReparto();
    // Se comparan los rasgos que definen cada nivel, no el objeto: dos
    // `ButtonStyle` construidos por separado nunca son iguales con `==`.
    void mismoNivel(String donde, ButtonStyle? puesto, ButtonStyle esperado) {
      expect(puesto, isNotNull, reason: '$donde se quedo sin estilo');
      expect(
        _bordeEn(puesto!, const {})?.width,
        _bordeEn(esperado, const {})?.width,
        reason:
            '$donde no usa el nivel que le toca de Botones: se le puso un '
            'estilo aparte y ahora hay dos sitios donde mirar',
      );
      expect(
        _letraEn(puesto, const {}),
        _letraEn(esperado, const {}),
        reason: '$donde pinta de otro color que su nivel de Botones',
      );
    }

    mismoNivel(
      'filledButtonTheme',
      tema.filledButtonTheme.style,
      Botones.principal(),
    );
    mismoNivel(
      'elevatedButtonTheme',
      tema.elevatedButtonTheme.style,
      Botones.principal(),
    );
    mismoNivel(
      'outlinedButtonTheme',
      tema.outlinedButtonTheme.style,
      Botones.secundario(),
    );
  });
}
