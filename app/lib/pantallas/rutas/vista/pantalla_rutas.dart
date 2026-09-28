// La pantalla de Rutas. Es tres pantallas en una: lista y detalle, asistente de
// 4 pasos y cierre parada por parada.
//
// **Aqui vive el dia sin conexion.** Todo lo de esta pantalla —ver, filtrar,
// armar, iniciar, completar, eliminar y cerrar— funciona sin red: se escribe en
// la base local, se pinta como hecho y la cola sube por detras. Lo unico que no
// se puede hacer sin conexion es abrir el enlace de Google Maps, y los rechazos
// del servidor llegan tarde, al subir, y salen en la bandeja con su hora y su
// motivo. Nunca se descartan.
//
// ## PENDIENTE: los filtros de esta pantalla NO van en la dirección
//
// El contrato de `navegacion/pantalla_registrada.dart` dice que van:
//
// > **Los filtros van en la URL** (`estado.uri.queryParameters`) […] Lee de ahí
// > y escribe con `context.go(...)`; no guardes el filtro sólo en un `State`.
//
// `pantallas/rutas/registro.dart` tira el `GoRouterState` entero
// —`_construir` devuelve `const PantallaRutas()`— y la pestaña, el buscador, el
// vehículo y el rango de fechas viven sólo aquí dentro. En la web eso son dos
// cosas que se ven:
//
//  * mandar `/routes` a alguien no le lleva a lo que uno está mirando —ni
//    siquiera a la misma pestaña—, y
//  * **recargar borra los filtros sin decir nada**, que es el caso que el
//    encargo del 24/09/2026 manda probar («entrar por la URL de cada pantalla y
//    recargar estando dentro»).
//
// Hecho ya para Pedidos, y ahí está el molde entero, con el aviso de lo que un
// enlace trae y no se puede aplicar: `pantallas/pedidos/datos/filtros_en_la_url.dart`
// y su prueba `test/pantallas/pedidos/filtros_en_la_url_test.dart`.
//
// **Lo que cuesta traerlo aquí:** un fichero `datos/filtros_en_la_url.dart`
// propio (los filtros de Rutas son 5, no 11), una línea en `registro.dart`,
// pasar este widget a `ConsumerStatefulWidget` con su `initState` y su empuje
// de la dirección, y el par de pruebas. Medio día, del que la mitad es la
// pestaña: `Pestanas` guarda la suya en su propio estado y hay que dejarla
// leer de fuera sin perder el deslizamiento.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/barra_de_filtros.dart';
import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/pestanas.dart';
import '../../../diseno/rango_de_fechas.dart';
import '../../../diseno/tema.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../pedidos/vista/kit.dart';
import '../datos/repositorio_rutas.dart';
import '../estado/proveedores_rutas.dart';
import 'asistente_nueva_ruta.dart';
import 'detalle_ruta.dart';
import 'lista_rutas.dart';

class PantallaRutas extends ConsumerWidget {
  const PantallaRutas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pestana = ref.watch(pestanaRutasProvider);
    final contadores = ref.watch(contadoresDePestanaProvider);
    final elegida = ref.watch(rutaElegidaProvider);
    // Los filtros NO se miran aqui: el `Limpiar` que los necesitaba se fue
    // dentro de `_FiltrosDeLaLista`, y vigilarlos desde aqui repintaria la
    // pantalla entera —las tres listas del `PageView` incluidas— cada vez que
    // alguien escribe una letra en el buscador.

    // CAMBIAR DE PESTAÑA A MANO SUELTA LA RUTA ABIERTA.
    //
    // Medido el 22/09/2026 en un monitor: con `RT-…-002` abierta en el panel de
    // la derecha, pulsar `Historial` cambiaba la lista y **dejaba el panel
    // enseñando esa misma ruta**, que ya no estaba en la lista de al lado, con
    // su botón `Iniciar ruta` vivo. O sea, media pantalla hablando de una cosa y
    // la otra media de otra.
    //
    // El panel de la derecha es el detalle de algo de ESTA lista: si se cambia
    // de lista, no hay nada abierto.
    void irALaPestana(int i) {
      ref.read(pestanaRutasProvider.notifier).elegir(PestanaRutas.values[i]);
      ref.read(rutaElegidaProvider.notifier).elegir(null);
    }

