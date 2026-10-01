import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cargando.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/rango_de_fechas.dart';
import '../../../diseno/pestanas.dart';
import '../../../diseno/selector.dart';
import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tarjeta.dart';
import '../../../navegacion/estado_navegacion.dart';
import '../../../nucleo/frescura/primera_bajada.dart';
import '../../../nucleo/proveedores.dart';
import '../datos/consultas_informes.dart';
import '../estado/informes_estado.dart';
import 'boton_exportar.dart';

/// Textos que esta pantalla necesita y la de Next no tiene. Van juntos y
/// marcados para que se sepa siempre que se comparo con Next y que no
/// (PLAN.md §4.3, regla 5).
abstract final class TextosNuevosDeInformes {
  /// Cuando hay datos, pero salen del aparato.
  static String cuadradoConElAparato(String fecha) =>
      'Cuadrado con los datos del aparato, del $fecha. '
      'Con conexión sale el del servidor.';

  /// LO MISMO, EN LA WEB. Ni «aparato» ni «con conexión»: en un navegador no
  /// hay aparato del que sacar nada y la conexión la da por hecha la propia
  /// página, que cargó.
  ///
  /// Jose, 17/09/2026, viendo el texto de arriba en `reparto.procovar.cloud`:
  /// era el mundo de la APK asomando en la web.
  static String cuadradoConLoQueBajo(String fecha) =>
      'Cuadrado con lo último que bajó, de las $fecha.';

  /// Cuando lo bajado tiene mas de un dia. **Aqui el informe ya no sirve para
  /// cerrar nada**, y hay que decirlo con esas palabras.
  static const noSirveSinEstarAlDia =
      'Estos datos tienen más de un día: el informe no cuadra con el servidor '
      'y no sirve para cerrar. Conéctate y deja que baje.';

  /// Y EN LA WEB. Que los datos tengan un dia en un navegador no se arregla
  /// conectandose —ya lo esta—: significa que la sincronizacion no esta
  /// llegando, y eso lo arregla la oficina.
  static const noSirveSinEstarAlDiaEnWeb =
      'Estos datos tienen más de un día: el informe no cuadra con el servidor '
      'y no sirve para cerrar. Recarga la página y, si sigue igual, avisa a la '
      'oficina.';

  /// Cuando no se bajo nunca. No se pinta ninguna tabla: una tabla de ceros se
  /// lee como «no hubo ventas», que es lo contrario de lo que pasa.
  static const sinNadaQueCuadrar =
      'No hay nada descargado todavía, así que no hay nada que cuadrar. '
      'Con conexión baja sola.';

  /// CUANDO LA ULTIMA BAJADA VOLVIO A MEDIAS.
  ///
  /// Es la tercera pregunta, y faltaba. Las otras dos —«no se bajo nunca» y
  /// «esto tiene mas de un dia»— no la cubren: aqui la marca de frescura SI se
  /// movio y las tablas SI tienen filas, asi que las dos contestan que todo esta
  /// bien mientras el padron trae 2.000 clientes de 8.103.
  ///
  /// Y esta es la pantalla donde eso se convierte en dinero: un total cuadrado
  /// con medio padron sale creible, en verde, con su boton de exportar a Excel
  /// al lado. `CLAUDE.md` §4: «un importe asi se lee bien y esta mal, que es lo
  /// peor que puede pasarle a un numero que alguien va a cobrar».
  ///
  /// El motivo va TAL CUAL lo escribe `nucleo/sincro/bajada.dart` —«se llego al
  /// tope de 50 tandas y el servidor seguia diciendo que queda mas»— porque es
  /// lo unico que dice que paso. «No se pudo traer todo» no le sirve a nadie.
  static String noEstaEntero(String motivo) =>
      'La última bajada no está entera, así que este informe está cuadrado con '
      'sólo una parte de los datos y los totales salen por debajo: no sirve '
      'para cerrar. Lo que pasó: $motivo. Conéctate y deja que termine de '
      'bajar.';

  /// Lo que se dice en la web mientras la primera bajada va en camino.
  static const cargandoElReporte = 'Cargando reporte...';

