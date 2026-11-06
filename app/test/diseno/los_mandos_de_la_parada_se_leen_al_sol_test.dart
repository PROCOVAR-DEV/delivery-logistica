// LOS MANDOS DE LA PARADA SE LEEN AL SOL (issue 26 de Amado, 06/11/2026):
//
//     «Los botones para accionar sobre la parada no tienen contraste, son blanco sobre verde y no se
//      leen apenas. En un lugar con sol no se van a ver.»
//
// Era el `ChoiceChip` de «Entregado» / «No entregada»: el tema no le daba color a la letra y Material
// la pintaba BLANCA, sobre el verde claro del elegido (1,1 de contraste) y sobre el gris del otro. Esto
// MIDE, con el tema de la calle montado, lo que se pinta de cada mando de la parada: la letra, el
// contorno y el relleno —leido de los PIXELES del chip, no de lo que el tema dice que pinta—.
//
// El objetivo es 7:1 (AAA), contra el papel Y contra el blanco de la tarjeta que los lleva, letra de
// 16 como minimo y 48 px de alto. La prueba de mutacion de abajo monta el tema ANTIGUO (letra blanca
// sobre el verde del elegido) y comprueba que ESTA MISMA medida lo tumba: si no, no mediria nada.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/diseno/tema.dart';

const _minimo = 7.0;
const _clave = ValueKey('banco');

