import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/pestanas.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/plataforma.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../datos/modelos.dart';
import '../estado/filtros_en_la_url.dart';
import '../estado/proveedores.dart';
import 'acciones.dart';
import 'columna.dart';
import 'kit.dart';
import 'panel_sin_colocar.dart';
import 'tarjeta.dart';

/// EL TABLERO DE PREPARACION.
///
/// Entre «me han llegado 180 pedidos» y «sale este camion con estas 14 paradas»
/// hay un trabajo que hoy se hace en la cabeza del logistico y en un papel:
/// agrupar por zona. Esto es ese paso — columnas que pone el, tarjetas que
/// arrastra el.
///
/// Y es la pantalla que mas sentido tiene **sin red**: preparar es mover cosas
/// de sitio, y es justo lo que se hace durante el dia, que es cuando no hay
/// senal. No hay ningun «modo sin conexion» que encender: se guarda en el
/// aparato y se sube por detras.
///
/// **Sin `Scaffold` ni `AppBar`**: los pone el armazon
/// (`navegacion/pantalla_registrada.dart`). Devolver otro deja dos barras
/// superiores y rompe el selector de sucursal.
class PantallaTablero extends ConsumerStatefulWidget {
  const PantallaTablero({this.lectura, super.key});

  /// Lo que venia en la direccion: los filtros que se pudieron aplicar y **la
  /// lista de los que no**. En web, mandar un enlace al tablero ya filtrado
  /// tiene que llevar al mismo sitio, y cuando no puede tiene que DECIRLO.
  ///
  /// `null` es «esta pantalla se pinto suelta», que es lo que hace una prueba de
  /// widget: entonces no se toca el filtro que ya hubiera puesto.
  final LecturaDeLaUrl? lectura;

  @override
  ConsumerState<PantallaTablero> createState() => _PantallaTableroState();
}

class _PantallaTableroState extends ConsumerState<PantallaTablero> {
  /// EN EL MOVIL, EN QUE PAGINA SE ESTA.
  ///
  /// `0` es «sin colocar»; de `1` en adelante, las zonas una a una y al final la
  /// de crear otra. Es UN numero y no un si/no porque el gesto que pidio Jose es
  /// el mismo para las dos cosas: deslizar pasa de «sin colocar» a la primera
  /// zona igual que pasa de una zona a la siguiente.
  int _pagina = 0;

  /// La pagina de «sin colocar». Con nombre porque se lee en cuatro sitios y
  /// `0` suelto no dice cual de las dos mitades es.
  static const _sinColocar = 0;

  /// Por debajo de esto, las dos mitades no caben una al lado de la otra.
  static const _anchoDeDosMitades = anchoDeDosMitades;

  @override
  void initState() {
    super.initState();
    _adoptarLaUrl();
  }

  @override
  void didUpdateWidget(PantallaTablero anterior) {
    super.didUpdateWidget(anterior);
    _adoptarLaUrl();
  }

