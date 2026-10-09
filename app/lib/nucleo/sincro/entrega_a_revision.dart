import 'package:dio/dio.dart';

import '../base/base.dart';
import '../cola/apunte.dart';
import '../cola/cola_salida.dart';
import '../identidad/almacen_sesion.dart';
import '../red/entorno.dart';
import '../red/fallos.dart';
import '../red/interceptor_fallos.dart';
import '../registro/registro.dart';
import 'identidad_del_aparato.dart';
import 'subida.dart' show marcaDeAparatoNoRegistrado;

/// El ambito que Accesos pone en el token de entrega (`POST /api/auth/entrega`).
const ambitoDeEntrega = 'reparto.entrega';

/// Los literales que lee la persona (`docs/bandeja-de-revision.md`, B.5). Aqui y
/// no en la pantalla: la pantalla los pinta, esto es lo que SE DICE.
abstract final class TextosDeEntrega {
  static const aparatoSinAlta =
      'Este aparato no estaba registrado. Pide a un administrador que te '
      'devuelva el acceso.';
  static const yaTienePermiso =
      'Ya tienes permiso: cierra sesión y entra de nuevo.';
  static const sesionTerminada =
      'Tu sesión terminó. No se puede entregar. Tus cambios siguen en este '
      'aparato.';
  static const sinConexion =
      'Sin conexión con el servidor. Tus cambios siguen en este aparato: '
      'vuelve a intentarlo.';
  static const colaDeOtraPersona =
      'Estos cambios son de otra persona. Entra con su cuenta para entregarlos.';
  static const sinSucursal =
      'Tu cuenta no tiene una sucursal asignada. Pide a un administrador que '
      'te la asigne; tus cambios siguen en este aparato.';
  static const demasiadosIntentos =
      'Has pedido demasiadas entregas seguidas. Espera un momento y vuelve a '
      'pulsar; tus cambios siguen en este aparato.';
  static const noAceptoElToken =
      'El servidor no aceptó la entrega. Inténtalo más tarde; tus cambios '
      'siguen en este aparato.';
}

/// Que paso con la respuesta de UN apunte.
enum _Anotado { entregado, entregadoYDecidido, yaResuelto, sinRespuesta }

/// Como termino una entrega.
enum ResultadoDeEntrega {
  /// Todo lo que estaba `pendiente` esta ya en la bandeja del revisor.
  entregado,

  /// Se entrego una parte; el resto sigue `pendiente` y se puede reintentar.
  parcial,

  /// No habia nada `pendiente`: no se pidio ni un token.
  nadaQueEntregar,

  /// Es la web: no tiene cola ni entrega (CLAUDE.md §1). No se hizo nada.
  noAplica,

  sinConexion,
  sesionTerminada,
  yaTienePermiso,
  aparatoSinAlta,
  colaDeOtraPersona,

  /// El servidor dijo que no, con su literal en [ResumenDeEntrega.error].
  rechazado,
}

/// Lo que se le cuenta a la pantalla: cuantos entregados, cuantos sin entregar y
/// el literal de lo que fallo. **Nada de esto borra ni reescribe un apunte.**
class ResumenDeEntrega {
  const ResumenDeEntrega(
    this.resultado, {
    this.entregados = 0,
    this.sinEntregar = 0,
    this.error,
    this.errores = const <String>[],
    this.yaResueltos = 0,
    this.esperar,
  });

  final ResultadoDeEntrega resultado;

  /// Apuntes que pasaron a `enRevision` en ESTA pulsacion.
  final int entregados;

  /// Apuntes que siguen `pendiente`, intactos.
  final int sinEntregar;

  /// El literal que se enseña, ya escrito. `null` si salio todo.
  final String? error;

  /// Los rechazos por apunte (`huella_distinta`, `entrega_no_admitida`…), con su
  /// literal, cuando la entrega siguio con los demas.
  final List<String> errores;

  /// Apuntes que el servidor YA tenia resueltos por la subida normal (la
  /// respuesta de entonces se perdio): ya no estan `pendiente` y no son entregas.
  final int yaResueltos;

  /// Cuanto pide esperar el servidor (`Retry-After` de un 429), si lo dijo.
  final Duration? esperar;

