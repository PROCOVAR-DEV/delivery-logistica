import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../datos/modelos.dart';
import 'kit.dart';
import 'tarjeta.dart';

/// Lo que viaja cuando se arrastra una columna entera por su cabecera.
class ColumnaArrastrada {
  const ColumnaArrastrada(this.columnaId);

  final String columnaId;
}

/// Una columna del tablero: la zona que se invento el logistico, con lo que
/// lleva puesto dentro.
class ColumnaDelTablero extends StatelessWidget {
  const ColumnaDelTablero({
    required this.columna,
    required this.tarjetas,
    required this.alSoltar,
    required this.alPulsarTarjeta,
    required this.alAbrirMenu,
    required this.alSoltarColumna,
    this.ancho,
    this.esLaPrimera = false,
    this.esLaSegunda = false,
    super.key,
  });

  /// SI ESTA ES LA PRIMERA ZONA DE LA TIRA.
  ///
  /// Sólo para la Guia: los tres puntos de la cabecera existen una vez por zona
  /// y el recorrido sólo puede senalar uno. Marcando la primera, senala una y no
  /// tiene que elegir entre doce
  /// (`pantallas/ayuda/vista/control_senalado.dart`).
  final bool esLaPrimera;

  /// El destino de reordenar debe ser otra zona, no la propia cabecera.
  final bool esLaSegunda;

  final ColumnaTablero columna;
  final List<TarjetaColocada> tarjetas;

  /// [posicion] es donde se solto: `null` significa «al final».
  final void Function(TarjetaArrastrada datos, int? posicion) alSoltar;
  final void Function(TarjetaColocada tarjeta) alPulsarTarjeta;
  final VoidCallback alAbrirMenu;

  /// Arrastrar la cabecera de una columna reordena el tablero: la que se suelta
  /// se pone donde estaba esta.
  final void Function(ColumnaArrastrada arrastrada) alSoltarColumna;