  /// Los filtros de la direccion mandan al entrar.
  ///
  /// Se hace fuera del `build` —despues del fotograma— porque tocar un provider
  /// mientras se construye es lo que Riverpod prohibe, con razon: dejaria el
  /// arbol a medio pintar con dos estados distintos.
  void _adoptarLaUrl() {
    final deLaUrl = widget.lectura?.filtros;
    if (deLaUrl == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ahora = ref.read(filtrosTableroProvider);
      if (!FiltrosEnLaUrl.iguales(ahora, deLaUrl)) {
        ref.read(filtrosTableroProvider.notifier).poner(deLaUrl);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asincrono = ref.watch(tableroProvider);
    final cuerpo = asincrono.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Problema(texto: _texto(e)),
      data: _conDatos,
    );

    // LO QUE EL ENLACE TRAIA Y NO SE PUDO APLICAR, ENCIMA DE TODO LO DEMAS.
    //
    // Va por delante del conteo —«Sin colocar (308)»— a proposito: quien abrio
    // un enlace tiene que enterarse de que el tablero NO esta acotado como el
    // enlace decia **antes** de leer un numero y creerselo. Y va fuera del
    // `when`, para que salga tambien cuando lo que hay debajo es un problema:
    // un enlace roto no deja de estar roto porque ademas falte elegir sucursal.
    final noSePudieron = widget.lectura?.noSePudieron ?? const <String>[];
    if (noSePudieron.isEmpty) return cuerpo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FranjaNoSePudo(noSePudieron),
        Expanded(child: cuerpo),
      ],
    );
  }

  Widget _conDatos(Tablero tablero) {
    // Las dos situaciones normales que no son un tablero: sin sucursal elegida
    // y sin almacen con coordenadas. Se dicen con las palabras del pliego.
    final problema = tablero.problema;
    if (problema != null) return _Problema(texto: problema);
    return _cuerpo(tablero);
  }

  Widget _cuerpo(Tablero tablero) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (tablero.desaparecidos.isNotEmpty)
        _AvisoDesaparecidos(desaparecidos: tablero.desaparecidos),
      _BarraDeArriba(tablero: tablero),
      Expanded(
        child: LayoutBuilder(
          builder: (contexto, medidas) {
            if (medidas.maxWidth >= _anchoDeDosMitades) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 340,
                    child: PanelSinColocar(
                      tablero: tablero,
                      alPulsarTarjeta: (pedido) =>
                          _moverTarjeta(tablero, pedido),
                      alDevolver: _devolver,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: _Tira(tablero: tablero)),
                ],
              );
            }
            // EL MOVIL: UNA SOLA TIRA DE PAGINAS.
            //
            // «Sin colocar» es la primera y DESPUES van las zonas, una a una.
            // Puestas en fila, el mismo gesto sirve para las dos cosas que
            // pidio Jose: pasar de una pestana a la otra, y ya dentro de zonas
            // ir de una zona a la siguiente sin volver a la pestana.
            //
            // Y por eso NO van anidadas —las pestanas por fuera, las zonas por
            // dentro—, que era lo primero que salia: dos deslizamientos en el
            // mismo eje no se turnan. Manda el de dentro, y cuando llega a su
            // extremo el de fuera no recoge el gesto: quedaria una zona de la
            // que no se puede salir con el dedo.
            final cuantas = 1 + _cuantasZonas(tablero);
            final pagina = _pagina.clamp(_sinColocar, cuantas - 1);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                  child: ControlSenalado(
                    nombre: Senalado.tableroCarruselDeZonas,
                    child: CarruselDePestanas(
                      indice: pagina,
                      cuantas: cuantas,
                      titulo: _tituloDePagina(tablero, pagina),
                      etiquetas: _nombresDePagina(tablero),
                      alCambiar: _irA,
                    ),
                  ),
                ),
                Expanded(
                  child: CuerpoDeslizable(
                    indice: pagina,
                    cuantas: cuantas,
                    alCambiar: _irA,
                    pagina: (contexto, i) => _paginaDelMovil(tablero, i),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );

  /// EL ROTULO DE LA PAGINA EN LA QUE SE ESTA — el unico que se pinta.
  ///
  /// Es el de la MITAD en la que se esta, no el de la zona concreta: dentro de
  /// zonas pone «Zonas (12)» y no «Centro (3)», porque el nombre y la cuenta de
  /// la zona ya los dice a lo grande la cabecera de la propia columna, dos
  /// dedos mas abajo. Dos sitios con el mismo texto es el sitio perfecto para
  /// que un dia digan cosas distintas.
  ///
  /// Cual de las doce zonas es lo dicen las bolitas y la cabecera de la columna.
  String _tituloDePagina(Tablero tablero, int pagina) {
    if (pagina == _sinColocar) {
      return 'Sin colocar (${tablero.sinColocar.total})';
    }
    if (tablero.columnas.isNotEmpty && pagina - 1 >= tablero.columnas.length) {
      return 'Nueva columna';
    }
    return 'Zonas (${tablero.columnas.length})';
  }

  /// CUANTAS PAGINAS DE ZONAS HAY EN EL MOVIL: una por columna, mas la de crear
  /// otra. Sin ninguna columna es una sola, la que explica que las pone el.
  int _cuantasZonas(Tablero tablero) =>
      tablero.columnas.isEmpty ? 1 : tablero.columnas.length + 1;

  /// El nombre de cada pagina, que es lo que dice la flecha a donde lleva.
  List<String> _nombresDePagina(Tablero tablero) => [
    'Sin colocar',
    if (tablero.columnas.isEmpty)
      'Zonas'
    else ...[
      for (final columna in tablero.columnas) columna.nombre,
      'Nueva columna',
    ],
  ];

  Widget _paginaDelMovil(Tablero tablero, int i) {
    if (i == _sinColocar) {
      return PanelSinColocar(
        tablero: tablero,
        alPulsarTarjeta: (pedido) => _moverTarjeta(tablero, pedido),
        alDevolver: _devolver,
        // Sin rotulo: lo dice el carrusel, justo encima.
        conRotulo: false,
      );
    }
    if (tablero.columnas.isEmpty) return const _SinColumnas();
    final cual = i - 1;
    if (cual >= tablero.columnas.length) return const _PaginaNuevaColumna();
    // `ancho: null` = que ocupe la pagina entera, que es justo lo que hay.
    return _Zona(tablero: tablero, cual: cual);
  }

  void _irA(int pagina) {
    if (pagina == _pagina) return;
    setState(() => _pagina = pagina);
  }

  void _moverTarjeta(Tablero tablero, TarjetaPedido pedido) {
    unawaited(
      AccionesTablero.moverTarjeta(
        context,
        ref,
        pedido: pedido,
        tablero: tablero,
      ),
    );
  }

  void _devolver(TarjetaArrastrada datos) {
    // Arrastrar a la izquierda algo que ya estaba a la izquierda no es una
    // orden: es un dedo que se escapo.
    if (datos.desdeColumnaId == null) return;
    // POR `AccionesTablero.hacer` Y NO A PELO. Un `unawaited` suelto sobre algo
    // que escribe en la base es un error asincrono sin dueno: con el disco
    // lleno, el gesto no se guarda y **no se entera nadie**. Ver
    // `AccionesTablero.noSePudoGuardar`.
    unawaited(
      AccionesTablero.hacer(
        context,
        ref,
        () => ref.read(tableroProvider.notifier).quitar(datos.pedidoId),
      ),
    );
  }
}

