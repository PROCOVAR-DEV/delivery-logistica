import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/caja_de_numero.dart';
import '../../../diseno/rango_de_fechas.dart';
import '../../../diseno/tema.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../datos/modelos.dart';
import '../estado/filtros_en_la_url.dart';
import '../estado/proveedores.dart';
import 'kit.dart';
import 'tarjeta.dart';

/// LA MITAD IZQUIERDA: los pedidos sin colocar, **ordenados por cercania al
/// almacen, el mas cerca primero**.
///
/// Ese orden es la mitad del encargo: es como se decide que se reparte hoy
/// cuando no cabe todo. Lo que esta cerca sale igual, porque cuesta poco; lo que
/// esta lejos espera al dia en que haya suficiente para ese lado.
class PanelSinColocar extends ConsumerStatefulWidget {
  const PanelSinColocar({
    required this.tablero,
    required this.alPulsarTarjeta,
    required this.alDevolver,
    this.conRotulo = true,
    super.key,
  });

  final Tablero tablero;
  final void Function(TarjetaPedido pedido) alPulsarTarjeta;

  /// Arrastrar de vuelta a la izquierda: vuelve a «sin colocar» y la lista lo
  /// recoloca sola por cercania.
  final void Function(TarjetaArrastrada datos) alDevolver;

  /// SI ESTA CABECERA DICE «Sin colocar (308)» O SE CALLA.
  ///
  /// En el movil se calla, porque el rotulo del carrusel de arriba ya lo dice y
  /// repetir el mismo numero dos dedos mas abajo es escribirlo dos veces. En
  /// escritorio no hay carrusel —se ven las dos mitades a la vez— y esta
  /// cabecera es lo unico que dice de que va esta columna.
  ///
  /// Lo decide QUIEN LLAMA y no un `MediaQuery` de aqui dentro: el que parte la
  /// pantalla es un `LayoutBuilder` que mide de verdad lo que hay, y preguntarle
  /// al `MediaQuery` por su cuenta es como se acaba con la cabecera escondida en
  /// una pantalla ancha.
  final bool conRotulo;

  @override
  ConsumerState<PanelSinColocar> createState() => _PanelSinColocarState();
}

class _PanelSinColocarState extends ConsumerState<PanelSinColocar> {
  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final filtros = ref.watch(filtrosTableroProvider);
    final izquierda = widget.tablero.sinColocar;

