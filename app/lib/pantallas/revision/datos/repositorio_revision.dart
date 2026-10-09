import '../../../nucleo/red/cliente_api.dart';
import 'bandeja.dart';
import 'quien_revisa.dart';

/// La bandeja del revisor, contra `sync` y SOLO contra `sync`.
///
/// Las direcciones son las de `docs/bandeja-de-revision.md` B.2 («Endpoints de
/// `sync`», con token normal de revisor). El cliente ya trae `…/sync` de base,
/// igual que Sincronizacion pide `/estado`. **Si S2 las llama distinto, es aqui
/// donde se cambia.**
///
/// Nada de esto se reintenta a mano ni se da por hecho: lo que el servidor
/// contesta (o el `Rechazo` con su motivo literal) es lo unico que cuenta.
class RepositorioRevision {
  RepositorioRevision(this._api);

  final ClienteApi _api;

  /// `GET /sync/revision`: las entregas con algo vivo, acotadas por el
  /// ALCANCE de quien pregunta (lo cierra el servidor, dentro del SQL).
  /// [sucursal] solo ESTRECHA y solo se lo admite a quien ve varias.
  Future<BandejaDelRevisor> bandeja({String? sucursal}) async =>
      BandejaDelRevisor.deJson(
        await _api.pedir<Map<String, Object?>>(
          '/revision',
          params: sucursal == null
              ? null
              : <String, Object?>{'sucursal': sucursal},
        ),
      );

  /// `GET /sync/revision/{entrega}`: la entrega con sus apuntes, en orden.
  Future<EntregaEnRevision> detalle(String entrega) async {
    final json = await _api.pedir<Map<String, Object?>>('/revision/$entrega');
    // O la entrega y sus apuntes al mismo nivel, o `{entrega: {...}, apuntes}`.
    final cabecera = json['entrega'];
    return EntregaEnRevision.deJson(
      cabecera is Map<String, Object?>
          ? <String, Object?>{...cabecera, 'apuntes': json['apuntes']}
          : json,
    );
  }

  /// `POST /sync/revision/{aparato}/{clave}/aplicar`.
  ///
  /// [reintentarInterrumpido] manda `{"reintentarInterrumpido": true}`: SOLO para
  /// un `aplicando` marcado `interrumpido`, y tras comprobar a mano la ruta. Sin
  /// la bandera el servidor contesta 409 `ya_se_esta_aplicando` (y dice quien lo
  /// tiene). Por defecto no se manda cuerpo.
  ///
  /// **Sin reintento automatico** (`reintentar: false`): es una orden de una
  /// persona. Un 502 `reparto_no_disponible` es "vuelve a intentarlo TU", y la
  /// red repitiendola sola seria aplicar otra vez a escondidas.
  Future<RespuestaDeAplicar> aplicar(
    String aparato,
    String clave, {
    bool reintentarInterrumpido = false,
  }) async => RespuestaDeAplicar.deJson(
    await _api.mandar<Object?>(
      'POST',
      '/revision/$aparato/$clave/aplicar',
      reintentarInterrumpido
          ? const <String, Object?>{'reintentarInterrumpido': true}
          : null,
      reintentar: false,
    ),
  );

  /// `POST /sync/revision/{entrega}/aplicar`: en orden. SE DETIENE en el primer
  /// apunte que no queda aplicado; la respuesta dice donde y por que.
  Future<RespuestaDeAplicar> aplicarTodo(String entrega) async =>
      RespuestaDeAplicar.deJson(
        await _api.mandar<Object?>(
          'POST',
          '/revision/$entrega/aplicar',
          null,
          reintentar: false,
        ),
      );

  /// `POST /sync/revision/{aparato}/{clave}/descartar` con `{motivo}`.
  ///
  /// **Sin motivo no sale NI UNA peticion**, aunque la pantalla se equivoque:
  /// es la segunda cerradura. La tercera es el `422` del servidor.
  Future<void> descartar(String aparato, String clave, String motivo) async {
    if (!motivoValido(motivo)) {
      throw ArgumentError.value(motivo, 'motivo', 'un descarte lleva motivo');
    }
    await _api.mandar<Object?>(
      'POST',
      '/revision/$aparato/$clave/descartar',
      <String, Object?>{'motivo': motivo.trim()},
      reintentar: false,
    );
  }
}
