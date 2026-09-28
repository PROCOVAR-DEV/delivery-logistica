// La pantalla de Pedidos.
//
// Lectura pura: aqui no se escribe nada y por eso no toca la cola. Lo que si
// hace, y es la mitad del valor de la pantalla, es SUMAR el pre-despacho: cuanto
// hay que sacar del almacen de lo filtrado o de lo marcado a mano.
//
// Todo sale de la base local. Sin conexion funciona entero —los 9 filtros, el
// orden de la pagina, la ficha, la seleccion y los dos pre-despachos—; lo unico
// que cambia es lo que dice el reloj de datos de arriba.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/barra_de_filtros.dart';
import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/rango_de_fechas.dart';
import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tema.dart';
import '../../../impresion/hoja.dart' as papel;
import '../../../impresion/pre_despacho.dart' show pdfPreDespacho;
import '../../../impresion/vista_previa.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/primera_bajada.dart';
import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../../nucleo/proveedores.dart';
import '../datos/filtros_en_la_url.dart';
import '../datos/filtros_pedidos.dart';
import '../datos/formato.dart';
import '../datos/repositorio_pedidos.dart';
import '../estado/proveedores_pedidos.dart';
import 'cajon_detalle_pedido.dart';
import 'cajon_mandar_al_tablero.dart';
import 'kit.dart';
import 'tabla_pedidos.dart';
import 'vista_pre_despacho.dart';

class PantallaPedidos extends ConsumerStatefulWidget {
  const PantallaPedidos({this.consulta = const <String, String>{}, super.key});

  /// Lo que venía en la dirección (`estado.uri.queryParameters`). Vacío cuando
  /// se pinta la pantalla suelta en una prueba, que es el caso de siempre.
  final Map<String, String> consulta;

  /// El texto literal de la franja azul del arranque acotado.
  static const franjaAzul =
      'Enseñando sólo lo que puede subir a un camión: lo que tiene factura '
      '—cuadre o no— y sin archivar. Lo que cambió también sube: se carga con '
      'las líneas de la factura, no con las del pedido.';

  /// El gesto de la barra de lo marcado que abre el cajón del tablero. Literal
  /// aquí arriba para que la prueba busque lo que lee quien está delante.
  static const mandarAUnaZona = 'Mandar a una zona';

  @override
  ConsumerState<PantallaPedidos> createState() => _PantallaPedidosState();
}

class _PantallaPedidosState extends ConsumerState<PantallaPedidos> {
  /// Lo que traía el enlace y no se pudo aplicar. Se lee UNA vez, al montar: a
  /// partir de ahí quien manda es la barra de filtros.
  late final List<String> _noSePudieron;

