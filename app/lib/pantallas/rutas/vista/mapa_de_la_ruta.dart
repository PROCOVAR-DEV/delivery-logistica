// EL BLOQUE DEL MAPA dentro del detalle de una ruta: el croquis y la linea que
// DICE lo que se esta viendo.
//
// Los gestos de mandar la ruta (antes: abrir en Google Maps, WhatsApp, compartir y
// copiar) ya no estan aqui: ahora la ruta se manda al distribuidor con su enlace,
// en `distribucion/vista/enviar_a_distribuidor.dart`.
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
import '../../mapa/registro.dart';
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
}

/// La clave con la que la prueba encuentra el recuadro de «sin recorrido».
const claveDeSinRecorrido = ValueKey('mapa-sin-recorrido');

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
