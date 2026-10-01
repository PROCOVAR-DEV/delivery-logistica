import '../../../nucleo/plataforma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/copia_bajada.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/registro/registro.dart';
import 'package:reparto/nucleo/refresco_en_vivo.dart';

import '../datos/repositorio_vehiculos.dart';
import '../datos/vehiculo_api.dart';

final repositorioVehiculosProvider = Provider<RepositorioVehiculos>(
  (ref) => RepositorioVehiculos(ref.watch(clienteApiProvider)),
);

/// La flota. Es una peticion y no un stream sobre la base **porque aqui no hay
/// base**: lo que se ve es lo que hay en el servidor ahora mismo, o no se ve.
///
/// Y por eso mismo **el ciclo de sincronizacion no la repinta**: el ciclo escribe
/// en la base, y aqui no se lee de la base. Hasta el 17/09/2026 lo unico que
/// actualizaba esta pantalla era salir de ella y volver a entrar, aunque el aviso
/// en vivo del servidor estuviera llegando. El mismo fallo del Tablero, en otra
/// pantalla. Ver `nucleo/refresco_en_vivo.dart`.
final vehiculosProvider = FutureProvider.autoDispose<List<VehiculoDeLaApi>>((
  ref,
) {
  // Al cambiar de sucursal en la barra se vuelve a pedir: el alcance lo
  // resuelve el servidor con la cabecera `x-sucursal-id`.
  ref.watch(sucursalMiradaProvider);
  refrescarConElAviso(ref, const [CambioEnVivo.vehiculos]);
  return ref.watch(repositorioVehiculosProvider).listar();
});

/// La moneda y el costo por km. Escucha DOS tipos porque la pantalla enseña las
/// dos cosas: los tipos de vehiculo con su costo (`vehiculos`) y la tasa con la
/// que se convierten los importes (`ajustes`).
final ajustesVehiculosProvider = FutureProvider.autoDispose<AjustesDeLaApi>((
  ref,
) {
  refrescarConElAviso(ref, const [
    CambioEnVivo.ajustes,
    CambioEnVivo.vehiculos,
  ]);
  return ref.watch(repositorioVehiculosProvider).ajustes();
});

/// LO QUE EL APARATO TIENE BAJADO de la flota.
///
/// Esta pantalla vive de la red y no de la base, pero la base **si** tiene una
/// copia de `vehicles`: la deja la bajada del dia, y de ella comen el asistente
/// de rutas y el tablero. Sin conexion eso es lo unico que hay, y decirlo separa
/// las dos situaciones que hoy se ven iguales:
///
///  * el aparato bajo la flota y no hay red → se sigue pudiendo armar la ruta
///    con lo que hay dentro;
///  * el aparato **no la ha bajado nunca** → no se arregla dando de alta un
///    camion, se arregla trayendo el dia.
final flotaEnElAparatoProvider = StreamProvider<CopiaBajada>(
  (ref) => copiaBajada(
    ref.watch(baseProvider),
    coleccion: Colecciones.vehiculos,
    tabla: ref.watch(baseProvider).vehicles,
  ),
);

/// La busqueda de la cabecera. Filtra **en el cliente** por nombre y placa.
final busquedaVehiculosProvider = NotifierProvider<BusquedaVehiculos, String>(
  BusquedaVehiculos.new,
);

class BusquedaVehiculos extends Notifier<String> {
  @override
  String build() => '';

  void poner(String texto) => state = texto;
}

/// Cuantos por pagina: 25 por defecto, cambiable a 50 o 100 (§5).
final porPaginaVehiculosProvider = NotifierProvider<PorPaginaVehiculos, int>(
  PorPaginaVehiculos.new,
);

class PorPaginaVehiculos extends Notifier<int> {
  @override
  int build() => 25;

  void poner(int cuantos) => state = cuantos;
}

final paginaVehiculosProvider = NotifierProvider<PaginaVehiculos, int>(
  PaginaVehiculos.new,
);

class PaginaVehiculos extends Notifier<int> {
  @override
  int build() => 1;

  void poner(int pagina) => state = pagina;
}

/// EL FILTRO DE «QUE HAY LIBRE Y QUE NO» — 28/09/2026.
///
/// Jose pidio «saber de la flota»: de un vistazo, que hay libre y que no. Eso son
/// dos piezas —unos contadores que se leen sin tocar nada, y poder quedarse con
/// un grupo— y esta es la segunda.
///
/// `null` es «todos», que es como se entra. **No se recuerda entre visitas** a
/// proposito: un filtro pegado es como se llega a «no hay ningun camion» delante
/// de una flota entera, que es el mismo fallo que el aviso del tablero que sale
/// siempre y deja de leerse.
final filtroAndarProvider = NotifierProvider<FiltroAndar, AndarDelCamion?>(
  FiltroAndar.new,
);

class FiltroAndar extends Notifier<AndarDelCamion?> {
  @override
  AndarDelCamion? build() => null;

