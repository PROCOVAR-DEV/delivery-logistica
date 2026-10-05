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
///
/// **Y el documento entero sigue estando**, que es la otra mitad del encargo:
/// «pon las dos, el documento oficial y las tareas y sus pasos». No son dos
/// copias —la tarea es un trozo de la pagina, sacado de la misma cadena de
/// texto— y por eso no se pueden separar: no hay dos textos que mantener.
/// `test/pantallas/ayuda/las_tareas_salen_de_la_pagina_test.dart` lo ata.
///
/// ## UNA TAREA NO ES UN `##`. Eso fue el fallo de la 1.0.22
///
/// La primera version listaba **todos los `##` del manual**: 301 filas. Jose las
/// abrio y no le llevaban a ningun sitio, porque la mayoria no eran cosas que
/// hacer sino trozos de un documento — «Qué es», «Lo que hay que hacer», «Qué se
/// rompe si no se hace», «Los filtros». Sus palabras, 05/10/2026:
///
/// > «me pusiste las tareas pero las tareas no me mueven a ningún lugar
/// > enseñándome cómo debería trabajar en tiempo real, como un vídeo»
/// > «q las tareas enseñen algo de verdad no mierda textual q la gente no quiere
/// > leer quiere q le enseñes donde ir donde tocar para cada cosa»
///
/// Asi que una tarea es **un encabezado marcado a mano** con [marcaDeTarea], a
/// cualquier nivel (`#`, `##` o `###`): el manual las tiene escritas a los tres
/// niveles y eso no se puede arreglar con una regla de nivel. Lo que **no** puede
/// pasar es que la marca se olvide en ninguno de los dos sentidos, y por eso hay
/// dos pruebas en pareja en
/// `test/pantallas/ayuda/una_tarea_se_marca_test.dart`:
///
///  * **marcado sin «Empieza en:» ⇒ rojo.** Una tarea que no dice donde empieza
///    no puede llevar a ningun sitio, que es de lo que se quejo Jose.
///  * **«Empieza en:» sin marcar ⇒ rojo.** Es el sentido que de verdad importa:
///    sin el, alguien escribe una tarea nueva, se olvida de la marca y la tarea
///    **no sale en la lista sin que nada falle** — el modo de fallo del §3-bis,
///    que es el peor de esta casa porque no se ve.
///
/// Un `##` nuevo en una ficha de pantalla no lleva marca, asi que no se cuela.
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

/// LA MARCA QUE DICE «ESTE ENCABEZADO ES UNA TAREA».
///
/// Va en el renglon **inmediatamente siguiente** al encabezado, sola. Es un
/// comentario de HTML, asi que en GitHub no se ve: el manual se sigue leyendo
/// igual en el repositorio, que es la mitad de su razon de ser.
///
/// Inmediatamente siguiente, y no «en algun sitio debajo»: una regla difusa se
/// cumple a medias y entonces no se puede probar. Asi se puede buscar con un
/// `grep` y se puede contar.
const marcaDeTarea = '<!-- tarea -->';

/// LA MARCA QUE DICE A QUE CONTROL APUNTA UN PASO.
///
/// Va **al final del renglon del paso**, tambien como comentario de HTML:
///
/// ```md
/// 1. Toca **«Nuevo vehículo»**, arriba a la derecha. <!-- señala: vehiculos-nuevo -->
/// ```
///
/// El nombre es el de [ControlSenalado], y que exista lo comprueba
/// `test/pantallas/ayuda/los_pasos_senalan_controles_que_existen_test.dart`: un
/// nombre mal escrito dejaria un paso apuntando a nada, y **un recorrido que
/// apunta al boton equivocado es peor que uno que no apunta**.
final marcaDeSenal = RegExp(r'<!--\s*se[nñ]ala:\s*([a-z0-9-]+)\s*-->');

/// UN PASO DEL RECORRIDO GUIADO: una cosa que tocar, y donde esta.
///
/// Jose, 05/10/2026, despues de probar la 1.0.22:
///
/// > «las cosas q tienen botones me mueven a la página pero no me dice paso a
/// > paso con sus tooltips señalándome paso a paso en la aplicación cada botón q
/// > debo tocar»
///
/// O sea: el texto del paso no es el producto. **El producto es el foco encima
/// del control.** Un paso que describe con palabras donde hay que tocar, aunque
/// la descripcion sea exacta, esta a medias.
class PasoGuiado {
  const PasoGuiado({
    required this.cual,
    required this.deCuantos,
    required this.texto,
    required this.senala,
    this.detalles = const <String>[],
  });

  /// 1..[deCuantos]. Es el sitio en el RECORRIDO, no el numero que el manual
  /// escribio: el cajon dice «3 de 7» y eso tiene que cuadrar con cuantas veces
  /// hay que pulsar «Siguiente», pase lo que pase con la numeracion del texto.
  final int cual;
  final int deCuantos;

