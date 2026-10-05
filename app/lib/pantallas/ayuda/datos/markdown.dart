/// EL LECTOR DE MARKDOWN DE LA CASA. **Sin paquete nuevo, y es una decision.**
///
/// ## Por que no se baja un paquete
///
/// La aplicacion ya pesa 78 MB y una dependencia nueva no es un detalle. Ademas,
/// de lo que hay para esto: `flutter_markdown` esta **retirado** —el equipo de
/// Flutter lo dejo de mantener— y los que quedan traen su propio arbol de
/// paquetes para pintar HTML, selecciones y temas que aqui no se usan.
///
/// Y hay precedente escrito en este mismo proyecto, dos veces:
///
///  * el escritor de `.xlsx` se hizo a mano en 200 lineas (`pubspec.yaml`) para no
///    bajar `archive` y `xml` por debajo de lo que necesita lo impreso;
///  * el mapa **no trae ninguna biblioteca de mapas**: se dibuja con un
///    `CustomPainter`.
///
/// Lo que hay que pintar es lo que el manual usa de verdad, contado sobre las
/// 6.669 lineas de `docs/manual/`: encabezados, parrafos, vinetas, **pasos
/// numerados** —que es lo que mas importa, porque son las instrucciones—, citas,
/// bloques de codigo, reglas, tablas y, dentro del renglon, negrita, `codigo` y
/// enlaces. Nada mas, y nada de eso necesita un paquete.
///
/// ## Donde acaba este fichero
///
/// Aqui se parte el texto en bloques y en trozos de renglon, y **no se pinta
/// nada**: ni un `Widget`, ni un color. Asi se puede probar con `expect` sobre
/// datos en vez de buscando textos en una pantalla montada, que es la unica forma
/// de que las pruebas de esto digan algo concreto cuando fallan.
library;

/// UN BLOQUE del documento. Lo que va uno debajo del otro.
sealed class BloqueDeManual {
  const BloqueDeManual();
}

/// `# Titulo`, `## Tarea`, `### Si no aparece`…
class Encabezado extends BloqueDeManual {
  const Encabezado(this.nivel, this.texto);

  /// 1 a 6.
  final int nivel;
  final String texto;
}

class Parrafo extends BloqueDeManual {
  const Parrafo(this.texto);

  final String texto;
}

/// Un punto de una lista. Si [numero] es `null` es una vineta; si no, es un
/// **paso**, y entonces el numero se pinta tal cual viene escrito en el manual.
///
/// El numero NO se vuelve a contar aqui a proposito: si el manual dice «1, 2, 3,
/// 3, 4» porque alguien se equivoco al escribirlo, la pantalla tiene que ensenar
/// lo mismo que el documento, no una version arreglada que no coincide con el
/// papel que la gente tiene al lado.
class Punto extends BloqueDeManual {
  const Punto({required this.nivel, required this.texto, this.numero});

  /// 0 = pegado al margen. 1 y 2, las sangrias de dentro.
  final int nivel;
  final String texto;
  final String? numero;

  bool get esPaso => numero != null;
}

/// `> lo que dijo Jose`. Varias lineas seguidas son UNA cita.
class Cita extends BloqueDeManual {
  const Cita(this.texto);

  final String texto;
}

/// Lo de dentro de ``` ``` ```: se pinta tal cual, con tipografia de maquina y
/// sin tocarle ni un espacio.
class Codigo extends BloqueDeManual {
  const Codigo(this.texto);

  final String texto;
}

/// `---`.
class Regla extends BloqueDeManual {
  const Regla();
}

/// Una tabla. [encabezados] puede venir vacia si la tabla no los trae.
///
/// Las celdas van en texto crudo y se parten en trozos al pintar: una tabla de
/// tres columnas en un telefono de 390 px no se pinta como una tabla, y esa
/// decision es de la vista, no de aqui.
class Tabla extends BloqueDeManual {
  const Tabla({required this.encabezados, required this.filas});

  final List<String> encabezados;
  final List<List<String>> filas;
}

/// UN TROZO DE RENGLON. El texto de un bloque, ya separado en lo que se pinta
/// distinto.
class Trozo {
  const Trozo(
    this.texto, {
    this.fuerte = false,
    this.codigo = false,
    this.destino,
  });

  final String texto;

  /// `**asi**`.
  final bool fuerte;

  /// Entre comillas invertidas.
  final bool codigo;

  /// Si es un enlace, a donde apunta tal cual lo escribio quien hizo el manual:
  /// `../comun/glosario.md#apunte`, `pantallas/rutas.md`. **Se resuelve al
  /// pintar**, que es quien sabe en que pagina estamos y que paginas hay en esta
  /// forma de la aplicacion.
  final String? destino;

