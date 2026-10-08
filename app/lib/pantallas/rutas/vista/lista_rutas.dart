// La columna izquierda: filtros y lista de rutas.
//
// Los filtros se aplican EN EL CLIENTE sobre las rutas ya traidas, como en la de
// Next, y las rutas ya traidas son las de la base local. Resultado: sin conexion
// se filtra y se pagina igual que con ella.

import 'package:flutter/material.dart';

import '../../../diseno/preguntar_antes_de_borrar.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/primera_bajada.dart';
import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/vista/kit.dart';
import '../datos/acciones_rutas.dart';
import '../datos/importe_de_la_ruta.dart';
import '../datos/peso_de_la_ruta.dart';
import '../datos/repositorio_rutas.dart';
import '../estado/proveedores_rutas.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class ListaDeRutas extends ConsumerWidget {
  const ListaDeRutas({this.deLaPestana, super.key});

  /// DE QUE PESTANA es esta lista. `null` = la que este elegida, que es lo de
  /// siempre.
  ///
  /// Se pide desde fuera porque en el movil las tres van en un `PageView`: la
  /// que se ve por el borde mientras el dedo arrastra **no** es la elegida
  /// todavia, y si se la preguntara al provider pintaria la que se esta
  /// dejando.
  final PestanaRutas? deLaPestana;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El tipo, escrito: sin el, `??` le da contexto anulable al `watch` y
    // Riverpod se lo cree.
    final PestanaRutas pestana = deLaPestana ?? ref.watch(pestanaRutasProvider);
    final rutas = ref.watch(rutasDePestanaProvider(pestana));
    final pagina = ref.watch(paginaRutasProvider);
    final descargadas = ref.watch(rutasDescargadasProvider).value;
    final vehiculos = {
      for (final v in ref.watch(vehiculosProvider).value ?? const <Vehiculo>[])
        v.id: v,
    };
    final sucursales = {
      for (final s in ref.watch(sucursalesProvider).value ?? const <Sucursal>[])
        s.id: s,
    };
    // UNA sola consulta agrupada para las veinte tarjetas, no una por tarjeta.
    // Mientras no llegue es `null`, y entonces la tarjeta **no escribe un
    // cero**: «0 paradas» se lee como «esta ruta va vacia», que es un
    // diagnostico y no un «todavia no se sabe».
    final paradasPorRuta = ref.watch(paradasPorRutaProvider).value;
    // EN QUE ANDA EL CAMION DE CADA RUTA. Una sola consulta agrupada para las
    // veinte tarjetas, como la de las paradas. `null` mientras no llega: la
    // tarjeta entonces **no dice nada** del estado en vez de decir «libre», que
    // es un dato y estaria sin comprobar.
    final ocupados = ref.watch(camionesOcupadosProvider).value;
    // Y EL DINERO, de la misma manera y por el mismo motivo.
    //
    // No sale de `ruta.totalPrice`, que es una columna `NOT NULL DEFAULT 0` y
    // por tanto **no sabe decir «no se sabe»**: se suma de las paradas, que sí.
    // Ver la cabecera de `datos/importe_de_la_ruta.dart` para los tres `?? 0`
    // que borraban el rastro.
    final importePorRuta = ref.watch(importePorRutaProvider).value;
    // Y EL PESO, de la misma manera y por el mismo motivo.
    //
    // No sale de `ruta.totalWeight`: esa columna se escribe UNA VEZ, al armar,
    // y nadie la recalcula, asi que es el peso del dia en que se armo y no el
    // de las paradas que la ruta lleva hoy. Con el se medía la capacidad del
    // camion, que es la peor de las dos maneras de equivocarse: un camion que
    // no cabe puede parecer que cabe. Ver `datos/peso_de_la_ruta.dart`.
    final pesoPorRuta = ref.watch(pesoPorRutaProvider).value;

    // Una lista vacia de una coleccion que nunca se bajo NO es «no hay rutas».
    //
    // Y en la web son TRES casos, no uno. Esta pantalla se quedo fuera de la
    // pasada que separo los tres —el aviso lo dejo escrito quien la hizo— y sin
    // esto la web ensena «Esta pantalla no se ha descargado todavia. Con
    // conexion baja sola» durante el primer segundo de cada carga, que es un
    // diagnostico falso y ademas en el idioma del aparato. Regla 1.
    //
    // La constante, no el literal: la misma frase escrita a mano en dos sitios
    // se separa en cuanto alguien cambie uno, y esta es la que ya usa Pedidos.
    if (descargadas == false) {
      return switch (ref.watch(porQueEstaVacioProvider)) {
        // El aparato: ahi «no se ha descargado» es un estado de verdad.
        PorQueEstaVacio.noSeDescargo => const EstadoVacio(
          SinDescargar.textoDeLaPantallaVacia,
        ),
        // La web, el primer segundo: cargando y nada mas.
        PorQueEstaVacio.todaviaBajando => EstadoVacio(
          TextosDeLaWeb.cargando('las rutas'),
        ),
        // Y si no llego, se dice y se deja entrar.
        PorQueEstaVacio.noPudoBajar => EstadoVacio(
          TextosDeLaWeb.noPudoBajar('las rutas'),
        ),
      };
    }
    if (rutas.isEmpty) return EstadoVacio(pestana.vacio);

    final desde = (pagina - 1) * ConsultasRutas.porPagina;
    final visibles = rutas.skip(desde).take(ConsultasRutas.porPagina).toList();

    // Se agrupa por sucursal **sólo si en la pagina hay mas de una**: con una
    // sola, repetir su nombre en cada encabezado es ruido.
    final conVariasSucursales =
        visibles.map((r) => r.branchId).toSet().length > 1;

    return ListView(
      // AIRE ABAJO. Era el unico `ListView` de la casa sin el —la columna del
      // tablero ya lleva 48—, y sin el la ultima tarjeta y la paginacion se
      // quedan pegadas al borde de la pantalla.
      padding: const EdgeInsets.only(bottom: 48),
      children: [
        for (final (cualGrupo, grupo) in _agrupar(
          visibles,
          conVariasSucursales,
        ).indexed) ...[
          if (grupo.titulo != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                '${sucursales[grupo.titulo]?.name ?? 'Sin sucursal'} '
                '(${sucursales[grupo.titulo]?.externalId ?? '—'}) · '
                '${grupo.rutas.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          for (final (cual, ruta) in grupo.rutas.indexed)
            _TarjetaDeRuta(
              // Sólo la primera del primer grupo se deja senalar por la Guia.
              esLaPrimera: cual == 0 && cualGrupo == 0,
              ruta: ruta,
              vehiculo: vehiculos[ruta.vehicleId],
              ocupacionDelCamion: ruta.vehicleId == null
                  ? null
                  : ocupados?[ruta.vehicleId],
              seSabeLaOcupacion: ocupados != null,
              paradas: paradasPorRuta == null
                  ? null
                  : (paradasPorRuta[ruta.id] ?? 0),
              // Una ruta que no sale en el agrupado es una ruta SIN paradas, y
              // eso sí es un cero que se sabe. `null` es sólo «la consulta no
              // ha llegado todavía».
              importe: importePorRuta == null
                  ? null
                  : (importePorRuta[ruta.id] ?? ImporteDeRuta.nada),
              // Igual que el importe: una ruta que no sale en el agrupado no
              // lleva paradas, y ese cero si se sabe. `null` es solo «la
              // consulta no ha llegado todavia».
              peso: pesoPorRuta == null ? null : (pesoPorRuta[ruta.id] ?? 0),
            ),
        ],
        Paginacion(
          pagina: pagina,
          porPagina: ConsultasRutas.porPagina,
          total: rutas.length,
          alIr: (n) => ref.read(paginaRutasProvider.notifier).ir(n),
        ),
      ],
    );
  }

  List<_Grupo> _agrupar(List<Ruta> rutas, bool agrupar) {
    if (!agrupar) return [_Grupo(null, rutas)];
    final porSucursal = <String?, List<Ruta>>{};
    for (final ruta in rutas) {
      porSucursal.putIfAbsent(ruta.branchId, () => <Ruta>[]).add(ruta);
    }
    return [
      for (final entrada in porSucursal.entries)
        _Grupo(entrada.key, entrada.value),
    ];
  }
}