  @override
  String toString() =>
      'ResumenDeEntrega($resultado, entregados: $entregados, '
      'sinEntregar: $sinEntregar, error: $error)';
}

/// Un 429 con el `Retry-After` que mando el servidor. Sigue siendo un [Rechazo]:
/// no se reintenta solo; lo unico que anade es cuanto pide esperar.
class RechazoConEspera extends Rechazo {
  RechazoConEspera(Rechazo r, this.segundos)
    : super(r.codigo, r.mensaje, marca: r.marca, cuerpo: r.cuerpo);

  final int segundos;
}

/// ENTREGAR A REVISION lo que la persona hizo sin poder subirlo, y preguntar
/// despues que paso con ello. `docs/bandeja-de-revision.md`, B.1/B.2/B.5.
///
/// ## Que es y que NO es
///
/// Quien pierde `delivery.entrar` conserva su cola pero no tiene token con el que
/// subirla. Accesos le da, a quien sigue con la sesion viva, un token de **10
/// minutos y un solo ambito** (`POST /api/auth/entrega`), y con el este servicio
/// deja cada apunte en la bandeja de `sync/`, **tal cual, sin aplicarlo**. Lo
/// aplica o lo descarta otra persona.
///
/// Por eso va aparte de [Subida] y no como un modo suyo:
///
///  * **Su propio `Dio` y SIN `InterceptorSesion`.** Aquel renueva ante un 401 y
///    pide el token normal: justo lo que NO hay que hacer (la persona no tiene
///    permiso, `/refresh` le contesta 403, y renovar presenta —y gasta— el
///    refresh). El token de entrega NO gasta el refresh; este servicio tampoco.
///  * **Solo el token de entrega.** Un token normal no abre la puerta, y mandarlo
///    por aqui seria presentar a la persona con una autoridad que ya no tiene.
///  * **Nunca da de alta el aparato.** No hay token para eso. Un aparato sin alta
///    (o un 404 `aparato_no_registrado`) se dice y se para.
///
/// ## Lo que no puede pasar
///
///  * **Marcar antes de la respuesta.** `enRevision` se escribe con la respuesta
///    del servidor en la mano. Marcar al mandar deja un apunte que ni sube ni esta
///    arriba si la respuesta no llega.
///  * **Borrar ni reescribir nada.** Entregar cambia un estado; el cuerpo, la ruta
///    y la clave son los de siempre, o la huella del servidor no cuadraria.
///  * **Entregar lo que no es `pendiente`.** Un rechazado espera a una persona; un
///    descartado ya lo decidio una.
///  * **Insistir.** Un fallo de red lo deja todo `pendiente`, intacto, para que la
///    persona vuelva a pulsar. El token se renueva UNA vez por entrega.
class EntregaARevision {
  EntregaARevision({
    required Dio auth,
    required Dio sync,
    required ColaDeSalida cola,
    required BaseLocal base,
    required IdentidadDelAparato aparato,
    required AlmacenDeSesion almacen,
    required bool Function() trabajaSinConexion,
  }) : _auth = auth,
       _sync = sync,
       _cola = cola,
       _base = base,
       _aparato = aparato,
       _almacen = almacen,
       _trabajaSinConexion = trabajaSinConexion;

  /// El `Dio` de `sync` para la entrega: crudo, sin sesion. La URL es la de
  /// siempre, `Entorno.syncUrl`.
  static Dio dioDeSync({String? baseUrl, List<Interceptor> interceptores = const []}) =>
      Dio(
          BaseOptions(
            baseUrl: baseUrl ?? Entorno.syncUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            contentType: Headers.jsonContentType,
          ),
        )
        ..interceptors.addAll(interceptores);

  final Dio _auth;
  final Dio _sync;
  final ColaDeSalida _cola;
  final BaseLocal _base;
  final IdentidadDelAparato _aparato;
  final AlmacenDeSesion _almacen;
  final bool Function() _trabajaSinConexion;

  /// Dos pulsaciones a la vez serian dos tokens y dos pasadas por la misma cola.
  Future<ResumenDeEntrega>? _enVuelo;

  Future<ResumenDeEntrega> entregar() =>
      _enVuelo ??= _entregar().whenComplete(() => _enVuelo = null);

