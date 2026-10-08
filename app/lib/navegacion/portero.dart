import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../arranque/arranque.dart';
import '../nucleo/identidad/sesion.dart';
import '../nucleo/plataforma.dart';
import '../nucleo/proveedores.dart';
import '../nucleo/sincro/sucursal_del_aparato.dart';
import '../nucleo/registro/registro.dart';
import '../pantallas/acceso/estado/estado_acceso.dart';
import 'estado_navegacion.dart';

/// Las situaciones en las que puede estar alguien delante de la aplicación.
enum EstadoDeAcceso {
  /// Todavía no se sabe: se está mirando lo guardado. Dura lo que tarde una
  /// renovación, o lo que tarde la red en rendirse.
  comprobando,

  /// Hay sesión pero el aparato está VACÍO: se está configurando.
  ///
  /// Entrar la primera vez **es** configurarse el aparato, y eso se ve. No el
  /// Panel en ceros mientras las cosas aparecen por detrás, que es lo que hacía
  /// antes: una pantalla con todo a cero es indistinguible de una sucursal sin
  /// nada que repartir, y el logístico se va al almacén con ella en la mano.
  configurando,

  /// Hay sesión. Al Panel.
  dentro,

  /// No hay sesión, o murió. A la pantalla de acceso.
  fuera,

  /// Hay sesión, pero la API dijo 403 `sin_permiso_reparto`: esta PERSONA no
  /// entra a Reparto. A `/sin-permiso`.
  ///
  /// NO es `fuera`: la sesión sigue viva, la base y la cola de esta persona
  /// siguen abiertas e intactas, y no se sincroniza nada (no está en
  /// [haySesionParaSincronizar]) hasta que alguien entre de nuevo. Ver
  /// `docs/sin-permiso.md`.
  sinPermiso,
}

/// ¿HAY SESIÓN CON LA QUE SINCRONIZAR? Son DOS estados, no uno.
///
/// `configurando` cuenta igual que `dentro`: en los dos hay sesión —se acaba de
/// entrar— y lo único que cambia es que el aparato todavía está vacío. Que es
/// justo cuando más falta hace sincronizar.
///
/// Está aquí, con nombre y probada suelta, porque vivir escrita a mano dentro
/// del cableado (`nucleo/proveedores.dart`) ya costó un fallo que no se veía:
/// con sólo `dentro`, [Portero.configurar] llamaba al ciclo estando en
/// `configurando`, el ciclo cortaba en su guarda de «sin sesión no se intenta
/// nada» y devolvía «nada que hacer» **sin mandar una sola petición**. La
/// pantalla de «Configurando Reparto» se quedaba en el 0 % para siempre y un
/// aparato nuevo no se podía estrenar. Sin error, sin registro, sin nada que
/// mirar.
bool haySesionParaSincronizar(EstadoDeAcceso estado) =>
    estado == EstadoDeAcceso.dentro || estado == EstadoDeAcceso.configurando;

/// POR DÓNDE VA la configuración inicial, o por qué no se pudo.
class ConfiguracionInicial {
  const ConfiguracionInicial.enMarcha()
    : fallo = null,
      faltoAlgo = false,
      quedoPor = null;

  const ConfiguracionInicial.fallo(Object this.fallo)
    : faltoAlgo = true,
      quedoPor = null;

  /// El aparato quedó a medias: bajó algo, pero no todo.
  ///
  /// [quedoPor] es **el motivo literal del servidor**, tal cual lo escribe
  /// `nucleo/sincro/bajada.dart`: «se llegó al tope de N tandas y el servidor
  /// seguía diciendo que queda más», «no avanzó ni la marca ni el cursor». Se
  /// arrastra hasta la pantalla porque un motivo que nombra lo que se quedó
  /// fuera sirve y «no terminó» no sirve para nada. `null` cuando la bajada vino
  /// entera y lo que falló fue que el aparato siguió vacío.
  const ConfiguracionInicial.aMedias(this.quedoPor)
    : fallo = null,
      faltoAlgo = true;

  /// Lo que lanzó el ciclo, si lanzó algo. `null` cuando va bien, y también
  /// cuando la bajada terminó sin excepción pero dejándose cosas.
  final Object? fallo;

