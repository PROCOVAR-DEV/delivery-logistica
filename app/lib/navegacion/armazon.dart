import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/anchos.dart';
import '../nucleo/base/base.dart';
import '../nucleo/plataforma.dart';
import 'aviso_de_version_nueva.dart';
import 'barra_lateral.dart';
import 'barra_superior.dart';
import 'franja_de_estado.dart';
import 'menu_de_cuenta.dart';
import 'pantalla_registrada.dart';

/// EL ARMAZON COMUN de todas las pantallas.
///
/// De arriba abajo y siempre en el mismo orden:
///
///   barra superior (64 px)  ← titulo, menu en movil, sucursal, moneda, avatar
///   AVISO DE VERSION NUEVA  ← solo cuando la hay; recargar en web, instalar en
///                             el aparato
///   FRANJA DE ESTADO        ← de que hora son los datos y cuantos sin subir
///   la pantalla
///
/// La franja va **debajo** de la barra y no dentro: asi sobrevive a los 390 px
/// de un telefono, donde dentro de la barra seria lo primero en recortarse. Y es
/// justo lo que no puede faltar (caso S8).
///
/// ## …en la APK y en el escritorio. En web NO va — 15/09/2026
///
/// La franja contesta «¿de que hora son estos datos?», y esa pregunta solo tiene
/// sentido donde los datos pueden ser de anteayer: el logistico baja el dia por
/// la mannana y se va al almacen sin cobertura, y sin la franja arma la ruta de
/// ayer convencido de que es la de hoy. En un navegador con internet la
/// respuesta es siempre «de hace un momento», asi que la franja gasta sitio
/// arriba de las siete pantallas para decir algo que nunca cambia — y, peor,
/// **ensena que aqui hay un dia que traer a mano**, que es lo que en web no
/// existe. Es ademas la puerta a los dos cajones de traer y entregar el dia, que
/// tampoco pintan nada alli.
///
/// Lo que se quita es el aparato de PREPARARSE para no tener conexion, no el
/// aviso de que ahora mismo no la hay: si la web pierde la red a mitad, eso
/// sigue saliendo por su sitio de siempre (ver el informe).
///
/// ## El aviso de version nueva va AQUI, y en los TRES destinos
///
/// Es la unica pieza del armazon que sale tambien en la web, y no es una
/// excepcion a §1 sino su caso mas claro: la web es justo donde una pestaña
/// lleva abierta desde ayer con el paquete de anteayer, y ahi lo que hace falta
/// es **recargar** —dos segundos, sin nada que perder, porque la web no tiene ni
/// copia ni cola—. Lo que cambia por destino es el mensaje y el gesto, no si
/// existe; eso lo decide `aviso_de_version_nueva.dart`, que es el unico sitio
/// donde se mira.
///
/// Va en el armazon y no en una pantalla por lo mismo que el patron lo mete en
/// su `layout.tsx`: quien tiene la version vieja la tiene abierta en la pantalla
/// en la que trabaja, no en la que se acuerde de visitar. **La puerta
/// (`/acceso`) queda fuera**, porque va sin armazon — y esta bien: alli todavia
/// no hay nada que perder ni nada a medias, y el aviso sale en cuanto se entra.
///
class Armazon extends ConsumerWidget {
  const Armazon({
    required this.pantallas,
    required this.rutaActual,
    required this.child,
    super.key,
  });

  final List<PantallaRegistrada> pantallas;
  final String rutaActual;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ancho = MediaQuery.sizeOf(context).width;
    final esEscritorio = ancho >= Anchos.escritorio;
    final hayDiaQueTraer = ref.watch(trabajaSinConexionProvider);

    final actual = pantallas.firstWhereOrNull((p) => p.ruta == rutaActual);
    final titulo = actual?.titulo ?? '';