  @override
  void initState() {
    super.initState();
    final lectura = FiltrosEnLaUrl.leer(widget.consulta);
    _noSePudieron = lectura.noSePudieron;
    // FUERA DEL `build`. Tocar un provider mientras se pinta es el error que
    // Riverpod corta en seco; y va sólo si el enlace traía algo, para que abrir
    // `/orders` a pelo no pise unos filtros que ya estuvieran puestos.
    if (widget.consulta.isNotEmpty) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(filtrosPedidosProvider.notifier).poner(lectura.filtros);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtros = ref.watch(filtrosPedidosProvider);
    // LA DIRECCIÓN SIGUE A LOS FILTROS. Sin esto el enlace de la barra del
    // navegador se queda en `/orders` diga lo que diga la pantalla, y recargar
    // vuelve a la lista entera.
    _ponerEnLaDireccion(filtros);
    final total = ref.watch(totalPedidosProvider);
    final pagina = ref.watch(paginaPedidosProvider);
    final descargados = ref.watch(pedidosDescargadosProvider);

    // SIN `Scaffold` ni `AppBar` propios: los pone el armazon
    // (`navegacion/pantalla_registrada.dart`), que ya trae barra lateral, barra
    // superior con el titulo «Pedidos» y franja de estado. Uno dentro de otro
    // apila dos superficies de Material y deja los avisos emergentes colgando
    // del de dentro, que es el que no se ve entero.
    // `p-3 sm:p-6` de delivery.
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.idioma;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.all(estrecho ? Aire.md : Aire.xl),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Todos los pedidos acumulados de todas las rutas',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Colores.tintaSuave),
                ),
              ),
              // El reloj de datos de ESTA pantalla. La franja del armazon dice
              // la frescura global; esta dice la de las colecciones que se estan
              // mirando, que es lo que decide si se arma la ruta de hoy o la de
              // ayer (caso S8).
              const BarraDeDatos(colecciones: ColeccionesDePantalla.pedidos),
            ],
          ),
          // LO QUE EL ENLACE TRAÍA Y NO SE PUDO APLICAR, ANTES QUE NADA.
          //
          // Va encima de la franja azul y encima del conteo a propósito: quien
          // abrió un enlace tiene que enterarse de que la lista NO está acotada
          // como el enlace decía, antes de leer un número y creérselo.
          if (_noSePudieron.isNotEmpty) _FranjaNoSePudo(_noSePudieron),
          if (filtros.arranqueAcotado) const _FranjaAzul(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Aire.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    textoDelConteo(total.value ?? 0, filtros, fechaCorta),
                    style: Tipos.texto(
                      tamano: 13,
                      peso: FontWeight.w500,
                      color: Colores.tintaSuave,
                    ),
                  ),
                ),
                if (total.isLoading || pagina.isLoading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colores.tintaSuave,
                    ),
                  ),
              ],
            ),
          ),
          const _BarraDeFiltros(),
          const _PreDespachoDeLoElegido(),
          const SizedBox(height: Aire.lg),
          // Una lista vacia de una coleccion que nunca se bajo NO es «no hay
          // nada»: es un fallo que se lee como un dato (caso S7). Se dice con
          // otras palabras y antes de mirar el total.
          // La tabla y su paginacion van dentro de la MISMA caja blanca: en
          // delivery la paginacion es el pie de la tabla (`border-t bg-white`),
          // no una barra suelta debajo.
          TarjetaDeTabla(
            pie: (total.value ?? 0) > 0
                ? Paginacion(
                    pagina: filtros.pagina,
                    porPagina: ConsultasPedidos.porPagina,
                    total: total.value ?? 0,
                    alIr: (n) =>
                        ref.read(filtrosPedidosProvider.notifier).irAPagina(n),
                  )
                : null,
            // EN LA WEB SON TRES CASOS, NO UNO — 17/09/2026.
            //
            // Esta pantalla se quedó fuera de la pasada que separó los tres, y
            // era **la que Jose nombró**: en la web salía «Esta pantalla no se
            // ha descargado todavía. Con conexión baja sola» en cada carga,
            // porque su base nace vacía. Dos de las frases que él lleva todo el
            // día pidiendo que desaparezcan, en la pantalla de la queja.
            child: descargados.value == false
                ? switch (ref.watch(porQueEstaVacioProvider)) {
                    // El aparato: ahí «no se ha descargado» es un estado real.
                    PorQueEstaVacio.noSeDescargo => const EstadoVacio(
                      SinDescargar.textoDeLaPantallaVacia,
                    ),
                    // La web, el primer segundo: cargando y sin acusar a nadie.
                    PorQueEstaVacio.todaviaBajando => EstadoVacio(
                      TextosDeLaWeb.cargando('los pedidos'),
                    ),
                    // Y si no llegó, se dice y se deja entrar.
                    PorQueEstaVacio.noPudoBajar => EstadoVacio(
                      TextosDeLaWeb.noPudoBajar('los pedidos'),
                    ),
                  }
                : _Cuerpo(filtros: filtros, pagina: pagina, total: total),
          ),
        ],
      ),
    );
  }
}