  /// Por qué se quedó a medias la bajada, con las palabras de `bajada.dart`.
  final String? quedoPor;

  /// `true` cuando hay que decir que faltó y ofrecer reintentar. **No se entra
  /// fingiendo que está.**
  final bool faltoAlgo;
}

/// EL PORTERO. Sin sesión, a la pantalla de acceso; con sesión, al Panel.
///
/// Es un `ChangeNotifier` porque es lo que `GoRouter` sabe escuchar
/// (`refreshListenable`): al cambiar el estado, el enrutador vuelve a pasar por
/// `redirigir` y la persona aterriza donde toca **sin que ninguna pantalla tenga
/// que llamar a `context.go`**.
///
/// ## La regla de Jose, que manda
///
/// > Para entrar hace falta conexión. Una vez dentro, no.
///
/// Al arrancar **sin red y con sesión guardada SE ENTRA** ([Arranque.
/// dentroSinComprobar]). Mandar a esa persona al acceso sería mandarla a una
/// pantalla que sin servidor tampoco funciona, con el trabajo del día dentro del
/// teléfono. Sólo un 401 mata la sesión; un fallo de red la conserva
/// (`docs/identidad.md`, regla 3).
class Portero extends ChangeNotifier {
  Portero(this._ref);

  final Ref _ref;

  EstadoDeAcceso get estado => _estado;
  EstadoDeAcceso _estado = EstadoDeAcceso.comprobando;

  /// Quién entró. Sale del token guardado, así que se sabe sin red.
  Sesion? get sesion => _sesion;
  Sesion? _sesion;

  /// `true` cuando se entró con lo guardado sin poder comprobarlo por falta de
  /// red. No cambia lo que se puede hacer: se dice para poder pintarlo.
  bool get sinComprobar => _sinComprobar;
  bool _sinComprobar = false;

  /// **El aparato tiene datos y aun así no hay sesión.** Lo pinta la pantalla de
  /// acceso: no es «entra», es «tu sesión se perdió y hace falta señal».
  bool get sesionPerdida => _sesionPerdida;
  bool _sesionPerdida = false;

  /// Por dónde va la configuración inicial. `null` cuando no hay ninguna.
  ConfiguracionInicial? get configuracion => _configuracion;
  ConfiguracionInicial? _configuracion;

  /// Lo que hace la aplicación al abrirse: lee la sesión, abre la base de quien
  /// entró e intenta RENOVAR. No se comprueba el token de acceso por su
  /// cuenta — dura quince minutos, así que casi siempre estará caducado al
  /// abrir, y eso no significa que la sesión haya muerto.
  Future<void> comprobar() async {
    final ResultadoDelArranque resultado;
    try {
      resultado = await arrancar(_ref);
    } on Object catch (e, pila) {
      // Un arranque que revienta NO puede dejar la aplicación en la pantalla de
      // esperar para siempre. Se va al acceso, que es la única pantalla que
      // funciona sin nada montado.
      Registro.fallo('el arranque falló: $e', e, pila);
      _sesionPerdida = false;
      _poner(EstadoDeAcceso.fuera);
      return;
    }

    _sesion = resultado.sesion;
    _sesionPerdida = resultado.sesionPerdida;
    switch (resultado.como) {
      case Arranque.fuera:
        _poner(EstadoDeAcceso.fuera);
      case Arranque.dentro:
        await _entrar(sinComprobar: false);
      case Arranque.dentroSinComprobar:
        // SIN RED Y CON DATOS: se entra y ya. Sin red no hay configuración que
        // hacer, y quedarse en la pantalla de «Configurando Reparto» esperando
        // a una señal que no hay es dejar a alguien mirando una barra que no se
        // mueve con su día dentro del aparato.
        await _entrar(sinComprobar: true);
      case Arranque.sinPermiso:
        _poner(EstadoDeAcceso.sinPermiso);
    }
  }