  bool get esEnlace => destino != null;
}

final _encabezado = RegExp(r'^(#{1,6})\s+(.*)$');
final _vineta = RegExp(r'^(\s*)[-*]\s+(.*)$');
final _paso = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
final _regla = RegExp(r'^\s{0,3}(-{3,}|\*{3,}|_{3,})\s*$');
final _cita = RegExp(r'^\s{0,3}>\s?(.*)$');
final _valla = RegExp(r'^\s{0,3}`{3,}');

/// Parte un documento en bloques.
List<BloqueDeManual> bloquesDe(String markdown) {
  final bloques = <BloqueDeManual>[];
  final renglones = markdown.replaceAll('\r\n', '\n').split('\n');

  // Lo que se esta juntando ahora mismo: un parrafo o una cita de varias lineas.
  final juntando = <String>[];
  var juntandoCita = false;

  void soltar() {
    if (juntando.isEmpty) return;
    final texto = juntando.join(' ').trim();
    juntando.clear();
    if (texto.isEmpty) return;
    bloques.add(juntandoCita ? Cita(texto) : Parrafo(texto));
  }

  for (var i = 0; i < renglones.length; i++) {
    final renglon = renglones[i];

    // 1. LOS BLOQUES DE CODIGO VAN PRIMERO: dentro de ellos no hay markdown.
    //    Una tabla de ejemplo o un `# comentario` de un guion no son una tabla ni
    //    un encabezado, y mirarlos antes de la valla los convertiria en eso.
    if (_valla.hasMatch(renglon)) {
      soltar();
      final dentro = <String>[];
      i++;
      while (i < renglones.length && !_valla.hasMatch(renglones[i])) {
        dentro.add(renglones[i]);
        i++;
      }
      // Sin los blancos del final: un `split` de un texto que acaba en salto
      // deja un renglon vacio, y en un bloque de codigo eso se pinta como una
      // linea en blanco dentro del recuadro.
      while (dentro.isNotEmpty && dentro.last.trim().isEmpty) {
        dentro.removeLast();
      }
      bloques.add(Codigo(dentro.join('\n')));
      continue;
    }

    if (renglon.trim().isEmpty) {
      soltar();
      juntandoCita = false;
      continue;
    }

    // 2. UNA TABLA EMPIEZA EN EL PRIMER RENGLON QUE ABRE CON `|` y sigue mientras
    //    sigan abriendo con `|`.
    //
    //    Y el renglon de en medio, `|---|---|`, **se tira dentro de `_tablaDe`**
    //    (`esSeparadora`). Ahi esta la guarda de verdad, no en este orden: sin
    //    tirarlo, la tabla sale con una primera fila de guiones, que en el telefono
    //    se pinta como un renglon con «---» de valor. Se comprobo rompiendolo.
    if (renglon.trimLeft().startsWith('|')) {
      soltar();
      final crudas = <String>[];
      while (i < renglones.length && renglones[i].trimLeft().startsWith('|')) {
        crudas.add(renglones[i]);
        i++;
      }
      i--;
      bloques.add(_tablaDe(crudas));
      continue;
    }

    if (_regla.hasMatch(renglon)) {
      soltar();
      bloques.add(const Regla());
      continue;
    }

    final conEncabezado = _encabezado.firstMatch(renglon);
    if (conEncabezado != null) {
      soltar();
      bloques.add(
        Encabezado(
          conEncabezado.group(1)!.length,
          conEncabezado.group(2)!.trim(),
        ),
      );
      continue;
    }

    final conCita = _cita.firstMatch(renglon);
    if (conCita != null) {
      if (!juntandoCita) soltar();
      juntandoCita = true;
      juntando.add(conCita.group(1)!.trim());
      continue;
    }

    final conPaso = _paso.firstMatch(renglon);
    if (conPaso != null) {
      soltar();
      juntandoCita = false;
      bloques.add(
        Punto(
          nivel: _nivelDe(conPaso.group(1)!),
          numero: conPaso.group(2),
          texto: conPaso.group(3)!.trim(),
        ),
      );
      continue;
    }

    final conVineta = _vineta.firstMatch(renglon);
    if (conVineta != null) {
      soltar();
      juntandoCita = false;
      bloques.add(
        Punto(
          nivel: _nivelDe(conVineta.group(1)!),
          texto: conVineta.group(2)!.trim(),
        ),
      );
      continue;
    }

    // 3. UN RENGLON SANGRADO DEBAJO DE UN PUNTO ES LA CONTINUACION DE ESE PUNTO,
    //    no un parrafo nuevo.
    //
    //    En el manual los puntos largos se parten a los 80 caracteres y siguen
    //    sangrados —«1. Arriba, a la izquierda de tu avatar, hay una pastilla con
    //    el codigo de la / sucursal»—. Sin esto, la segunda mitad de cada paso
    //    sale como un parrafo pegado al margen y los pasos se leen partidos, que
    //    en una lista de instrucciones es la diferencia entre entenderla y no.
    if (renglon.startsWith(' ') && juntando.isEmpty && bloques.isNotEmpty) {
      final ultimo = bloques.last;
      if (ultimo is Punto) {
        bloques[bloques.length - 1] = Punto(
          nivel: ultimo.nivel,
          numero: ultimo.numero,
          texto: '${ultimo.texto} ${renglon.trim()}',
        );
        continue;
      }
    }

    juntando.add(renglon.trim());
  }
  soltar();

  return bloques;
}

