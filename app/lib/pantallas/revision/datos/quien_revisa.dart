import '../../../nucleo/identidad/sesion.dart';
import 'bandeja.dart';

/// QUIEN REVISA — Jose, 08/10/2026 (`docs/bandeja-de-revision.md`, «Decisiones
/// de Jose»): **ADMINISTRADOR de esa sucursal, SUPER ADMIN y DESARROLLADOR, y
/// nadie revisa lo suyo.**
///
/// LOGISTICO entra a Reparto pero NO revisa: no le toca decidir sobre el trabajo
/// de otro logistico.
///
/// **ESTO NO ES UN PERMISO.** El rol viaja en el token y cualquiera con un editor
/// de texto escribe el que quiera; sirve para no estorbar (que no se ofrezca lo
/// que el servidor va a negar con un 403). El cerrojo de verdad —revisor distinto
/// del autor, sucursal dentro de su alcance, lista blanca de rutas— lo pone
/// `sync` al aplicar. Ver `PantallaRegistrada.soloParaRoles`.
const rolesQueRevisan = <String>[
  'ADMINISTRADOR',
  'SUPER ADMIN',
  'DESARROLLADOR',
];

/// ¿Es de los que revisan?
bool puedeRevisar(Sesion? quien) =>
    quien?.tieneAlguno(rolesQueRevisan) ?? false;

/// Una nota de descarte tiene que decir algo: el servidor exige 5 caracteres
/// (`CHECK … length(btrim(motivo)) >= 5`, B.2). La misma regla, escrita una vez.
const motivoMinimoDelDescarte = 5;

bool motivoValido(String motivo) =>
    motivo.trim().length >= motivoMinimoDelDescarte;

/// ¿PUEDE ESTA PERSONA DECIDIR SOBRE ESTA ENTREGA? `null` = sí; si no, **el
/// motivo, para decirlo** (un botón que falta sin explicación es la pantalla
/// rota).
///
/// Falla CERRADO: sin sesión, o sin saber quién es (`sub` vacío), no se decide.
/// «Nadie revisa lo suyo» solo se puede cumplir sabiendo quién eres.
String? porQueNoPuedeDecidir(Sesion? quien, EntregaEnRevision entrega) {
  if (!puedeRevisar(quien)) return TextosDeRevision.noRevisas;
  if (quien!.sub.isEmpty) return TextosDeRevision.noSeQuienEres;
  if (quien.sub == entrega.persona) return TextosDeRevision.esLoTuyo;
  return null;
}

/// Los literales de la pantalla, en un sitio.
abstract final class TextosDeRevision {
  static const titulo = 'Revisión';
  static const explicacion =
      'Trabajo que hicieron personas que ya no tienen permiso en Reparto. '
      'Se conserva tal como llegó: no se aplica nunca solo. Tú decides.';

  static const noRevisas =
      'No tienes permiso para revisar. Revisan el administrador de la '
      'sucursal, el super administrador y el desarrollador.';
  static const noSeQuienEres =
      'No se sabe quién eres en este aparato, así que no se puede comprobar '
      'que no estés revisando lo tuyo. Vuelve a entrar.';
  static const esLoTuyo =
      'Lo entregaste tú. Nadie revisa lo suyo: tiene que decidirlo otra '
      'persona.';

  static const cargando = 'Cargando la bandeja de revisión…';
  static const vacia =
      'No hay nada esperando revisión. Cuando alguien que pierda el permiso '
      'entregue su trabajo, aparecerá aquí.';
  static const sinConexion =
      'No se pudo leer la bandeja: sin conexión con el servidor. No se sabe '
      'si hay trabajo esperando; no se da por vacía.';
  static const sinConexionAlDecidir =
      'Sin conexión: no se sabe si la orden llegó. Actualiza para ver cómo '
      'quedó de verdad antes de repetir.';

  static const aplicar = 'Aplicar';
  static const reintentar = 'Reintentar';
  static const aplicarTodo = 'Aplicar todo en orden';
  static const descartar = 'Descartar';
  static const descartarConMotivo = 'Descartar y dejar el motivo';
  static const aplicando = 'Aplicando…';
  static const enCursoAplicarTodo = 'Aplicando en orden…';

