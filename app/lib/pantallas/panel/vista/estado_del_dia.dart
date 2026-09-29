import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/banner_de_gesto.dart';
import '../../../diseno/colores.dart';
import '../../../nucleo/proveedores.dart';
import '../../../navegacion/estado_navegacion.dart';
import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../../nucleo/sincro/ciclo.dart';
import '../../../nucleo/sincro/huerfanos.dart';
import '../../../nucleo/sincro/recuento.dart';
import '../../entregar_el_dia/datos/textos.dart';
import '../../entregar_el_dia/estado/entregar_el_dia.dart';
import '../../entregar_el_dia/vista/cajon_entregar_el_dia.dart';
import '../../traer_el_dia/datos/textos.dart';
import '../../traer_el_dia/estado/traer_el_dia.dart';
import '../../traer_el_dia/vista/cajon_traer_el_dia.dart';
import '../datos/textos_del_dia.dart';

/// EL ESTADO DEL DIA: **una sola pieza**, arriba del Panel.
///
/// Dice en que esta el aparato y que toca ahora. No son dos botones puestos ahi
/// para que el logistico elija: la pantalla ya sabe cual le sirve.
///
///  * En el patio del almacen, sin cobertura, **no hay nada que elegir** — y por
///    eso ahi no hay boton: hay un estado y una hora.
///  * Con trabajo dentro del telefono, **enviarlo manda sobre todo lo demas**.
///    Los datos bajados se vuelven a bajar; una parada marcada a las cuatro que
///    nunca subio, no.
///  * Y cuando no queda nada dentro, lo que toca es traer el dia.
///
/// Los dos cajones siguen donde estaban y se llega a los dos: el boton abre el
/// que toca, y pulsar la pieza abre el de traer (o el de enviar, si hay algo
/// dentro). La franja de estado sigue siendo la otra puerta desde las otras seis
/// pantallas.
class EstadoDelDia extends ConsumerWidget {
  const EstadoDelDia({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marcha = ref.watch(marchaDelCicloProvider);
    final trajo = ref.watch(traerElDiaProvider);
    final entrego = ref.watch(entregarElDiaProvider);
    // EL CONTEO ENTERO, SIN COLAPSAR. `.value` para las cifras —que mientras no
    // haya nada no se pintan— y el `AsyncValue` sin tocar para la hora, porque
    // ahi «todavia no he mirado» tiene que poder distinguirse de «no hay nada».
    // Ver `TextosDelDia.datosDeLas`.
    final loQueHay = ref.watch(loQueHayProvider);
    final hay = loQueHay.value;
    final deCuandoSon = loQueHay.whenData((r) => r.laMasVieja);
    final pendientes = ref.watch(sinSubirProvider).value ?? 0;
    // LO QUE ESTA AQUI, NO ESTA ARRIBA Y NO LO VA A SUBIR NADIE.
    //
    // No sale en `pendientes` —no le queda apunte— ni en la bandeja —no lo
    // rechazo nadie—, asi que sin esto esta pieza pintaba «Todo al día · no
    // queda nada sin enviar» en VERDE encima de una ruta que solo existe en
    // este telefono. Ver `QueToca.trabajoColgado`.
    //
    // Es un `Stream` sobre las tablas (`trabajoHuerfanoProvider`) y no una
    // pregunta de una vez: lo que hay que cazar aparece con la pantalla ya
    // delante — es la regla del §3-ter y del §4-bis, escrita alli y rota el
    // mismo dia.
    final colgado = loQueNadieVaASubir(
      ref.watch(trabajoHuerfanoProvider).value ?? const <TrabajoHuerfano>[],
    );

    // EL ESTADO SALE DE SI LAS PETICIONES LLEGAN, no de si el aparato cree que
    // hay wifi. En Cuba el telefono ensena el wifi conectado y no sale un
    // paquete; `connectivity_plus` sirve para intentarlo antes y para nada mas
    // (`red/salud.dart`).
    final salud = ref.watch(saludDeLaRedProvider);

    // El latido, sólo para que esto se redibuje mientras el intento corre. Ver
    // `latidoDelIntentoProvider`.
    ref.watch(latidoDelIntentoProvider);
    final empezadoA = marcha.empezadoA;
    final toca = queTocaAhora(
      enVuelo: marcha.enVuelo,
      paso: marcha.avance?.paso,
      vaMal: salud.vaMal,
      pendientes: pendientes,
      llevaEnVuelo: empezadoA == null
          ? null
          : ref.watch(relojProvider)().difference(empezadoA),
      // La MISMA pregunta que apaga el boton de la franja, para que las dos
      // piezas digan lo mismo: si los datos son de ahora, no hay que traerlos.
      //
      // MAS LA GUARDA DEL RELOJ. Con el reloj del telefono por DETRAS de la
      // marca de la bajada, `EstadoFrescura` contesta «recientes» —la resta sale
      // negativa— y esta pieza se plantaba en `todoAlDia`: verde y **sin boton
      // de traer el dia**, con los pedidos de anteayer dentro. Ver
      // `elRelojNoCuadra`.
      hayQueTraer:
          EstadoFrescura.de(
            ref.watch(frescuraGlobalProvider).value,
            ahora: ref.watch(relojProvider)(),
          ).enAmbar ||
          elRelojNoCuadra(
            ref.watch(frescuraGlobalProvider).value,
            ahora: ref.watch(relojProvider)(),
          ),
      hayTrabajoColgado: colgado.hayAlguno,
    );

    return BannerDeGesto(
      titulo: TextosDelDia.titulo(toca, sinSubir: pendientes),
      explicacion: TextosDelDia.explicacion(toca),
      lineaFuerte: _lineaFuerte(
        toca: toca,
        marcha: marcha,
        trajo: trajo,
        entrego: entrego,
        hay: hay,
        deCuandoSon: deCuandoSon,
        pendientes: pendientes,
        colgado: colgado,
      ),
      lineaSuave: _lineaSuave(
        toca: toca,
        trajo: trajo,
        entrego: entrego,
        hay: hay,
        deCuandoSon: deCuandoSon,
        pendientes: pendientes,
      ),
      color: _color(toca: toca, trajo: trajo, entrego: entrego),
      icono: switch (toca) {
        QueToca.trayendo || QueToca.enviando => Icons.hourglass_top,
        QueToca.sinConexion => Icons.cloud_off_outlined,
        QueToca.hayQueEnviar => Icons.cloud_upload_outlined,
        QueToca.trabajoColgado => Icons.report_problem_outlined,
        QueToca.alDia => Icons.cloud_download_outlined,
        QueToca.todoAlDia => Icons.check_circle_outline,
      },
      textoDelBoton: TextosDelDia.boton(toca, sinSubir: pendientes),
      alPulsarBoton: switch (toca) {
        // Mientras corre no se vuelve a disparar, y sin senal no hay boton. El
        // candado de verdad sigue estando en `ciclo.dart`: quien llegue mientras
        // uno va se engancha al que ya corre.
        QueToca.trayendo || QueToca.enviando || QueToca.sinConexion => null,
        QueToca.hayQueEnviar => () => abrirCajonDeEntregarElDia(
          context,
          empezarYa: true,
        ),
        // Sin boton: no hay nada que pulsar que lo arregle. Ver
        // `QueToca.trabajoColgado`.
        QueToca.trabajoColgado => null,
        QueToca.alDia => () => abrirCajonDeTraerElDia(context, empezarYa: true),
        // Nada que hacer: no hay boton. Ver `QueToca.todoAlDia`.
        QueToca.todoAlDia => null,
      },
      // Pulsar la pieza abre el cajon SIN disparar nada: es para mirar que se
      // tiene. Sin senal es la unica forma de llegar, y ahi dentro el boton
      // sigue existiendo — si la pista se equivoco, desde el cajon se intenta de
      // verdad.
      alPulsarBanner: pendientes > 0
          ? () => abrirCajonDeEntregarElDia(context)
          : () => abrirCajonDeTraerElDia(context),
    );
  }

  String _lineaFuerte({
    required QueToca toca,
    required Marcha marcha,
    required LoQueSeTrajo? trajo,
    required LoQueSeEntrego? entrego,
    required RecuentoDeLoQueHay? hay,
    required AsyncValue<DateTime?> deCuandoSon,
    required int pendientes,
    required List<TrabajoHuerfano> colgado,
  }) {
    switch (toca) {
      case QueToca.trayendo:
      case QueToca.enviando:
        return TextosDelDia.porDondeVa(marcha.avance);
      case QueToca.sinConexion:
        return TextosDelDia.deQueHoraYQueQueda(deCuandoSon, pendientes);
      case QueToca.hayQueEnviar:
        // Si se acaba de intentar, lo que manda es COMO QUEDO: "Quedan 23 sin
        // subir" dice mas que repetir el numero.
        return entrego != null
            ? TextosDeEntregarElDia.comoQuedo(entrego)
            : TextosDelDia.sinSubir(pendientes);
      case QueToca.trabajoColgado:
        // SE NOMBRA CADA TIPO: «1 ruta», «1 ruta y 2 almacenes». «Hay trabajo
        // colgado» no le dice a nadie a que pantalla ir a mirar.
        return colgado.texto;
      case QueToca.alDia:
      case QueToca.todoAlDia:
        if (entrego != null && entrego.completo) {
          return TextosDeEntregarElDia.comoQuedo(entrego);
        }
        if (trajo != null) return TextosDeTraerElDia.comoQuedo(trajo);
        return hay == null ? '' : TextosDeTraerElDia.lasTresCifras(hay);
    }
  }

  String _lineaSuave({
    required QueToca toca,
    required LoQueSeTrajo? trajo,
    required LoQueSeEntrego? entrego,
    required RecuentoDeLoQueHay? hay,
    required AsyncValue<DateTime?> deCuandoSon,
    required int pendientes,
  }) {
    switch (toca) {
      case QueToca.trayendo:
      case QueToca.enviando:
        return '';
      case QueToca.sinConexion:
        return '';
      case QueToca.hayQueEnviar:
        return entrego != null
            ? TextosDeEntregarElDia.subieron(entrego.subidos)
            : TextosDelDia.datosDeLas(deCuandoSon);
      case QueToca.trabajoColgado:
        return TextosDelDia.datosDeLas(deCuandoSon);
      case QueToca.alDia:
      case QueToca.todoAlDia:
        if (entrego != null && entrego.completo) {
          return TextosDeEntregarElDia.subieron(entrego.subidos);
        }
        if (trajo != null) return TextosDeTraerElDia.deLasHoras(trajo.hora);
        return TextosDelDia.datosDeLas(deCuandoSon);
    }
  }

  /// El color de la banda. **Verde solo cuando de verdad esta todo**: las dos
  /// guardas (`LoQueSeTrajo.completo` y `LoQueSeEntrego.completo`) siguen
  /// viviendo en su sitio y aqui solo se leen.
  Color _color({
    required QueToca toca,
    required LoQueSeTrajo? trajo,
    required LoQueSeEntrego? entrego,
  }) {
    switch (toca) {
      case QueToca.trayendo:
      case QueToca.enviando:
        return Colores.enCurso;
      case QueToca.sinConexion:
        return Colores.ambar;
      case QueToca.hayQueEnviar:
        // Rojo si ya se intento y quedo algo; ambar si todavia no se ha
        // intentado. El ambar dice «mira esto»; el rojo, «esto ya es un
        // problema».
        return entrego != null ? Colores.rojo : Colores.ambar;
      // ROJO SIN CONDICIONES. Esto no se arregla esperando ni pulsando: es
      // trabajo que ya esta perdido salvo que alguien haga algo.
      case QueToca.trabajoColgado:
        return Colores.rojo;
      // Todo al dia es el unico estado que se puede pintar VERDE sin mas: no
      // queda nada por hacer y los datos son de ahora.
      case QueToca.todoAlDia:
        return Colores.verde;
      case QueToca.alDia:
        if (entrego != null && !entrego.completo) return Colores.rojo;
        if (trajo == null) return Colores.primario;
        return trajo.completo
            ? Colores.verde
            : trajo.sinSenal
            ? Colores.ambar
            : Colores.rojo;
    }
  }
}
