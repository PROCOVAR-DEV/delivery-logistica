import 'dart:async';

import '../red/eventos_io.dart' show esperaDeReintento;
import '../red/fallos.dart';
import '../registro/registro.dart';
import 'entrega_a_revision.dart' show RechazoConEspera;
import 'flujo_de_revision.dart';

/// Lo que hace falta para abrir el flujo: la dirección (con `?aparato=`) y el
/// token de entrega.
typedef CredencialesDelAviso = ({Uri url, String token});

/// La primera espera tras un fallo. Dos segundos y no uno (como el canal de los
/// pedidos): aquí no hay nadie mirando un tablero, y detrás de cada vuelta hay UNA
/// petición a Accesos para otro token, ademas de la del flujo.
const esperaInicialDelAviso = Duration(seconds: 2);

/// El tope: un minuto. Una petición por minuto en el peor caso.
const esperaMaximaDelAviso = Duration(seconds: 60);

/// CUÁNTO TIENE QUE DURAR UNA CONEXIÓN PARA CONTAR COMO BUENA, y reiniciar la
/// espera. Con el `200` solo no basta: un proxy o un servidor que acepta y corta
/// al instante también contesta 200, y sin esto cada vuelta sería «la primera» y
/// la espera nunca crecería (`eventos.dart`, `sueloEntreVolver`, cuenta el mismo
/// caso). El corte normal, a los 10 minutos, sí cuenta: reconecta a los 2 s.
const duracionDeUnaConexionBuena = Duration(seconds: 30);

/// Lo más que se hace caso a un `Retry-After`. Un servidor roto que mandara
/// `86400` dejaría el aviso mudo un día entero, y hay un botón de respaldo.
const topeDelRetryAfter = Duration(minutes: 10);

/// EL AVISO EN VIVO DE LA REVISIÓN, para quien perdió `delivery.entrar`.
///
/// Jose, 09/10/2026, tras probarlo en un móvil real: el administrador aplicó el
/// cambio y el teléfono siguió diciendo «Todavía no se ha aplicado nada» hasta
/// pulsar «Actualizar estados». «Nada de polling: para eso tenemos SSE».
///
/// ## Qué hace
///
/// Mantiene UNA conexión `GET /sync/revision/eventos` abierta mientras la
/// pantalla la necesite. Llama a [alAviso], que vuelve a hacer la consulta de
/// «Actualizar estados», en DOS casos y solo en esos:
///
///  1. cuando el servidor dice `revision` —se decidió un apunte de esta persona—;
///  2. **en cada apertura** (`abierto`, también la primera): el servidor no guarda
///     eventos y no hay `Last-Event-ID`, así que lo decidido mientras el flujo
///     estaba cerrado —el token de entrega caduca cada 10 minutos, o el móvil
///     cambió de antena— solo se sabe preguntando. Es el «se consulta `mias` tras
///     cada (re)conexión» del contrato (`contratos-api.md` §12.3). En
///     `/sin-permiso` nadie más pregunta (el ciclo está parado): sin esto el panel
///     se quedaba en «Todavía no se ha aplicado nada» con el apunte ya aplicado.
///
/// **No hay temporizador que pregunte**: el único reloj de aquí reconecta (o
/// cuenta cuánto llevamos conectados). Una consulta atada a abrir la conexión no
/// es un sondeo —cuesta UNA petición por reconexión, la de cada 10 minutos— y sin
/// conexión abierta y sin evento no se pregunta nada. `sin_permiso_test.dart` lo
/// fija: 10 minutos de panel abierto, ninguna consulta más que la de apertura.
///
/// ## Cuándo vive
///
/// Quien la crea (`escuchaDeRevisionProvider`) decide cuándo: solo con algo
/// `enRevision`, el panel montado, en la APK o el escritorio y en `sinPermiso`.
/// Aquí dentro solo hay [iniciar] y [parar], y [parar] lo suelta TODO.
///
/// ## Qué pasa cuando algo sale mal
///
///  * **El servidor cierra** (cada 10 minutos, al caducar el token de entrega):
///    se pide OTRO token y se reabre. Sin él no hay flujo.
///  * **No se pudo abrir / se cortó la red / 5xx**: espera creciente, 2 s → 60 s.
///  * **401** (token): igual, con espera. NUNCA al instante: un 401 con un token
///    recién firmado no se arregla pidiendo otro en el mismo segundo.
///  * **429**: espera lo que diga `Retry-After` (si es más que la espera creciente),
///    con tope [topeDelRetryAfter]. Es el servidor diciendo «ya tienes demasiados
///    flujos abiertos»: insistir es empeorarlo.
///  * **403 (aparato ajeno), 404 (un servidor que aún no tiene el flujo) y
///    cualquier otro 4xx**: se acaba. Son un «no» que el tiempo no cambia
///    (`eventos_io.dart`: «un reintentador contra un rechazo permanente es un
///    bucle, no una defensa»). Lo mismo si Accesos dice que no hay sesión, que la
///    persona ya tiene permiso o que no tiene sucursal.
///
/// Cuando se acaba, la pantalla no se queda sin nada: el botón «Actualizar
/// estados» sigue ahí y dice por qué si es que falla de verdad.
///
/// ## Lo que NO hace, a propósito
///
/// **No consulta sin `abierto`.** Si el flujo no llega a abrir (sin red, un 401, un
/// 429…) no hay nada que ponerse al día y no se pregunta: ahí vale el botón. Y un
/// servidor que acepta y se muere al instante da un `abierto` por cada vuelta: la
/// espera creciente (2 a 60 s) lo acota a una consulta por vuelta, como mucho una
/// por minuto.
class EscuchaDeRevision {
  EscuchaDeRevision({
    required AbridorDeFlujoDeRevision abrir,
    required Future<CredencialesDelAviso?> Function() credenciales,
    required void Function() alAviso,
    this.esperaInicial = esperaInicialDelAviso,
    this.esperaMaxima = esperaMaximaDelAviso,
    this.conexionBuena = duracionDeUnaConexionBuena,
  }) : _abridor = abrir,
       _credenciales = credenciales,
       _alAviso = alAviso;

