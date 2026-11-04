// LA REVISIÓN POR LA OFICINA: LA SEGUNDA LLAVE (tarea 6).
//
// Una ruta que cerró el distribuidor desde su teléfono no se da por buena hasta que alguien de la oficina la mira. El servidor
// manda `revisadaAt` en las rutas (nulo = pendiente de revisar); si NO lo manda, esta pantalla no pinta nada. «Confirmar revisión»
// es `POST /api/routes/{id}/revision {"confirmar":true}`.
//
// Dos piezas: [RevisionDeLaRuta] (el estado y el botón, dentro del detalle y del cajón de la lista) y [ListaPorRevisar]
// (la lista filtrable de lo completado).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/colores.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/vista/kit.dart'
    show EstadoVacio, Insignia, OpcionSelector, Selector;
import '../datos/api_distribucion.dart';
import '../datos/modelos.dart';
import 'recorrido_real.dart';

abstract final class TextosDeLaRevision {
  static const pendiente = 'Pendiente de revisión';
  static const confirmar = 'Confirmar revisión';
  static String revisada(String? por, DateTime? cuando) =>
      'Revisada ✓${por == null ? '' : ' por $por'}${cuando == null ? '' : ' el ${fechaYHora(cuando)}'}';
  static const nadaPendiente = 'No hay rutas pendientes de revisión.';
  static const nadaRevisado = 'Todavía no hay rutas revisadas.';
  static const nadaDeEsto =
      'No hay rutas completadas por distribuidores que cuadren con esto.';
}

const claveDeConfirmarRevision = ValueKey('revision-confirmar');
const claveDeLaRevisionPendiente = ValueKey('revision-pendiente');
const claveDeLaRevisionHecha = ValueKey('revision-hecha');
const claveDelAvisoDeRevision = ValueKey('revision-aviso');
Key claveDeLaFilaPorRevisar(String id) => ValueKey('por-revisar-$id');

class RevisionDeLaRuta extends ConsumerStatefulWidget {
  const RevisionDeLaRuta({required this.rutaId, super.key});

  final String rutaId;

  @override
  ConsumerState<RevisionDeLaRuta> createState() => _RevisionDeLaRutaState();
}

class _RevisionDeLaRutaState extends ConsumerState<RevisionDeLaRuta> {
  bool _ocupado = false;
  String? _fallo;

