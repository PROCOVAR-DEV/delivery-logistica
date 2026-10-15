import 'dart:convert';

/// El par de tokens y lo que el token de acceso lleva dentro.
///
/// `sub`, `sucursalId` y `roles` se copian del token porque es lo que la API ya
/// lee, y porque sin red hay que poder saber quien es y que sucursal le toca sin
/// preguntarle a nadie.
///
/// `nombre`, `correo` y `rol` se copian por lo mismo, pero para ENSENARLOS: el
/// menu de la cuenta dice quien eres, y preguntarselo a `/api/me` cada vez que
/// alguien pulsa el avatar es una peticion para pintar dos renglones que el
/// token ya trae firmados. Auth los manda como `name`, `email` y `role`.
class Sesion {
  const Sesion({
    required this.token,
    required this.refresh,
    required this.sub,
    this.sucursalId,
    this.roles = const <String>[],
    this.nombre = '',
    this.correo = '',
    this.rol = '',
    this.pedidoA,
  });

  /// [pedidoA] se pasa SOLO con un par recién llegado del servidor (`/token`,
  /// `/refresh`): la hora del aparato justo ANTES de pedirlo. Lo guardado lo trae
  /// dentro.
  factory Sesion.deJson(Map<String, Object?> json, {DateTime? pedidoA}) {
    final token = json['token'] as String?;
    // Auth contesta `refresh_token` en las tres puertas (`/api/auth/token`,
    // `/refresh` y `/logout`). `refresh` se sigue admitiendo porque es como se
    // guarda el par en el aparato, y lo guardado tiene que poder volver a
    // leerse.
    final refresh = (json['refresh_token'] ?? json['refresh']) as String?;
    if (token == null || refresh == null) {
      throw const FormatException('la respuesta no trae el par de tokens');
    }
    final carga = _cargaDelToken(token);
    return Sesion(
      token: token,
      refresh: refresh,
      sub: (json['sub'] ?? carga['sub'] ?? '') as String,
      // El token trae el CODIGO de la sucursal (CAM, HAB, STG...) con dos
      // nombres, `sucursal` y `branch_id`, que es lo que firma auth
      // (`apk-tokens.ts`) y lo que lee la API del reparto. Vacio significa
      // «ninguna», que en un Super Admin son las ocho.
      sucursalId: _sucursal(
        json['sucursalId'] ??
            carga['sucursalId'] ??
            carga['sucursal'] ??
            carga['branch_id'],
      ),
      roles: _roles(json['roles'] ?? carga['roles']),
      // Los tres de ensenar. Vacio es una respuesta valida, no un fallo: una
      // sesion GUARDADA ANTES de que esto existiera no los tiene, y un token de
      // otra puerta podria no traerlos. Quien los pinta decide que poner en su
      // lugar; lo que no puede pasar es que falten y la aplicacion no arranque.
      nombre: _texto(json['nombre'] ?? carga['name']),
      correo: _texto(json['correo'] ?? carga['email']),
      rol: _texto(json['rol'] ?? carga['role']),
      pedidoA: pedidoA ?? DateTime.tryParse(_texto(json['pedidoA'])),
    );
  }

  /// LA SESION DE LA WEB: la que llega en la cookie del login unico.
  ///
  /// **No hay par.** En la web la sesion es la cookie `httpOnly` que dejo
  /// Accesos, y quien la renueva es Accesos por su cuenta: aqui no hay refresh
  /// que guardar ni que gastar. Lo que se arma es la ficha para PINTAR —quien
  /// eres, tu sucursal, tu rol— y para saber de quien es la copia de la base.
  ///
  /// [token] es el de la propia cookie, que `GET /api/me` devuelve en el cuerpo
  /// exactamente para esto (`api/internal/api/yo.go`): el JavaScript de la
  /// pagina no puede leer la cookie, asi que sin esta vuelta no habria forma de
  /// saber ni quien entro.
  ///
  /// [usuario] es el `user` de esa misma respuesta. Manda sobre lo que diga la
  /// carga del token en los campos que trae, porque es lo que el servidor acaba
  /// de decidir; lo que no traiga sale del token, que viene firmado.
  factory Sesion.deLaCookie({
    required String token,
    Map<String, Object?> usuario = const <String, Object?>{},
  }) => Sesion.deJson(<String, Object?>{
    'token': token,
    // Vacio y no un valor falso: [llevaPar] es lo que distingue esta sesion de
    // la de la APK, y lo que evita que nadie intente renovar lo que no existe.
    'refresh': '',
    'sub': usuario['id'] is String ? usuario['id'] : null,
    'nombre': usuario['name'],
    'correo': usuario['email'],
    'rol': usuario['role'],
    'sucursalId': usuario['branchId'],
  });

