// El detalle de la ruta elegida: la columna derecha.
//
// Todo sale de la base local, asi que sin red se ve entero: el mapa, las
// paradas, la carga total, los km, el peso, el importe y la duracion. Lo que
// necesita señal —el fondo de calles, el recorrido por carretera y abrir Google
// Maps— **mejora** lo que ya hay y, cuando no llega, la pantalla lo dice con el
// motivo a la vista. Nunca en silencio, y nunca una rueda girando.
//
// ## Que se desplaza hasta el final
//
// Jose, 17/09/2026, mirando el original: «me corta parte de abajo, esto hasta
// del mapa, no solo de la última card, no puedo ver el final». Es un fallo del
// patron, no algo que copiar, y aqui se evita por tres sitios a la vez:
//
//  * esto es un `ListView`, o sea que **se desplaza** de arriba abajo;
//  * el mapa pide un alto PROPIO y con techo (`altoDelMapa`), nunca «lo que
//    sobre»: un hijo sin alto dentro de algo que se desplaza es exactamente
//    como se corta esto;
//  * el relleno de abajo (ver `rellenoAlFinalDelDetalle`) deja la ultima linea
//    por encima de la barra del sistema del telefono.

import '../../../nucleo/regla_de_entrada.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/tema.dart';
import '../../../impresion/pre_despacho.dart' show pdfPreDespacho;
import '../../../impresion/vista_previa.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../distribuidores/datos/distribuidor_de_la_ruta.dart';
import '../../distribuidores/vista/distribuidor_de_la_ruta.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';
import '../../pedidos/datos/acciones_de_pedido.dart'
    show porQueNoSeLePuedeCambiarElPunto;
import '../../pedidos/vista/cajon_ubicar_entrega.dart';
import '../../pedidos/vista/kit.dart';
import '../../pedidos/vista/vista_pre_despacho.dart';
import '../datos/acciones_rutas.dart';
import '../datos/formato_de_la_ruta.dart';
import '../datos/importe_de_la_ruta.dart';
import '../datos/pre_despacho_de_la_ruta.dart';
import '../datos/repositorio_rutas.dart';
import '../estado/proveedores_rutas.dart';
import 'aviso_de_facturas_canceladas.dart';
import 'cierre_de_ruta.dart';
import 'mapa_de_la_ruta.dart';
import 'paradas_ordenables.dart';
import 'tabla_por_producto_y_factura.dart';

/// EL RELLENO DE ABAJO DEL TODO.
///
/// En un telefono, la barra de gestos del sistema se come la ultima linea de lo
/// que se desplaza: se llega al final de la lista y el ultimo renglon queda
/// medio tapado, que se lee como «no puedo ver el final». Generoso a proposito,
/// que sobre aire no molesta y que falte si.
const rellenoAlFinalDelDetalle = 56.0;

class DetalleDeRuta extends ConsumerWidget {
  const DetalleDeRuta({required this.rutaId, this.enCajon = false, super.key});

  final String rutaId;

  /// ¿VA DENTRO DE UN [Cajon]? (el móvil, ver [CajonDelDetalleDeRuta]).
  ///
  /// Cambia dos cosas y nada más:
  ///
  ///  * **Quien desplaza.** Aquí fuera esto es un `ListView` y se desplaza solo;
  ///    dentro del cajón el que se desplaza es el cuerpo del cajón, y un
  ///    `ListView` dentro de otro desplazable es un alto sin límite, o sea el
  ///    error de «vertical viewport was given unbounded height». Así que ahí
  ///    dentro esto es una `Column` a secas.
  ///  * **La cabecera.** El cajón ya trae el código de la ruta en su título y la
  ///    ✕ que no desaparece nunca; repetir aquí las dos cosas es gastar el alto
  ///    del teléfono, que es justo lo que se venía a arreglar.
  final bool enCajon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TRES ESTADOS, NO DOS. Y el que faltaba era el que dejaba la rueda girando
    // para siempre.
    //
    // Esto era `ref.watch(...).value` y `if (ruta == null) return
    // EstadoVacio('Cargando...')`, o sea **dos cosas distintas metidas en un
    // solo `null`**: «todavía no se sabe» y «esa ruta ya no está». Jose,
    // 17/09/2026, con una ruta de prueba borrada del servidor y el teléfono
    // apuntando a ella: «la apk se me quedó cargando ahí en la ruta». Era
    // literal — nunca iba a llegar nada, porque ya no había nada que llegara.
    //
    // Es la familia de fallos del §3-ter y del «Sin colocar (722) encima de una
    // lista de 293»: un estado vacío que se lee como si fuera otro. Aquí se
    // miran los tres del `AsyncValue`, y el `error` también, que antes tampoco
    // se miraba.
    final asincrono = ref.watch(rutaConTodoProvider(rutaId));
    final ruta = switch (asincrono) {
      AsyncValue(:final error?) => _NoEsta(
        motivo: 'No se pudo abrir esta ruta: $error',
      ),
      // `data(null)` = la ruta ya no está. Se dice, y se da la salida: sin ella
      // en el móvil no queda nada a lo que volver.
      AsyncData(value: null) => const _NoEsta(
        motivo:
            'Esta ruta ya no está. La han borrado o se fue a otra sucursal.',
      ),
      AsyncData(value: _?) => null,
      // Sólo aquí es «cargando»: cuando de verdad no se sabe todavía.
      _ => const EstadoVacio('Cargando...'),
    };
    if (ruta != null) return ruta;
    final datos = asincrono.value!;

    final paradas =
        ref.watch(paradasDeRutaProvider(rutaId)).value ?? datos.paradas;
    final conTodo = RutaConTodo(
      ruta: datos.ruta,
      paradas: paradas,
      vehiculo: datos.vehiculo,
      sucursal: datos.sucursal,
    );

