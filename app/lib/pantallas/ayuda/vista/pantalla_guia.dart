/// LA GUIA. El manual del reparto, DENTRO de la aplicacion.
///
/// ## Lo que vino a arreglar
///
/// El manual estaba escrito —6.669 lineas en `docs/manual/`— y no se podia leer
/// desde ningun sitio: vivia en el repositorio, y el logistico de Santiago, que
/// empieza a usar esto la semana que viene, no tiene el repositorio. Jose:
///
/// > «no hay navegacion en el side bar para ver el manual … necesito una guia
/// > paso a paso para q la gente sepa utilizar la aplicacion»
///
/// ## Las dos puertas, y por que son dos
///
/// > «estas tareas me las agregas a el side bar para q puedan ir cuando quieran,
/// > ponlo como guía, y pon las dos: el documento oficial y las tareas y sus
/// > pasos»
///
///  * **Tareas** — el catalogo de «¿como hago X?», con sus pasos numerados, sus
///    notas y su boton de «llévame ahí». Es la puerta del dia a dia y por eso es
///    la que sale al abrir: alguien con el telefono en la mano y una duda
///    concreta, noventa y nueve de cada cien veces.
///  * **Documento** — las paginas enteras, para leer de principio a fin. Es la
///    puerta del primer dia y la que se imprime.
///
/// **No son dos copias de nada**: una tarea es el trozo de una pagina que va
/// desde su `##` hasta el siguiente, sacado de la misma cadena de texto en
/// `datos/manual.dart`. No hay dos textos que mantener, asi que no hay dos textos
/// que puedan separarse. Lo ata
/// `test/pantallas/ayuda/las_tareas_salen_de_la_pagina_test.dart`.
///
/// El buscador **mira en las dos y dice de cual viene cada resultado**, porque
/// buscar «almacén» tiene que encontrar la tarea de poner el almacen Y la ficha de
/// la pantalla de Almacenes.
///
/// ## Un selector de dos y no el carrusel de la casa
///
/// `diseno/pestanas.dart` ensena **solo la pestaña en la que estas** y unas
/// bolitas para decir que hay mas — esta hecho para las doce zonas del Tablero. Con
/// dos puertas eso esconderia el documento detras de una bolita, y el encargo dice
/// lo contrario: «el documento completo está a un toque, no escondido en un
/// submenú de un submenú». Asi que las dos se ven siempre, con el tratamiento de
/// «donde estoy» que ya usa la barra lateral: color, borde y el icono. **Sin
/// fondo relleno** (§4).
///
/// ## Sin senal, y eso lo decide todo
///
/// El contenido viaja en el propio paquete de la aplicacion
/// (`assets/manual/manual.txt`) y se lee con `rootBundle`. No se baja, no se pide
/// a la red y no se abre ningun navegador: quien mas necesita la guia es el
/// logistico en el patio de un almacen sin cobertura.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/cajon.dart';
import '../../../diseno/cargando.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/tema.dart';
import '../datos/enlaces.dart';
import '../datos/manual.dart';
import '../datos/proveedores.dart';
import 'pintar_markdown.dart';

/// Los literales de la Guia, en un solo sitio: los usan la pantalla, su registro
/// y sus pruebas.
abstract final class TextosDeLaGuia {
  /// **«Guía»**, y es el literal que eligio Jose. No «Ayuda» ni «Manual».
  static const titulo = 'Guía';

  static const tareas = 'Tareas';
  static const documento = 'Documento';
  static const pista = 'Buscar en la guía';

  /// Lo que se dice cuando el manual no se puede leer. **Dice el por que**, que
  /// es la regla: sin conexion no se miente, y «no se pudo cargar» no le dice
  /// nada a nadie.
  static const noSePudoLeer =
      'La guía no se pudo leer de dentro de la aplicación. No es la señal: el '
      'manual viaja horneado en la propia aplicación y no se baja de ningún '
      'sitio, así que esto es un fallo de la versión instalada. Avisa a la '
      'oficina con la versión que tienes.';

