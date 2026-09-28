// Los controles de fecha de las listas: `Desde`, `Hasta`, `sólo ese día` y la
// ✕ que los quita.
//
// **Por que estaban haciendo falta:** el SQL que acota por fecha ya estaba
// escrito y la ✕ de limpiarlo tambien, pero no habia ningun control que PUSIERA
// las fechas, asi que el filtro existia y era inalcanzable. Con eso, «el
// pre-despacho de HOY» —con lo que empieza la mañana del logistico— no se podia
// pedir.
//
// **No se usa `showDatePicker`.** Esa es una ventana modal centrada, y en esta
// aplicacion no hay modales: es la excepcion aprobada del 05/09/2026
// (`pantallas.md` §0 y §9.2). El calendario sale en un menu anclado al propio
// boton, que es el mismo patron del `Selector` de la casa.
//
// **Y en el telefono sale en un CAJON**, no en el menu (28/09/2026). Ver el
// comentario largo de `_CampoDeFechaState.build`.

import 'package:flutter/material.dart';

import 'anchos.dart';
import 'cajon.dart';
import 'colores.dart';
import 'tema.dart';

/// Un dia a secas, sin hora: es lo que compara el filtro, y una hora dentro de
/// un `DateTime` que se compara con `==` es la forma mas facil de que «el mismo
/// dia» deje de ser el mismo dia.
DateTime soloElDia(DateTime cuando) =>
    DateTime(cuando.year, cuando.month, cuando.day);

/// Un boton de fecha: sin nada puesto pinta su titulo; con fecha, la fecha.
class CampoDeFecha extends StatefulWidget {
  const CampoDeFecha({
    required this.titulo,
    required this.valor,
    required this.alElegir,
    this.minimo,
    this.maximo,
    this.hoy,
    super.key,
  });

  /// El tooltip, y la etiqueta cuando no hay fecha puesta. Literales del pliego:
  /// `Desde (fecha del pedido)` / `Hasta (fecha del pedido)`.
  final String titulo;

  /// La etiqueta corta del boton cuando no hay nada: `Desde` / `Hasta`.
  final DateTime? valor;

  final ValueChanged<DateTime> alElegir;

  /// `desde` acota el minimo de `hasta` y al reves, como en la de Next: asi no
  /// se puede pedir un rango al reves, que devuelve cero y parece que no hubo
  /// pedidos.
  final DateTime? minimo;
  final DateTime? maximo;

  /// Por que mes se abre el calendario cuando no hay fecha puesta. Entra por
  /// parametro y no se lee del reloj del sistema para que sea EL MISMO reloj
  /// que el resto de la aplicacion —el de `relojProvider`—: dos relojes son dos
  /// «hoy» distintos, y en una prueba serian un mes distinto cada vez que pase
  /// la medianoche.
  final DateTime? hoy;

  static String _texto(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  State<CampoDeFecha> createState() => _CampoDeFechaState();
}

class _CampoDeFechaState extends State<CampoDeFecha> {
  /// El menu se cierra con SU controlador, nunca con `Navigator.maybePop()`.
  /// El menu de un `MenuAnchor` no es una ruta: `maybePop` no lo cerraria, se
  /// llevaria por delante la PANTALLA que hay debajo.
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final titulo = widget.titulo;
    final valor = widget.valor;
    final minimo = widget.minimo;
    final maximo = widget.maximo;
    final puesta = valor != null;
    // Los topes del calendario. Van anchos a proposito: el pasado llega hasta
    // 2020 —hay pedidos viejos espejados— y el futuro hasta el año que viene,
    // porque una fecha de entrega comprometida puede estar por delante.
    final primero = minimo ?? DateTime(2020);
    final ahora = widget.hoy ?? DateTime.now();
    final ultimo = maximo ?? DateTime(ahora.year + 1, 12, 31);

    // Sin fecha puesta se abre por el tope de arriba —o por hoy, si cae dentro—,
    // que es de donde se sale casi siempre: el dia de hoy.
    final inicial = valor ?? _dentro(ahora, primero, ultimo);