    final piezas = <Widget>[
      // La cabecera, SÓLO fuera del cajón: dentro, el código de la ruta y la ✕
      // los pone el propio cajón (ver [enCajon]).
      if (!enCajon) ...[_Cabecera(ruta: conTodo), const SizedBox(height: 8)],
      _Acciones(ruta: conTodo),
      const SizedBox(height: 12),
      // Las facturas que se cancelaron en Ventra y se quitaron de ESTA ruta (esquema 15).
      FacturasCanceladasDeLaRuta(rutaId: conTodo.ruta.id),
      // EN QUE ANDA EL CAMION DE ESTA RUTA. Entra por parametro y no lo lee la
      // cabecera, porque esa cabecera se prueba SUELTA, sin `ProviderScope` (ver
      // su nota): dentro de un `testWidgets` una consulta de Drift cuelga la
      // prueba en vez de fallarla (`CLAUDE.md` §5).
      LineaDeDatosDeLaRuta(
        ruta: conTodo,
        ahora: ref.read(relojProvider)(),
        ocupacionDelCamion: conTodo.ruta.vehicleId == null
            ? null
            : ref
                  .watch(camionesOcupadosProvider)
                  .value?[conTodo.ruta.vehicleId],
        seSabeLaOcupacion: ref.watch(camionesOcupadosProvider).value != null,
      ),
      // QUIÉN REPARTE (issue 7): el nombre sale de la tabla local, así un renombrado se ve
      // aquí sin tocar la ruta. Va FUERA de `LineaDeDatosDeLaRuta` a propósito: esa cabecera
      // se prueba suelta, sin `ProviderScope`, y este renglón lee un provider (15/10/2026: la
      // fusión lo metió dentro y once pruebas de la cabecera reventaron).
      const SizedBox(height: 4),
      DistribuidorDeLaRuta(distribuidorId: conTodo.ruta.distribuidorId),
      // CÓMO ESTÁ ORDENADA (issue 11 de Amado). Sólo donde aún se puede cambiar:
      // ver `comoEstaOrdenada`, por qué en una completada no se enseña.
      if (conTodo.ruta.status != EstadoRuta.completada) ...[
        const SizedBox(height: 4),
        Text(
          comoEstaOrdenada(optimizada: conTodo.ruta.optimized),
          key: claveDeComoEstaOrdenada,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 12),
      // EL MAPA, con sus cuatro gestos —abrir en Google Maps, WhatsApp,
      // compartir y copiar. Antes aqui habia medio gesto: un boton que
      // copiaba el enlace al portapapeles y nada mas, con el mapa sin portar
      // del Next. Jose, 17/09/2026: «El mapa, ¿por qué no me sale el mapa con
      // la ruta, si teníamos hasta para compartir la ruta por WhatsApp?».
      MapaDeLaRuta(ruta: conTodo),
      const SizedBox(height: 12),
      _Paradas(ruta: conTodo),
      const SizedBox(height: 20),
      // EL PRE-DESPACHO, EN TODAS LAS RUTAS. Antes sólo lo tenía la que se
      // armaba a mano en el asistente; la que salía del tablero no lo traía.
      // Ver `datos/pre_despacho_de_la_ruta.dart`.
      _PreDespacho(ruta: conTodo),
    ];

    // Dentro del cajón el que se desplaza es el cuerpo del cajón: aquí una
    // `Column` y nada más. Un `ListView` dentro de un `SingleChildScrollView`
    // revienta por alto sin límite.
    if (enCajon) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: piezas,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, rellenoAlFinalDelDetalle),
      children: piezas,
    );
  }
}

/// EL DETALLE DE LA RUTA, EN UN CAJÓN. **La forma del móvil.**
///
/// Jose, 22/09/2026: «cuando estoy viendo un detalle de una ruta me puedo mover
/// por los diferentes tabs eso no lo quiero ponlo en un drawer en el movil para
/// ver eso y asi queda mejor para no andar navegando».
///
/// Hasta hoy, en el teléfono el detalle SUSTITUÍA a la lista dentro de la misma
/// pantalla, y eso traía las dos cosas que Jose pedía quitar:
///
///  * la cabecera de la lista —el buscador, los filtros y las tres pestañas—
///    seguía clavada arriba encima del detalle, donde ya no sirve de nada.
///    Medido en un teléfono de 2340 px de alto: **~1050 px** de cabecera y el
///    mapa de la ruta metido en una rendija de ~270 px, con sus mandos de + / −
///    y el de pantalla completa fuera de la vista;
///  * y el carrusel de pestañas seguía vivo debajo, así que con una ruta abierta
///    se podía deslizar a `Historial` — o sea, navegar a otro sitio desde dentro
///    de un detalle.
///
/// Un cajón resuelve las dos de una vez y sin condiciones nuevas: es una ruta
/// modal, o sea que **tapa la pantalla entera** (también la barra lateral y la
/// superior del armazón, que un `Stack` de dentro no alcanzaría) y **se come
/// todos los gestos** de lo que hay debajo. Se mira la ruta, se cierra, y la
/// lista sigue exactamente donde estaba: misma pestaña, mismo desplazamiento,
/// misma página.
///
/// La ✕ es la de la cabecera del cajón, la de la regla de la casa: fuera del
/// cuerpo desplazable, así que no se puede perder de vista por mucho que se baje.
class CajonDelDetalleDeRuta extends ConsumerWidget {
  const CajonDelDetalleDeRuta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elegida = ref.watch(rutaElegidaProvider);