  static String sinResultados(String buscado) =>
      'Nada en la guía cuadra con «$buscado». Prueba con una palabra sola: '
      '«camión», «ruta», «almacén».';

  /// Cuando el manual declara una pantalla que en esta forma no existe.
  static String noHayEsaPantalla(String nombre, FormaDeLaAplicacion forma) =>
      '«$nombre» no existe en ${forma.comoSeLlama}, así que desde aquí no se '
      'puede ir. Los pasos se quedan por si te toca hacerlo en otra de las tres '
      'formas.';
}

/// Las claves de los mandos. Publicas porque las pruebas tienen que poder
/// pulsarlos, y buscarlos por su texto ataria la prueba al rotulo.
abstract final class ClavesDeLaGuia {
  static const tareas = ValueKey('guia-tareas');
  static const documento = ValueKey('guia-documento');
  static const buscar = ValueKey('guia-buscar');
  static const llevameAhi = ValueKey('guia-llevame-ahi');

  static ValueKey<String> tarea(String id) => ValueKey('guia-tarea-$id');
  static ValueKey<String> pagina(String camino) =>
      ValueKey('guia-pagina-$camino');
}

class PantallaGuia extends ConsumerStatefulWidget {
  const PantallaGuia({super.key});

  /// El camino, en UN solo sitio. **`/guia` y no `/ayuda`**: es el literal del
  /// menu, y una direccion que no se parece a su entrada es una direccion que
  /// nadie adivina.
  ///
  /// No empieza por `/api` ni por `/sync`, que es lo que vigila
  /// `test/navegacion/contrato_registro_test.dart` desde el §3-quater.
  static const ruta = '/guia';

  /// Lo que viaja en la direccion. Los filtros van en la URL (el contrato de
  /// `pantalla_registrada.dart`), y aqui sirve para algo mas: al pulsar «llévame
  /// ahí» y volver con el atras, **la guia se abre donde estaba**.
  static const deLaBusqueda = 'buscar';
  static const deLaTarea = 'tarea';
  static const deLaPagina = 'pagina';
  static const deLaPuerta = 'ver';

  @override
  ConsumerState<PantallaGuia> createState() => _PantallaGuiaState();
}

class _PantallaGuiaState extends ConsumerState<PantallaGuia> {
  /// Lo que hay abierto en un cajon AHORA MISMO, con la misma forma que la
  /// direccion: `tarea:<id>`, `pagina:<camino>` o `null`.
  String? _enElCajon;

  /// NOS VAMOS DE LA GUIA, y esto no es un adorno: es lo que impide que «llévame
  /// ahí» se deshaga a si mismo.
  ///
  /// Al pulsarlo pasan dos cosas a la vez: el camino cambia a `/vehicles` y el
  /// cajon se cierra solo (`AtrasDelCajon`, 28/09/2026). El cierre despierta al
  /// `await` de [_abrirElCajon], que hasta ahora miraba la direccion para decidir
  /// si quitar el `?tarea=` — y **la direccion todavia decia `/guia`**, porque
  /// go_router la resuelve un microtick despues. Resultado: la guia se escribia
  /// encima de la navegacion y «llévame ahí» no llevaba a ningun sitio. Medido el
  /// 05/10/2026: tras pulsar, la direccion era `/guia`.
  ///
  /// Con esto no hay carrera que perder: quien se va lo dice, y el `await` no
  /// toca la direccion.
  bool _nosVamos = false;

