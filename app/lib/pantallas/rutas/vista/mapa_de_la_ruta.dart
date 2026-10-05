// EL BLOQUE DEL MAPA dentro del detalle de una ruta: el croquis, la linea que
// DICE lo que se esta viendo, lo que se queda fuera, y los cuatro gestos —abrir
// en Google Maps, WhatsApp, compartir y copiar.
//
// Jose, 17/09/2026: «El mapa, ¿por qué no me sale el mapa con la ruta, si
// teníamos hasta para compartir la ruta por WhatsApp?». Tenia razon en las dos
// mitades: el mapa no se porto del Next, y de compartir solo habia medio gesto
// (un boton que copiaba el enlace al portapapeles y ya).
//
// ## La linea que DICE lo que se esta viendo
//
// El mapa tiene dos capas y la de arriba puede no llegar (`croquis_de_ruta.dart`
// lo cuenta entero): con señal se ven las calles de verdad y el recorrido por
// carretera; sin ella, el croquis con las paradas en su orden y la linea recta.
// **Las dos cosas son un mapa util, pero no son el mismo mapa**, y quien lo mira
// tiene que saber cual tiene delante sin compararlo con nada.
//
// Y la frase del caso sin calles no puede ser la misma en los tres destinos:
//
//  * en la **APK y el escritorio** lo importante es que el croquis sale de lo
//    que **ya esta en el aparato**, asi que el chofer lo ve igual en la calle:
//    es la promesa del proyecto;
//  * en la **web** eso no le explica nada a nadie. Quien abre un navegador tiene
//    internet, siempre (`CLAUDE.md` §1): si ahi no hay calles es que el fondo no
//    cargo, no que se haya quedado sin cobertura. Contarle lo del aparato seria
//    explicarle algo que en su caso no pasa nunca.
//
// **Esa es la unica diferencia entre la web y el aparato en todo este bloque**,
// y no hay ninguna otra a proposito.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart' show BotonPrincipal;
import '../../../mapa/proveedores_de_mapa.dart';
import '../../../nucleo/plataforma.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../mapa/registro.dart';
import '../../pedidos/datos/formato.dart';
import '../datos/abrir_y_compartir.dart';
import '../datos/enlace_de_la_ruta.dart';
import '../datos/mapa_en_vivo.dart';
import '../datos/recorrido.dart';
import '../datos/repositorio_rutas.dart';
import 'croquis_de_ruta.dart';

/// LAS FRASES, con nombre y publicas.
///
/// Con nombre porque la prueba tiene que poder decir «sale ESTA y no sale la
/// otra» sin copiar la cadena: una prueba que repite el texto del codigo no
/// comprueba el texto, comprueba que sabe copiar (`CLAUDE.md` §5).
abstract final class TextosDelMapa {
  /// Con las calles puestas no hay nada que explicar sobre la señal: se ve lo
  /// que se espera ver.
  static const conCalles = 'Mapa de calles.';

  /// Sin calles, en la APK y el escritorio.
  // CORTAS, las cuatro. Jose, 17/09/2026: «sin tanto texto». El patrón no
  // escribe ni una línea debajo del mapa; aquí se dice sólo lo que cambia el
  // diagnóstico —si son calles o croquis, y si el recorrido es real o recto—
  // porque sin eso una línea recta se lee como la ruta de verdad.
  static const croquisEnElAparato =
      'Sin señal: croquis con las coordenadas del aparato.';

  /// Sin calles, en el navegador. Ni una palabra sobre la cobertura: si la
  /// página cargó, conexión hay, y lo que falló fue el fondo del mapa.
  static const croquisEnLaWeb =
      'El mapa de calles no cargó: esto es el croquis.';

  static const recorridoPorCarretera = 'Recorrido por las calles.';

  /// La linea recta, que es a lo que cae tambien el patron cuando su servicio de
  /// rutas no contesta.
  static const recorridoAproximado = 'Recorrido aproximado, en línea recta.';

  /// Lo que vale en los cuatro casos. **Vacío a propósito**: lo que decía —que
  /// las paradas van numeradas y que Google Maps navega— ya lo dicen la leyenda
  /// y el botón que está justo debajo.
  static const siempre = '';