    // SI LA RUTA SE SUELTA DESDE DENTRO, EL CAJÓN SE CIERRA SOLO.
    //
    // Hay tres sitios que la sueltan sin tocar la ✕: completar la ruta (que
    // además se va al `Historial`), el «Volver a la lista» de una ruta que ya no
    // está, y el cierre cuando completa. Sin esto, cualquiera de los tres deja
    // el cajón abierto encima de una ruta que ya no hay.
    //
    // Después del fotograma, no dentro: sacar una ruta del `Navigator` en plena
    // construcción es el «markNeedsBuild called during build» de siempre.
    ref.listen<String?>(rutaElegidaProvider, (_, ahora) {
      if (ahora != null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    });

    final datos = elegida == null
        ? null
        : ref.watch(rutaConTodoProvider(elegida)).value;
    final subtitulo = [
      if ((datos?.ruta.name ?? '').isNotEmpty) datos!.ruta.name!,
      if ((datos?.sucursal?.name ?? '').isNotEmpty) datos!.sucursal!.name,
    ].join(' · ');

    return Cajon(
      // El código de la ruta manda: es lo que se viene a mirar. Mientras no ha
      // llegado la fila no se inventa un código, se dice de qué va el panel.
      titulo: datos?.ruta.routeCode ?? datos?.ruta.id ?? 'Detalle de la ruta',
      subtitulo: subtitulo.isEmpty ? null : subtitulo,
      ancho: AnchoCajon.xl,
      cuerpo: elegida == null
          ? const SizedBox.shrink()
          : DetalleDeRuta(rutaId: elegida, enCajon: true),
    );
  }
}

/// LA CLAVE DE LA ✕ DE LA CABECERA DEL DETALLE. Publica porque la prueba la
/// pulsa, y buscarla por el icono ataria la prueba al dibujo.
///
/// En el movil hay ADEMAS una barra fija de «Volver a la lista» encima del
/// detalle (`pantalla_rutas.dart`), que es la salida que no se puede perder de
/// vista. Esta ✕ es la de escritorio, donde la lista se ve al lado y lo que
/// hace falta es poder DESELECCIONAR.
const claveDeLaEquisDelDetalle = ValueKey('ruta-cerrar-detalle');

/// LA RUTA QUE YA NO ESTÁ: se dice, y se sale.
///
/// La salida es la mitad que importa. Sin ella, en el teléfono —donde el detalle
/// sustituye a la lista— quien llega aquí se queda mirando un cartel y nada
/// más: la ruta elegida sigue puesta y la pantalla no puede pintar otra cosa.
class _NoEsta extends ConsumerWidget {
  const _NoEsta({required this.motivo});

  final String motivo;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(motivo, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          BotonPrincipal(
            key: claveDeVolverDeLaQueNoEsta,
            icono: Icons.arrow_back,
            texto: 'Volver a la lista',
            alPulsar: () => ref.read(rutaElegidaProvider.notifier).elegir(null),
          ),
        ],
      ),
    ),
  );
}

/// La clave del botón de salir de una ruta que ya no existe.
const claveDeVolverDeLaQueNoEsta = ValueKey('ruta-que-ya-no-esta-volver');

/// Las claves de los dos botones que cambian con el estado de la ruta. Buscarlos
/// por su texto ataria la prueba a como se llaman hoy, y justo el texto es una
/// de las cosas que cambia: sólo `Ver cierre` en una ruta completada.
const claveDelCierre = ValueKey('ruta-cierre');
const claveDeComoEstaOrdenada = ValueKey('ruta-como-esta-ordenada');
const claveDeCompletar = ValueKey('ruta-marcar-como-completada');

class _Cabecera extends ConsumerWidget {
  const _Cabecera({required this.ruta});

  final RutaConTodo ruta;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ruta.ruta.routeCode ?? ruta.ruta.id,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (ruta.ruta.name != null) Text(ruta.ruta.name!),
          ],
        ),
      ),
      if (ruta.sucursal != null)
        Insignia(ruta.sucursal!.name, color: Colores.gris),
      // LA SALIDA. Jose, 17/09/2026: «toqué una ruta hecha para ver detalles y
      // no puedo salir de esa ruta señalada».
      //
      // Y era literal: la ruta elegida sólo se soltaba al COMPLETARLA. En el
      // telefono el detalle sustituye a la lista, asi que quien tocaba una ruta
      // ya hecha —que no se puede completar— se quedaba dentro sin ninguna
      // salida.
      //
      // Va en la cabecera y **a todos los anchos**, no solo en el movil: en
      // escritorio la lista se ve al lado, pero deseleccionar tampoco se podia.
      // Y no desaparece nunca, que es la regla de la casa para la ✕.
      IconButton(
        key: claveDeLaEquisDelDetalle,
        icon: const Icon(Icons.close),
        tooltip: 'Volver a la lista',
        onPressed: () => ref.read(rutaElegidaProvider.notifier).elegir(null),
      ),
    ],
  );
}

class _Acciones extends ConsumerWidget {
  const _Acciones({required this.ruta});

  final RutaConTodo ruta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acciones = ref.read(accionesDeRutaProvider);
    final estado = ruta.ruta.status;