    // EN EL TELÉFONO, CAJÓN. EN ESCRITORIO, EL MENÚ ANCLADO DE SIEMPRE.
    //
    // Jose, 28/09/2026, mirando Pedidos en el móvil con el calendario abierto
    // encima de la tabla:
    //
    //     «recuerda que este modal en el movil debe ser un drawer, el
    //      calendario, todo lo que salga asi como modal que sobresalga, los
    //      dropdowns creo que seria mejor ponerlos como drawer, todo eso para
    //      las opciones y queda mucho mas comodo»
    //
    // El caso concreto es medible: el panel del menú mide 320×340 px fijos y el
    // botón `Desde` vive en una barra de filtros que en un teléfono de 390 px ya
    // va a dos columnas, o sea a media pantalla. El calendario le sale por el
    // lado, se recorta contra el borde y tapa la tabla que se venía a filtrar,
    // sin ninguna ✕ con la que salir. En cajón ocupa la pantalla entera, con su
    // cabecera y su ✕, y el mes se toca con el dedo en vez de con la uña.
    //
    // **En escritorio no se cambia nada, y eso es parte del arreglo**: el menú
    // anclado es lo que se decidió a propósito —ni `showDatePicker`, que es el
    // modal centrado que el pliego no quiere, ni `showMenu`, que calculaba la
    // posición una sola vez al abrir y dejaba el panel flotando al desplazar la
    // página (25/09/2026)—. El corte sale de `Anchos.escritorio`, el mismo que
    // usan `Cajon` y `Selector`: un número a mano aquí sería un tercer corte.
    if (MediaQuery.sizeOf(context).width < Anchos.escritorio) {
      return _boton(
        titulo: titulo,
        valor: valor,
        puesta: puesta,
        alPulsar: () => abrirCajon<void>(
          context,
          titulo: titulo,
          ancho: AnchoCajon.md,
          cuerpo: (contextoCajon) => _calendario(
            inicial: inicial,
            primero: primero,
            ultimo: ultimo,
            // El cajón SÍ es una ruta, así que se cierra con el `Navigator`. El
            // menú no lo es y se cierra con su `MenuController` (ver arriba):
            // cambiarlos de sitio cierra la pantalla de debajo.
            alCerrar: () => Navigator.of(contextoCajon).maybePop(),
          ),
        ),
      );
    }

    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colores.blanco),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radios.lg),
            side: BorderSide(color: Colores.linea),
          ),
        ),
      ),
      builder: (contexto, controlador, _) => _boton(
        titulo: titulo,
        valor: valor,
        puesta: puesta,
        alPulsar: () =>
            controlador.isOpen ? controlador.close() : controlador.open(),
      ),
      menuChildren: [
        // El panel del menu monta su PROPIO `PrimaryScrollController`, con una
        // barra de desplazamiento siempre visible. El calendario trae dentro
        // otro desplazable vertical —la lista de años— que heredaria ese mismo
        // controlador, y dos posiciones en un controlador con barra visible es
        // un error que tumba el fotograma entero. Aqui se corta la herencia:
        // cada uno se desplaza por su cuenta.
        //
        // **En el cajon esto no se pone, y no es un olvido.** Medido con una
        // sonda el 28/09/2026: dentro de un `Cajon` —que se abre con
        // `showGeneralDialog`, o sea en el `Overlay`, POR ENCIMA del
        // `Scaffold`— `PrimaryScrollController.maybeOf` devuelve `null`, asi
        // que no hay ninguna herencia que cortar. Una linea que no se puede
        // romper no es una guarda: lo que si vigila el caso es la prueba «se
        // puede abrir la lista de años» del cajon, que mira el resultado.
        PrimaryScrollController.none(
          child: SizedBox(
            width: 320,
            height: 340,
            child: _calendario(
              inicial: inicial,
              primero: primero,
              ultimo: ultimo,
              alCerrar: _menu.close,
            ),
          ),
        ),
      ],
    );
  }

  /// El calendario, el mismo en el menu y en el cajon. Lo unico que cambia es
  /// quien lo cierra.
  ///
  /// **No lleva alto propio**, y eso es a proposito aunque el menu se lo ponga
  /// por fuera: `CalendarDatePicker` YA se mide solo —su `build` devuelve un
  /// `SizedBox(height: cabecera + alto maximo de la rejilla)`—, asi que dentro
  /// del cuerpo desplazable del cajon sale entero y sin recortes. Meterle aqui
  /// los 340 px del menu seria peor que no poner nada: en un telefono recorta
  /// la ultima fila de dias, que es donde caen los finales de mes.
  Widget _calendario({
    required DateTime inicial,
    required DateTime primero,
    required DateTime ultimo,
    required VoidCallback alCerrar,
  }) => _Calendario(
    inicial: inicial,
    primero: primero,
    ultimo: ultimo,
    alElegir: widget.alElegir,
    alCerrar: alCerrar,
  );

  /// La caja del filtro. Es la MISMA en los dos sitios: lo unico que cambia es
  /// lo que hace al pulsarla.
  Widget _boton({
    required String titulo,
    required DateTime? valor,
    required bool puesta,
    required VoidCallback alPulsar,
  }) => Tooltip(
    message: titulo,
    child: OutlinedButton.icon(
      onPressed: alPulsar,
      icon: const Icon(Icons.event, size: 16),
      label: Text(puesta ? CampoDeFecha._texto(valor!) : titulo),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colores.blanco,
        foregroundColor: puesta ? Colores.tinta : Colores.tintaSuave,
        side: BorderSide(
          color: puesta
              ? Colores.primario.withValues(alpha: 0.5)
              : Colores.linea,
        ),
        padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: 9),
        textStyle: Tipos.texto(
          tamano: 14,
          peso: puesta ? FontWeight.w600 : FontWeight.w400,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radios.lg),
        ),
      ),
    ),
  );

  DateTime _dentro(DateTime d, DateTime primero, DateTime ultimo) {
    if (d.isBefore(primero)) return primero;
    if (d.isAfter(ultimo)) return ultimo;
    return d;
  }
}