  @override
  Widget build(BuildContext context) {
    final estado = GoRouterState.of(context);
    final parametros = estado.uri.queryParameters;
    final buscado = parametros[PantallaGuia.deLaBusqueda] ?? '';
    final enElDocumento =
        parametros[PantallaGuia.deLaPuerta] == TextosDeLaGuia.documento;

    final manual = ref.watch(manualProvider);
    final forma = ref.watch(formaDeLaAplicacionProvider);

    manual.whenData((leido) => _ponerElCajonComoDiceLaUrl(parametros, leido));

    return Center(
      child: ConstrainedBox(
        // El texto corrido se lee mal a lo ancho de un monitor: la medida es la
        // misma que la del cajon de entrega (768 px) mas el aire de los lados.
        constraints: const BoxConstraints(maxWidth: Anchos.entrega + Aire.xxl),
        child: switch (manual) {
          AsyncLoading() => const Cargando('Cargando la guía...'),
          AsyncError() => Padding(
            padding: const EdgeInsets.all(Aire.xl),
            child: EstadoVacio(
              TextosDeLaGuia.noSePudoLeer,
              icono: Icons.menu_book_outlined,
            ),
          ),
          AsyncValue(:final value?) => _Contenido(
            manual: value,
            forma: forma,
            buscado: buscado,
            enElDocumento: enElDocumento,
            alBuscar: (texto) => _irA(parametros, {
              PantallaGuia.deLaBusqueda: texto.isEmpty ? null : texto,
            }),
            alCambiarDePuerta: (aDocumento) => _irA(parametros, {
              PantallaGuia.deLaPuerta: aDocumento
                  ? TextosDeLaGuia.documento
                  : null,
            }),
            alAbrirTarea: (id) => _irA(parametros, {
              PantallaGuia.deLaTarea: id,
              PantallaGuia.deLaPagina: null,
            }),
            alAbrirPagina: (camino) => _irA(parametros, {
              PantallaGuia.deLaPagina: camino,
              PantallaGuia.deLaTarea: null,
            }),
          ),
        },
      ),
    );
  }

  /// Escribe en la direccion lo que cambia y deja lo demas como estaba.
  void _irA(Map<String, String> ahora, Map<String, String?> cambios) {
    final nuevos = <String, String>{...ahora};
    cambios.forEach((clave, valor) {
      if (valor == null) {
        nuevos.remove(clave);
      } else {
        nuevos[clave] = valor;
      }
    });
    context.go(
      Uri(path: PantallaGuia.ruta, queryParameters: nuevos.isEmpty ? null : nuevos)
          .toString(),
    );
  }

