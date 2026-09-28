import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/colores.dart';
import '../diseno/tema.dart';
import '../nucleo/frescura/reloj_de_datos.dart';
import '../nucleo/proveedores.dart';
import '../nucleo/sincro/huerfanos.dart';
import '../nucleo/sincro/que_se_puede.dart';
// La UNICA cosa que `navegacion/` importa de `pantallas/`, y con motivo: la
// franja es la pieza del armazon que esta en las siete pantallas, asi que es la
// unica desde la que se puede llegar al gesto de traer el dia estando en
// Clientes o en Rutas. El cajon no puede vivir en `nucleo/` porque `nucleo/` no
// depende de `diseno/` y el cajon es todo diseno.
import '../pantallas/entregar_el_dia/vista/cajon_entregar_el_dia.dart';
import '../pantallas/traer_el_dia/vista/cajon_traer_el_dia.dart';
import 'estado_navegacion.dart';

/// LA FRANJA DE ESTADO. Arriba, a lo ancho, en las siete pantallas.
///
/// Es una franja propia y no un hueco dentro de la barra superior **a
/// proposito**: en la barra compite por sitio con el titulo, la sucursal, la
/// moneda y el avatar, y en un telefono de 390 px lo primero que se recorta es
/// lo que no cabe. Justo esto es lo que no se puede recortar (caso S8).
///
/// Y dice **la hora**, no «sin conexión». A quien despacha no le sirve saber si
/// hay senal: le sirve saber si los pedidos que esta mirando son de esta manana
/// o de anteayer, porque de eso depende si arma la ruta de hoy o la de ayer.
class FranjaDeEstado extends ConsumerWidget {
  const FranjaDeEstado({this.alPulsarPendientes, super.key});

  final VoidCallback? alPulsarPendientes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bajada = ref.watch(frescuraGlobalProvider);
    final sinSubir = ref.watch(sinSubirProvider);
    final ahora = ref.watch(relojProvider)();
    // SI NO HAY CONEXION, SE DICE AQUI. Esta franja esta en las siete pantallas;
    // la tarjeta del Panel solo en una, y quien esta armando una ruta no la ve.
    //
    // No sale de si el aparato cree que hay wifi, sino de si las peticiones
    // llegan (`nucleo/red/salud.dart`): en Cuba el telefono ensena el wifi
    // conectado y no sale un paquete, que es exactamente lo que pasaba en el
    // Galaxy A16 del 16/09.
    final sinConexion = ref.watch(saludDeLaRedProvider).vaMal;
    // El giro de «actualizando» vive AQUI en el telefono: arriba no cabe y se
    // pintaba debajo del selector de sucursal. Y este es su sitio natural —la
    // franja es la pieza que habla del estado de los datos—, con la hora al
    // lado, que es lo que hace falta saber.
    final actualizando = ref.watch(actualizandoProvider);
    // LO QUE ESTA AQUI Y NO ARRIBA, Y NO LO VA A SUBIR NADIE.
    //
    // Es el caso que no revienta: una ruta armada sin señal cuyo apunte se
    // perdio no sale en «<n> sin subir» —no le queda apunte—, ni en la bandeja
    // —no la rechazo nadie—, ni en el Panel. Se veia en su pantalla y punto.
    // Aqui se dice, al lado de lo que si esta sin subir, que es donde ya se
    // mira. Ver `nucleo/sincro/huerfanos.dart`.
    final huerfano =
        ref.watch(trabajoHuerfanoProvider).value ?? const <TrabajoHuerfano>[];
    // Y LA BAJADA QUE VOLVIO A MEDIAS, con el motivo del servidor tal cual.
    final aMedias = ref.watch(bajadaAMediasProvider);
    // LO QUE SUBIO Y SALIO CON MENOS DE LO QUE SE PUSO.
    //
    // El tercer caso que no revienta, y el que estuvo mudo hasta el
    // 28/09/2026: el apunte de armar una zona entra, la ruta se crea arriba, y
    // el servidor contesta ademas quien se cayo y por que. Eso no sale en «N
    // sin subir» —ya subio— ni en la bandeja —no lo rechazo nadie—, y el
    // apunte pudo entrar horas despues con la pantalla cerrada: si no se dice
    // aqui, no se dice en ningun sitio. Ver `nucleo/cola/cola_salida.dart`,
    // `descartesSinLeer`.
    final descartados = ref.watch(descartadosProvider).value ?? const [];

