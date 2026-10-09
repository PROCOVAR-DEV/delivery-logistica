import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../registro/registro.dart';
import 'almacen_sesion.dart';
import 'sesion.dart';

/// EL ALMACEN DEL ESCRITORIO DE LINUX: un fichero propio, cifrado, en la
/// carpeta de datos de la aplicacion.
///
/// ## Por que no se usa el almacen del sistema
///
/// Porque en Linux **no sirve**, y no por una configuracion de este equipo.
/// `flutter_secure_storage_linux` 3.0.3 arma su `SecretSchema` asi:
///
/// ```cpp
/// the_schema.name = label.c_str();   // en el constructor
/// ...
/// void setLabel(std::string l) { label = l; }   // despues
/// ```
///
/// El `name` del esquema se queda apuntando al buffer de un `std::string` que
/// luego se reasigna: puntero colgando, y el atributo `xdg:schema` que acaba
/// escrito en el llavero es basura (`"+"` en la prueba del 15/09/2026). El
/// `lookup` de vuelta busca por el esquema bueno y no encuentra nada. O sea:
/// **en Linux ese almacen es de solo escritura**. `write` contesta que si,
/// `read` devuelve vacio, y la persona se encuentra la pantalla de la
/// contrasena con sus datos ahi mismo, en el disco.
///
/// Se eligio almacen propio en vez de mantener un fork del plugin por tres
/// razones: el fork obliga a compilar C++ nuestro en cada maquina que compile,
/// nos ata a seguir la version de arriba para siempre, y **aun arreglado
/// dependeria de que haya un servicio de secretos corriendo y desbloqueado** —
/// que en un escritorio sin sesion grafica de las de siempre, o en un aparato
/// de reparto que arranca solo, no lo hay. Un fichero en la carpeta de datos
/// esta siempre.
///
/// Android **no pasa por aqui**: alli manda el Keystore y funciona
/// (`almacen_sesion_nativo.dart`).
///
/// ## QUE SEGURIDAD TIENE ESTO DE VERDAD — leelo antes de confiarle nada
///
/// El fichero va cifrado, pero **la clave se puede recalcular en esta maquina y
/// con esta cuenta sin saber ninguna contrasena**. Sale de:
///
/// ```
/// material = machine-id del sistema + el usuario + la ruta de la carpeta
/// maestra  = HMAC-SHA256(clave: sal aleatoria del fichero, dato: material)
/// ```
///
/// Y **tiene que ser asi**: `docs/identidad.md` manda que sin conexion no se
/// comprueba ninguna contrasena, asi que la clave no puede salir de la
/// contrasena de nadie — si saliera de ahi, abrir la aplicacion sin senal
/// pediria la contrasena, que es exactamente lo que este almacen existe para
/// evitar. La consecuencia hay que decirla entera y sin adornos:
///
///  * **NO protege** de alguien que entre con la cuenta de esa persona en ese
///    ordenador, ni de root, ni de un programa que corra como esa persona. Todo
///    eso puede leer el material, rehacer la clave y sacar el par de tokens.
///    Contra ese enemigo lo unico que hay son los permisos del fichero (0600) y
///    el par caduca en 30 dias.
///  * **SI protege** de que el fichero viaje suelto y siga sirviendo: una copia
///    de seguridad restaurada en otro ordenador, el directorio copiado a un
///    pendrive, la carpeta adjunta en un informe de fallo. Fuera de esta
///    maquina y de esta cuenta el fichero no se abre, porque el material no
///    esta dentro de el.
///  * **SI evita** que el token salga en claro en un `grep`, en un indexador de
///    escritorio o en un volcado del disco a ojo.
///
/// En una frase: esto es **cifrado atado a la maquina**, no una caja fuerte. El
/// dia que se decida cifrar tambien la copia de datos con una clave derivada de
/// la contrasena (lo que `identidad.md` deja escrito para mas adelante), este
/// fichero es el primero que tiene que cambiar.
class AlmacenEnFichero with PorRevocarEnTexto implements AlmacenDeSesion {
  AlmacenEnFichero({Directory? carpeta, String? materialDeLaMaquina})
    : _carpetaPuesta = carpeta,
      _materialPuesto = materialDeLaMaquina;