  /// EL CAJON SIGUE A LA DIRECCION, no al reves.
  ///
  /// Asi es como «llévame ahí» puede volver: al pulsarlo, el camino cambia a
  /// `/vehicles` y el cajon se cierra solo —eso lo hace `AtrasDelCajon`, 28/09/2026—
  /// pero la direccion de la guia que queda en el historial sigue llevando
  /// `?tarea=…`. Al volver con el atras, esta pantalla se vuelve a pintar con ese
  /// parametro puesto y el cajon se abre donde estaba.
  void _ponerElCajonComoDiceLaUrl(
    Map<String, String> parametros,
    Manual manual,
  ) {
    final tarea = parametros[PantallaGuia.deLaTarea];
    final pagina = parametros[PantallaGuia.deLaPagina];
    final cual = tarea != null
        ? 'tarea:$tarea'
        : (pagina != null ? 'pagina:$pagina' : null);

    // Si ya se pulso «llévame ahí», no se vuelve a abrir nada: la pantalla esta a
    // punto de desaparecer y abrir un cajon ahora lo dejaria encima de la
    // siguiente.
    if (_nosVamos) return;

    if (cual == _enElCajon) return;
    _enElCajon = cual;
    if (cual == null) return;

    // Al terminar el fotograma: abrir un cajon es empujar una ruta, y eso no se
    // puede hacer mientras se esta pintando.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _enElCajon != cual) return;
      _abrirElCajon(cual, manual, parametros);
    });
  }

  Future<void> _abrirElCajon(
    String cual,
    Manual manual,
    Map<String, String> parametros,
  ) async {
    final forma = ref.read(formaDeLaAplicacionProvider);
    final pantallas = pantallasParaLaGuia();

    EnlacesDelManual enlacesDe(String camino) => EnlacesDelManual(
      caminoDeLaPagina: camino,
      aDonde: (destino, desde) {
        final resuelto = resolverElEnlace(
          destino,
          desde,
          manual,
          hayPantallaEn: (ruta) => pantallas.any((p) => p.ruta == ruta),
        );
        return switch (resuelto) {
          null => null,
          ALaPagina(:final camino) => 'pagina:$camino',
          ALaTarea(:final id) => 'tarea:$id',
          ALaPantalla(:final ruta) => 'pantalla:$ruta',
        };
      },
      alSeguir: _seguirElEnlace,
    );

    if (cual.startsWith('tarea:')) {
      final tarea = manual.tarea(cual.substring('tarea:'.length));
      if (tarea == null) {
        // La direccion nombra una tarea que en esta forma no existe (un enlace
        // guardado del telefono abierto en la web). No se finge: se quita de la
        // direccion y se queda la lista, que es lo que si hay.
        _enElCajon = null;
        if (mounted) {
          _irA(parametros, {PantallaGuia.deLaTarea: null});
        }
        return;
      }
      await abrirCajon<void>(
        context,
        titulo: tarea.titulo,
        subtitulo: tarea.tituloDeLaPagina,
        cuerpo: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: pintarElManual(tarea.cuerpo, enlacesDe(tarea.camino)),
        ),
        // El pie sale si el manual NOMBRA una pantalla, tenga boton o no: cuando
        // no lo tiene, el pie es justamente el que explica por que.
        pie: tarea.nombreDePantalla == null
            ? null
            : (_) => _PieDeLaTarea(
                tarea: tarea,
                forma: forma,
                alLlevar: _llevarALaPantalla,
              ),
      );
    } else {
      final camino = cual.substring('pagina:'.length);
      final pagina = manual.pagina(camino);
      if (pagina == null) {
        _enElCajon = null;
        if (mounted) {
          _irA(parametros, {PantallaGuia.deLaPagina: null});
        }
        return;
      }
      await abrirCajon<void>(
        context,
        titulo: pagina.titulo,
        subtitulo: pagina.carpeta.isEmpty ? null : pagina.carpeta,
        cuerpo: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: pintarElManual(pagina.contenido, enlacesDe(pagina.camino)),
        ),
      );
    }

    // El cajon se cerro porque se pulso «llévame ahí»: la direccion ya es otra y
    // aqui no se toca nada. El `?tarea=` se queda en el historial, que es
    // justamente lo que hace que al volver la guia se abra donde estaba.
    if (_nosVamos) {
      _nosVamos = false;
      return;
    }
    if (!mounted || _enElCajon != cual) return;
    _enElCajon = null;
    _irA(GoRouterState.of(context).uri.queryParameters, {
      PantallaGuia.deLaTarea: null,
      PantallaGuia.deLaPagina: null,
    });
  }

  /// Irse a otra pantalla DESDE la guia. Pasa por aqui tanto el boton del pie como
  /// un enlace del texto que apunte a una pantalla, porque las dos tienen la misma
  /// carrera que perder.
  void _llevarALaPantalla(String ruta) {
    _nosVamos = true;
    _enElCajon = null;
    context.go(ruta);
  }

  void _seguirElEnlace(String resuelto) {
    final parametros = GoRouterState.of(context).uri.queryParameters;
    if (resuelto.startsWith('pantalla:')) {
      _llevarALaPantalla(resuelto.substring('pantalla:'.length));
      return;
    }
    if (resuelto.startsWith('tarea:')) {
      _irA(parametros, {
        PantallaGuia.deLaTarea: resuelto.substring('tarea:'.length),
        PantallaGuia.deLaPagina: null,
      });
      return;
    }
    _irA(parametros, {
      PantallaGuia.deLaPagina: resuelto.substring('pagina:'.length),
      PantallaGuia.deLaTarea: null,
    });
  }
}

/// EL PIE DE UNA TAREA: «llévame ahí».
///
/// Es lo que convierte un manual en una guia. Se lee «esto se hace en
/// Vehículos», se toca, y se esta en Vehículos — sin cerrar la guia, buscar el
/// menu y acordarse de a donde se iba.
///
/// Y cuando la pantalla **no existe en esta forma** se dice por que, en vez de
/// dejar un boton que lleva a un 404 de la aplicacion o de esconder el pie sin
/// explicar nada (§4: nada se descarta en silencio).
class _PieDeLaTarea extends StatelessWidget {
  const _PieDeLaTarea({
    required this.tarea,
    required this.forma,
    required this.alLlevar,
  });

