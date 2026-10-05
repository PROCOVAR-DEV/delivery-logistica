/// EL MANUAL, LEIDO. De las 6.669 lineas de `docs/manual/` a lo que se pinta.
///
/// Aqui no hay ni un `Widget`: esto parte el paquete en paginas, saca de cada
/// pagina sus TAREAS y contesta a «¿como hago X?». Lo que se ve esta en
/// `vista/`.
///
/// ## La unidad es la TAREA, no el documento
///
/// Jose, 05/10/2026:
///
/// > «quiero q vaya vista a vista marcando donde tocar, que hacer, con notas y
/// > todo, como si estuviera en un video»
/// > «cada tarea de configuracion y trabajo deben de permanecer como guia, esa va
/// > a ser la guia para q la gente entienda la apk»
///
/// Nadie va a leer 6.669 lineas. Van a buscar «como cambio el camion de una
/// ruta» el dia que les toque, con el telefono en la mano y alguien esperando.
/// Asi que cada `##` de cada pagina es una [TareaDelManual] con nombre propio, y
/// eso es lo que se lista y lo que se busca.
///
/// **Y el documento entero sigue estando**, que es la otra mitad del encargo:
/// «pon las dos, el documento oficial y las tareas y sus pasos». No son dos
/// copias —la tarea es un trozo de la pagina, sacado de la misma cadena de
/// texto— y por eso no se pueden separar: no hay dos textos que mantener.
/// `test/pantallas/ayuda/las_tareas_salen_de_la_pagina_test.dart` lo ata.
library;

import 'empaquetado.dart';
import 'markdown.dart';

/// LAS TRES FORMAS DE LA APLICACION. Es la regla 1 de `CLAUDE.md` aplicada a la
/// guia: **la APK no puede ensenar la guia del escritorio ni al reves.**
///
/// ## Por que esto vive aqui y no en `nucleo/plataforma.dart`
///
/// `Destino.trabajaSinConexion` contesta la pregunta de siempre —¿hay que
/// prepararse para quedarse sin senal?— y con eso se separa la web de las otras
/// dos, que es lo unico que el resto de la aplicacion ha necesitado hasta hoy. La
/// guia es la primera pieza que necesita separar **la APK del escritorio**, y esa
/// pregunta no existe alli.
///
/// Asi que esto es **anadido, no copiado**: la mitad web/no-web se le pregunta a
/// `Destino` y no se vuelve a decidir aqui (ver `forma_de_la_aplicacion.dart`).
/// Lo unico propio es partir en dos lo que `Destino` deja junto.
enum FormaDeLaAplicacion {
  web('la web'),
  apk('el teléfono'),
  escritorio('el escritorio');

  const FormaDeLaAplicacion(this.comoSeLlama);

  /// Como se nombra en una frase: «Esta pantalla no existe en el teléfono.»
  final String comoSeLlama;

  /// La carpeta de `docs/manual/` que es suya.
  String get carpeta => switch (this) {
    FormaDeLaAplicacion.web => 'web',
    FormaDeLaAplicacion.apk => 'apk',
    FormaDeLaAplicacion.escritorio => 'escritorio',
  };
}

/// DE QUIEN ES UNA PAGINA.
///
/// Sale de su primera carpeta y nada mas. Una pagina que no este en ninguna de
/// las tres carpetas de las formas —`comun/`, `solo-administracion/`, la raiz, o
/// una carpeta que todavia no existe— **es de todos**, y eso es a proposito: el
/// dia que alguien anada `docs/manual/puesta-en-marcha/`, sus paginas salen en
/// las tres formas sin tocar ni una linea de aqui. Equivocarse hacia ese lado
/// ensena una pagina de mas; equivocarse hacia el otro **esconde el manual de
/// alguien sin que nada falle**.
class OrigenDeLaPagina {
  const OrigenDeLaPagina._(this.deQuienEs);

  /// `null` = de todos.
  final FormaDeLaAplicacion? deQuienEs;