class _Grupo {
  const _Grupo(this.titulo, this.rutas);

  final String? titulo;
  final List<Ruta> rutas;
}

/// LA TARJETA DE UNA RUTA, EN RENGLONES FIJOS.
///
/// Jose, 17/09/2026, comparando con el patrón: «ves, está más limpio, más
/// organizado, más uniformes, todas las cajas misma altura, los cuerpos no se
/// desintegran ni nada de eso ni se deforman».
///
/// Antes esto era **un solo párrafo** con los cinco datos pegados por puntos:
/// «68.0 km · camion (P-123) · 2da Paralela… · 12/06 · 5212,78 USD». Un párrafo
/// envuelve según lo largo que sea el nombre del camión y lo larga que sea la
/// dirección, así que cada tarjeta salía de una altura distinta y la columna
/// entera se veía temblando. De ahí lo de «se desintegran».
///
/// Ahora son **renglones fijos, uno por cosa, y cada uno de una sola línea**
/// (`maxLines: 1` + `ellipsis`). Con eso todas las tarjetas miden lo mismo
/// aunque un cliente se llame como para llenar dos renglones, y lo que no cabe
/// se corta con puntos suspensivos en vez de empujar lo de abajo.
///
/// El importe va solo y en grande al final, como en el patrón: es el dato que
/// se busca de un vistazo cuando se recorre la lista.
class _TarjetaDeRuta extends ConsumerWidget {
  const _TarjetaDeRuta({
    required this.esLaPrimera,
    required this.ruta,
    required this.vehiculo,
    required this.ocupacionDelCamion,
    required this.seSabeLaOcupacion,
    required this.paradas,
    required this.importe,
    required this.peso,
  });