  /// `null` = ocupa lo que le den (el movil).
  final double? ancho;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    // LA ZONA ENTERA ES EL BLANCO DE LOS DOS ARRASTRES, y por eso la Guia la
    // senala: en la web y en el escritorio se reparte arrastrando, y «suéltala
    // sobre la zona» no tenia donde apuntar. Sólo la primera
    // (`esLaPrimera`): hay una por zona y dos con el mismo nombre no se
    // distinguen.
    final zona = ControlSenalado(
      nombre: Senalado.tableroZonaDondeSoltar,
      senalable: esLaPrimera,
      child: DragTarget<ColumnaArrastrada>(
        onAcceptWithDetails: (detalles) {
          if (detalles.data.columnaId != columna.id) {
            alSoltarColumna(detalles.data);
          }
        },
        builder: (contexto, encimaColumna, _) => Container(
          width: ancho,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: tema.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: encimaColumna.isEmpty
                ? null
                : Border.all(color: tema.colorScheme.primary, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // La cabecera se arrastra: es como se reordena el tablero. Igual
              // que las tarjetas, el gesto lo decide el PUNTERO: del tiron con
              // raton o lapiz, con pulsacion larga con el dedo, que es lo que
              // evita comerse el desplazamiento lateral de la tira en un
              // telefono. El porque esta en `ArrastrableSegunPuntero`
              // (`kit.dart`). Reordenar sólo se ofrece arrastrando en pantalla
              // grande; el menú no tiene acciones de mover izquierda/derecha.
              ArrastrableSegunPuntero<ColumnaArrastrada>(
                datos: ColumnaArrastrada(columna.id),
                feedback: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: ancho ?? 260,
                    child: _Cabecera(
                      columna: columna,
                      alAbrirMenu: alAbrirMenu,
                      alSoltar: alSoltar,
                    ),
                  ),
                ),
                child: _Cabecera(
                  columna: columna,
                  alAbrirMenu: alAbrirMenu,
                  alSoltar: alSoltar,
                  // La del `feedback` NO se marca: mientras se arrastra hay dos
                  // cabeceras montadas y dos con el mismo nombre no se pueden
                  // distinguir.
                  senalable: esLaPrimera,
                ),
              ),
              Expanded(
                child: DragTarget<TarjetaArrastrada>(
                  // Soltar en el hueco de abajo es «ponlo el ultimo».
                  onAcceptWithDetails: (detalles) =>
                      alSoltar(detalles.data, null),
                  builder: (contexto, encima, _) => Container(
                    decoration: BoxDecoration(
                      color: encima.isNotEmpty
                          ? tema.colorScheme.primary.withValues(alpha: 0.08)
                          : null,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(10),
                      ),
                    ),
                    child: tarjetas.isEmpty
                        ? _Vacia(encima: encima.isNotEmpty)
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 48),
                            itemCount: tarjetas.length,
                            itemBuilder: (contexto, i) => _Ranura(
                              // Soltar SOBRE una tarjeta es «ponlo aqui», en su
                              // sitio: el orden dentro de la columna es el orden de
                              // visita que propone quien conoce las calles.
                              alSoltar: (datos) =>
                                  alSoltar(datos, tarjetas[i].posicion),
                              hijo: TarjetaDePedido(
                                pedido: tarjetas[i].pedido,
                                columnaId: columna.id,
                                posicion: tarjetas[i].posicion,
                                onTap: () => alPulsarTarjeta(tarjetas[i]),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return ControlSenalado(
      nombre: Senalado.tableroSegundaZonaDondeSoltar,
      senalable: esLaSegunda,
      child: zona,
    );
  }
}

class _Cabecera extends ConsumerWidget {
  const _Cabecera({
    required this.columna,
    required this.alAbrirMenu,
    required this.alSoltar,
    this.senalable = false,
  });

  /// Si la Guia puede senalar los tres puntos de ESTA cabecera.
  final bool senalable;

  final ColumnaTablero columna;
  final VoidCallback alAbrirMenu;
  final void Function(TarjetaArrastrada datos, int? posicion) alSoltar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final excede = columna.excedeCamion;
    final capacidad = columna.vehiculoCapacidad;
    // LA CABECERA ES LO QUE SE AGARRA PARA REORDENAR LAS ZONAS, asi que es lo
    // que la Guia senala en ese paso. La del `feedback` llega con
    // `senalable: false`, que es lo que evita las dos a la vez mientras se
    // arrastra.
    return ControlSenalado(
      nombre: Senalado.tableroCabeceraDeLaZona,
      senalable: senalable,
      child: DragTarget<TarjetaArrastrada>(
        // Tambien se puede soltar en la cabecera: en el movil es lo que queda a
        // la vista cuando la columna esta llena.
        onAcceptWithDetails: (detalles) => alSoltar(detalles.data, null),
        builder: (contexto, encima, _) => Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          decoration: BoxDecoration(
            color: encima.isNotEmpty
                ? tema.colorScheme.primary.withValues(alpha: 0.12)
                : null,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${columna.nombre} (${columna.pedidos})',
                      style: tema.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ControlSenalado(
                    nombre: Senalado.tableroMenuDeLaZona,
                    senalable: senalable,
                    child: IconButton(
                      icon: const Icon(Icons.more_vert),
                      tooltip: 'Opciones de la columna',
                      visualDensity: VisualDensity.compact,
                      onPressed: alAbrirMenu,
                    ),
                  ),
                ],
              ),
              // `Wrap` Y NO `Row`: con la capacidad delante, «1.210 kg / 1.000 kg ·
              // 0,00 USD» mas el aviso no cabe en una columna de 300 px y un `Row`
              // se desborda —franja amarilla y negra— o, con `Expanded`, se come
              // con puntos suspensivos justo el numero que hay que leer. Aqui baja
              // a la linea de abajo y se lee entero.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  Text(
                    // CUÁNTO LLEVA **Y CUÁNTO CABE**, como el paso 3 del
                    // asistente de rutas («0.0 / 1000 kg»). Sin el segundo número
                    // el peso no dice nada: no hay forma de saber que te estás
                    // pasando hasta que el camión está en el almacén, y para
                    // entonces la ruta ya se armó. Sin camión previsto se pinta
                    // sólo el peso: un «/ —» promete un tope que nadie ha puesto.
                    '${pesoBonito(columna.pesoKg)}'
                    '${capacidad == null ? '' : ' / ${pesoBonito(capacidad)}'} · '
                    '${dineroBonito(ref, columna.costoUsd)}',
                    style: tema.textTheme.bodySmall,
                  ),
                  // El exceso AVISA y no impide: el tablero es un borrador y el
                  // camion previsto es una intencion. La capacidad se comprueba
                  // donde importa, al armar la ruta (§7.3).
                  if (excede == true)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: ColoresTablero.ambar,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'no cabe',
                          style: tema.textTheme.bodySmall?.copyWith(
                            color: ColoresTablero.ambar,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      // Sin camion previsto NO se dice «cabe»: se dice que no se
                      // sabe, que es lo que pasa.
                      'Camión: ${columna.vehiculoNombre ?? '—'}',
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Una columna creada sin senal se puede usar igual; lo unico
                  // que se dice es que todavia no ha subido.
                  if (columna.rechazada)
                    insigniaAviso('rechazada')
                  else if (columna.sinSubir)
                    insigniaAviso('sin subir'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ranura extends StatelessWidget {
  const _Ranura({required this.hijo, required this.alSoltar});

  final Widget hijo;
  final void Function(TarjetaArrastrada datos) alSoltar;

  @override
  Widget build(BuildContext context) => DragTarget<TarjetaArrastrada>(
    onAcceptWithDetails: (detalles) => alSoltar(detalles.data),
    builder: (contexto, encima, _) => Container(
      decoration: encima.isEmpty
          ? null
          : BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(contexto).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
      child: hijo,
    ),
  );
}

class _Vacia extends StatelessWidget {
  const _Vacia({required this.encima});

  final bool encima;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        encima ? 'Suelta aquí' : 'Todavía no hay nada en esta zona',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}