  static const deTodos = OrigenDeLaPagina._(null);

  static OrigenDeLaPagina deLaPagina(String camino) {
    final primera = camino.contains('/') ? camino.split('/').first : '';
    for (final forma in FormaDeLaAplicacion.values) {
      if (forma.carpeta == primera) return OrigenDeLaPagina._(forma);
    }
    return deTodos;
  }

  bool seVeEn(FormaDeLaAplicacion forma) =>
      deQuienEs == null || deQuienEs == forma;
}

/// UNA TAREA: un `##` de una pagina, con sus pasos.
class TareaDelManual {
  const TareaDelManual({
    required this.camino,
    required this.tituloDeLaPagina,
    required this.titulo,
    required this.ancla,
    required this.cuerpo,
    this.rutaDePantalla,
    this.nombreDePantalla,
  });

  /// La pagina de la que sale: `apk/3-tareas.md`.
  final String camino;

  /// Y su titulo, que es lo que se pinta debajo del nombre de la tarea para
  /// saber de donde viene: «Tareas sueltas», «El día en el teléfono».
  final String tituloDeLaPagina;

  final String titulo;

  /// El ancla con la que los enlaces del manual apuntan a esta tarea
  /// (`#buscar-un-pedido`). Es la que escribe GitHub, porque es la que ya hay
  /// escrita en `docs/manual/`.
  final String ancla;

  /// El markdown de la tarea, **sin** su `##` y **sin** el renglon de «Empieza
  /// en:» — ese renglon se convierte en el boton de «llévame ahí», y dejarlo
  /// tambien en el texto seria decir dos veces lo mismo en una pantalla de 390
  /// px.
  final String cuerpo;

  /// LA DIRECCION DE LA PANTALLA EN LA QUE EMPIEZA ESTA TAREA, si la hay **en esta
  /// forma de la aplicacion**.
  ///
  /// Es lo que convierte un manual en una guia: se lee «esto se hace en
  /// Vehículos», se toca, y **se esta en Vehículos**. Sin cerrar la guia, buscar el
  /// menu y acordarse de a donde se iba.
  ///
  /// `null` con [nombreDePantalla] puesto es un caso de verdad y no un hueco: la
  /// tarea dice en que pantalla se hace y esa pantalla **aqui no existe** —el canal
  /// con PEDIDO no se registra en la APK ni en el escritorio—. Entonces no hay
  /// boton y se dice por que; poner el boton igual llevaria a «No hay ninguna
  /// pantalla en /webhook».
  final String? rutaDePantalla;

  /// COMO LA LLAMA EL MENU: «Vehículos». Es lo que el manual escribe entre
  /// comillas angulares, puesto o no puesto el boton.
  final String? nombreDePantalla;

  /// La clave con la que esta tarea viaja en la direccion
  /// (`/guia?tarea=apk/3-tareas.md~buscar-un-pedido`). Asi, al volver de «llévame
  /// ahí», la guia se abre donde estaba.
  ///
  /// **El separador es `~` y NO `#`**, aunque el ancla en el manual se escriba con
  /// `#`. Comprobado el 05/10/2026: un `#` dentro de un parametro **no sobrevive**
  /// al viaje por go_router ni codificado como `%23` — llega a la pantalla como
  /// `tarea=apk/3-tareas.md`, sin el ancla, y la tarea no se encuentra. La guia se
  /// abria con la lista en vez de con la tarea y nadie habria sabido por que. El
  /// `~` es un caracter sin reservar, asi que viaja tal cual.
  String get id => '$camino$separadorDeTarea$ancla';

  /// En un solo sitio: lo usan el id, las pruebas y quien tenga que partirlo.
  static const separadorDeTarea = '~';
}

/// UNA PAGINA del manual, entera.
class PaginaDelManual {
  const PaginaDelManual({
    required this.camino,
    required this.titulo,
    required this.origen,
    required this.contenido,
    required this.tareas,
  });