  Future<ResumenDeEntrega> _entregar() async {
    // LA WEB NO ENTREGA NADA: no tiene cola ni base local (CLAUDE.md §1).
    if (!_trabajaSinConexion()) {
      return const ResumenDeEntrega(ResultadoDeEntrega.noAplica);
    }

    final lote = await _cola.lote(maximo: 500);
    if (lote.isEmpty) {
      return const ResumenDeEntrega(ResultadoDeEntrega.nadaQueEntregar);
    }

    final sesion = await _almacen.leer();
    if (sesion == null || !sesion.llevaPar) {
      return ResumenDeEntrega(
        ResultadoDeEntrega.sesionTerminada,
        sinEntregar: lote.length,
        error: TextosDeEntrega.sesionTerminada,
      );
    }

    // La cola de A no sale con la sesion de B: la misma cerradura de `Subida`.
    final dueno = await _base.duenoGuardado();
    if (dueno != null && dueno != sesion.sub) {
      return ResumenDeEntrega(
        ResultadoDeEntrega.colaDeOtraPersona,
        sinEntregar: lote.length,
        error: TextosDeEntrega.colaDeOtraPersona,
      );
    }

    // SOLO LEER: darlo de alta exige un token normal que esta persona no tiene.
    final aparato = await _aparato.leer();
    if (aparato == null) {
      return ResumenDeEntrega(
        ResultadoDeEntrega.aparatoSinAlta,
        sinEntregar: lote.length,
        error: TextosDeEntrega.aparatoSinAlta,
      );
    }

    String token;
    try {
      token = await _pedirToken();
    } on Object catch (e) {
      return _cierre(e, entregados: 0, sinEntregar: lote.length);
    }

    var entregados = 0;
    var yaResueltos = 0;
    // Una clave que el servidor ya tenia DECIDIDA: sus datos (quien, cuando, el id
    // creado) no vienen en la respuesta de la entrega, vienen en `mias`.
    var hayQueConsultar = false;
    var yaRenovoElToken = false;
    final errores = <String>[];
    // Las rutas cuya hoja de resultados NO llego: su `completed` tampoco sale. Es
    // la misma regla que `Subida._cierreSinAceptar`; completar la ruta la congela.
    final sinHoja = <String>{};
    Object? parada;

    for (final previo in lote) {
      final apunte = await _cola.porClave(previo.clave);
      // Nada de entregar lo que ya no es `pendiente`: se resolvio mientras tanto.
      if (apunte == null || apunte.estado != EstadoApunte.pendiente) continue;

      final ruta = _rutaDeCierre(apunte);
      if (ruta != null && sinHoja.contains(ruta)) continue;
      final hoja = _hojaDe(apunte);

      try {
        Map<String, Object?> respuesta;
        try {
          respuesta = await _mandar(token, aparato, apunte);
        } on SesionMuerta {
          // El token de entrega dura 10 minutos: una entrega larga lo ve caducar.
          // Se pide OTRO, UNA sola vez en toda la entrega; un segundo 401 con un
          // token recien firmado no se arregla pidiendo mas.
          if (yaRenovoElToken) rethrow;
          yaRenovoElToken = true;
          token = await _pedirToken();
          respuesta = await _mandar(token, aparato, apunte);
        }
        switch (await _anotar(apunte, respuesta)) {
          case _Anotado.entregado:
            entregados++;
          case _Anotado.entregadoYDecidido:
            entregados++;
            hayQueConsultar = true;
          case _Anotado.yaResuelto:
            yaResueltos++;
          case _Anotado.sinRespuesta:
            if (hoja != null) sinHoja.add(hoja);
        }
      } on Rechazo catch (e) {
        if (hoja != null) sinHoja.add(hoja);
        // Un apunte que el servidor no admite NO para a los demas (y un 409 de
        // Accesos —`tiene_permiso`— NO es esto: ese es de la persona)...
        if ((e.codigo == 409 && e.marca == 'huella_distinta') || e.codigo == 422) {
          errores.add(e.mensaje);
          continue;
        }
        // ...pero lo demas (cupo, aparato sin alta, token no valido) es de todos.
        parada = e;
        break;
      } on Object catch (e) {
        parada = e;
        break;
      }
    }

    if (hayQueConsultar) {
      try {
        await _aplicarMias(await _pedirMias(token, aparato));
      } on Object catch (e) {
        // Es una ayuda: lo entregado ya esta anotado y el proximo «Actualizar
        // estados» lo resolvera.
        Registro.aviso('entrega: no se pudo consultar lo ya decidido: $e');
      }
    }

    final sinEntregar = await _base.cuantosPendientes();
    if (parada != null) {
      return _cierre(
        parada,
        entregados: entregados,
        sinEntregar: sinEntregar,
        yaResueltos: yaResueltos,
      );
    }
    if (sinEntregar == 0 && errores.isEmpty) {
      return ResumenDeEntrega(
        ResultadoDeEntrega.entregado,
        entregados: entregados,
        yaResueltos: yaResueltos,
      );
    }
    return ResumenDeEntrega(
      entregados == 0 ? ResultadoDeEntrega.rechazado : ResultadoDeEntrega.parcial,
      entregados: entregados,
      sinEntregar: sinEntregar,
      error: errores.isEmpty ? null : errores.first,
      errores: errores,
      yaResueltos: yaResueltos,
    );
  }

