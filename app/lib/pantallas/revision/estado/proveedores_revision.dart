import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../navegacion/menu_de_cuenta.dart' show sesionParaElMenuProvider;
import '../../../navegacion/portero.dart' show porteroProvider;
import '../../../nucleo/plataforma.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/red/cliente_api.dart';
import '../../../nucleo/red/entorno.dart';
import '../../../nucleo/red/fallos.dart';
import '../../../nucleo/refresco_en_vivo.dart';
import '../datos/bandeja.dart';
import '../datos/quien_revisa.dart';
import '../datos/repositorio_revision.dart';

/// EL `sync` DE ESTA PANTALLA, segun donde este abierta.
///
///  * **APK y escritorio**: el de siempre (`clienteSyncProvider`), con el par de
///    tokens del aparato y su renovacion.
///  * **Web**: `sync` NO lee la cookie (`DeToken` solo mira `Authorization:
///    Bearer`), pero la web ya tiene el token en la mano: `GET /api/me` lo
///    devuelve en el cuerpo y el portero lo guarda. Va como **Bearer explicito y
///    sin cookie** (`bearerExplicito`, `docs/bandeja-de-revision.md` B.6): ni
///    `withCredentials` ni CSRF. Con la puerta de respaldo (usuario y
///    contrasena en el navegador) el token es el del almacen, que se renueva.
///
/// Decision de Jose, 08/10/2026: la bandeja del revisor tambien en la web. Es un
/// buzon de oficina, no una cola: no guarda nada en el navegador.
final clienteDeRevisionProvider = Provider<ClienteApi>((ref) {
  if (ref.watch(trabajaSinConexionProvider)) {
    return ref.watch(clienteSyncProvider);
  }
  final almacen = ref.watch(almacenSesionProvider);
  // Montado igual que `_cliente` de `proveedores.dart` (que es privado), con la
  // unica diferencia del Bearer.
  return ClienteApi.montar(
    baseUrl: Entorno.syncUrl,
    almacen: almacen,
    renovador: ref.watch(renovadorProvider),
    sucursalMirada: () => ref.read(sucursalMiradaProvider),
    alIntentar: ({required bool llego}) =>
        ref.read(saludDeLaRedProvider.notifier).anotarIntento(llego: llego),
    // SIN `alMorirLaSesion`, a proposito. Un 401 de `sync` en la web no prueba
    // que la sesion web haya muerto (eso lo dicen las llamadas a `/api`), y si
    // fuera un fallo de configuracion del lado de `sync` el portero mandaria a
    // Accesos, Accesos devolveria a la pagina y volveria a pedir: el bucle de
    // los treinta `GET /sync/estado` del 22/09/2026. Aqui el 401 se DICE en la
    // pantalla («La sesion termino…») y no se mueve a nadie.
    alFaltarPermiso: () => ref.read(porteroProvider).sinPermiso(),
    bearerExplicito: () async =>
        (await almacen.leer())?.token ??
        ref.read(porteroProvider).sesion?.token,
  );
});

final repositorioRevisionProvider = Provider<RepositorioRevision>(
  (ref) => RepositorioRevision(ref.watch(clienteDeRevisionProvider)),
);

/// La bandeja, leida del servidor. No hay base local: lo que se ve es lo que el
/// servidor sabe AHORA, o no se ve (mismo criterio que Sincronizacion).
///
/// Sin reintento automatico de Riverpod: un `403` es definitivo y repetirlo es
/// un bucle (lo que paso con el canal del webhook, 26/09/2026). La red ya
/// reintenta dentro de `ClienteApi`. Se vuelve a pedir al volver de una
/// desconexion (`refrescarConElAviso`) y despues de cada decision propia.
final bandejaProvider = FutureProvider.autoDispose<BandejaDelRevisor>((
  ref,
) async {
  refrescarConElAviso(ref, const <String>[]);
  final sucursal = ref.watch(sucursalMiradaProvider);
  return ref.watch(repositorioRevisionProvider).bandeja(sucursal: sucursal);
}, retry: (_, _) => null);

/// Una entrega con sus apuntes; solo se pide cuando se abre.
final detalleDeEntregaProvider = FutureProvider.autoDispose
    .family<EntregaEnRevision, String>(
      (ref, entrega) => ref.watch(repositorioRevisionProvider).detalle(entrega),
      retry: (_, _) => null,
    );

/// DONDE SE PARO «Aplicar todo en orden» y por que.
///
/// Se paro porque un apunte no quedo aplicado (lo de detras puede depender de el).
/// [porque] es el LITERAL del servidor; [sinProcesar] cuantos quedaron sin tocar.
class ParadaDeAplicarTodo {
  const ParadaDeAplicarTodo({
    required this.clave,
    required this.porque,
    required this.sinProcesar,
  });

