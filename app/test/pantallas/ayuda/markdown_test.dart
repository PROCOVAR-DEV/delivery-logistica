// EL LECTOR DE MARKDOWN DE LA CASA.
//
// No hay paquete que haga esto —`flutter_markdown` esta retirado— y la decision
// fue escribirlo, como el escritor de `.xlsx` y como el pintor del mapa. Asi que
// lo que aqui falle sale en la pantalla de alguien leyendo instrucciones, y las
// instrucciones mal partidas son peores que no tenerlas: un paso que se corta por
// la mitad se lee como dos pasos.
//
// Los casos no son inventados: cada grupo trae el trozo de `docs/manual/` que lo
// trajo.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/ayuda/datos/markdown.dart';

void main() {
  group('los encabezados', () {
    test('salen con su nivel', () {
      final bloques = bloquesDe('# Uno\n\n## Dos\n\n### Tres\n');
      expect(bloques, hasLength(3));
      expect((bloques[0] as Encabezado).nivel, 1);
      expect((bloques[0] as Encabezado).texto, 'Uno');
      expect((bloques[1] as Encabezado).nivel, 2);
      expect((bloques[2] as Encabezado).nivel, 3);
    });

    test('un «#» sin espacio NO es un encabezado', () {
      // Es lo que hace que la marca que separa ficheros del paquete
      // (`#@ FICHERO …`) no pueda salir de nada que alguien escriba.
      expect(bloquesDe('#sin espacio\n').single, isA<Parrafo>());
    });
  });

  group('los pasos', () {
    test('salen numerados, con el numero TAL CUAL lo escribe el manual', () {
      final bloques = bloquesDe('1. Uno\n2. Dos\n3. Tres\n');
      expect(bloques.whereType<Punto>().map((p) => p.numero), ['1', '2', '3']);
      expect(bloques.whereType<Punto>().every((p) => p.esPaso), isTrue);
    });

    /// EL CASO QUE LO TRAJO. En `docs/manual/apk/3-tareas.md` los pasos largos se
    /// parten a los 80 caracteres y siguen sangrados. Sin tratar la continuacion,
    /// la segunda mitad sale como un parrafo pegado al margen y el paso se lee
    /// partido en dos — en una lista de instrucciones, la diferencia entre
    /// entenderla y no.
    test('un renglon sangrado debajo es la CONTINUACION del paso, no otro', () {
      final bloques = bloquesDe(
        '1. Arriba, a la izquierda de tu avatar, hay una pastilla con el código\n'
        '   de la sucursal: **«STG»**.\n'
        '2. **Tócala.**\n',
      );
      final pasos = bloques.whereType<Punto>().toList();
      expect(pasos, hasLength(2));
      expect(
        pasos[0].texto,
        'Arriba, a la izquierda de tu avatar, hay una pastilla con el código de '
        'la sucursal: **«STG»**.',
      );
      expect(pasos[1].texto, '**Tócala.**');
      expect(
        bloques.whereType<Parrafo>(),
        isEmpty,
        reason: 'la segunda mitad del paso 1 se ha quedado suelta como parrafo',
      );
    });

    test('las vinetas no llevan numero', () {
      final bloques = bloquesDe('- Una\n- Otra\n');
      expect(bloques.whereType<Punto>().every((p) => p.esPaso), isFalse);
      expect(bloques.whereType<Punto>().map((p) => p.texto), ['Una', 'Otra']);
    });

    test('la sangria sube de nivel, y de uno en uno', () {
      // Las sangrias reales del manual: 2, 3 y 4 espacios. Los 3 son lo que mide
      // «1. », o sea una vineta dentro de un paso.
      final bloques = bloquesDe('- A\n  - B\n   - C\n    - D\n');
      expect(bloques.whereType<Punto>().map((p) => p.nivel), [0, 1, 1, 2]);
    });
  });

  group('los bloques de codigo', () {
    test('se quedan tal cual, con sus espacios', () {
      final bloques = bloquesDe('```\n  uno\n    dos\n```\n');
      expect((bloques.single as Codigo).texto, '  uno\n    dos');
    });

    /// LO DE DENTRO NO ES MARKDOWN, y mirarlo antes de la valla lo convertiria en
    /// otra cosa. El manual tiene bloques con `|` y con `#` dentro.
    test('lo de dentro no se interpreta', () {
      final bloques = bloquesDe('```\n# no soy un titulo\n| ni | una tabla |\n```\n');
      expect(bloques, hasLength(1));
      expect(bloques.single, isA<Codigo>());
    });

    test('una valla sin cerrar no se come el resto en silencio', () {
      final bloques = bloquesDe('```\nalgo\n');
      expect((bloques.single as Codigo).texto, 'algo');
    });
  });

  group('las tablas', () {
    test('la primera fila son titulos si debajo viene la separadora', () {
      final tabla = bloquesDe(
        '| Dónde | Tu manual |\n|---|---|\n'
        '| En el navegador | **Web** |\n| En el teléfono | **APK** |\n',
      ).single as Tabla;
      expect(tabla.encabezados, ['Dónde', 'Tu manual']);
      expect(tabla.filas, [
        ['En el navegador', '**Web**'],
        ['En el teléfono', '**APK**'],
      ]);
    });

    test('sin separadora, no hay titulos y no se pierde la primera fila', () {
      final tabla = bloquesDe('| a | b |\n| c | d |\n').single as Tabla;
      expect(tabla.encabezados, isEmpty);
      expect(tabla.filas, hasLength(2));
    });

    test('la separadora con alineacion tambien se reconoce', () {
      final tabla = bloquesDe('| a |\n|:---:|\n| b |\n').single as Tabla;
      expect(tabla.encabezados, ['a']);
      expect(tabla.filas, [['b']]);
    });
  });

  group('las citas y las reglas', () {
    test('varias lineas seguidas de «>» son UNA cita', () {
      final bloques = bloquesDe(
        '> el trabajo sin conexion es solo para las\n'
        '> aplicaciones cojone\n',
      );
      expect(bloques, hasLength(1));
      expect(
        (bloques.single as Cita).texto,
        'el trabajo sin conexion es solo para las aplicaciones cojone',
      );
    });

    test('un blanco separa dos citas', () {
      final bloques = bloquesDe('> una\n\n> otra\n');
      expect(bloques.whereType<Cita>(), hasLength(2));
    });

    test('«---» es una regla', () {
      expect(bloquesDe('a\n\n---\n\nb\n').whereType<Regla>(), hasLength(1));
    });

    /// EL `|---|` DE UNA TABLA NO ES NADA: ni una regla, ni una fila.
    ///
    /// Aqui estuvo escrito que el peligro era que una regla se lo comiera, y era
    /// **falso**: `_regla` no cuadra con `|---|` ni queriendo, asi que esa guarda no
    /// protegia nada. Se vio rompiendola a proposito: la mutacion salio VERDE
    /// («CLAUDE.md» §4-bis — si una mutacion sale verde, el caso no ejerce la
    /// guarda). Lo que si puede pasar, y es lo que esto vigila, es que el renglon
    /// de guiones **se cuente como una fila de datos**: en el telefono cada fila es
    /// un bloque, asi que saldria un bloque con «---» de contenido.
    test('el «|---|» de una tabla no es ni una regla ni una fila', () {
      final bloques = bloquesDe('| a |\n|---|\n| b |\n');
      expect(bloques.whereType<Regla>(), isEmpty);
      final tabla = bloques.whereType<Tabla>().single;
      expect(tabla.filas, [['b']], reason: 'el renglon de guiones se cuela de fila');
      expect(tabla.encabezados, ['a']);
    });
  });

  group('dentro del renglon', () {
    test('la negrita', () {
      final trozos = trozosDe('Pulsa **«Guardar»** ahora');
      expect(trozos.map((t) => t.texto), ['Pulsa ', '«Guardar»', ' ahora']);
      expect(trozos.map((t) => t.fuerte), [false, true, false]);
    });

    test('el codigo', () {
      final trozos = trozosDe('vale `≥ 17318.8 kg` justo');
      expect(trozos[1].texto, '≥ 17318.8 kg');
      expect(trozos[1].codigo, isTrue);
    });

    test('el enlace, con su destino', () {
      final trozos = trozosDe('ver [el glosario](../comun/glosario.md#apunte)');
      expect(trozos[1].texto, 'el glosario');
      expect(trozos[1].destino, '../comun/glosario.md#apunte');
      expect(trozos[1].esEnlace, isTrue);
    });

    /// EL CASO DE `docs/manual/README.md`: `**[Manual de la web](web/README.md)**`.
    /// Mirar la negrita antes del enlace partiria el enlace en dos trozos sin
    /// destino, y esa tabla es la portada del manual.
    test('un enlace dentro de una negrita conserva el destino', () {
      final trozos = trozosDe('**[Manual de la web](web/README.md)**');
      expect(trozos, hasLength(1));
      expect(trozos.single.texto, 'Manual de la web');
      expect(trozos.single.destino, 'web/README.md');
      expect(trozos.single.fuerte, isTrue);
    });

    test('una negrita dentro de un enlace no deja los asteriscos a la vista', () {
      final trozos = trozosDe('[**Rutas**](routes.md)');
      expect(trozos.single.texto, 'Rutas');
      expect(trozos.single.destino, 'routes.md');
    });

    test('lo que no cuadra con nada sale como texto, nunca se tira', () {
      expect(trozosDe('a * b ** c ` d').map((t) => t.texto).join(), 'a * b ** c ` d');
    });

    test('soloElTexto quita los adornos y deja las palabras', () {
      expect(
        soloElTexto('**Ojo:** mira `products.weight` y [esto](a.md)'),
        'Ojo: mira products.weight y esto',
      );
    });
  });

  /// NADA SE PIERDE AL PINTAR. Es la guarda ancha: cualquier trozo de manual que
  /// entre tiene que salir con todas sus palabras, aunque el bloque en el que caiga
  /// no sea el que uno esperaba. Un manual al que se le come un renglon no avisa.
  test('ningun renglon se pierde por el camino', () {
    const trozo = '''
# Tareas sueltas

«Quiero hacer X»: dónde tocar, paso a paso.

---

## Buscar un pedido

**Empieza en:** **Menú → «Pedidos»**.

1. **Toca la caja de buscar** («Buscar») y escribe el cliente, el folio, la
   dirección o un producto.
2. **Busca solo**, sin darle a nada.

### Si no aparece

Mira en este orden:

- **La sucursal de arriba.** Es lo primero, siempre.
- **La franja azul** de arriba.

> «tengo q dar enter para q el filtro funcione»

| Dónde | Qué |
|---|---|
| Arriba | La sucursal |

```
Ruta RT-20260928-001 — Reparto Vista
```
''';
    final palabras = RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(trozo)
        .map((m) => m.group(0)!)
        .toList();

    final pintado = <String>[];
    for (final bloque in bloquesDe(trozo)) {
      switch (bloque) {
        // El numero del paso tambien se pinta, y tambien cuenta: «el 3» es con lo
        // que alguien vuelve a su sitio despues de mirar la pantalla de al lado.
        case Punto(:final texto, :final numero):
          pintado.add('${numero ?? ''} ${soloElTexto(texto)}');
        case Encabezado(:final texto):
        case Parrafo(:final texto):
        case Cita(:final texto):
          pintado.add(soloElTexto(texto));
        case Codigo(:final texto):
          pintado.add(texto);
        case Tabla(:final encabezados, :final filas):
          pintado.addAll(encabezados.map(soloElTexto));
          for (final fila in filas) {
            pintado.addAll(fila.map(soloElTexto));
          }
        case Regla():
          break;
      }
    }
    final salen = RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(pintado.join(' '))
        .map((m) => m.group(0)!)
        .toList();

    expect(
      salen,
      containsAllInOrder(palabras),
      reason: 'se ha perdido algo por el camino, y un manual recortado no avisa',
    );
  });
}
