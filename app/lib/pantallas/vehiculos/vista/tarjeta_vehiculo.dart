import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/tarjeta.dart';
import '../../../diseno/tema.dart';
import '../datos/vehiculo_api.dart';

/// La tarjeta de la rejilla. Pliego: `pantallas.md` §5.
class TarjetaVehiculo extends StatelessWidget {
  const TarjetaVehiculo({
    required this.vehiculo,
    required this.alEditar,
    required this.alEliminar,
    required this.alMarcarDisponible,
    required this.alUsarParaDomicilio,
    required this.importe,
    super.key,
  });

  final VehiculoDeLaApi vehiculo;

  /// El costo por km se pinta en la moneda que se esta mirando, como el resto
  /// del dinero de la aplicacion y como la de Next, que lo pasa por `format()`.
  /// Se guarda en USD; el CUP se calcula al pintarlo.
  final PintarImporte importe;
  final VoidCallback alEditar;
  final VoidCallback alEliminar;
  final VoidCallback alMarcarDisponible;
  final VoidCallback alUsarParaDomicilio;

  /// Los colores son los SEMANTICOS del kit, no unos propios: azul = en marcha,
  /// ambar = atencion, verde = listo. Los tenia repetidos aqui y por eso el «en
  /// uso» de un vehiculo no era el mismo azul que el de un pedido.
  ///
  /// SALEN DE `andar`, no del campo guardado — 28/09/2026. Antes salian de
  /// `vehiculo.enUso`, que lee `vehicles.status`: un campo que alguien pone y
  /// alguien tiene que quitar, y que se queda en `in_use` en cuanto una ruta se
  /// cierra por otro camino. `andar` lo deduce de la ruta abierta del camion;
  /// el porque entero esta en `VehiculoDeLaApi.andar`.
  ///
  /// `asignado` —tiene una ruta planificada pero no ha salido— va en AMBAR y no
  /// en azul a proposito: azul es «esta fuera». Son las dos respuestas que
  /// antes se juntaban en «En uso», y juntarlas manda a buscar otro camion a
  /// quien tenia uno disponible hasta mañana.
  Color get _colorEstado => switch (vehiculo.andar) {
    AndarDelCamion.enRuta => Colores.enCurso,
    AndarDelCamion.asignado => Colores.ambar,
    AndarDelCamion.enMantenimiento => Colores.ambar,
    AndarDelCamion.libre => Colores.verde,
  };

