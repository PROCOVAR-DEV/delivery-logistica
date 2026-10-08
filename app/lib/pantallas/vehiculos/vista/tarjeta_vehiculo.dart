import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/tarjeta.dart';
import '../../../diseno/tema.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
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
    this.esLaPrimera = false,
    super.key,
  });

  /// SI ESTA ES LA PRIMERA TARJETA DE LA LISTA.
  ///
  /// Sólo sirve para una cosa: la Guia sólo puede senalar un control por nombre,
  /// y «Editar» existe una vez por camion. Marcando sólo la primera, el recorrido
  /// senala una y no tiene que elegir entre nueve
  /// (`pantallas/ayuda/vista/control_senalado.dart` explica por que dos a la vez
  /// no se pueden distinguir).
  final bool esLaPrimera;

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
          // DADO DE BAJA — Amado, 07/10/2026 (incidencia 4). Un camion con rutas
          // no se borra, se inactiva, y desde entonces no sale en la seleccion
          // de rutas nuevas. Se dice AQUI porque `etiquetaEstado` habla de en
          // que anda el camion (libre, con ruta, en el taller) y esto es otra
          // cosa: un camion puede estar libre Y de baja.
          if (!vehiculo.activo) ...[
            const SizedBox(height: Aire.xs),
            const InsigniaInactivo(),
          ],
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
                ControlSenalado(
                  nombre: Senalado.vehiculosUsarParaDomicilio,
                  senalable: esLaPrimera,
                  child: OutlinedButton(
                    onPressed: alUsarParaDomicilio,
                    child: const Text('Usar para domicilio'),
                  ),
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
            '${vehiculo.pedidos} '
            '${vehiculo.pedidos == 1 ? 'orden asignada' : 'órdenes asignadas'}',
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
          // ESTA EN EL TALLER **Y** LLEVA UNA RUTA ABIERTA — 28/09/2026.
          //
          // No es lo mismo que el aviso de arriba y por eso es otro. Alli el
          // campo guardado MIENTE —dice «en uso» sin ruta ninguna— y lo unico
          // que hay que hacer es limpiarlo. Aqui las dos mitades son verdad y se
          // contradicen: alguien escribio «al taller» a mano y hay una ruta sin
          // cerrar con su codigo delante. Eso no lo arregla la pantalla, lo
          // arregla una persona, y por eso se dice con la ruta NOMBRADA: sin el
          // codigo hay que ponerse a buscar cual es.
          //
          // La insignia dice «Mantenimiento», que es lo que hace que alguien
          // mire (el porque entero, en `VehiculoDeLaApi.andar`). Esta linea es
          // la otra mitad: la insignia llama y esto cuenta que pasa.
          if (vehiculo.enTallerConRutaAbierta) ...[
            const SizedBox(height: Aire.xs),
            Text(
              'Está en el taller y lleva la ruta '
              '${vehiculo.rutaActiva!.titulo} abierta. O vuelve a estar '
              'disponible, o esa ruta la tiene que llevar otro camión: '
              'mandarlo al taller no la cierra, porque una ruta cerrada es una '
              'ruta repartida.',
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
                ControlSenalado(
                  nombre: Senalado.vehiculosMarcarDisponible,
                  senalable: esLaPrimera,
                  child: TextButton(
                    onPressed: alMarcarDisponible,
                    child: const Text('Marcar disponible'),
                  ),
                ),
              ControlSenalado(
                nombre: Senalado.vehiculosEditar,
                senalable: esLaPrimera,
                child: TextButton(
                  onPressed: alEditar,
                  child: const Text('Editar'),
                ),
              ),
              // PREGUNTA ANTES, desde el 01/10/2026. Aqui decia «sin
              // confirmacion, como la de Next», y era un descuido vestido de
              // decision: la casa ya habia decidido lo contrario el 25/09/2026
              // con «Borrar la columna» del tablero. La pregunta la pone quien
              // conoce el camion —`_Rejilla._borrarPreguntando`, que es donde
              // esta el porque entero—, no la tarjeta: esto sigue siendo un
              // `VoidCallback` y no sabe de red ni de cajones.
              //
              // **Y aun asi es el que mas tiene que verse que es** —
              // 28/09/2026. Borra un camion de una, sin preguntar, y hasta hoy
              // se leia exactamente igual que «Editar» y que «Marcar
              // disponible»: la misma palabra en el mismo oro, tercera de una
              // fila de tres. Ahora es un [BotonDestructivo] — rojo, contorno de
              // 2 px y papelera —, que es lo unico rojo de la tarjeta.
              ControlSenalado(
                nombre: Senalado.vehiculosEliminar,
                senalable: esLaPrimera,
                child: BotonDestructivo(
                  texto: 'Eliminar',
                  alPulsar: alEliminar,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// «Inactivo»: color, borde y icono, SIN fondo relleno.
///
/// No es [Insignia] a proposito: aquella es una pastilla con el fondo tintado, y
/// la regla de la casa es que lo que se distingue lo hace por **color, borde e
/// icono** (`CLAUDE.md` §4). Publica para poder probarla suelta.
class InsigniaInactivo extends StatelessWidget {
  const InsigniaInactivo({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      border: Border.all(color: Colores.tintaSuave),
      borderRadius: BorderRadius.circular(Radios.pastilla),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.block, size: 13, color: Colores.tintaSuave),
        const SizedBox(width: 4),
        Text(
          'Inactivo',
          style: Tipos.texto(
            tamano: 11,
            peso: FontWeight.w600,
            color: Colores.tintaSuave,
            interletra: 0.1,
          ),
        ),
      ],
    ),
  );
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