  final AbridorDeFlujoDeRevision _abridor;
  final Future<CredencialesDelAviso?> Function() _credenciales;
  final void Function() _alAviso;
  final Duration esperaInicial;
  final Duration esperaMaxima;
  final Duration conexionBuena;

  bool _vivo = false;

  /// Cada intento de abrir tiene su número: lo que se queda esperando un token
  /// cuando se para (o se vuelve a empezar) no puede abrir nada después.
  int _intento = 0;

  /// Vueltas fallidas seguidas: de aquí sale la espera creciente.
  int _fallos = 0;

  StreamSubscription<String>? _flujo;
  Timer? _reintento;
  Timer? _conexionBuena;

  /// ¿Está escuchando o esperando para reconectar? `false` tras [parar] o cuando
  /// se rindió.
  bool get viva => _vivo;

  /// Empieza. Idempotente: llamarla con la escucha en marcha no abre otra.
  void iniciar() {
    if (_vivo) return;
    _vivo = true;
    unawaited(_abrir());
  }

  /// Lo suelta TODO: la conexión, el reintento y el contador de «conexión buena».
  /// Idempotente.
  void parar() {
    _vivo = false;
    _intento++;
    _reintento?.cancel();
    _reintento = null;
    _conexionBuena?.cancel();
    _conexionBuena = null;
    final flujo = _flujo;
    _flujo = null;
    unawaited(flujo?.cancel());
  }

  Future<void> _abrir() async {
    final mio = ++_intento;
    bool sigo() => _vivo && mio == _intento;

    final CredencialesDelAviso? credenciales;
    try {
      // Un token NUEVO en cada apertura: el de la anterior caducó (el servidor
      // corta el flujo a los 10 minutos) o no se llegó a usar.
      credenciales = await _credenciales();
    } on Object catch (e) {
      if (sigo()) _despuesDe(e);
      return;
    }
    if (!sigo()) return;
    if (credenciales == null) {
      _rendirse('el aparato no tiene alta; no hay a quién escuchar');
      return;
    }

    _flujo = _abridor(credenciales.url, credenciales.token).listen(
      (suceso) {
        if (suceso == sucesoAbierto) {
          // PONERSE AL DÍA: lo decidido con el flujo cerrado no avisó a nadie.
          _alAviso();
          _conexionBuena?.cancel();
          _conexionBuena = Timer(conexionBuena, () {
            _conexionBuena = null;
            _fallos = 0;
          });
        } else if (suceso == sucesoRevision) {
          _alAviso();
        }
        // Cualquier otro evento (uno que esta versión no conoce) se ignora: el
        // contrato dice que añadir tipos no rompe a nadie.
      },
      onError: (Object e) {
        _soltarLaConexion();
        _despuesDe(e);
      },
      onDone: () {
        _soltarLaConexion();
        _despuesDe(null);
      },
      cancelOnError: true,
    );
  }

  void _soltarLaConexion() {
    _flujo = null;
    _conexionBuena?.cancel();
    _conexionBuena = null;
  }

  /// Qué hacer con lo que acaba de pasar: reconectar (y cuándo) o rendirse.
  /// [fallo] `null` es el cierre limpio del servidor.
  void _despuesDe(Object? fallo) {
    if (!_vivo) return;
    Duration? pideEsperar;
    switch (fallo) {
      case null:
        break;
      case RechazoDelFlujo(codigo: final c, :final esperar):
        // Sin código (red) y 5xx son del momento; el 401 es un token que se
        // cambia; el 429 trae cuánto esperar. Cualquier otro 4xx es un «no».
        if (c != null && c != 401 && c != 429 && c < 500) {
          _rendirse('el servidor rechaza el flujo ($c)');
          return;
        }
        pideEsperar = esperar;
      case RechazoConEspera(:final segundos):
        pideEsperar = Duration(seconds: segundos);
      case Rechazo(codigo: final c, mensaje: final m):
        // Accesos al pedir el token. Un 429 sin `Retry-After` se espera con la
        // espera creciente; los demás 4xx (sin sucursal, ya tiene permiso…) no
        // los arregla el tiempo.
        if (c != 429) {
          _rendirse('Accesos no da token de entrega ($c $m)');
          return;
        }
      case SesionMuerta():
        _rendirse('no hay sesión');
        return;
      default:
        // La red, o algo que no se entiende: se reintenta con espera.
        break;
    }
    _programar(pideEsperar, fallo);
  }

  void _programar(Duration? pideEsperar, Object? motivo) {
    var espera = esperaDeReintento(
      _fallos,
      inicial: esperaInicial,
      tope: esperaMaxima,
    );
    _fallos++;
    if (pideEsperar != null && pideEsperar > espera) {
      espera = pideEsperar > topeDelRetryAfter ? topeDelRetryAfter : pideEsperar;
    }
    Registro.info(
      'aviso en vivo de revisión: ${motivo ?? "el servidor cerró el flujo"}; '
      'se reabre en ${espera.inMilliseconds} ms',
    );
    _reintento?.cancel();
    _reintento = Timer(espera, () {
      _reintento = null;
      unawaited(_abrir());
    });
  }

  void _rendirse(String motivo) {
    Registro.aviso(
      'aviso en vivo de revisión: $motivo; se queda «Actualizar estados»',
    );
    parar();
  }
}