  /// La API dijo que esta persona no entra a Reparto (403 `sin_permiso_reparto`).
  ///
  /// **No toca nada más**: ni la sesión, ni la base, ni la cola. Pausa el envío
  /// por el mismo camino que el 401 —sin sesión «sincronizable» el ciclo no
  /// intenta nada— pero conservando todo, porque un apunte sin subir no es
  /// culpa del apunte. Idempotente: se llama una vez por cada petición que lo ve.
  ///
  /// **Estando `fuera` se ignora**: un 403 tardío de una petición que iba en vuelo
  /// cuando se hizo [salir] o [murio] no puede resucitar la pantalla de «no
  /// tienes permiso» (sin sesión no hay permiso que negar: toca el acceso).
  /// [comprobar] con `Arranque.sinPermiso` no pasa por aquí.
  void sinPermiso() {
    if (_estado == EstadoDeAcceso.fuera) return;
    _poner(EstadoDeAcceso.sinPermiso);
  }

  /// Acaba de entrar con usuario y contraseña. El par ya está guardado.
  Future<void> entro(Sesion sesion) async {
    _sesion = sesion;
    _sesionPerdida = false;
    // LA BASE DE ESTA PERSONA, antes de mirar si tiene datos. Si no, lo que se
    // miraría es la base neutra —la de antes de que entrara nadie— y siempre
    // saldría vacía.
    _ref.read(duenoDeLaBaseProvider.notifier).es(sesion.sub);
    await _entrar(sinComprobar: false);
  }

  /// La sesión murió (un 401 que sigue siendo 401 después de renovar). Es lo
  /// único que echa a nadie fuera.
  void murio() {
    _sesion = null;
    _configuracion = null;
    // Lo de esa persona se queda en SU fichero, entero. Cuando vuelva a entrar
    // lo encuentra.
    _ref.read(duenoDeLaBaseProvider.notifier).es(null);
    _poner(EstadoDeAcceso.fuera);
  }

  /// Salir a mano. Revoca en auth si hay red, borra el par y **cambia de copia**.
  ///
  /// ## Ya NO se borra lo local, y es a propósito
  ///
  /// Antes salir llamaba a `borrarTodoLoDelDominio()`, que borraba el dominio y
  /// **dejaba la cola**. Con una sola base por aparato eso significaba que los
  /// apuntes sin subir de quien se iba esperaban a que entrara otro para salir
  /// con SU token: el trabajo de una sucursal subiendo como si fuera de otra.
  ///
  /// Ahora cada persona tiene su base y su cola (`conexion/nombre.dart`). Salir
  /// cambia de copia: lo de quien se va se queda entero en su fichero y quien
  /// vuelve lo encuentra, sin rebajarse sus ocho mil clientes otra vez por la
  /// conexión de allá. Borrar los datos de alguien pasa a ser un gesto aparte y
  /// explícito —olvidar a esa persona—, que avisa si tiene trabajo sin subir.
  Future<void> salir() async {
    final quien = _sesion;
    _sesion = null;
    _configuracion = null;
    _sesionPerdida = false;
    _poner(EstadoDeAcceso.fuera);
    try {
      await _ref.read(servicioAccesoProvider).salir(quien);
    } on Object catch (e) {
      Registro.aviso('salida con incidencias: $e');
    }
    _ref.read(duenoDeLaBaseProvider.notifier).es(null);
  }

  /// Entrar de verdad: o al Panel, o a configurar el aparato primero.
  ///
  /// **Si el aparato ya tiene los datos, arranca directo**, sin pantalla de
  /// espera y sin esperar a la red: el ciclo sale por detrás como siempre. Si
  /// está vacío, la pantalla de configuración manda hasta que termine.
  ///
  /// ## En web NO se configura nada, y por eso no se ve — 15/09/2026
  ///
  /// «Configurando Reparto» existe para dejar el aparato listo para un día
  /// entero sin señal: es una promesa que hay que cumplir ANTES de que alguien
  /// se vaya al patio de un almacén, y por eso se espera con la pantalla
  /// delante. Quien abre un navegador no se va a ningún sitio y no se le puede
  /// caer la conexión encima del hombro: la primera carga es la misma bajada,
  /// pero por detrás, y se entra directo.
  ///
  /// Y no se queda nadie mirando una pantalla en blanco: **las siete pantallas
  /// ya saben decir que todavía no se han descargado** (`SinDescargar`, caso
  /// S7), que es exactamente lo que hace falta mientras la primera bajada llega.
  Future<void> _entrar({required bool sinComprobar}) async {
    // EL NOMBRE, anotado en SU copia. Es lo único que deja que el gesto de
    // olvidar a alguien diga «Yasmani» en vez del `sub` del token, que a quien
    // lo lee no le dice nada (`nucleo/base/personas.dart`).
    await _anotarQuienEs();
    // LO QUE SE ESTABA MIRANDO LA ULTIMA VEZ. Va aqui, con la base de esta
    // persona ya abierta y ANTES de dejar entrar, para que el Panel se pinte
    // directamente con su sucursal y su moneda. Pintarlo primero con «Todas» y
    // corregirlo despues es ensenar durante un segundo «Falta configurar esta
    // sucursal» a quien la tiene completa.
    await _recordarLoElegido();
    // El orden de la condición no es casual: en web se corta ANTES de contar lo
    // que hay, que son dieciocho consultas para decidir algo ya decidido.
    final prepararseParaNoTenerSenal = _ref.read(trabajaSinConexionProvider);
    if (sinComprobar ||
        !prepararseParaNoTenerSenal ||
        !await _elAparatoEstaVacio()) {
      _configuracion = null;
      _poner(EstadoDeAcceso.dentro, sinComprobar: sinComprobar);
      _sincronizar('al entrar');
      return;
    }

    _configuracion = const ConfiguracionInicial.enMarcha();
    _poner(EstadoDeAcceso.configurando);
    await configurar();
  }