    // Y LO MISMO DESLIZANDO, PERO SÓLO SI DE VERDAD LO MUEVE UNA PERSONA.
    //
    // El `PageView` avisa también cuando termina la animación de un cambio que
    // vino del código, y hay uno que NO puede soltar la ruta: `Iniciar ruta`
    // mueve la pestaña a `En curso` **y se lleva la ruta consigo** a propósito
    // (`detalle_ruta.dart`), para que no le desaparezca de delante a quien
    // acaba de arrancarla. En ese aviso el índice que llega ya es el que hay
    // puesto; en un deslizamiento de verdad, todavía no.
    void alDeslizar(int i) {
      if (PestanaRutas.values[i] == ref.read(pestanaRutasProvider)) return;
      irALaPestana(i);
    }

    // SIN `Scaffold` ni `AppBar` propios: los pone el armazon
    // (`navegacion/pantalla_registrada.dart`), que ya trae barra lateral, barra
    // superior con el titulo «Rutas» y franja de estado. Uno dentro de otro
    // apila dos superficies de Material y deja los avisos emergentes —los
    // rechazos del armado y el `Cierre guardado.`— colgando del de dentro.

    // EL BOTON DE ATRAS DEL SISTEMA TAMBIEN SUELTA LA RUTA.
    //
    // En un telefono ese es el primer gesto que hace la gente para salir de
    // algo, y aqui no servia: la ruta elegida es estado de un provider, no una
    // pagina del enrutador, asi que atras no la tocaba — se salia de Rutas
    // entera y al volver seguia elegida.
    //
    // `canPop: false` mientras haya una elegida: el primer atras la suelta y se
    // queda en Rutas; el segundo ya sale, como siempre.
    //
    // Desde el 22/09/2026 esto es la red de abajo, no la primera parada: en el
    // teléfono el detalle va en un cajón, que es una ruta del `Navigator` y se
    // come el «atrás» él mismo (y al cerrarse suelta la ruta). Esto sigue
    // sirviendo en escritorio, donde no hay cajón sino panel de al lado.
    return PopScope(
      canPop: elegida == null,
      onPopInvokedWithResult: (seFue, _) {
        if (seFue) return;
        ref.read(rutaElegidaProvider.notifier).elegir(null);
      },
      child: SafeArea(
        // LO QUE MANDA SOBRE LA LISTA VA CON LA LISTA — 28/09/2026.
        //
        // Jose, mirando `/routes` en un monitor ancho:
        //
        //     «aqui por q el boton se queda a la mitad el de crear una nueva
        //      ruta y el en curso osea el del estado por q se queda tmabien a
        //      mitad arregla eso»
        //
        // Lo que estaba: el titulo, el reloj, el boton `+ Nueva Ruta`, las tres
        // pastillas de estado y la barra de filtros colgaban de una columna a
        // TODO EL ANCHO, y debajo de ellos la pantalla se partia en dos paneles
        // —la lista a la izquierda, ~530 px, y el detalle a la derecha—. O sea
        // que los cinco mandos de la lista vivian encima de los dos paneles:
        //
        //  * el `+ Nueva Ruta`, empujado al extremo derecho por su `Spacer`,
        //    acababa flotando a mil pixeles de la lista que crea, en mitad del
        //    panel del detalle, que no tiene nada que ver con el;
        //  * y las pastillas y el rotulo se quedaban colgando a media fila, con
        //    el resto del renglon vacio hasta el otro borde. Eso es el «se queda
        //    a mitad» de las dos frases.
        //
        // Ahora los mandos de la lista son PARTE del panel de la lista: nacen y
        // mueren dentro de sus ~530 px, y el panel del detalle no lleva encima
        // nada que no sea del detalle. Es la forma de siempre de un maestro-
        // detalle: cada panel con su propia cabecera.
        //
        // **A ancho de telefono no cambia nada**, y eso es la mitad del valor de
        // hacerlo asi: por debajo de `anchoEscritorio` no hay dos paneles, asi
        // que este mismo panel ES la pantalla entera y queda exactamente como
        // estaba —cabecera, pestañas, filtros y lista, uno debajo de otro—. Un
        // solo arbol para las dos formas; no hay una colocacion de escritorio y
        // otra de movil que alguien arregle a medias.
        //
        // LO QUE SE PAGA, escrito para que no sorprenda: `PestanasQueCaben`
        // decide por su ancho, y su umbral (`anchoDeLasPestanas`, 900 px) esta
        // fijo dentro de `lib/diseno/pestanas.dart`. En una columna de ~530 px
        // las tres pastillas se cambian por el carrusel —el rotulo de la que se
        // mira, tres bolitas con el nombre y la cuenta de cada una en su
        // globito, y las flechas—, que es el mismo control que Jose pidio para
        // el telefono. Las tres etiquetas de esta pantalla miden ~420 px
        // juntas, o sea que CABRIAN en la columna: si algun dia ese umbral se
        // puede pasar por parametro, aqui se le pasa y vuelven las pastillas.
        child: LayoutBuilder(
          builder: (contexto, medidas) {
            // Se mide con `medidas.maxWidth`, que es el ancho que de verdad le
            // queda a la pantalla dentro del armazon, y no con el de la
            // ventana: con la barra lateral fija puesta, los dos numeros no son
            // el mismo y quien decide la forma tiene que ser el mismo que decide
            // si hay sitio para dos columnas.
            final enEscritorio = medidas.maxWidth >= anchoEscritorio;

            // EL PANEL DE LA LISTA: su cabecera, sus pestañas, sus filtros y
            // ella. En movil es la pantalla entera; en escritorio es la columna
            // de la izquierda. El mismo arbol en los dos sitios.
            final panelDeLaLista = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _CabeceraDeLaLista(),
                // LAS TRES PESTANAS, SEGUN EL SITIO QUE HAYA: carrusel cuando
                // la columna es estrecha, las tres a la vez cuando cabe (ver
                // `PestanasQueCaben`).
                //
                // Antes eran tres botones sueltos dentro del `Wrap` del titulo,
                // y en un telefono las tres etiquetas con sus cuentas no caben
                // en una linea. Ahora sale el rotulo de la que se esta mirando
                // y, debajo, tres bolitas. Se cambia deslizando la lista, con
                // las bolitas o con las flechas.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Aire.sm),
                  child: PestanasQueCaben(
                    indice: pestana.index,
                    etiquetas: [
                      for (final cual in PestanaRutas.values)
                        '${cual.etiqueta} (${contadores[cual] ?? 0})',
                    ],
                    // AQUÍ CABEN CON MENOS DE 900 — 28/09/2026.
                    //
                    // Los mandos de esta pantalla viven dentro del panel de la
                    // lista, que en un monitor mide unos 530 px. Las tres
                    // —`Planificadas (0) · En curso (1) · Historial (0)`— miden
                    // unas 420 juntas, así que con el umbral común salían en
                    // carrusel teniendo sitio de sobra: dos de tres escondidas
                    // detrás de unas bolitas para nada.
                    //
                    // NO ES EL ANCHO, ES SI HAY DOS PANELES — 28/09/2026.
                    //
                    // Esto empezó siendo un número y se probaron dos, 460 y
                    // 400, y los dos estaban mal por el mismo motivo: el panel
                    // de la lista en un monitor (~433 px, porque la barra
                    // lateral se lleva 255) y la pantalla de un teléfono grande
                    // (~404 px a 420) **miden casi lo mismo**, así que ningún
                    // umbral de ancho separa los dos casos sin acertar por los
                    // pelos. Con 460 seguía saliendo el carrusel en el monitor;
                    // con 400 salían las pastillas en un teléfono de 420.
                    //
                    // Y no hacía falta adivinarlo: quien construye esto YA SABE
                    // si está en escritorio, que es lo mismo que decide si hay
                    // dos columnas. En escritorio caben las tres —y si un día
                    // no caben, el `Wrap` las baja de renglón, que sigue siendo
                    // mejor que esconder dos detrás de unas bolitas—; en un
                    // teléfono el carrusel es lo correcto y se queda con el
                    // umbral común de `PestanasQueCaben`.
                    anchoParaTodas: enEscritorio ? 0 : null,
                    alCambiar: irALaPestana,
                  ),
                ),
                const _FiltrosDeLaLista(),
                Expanded(
                  // LA LISTA, QUE SE CAMBIA DESLIZANDO EL DEDO.
                  //
                  // Las tres pestanas son tres listas del mismo tamano puestas
                  // en fila; deslizar a lo ancho pasa de una a la siguiente y el
                  // botoncito de arriba se enciende solo. El desplazamiento de
                  // cada lista es vertical, asi que los dos gestos no se pisan.
                  child: CuerpoDeslizable(
                    indice: pestana.index,
                    cuantas: PestanaRutas.values.length,
                    alCambiar: alDeslizar,
                    pagina: (contexto, i) =>
                        ListaDeRutas(deLaPestana: PestanaRutas.values[i]),
                  ),
                ),
              ],
            );

            // EN MÓVIL, EL DETALLE VA EN UN CAJÓN Y NO AQUÍ DENTRO.
            //
            // Jose, 22/09/2026: «cuando estoy viendo un detalle de una ruta me
            // puedo mover por los diferentes tabs eso no lo quiero ponlo en un
            // drawer en el movil». El porqué entero está en
            // `CajonDelDetalleDeRuta`; lo que hay que saber aquí es que **este
            // panel sigue siendo la lista y nada más**, pase lo que pase con la
            // ruta elegida.
            if (!enEscritorio) {
              return _LaListaConSuCajon(lista: panelDeLaLista);
            }

            // En escritorio: 3 columnas (1 lista + 2 detalle), cada una con su
            // propio desplazamiento.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: panelDeLaLista),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: elegida == null
                      ? const EstadoVacio(
                          'Selecciona una ruta para ver el detalle',
                        )
                      : DetalleDeRuta(rutaId: elegida),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// LA CABECERA DEL PANEL DE LA LISTA: el título con su reloj, y el botón de
/// crear.
///
/// Antes los tres —título, reloj y botón— colgaban del mismo `Wrap`, así que el
/// botón salía pegado al título en escritorio y, en un teléfono, caído en una
/// esquina con el ancho de su texto. Jose, 25/09/2026: «el botón para crear ruta
/// sale al lado en vez de al otro lado, y en móvil en una esquina y no todo el
/// tamaño que lleva, le falta width».
///
/// **Mide su propio ancho y no el de la ventana** — 28/09/2026, y es lo que hace
/// que esto siga valiendo dentro del panel de ~530 px. Con `MediaQuery` esta
/// cabecera se creía en un monitor de 1600 px estando en una columna de 530, y
/// entonces montaba la fila «título ··· botón a la derecha» en un sitio donde el
/// `Spacer` no tiene nada que dar: el botón se pegaba al título otra vez, que es
/// literalmente la queja del 25/09 de vuelta.
///
/// Por debajo de [Anchos.idioma] de columna el botón baja a su propia línea y
/// ocupa TODO el ancho del panel, que es lo que lo hace fácil de acertar con el
/// pulgar en un teléfono y lo que lo deja pegado a la lista que crea en un
/// monitor. Por encima, se va al extremo derecho DEL PANEL, que es donde se
/// busca la acción y que ahora es un borde de verdad y no el otro lado de la
/// pantalla.
class _CabeceraDeLaLista extends StatelessWidget {
  const _CabeceraDeLaLista();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Aire.lg),
    child: LayoutBuilder(
      builder: (contexto, medidas) {
        final estrecho = medidas.maxWidth < Anchos.idioma;

        const titulo = Text(
          'Planificador de Rutas',
          style: TextStyle(fontWeight: FontWeight.bold),
        );
        // El reloj de datos de las colecciones de esta pantalla. La franja del
        // armazon da la frescura global; esta da la de lo que se esta mirando.
        const reloj = BarraDeDatos(colecciones: ColeccionesDePantalla.rutas);
        final boton = FilledButton(
          onPressed: () =>
              abrirCajon<void>(context, (_) => const AsistenteNuevaRuta()),
          child: const Text('+ Nueva Ruta'),
        );

        if (estrecho) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [titulo, reloj],
              ),
              const SizedBox(height: Aire.md),
              // `stretch` de la columna: el botón a todo lo ancho.
              boton,
            ],
          );
        }

        // `Expanded` PARA EL TÍTULO Y NADA DE `Spacer` — 28/09/2026.
        //
        // Era `Flexible(titulo+reloj)` + `Spacer()` + botón, y los dos flexibles
        // se repartían el hueco libre **a la mitad cada uno**. Eso aquí es un
        // desbordamiento de verdad: el reloj de datos es un
        // `Row(mainAxisSize: min)` sin ningún hijo flexible dentro
        // (`nucleo/frescura/reloj_de_datos.dart`), así que no encoge — si su
        // mitad no le llega, se sale por el lado y sale la cebra amarilla y
        // negra encima del título.
        //
        // Medido: a 700 px de cabecera le tocaban 219,4 px y pedía 260,4. **Ya
        // pasaba antes de mover nada** —a esos anchos no había ninguna prueba
        // que montara esta pantalla—, y al meter la cabecera dentro del panel
        // de la lista habría vuelto a pasar en un monitor de 2560, donde la
        // columna pasa de 640 px y esta rama se vuelve a usar.
        //
        // Con `Expanded` y sin `Spacer` el hueco libre es entero para el título
        // y su reloj —que es quien no sabe encoger—, y el botón se queda
        // igualmente pegado al borde derecho porque el `Expanded` lo empuja
        // hasta allí. A 700 px pasa de 219,4 a 439.
        return Row(
          children: [
            const Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [titulo, reloj],
              ),
            ),
            const SizedBox(width: Aire.md),
            boton,
          ],
        );
      },
    ),
  );
}