    Future<void> hacer(Future<void> Function() que) async {
      final mensajero = ScaffoldMessenger.maybeOf(context);
      try {
        await que();
      } on RechazoLocal catch (fallo) {
        mensajero?.showSnackBar(SnackBar(content: Text(fallo.mensaje)));
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ControlSenalado(
          nombre: Senalado.rutasVerParadas,
          child: OutlinedButton(
            onPressed: () => _verParadas(context, ruta),
            child: Text('Ver paradas (${ruta.paradas.length})'),
          ),
        ),
        if (estado == EstadoRuta.planificada)
          ControlSenalado(
            nombre: Senalado.rutasIniciar,
            child: BotonPrincipal(
              icono: Icons.play_arrow,
              texto: 'Iniciar ruta',
              alPulsar: () => hacer(() async {
                await acciones.iniciar(ruta.ruta.id);
                // **Y se va con ella a la pestaña donde acaba de caer.**
                //
                // Iniciar la saca de `Planificadas` —correctamente: ya no esta
                // activa, esta en curso—, y sin esto la ruta le desaparece de
                // delante a quien acaba de arrancarla, que se queda mirando un
                // hueco y creyendo que no funciono. La de Next hace esto mismo
                // (`routes/page.tsx:447`).
                ref
                    .read(pestanaRutasProvider.notifier)
                    .elegir(PestanaRutas.enCurso);
              }),
            ),
          ),
        // Jose, 06/10/2026: los estados se preguntan sólo al pulsar
        // «Marcar como completada», nunca con un cierre previo en curso.
        // EL CIERRE, ya completada: **`Ver cierre`, y sin la cuenta**. En una
        // ruta cerrada «sin marcar» ya no es algo que hacer: es como acabo. Un
        // `Cierre (3)` ahi parece una tarea pendiente que nadie va a poder
        // hacer, y eso es peor que no ensenar el numero.
        if (estado == EstadoRuta.completada)
          ControlSenalado(
            nombre: Senalado.rutasCierre,
            child: OutlinedButton(
              key: claveDelCierre,
              onPressed: () => abrirCajon<void>(
                context,
                (_) => CierreDeRuta(
                  rutaId: ruta.ruta.id,
                  modo: ModoDelCierre.soloLectura,
                ),
              ),
              child: const Text('Ver cierre'),
            ),
          ),
        if (estado == EstadoRuta.enCurso)
          ControlSenalado(
            nombre: Senalado.rutasCompletar,
            child: BotonPrincipal(
              key: claveDeCompletar,
              icono: Icons.check_circle_outline,
              texto: 'Marcar como completada',
              alPulsar: () {
                // La navegacion de despues es la misma venga por donde venga:
                // soltar la ruta elegida e irse al Historial, como la de Next
                // (`routes/page.tsx:463-464`). Quedarse con ella abierta a la
                // derecha despues de darla por cerrada deja el detalle de algo que
                // ya no es de lo que va la pantalla.
                void luego() {
                  ref.read(rutaElegidaProvider.notifier).elegir(null);
                  ref
                      .read(pestanaRutasProvider.notifier)
                      .elegir(PestanaRutas.historial);
                }

                // Siempre se revisa la hoja, incluso con marcas anteriores.
                // Las selecciones iniciales se conservan para confirmar o corregir.
                // Sin paradas el modal también permite confirmar la ruta vacía.
                abrirCajon<void>(
                  context,
                  (_) => CierreDeRuta(
                    rutaId: ruta.ruta.id,
                    modo: ModoDelCierre.alCompletar,
                    alCompletar: luego,
                  ),
                );
                RegistroDeControles.completar(Senalado.rutasCompletar);
              },
            ),
          ),
        // ESTE PESO NO PASA POR `pesoDeLaRuta`, Y ES A PROPÓSITO.
        //
        // No es «el peso de la ruta»: es el aviso de sobrepeso, y está escrito
        // letra a letra como el del servidor —«Peso total (%.1f kg) supera la
        // capacidad del vehículo (%g kg)», `api/internal/api/rutas.go:936` y
        // `tablero.go:1571`—. Si dos fallan a la vez, la persona tiene que leer
        // el mismo mensaje aquí y allí (lo mismo hace `acciones_rutas.armar`).
        // Redondearlo aquí lo separaría del literal del servidor, que es peor
        // que la diferencia de formato que arregla.
        if (ruta.sobrepeso)
          Insignia(
            'Peso total (${ruta.pesoTotal.toStringAsFixed(1)} kg) supera '
            'capacidad (${ruta.vehiculo!.capacity.toStringAsFixed(0)} kg)',
            color: Colores.ambar,
          ),
      ],
    );
  }

  void _verParadas(BuildContext context, RutaConTodo ruta) {
    abrirCajon<void>(
      context,
      // EL CAJON ENTERO va dentro del `Consumer`, titulo incluido: lo que se ve
      // aqui CAMBIA con el cajon delante (§3-ter). Con las paradas capturadas al
      // abrirlo, quitar una dejaba su tarjeta puesta —y el «(3)» del titulo en
      // 3— hasta cerrar y volver a abrir: la parada fantasma, vista desde la
      // hoja. `paradasDeRutaProvider` es el `Stream` sobre `orders`.
      (_) => Consumer(
        builder: (context, ref, _) {
          final paradas =
              ref.watch(paradasDeRutaProvider(ruta.ruta.id)).value ??
              ruta.paradas;
          // LA RUTA VIVA: el estado y la firma de quién ordenó cambian con el
          // cajón delante (al reordenar, o si otro la completa).
          final viva =
              ref.watch(rutaConTodoProvider(ruta.ruta.id)).value?.ruta ??
              ruta.ruta;
          // LO QUE HAY QUE BAJAR EN CADA PARADA.
          //
          // Jose, 17/09/2026: «el chofer debe saber qué es lo que se tiene
          // que bajar en cada parada, ahí no se ve nada de lo que se va a
          // bajar». Tenía razón y era el agujero grande de esta hoja: decía
          // cuánto pesa y cuánto se cobra, o sea lo que le importa a la
          // oficina, y **no decía qué es**, que es lo único que le sirve a
          // quien descarga el camión delante del cliente.
          final renglones =
              ref.watch(renglonesDeParadasProvider(ruta.ruta.id)).value ??
              const <String, List<RenglonConPeso>>{};
          return Cajon(
            titulo: 'Paradas y precio por cliente (${paradas.length})',
            subtitulo: ruta.ruta.routeCode ?? ruta.ruta.id,
            cuerpo: Padding(
              padding: const EdgeInsets.all(16),
              // REORDENAR ARRASTRANDO (issue 11): en una ruta no completada
              // cada parada lleva su asa y arriba «Ordenar por cercanía».
              child: ParadasOrdenables(
                rutaId: viva.id,
                estado: viva.status,
                optimizada: viva.optimized,
                paradas: paradas,
                alReordenar: ({orden}) => ref
                    .read(accionesDeRutaProvider)
                    .reordenar(viva.id, orden: orden),
                tarjeta: (parada, numero, asa) => TarjetaDeParada(
                  numero: numero,
                  parada: parada,
                  asa: asa,
                  origenLat: viva.originLat,
                  origenLng: viva.originLng,
                  lineas: renglones[parada.id] ?? const <RenglonConPeso>[],
                  alQuitar: viva.status == EstadoRuta.planificada
                      ? () => _quitarDeLaRuta(context, ref, viva.id, parada)
                      : null,
                  // Solo donde se puede: sin entregar y en una ruta no completada
                  // (la misma pregunta que le hace el cajón y la acción).
                  alUbicar:
                      porQueNoSeLePuedeCambiarElPunto(parada, viva) == null
                      ? () => abrirUbicarLaEntrega(context, parada.id)
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// «QUITAR DE RUTA»: pregunta EN UN CAJON, y solo si se contesta que si se quita.
  ///
  /// Era un `AlertDialog` centrado, que es lo que la casa no hace: **cajon
  /// siempre, tambien en escritorio** (`CLAUDE.md` §4, excepcion aprobada el
  /// 05/09/2026). La forma es la de [preguntarAntesDeBorrar] —titulo, lo que
  /// pasa, el boton que NOMBRA lo que se hace y un «No» al lado— y cerrar sin
  /// contestar es NO: sacar a alguien de un camion no se hace por un descuido.
  ///
  /// Cogerlo del [context] de la pantalla y no del cajon de las paradas: el
  /// segundo cajon se abre ENCIMA del primero y el primero tiene que seguir
  /// ahi, repintandose cuando la parada se va.
  Future<void> _quitarDeLaRuta(
    BuildContext context,
    WidgetRef ref,
    String rutaId,
    Pedido parada,
  ) async {
    // El mensajero y las acciones se cogen ANTES de cualquier `await`: despues el
    // cajon que pregunta ya se cerro.
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final acciones = ref.read(accionesDeRutaProvider);
    final seguro = await preguntarAntesDeQuitar(
      context,
      cliente: parada.customerName,
      conduce: parada.operationNumber,
      factura:
          facturaConFecha(parada.facturaNumero, parada.facturaAt) ??
          'Sin número de factura',
    );
    if (!seguro) return;
    try {
      await acciones.quitarParada(rutaId, parada.id);
    } on RechazoLocal catch (fallo) {
      mensajero?.showSnackBar(SnackBar(content: Text(fallo.mensaje)));
    }
  }
}

/// LA PREGUNTA DE ANTES DE QUITAR UNA PARADA DE SU RUTA.
///
/// **Es publica para poder probarla suelta**, igual que [TarjetaDeParada]: el
/// gesto completo pasa por el cajon de las paradas y su `Stream`, y lo que hay
/// que atar aqui es la pregunta —cajon, nombra a quien sale, dice a donde vuelve
/// y contestar «No» o cerrar no quita nada—.
///
/// ## A donde vuelve, y lo que NO se sabe desde aqui
///
/// Una factura que salio de una zona del tablero vuelve a esa zona cuando el
/// servidor procesa el «quitar» (en la web, en el acto; en la APK y el
/// escritorio, al sincronizar). Pero **el aparato no sabe de que zona salio**: ese
/// origen vive en el servidor (`board_route_origins`) y la bajada no lo trae.
/// Asi que la pregunta dice lo que SI es verdad en todos los casos —vuelve a
/// pedidos disponibles— y lo que pasa si ademas venia del tablero, sin inventar
/// un nombre de zona que no se tiene.
Future<bool> preguntarAntesDeQuitar(
  BuildContext contexto, {
  required String cliente,
  String? conduce,
  String? factura,
}) async {
  final seguro = await abrirCajon<bool>(
    contexto,
    (contextoCajon) => Cajon(
      titulo: 'Quitar de la ruta',
      // La factura va primero (issue 17 de Amado): es lo que identifica el pedido.
      subtitulo: [
        ?factura,
        cliente,
        if ((conduce ?? '').trim().isNotEmpty) 'Conduce: $conduce',
      ].join(' · '),
      cuerpo: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '«$cliente» sale de esta ruta y vuelve a facturas disponibles. '
              'La ruta se queda con las demás paradas y su peso y su importe '
              'se recalculan sin él.\n\n'
              'Si la ruta se armó desde una zona del tablero, la factura '
              'regresa a esa zona cuando se sincronice (en la web, de '
              'inmediato).',
            ),
            const SizedBox(height: 20),
            BotonPrincipal(
              icono: Icons.remove_circle_outline,
              texto: 'Sí, quitar «$cliente» de la ruta',
              alPulsar: () => Navigator.of(contextoCajon).pop(true),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(contextoCajon).pop(false),
              child: const Text('No, dejarlo en la ruta'),
            ),
          ],
        ),
      ),
    ),
  );
  return seguro ?? false;
}

/// LA CABECERA DEL DETALLE: el renglon de datos de la ruta, y lo que le falta.
///
/// **Es publica a proposito, y no por gusto.** Lo unico que necesita es un
/// [RutaConTodo] armado a mano, asi que se prueba suelta, sin `ProviderScope` y
/// sin base: dentro de un `testWidgets` una consulta de Drift **cuelga la prueba
/// en vez de fallarla** (`CLAUDE.md` §5), y un cuelgue no prueba nada. Mismo
/// motivo por el que [AvisoDeRechazo] vive en su propio fichero publico.
class LineaDeDatosDeLaRuta extends StatelessWidget {
  const LineaDeDatosDeLaRuta({
    required this.ruta,
    this.ahora,
    this.ocupacionDelCamion,
    this.seSabeLaOcupacion = false,
    super.key,
  });

  final RutaConTodo ruta;

  /// La ruta ABIERTA que tiene cogido al camión de ésta, si hay alguna. Puede
  /// ser ésta misma —lo normal— o **otra**, que es el caso que importa: dos
  /// rutas con el mismo camión, que hasta el 28/09/2026 no se veía por ningún
  /// sitio. Ver `ConsultasRutas.camionesOcupados`.
  final RutaQueOcupa? ocupacionDelCamion;

  /// Si la consulta ya llegó. `false` por defecto para que la cabecera se pueda
  /// seguir probando suelta sin decir nada del camión: escribir «libre» sin
  /// haberlo comprobado sería un dato inventado.
  final bool seSabeLaOcupacion;

  /// CÓMO ANDA EL CAMIÓN, pegado a su nombre. Mismo criterio y mismo texto que
  /// la lista (`lista_rutas.dart`, `_comoAndaElCamion`): sólo se escribe lo que
  /// añade algo. Si quien lo tiene cogido es esta misma ruta no se dice nada
  /// —ya se está mirando—; si lo tiene otra, se dice cuál.
  String get _comoAndaElCamion {
    if (!seSabeLaOcupacion || ruta.vehiculo == null) return '';
    final ocupa = ocupacionDelCamion;
    if (ocupa == null) return ' · libre';
    if (ocupa.rutaId == ruta.ruta.id) return '';
    return ocupa.enCurso
        ? ' · EN RUTA en ${ocupa.titulo}'
        : ' · ya va en ${ocupa.titulo}';
  }

  /// La hora de ahora, para lo que lleva una ruta EN CURSO. Entra por aquí y no
  /// de un proveedor a propósito: esta cabecera se prueba suelta, sin
  /// `ProviderScope` (ver la nota de arriba). `null` deja el `—` de siempre.
  final DateTime? ahora;

  @override
  Widget build(BuildContext context) {
    final r = ruta.ruta;
    final estado = switch (r.status) {
      EstadoRuta.planificada => 'Planificada',
      EstadoRuta.enCurso => 'En curso',
      EstadoRuta.completada => 'Completada',
      _ => r.status,
    };
    // EL IMPORTE SE SUMA DE LAS PARADAS, NO SE LEE DE `totalPrice`.
    //
    // `routes.total_price` es `NOT NULL DEFAULT 0` en el servidor y llega aqui
    // con dos `?? 0` mas por el camino: no sabe decir «no se sabe», asi que
    // decia `$0.00` sobre dos paradas marcadas «sin cotizar» en la misma
    // pantalla (`RT-20260921-007`, 22/09/2026). Las paradas si saben decir
    // `null`. Ver `datos/importe_de_la_ruta.dart`.
    final importe = ImporteDeRuta.deLasParadas(
      ruta.paradas.map(
        (p) => costoDeLaParada(p.pedidoCosto, p.facturaDomicilio),
      ),
    );
    final queFalta = importe.queFalta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$estado · ${r.totalDistance.toStringAsFixed(1)} km (incl. regreso) · '
          // EL PESO DE LA RUTA, CON EL FORMATO DEL TABLERO.
          //
          // Aquí decía `kg(r.totalWeight)` —un decimal y punto— sobre el mismo
          // `double` que la zona del Tablero escribe con `pesoBonito` —entero y
          // coma—: «516 kg» allí y «516.5 kg» aquí, el mismo bulto
          // (28/09/2026). Lo que ata los dos formatos es
          // `el_mismo_peso_escrito_igual_test.dart`, no este comentario
          // (`CLAUDE.md` §3-bis).
          //
          // Y EL NÚMERO SALE DE LAS PARADAS, no de `routes.total_weight`, que
          // es lo que se arregló el 28/09/2026. Era el ÚNICO dato de este
          // renglón que no se sumaba de la lista que hay justo debajo —el
          // importe y la «Carga total» ya lo hacían—, y por eso era el único
          // que podía mentir: en la APK 1.0.13, `RT-20260928-003` decía «420
          // kg» encima de dos paradas de 419,7 y 96,8. El porqué entero está en
          // `datos/peso_de_la_ruta.dart`.
          '${pesoDeLaRuta(ruta.pesoTotal)} · ${importe.rotulo} · '
          // «Sin vehículo», LO MISMO QUE EN LA LISTA. Un `—` aquí se lee como
          // «no se sabe» estando al lado de otros dos que sí lo son, y no es
          // eso: es que esta ruta no lleva camión asignado, que es un dato.
          '${ruta.vehiculo?.name ?? 'Sin vehículo'}'
          '${ruta.vehiculo?.plate == null ? '' : ' · ${ruta.vehiculo!.plate}'}'
          '$_comoAndaElCamion · '
          '${fechaCorta(r.deliveryDate)} · '
          'Carga total: ${ruta.paradas.length} · '
          '${tiempoDeLaRuta(arranco: r.startedAt, termino: r.finishedAt, ahora: ahora)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        // Y DEBAJO, QUE HACER. El `— (2 de 5 sin cotizar)` de arriba dice que no
        // se sabe; esto dice a donde ir a arreglarlo, que es lo unico que sirve
        // a quien lo lee. Sale **solo cuando falta alguna**: un aviso que sale
        // siempre deja de leerse (`CLAUDE.md` §3-quinquies).
        if (queFalta != null) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.report_problem_outlined,
                size: 14,
                color: Colores.ambar,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  queFalta,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Colores.ambar),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Paradas extends ConsumerWidget {
  const _Paradas({required this.ruta});

  final RutaConTodo ruta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final renglones =
        ref.watch(renglonesDeParadasProvider(ruta.ruta.id)).value ??
        const <String, List<RenglonConPeso>>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Carga total',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entrada in _cargaTotal(renglones).entries)
              Insignia(
                '${entrada.key} ×${cantidad(entrada.value)}',
                color: Colores.enCurso,
              ),
          ],
        ),
      ],
    );
  }

  Map<String, double> _cargaTotal(Map<String, List<RenglonConPeso>> renglones) {
    final total = <String, double>{};
    for (final parada in ruta.paradas) {
      for (final r in renglones[parada.id] ?? const <RenglonConPeso>[]) {
        final nombre = r.renglon.description.trim();
        if (nombre.isEmpty) continue;
        total[nombre] = (total[nombre] ?? 0) + r.empaques;
      }
    }
    return total;
  }
}