  /// `POST {AUTH_URL}/api/auth/entrega` con el refresh guardado. **No gasta el
  /// refresh** ni devuelve otro: el par de la persona queda como estaba.
  ///
  /// El refresh es SIEMPRE el vigente del almacen, leido en el momento: otra pieza
  /// pudo renovarlo desde que empezo la entrega, y presentar uno viejo es presentar
  /// un refresh gastado.
  Future<String> _pedirToken() async {
    final sesion = await _almacen.leer();
    if (sesion == null || !sesion.llevaPar) {
      throw const SesionMuerta('no hay sesion guardada');
    }
    final r = await _llamar(_auth, 'POST', '/entrega', null, <String, Object?>{
      'refresh_token': sesion.refresh,
    });
    final token = r['token'];
    // Solo un token de ENTREGA vale aqui. Si Accesos devolviera otra cosa, no se
    // usa: presentarse a `sync` con un token que no es el de este camino.
    if (token is! String || token.isEmpty || r['ambito'] != ambitoDeEntrega) {
      throw const FormatException('Accesos no devolvió un token de entrega');
    }
    return token;
  }

  Future<Map<String, Object?>> _mandar(
    String token,
    String aparato,
    Apunte apunte,
  ) => _llamar(_sync, 'POST', '/revision/entrega', token, <String, Object?>{
    'aparato': aparato,
    'apuntes': [apunte.aJson(ColaDeSalida.cuerpoDe(apunte))],
  });

  /// Aplica la respuesta de UN apunte.
  ///
  /// `estado` es `en_revision` (lo acabo de guardar) o `repetido` (ya lo tenia), y
  /// `estadoActual` dice en que esta AHORA. Un `repetido` puede venir de dos sitios
  /// y NO es lo mismo:
  ///
  ///  * **con `revision`**: esta en la bandeja. `en_revision`/`aplicando` es
  ///    «esperando»; `aplicado`/`rechazado`/`descartado` ya lo decidio alguien, y
  ///    quien, cuando y el id creado vienen en `mias` (el literal de `motivo` de un
  ///    descarte ya trae el «por X» dentro, y partirlo seria adivinar).
  ///  * **sin `revision`** y `aplicado`/`rechazado`: lo resolvio ANTES la subida
  ///    normal (el libro `apuntes`), cuando la persona aun tenia permiso. No es una
  ///    entrega: se resuelve como la subida normal y NO pasa por `enRevision`.
  Future<_Anotado> _anotar(Apunte apunte, Map<String, Object?> respuesta) async {
    final crudos = respuesta['resultados'];
    if (crudos is List) {
      for (final crudo in crudos) {
        if (crudo is! Map<String, Object?> || crudo['clave'] != apunte.clave) {
          continue;
        }
        final entrega = crudo['revision'] as String?;
        final actual = crudo['estadoActual'];
        switch (crudo['estado']) {
          case 'en_revision':
            await _cola.marcarEnRevision(apunte.clave, entrega: entrega);
            return _Anotado.entregado;
          case 'repetido':
            if (entrega == null && (actual == 'aplicado' || actual == 'rechazado')) {
              // Lo resolvio antes la subida normal: se resuelve IGUAL que ella, con
              // el `id` que se creo (sin el, el `local-…` queda para siempre y la
              // fila sale como huerfana) y lo que se cayo.
              await _cola.resolver(
                apunte.clave,
                ResultadoApunte(
                  estado: actual == 'aplicado'
                      ? EstadoResultado.repetido
                      : EstadoResultado.rechazado,
                  id: actual == 'aplicado' ? crudo['id'] as String? : null,
                  motivo: actual == 'rechazado' ? crudo['motivo'] as String? : null,
                  descartados: DescartadoDelServidor.deLista(crudo['descartados']),
                ),
              );
              return _Anotado.yaResuelto;
            }
            await _cola.marcarEnRevision(apunte.clave, entrega: entrega);
            final decidido = actual == 'aplicado' ||
                actual == 'rechazado' ||
                actual == 'descartado';
            if (!decidido) return _Anotado.entregado;
            // Si la propia respuesta trae quien, cuando y el texto del descarte, se
            // anota aqui; si falta algo, se pregunta a `mias`.
            final decision = _decisionDeUnRepetido(crudo, actual as String);
            if (decision == null) return _Anotado.entregadoYDecidido;
            await _cola.resolverRevision(apunte.clave, decision);
            return _Anotado.entregado;
          default:
            Registro.aviso(
              'entrega de ${apunte.clave}: estado ${crudo['estado']} que no se '
              'entiende; se queda pendiente',
            );
            return _Anotado.sinRespuesta;
        }
      }
    }
    // Subio y no se sabe como quedo: pendiente, y la clave hace que el reintento
    // vuelva `repetido` en vez de duplicar.
    Registro.aviso(
      'entrega de ${apunte.clave} sin respuesta para esa clave; se queda pendiente',
    );
    return _Anotado.sinRespuesta;
  }