  /// El nombre no lleva `.json` a proposito: dentro no hay nada legible y una
  /// extension que invite a abrirlo con un editor es una invitacion a
  /// «arreglarlo» a mano.
  static const _nombreDelFichero = 'sesion.caja';

  /// El de la ida y vuelta de [comprobar]. Aparte del de la sesion: comprobar
  /// no puede ser lo que rompa lo que se quiere proteger.
  static const _nombreDeLaPrueba = 'comprobacion.caja';

  /// Donde se guarda el material de la maquina cuando el sistema no tiene
  /// `machine-id`. Ver [_material].
  static const _nombreDelRespaldo = 'maquina.sal';

  /// Lo que se mete en la derivacion junto con la sal, para que dos cosas
  /// cifradas con el mismo material nunca compartan clave.
  static const _proposito = 'reparto.sesion.v1';

  final Directory? _carpetaPuesta;
  final String? _materialPuesto;

  Directory? _carpeta;
  String? _material;

  /// La sesion guardada, o `null` si no hay ninguna **o no se pudo leer o no se
  /// pudo descifrar**. No lanza nunca — la regla de `almacen_sesion.dart`.
  ///
  /// Un fichero que no se puede descifrar (se copio de otra maquina, se corto a
  /// medias, se toco a mano) se trata como «no hay sesion» y **no se borra**:
  /// un almacen que hoy no contesta puede contestar manana, y borrar el par por
  /// un fallo del disco es la regla 3 de `identidad.md` aplicada al fichero.
  @override
  Future<Sesion?> leer() async {
    try {
      final fichero = await _elFichero(_nombreDelFichero);
      if (!fichero.existsSync()) return null;
      final texto = _descifrar(await fichero.readAsString());
      if (texto == null) {
        Registro.fallo(
          'el fichero de la sesion esta en la carpeta y no se puede abrir: '
          'o viene de otra maquina o esta estropeado. No se borra',
        );
        return null;
      }
      return Sesion.deJson(jsonDecode(texto) as Map<String, Object?>);
    } on Object catch (e, pila) {
      Registro.fallo('no se pudo leer el fichero de la sesion', e, pila);
      return null;
    }
  }

  /// Guarda el par **y lo vuelve a leer del disco para decir si quedo**.
  ///
  /// La lectura de vuelta no sobra ni aqui, donde el almacen es nuestro: un
  /// disco lleno, una carpeta de solo lectura o un montaje que se cayo dan
  /// exactamente el mismo cuadro que daba el llavero de Linux —«la escritura no
  /// dio error» y la sesion no esta—, y eso no se puede descubrir en el
  /// siguiente arranque.
  @override
  Future<bool> guardar(Sesion sesion) async {
    final texto = jsonEncode(sesion.aJson());
    try {
      await _escribir(_nombreDelFichero, texto);
      final vuelta = _descifrar(
        await (await _elFichero(_nombreDelFichero)).readAsString(),
      );
      if (vuelta == texto) return true;
      Registro.fallo(
        'el fichero de la sesion se escribio y al releerlo no cuadra: '
        'este aparato no va a poder trabajar sin senal',
      );
      return false;
    } on Object catch (e, pila) {
      Registro.fallo('no se pudo guardar el fichero de la sesion', e, pila);
      return false;
    }
  }

  @override
  Future<void> borrar() async {
    try {
      final fichero = await _elFichero(_nombreDelFichero);
      if (fichero.existsSync()) await fichero.delete();
    } on Object catch (e) {
      // Salir tiene que poder salir. Si el fichero no se deja borrar, el par
      // caduca solo; lo que no puede pasar es que la persona se quede dentro.
      Registro.aviso('no se pudo borrar el fichero de la sesion: $e');
    }
  }

  /// Aparte del de la sesion, a proposito: ver [RefrescoPorRevocar].
  static const _nombreDePorRevocar = 'por_revocar.caja';