    // Mientras la consulta de frescura no ha contestado NO se dice «sin
    // descargar»: seria acusar de vacio a algo que aun no se ha mirado. Se
    // espera, que dura un fotograma.
    final estado = bajada.hasValue
        ? EstadoFrescura.de(bajada.value, ahora: ahora)
        : null;

    final pendientes = sinSubir.value ?? 0;
    final enAmbar = estado?.enAmbar ?? false;

    // LA FRANJA ES PULSABLE y lleva al gesto de traer el dia.
    //
    // Es la segunda puerta, y la que hace que el gesto exista tambien en las
    // otras seis pantallas: quien esta armando una ruta y ve «Datos de hace 9 h»
    // tiene que poder darle ahi mismo, sin aprenderse que hay que volver al
    // Panel. El sitio donde se lee que los datos estan viejos es el sitio donde
    // se arregla.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => abrirCajonDeTraerElDia(context),
        child: _pintar(
          context,
          estado: estado,
          pendientes: pendientes,
          // Sin conexion la franja se pone en ambar aunque los datos sean de
          // hace un minuto: lo que hay que mirar entonces no es la hora. Con
          // trabajo huerfano o con una bajada a medias, igual: los dos son
          // «mira esto», y los dos pueden pasar con la hora en verde.
          enAmbar:
              enAmbar ||
              sinConexion ||
              huerfano.hayAlguno ||
              aMedias != null ||
              descartados.isNotEmpty,
          sinConexion: sinConexion,
          actualizando: actualizando,
          huerfano: huerfano,
          aMedias: aMedias,
          descartados: descartados.length,
          // Que se puede hacer ahora mismo. Las reglas viven en
          // `sincro/que_se_puede.dart`, no aqui: son de negocio y las mira
          // tambien la tarjeta del Panel.
          puede: quePuedeHacerse(
            hayConexion: !sinConexion,
            hayQueTraer: enAmbar,
          ),
        ),
      ),
    );
  }

  Widget _pintar(
    BuildContext context, {
    required EstadoFrescura? estado,
    required int pendientes,
    required bool enAmbar,
    required bool sinConexion,
    required bool actualizando,
    required List<TrabajoHuerfano> huerfano,
    required String? aMedias,
    required int descartados,
    required QueSePuede puede,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Aire.lg, vertical: 6),
      decoration: BoxDecoration(
        // En calma es el propio papel, un punto mas oscuro: la franja tiene que
        // estar SIEMPRE, pero cuando no hay nada que decir no debe pedir la
        // vista. En ambar si, porque entonces si la pide.
        color: enAmbar ? Colores.ambarFondo : Colores.grisFondo,
        border: Border(
          bottom: BorderSide(
            color: enAmbar
                ? Colores.ambar.withValues(alpha: 0.25)
                : Colores.linea,
          ),
        ),
      ),
      child: Row(
        children: [
          // EL GIRO NO SALE SI YA SABEMOS QUE NO HAY CONEXION.
          //
          // El ciclo sigue reintentando por detras —y eso esta bien, es lo que
          // hace que suba solo en cuanto vuelva la senal—, pero un giro al lado
          // de «Sin conexion» se contradice: uno dice «esto avanza» y el otro
          // dice «no hay por donde». Jose, el 16/09/2026: «ya dice sin conexion
          // el cartel pero el loading sigue funcionando por q razon sigue
          // saliendo ahi eso esta bien???». No lo estaba.
          //
          // Manda la nube tachada, que es lo cierto.
          //
          // El giro SUSTITUYE al reloj mientras dura: son lo mismo —de cuando
          // son los datos— y dos iconos a la vez en 390 px es ruido.
          if (actualizando && !sinConexion)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: enAmbar ? Colores.ambar : Colores.tintaSuave,
              ),
            )
          else
            Icon(
              sinConexion
                  ? Icons.cloud_off_outlined
                  : (enAmbar ? Icons.schedule : Icons.schedule_outlined),
              size: 14,
              color: enAmbar ? Colores.ambar : Colores.tintaSuave,
            ),
          const SizedBox(width: 6),
          // «Sin conexión» va DELANTE de la hora y no detrás: es lo que cambia
          // lo que se puede hacer ahora mismo. La hora sigue estando porque las
          // dos cosas importan, y el `FittedBox` de al lado encoge la letra en
          // vez de recortar por la derecha.
          if (sinConexion) ...[
            Text(
              'Sin conexión',
              style: Tipos.texto(
                tamano: 12,
                peso: FontWeight.w700,
                color: Colores.ambar,
              ),
            ),
            Text('  ·  ', style: Tipos.texto(tamano: 12, color: Colores.ambar)),
          ],
          // LA COLUMNA: la hora arriba y, DEBAJO, lo que no puede compartir
          // renglon con ella.
          //
          // Los dos avisos de abajo son raros y graves, y ninguno cabe en la
          // misma linea que la hora en un telefono de 390 px: encogidos por el
          // `FittedBox` se quedarian en letra de seis puntos, que es no
          // decirlos. Cuando no hay ninguno **no ocupan un pixel**, asi que la
          // franja sigue siendo una franja, que es la regla del caso S8.
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (estado != null)
                  // `FittedBox` y no un recorte: en un telefono estrecho, con la
                  // hora y «<n> sin subir` a la vez, el texto no cabe — y aqui no
                  // se puede cortar nada, porque las dos mitades son el aviso. Se
                  // encoge la letra, que sigue leyendose, en vez de perder media
                  // franja por la derecha.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: RelojDeDatos(
                      estado: estado,
                      sinSubir: pendientes,
                      // «<n> sin subir» lleva al gesto que lo arregla, que es
                      // entregar el dia. El numero y el boton que lo baja a
                      // cero tienen que estar a un dedo el uno del otro: quien
                      // lee «23 sin subir» en la pantalla de Rutas no tiene por
                      // que aprenderse que hay que volver al Panel.
                      alPulsarPendientes:
                          alPulsarPendientes ??
                          () => abrirCajonDeEntregarElDia(context),
                    ),
                  ),
                // TRABAJO QUE NO VA A SUBIR SOLO. Se NOMBRA lo que es —«1
                // ruta», «2 vehículos»— porque «3 cosas» no le dice a nadie
                // donde mirar, y lleva al mismo cajon que «<n> sin subir»: es
                // la misma pregunta, «¿que me queda por entregar?», y alli
                // esta la explicacion entera.
                if (huerfano.hayAlguno)
                  _Linea(
                    texto: 'Sólo en este aparato: ${huerfano.texto}',
                    alPulsar:
                        alPulsarPendientes ??
                        () => abrirCajonDeEntregarElDia(context),
                  ),
                // LA BAJADA QUE SE QUEDO A MEDIAS, con su motivo literal. Lleva
                // al gesto que la arregla, que es traer el dia otra vez.
                if (aMedias != null)
                  _Linea(
                    texto: 'Faltan datos por bajar: $aMedias',
                    alPulsar: () => abrirCajonDeTraerElDia(context),
                  ),
                // LA RUTA QUE SUBIO CON MENOS DE LO QUE SE PUSO. Aqui va el
                // NUMERO y no los motivos: los motivos son largos —llevan el
                // pedido, el porque y que hacer— y su sitio es el cajon, que
                // es adonde lleva esto. Lo que tiene que hacer esta linea es
                // que alguien lo abra.
                if (descartados > 0)
                  _Linea(
                    texto: descartados == 1
                        ? 'Una ruta subió con menos pedidos de los que pusiste'
                        : '$descartados rutas subieron con menos pedidos de '
                              'los que pusiste',
                    alPulsar:
                        alPulsarPendientes ??
                        () => abrirCajonDeEntregarElDia(context),
                  ),
              ],
            ),
          ),
          // LOS DOS GESTOS, A LA VISTA Y SEPARADOS.
          //
          // Antes aqui habia UN icono de 15 px y nada mas: traer el dia se
          // pulsaba tocando la franja entera, y entregarlo tocando el numero de
          // «<n> sin subir». Las dos cosas funcionaban y ninguna se veia. Jose,
          // el 16/09/2026: «necesito tambien via rapida para enviar los datos y
          // los recibirlos q tengo q ir a panel y revisarlos por ahi».
          //
          // Y habia un hueco de verdad: **sin nada pendiente no habia forma de
          // subir**. El numero era la unica puerta a entregar el dia, y cuando
          // marcaba cero desaparecia. Quien acaba de cerrar una ruta y quiere
          // asegurarse de que subio no tenia donde darle.
          //
          // Dos botones con su tooltip y su area de dedo. Caben en 390 px
          // porque sustituyen al icono suelto, y el numero de pendientes va
          // ENCIMA del de subir, que es donde significa algo.
          const SizedBox(width: 4),
          _BotonDeFranja(
            icono: Icons.cloud_download_outlined,
            // Apagado, el tooltip dice POR QUE. Un boton apagado y mudo ensena
            // a desconfiar de todos los botones.
            tooltip: puede.traer.motivo ?? 'Traer el día',
            enAmbar: enAmbar,
            alPulsar: puede.traer.sePuede
                ? () => abrirCajonDeTraerElDia(context)
                : null,
          ),
          _BotonDeFranja(
            icono: Icons.cloud_upload_outlined,
            tooltip:
                puede.enviar.motivo ??
                (pendientes > 0
                    ? 'Entregar el día · $pendientes sin subir'
                    : 'Entregar el día'),
            enAmbar: enAmbar,
            insignia: pendientes,
            alPulsar: puede.enviar.sePuede
                ? (alPulsarPendientes ??
                      () => abrirCajonDeEntregarElDia(context))
                : null,
          ),
        ],
      ),
    );
  }
}