  /// LA FRASE ENTERA. Se arma de trozos y no se escriben las cuatro a mano: con
  /// cuatro frases sueltas, cambiar «paradas» por «puntos» deja tres bien y una
  /// mal, y la que se queda mal es la que nadie vuelve a leer.
  /// **CUANDO TODO VA BIEN, NO SE DICE NADA.**
  ///
  /// Jose, 17/09/2026: «hay varios botones que están cortados; podríamos quitar
  /// ese texto y que quepan ahí sin necesidad de tener scroll en esa vista».
  ///
  /// Y es lo correcto además de por el sitio: «Mapa de calles. Recorrido por
  /// las calles» describe lo que se está viendo, que ya se ve. El patrón no
  /// escribe ni una línea debajo del mapa.
  ///
  /// Lo que sí se sigue diciendo es lo que **cambia el diagnóstico**: que esto
  /// es el croquis y no las calles, o que el recorrido es una línea recta y no
  /// el camino de verdad. Sin eso, una recta se lee como la ruta buena y los
  /// kilómetros de la cabecera parecen los del camión.
  static String queSeEstaViendo(QueSeVe que, {required bool enElAparato}) {
    if (que.conCalles && que.recorridoPorCarretera) return '';
    return _armar(que, enElAparato: enElAparato);
  }

  static String _armar(QueSeVe que, {required bool enElAparato}) => [
    que.conCalles
        ? conCalles
        : enElAparato
        ? croquisEnElAparato
        : croquisEnLaWeb,
    que.recorridoPorCarretera ? recorridoPorCarretera : recorridoAproximado,
    siempre,
  ].where((t) => t.isNotEmpty).join(' ');

  /// Cuando abrir Google Maps no sale. **Nombra el motivo**, que es la regla de
  /// la casa: «no se pudo» no le dice a nadie que hacer.
  static const noSeAbrio =
      'No se pudo abrir Google Maps. Hace falta señal y una aplicación que abra '
      'enlaces; mientras tanto, «Copiar» deja el enlace en el portapapeles.';

  static const noSeCompartio =
      'Este aparato no ofreció ningún modo de compartir. Con «Copiar» el enlace '
      'queda en el portapapeles.';

  static const noSeAbrioWhatsApp =
      'No se pudo abrir WhatsApp. Comprueba que está instalado; mientras tanto, '
      '«Copiar» deja el mensaje en el portapapeles.';

  static const copiado = 'Copiado. Ya se puede pegar en un chat.';
}

/// Las claves con las que la prueba pulsa. Publicas y por nombre: buscarlas por
/// el texto del boton ataria la prueba a como se llama hoy.
const claveDeAbrirEnGoogleMaps = ValueKey('mapa-abrir-en-google-maps');
const claveDeWhatsApp = ValueKey('mapa-compartir-por-whatsapp');
const claveDeCompartir = ValueKey('mapa-compartir-con-el-sistema');
const claveDeCopiar = ValueKey('mapa-copiar-el-mensaje');
const claveDeSinRecorrido = ValueKey('mapa-sin-recorrido');
const claveDeLoQueQuedaFuera = ValueKey('mapa-lo-que-queda-fuera');

class MapaDeLaRuta extends ConsumerStatefulWidget {
  const MapaDeLaRuta({required this.ruta, super.key});

  final RutaConTodo ruta;

  @override
  ConsumerState<MapaDeLaRuta> createState() => _MapaDeLaRutaState();
}

class _MapaDeLaRutaState extends ConsumerState<MapaDeLaRuta> {
  /// Se arranca dando por hecho que NO hay calles ni recorrido por carretera.
  ///
  /// Al reves seria mentir durante el segundo que tardan en llegar —y para
  /// siempre si no llegan, que es el caso de la calle—. Una pantalla que empieza
  /// prometiendo lo que todavia no tiene es la misma familia de fallo que un
  /// «Todo en verde» antes de comprobar nada.
  QueSeVe _queSeVe = (conCalles: false, recorridoPorCarretera: false);