/// LA LISTA DEL MÓVIL, QUE ABRE EL DETALLE EN UN CAJÓN.
///
/// Lo único que pinta es la lista; lo que hace es **vigilar la ruta elegida** y
/// abrir [CajonDelDetalleDeRuta] en cuanto haya una.
///
/// Va atado a `rutaElegidaProvider` y no al gesto de tocar una tarjeta porque
/// tocar una tarjeta no es el único sitio que elige ruta: el asistente elige la
/// que acaba de armar (`asistente_nueva_ruta.dart`), y ésa también tiene que
/// abrirse en el teléfono. Una sola puerta, no dos.
///
/// **Después del fotograma, nunca dentro.** Dos motivos y los dos hacen daño:
/// meter una ruta en el `Navigator` en plena construcción del árbol es el
/// «markNeedsBuild called during build» de siempre, y además el asistente hace
/// `elegir(rutaId)` y a renglón seguido `maybePop()` para cerrarse él — si el
/// cajón del detalle se abriera en medio, ese `maybePop` cerraría el detalle
/// recién abierto en vez del asistente.
class _LaListaConSuCajon extends ConsumerStatefulWidget {
  const _LaListaConSuCajon({required this.lista});

  final Widget lista;

  @override
  ConsumerState<_LaListaConSuCajon> createState() => _LaListaConSuCajonState();
}