/// Los mandos de la parada, tal y como los monta `ruta_guiada.dart`, sobre [fondo].
Widget _banco(ThemeData tema, Color fondo, {bool entregado = true}) =>
    MaterialApp(
      theme: tema,
      home: Scaffold(
        backgroundColor: fondo,
        body: RepaintBoundary(
          key: _clave,
          child: Material(
            color: fondo,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('si'),
                      label: const Text('Entregado'),
                      selected: entregado,
                      onSelected: (_) {},
                    ),
                    ChoiceChip(
                      key: const ValueKey('no'),
                      label: const Text('No entregada'),
                      selected: !entregado,
                      onSelected: (_) {},
                    ),
                  ],
                ),
                SwitchListTile(
                  key: const ValueKey('on'),
                  title: const Text('Cobrado'),
                  subtitle: const Text('Sí, cobré'),
                  value: true,
                  onChanged: (_) {},
                ),
                SwitchListTile(
                  key: const ValueKey('off'),
                  title: const Text('Cobrado'),
                  subtitle: const Text('No cobré'),
                  value: false,
                  onChanged: (_) {},
                ),
                BotonPrincipal(
                  key: const ValueKey('guardar'),
                  texto: 'Guardar y pasar a la siguiente',
                  icono: Icons.check,
                  alPulsar: () {},
                ),
                OutlinedButton.icon(
                  key: const ValueKey('navegar'),
                  onPressed: () {},
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Navegar a esta parada'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('llamar'),
                  onPressed: () {},
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Llamar al cliente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

/// La letra EFECTIVA de un `Text` dentro de [mando]: el estilo del propio `Text` sobre el del arbol.
TextStyle _letra(WidgetTester t, Finder mando) {
  final texto = find.descendant(of: mando, matching: find.byType(Text)).first;
  final el = t.element(texto);
  return DefaultTextStyle.of(el).style.merge(t.widget<Text>(texto).style);
}

/// El color de un pixel del banco renderizado, en el punto [donde] (coordenadas logicas).
Future<Color> _pixel(WidgetTester t, Offset donde) async {
  late Color color;
  await t.runAsync(() async {
    final borde = t.renderObject<RenderRepaintBoundary>(find.byKey(_clave));
    final imagen = await borde.toImage();
    final datos = (await imagen.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final x = donde.dx.round(), y = donde.dy.round();
    final i = (y * imagen.width + x) * 4;
    color = Color.fromARGB(
      datos.getUint8(i + 3),
      datos.getUint8(i),
      datos.getUint8(i + 1),
      datos.getUint8(i + 2),
    );
  });
  return color;
}

/// El contorno que de verdad se pinta en un chip (el `Material` que monta lleva su forma).
BorderSide _contornoDelChip(WidgetTester t, Finder chip) {
  final material = t.widget<Material>(
    find.descendant(of: chip, matching: find.byType(Material)).first,
  );
  return (material.shape! as RoundedRectangleBorder).side;
}

/// Lo que mide cada mando: nombre -> contraste. Contra [fondo], que es lo que hay DETRAS del mando.
Future<Map<String, double>> _medir(
  WidgetTester t,
  ThemeData tema,
  Color fondo,
) async {
  t.view.physicalSize = const Size(420, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final medidas = <String, double>{};

  for (final entregado in [true, false]) {
    await t.pumpWidget(_banco(tema, fondo, entregado: entregado));
    await t.pumpAndSettle();
    final elegido = find.byKey(ValueKey(entregado ? 'si' : 'no'));
    final suelto = find.byKey(ValueKey(entregado ? 'no' : 'si'));
    for (final (nombre, chip) in [('elegido', elegido), ('suelto', suelto)]) {
      final caja = t.getRect(chip);
      // El relleno: un punto DENTRO del chip, arriba y en medio, donde no hay ni letra ni contorno.
      final relleno = await _pixel(t, Offset(caja.center.dx, caja.top + 5));
      final base = Color.alphaBlend(relleno, fondo);
      final letra = _letra(t, chip);
      medidas['chip $nombre: letra sobre su relleno'] = contrasteEntre(
        letra.color!,
        base,
      );
      final lado = _contornoDelChip(t, chip);
      medidas['chip $nombre: contorno sobre el fondo'] = contrasteEntre(
        lado.color,
        fondo,
      );
      medidas['chip $nombre: tamano de letra'] = letra.fontSize!;
      medidas['chip $nombre: alto'] = caja.height;
    }
  }

  await t.pumpWidget(_banco(tema, fondo));
  await t.pumpAndSettle();
  final c = t.element(find.byKey(const ValueKey('on')));
  final tm = Theme.of(c).switchTheme;
  for (final (nombre, estado) in [
    ('puesto', {WidgetState.selected}),
    ('quitado', <WidgetState>{}),
  ]) {
    final bola = tm.thumbColor!.resolve(estado)!;
    final pista = Color.alphaBlend(tm.trackColor!.resolve(estado)!, fondo);
    medidas['interruptor $nombre: bola sobre la pista'] = contrasteEntre(
      bola,
      pista,
    );
    medidas['interruptor $nombre: contorno sobre el fondo'] = contrasteEntre(
      tm.trackOutlineColor!.resolve(estado)!,
      fondo,
    );
  }
  final fila = t.getRect(find.byKey(const ValueKey('on')));
  medidas['interruptor: alto de la fila'] = fila.height;
  medidas['interruptor: letra del titulo'] = _letra(
    t,
    find.byKey(const ValueKey('on')),
  ).fontSize!;
  final leyenda = find.text('Sí, cobré');
  medidas['interruptor: letra de la leyenda'] = DefaultTextStyle.of(
    t.element(leyenda),
  ).style.merge(t.widget<Text>(leyenda).style).fontSize!;

  for (final (nombre, tecla) in [
    ('guardar', 'guardar'),
    ('navegar', 'navegar'),
    ('llamar', 'llamar'),
  ]) {
    final boton = tecla == 'guardar'
        ? find.descendant(
            of: find.byKey(const ValueKey('guardar')),
            matching: find.byType(FilledButton),
          )
        : find.byKey(ValueKey(tecla));
    final estilo =
        t.widget<ButtonStyleButton>(boton).style ?? const ButtonStyle();
    final delTema = switch (t.widget(boton)) {
      OutlinedButton() => Theme.of(t.element(boton)).outlinedButtonTheme.style,
      _ => Theme.of(t.element(boton)).filledButtonTheme.style,
    }!;
    final e = estilo.merge(delTema);
    const reposo = <WidgetState>{};
    medidas['boton $nombre: letra sobre el fondo'] = contrasteEntre(
      e.foregroundColor!.resolve(reposo)!,
      fondo,
    );
    medidas['boton $nombre: contorno sobre el fondo'] = contrasteEntre(
      e.side!.resolve(reposo)!.color,
      fondo,
    );
    medidas['boton $nombre: tamano de letra'] = e.textStyle!
        .resolve(reposo)!
        .fontSize!;
    medidas['boton $nombre: alto'] = t.getRect(boton).height;
  }
  return medidas;
}

void _exigirLoDeLaCalle(Map<String, double> m, String donde) {
  for (final MapEntry(key: nombre, value: valor) in m.entries) {
    if (nombre.endsWith('tamano de letra') ||
        nombre.endsWith('letra del titulo') ||
        nombre.endsWith('letra de la leyenda')) {
      expect(
        valor,
        greaterThanOrEqualTo(16),
        reason: '$donde · $nombre = $valor (minimo 16)',
      );
    } else if (nombre.endsWith('alto') || nombre.endsWith('alto de la fila')) {
      expect(
        valor,
        greaterThanOrEqualTo(Botones.altoTactilMinimo),
        reason: '$donde · $nombre = $valor (minimo 48)',
      );
    } else {
      expect(
        valor,
        greaterThanOrEqualTo(_minimo),
        reason: '$donde · $nombre = ${valor.toStringAsFixed(2)}:1 (minimo 7:1)',
      );
    }
  }
}

ThemeData _laCalle() => temaDeLaCalle(temaDeReparto());

void main() {
  for (final (donde, fondo) in [
    ('sobre el papel', Colores.papel),
    ('sobre la tarjeta blanca', Colores.blanco),
  ]) {
    testWidgets(
      'los mandos de la parada dan 7:1, 16 de letra y 48 de alto $donde',
      (tester) async {
        final medidas = await _medir(tester, _laCalle(), fondo);
        // ignore: avoid_print
        print(
          'MEDIDAS $donde:\n${medidas.entries.map((e) => '  ${e.key}: ${e.value.toStringAsFixed(2)}').join('\n')}',
        );
        _exigirLoDeLaCalle(medidas, donde);
      },
    );
  }

  // MUTACION: el tema de ANTES. La letra del chip sin color sale blanca (lo que paso de verdad), y el
  // elegido pinta el verde claro de Material. Si la medida de arriba no lo tumbara, no mediria nada.
  testWidgets(
    'MUTACION: letra blanca sobre el verde claro del elegido TUMBA la medida',
    (tester) async {
      final base = _laCalle();
      final viejo = base.copyWith(
        chipTheme: base.chipTheme.copyWith(
          selectedColor: Colores.verdeFondo,
          labelStyle: base.chipTheme.labelStyle!.copyWith(color: Colors.white),
          secondaryLabelStyle: base.chipTheme.secondaryLabelStyle!.copyWith(
            color: Colors.white,
          ),
        ),
      );
      final medidas = await _medir(tester, viejo, Colores.blanco);
    // ignore: avoid_print
    print('ANTES ${medidas.entries.map((e) => '${e.key}: ${e.value.toStringAsFixed(2)}').join(' | ')}');
      expect(
        medidas['chip elegido: letra sobre su relleno']!,
        lessThan(2),
        reason: 'blanco sobre verde claro',
      );
      expect(
        () => _exigirLoDeLaCalle(medidas, 'mutado'),
        throwsA(isA<TestFailure>()),
      );
    },
  );

  testWidgets(
    'MUTACION: el interruptor con la bola blanca sobre el oro TUMBA la medida',
    (tester) async {
      final base = _laCalle();
      final viejo = base.copyWith(
        switchTheme: SwitchThemeData(
          trackColor: WidgetStatePropertyAll(Colores.marca),
          trackOutlineColor: WidgetStatePropertyAll(Colores.linea),
          thumbColor: const WidgetStatePropertyAll(Colores.blanco),
        ),
      );
      final medidas = await _medir(tester, viejo, Colores.blanco);
    // ignore: avoid_print
    print('ANTES ${medidas.entries.map((e) => '${e.key}: ${e.value.toStringAsFixed(2)}').join(' | ')}');
      expect(medidas['interruptor puesto: bola sobre la pista']!, lessThan(3));
      expect(
        () => _exigirLoDeLaCalle(medidas, 'mutado'),
        throwsA(isA<TestFailure>()),
      );
    },
  );

  testWidgets(
    'MUTACION: el boton con el oro de 4,5 y raya fina TUMBA la medida',
    (tester) async {
      final base = _laCalle();
      final viejo = base.copyWith(
        filledButtonTheme: FilledButtonThemeData(style: Botones.principal()),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: Botones.secundario(),
        ),
      );
      final medidas = await _medir(tester, viejo, Colores.blanco);
    // ignore: avoid_print
    print('ANTES ${medidas.entries.map((e) => '${e.key}: ${e.value.toStringAsFixed(2)}').join(' | ')}');
      expect(
        () => _exigirLoDeLaCalle(medidas, 'mutado'),
        throwsA(isA<TestFailure>()),
      );
    },
  );

  test('el tema de siempre NO se endurece: el principal global sigue en el oro de 4,5', () {
    // `temaDeLaCalle` es solo de la parada: la identidad de la aplicacion no cambia.
    expect(
      temaDeReparto().filledButtonTheme.style!.foregroundColor!.resolve({}),
      Colores.primario,
    );
  });
}