  /// La decision de un `repetido` ya decidido, **si la respuesta basta**: aplicado
  /// con su `decididoPorNombre` (y el `id` y los `descartados` que traiga),
  /// descartado con quien y el texto de quien descarto (`motivoDelDescarte`; el
  /// `motivo` lleva la frase ya montada y NO se usa), o rechazado con el literal del
  /// reparto. `null` = falta algo, y entonces se va a `mias`.
  static DecisionDeRevision? _decisionDeUnRepetido(
    Map<String, Object?> crudo,
    String actual,
  ) {
    final por = crudo['decididoPorNombre'];
    final bastan = switch (actual) {
      'aplicado' => por is String && por.isNotEmpty,
      'descartado' =>
        por is String && por.isNotEmpty && crudo['motivoDelDescarte'] is String,
      'rechazado' => crudo['motivo'] is String,
      _ => false,
    };
    if (!bastan) return null;
    return DecisionDeRevision.deJson(<String, Object?>{
      ...crudo,
      'estado': actual,
      'idCreado': crudo['id'],
      if (actual == 'descartado') 'motivo': crudo['motivoDelDescarte'],
    });
  }

  /// Convierte lo que lanzo una llamada en el resultado que se le cuenta a la
  /// persona. **Ninguna rama toca la cola**: lo que no se entrego sigue igual.
  ResumenDeEntrega _cierre(
    Object fallo, {
    required int entregados,
    required int sinEntregar,
    int yaResueltos = 0,
  }) {
    ResumenDeEntrega con(ResultadoDeEntrega r, String texto) => ResumenDeEntrega(
      entregados > 0 && r != ResultadoDeEntrega.rechazado
          ? ResultadoDeEntrega.parcial
          : r,
      entregados: entregados,
      sinEntregar: sinEntregar,
      error: texto,
      yaResueltos: yaResueltos,
      esperar: fallo is RechazoConEspera ? Duration(seconds: fallo.segundos) : null,
    );

    if (fallo is SesionMuerta) {
      return con(ResultadoDeEntrega.sesionTerminada, TextosDeEntrega.sesionTerminada);
    }
    if (fallo is FalloDeRed) {
      return con(ResultadoDeEntrega.sinConexion, TextosDeEntrega.sinConexion);
    }
    if (fallo is Rechazo) {
      if (fallo.codigo == 409 && fallo.marca == 'tiene_permiso') {
        return con(ResultadoDeEntrega.yaTienePermiso, TextosDeEntrega.yaTienePermiso);
      }
      // SIN darse de alta otra vez: no hay token para eso (`Subida` si lo hace,
      // con el token normal que esta persona ya no tiene).
      if (fallo.codigo == 404 && fallo.marca == marcaDeAparatoNoRegistrado) {
        return con(ResultadoDeEntrega.aparatoSinAlta, TextosDeEntrega.aparatoSinAlta);
      }
      return con(ResultadoDeEntrega.rechazado, _literalDe(fallo));
    }
    Registro.aviso('entrega: respuesta que no se entiende: $fallo');
    return con(ResultadoDeEntrega.rechazado, TextosDeEntrega.noAceptoElToken);
  }