  @override
  Widget build(BuildContext context) {
    final recorrido = recorridoDe(widget.ruta);
    final enlace = enlaceDeLaRuta(recorrido);
    final enElAparato = ref.watch(trabajaSinConexionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recorrido',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        // NUNCA UN CUADRO GRIS. O el mapa, o un recuadro que dice por que no hay
        // mapa. Es lo mismo que hace el patron con su `routes.noGps`.
        if (recorrido.hayAlgoQueDibujar)
          CroquisDeRuta(
            recorrido: recorrido,
            fondo: ref.watch(fondoDeCallesProvider),
            porCalles: ref.watch(recorridoPorCallesProvider),
            onQueSeVe: (que) {
              if (mounted && que != _queSeVe) setState(() => _queSeVe = que);
            },
          )
        else
          _SinRecorrido(recorrido: recorrido),

        // Sin frase, ni el hueco de la frase: un `SizedBox` de 8 px encima de
        // un `Text` vacío sigue empujando los botones hacia abajo, que es lo
        // que se venía a arreglar.
        if (TextosDelMapa.queSeEstaViendo(
          _queSeVe,
          enElAparato: enElAparato,
        ).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            TextosDelMapa.queSeEstaViendo(_queSeVe, enElAparato: enElAparato),
            style: TextStyle(fontSize: 11, color: Colores.gris),
          ),
        ],

        // SIN MAPA DESCARGADO, SE DICE Y SE OFRECE BAJARLO.
        //
        // Jose, 21/09/2026, con el avión puesto y el croquis a secas delante:
        // «y por qué sin conexión no tenía el mapa, pon un mensaje que salga
        // ahí la opción de que se descargue el mapa». Tenía razón: la pantalla
        // decía «se ve igual sin señal» y no decía lo único que hay que hacer
        // para que eso sea verdad.
        //
        // Sale **sólo en la APK y el escritorio** (regla 1: en la web no existe
        // el aparato de sin-conexión) y **sólo si no hay paquete**. Con el mapa
        // ya bajado no se dice nada: un aviso que sale siempre deja de leerse.
        if (enElAparato &&
            ref.watch(paqueteGuardadoProvider).value == null) ...[
          const SizedBox(height: 8),
          _SinMapaDescargado(),
        ],

        // LO QUE NO VIAJA EN EL ENLACE, con su numero y su motivo. El comentario
        // que traia el patron vale palabra por palabra: un enlace que se come
        // cinco paradas en silencio manda al chofer a dar media vuelta.
        if (enlace.loQueQuedaFuera != null) ...[
          const SizedBox(height: 6),
          _Aviso(key: claveDeLoQueQuedaFuera, texto: enlace.loQueQuedaFuera!),
        ],

        // Y si NO HAY enlace, se dice por que, aunque el mapa se vea bien: son
        // dos cosas distintas y fallan por separado.
        if (!enlace.hay) ...[
          const SizedBox(height: 6),
          _Aviso(texto: enlace.motivo!),
        ],

        const SizedBox(height: 10),
        _Acciones(ruta: widget.ruta, enlace: enlace),
      ],
    );
  }
}

/// Cuando no hay ni una coordenada: **un recuadro que lo dice**, no un hueco.
class _SinRecorrido extends StatelessWidget {
  const _SinRecorrido({required this.recorrido});

  final Recorrido recorrido;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: claveDeSinRecorrido,
    decoration: BoxDecoration(
      color: Colores.grisFondo,
      border: Border.all(color: Colores.linea),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        recorrido.paradas.isEmpty
            ? 'Esta ruta todavía no tiene paradas, así que no hay recorrido que '
                  'dibujar.'
            : 'No se puede dibujar el recorrido: ni el almacén de salida ni '
                  'ninguna de las ${recorrido.paradas.length} paradas tiene '
                  'coordenadas guardadas.',
        style: TextStyle(fontSize: 12, color: Colores.gris),
      ),
    ),
  );
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colores.ambarFondo,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(texto, style: TextStyle(fontSize: 11, color: Colores.tinta)),
    ),
  );
}

class _Acciones extends ConsumerWidget {
  const _Acciones({required this.ruta, required this.enlace});

  final RutaConTodo ruta;
  final EnlaceDeLaRuta enlace;