/// EL PRE-DESPACHO DE LA RUTA: lo que hay que sacar del almacén, producto a
/// producto y factura a factura. Issue 8 de Amado.
///
/// Es **la misma vista** que el paso 4 del asistente y que Pedidos
/// ([VistaPreDespacho]), con la misma suma por debajo
/// (`datos/pre_despacho_de_la_ruta.dart`), y sale en TODAS las rutas: la armada a
/// mano y la que sale de una zona del tablero. «Carga total», encima, se queda
/// como estaba.
///
/// Debajo va la tabla «Por producto y factura» —un bloque por producto, una fila
/// por factura y el subtotal—, porque el almacén rebaja las tarjetas de estiba por cantidad Y
/// factura, y la cuenta por producto no se lo dice.
class _PreDespacho extends ConsumerWidget {
  const _PreDespacho({required this.ruta});

  final RutaConTodo ruta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `null` mientras no ha llegado: la vista dice «Cargando...» y no «Sin
    // productos», que sería afirmar que la ruta va vacía.
    final pre = ref.watch(preDespachoDeLaRutaProvider(ruta.ruta.id)).value;
    final titulo = Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.bold);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(PreDespacho.titulo, style: titulo)),
            BotonPrincipal(
              key: claveDeVerEImprimirElPreDespacho,
              icono: Icons.print_outlined,
              texto: PreDespacho.verEImprimir,
              // Una hoja en blanco no es una hoja.
              alPulsar: pre == null || pre.totales.lineas.isEmpty
                  ? null
                  : () => _verEImprimir(context, ref, pre),
            ),
          ],
        ),
        const SizedBox(height: 6),
        VistaPreDespacho(totales: pre?.totales),
        if (pre != null && pre.facturas.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(PorProductoYFactura.titulo, style: titulo),
          const SizedBox(height: 6),
          TablaPorProductoYFactura(
            productos: lineasDelPapel(pre.totales),
            facturas: pre.facturas,
          ),
        ],
      ],
    );
  }

  /// La hoja con la que alguien baja al almacén. Se mira primero y se imprime
  /// desde su vista previa, como en el asistente.
  Future<void> _verEImprimir(
    BuildContext context,
    WidgetRef ref,
    PreDespachoDeLaRuta pre,
  ) async {
    // El almacén tiene que saber a quién entrega la carga.
    final distribuidor = await nombreDelDistribuidorParaLaHoja(
      ref.read(baseProvider),
      ruta.ruta.distribuidorId,
    );
    if (!context.mounted) return;
    final fecha = ruta.ruta.deliveryDate;
    final hoja = hojaDePreDespachoDeLaRuta(
      distribuidor: distribuidor,
      totales: pre.totales,
      sucursal: ruta.sucursal?.name ?? '',
      vehiculo: ruta.vehiculo?.name ?? '',
      // `AAAA-MM-DD`, como lo escribe la hoja: se compara carácter a carácter.
      dia: fecha == null
          ? null
          : '${fecha.year.toString().padLeft(4, '0')}-'
                '${fecha.month.toString().padLeft(2, '0')}-'
                '${fecha.day.toString().padLeft(2, '0')}',
      pedidos: ruta.paradas.length,
      pesoKg: ruta.pesoTotal,
      facturas: pre.facturas,
    );
    final impresoEn = ref.read(relojProvider)();
    await abrirCajon<void>(
      context,
      (contexto) => Cajon(
        titulo: PreDespacho.tituloDeLaHoja,
        subtitulo: ruta.ruta.routeCode ?? ruta.ruta.id,
        ancho: AnchoCajon.xl,
        // EL ALTO SALE DE LA PANTALLA (el mismo 0.75 que las otras hojas): la
        // vista previa quiere todo el alto que le den y el cuerpo del cajón se
        // desplaza, así que sin un alto concreto no se pinta.
        cuerpo: SizedBox(
          height: MediaQuery.sizeOf(contexto).height * 0.75,
          child: VistaPreviaPdf(
            armar: (formato) => pdfPreDespacho(hoja, impresoEn: impresoEn),
            nombreDeFichero: 'pre-despacho.pdf',
          ),
        ),
      ),
    );
  }
}