    // QUIEN MIRA, para esconder del menu lo que no le toca. Se mira por `.value`
    // y no se espera: mientras la sesion se lee, las entradas con rol no salen y
    // aparecen al resolver —esto se repinta—. No es un permiso; el cerrojo lo
    // pone la api con un 403. Ver `PantallaRegistrada.soloParaRoles`.
    final quienMira = ref.watch(sesionParaElMenuProvider).value;

    return Scaffold(
      // En movil la barra lateral vive en el cajon del Scaffold: fuera de
      // pantalla, con velo, y pulsar fuera cierra (§8.1).
      drawer: esEscritorio
          ? null
          : Drawer(
              width: Anchos.barraLateral,
              child: BarraLateral(
                pantallas: pantallas,
                rutaActual: rutaActual,
                quienMira: quienMira,
                dentroDeCajon: true,
              ),
            ),
      // SAFEAREA. LA BARRA DE ARRIBA NO PUEDE METERSE DEBAJO DEL RELOJ.
      //
      // Este `Scaffold` no lleva `appBar` —la barra la pinta [BarraSuperior]
      // dentro del cuerpo—, y sin `appBar` el cuerpo empieza en el pixel cero
      // de la pantalla: por debajo del reloj, del wifi y de la bateria.
      //
      // En un navegador no se nota, porque ahi el cero es el borde de la
      // pestana. En un telefono se nota mucho: el 16/09/2026, en un Galaxy A16,
      // el selector de sucursal y el conmutador de moneda quedaron TAPADOS por
      // la hora y los iconos del sistema, y no habia forma de pulsarlos. No es
      // que se viera feo — es que la mitad de la barra no se podia tocar.
      //
      // Por eso va aqui y no dentro de [BarraSuperior]: lo que hay que apartar
      // es el cuerpo entero, incluida la franja de estado y las pantallas, no
      // solo la barra. El cajon lateral tiene el suyo propio
      // (`barra_lateral.dart`) porque vive fuera de este arbol.
      //
      // El `Builder` de dentro no es adorno: `Scaffold.of` necesita un contexto
      // POR DEBAJO del Scaffold. Con el contexto de `build` el boton de menu no
      // encuentra ningun cajon y revienta al pulsarlo.
      body: SafeArea(
        child: Builder(
          builder: (contexto) {
            final columna = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BarraSuperior(
                  titulo: titulo,
                  // En escritorio no hay boton de menu: la barra lateral esta
                  // fija y un boton que no abre nada ensena a desconfiar.
                  alAbrirMenu: esEscritorio
                      ? null
                      : () => Scaffold.of(contexto).openDrawer(),
                ),
                // ENCIMA DE LA FRANJA DE ESTADO, y sin `if`: el aviso decide
                // por si mismo si tiene algo que decir en este destino, y casi
                // siempre no tiene nada y no ocupa un pixel. Arriba del todo
                // porque cuando sale es mas importante que la hora de los
                // datos: con la version vieja, la hora puede estar bien y la
                // pantalla seguir mintiendo.
                const AvisoDeVersionNueva(),
                // LA FRANJA SE MIDE CONTRA LO QUE ESTA PANTALLA USA, no
                // contra la copia entera. El armazon es el unico que sabe en
                // que pantalla estamos, asi que es el que se lo pasa; el porque
                // entero, en `FranjaDeEstado.colecciones`.
                //
                // Una ruta que no esta en el registro —no deberia haberla— se
                // queda con las nueve, que es la medida mas vieja posible y por
                // tanto el lado seguro.
                if (hayDiaQueTraer)
                  FranjaDeEstado(
                    colecciones: actual?.colecciones ?? Colecciones.todas,
                  ),
                Expanded(child: child),
              ],
            );

            if (!esEscritorio) return columna;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BarraLateral(
                  pantallas: pantallas,
                  rutaActual: rutaActual,
                  quienMira: quienMira,
                ),
                Expanded(child: columna),
              ],
            );
          },
        ),
      ),
    );
  }
}
