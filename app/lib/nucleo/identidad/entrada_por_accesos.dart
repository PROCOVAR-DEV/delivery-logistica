import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../plataforma.dart';
import '../red/entorno.dart';
import '../red/interceptor_sesion.dart' show esSinPermisoDeReparto;
import '../registro/registro.dart';
import 'navegador.dart';
import 'sesion.dart';

/// LA WEB ENTRA SOLA POR ACCESOS. La APK no, y eso no se toca.
///
/// `docs/identidad.md` lo dice en una tabla de dos filas:
///
/// | Cliente | Como | Que guarda |
/// |---|---|---|
/// | **Web** | Login unico de auth: redireccion y vuelta con sesion | Cookie |
/// | **APK** | Usuario y contrasena contra el endpoint de token | El par |
///
/// Son dos puertas al mismo sitio y cada una existe por algo. La APK manda
/// usuario y contrasena porque se va al patio de un almacen y tiene que poder
/// guardar el par para el dia entero sin senal. La web no se va a ningun sitio:
/// quien ya entro en Accesos aterriza dentro **sin escribir nada**, y lo que
/// sostiene su sesion es una cookie `httpOnly` que el JavaScript de la pagina no
/// puede leer.
///
/// ## Como se sabe si hay sesion
///
/// **Preguntandoselo al servidor.** La cookie no se puede leer desde aqui —para
/// eso es `httpOnly`—, asi que mirar lo que hay guardado en el navegador no
/// contesta la pregunta: en la web el almacen devuelve `null` aunque haya
/// sesion. Quien sabe es `GET /api/me`, que devuelve la persona **y el token de
/// la cookie** exactamente para esto (`api/internal/api/yo.go`).
///
/// Y son TRES respuestas, no dos, que es lo que evita el bucle:
///
///  * **hay sesion** → dentro, sin formulario;
///  * **401** → no hay sesion → al login unico;
///  * **no contesta** → NO es «no hay sesion». Mandar a Accesos a alguien cuya
///    API esta caida es mandarlo a dar la vuelta para volver al mismo sitio. Se
///    queda en la puerta y se dice lo que pasa.
class EntradaPorAccesos {
  EntradaPorAccesos({
    required Dio api,
    required Navegador navegador,
    String baseApi = Entorno.apiUrl,
  }) : _api = api,
       _navegador = navegador,
       _base = _sinBarraFinal(baseApi),
       _alCargar = navegador.direccionAlCargar {
    _motivo = motivoEnLaDireccion(_alCargar);
  }

  final Dio _api;
  final Navegador _navegador;

  /// La base de la API, ya sin barra final: `https://reparto.procovar.cloud/api`.
  /// Las cuatro rutas de la puerta cuelgan de ahi, porque el proxy se queda con
  /// `/api` antes que la aplicacion (`CLAUDE.md` §3-quater).
  final String _base;

  /// La direccion con la que se cargo la pagina, **capturada al construir**.
  ///
  /// No se lee cuando hace falta: para entonces el portero ya ha movido la
  /// aplicacion a `/arranque` y el motivo que el servidor dejo en la direccion
  /// se habria perdido. Esto se construye en el arranque, que es lo primero que
  /// corre.
  final Uri _alCargar;

  String? _motivo;
  bool _yaNavegue = false;

  /// POR QUE NO SE ENTRO SOLA, si es que no se entro. `null` cuando no ha
  /// fallado nada y hay que mandar a la persona a Accesos.
  String? get motivo => _motivo;

  /// A donde iba quien abrio el enlace. `null` si iba a la portada.
  ///
  /// Se mira en dos sitios porque depende de lo rapido que haya llegado el
  /// arranque: la direccion tal cual —`/orders?municipio=Centro`— o, si el
  /// portero ya la guardo, dentro de su `volverA`.
  String? get aDondeIba => destinoEnLaDireccion(_alCargar);