  static const motivoDelDescarte = 'Motivo del descarte';
  static const motivoDelDescarteAyuda =
      'Obligatorio, al menos $motivoMinimoDelDescarte caracteres. Queda escrito '
      'con tu nombre y la hora; el apunte no se borra.';
  static const descartarTitulo = 'Descartar este apunte';
  static const descartarExplica =
      'No se aplicará. Se queda en la bandeja como descartado, con tu nombre, '
      'la hora y el motivo, y la persona lo verá.';

  static const sigueEsperando = 'Sigue esperando que alguien decida.';
  static const aplicandoAhora =
      'Se está aplicando ahora mismo. Espera a que termine y actualiza.';
  static const interrumpido =
      'Se quedó aplicándose y no terminó (interrumpido). Comprueba a mano la '
      'ruta: puede haberse aplicado. No se reintenta solo.';
  static const reintentarInterrumpido = 'Reintentar (ya lo comprobé)';
  static const reintentarTitulo = 'Reintentar un apunte interrumpido';
  static const reintentarExplica =
      'Este apunte se quedó a medias: el servidor no sabe si el reparto '
      'llegó a aplicarlo. La API no distingue un gesto repetido, así que si '
      'ya se aplicó, reintentarlo lo aplicaría DOS VECES.\n\nComprueba a mano '
      'en la ruta que NO se aplicó y entonces confirma.';
  static const reintentarConfirma = 'Sí, lo comprobé: reintentar';
  static const reintentarNo = 'No, dejarlo';

  /// Un 502 `reparto_no_disponible`: una caida, NO un rechazo. El apunte sigue
  /// `en_revision`.
  static String repartoNoContesto(String? literal) =>
      'El reparto no contestó; el apunte sigue en revisión, no está rechazado. '
      'Inténtalo de nuevo.${literal == null ? '' : ' ($literal)'}';

  /// Cualquier otro 5xx (p. ej. 500 `no_se_pudo_anotar`): no se sabe si quedo
  /// aplicado.
  static String falloDelServidor(String? literal) =>
      'El servidor falló${literal == null ? '' : ': $literal'}. No se sabe si '
      'se aplicó: comprueba la ruta a mano y actualiza antes de repetir.';

  // --- Confirmar «Aplicar todo en orden» y los apuntes que borran o modifican.
  static const aplicarTodoTitulo = 'Confirma antes de aplicar';
  static String recuento(int total, String porMetodo) =>
      'Vas a aplicar $total ${total == 1 ? 'cambio' : 'cambios'}: $porMetodo. '
      'Se ejecutan con tu autoridad, en orden, y se detiene en el primero que '
      'falle.';
  static const avisoDeBorrados =
      'Hay apuntes que BORRAN. Mira la lista antes de seguir.';
  static const porTipo = 'Qué hace cada grupo';
  static String verLasRutas(int n) =>
      n == 1 ? 'Ver la ruta exacta' : 'Ver las $n rutas exactas';
  static String escribeElNumero(int total) =>
      'Para seguir, escribe $total (el número de cambios).';
  static const numeroDeCambios = 'Número de cambios';
  static String confirmaAplicar(int total) =>
      'Aplicar $total ${total == 1 ? 'cambio' : 'cambios'}';
  static const noAplicarTodo = 'No, dejarlos';
  static const sueltoBorra =
      'Se ejecuta con tu autoridad. Mira bien la ruta antes de seguir.';
  static String sueltoTitulo(String metodo) => 'Aplicar un $metodo';
  static const sueltoConfirma = 'Sí, aplicarlo';
  static const sueltoNo = 'No, dejarlo';

  static const truncada =
      'La bandeja se cortó en las primeras 500 entregas: hay más de las que se '
      'ven. Decide algunas y actualiza para ver el resto.';

  /// «Aplicar todo en orden» se paro.
  static String detenidoEn(String donde, int sinProcesar) =>
      'Aplicar todo se detuvo en $donde. '
      '${sinProcesar == 0 ? 'No quedó nada sin procesar.' : (sinProcesar == 1 ? 'Queda 1 apunte sin procesar.' : 'Quedan $sinProcesar apuntes sin procesar.')}';

  static String aplicadoPor(String? quien, String cuando) =>
      'Aplicado por ${quien ?? 'una persona'}${cuando.isEmpty ? '' : ' el $cuando'}.';
  static String descartadoPor(String? quien, String cuando) =>
      'Descartado por ${quien ?? 'una persona'}${cuando.isEmpty ? '' : ' el $cuando'}.';
}