    return DragTarget<TarjetaArrastrada>(
      onAcceptWithDetails: (detalles) => widget.alDevolver(detalles.data),
      builder: (contexto, encima, _) => Container(
        color: encima.isEmpty
            ? null
            : tema.colorScheme.primary.withValues(alpha: 0.08),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  // El rotulo, si toca. El porque, en `conRotulo`.
                  if (widget.conRotulo)
                    Expanded(
                      child: Text(
                        'Sin colocar (${izquierda.total})',
                        style: tema.textTheme.titleSmall,
                      ),
                    )
                  else
                    const Spacer(),
                  ControlSenalado(
                    nombre: Senalado.tableroSinColocarFiltros,
                    child: IconButton(
                      icon: Badge(
                        isLabelVisible: filtros.hayAlguno,
                        child: const Icon(Icons.filter_list),
                      ),
                      tooltip: 'Filtros',
                      onPressed: _abrirFiltros,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // LA CAJA DE LA CASA, y aqui es donde faltaba — 22/09/2026.
              //
              // Esto era un `TextField` con `onSubmitted` y nada mas: se
              // escribia `DAYLIS` y no pasaba NADA hasta pulsar Intro. Palabras
              // de Jose: «tengo q dar enter para q el filtro funcione». Nadie
              // pulsa Intro en un buscador.
              //
              // `ancho: null` = el ancho de la columna, que es lo que habia.
              child: ControlSenalado(
                nombre: Senalado.tableroSinColocarBuscar,
                child: CajaDeBusqueda(
                  valor: filtros.q ?? '',
                  ancho: null,
                  // La misma caja de la lista de pedidos, contenido de los
                  // renglones incluido: «¿que pedidos llevan malta?».
                  pista: 'Cliente, operación, dirección, artículo…',
                  alBuscar: (texto) => FiltrosEnLaUrl.poner(
                    context,
                    ref,
                    filtros.copiaCon(q: texto),
                  ),
                ),
              ),
            ),
            // «SE VEN 200 DE 300» TENÍA QUE LLEVAR A ALGUN SITIO — 17/09/2026.
            //
            // Decía «afina con los filtros» y ya. Y eso no es una salida: los
            // 100 que faltaban eran **los más lejanos al almacén** —la lista va
            // ordenada por cercanía—, o sea justo los que no se encuentran
            // afinando, porque quien los busca no sabe ni qué municipio mirar.
            // No había forma de verlos. Ninguna.
            //
            // Es el §3 del CLAUDE.md otra vez: se pidió un tope y no se puso
            // manera de pedir la tanda siguiente. Aquí es barato, además: los
            // pedidos ya están todos en la base de este aparato, así que subir
            // el tope no cuesta ni una petición.
            if (izquierda.truncada)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Se ven ${izquierda.pedidos.length} de '
                        '${izquierda.total}.',
                        style: tema.textTheme.labelSmall?.copyWith(
                          color: ColoresTablero.ambar,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(filtrosTableroProvider.notifier)
                          .poner(
                            filtros.copiaCon(
                              limite: filtros.limite + FiltrosSinColocar.tanda,
                            ),
                          ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: ColoresTablero.ambar,
                        textStyle: tema.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(
                        'Ver ${izquierda.total - izquierda.pedidos.length} más',
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: izquierda.pedidos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          filtros.hayAlguno
                              ? 'Ningún pedido con estos filtros.'
                              : 'No queda ningún pedido por colocar.',
                          textAlign: TextAlign.center,
                          style: tema.textTheme.bodySmall,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: izquierda.pedidos.length,
                      // Sólo la primera tarjeta se deja senalar: hay una por
                      // pedido sin colocar y pueden ser setecientas.
                      itemBuilder: (contexto, i) => ControlSenalado(
                        nombre: Senalado.tableroTarjetaDePedido,
                        senalable: i == 0,
                        child: TarjetaDePedido(
                          pedido: izquierda.pedidos[i],
                          onTap: () =>
                              widget.alPulsarTarjeta(izquierda.pedidos[i]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirFiltros() async {
    final facetas = await ref
        .read(consultasTableroProvider)
        .facetas(widget.tablero.sucursalId);
    if (!mounted) return;
    await mostrarCajon<void>(
      context: context,
      titulo: 'Filtros',
      contenido: (contexto) =>
          _Filtros(municipios: facetas.$1, vendedores: facetas.$2),
    );
  }
}

class _Filtros extends ConsumerWidget {
  const _Filtros({required this.municipios, required this.vendedores});

  final List<String> municipios;
  final List<String> vendedores;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtros = ref.watch(filtrosTableroProvider);
    void poner(FiltrosSinColocar nuevos) =>
        FiltrosEnLaUrl.poner(context, ref, nuevos);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // EL CALENDARIO DE LA CASA, no `showDatePicker`.
        //
        // Este era el cuarto modal de fecha de la aplicación, y el que peor
        // sentaba: el panel de filtros ya es un cajón, así que tocar «Día del
        // pedido» abría una ventana modal ENCIMA del cajón. Aquí no hay
        // modales —excepción aprobada el 05/09/2026, escrita en
        // `diseno/rango_de_fechas.dart`, en `pantallas.md` §0 y §9.2 y en el §4
        // del CLAUDE.md—, y `CampoDeFecha` ancla el calendario al botón.
        //
        // Era además la cuarta ventana distinta: abría desde 2024, mientras
        // Informes abría desde `año−5` y el asistente desde `hoy−30 días`. Las
        // cuatro son ahora la de la casa: 2020 → año que viene.
        //
        // La ✕ se queda como estaba: `CampoDeFecha` sólo entrega fechas de
        // verdad, así que volver a «Todos» necesita su propio botón.
        Row(
          children: [
            Expanded(
              child: CampoDeFecha(
                titulo: 'Día del pedido',
                valor: filtros.dia,
                alElegir: (d) => poner(filtros.copiaCon(dia: d)),
              ),
            ),
            if (filtros.dia != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Quitar el día',
                visualDensity: VisualDensity.compact,
                onPressed: () => poner(filtros.copiaCon(quitarDia: true)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // LOS DOS DESPLEGABLES DE AQUI VAN CON `isExpanded` — 26/09/2026.
        //
        // En el barrido de los cuatro anchos, el de **Vendedor** desbordaba a
        // 390 px con el cajon de filtros abierto: `A RenderFlex overflowed by
        // 20 pixels on the right.` Lo que se sale por la derecha es la flecha
        // del desplegable, o sea **la unica pista de que eso se puede tocar**,
        // encima de la franja amarilla y negra.
        //
        // No es culpa de estos nombres: `DropdownButton` sin `isExpanded` monta
        // su fila interna con `mainAxisSize: min` y NO envuelve el hijo en un
        // `Expanded`, asi que el texto pide su ancho natural. Un vendedor con
        // nombre y dos apellidos —«Luis Alberto Dominguez Hernandez», que es
        // como vienen de PEDIDO— ya basta. Y el municipio va igual aunque hoy
        // no lo cace nadie: es el mismo desplegable con datos del mismo sitio,
        // y «Santa Cruz del Sur» o «San Miguel del Padron» son municipios de
        // verdad. Arreglar solo el que salto deja el hermano esperando al dia
        // que llegue un nombre un poco mas largo.
        //
        // La elipsis va aparte de `isExpanded`: con el hijo ya acotado, un
        // nombre largo se partiria en dos lineas dentro de una caja de alto
        // fijo. Cortar con «…» se puede porque el nombre entero se lee al
        // desplegar la lista.
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: filtros.municipio,
          decoration: const InputDecoration(
            labelText: 'Municipio',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String>(child: Text('Todos')),
            for (final m in municipios)
              DropdownMenuItem<String>(
                value: m,
                child: Text(m, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (valor) => poner(
            valor == null
                ? filtros.copiaCon(quitarMunicipio: true)
                : filtros.copiaCon(municipio: valor),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: false,
          initialValue: filtros.vendedor,
          decoration: const InputDecoration(
            labelText: 'Vendedor',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String>(child: Text('Todos')),
            for (final v in vendedores)
              DropdownMenuItem<String>(
                value: v,
                child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (valor) => poner(
            valor == null
                ? filtros.copiaCon(quitarVendedor: true)
                : filtros.copiaCon(vendedor: valor),
          ),
        ),
        const SizedBox(height: 12),
        // EL TOPE DE KM, SIN PEDIR INTRO — 22/09/2026.
        //
        // Era un `TextFormField` con `onFieldSubmitted` a secas: escribir `12` y
        // pasar al filtro de al lado no hacia nada, y en la misma columna la
        // caja de buscar ya aplica sola. Jose: «tengo q dar enter para q el
        // filtro funcione… ahi en tableros».
        //
        // `CajaDeNumero` y no una caja escrita aqui: un numero NO lleva el
        // respiro de la caja de buscar —tecleando `12` se aplicaria primero `1`,
        // que es un tope valido y deja la lista casi vacia—, asi que aplica al
        // salir del campo, con Intro para quien tiene el habito, y lo que no es
        // un numero devuelve el campo a lo aplicado en vez de dejar la pantalla
        // diciendo una cosa y el filtro haciendo otra.
        //
        // La etiqueta va arriba, como la del cobro del domicilio: el `hintText`
        // de la caja desaparece en cuanto hay algo escrito, y un campo con un
        // numero suelto y sin nombre no dice de que es.
        Text(
          'Hasta cuántos km del almacén',
          style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
        ),
        const SizedBox(height: 6),
        CajaDeNumero(
          valor: filtros.kmMax,
          ancho: null,
          pista: 'Sin tope',
          alAplicar: (valor) => poner(
            valor == null
                ? filtros.copiaCon(quitarKmMax: true)
                : filtros.copiaCon(kmMax: valor),
          ),
        ),
        const SizedBox(height: 12),
        // EL COBRO DEL DOMICILIO, que decide si un pedido se puede repartir hoy.
        //
        // El costo lo pone el repartidor desde Entrega, y sin el no se sabe lo
        // que cuesta llevarlo. Las dos preguntas hacen falta: «que puedo
        // repartir ya» y «que esta esperando a que le pongan el costo» —esta
        // segunda es una lista de trabajo para otra persona—.
        //
        // Segmentos y no un desplegable: son tres opciones cortas y excluyentes,
        // y asi se ve de un vistazo cual esta puesta sin abrir nada.
        Text(
          'Cobro del domicilio',
          style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
        ),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment<int>(value: 0, label: Text('Todos')),
            ButtonSegment<int>(value: 1, label: Text('Con cobro')),
            ButtonSegment<int>(value: 2, label: Text('Sin cobro')),
          ],
          selected: {
            switch (filtros.conCobroDeDomicilio) {
              null => 0,
              true => 1,
              false => 2,
            },
          },
          onSelectionChanged: (cual) => poner(switch (cual.first) {
            1 => filtros.copiaCon(conCobroDeDomicilio: true),
            2 => filtros.copiaCon(conCobroDeDomicilio: false),
            _ => filtros.copiaCon(quitarCobroDeDomicilio: true),
          }),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => poner(const FiltrosSinColocar()),
          child: const Text('Quitar todos los filtros'),
        ),
      ],
    );
  }
}