  /// El markdown del paso, **sin** la marca de [marcaDeSenal]: esa marca es para
  /// la maquina y pintarla seria ensenar el andamio.
  final String texto;

  /// El nombre del control al que apunta, o `null` si el paso no senala ninguno.
  ///
  /// `null` **no se calla**: el recorrido lo pinta como un paso sin foco y lo
  /// dice con esas palabras (§4, nada se descarta en silencio). Lo que no hace
  /// nunca es apuntar a un sitio cualquiera.
  final String? senala;

  /// Los sub-puntos sangrados debajo del paso, tal cual los escribio el manual.
  final List<String> detalles;

  bool get seSenala => senala != null;
}

/// UNA TAREA: un encabezado marcado con [marcaDeTarea], con sus pasos.
class TareaDelManual {
  const TareaDelManual({
    required this.camino,
    required this.tituloDeLaPagina,
    required this.titulo,
    required this.ancla,
    required this.cuerpo,
    this.pasos = const <PasoGuiado>[],
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

  /// LOS PASOS DEL RECORRIDO, en orden. Vacio = esta tarea no se puede guiar.
  final List<PasoGuiado> pasos;

  /// SE PUEDE GUIAR si hay pasos **y** se sabe sobre que pantalla ponerlos.
  ///
  /// Las dos mitades hacen falta y por motivos distintos:
  ///
  ///  * sin pasos no hay recorrido, solo texto;
  ///  * con [nombreDePantalla] puesto y [rutaDePantalla] en `null`, el manual
  ///    nombra una pantalla que **en esta forma no existe** (el canal con PEDIDO
  ///    en la APK). Guiar ahi seria poner el foco encima de otra pantalla y
  ///    senalar cualquier cosa.
  ///
  /// Una tarea sin pantalla ninguna —«la franja de arriba, desde cualquier
  /// pantalla»— **si se guia**: el sitio es el de ahora mismo, no hay a donde
  /// llevar a nadie, y eso es correcto, no un hueco.
  bool get seAcompana =>
      pasos.isNotEmpty && (nombreDePantalla == null || rutaDePantalla != null);

  /// Cuantos de sus pasos senalan un control de verdad. Es el numero que dice si
  /// esta tarea ensena o solo cuenta.
  int get pasosSenalados => pasos.where((p) => p.seSenala).length;

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
      final porGrupo = _ordenDelGrupo(
        a,
        forma,
      ).compareTo(_ordenDelGrupo(b, forma));
      if (porGrupo != 0) return porGrupo;
      final porCarpeta = a.carpeta.compareTo(b.carpeta);
      if (porCarpeta != 0) return porCarpeta;
      return _ordenDeLaPagina(a).compareTo(_ordenDeLaPagina(b));
    });
    return Manual(suyas);
  }

  List<TareaDelManual> get tareas => [for (final p in paginas) ...p.tareas];

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

