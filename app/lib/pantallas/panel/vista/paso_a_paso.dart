import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/frescura/primera_bajada.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../datos/configuracion_pendiente.dart';
import '../estado/configuracion_estado.dart';

/// EL PASO A PASO DE LA PUESTA EN MARCHA — lo primero del Panel cuando falta
/// algo, y nada en absoluto cuando no falta.
///
/// ## Por que vive en el Panel y no en una pantalla propia
///
/// Porque tiene que verlo **quien entra y le falta algo, sin ir a buscarlo**.
/// El Panel es la primera pantalla de la manana (`rutas.dart`, `rutaDeInicio`):
/// una pantalla «Puesta en marcha» en el menu sólo la abre quien ya sospecha que
/// falta algo, y quien sospecha eso no es el que se encuentra Vehiculos vacio.
/// Tampoco va en el armazon —siete pantallas con la misma banda encima es una
/// banda que nadie lee—, y ademas `lib/navegacion/` es de otro.
///
/// ## Quien manda cuando coincide con el estado del dia
///
/// `EstadoDelDia` ya ocupa el sitio de arriba del Panel con el gesto del dia
/// (traer / enviar). Cuando los dos tienen algo que decir, **el paso a paso va
/// encima**, y no es un capricho:
///
///  * **Si el aparato no tiene datos, este widget NO SE PINTA** (la regla vive
///    en `ElPasoAPaso.seEnsena`). Sin nada bajado no se sabe que falta, y poner
///    cuatro pasos en «no se sabe» justo encima del boton que los resolveria es
///    tapar la respuesta con la pregunta. Ahi manda `EstadoDelDia`: lo primero
///    es traer el dia.
///  * **Si el aparato ya tiene datos y falta configuracion, manda configurar.**
///    Volver a traer el dia no va a hacer aparecer un camion que nadie ha dado
///    de alta, asi que el gesto de sincronizar, puesto primero, seria el consejo
///    equivocado repetido cada manana.
///
/// O sea: los dos nunca compiten por el primer sitio. Cuando este aparece, es
/// porque el otro ya no es lo que toca.
class PasoAPaso extends ConsumerWidget {
  const PasoAPaso({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(pasoAPasoProvider).value;
    final porQue = ref.watch(porQueEstaVacioProvider);
    // Mientras se mira la base no se pinta nada. Un hueco que aparece medio
    // segundo despues empuja el Panel entero hacia abajo debajo del dedo.
    if (estado == null || !estado.seEnsena) return const SizedBox.shrink();

    // EN LA WEB, MIENTRAS LA PRIMERA BAJADA VA EN CAMINO, ESTO NO SE PINTA.
    //
    // Es el fallo del 17/09/2026: la base de la web nace vacia en cada carga de
    // la pagina, asi que durante un segundo los cuatro pasos estan en «no se
    // sabe» y los que ya bajaron, no. Con eso bastaba para que el Panel dijera
    // «Falta configurar esta sucursal» y señalara un almacen que existia y
    // todavia no habia llegado. Jose: «Eso no puede pasar mi loco».
    //
    // No se pinta un «cargando» en su sitio a proposito: este widget ya es el
    // que no ocupa nada cuando no hay nada que decir, y meter una rueda donde
    // luego no va a haber nada empuja el Panel entero hacia abajo para
    // devolverlo medio segundo despues.
    //
    // **El suelo esta puesto en `primera_bajada.dart`**: esto deja de ser
    // `todaviaBajando` en cuanto termina un ciclo o a los 20 s, pase lo que
    // pase. No hay forma de que el paso a paso se quede escondido para siempre.
    if (porQue == PorQueEstaVacio.todaviaBajando && estado.algoSinMirar) {
      return const SizedBox.shrink();
    }

    final pendientes = estado.pendientes;
    final hechos = estado.hechos;
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.entrega;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: Aire.xl),
      padding: EdgeInsets.all(estrecho ? Aire.lg : Aire.xl),
      decoration: BoxDecoration(
        color: Colores.blanco,
        borderRadius: BorderRadius.circular(Radios.xl),
        border: Border.all(color: Colores.ambar.withValues(alpha: 0.35)),
        boxShadow: Sombras.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.checklist_rtl_outlined,
                size: 20,
                color: Colores.ambar,
              ),
              const SizedBox(width: Aire.sm),
              Expanded(
                child: Text(
                  // EL TITULO NO PUEDE ACUSAR DE ALGO QUE NO SE HA MIRADO.
                  //
                  // «Falta configurar esta sucursal» sólo es verdad si hay algun
                  // paso que se miro y no estaba. Con todos los pendientes en
                  // «no se sabe» —una coleccion que aun no bajo— lo que falta es
                  // la bajada, no la configuracion, y mandar a alguien a dar de
                  // alta un almacen que ya existe es justo lo que esto evita.
                  estado.faltaAlgoDeVerdad
                      ? tituloDeLoQueFalta(estado)
                      : tituloDeLoQueFaltaPorBajar(porQue),
                  style: Tipos.texto(
                    tamano: 17,
                    peso: FontWeight.w700,
                    color: Colores.tinta,
                  ),
                ),
              ),
              Text(
                '${hechos.length} de ${estado.pasos.length}',
                style: Tipos.mono(
                  tamano: 12,
                  peso: FontWeight.w600,
                  color: Colores.tintaSuave,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            // Con varias a la vista se dice que la cuenta es por sucursal: sin
            // eso, «Al menos un vehículo» en rojo teniendo camiones delante se
            // lee como un fallo de la pantalla, y se deja de leer.
            estado.sucursales > 1
                ? 'Un paso sólo está hecho cuando lo está en TODAS las '
                      'sucursales que estás mirando. Van en este orden: cada '
                      'uno necesita el anterior.'
                : 'Sin esto no se puede armar una ruta. Van en este orden: cada '
                      'uno necesita el anterior.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colores.tintaSuave),
          ),
          const SizedBox(height: Aire.lg),

          // LOS QUE FALTAN, enteros. Numerados con el sitio que ocupan en la
          // lista completa —«3 de 4»— y no con el sitio que ocupan entre los que
          // faltan: si no, al hacer uno los demas se renumerarian y el paso 3 de
          // ayer seria el 2 de hoy.
          for (final (cual, paso) in pendientes.indexed) ...[
            _PasoQueFalta(
              numero: estado.pasos.indexOf(paso) + 1,
              total: estado.pasos.length,
              paso: paso,
              porQue: porQue,
              // Sólo el primero que falta se deja senalar por la Guia.
              esElPrimeroQueFalta: cual == 0,
            ),
            const SizedBox(height: Aire.md),
          ],

          // LOS QUE YA ESTAN: una linea y fuera del camino. Se dicen —para que
          // se vea que el paso a paso los miro y no se los saltó— pero no
          // ocupan.
          if (hechos.isNotEmpty) ...[
            const SizedBox(height: Aire.xs),
            for (final paso in hechos) _PasoHecho(paso: paso),
          ],
        ],
      ),
    );
  }
}