  /// Tocar el grupo que ya esta puesto lo quita: el mismo gesto entra y sale, y
  /// asi no hace falta un boton de «quitar filtro» que nadie encuentra.
  void alternar(AndarDelCamion cual) => state = state == cual ? null : cual;
}

/// El resultado de una accion de escritura, para pintarlo.
class AvisoVehiculos {
  const AvisoVehiculos(this.texto, {required this.esFallo});

  /// Literal NUEVO (no existe en la de Next): la de Next nunca se queda sin
  /// red porque vive en un navegador con el servidor al lado. Dice dos cosas y
  /// las dos importan: que no hubo red y, sobre todo, **que no se guardo nada**.
  /// EL MISMO FALLO, DOS TEXTOS, PORQUE NO SE ARREGLA IGUAL — 17/09/2026.
  ///
  /// En el aparato «inténtalo otra vez cuando haya red» es lo que hay que
  /// hacer: se está en el patio de un almacén y la red vuelve sola.
  ///
  /// En la web no. Si la página cargó, conexión hay; el que no contesta es el
  /// servidor, y mandar a mirar la señal a quien está sentado en la oficina es
  /// mandarlo a mirar donde no es. Es el mismo razonamiento de
  /// `TextosDeCaida.queHacer`, que ya lo tenía resuelto para la puerta.
  ///
  /// Lo que NO cambia en ninguno de los dos, y es la mitad que importa:
  /// **que no se guardó nada**.
  factory AvisoVehiculos.sinConexion() => AvisoVehiculos(
    Destino.trabajaSinConexion
        ? 'Sin conexión: no se guardó nada. Los vehículos se configuran con '
              'conexión; inténtalo otra vez cuando haya red.'
        : 'Sin conexión con el servidor: no se guardó nada. La página cargó, '
              'así que conexión hay: el que no contesta es el servidor. Prueba '
              'otra vez y, si sigue igual, avisa a la oficina.',
    esFallo: true,
  );

  final String texto;
  final bool esFallo;
}

/// Las escrituras de la pantalla.
///
/// **Aqui no hay `ColaDeSalida` y no la puede haber.** Si una accion no sale,
/// no se guarda en ningun sitio y se dice. Fingir que se guardo es lo unico que
/// esta prohibido: alguien daria por hecho que el camion nuevo esta dado de
/// alta y manana la ruta no se puede armar.
class ControlVehiculos extends Notifier<AvisoVehiculos?> {
  @override
  AvisoVehiculos? build() => null;

  void limpiar() => state = null;

  /// LO QUE YA VA DE CAMINO, por acción.
  ///
  /// UN SOLO CLIC MANDABA DOS BORRADOS — 01/10/2026.
  ///
  /// Medido en producción con el navegador delante: un espía de ratón
  /// certificó **un** `pointerdown`, **un** `pointerup` y **un** `click`, y el
  /// registro de red enseñó DOS `DELETE /api/vehicles/<id>` a 113 ms uno del
  /// otro. El primero contestó `200 {"success":true}` y el segundo `404
  /// {"error":"Not found"}`, porque el camión ya no estaba: lo había borrado el
  /// primero.
  ///
  /// No era el reintento de `ClienteApi._conReintento` —ése espera 1 s, 4 s y
  /// 10 s y sólo reintenta un `FalloDeRed`, nunca un `Rechazo`—: las dos
  /// peticiones **se solapan**, o sea que el manejador entró dos veces. En un
  /// `widget test` no pasa (un `tester.tap` da un `onPressed` y una sola
  /// petición): el gesto se duplica en el navegador, que es donde el mismo clic
  /// llega por dos caminos —los eventos de puntero y el nodo de accesibilidad
  /// del botón—, y eso desde aquí no se arregla.
  ///
  /// Lo que SÍ se arregla aquí, y es la causa de que se notara: **nada impedía
  /// que la misma acción se ejecutara dos veces a la vez.** Ninguna de las seis
  /// escrituras de esta clase tenía guarda de «ya voy»; el `_guardando` de la
  /// pantalla sólo apaga el `Guardar` de los dos cajones, y los tres botones de
  /// la tarjeta —Eliminar, Marcar disponible, Usar para domicilio— no tenían
  /// nada. Con dos borrados a la vez el segundo recibe el «no» del servidor
  /// sobre un borrado que SÍ funcionó, y por el §4 ese «no» se pinta LITERAL:
  /// una franja roja a todo lo ancho que dice «Not found», en inglés
  /// (`httpx.MsgNotFound`), encima de una operación correcta. El §4 hizo lo
  /// suyo; lo que estaba mal es que hubiera un rechazo que no debía existir.
  ///
  /// La guarda es **por acción concreta** y no una sola para toda la pantalla, a
  /// propósito: con una global, borrar el camión A y acto seguido el B dejaría
  /// el B tirado sin decir nada, que es el descarte en silencio que el §4
  /// prohíbe. Y al segundo que llega no se le contesta `false` —eso cerraría mal
  /// el cajón o pintaría un fallo que no hubo—: **se le devuelve el mismo
  /// `Future`**, así que los dos ven el mismo resultado y la pantalla se
  /// comporta como lo que de verdad hubo, un gesto.
  ///
  /// Y es «mientras va», no «una sola vez en la vida»: en cuanto la primera
  /// termina la llave se suelta, así que reintentar a mano tras un fallo de red
  /// sigue saliendo.
  final Map<String, Future<bool>> _enVuelo = <String, Future<bool>>{};