  /// ¿HAY SESION? Se lo pregunta al servidor, que es el unico que lo sabe.
  Future<QuienSoy> quienSoy() async {
    try {
      final respuesta = await _api.get<Map<String, Object?>>(
        '/me',
        // La cookie va en la peticion. Con la aplicacion y la API bajo el mismo
        // dominio esto sobra, pero en desarrollo son dos puertos y sin ello la
        // cookie no viaja: se veria «no hay sesion» con la sesion puesta.
        options: Options(extra: <String, Object?>{'withCredentials': true}),
      );
      final datos = respuesta.data ?? const <String, Object?>{};
      final usuario = datos['user'];
      final token = datos['token'];
      if (usuario is! Map<String, Object?> ||
          token is! String ||
          token.isEmpty) {
        // 200 con `{"user":null}` es la forma que tiene `/api/me` de decir que
        // no hay sesion sin confundirla con un fallo.
        return const NoHaySesion();
      }
      return HaySesion(Sesion.deLaCookie(token: token, usuario: usuario));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return const NoHaySesion();
      // HAY SESION, PERO LA PERSONA NO ENTRA A REPARTO. Ni «no hay sesion» —
      // mandarla a Accesos para que vuelva con la cookie puesta es un bucle
      // entre las dos paginas— ni «no contesta». Es su propia pantalla.
      if (esSinPermisoDeReparto(e.response)) return const SinPermiso();
      // NI 401 NI 200: el servidor no esta. Se dice, y NO se manda a nadie a
      // Accesos — la vuelta de Accesos entra por esta misma API.
      final detalle = e.message ?? e.type.name;
      Registro.fallo('no se pudo preguntar quien soy: $detalle');
      _motivo ??= motivoNoContesta;
      return NoContesta(detalle);
    }
  }

  /// AL LOGIN UNICO. Se pierde la pagina: es una navegacion de verdad.
  void aAccesos({String? volverA}) {
    if (_yaNavegue) return; // dos redirecciones a la vez es una pantalla rota
    _yaNavegue = true;
    final destino = volverA ?? aDondeIba;
    final consulta = (destino == null || destino.isEmpty)
        ? ''
        : '?volverA=${Uri.encodeQueryComponent(destino)}';
    Registro.info(
      'a Accesos${destino == null ? "" : " (volviendo a $destino)"}',
    );
    _navegador.irA('$_base/auth/entrar$consulta');
  }

  /// SALIR. Pasa por Accesos, que es donde vive la sesion y donde esta el cartel
  /// de «¿seguro?»; la cookie de aqui la borra el servidor al volver.
  ///
  /// No mira [_yaNavegue] —salir es un acto explicito y gana— pero si lo pone,
  /// para que la pantalla de acceso no dispare encima su propia redireccion al
  /// login y las dos se peleen por la barra de direcciones.
  void aSalir() {
    _yaNavegue = true;
    _navegador.irA('$_base/auth/logout');
  }

  /// El motivo, en cristiano y con lo que hay que hacer. Los nombres son los que
  /// escribe el servidor en la direccion (`api/internal/api/auth_web.go`).
  static String textoDelMotivo(String motivo) => switch (motivo) {
    'nodisponible' =>
      'El acceso con la cuenta de Procovar todavía no está configurado en este '
          'servidor. Avisa a quien lleva el sistema.',
    'sincodigo' => 'La vuelta desde Accesos llegó incompleta. Vuelve a probar.',
    motivoNoContesta =>
      'El servidor del reparto no contesta. La página cargó, así que conexión '
          'hay: prueba otra vez y, si sigue igual, avisa a la oficina.',
    _ =>
      'No se pudo conectar con Accesos. Vuelve a probar en un momento; si '
          'sigue igual, avisa a la oficina.',
  };

  /// El motivo que no viene del servidor: la API no contesto.
  static const motivoNoContesta = 'nocontesta';