  final TareaDelManual tarea;
  final FormaDeLaAplicacion forma;
  final ValueChanged<String> alLlevar;

  @override
  Widget build(BuildContext context) {
    final nombre = tarea.nombreDePantalla ?? '';
    if (tarea.rutaDePantalla == null) {
      return Text(
        TextosDeLaGuia.noHayEsaPantalla(nombre, forma),
        style: Tipos.texto(tamano: 13, color: Colores.tintaSuave, alto: 1.45),
      );
    }
    return Row(
      children: [
        Expanded(
          child: BotonPrincipal(
            key: ClavesDeLaGuia.llevameAhi,
            texto: 'Ir a $nombre',
            // La flecha al final porque el mando LLEVA HACIA ADELANTE: una flecha
            // a la derecha puesta a la izquierda del rotulo se lee al reves de lo
            // que hace (ver `BotonPrincipal.iconoAlFinal`).
            icono: Icons.arrow_forward,
            iconoAlFinal: true,
            enUnaLinea: true,
            alPulsar: () => alLlevar(tarea.rutaDePantalla!),
          ),
        ),
      ],
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({
    required this.manual,
    required this.forma,
    required this.buscado,
    required this.enElDocumento,
    required this.alBuscar,
    required this.alCambiarDePuerta,
    required this.alAbrirTarea,
    required this.alAbrirPagina,
  });

  final Manual manual;
  final FormaDeLaAplicacion forma;
  final String buscado;
  final bool enElDocumento;
  final ValueChanged<String> alBuscar;
  final ValueChanged<bool> alCambiarDePuerta;
  final ValueChanged<String> alAbrirTarea;
  final ValueChanged<String> alAbrirPagina;

  @override
  Widget build(BuildContext context) {
    final buscando = buscado.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Aire.lg, Aire.lg, Aire.lg, Aire.md),
          child: CajaDeBusqueda(
            key: ClavesDeLaGuia.buscar,
            valor: buscado,
            pista: TextosDeLaGuia.pista,
            // `null` = tan ancha como la deje su padre. En un telefono una caja
            // de 220 px deja media pantalla vacia al lado.
            ancho: null,
            alBuscar: alBuscar,
          ),
        ),
        // LAS DOS PUERTAS. Al buscar no se enseñan: lo que sale entonces es UNA
        // lista con las dos clases de resultado, cada una diciendo de donde
        // viene, que es lo que se pidio («el buscador busca en las dos, y dice de
        // cuál viene cada resultado»). Dos pestañas sobre unos resultados que
        // vienen de las dos solo haria preguntarse cual de las dos se esta
        // mirando.
        if (!buscando)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Aire.lg),
            child: Row(
              children: [
                _Puerta(
                  clave: ClavesDeLaGuia.tareas,
                  rotulo: '${TextosDeLaGuia.tareas} (${manual.tareas.length})',
                  icono: Icons.checklist_outlined,
                  activa: !enElDocumento,
                  alPulsar: () => alCambiarDePuerta(false),
                ),
                const SizedBox(width: Aire.sm),
                _Puerta(
                  clave: ClavesDeLaGuia.documento,
                  rotulo:
                      '${TextosDeLaGuia.documento} (${manual.paginas.length})',
                  icono: Icons.menu_book_outlined,
                  activa: enElDocumento,
                  alPulsar: () => alCambiarDePuerta(true),
                ),
              ],
            ),
          ),
        Expanded(
          child: buscando
              ? _Resultados(
                  manual: manual,
                  buscado: buscado,
                  alAbrirTarea: alAbrirTarea,
                  alAbrirPagina: alAbrirPagina,
                )
              : (enElDocumento
                    ? _ListaDePaginas(
                        manual: manual,
                        alAbrirPagina: alAbrirPagina,
                      )
                    : _ListaDeTareas(
                        manual: manual,
                        alAbrirTarea: alAbrirTarea,
                        alAbrirPagina: alAbrirPagina,
                      )),
        ),
      ],
    );
  }
}