  Future<bool> crear(DatosVehiculo datos) =>
      // Sin id todavía, así que la llave es la acción: es justo lo que hace
      // falta para que un doble `Guardar` no dé de alta el camión dos veces.
      _hacer('crear', () => _repositorio.crear(datos), 'Vehículo agregado.');

  Future<bool> editar(String id, DatosVehiculo datos) => _hacer(
    'editar:$id',
    () => _repositorio.editar(id, datos),
    'Vehículo actualizado.',
  );

  Future<bool> eliminar(String id) => _hacer(
    'eliminar:$id',
    () => _repositorio.eliminar(id),
    'Vehículo eliminado.',
  );

  Future<bool> marcarDisponible(String id) => _hacer(
    'disponible:$id',
    () => _repositorio.marcarDisponible(id),
    'Vehículo marcado como disponible.',
  );

  Future<bool> usarParaDomicilio(String id) => _hacer(
    'domicilio:$id',
    () => _repositorio.usarParaDomicilio(id),
    'Se usará este vehículo para calcular el domicilio.',
  );

  Future<bool> guardarTipos(List<TipoDeVehiculo> tipos) => _hacer(
    'tipos',
    () => _repositorio.guardarTipos(tipos),
    'Tipos guardados.',
  );

  RepositorioVehiculos get _repositorio =>
      ref.read(repositorioVehiculosProvider);

  /// La puerta de las seis escrituras: una sola de cada [clave] a la vez.
  Future<bool> _hacer(
    String clave,
    Future<void> Function() accion,
    String exito,
  ) {
    final yaVa = _enVuelo[clave];
    if (yaVa != null) return yaVa;
    final vuelo = _mandar(accion, exito);
    _enVuelo[clave] = vuelo;
    // Se suelta en cuanto termina, salga bien o mal. `whenComplete` y no un
    // `finally` dentro de `_mandar`: la llave la pone esta puerta, así que la
    // quita esta puerta.
    vuelo.whenComplete(() {
      if (_enVuelo[clave] == vuelo) _enVuelo.remove(clave);
    });
    return vuelo;
  }

  Future<bool> _mandar(Future<void> Function() accion, String exito) async {
    state = null;
    try {
      await accion();
    } on FalloDeRed {
      // Red caida, tiempo agotado o 5xx: la peticion NO llego. No se encola, no
      // se escribe en local, no se dice que se guardo.
      state = AvisoVehiculos.sinConexion();
      return false;
    } on Rechazo catch (e) {
      // El servidor entendio y dijo que no. Su mensaje se ensena LITERAL, en
      // espanol, sin envolver en «Ha ocurrido un error».
      state = AvisoVehiculos(e.mensaje, esFallo: true);
      return false;
    } on SesionMuerta catch (e) {
      state = AvisoVehiculos(e.mensaje, esFallo: true);
      return false;
    } on Object catch (e, pila) {
      // Y LO QUE NO ES NINGUNO DE LOS TRES.
      //
      // Los tres `on` de arriba son los fallos que se saben nombrar. Cualquier
      // otra cosa —una respuesta con la forma cambiada, un `FormatException`,
      // un `TypeError` de un campo que llego `null`— se escapaba entera, y
      // `state` se habia puesto a `null` al empezar: o sea que la pantalla
      // volvia al estado de calma y **no salia ni un cartel**. Se pulsa
      // Guardar, no pasa nada, y no hay forma de saber si se guardo.
      //
      // Es el §4 de la casa: si algo falla, la pantalla no se queda verde. Aqui
      // no se pierde trabajo —Vehiculos no tiene cola y no finge que guarda—,
      // pero un gesto mudo acaba en el camion dado de alta dos veces.
      Registro.fallo('vehículos: la acción falló sin motivo conocido', e, pila);
      state = AvisoVehiculos(
        'No se pudo guardar y no se sabe por qué: el servidor contestó algo '
        'que esta pantalla no entiende. NO se guardó nada. Vuelve a '
        'intentarlo y, si sigue igual, avisa a la oficina.',
        esFallo: true,
      );
      return false;
    }
    // Sólo se refresca cuando de verdad se aplico.
    ref.invalidate(vehiculosProvider);
    ref.invalidate(ajustesVehiculosProvider);
    state = AvisoVehiculos(exito, esFallo: false);
    return true;
  }
}

final controlVehiculosProvider =
    NotifierProvider<ControlVehiculos, AvisoVehiculos?>(ControlVehiculos.new);