  /// La clave del apunte donde se paro.
  final String? clave;
  final String? porque;
  final int sinProcesar;
}

/// Lo que esta pasando con las decisiones de ESTA visita a la pantalla.
class DecisionesEnCurso {
  const DecisionesEnCurso({
    this.enCurso = const <String>{},
    this.avisos = const <String, String>{},
    this.paradas = const <String, ParadaDeAplicarTodo>{},
  });

  /// Claves de lo que esta esperando respuesta del servidor ([claveDeApunte],
  /// [claveDeEntrega]).
  final Set<String> enCurso;

  /// Lo que el servidor contesto que NO, con su motivo LITERAL, por clave de
  /// apunte. El apunte sigue esperando decision. (Y lo que no se sabe: «el
  /// reparto no contesto», «sin conexion»: ahi el apunte NO esta rechazado.)
  final Map<String, String> avisos;

  /// Donde se detuvo el ultimo «Aplicar todo en orden», por clave de entrega.
  final Map<String, ParadaDeAplicarTodo> paradas;

  bool ocupado(String clave) => enCurso.contains(clave);
}

/// La clave de un apunte en [DecisionesEnCurso]; `entrega:<id>` para «todo».
String claveDeApunte(ApunteEnRevision a) => '${a.aparato}/${a.clave}';
String claveDeEntrega(EntregaEnRevision e) => 'entrega:${e.id}';

/// LAS DECISIONES DEL REVISOR.
///
/// **Nada se pinta como hecho antes de la respuesta del servidor.** Mientras la
/// peticion vuela, el apunte esta "en curso" (boton apagado, «Aplicando…») y su
/// estado sigue siendo el que el servidor dijo; solo cuando contesta se vuelve a
/// leer la entrega y el estado nuevo sale de ALLI. Un «Aplicado» puesto por
/// adelantado es el 200 OK que no era del 16/09/2026 otra vez.
///
/// Un `Rechazo` (el reparto dijo que no, o el servidor no deja decidir) se guarda
/// con su motivo literal y el apunte **sigue esperando decision**.
class DecisionesDelRevisor extends Notifier<DecisionesEnCurso> {
  @override
  DecisionesEnCurso build() => const DecisionesEnCurso();

  RepositorioRevision get _repo => ref.read(repositorioRevisionProvider);

  /// ¿Puede esta persona decidir sobre esta entrega? Segunda cerradura, detras
  /// de la que esconde los botones.
  Future<bool> _puedeDecidir(EntregaEnRevision entrega) async {
    final quien = await ref.read(sesionParaElMenuProvider.future);
    return porQueNoPuedeDecidir(quien, entrega) == null;
  }

  /// Pone [clave] en curso y olvida los avisos viejos de [limpiar] (y la parada
  /// de la entrega, si es una entrega). Si la pantalla se cerro mientras volaba
  /// la peticion no hay nada que pintar.
  void _empezar(String clave, Iterable<String> limpiar) {
    if (!ref.mounted) return;
    state = DecisionesEnCurso(
      enCurso: {...state.enCurso, clave},
      avisos: {...state.avisos}..removeWhere((k, _) => limpiar.contains(k)),
      paradas: {...state.paradas}..remove(clave),
    );
  }

  void _terminar(
    String clave, {
    Map<String, String> avisos = const {},
    ParadaDeAplicarTodo? parada,
  }) {
    if (!ref.mounted) return;
    state = DecisionesEnCurso(
      enCurso: {...state.enCurso}..remove(clave),
      avisos: {...state.avisos, ...avisos},
      paradas: {...state.paradas, clave: ?parada},
    );
  }

  /// Lo que se le dice a la persona cuando una orden no salio, **con el literal
  /// del servidor**:
  ///
  ///  * `Rechazo` (4xx: 403 no_revisa / es_lo_tuyo / sucursal_ajena, 409
  ///    ya_se_esta_aplicando / ya_decidido, 422 motivo_obligatorio…): su frase.
  ///  * **502** `reparto_no_disponible`: una CAIDA del reparto, no un rechazo. El
  ///    apunte VUELVE a `en_revision`; se dice «el reparto no contesto, intentalo
  ///    de nuevo» y nunca se pinta rechazado.
  ///  * **Otro 5xx** (el 500 `no_se_pudo_anotar`: se aplico en el reparto pero la
  ///    base no lo anoto): no se sabe si quedo aplicado. Se dice, con su literal.
  ///  * **Sin respuesta** (se corto la red): no se sabe si llego la orden.
  String _literal(Object e) => switch (e) {
    FalloDeRed(codigo: 502, :final detalle) =>
      TextosDeRevision.repartoNoContesto(detalle),
    FalloDeRed(codigo: final c?, :final detalle) when c >= 500 =>
      TextosDeRevision.falloDelServidor(detalle),
    FalloDeRed() => TextosDeRevision.sinConexionAlDecidir,
    final FalloApi f => f.mensaje,
    _ => '$e',
  };

