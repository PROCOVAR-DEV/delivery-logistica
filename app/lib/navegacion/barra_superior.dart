import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/anchos.dart';
import '../diseno/colores.dart';
import '../diseno/numeros.dart';
import '../diseno/selector.dart';
import '../diseno/tema.dart';
import '../nucleo/base/base.dart';
import '../nucleo/proveedores.dart';
import 'estado_navegacion.dart';
import 'menu_de_cuenta.dart';

/// La barra superior: 64 px, pegajosa arriba (pliego §8.2).
///
/// Izquierda: boton de menu **solo en movil**, titulo de la pantalla y
/// `actualizando…` con el giro mientras haya cualquier consulta en vuelo.
/// Derecha: sucursal, moneda y avatar.
class BarraSuperior extends ConsumerWidget implements PreferredSizeWidget {
  const BarraSuperior({required this.titulo, this.alAbrirMenu, super.key});

  final String titulo;

  /// `null` en escritorio: alli la barra lateral esta siempre a la vista y un
  /// boton de menu que no abre nada es un boton que ensena a desconfiar.
  final VoidCallback? alAbrirMenu;

  @override
  Size get preferredSize => const Size.fromHeight(Anchos.altoBarraSuperior);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final actualizando = ref.watch(actualizandoProvider);
    final sinConexion = ref.watch(saludDeLaRedProvider).vaMal;

    // Sobre PAPEL, no sobre blanco: en delivery la barra es `bg-paper/80` y lo
    // blanco son las tarjetas y la barra lateral. Una barra superior blanca
    // sobre un fondo casi blanco hace que la pantalla no tenga arriba.
    // El umbral es el mismo con el que el pliego (§11) esconde el idioma: por
    // debajo de esto la barra ya no tiene sitio para todo.
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.idioma;