  /// Y lo que se dice en la web cuando esa bajada no llego.
  static final noLlegoElReporte = TextosDeLaWeb.noPudoBajar(
    'los datos del reporte',
  );
}

/// REPORTES (pliego §7). **No esta en el menu**: se llega por URL y desde las
/// acciones rapidas del Panel.
class PantallaInformes extends ConsumerWidget {
  const PantallaInformes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final informe = ref.watch(informeProvider);
    final bajada = ref.watch(frescuraGlobalProvider);
    final ahora = ref.watch(relojProvider)();

    // LA MONEDA, PARA TODA LA PANTALLA. Se resuelve una vez aqui y baja como
    // parametro: si cada tabla la mirara por su cuenta podrian pintar dos
    // monedas distintas en la misma vista mientras la tasa se recarga.
    //
    // `monedaEfectivaProvider` ya se cae a USD cuando la sucursal que se mira
    // no tiene tasa, y `TasaDeLaMirada.importe` no usa NUNCA la de otra. El
    // porque —sin tasa, con todas las sucursales, tasa vieja— lo dice la barra
    // de arriba; aqui sólo se pinta.
    final tasa = ref.watch(tasaDeLaMiradaProvider);
    final moneda = ref.watch(monedaEfectivaProvider);
    // `TasaDeLaMirada.importe` ya contesta `—` a un `null`, que es justo lo que
    // hace falta: **un importe que no se sabe no se pinta nunca como `0.00`**
    // (`CLAUDE.md` §2). Lo que se traia el `null` de abajo era la consulta, que
    // escribia un cero; ahora llega hasta aqui y se dice.
    String importe(double? usd) => tasa.importe(usd, moneda);

    final cuando = bajada.value;
    final sinDescargar = bajada.hasValue && cuando == null;
    final viejo =
        cuando != null && ahora.difference(cuando) > const Duration(hours: 24);
    // POR QUE ESTA VACIO, que no es lo mismo que «esta vacio».
    //
    // En la web la base nace vacia en cada carga de la pagina, asi que el primer
    // segundo esto decia «No hay nada descargado todavía… Con conexión baja
    // sola»: dos frases del mundo de la APK delante de alguien sentado en la
    // oficina con internet, acusando de un problema que no existia.
    final porQue = ref.watch(porQueEstaVacioProvider);

    // `p-3 sm:p-6` de delivery.
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.idioma;
    final aire = estrecho ? Aire.md : Aire.xl;