  /// El texto que se manda. Se arma una sola vez y lo usan los tres gestos, para
  /// que el chofer reciba lo mismo venga por donde venga.
  String get _mensaje {
    final r = ruta.ruta;
    final vehiculo = ruta.vehiculo;
    return mensajeParaElChofer(
      titulo: [
        'Ruta ${r.routeCode ?? r.id}',
        if (r.name != null) r.name!,
      ].join(' — '),
      resumen: [
        EnlaceDeLaRuta.cuantasParadas(ruta.paradas.length),
        '${r.totalDistance.toStringAsFixed(1)} km (incl. regreso)',
        if (vehiculo != null)
          vehiculo.plate == null
              ? vehiculo.name
              : '${vehiculo.name} (${vehiculo.plate})',
        fechaCorta(r.deliveryDate),
      ].join(' · '),
      enlace: enlace,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aparato = ref.watch(abrirYCompartirProvider);
    final mensajero = ScaffoldMessenger.maybeOf(context);

    void decir(String texto) => mensajero?.showSnackBar(
      SnackBar(content: Text(texto), duration: const Duration(seconds: 5)),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // ABRIR EN GOOGLE MAPS. Es el unico que se apaga sin enlace: no hay nada
        // que abrir. Los otros tres siguen sirviendo, porque un mensaje que dice
        // «esta ruta no tiene coordenadas del almacen» le sirve al chofer para
        // llamar a la oficina, y un boton muerto no le sirve para nada.
        ControlSenalado(
          nombre: Senalado.rutasAbrirEnGoogleMaps,
          child: FilledButton.icon(
            key: claveDeAbrirEnGoogleMaps,
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Abrir en Google Maps'),
            onPressed: !enlace.hay
                ? null
                : () async {
                    if (!await aparato.abrir(Uri.parse(enlace.url!))) {
                      decir(TextosDelMapa.noSeAbrio);
                    }
                  },
          ),
        ),
        ControlSenalado(
          nombre: Senalado.rutasWhatsApp,
          child: OutlinedButton.icon(
            key: claveDeWhatsApp,
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: const Text('WhatsApp'),
            onPressed: () async {
              if (!await aparato.abrir(enlaceDeWhatsApp(_mensaje))) {
                decir(TextosDelMapa.noSeAbrioWhatsApp);
              }
            },
          ),
        ),
        ControlSenalado(
          nombre: Senalado.rutasCompartir,
          child: OutlinedButton.icon(
            key: claveDeCompartir,
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('Compartir'),
            onPressed: () async {
              if (!await aparato.compartir(
                texto: _mensaje,
                asunto: 'Ruta ${ruta.ruta.routeCode ?? ruta.ruta.id}',
              )) {
                decir(TextosDelMapa.noSeCompartio);
              }
            },
          ),
        ),
        ControlSenalado(
          nombre: Senalado.rutasCopiar,
          child: OutlinedButton.icon(
            key: claveDeCopiar,
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('Copiar'),
            onPressed: () async {
              if (await aparato.copiar(_mensaje)) decir(TextosDelMapa.copiado);
            },
          ),
        ),
      ],
    );
  }
}

/// «No tienes el mapa de Cuba» + el botón que lleva a bajarlo.
///
/// Es un aviso con salida, no un cartel: el croquis funciona sin el mapa —las
/// paradas, su orden y el recorrido se dibujan igual—, así que esto no bloquea
/// nada. Lo que hace es contar que **las calles de fondo se bajan una vez** y
/// llevar allí de un toque, en vez de dejar a alguien buscando en el menú.
class _SinMapaDescargado extends StatelessWidget {
  const _SinMapaDescargado();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colores.ambarFondo,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colores.ambar.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        Icon(Icons.map_outlined, size: 18, color: Colores.ambar),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Sin el mapa de Cuba descargado, aquí sólo se dibujan las paradas y '
            'el recorrido. Se baja una vez y se queda en el aparato.',
            style: TextStyle(fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        BotonPrincipal(
          icono: Icons.download_outlined,
          texto: 'Descargar',
          alPulsar: () => context.go(caminoDelMapaSinConexion),
        ),
      ],
    ),
  );
}