String _texto(Object fallo) => switch (fallo) {
  // No se ensena «todo», que es lo que pareceria razonable y seria lo peor.
  final FaltaElegirSucursal e => e.mensaje,
  // Se ordena desde el sitio del que sale la mercancia, o no se ordena.
  final SinAlmacenConCoordenadas e => e.mensaje,
  final RechazoDelTablero e => e.mensaje,
  _ => 'No se pudo abrir el tablero: $fallo',
};

/// La tira de columnas, que se desplaza a lo ancho, con el «+» al final.
///
/// **Solo en pantalla ancha.** En el movil las zonas ya no van en una tira que
/// se empuja: van una por pagina y se pasa deslizando (`_paginaDelMovil`). En
/// una tira, para llegar a la zona seis hay que arrastrar cinco veces sin que
/// nada enganche; en paginas, cada deslizamiento cae en una zona entera.
class _Tira extends ConsumerWidget {
  const _Tira({required this.tablero});

  final Tablero tablero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tablero.columnas.isEmpty) return const _SinColumnas();

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(4),
      // Una mas: el «+» del final, que es como dice el pliego que se crea una
      // columna.
      itemCount: tablero.columnas.length + 1,
      itemBuilder: (contexto, i) => i == tablero.columnas.length
          ? const _BotonNuevaColumna(ancho: 140)
          : _Zona(tablero: tablero, cual: i, ancho: 300),
    );
  }
}

/// UNA ZONA, con todo lo que se puede hacer sobre ella.
///
/// Vive suelta porque la usan los dos mundos: la tira de escritorio y la pagina
/// del movil. Tenerla dos veces era tener dos sitios donde arreglar la misma
/// regla de «soltar donde ya estaba no es una orden», y uno de los dos se
/// olvida.
class _Zona extends ConsumerWidget {
  const _Zona({required this.tablero, required this.cual, this.ancho});

  final Tablero tablero;

  /// Cual de `tablero.columnas`, por su sitio: hace falta el numero y no solo la
  /// columna, porque reordenar es «ponla donde esta esta».
  final int cual;