/// UNA LINEA DE AVISO debajo de la hora: ambar, pulsable y entera.
///
/// `maxLines: 2` y `ellipsis` y no un `FittedBox`: estos textos llevan dentro el
/// motivo literal del servidor —«se llego al tope de 20 tandas y el servidor
/// seguia diciendo que queda mas»— y encogerlo hasta que quepa en un renglon es
/// dejarlo ilegible. Se lee lo que cabe y se abre el cajon, que lo dice entero.
class _Linea extends StatelessWidget {
  const _Linea({required this.texto, required this.alPulsar});

  final String texto;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: alPulsar,
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 1),
        child: Text(
          texto,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Tipos.texto(
            tamano: 12,
            peso: FontWeight.w600,
            color: Colores.ambar,
          ),
        ),
      ),
    );
  }
}

/// Un boton de la franja: icono, tooltip y area de dedo, sin robarle alto.
///
/// `IconButton` a secas mide 48 px y doblaria la altura de la franja, que vive
/// en las siete pantallas y no puede engordar. Se le quita el relleno y se le
/// pone un area propia de 40x32: suficiente para un dedo, sin que la franja deje
/// de ser una franja.
class _BotonDeFranja extends StatelessWidget {
  const _BotonDeFranja({
    required this.icono,
    required this.tooltip,
    required this.enAmbar,
    required this.alPulsar,
    this.insignia = 0,
  });

  final IconData icono;
  final String tooltip;
  final bool enAmbar;

  /// `null` = apagado. El motivo va en [tooltip].
  final VoidCallback? alPulsar;

  /// Cuantos apuntes esperan. En cero no se pinta nada: un globo con un cero
  /// dentro es ruido que ensena a no mirar los globos.
  final int insignia;

  @override
  Widget build(BuildContext context) {
    // Apagado se pinta en gris, no se esconde: el gesto sigue estando en su
    // sitio, y asi se aprende que existe y cuando se enciende.
    final color = alPulsar == null
        ? Colores.lineaFuerte
        : (enAmbar ? Colores.ambar : Colores.tintaSuave);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: alPulsar,
        borderRadius: BorderRadius.circular(Radios.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 8),
              Icon(icono, size: 17, color: color),
              if (insignia > 0) ...[
                const SizedBox(width: 3),
                Text(
                  '$insignia',
                  style: Tipos.texto(
                    tamano: 11,
                    peso: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