    return Container(
      height: Anchos.altoBarraSuperior,
      decoration: BoxDecoration(
        color: Colores.papel,
        border: Border(bottom: BorderSide(color: Colores.linea)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Aire.md),
      child: Row(
        children: [
          if (alAbrirMenu != null)
            IconButton(
              tooltip: 'Menú',
              icon: const Icon(Icons.menu, size: 22),
              color: Colores.tintaSuave,
              onPressed: alAbrirMenu,
            ),
          const SizedBox(width: Aire.xs),
          // EL TITULO SE COME TODO EL HUECO LIBRE, y por eso va en `Expanded` y
          // no en `Flexible` con un `Spacer` detras.
          //
          // Con `Flexible` + `Spacer` los dos pesan igual, asi que Flutter les
          // reparte el sobrante A MEDIAS: el `Spacer` empujaba el grupo de la
          // derecha solo hasta la mitad y la otra mitad quedaba vacia detras del
          // avatar. En un monitor ancho eso se ve como la sucursal, la moneda y
          // el avatar flotando en el centro en vez de en su esquina; en un
          // telefono no se notaba porque alli no sobra hueco que repartir.
          //
          // El titulo y el giro van juntos DENTRO del Expanded para que el giro
          // salga pegado al titulo, como en delivery, y no al otro lado.
          //
          // EN UN TELEFONO EL TITULO NO SE PINTA, y es una decision, no un
          // recorte por falta de sitio. En 390 px la barra llevaba el boton de
          // menu, el titulo, el selector de sucursal (hasta 220 px), la moneda y
          // el avatar: suman mas que la pantalla, y lo que se salia por la
          // derecha era el avatar — o sea el menu de la cuenta y «Salir—.
          // Visto por Jose el 16/09/2026: «el avatar a la derecha no se ve casi
          // por q tengo el select de las sucursales q oocupa mucho espacio».
          //
          // De las cuatro piezas, la que menos falta hace es el titulo: dice el
          // nombre de la pantalla que se acaba de elegir en el menu. La sucursal
          // y la moneda, en cambio, CAMBIAN LOS NUMEROS que se estan mirando, y
          // por eso el pliego (§11) prohibe esconderlas. El avatar tiene que
          // poder pulsarse.
          // TODO LO QUE NO ES EL BOTON DE MENU VA DENTRO DE ESTE `Expanded`, y
          // el `LayoutBuilder` de dentro es lo que arregla el desborde.
          //
          // El hijo de un `Row` que NO es flexible se mide con el ancho SIN
          // TOPE: el grupo de la derecha pedia sus 150 + 8 + 92,9 + 8 + 66 sin
          // enterarse de que la barra medía 366, y lo que sobraba salia por el
          // borde con la cebra amarilla y negra. Medido a 390 px con las ocho
          // sucursales, una elegida —la caja llega a su tope de 150— y la moneda
          // en CUP con la tasa vieja, que añade el reloj de aviso: **376,9 px en
          // una barra de 366, o sea casi once de desborde**, y lo que se comia
          // era otra vez el avatar.
          //
          // Metido dentro de un `Expanded`, el `LayoutBuilder` sí sabe cuánto
          // queda (`medidas.maxWidth`), y con ese número se le pone tope al
          // grupo de la derecha. A partir de ahi el `Flexible` de la sucursal
          // recorta su etiqueta con puntos suspensivos en vez de empujar al
          // avatar fuera de la pantalla. En un monitor ancho no cambia nada: el
          // tope es mayor que lo que el grupo pide, asi que sigue midiendo lo
          // suyo y pegado a su esquina.
          Expanded(
            child: LayoutBuilder(
              builder: (context, medidas) => Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (!estrecho)
                          Flexible(
                            child: Text(
                              titulo,
                              overflow: TextOverflow.ellipsis,
                              style: tema.textTheme.titleLarge,
                            ),
                          ),
                        // EL GIRO DE «actualizando…» NO SALE EN UN TELEFONO.
                        //
                        // No cabe, y lo que hacia al no caber era peor que faltar: con
                        // el titulo ya fuera, este hueco se queda en unos pocos pixeles
                        // —el menu, la sucursal, la moneda y el avatar se llevan los
                        // 390—, asi que el giro se salia y se pintaba DEBAJO del
                        // selector de sucursal. Visto por Jose el 16/09/2026: «el
                        // actualizando me sale atras de el selector de sucursales».
                        //
                        // Y tiene un sitio mejor: la franja de estado de debajo, que es
                        // donde se mira si los datos estan al dia. Ahi va, con la hora
                        // al lado, que es lo que de verdad hace falta saber.
                        // Sin conexion tampoco se gira aqui: el ciclo reintenta por
                        // detras, pero no hay progreso que ensenar. Ver la franja.
                        if (actualizando && !estrecho && !sinConexion) ...[
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colores.tintaSuave,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'actualizando…',
                            style: Tipos.texto(
                              tamano: 11,
                              peso: FontWeight.w500,
                              color: Colores.tintaSuave.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // EL GRUPO DE LA DERECHA, CON TOPE PERO SIN REPARTO.
                  //
                  // NADA DE `Flexible` SUELTO AQUI, por mucho que lo pida el
                  // cuerpo. Se probó y rompió la prueba de «el grupo de la
                  // derecha llega al borde»: un `Flexible` al lado del
                  // `Expanded` del título son dos hijos con el mismo peso, así
                  // que Flutter les reparte el sobrante A MEDIAS y el grupo
                  // vuelve a quedarse flotando en mitad de la barra.
                  //
                  // Un `ConstrainedBox` no reparte nada: sólo le dice al grupo
                  // cuánto hay como mucho. Si le sobra —un monitor ancho—, el
                  // grupo mide lo suyo y el `Expanded` del título se queda con
                  // el resto, que es lo que lo pega a la esquina. Si no le
                  // llega, el recorte cae donde tiene que caer: en la ETIQUETA
                  // de la sucursal, que se queda con puntos suspensivos. La
                  // sucursal y la moneda no se esconden nunca (§11) porque son
                  // las que cambian los números; lo que se acorta es su texto.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: medidas.maxWidth),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: _Sucursal(compacta: estrecho)),
                        // AQUI NO VA NINGUN SELECTOR DE IDIOMA, Y NO ES UN
                        // PENDIENTE.
                        //
                        // El pliego lo pide (`docs/pantallas.md` §11: `Idioma`
                        // ES/EN entre sucursal y moneda, oculto por debajo de
                        // 640 px), y llego a estar medio hecho: 305 claves en
                        // `app_es.arb`, otras 305 en `app_en.arb`, la clase
                        // `Textos` de gen_l10n y sus delegaciones. Enchufado a
                        // UNA pantalla de las cuarenta y pico; el resto de la
                        // aplicacion, incluida esta barra, siempre fueron
                        // literales en espanol a pelo.
                        //
                        // **Jose decidio el 24/09/2026 quitarlo entero.** Las
                        // ocho sucursales son de Cuba y nadie ha pedido ingles;
                        // lo que habia era codigo muerto que las pruebas daban
                        // por vivo, que es peor que no tenerlo. No hay nada que
                        // terminar aqui: si algun dia hace falta ingles, se
                        // empieza de cero y se empieza por las pantallas, no por
                        // la barra. El porque completo esta en
                        // `lib/idioma.dart`.
                        const SizedBox(width: 8),
                        const _Moneda(),
                        const SizedBox(width: 8),
                        const MenuDeCuenta(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El selector de sucursal del Super Admin.
///
/// Cambiarlo **no recarga la pagina**: los providers de pantalla miran
/// `sucursalMiradaProvider`, asi que se reconstruyen solos y los numeros cambian
/// en el sitio. Eso es lo que pide el pliego §0 y es la razon de que la sucursal
/// viva en un provider y no en la URL.
/// «Todas las sucursales (8)» son veintitres caracteres para decir «ninguna
/// elegida»; «Todas (8)» son nueve y dice lo mismo. En un telefono esos catorce
/// caracteres son el avatar cabiendo o no cabiendo.
String _todas(int cuantas, bool compacta) =>
    compacta ? 'Todas ($cuantas)' : 'Todas las sucursales ($cuantas)';

class _Sucursal extends ConsumerWidget {
  const _Sucursal({required this.compacta});

  /// En un telefono la etiqueta se acorta y la caja se estrecha. «Todas las
  /// sucursales (8)» son veintitres caracteres para decir «ninguna elegida»;
  /// «Todas (8)» son nueve y dice lo mismo.
  final bool compacta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sucursales =
        ref.watch(sucursalesProvider).value ?? const <Sucursal>[];
    final mirada = ref.watch(sucursalMiradaProvider);

    // Con ninguna no se pinta nada; con una sola, etiqueta fija (§8.2).
    if (sucursales.isEmpty) return const SizedBox.shrink();
    if (sucursales.length == 1) {
      final unica = sucursales.first;
      final codigo = unica.externalId;
      // Una sola sucursal: se dice cual es en una pastilla blanca con su borde
      // fino — la misma caja que el selector, para que la barra no tenga una
      // pieza sin forma al lado de otra que si la tiene.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: 8),
        decoration: BoxDecoration(
          color: Colores.blanco,
          border: Border.all(color: Colores.linea),
          borderRadius: BorderRadius.circular(Radios.lg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_outlined, size: 16, color: Colores.tintaSuave),
            const SizedBox(width: 6),
            // `Flexible` y no el `ConstrainedBox` a secas: la barra le pone tope
            // a esta pastilla cuando no cabe, y un hijo rigido dentro de un
            // `Row` se lleva el recorte por el borde en vez de acortar su texto.
            // Es el mismo desborde de la barra, una capa mas adentro.
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compacta ? 110 : 180),
                child: Text(
                  codigo == null
                      ? unica.name
                      : (compacta ? codigo : '${unica.name} ($codigo)'),
                  overflow: TextOverflow.ellipsis,
                  style: Tipos.texto(tamano: 14, color: Colores.tinta),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Si la sucursal guardada ya no esta entre las visibles, se olvida (§8.2):
    // dejarla puesta filtraria por una sucursal que la persona ya no ve y la
    // pantalla saldria vacia sin motivo a la vista.
    final valida = mirada != null && sucursales.any((s) => s.id == mirada);
    final valor = valida ? mirada : '';

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compacta ? 150 : 220),
      child: Selector<String>(
        icono: Icons.store_outlined,
        tooltip: 'Sucursal que se está mirando',
        // `etiquetaVacia` NO basta, y esto costo una vuelta: el selector pinta
        // `elegida?.etiqueta ?? etiquetaVacia`, y aqui SI hay una opcion con
        // valor vacio —la de «todas»—, asi que la que manda es SU etiqueta. Con
        // solo cambiar esta linea el telefono seguia diciendo «Todas las s…».
        // Se acortan las dos, abajo tambien.
        etiquetaVacia: _todas(sucursales.length, compacta),
        valor: valor,
        opciones: [
          OpcionSelector<String>(
            valor: '',
            etiqueta: _todas(sucursales.length, compacta),
          ),
          for (final s in sucursales)
            OpcionSelector<String>(
              valor: s.id,
              etiqueta: s.name,
              nota: s.externalId,
            ),
        ],
        alElegir: (v) => ref
            .read(sucursalMiradaProvider.notifier)
            .mirar(v.isEmpty ? null : v),
      ),
    );
  }
}

/// La moneda en la que se PINTAN los importes.
///
/// Sin tasa se queda en USD fijo, con borde ambar y **el motivo de verdad** en el
/// tooltip (§8.2). No se ofrece elegir CUP sin tasa: convertir sin tasa es
/// inventarse un numero, y un numero inventado en una hoja de reparto acaba
/// cobrado.
///
/// ## De donde sale la tasa, y de donde NO
///
/// De [tasaDeLaMiradaProvider], que la lee de la SUCURSAL que se esta mirando.
///
/// Antes se leia la tabla local `currencies`, **que no llenaba nadie**: no esta
/// en `Colecciones`, la bajada del dia no la trae y el servidor no la sirve. Salia
/// vacia siempre, asi que esta pastilla se quedaba en ambar para siempre, en las
/// ocho sucursales, tuvieran tasa o no — y como el mensaje que enseñaba («esta
/// sucursal no tiene tasa de cambio todavia») puede ser verdad, nadie lo iba a
/// cuestionar. Esa tabla ya no existe.
///
/// Tampoco se lee `settings.cupRate`, que es el campo viejo y GLOBAL de delivery,
/// con 320 por defecto. Leerlo seria darle a las ocho sucursales la misma tasa,
/// que es como Granma acabo enseñando los 685 de La Habana.
class _Moneda extends ConsumerWidget {
  const _Moneda();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasa = ref.watch(tasaDeLaMiradaProvider);
    final mirada = ref.watch(monedaEfectivaProvider);

    // --- Sin tasa de ESTA sucursal: USD fijo, y se dice por que --------------
    if (!tasa.hayCup) {
      return _pastillaAmbar(
        aviso: tasa.motivo ?? '',
        icono: Icons.money_off_csred_outlined,
      );
    }

    // --- Con tasa ------------------------------------------------------------
    //
    // La NOTA de la opcion lleva la tasa Y SU FECHA. La fecha no es un adorno: es
    // lo unico que demuestra que la tasa es de verdad y lo que deja ver de cuando
    // es sin abrir nada. Hoy las que hay son del 9 de septiembre.
    final nota =
        '1 USD = ${Numeros.entero(tasa.cupPorUsd!)} · '
        'del ${tasa.traidoAt!.day}/${tasa.traidoAt!.month}/'
        '${tasa.traidoAt!.year}';

    final selector = Selector<String>(
      tooltip: tasa.aviso ?? 'Moneda de visualización',
      etiquetaVacia: 'USD',
      valor: mirada,
      opciones: [
        const OpcionSelector<String>(valor: 'USD', etiqueta: 'USD'),
        OpcionSelector<String>(valor: 'CUP', etiqueta: 'CUP', nota: nota),
      ],
      alElegir: (v) => ref.read(monedaMiradaProvider.notifier).mirar(v),
    );

    // TASA VIEJA: SE ENSEÑA, CON AVISO. Lo decide Accesos (24 h alli), no esta
    // pantalla. El aviso va a la vista y no solo en el tooltip cuando se esta
    // pintando en CUP: es cuando el numero desfasado esta delante de los ojos.
    if (tasa.aviso == null || mirada != 'CUP') return selector;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: tasa.aviso!,
          child: Icon(Icons.schedule_outlined, size: 16, color: Colores.ambar),
        ),
        const SizedBox(width: 6),
        selector,
      ],
    );
  }

  /// La pastilla de «aqui no se puede ver en CUP», con el motivo dentro.
  Widget _pastillaAmbar({required String aviso, required IconData icono}) {
    return Tooltip(
      message: aviso,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: 8),
        decoration: BoxDecoration(
          color: Colores.blanco,
          border: Border.all(color: Colores.ambar.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(Radios.lg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 16, color: Colores.ambar),
            const SizedBox(width: 6),
            // En mono: es una cifra, aunque sea el codigo de la moneda.
            Text(
              'USD',
              style: Tipos.mono(
                tamano: 12,
                peso: FontWeight.w600,
                color: Colores.ambar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