    final cabecera = Padding(
      padding: EdgeInsets.fromLTRB(aire, aire, aire, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filtros(sinDescargar: sinDescargar, porQue: porQue),
          const SizedBox(height: Aire.lg),
          _Advertencia(
            sinDescargar: sinDescargar,
            viejo: viejo,
            cuando: cuando,
            porQue: porQue,
            // LA BAJADA QUE VOLVIO A MEDIAS. Lo leia un solo sitio —la franja
            // de estado, una linea de doce puntos arriba del todo— y esta es la
            // pantalla donde un truncamiento se convierte en un importe.
            aMedias: ref.watch(bajadaAMediasProvider),
          ),
          const SizedBox(height: Aire.lg),
        ],
      ),
    );

    // Un aviso suelto —«cargando», «no pudo bajar»— tambien va en su propio
    // desplazable: el cuerpo de un `NestedScrollView` tiene que traer el suyo,
    // o el de fuera no tiene con quien turnarse y la cabecera se queda clavada.
    Widget suelto(Widget hijo) => ListView(
      padding: EdgeInsets.fromLTRB(aire, 0, aire, aire),
      children: [hijo],
    );

    final cuerpo = sinDescargar
        ? switch (porQue) {
            // El aparato: es un estado de verdad y se dice como siempre.
            PorQueEstaVacio.noSeDescargo => suelto(
              const PantallaSinDescargar(),
            ),
            // La web, el primer segundo: **cargando, y nada mas**. Sin
            // diagnostico, porque no se ha mirado nada todavia.
            PorQueEstaVacio.todaviaBajando => suelto(
              const Cargando(TextosNuevosDeInformes.cargandoElReporte),
            ),
            // La web cuando la bajada no llego: se dice, y se deja entrar. Los
            // filtros de arriba siguen ahi y la pagina se puede recargar.
            PorQueEstaVacio.noPudoBajar => suelto(
              EstadoVacio(
                TextosNuevosDeInformes.noLlegoElReporte,
                icono: Icons.cloud_off_outlined,
              ),
            ),
          }
        : switch (informe) {
            AsyncValue<Informe>(:final value?) => _Pestanas(
              informe: value,
              importe: importe,
              aire: aire,
            ),
            AsyncValue<Informe>(:final error?) => suelto(EstadoVacio('$error')),
            _ => suelto(const Cargando('Cargando reporte...')),
          };

    // UN SOLO DESPLAZAMIENTO VERTICAL, Y POR ESO UN `NestedScrollView`
    // — 17/09/2026.
    //
    // Antes esto era un `ListView` con los filtros, el aviso y, de ultimo, una
    // caja de 560 px de alto con las tres pestañas dentro; y cada pestaña
    // llevaba **su propio** `SingleChildScrollView`. Dos desplazamientos en el
    // mismo eje, uno dentro del otro, que es el caso que Flutter no turna:
    // manda el de dentro y el de fuera no recibe el gesto nunca.
    //
    // Lo que se veia en un teléfono de 390x844, medido: la caja de las pestañas
    // ocupaba de y=447 a y=1007 —163 px de ella ya estaban por debajo del borde
    // de la pantalla— y el «Totales:» del pie de «Detalle de Órdenes» caia en
    // y=1249. Para llegar a él hacian falta LOS DOS desplazamientos (271 px del
    // de dentro y 175 del de fuera), y el de fuera no se podia mover con el dedo
    // sobre la tabla. O sea: **el pie del informe no se veia nunca.** Es
    // literalmente lo que dijo Jose — «me corta parte de abajo… no puedo ver el
    // final».
    //
    // El `NestedScrollView` es lo que los pone de acuerdo: el dedo sobre la
    // tabla gasta primero la cabecera de arriba y sólo despues baja la lista.
    // No se pierde nada de lo de antes —los filtros siguen encima y se van al
    // desplazar— y se gana que el final del informe exista.
    return NestedScrollView(
      headerSliverBuilder: (contexto, _) => [
        SliverToBoxAdapter(child: cabecera),
      ],
      body: cuerpo,
    );
  }
}

/// El subtexto de la tarjeta de `Ingresos Totales` cuando no hay total: dice
/// **que hacer**, no solo que falta. Un `—` a secas no lo dice.
String _faltanPorCotizar(int cuantas) => cuantas == 1
    ? 'Falta cotizar 1 orden: sin ella no hay total.'
    : 'Faltan cotizar $cuantas órdenes: sin ellas no hay total.';

/// Lo que dice la pantalla sobre de donde salen sus numeros.
///
/// El informe de verdad lo cuadra el servidor sobre TODO lo que tiene. Aqui solo
/// puede salir lo bajado, y callarlo seria dar por bueno un total al que le
/// faltan pedidos. El aviso no es opcional ni se cierra: es parte del dato.
class _Advertencia extends StatelessWidget {
  const _Advertencia({
    required this.sinDescargar,
    required this.viejo,
    required this.cuando,
    required this.porQue,
    required this.aMedias,
  });

  final bool sinDescargar;
  final bool viejo;
  final DateTime? cuando;
  final PorQueEstaVacio porQue;

  /// Por que la ultima bajada volvio a medias, con las palabras de
  /// `bajada.dart`. `null` = vino entera.
  final String? aMedias;

