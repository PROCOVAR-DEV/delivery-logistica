import 'package:dio/dio.dart';

import '../../../nucleo/identidad/almacen_sesion.dart';
import '../../../nucleo/identidad/entrada_por_accesos.dart';
import '../../../nucleo/identidad/renovador.dart' show esSinPermisoDeAccesos;
import '../../../nucleo/identidad/revocador_de_cierres.dart'
    show cierreConfirmado;
import '../../../nucleo/identidad/sesion.dart';
import '../../../nucleo/registro/registro.dart';
import '../../../nucleo/plataforma.dart';
import '../../../nucleo/red/fallos.dart' show textoSinPermisoDeReparto;

/// Por que no se pudo entrar, en cristiano.
///
/// Cada uno lleva su mensaje porque **lo que se le dice a alguien que no puede
/// entrar decide lo que hace después**: «usuario o contraseña incorrectos» se
/// arregla probando otra vez; «no estás en ninguna sucursal» se arregla llamando
/// a la oficina, y decirle a esa persona «ha ocurrido un error» la deja
/// probando su contraseña buena una y otra vez hasta que el limitador la echa.
enum MotivoDeAcceso {
  /// 401. Usuario que no existe, cuenta sin contraseña o contraseña mal: auth
  /// los contesta los tres igual a propósito, y aquí se respeta.
  credenciales,

  /// 403 `sin_sucursal`. **Esto no es un fallo de la aplicación**: la contraseña
  /// era buena. Es que la cuenta no está dada de alta en ninguna sucursal, y en
  /// el reparto un token sin sucursal no es un token limitado — es el que abre
  /// las ocho. Por eso auth prefiere no emitirlo.
  sinSucursal,

  /// 403 `sin_permiso`. La contraseña era buena y la cuenta existe: es que NO
  /// tiene `delivery.entrar`, o sea que no es de uno de los roles que entran a
  /// Reparto. No se guarda nada y no hay nada que reintentar: se pide acceso a un
  /// administrador y, mientras, se ofrece la salida a Accesos.
  sinPermiso,

  /// 403 con la cuenta dada de baja.
  cuentaDeBaja,

  /// 429. Demasiados intentos.
  demasiadosIntentos,

  /// No hay red, o el servidor no contesta. **Para entrar hace falta conexión**,
  /// y esto es exactamente eso y no una sesión muerta.
  sinConexion,

  /// 5xx y todo lo demás.
  servidor,
}

class FalloDeAcceso implements Exception {
  const FalloDeAcceso(this.motivo, this.mensaje, {this.detalle});

  final MotivoDeAcceso motivo;

  /// Lo que se pinta debajo del botón.
  final String mensaje;

  /// Lo que dijo el servidor, para el registro. No se pinta.
  final String? detalle;

  @override
  String toString() => 'FalloDeAcceso($motivo, $mensaje, $detalle)';
}

/// Quien entró, y **si la sesión se quedó guardada de verdad**.
///
/// Las dos cosas juntas porque se deciden juntas y se cuentan juntas: entrar
/// bien con una sesión que no persiste es exactamente el caso que dejó a Jose
/// escribiendo la contraseña otra vez al reabrir la aplicación el 15/09/2026.
/// Quien entra tiene derecho a enterarse EN ESE MOMENTO, que es el único en el
/// que todavía hay conexión y hay alguien a quien preguntar.
class Acceso {
  const Acceso(this.sesion, {required this.seGuardo});

  final Sesion sesion;

  /// `false` cuando el aparato aceptó guardar el par y después no lo encuentra.
  /// La sesión sirve para HOY; lo que no va a sobrevivir es cerrar y abrir.
  final bool seGuardo;
}

/// LA PUERTA. Usuario y contraseña contra `POST /api/auth/token`.
///
/// Va con el Dio **crudo** de auth (`dioAuthProvider`), sin `InterceptorSesion`:
/// entrar no se renueva a sí mismo, y un 401 de aquí es «esa contraseña no es»,
/// no «la sesión murió».
///
/// La aplicación **no lleva ninguna clave dentro** (`docs/identidad.md`): manda
/// usuario y contraseña por HTTPS y recibe el par de tokens. Una APK se
/// descompila.
class ServicioDeAcceso {
  ServicioDeAcceso({
    required Dio auth,
    required AlmacenDeSesion almacen,
    EntradaPorAccesos? porAccesos,
  }) : _auth = auth,
       _almacen = almacen,
       _porAccesos = porAccesos;

