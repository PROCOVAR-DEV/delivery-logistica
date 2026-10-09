import 'dart:convert';

import 'sesion.dart';

export 'almacen_sesion_stub.dart'
    if (dart.library.io) 'almacen_sesion_nativo.dart'
    if (dart.library.js_interop) 'almacen_sesion_web.dart';

/// Si el sitio donde se guarda la sesion SIRVE de verdad en este aparato.
///
/// ## Por que esto existe
///
/// La pantalla de acceso promete «Para entrar hace falta conexion. Una vez
/// dentro, no: puedes seguir trabajando el dia entero sin senal». Esa promesa
/// solo es verdad si el par de tokens se puede **guardar y volver a leer**. El
/// 15/09/2026 se probo la aplicacion de escritorio compilada: se entro con una
/// cuenta de verdad, se cerro y se volvio a abrir, y pidio la contrasena otra
/// vez. El par estaba escrito en el llavero del sistema —se leyo el fichero— y
/// aun asi `leer()` devolvia `null`.
///
/// Lo peor no fue que fallara: fue que **no lo dijo**. La aplicacion aterrizaba
/// en un formulario mudo, igual que si nadie hubiera entrado nunca. Si eso pasa
/// en el patio de un almacen sin senal, el logistico no puede entrar con sus
/// datos ahi mismo, en el disco, y no hay a quien preguntar.
///
/// Por eso el almacen tiene que poder contestar a «¿sirves?» **antes** de que
/// alguien escriba su contrasena, y la pantalla de acceso lo dice: o se cumple
/// la promesa, o no se promete.
class SaludDelAlmacen {
  const SaludDelAlmacen.bien() : motivo = null;

  const SaludDelAlmacen.rota(String this.motivo);

  /// Que le pasa, en cristiano y para pintarlo. `null` cuando no le pasa nada.
  final String? motivo;

  /// `true` cuando lo que se guarda se puede volver a leer.
  bool get guarda => motivo == null;

  @override
  String toString() => guarda ? 'SaludDelAlmacen.bien()' : 'rota($motivo)';
}

/// Donde vive el par de tokens.
///
/// Son dos mundos distintos a proposito (`identidad.md`):
///
///  * **APK** → el almacen seguro del sistema (Keystore). La APK no lleva
///    ninguna clave dentro: manda usuario y contrasena por HTTPS y recibe el
///    par. Una APK se descompila.
///  * **Web** → el almacen del navegador. Ver `almacen_sesion_web.dart`.
///
/// ## Ninguno de los tres metodos puede LANZAR
///
/// Y es una regla, no una casualidad. Quien llama a `leer()` es el arranque, y
/// una excepcion ahi sube hasta el portero, que la traduce a «no hay sesion» y
/// manda a la persona a un formulario que no explica nada. El almacen que no
/// puede leer lo dice devolviendo `null` **y dejandolo en el registro**; el que
/// no puede ni guardar lo dice en [comprobar].
abstract interface class AlmacenDeSesion {
  /// La sesion guardada, o `null` si no hay ninguna **o no se pudo leer**. No
  /// lanza nunca.
  Future<Sesion?> leer();

  /// Guarda el par. Devuelve `true` si ademas **se pudo volver a leer**.
  ///
  /// El valor de vuelta no es un adorno: en Linux el almacen del sistema acepta
  /// la escritura y despues no encuentra nada, asi que «guardar salio bien» y
  /// «la sesion esta guardada» son dos cosas distintas y hay que medir la
  /// segunda.
  Future<bool> guardar(Sesion sesion);

  Future<void> borrar();

  /// Los refrescos de sesiones cerradas SIN conexion que Accesos aun no sabe que
  /// estan cerradas. Ver [RefrescoPorRevocar]. No lanza nunca.
  Future<List<RefrescoPorRevocar>> porRevocar();

  /// Anota uno ANTES de borrar la sesion. `true` si quedo (y se puede releer).
  Future<bool> dejarPorRevocar(RefrescoPorRevocar pendiente);

  /// Lo quita, y solo debe llamarse cuando el servidor CONFIRMO la revocacion.
  Future<void> quitarPorRevocar(String refresh);