/// LA DIRECCIÓN, AL DÍA CON LOS FILTROS.
///
/// Se llama desde el `build` pero no pinta nada: empuja la dirección nueva
/// **después** del fotograma, porque `context.go` en mitad de un `build`
/// reconstruye el árbol que se está construyendo.
///
/// Y sólo cuando de verdad cambia. Sin esa comparación, cada repintado —y hay
/// uno por cada emisión de los streams de la lista, o sea varios por segundo
/// mientras baja— metería una entrada en el historial del navegador, y volver
/// atrás sería pulsar cincuenta veces para salir de la pantalla.
extension _DireccionDePedidos on _PantallaPedidosState {
  void _ponerEnLaDireccion(FiltrosPedidos filtros) {
    final router = GoRouter.maybeOf(context);
    // Sin enrutador —una prueba que pinta la pantalla suelta— no hay dirección
    // que poner, y eso no puede ser un fallo.
    if (router == null) return;
    final destino = FiltrosEnLaUrl.direccion(filtros);
    if (router.state.uri.toString() == destino) return;
    // `replace` y no `go`: cambiar un filtro no es navegar a otro sitio.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final enElFotograma = GoRouter.of(context);
      // SI YA NO ESTAMOS EN PEDIDOS, NO SE TOCA LA DIRECCION — 24/09/2026.
      //
      // Esto dejaba el menu de la izquierda MUERTO en cuanto alguien abria
      // Pedidos: se pulsaba «Rutas», `context.go('/routes')` hacia su trabajo,
      // y un instante despues este `replace` —encolado desde el ultimo `build`
      // de una pantalla que todavia no se ha desmontado— volvia a poner
      // `/orders?...` encima. Desde la silla de quien trabaja: se entra en
      // Pedidos y **ya no se sale**. Ni error, ni aviso, ni nada; el resto de
      // la pantalla sigue respondiendo, asi que ni siquiera parece colgada.
      // Visto dos veces seguidas en el escritorio el 24/09/2026.
      //
      // `mounted` NO basta: entre el `go` y este callback la pantalla de antes
      // sigue montada, que es justo la ventana en la que esto muerde.
      if (enElFotograma.state.matchedLocation != FiltrosEnLaUrl.camino) return;
      if (enElFotograma.state.uri.toString() == destino) return;
      enElFotograma.replace(destino);
    });
  }
}

/// LO QUE EL ENLACE PEDÍA Y NO SE PUDO HACER, con su clave y su valor.
///
/// «No se pudo aplicar un filtro» no le dice nada a nadie; `desde=31-12-2026`
/// sí, porque quien mandó el enlace puede corregirlo. Es la misma regla del
/// §3-quinquies: el motivo literal o nada.
class _FranjaNoSePudo extends StatelessWidget {
  const _FranjaNoSePudo(this.cuales);

  final List<String> cuales;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: Aire.sm),
    padding: const EdgeInsets.all(Aire.lg),
    decoration: BoxDecoration(
      color: Colores.ambarFondo,
      border: Border.all(color: Colores.ambar.withValues(alpha: 0.45)),
      borderRadius: BorderRadius.circular(Radios.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${FiltrosEnLaUrl.noSePudieronAplicar}: ${cuales.join(', ')}.',
          style: Tipos.texto(
            tamano: 13,
            peso: FontWeight.w600,
            color: Colores.tinta,
            alto: 1.5,
          ),
        ),
        const SizedBox(height: Aire.xs),
        Text(
          FiltrosEnLaUrl.yPorEsoLaListaNoEstaAcotada,
          style: Tipos.texto(tamano: 13, color: Colores.tinta, alto: 1.5),
        ),
      ],
    ),
  );
}

class _FranjaAzul extends ConsumerWidget {
  const _FranjaAzul();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    margin: const EdgeInsets.only(top: Aire.sm),
    padding: const EdgeInsets.all(Aire.lg),
    decoration: BoxDecoration(
      color: Colores.enCursoFondo,
      border: Border.all(color: Colores.primario.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(Radios.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PantallaPedidos.franjaAzul,
          style: Tipos.texto(tamano: 13, color: Colores.tinta, alto: 1.5),
        ),
        const SizedBox(height: Aire.md),
        OutlinedButton(
          onPressed: () => ref.read(filtrosPedidosProvider.notifier).verTodos(),
          child: const Text('Ver todos los pedidos'),
        ),
      ],
    ),
  );
}

class _BarraDeFiltros extends ConsumerWidget {
  const _BarraDeFiltros();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtros = ref.watch(filtrosPedidosProvider);
    final notas = ref.read(filtrosPedidosProvider.notifier);
    final facetas = ref.watch(facetasPedidosProvider).value ?? Facetas.vacias;