  Future<void> _confirmar() async {
    setState(() {
      _ocupado = true;
      _fallo = null;
    });
    try {
      await ref.read(apiDistribucionProvider).confirmarRevision(widget.rutaId);
      ref.invalidate(revisionesProvider);
    } on Object catch (e) {
      if (mounted) setState(() => _fallo = motivoDelFallo(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(revisionDeLaRutaProvider(widget.rutaId));
    if (r == null) return const SizedBox.shrink();
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.pendiente) ...[
          const Insignia(
            TextosDeLaRevision.pendiente,
            key: claveDeLaRevisionPendiente,
            color: ColoresDelMapa.regreso,
          ),
          const SizedBox(height: 6),
          Text(
            'La cerró el distribuidor desde su teléfono. Mira su recorrido y, si está bien, confírmala.',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            key: claveDeConfirmarRevision,
            icon: const Icon(Icons.task_alt, size: 18),
            label: const Text(TextosDeLaRevision.confirmar),
            onPressed: _ocupado ? null : _confirmar,
          ),
        ] else
          Insignia(
            TextosDeLaRevision.revisada(r.revisadaPor, r.revisadaAt),
            key: claveDeLaRevisionHecha,
            color: ColoresDelMapa.salida,
          ),
        if (_fallo != null) ...[
          const SizedBox(height: 6),
          DecoratedBox(
            key: claveDelAvisoDeRevision,
            decoration: BoxDecoration(
              color: Colores.ambarFondo,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                _fallo!,
                style: TextStyle(fontSize: 12, color: Colores.tinta),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// El cajón de una ruta de la lista: su revisión y su recorrido, juntos.
Future<void> abrirRevisionDeLaRuta(BuildContext contexto, RevisionDeRuta r) =>
    abrirCajon<void>(
      contexto,
      titulo: r.codigo ?? 'Ruta',
      subtitulo: [?r.nombre, ?r.distribuidor, ?r.vehiculo].join(' · '),
      cuerpo: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RevisionDeLaRuta(rutaId: r.id),
          const SizedBox(height: 16),
          RecorridoRealDeLaRuta(rutaId: r.id),
        ],
      ),
    );

enum FiltroDeRevision { pendientes, revisadas, todas }

/// Lo que se ve según el filtro y el buscador. Pura, para probarla sin pantalla.
List<RevisionDeRuta> filtrarRevisiones(
  List<RevisionDeRuta> rutas, {
  FiltroDeRevision filtro = FiltroDeRevision.pendientes,
  String q = '',
}) {
  final t = q.trim().toLowerCase();
  final salida =
      [
        for (final r in rutas)
          if (r.seRevisa &&
              switch (filtro) {
                FiltroDeRevision.pendientes => r.pendiente,
                FiltroDeRevision.revisadas => r.revisada,
                FiltroDeRevision.todas => true,
              } &&
              (t.isEmpty ||
                  [
                    r.codigo,
                    r.nombre,
                    r.distribuidor,
                    r.vehiculo,
                  ].any((x) => x != null && x.toLowerCase().contains(t))))
            r,
      ]..sort(
        (a, b) =>
            (b.terminada ?? DateTime(0)).compareTo(a.terminada ?? DateTime(0)),
      );
  return salida;
}

int cuantasPendientes(List<RevisionDeRuta> rutas) =>
    rutas.where((r) => r.pendiente).length;

class ListaPorRevisar extends ConsumerStatefulWidget {
  const ListaPorRevisar({super.key});

  static const claveDelFiltro = ValueKey('por-revisar-filtro');

  @override
  ConsumerState<ListaPorRevisar> createState() => _ListaPorRevisarState();
}

class _ListaPorRevisarState extends ConsumerState<ListaPorRevisar> {
  var _filtro = FiltroDeRevision.pendientes;
  var _q = '';

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final rutas = ref.watch(revisionesProvider);
    return switch (rutas) {
      AsyncValue(:final error?) => EstadoVacio(
        'No se pudo leer la lista: ${motivoDelFallo(error)}',
        accion: OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Reintentar'),
          onPressed: () => ref.invalidate(revisionesProvider),
        ),
      ),
      AsyncData(:final value) => _lista(context, tema, value),
      _ => const EstadoVacio('Cargando las rutas…'),
    };
  }

  Widget _lista(
    BuildContext context,
    ThemeData tema,
    List<RevisionDeRuta> todas,
  ) {
    final vistas = filtrarRevisiones(todas, filtro: _filtro, q: _q);
    final hayAlguna = todas.any((r) => r.seRevisa);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CajaDeBusqueda(
              valor: _q,
              ancho: 260,
              pista: 'Buscar por código, distribuidor, vehículo…',
              alBuscar: (t) => setState(() => _q = t),
            ),
            Selector<FiltroDeRevision>(
              key: ListaPorRevisar.claveDelFiltro,
              titulo: 'Mostrar',
              valor: _filtro,
              opciones: const [
                OpcionSelector(
                  FiltroDeRevision.pendientes,
                  'Pendientes de revisión',
                ),
                OpcionSelector(FiltroDeRevision.revisadas, 'Revisadas'),
                OpcionSelector(FiltroDeRevision.todas, 'Todas'),
              ],
              alElegir: (f) => setState(() => _filtro = f),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (vistas.isEmpty)
          EstadoVacio(
            !hayAlguna
                ? 'Ninguna ruta pasa por revisión todavía: aparecen aquí las que cierra un distribuidor desde su teléfono.'
                : _q.trim().isNotEmpty
                ? TextosDeLaRevision.nadaDeEsto
                : switch (_filtro) {
                    FiltroDeRevision.pendientes =>
                      TextosDeLaRevision.nadaPendiente,
                    FiltroDeRevision.revisadas =>
                      TextosDeLaRevision.nadaRevisado,
                    FiltroDeRevision.todas => TextosDeLaRevision.nadaDeEsto,
                  },
          )
        else
          for (final r in vistas)
            Card(
              key: claveDeLaFilaPorRevisar(r.id),
              child: ListTile(
                onTap: () => abrirRevisionDeLaRuta(context, r),
                title: Text([?r.codigo, ?r.nombre].join(' · ')),
                subtitle: Text(
                  [
                    ?r.distribuidor,
                    ?r.vehiculo,
                    if (r.terminada != null)
                      'terminó ${fechaYHora(r.terminada)}',
                  ].join(' · '),
                ),
                trailing: r.pendiente
                    ? const Insignia(
                        TextosDeLaRevision.pendiente,
                        color: ColoresDelMapa.regreso,
                      )
                    : const Insignia(
                        'Revisada ✓',
                        color: ColoresDelMapa.salida,
                      ),
              ),
            ),
      ],
    );
  }
}