  /// ¿Este aparato puede guardar una sesion y volver a leerla?
  ///
  /// Se pregunta en la pantalla de acceso, ANTES de pedir la contrasena. Hace
  /// una ida y vuelta de verdad con una clave propia y la limpia detras: mirar
  /// si el plugin esta montado no vale, porque el caso que se vio es
  /// exactamente uno en el que el plugin esta montado y contesta que si a todo.
  Future<SaludDelAlmacen> comprobar();
}

/// EL REFRESCO DE UN CIERRE DE SESION QUE NO LLEGO A ACCESOS — 08/10/2026.
///
/// Salir sin conexion no podia avisar a Accesos (`POST /logout`) y el refresco
/// quedaba vivo hasta 30 dias sin que nadie lo reintentara. Se guarda aqui,
/// aparte y por persona, y se revoca en cuanto hay red (`RevocadorDeCierres`).
///
/// **NO ES UNA SESION y no sirve para entrar.** `leer()` no lo mira nunca, el
/// arranque tampoco, y nada lo pone en una cabecera: su unico uso es
/// presentarselo a `/logout`. Se borra SOLO cuando el servidor confirma.
class RefrescoPorRevocar {
  const RefrescoPorRevocar({required this.sub, required this.refresh});

  factory RefrescoPorRevocar.deJson(Map<String, Object?> j) =>
      RefrescoPorRevocar(
        sub: j['sub'] as String? ?? '',
        refresh: j['refresh'] as String? ?? '',
      );

  /// De quien es (el `sub` de la sesion que se cerro).
  final String sub;
  final String refresh;

  Map<String, Object?> aJson() => <String, Object?>{
    'sub': sub,
    'refresh': refresh,
  };
}

/// Lo de [RefrescoPorRevocar] sobre dos primitivas de texto, para que cada
/// almacen (llavero, fichero cifrado, memoria) solo diga DONDE lo escribe.
mixin PorRevocarEnTexto {
  /// El texto guardado, o `null`. No lanza.
  Future<String?> leerPorRevocar();

  /// Escribe `texto` (o borra si es `null`) y dice si se pudo.
  Future<bool> escribirPorRevocar(String? texto);

  Future<List<RefrescoPorRevocar>> porRevocar() async {
    try {
      final crudo = await leerPorRevocar();
      if (crudo == null || crudo.isEmpty) return const [];
      return [
        for (final e in jsonDecode(crudo) as List<Object?>)
          RefrescoPorRevocar.deJson(e! as Map<String, Object?>),
      ].where((r) => r.refresh.isNotEmpty).toList();
    } on Object {
      // Ilegible: no hay nada que revocar que se pueda leer. No se inventa.
      return const [];
    }
  }

  Future<bool> dejarPorRevocar(RefrescoPorRevocar pendiente) async {
    final ya = await porRevocar();
    final todos = [
      ...ya.where((r) => r.refresh != pendiente.refresh),
      pendiente,
    ];
    final texto = jsonEncode([for (final r in todos) r.aJson()]);
    if (!await escribirPorRevocar(texto)) return false;
    return await leerPorRevocar() == texto;
  }

  Future<void> quitarPorRevocar(String refresh) async {
    final quedan = (await porRevocar())
        .where((r) => r.refresh != refresh)
        .toList();
    await escribirPorRevocar(
      quedan.isEmpty ? null : jsonEncode([for (final r in quedan) r.aJson()]),
    );
  }
}

