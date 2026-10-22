import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/caja_de_numero.dart';
import '../../../diseno/lista_que_se_recoloca.dart';
import '../../../diseno/rango_de_fechas.dart';
import '../../../diseno/selector_multiple.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/proveedores.dart' show relojProvider;
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../datos/modelos.dart';
import '../estado/filtros_en_la_url.dart';
import '../estado/proveedores.dart';
import '../estado/seleccion.dart';
import 'acciones.dart';
import 'kit.dart';
import 'tarjeta.dart';

/// LA MITAD IZQUIERDA: los pedidos sin colocar, **del mas viejo al mas reciente
/// por la fecha de su factura**.
///
/// Hasta el 14/10/2026 iban por cercania al almacen, el mas cerca primero, y era
/// deliberado: es como se decide que se reparte hoy cuando no cabe todo. Amado
/// (issue 6, punto 2) pidio el orden cronologico, y lo que se pierde es ver lo
/// cercano de un golpe: los km siguen en cada tarjeta y en el filtro. El orden y
/// su porque, en `ConsultasTablero.sinColocar`.
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
  /// recoloca sola por la fecha de su factura.
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
    // Lo marcado CRUZADO con lo que se ve: una marca que un filtro esconde no
    // se cuenta ni se coloca.
    final marcadas = ref.watch(seleccionTableroProvider);
    final visibles = [for (final p in izquierda.pedidos) p.pedidoId];
    final lasMarcadas = [
      for (final id in visibles)
        if (marcadas.contains(id)) id,
    ];

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
                  pista: 'Cliente, operación, factura, dirección, artículo…',
                  alBuscar: (texto) => FiltrosEnLaUrl.poner(
                    context,
                    ref,
                    filtros.copiaCon(q: texto),
                  ),
                ),
              ),
            ),
            if (visibles.isNotEmpty)
              _BarraDeMarcar(
                visibles: visibles,
                marcadas: lasMarcadas,
                alColocar: () => unawaited(
                  AccionesTablero.colocarMarcadas(
                    context,
                    ref,
                    tablero: widget.tablero,
                    pedidoIds: lasMarcadas,
                  ),
                ),
              ),
            // «SE VEN 200 DE 300» TENÍA QUE LLEVAR A ALGUN SITIO — 17/09/2026.
            //
            // Decía «afina con los filtros» y ya. Y eso no es una salida: los
            // 100 que faltaban eran **los últimos de la lista** —entonces los más
            // lejanos al almacén, hoy los de factura más reciente—, o sea justo
            // los que no se encuentran afinando, porque quien los busca no sabe
            // ni qué municipio mirar.
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
                              ? 'Ninguna factura con estos filtros.'
                              : 'No queda ninguna factura por colocar.',
                          textAlign: TextAlign.center,
                          style: tema.textTheme.bodySmall,
                        ),
                      ),
                    )
                  // Al cambiar el almacén, los filtros o al colocar una, las
                  // tarjetas se deslizan a su sitio nuevo (Jose, 15/10/2026).
                  : ListaQueSeRecoloca(
                      claves: [for (final p in izquierda.pedidos) p.pedidoId],
                      child: ListView.builder(
                        itemCount: izquierda.pedidos.length,
                        // Sólo la primera tarjeta se deja senalar: hay una por
                        // pedido sin colocar y pueden ser setecientas.
                        itemBuilder: (contexto, i) => SeRecoloca(
                          key: ValueKey(izquierda.pedidos[i].pedidoId),
                          clave: izquierda.pedidos[i].pedidoId,
                          child: ControlSenalado(
                            nombre: Senalado.tableroTarjetaDePedido,
                            senalable: i == 0,
                            child: TarjetaDePedido(
                              pedido: izquierda.pedidos[i],
                              marcada: marcadas.contains(
                                izquierda.pedidos[i].pedidoId,
                              ),
                              alMarcar: () => ref
                                  .read(seleccionTableroProvider.notifier)
                                  .alternar(izquierda.pedidos[i].pedidoId),
                              onTap: () =>
                                  widget.alPulsarTarjeta(izquierda.pedidos[i]),
                            ),
                          ),
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

/// MARCAR VARIAS Y COLOCARLAS DE UNA VEZ (issue 21 de Maikel, Santiago).
///
/// La casilla marca o desmarca **las que se ven** —con los filtros puestos, y si
/// la lista está acotada («Se ven 200 de 300») sólo esas 200—: filtrando por
/// municipio y marcando todo, el municipio entero va a una zona en un gesto.
class _BarraDeMarcar extends ConsumerWidget {
  const _BarraDeMarcar({
    required this.visibles,
    required this.marcadas,
    required this.alColocar,
  });

  final List<String> visibles;
  final List<String> marcadas;
  final VoidCallback alColocar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final todas = marcadas.length == visibles.length;
    final seleccion = ref.read(seleccionTableroProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Checkbox(
            key: const ValueKey('marcar-todas'),
            tristate: true,
            value: todas ? true : (marcadas.isEmpty ? false : null),
            onChanged: (_) => seleccion.marcar(visibles, marcar: !todas),
            visualDensity: VisualDensity.compact,
          ),
          Text(
            marcadas.isEmpty
                ? 'Marcar las ${visibles.length} que se ven'
                : '${marcadas.length} '
                      '${marcadas.length == 1 ? 'marcada' : 'marcadas'}',
            style: tema.textTheme.labelMedium,
          ),
          if (marcadas.isNotEmpty) ...[
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('colocar-marcadas'),
              onPressed: alColocar,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Colocar en una zona'),
            ),
          ],
        ],
      ),
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
        // DESDE/HASTA Y NO UN DÍA (issue 13 de Amado, 15/10/2026): los mismos
        // controles y la misma fecha DEL PEDIDO que Pedidos, `sólo ese día` para
        // el día suelto de antes y la ✕ para volver a «todos».
        RangoDeFechas(
          desde: filtros.desde,
          hasta: filtros.hasta,
          tituloDesde: 'Desde (fecha de la factura)',
          tituloHasta: 'Hasta (fecha de la factura)',
          hoy: ref.watch(relojProvider)(),
          alCambiar: (desde, hasta) => poner(
            filtros.copiaCon(
              desde: desde,
              quitarDesde: desde == null,
              hasta: hasta,
              quitarHasta: hasta == null,
            ),
          ),
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
        // VARIOS VENDEDORES A LA VEZ (issue 18 de Amado, 16/10/2026): «pueden haber
        // pocos domicilios y se combinan los de ambos». Salen los pedidos de CUALQUIERA
        // de los marcados. Es un cajón con casillas (`SelectorMultiple`), y de paso se
        // va el `isExpanded: false` del desplegable de antes, que desbordaba a 390 px.
        Text(
          'Vendedor',
          style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
        ),
        const SizedBox(height: 6),
        SelectorMultiple(
          key: const ValueKey('Vendedor del pedido'),
          titulo: 'Vendedor de la factura',
          todos: 'Todos los vendedores',
          plural: 'vendedores',
          expandido: true,
          opciones: [for (final v in vendedores) OpcionMultiple(v)],
          seleccion: filtros.vendedores,
          alCambiar: (elegidos) =>
              poner(filtros.copiaCon(vendedores: elegidos)),
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