  final String token;

  /// El refresh, **de un solo uso**. Se sustituye ENTERO en cada renovacion y el
  /// viejo no se guarda nunca: el servidor lee un refresh repetido como robo y
  /// revoca todas las sesiones de la cuenta.
  final String refresh;

  final String sub;
  final String? sucursalId;

  /// Escritos exactamente asi: `SUPER ADMIN`, `ADMINISTRADOR`, `SUPERVISOR`,
  /// `GESTOR`, `OPERADOR`. PEDIDO los compara como texto.
  final List<String> roles;

  /// El nombre de la persona (`name` del token). Puede venir vacio.
  final String nombre;

  /// El correo (`email` del token). Puede venir vacio.
  final String correo;

  /// El rol en singular que manda auth (`role`), que NO es lo mismo que [roles]:
  /// aquel es la lista con la que se decide que se puede hacer, este es la
  /// palabra que se pinta debajo del nombre.
  final String rol;

  /// CUÁNDO SE PIDIÓ ESTE PAR, con el reloj del APARATO. `null` = no se sabe
  /// (un par guardado antes de que esto existiera, o la cookie de la web).
  ///
  /// Es la hora de ANTES de la petición, no la de la respuesta: Accesos lo firmó
  /// después, así que el token es, como mucho, así de viejo. Ver [leQueda].
  final DateTime? pedidoA;

  /// CUÁNTO LE QUEDA AL TOKEN DE ACCESO, o `null` si no se puede saber — 15/10/2026.
  ///
  /// No se compara su `exp` con la hora del aparato: ese reloj puede ir desfasado
  /// minutos u horas. Se cuenta lo que dura según quien lo firmó (`exp − iat`, los
  /// dos del servidor) desde [pedidoA], y el aparato sólo mide cuánto pasó desde
  /// entonces con SU reloj: el desfase se anula. Un reloj que va hacia atrás
  /// (`ahora` antes de [pedidoA]) da `null`; uno que salta hacia delante sólo
  /// adelanta una renovación. Y si aun así se equivoca, el 401 renueva y reintenta.
  Duration? leQueda(DateTime ahora) {
    final desde = pedidoA;
    final carga = _cargaDelToken(token);
    final iat = carga['iat'];
    final exp = carga['exp'];
    if (desde == null || iat is! num || exp is! num || ahora.isBefore(desde)) {
      return null;
    }
    return Duration(seconds: (exp - iat).toInt()) - ahora.difference(desde);
  }

  bool get esSuperAdmin => tieneAlguno(const ['SUPER ADMIN']);

  /// Si lleva alguno de esos roles, **mirando los DOS sitios**: el [rol] en
  /// singular que manda auth y la lista [roles].
  ///
  /// Son dos porque auth los manda por separado: `role` sale del rol por defecto
  /// de la cuenta y `roles` de sus membresias. Una cuenta puede traer el suyo en
  /// uno y no en el otro, y mirar solo la lista deja fuera a quien lo tenga en el
  /// singular — sin error, simplemente no ve lo que le toca. Es la misma cuenta
  /// que hace `auth.Usuario.tieneAlguno` en la api, y a proposito: **si los dos
  /// lados no miran lo mismo, la pantalla se esconde y el servidor la abre, o al
  /// contrario.**
  ///
  /// NO DECIDE PERMISOS, y eso no es un detalle: el rol viaja en el token y
  /// cualquiera con un editor de texto puede escribir el que quiera. Sirve para
  /// **no estorbar** —esconder del menu lo que a alguien no le toca— y el cerrojo
  /// de verdad lo pone el servidor con un 403.
  bool tieneAlguno(List<String> cuales) {
    for (final c in cuales) {
      if (rol == c || roles.contains(c)) return true;
    }
    return false;
  }