  /// LA CONFIGURACIÓN INICIAL: el ciclo entero, esperado, con la pantalla
  /// delante. También es lo que llama el botón de reintentar.
  Future<void> configurar() async {
    _configuracion = const ConfiguracionInicial.enMarcha();
    _poner(EstadoDeAcceso.configurando);

    final resumen = await _ref
        .read(cicloProvider)
        .ahora(motivo: 'configuración inicial', yaSeRenovo: true);

    // El ciclo mismo pudo descubrir que la persona no entra a Reparto: la
    // pantalla de «no tienes permiso» manda, no la de reintentar.
    if (_estado == EstadoDeAcceso.sinPermiso) return;

    if (resumen.fallo != null) {
      _configuracion = ConfiguracionInicial.fallo(resumen.fallo!);
      _poner(EstadoDeAcceso.configurando, forzar: true);
      return;
    }

    // Sin excepción NO es lo mismo que completo. La bajada puede volver sin
    // fallo y con la mitad de los clientes —una tanda truncada que dejó de
    // encadenarse—, y entrar ahí fingiendo que está es exactamente el patrón
    // que más daño hace en este proyecto (`nucleo/sincro/bajada.dart`).
    if (!resumen.bajada.entera || await _elAparatoEstaVacio()) {
      // CON SU MOTIVO. La pantalla lo pintaba como «El servidor no terminó de
      // mandar los datos», que es lo mismo que no decir nada: el motivo de
      // verdad nombra lo que se quedó fuera y es lo único que deja saber si
      // vale la pena volver a darle o hay que llamar a alguien.
      _configuracion = ConfiguracionInicial.aMedias(resumen.bajada.quedoPor);
      _poner(EstadoDeAcceso.configurando, forzar: true);
      return;
    }

    _configuracion = null;
    _poner(EstadoDeAcceso.dentro);
  }

  /// La sucursal y la moneda de la ultima vez. Ninguna de las dos puede impedir
  /// entrar: si no se pueden leer, se entra con lo de siempre.
  Future<void> _recordarLoElegido() async {
    await _ref.read(sucursalMiradaProvider.notifier).restaurar();
    await _ref.read(monedaMiradaProvider.notifier).restaurar();
    // La del APARATO, que no es la que se mira: sin ella, quien ve las ocho no
    // puede subir nada de lo que hizo sin señal. Ver
    // `ClaveDePreferencia.sucursalDelAparato`.
    await _ref.read(sucursalDelAparatoProvider.notifier).restaurar();
  }

  Future<void> _anotarQuienEs() async {
    final quien = _sesion;
    if (quien == null || quien.nombre.isEmpty) return;
    try {
      await _ref.read(baseProvider).anotarNombreDelDueno(quien.nombre);
    } on Object catch (e) {
      // Un nombre que no se pudo anotar no puede impedir entrar: lo peor que
      // pasa es que su copia salga como «Una cuenta anterior».
      Registro.aviso('no se pudo anotar el nombre del dueño: $e');
    }
  }