  @override
  Widget build(BuildContext context) {
    final enWeb = porQue != PorQueEstaVacio.noSeDescargo;

    if (sinDescargar) {
      return switch (porQue) {
        PorQueEstaVacio.noSeDescargo => const AvisoAmbar(
          TextosNuevosDeInformes.sinNadaQueCuadrar,
        ),
        // MIENTRAS BAJA NO SE ACUSA A NADIE. El recuadro ambar de «no hay nada
        // que cuadrar» delante de alguien cuyos datos entran un segundo despues
        // es exactamente el mensaje falso del 17/09/2026. Lo que toca es
        // esperar, y de decirlo se ocupa el cargando de abajo.
        PorQueEstaVacio.todaviaBajando => const SizedBox.shrink(),
        PorQueEstaVacio.noPudoBajar => AvisoAmbar(
          TextosNuevosDeInformes.noLlegoElReporte,
        ),
      };
    }
    if (cuando == null) return const SizedBox.shrink();

    final fecha = DateFormat('d/M/y, H:mm', 'es').format(cuando!);
    final hora = DateFormat('H:mm', 'es').format(cuando!);
    final texto = enWeb
        ? TextosNuevosDeInformes.cuadradoConLoQueBajo(hora)
        : TextosNuevosDeInformes.cuadradoConElAparato(fecha);

    // VA ANTES QUE «tiene mas de un dia» a proposito: las dos son verdad a la
    // vez muchas veces, y de las dos la que manda es esta. Unos datos de ayer
    // al menos estan enteros; estos ni eso.
    final medias = aMedias;
    if (medias != null) {
      return AvisoAmbar(
        '$texto\n${TextosNuevosDeInformes.noEstaEntero(medias)}',
      );
    }

    if (viejo) {
      return AvisoAmbar(
        '$texto\n'
        '${enWeb ? TextosNuevosDeInformes.noSirveSinEstarAlDiaEnWeb : TextosNuevosDeInformes.noSirveSinEstarAlDia}',
      );
    }
    return Text(
      texto,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Colores.gris),
    );
  }
}

class _Filtros extends ConsumerWidget {
  const _Filtros({required this.sinDescargar, required this.porQue});

  /// Las dos hacen falta aqui por el boton de exportar: sin ellas el motivo por
  /// el que esta apagado seria siempre «no hay ninguna orden», tambien delante
  /// de alguien cuya bajada no llego. Ver `motivoParaNoExportar`.
  final bool sinDescargar;
  final PorQueEstaVacio porQue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroDeInformesProvider);
    final vehiculos = ref.watch(vehiculosDelInformeProvider).value ?? const [];
    final notas = ref.read(filtroDeInformesProvider.notifier);

    return Tarjeta(
      titulo: 'Filtros',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Fecha(
            etiqueta: 'Desde',
            valor: filtro.desde,
            alElegir: (d) => notas.poner(
              d == null
                  ? filtro.copiar(quitarDesde: true)
                  : filtro.copiar(desde: d),
            ),
          ),
          _Fecha(
            etiqueta: 'Hasta',
            valor: filtro.hasta,
            alElegir: (d) => notas.poner(
              d == null
                  ? filtro.copiar(quitarHasta: true)
                  : filtro.copiar(hasta: d),
            ),
          ),
          Selector<String>(
            icono: Icons.local_shipping_outlined,
            tooltip: 'Vehículo',
            etiquetaVacia: 'Todos los vehículos',
            valor: filtro.vehiculoId ?? '',
            opciones: [
              const OpcionSelector<String>(
                valor: '',
                etiqueta: 'Todos los vehículos',
              ),
              for (final v in vehiculos)
                OpcionSelector<String>(
                  valor: v.id,
                  etiqueta: v.name,
                  nota: v.plate,
                ),
            ],
            alElegir: (v) => notas.poner(
              v.isEmpty
                  ? filtro.copiar(quitarVehiculo: true)
                  : filtro.copiar(vehiculoId: v),
            ),
          ),
          // `Limpiar` solo si hay algo puesto: un boton que no hace nada ensena
          // a no leer los botones.
          if (filtro.hayAlgoPuesto)
            TextButton(onPressed: notas.limpiar, child: const Text('Limpiar')),
          // `Exportar a Excel`, el ultimo de la fila como en el patron
          // (`ml-auto`). Los importes salen **en la moneda que se esta
          // mirando**, igual que las tablas de abajo; el fichero lo arma
          // `datos/excel_del_informe.dart` y lo entrega
          // `datos/entrega_del_excel.dart`, que es donde vive la diferencia
          // entre guardar, compartir y descargar.
          BotonExportarExcel(sinDescargar: sinDescargar, porQue: porQue),
        ],
      ),
    );
  }
}