/// EL TITULO CUANDO ALGO FALTA DE VERDAD.
///
/// **Con una sola sucursal a la vista es el de siempre, palabra por palabra.**
/// Ese es el caso que usa todo el mundo —cinco de los siete roles pertenecen a
/// una sucursal— y arreglar el de «todas» no puede rozarlo.
///
/// Con varias, «esta sucursal» es mentira dos veces: no hay ninguna «esta», y
/// no dice en cual falta que. Un aviso que no nombra a nadie no lo arregla
/// nadie. Asi que se dice **en cuantas de cuantas**, y cada paso dice luego en
/// cuantas falta el (`PasoDeConfiguracion.enCuantasFalta`).
String tituloDeLoQueFalta(ElPasoAPaso estado) => estado.sucursales > 1
    ? 'Faltan cosas por configurar en ${estado.sucursalesConAlgoQueFalta} '
          'de las ${estado.sucursales} sucursales'
    : 'Falta configurar esta sucursal';

/// EL TITULO CUANDO LO UNICO PENDIENTE ES QUE BAJE.
///
/// Dos textos y no uno porque son dos situaciones distintas: en el aparato se
/// arregla trayendo el dia —hay un boton justo debajo— y en la web no hay dia
/// que traer ni aparato al que traerselo.
String tituloDeLoQueFaltaPorBajar(PorQueEstaVacio porQue) => switch (porQue) {
  PorQueEstaVacio.noSeDescargo => 'Falta por traer parte de la configuración',
  PorQueEstaVacio.todaviaBajando => 'Todavía está bajando la configuración',
  PorQueEstaVacio.noPudoBajar => 'No se pudo traer la configuración',
};