  /// ¿Está el aparato sin configurar? La respuesta sale de LA BASE, no de lo que
  /// contestó el servidor (`nucleo/sincro/recuento.dart`).
  ///
  /// AQUÍ SE PREGUNTA SI ESTÁ VIRGEN, **no si está completo**, y la diferencia
  /// costó un intento.
  ///
  /// Se probó a exigir además que no faltara ninguna imprescindible
  /// (`Faltas.de`, que cuenta como falta una colección bajada y a cero filas).
  /// Eso deja **encerrada para siempre** a una sucursal que de verdad no tiene
  /// almacenes todavía: nunca saldría de «Configurando Reparto», con la barra
  /// quieta y sin nada que pueda hacer. Lo cazó `widget_test`.
  ///
  /// Que falte algo se dice **dentro**, en el paso a paso del Panel y en el
  /// aviso de la bajada, que para eso están. Dejar a alguien fuera de la
  /// aplicación es una respuesta peor que dejarle entrar avisado.
  Future<bool> _elAparatoEstaVacio() async {
    try {
      return (await _ref.read(recontadorProvider).ahora()).vaATraerTodo;
    } on Object catch (e) {
      // Si no se puede ni contar, se entra: dejar a alguien fuera del Panel
      // porque una consulta falló es peor que enseñarle el Panel.
      Registro.aviso('no se pudo contar lo que hay en el aparato: $e');
      return false;
    }
  }

  /// EL CICLO DEL DÍA, en cuanto se entra: renovar → subir → bajar.
  ///
  /// **Y no sólo la bajada**, que es lo que había antes. Quien abre la
  /// aplicación por la mañana puede traer la cola de ayer sin subir —cerró el
  /// día en el patio del almacén y se fue a su casa—, y esa cola tiene que salir
  /// antes de que la bajada le ponga encima la foto del servidor.
  ///
  /// **En segundo plano**: la pantalla no espera a que acabe, porque con la
  /// conexión de allá eso es un minuto mirando un giro, y lo que hay que ver es
  /// el Panel. Que falle no echa a nadie fuera ni borra nada: lo que ya estaba
  /// bajado sigue en la base, la cola sigue entera y la franja de estado dirá de
  /// cuándo son los datos.
  ///
  /// La primera vez es al revés y por eso no pasa por aquí: ahí no hay Panel que
  /// enseñar, sólo ceros, y lo que se ve es [EstadoDeAcceso.configurando].
  ///
  /// `yaSeRenovo` porque los dos caminos que llegan aquí traen el par recién
  /// hecho: el arranque acaba de renovar y la pantalla de acceso acaba de
  /// recibirlo de `POST /token`. Renovar otra vez dos dedos después es una ida y
  /// vuelta regalada por la conexión de allá.
  void _sincronizar(String motivo) =>
      _ref.read(cicloProvider).ahora(motivo: motivo, yaSeRenovo: true).ignore();

  void _poner(
    EstadoDeAcceso nuevo, {
    bool sinComprobar = false,
    bool forzar = false,
  }) {
    if (!forzar && _estado == nuevo && _sinComprobar == sinComprobar) return;
    // Del «no tienes permiso» no se sale a trabajar solo: ni `dentro` ni
    // `configurando` (un ciclo que acaba tarde), y TAMPOCO con [entro]: se traga
    // en silencio, por diseño. Solo se sale SALIENDO ([salir], y luego entrar
    // desde el acceso) o recargando la página en la web.
    if (_estado == EstadoDeAcceso.sinPermiso &&
        (nuevo == EstadoDeAcceso.dentro ||
            nuevo == EstadoDeAcceso.configurando)) {
      return;
    }
    _estado = nuevo;
    _sinComprobar = sinComprobar;
    notifyListeners();
  }
}

final porteroProvider = Provider<Portero>((ref) {
  final portero = Portero(ref);
  ref.onDispose(portero.dispose);
  return portero;
});

/// La ruta de la pantalla de acceso. Vive aquí y no en su `registro.dart` para
/// que el portero no tenga que importar la pantalla.
const rutaDeAcceso = '/acceso';

/// La pantalla de esperar mientras se comprueba lo guardado.
///
/// Existe para que no se vea la pantalla de acceso durante un segundo antes de
/// entrar: quien tiene sesión guardada no tiene por qué ver nunca un formulario
/// de contraseña, y ese parpadeo enseña a escribir la contraseña por reflejo.
const rutaDeArranque = '/arranque';

