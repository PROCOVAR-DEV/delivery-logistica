import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../datos/repositorio_clientes.dart';

final repositorioClientesProvider = Provider<RepositorioClientes>(
  (ref) => RepositorioClientes(ref.watch(baseProvider)),
);

/// Los filtros de la pantalla. Viven aparte de la consulta para que cambiar uno
/// no arrastre el resto ni pierda la seleccion.
class FiltrosDeClientes extends Notifier<FiltrosClientes> {
  @override
  FiltrosClientes build() => const FiltrosClientes();

  void poner(FiltrosClientes nuevos) => state = nuevos;

  void quitar() => state = const FiltrosClientes();

  void aPagina(int pagina) => state = state.copiar(pagina: pagina);
}

final filtrosClientesProvider =
    NotifierProvider<FiltrosDeClientes, FiltrosClientes>(FiltrosDeClientes.new);

/// La lista, como **stream sobre la base local**.
///
/// Es un stream y no una peticion porque la fuente de verdad es la base: cuando
/// la bajada mete clientes nuevos o cambia el almacen principal, la pantalla se
/// repinta sola. Nadie espera a un servidor para ver esto.
final clientesProvider = StreamProvider.autoDispose<PaginaClientes>((
  ref,
) async* {
  final base = ref.watch(baseProvider);
  final repositorio = ref.watch(repositorioClientesProvider);
  final filtros = ref.watch(filtrosClientesProvider);
  // Al cambiar de sucursal en la barra NO se recarga la pagina: se mira aqui, y
  // el provider se reconstruye solo con los numeros de la otra.
  final sucursal = ref.watch(sucursalMiradaProvider);

  Future<PaginaClientes> leer() =>
      repositorio.consultar(filtros, sucursalId: sucursal);

  yield await leer();

  final cambios = base.tableUpdates(
    TableUpdateQuery.onAllTables([
      base.customers,
      base.warehouses,
      base.branches,
      base.frescura,
    ]),
  );
  await for (final _ in cambios) {
    yield await leer();
  }
});

/// De que hora son estos datos. Manda la bajada **mas vieja** de las dos
/// colecciones que sostienen la pantalla: los clientes y los almacenes desde los
/// que se miden los km. Con los clientes de hoy y el almacen de anteayer, la
/// distancia es de anteayer.
final frescuraClientesProvider = StreamProvider.autoDispose<EstadoFrescura>((
  ref,
) {
  final reloj = ref.watch(relojProvider);
  return ref
      .watch(frescuraProvider)
      // LA MISMA LISTA que declara `registrarClientes()` para la franja de
      // arriba. Estaba escrita aqui a mano, y dos copias se separan sin que
      // salte nada: entonces la franja y este reloj dicen dos horas distintas
      // en la misma ventana (§3-bis).
      .laMasVieja(ColeccionesDePantalla.clientes)
      .map((bajada) => EstadoFrescura.de(bajada, ahora: reloj()));
});