  @override
  Future<String?> leerPorRevocar() async {
    try {
      final fichero = await _elFichero(_nombreDePorRevocar);
      if (!fichero.existsSync()) return null;
      return _descifrar(await fichero.readAsString());
    } on Object catch (e) {
      Registro.aviso('no se pudo leer el fichero de lo por revocar: $e');
      return null;
    }
  }

  @override
  Future<bool> escribirPorRevocar(String? texto) async {
    try {
      if (texto == null) {
        final fichero = await _elFichero(_nombreDePorRevocar);
        if (fichero.existsSync()) await fichero.delete();
      } else {
        await _escribir(_nombreDePorRevocar, texto);
      }
      return true;
    } on Object catch (e) {
      Registro.aviso('no se pudo escribir el fichero de lo por revocar: $e');
      return false;
    }
  }

  /// Una ida y vuelta de verdad —escribir, leer, descifrar, borrar— con su
  /// propio fichero.
  ///
  /// Se hace entera y contra el disco porque lo que hay que responder es «¿este
  /// aparato guarda?», y de eso no se entera nadie mirando si la carpeta
  /// existe: el caso que se vio en el llavero era justo uno que decia que si a
  /// todo y perdia el dato.
  @override
  Future<SaludDelAlmacen> comprobar() async {
    // Un testigo distinto cada vez: uno fijo no distingue «se leyo lo que acabo
    // de escribir» de «quedo ahi de la vez anterior».
    final testigo = '${DateTime.now().microsecondsSinceEpoch}-${_azar()}';
    try {
      await _escribir(_nombreDeLaPrueba, testigo);
      final fichero = await _elFichero(_nombreDeLaPrueba);
      final vuelta = _descifrar(await fichero.readAsString());
      if (fichero.existsSync()) await fichero.delete();
      if (vuelta == testigo) return const SaludDelAlmacen.bien();
      return const SaludDelAlmacen.rota(
        'Este aparato acepta guardar la sesión pero después no la encuentra.',
      );
    } on Object catch (e) {
      Registro.aviso('la carpeta de datos no sirve para guardar: $e');
      return const SaludDelAlmacen.rota(
        'Este aparato no tiene dónde guardar la sesión.',
      );
    }
  }

  // ---------------------------------------------------------------- el disco

  Future<Directory> _laCarpeta() async {
    final ya = _carpeta;
    if (ya != null) return ya;
    final carpeta = _carpetaPuesta ?? await getApplicationSupportDirectory();
    if (!carpeta.existsSync()) await carpeta.create(recursive: true);
    _carpeta = carpeta;
    // El material se amasa AQUI, con la carpeta ya resuelta: entra en el la
    // ruta, y ninguna de las dos funciones de cifrado puede esperar por nada.
    _material ??= _materialPuesto ?? _amasarMaterial(carpeta);
    return carpeta;
  }

  Future<File> _elFichero(String nombre) async =>
      File('${(await _laCarpeta()).path}/$nombre');

  /// Escribe cifrado, **primero al lado y despues renombrando**.
  ///
  /// El renombrado es atomico en el mismo sistema de ficheros: si la maquina se
  /// va en mitad de la escritura, lo que queda es el fichero de antes entero, y
  /// no uno cortado por la mitad que se lee como «aqui no hay sesion».
  Future<void> _escribir(String nombre, String texto) async {
    final fichero = await _elFichero(nombre);
    final aMedias = File('${fichero.path}.nuevo');
    await aMedias.writeAsString(_cifrar(texto), flush: true);
    await _soloParaMi(aMedias);
    await aMedias.rename(fichero.path);
    await _soloParaMi(fichero);
  }

  /// Permisos 0600. Es lo unico que separa el par de tokens de otra cuenta de
  /// este mismo ordenador, asi que si no se puede poner **se dice**.
  ///
  /// Dart no sabe cambiar permisos, de ahi el `chmod` de fuera. Que falle no
  /// tumba nada: se avisa y se sigue, porque quedarse sin sesion por no poder
  /// afinar unos permisos seria peor que el problema que evita.
  Future<void> _soloParaMi(File fichero) async {
    try {
      final hecho = await Process.run('chmod', <String>['600', fichero.path]);
      if (hecho.exitCode != 0) {
        Registro.aviso(
          'no se pudieron poner los permisos 600 en ${fichero.path}: '
          '${hecho.stderr}',
        );
      }
    } on Object catch (e) {
      Registro.aviso('no se pudo llamar a chmod para ${fichero.path}: $e');
    }
  }