    // La colocación la decide `BarraDeFiltros` y no esta pantalla: caja de
    // buscar arriba y a todo el ancho, y los desplegables en rejilla de dos
    // columnas iguales en el teléfono. Antes era un `Wrap` suelto, y a 390 px
    // eso dejaba 146 px muertos a la derecha de la caja y partía los siete
    // controles en escalones desiguales —seis o siete filas de filtros antes de
    // ver un solo pedido—. Ver `lib/diseno/barra_de_filtros.dart`.
    //
    // El margen lo pone la propia pantalla (`padding` del cuerpo), así que aquí
    // va a cero para no sumarlo dos veces.
    return BarraDeFiltros(
      margen: EdgeInsets.zero,
      // Busca sola a los 400 ms, y **se vacia cuando se vacian los
      // filtros**: antes se quedaba el texto puesto filtrando en silencio
      // debajo de una lista que ya no estaba filtrada.
      busqueda: CajaDeBusqueda(
        valor: filtros.q,
        alBuscar: (t) => notas.cambiar((f) => f.copiarCon(q: t)),
      ),
      // CADA FILTRO LLEVA SU CLAVE, Y ES LO QUE LE DA SU ANCHO — 28/09/2026.
      //
      // `BarraDeFiltros` reparte la fila del teléfono **a lo que mide cada
      // uno**, que es lo que pidió Jose: «esos campos son de ese mismo tamaño
      // en vez de repartirse para que quepan todos y con su respectivo
      // tamaño». Y lo único que esa capa sabe de un filtro es su clave: no
      // conoce `Selector` ni tiene por qué.
      //
      // Sin estas claves el reparto **no hacía nada**: `_peso` no encontraba
      // rótulo, devolvía el valor de en medio para todos y los cinco salían
      // iguales, o sea el 50/50 de antes con más código. Estuvo así desde que
      // se escribió, y no lo cazó nadie porque las pruebas de la barra montan
      // cajas que tampoco llevaban clave arriba.
      //
      // El texto es el `titulo` y no la opción elegida a propósito: la opción
      // cambia al elegir, y una clave que cambia le tira el estado al widget.
      // El `titulo` es estable y mide parecido, que es todo lo que hace falta
      // para repartir una fila.
      filtros: [
        Selector<RepartoFiltro>(
          key: const ValueKey('Estado de reparto en delivery'),
          titulo: 'Estado de reparto en delivery',
          valor: filtros.reparto,
          opciones: [
            for (final r in RepartoFiltro.values) OpcionSelector(r, r.etiqueta),
          ],
          alElegir: (r) => notas.cambiar((f) => f.copiarCon(reparto: r)),
        ),
        Selector<String>(
          key: const ValueKey('Municipio del cliente'),
          titulo: 'Municipio del cliente',
          valor: filtros.municipio,
          opciones: [
            const OpcionSelector('', 'Todos los municipios'),
            for (final m in facetas.municipios)
              OpcionSelector(m.valor, m.valor, nota: '${m.pedidos}'),
          ],
          alElegir: (m) => notas.cambiar((f) => f.copiarCon(municipio: m)),
        ),
        Selector<CotizadoFiltro>(
          key: const ValueKey('Precio del domicilio'),
          titulo: 'Precio del domicilio',
          valor: filtros.cotizado,
          opciones: [
            for (final c in CotizadoFiltro.values)
              OpcionSelector(c, c.etiqueta),
          ],
          alElegir: (c) => notas.cambiar((f) => f.copiarCon(cotizado: c)),
        ),
        Selector<String>(
          key: const ValueKey('Vendedor del pedido'),
          titulo: 'Vendedor del pedido',
          valor: filtros.vendedor,
          opciones: [
            const OpcionSelector('', 'Todos los vendedores'),
            for (final v in facetas.vendedores)
              OpcionSelector(v.valor, v.valor, nota: '${v.pedidos}'),
          ],
          alElegir: (v) => notas.cambiar((f) => f.copiarCon(vendedor: v)),
        ),
        Selector<OrdenLocal>(
          key: const ValueKey('Cómo se ordena esta página'),
          titulo: 'Cómo se ordena esta página',
          valor: filtros.orden,
          opciones: [
            for (final o in OrdenLocal.values) OpcionSelector(o, o.etiqueta),
          ],
          alElegir: (o) => notas.cambiar((f) => f.copiarCon(orden: o)),
        ),
      ],
      anchoCompleto: [
        // `Desde` / `Hasta` / `sólo ese día` / ✕. El SQL que acota por fecha
        // ya estaba escrito y la ✕ tambien; lo que no habia era con que PONER
        // las fechas, asi que «el pre-despacho de HOY» era inalcanzable.
        //
        // Va a fila entera y no a la rejilla: son dos botones más una ✕, y en
        // media columna se partían dejando la ✕ colgando sola.
        // LAS FECHAS Y EL PRE-DESPACHO, EN LA MISMA FILA — 28/09/2026.
        //
        // El pre-despacho estaba solo en una fila debajo de todo, con su hueco
        // a la derecha. Jose: «ahi mismo me tienes predespacho abajo podiendo
        // ponerlo al lado de fechas del pedido».
        //
        // Y van juntos porque son la misma pregunta: «de lo que estoy viendo,
        // que me llevo al papel». Acotar por fecha y sacar la hoja se hacen
        // seguidos, y tenerlos separados por una fila entera obligaba a bajar
        // la vista entre un gesto y el siguiente.
        //
        // `Wrap` y no `Row`: a 390 px no caben los dos, y entonces el
        // pre-despacho baja solo en vez de apretar las fechas.
        Wrap(
          spacing: Aire.sm,
          runSpacing: Aire.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            RangoDeFechas(
              desde: filtros.desde,
              hasta: filtros.hasta,
              tituloDesde: 'Desde (fecha del pedido)',
              tituloHasta: 'Hasta (fecha del pedido)',
              hoy: ref.watch(relojProvider)(),
              alCambiar: notas.ponerFechas,
            ),
            const _PreDespachoDeLoFiltrado(),
          ],
        ),
      ],
    );
  }
}