/// Un paso pendiente. Dice **que es**, **que pasa si falta** y **a donde ir**.
class _PasoQueFalta extends StatelessWidget {
  const _PasoQueFalta({
    required this.numero,
    required this.total,
    required this.paso,
    required this.porQue,
    this.esElPrimeroQueFalta = false,
  });

  /// Si la Guia puede senalar el boton de ESTE paso. Sólo el primero pendiente:
  /// hay un boton por paso y dos con el mismo nombre no se distinguen.
  final bool esElPrimeroQueFalta;

  final int numero;
  final int total;
  final PasoDeConfiguracion paso;

  /// Por que esta vacia la copia. Sólo cambia lo que se lee en los pasos que
  /// **no se han mirado**; lo que de verdad falta se dice igual en los tres
  /// destinos.
  final PorQueEstaVacio porQue;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    // EL COLOR SEPARA LOS DOS ESTADOS. Ambar = falta, hay que hacerlo. Azul =
    // no se sabe todavia, y se arregla trayendo el dia. Con el mismo color los
    // dos se leen igual, que es el fallo que esto viene a quitar.
    final sinSaber = paso.como == ComoVa.sinSaber;
    final color = sinSaber ? Colores.enCurso : Colores.ambar;
    final fondo = sinSaber ? Colores.enCursoFondo : Colores.ambarFondo;

    final ruta = paso.ruta;
    final donde = paso.dondeSeArregla;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Aire.md),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(Radios.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '$numero/$total',
                  style: Tipos.mono(
                    tamano: 12,
                    peso: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paso.titulo,
                      style: Tipos.texto(
                        tamano: 14,
                        peso: FontWeight.w600,
                        color: Colores.tinta,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Que es y para que sirve, siempre; y debajo, que pasa si
                    // falta. Las dos: la primera dice de que se habla y la
                    // segunda es la que hace que alguien lo haga hoy.
                    Text(
                      paso.paraQue,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: Colores.tintaSuave,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      paso.explicacionEn(porQue),
                      style: tema.textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // EL BOTON SOLO SI LLEVA A ALGUN SITIO.
          //
          //  * Falta y se arregla aqui   → boton a su pantalla.
          //  * No se sabe               → no hay boton propio: se arregla con
          //    «Traer el día», que es el gesto que ya esta justo debajo, en
          //    `EstadoDelDia`. Poner aqui un segundo boton que hace lo mismo son
          //    dos puertas a la misma habitacion.
          //  * No se arregla en esta aplicacion (el punto de partida y la tasa)
          //    → se dice donde se arregla, en texto. **Nunca un boton apagado**:
          //    uno gris invita a pulsarlo igual, y uno que lleva a una pantalla
          //    donde el problema no se toca es peor que ninguno.
          if (!sinSaber && ruta != null) ...[
            const SizedBox(height: Aire.sm),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Align(
                alignment: Alignment.centerLeft,
                // Sólo el PRIMER paso que falta se deja senalar por la Guia: hay
                // un boton por paso pendiente y el recorrido sólo puede senalar
                // uno. El primero es ademas el que toca hacer
                // (`pantallas/ayuda/vista/control_senalado.dart`).
                child: ControlSenalado(
                  nombre: Senalado.panelArreglarElPaso,
                  senalable: esElPrimeroQueFalta,
                  child: BotonPrincipal(
                    // EL GLIFO LO TRAE EL PASO, no este fichero: cada uno lleva
                    // a una pantalla distinta. `Icons.arrow_forward` es el
                    // ultimo recurso del paso que no dijo el suyo, y sigue
                    // siendo honesto — «ir» es literalmente lo que hace el
                    // mando.
                    icono: paso.iconoDelBoton ?? Icons.arrow_forward,
                    texto: paso.textoDelBoton ?? 'Ir',
                    alPulsar: () => context.go(ruta),
                  ),
                ),
              ),
            ),
          ] else if (!sinSaber && donde != null) ...[
            const SizedBox(height: Aire.sm),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 15, color: Colores.tintaSuave),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      donde,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: Colores.tintaSuave,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Un paso ya hecho: una linea gris con su marca y nada mas.
class _PasoHecho extends StatelessWidget {
  const _PasoHecho({required this.paso});

  final PasoDeConfiguracion paso;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(Icons.check_circle_outline, size: 16, color: Colores.verde),
        const SizedBox(width: Aire.sm),
        Expanded(
          child: Text(
            paso.titulo,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colores.tintaSuave),
          ),
        ),
      ],
    ),
  );
}