  /// `null` = que ocupe lo que le den. Es lo del movil, donde la zona es la
  /// pagina entera.
  final double? ancho;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columna = tablero.columnas[cual];
    return ColumnaDelTablero(
      columna: columna,
      ancho: ancho,
      // Sólo la primera zona se deja senalar por la Guia: ver
      // `ColumnaDelTablero.esLaPrimera`.
      esLaPrimera: cual == 0,
      esLaSegunda: cual == 1,
      tarjetas: tablero.deColumna(columna.id),
      alSoltar: (datos, posicion) {
        // Soltar una tarjeta donde ya estaba no es una orden: es un dedo que se
        // escapo. Sin esto, cada roce deja un apunte en la cola.
        if (datos.desdeColumnaId == columna.id && posicion == null) return;
        // Igual que en `_devolver`: si el aparato no puede guardar, se dice.
        unawaited(
          AccionesTablero.hacer(
            context,
            ref,
            () => ref
                .read(tableroProvider.notifier)
                .colocar(
                  pedidoId: datos.pedidoId,
                  columnaId: columna.id,
                  posicion: posicion,
                ),
          ),
        );
      },
      alSoltarColumna: (arrastrada) {
        final ids = tablero.columnas.map((c) => c.id).toList()
          ..remove(arrastrada.columnaId);
        ids.insert(cual.clamp(0, ids.length), arrastrada.columnaId);
        unawaited(
          AccionesTablero.hacer(
            context,
            ref,
            () => ref.read(tableroProvider.notifier).reordenar(ids),
          ),
        );
      },
      alPulsarTarjeta: (tarjeta) => unawaited(
        AccionesTablero.moverTarjeta(
          context,
          ref,
          pedido: tarjeta.pedido,
          tablero: tablero,
          columnaActual: tarjeta.columnaId,
          posicionActual: tarjeta.posicion,
        ),
      ),
      alAbrirMenu: () => unawaited(
        AccionesTablero.menuDeColumna(
          context,
          ref,
          columna: columna,
          tablero: tablero,
        ),
      ),
    );
  }
}