  final Dio _auth;
  final AlmacenDeSesion _almacen;

  /// La puerta de la WEB. `null` en la APK y en el escritorio, y ahi no es un
  /// hueco: alli cerrar sesion es revocar el par y borrarlo, no mandar el
  /// navegador a ningun sitio.
  final EntradaPorAccesos? _porAccesos;

  /// Entra y **guarda el par**. Lo que devuelve dice además si quedó guardado.
  Future<Acceso> entrar({
    required String usuario,
    required String contrasena,
    String? sucursal,
  }) async {
    try {
      final respuesta = await _auth.post<Map<String, Object?>>(
        '/token',
        data: <String, Object?>{
          // `identifier` y no `email`: aquí se entra con el nombre de usuario de
          // PEDIDO (`yasmani`, `claudia.hab`) tanto como con el correo, y auth
          // admite los dos por este mismo campo.
          'identifier': usuario,
          'password': contrasena,
          if (sucursal != null && sucursal.isNotEmpty) 'sucursal': sucursal,
        },
      );
      final sesion = Sesion.deJson(respuesta.data ?? const <String, Object?>{});
      final seGuardo = await _almacen.guardar(sesion);
      Registro.info('dentro: ${sesion.sub} (${sesion.sucursalId ?? "todas"})');
      if (!seGuardo) {
        Registro.fallo(
          'se entró pero el par no quedó guardado: este aparato no puede '
          'trabajar sin señal después de cerrar la aplicación',
        );
      }
      return Acceso(sesion, seGuardo: seGuardo);
    } on DioException catch (e) {
      throw _traducir(e);
    } on FormatException catch (e) {
      // Auth contestó 200 con algo que no es un par de tokens. Es del servidor,
      // no de quien escribió la contraseña, y se dice así.
      throw FalloDeAcceso(
        MotivoDeAcceso.servidor,
        'El servidor contestó algo que no se entiende. Avisa a la oficina.',
        detalle: e.message,
      );
    }
  }

  /// Cierra la sesión de ESTE aparato. Auth contesta 200 pase lo que pase, así
  /// que esto no puede impedir salir: lo local se borra igual.
  ///
  /// ## Y EN LA WEB SE CIERRA EN LOS DOS LADOS
  ///
  /// Allí la sesión no es un par guardado: es una cookie `httpOnly` que este
  /// JavaScript **no puede ni leer ni borrar** (y ha de ser así — un token que
  /// el navegador puede leer se lo lleva cualquier script de la página). Hasta
  /// que esto existió, quien le daba a «cerrar sesión» volvía a entrar sin más y
  /// pensaba que había salido, que es justo lo que importa en el ordenador
  /// compartido donde se le da al botón.
  ///
  /// Quien la borra es el servidor, y el camino entero pasa por Accesos —donde
  /// vive la sesión de verdad y donde está el cartel de «¿seguro?»—:
  /// `GET /api/auth/logout` → Accesos → `GET /api/auth/logout/done`, que retira
  /// la cookie con los mismos atributos con los que se puso.
  Future<void> salir(Sesion? sesion) async {
    // Sin par no hay nada que revocar: confirmado de antemano.
    var confirmado = true;
    try {
      // SÓLO SI HAY PAR QUE REVOCAR. Una sesión de cookie no lo tiene, y
      // mandarle a auth un `refresh_token` vacío es una petición que sólo puede
      // fallar y ensuciar el registro de Accesos.
      if (sesion != null && sesion.llevaPar) {
        final respuesta = await _auth.post<Object?>(
          '/logout',
          data: <String, Object?>{'refresh_token': sesion.refresh},
        );
        // Un 200 de portal cautivo (`text/html`) no es Accesos: no confirma.
        confirmado = cierreConfirmado(respuesta);
      }
    } on DioException catch (e) {
      // Sin red no se puede revocar, y aun así se sale: dejar la sesión abierta
      // en el teléfono porque el servidor tuvo un mal momento es peor.
      Registro.aviso('no se pudo avisar a auth del cierre: ${e.type}');
      // Un 401 de NUESTRO servidor es que ya estaba cerrado; el de un portal
      // cautivo no dice nada de Accesos.
      confirmado = cierreConfirmado(e.response);
    }
    // PERO EL REFRESCO NO SE TIRA si no se confirmó: se guarda aparte, ANTES de
    // borrar la sesión de abajo, y se revoca en cuanto haya red
    // (`RevocadorDeCierres`). Antes quedaba vivo en Accesos hasta 30 días sin que
    // nadie lo reintentara.
    if (!confirmado && sesion != null) {
      final quedo = await _almacen.dejarPorRevocar(
        RefrescoPorRevocar(sub: sesion.sub, refresh: sesion.refresh),
      );
      if (!quedo) {
        Registro.fallo(
          'el cierre no llegó a Accesos y no se pudo dejar pendiente: el '
          'refresco queda vivo hasta que caduque',
        );
      }
    }
    // Lo guardado, siempre: en la web es el par de la puerta de respaldo, si se
    // llegó a usar. Dejarlo ahí sería seguir dentro con la cookie ya borrada.
    await _almacen.borrar();
    // Y EL ÚLTIMO PASO, sólo en la web: se va. La aplicación no vuelve de aquí.
    _porAccesos?.aSalir();
  }