/// La sangria en niveles. Dos espacios son un nivel, pero los pasos del manual
/// sangran a TRES —lo que mide «1. »— y a cuatro, asi que no se divide y ya: se
/// mide a tramos, y de un nivel no se pasa sin pasar el anterior.
int _nivelDe(String espacios) {
  final cuantos = espacios.length;
  if (cuantos < 2) return 0;
  if (cuantos < 4) return 1;
  return 2;
}

Tabla _tablaDe(List<String> crudas) {
  List<String> celdasDe(String renglon) {
    var t = renglon.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((c) => c.trim()).toList();
  }

  bool esSeparadora(String renglon) =>
      RegExp(r'^[\s|:-]+$').hasMatch(renglon) && renglon.contains('-');

  final filas = <List<String>>[];
  var encabezados = <String>[];
  for (var i = 0; i < crudas.length; i++) {
    if (esSeparadora(crudas[i])) continue;
    final celdas = celdasDe(crudas[i]);
    // La primera fila es la de los titulos SOLO si debajo viene la separadora.
    // Una tabla sin separadora es una tabla sin encabezados, y llamar titulos a
    // su primera fila la perderia.
    if (i == 0 && crudas.length > 1 && esSeparadora(crudas[1])) {
      encabezados = celdas;
      continue;
    }
    filas.add(celdas);
  }
  return Tabla(encabezados: encabezados, filas: filas);
}

final _dentroDelRenglon = RegExp(
  // Un enlace, `codigo`, **negrita**. En ese orden: el rotulo de un enlace puede
  // llevar negrita dentro —`**[Manual de la web](web/README.md)**` sale asi en
  // `docs/manual/README.md`— y mirar la negrita primero partiria el enlace en
  // dos trozos sin destino.
  r'\[([^\]\n]+)\]\(([^)\s]+)\)'
  r'|`([^`\n]+)`'
  r'|\*\*([^*\n]+(?:\*[^*\n]+)*)\*\*',
);

/// Parte un renglon en sus trozos. Lo que no cuadra con nada sale como texto
/// llano, nunca se tira.
List<Trozo> trozosDe(String texto) {
  final trozos = <Trozo>[];
  var desde = 0;

  void llano(String t) {
    if (t.isEmpty) return;
    trozos.add(Trozo(t));
  }

  for (final hallazgo in _dentroDelRenglon.allMatches(texto)) {
    llano(texto.substring(desde, hallazgo.start));
    desde = hallazgo.end;

    final rotulo = hallazgo.group(1);
    if (rotulo != null) {
      // El rotulo de un enlace puede traer negrita o codigo dentro. Se queda el
      // texto, se queda el destino y se pierde el adorno: un enlace ya se
      // distingue por su color.
      trozos.add(
        Trozo(
          rotulo.replaceAll('**', '').replaceAll('`', ''),
          destino: hallazgo.group(2),
        ),
      );
      continue;
    }
    final codigo = hallazgo.group(3);
    if (codigo != null) {
      trozos.add(Trozo(codigo, codigo: true));
      continue;
    }
    final fuerte = hallazgo.group(4);
    if (fuerte != null) {
      // Una negrita puede traer un enlace dentro: `**[Manual](web/README.md)**`.
      // Se vuelve a mirar por dentro, y lo que salga se marca en negrita.
      for (final dentro in trozosDe(fuerte)) {
        trozos.add(
          Trozo(
            dentro.texto,
            fuerte: true,
            codigo: dentro.codigo,
            destino: dentro.destino,
          ),
        );
      }
    }
  }
  llano(texto.substring(desde));

  return trozos;
}

/// El texto de un renglon sin los adornos. Es lo que se busca y lo que se lee en
/// voz alta: nadie teclea los asteriscos.
String soloElTexto(String markdown) =>
    trozosDe(markdown).map((t) => t.texto).join();