/// EL «HOY» SALE DEL RELOJ DE LA APLICACION, NO DE `DateTime.now()` — 01/10/2026.
///
/// `CampoDeFecha` abre el calendario por el mes de hoy, y si no se le dice cual
/// es, lo pregunta el solo. Eso convierte a esta pantalla en una que **cambia de
/// mes sola al cambiar el dia**, y su prueba en una que **se pudre con el
/// calendario**: pulsaba el dia 20 esperando «20/9/2026», y el 1 de octubre
/// empezo a salir «20/10/2026». Rojo sin que nadie tocara una linea.
///
/// Lo avisaba el propio `rango_de_fechas.dart`: «en una prueba serian un mes
/// distinto cada vez que pase». Estaba el parametro y no se usaba.
///
/// Con el reloj de la aplicacion por medio, una prueba lo congela y la pantalla
/// se comporta igual el dia 1 que el 31.
class _Fecha extends ConsumerWidget {
  const _Fecha({
    required this.etiqueta,
    required this.valor,
    required this.alElegir,
  });

  final String etiqueta;
  final DateTime? valor;
  final ValueChanged<DateTime?> alElegir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // EL CALENDARIO DE LA CASA, no `showDatePicker`.
    //
    // `showDatePicker` es una ventana modal centrada, y aquí no hay modales: es
    // la excepción aprobada del 05/09/2026 y está escrita en
    // `lib/diseno/rango_de_fechas.dart` («**No se usa `showDatePicker`**»), en
    // `pantallas.md` §0 y §9.2 y en el §4 del CLAUDE.md del repo. `CampoDeFecha`
    // saca el calendario en un menú anclado al propio botón, que es el mismo
    // patrón del `Selector`.
    //
    // Y de paso se va la ventana rara: esto abría de `año−5` a `año+1`, cuando
    // el resto de la aplicación usa 2020 → año+1 (hay pedidos viejos espejados
    // y fechas comprometidas por delante). Eran cuatro ventanas distintas en la
    // misma aplicación; ahora es una.
    final boton = CampoDeFecha(
      titulo: etiqueta,
      valor: valor,
      alElegir: alElegir,
      hoy: ref.watch(relojProvider)(),
    );

    if (valor == null) return boton;