  final String camino;
  final String titulo;
  final OrigenDeLaPagina origen;

  /// El markdown tal cual viene de `docs/manual/`. **Esto es el documento
  /// oficial**: lo que se lee de principio a fin y lo que se imprime.
  final String contenido;

  /// Sus `##`, en el orden en que estan escritos.
  final List<TareaDelManual> tareas;

  /// La carpeta en la que vive, `''` si esta en la raiz del manual.
  String get carpeta =>
      camino.contains('/') ? camino.substring(0, camino.lastIndexOf('/')) : '';
}

/// DE DONDE SALE UN RESULTADO DE BUSQUEDA. Jose lo pidio con esas palabras: «el
/// buscador busca en las dos, y dice de cuál viene cada resultado».
enum DeDondeSale { tarea, pagina }

class Resultado {
  const Resultado({
    required this.deDondeSale,
    required this.titulo,
    required this.donde,
    required this.id,
    required this.enElTitulo,
  });

  final DeDondeSale deDondeSale;

  /// El nombre de la tarea, o el de la pagina.
  final String titulo;

  /// La linea de debajo: de que pagina viene la tarea, o en que carpeta esta la
  /// pagina.
  final String donde;

  /// [TareaDelManual.id] o [PaginaDelManual.camino].
  final String id;

  /// Si lo buscado aparece en el titulo. Esos van primero: quien escribe
  /// «camion» busca la tarea que se llama asi, no las once paginas que la
  /// nombran de pasada.
  final bool enElTitulo;
}

/// EL MANUAL ENTERO, ya leido.
class Manual {
  const Manual(this.paginas);

  /// Vacio, para cuando el paquete no se puede leer. **No es lo mismo que un
  /// manual sin tareas**, y quien lo pinta lo dice con palabras: aqui no se
  /// ensena una lista vacia como si el manual no tuviera nada dentro.
  static const vacio = Manual(<PaginaDelManual>[]);

  final List<PaginaDelManual> paginas;

  /// Lee el paquete que viaja en los assets.
  ///
  /// [pantallas] son **las pantallas registradas en ESTA forma de la
  /// aplicacion**, y de ahi sale el boton de «llévame ahí»: el manual nombra la
  /// pantalla por su etiqueta del menu —«Vehículos»— y aqui se busca cual es.
  ///
  /// Que la lista sea la de esta forma y no una lista fija es lo que impide un
  /// boton que no lleva a ningun sitio: el canal con PEDIDO no se registra en la
  /// APK ni en el escritorio, asi que alli esa tarea se queda sin boton y lo dice.
  factory Manual.desdeElPaquete(
    String paquete, {
    required List<PantallaDelMenu> pantallas,
  }) {
    final paginas = <PaginaDelManual>[];
    desempaquetarManual(paquete).forEach((camino, contenido) {
      paginas.add(
        _leerLaPagina(
          camino: camino,
          contenido: contenido,
          pantallas: pantallas,
        ),
      );
    });
    return Manual(paginas);
  }

  /// Las paginas de ESTA forma, en el orden en que se leen.
  ///
  /// Primero las suyas —el logistico de Santiago abre el telefono y lo primero
  /// que ve es su guia—, despues las de todos de menos a mas profundas, y la raiz
  /// al final: `docs/manual/README.md` es «elige tu manual», o sea el indice del
  /// repositorio, y dentro de la aplicacion el indice es esta pantalla.
  Manual paraLaForma(FormaDeLaAplicacion forma) {
    final suyas = [
      for (final p in paginas)
        if (p.origen.seVeEn(forma)) p,
    ];
    suyas.sort((a, b) {
      final porGrupo = _ordenDelGrupo(a, forma).compareTo(
        _ordenDelGrupo(b, forma),
      );
      if (porGrupo != 0) return porGrupo;
      final porCarpeta = a.carpeta.compareTo(b.carpeta);
      if (porCarpeta != 0) return porCarpeta;
      return _ordenDeLaPagina(a).compareTo(_ordenDeLaPagina(b));
    });
    return Manual(suyas);
  }