/// LEER UNA PAGINA: su titulo, su texto entero y sus TAREAS.
///
/// ## Donde empieza y donde acaba una tarea
///
/// Empieza en su encabezado marcado y acaba en **el siguiente encabezado de nivel
/// igual o mas alto**, o en la siguiente tarea. Eso no es una comodidad: es lo que
/// hace que `# Paso 2 — Al menos un vehículo` se lleve dentro su «Qué es», su «Lo
/// que hay que hacer» y su «Qué se rompe si no se hace», que es como esta escrito
/// en `comun/puesta-en-marcha.md` y como se entiende. Con la regla de «hasta el
/// siguiente encabezado, sea del nivel que sea», ese paso se partiria en tres
/// filas de la lista y ninguna de las tres seria una cosa que hacer — que es
/// exactamente lo que Jose rechazo.
PaginaDelManual _leerLaPagina({
  required String camino,
  required String contenido,
  required List<PantallaDelMenu> pantallas,
}) {
  final renglones = contenido.split('\n');

  var titulo = '';
  var tituloVisto = false;
  final tareas = <_TareaEnObra>[];
  _TareaEnObra? enObra;
  var dentroDeCodigo = false;

  // CUANTAS VECES SE HA VISTO CADA ANCLA EN ESTA PAGINA.
  //
  // Se cuentan **todos** los encabezados y no solo las tareas, porque el ancla
  // tiene que ser la que escribe GitHub: en `docs/manual/` hay enlaces escritos a
  // mano (`#paso-4--la-tasa-de-cambio-de-la-sucursal`) y GitHub numera por orden
  // de aparicion contando todo. Contar solo las tareas daria otro sufijo y esos
  // enlaces dejarian de abrir nada dentro de la aplicacion.
  //
  // Se numera como GitHub: la primera tal cual, la segunda `-1`, la tercera `-2`.
  final vistas = <String, int>{};

  final encabezado = RegExp(r'^(#{1,6})\s+(.*)$');

  for (var i = 0; i < renglones.length; i++) {
    final renglon = renglones[i];

    // Dentro de un bloque de codigo no hay encabezados: un `## algo` ahi es una
    // linea de ejemplo, no una tarea nueva.
    if (RegExp(r'^\s{0,3}`{3,}').hasMatch(renglon)) {
      dentroDeCodigo = !dentroDeCodigo;
      enObra?.cuerpo.add(renglon);
      continue;
    }

    if (!dentroDeCodigo) {
      final cabeza = encabezado.firstMatch(renglon);
      if (cabeza != null) {
        final nivel = cabeza.group(1)!.length;
        final texto = soloElTexto(cabeza.group(2)!.trim());
        final base = anclaDe(cabeza.group(2)!.trim());
        final cuantas = vistas.update(base, (n) => n + 1, ifAbsent: () => 0);
        final ancla = cuantas == 0 ? base : '$base-$cuantas';

        // EL PRIMER `# ` ES EL TITULO DE LA PAGINA, nunca una tarea. Las paginas
        // del dia (`apk/2-el-dia-en-el-telefono.md`) tienen DIEZ `# ` mas debajo,
        // y esos si son tareas.
        if (!tituloVisto && nivel == 1) {
          titulo = texto;
          tituloVisto = true;
          if (enObra != null) {
            tareas.add(enObra);
            enObra = null;
          }
          continue;
        }

        final esTarea =
            i + 1 < renglones.length && renglones[i + 1].trim() == marcaDeTarea;

        // Se cierra la que habia si esta tarea empieza, o si el encabezado es de
        // nivel igual o mas alto. Un encabezado mas profundo se queda DENTRO.
        if (enObra != null && (esTarea || nivel <= enObra.nivel)) {
          tareas.add(enObra);
          enObra = null;
        }

        if (esTarea) {
          enObra = _TareaEnObra(nivel: nivel, titulo: texto, ancla: ancla);
          i++; // la marca no entra en el cuerpo: es andamio.
          continue;
        }
        enObra?.cuerpo.add(renglon);
        continue;
      }

      // EL RENGLON DE «Empieza en:» SE QUEDA EN EL TEXTO, y ademas pone el boton.
      // No se quita: lleva cosas que el boton no puede decir («**Necesita
      // señal.**»), y la primera que declare la pantalla manda — una tarea empieza
      // en un sitio, no en dos.
      final conPantalla = renglonDePantalla.firstMatch(renglon);
      if (conPantalla != null && enObra != null && enObra.pantalla == null) {
        enObra.pantalla = pantallaQueNombra(conPantalla.group(1)!, pantallas);
      }
    }

    enObra?.cuerpo.add(renglon);
  }
  if (enObra != null) tareas.add(enObra);

  // Sin `# ` ninguno, el nombre del fichero. Pasa en una pagina a medio escribir,
  // y una tarjeta con el titulo en blanco no se puede ni pulsar a ciegas.
  if (titulo.isEmpty) {
    final nombre = camino.split('/').last.replaceAll('.md', '');
    titulo = nombre == 'README' ? camino : nombre.replaceAll('-', ' ');
  }

  return PaginaDelManual(
    camino: camino,
    titulo: titulo,
    origen: OrigenDeLaPagina.deLaPagina(camino),
    contenido: contenido,
    tareas: [
      for (final t in tareas)
        TareaDelManual(
          camino: camino,
          // El titulo de la pagina se sabe DESPUES de haber leido el `# `, asi
          // que se pone aqui y no al cerrar cada tarea.
          tituloDeLaPagina: titulo,
          titulo: t.titulo,
          ancla: t.ancla,
          cuerpo: t.cuerpo.join('\n').trim(),
          pasos: pasosDelCuerpo(t.cuerpo.join('\n')),
          rutaDePantalla: t.pantalla?.ruta,
          nombreDePantalla: t.pantalla?.nombre,
        ),
    ],
  );
}

/// Lo que se va juntando de una tarea mientras se lee la pagina.
class _TareaEnObra {
  _TareaEnObra({
    required this.nivel,
    required this.titulo,
    required this.ancla,
  });

  final int nivel;
  final String titulo;
  final String ancla;
  final List<String> cuerpo = <String>[];
  ({String nombre, String? ruta})? pantalla;
}