/// Una de las dos puertas. **Sin fondo relleno**: lo que dice donde estas es el
/// color, el borde y el icono (§4), el mismo tratamiento que la entrada activa de
/// la barra lateral.
///
/// Lleva icono aunque una pestaña no sea una accion —`_Pestana` de
/// `diseno/pestanas.dart` explica por que ahi no lo lleva— porque estos dos
/// iconos **son de lo que hay detras**, no un glifo de relleno: una lista con
/// marcas y un libro abierto. En un telefono, eso es lo que se reconoce antes de
/// leer.
class _Puerta extends StatelessWidget {
  const _Puerta({
    required this.clave,
    required this.rotulo,
    required this.icono,
    required this.activa,
    required this.alPulsar,
  });

  final Key clave;
  final String rotulo;
  final IconData icono;
  final bool activa;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    final color = activa ? Colores.primario : Colores.tintaSuave;
    return Expanded(
      child: Material(
        key: clave,
        color: activa ? Colores.primarioTenue : Colors.transparent,
        borderRadius: BorderRadius.circular(Radios.lg),
        child: InkWell(
          onTap: alPulsar,
          borderRadius: BorderRadius.circular(Radios.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radios.lg),
              border: Border.all(
                color: activa ? Colores.primario : Colores.linea,
                width: activa ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icono, size: 17, color: color),
                const SizedBox(width: Aire.sm),
                Flexible(
                  child: Text(
                    rotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tipos.texto(
                      tamano: 13.5,
                      peso: activa ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
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

/// EL CATALOGO DE TAREAS, agrupado por la pagina de la que sale.
///
/// La cabecera de cada grupo se puede pulsar y abre **la pagina entera**: asi el
/// documento oficial esta a un toque desde el sitio donde se esta mirando una
/// tarea suya, y no solo desde la otra puerta.
class _ListaDeTareas extends StatelessWidget {
  const _ListaDeTareas({
    required this.manual,
    required this.alAbrirTarea,
    required this.alAbrirPagina,
  });

  final Manual manual;
  final ValueChanged<String> alAbrirTarea;
  final ValueChanged<String> alAbrirPagina;

  @override
  Widget build(BuildContext context) {
    final filas = <Widget>[];
    for (final pagina in manual.paginas) {
      if (pagina.tareas.isEmpty) continue;
      filas.add(
        _CabeceraDeGrupo(
          titulo: pagina.titulo,
          cuantas: pagina.tareas.length,
          alPulsar: () => alAbrirPagina(pagina.camino),
        ),
      );
      for (final tarea in pagina.tareas) {
        filas.add(
          _Fila(
            clave: ClavesDeLaGuia.tarea(tarea.id),
            titulo: tarea.titulo,
            debajo: tarea.nombreDePantalla == null
                ? null
                : 'En ${tarea.nombreDePantalla}',
            alPulsar: () => alAbrirTarea(tarea.id),
          ),
        );
      }
    }

    if (filas.isEmpty) {
      return const EstadoVacio(
        'La guía que viaja en esta versión no trae ninguna tarea. El documento '
        'completo sigue en la otra puerta.',
        icono: Icons.checklist_outlined,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Aire.lg, Aire.md, Aire.lg, Aire.xxl),
      children: filas,
    );
  }
}

class _ListaDePaginas extends StatelessWidget {
  const _ListaDePaginas({required this.manual, required this.alAbrirPagina});

  final Manual manual;
  final ValueChanged<String> alAbrirPagina;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(Aire.lg, Aire.md, Aire.lg, Aire.xxl),
    children: [
      for (final pagina in manual.paginas)
        _Fila(
          clave: ClavesDeLaGuia.pagina(pagina.camino),
          titulo: pagina.titulo,
          debajo: pagina.tareas.isEmpty
              ? pagina.camino
              : '${pagina.tareas.length} tareas · ${pagina.camino}',
          icono: Icons.description_outlined,
          alPulsar: () => alAbrirPagina(pagina.camino),
        ),
    ],
  );
}

class _Resultados extends StatelessWidget {
  const _Resultados({
    required this.manual,
    required this.buscado,
    required this.alAbrirTarea,
    required this.alAbrirPagina,
  });

  final Manual manual;
  final String buscado;
  final ValueChanged<String> alAbrirTarea;
  final ValueChanged<String> alAbrirPagina;

  @override
  Widget build(BuildContext context) {
    final encontrados = manual.buscar(buscado);
    if (encontrados.isEmpty) {
      return EstadoVacio(
        TextosDeLaGuia.sinResultados(buscado.trim()),
        icono: Icons.search_off_outlined,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Aire.lg, Aire.md, Aire.lg, Aire.xxl),
      children: [
        for (final r in encontrados)
          _Fila(
            clave: r.deDondeSale == DeDondeSale.tarea
                ? ClavesDeLaGuia.tarea(r.id)
                : ClavesDeLaGuia.pagina(r.id),
            titulo: r.titulo,
            debajo: r.donde,
            icono: r.deDondeSale == DeDondeSale.tarea
                ? Icons.checklist_outlined
                : Icons.description_outlined,
            // DE CUAL DE LAS DOS VIENE. Sin esto, dos resultados con el mismo
            // nombre —la tarea «Poner o corregir un almacén» y la pagina
            // «Almacenes»— se leen como el mismo sitio.
            insignia: r.deDondeSale == DeDondeSale.tarea ? 'Tarea' : 'Página',
            alPulsar: () => r.deDondeSale == DeDondeSale.tarea
                ? alAbrirTarea(r.id)
                : alAbrirPagina(r.id),
          ),
      ],
    );
  }
}

class _CabeceraDeGrupo extends StatelessWidget {
  const _CabeceraDeGrupo({
    required this.titulo,
    required this.cuantas,
    required this.alPulsar,
  });

  final String titulo;
  final int cuantas;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Aire.lg, bottom: Aire.xs),
    child: InkWell(
      onTap: alPulsar,
      borderRadius: BorderRadius.circular(Radios.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 15,
              color: Colores.tintaSuave,
            ),
            const SizedBox(width: Aire.sm),
            Expanded(
              child: Text(
                titulo.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tipos.texto(
                  tamano: 11,
                  peso: FontWeight.w700,
                  color: Colores.tintaSuave,
                  interletra: 0.6,
                ),
              ),
            ),
            Text(
              'Ver la página',
              style: Tipos.texto(
                tamano: 11.5,
                peso: FontWeight.w600,
                color: Colores.primario,
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: Colores.primario),
          ],
        ),
      ),
    ),
  );
}

/// Una fila de la lista. Alta de dedo, con el titulo en una o dos lineas y la
/// linea de debajo diciendo de donde sale.
class _Fila extends StatelessWidget {
  const _Fila({
    required this.clave,
    required this.titulo,
    required this.alPulsar,
    this.debajo,
    this.icono,
    this.insignia,
  });

  final Key clave;
  final String titulo;
  final String? debajo;
  final IconData? icono;
  final String? insignia;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Material(
      key: clave,
      color: Colores.blanco,
      borderRadius: BorderRadius.circular(Radios.md),
      child: InkWell(
        onTap: alPulsar,
        borderRadius: BorderRadius.circular(Radios.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Aire.md,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radios.md),
            border: Border.all(color: Colores.linea),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icono != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icono, size: 17, color: Colores.tintaSuave),
                ),
                const SizedBox(width: Aire.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: Tipos.texto(
                        tamano: 14.5,
                        peso: FontWeight.w600,
                        color: Colores.tinta,
                        alto: 1.3,
                      ),
                    ),
                    if (debajo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          debajo!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Tipos.texto(
                            tamano: 12,
                            color: Colores.tintaSuave,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (insignia != null) ...[
                const SizedBox(width: Aire.sm),
                Insignia(insignia!),
              ],
              const SizedBox(width: Aire.xs),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colores.tintaSuave,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