/// La clave del botón que abre la hoja del pre-despacho de la ruta.
const claveDeVerEImprimirElPreDespacho = ValueKey('ruta-pre-despacho-imprimir');

/// UNA PARADA EN LA HOJA DE «VER PARADAS».
///
/// Jose, 17/09/2026, con el cajón abierto: «mejora la vista de las paradas,
/// porque ahí no veo nada; necesito más detalle y que se vea bien, no esa
/// mierda en texto».
///
/// Era literal: los cinco datos de cada parada iban pegados en un párrafo
/// separado por puntos, así que en una dirección larga el importe acababa en la
/// tercera línea, detrás de una coma. El dato que se busca de un vistazo en
/// esta hoja —**cuánto se le cobra a ese cliente**— era el peor colocado de
/// todos.
///
/// Ahora cada parada es una tarjeta con el número a la izquierda, el cliente y
/// su dirección en el medio, y **el importe en grande a la derecha**, alineado
/// con los de arriba y abajo para poder recorrerlos con el ojo. El peso y los
/// kilómetros bajan a dos insignias, que es lo que son: datos de apoyo.
///
/// Es la forma del patrón, que aquí acierta: en `delivery.procovar.cloud` la
/// hoja de paradas se lee de un vistazo y la nuestra no se leía.
///
/// **Es pública a propósito**, por el mismo motivo que [LineaDeDatosDeLaRuta]:
/// así se prueba suelta, con un `Pedido` armado a mano y sin base. Vivía dentro
/// del cajón de «Ver paradas», y probarla obligaba a abrir el cajón con su
/// `ProviderScope` y su Drift detrás — que dentro de un `testWidgets` **cuelga
/// la prueba en vez de fallarla** (`CLAUDE.md` §5). Por eso la raya muda de
/// «— desde partida» no la cazaba nada: nadie la miraba.
class TarjetaDeParada extends StatelessWidget {
  const TarjetaDeParada({
    required this.numero,
    required this.parada,
    required this.lineas,
    this.origenLat,
    this.origenLng,
    this.alQuitar,
    this.alUbicar,
    this.asa,
    super.key,
  });