  /// Si la Guia puede senalar los mandos de ESTA tarjeta. Sólo la primera: hay
  /// una por ruta (`pantallas/ayuda/vista/control_senalado.dart`).
  final bool esLaPrimera;

  final Ruta ruta;
  final Vehiculo? vehiculo;

  /// La ruta ABIERTA que tiene cogido a este camión, si hay alguna. Puede ser
  /// ésta misma —lo normal— o **otra**, que es el caso que importa: dos rutas
  /// con el mismo camión el mismo día, y hasta el 28/09/2026 eso no se veía por
  /// ningún sitio.
  final RutaQueOcupa? ocupacionDelCamion;

  /// Si la consulta ya llegó. `false` es «todavía no se sabe», y entonces no se
  /// escribe nada: decir «libre» sin haberlo comprobado es el cero creíble de
  /// siempre con otra cara.
  final bool seSabeLaOcupacion;

  /// Cuantas paradas lleva. `null` = todavia no ha llegado la cuenta; entonces
  /// **no se escribe un cero**, que se leeria como «esta ruta va vacia».
  final int? paradas;

  /// Lo que suma la ruta y cuantas paradas le faltan por cotizar. `null` =
  /// todavia no ha llegado la consulta; entonces **tampoco se escribe un cero**,
  /// por el mismo motivo y con mas razon: un `\$0.00` en el renglon del dinero se
  /// lee como que el reparto salio gratis.
  final ImporteDeRuta? importe;

  /// LO QUE PESA LA RUTA, sumado de sus paradas. `null` = la consulta todavia
  /// no ha llegado, y entonces **no se avisa de sobrepeso**: decir que cabe —o
  /// que no— sin haberlo medido es el numero creible de siempre con otra cara.
  final double? peso;

  /// CÓMO ANDA ESTE CAMIÓN, pegado a su nombre — 28/09/2026.
  ///
  /// Jose: «que ese vehiculo se ponga su estado para q saber como anda ese
  /// vehiculo». La tarjeta pintaba «Camión 1 (P-001)» y se acababa ahí.
  ///
  /// Sale de las RUTAS y no de `vehicles.status`, que es un campo que alguien
  /// pone y nadie quita (ver `ConsultasRutas.camionesOcupados`). Y sólo se
  /// escribe lo que AÑADE algo:
  ///
  ///   · si quien lo tiene cogido es ESTA ruta, no se dice nada: ya se está
  ///     mirando, y repetirlo en cada tarjeta es ruido que tapa el caso de
  ///     abajo;
  ///   · si lo tiene OTRA, se dice cuál. Ése es el conflicto —dos rutas con el
  ///     mismo camión— y es lo único de aquí que hace que alguien haga algo;
  ///   · si no lo tiene ninguna, «libre», que es la respuesta a «¿puedo
  ///     despachar ésta ya?».
  String get _comoAndaElCamion {
    if (!seSabeLaOcupacion) return '';
    final ocupa = ocupacionDelCamion;
    if (ocupa == null) return ' · libre';
    if (ocupa.rutaId == ruta.id) return '';
    return ocupa.enCurso
        ? ' · EN RUTA en ${ocupa.titulo}'
        : ' · ya va en ${ocupa.titulo}';
  }

