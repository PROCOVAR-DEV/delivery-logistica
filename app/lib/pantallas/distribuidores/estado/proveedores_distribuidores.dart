import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/copia_bajada.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/refresco_en_vivo.dart';
import '../datos/repositorio_distribuidores.dart';

final repositorioDistribuidoresProvider = Provider<RepositorioDistribuidores>(
  (ref) => RepositorioDistribuidores(
    ref.watch(clienteApiProvider),
    ref.watch(baseProvider),
  ),
);

/// LA LISTA DEL SERVIDOR, para el cajon que los mantiene.
///
/// Una peticion y no un stream sobre la base, a proposito: el cajon enseña lo que
/// el servidor tiene AHORA, con sus retirados y cuantas rutas usa cada uno, y sin
/// conexion no finge enseñar una lista vieja que no puede cambiar. (El selector de
/// «Nueva ruta» es otra cosa y SI mira la base: [distribuidoresParaRutaNuevaProvider].)
///
/// Se vuelve a pedir con el aviso `vehiculos`, que es el que publica el servidor
/// al tocar el nomenclador (`api/internal/api/distribuidores.go`): lo que cambie
/// otra persona mientras el cajon esta abierto aparece solo.
final distribuidoresDelServidorProvider =
    FutureProvider.autoDispose<List<DistribuidorDelServidor>>((ref) {
      // Al cambiar de sucursal en la barra se vuelve a pedir: el alcance lo
      // resuelve el servidor con la cabecera `x-sucursal-id`.
      ref.watch(sucursalMiradaProvider);
      refrescarConElAviso(ref, const [CambioEnVivo.vehiculos]);
      return ref.watch(repositorioDistribuidoresProvider).listar();
    });

/// TODOS los distribuidores que el aparato tiene bajados de la sucursal que se
/// mira, retirados incluidos: de ellos sale el NOMBRE de quien reparte cada ruta,
/// y una ruta vieja sigue diciendo quien la repartio aunque ya este retirado.
///
/// **Stream y no Future** (`CLAUDE.md` §3-ter): en la web la base nace vacia en
/// cada carga y la bajada la llena un segundo despues; con una sola respuesta, la
/// lista de rutas se quedaria diciendo «Distribuidor sin descargar» para siempre.
final distribuidoresDeLaBarraProvider = StreamProvider<List<Distribuidor>>((
  ref,
) {
  final base = ref.watch(baseProvider);
  final sucursal = ref.watch(sucursalMiradaProvider);
  final consulta = base.select(base.distribuidores)
    ..orderBy([(d) => OrderingTerm.asc(d.nombre)]);
  if (sucursal != null && sucursal.isNotEmpty) {
    consulta.where((d) => d.branchId.equals(sucursal));
  }
  return consulta.watch();
});

/// LOS QUE SE PUEDEN ELEGIR EN UNA RUTA NUEVA DE ESTA SUCURSAL: los de esa
/// sucursal y en activo.
///
/// Se pregunta por la sucursal de la RUTA (la del paso 1 del asistente, o la de la
/// zona del tablero) y no por la que se mira en la barra: un SUPER ADMIN que mira
/// «todas» arma una ruta de Holguin, y el selector tiene que ofrecer los de
/// Holguin. Es el mismo filtro que aplica el servidor al validar
/// (`distribuidorDeLaRuta`): de la misma sucursal y en activo.
///
/// Sin sucursal no hay nada que ofrecer: un distribuidor es de una sucursal.
final distribuidoresParaRutaNuevaProvider =
    StreamProvider.family<List<Distribuidor>, String?>((ref, sucursalId) {
      if (sucursalId == null || sucursalId.isEmpty) {
        return Stream.value(const <Distribuidor>[]);
      }
      final base = ref.watch(baseProvider);
      return (base.select(base.distribuidores)
            ..where((d) => d.branchId.equals(sucursalId) & d.activo.equals(true))
            ..orderBy([(d) => OrderingTerm.asc(d.nombre)]))
          .watch();
    });

/// SI EL APARATO BAJO ALGUNA VEZ LOS DISTRIBUIDORES, y cuantos tiene. Separa «esta
/// sucursal no tiene ninguno» de «este aparato no los ha descargado»: se arreglan
/// al reves (dando de alta uno, o trayendo el dia). El cartel de «no bajo».
final distribuidoresEnElAparatoProvider = StreamProvider<CopiaBajada>((ref) {
  final base = ref.watch(baseProvider);
  return copiaBajada(
    base,
    coleccion: Colecciones.distribuidores,
    tabla: base.distribuidores,
  );
});
