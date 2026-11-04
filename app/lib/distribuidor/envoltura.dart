// LO QUE ENVUELVE A LA APP del distribuidor (dentro del `MaterialApp`, con su tema):
//  1. la primera vez, «Preparando el mapa de Cuba…» (sin red);
//  2. el aviso de ubicacion de la primera vez, con «Aceptar»;
//  3. el motor del GPS, que se enciende con las rutas en curso.
// La app de debajo (el enrutador) se queda SIEMPRE en el mismo sitio del arbol: se
// tapa, no se desmonta, para no perder la pantalla en la que estaba.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navegacion/portero.dart';
import 'aviso_de_ubicacion.dart';
import 'mapa/preparacion_del_mapa.dart';
import 'proveedores_distribuidor.dart';

class EnvolturaDelDistribuidor extends ConsumerStatefulWidget {
  const EnvolturaDelDistribuidor({required this.app, super.key});

  final Widget app;

  @override
  ConsumerState<EnvolturaDelDistribuidor> createState() =>
      _EnvolturaDelDistribuidorState();
}

class _EnvolturaDelDistribuidorState
    extends ConsumerState<EnvolturaDelDistribuidor> {
  bool _ahoraNo = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(motorDelGpsProvider);
    final mapa = ref.watch(preparacionDelMapaProvider);
    final portero = ref.watch(porteroProvider);
    final aceptacion = ref.watch(aceptacionDeUbicacionProvider);

    return Stack(
      children: [
        Positioned.fill(child: widget.app),
        if (!mapa.lista)
          const Positioned.fill(child: PantallaPreparandoElMapa())
        else
          Positioned.fill(
            child: ListenableBuilder(
              listenable: portero,
              builder: (contexto, _) {
                final dentro = portero.estado == EstadoDeAcceso.dentro;
                final sinAceptar =
                    aceptacion.hasValue && aceptacion.value == null;
                if (!dentro || !sinAceptar || _ahoraNo) {
                  return const SizedBox.shrink();
                }
                return AvisoDeUbicacion(
                  alAceptar: () => ref
                      .read(aceptacionDeUbicacionProvider.notifier)
                      .aceptar(portero.sesion?.sub ?? ''),
                  alAhoraNo: () => setState(() => _ahoraNo = true),
                );
              },
            ),
          ),
      ],
    );
  }
}