/// El dia tal y como lo escribe la hoja: `AAAA-MM-DD`, y **sólo cuando el rango
/// es un dia**, igual que la de Next. Con un rango de varios dias la cabecera
/// no dice ninguno: escribir uno de los dos seria mentir sobre lo que hay
/// debajo.
String? diaDeLaHoja(FiltrosPedidos f) {
  final desde = f.desde;
  if (desde == null || desde != f.hasta) return null;
  return '${desde.year.toString().padLeft(4, '0')}-'
      '${desde.month.toString().padLeft(2, '0')}-'
      '${desde.day.toString().padLeft(2, '0')}';
}

/// La hoja que se manda al PDF, como funcion pura.
///
/// Va aparte del widget porque es lo que de verdad lleva los numeros al papel:
/// asi se comprueba sin pintar nada. La usan los DOS botones `Ver e imprimir`
/// de esta pantalla —el de lo marcado y el de lo filtrado—, para que las dos
/// hojas salgan con la misma forma.
papel.HojaPreDespacho hojaDePreDespacho({
  required TotalesPreDespacho totales,
  required String sucursal,
  required String? dia,
}) => papel.HojaPreDespacho(
  sucursal: sucursal,
  // Pedidos no sabe de camiones: esta hoja sale del almacen, no de una ruta.
  vehiculo: '',
  dia: dia,
  pedidos: totales.pedidos,
  pesoKg: totales.pesoDeLosPedidos,
  lineas: [
    for (final linea in totales.lineas)
      papel.LineaPreDespacho(
        producto: linea.producto,
        formatos: linea.empaques,
        unidades: linea.unidades,
        pesoKg: linea.pesoKg,
      ),
  ],
);

/// Abre la hoja del pre-despacho: **se mira primero y se imprime desde la
/// propia vista previa**. Es el orden que tenia la de Next y el que tiene
/// sentido cuando quien saca la mercancia es otra persona.
void verEImprimirPreDespacho(
  BuildContext context, {
  required TotalesPreDespacho totales,
  required String sucursal,
  required String? dia,
}) {
  final hoja = hojaDePreDespacho(
    totales: totales,
    sucursal: sucursal,
    dia: dia,
  );

  abrirCajon<void>(
    context,
    (contexto) => Cajon(
      // `Hoja de pre-despacho`, no `Pre-despacho`: la vista previa del PDF se
      // abre ENCIMA de la vista, y con los dos cajones apilados y el mismo
      // título no había forma de saber cuál se estaba mirando.
      titulo: PreDespacho.tituloDeLaHoja,
      subtitulo:
          '${totales.pedidos} pedido(s) · '
          '${totales.pesoDeLosPedidos.toStringAsFixed(1)} kg',
      ancho: AnchoCajon.xl,
      // La vista previa quiere todo el alto que le den, y el cuerpo del cajon
      // es un desplazable: sin un alto concreto no hay nada que le diga
      // cuanto, y la hoja no llega a pintarse.
      cuerpo: SizedBox(
        height: MediaQuery.sizeOf(contexto).height * 0.75,
        child: VistaPreviaPdf(
          armar: (formato) => pdfPreDespacho(hoja, impresoEn: DateTime.now()),
          nombreDeFichero: 'pre-despacho.pdf',
        ),
      ),
    ),
  );
}