/// LOS PASOS DEL RECORRIDO, sacados del cuerpo de una tarea.
///
/// Son **la lista numerada pegada al margen**, y se para en el primer encabezado
/// que venga DESPUES del primer paso. Esa segunda mitad hace falta y es medida, no
/// prudencia: debajo de cada tarea el manual escribe sus averias en `###` —«Si no
/// aparece», «Si el botón está apagado»— y esas listas tambien van numeradas. Sin
/// la parada, «Dar de alta un camión» tendria diez pasos y cuatro de ellos serian
/// «qué hacer si no se guarda», o sea el recorrido llevaria a sitios donde no hay
/// que ir.
///
/// Y no se para en el primer encabezado a secas porque hay tareas cuyos pasos
/// viven **debajo** de un `## Lo que hay que hacer` (`comun/puesta-en-marcha.md`):
/// ahi el encabezado va antes del primer paso y pararse en el dejaria la tarea sin
/// ninguno.
/// Y EL RECORRIDO EMPIEZA EN EL PASO 1, o no es un recorrido.
///
/// Esa guarda la pidió un renglón de verdad, `web/2-tareas.md`: «…encima de una
/// lista de / 3. No es un fallo.» La frase se parte a los 80 caracteres y la mitad
/// de abajo empieza por «3. », así que el lector de markdown la ve como un paso
/// numerado. Sin esta condición, «Filtrar la lista de rutas» salía con **un paso
/// que decía «No es un fallo.»** y el recorrido guiado se ofrecía para eso.
///
/// Se comprueba el número que escribió el manual y no la cuenta propia: un trozo
/// suelto de una frase no empieza en 1 casi nunca, y una lista de instrucciones
/// empieza en 1 siempre.
List<PasoGuiado> pasosDelCuerpo(String cuerpo) {
  final crudos = <({String texto, List<String> detalles})>[];
  var empezaron = false;

  for (final bloque in bloquesDe(cuerpo)) {
    if (bloque is Encabezado) {
      if (empezaron) break;
      continue;
    }
    if (bloque is! Punto) continue;
    if (bloque.esPaso && bloque.nivel == 0) {
      if (!empezaron && bloque.numero != '1') continue;
      empezaron = true;
      crudos.add((texto: bloque.texto, detalles: <String>[]));
      continue;
    }
    // Un sub-punto debajo de un paso es una nota DE ESE paso.
    if (empezaron && bloque.nivel > 0 && crudos.isNotEmpty) {
      crudos.last.detalles.add(bloque.texto);
    }
  }

  return [
    for (var i = 0; i < crudos.length; i++)
      PasoGuiado(
        cual: i + 1,
        deCuantos: crudos.length,
        texto: sinLaMarcaDeSenal(crudos[i].texto),
        // LA MARCA ES DEL PASO, LA ESCRIBA DONDE LA ESCRIBA.
        //
        // Se busca en el renglon del paso **y en sus notas**. En el manual los pasos
        // largos llevan sus avisos como sub-vinetas, y la marca acaba al final de la
        // ultima: buscandola solo en el renglon del paso, cuatro pasos de
        // `web/2-tareas.md` salian sin foco teniendo su control escrito. Medido el
        // 05/10/2026.
        senala: _senalaDe([crudos[i].texto, ...crudos[i].detalles]),
        detalles: [for (final d in crudos[i].detalles) sinLaMarcaDeSenal(d)],
      ),
  ];
}

/// El primer control que nombran estos renglones, o `null`.
String? _senalaDe(List<String> renglones) {
  for (final renglon in renglones) {
    final cual = marcaDeSenal.firstMatch(renglon);
    if (cual != null) return cual.group(1);
  }
  return null;
}

/// El texto de un paso sin su marca, y sin el hueco que deja al irse.
String sinLaMarcaDeSenal(String texto) =>
    texto.replaceAll(marcaDeSenal, '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// EL TEXTO SIN EL ANDAMIO, para pintarlo.
///
/// Las dos marcas —[marcaDeTarea] y [marcaDeSenal]— son comentarios de HTML, asi
/// que en GitHub no se ven. **El lector de markdown de la casa no sabe de HTML**,
/// asi que sin esto saldrian tal cual, en medio del texto, en la puerta del
/// Documento: `<!-- tarea -->` debajo de cada titulo.
///
/// Se quita al PINTAR y no al leer, porque `PaginaDelManual.contenido` tiene que
/// seguir siendo byte a byte lo que hay en `docs/manual/`: es lo que compara
/// `el_manual_no_se_separa_del_repositorio_test.dart`.
String sinElAndamio(String markdown) => markdown
    .replaceAll(marcaDeSenal, '')
    // El renglon de la marca de tarea se va ENTERO, con su salto: dejarlo vacio
    // mete una linea en blanco de mas entre cada titulo y su texto.
    .replaceAll(
      RegExp(
        '^[ \\t]*${RegExp.escape(marcaDeTarea)}[ \\t]*\n',
        multiLine: true,
      ),
      '',
    )
    .replaceAll(marcaDeTarea, '');

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
String anclaDe(String titulo) =>
    soloElTexto(titulo)
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N} \t-]', unicode: true), '')
        .trim()
        .replaceAll(RegExp(r'[ \t]'), '-');