    // LA ✕ DE QUITAR LA FECHA, A LA VISTA.
    //
    // Antes la única forma de quitarla era dejar el dedo pulsado sobre el botón
    // (`onLongPress`), sin una sola pista en pantalla de que eso existiera. En
    // un teléfono eso no lo descubre nadie: se pone una fecha por probar y ya no
    // hay manera de volver a «todas» salvo recargar la pantalla.
    //
    // Se pone la misma ✕ que ya usa el rango de fechas de Pedidos y de Rutas
    // (`diseno/rango_de_fechas.dart`), y sólo cuando hay algo que quitar, para
    // no poner un botón que no hace nada.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: boton),
        IconButton(
          onPressed: () => alElegir(null),
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Quitar $etiqueta',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// LAS TRES PESTANAS DEL REPORTE.
///
/// El `TabBarView` ya se desliza el solo —es un `PageView` por dentro—, asi que
/// aqui lo unico que faltaba eran **las flechas de los lados**: en un telefono
/// las tres etiquetas no caben (`isScrollable`), y «Detalle de Órdenes» se queda
/// fuera de la pantalla. Con las flechas se llega sin tener que empujar la tira
/// de pestanas hasta dar con ella.
///
/// Con estado propio y `TabController` a mano, y no `DefaultTabController`: la
/// flecha necesita SABER en cual se esta para apagarse en los extremos, y eso es
/// escuchar al controlador, que es justo lo que un controlador por defecto no
/// deja hacer desde el mismo `build` que lo crea.
class _Pestanas extends StatefulWidget {
  const _Pestanas({
    required this.informe,
    required this.importe,
    required this.aire,
  });

  final Informe informe;
  final PintarImporte importe;

  /// El relleno lateral de la pantalla (`p-3 sm:p-6`).
  final double aire;

  @override
  State<_Pestanas> createState() => _PestanasState();
}

class _PestanasState extends State<_Pestanas>
    with SingleTickerProviderStateMixin {
  static const _nombres = ['Resumen', 'Por Vehículo', 'Detalle de Órdenes'];

  late final TabController _mando = TabController(
    length: _nombres.length,
    vsync: this,
  )..addListener(_repintar);

  /// El subrayado se mueve ANTES de que termine la animacion (`index` cambia al
  /// empezar), y las flechas se tienen que enterar a la vez que el: si se
  /// esperara al final, la flecha del extremo quedaria encendida medio segundo
  /// sobre algo a lo que ya no se puede ir.
  void _repintar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mando
      ..removeListener(_repintar)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // EN CARRUSEL, como el Tablero y como Rutas: se ve sólo la pestaña en la
      // que estás y unas bolitas dicen que hay más.
      //
      // Aquí el cambio se nota el doble. El `TabBar` iba con `isScrollable`
      // porque las tres etiquetas no caben en un teléfono, así que «Detalle de
      // Órdenes» se quedaba fuera de la pantalla: existía, pero había que
      // empujar la tira a ciegas para dar con ella.
      // Y en un monitor salen las tres a la vez: el carrusel resuelve la falta
      // de sitio de un teléfono, y en una pantalla ancha esconder dos de tres
      // detrás de unas bolitas es quitar información a quien tiene sitio para
      // verla. Jose, 17/09/2026: «los tabs así como están eran para el móvil».
      PestanasQueCaben(
        indice: _mando.index,
        etiquetas: _nombres,
        alCambiar: _mando.animateTo,
        // El número de filas va pegado a su nombre, como en la pestaña de
        // antes: es la cuenta de lo que hay dentro, igual que el «(308)» de
        // «Sin colocar» en el Tablero.
        rotulo: _mando.index == 2
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_nombres[2]),
                  const SizedBox(width: 6),
                  Insignia(Numeros.entero(widget.informe.filas.length)),
                ],
              )
            : null,
      ),
      // `Expanded` y NO un alto fijo de 560 px.
      //
      // El alto fijo era la mitad del fallo: dentro de un `ListView` la caja se
      // pintaba entera aunque 163 de sus 560 px cayeran fuera de la pantalla, y
      // el desplazable de dentro no podia enseñar lo que quedaba por debajo de
      // ese borde. Con `Expanded` la caja mide **lo que hay de pantalla**, asi
      // que lo que se desplaza se ve entero.
      //
      // Lo que lo permite es que la pantalla ya no sea un `ListView`: es un
      // `NestedScrollView`, que le da al cuerpo un alto concreto. Ver el porque
      // largo en `PantallaInformes.build`.
      Expanded(
        child: TabBarView(
          controller: _mando,
          children: [
            _Pestana(
              aire: widget.aire,
              hijo: _Resumen(informe: widget.informe, importe: widget.importe),
            ),
            _Pestana(
              aire: widget.aire,
              hijo: _PorVehiculo(
                informe: widget.informe,
                importe: widget.importe,
              ),
            ),
            _Pestana(
              aire: widget.aire,
              hijo: _Detalle(informe: widget.informe, importe: widget.importe),
            ),
          ],
        ),
      ),
    ],
  );
}

/// El contenido de una pestaña, con su desplazamiento y su relleno.
///
/// **Es la unica lista vertical de esta mitad de la pantalla.** De apartarla de
/// la barra de gestos del sistema se encarga el `SafeArea` del armazon, que ya
/// recorta el alto de las siete pantallas; sumarlo tambien aqui seria contarlo
/// dos veces y dejar 34 px muertos al final del informe.
class _Pestana extends StatelessWidget {
  const _Pestana({required this.hijo, required this.aire});