  /// Accesos contesta con CODIGOS (`sin_sucursal`, `rate_limited`, `invalid_json`),
  /// no con frases: lo que se le ensena a la persona es la frase. Los de `sync`
  /// ya vienen en espanol y pasan tal cual.
  static String _literalDe(Rechazo r) {
    // Un token que `sync` no reconoce como de entrega: no es «no tienes permiso»
    // de la persona, es que esta entrega no se acepto.
    if (r.marca == marcaSinPermisoDeReparto) return TextosDeEntrega.noAceptoElToken;
    if (!RegExp(r'^[a-z_]+$').hasMatch(r.mensaje)) return r.mensaje;
    return switch (r.mensaje) {
      'sin_sucursal' => TextosDeEntrega.sinSucursal,
      'rate_limited' => TextosDeEntrega.demasiadosIntentos,
      _ => TextosDeEntrega.noAceptoElToken,
    };
  }

  // --- Preguntar que paso ------------------------------------------------------

  /// «Actualizar estados» de la pantalla de `/sin-permiso`: pide un token de
  /// entrega y consulta `GET /sync/revision/mias`. Con el aparato y la sesion
  /// delante; sin nada en revision no se hace ni una peticion.
  Future<ResumenDeConsulta> actualizarEstados() async {
    if (!_trabajaSinConexion() || await _base.cuantosEnRevision() == 0) {
      return const ResumenDeConsulta(ResultadoDeEntrega.nadaQueEntregar);
    }
    final sesion = await _almacen.leer();
    final aparato = await _aparato.leer();
    if (sesion == null || !sesion.llevaPar) {
      return const ResumenDeConsulta(
        ResultadoDeEntrega.sesionTerminada,
        error: TextosDeEntrega.sesionTerminada,
      );
    }
    if (aparato == null) {
      return const ResumenDeConsulta(
        ResultadoDeEntrega.aparatoSinAlta,
        error: TextosDeEntrega.aparatoSinAlta,
      );
    }
    try {
      final token = await _pedirToken();
      final (cambiaron, truncado) = await _aplicarMias(
        await _pedirMias(token, aparato),
      );
      return ResumenDeConsulta(
        ResultadoDeEntrega.entregado,
        cambiaron: cambiaron,
        truncado: truncado,
      );
    } on Object catch (e) {
      final c = _cierre(e, entregados: 0, sinEntregar: 0);
      return ResumenDeConsulta(c.resultado, error: c.error, esperar: c.esperar);
    }
  }

  /// Lo que hace el CICLO (con permiso y token normal): consulta `mias` **solo si
  /// hay algo `enRevision`**. [pedir] es la llamada del `ClienteApi` de `sync`, con
  /// su sesion y su renovacion de siempre. Un fallo no tumba el ciclo.
  Future<int> consultarConSesion(
    Future<Map<String, Object?>> Function(String ruta, Map<String, Object?> params)
    pedir,
  ) async {
    if (await _base.cuantosEnRevision() == 0) return 0;
    final aparato = await _aparato.leer();
    if (aparato == null) return 0;
    final r = await pedir('/revision/mias', <String, Object?>{'aparato': aparato});
    return (await _aplicarMias(r)).$1;
  }

  Future<Map<String, Object?>> _pedirMias(String token, String aparato) =>
      _llamar(_sync, 'GET', '/revision/mias', token, null, <String, Object?>{
        'aparato': aparato,
      });

