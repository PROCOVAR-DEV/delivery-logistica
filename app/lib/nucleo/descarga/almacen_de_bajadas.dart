// DONDE SE GUARDA LO QUE SE ESTA BAJANDO, y nada mas.
//
// Esto salio de `mapa/carpeta_del_mapa.dart` el 05/10/2026, al hacer que la
// actualizacion de la APK se baje dentro de la aplicacion igual que el mapa. La
// razon de sacarlo de alli es la de siempre en esta casa: **dos descargadores
// que se separan**. El motor de bajar —reanudar, comprobar el rango, la huella,
// el tope— es uno solo (`descarga_reanudable.dart`) y necesita un sitio donde
// escribir; ese sitio es esto.
//
// Es un puerto y no un `File` por dos motivos:
//
//  1. **Para poder probarlo.** Las pruebas inyectan los bytes y no bajan nada —
//     ni de Procovar, ni de ningun sitio. [AlmacenEnMemoria] es lo que ejercita
//     el reanudado y la huella sin red y sin disco.
//  2. **`dart:io` no existe en el navegador** y esta aplicacion compila tambien
//     para web. Ni el mapa ni la actualizacion se bajan alli (`CLAUDE.md` §1),
//     pero el codigo tiene que compilar igual en los cuatro destinos.

/// Lo que hace falta saber hacer con un fichero que se esta bajando.
abstract interface class AlmacenDeBajadas {
  /// Cuantos bytes tiene [nombre], o `0` si no esta. **`0` y «no esta» son lo
  /// mismo aqui a proposito**: los dos significan «hay que empezar por el
  /// principio».
  Future<int> bytes(String nombre);

  /// Anade al final. Es lo que hace posible reanudar.
  Future<void> anadir(String nombre, List<int> trozo);

  Future<void> borrar(String nombre);

  Future<void> renombrar(String de, String a);

  /// El contenido en trozos, para calcular el `sha256` sin cargarse decenas de
  /// MB en la memoria de un telefono.
  Stream<List<int>> porTrozos(String nombre);

  Future<void> escribirTexto(String nombre, String texto);

  Future<String?> leerTexto(String nombre);

  /// LA RUTA DE VERDAD EN EL DISCO, o `null` si no hay disco.
  ///
  /// Hace falta para una sola cosa, y es la que trajo este metodo: el APK de la
  /// actualizacion se le pasa al instalador de Android **por su ruta**, y el
  /// instalador es otro proceso — no puede leer de la memoria de este. Lo del
  /// mapa no la usa.
  ///
  /// `null` en la web, donde no hay carpeta ninguna.
  String? rutaEnDisco(String nombre);
}

/// UN ALMACEN EN MEMORIA. Es lo que usan las pruebas, y lo que permite
/// ejercitar la reanudacion y el `sha256` **sin una sola peticion de red y sin
/// tocar el disco**.
class AlmacenEnMemoria implements AlmacenDeBajadas {
  AlmacenEnMemoria({this.comoSiEstuvieraEn = '/memoria'});

  /// La carpeta que se finge al preguntar por [rutaEnDisco]. Es una ruta de
  /// mentira a proposito: lo que se comprueba con ella es que quien instala
  /// recibe **el fichero que se acaba de comprobar**, no que exista en el disco.
  final String comoSiEstuvieraEn;

  final Map<String, List<int>> _ficheros = {};

  /// Para que una prueba pueda dejar un fichero puesto de entrada.
  void sembrar(String nombre, List<int> contenido) {
    _ficheros[nombre] = [...contenido];
  }

  bool tiene(String nombre) => _ficheros.containsKey(nombre);

  /// Lo guardado tal cual, o `null` si no esta. Lo usa quien extienda esto para
  /// añadir una lectura propia —el mapa lee teselas por rango— sin tener que
  /// repetir el mapa de ficheros.
  List<int>? bytesCrudos(String nombre) => _ficheros[nombre];

  @override
  Future<int> bytes(String nombre) async => _ficheros[nombre]?.length ?? 0;

  @override
  Future<void> anadir(String nombre, List<int> trozo) async {
    (_ficheros[nombre] ??= <int>[]).addAll(trozo);
  }

  @override
  Future<void> borrar(String nombre) async => _ficheros.remove(nombre);

  @override
  Future<void> renombrar(String de, String a) async {
    final contenido = _ficheros.remove(de);
    if (contenido != null) _ficheros[a] = contenido;
  }

  @override
  Stream<List<int>> porTrozos(String nombre) async* {
    final contenido = _ficheros[nombre];
    if (contenido == null) return;
    // En trozos de verdad, no de una vez: es lo que ejercita el calculo por
    // partes del sha256, que es como corre en el aparato.
    for (var i = 0; i < contenido.length; i += 8192) {
      yield contenido.sublist(
        i,
        i + 8192 > contenido.length ? contenido.length : i + 8192,
      );
    }
  }

  @override
  Future<void> escribirTexto(String nombre, String texto) async {
    _ficheros[nombre] = texto.codeUnits;
  }

  @override
  Future<String?> leerTexto(String nombre) async {
    final c = _ficheros[nombre];
    return c == null ? null : String.fromCharCodes(c);
  }

  @override
  String? rutaEnDisco(String nombre) => '$comoSiEstuvieraEn/$nombre';
}
