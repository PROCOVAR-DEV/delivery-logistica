/// La regla 5, escrita en codigo.
///
/// | Lo que pasa        | Tipo          | Que hace la aplicacion                    |
/// |--------------------|---------------|-------------------------------------------|
/// | 200                | —             | dentro                                    |
/// | 401 (tras renovar) | `SesionMuerta`| limpia y a la pantalla de acceso          |
/// | 4xx que no es 401  | `Rechazo`     | se ensena el mensaje LITERAL del servidor |
/// | red, timeout, 5xx  | `FalloDeRed`  | CONSERVA los tokens y se reintenta luego  |
///
/// La linea que separa `SesionMuerta` de `FalloDeRed` es la que decide si un
/// logistico sigue trabajando o se queda fuera con el dia dentro. Borrar los
/// tokens por una caida pasajera obliga a entrar otra vez sin motivo, y en la
/// calle eso es quedarse sin aplicacion.
library;

/// LA MARCA DEL 403 «ESTA PERSONA NO ENTRA A REPARTO» (`{"codigo": …}`).
///
/// Solo entran ADMINISTRADOR, SUPER ADMIN, DESARROLLADOR y LOGISTICO; al resto
/// la API le contesta 403 en CUALQUIER llamada. Es DISTINTO de los otros 403
/// (alcance de sucursal: sin `codigo`) y NO es un rechazo de un apunte: es la
/// persona. Ver `docs/sin-permiso.md`.
const marcaSinPermisoDeReparto = 'sin_permiso_reparto';

/// La frase literal de ese 403. Solo la usa la segunda cerradura de
/// `Subida._aplicar`; lo que manda es [marcaSinPermisoDeReparto].
const textoSinPermisoDeReparto = 'No tienes permiso para entrar a Reparto.';

sealed class FalloApi implements Exception {
  const FalloApi();

  /// El texto que se le ensena a la persona.
  String get mensaje;
}

/// Red caida, tiempo agotado, o el servidor devolvio 5xx.
///
/// **Los tokens se quedan.** Esto se reintenta luego, solo.
class FalloDeRed extends FalloApi {
  const FalloDeRed({this.detalle, this.codigo});

  /// El 5xx, si lo hubo. `null` significa que la peticion ni salio.
  final int? codigo;
  final String? detalle;

  @override
  String get mensaje => 'Sin conexión con el servidor.';

  @override
  String toString() => 'FalloDeRed(codigo: $codigo, detalle: $detalle)';
}

/// CONTESTÓ ALGO, PERO NO NUESTRO SERVIDOR.
///
/// ## Un código HTTP no dice de quién es — 28/09/2026
///
/// Entre el teléfono y nuestra API hay cacharros que contestan por su cuenta:
/// el propio router, un proxy transparente, un filtro de la red del cliente,
/// una redirección a cualquier sitio. Como todos devuelven un código HTTP, esto
/// salía por la rama de `Rechazo` —«el servidor entendió la petición y dijo que
/// no»— y `Rechazo` es prueba de que la petición LLEGÓ. Con eso, la salud de la
/// red daba la conexión por buena aunque no llegara una sola petición.
///
/// **Es un `FalloDeRed` y hereda de él a propósito**, no un tipo suelto: todo
/// lo que ya estaba escrito para la red mala vale igual aquí y no hay que
/// acordarse de nada. Los tokens se quedan (`arranque.dart`, `subida.dart`), la
/// cola no se toca, se reintenta con sus esperas, y la salud de la red lo cuenta
/// como caída porque el `is FalloDeRed` de `proveedores.dart` y de
/// `cliente_api.dart` sigue siendo cierto. Lo único que cambia es lo que se le
/// dice a la persona.
///
/// Y eso es lo que justifica la clase aparte: «Sin conexión con el servidor»
/// manda a mirar la señal, y aquí la señal puede estar perfecta. Lo que hay
/// entre medias es otra cosa.
class ContestoOtroServidor extends FalloDeRed {
  const ContestoOtroServidor({super.codigo, super.detalle, this.tipo});

  /// El `Content-Type` que vino, cuando vino alguno. Va al registro: saber que
  /// llegó un `text/html` es media investigación hecha.
  final String? tipo;

  @override
  String get mensaje =>
      'No se llegó al servidor: contestó otra cosa por el camino.';

  @override
  String toString() =>
      'ContestoOtroServidor(codigo: $codigo, tipo: $tipo, detalle: $detalle)';
}