/// «Configurando Reparto». La primera vez, y sólo la primera.
const rutaDeConfiguracion = '/configurando';

/// «No tienes permiso para entrar a Reparto». Se llega a ella desde CUALQUIER
/// pantalla en cuanto la API dice 403 `sin_permiso_reparto`.
const rutaDeSinPermiso = '/sin-permiso';

/// EL REDIRECTOR. Una sola funcion, sin estado, para poder probarla suelta.
///
/// **Se acuerda de a donde iba.** Quien recarga `/orders?municipio=Centro` pasa
/// por la espera del arranque y tiene que acabar ahi, no en el Panel: los
/// filtros viajan en la URL justamente para poder mandar la lista filtrada por
/// enlace, y un portero que aterriza siempre en el Panel se come el enlace.
/// Visto en el navegador el 15/09/2026.
String? redirigir({
  required String rutaActual,
  required EstadoDeAcceso estado,
  required String inicio,
  String uriEntera = '',
  String? volverA,
}) {
  final enLaPuerta =
      rutaActual == rutaDeAcceso ||
      rutaActual == rutaDeArranque ||
      rutaActual == rutaDeConfiguracion ||
      rutaActual == rutaDeSinPermiso;

  switch (estado) {
    case EstadoDeAcceso.comprobando:
      if (rutaActual == rutaDeArranque) return null;
      return '$rutaDeArranque${_conDestino(uriEntera)}';

    case EstadoDeAcceso.configurando:
      // Mientras se configura no se entra a ninguna pantalla, ni siquiera
      // escribiendo la dirección: todas dirían «no se ha descargado todavía» y
      // el Panel saldría en ceros, que es justo lo que esto viene a quitar. El
      // destino se sigue arrastrando para aterrizar ahí al terminar.
      if (rutaActual == rutaDeConfiguracion) return null;
      return '$rutaDeConfiguracion${_conDestino(uriEntera)}';

    case EstadoDeAcceso.fuera:
      // Lo que se guarda es a donde iba, no la puerta por la que pasa: si no,
      // al entrar volveria a la pantalla de acceso.
      final destino = enLaPuerta ? volverA : uriEntera;
      if (rutaActual == rutaDeAcceso) return null;
      return '$rutaDeAcceso${_conDestino(destino ?? '')}';

    case EstadoDeAcceso.sinPermiso:
      // A su pantalla desde donde sea, sin arrastrar destino: al volver a
      // entrar se empieza por el inicio, no por la pantalla que dio el 403.
      return rutaActual == rutaDeSinPermiso ? null : rutaDeSinPermiso;

    case EstadoDeAcceso.dentro:
      if (!enLaPuerta) return null;
      final destino = volverA;
      if (destino == null || destino.isEmpty) return inicio;
      // Un destino que sea la propia puerta seria un bucle.
      final soloRuta = Uri.tryParse(destino)?.path ?? destino;
      if (soloRuta == rutaDeAcceso ||
          soloRuta == rutaDeArranque ||
          soloRuta == rutaDeConfiguracion ||
          soloRuta == rutaDeSinPermiso) {
        return inicio;
      }
      return destino;
  }
}

String _conDestino(String uri) {
  if (uri.isEmpty || uri == '/') return '';
  final soloRuta = Uri.tryParse(uri)?.path ?? uri;
  if (soloRuta == rutaDeAcceso ||
      soloRuta == rutaDeArranque ||
      soloRuta == rutaDeConfiguracion ||
      soloRuta == rutaDeSinPermiso) {
    return '';
  }
  return '?$claveDelDestino=${Uri.encodeQueryComponent(uri)}';
}

/// El nombre del parametro donde viaja «a donde iba».
const claveDelDestino = 'volverA';

/// Lo que consume `rutas.dart`.
String? porteroDeRutas(GoRouterState estado, Portero portero, String inicio) =>
    redirigir(
      rutaActual: estado.matchedLocation,
      estado: portero.estado,
      inicio: inicio,
      uriEntera: estado.uri.toString(),
      volverA: estado.uri.queryParameters[claveDelDestino],
    );
