import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';

/// UN RECHAZO, con su motivo y su hora. La misma pieza en los dos sitios.
///
/// Vive suelta porque la miran dos pantallas distintas y **tienen que verse
/// igual**: la de Sincronizacion, que ensena lo que el servidor rechazo a los
/// diez aparatos, y el cajon de entregar el dia, que ensena lo que rechazo a
/// ESTE. Si cada una la pintara a su manera, quien mira las dos tendria que
/// aprender dos veces a leer lo mismo.
///
/// `rechazado` no se reintenta NI SE BORRA SOLO. Un apunte que desaparece solo
/// es trabajo perdido que nadie sabe que perdio, y esto es donde se ve.
///
/// Pero **una persona si puede decidir**, y eso faltaba. El pliego dice que el
/// rechazo se queda «hasta que una persona decida» y no habia con que decidir:
/// ni descartar ni reintentar. Jose, 16/09/2026: «no puedo borrar esas
/// notificaciones». Con diez repartidores y varios turnos por aparato, una
/// bandeja que solo crece deja de leerse, y entonces el rechazo que SI importaba
/// se pierde entre los viejos.
///
/// Los dos gestos van aqui, en la propia fila, porque es donde esta el motivo:
/// la decision se toma leyendolo, no en otra pantalla.
class FilaDeRechazo extends StatelessWidget {
  const FilaDeRechazo({
    required this.motivo,
    required this.quien,
    required this.horas,
    required this.peticion,
    this.alDescartar,
    this.alReintentar,
    this.senalarLosGestos = false,
    super.key,
  });

  /// El motivo LITERAL del servidor. Se pinta tal cual: es lo unico que le dice
  /// a alguien que hacer. «3 de los 8 pedidos ya están en otra ruta. Vuelve a
  /// elegirlos.» sirve; «Ha ocurrido un error», no.
  final String motivo;

  /// De quien es. En el cajon del propio aparato se queda vacio: ahi no hay a
  /// quien atribuirlo, es de quien esta mirando.
  final String quien;

  /// Las horas ya compuestas. Son DOS y las dos hacen falta: la del aparato
  /// —cuando se hizo de verdad— y la del servidor. Con ocho horas sin senal de
  /// por medio, no son la misma tarde.
  final String horas;

  /// `POST /api/routes/…/results`. Es lo que deja saber QUE se perdio.
  final String peticion;

  /// Quitarlo de en medio. `null` donde no se puede decidir: en la pantalla de
  /// Sincronizacion se ven los rechazos de LOS DIEZ aparatos, y el de otro no se
  /// toca desde aqui.
  final VoidCallback? alDescartar;

  /// Devolverlo a la cola. Se usa cuando lo que lo tumbaba ya no esta.
  final VoidCallback? alReintentar;

  /// SI ESTA FILA ES LA QUE LA GUIA SENALA.
  ///
  /// Lo decide **quien la pinta**, y no esta pieza, por lo mismo que en el resto
  /// de la casa: hay una fila por rechazo y dos marcas con el mismo nombre a la
  /// vez no se pueden distinguir, asi que solo la primera la lleva — y cual es la
  /// primera lo sabe la lista, no la fila.
  ///
  /// Por defecto `false`: la pantalla de Sincronizacion ensena los rechazos de
  /// los diez aparatos y alli no se decide nada (los dos gestos llegan en `null`).
  final bool senalarLosGestos;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colores.rojoFondo,
        border: Border.all(color: Colores.rojo.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.block_outlined, size: 18, color: Colores.rojo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  motivo,
                  style: tema.textTheme.bodyMedium?.copyWith(
                    color: Colores.rojo,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (quien.isNotEmpty)
            Text(
              quien,
              style: tema.textTheme.bodySmall?.copyWith(color: Colores.gris),
            ),
          if (horas.isNotEmpty)
            Text(
              horas,
              style: tema.textTheme.bodySmall?.copyWith(color: Colores.gris),
            ),
          Text(
            peticion,
            style: tema.textTheme.bodySmall?.copyWith(color: Colores.gris),
            overflow: TextOverflow.ellipsis,
          ),
          if (alDescartar != null || alReintentar != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (alReintentar != null)
                  ControlSenalado(
                    nombre: Senalado.rechazoReintentar,
                    senalable: senalarLosGestos,
                    child: TextButton.icon(
                      onPressed: alReintentar,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reintentar'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colores.primario,
                      ),
                    ),
                  ),
                if (alDescartar != null)
                  TextButton.icon(
                    onPressed: alDescartar,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Descartar'),
                    style: TextButton.styleFrom(foregroundColor: Colores.rojo),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