  /// BORRAR UNA RUTA PREGUNTA ANTES — 01/10/2026.
  ///
  /// Hasta hoy no preguntaba nada: un toque en «Eliminar» y la ruta se iba. El
  /// 25/09/2026 la casa ya habia decidido lo contrario con «Borrar la columna»
  /// del tablero —Jose, viendo una zona desaparecer de un toque: «sacame
  /// notificaciones emergentes para esto, no me pongas eso asi borrar por
  /// borrar»—, y el 01/10 se arreglo lo mismo en Vehiculos. Aqui se habia
  /// quedado, y es la pantalla donde mas duele: la semana que viene el logistico
  /// de Santiago prueba esto solo, a 900 km, y una ruta borrada por error es una
  /// mañana de armado tirada.
  ///
  /// La pieza es la de la casa —[preguntarAntesDeBorrar]— y no una inventada
  /// aqui: cajon tambien en escritorio, con su ✕, el boton nombra la ruta que se
  /// va, y **cerrar sin contestar es NO**.
  ///
  /// ## Lo propio es QUE SE PIERDE, y sale del servidor
  ///
  /// Leido de `borrarRuta` (`api/internal/api/rutas.go`), que es quien lo hace de
  /// verdad: se borra la fila de `routes` —con ella se van el codigo, la fecha,
  /// el punto de partida y los kilometros—, `SoltarPedidosDeRuta` deja los
  /// pedidos **sin borrar** soltandoles `route_id`, `stop_order`, `segment_km` y
  /// `trip_leg`. Los pendientes vuelven a disponibles; los entregados conservan
  /// su resultado y no se ofrecen para otro reparto. El camion se libera si
  /// estaba `in_use`. Nada de «¿estas
  /// seguro?»: eso no es informacion, es un peaje.
  ///
  /// Las marcas de las paradas son provisionales hasta completar la ruta.
  /// Jose, 06/10/2026: no bloquean editar ni borrar una ruta aún en curso.
  Future<void> _borrarPreguntando(BuildContext contexto, WidgetRef ref) async {
    // El mensajero se coge ANTES de cualquier `await`: despues, este widget
    // puede no estar montado y su `context` no sirve.
    final mensajero = ScaffoldMessenger.maybeOf(contexto);
    final seguro = await preguntarAntesDeBorrar(
      contexto,
      // El mismo rotulo que lleva la insignia de la tarjeta, para que sea
      // evidente que se esta borrando LA QUE SE ESTA MIRANDO.
      queSeVa: ruta.routeCode ?? ruta.id,
      loQuePasa:
          'La ruta desaparece con su código, su fecha, el orden de visita y '
          'los kilómetros que se calcularon al armarla. Para tenerla otra vez '
          'hay que volver a armarla desde el asistente, a mano.\n\n'
          'Lo que NO se borra son los pedidos ni sus resultados: sueltan esta '
          'ruta. Los pendientes vuelven a la lista de disponibles; los '
          'entregados siguen entregados y no se reparten otra vez. Y '
          'el camión se queda libre.\n\n'
          'Si la ruta se armó desde una zona del tablero, las facturas vuelven '
          'a esa zona cuando se sincronice el borrado (en la web, de '
          'inmediato). Mientras tanto, sin señal, salen en «Sin colocar».',
    );
    if (!seguro) return;
    try {
      await ref.read(accionesDeRutaProvider).eliminar(ruta.id);
    } on RechazoLocal catch (fallo) {
      mensajero?.showSnackBar(SnackBar(content: Text(fallo.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elegida = ref.watch(rutaElegidaProvider) == ruta.id;
    // EL SOBREPESO SE MIDE CONTRA LAS PARADAS, no contra `ruta.totalWeight`
    // — 28/09/2026. Esa columna es el total del dia en que se armo y nadie la
    // vuelve a calcular; aqui decide si el camion cabe, y un camion que no cabe
    // pareciendo que cabe no se descubre hasta el almacen.
    //
    // Con el peso todavia sin llegar (`null`) NO se avisa: «Sobrepeso» sobre un
    // numero que no se ha medido es peor que no decir nada.
    final sobrepeso =
        vehiculo != null && peso != null && peso! > vehiculo!.capacity;

    // La elegida se tine de primario y coge su borde: con el gris de antes, con
    // ocho rutas seguidas, no se veia cual estaba abierta a la derecha.
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      color: elegida ? Colores.primarioTenue : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.xl),
        side: BorderSide(
          color: elegida
              ? Colores.primario.withValues(alpha: 0.4)
              : Colores.linea,
        ),
      ),
      child: ControlSenalado(
        nombre: Senalado.rutasTarjetaDeRuta,
        senalable: esLaPrimera,
        child: InkWell(
          onTap: () => ref.read(rutaElegidaProvider.notifier).elegir(ruta.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. El codigo y como esta. Los dos extremos del renglon, que es
                //    donde los busca el ojo al recorrer la columna.
                //
                //    `spaceBetween` Y NADA DE `Spacer` — 28/09/2026. Es el mismo
                //    fallo que ya esta contado en `pantalla_rutas.dart` y aqui
                //    quedo sin arreglar; Jose lo vio en la tarjeta:
                //
                //        «mira ahi en curso no esta ni alinieado con eliminar q
                //         es como deberia estar por q es en la esquina derecha de
                //         arriba» · «esta corrida hacia la izquierda en ves de
                //         estar a la esquina»
                //
                //    `Flexible` y `Spacer` son los DOS flexibles de este renglon,
                //    los dos con flex 1, asi que el hueco libre se parte por la
                //    mitad. El `Flexible` es `loose` y coge solo lo que mide la
                //    insignia del codigo; la mitad que no gasta **no se la queda
                //    el `Spacer`**: sobra al final del renglon, y con el
                //    `mainAxisAlignment` de por defecto (`start`) se queda ahi,
                //    empujando la insignia del estado hacia dentro.
                //
                //    Medido a 390 px con `tester.getRect`: la insignia de «En
                //    curso» acababa en x=333 con el borde del contenido en 374
                //    — 41 px corrida. Y **no la misma cantidad en cada tarjeta**:
                //    depende de lo largo que sea el codigo de SU ruta, asi que
                //    `RT-001` la dejaba en 333 y `RT-20260921-007` en 374. La
                //    columna entera salia con dientes de sierra. A 1400 px eran
                //    600 px de desvio.
                //
                //    Con `spaceBetween` y sin `Spacer` hay un solo flexible: el
                //    codigo coge lo que necesita, todo lo que sobra se va al hueco
                //    del medio y el estado se queda pegado al borde, mida lo que
                //    mida el codigo.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Insignia(
                        ruta.routeCode ?? ruta.id,
                        color: Colores.enCurso,
                      ),
                    ),
                    Insignia(
                      switch (ruta.status) {
                        EstadoRuta.planificada => 'Planificada',
                        EstadoRuta.enCurso => 'En curso',
                        EstadoRuta.completada => 'Completada',
                        _ => ruta.status,
                      },
                      color: switch (ruta.status) {
                        EstadoRuta.planificada => Colores.ambar,
                        EstadoRuta.enCurso => Colores.enCurso,
                        EstadoRuta.completada => Colores.verde,
                        _ => Colores.gris,
                      },
                    ),
                  ],
                ),
                // 2. El tamano de la ruta: cuantas paradas y cuanto se anda.
                const SizedBox(height: 6),
                _Renglon(
                  texto: [
                    if (paradas != null)
                      '$paradas ${paradas == 1 ? 'parada' : 'paradas'}',
                    '${ruta.totalDistance.toStringAsFixed(1)} km',
                    fechaCorta(ruta.deliveryDate),
                  ].join(' · '),
                  peso: FontWeight.w600,
                ),
                // 3. El camion. 4. De donde sale. Cada uno con su icono y en una
                //    sola linea: son los dos datos que mas se alargan.
                _Renglon(
                  icono: Icons.local_shipping_outlined,
                  texto: vehiculo == null
                      ? 'Sin vehículo'
                      : '${vehiculo!.name}'
                            '${vehiculo!.plate == null ? '' : ' (${vehiculo!.plate})'}'
                            '$_comoAndaElCamion',
                ),
                _Renglon(
                  icono: Icons.place_outlined,
                  texto: ruta.originAddress ?? 'Sin punto de partida',
                ),
                if (sobrepeso)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Insignia('Sobrepeso', color: Colores.ambar),
                  ),
                // 5. El importe, solo y en grande. Y `Eliminar` a su derecha, en
                //    un renglon de alto fijo: sin eso, una ruta completada —que no
                //    lleva boton— saldria mas baja que la de al lado, que es
                //    justo lo que se venia a arreglar.
                //
                //    CUANDO FALTA COTIZAR ALGUNA PARADA NO HAY IMPORTE, y aqui se
                //    dice con cuantas de cuantas y en ambar, no con un `$0.00` en
                //    el azul de siempre. El 22/09/2026, `RT-20260921-007` decia
                //    `$0.00` en este mismo hueco con sus dos paradas sin cotizar.
                //
                //    El texto va en `Expanded` con `ellipsis` **y no en un
                //    `Spacer`**: el rotulo largo es mas ancho que un `$0.00`, y
                //    sin eso una tarjeta sin cotizar se desbordaria o creceria
                //    respecto a la de al lado, que es lo que arregla
                //    `tarjetas_de_la_misma_altura_test.dart`.
                const SizedBox(height: 6),
                SizedBox(
                  // 48 Y NO 32 — 28/09/2026, al quitarle el relleno a los botones.
                  //
                  // El renglon medía 32 y el boton de dentro se quedaba con **32
                  // px de alto tactil**, dieciseis por debajo del minimo de
                  // Material: quien apunta a «Eliminar» en un telefono de pie en
                  // el almacen le da al importe de al lado. Se daba por bueno como
                  // algo que «viene de antes y no es cosa de esto», y hoy si lo
                  // es: sin relleno detras,
                  // apuntar a la palabra es lo unico que hay, asi que el sitio
                  // donde cae el dedo no puede seguir siendo mas pequeno de lo que
                  // manda [Botones.altoTactilMinimo].
                  //
                  // Sube igual en TODAS las tarjetas, asi que las dos siguen
                  // midiendo lo mismo: `tarjetas_de_la_misma_altura_test.dart`
                  // compara una con otra, no contra un numero.
                  height: Botones.altoTactilMinimo,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          importe == null ? '—' : importe!.rotulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Tipos.mono(
                            tamano: 15,
                            peso: FontWeight.w700,
                            color: importe != null && !importe!.completo
                                ? Colores.ambar
                                : Colores.primario,
                          ),
                        ),
                      ),
                      if (ruta.status != EstadoRuta.completada)
                        // ESTO ERA UN `TextButton` PELADO Y YA TIENE CAJA —
                        // 28/09/2026.
                        //
                        // Eliminar una ruta es lo mas destructivo de esta
                        // pantalla y se leia exactamente igual que «Editar»: la
                        // palabra sola, en el oro de cualquier enlace. Ahora es un
                        // [BotonDestructivo]: rojo, contorno de 2 px y papelera.
                        //
                        // Y CON ESO SE VA EL AJUSTE DE SANGRIA que llevaba hasta
                        // hoy —le restaba los 12 px de aire propio para que la
                        // palabra acabase donde acaba la insignia de arriba—. Ese
                        // ajuste es para los mandos **sin caja**, donde lo unico
                        // que se ve es el texto. Con un contorno alrededor el caso
                        // se da la vuelta: el borde visible ES el rectangulo del
                        // boton, asi que pegar el rectangulo al borde del
                        // contenido lo deja donde toca —igual que la insignia—, y
                        // quitarle la sangria ahora pondria la palabra encima de
                        // su propia linea. El reparto entre «las que tienen caja»
                        // y «las que no», con sus numeros medidos, esta en
                        // `diseno/tema.dart`, junto a [Botones].
                        ControlSenalado(
                          nombre: Senalado.rutasEliminar,
                          senalable: esLaPrimera,
                          child: BotonDestructivo(
                            texto: 'Eliminar',
                            alPulsar: () => _borrarPreguntando(context, ref),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// UN RENGLON DE LA TARJETA. Una sola linea, siempre, pase lo que pase con lo
/// que le metan: es lo unico que garantiza que dos tarjetas midan lo mismo.
///
/// **El que sujeta esto es `overflow: ellipsis`, no `maxLines: 1`.** Medido el
/// 17/09/2026 al mutarlo: quitando solo `maxLines` las dos tarjetas seguian
/// midiendo 152; quitando los dos, la de la direccion larga se iba a 216 — 64
/// pixeles de diferencia con la de al lado, que es justo lo que se ve como que
/// la columna tiembla. Se dejan los dos escritos porque juntos dicen la
/// intencion, pero **quien mute esto tiene que quitar los dos**: romper solo
/// `maxLines` sale verde y no prueba nada.
class _Renglon extends StatelessWidget {
  const _Renglon({required this.texto, this.icono, this.peso});

  final String texto;
  final IconData? icono;
  final FontWeight? peso;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        if (icono != null) ...[
          Icon(icono, size: 14, color: Colores.gris),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontWeight: peso),
          ),
        ),
      ],
    ),
  );
}