  /// `true` cuando la sesion la lleva el APARATO: un par de tokens guardado.
  ///
  /// `false` en la web, donde la lleva la cookie del login unico. Es la
  /// pregunta que hay que hacerse antes de renovar, antes de guardar y antes de
  /// revocar: sin par no hay nada de eso que hacer, y hacerlo igual es mandarle
  /// a auth un refresh vacio y quedarse fuera.
  bool get llevaPar => refresh.isNotEmpty;

  /// El nombre para PINTAR. Nunca vacio y nunca el `sub`.
  ///
  /// El `sub` es el identificador de la fila en la base de auth
  /// (`uaoOUHqTXNYUv672kjdLoZLpFrseCz9e`). A quien lo lee no le dice nada, y
  /// ensenarselo al logistico es sacar la base a la cara. Sin nombre se pone
  /// «Tu cuenta», que al menos es verdad.
  String get nombreParaVer => nombre.isNotEmpty ? nombre : 'Tu cuenta';

  /// La letra del cuadro del avatar. La del nombre, o `?` si no hay nombre —
  /// **nunca** la del `sub`, que seria una letra de un identificador.
  String get inicial =>
      nombre.isEmpty ? '?' : nombre.substring(0, 1).toUpperCase();

  /// El rotulo de debajo del nombre: el `role` de auth, o el primero de [roles]
  /// si aquel no vino. Vacio si no hay ninguno, y entonces no se pinta.
  String get rolParaVer =>
      rol.isNotEmpty ? rol : (roles.isNotEmpty ? roles.first : '');

  Map<String, Object?> aJson() => <String, Object?>{
    'token': token,
    'refresh': refresh,
    'sub': sub,
    'sucursalId': sucursalId,
    'roles': roles,
    'nombre': nombre,
    'correo': correo,
    'rol': rol,
    'pedidoA': pedidoA?.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'Sesion(sub: $sub, sucursal: $sucursalId)';

  /// Lee la carga del JWT SIN comprobar la firma.
  ///
  /// Y esta bien que no la compruebe: quien valida el token es el servidor en
  /// cada peticion. Aqui sólo se lee para saber que sucursal pintar en la barra.
  /// Confiar en esto para decidir permisos seria darle a cualquiera con un
  /// editor de texto el rol que quiera.
  static Map<String, Object?> _cargaDelToken(String token) {
    try {
      final partes = token.split('.');
      if (partes.length != 3) return const <String, Object?>{};
      final normalizado = base64Url.normalize(partes[1]);
      final json = jsonDecode(utf8.decode(base64Url.decode(normalizado)));
      return json is Map<String, Object?> ? json : const <String, Object?>{};
    } on Object {
      // Un token ilegible no puede tumbar el arranque: se entra sin los extras
      // y el servidor dira lo que tenga que decir en la primera peticion.
      return const <String, Object?>{};
    }
  }

  /// La sucursal, o `null` si viene vacia. La cadena vacia que firma auth
  /// cuando alguien no tiene ninguna NO puede quedarse como sucursal: seria una
  /// cabecera `x-sucursal-id: ` en cada peticion.
  static String? _sucursal(Object? crudo) {
    final texto = crudo is String ? crudo.trim() : null;
    return (texto == null || texto.isEmpty) ? null : texto;
  }

  /// Un texto del token, o vacio. Lo que no sea texto se trata como ausente: un
  /// `name` que viniera como numero no puede reventar el arranque.
  static String _texto(Object? crudo) => crudo is String ? crudo.trim() : '';

  static List<String> _roles(Object? crudo) => switch (crudo) {
    final List<Object?> lista => lista.whereType<String>().toList(),
    final String uno => <String>[uno],
    _ => const <String>[],
  };
}