  static FalloDeAcceso _traducir(DioException e) {
    final codigo = e.response?.statusCode;
    final cuerpo = e.response?.data;
    final error = cuerpo is Map ? cuerpo['error'] as String? : null;
    final mensaje = cuerpo is Map ? cuerpo['message'] as String? : null;

    if (codigo == null) {
      // El mismo fallo se cuenta distinto segun donde se abra, y no es un
      // adorno: en la APK «no hay señal» es casi siempre verdad, y en la web es
      // casi siempre mentira. Ver `pantalla_acceso.dart`.
      return FalloDeAcceso(
        MotivoDeAcceso.sinConexion,
        TextosDeCaida.titular(sinConexion: Destino.trabajaSinConexion),
        detalle: e.message ?? e.type.name,
      );
    }

    // ANTES que el `switch`: la marca puede venir en `error` o en `codigo`, y los
    // otros 403 de la puerta (`sin_sucursal`, `revoked`) no la traen.
    if (esSinPermisoDeAccesos(e.response)) {
      return FalloDeAcceso(
        MotivoDeAcceso.sinPermiso,
        mensaje ?? textoSinPermisoDeReparto,
        detalle: error,
      );
    }

    return switch (codigo) {
      401 => const FalloDeAcceso(
        MotivoDeAcceso.credenciales,
        'Usuario o contraseña incorrectos.',
      ),
      403 when error == 'sin_sucursal' => FalloDeAcceso(
        MotivoDeAcceso.sinSucursal,
        mensaje ??
            'La cuenta no está dada de alta en ninguna sucursal, o la '
                'sucursal pedida no es suya.',
        detalle: error,
      ),
      // `revoked` es la baja de la persona (`apk-tokens.ts`). Cualquier OTRO
      // 403 no es de auth: lo puso algo por delante —Cloudflare contesta
      // «error code: 1010» con 403— y decirle a alguien que su cuenta está dada
      // de baja cuando lo que pasa es que un filtro no dejó pasar la petición es
      // mandarlo a la oficina a preguntar por algo que no existe. Visto en el
      // navegador el 15/09/2026.
      403 when error == 'revoked' => FalloDeAcceso(
        MotivoDeAcceso.cuentaDeBaja,
        mensaje ?? 'La cuenta está dada de baja.',
        detalle: error,
      ),
      403 => FalloDeAcceso(
        MotivoDeAcceso.servidor,
        'El servidor no dejó pasar la petición (403). No es tu contraseña: '
        'avisa a la oficina.',
        detalle: mensaje ?? error,
      ),
      429 => const FalloDeAcceso(
        MotivoDeAcceso.demasiadosIntentos,
        'Demasiados intentos seguidos. Espera un minuto y vuelve a probar.',
      ),
      400 => const FalloDeAcceso(
        MotivoDeAcceso.credenciales,
        'Falta el usuario o la contraseña.',
      ),
      _ => FalloDeAcceso(
        MotivoDeAcceso.servidor,
        'El servidor no está respondiendo bien ($codigo). Vuelve a probar en '
        'un momento.',
        detalle: mensaje ?? error,
      ),
    };
  }
}