class _Cuerpo extends ConsumerWidget {
  const _Cuerpo({
    required this.filtros,
    required this.pagina,
    required this.total,
  });

  final FiltrosPedidos filtros;
  final AsyncValue<List<Pedido>> pagina;
  final AsyncValue<int> total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filas = pagina.value;
    if (filas == null) return const EstadoVacio('Cargando...');

    if (filas.isEmpty) {
      // VACÍA POR UN FILTRO NO ES VACÍA DE VERDAD, Y NO SE DICEN IGUAL.
      //
      // Antes salía siempre «Aún no hay pedidos», con filtros puestos o sin
      // ellos. Con un filtro que no casa eso es mentira: hay 246 pedidos, lo que
      // no hay es ninguno que cuadre. Quien lo lee se queda pensando que la
      // bajada falló, cuando lo único que pasa es que escribió mal una búsqueda.
      // Visto el 25/09/2026 buscando algo que no existe: la lista decía «0
      // pedidos» arriba y «aún no hay pedidos» en medio.
      //
      // El botón de quitar los filtros ya estaba y salvaba la situación; lo que
      // faltaba era que la frase de arriba no lo contradijera.
      final porUnFiltro = filtros.hayAlguno;
      return EstadoVacio(
        porUnFiltro
            ? 'Ningún pedido cuadra con estos filtros.'
            : 'Aún no hay pedidos de esta sucursal.',
        accion: porUnFiltro
            ? OutlinedButton(
                onPressed: () =>
                    ref.read(filtrosPedidosProvider.notifier).quitarTodos(),
                child: const Text('Quitar todos los filtros'),
              )
            : null,
      );
    }

    final renglones = ref.watch(renglonesDePaginaProvider).value ?? const {};
    final rutas = ref.watch(rutasPorIdProvider).value ?? const {};
    final seleccion = ref.watch(seleccionPedidosProvider);
    final marcas = ref.read(seleccionPedidosProvider.notifier);

    return TablaPedidos(
      pedidos: filas,
      renglones: renglones,
      rutas: rutas,
      seleccion: seleccion,
      conSucursal: ref.watch(sucursalMiradaProvider) == null,
      ahora: ref.watch(relojProvider)(),
      alMarcar: marcas.alternar,
      alMarcarPagina: (ids, marcar) => marcas.marcarPagina(ids, marcar: marcar),
      alAbrir: (pedido) => abrirCajon<void>(
        context,
        (_) => CajonDetallePedido(pedidoId: pedido.id),
      ),
    );
  }
}