/// El servidor entendio la peticion y dijo que no.
///
/// `mensaje` es LITERAL y viene del servidor, en espanol
/// (`contratos-api.md`, apendice). Se pinta tal cual, sin envolver en «Ha
/// ocurrido un error»: «3 de los 8 pedidos ya están en otra ruta. Vuelve a
/// elegirlos.» le dice a alguien que hacer; «Ha ocurrido un error», no.
///
/// **Un `Rechazo` no se reintenta jamas.**
class Rechazo extends FalloApi {
  const Rechazo(this.codigo, this.mensaje, {this.marca, this.cuerpo});

  final int codigo;

  /// EL CUERPO ENTERO DE LA RESPUESTA, sin tocar. `null` si no vino ninguno.
  ///
  /// [mensaje] es lo que se pinta y basta casi siempre. Esto es para los pocos
  /// «no» que traen **una lista nombrada** al lado de la frase, y en los que la
  /// frase sola no le dice a nadie qué hacer:
  ///
  ///  * `POST /api/board/columns/{id}/route` contesta 409 con `descartados`, que
  ///    es quién se cayó de la zona y por qué. Sin esa lista, una columna de
  ///    doce que produce una ruta de nueve no tiene explicación, «que es la
  ///    manera más rápida de que el logístico deje de fiarse» (tablero.md §5.2).
  ///  * `DELETE /api/board/columns/{id}` contesta 409 con `pedidos`, el número
  ///    que decide si hay que vaciar dos tarjetas o mover ochenta.
  ///
  /// Se guarda crudo y no interpretado a propósito: quien lo lee sabe de qué
  /// endpoint viene y esta capa no.
  final Object? cuerpo;

  @override
  final String mensaje;

  /// LA MARCA QUE UNA MAQUINA PUEDE LEER, cuando el servidor la manda.
  ///
  /// El formato de la casa sigue siendo la frase en espanol, y esto no la
  /// sustituye: es para los pocos fallos donde el cliente tiene que **hacer
  /// algo distinto** segun cual sea, y el numero no basta para distinguirlos.
  ///
  /// El caso que la trajo: `/sync/subida` contesta 404 cuando el aparato no
  /// esta registrado, y el telefono respondia tirando su identificador y
  /// dandose de alta otra vez. Pero un 404 de Traefik durante un redespliegue
  /// —que ni siquiera es JSON— tambien es un 404, y hacia lo mismo. En
  /// produccion salieron **12 aparatos para un solo telefono**.
  ///
  /// `null` = el servidor no mando ninguna. Entonces **no se puede suponer
  /// cual es**, y quien decide algo destructivo con esto tiene que fallar
  /// cerrado.
  ///
  /// ## Y ESE 404 DE TRAEFIK YA NO LLEGA HASTA AQUI — 28/09/2026
  ///
  /// Cambio a proposito y conviene saberlo antes de leer el parrafo de arriba
  /// pensando que sigue igual: `InterceptorFallos.traducir` mira ahora **quien
  /// firma la respuesta**, y una que no sea JSON de nuestra API sale como
  /// `ContestoOtroServidor`, que es un `FalloDeRed`. El 404 de Traefik durante
  /// un redespliegue —el de los 12 aparatos para un solo telefono— ya no es un
  /// `Rechazo`: es red, **y se reintenta**.
  ///
  /// Es lo correcto y no un efecto lateral que haya que arreglar: durante un
  /// redespliegue el servicio no esta, y eso se espera y se repite, no se le
  /// enseña a nadie como «el servidor dijo que no». Esta guarda no sobra por
  /// eso: sigue haciendo falta para los 404 de VERDAD —los nuestros, en JSON—,
  /// que son los que traen marca y los que hay que distinguir.
  final String? marca;

  @override
  String toString() => 'Rechazo($codigo, $mensaje${marca == null ? '' : ', $marca'})';
}

/// La sesion murio: un 401 que sigue siendo 401 despues de renovar, o un
/// refresh que el servidor ya no acepta.
///
/// Es lo unico que manda a alguien a la pantalla de acceso.
class SesionMuerta extends FalloApi {
  const SesionMuerta([this.detalle]);

  final String? detalle;

  @override
  String get mensaje => 'La sesión terminó. Hay que entrar otra vez.';

  @override
  String toString() => 'SesionMuerta($detalle)';
}