  /// El motivo que el servidor dejo en la direccion, o `null`.
  ///
  /// Se mira en DOS sitios y no es por gusto: el portero mueve la aplicacion a
  /// `/arranque?volverA=…` en cuanto arranca, asi que segun lo rapido que se
  /// lea, el `?sso=` esta suelto en la direccion o metido dentro del `volverA`.
  /// Mirar solo uno es que el motivo se pierda la mitad de las veces, y un
  /// motivo que se pierde deja exactamente la pantalla muda que esto viene a
  /// quitar.
  static String? motivoEnLaDireccion(Uri direccion) {
    final suelto = direccion.queryParameters['sso'];
    if (suelto != null && suelto.isNotEmpty) return suelto;
    final guardada = direccion.queryParameters[_claveDelDestino];
    if (guardada == null || guardada.isEmpty) return null;
    final dentro = Uri.tryParse(guardada)?.queryParameters['sso'];
    return (dentro == null || dentro.isEmpty) ? null : dentro;
  }

  /// A donde iba la persona, leido de la misma direccion y con la misma regla de
  /// los dos sitios. Las puertas no cuentan: volver a `/acceso` despues de
  /// entrar seria un bucle.
  static String? destinoEnLaDireccion(Uri direccion) {
    final guardada = direccion.queryParameters[_claveDelDestino];
    if (guardada != null && guardada.isNotEmpty) {
      return _siNoEsLaPuerta(guardada);
    }
    final propia = direccion.hasQuery
        ? '${direccion.path}?${direccion.query}'
        : direccion.path;
    return _siNoEsLaPuerta(propia);
  }

  /// La clave donde el portero guarda «a donde iba»
  /// (`navegacion/portero.dart`, `claveDelDestino`). Escrita aqui y no
  /// importada para no meter la navegacion dentro del nucleo; si alguna vez
  /// cambia alli, esto deja de acordarse de a donde iba nadie — y por eso hay
  /// una prueba que las ata.
  static const _claveDelDestino = 'volverA';

  static const _puertas = <String>{
    '/acceso',
    '/arranque',
    '/configurando',
    '/sin-permiso',
  };

  static String? _siNoEsLaPuerta(String destino) {
    final ruta = Uri.tryParse(destino)?.path ?? destino;
    if (ruta.isEmpty || ruta == '/' || _puertas.contains(ruta)) return null;
    return destino;
  }

  static String _sinBarraFinal(String base) =>
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;
}

/// Lo que contesta `/api/me`. TRES respuestas, no dos: ver arriba.
sealed class QuienSoy {
  const QuienSoy();
}

class HaySesion extends QuienSoy {
  const HaySesion(this.sesion);

  final Sesion sesion;
}

class NoHaySesion extends QuienSoy {
  const NoHaySesion();
}

/// Hay sesion en Accesos, pero la API dice 403 `sin_permiso_reparto`.
class SinPermiso extends QuienSoy {
  const SinPermiso();
}

class NoContesta extends QuienSoy {
  const NoContesta(this.detalle);

  /// Lo que dijo la red, para el registro. No se pinta.
  final String detalle;
}

/// ¿SE ENTRA POR ACCESOS O CON USUARIO Y CONTRASENA?
///
/// Es la otra cara de [trabajaSinConexionProvider] y por eso sale de el: quien
/// se va al patio de un almacen necesita guardar el par, y quien abre un
/// navegador tiene el login unico ahi mismo. Se lee por provider para que una
/// prueba pueda ponerse en el otro destino sin compilar para web.
final entraPorAccesosProvider = Provider<bool>(
  (ref) => !ref.watch(trabajaSinConexionProvider),
);

final navegadorProvider = Provider<Navegador>((ref) => abrirNavegador());

/// El Dio **crudo** de la API, sin `InterceptorSesion`.
///
/// Sin interceptor a proposito: preguntar quien soy no puede disparar una
/// renovacion —no hay par que renovar— ni echar a nadie por un 401, que aqui es
/// la respuesta normal de «todavia no has entrado».
final dioApiCrudoProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      baseUrl: Entorno.apiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
    ),
  ),
);

final entradaPorAccesosProvider = Provider<EntradaPorAccesos>(
  (ref) => EntradaPorAccesos(
    api: ref.watch(dioApiCrudoProvider),
    navegador: ref.watch(navegadorProvider),
  ),
);