  List<TareaDelManual> get tareas => [
    for (final p in paginas) ...p.tareas,
  ];

  PaginaDelManual? pagina(String camino) {
    for (final p in paginas) {
      if (p.camino == camino) return p;
    }
    return null;
  }

  TareaDelManual? tarea(String id) {
    for (final t in tareas) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// BUSCAR. En las tareas **y** en las paginas.
  ///
  /// Lo buscado y lo mirado pasan los dos por [paraBuscar], que quita tildes y
  /// adornos: en un teclado de telefono nadie escribe «camión» con tilde, y
  /// `**camión**` no puede dejar de encontrarse por los asteriscos.
  ///
  /// Orden: lo que coincide en el titulo primero, y dentro de eso el orden de
  /// lectura. Quien escribe «camion» busca la tarea que se llama asi.
  List<Resultado> buscar(String texto) {
    final aguja = paraBuscar(texto);
    if (aguja.isEmpty) return const <Resultado>[];

    final encontrados = <Resultado>[];
    for (final p in paginas) {
      for (final t in p.tareas) {
        final enElTitulo = paraBuscar(t.titulo).contains(aguja);
        if (!enElTitulo && !paraBuscar(t.cuerpo).contains(aguja)) continue;
        encontrados.add(
          Resultado(
            deDondeSale: DeDondeSale.tarea,
            titulo: t.titulo,
            donde: t.tituloDeLaPagina,
            id: t.id,
            enElTitulo: enElTitulo,
          ),
        );
      }
      final enElTitulo = paraBuscar(p.titulo).contains(aguja);
      if (!enElTitulo && !paraBuscar(p.contenido).contains(aguja)) continue;
      encontrados.add(
        Resultado(
          deDondeSale: DeDondeSale.pagina,
          titulo: p.titulo,
          donde: p.carpeta.isEmpty ? 'Manual' : p.carpeta,
          id: p.camino,
          enElTitulo: enElTitulo,
        ),
      );
    }

    // Estable: `sort` de Dart no lo es, asi que se ordena por la pareja (en el
    // titulo, sitio en la lista) y el orden de lectura se conserva dentro de cada
    // mitad. Sin esto, dos busquedas iguales pueden salir en otro orden.
    final conSitio = [
      for (var i = 0; i < encontrados.length; i++) (i, encontrados[i]),
    ];
    conSitio.sort((a, b) {
      if (a.$2.enElTitulo != b.$2.enElTitulo) return a.$2.enElTitulo ? -1 : 1;
      return a.$1.compareTo(b.$1);
    });
    return [for (final par in conSitio) par.$2];
  }

  int _ordenDelGrupo(PaginaDelManual p, FormaDeLaAplicacion forma) {
    if (p.origen.deQuienEs == forma) return 0;
    if (p.carpeta.isEmpty) return 9;
    // Mas cerca de la raiz, antes: `comun/` antes que `comun/pantallas/`.
    return 1 + p.carpeta.split('/').length;
  }

  /// Dentro de una carpeta, el `README.md` primero: es la portada, y despues van
  /// `1-…`, `2-…`, que ya se ordenan solas por nombre.
  String _ordenDeLaPagina(PaginaDelManual p) {
    final nombre = p.camino.split('/').last;
    return nombre == 'README.md' ? '\u0000' : nombre;
  }
}

/// ESCRIBIR LO MISMO DE DOS MANERAS TIENE QUE ENCONTRARSE IGUAL.
///
/// Minusculas, sin tildes, sin adornos de markdown y con los espacios juntados.
/// Lo de las tildes no es un adorno: en el teclado de un telefono se escribe
/// «camion», y un buscador que no encuentra «camión» por eso es un buscador que
/// la gente deja de usar a la segunda vez.
String paraBuscar(String texto) {
  final limpio = soloElTexto(texto).toLowerCase();
  final salida = StringBuffer();
  for (final letra in limpio.split('')) {
    salida.write(_sinTilde[letra] ?? letra);
  }
  return salida.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _sinTilde = <String, String>{
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  // LA Ñ TAMBIEN, y hace falta de verdad: el manual escribe «señal» con ñ y
  // «sin-senal» sin ella (`docs/manual/apk/4-sin-senal.md`). Como lo buscado pasa
  // por aqui igual que lo mirado, las dos formas se encuentran la una a la otra;
  // dejarla fuera haria que buscar «sin senal» —lo que se teclea— no encontrara
  // la pagina que habla justo de eso.
  'ñ': 'n',
  'ç': 'c',
};

/// EL RENGLON QUE DICE EN QUE PANTALLA EMPIEZA UNA TAREA.
///
/// Asi lo escribe el manual, debajo del `##` de cada tarea:
///
/// ```md
/// ## Dar de alta un camión
///
/// **Empieza en:** **Menú → «Vehículos»**. **Necesita señal.**
/// ```
///
/// **La pantalla se nombra por su etiqueta del menu, entre comillas angulares**,
/// que es lo que la persona tiene delante — y es tambien, exactamente,
/// `PantallaRegistrada.titulo`. Asi que de ahi sale la direccion a la que lleva
/// el boton de «llévame ahí»: se busca una pantalla registrada que se llame asi.
///
/// Esto no es una convencion nueva inventada para la guia: es la forma que ya
/// estaba escrita en `docs/manual/` cuando se monto esta pantalla. Y tiene la
/// propiedad que importa: **ata el manual al registro**. El dia que alguien
/// renombre la entrada del menu, el manual deja de resolver y
/// `el_manual_apunta_a_pantallas_que_existen_test.dart` lo dice, en vez de dejar
/// una guia que nombra una pantalla que ya no se llama asi.
///
/// Tambien se acepta la forma con enlace —`[Rutas](/routes)`— por si alguien la
/// escribe: ahi la direccion viene dada y se comprueba que exista.
///
/// **El renglon se queda en el texto de la tarea**, no se convierte en el boton y
/// desaparece: lleva cosas que el boton no puede decir («**Necesita señal.**», «la
/// franja de arriba, desde cualquier pantalla»). Quitarlo seria quitar
/// informacion para no repetir tres palabras.
final renglonDePantalla = RegExp(r'^\s*\*\*Empieza en:\*\*(.*)$');

/// La pantalla nombrada entre comillas angulares: «Vehículos».
final _entreComillas = RegExp('\u00ab([^\u00bb]+)\u00bb');

/// La pantalla nombrada con un enlace a su direccion: `[Rutas](/routes)`.
final _conEnlace = RegExp(r'\[([^\]]+)\]\((/[^)\s]*)\)');

/// UNA PANTALLA DEL MENU, para que esto no tenga que importar `navegacion/`.
///
/// Son los dos datos que hacen falta: como se llama —lo que el manual escribe
/// entre comillas— y a donde lleva. La lista la monta quien lea el manual
/// (`datos/proveedores.dart`) a partir del registro de verdad.
class PantallaDelMenu {
  const PantallaDelMenu(this.ruta, this.titulo);

  final String ruta;
  final String titulo;
}

/// QUE PANTALLA NOMBRA EL RENGLON DE «Empieza en:», y si existe aqui.
///
/// Devuelve el nombre **siempre que el manual nombre una pantalla**, y la ruta solo
/// si esa pantalla esta registrada en esta forma. Son dos datos y no uno porque los
/// dos casos se cuentan distinto:
///
///  * nombre y ruta: boton de «llévame ahí»;
///  * nombre sin ruta: **no hay boton, y se dice por que** — la pantalla existe en
///    el producto pero no en esta forma;
///  * nada: la tarea no empieza en una pantalla. `**Empieza en:** la franja de
///    arriba, desde cualquier pantalla` es un sitio de verdad y no es una pantalla,
///    y su propio texto lo explica mejor que cualquier boton.
///
/// **El nombre solo se da por nombre de pantalla si el renglon dice «Menú →»**, que
/// es como el manual escribe exactamente eso. Sin esa condicion, un
/// `**Empieza en:** la pastilla de «STG»` se leeria como una pantalla llamada «STG»
/// y la tarea diria «esa pantalla no existe en el teléfono» sobre algo que no es
/// una pantalla — un aviso falso, que es peor que no avisar.
({String nombre, String? ruta})? pantallaQueNombra(
  String renglon,
  List<PantallaDelMenu> pantallas,
) {
  String? rutaDe(bool Function(PantallaDelMenu) cuadra) {
    for (final p in pantallas) {
      if (cuadra(p)) return p.ruta;
    }
    return null;
  }

  final conEnlace = _conEnlace.firstMatch(renglon);
  if (conEnlace != null) {
    final ruta = conEnlace.group(2)!;
    final registrada = rutaDe((p) => p.ruta == ruta);
    return (nombre: conEnlace.group(1)!.trim(), ruta: registrada);
  }

  if (!_porElMenu.hasMatch(renglon)) return null;
  final comillas = _entreComillas.firstMatch(renglon);
  if (comillas == null) return null;
  final nombre = comillas.group(1)!.trim();
  return (nombre: nombre, ruta: rutaDe((p) => p.titulo == nombre));
}

/// «Menú → «Pedidos»». Se admite la flecha de verdad y la de teclado, y con o sin
/// tilde: el manual lo escribe a mano en mas de ochenta sitios.
final _porElMenu = RegExp('[Mm]en[uú]\\s*(\u2192|->)');

PaginaDelManual _leerLaPagina({
  required String camino,
  required String contenido,
  required List<PantallaDelMenu> pantallas,
}) {
  final renglones = contenido.split('\n');

  var titulo = '';
  final tareas = <TareaDelManual>[];

  // Lo que se esta juntando de la tarea en curso.
  String? tituloDeLaTarea;
  var cuerpo = <String>[];
  ({String nombre, String? ruta})? pantallaDeLaTarea;
  var dentroDeCodigo = false;

  // CUANTAS VECES SE HA VISTO CADA ANCLA EN ESTA PAGINA.
  //
  // Hace falta porque el manual repite titulos a proposito: en
  // `comun/puesta-en-marcha.md` cada paso lleva su «## Qué es», su «## Lo que hay
  // que hacer» y su «## Qué se rompe si no se hace». Son tareas distintas con el
  // mismo nombre, y sin desambiguar comparten id: dos filas de la lista abririan
  // la misma, y `?tarea=` solo puede llevar a una.
  //
  // Se numera **como GitHub**: la primera tal cual, la segunda `-1`, la tercera
  // `-2`. Asi los enlaces que ya estan escritos en el manual siguen cuadrando.
  final vistas = <String, int>{};

  void cerrarLaTarea() {
    if (tituloDeLaTarea == null) return;
    final pantalla = pantallaDeLaTarea;
    final base = anclaDe(tituloDeLaTarea!);
    final cuantas = vistas.update(base, (n) => n + 1, ifAbsent: () => 0);
    tareas.add(
      TareaDelManual(
        camino: camino,
        tituloDeLaPagina: titulo,
        titulo: tituloDeLaTarea!,
        ancla: cuantas == 0 ? base : '$base-$cuantas',
        cuerpo: cuerpo.join('\n').trim(),
        rutaDePantalla: pantalla?.ruta,
        nombreDePantalla: pantalla?.nombre,
      ),
    );
    tituloDeLaTarea = null;
    cuerpo = <String>[];
    pantallaDeLaTarea = null;
  }

  for (final renglon in renglones) {
    // Dentro de un bloque de codigo no hay encabezados: un `## algo` ahi es una
    // linea de ejemplo, no una tarea nueva.
    if (RegExp(r'^\s{0,3}`{3,}').hasMatch(renglon)) {
      dentroDeCodigo = !dentroDeCodigo;
      if (tituloDeLaTarea != null) cuerpo.add(renglon);
      continue;
    }
    if (!dentroDeCodigo) {
      if (titulo.isEmpty && renglon.startsWith('# ')) {
        titulo = soloElTexto(renglon.substring(2).trim());
        continue;
      }
      if (renglon.startsWith('## ')) {
        cerrarLaTarea();
        tituloDeLaTarea = soloElTexto(renglon.substring(3).trim());
        continue;
      }
      // EL RENGLON DE «Empieza en:» SE QUEDA EN EL TEXTO, y ademas pone el
      // boton. No se quita: lleva cosas que el boton no puede decir
      // («**Necesita señal.**»), y la primera que declare la pantalla manda —una
      // tarea empieza en un sitio, no en dos.
      final conPantalla = renglonDePantalla.firstMatch(renglon);
      if (conPantalla != null &&
          tituloDeLaTarea != null &&
          pantallaDeLaTarea == null) {
        pantallaDeLaTarea = pantallaQueNombra(conPantalla.group(1)!, pantallas);
      }
    }
    if (tituloDeLaTarea != null) cuerpo.add(renglon);
  }
  cerrarLaTarea();

  // Sin `# ` ninguno, el nombre del fichero. Pasa en una pagina a medio escribir,
  // y una tarjeta con el titulo en blanco no se puede ni pulsar a ciegas.
  if (titulo.isEmpty) {
    final nombre = camino.split('/').last.replaceAll('.md', '');
    titulo = nombre == 'README' ? camino : nombre.replaceAll('-', ' ');
  }

  // El titulo de la pagina se sabe DESPUES de haber leido el `# `, y las tareas
  // se cerraron con el que habia entonces. Se vuelve a poner aqui para que
  // ninguna se quede con el titulo en blanco si el `# ` venia detras de algo.
  return PaginaDelManual(
    camino: camino,
    titulo: titulo,
    origen: OrigenDeLaPagina.deLaPagina(camino),
    contenido: contenido,
    tareas: [
      for (final t in tareas)
        TareaDelManual(
          camino: t.camino,
          tituloDeLaPagina: titulo,
          titulo: t.titulo,
          ancla: t.ancla,
          cuerpo: t.cuerpo,
          rutaDePantalla: t.rutaDePantalla,
          nombreDePantalla: t.nombreDePantalla,
        ),
    ],
  );
}

/// EL ANCLA DE UN ENCABEZADO, **como la escribe GitHub**.
///
/// No es un capricho de formato: en `docs/manual/` hay enlaces escritos a mano con
/// esa forma —`#poner-o-corregir-un-almacén`, `#cambiar-entre-usd-y-cup`— y si
/// aqui se calculara de otra manera esos enlaces no llevarian a ninguna parte
/// dentro de la aplicacion. Se tocarian tres veces y se dejarian de tocar.
///
/// Las tres reglas de GitHub, y las tres hicieron falta de verdad:
///
///  1. **minusculas**;
///  2. **fuera la puntuacion**, pero las tildes y la ñ **se quedan**;
///  3. **cada espacio es un guion, y no se juntan**. Esto ultimo se descubrio el
///     05/10/2026 con un enlace que ya estaba escrito en `apk/3-tareas.md`:
///     `#paso-4--la-tasa-de-cambio-de-la-sucursal`, de un encabezado
///     «Paso 4 · La tasa…». El `·` se va y deja DOS espacios, o sea DOS guiones.
///     Juntandolos, ese enlace —y los demas con `·`— no abrian nada.
String anclaDe(String titulo) => soloElTexto(titulo)
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N} \t-]', unicode: true), '')
    .trim()
    .replaceAll(RegExp(r'[ \t]'), '-');