class _LaListaConSuCajonState extends ConsumerState<_LaListaConSuCajon> {
  /// Para no abrir dos cajones encima del mismo detalle. Pasa de verdad: cuando
  /// una ruta provisional sube, su id cambia con el cajón ya abierto
  /// (`RutaElegida`), y eso es otro aviso más del provider.
  bool _abierto = false;

  @override
  void initState() {
    super.initState();
    // `ref.listen` sólo cuenta los cambios de aquí en adelante, así que una ruta
    // que YA venía elegida —se encogió la ventana, o se llega desde el
    // asistente— no abriría nada.
    if (ref.read(rutaElegidaProvider) != null) _abrirElCajon();
  }

  void _abrirElCajon() {
    if (_abierto) return;
    _abierto = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Entre el aviso y el fotograma puede haberse soltado la ruta: un cajón
      // vacío es peor que ninguno.
      if (!mounted || ref.read(rutaElegidaProvider) == null) {
        _abierto = false;
        return;
      }
      unawaited(
        abrirCajon<void>(context, (_) => const CajonDelDetalleDeRuta()).then((
          _,
        ) {
          _abierto = false;
          // CERRAR EL CAJÓN ES SOLTAR LA RUTA. Da igual por dónde se haya
          // cerrado —la ✕, el velo, el botón de atrás del teléfono—: si no se
          // soltara, la tarjeta se quedaría marcada en la lista y volver a
          // tocarla no abriría nada, porque el provider no cambiaría de valor.
          if (mounted) ref.read(rutaElegidaProvider.notifier).elegir(null);
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(rutaElegidaProvider, (_, ahora) {
      if (ahora != null) _abrirElCajon();
    });
    return widget.lista;
  }
}

/// LOS RÓTULOS DEL FILTRO DE LA UBICACIÓN, en un sitio y públicos.
///
/// Están aquí y no dentro de `_FiltrosDeLaLista` —que es privada— porque las
/// pruebas tienen que buscar **lo que se lee en pantalla**, y una prueba que
/// copia el literal no comprueba el literal: el día que alguien cambie el texto,
/// la prueba seguirá verde buscando el viejo. Es la misma decisión que
/// `Selector.nadaQueCuadre` y `SinDescargar.textoDeLaPantallaVacia`.
abstract final class TextosDeLosFiltrosDeRutas {
  /// La opción «todas», que va **la primera** de la lista.
  static const cualquierUbicacion = 'Cualquier ubicación';

  /// El título del filtro. Es **también su clave** en `BarraDeFiltros`, que
  /// reparte la fila del teléfono por lo que mide el rótulo de cada filtro; ver
  /// la nota de las claves más abajo.
  static const tituloUbicacion = 'Ubicación de salida';
}

class _FiltrosDeLaLista extends ConsumerWidget {
  const _FiltrosDeLaLista();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtros = ref.watch(filtrosRutasProvider);
    final notas = ref.read(filtrosRutasProvider.notifier);
    final vehiculos = ref.watch(vehiculosProvider).value ?? const <Vehiculo>[];
    final ubicaciones = ref.watch(ubicacionesDeSalidaProvider);

    // La colocación la manda `BarraDeFiltros`, igual que Pedidos, Clientes y
    // Vehículos. Antes: `Padding` de 12 literal —el título de esta misma
    // pantalla usa 16, las pestañas 8 y el botón «Limpiar» cero— y un `Wrap`
    // donde la caja de buscar se llevaba 260 de los 366 útiles del teléfono y
    // tiraba el selector de vehículo a la línea siguiente.
    // Ver `lib/diseno/barra_de_filtros.dart`.
    //
    // EL MARGEN SE MIDE CON EL ANCHO DE ESTE PANEL, no con el de la ventana
    // —28/09/2026, y es la misma razón que en `_CabeceraDeLaLista`—. El que trae
    // `BarraDeFiltros` por defecto sale de `MediaQuery`, así que dentro de la
    // columna de ~530 px de un monitor se ponía el de pantalla grande
    // (`Aire.xl` a cada lado) y se comía 48 px de los 530 que hay. Se le pasa
    // el mismo cálculo medido donde toca; en un teléfono da exactamente lo de
    // siempre, porque allí el panel ES la ventana.
    return LayoutBuilder(
      builder: (contexto, medidas) => BarraDeFiltros(
        margen: EdgeInsets.symmetric(
          horizontal: medidas.maxWidth < Anchos.idioma ? Aire.md : Aire.xl,
          vertical: Aire.md,
        ),
        // Igual que la de Pedidos: busca sola y **se vacia cuando
        // `Limpiar` vacia los filtros**, en vez de quedarse un texto
        // filtrando en silencio.
        busqueda: CajaDeBusqueda(
          valor: filtros.q,
          ancho: 260,
          pista: 'Buscar por código, nombre, vehículo...',
          alBuscar: (t) => notas.poner(filtros.copiarCon(q: t)),
        ),
        // CADA FILTRO LLEVA SU CLAVE, Y ES LO QUE LE DA SU ANCHO.
        //
        // `BarraDeFiltros` reparte la fila del teléfono **a lo que mide cada
        // uno**, y lo único que esa capa sabe de un filtro es su clave: no
        // conoce `Selector` ni tiene por qué. Sin clave, `_peso` no encuentra
        // rótulo y devuelve el valor de en medio, o sea el 50/50 de antes.
        //
        // El de vehículo **no la llevaba** —se le puso hoy, 28/09/2026, al
        // añadir el de la ubicación—: con uno de los dos sin clave el reparto
        // de la fila era mentira en la mitad de los casos y nadie lo veía,
        // porque dos pesos iguales y dos pesos «por defecto» dan la misma fila.
        //
        // El texto es el `titulo` y no la opción elegida a propósito: la opción
        // cambia al elegir, y una clave que cambia le tira el estado al widget.
        filtros: [
          Selector<String>(
            key: const ValueKey('Rutas de un camión'),
            titulo: 'Rutas de un camión',
            valor: filtros.vehiculoId,
            opciones: [
              const OpcionSelector('', 'Cualquier vehículo'),
              for (final v in vehiculos)
                OpcionSelector(
                  v.id,
                  v.name,
                  nota: v.status == EstadoVehiculo.enUso ? 'en ruta' : null,
                ),
            ],
            alElegir: (id) => notas.poner(filtros.copiarCon(vehiculoId: id)),
          ),
          // DE DÓNDE SALIÓ — 28/09/2026.
          //
          // Jose: «en las rutas añadir tambien el filtro por la ubicacion q
          // salio para saber de donde saiioo sin necesidad de estar viendo
          // todas juntas». El dato ya estaba en la tarjeta —el renglón del
          // alfiler, `PV-STGO`— y no había forma de acotar por él.
          //
          // Las opciones salen de las RUTAS del alcance
          // (`ubicacionesDeSalidaProvider`), no del catálogo de almacenes. El
          // porqué entero está en `FiltrosRutas.ubicacionSalida`; lo que hay
          // que saber aquí es que cada opción tiene al menos una ruta detrás y
          // que dice cuántas, que es lo que contesta «de dónde salieron» sin
          // tener que elegir para averiguarlo.
          //
          // SE ENSEÑA SIEMPRE, TAMBIÉN CON UN SOLO ALMACÉN, y eso es una
          // decisión:
          //
          //  * un filtro que aparece y desaparece según lo que haya bajado es
          //    un filtro que nadie encuentra. En la web la base nace vacía en
          //    cada carga (§3-ter), así que el primer segundo no habría filtro
          //    y el siguiente sí: el parpadeo se lee como «esta pantalla está
          //    rota», y quien lo vio una vez vacío no vuelve a buscarlo;
          //  * y esconderlo cuando la sucursal tiene un solo almacén dice lo
          //    contrario de lo que pasa: que esta pantalla no sabe filtrar por
          //    ahí. Jose ya lo pidió al revés con los almacenes — que se vea
          //    que existen aunque no estén configurados, no que desaparezcan
          //    en silencio. Con un solo origen el desplegable además NOMBRA
          //    cuál es, que es un dato y no ruido.
          //
          // La opción «cualquiera» va **la primera**, como en todos los
          // desplegables de la casa, y sale de esta lista y no de dentro del
          // `Selector`, así que ningún reordenado de las ubicaciones se la
          // puede llevar por delante.
          Selector<String>(
            key: const ValueKey(TextosDeLosFiltrosDeRutas.tituloUbicacion),
            titulo: TextosDeLosFiltrosDeRutas.tituloUbicacion,
            valor: filtros.ubicacionSalida,
            opciones: [
              const OpcionSelector(
                '',
                TextosDeLosFiltrosDeRutas.cualquierUbicacion,
              ),
              for (final u in ubicaciones)
                OpcionSelector(u.clave, u.etiqueta, nota: '${u.rutas}'),
            ],
            alElegir: (v) =>
                notas.poner(filtros.copiarCon(ubicacionSalida: v)),
          ),
        ],
        // Fila entera: son dos botones de fecha más la ✕, y en media columna se
        // parten dejando la ✕ colgando sola.
        //
        // Las dos fechas sobre `createdAt`. El filtro ya se aplicaba en
        // `filtrarRutas`; lo que faltaba era con que ponerlo. Sin `sólo ese
        // día`: eso es de Pedidos (pliego §2), aqui el pliego (§3) sólo pide
        // `Desde` y `Hasta`.
        anchoCompleto: [
          RangoDeFechas(
            desde: filtros.desde,
            hasta: filtros.hasta,
            conSoloEseDia: false,
            // El reloj de la aplicacion, no el del sistema: el calendario se
            // abre por el mismo «hoy» que usa todo lo demas.
            hoy: ref.watch(relojProvider)(),
            // `limpiar…` cuando llega `null`: la ✕ del rango quita las dos
            // fechas, y sin esos dos avisos `copiarCon` leería el `null` como
            // «no lo toques» y la ✕ no haría nada.
            alCambiar: (desde, hasta) => notas.poner(
              filtros.copiarCon(
                desde: desde,
                limpiarDesde: desde == null,
                hasta: hasta,
                limpiarHasta: hasta == null,
              ),
            ),
          ),
        ],
        // `LIMPIAR` VA DENTRO DE LA BARRA, en el hueco que `BarraDeFiltros`
        // tiene para eso — 28/09/2026. Estaba suelto debajo, en un `Align` con
        // margen cero mientras la barra de encima llevaba el suyo, así que no
        // quedaba alineado con ningún filtro. Es justo lo que esa barra existe
        // para evitar: cada pantalla colocando lo suyo a su manera.
        accionFinal: filtros.hayAlguno
            ? TextButton.icon(
                onPressed: () =>
                    ref.read(filtrosRutasProvider.notifier).limpiar(),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Limpiar'),
              )
            : null,
      ),
    );
  }
}