  // ----------------------------------------------------------------- la caja

  /// El sobre: sal, nonce, dato y sello, todo en base64 dentro de un JSON.
  ///
  /// La sal es por fichero, no por instalacion: asi el fichero de la sesion y
  /// el de la comprobacion no comparten clave ni keystream aunque salgan del
  /// mismo material.
  String _cifrar(String texto) {
    final sal = _azarBytes(16);
    final nonce = _azarBytes(16);
    final maestra = _maestra(sal);
    final claro = utf8.encode(texto);
    final cifrado = _xor(
      claro,
      _flujo(_derivar(maestra, 'flujo'), nonce, claro.length),
    );
    final sello = Hmac(
      sha256,
      _derivar(maestra, 'sello'),
    ).convert(<int>[...nonce, ...cifrado]).bytes;
    return jsonEncode(<String, Object?>{
      'v': 1,
      'sal': base64.encode(sal),
      'nonce': base64.encode(nonce),
      'dato': base64.encode(cifrado),
      'sello': base64.encode(sello),
    });
  }

  /// Devuelve el texto, o `null` si el sobre no cuadra **por lo que sea**: otra
  /// maquina, otro usuario, un byte cambiado, un JSON que no es.
  ///
  /// Nunca lanza y nunca distingue el motivo hacia fuera: quien llama solo
  /// tiene que hacer una cosa —tratarlo como «no hay sesion»— y el motivo va al
  /// registro.
  String? _descifrar(String sobre) {
    try {
      final json = jsonDecode(sobre) as Map<String, Object?>;
      if (json['v'] != 1) return null;
      final sal = base64.decode(json['sal']! as String);
      final nonce = base64.decode(json['nonce']! as String);
      final cifrado = base64.decode(json['dato']! as String);
      final sello = base64.decode(json['sello']! as String);
      final maestra = _maestra(sal);
      final esperado = Hmac(
        sha256,
        _derivar(maestra, 'sello'),
      ).convert(<int>[...nonce, ...cifrado]).bytes;
      // Comparacion sin atajos: salir en el primer byte distinto filtra, por lo
      // que tarda, cuanto se acerto. Aqui importa poco, pero escribir la
      // comparacion floja una vez es como acaba copiada donde si importa.
      if (!_igualesSinPrisa(sello, esperado)) return null;
      final claro = _xor(
        cifrado,
        _flujo(_derivar(maestra, 'flujo'), nonce, cifrado.length),
      );
      return utf8.decode(claro);
    } on Object {
      return null;
    }
  }

  /// La clave maestra de ESTE fichero: el material de la maquina amasado con la
  /// sal del propio fichero.
  ///
  /// La sal va de clave del HMAC y el material de dato, que es la forma de
  /// «extraer» de HKDF. No es un derivador lento a proposito: no tendria
  /// sentido, porque el material no es un secreto que se pueda adivinar a
  /// fuerza bruta — es publico para quien tenga esta cuenta. Ver la nota de
  /// seguridad de arriba.
  List<int> _maestra(List<int> sal) => Hmac(
    sha256,
    sal,
  ).convert(utf8.encode('${_material ?? ''}\n$_proposito')).bytes;

  /// Las dos claves, una para cifrar y otra para sellar. Nunca la misma: usar
  /// una clave para dos cosas es como se rompen los esquemas caseros.
  List<int> _derivar(List<int> maestra, String para) =>
      Hmac(sha256, maestra).convert(utf8.encode(para)).bytes;