  final int numero;
  final Pedido parada;

  /// «Ubicar la entrega» (issue 19 de Amado): el cajón donde se le pone a mano el
  /// punto de entrega a esta parada. `null` donde no se puede (parada entregada o
  /// ruta completada), y entonces no se enseña el botón.
  final VoidCallback? alUbicar;

  /// El asa para arrastrar la parada a otro sitio del orden (`ParadasOrdenables`),
  /// o `null` donde no se reordena.
  final Widget? asa;

  /// EL PUNTO DE PARTIDA DE LA RUTA, que es de la ruta y no de la parada.
  ///
  /// Entra por aquí porque sin él no se puede medir nada: la parada sabe dónde
  /// está el cliente (`endLat`/`endLng`) pero no de dónde salió el camión. Los
  /// dos juntos son lo que deja de depender de que alguien haya escrito
  /// `segment_km` en la base — ver `datos/formato_de_la_ruta.dart`.
  final double? origenLat;
  final double? origenLng;

  /// Lo que se baja en esta parada. Vacío mientras no han llegado; entonces no
  /// se escribe «nada que bajar», que sería mentira.
  final List<RenglonConPeso> lineas;
  final Future<void> Function()? alQuitar;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radios.xl),
      side: BorderSide(color: Colores.linea),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?asa,
          // El número de la parada, el mismo que lleva en el mapa.
          CircleAvatar(
            radius: 14,
            backgroundColor: Colores.enCurso,
            child: Text(
              '$numero',
              style: const TextStyle(
                color: Colores.blanco,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LA FACTURA MANDA, y su fecha (issue 17 de Amado, 16/10/2026): el cliente
                // trabaja todo por número de factura y la fecha dice el atraso. El
                // widget es el de las tarjetas del Tablero y de Pedidos.
                FacturaYCliente(
                  facturaNumero: parada.facturaNumero,
                  facturadaEl: parada.facturaAt,
                  cliente: parada.customerName,
                  claveDeLaFactura: ValueKey('parada-factura-${parada.id}'),
                ),
                const SizedBox(height: 2),
                Text(
                  parada.endAddress ?? parada.address,
                  style: TextStyle(color: Colores.gris, fontSize: 12),
                ),
                if (lineas.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // QUÉ SE BAJA, en renglones y con su cantidad. Va **antes**
                  // que el peso y los kilómetros a propósito: el peso es del
                  // que planifica, esto es del que descarga.
                  for (final l in lineas)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${cantidad(l.empaques)}×',
                            style: Tipos.mono(
                              tamano: 12,
                              peso: FontWeight.w700,
                              color: Colores.tinta,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l.renglon.description,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Insignia(kg(parada.weight), color: Colores.gris),
                    // LO QUE HAY DESDE LA PARTIDA, y no una raya muda.
                    //
                    // Esto era `'${km(parada.segmentKm)} desde partida'`, o sea
                    // que sólo sabía leer la columna de la base. Una ruta armada
                    // desde el Tablero en el aparato no la escribe, así que sus
                    // paradas salían **todas** con `—` (`RT-20260928-001`,
                    // 28/09/2026). El porqué entero, y por qué el rótulo ahora
                    // dice «en recta», están en `datos/formato_de_la_ruta.dart`.
                    Insignia(
                      rotuloDesdeLaPartida(
                        guardado: parada.segmentKm,
                        origenLat: origenLat,
                        origenLng: origenLng,
                        lat: parada.endLat,
                        lng: parada.endLng,
                      ),
                      color: Colores.gris,
                    ),
                    // EL NUMERO DE OPERACION DE LA FACTURA ES EL CONDUCE — Jose,
                    // 07/10/2026 (incidencia 6 de Amado). No hay dato nuevo: es
                    // `operation_number`, y se rotula como lo llama quien reparte.
                    //
                    // Sin número no se escribe la etiqueta: «Conduce: » vacío
                    // parece un dato que falta y es uno que no existe. Un texto
                    // vacío cuenta igual que un nulo.
                    if ((parada.operationNumber ?? '').trim().isNotEmpty)
                      Insignia(
                        'Conduce: ${parada.operationNumber!}',
                        color: Colores.enCurso,
                      ),
                  ],
                ),
                // EL PUNTO PUESTO A MANO, a la vista: esta parada NO está donde dice la
                // geolocalización del cliente (issue 19 de Amado).
                if (parada.puntoManual) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Insignia(
                      'Punto puesto a mano',
                      key: ValueKey('parada-punto-manual-${parada.id}'),
                      color: Colores.ambar,
                      tooltip: (parada.puntoManualPor ?? '').isEmpty
                          ? null
                          : 'Lo puso ${parada.puntoManualPor}',
                    ),
                  ),
                ],
                if (alUbicar != null || alQuitar != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        if (alUbicar != null)
                          TextButton.icon(
                            key: ValueKey('parada-ubicar-${parada.id}'),
                            onPressed: alUbicar,
                            icon: const Icon(Icons.edit_location_alt_outlined),
                            label: const Text('Ubicar la entrega'),
                          ),
                        if (alQuitar != null)
                          TextButton.icon(
                            onPressed: alQuitar,
                            icon: const Icon(Icons.remove_circle_outline),
                            label: const Text('Quitar de ruta'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // EL IMPORTE, EN GRANDE Y A LA DERECHA. Es el dato que se viene a
          // buscar aquí, y alineado a la derecha los de todas las paradas caen
          // en la misma columna: así se recorren con el ojo sin leer.
          Text(
            usd(costoDeLaParada(parada.pedidoCosto, parada.facturaDomicilio)),
            style: Tipos.mono(
              tamano: 15,
              peso: FontWeight.w700,
              color: Colores.primario,
            ),
          ),
        ],
      ),
    ),
  );
}
