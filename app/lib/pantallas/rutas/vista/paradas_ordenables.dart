// REORDENAR LAS PARADAS ARRASTRANDO (issue 11 de Amado, 15/10/2026).
//
// «En la ruta, sería conveniente que las paradas se puedan reordenar utilizando la
// interfaz con drag/drop […] El reordenamiento debe impactar en el diseño de la
// ruta.» Esto es la lista de «Ver paradas» de una ruta NO completada: cada parada
// lleva un asa visible (`Icons.drag_handle`) que arrastra DEL TIRÓN con el ratón
// y con el dedo —`ReorderableDragStartListener`: el asa es sólo para eso, así que
// no compite con desplazar la lista—, y arriba el botón «Ordenar por cercanía».
//
// Lo que se suelta va a `AccionesDeRuta.reordenar`: en la web al servidor, en la
// APK y el escritorio a la base local y a la cola. El croquis, el enlace de
// Google Maps, los km de la cabecera y el post-despacho leen el `stopOrder` de la
// base, así que cambian solos.
//
// Es pública y no lee proveedores para poder probarla suelta, sin Drift: dentro
// de un `testWidgets` una consulta de Drift cuelga la prueba (`CLAUDE.md` §5).

import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/lista_que_se_recoloca.dart';
import '../../../nucleo/base/base.dart';
import '../datos/acciones_rutas.dart';
import '../datos/formato_de_la_ruta.dart';

/// Claves para las pruebas: buscar por el dibujo ataría la prueba al icono.
const claveDeOrdenarPorCercania = ValueKey('ruta-ordenar-por-cercania');
ValueKey<String> claveDelAsa(String pedidoId) => ValueKey('ruta-asa-$pedidoId');

class ParadasOrdenables extends StatefulWidget {
  const ParadasOrdenables({
    required this.rutaId,
    required this.estado,
    required this.optimizada,
    required this.paradas,
    required this.alReordenar,
    required this.tarjeta,
    super.key,
  });

  final String rutaId;

  /// El estado de la ruta, VIVO. En una `completed` no se arrastra ni se ofrece
  /// el botón: es histórico (`CLAUDE.md` §1).
  final String estado;
  final bool optimizada;

  /// Las paradas de la hoja, en su orden. Las que ya soltaron la ruta con un
  /// resultado (un devuelto) se enseñan, pero no se ordenan: el servidor sólo
  /// ordena lo que va cargado (`routeId`).
  final List<Pedido> paradas;

  /// `orden` nulo = por cercanía. Lanza [RechazoLocal] con el motivo literal.
  final Future<void> Function({List<String>? orden}) alReordenar;

  /// La tarjeta de cada parada, con su número y su asa (nula si no se arrastra).
  final Widget Function(Pedido parada, int numero, Widget? asa) tarjeta;

  @override
  State<ParadasOrdenables> createState() => _ParadasOrdenablesState();
}

class _ParadasOrdenablesState extends State<ParadasOrdenables> {
  /// El orden recién soltado, mientras la base no lo trae: sin esto la tarjeta
  /// vuelve a su sitio un instante y salta, que se lee como «no funcionó».
  List<String>? _provisional;
  bool _enVuelo = false;

  /// El «no» del último gesto, a la vista DENTRO del cajón (el aviso de abajo
  /// puede quedar tapado por el propio cajón en el teléfono).
  String? _rechazo;

  List<Pedido> get _cargadas => [
    for (final p in widget.paradas)
      if (p.routeId == widget.rutaId) p,
  ];

  @override
  void didUpdateWidget(ParadasOrdenables viejo) {
    super.didUpdateWidget(viejo);
    final provisional = _provisional;
    if (provisional != null &&
        _iguales(provisional, [for (final p in _cargadas) p.id])) {
      _provisional = null;
    }
  }

  static bool _iguales(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _aplicar({List<String>? orden}) async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _provisional = orden;
      _rechazo = null;
      _enVuelo = true;
    });
    try {
      await widget.alReordenar(orden: orden);
    } on RechazoLocal catch (no) {
      // NO SE MUEVE NADA: se vuelve al orden de la base y se dice por qué.
      if (mounted) {
        setState(() {
          _provisional = null;
          _rechazo = no.mensaje;
        });
      }
      mensajero?.showSnackBar(SnackBar(content: Text(no.mensaje)));
    } finally {
      if (mounted) setState(() => _enVuelo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.estado != EstadoRuta.completada;
    final cargadas = _cargadas;
    final soltadas = [
      for (final p in widget.paradas)
        if (p.routeId != widget.rutaId) p,
    ];
    final porId = {for (final p in cargadas) p.id: p};
    final ids = _provisional ?? [for (final p in cargadas) p.id];
    final enOrden = [
      for (final id in ids)
        if (porId[id] != null) porId[id]!,
      for (final p in cargadas)
        if (!ids.contains(p.id)) p,
    ];

    if (!editable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.paradas.length; i++)
            widget.tarjeta(
              widget.paradas[i],
              widget.paradas[i].stopOrder ?? i + 1,
              null,
            ),
        ],
      );
    }

    final estilo = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              comoEstaOrdenada(optimizada: widget.optimizada),
              style: estilo,
            ),
            OutlinedButton.icon(
              key: claveDeOrdenarPorCercania,
              onPressed: _enVuelo || cargadas.length < 2
                  ? null
                  : () => _aplicar(),
              icon: const Icon(Icons.near_me_outlined),
              label: const Text('Ordenar por cercanía'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Arrastra cada parada por su asa para cambiar el orden de visita.',
          style: estilo?.copyWith(color: Colores.gris),
        ),
        if (_rechazo != null) ...[
          const SizedBox(height: 8),
          Text(_rechazo!, style: estilo?.copyWith(color: Colores.rojo)),
        ],
        const SizedBox(height: 12),
        // EL ALTO SALE DE LA PANTALLA, como la vista previa de las hojas: la
        // lista se desplaza ELLA, y así al arrastrar hasta el borde se mueve sola
        // (dentro del desplazable del cajón, con `shrinkWrap`, no se movería y no
        // se podría llevar la parada 15 a la 1 en un teléfono).
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          // «Ordenar por cercanía» las desliza a su orden nuevo; el arrastre
          // anima solo y aquí no mueve nada (la soltada no está montada).
          child: ListaQueSeRecoloca(
            claves: [for (final p in enOrden) p.id],
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: enOrden.length,
              // `onReorderItem`: `hasta` ya viene corregido por la que se saca.
              onReorderItem: (desde, hasta) {
                if (_enVuelo) return;
                final nuevo = [for (final p in enOrden) p.id];
                final movida = nuevo.removeAt(desde);
                nuevo.insert(hasta, movida);
                if (_iguales(nuevo, [for (final p in enOrden) p.id])) return;
                _aplicar(orden: nuevo);
              },
              itemBuilder: (context, i) {
                final parada = enOrden[i];
                return SeRecoloca(
                  key: ValueKey(parada.id),
                  clave: parada.id,
                  child: widget.tarjeta(
                    parada,
                    i + 1,
                    _enVuelo
                        ? Icon(Icons.drag_handle, color: Colores.gris)
                        : ReorderableDragStartListener(
                            key: claveDelAsa(parada.id),
                            index: i,
                            child: const MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Tooltip(
                                message: 'Arrastrar para cambiar el orden',
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
        ),
        // Las que ya bajaron del camión con un resultado: se ven, no se ordenan.
        for (final p in soltadas) widget.tarjeta(p, p.stopOrder ?? 0, null),
      ],
    );
  }
}