  Color get _fondoEstado => switch (vehiculo.andar) {
    AndarDelCamion.enRuta => Colores.enCursoFondo,
    AndarDelCamion.asignado => Colores.ambarFondo,
    AndarDelCamion.enMantenimiento => Colores.ambarFondo,
    AndarDelCamion.libre => Colores.verdeFondo,
  };

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Tarjeta(
      relleno: const EdgeInsets.all(Aire.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // El icono en su cuadrado tintado, como las tarjetas del panel.
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _fondoEstado,
                  borderRadius: BorderRadius.circular(Radios.md),
                ),
                child: Icon(
                  vehiculo.enMantenimiento ? Icons.build : Icons.local_shipping,
                  size: 20,
                  color: _colorEstado,
                ),
              ),
              const SizedBox(width: Aire.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(vehiculo.nombre, style: tema.textTheme.titleSmall),
                    // La placa en JetBrains Mono: es un codigo, y con la
                    // `monospace` del sistema sale en Courier New en Windows.
                    if (vehiculo.placa?.isNotEmpty ?? false)
                      Text(
                        vehiculo.placa!,
                        style: Tipos.mono(
                          tamano: 12,
                          color: Colores.tintaSuave,
                        ),
                      ),
                  ],
                ),
              ),
              Insignia(
                vehiculo.etiquetaEstado,
                color: _colorEstado,
                fondo: _fondoEstado,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (vehiculo.tipo != null)
                Chip(
                  label: Text(vehiculo.tipo!),
                  visualDensity: VisualDensity.compact,
                ),
              if (vehiculo.usarParaDomicilio)
                Chip(
                  avatar: const Icon(Icons.home_work, size: 16),
                  label: Text(
                    vehiculo.costoKmUsd == null
                        ? 'Cálculo domicilio'
                        : 'Cálculo domicilio · '
                              '${importe(vehiculo.costoKmUsd)}/km',
                  ),
                  visualDensity: VisualDensity.compact,
                )
              else
                OutlinedButton(
                  onPressed: alUsarParaDomicilio,
                  child: const Text('Usar para domicilio'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Caja(
                  titulo: 'Capacidad',
                  valor: '${vehiculo.capacidad.toStringAsFixed(0)} kg',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Caja(titulo: 'Rutas', valor: '${vehiculo.rutas}'),
              ),
            ],
          ),
          // LA CAJA DE LA RUTA. Se pintaba `if (vehiculo.enUso && …)`, y con eso
          // NO SALIA NUNCA por dos motivos a la vez: el servidor no mandaba el
          // campo `routes` —lo empezo a mandar el 28/09/2026— y ademas se
          // exigia que el campo guardado dijera `in_use`, que es justo el que no
          // hay que creerse. Ahora la condicion es la unica que importa: si hay
          // ruta abierta, se dice cual.
          if (vehiculo.rutaActiva != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _fondoEstado,
                borderRadius: BorderRadius.circular(Radios.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // «Ruta activa» para la que esta rodando y «Ruta
                    // planificada» para la que no ha salido: el rotulo dice
                    // cual de las dos es sin que haya que leer el codigo.
                    vehiculo.rutaActiva!.enCurso
                        ? 'Ruta activa'
                        : 'Ruta planificada',
                    style: Tipos.texto(
                      tamano: 10,
                      peso: FontWeight.w600,
                      color: _colorEstado,
                      interletra: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(vehiculo.rutaActiva!.titulo),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${vehiculo.pedidos} órdenes asignadas',
            style: tema.textTheme.bodySmall?.copyWith(
              color: Colores.tintaSuave,
            ),
          ),
          // EL CAMPO GUARDADO DICE «EN USO» Y NO LLEVA NINGUNA RUTA.
          //
          // No se pinta como ocupado —eso seria repetir la mentira— pero
          // tampoco se calla: ese campo lo siguen mirando el desplegable del
          // asistente de Rutas y el del tablero, asi que mientras no se limpie
          // este camion sale con un «en ruta» falso en los dos. El boton
          // «Marcar disponible» de aqui abajo es lo que lo arregla.
          if (vehiculo.estadoGuardadoMiente) ...[
            const SizedBox(height: Aire.xs),
            Text(
              'El estado guardado dice «en uso» y no lleva ninguna ruta '
              'abierta. Márcalo disponible: hasta entonces sale como ocupado '
              'al elegir camión.',
              style: tema.textTheme.bodySmall?.copyWith(color: Colores.ambar),
            ),
          ],
          if (vehiculo.notas?.isNotEmpty ?? false) ...[
            const SizedBox(height: Aire.xs),
            Text(
              vehiculo.notas!,
              style: tema.textTheme.bodySmall?.copyWith(
                color: Colores.tintaSuave,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (vehiculo.enUso)
                TextButton(
                  onPressed: alMarcarDisponible,
                  child: const Text('Marcar disponible'),
                ),
              TextButton(onPressed: alEditar, child: const Text('Editar')),
              // Sin confirmacion, como la de Next. Se deja igual a proposito:
              // cambiarlo aqui y no alla es que la misma accion se comporte
              // distinto segun por donde entres.
              TextButton(onPressed: alEliminar, child: const Text('Eliminar')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Caja extends StatelessWidget {
  const _Caja({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: Aire.sm),
    decoration: BoxDecoration(
      color: Colores.papel,
      border: Border.all(color: Colores.linea),
      borderRadius: BorderRadius.circular(Radios.md),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          titulo,
          style: Tipos.texto(
            tamano: 10,
            peso: FontWeight.w600,
            color: Colores.tintaSuave,
            interletra: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        // La cifra en mono: dos tarjetas de vehiculo una al lado de la otra se
        // comparan por estas dos cajas.
        Text(
          valor,
          style: Tipos.mono(
            tamano: 15,
            peso: FontWeight.w600,
            color: Colores.tinta,
          ),
        ),
      ],
    ),
  );
}