  /// Keystream: HMAC-SHA256(clave, nonce ‖ numero de bloque), uno detras de
  /// otro.
  ///
  /// Es un cifrado de flujo construido sobre una primitiva que ya esta escrita
  /// y probada (`package:crypto`), en vez de un AES a mano, que es como se
  /// escriben los fallos que nadie ve. El nonce es distinto en cada escritura,
  /// asi que el keystream no se repite nunca con la misma clave.
  Uint8List _flujo(List<int> clave, List<int> nonce, int largo) {
    final hmac = Hmac(sha256, clave);
    final salida = Uint8List(largo);
    var puesto = 0;
    var bloque = 0;
    while (puesto < largo) {
      final trozo = hmac.convert(<int>[
        ...nonce,
        (bloque >> 24) & 0xff,
        (bloque >> 16) & 0xff,
        (bloque >> 8) & 0xff,
        bloque & 0xff,
      ]).bytes;
      final cuantos = min(trozo.length, largo - puesto);
      salida.setRange(puesto, puesto + cuantos, trozo);
      puesto += cuantos;
      bloque++;
    }
    return salida;
  }

  Uint8List _xor(List<int> a, List<int> b) {
    final salida = Uint8List(a.length);
    for (var i = 0; i < a.length; i++) {
      salida[i] = a[i] ^ b[i];
    }
    return salida;
  }

  bool _igualesSinPrisa(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diferencia = 0;
    for (var i = 0; i < a.length; i++) {
      diferencia |= a[i] ^ b[i];
    }
    return diferencia == 0;
  }

  // -------------------------------------------------------------- la maquina

  /// De donde sale el material que ata el fichero a esta maquina y a esta
  /// cuenta.
  ///
  /// `machine-id` lo pone el sistema al instalarse y no cambia; el usuario y la
  /// ruta de la carpeta anaden la cuenta. Ninguna de las tres es un secreto —
  /// `/etc/machine-id` lo lee cualquiera—, y por eso esto ata, no protege.
  ///
  /// Si no hay `machine-id` (un contenedor pelado, un sistema raro) se cae a un
  /// fichero de sal propio al lado del de la sesion. Eso es peor y se dice en
  /// el registro: **ahi la clave vive en la misma carpeta que el dato**, asi
  /// que una copia del directorio entero sirve en cualquier maquina.
  String _amasarMaterial(Directory carpeta) {
    final id = _idDeLaMaquina(carpeta);
    final usuario =
        Platform.environment['USER'] ?? Platform.environment['LOGNAME'] ?? '';
    return '$id\n$usuario\n${carpeta.path}';
  }

  String _idDeLaMaquina(Directory carpeta) {
    for (final ruta in const <String>[
      '/etc/machine-id',
      '/var/lib/dbus/machine-id',
    ]) {
      try {
        final fichero = File(ruta);
        if (fichero.existsSync()) {
          final texto = fichero.readAsStringSync().trim();
          if (texto.isNotEmpty) return texto;
        }
      } on Object {
        // El siguiente.
      }
    }
    return _salDeRespaldo(carpeta);
  }

  String _salDeRespaldo(Directory carpeta) {
    final fichero = File('${carpeta.path}/$_nombreDelRespaldo');
    try {
      if (fichero.existsSync()) return fichero.readAsStringSync().trim();
      final nueva = base64.encode(_azarBytes(32));
      if (!carpeta.existsSync()) carpeta.createSync(recursive: true);
      fichero.writeAsStringSync(nueva, flush: true);
      unawaited(_soloParaMi(fichero));
      Registro.aviso(
        'este sistema no tiene machine-id: la clave del fichero de la sesion '
        'queda en la misma carpeta que el fichero, asi que copiar la carpeta '
        'entera se lleva las dos cosas',
      );
      return nueva;
    } on Object catch (e) {
      Registro.aviso('no se pudo dejar la sal de la maquina: $e');
      return 'sin-maquina';
    }
  }

  static final _dados = Random.secure();

  static Uint8List _azarBytes(int cuantos) {
    final salida = Uint8List(cuantos);
    for (var i = 0; i < cuantos; i++) {
      salida[i] = _dados.nextInt(256);
    }
    return salida;
  }

  static String _azar() => base64Url.encode(_azarBytes(9));
}