/// Un tablero sin ninguna zona todavia.
class _SinColumnas extends ConsumerWidget {
  const _SinColumnas();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Las zonas las pones tú.', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Cada sucursal divide su territorio a su manera: por distritos, '
            'por carreteras o por barrios de toda la vida. Crea la primera '
            'columna con el «+».',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          // LOS TRES SITIOS DONDE SE CREA UNA ZONA COMPARTEN NOMBRE, y se puede:
          // son excluyentes. Este sale con el tablero vacio, el de
          // `_PaginaNuevaColumna` sólo en el telefono y el de
          // `_BotonNuevaColumna` sólo en la tira de escritorio. Nunca hay dos
          // montados a la vez, que es la unica condicion que pone
          // `RegistroDeControles`.
          ControlSenalado(
            nombre: Senalado.tableroNuevaZona,
            child: FilledButton.icon(
              onPressed: () =>
                  unawaited(AccionesTablero.crearColumna(context, ref)),
              icon: const Icon(Icons.add),
              label: const Text('Nueva columna'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// LA ULTIMA PAGINA DEL MOVIL: crear otra zona.
///
/// En la tira de escritorio esto es el recuadro del «+» al final. En el movil,
/// donde cada zona ocupa una pagina, un recuadro estirado a pantalla completa
/// seria un boton gigante: se dice con palabras y ya.
class _PaginaNuevaColumna extends ConsumerWidget {
  const _PaginaNuevaColumna();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Fin de las zonas.', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Si el territorio se te queda corto, pon otra.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          // LOS TRES SITIOS DONDE SE CREA UNA ZONA COMPARTEN NOMBRE, y se puede:
          // son excluyentes. Este sale con el tablero vacio, el de
          // `_PaginaNuevaColumna` sólo en el telefono y el de
          // `_BotonNuevaColumna` sólo en la tira de escritorio. Nunca hay dos
          // montados a la vez, que es la unica condicion que pone
          // `RegistroDeControles`.
          ControlSenalado(
            nombre: Senalado.tableroNuevaZona,
            child: FilledButton.icon(
              onPressed: () =>
                  unawaited(AccionesTablero.crearColumna(context, ref)),
              icon: const Icon(Icons.add),
              label: const Text('Nueva columna'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BotonNuevaColumna extends ConsumerWidget {
  const _BotonNuevaColumna({required this.ancho});

  final double ancho;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    width: ancho,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    child: ControlSenalado(
      nombre: Senalado.tableroNuevaZona,
      child: OutlinedButton(
        onPressed: () => unawaited(AccionesTablero.crearColumna(context, ref)),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add),
            SizedBox(height: 4),
            Text('Columna', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

/// De donde se mide, de cuando son los datos y qué ha dejado de servir.
///
/// Lo que queda sin subir NO se pinta aqui: ya lo dice la franja del armazon,
/// en las siete pantallas. Dos contadores del mismo numero es el sitio perfecto
/// para que un dia digan cosas distintas.
class _BarraDeArriba extends ConsumerWidget {
  const _BarraDeArriba({required this.tablero});

  final Tablero tablero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final avisos = tablero.avisos;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      color: tema.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // «Santiago de Cuba · desde Santiago de Cuba» no le dice nada a
                // nadie, y así salía en SEIS de las ocho: en Accesos el almacén
                // se llama como el sitio (Camaguey, Guantanamo, Holguin, Las
                // Tunas, Sancti Spiritus, Santiago de Cuba). Sólo Granma
                // —«Bayamo (Granma)»— y La Habana —«Almacén Habana»— decían algo.
                //
                // Jose, 25/09/2026: «explicame q es esa mierda por q sale ahí».
                //
                // El «desde» sirve para una cosa concreta: los kilómetros de
                // cada tarjeta —y el domicilio que se cobra con ellos— se miden
                // desde ESE almacén. Eso hay que decirlo cuando la sucursal
                // tiene más de uno, porque entonces cuál se usa no es evidente.
                // Cuando tiene uno solo y se llama igual, es ruido.
                // Y DESDE EL 26/09/2026 SE PUEDE ELEGIR, cuando hay más de uno.
                // Jose: «hace falta que aparezca por lo menos y diga que no está
                // configurado el que no tiene la ubicación puesta». El porqué
                // entero, en `CabeceraDelTablero`.
                CabeceraDelTablero(
                  tablero.sucursalNombre,
                  tablero.almacen.nombre,
                  sucursalId: tablero.sucursalId,
                  almacenes: tablero.almacenes,
                ),
                // Un tablero que parece vivo y lleva seis horas congelado es
                // peor que uno que avisa.
                //
                // Y si hay algo aqui que no esta arriba, eso manda sobre la
                // hora: refrescar borraria la foto de aqui y se lo llevaria por
                // delante, asi que la aplicacion se niega — y lo DICE, que es la
                // mitad que faltaba. Callarselo dejaba a quien pulsaba sin saber
                // si es que no habia cambios o que se estaba protegiendo su
                // trabajo.
                // AQUI SALIA «el servidor rechazó tu cambio», y se quitó el
                // 24/09/2026 porque no podía salir nunca: en un navegador la
                // tabla `apuntes` no se llena, así que no había nada que leer.
                // El «no» del servidor sale en el acto, con su motivo literal,
                // en el propio gesto. El porqué entero está en
                // `estado/proveedores.dart`, donde vivía el provider.
                if (ref.read(tableroProvider.notifier).porQueNoSeRefresca
                    case final pendiente?)
                  Text(
                    'No se actualiza: hay $pendiente. Se sube primero y '
                    'después se trae — así no se pierde nada.',
                    style: tema.textTheme.labelMedium?.copyWith(
                      color: ColoresTablero.ambar,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                // «Visto por ultima vez a las 10:41» — SOLO DONDE HAY UNA
                // COPIA QUE PUEDA ENVEJECER, o sea en la APK y el escritorio.
                //
                // En la web el tablero sale del servidor y se repinta solo en
                // cuanto algo cambia, asi que esa hora no avisa de nada: es la
                // hora de hace un segundo, puesta ahi para siempre. Y «Sin
                // descargar todavia» es directamente falso en un navegador.
                // Regla 1 del CLAUDE.md, y van cinco veces.
                else if (Destino.trabajaSinConexion)
                  Text(
                    tablero.vistoAt == null
                        ? 'Sin descargar todavía'
                        : 'Visto por última vez a las '
                              '${horaBonita(tablero.vistoAt!)}',
                    style: tema.textTheme.labelMedium?.copyWith(
                      color: tablero.vistoAt == null
                          ? ColoresTablero.ambar
                          : tema.colorScheme.onSurfaceVariant,
                    ),
                  ),
                // Tres contadores y no uno: se arreglan de tres maneras
                // distintas, y un numero unico obligaria a abrir las doce
                // columnas para saber cual es.
                if (avisos.archivados > 0)
                  insigniaGrave('${avisos.archivados} archivados en PEDIDO'),
                if (avisos.enOtraRuta > 0)
                  insigniaGrave('${avisos.enOtraRuta} ya en otra ruta'),
                if (avisos.sinFactura > 0)
                  insigniaGrave(
                    '${avisos.sinFactura} sin factura o sin cotejar',
                  ),
                if (avisos.cambiados > 0)
                  insigniaAviso('${avisos.cambiados} cambiaron en la factura'),
              ],
            ),
          ),
          _BotonDeTraer(sucursalId: tablero.sucursalId),
        ],
      ),
    );
  }
}

/// EL BOTÓN DE «TRAER LO DEL SERVIDOR», QUE **CONTESTA** — 28/09/2026.
///
/// Jose, sin señal, en el teléfono: se pulsa y «ni error, ni aviso, ni nada».
/// Los datos se quedaban como estaban y no había forma de saber si es que no
/// había nada nuevo, si seguía trayendo o si no se pudo. Era un `unawaited`
/// suelto sobre una función que devolvía `void` y se tragaba el «sin señal».
///
/// Ahora dice lo que pasó **con el motivo literal**: «no hay conexión con el
/// servidor», «hay 1 cambio sin subir», o lo que conteste el servidor. El
/// §3-quinquies pide justo lo contrario de un aviso que sale siempre, y por eso
/// esto va **en el gesto y sólo en el gesto**: el ciclo automático de cada dos
/// minutos sigue tan callado como estaba, porque ahí no hay nadie esperando.
///
/// El «sí» va aparte y corto. Sin él vuelve el mismo agujero por el otro lado:
/// si el aviso sale sólo cuando falla, un tablero que ya estaba al día se lee
/// como un botón que no hace nada, que es la queja de partida.
///
/// Y mientras trae, la rueda: en la conexión de allá esto tarda de 55 s a 115 s
/// según el propio cliente, y un botón que no cambia durante minuto y medio se
/// pulsa cuatro veces.
class _BotonDeTraer extends ConsumerStatefulWidget {
  const _BotonDeTraer({required this.sucursalId});

  /// Para no dejar una petición de la sucursal anterior contestando encima de
  /// la nueva: si se cambia de sucursal a media bajada, lo que llegue ya no es
  /// de lo que hay delante y no se dice nada.
  final String sucursalId;

  @override
  ConsumerState<_BotonDeTraer> createState() => _BotonDeTraerState();
}

class _BotonDeTraerState extends ConsumerState<_BotonDeTraer> {
  bool _trayendo = false;

  @override
  Widget build(BuildContext context) {
    if (_trayendo) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Traer lo del servidor',
      visualDensity: VisualDensity.compact,
      onPressed: () => unawaited(_traer()),
    );
  }

  Future<void> _traer() async {
    final sucursal = widget.sucursalId;
    setState(() => _trayendo = true);
    final LoQuePasoAlTraer paso;
    try {
      paso = await ref.read(tableroProvider.notifier).bajarDelServidor();
    } finally {
      // El `finally` y no detrás del `await`: si esto revienta por algo que
      // nadie previó, la rueda se queda girando para siempre y el botón no se
      // puede volver a pulsar. Un tablero atascado sin decir por qué es el
      // mismo fallo que se está arreglando, con otra cara.
      if (mounted) setState(() => _trayendo = false);
    }
    if (!mounted || widget.sucursalId != sucursal) return;
    final mensajero = ScaffoldMessenger.maybeOf(context);
    if (mensajero == null) return;
    mensajero
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            paso.seTrajo
                ? 'Tablero al día con el servidor.'
                : 'No se trajo nada: ${paso.motivo}.',
          ),
          backgroundColor: paso.seTrajo ? null : ColoresTablero.rojo,
          duration: Duration(seconds: paso.seTrajo ? 2 : 6),
        ),
      );
  }
}

/// LO QUE EL ENLACE PEDIA Y NO SE PUDO HACER, con su clave y su valor.
///
/// «No se pudo aplicar un filtro» no le dice nada a nadie; `dia=31-12-2026` si,
/// porque quien mando el enlace puede corregirlo. Es la misma regla del
/// §3-quinquies: el motivo literal o nada. La gemela de Pedidos vive en
/// `pantallas/pedidos/vista/pantalla_pedidos.dart` y dice exactamente lo mismo:
/// las dos pantallas se abren con el mismo enlace pegado y tienen que hablar
/// igual.
class _FranjaNoSePudo extends StatelessWidget {
  const _FranjaNoSePudo(this.cuales);

  final List<String> cuales;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(Aire.md),
    decoration: BoxDecoration(
      color: ColoresTablero.ambarFondo,
      border: Border(
        bottom: BorderSide(color: ColoresTablero.ambar.withValues(alpha: 0.45)),
      ),
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

/// Los que se llevo la cascada: se avisa UNA vez, con lo que se sabia de ellos
/// antes de que se fueran (§7.5).
class _AvisoDesaparecidos extends ConsumerWidget {
  const _AvisoDesaparecidos({required this.desaparecidos});

  final List<PedidoDesaparecido> desaparecidos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuantos = desaparecidos.length;
    final lista = desaparecidos
        .map(
          (d) =>
              '${d.operationNumber ?? d.pedidoId}'
              '${d.columna == null ? '' : ' (${d.columna})'}',
        )
        .join(', ');
    return MaterialBanner(
      backgroundColor: ColoresTablero.rojoFondo,
      content: Text(
        cuantos == 1
            ? '1 pedido que tenías puesto ya no está en PEDIDO: $lista'
            : '$cuantos pedidos que tenías puestos ya no están en PEDIDO: '
                  '$lista',
      ),
      actions: [
        TextButton(
          onPressed: () => unawaited(
            ref.read(tableroProvider.notifier).olvidarDesaparecidos(),
          ),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}

/// Lo que no deja pintar el tablero, dicho con las palabras del pliego.
class _Problema extends StatelessWidget {
  const _Problema({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(texto, textAlign: TextAlign.center),
    ),
  );
}

/// LO QUE SE LEE ARRIBA DEL TABLERO: la sucursal y, si aporta algo, desde dónde
/// se mide.
///
/// Es un widget con nombre y no una línea suelta dentro del `build` para que su
/// prueba pase por lo que de verdad se pinta —`la_cabecera_no_se_repite_test`—
/// y no por una función copiada al lado.
class CabeceraDelTablero extends ConsumerWidget {
  const CabeceraDelTablero(
    this.sucursal,
    this.almacen, {
    this.sucursalId = '',
    this.almacenes = const <AlmacenDeLaSucursal>[],
    super.key,
  });

  final String sucursal;

  /// El almacén desde el que se mide. Vacío mientras no se sabe cuál es.
  final String almacen;

  /// Para poder anotar la elección donde toca: es por sucursal.
  final String sucursalId;

  /// TODOS los de la sucursal, con ubicación o sin ella.
  final List<AlmacenDeLaSucursal> almacenes;

  /// CON UNO SOLO NO SE OFRECE ELEGIR.
  ///
  /// Un desplegable de un elemento no elige nada: es un botón que promete algo y
  /// abre una lista de uno. Tres de las ocho sucursales están así hoy —Granma,
  /// Holguín y Las Tunas tienen un almacén cada una—, y en ésas la cabecera se
  /// queda exactamente como estaba.
  bool get sePuedeElegir => almacenes.length > 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final texto = _cabecera(sucursal, almacen);
    final estilo = Theme.of(context).textTheme.labelMedium;
    if (!sePuedeElegir) return Text(texto, style: estilo);

    // SE TOCA. Y se ve que se toca: sin la flecha, un texto que abre algo no lo
    // parece — es el mismo fallo que el `isExpanded` que faltaba en los
    // desplegables de esta pantalla, donde lo que se perdía era justo la flecha.
    return InkWell(
      onTap: () => _abrirLaLista(context, ref),
      borderRadius: BorderRadius.circular(Radios.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // `Flexible` y elipsis: a 390 px «San Antonio de los Baños · desde
            // HABANA HACENDADO» no cabe, y lo que no puede irse por la derecha
            // es la flecha.
            Flexible(
              child: Text(
                texto,
                style: estilo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 16),
          ],
        ),
      ),
    );
  }

  /// La lista, EN UN CAJÓN, también en escritorio.
  ///
  /// La regla general de Procovar es cajón en móvil y modal en escritorio. Aquí
  /// no: delivery-logistica tiene una **excepción aprobada el 05/09/2026**
  /// —escrita en el §4 del `CLAUDE.md` de este repo, en `pantallas.md` §0 y §9.2
  /// y en la cabecera de `diseno/cajon.dart`— y no hay variante modal. Lo que se
  /// conserva de la regla es lo que de verdad importa: en móvil ocupa la pantalla
  /// entera, y **la ✕ de cerrar no desaparece nunca** — la pone la cabecera del
  /// propio [Cajon], fuera del cuerpo desplazable.
  ///
  /// Se usa `mostrarCajon` y no `showDialog` por eso mismo, y porque los otros
  /// cinco paneles de esta pantalla ya van así: un panel que se abriera de otra
  /// forma se leería como si fuera otra cosa.
  Future<void> _abrirLaLista(BuildContext context, WidgetRef ref) =>
      mostrarCajon<void>(
        context: context,
        titulo: 'Desde qué almacén se mide',
        contenido: (contexto) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Los kilómetros de cada tarjeta —y el domicilio que se cobra con '
              'ellos— se miden desde este punto.',
              style: Theme.of(contexto).textTheme.bodySmall,
            ),
            const SizedBox(height: Aire.md),
            for (final a in almacenes)
              _FilaDeAlmacen(
                almacen: a,
                elegido: a.nombre == almacen,
                alElegir: a.sirveParaMedir
                    ? () {
                        ref
                            .read(almacenElegidoProvider.notifier)
                            .elegir(sucursalId, a.id);
                        Navigator.of(contexto).maybePop();
                      }
                    : null,
              ),
          ],
        ),
      );
}

/// UNA FILA DE LA LISTA DE ALMACENES.
///
/// Dos cosas distintas y las dos hacen falta: **que existe** y **que le falta la
/// ubicación**. Un almacén sin punto sale con su nombre, apagado, y con el motivo
/// en palabras de la casa al lado. No se puede pulsar, y ahí no hay término
/// medio: medir desde un punto que no existe da un kilometraje creíble y
/// equivocado, y con ese kilometraje se le cobra el domicilio al cliente. El
/// fallo que más caro sale aquí es el número que se lee bien y está mal.
class _FilaDeAlmacen extends StatelessWidget {
  const _FilaDeAlmacen({
    required this.almacen,
    required this.elegido,
    required this.alElegir,
  });

  final AlmacenDeLaSucursal almacen;
  final bool elegido;

  /// `null` = **no se puede elegir**. Es lo que apaga la fila, y es una sola
  /// fuente: así no puede pasar que se vea apagada y se pueda pulsar, ni al
  /// revés.
  final VoidCallback? alElegir;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final sirve = alElegir != null;
    return ListTile(
      key: ValueKey('almacen-${almacen.id}'),
      contentPadding: EdgeInsets.zero,
      enabled: sirve,
      onTap: alElegir,
      leading: Icon(
        elegido ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 20,
        color: sirve ? Colores.primario : Colores.tintaSuave,
      ),
      title: Text(
        almacen.nombre,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tema.textTheme.bodyMedium?.copyWith(
          color: sirve ? Colores.tinta : Colores.tintaSuave,
        ),
      ),
      subtitle: sirve
          ? (almacen.principal
                ? Text('el principal', style: tema.textTheme.bodySmall)
                : null)
          // EL MOTIVO, LITERAL Y EN SU FILA. Un icono de aviso a secas deja a
          // quien mira preguntándose qué le pasa, y lo que le pasa tiene
          // arreglo: lo pone el logístico de esa sucursal.
          : Text(
              AlmacenDeLaSucursal.sinUbicacion,
              style: tema.textTheme.bodySmall?.copyWith(
                color: ColoresTablero.ambar,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// La sucursal y, si aporta algo, desde dónde se mide.
///
/// Se comparan los nombres **sin tildes y sin mayúsculas** porque es justo así
/// como se parecen: la sucursal es «Camagüey» y su almacén, «Camaguey». Dos
/// escrituras del mismo sitio no son dos sitios.
String _cabecera(String sucursal, String almacen) {
  final a = _llano(almacen);
  if (a.isEmpty) return sucursal;
  final s = _llano(sucursal);
  // Uno dentro del otro también cuenta: «Granma» y «Bayamo (Granma)» sí son
  // distintos —el almacén nombra la ciudad, que es lo que hacía falta saber—,
  // pero «Santiago» dentro de «Santiago de Cuba» no aporta nada.
  if (a == s || s.contains(a)) return sucursal;
  return '$sucursal · desde $almacen';
}

/// Sin tildes, sin mayúsculas y sin espacios de sobra.
String _llano(String texto) {
  const con = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const sin = 'aaaaaeeeeiiiiooooouuuunc';
  final buf = StringBuffer();
  for (final letra in texto.trim().toLowerCase().split('')) {
    final i = con.indexOf(letra);
    buf.write(i == -1 ? letra : sin[i]);
  }
  return buf.toString();
}
