import '../../../nucleo/plataforma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/copia_bajada.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/refresco_en_vivo.dart';

import '../datos/almacen_api.dart';
import '../datos/repositorio_almacenes.dart';

final repositorioAlmacenesProvider = Provider<RepositorioAlmacenes>(
  (ref) => RepositorioAlmacenes(ref.watch(clienteApiProvider)),
);

/// Las sucursales con sus almacenes, tal y como las devuelve Accesos.
///
/// Pide a la red en cada visita, asi que **el ciclo de sincronizacion no la
/// repinta**; y los almacenes son ademas la coleccion que NI SIQUIERA VIAJA en
/// `GET /api/sync/cambios` —salen en `faltan`— sino en una peticion aparte al
/// final del ciclo. Sin el aviso en vivo, dos personas configurando el mismo
/// almacen se pisan sin verse, y el domicilio se cobra por la distancia DESDE
/// ese punto. Ver `nucleo/refresco_en_vivo.dart`.
final almacenesProvider = FutureProvider.autoDispose<List<SucursalDeAccesos>>((
  ref,
) {
  ref.watch(sucursalMiradaProvider);
  refrescarConElAviso(ref, const [CambioEnVivo.almacenes]);
  return ref.watch(repositorioAlmacenesProvider).listar();
});

/// LO QUE EL APARATO TIENE BAJADO de los almacenes.
///
/// Esta pantalla lee y escribe en Accesos, pero la bajada del dia deja ademas
/// una copia de `warehouses` en la base, y de ella salen el punto de partida del
/// asistente de rutas y el origen desde el que se mide el domicilio. Sin red es
/// lo unico que hay, y decirlo separa dos situaciones que hoy se ven iguales:
/// «no se pudo preguntar, pero el aparato tiene la copia del lunes» y «este
/// aparato no ha descargado los almacenes nunca».
final almacenesEnElAparatoProvider = StreamProvider<CopiaBajada>(
  (ref) => copiaBajada(
    ref.watch(baseProvider),
    coleccion: Colecciones.almacenes,
    tabla: ref.watch(baseProvider).warehouses,
  ),
);

/// Que sucursal se esta configurando DENTRO de la pantalla, cuando alguien la
/// ha elegido a mano en el desplegable. `null` = nadie la ha tocado, y entonces
/// manda la barra de arriba ([cualSeConfigura]).
///
/// ## SE OLVIDA AL CAMBIAR DE SUCURSAL ARRIBA — 29/09/2026
///
/// `build()` mira [sucursalMiradaProvider], asi que un cambio en la barra
/// reconstruye esto y devuelve la eleccion a `null`. Sin eso, la segunda mitad
/// del mismo fallo: se elige Camaguey aqui dentro, se cambia la barra a
/// Santiago, y la pantalla se queda en Camaguey — y ahi se edita el punto desde
/// el que se cobra el domicilio de otra provincia.
final sucursalElegidaProvider = NotifierProvider<SucursalElegida, String?>(
  SucursalElegida.new,
);

class SucursalElegida extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(sucursalMiradaProvider);
    return null;
  }

  void poner(String? codigo) => state = codigo;
}

/// CUAL DE LAS SUCURSALES SE CONFIGURA, en orden de quien manda:
///
///  1. la que alguien haya elegido **en el desplegable de la pantalla**;
///  2. la que esté elegida **en la barra de arriba**;
///  3. la primera de la lista, que es lo único que queda cuando la barra dice
///     «Todas» — ahí no hay ninguna respuesta correcta y hace falta enseñar
///     alguna, porque esta pantalla configura una sucursal cada vez.
///
/// El escalón 2 es el que faltaba. `GET /api/almacenes` devuelve **las ocho** a
/// quien ve las ocho, y a propósito (`api/internal/api/almacenes.go`: sin eso el
/// aparato se queda sin copia al cambiar de sucursal), así que «la primera de la
/// lista» no es la de nadie: es la primera que devuelve Accesos. Jose, con
/// Santiago puesto arriba, veía Camagüey.
///
/// Función suelta y sin `ref` para poder probarla sin montar la pantalla.
SucursalDeAccesos? cualSeConfigura(
  List<SucursalDeAccesos> todas, {
  required String? elegidaEnLaPantalla,
  required String? codigoDeLaBarra,
}) {
  if (todas.isEmpty) return null;
  for (final codigo in [elegidaEnLaPantalla, codigoDeLaBarra]) {
    if (codigo == null) continue;
    final suya = todas.where((s) => s.codigo == codigo).firstOrNull;
    if (suya != null) return suya;
  }
  return todas.first;
}

class AvisoAlmacenes {
  const AvisoAlmacenes(this.texto, {required this.esFallo});

  /// Literal NUEVO. Dice lo unico que importa: **no salio del aparato**. El
  /// mensaje bueno, `Guardado en Accesos.`, sólo se puede dar cuando Accesos
  /// contesto; decirlo sin red seria mentir en la pantalla.
  factory AvisoAlmacenes.sinConexion() => AvisoAlmacenes(
    Destino.trabajaSinConexion
        ? 'Sin conexión: no se guardó nada en Accesos. Los almacenes se '
              'configuran con conexión; inténtalo otra vez cuando haya red.'
        : 'Sin conexión con Accesos: no se guardó nada. La página cargó, así '
              'que conexión hay: el que no contesta es Accesos. Prueba otra vez '
              'y, si sigue igual, avisa a la oficina.',
    esFallo: true,
  );

  final String texto;
  final bool esFallo;
}

/// El guardado. Como en Vehiculos: **sin cola y sin base local**. O sale, o se
/// dice que no salio.
class ControlAlmacenes extends Notifier<AvisoAlmacenes?> {
  @override
  AvisoAlmacenes? build() => null;

  void limpiar() => state = null;

  Future<bool> guardar(String codigo, List<AlmacenDeAccesos> almacenes) async {
    state = null;
    try {
      final resultado = await ref
          .read(repositorioAlmacenesProvider)
          .guardar(codigo, almacenes);
      ref.invalidate(almacenesProvider);
      // El aviso de Accesos («N sin coordenadas…») se ensena TAL CUAL y detras
      // de la confirmacion: se guardo, pero hay algo que mirar.
      final aviso = resultado.aviso;
      state = AvisoAlmacenes(
        aviso == null ? 'Guardado en Accesos.' : 'Guardado en Accesos. $aviso',
        esFallo: false,
      );
      return true;
    } on FalloDeRed {
      state = AvisoAlmacenes.sinConexion();
      return false;
    } on Rechazo catch (e) {
      // Los mensajes de Accesos son literales y en espanol: `Accesos no aceptó
      // el cambio: …`, `Sin acceso a esa sucursal`. Se pintan tal cual.
      state = AvisoAlmacenes(e.mensaje, esFallo: true);
      return false;
    } on SesionMuerta catch (e) {
      state = AvisoAlmacenes(e.mensaje, esFallo: true);
      return false;
    }
  }
}

final controlAlmacenesProvider =
    NotifierProvider<ControlAlmacenes, AvisoAlmacenes?>(ControlAlmacenes.new);