  final Widget hijo;
  final double aire;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(aire, 0, aire, aire),
    children: [hijo],
  );
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.informe, required this.importe});

  final Informe informe;
  final PintarImporte importe;

  @override
  Widget build(BuildContext context) {
    if (informe.filas.isEmpty) {
      return const EstadoVacio(
        'No hay órdenes para los filtros seleccionados.',
      );
    }
    final r = informe.resumen;
    final tarjetas = <Widget>[
      TarjetaDeCifra(
        etiqueta: 'Total Órdenes',
        valor: Numeros.entero(r.totalOrdenes),
      ),
      // LAS DOS QUE PUEDEN NO SABERSE. Con alguna orden sin cotizar no hay
      // total: se pinta `— (N sin cotizar)` y el subtexto dice que hacer. Un
      // `0,00 USD` aqui es lo que se veia el 22/09/2026 en produccion sobre 10,4
      // km de reparto con el camion cotizado a 1,50 USD/km.
      TarjetaDeCifra(
        etiqueta: 'Ingresos Totales',
        valor: r.ingresos == null
            ? Numeros.totalIncompleto(r.sinCotizar)
            : importe(r.ingresos),
        subtexto: r.ingresos == null ? _faltanPorCotizar(r.sinCotizar) : null,
        color: r.ingresos == null ? Colores.ambar : null,
      ),
      TarjetaDeCifra(
        etiqueta: 'Precio Promedio',
        valor: r.precioPromedio == null
            ? Numeros.totalIncompleto(r.sinCotizar)
            : importe(r.precioPromedio),
        color: r.precioPromedio == null ? Colores.ambar : null,
      ),
      TarjetaDeCifra(etiqueta: 'Peso Total', valor: Numeros.kg(r.peso)),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, medidas) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final t in tarjetas)
                  SizedBox(
                    width: medidas.maxWidth < Anchos.entrega
                        ? medidas.maxWidth
                        : (medidas.maxWidth - 36) / 4,
                    child: t,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Top vehículos',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final v in informe.porVehiculo.take(3))
                SizedBox(
                  width: 260,
                  child: Tarjeta(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(v.nombre),
                        if (v.placa != null)
                          Text(
                            v.placa!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colores.gris),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          '${v.ingresos == null ? Numeros.totalIncompleto(v.sinCotizar) : importe(v.ingresos)} · '
                          '${Numeros.entero(v.ordenes)} órdenes',
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PorVehiculo extends StatelessWidget {
  const _PorVehiculo({required this.informe, required this.importe});

  final Informe informe;
  final PintarImporte importe;

  @override
  Widget build(BuildContext context) {
    if (informe.porVehiculo.isEmpty) {
      return const EstadoVacio(
        'No hay datos de vehículos para los filtros seleccionados.',
      );
    }
    var ordenes = 0;
    var peso = 0.0;
    var sinCotizar = 0;
    for (final v in informe.porVehiculo) {
      ordenes += v.ordenes;
      peso += v.peso;
      sinCotizar += v.sinCotizar;
    }
    // El pie NO puede parecer completo si le falta un sumando: misma regla que
    // `TotalesPreDespacho._sumaCompleta`.
    final ingresos = ConsultasInformes.sumaCompleta(
      informe.porVehiculo.map((v) => v.ingresos),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TablaAncha(
        anchoMinimo: 720,
        child: _Tabla(
          cabeceras: const [
            'Vehículo',
            'Placa',
            'Órdenes',
            'Ingresos',
            'Peso Total',
            'Promedio/Orden',
          ],
          filas: [
            for (final v in informe.porVehiculo)
              [
                v.nombre,
                v.placa ?? '—',
                Numeros.entero(v.ordenes),
                v.ingresos == null
                    ? Numeros.totalIncompleto(v.sinCotizar)
                    : importe(v.ingresos),
                Numeros.kg(v.peso),
                v.promedioPorOrden == null ? '—' : importe(v.promedioPorOrden),
              ],
          ],
          pie: [
            sinCotizar == 0 ? 'Totales' : 'Totales ($sinCotizar sin cotizar)',
            '',
            Numeros.entero(ordenes),
            ingresos == null
                ? Numeros.totalIncompleto(sinCotizar)
                : importe(ingresos),
            Numeros.kg(peso),
            '',
          ],
        ),
      ),
    );
  }
}

class _Detalle extends StatelessWidget {
  const _Detalle({required this.informe, required this.importe});

  final Informe informe;
  final PintarImporte importe;

  @override
  Widget build(BuildContext context) {
    if (informe.filas.isEmpty) {
      return const EstadoVacio(
        'No hay órdenes para los filtros seleccionados.',
      );
    }
    var peso = 0.0;
    var sinCotizar = 0;
    for (final f in informe.filas) {
      peso += f.pesoKg;
      if (f.importe == null) sinCotizar++;
    }
    final total = ConsultasInformes.sumaCompleta(
      informe.filas.map((f) => f.importe),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TablaAncha(
        anchoMinimo: 860,
        child: _Tabla(
          cabeceras: const [
            'Fecha',
            'Cliente',
            'Ruta',
            'Destino',
            'Vehículo',
            'Peso',
            'Precio',
          ],
          filas: [
            for (final f in informe.filas)
              [
                f.fecha == null
                    ? '—'
                    : DateFormat('d/M/y', 'es').format(f.fecha!),
                f.cliente,
                f.ruta ?? '—',
                f.destino,
                f.vehiculo ?? '—',
                Numeros.kg(f.pesoKg),
                // LA COLUMNA QUE VA AL EXCEL Y A CONTABILIDAD. Sin cotizacion
                // se dice con las MISMAS palabras que `Pedidos` y que la hoja
                // de paradas de la ruta: «sin cotizar», nunca `0,00`.
                f.importe == null ? Numeros.sinCotizar : importe(f.importe),
              ],
          ],
          pie: [
            sinCotizar == 0 ? 'Totales:' : 'Totales: ($sinCotizar sin cotizar)',
            '',
            '',
            '',
            '',
            Numeros.kg(peso),
            total == null
                ? Numeros.totalIncompleto(sinCotizar)
                : importe(total),
          ],
        ),
      ),
    );
  }
}

/// Una tabla sencilla de textos. No usa `DataTable` porque `DataTable` reparte
/// la anchura sobrante a su manera y aqui el ancho lo fija `TablaAncha`.
class _Tabla extends StatelessWidget {
  const _Tabla({required this.cabeceras, required this.filas, this.pie});

  final List<String> cabeceras;
  final List<List<String>> filas;
  final List<String>? pie;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // La cabecera en versalitas sobre papel, como todas las de delivery.
        _Fila(
          celdas: cabeceras,
          estilo: Tipos.texto(
            tamano: 11,
            peso: FontWeight.w600,
            color: Colores.tintaSuave,
            interletra: 0.4,
          ),
          fondo: Colores.papel,
        ),
        Divider(height: 1, thickness: 1, color: Colores.linea),
        for (final f in filas)
          _Fila(celdas: f, estilo: tema.textTheme.bodySmall, conLinea: true),
        if (pie != null) ...[
          Divider(height: 1, thickness: 1, color: Colores.linea),
          _Fila(
            celdas: pie!,
            estilo: Tipos.texto(
              tamano: 13,
              peso: FontWeight.w700,
              color: Colores.tinta,
            ),
            fondo: Colores.papel,
          ),
        ],
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.celdas,
    this.estilo,
    this.fondo,
    this.conLinea = false,
  });

  final List<String> celdas;
  final TextStyle? estilo;
  final Color? fondo;

  /// La linea fina de abajo, la que separa una fila de la siguiente.
  final bool conLinea;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: fondo,
      border: conLinea
          ? Border(bottom: BorderSide(color: Colores.linea))
          : null,
    ),
    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: Aire.sm),
    child: Row(
      children: [
        for (final c in celdas)
          Expanded(
            child: Text(c, style: estilo, overflow: TextOverflow.ellipsis),
          ),
      ],
    ),
  );
}