/// El calendario de dentro del menu. Va aparte y con estado propio para que
/// elegir un dia no tenga que cerrar y reabrir el menu para verse marcado.
class _Calendario extends StatefulWidget {
  const _Calendario({
    required this.inicial,
    required this.primero,
    required this.ultimo,
    required this.alElegir,
    required this.alCerrar,
  });

  final DateTime inicial;
  final DateTime primero;
  final DateTime ultimo;
  final ValueChanged<DateTime> alElegir;
  final VoidCallback alCerrar;

  @override
  State<_Calendario> createState() => _CalendarioState();
}

class _CalendarioState extends State<_Calendario> {
  late DateTime _elegido = widget.inicial;

  @override
  Widget build(BuildContext context) => CalendarDatePicker(
    initialDate: _elegido,
    firstDate: widget.primero,
    lastDate: widget.ultimo,
    onDateChanged: (dia) {
      setState(() => _elegido = dia);
      widget.alElegir(soloElDia(dia));
      // El menu se cierra solo: una vez elegido el dia no queda nada que hacer
      // ahi dentro, y dejarlo abierto tapa la lista que se acaba de filtrar.
      widget.alCerrar();
    },
  );
}

/// Los cuatro controles juntos: `Desde`, `Hasta`, `sólo ese día` y la ✕.
///
/// Van en un solo widget porque son un solo filtro: los tres ultimos sólo
/// tienen sentido en funcion de lo que digan los dos primeros, y repartirlos
/// por dos pantallas fue justo como se quedaron sin poner.
class RangoDeFechas extends StatelessWidget {
  const RangoDeFechas({
    required this.desde,
    required this.hasta,
    required this.alCambiar,
    this.tituloDesde = 'Desde',
    this.tituloHasta = 'Hasta',
    this.conSoloEseDia = true,
    this.hoy,
    super.key,
  });

  final DateTime? desde;
  final DateTime? hasta;

  /// Los dos a la vez, y con `null` explicito: sin eso no habria forma de
  /// BORRAR una fecha — pasar `null` seria indistinguible de «no la toques» y
  /// el rango se quedaria puesto para siempre.
  final void Function(DateTime? desde, DateTime? hasta) alCambiar;

  final String tituloDesde;
  final String tituloHasta;

  /// `sólo ese día`: copia `desde` en `hasta`. Sale cuando hay `desde` y los
  /// dos no coinciden ya, igual que en la de Next.
  final bool conSoloEseDia;

  /// El «hoy» de la aplicacion, para abrir el calendario por su mes.
  final DateTime? hoy;

  static const tooltipQuitar = 'Quitar el filtro de fechas';

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      CampoDeFecha(
        titulo: tituloDesde,
        valor: desde,
        maximo: hasta,
        hoy: hoy,
        alElegir: (dia) => alCambiar(dia, hasta),
      ),
      CampoDeFecha(
        titulo: tituloHasta,
        valor: hasta,
        minimo: desde,
        hoy: hoy,
        alElegir: (dia) => alCambiar(desde, dia),
      ),
      if (conSoloEseDia && desde != null && desde != hasta)
        OutlinedButton(
          onPressed: () => alCambiar(desde, desde),
          child: const Text('sólo ese día'),
        ),
      if (desde != null || hasta != null)
        IconButton(
          tooltip: tooltipQuitar,
          icon: const Icon(Icons.close),
          onPressed: () => alCambiar(null, null),
        ),
    ],
  );
}