  /// Aplica `{entregas:[{clave, estado, …}]}` a lo que esta `enRevision`.
  ///
  /// Devuelve cuantos cambiaron y si el servidor DIJO que la lista iba truncada
  /// (`truncado`): las vivas van primero, asi que lo que se queda fuera es lo mas
  /// viejo ya decidido, pero un apunte local `enRevision` que caiga ahi no se
  /// entera. Un tope alcanzado se dice (CLAUDE.md §3).
  Future<(int, bool)> _aplicarMias(Map<String, Object?> respuesta) async {
    final entregas = respuesta['entregas'];
    if (entregas is! List) {
      throw const FormatException('`mias` no devolvio `entregas`');
    }
    var cambiaron = 0;
    for (final e in entregas) {
      if (e is! Map<String, Object?>) continue;
      final clave = e['clave'];
      if (clave is! String) continue;
      final antes = await _cola.porClave(clave);
      // Solo lo que el aparato tiene entregado: lo demas no es suyo que moverlo.
      if (antes == null || antes.estado != EstadoApunte.enRevision) continue;
      try {
        await _cola.resolverRevision(clave, DecisionDeRevision.deJson(e));
      } on FormatException catch (x) {
        // Un apunte que no se entiende NO tumba a los demas.
        Registro.aviso('mias: $clave con un estado que no se entiende: $x');
        continue;
      }
      final despues = await _cola.porClave(clave);
      if (despues?.estado != antes.estado ||
          despues?.motivoRevision != antes.motivoRevision) {
        cambiaron++;
      }
    }
    final truncado = respuesta['truncado'] == true;
    if (truncado) {
      Registro.aviso('mias: el servidor devolvio la lista truncada');
    }
    return (cambiaron, truncado);
  }

  // --- Utilidades --------------------------------------------------------------

  /// `/routes/{id}/results` → `{id}`; cualquier otra cosa → `null`.
  static String? _hojaDe(Apunte a) =>
      RegExp(r'^/routes/([^/?]+)/results$').firstMatch(a.ruta)?.group(1);

  /// `PATCH /routes/{id}` con `status: completed` → `{id}`.
  static String? _rutaDeCierre(Apunte a) {
    if (a.metodo != 'PATCH') return null;
    final id = RegExp(r'^/routes/([^/?]+)$').firstMatch(a.ruta)?.group(1);
    if (id == null) return null;
    final cuerpo = ColaDeSalida.cuerpoDe(a);
    return cuerpo is Map && cuerpo['status'] == 'completed' ? id : null;
  }

  /// UNA llamada, con el `Authorization` que se le diga y la tabla de la regla 5
  /// (`InterceptorFallos.traducir`) aplicada a mano: estos `Dio` son crudos.
  Future<Map<String, Object?>> _llamar(
    Dio dio,
    String metodo,
    String ruta,
    String? token,
    Object? cuerpo, [
    Map<String, Object?>? params,
  ]) async {
    try {
      final r = await dio.request<Object?>(
        ruta,
        data: cuerpo,
        queryParameters: params,
        options: Options(
          method: metodo,
          headers: <String, Object?>{
            'Authorization': ?(token == null ? null : 'Bearer $token'),
          },
        ),
      );
      final datos = r.data;
      if (datos is! Map<String, Object?>) {
        throw const FormatException('respuesta que no es un objeto JSON');
      }
      return datos;
    } on DioException catch (e) {
      final fallo = InterceptorFallos.traducir(e);
      // Un 429 puede traer cuanto esperar; se conserva, y NO se reintenta solo.
      final espera = int.tryParse(e.response?.headers.value('retry-after') ?? '');
      if (fallo is Rechazo && fallo.codigo == 429 && espera != null && espera > 0) {
        throw RechazoConEspera(fallo, espera);
      }
      throw fallo;
    }
  }
}

/// Lo que cuenta «Actualizar estados».
class ResumenDeConsulta {
  const ResumenDeConsulta(
    this.resultado, {
    this.cambiaron = 0,
    this.error,
    this.truncado = false,
    this.esperar,
  });

  final ResultadoDeEntrega resultado;

  /// Cuantos apuntes cambiaron de estado con lo que dijo el servidor.
  final int cambiaron;
  final String? error;

  /// El servidor dijo que la lista venia truncada: puede haber apuntes decididos
  /// que no se muestran todavia.
  final bool truncado;

  /// Cuanto pide esperar el servidor (`Retry-After` de un 429).
  final Duration? esperar;

  bool get bien => error == null;
}