  /// Vuelve a leer del servidor como quedo la entrega, **y se espera**: hasta
  /// que no llega la foto nueva el apunte sigue "en curso" (boton apagado). Si
  /// no, durante ese rato la pantalla ensenaria el estado de ANTES con el boton
  /// vivo, que es justo lo contrario de no pintar nada antes de la respuesta.
  Future<void> _releer(EntregaEnRevision entrega) async {
    if (!ref.mounted) return;
    final detalle = detalleDeEntregaProvider(entrega.id);
    ref
      ..invalidate(bandejaProvider)
      ..invalidate(detalle);
    try {
      await ref.read(detalle.future);
    } on Object {
      // Si no se puede releer, lo dice la propia tarjeta (su `detalle.error`).
    }
  }

  /// Aplica un apunte.
  ///
  /// [reintentarInterrumpido] es el reintento de un `aplicando` que se corto a
  /// medias (`interrumpido`): manda la bandera que el servidor exige, y SOLO se
  /// admite sobre un apunte marcado interrumpido. La pantalla lo pide con una
  /// confirmacion que explica que hay que comprobar la ruta a mano.
  Future<void> aplicar(
    EntregaEnRevision entrega,
    ApunteEnRevision a, {
    bool reintentarInterrumpido = false,
  }) async {
    final clave = claveDeApunte(a);
    final seAplica = reintentarInterrumpido
        ? a.estado == EstadoDelApunte.aplicando && a.interrumpido
        : a.estado.esperaDecision;
    if (!seAplica || !await _puedeDecidir(entrega)) return;
    // Mirar si ya esta en curso y ponerlo en curso, SIN `await` en medio: dos
    // pulsaciones seguidas no pueden pasar las dos por la comprobacion.
    if (state.ocupado(clave)) return;
    _empezar(clave, [clave]);
    var avisos = const <String, String>{};
    try {
      final r = await _repo.aplicar(
        a.aparato,
        a.clave,
        reintentarInterrumpido: reintentarInterrumpido,
      );
      avisos = _rechazos(r, entrega);
    } on FalloApi catch (e) {
      avisos = {clave: _literal(e)};
    } finally {
      await _releer(entrega);
      _terminar(clave, avisos: avisos);
    }
  }

  /// «Aplicar todo en orden»: el servidor SE DETIENE en el primer apunte que no
  /// queda aplicado. Aqui se guarda donde, por que y cuantos quedaron.
  Future<void> aplicarTodo(EntregaEnRevision entrega) async {
    final clave = claveDeEntrega(entrega);
    if (!await _puedeDecidir(entrega)) return;
    if (state.ocupado(clave)) return;
    _empezar(clave, [clave, ...entrega.apuntes.map(claveDeApunte)]);
    var avisos = const <String, String>{};
    ParadaDeAplicarTodo? parada;
    try {
      final r = await _repo.aplicarTodo(entrega.id);
      avisos = _rechazos(r, entrega);
      if (r.detenido) {
        parada = ParadaDeAplicarTodo(
          clave: r.detenidoEn,
          porque: r.detenidoPorque,
          sinProcesar: r.sinProcesar,
        );
      }
    } on FalloApi catch (e) {
      avisos = {clave: _literal(e)};
    } finally {
      await _releer(entrega);
      _terminar(clave, avisos: avisos, parada: parada);
    }
  }

  /// De los resultados, los que el reparto rechazo, por clave de apunte.
  Map<String, String> _rechazos(
    RespuestaDeAplicar respuesta,
    EntregaEnRevision entrega,
  ) => {
    for (final r in respuesta.resultados)
      if (r.estado == EstadoDelApunte.rechazado && r.motivo != null)
        '${entrega.aparato}/${r.clave}': r.motivo!,
  };

  /// Descarta CON motivo. Devuelve `null` si el servidor lo acepto, o el motivo
  /// literal de por que no (para que el cajon lo diga y siga abierto).
  Future<String?> descartar(
    EntregaEnRevision entrega,
    ApunteEnRevision a,
    String motivo,
  ) async {
    final clave = claveDeApunte(a);
    if (!await _puedeDecidir(entrega)) return TextosDeRevision.noRevisas;
    if (state.ocupado(clave)) return TextosDeRevision.aplicando;
    _empezar(clave, [clave]);
    try {
      await _repo.descartar(a.aparato, a.clave, motivo);
      return null;
    } on FalloApi catch (e) {
      return _literal(e);
    } finally {
      await _releer(entrega);
      _terminar(clave);
    }
  }
}

final decisionesDelRevisorProvider =
    NotifierProvider.autoDispose<DecisionesDelRevisor, DecisionesEnCurso>(
      DecisionesDelRevisor.new,
    );