/// EL ALMACEN DE LA WEB: la sesion la lleva la cookie del login unico.
///
/// Vive AQUI y no en `almacen_sesion_web.dart` a proposito: aquel importa
/// `package:web` y por tanto no se puede ni cargar en una prueba, que corre en
/// la maquina virtual de Dart. La regla de las dos reglas de abajo —que una
/// sesion de cookie no se escriba, y que salir borre— es justo la que hay que
/// poder romper para ver si alguna prueba la caza. El sitio donde se guarda de
/// verdad se le pasa por fuera.
///
/// Con el, `leer()` devolviendo `null` NO es «no hay sesion»: es «la sesion no
/// la llevo yo», y quien decide es el servidor al contestar. El resto de la
/// aplicacion ya cuenta con eso y no hay que tocarlo — `InterceptorSesion` sale
/// sin cabecera y con la cookie puesta, el [Renovador] no intenta renovar lo que
/// no existe y la subida deja pasar la guarda del dueno porque en un navegador
/// no hay dos personas compartiendo una base.
///
/// ## Y detras lleva el del navegador, a proposito
///
/// Si el login unico falla, la pantalla de acceso deja entrar con usuario y
/// contrasena. Ese par SI hay que guardarlo: sin el, `InterceptorSesion` no
/// tendria token que poner y cada recarga devolveria a la puerta. Asi que:
///
///  * **sesion de cookie** (`llevaPar == false`) → no se escribe nada. Escribirla
///    seria dejar el token en `localStorage` **despues de cerrar sesion**: el
///    servidor borra su cookie, el almacen sigue devolviendo el token viejo y la
///    persona sigue dentro creyendo que salio.
///  * **par de la puerta de respaldo** → se guarda como siempre.
///
/// `borrar()` limpia el respaldo en los dos casos. La cookie no la borra nadie
/// desde aqui: eso lo hace `GET /api/auth/logout/done` en el servidor, que es el
/// unico que puede.
class AlmacenPorCookie implements AlmacenDeSesion {
  const AlmacenPorCookie(this._respaldo);

  final AlmacenDeSesion _respaldo;

  @override
  Future<Sesion?> leer() => _respaldo.leer();

  @override
  Future<bool> guardar(Sesion sesion) async =>
      sesion.llevaPar ? _respaldo.guardar(sesion) : true;

  @override
  Future<void> borrar() => _respaldo.borrar();

  @override
  Future<List<RefrescoPorRevocar>> porRevocar() => _respaldo.porRevocar();

  @override
  Future<bool> dejarPorRevocar(RefrescoPorRevocar pendiente) =>
      _respaldo.dejarPorRevocar(pendiente);

  @override
  Future<void> quitarPorRevocar(String refresh) =>
      _respaldo.quitarPorRevocar(refresh);

  /// Lo que hay que comprobar es el respaldo: es lo unico que escribe. La cookie
  /// la lleva el navegador y no hay nada que preguntarle.
  @override
  Future<SaludDelAlmacen> comprobar() => _respaldo.comprobar();
}

/// En memoria. Para los tests y para el destino que no tenga donde guardar.
class AlmacenEnMemoria with PorRevocarEnTexto implements AlmacenDeSesion {
  AlmacenEnMemoria([this._sesion, this.salud = const SaludDelAlmacen.bien()]);

  /// Un almacen que ACEPTA la escritura y luego no encuentra nada, que es el
  /// modo de fallo de verdad que se vio en Linux el 15/09/2026. Escrito aqui
  /// para que se pueda probar sin un llavero delante.
  factory AlmacenEnMemoria.queNoGuarda([String motivo]) = _AlmacenQueNoGuarda;

  Sesion? _sesion;

  /// Lo que contesta [comprobar]. Se puede mover en una prueba.
  SaludDelAlmacen salud;

  @override
  Future<Sesion?> leer() async => _sesion;

  @override
  Future<bool> guardar(Sesion sesion) async {
    _sesion = sesion;
    return true;
  }

  @override
  Future<void> borrar() async => _sesion = null;

  String? _porRevocar;

  @override
  Future<String?> leerPorRevocar() async => _porRevocar;

  @override
  Future<bool> escribirPorRevocar(String? texto) async {
    _porRevocar = texto;
    return true;
  }

  @override
  Future<SaludDelAlmacen> comprobar() async => salud;
}

class _AlmacenQueNoGuarda extends AlmacenEnMemoria {
  _AlmacenQueNoGuarda([String motivo = 'el almacen no guarda'])
    : super(null, SaludDelAlmacen.rota(motivo));

  @override
  Future<bool> guardar(Sesion sesion) async => false;

  @override
  Future<Sesion?> leer() async => null;
}