/// EL PRE-DESPACHO DE LO MARCADO A MANO.
///
/// La franja de lo elegido ya no lleva la tabla dentro: lleva **el botón que
/// abre la vista**, igual que el cierre de ruta lleva el del post-despacho. Lo
/// que había aquí era una tabla de escritorio metida entre los filtros y la
/// lista, y en un teléfono eso es una hoja de almacén sin las cantidades.
///
/// Y los tres gestos van en un `Wrap`, no en un `Row`: a 390 px tres botones
/// seguidos no caben en una línea, y un `Row` no los baja — los aprieta hasta
/// partir sus palabras letra a letra.
class _PreDespachoDeLoElegido extends ConsumerWidget {
  const _PreDespachoDeLoElegido();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seleccion = ref.watch(seleccionPedidosProvider);
    if (seleccion.isEmpty) return const SizedBox.shrink();
    final totales = ref.watch(preDespachoElegidoProvider).value;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: Aire.md),
      decoration: BoxDecoration(
        color: Colores.primarioTenue,
        border: Border.all(color: Colores.primario.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(Radios.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Aire.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${seleccion.length} pedido(s) elegidos',
              style: Tipos.texto(
                tamano: 14,
                peso: FontWeight.w600,
                color: Colores.tinta,
              ),
            ),
            const SizedBox(height: Aire.sm),
            Wrap(
              spacing: Aire.sm,
              runSpacing: Aire.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Sin esto no hay papel para el almacen: el PDF existia y
                // estaba probado, y no habia ningun boton que lo llamara.
                BotonDelPreDespacho(
                  key: PreDespacho.claveDelBotonDeLoElegido,
                  totales: totales,
                  alAbrir: () => abrirVistaDePreDespacho(
                    context,
                    fuente: preDespachoElegidoProvider,
                  ),
                ),
                // EL GESTO QUE CERRABA EL FLUJO Y NO ESTABA.
                //
                // Se marca aqui lo que se va a repartir —con los nueve filtros,
                // que es como se decide— y se manda de golpe a una zona del
                // tablero. Sin esto habia que irse al tablero y colocarlos uno a
                // uno, y Jose lo pregunto tal cual: «sigo sin ver, cuando escojo
                // los pedidos, seleccionar un tablero».
                TextButton(
                  onPressed: () => abrirCajonMandarAlTablero(context),
                  child: const Text(PantallaPedidos.mandarAUnaZona),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(seleccionPedidosProvider.notifier)
                      .quitarLaMarca(),
                  child: const Text('Quitar la marca'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// EL PRE-DESPACHO DE LO FILTRADO: un botón, no un desplegable — 22/09/2026.
///
/// Era un `ExpansionTile` que se abría entre los filtros y la lista y dejaba
/// una tabla apretada en medio de la página. Jose: «mejora la vista del
/// predespacho ese q no sea asi con un dropdown anormal ese de pedido no sirve
/// mejora eso ahi para q tenga su propiavista como el post».
///
/// ## La suma sigue siendo perezosa, y eso NO cambia
///
/// En el aparato no hay tope de 5000 (`PLAN.md` §7.2), pero sumar doce mil
/// pedidos al pintar la pantalla es trabajo que casi nadie mira. Antes lo que
/// disparaba la suma era abrir el desplegable; ahora es **pulsar el botón**, y
/// por eso el rótulo dice sólo «Pre-despacho» hasta que hay algo contado y
/// «Pre-despacho · 24 productos» a partir de entonces. `preDespachoFiltradoProvider`
/// no es `autoDispose`, así que al cerrar el cajón el número se queda puesto.
class _PreDespachoDeLoFiltrado extends ConsumerStatefulWidget {
  const _PreDespachoDeLoFiltrado();

  @override
  ConsumerState<_PreDespachoDeLoFiltrado> createState() =>
      _PreDespachoDeLoFiltradoState();
}

class _PreDespachoDeLoFiltradoState
    extends ConsumerState<_PreDespachoDeLoFiltrado> {
  bool _pedido = false;

  @override
  Widget build(BuildContext context) {
    final totales = _pedido
        ? ref.watch(preDespachoFiltradoProvider).value
        : null;

    // SIN `Padding` NI `Align`: desde el 28/09/2026 vive dentro del `Wrap` de
    // las fechas, y es ese `Wrap` quien lo coloca. Los de antes eran para
    // cuando estaba solo en su propia fila, y aquí dentro lo único que hacían
    // era separarlo de las fechas con las que va.
    return BotonDelPreDespacho(
      key: PreDespacho.claveDelBotonDeLoFiltrado,
      totales: totales,
      alAbrir: () {
        setState(() => _pedido = true);
        abrirVistaDePreDespacho(context, fuente: preDespachoFiltradoProvider);
      },
    );
  }
}

/// Abre la vista del pre-despacho sobre uno de los dos proveedores.
///
/// El cajón lleva su propio `Consumer`: la suma puede no estar cuando se abre
/// —es justo el caso de lo filtrado, que empieza a sumarse al pulsar— y el
/// cajón tiene que rellenarse solo cuando caiga, sin cerrarlo y reabrirlo.
void abrirVistaDePreDespacho(
  BuildContext context, {
  required FutureProvider<TotalesPreDespacho> fuente,
}) {
  unawaited(
    abrirCajon<void>(
      context,
      (contexto) => Consumer(
        builder: (contexto, ref, _) {
          final totales = ref.watch(fuente).value;
          return CajonDePreDespacho(
            totales: totales,
            alImprimir: totales == null
                ? null
                : () => verEImprimirPreDespacho(
                    contexto,
                    totales: totales,
                    sucursal: ref.watch(sucursalDeLaHojaProvider).value ?? '',
                    dia: diaDeLaHoja(ref.watch(filtrosPedidosProvider)),
                  ),
          );
        },
      ),
    ),
  );
}
