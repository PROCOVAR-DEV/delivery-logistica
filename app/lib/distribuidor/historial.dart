// EL HISTORIAL DEL DISTRIBUIDOR: sus rutas ya terminadas o canceladas, con lo que
// hizo en cada una. Sale de la base LOCAL (las completadas se quedan en el movil;
// el servidor las sigue bajando 30 dias y el cuadre no las borra) y no se poda antes
// de 90 dias.
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nucleo/base/base.dart';
import '../nucleo/proveedores.dart';

/// Los numeros de una ruta cerrada, calculados de sus paradas.
class ResumenDeRuta {
  const ResumenDeRuta({
    required this.paradas,
    required this.entregadas,
    required this.noEntregadas,
    required this.cobradas,
    this.inicio,
    this.fin,
  });

  final int paradas;
  final int entregadas;

  /// Con resultado distinto de «entregado» (devueltas / no entregadas).
  final int noEntregadas;

  /// Entregadas en las que marco «cobrado».
  final int cobradas;
  final DateTime? inicio;
  final DateTime? fin;

  Duration? get duracion =>
      inicio == null || fin == null ? null : fin!.difference(inicio!);

  /// Paradas sin resultado (una ruta cancelada las deja asi).
  int get sinMarcar => paradas - entregadas - noEntregadas;
}

ResumenDeRuta resumirLaRuta(
  Ruta ruta,
  List<Pedido> paradas,
  Map<String, bool> cobros,
) {
  final entregadas = paradas.where(
    (p) => p.resultado == ResultadoParada.entregado,
  );
  return ResumenDeRuta(
    paradas: paradas.length,
    entregadas: entregadas.length,
    noEntregadas: paradas
        .where(
          (p) =>
              p.resultado != null && p.resultado != ResultadoParada.entregado,
        )
        .length,
    cobradas: entregadas.where((p) => cobros[p.id] == true).length,
    inicio: ruta.startedAt,
    fin: ruta.finishedAt,
  );
}

/// Lo que dice el historial de la revision de logistica sobre una ruta completada:
/// «Revisada ✓» si el servidor bajo `revisadaAt`; si no, «Pendiente de revisión».
/// `null` en las canceladas (no hay nada que revisar). Supone que el servidor ya
/// manda `revisadaAt`; si no lo mandara, todas saldrian «pendientes».
String? textoDeRevision(Ruta ruta) {
  if (ruta.status != EstadoRuta.completada) return null;
  return ruta.revisadaAt != null
      ? 'Revisada ✓'
      : 'Pendiente de revisión de logística';
}

/// Las marcas de cobro de este aparato, por pedido.
final cobrosDeEntregaProvider = StreamProvider<Map<String, bool>>(
  (ref) => ref
      .watch(baseProvider)
      .select(ref.watch(baseProvider).cobrosDeEntrega)
      .watch()
      .map((filas) => {for (final f in filas) f.pedidoId: f.cobrado}),
);

/// ¿Queda algo de esta ruta SIN ENVIAR? Apuntes de la cola que tocan la ruta
/// (`/routes/<id>...`) sin aplicar, o puntos de GPS suyos sin subir.
final pendienteDeEnviarProvider = StreamProvider.family<bool, String>((
  ref,
  rutaId,
) {
  final base = ref.watch(baseProvider);

  Future<bool> mirar() async {
    final apuntes =
        await (base.select(base.apuntes)..where(
              (a) =>
                  a.ruta.like('/routes/$rutaId%') &
                  a.estado.isIn([
                    EstadoApunte.pendiente.name,
                    EstadoApunte.rechazado.name,
                  ]),
            ))
            .get();
    if (apuntes.isNotEmpty) return true;
    final puntos =
        await (base.select(base.puntosGps)..where(
              (p) => p.subido.equals(false) & p.rutaIds.like('%"$rutaId"%'),
            ))
            .get();
    return puntos.isNotEmpty;
  }

  return () async* {
    yield await mirar();
    yield* base
        .tableUpdates(
          TableUpdateQuery.onAllTables([base.apuntes, base.puntosGps]),
        )
        .asyncMap((_) => mirar());
  }();
});
