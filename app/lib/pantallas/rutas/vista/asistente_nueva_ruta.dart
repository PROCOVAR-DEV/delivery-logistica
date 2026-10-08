// El asistente «Nueva Ruta»: cajon a pantalla completa con pie fijo y 4 pasos
// —Sucursal, Salida, Vehículo, Pedidos—.
//
// **Funciona entero sin conexion**, y eso no es un extra: armar la ruta pasa en
// el patio del almacen. Los pedidos elegibles salen de la base local, la
// capacidad se comprueba aqui, el orden de visita y los km los calcula el
// aparato (`geo.dart`) y la ruta se guarda con un id `local-…` y su propio
// codigo. Lo que el servidor diga llegara despues, y si dice que no, saldra en la
// bandeja de rechazos con su hora y su motivo.
//
// Pliego: `../../../../docs/pantallas.md` §3, «Asistente Nueva Ruta».

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/caja_de_numero.dart';
import '../../../diseno/cajon.dart' show AtrasDelCajon;
import '../../../diseno/numeros.dart';
import '../../../diseno/rango_de_fechas.dart';
import '../../../diseno/tema.dart';
import '../../../impresion/hoja.dart' as papel;
import '../../../impresion/pre_despacho.dart' show pdfPreDespacho;
import '../../../impresion/vista_previa.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../almacenes/vista/almacenes_de_la_ultima_bajada.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';
import '../../pedidos/estado/proveedores_pedidos.dart';
import '../../pedidos/vista/kit.dart';
import '../../pedidos/vista/vista_pre_despacho.dart';
import '../datos/acciones_rutas.dart';
import '../datos/meter_la_zona.dart';
import '../datos/repositorio_rutas.dart';
import '../datos/zona_en_el_asistente.dart';
import '../estado/proveedores_rutas.dart';
import 'aviso_de_rechazo.dart';

class AsistenteNuevaRuta extends ConsumerStatefulWidget {
  const AsistenteNuevaRuta({super.key});

  static const sinAlmacenes =
      'Esta sucursal no tiene ningún almacén con ubicación. Se pone en '
      'Almacenes, y hasta entonces no hay desde dónde medir.';

  static const sinVehiculos =
      'No hay vehículos disponibles. Crea o libera uno en Vehículos para poder '
      'crear la ruta.';

  /// Los dos botones que sacan del callejón. Un paso que no se puede terminar
  /// **tiene que llevar al sitio donde se arregla**: nombrar la pantalla y
  /// dejar ahí a alguien es obligarle a salir, buscarla en el menú, hacerlo y
  /// volver a empezar el asistente desde el paso 1.
  static const irAVehiculos = 'Agregar el primer vehículo';
  static const irAAlmacenes = 'Poner el almacén';

  static const sinPedidos = 'No hay pedidos disponibles para rutear.';

  static const cargandoPedidos = 'Cargando pedidos...';

  static const preDespachoVacio =
      'Según vayas eligiendo pedidos, aquí sale cuánto hay que sacar de cada '
      'producto.';

  /// LOS CUATRO PASOS, con el nombre que sale bajo su tramo de la barra.
  static const pasos = <int, String>{
    1: 'Sucursal',
    2: 'Salida',
    3: 'Vehículo',
    4: 'Pedidos',
  };

  /// La tarjeta del paso `n`. La usan las pruebas para decir «estoy en el 2»
  /// sin depender del texto del título, que es lo que más se retoca.
  static Key claveDelPaso(int n) => ValueKey('paso-$n');

  /// El tramo `n` de la barra de progreso, el que se pulsa para volver.
  static Key claveDelTramo(int n) => ValueKey('tramo-$n');

  /// LA CAJA DE LA LISTA DE PEDIDOS.
  ///
  /// Es la pieza que arregla la queja de Jose del 17/09/2026: «no me digas que
  /// está abajo del todo y tengo que bajar por todos los pedidos, que es una
  /// lista larga a la cual no me le has puesto ni paginación». La lista estaba
  /// suelta dentro del desplazamiento del cajón, así que con 295 pedidos el
  /// resumen y el botón de generar quedaban a cientos de píxeles hacia abajo.
  ///
  /// Con la caja acotada **la lista se desplaza dentro de ella** y lo de debajo
  /// —el resumen y el pie— no se mueve de sitio. Por eso la de Next no necesita
  /// paginación: `max-h-64 overflow-y-auto`, lo mismo que esto.
  static const claveDeLaLista = ValueKey('caja-de-la-lista');

  /// La línea fija de debajo de la lista: cuántos van y cuánto pesan.
  static const claveDelResumen = ValueKey('resumen-de-lo-elegido');

  /// El botón que abre el pre-despacho en el móvil.
  static const claveDelBotonDePreDespacho = ValueKey('boton-pre-despacho');

  /// La caja del pre-despacho. En escritorio va al lado de la lista; por debajo
  /// de [anchoDosColumnas], debajo.
  static const claveDelPreDespacho = ValueKey('caja-del-pre-despacho');

  /// El alto de la caja de la lista. El `max-h-64` de la de Next son 256 px;
  /// aquí hay 320 porque las filas llevan una línea más (los artículos).
  static const altoDeLaLista = 320.0;

  /// Por debajo de este ancho **dentro de la tarjeta** el pre-despacho cae
  /// debajo de la lista. No es el ancho de la pantalla: la tarjeta vive dentro
  /// del cajón y con sus márgenes, y lo que decide si caben dos columnas es lo
  /// que mide ELLA.
  static const anchoDosColumnas = 900.0;

  /// El ancho de la columna del pre-despacho: las `22rem` de la de Next.
  static const anchoPreDespacho = 352.0;

  /// EL ANCHO DE CADA FILTRO, y es el mismo para todos a propósito.
  ///
  /// Eran un `Wrap` de pastillas de anchos distintos —220 el buscador, 110 los
  /// números, y cada selector lo que midiera su texto—, y eso en pantalla se
  /// desmigaja: filas con tres cachos de distinto tamaño, huecos irregulares y
  /// la altura saltando al cambiar un texto. Palabras de Jose: «las cajas no
  /// uniformes, los cuerpos se deforman». Con un ancho único las filas salen
  /// en columnas alineadas a la izquierda y se recorren de un vistazo.
  static const anchoFiltro = 220.0;

  @override
  ConsumerState<AsistenteNuevaRuta> createState() => _AsistenteState();
}

class _AsistenteState extends ConsumerState<AsistenteNuevaRuta> {
  int _paso = 1;
  String? _sucursalId;
  Almacen? _salida;
  String? _vehiculoId;

  /// LA FECHA DE ENTREGA ARRANCA EN HOY, no vacía — 28/09/2026.
  ///
  /// Era «(opcional)» y nacía en blanco, y el resultado se vio en producción:
  /// **las NUEVE rutas del servidor tenían `delivery_date` nulo**, las nueve.
  /// Un campo opcional que nadie rellena nunca no es una opción, es una columna
  /// muerta — y por eso la ficha y la lista de rutas enseñaban un `—` donde va
  /// el día. Jose: «esos datos debemos de tenerlo por q no se estan poniendo».
  ///
  /// Hoy es además la respuesta correcta casi siempre: una ruta se arma con los
  /// pedidos que suben al camión ahora. Quien la prepare para mañana cambia el
  /// día, que sigue siendo un clic; lo que ya no se puede es dejarla sin
  /// ninguno sin darse cuenta.
  ///
  /// Se pone en [initState] y no aquí para que salga del reloj de la casa y no
  /// de `DateTime.now()`, que es lo que deja probar el asistente con una fecha
  /// fija.
  DateTime? _fechaDeEntrega;
  final _nombre = TextEditingController();

  @override
  void initState() {
    super.initState();
    final ahora = ref.read(relojProvider)();
    _fechaDeEntrega = DateTime(ahora.year, ahora.month, ahora.day);
  }

  /// EL DESPLAZAMIENTO DE LA CAJA DE LA LISTA, y es SUYO.
  ///
  /// Dos cosas a la vez. La primera: sin un controlador propio la lista se
  /// engancha al `PrimaryScrollController`, que ya es el del cuerpo del cajón, y
  /// entonces son dos desplazamientos peleándose por el mismo gesto. La segunda:
  /// marcar un pedido es un `setState`, y con el controlador aquí la lista se
  /// queda donde estaba en vez de volverse al principio en cada clic.
  final _desplazamientoDeLaLista = ScrollController();

  /// Lo elegido, **con el pedido dentro y no sólo su id**.
  ///
  /// Hace falta guardarlo entero porque un pedido elegido puede dejar de salir
  /// en la lista al cambiar de dia o de vendedor, y sigue contando: su peso
  /// sigue en el camion y tiene que seguir sumando en la barra de capacidad. Con
  /// un `Set<String>` el peso de esos se perdia y el camion parecia mas vacio de
  /// lo que iba a salir.
  final _elegidos = <String, Pedido>{};

  FiltrosDisponibles _filtros = const FiltrosDisponibles();

  /// LA ZONA DEL TABLERO ELEGIDA EN EL PASO 4. `null` = todas.
  ///
  /// Es un filtro mas, y por eso vive aqui y no dentro de `_filtros`: los de
  /// `_filtros` los resuelve la consulta de disponibles en la base, y este se
  /// aplica encima con `soloDeLaZona`. No baja a la consulta a proposito —lo
  /// que esta puesto en una zona lo sabe el tablero, no la tabla de pedidos— y
  /// asi la lista de zonas y la de disponibles no se pueden contradecir.

  /// ¿El camion del paso 3 lo eligio una PERSONA?
  ///
  /// Es lo unico que separa «el camion que trajo la zona anterior» —que se pisa
  /// sin preguntar, porque no era la decision de nadie— de «el que eligio quien
  /// esta armando», que no se pisa. El porque entero, en `camionDeLaZona`.
  bool _camionAMano = false;

  /// Que el salto al paso 3 pase **una sola vez**. Sin esto, volver a mano al
  /// paso 1 rebotaria al 3 en el siguiente repintado y no habria forma de
  /// cambiar de sucursal.
  bool _arranqueResuelto = false;

  bool _generando = false;

  /// El último «no» del armado, mientras no se cierre. `null` = no hay ninguno.
  String? _rechazo;

  @override
  void dispose() {
    _nombre.dispose();
    _desplazamientoDeLaLista.dispose();
    super.dispose();
  }

  Vehiculo? get _vehiculo {
    final lista = ref.read(vehiculosProvider).value ?? const <Vehiculo>[];
    return lista.where((v) => v.id == _vehiculoId).firstOrNull;
  }

  double get _peso =>
      _elegidos.values.fold<double>(0, (suma, p) => suma + p.weight);

  void _ponerFiltros(FiltrosDisponibles nuevos) =>
      setState(() => _filtros = nuevos);

  /// LO QUE LLEGA YA VIENE CON SU RESPIRO: lo pone `CajaDeBusqueda`.
  ///
  /// Aqui habia un `TextEditingController` y un `Timer` copiados a mano, y esa
  /// copia es la razon de que cada buscador se portara distinto —«tengo q dar
  /// enter para q el filtro funcione»— y de que al escribir rapido se perdieran
  /// letras: el repintado con el eco de la busqueda anterior reescribia el
  /// campo por detras. Se tecleo `CHAPLIN` y se quedo en `CH`. El arreglo vive
  /// en la pieza compartida, en su `didUpdateWidget`.
  ///
  /// **Sin `trim()` a proposito**: el texto tiene que volver tal cual para que
  /// la caja reconozca su propio eco, y quien busca de verdad ya lo recorta
  /// (`repositorio_rutas.dart`).
  void _buscar(String texto) => _ponerFiltros(_filtros.copiarCon(q: texto));

  /// La sucursal se autocompleta: la del selector de la barra superior, o la
  /// unica que haya (pliego §3, paso 1). Preguntar por algo que sólo tiene una
  /// respuesta posible es un paso de mas en el patio de un almacen.
  void _autocompletarSucursal(List<Sucursal> sucursales) {
    if (_sucursalId != null || sucursales.isEmpty) return;
    final deLaBarra = ref.read(sucursalMiradaProvider);
    final elegida =
        sucursales.where((s) => s.id == deLaBarra).firstOrNull ??
        (sucursales.length == 1 ? sucursales.single : null);
    if (elegida == null) return;
    _sucursalId = elegida.id;
    _filtros = _filtros.copiarCon(sucursalId: elegida.id);
  }

  void _cambiarSucursal(String id) => setState(() {
    // EL ATAJO DE ARRANQUE SE DESARMA EN CUANTO LA PERSONA ELIGE.
    //
    // A partir de aquí el asistente va paso a paso, porque ya no está
    // «resuelto por el alcance»: lo está resolviendo alguien, y el siguiente
    // que le toca decidir es de qué almacén sale el camión.
    _arranqueResuelto = true;
    _sucursalId = id.isEmpty ? null : id;
    // Cambiar de sucursal invalida la salida: un almacen de Holguin no es
    // punto de partida de una ruta de Camaguey. Y lo elegido tampoco vale,
    // porque eran pedidos de la otra.
    _salida = null;
    _elegidos.clear();
    _filtros = FiltrosDisponibles(sucursalId: _sucursalId);
    _camionAMano = false;
  });

  @override
  Widget build(BuildContext context) {
    final sucursales =
        ref.watch(sucursalesProvider).value ?? const <Sucursal>[];
    _autocompletarSucursal(sucursales);

    final sucursal = sucursales.where((s) => s.id == _sucursalId).firstOrNull;
    final codigo = sucursal?.externalId;
    final almacenes = codigo == null
        ? const <Almacen>[]
        : (ref.watch(almacenesProvider(codigo)).value ?? const <Almacen>[]);
    final conUbicacion = [
      for (final a in almacenes)
        if (a.lat != null && a.lng != null) a,
    ];
    // El principal viene primero de la consulta, asi que el primero es el que
    // toca por defecto.
    _salida ??= conUbicacion.firstOrNull;

    // «Si la sucursal y la salida ya vienen resueltas, arranca directamente en
    // el paso 3» (pliego §3). ES UN ATAJO DE ARRANQUE, para quien abre el
    // asistente con todo ya decidido por su alcance.
    //
    // Lo que lo desarma es que la persona elija: ver `_cambiarSucursal`. Sin
    // eso, para un Super Admin —que abre sin sucursal, mirando «todas»— el
    // atajo se quedaba armado, y en cuanto elegía sucursal en el paso 1 la
    // salida se rellenaba sola con la primera y el asistente **saltaba el paso
    // 2**. Visto por Jose el 16/09/2026: «de sucursal pasa directamente a
    // vehiculo me salta salida».
    //
    // Y eso no es una comodidad: es quitarle una decisión. «recuerda q son
    // varios almacenes», y la salida decide desde dónde se miden los kilómetros
    // de toda la ruta.
    if (!_arranqueResuelto && _sucursalId != null && _salida != null) {
      _arranqueResuelto = true;
      _paso = 3;
    }

    final lista = ref.watch(disponiblesProvider(_filtros));
    // LA ZONA DEL TABLERO ES EL ULTIMO FILTRO, Y SE APLICA AQUI.
    //
    // La zona se lee del tablero en cada repintado y no se guarda: si alguien
    // la vacia o la borra mientras el asistente esta abierto, deja de acotar y
    // la lista vuelve a ser la entera. Guardada, seguiria acotando por una zona
    // que ya no existe, y eso son pedidos que no salen sin ninguna razon a la
    // vista.
    // LAS ZONAS YA NO ACOTAN LA LISTA: LA AGRUPAN.
    //
    // Antes, elegir una zona se llevaba por delante todo lo demas —la lista
    // pasaba a ser «solo lo de esta zona»— y eso chocaba con los otros filtros
    // sin decirlo. Ahora la lista es la de siempre y las zonas salen DENTRO,
    // cada una plegable y con su casilla para marcarla entera: lo preparado en
    // el tablero se ve donde se elige, sin esconder el resto.
    final zonas = ref.watch(zonasParaArmarProvider(_sucursalId));
    final disponibles = lista.value ?? const <Pedido>[];
    final peso = _peso;
    final capacidad = _vehiculo?.capacity;
    final sobrepeso = capacidad != null && peso > capacidad;

    final puedeGenerar =
        _salida != null &&
        _vehiculoId != null &&
        _elegidos.isNotEmpty &&
        !sobrepeso &&
        !_generando;

    // Lo que ya está resuelto, que es lo que pinta un tramo de verde y lo que
    // deja volver a él. Un paso «hecho» es uno que tiene respuesta, no uno por
    // el que se pasó: si alguien vuelve al 1 y deja la sucursal en blanco, ese
    // tramo deja de estar hecho y el de después tampoco.
    final hechos = <int, bool>{
      1: _sucursalId != null,
      2: _salida != null,
      3: _vehiculoId != null,
      4: _elegidos.isNotEmpty,
    };

    return AtrasDelCajon(
      // ATRÁS VA AL PASO ANTERIOR, no cierra el asistente. Jose, 28/09/2026:
      // «y tiene q ir al paso anterior de el drawer». En el paso 1 ya no queda
      // paso atrás y el cajón se cierra como siempre.
      //
      // Se envuelve por fuera y no se mete en el `Cajon` porque este asistente
      // NO usa el cajón de `diseno/`: usa el de `pedidos/vista/kit.dart`, que es
      // otra clase con el mismo nombre. El mecanismo es del de diseño y sirve
      // para los dos porque no sabe nada de asistentes: sólo pregunta si queda
      // paso atrás.
      quedaPasoAtras: _paso > 1,
      atras: () => setState(() => _paso -= 1),
      child: Cajon(
        titulo: 'Nueva Ruta',
        // DEBAJO DEL TÍTULO, LA SUCURSAL. Es el dato que manda sobre todo lo
        // demás —los pedidos, los camiones y el punto de partida son los de esa
        // sucursal— y quien abre el asistente tiene que verlo sin buscarlo. En el
        // sitio donde ponía «Paso 3 de 4», que es lo que ya dice la barra de
        // progreso con mucho más detalle.
        subtitulo: sucursal?.name ?? 'Elige la sucursal',
        ancho: AnchoCajon.completo,
        // LA BARRA DE PASOS, PEGADA BAJO LA CABECERA Y FUERA DEL DESPLAZAMIENTO.
        //
        // Es el armazón, no el contenido. En un teléfono el paso 4 no cabe de una
        // vez, y con la barra dentro del cuerpo había que subir por toda la lista
        // de pedidos para poder volver al paso anterior. Jose, 17/09/2026, sobre
        // esta misma trampa en el detalle de ruta: «me corta parte de abajo […]
        // no puedo ver el final». Aquí se desplaza el paso; el marco no.
        bajoLaCabecera: Center(
          child: ConstrainedBox(
            // El mismo ancho máximo que las tarjetas, para que los cuatro tramos
            // caigan justo encima de ellas y no de oreja a oreja del monitor.
            constraints: const BoxConstraints(maxWidth: 1152),
            child: _BarraDePasos(
              actual: _paso,
              hechos: hechos,
              // VIAJAR ENTRE LOS PASOS. Como sólo se pinta el que toca, ésta es
              // la única forma de corregir el anterior sin cancelar y empezar de
              // cero, y lo elegido se conserva: aquí no se limpia nada, sólo se
              // cambia qué tarjeta se enseña.
              alIr: (n) => setState(() => _paso = n),
            ),
          ),
        ),
        // EL PIE, PEGADO ABAJO Y SIEMPRE A LA VISTA. Lo sostiene el `Cajon`; lo
        // que hacía falta era que el cuerpo no creciera sin freno, y eso lo
        // arregla la caja de la lista del paso 4.
        //
        // `spaceBetween` + `Flexible`, y no `Spacer`: a 390 px los dos botones
        // pedían 354 px dentro de 342 y el pie se pasaba 12 px por la derecha —el
        // «Generar Ruta» cortado, que es lo mismo que no estar—. Con `Spacer` no
        // se arregla: el hueco es un hijo flexible más y el botón se quedaría a
        // media anchura también en un monitor.
        pie: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // EL «NO» DEL SERVIDOR, DENTRO DEL CAJÓN Y ENCIMA DEL BOTÓN.
            //
            // Esto salía por `showSnackBar`, y un `SnackBar` lo pinta el
            // `ScaffoldMessenger` de la pantalla de detrás: **debajo del cajón**.
            // O sea que el mensaje existía, se componía con su motivo y no lo veía
            // nadie. Desde fuera —Jose, 22/09/2026, pulsando «Generar Ruta» tres
            // veces seguidas— la aplicación «no hace nada y no dice nada», que es
            // la peor forma de decir que no.
            //
            // Va pegado al botón que lo provocó, a propósito: quien acaba de
            // pulsar está mirando ahí.
            if (_rechazo != null) ...[
              AvisoDeRechazo(
                mensaje: _rechazo!,
                alCerrar: () => setState(() => _rechazo = null),
              ),
              const SizedBox(height: Aire.sm),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: Aire.sm),
                Flexible(
                  child: ControlSenalado(
                    nombre: Senalado.rutasAsistenteGenerar,
                    child: BotonPrincipal(
                      icono: Icons.route_outlined,
                      texto: _generando ? 'Generando ruta...' : 'Generar Ruta',
                      // El rotulo cambia de largo solo y el boton va dentro de un
                      // `Flexible`: a 390 px, sin esto, el renglon se parte.
                      enUnaLinea: true,
                      alPulsar: puedeGenerar ? _generar : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        cuerpo: Center(
          // El `mx-auto max-w-6xl` de la de Next: el cajón va a pantalla completa
          // y sin esto, en un monitor ancho, una frase de ayuda se estira a 1.800
          // px y deja de leerse como un párrafo.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1152),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_paso == 1)
                  _Tarjeta(
                    key: AsistenteNuevaRuta.claveDelPaso(1),
                    numero: 1,
                    titulo: 'Sucursal',
                    hecho: hechos[1]!,
                    hijo: _pasoSucursal(sucursales),
                  ),
                if (_paso == 2)
                  _Tarjeta(
                    key: AsistenteNuevaRuta.claveDelPaso(2),
                    numero: 2,
                    titulo: 'Punto de partida',
                    hecho: hechos[2]!,
                    hijo: _pasoSalida(conUbicacion),
                  ),
                if (_paso == 3)
                  _Tarjeta(
                    key: AsistenteNuevaRuta.claveDelPaso(3),
                    numero: 3,
                    titulo: 'Vehículo',
                    hecho: hechos[3]!,
                    hijo: _pasoVehiculo(),
                  ),
                if (_paso == 4)
                  _Tarjeta(
                    key: AsistenteNuevaRuta.claveDelPaso(4),
                    numero: 4,
                    titulo: 'Pedidos de cliente (${_elegidos.length})',
                    hecho: hechos[4]!,
                    hijo: _pasoPedidos(
                      sucursales: sucursales,
                      disponibles: disponibles,
                      zonas: zonas,
                      cargando: lista.isLoading,
                      peso: peso,
                      capacidad: capacidad,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pasoSucursal(List<Sucursal> sucursales) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ControlSenalado(
        nombre: Senalado.rutasAsistenteSucursal,
        child: Selector<String>(
          titulo: 'Sucursal de la ruta',
          valor: _sucursalId ?? '',
          opciones: [
            const OpcionSelector('', 'Elige la sucursal…'),
            for (final s in sucursales)
              OpcionSelector(s.id, s.name, nota: s.externalId),
          ],
          alElegir: _cambiarSucursal,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Los pedidos, los vehículos y el punto de partida serán los de esta '
        'sucursal.',
        style: TextStyle(color: Colores.gris),
      ),
      const SizedBox(height: 12),
      // El «Siguiente» va DENTRO de la tarjeta, abajo a la derecha: los pasos
      // 1-3 son cortos y el botón del pie es el de generar la ruta entera, que
      // todavía no se puede. Dos botones de avanzar en la misma pantalla, uno
      // arriba y otro abajo, es lo que hacía dudar de cuál era cuál.
      Align(
        alignment: Alignment.centerRight,
        child: ControlSenalado(
          nombre: Senalado.rutasAsistenteSiguiente,
          child: BotonPrincipal(
            // LA FLECHA VA DETRAS DE LA PALABRA. Es lo unico que hace este boton
            // —pasar al paso siguiente— y una flecha que apunta a la derecha,
            // puesta a la IZQUIERDA del rotulo, se lee como «volver». El
            // `Icons.arrow_back` de «Volver a la lista» va delante por lo mismo,
            // al reves.
            icono: Icons.arrow_forward,
            iconoAlFinal: true,
            texto: 'Siguiente',
            alPulsar: _sucursalId == null
                ? null
                : () => setState(() => _paso = 2),
          ),
        ),
      ),
    ],
  );

  Widget _pasoSalida(List<Almacen> conUbicacion) {
    if (conUbicacion.isEmpty) {
      return const _SinSalida(
        texto: AsistenteNuevaRuta.sinAlmacenes,
        boton: AsistenteNuevaRuta.irAAlmacenes,
        icono: Icons.warehouse_outlined,
        adonde: '/warehouses',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // DE CUANDO SON ESTOS ALMACENES. Esta lista sale de la copia del
        // aparato, no de Accesos: aqui se arma sin senal, que es la mitad del
        // dia. Y desde el almacen que se elija se mide lo que se le cobra al
        // cliente por el domicilio, asi que uno retirado que este aparato
        // todavia no sabe que se retiro cobra mal cada entrega del dia.
        //
        // Accesos no da marca de cambio ni dice que borro —por eso los
        // almacenes van en `faltan` y esa decision no se toca—, asi que lo
        // unico que se puede hacer es DECIRLO, con su fecha. Regla 4: si algo
        // puede estar viejo, se dice. En la web esto no pinta nada (regla 1).
        const AlmacenesDeLaUltimaBajada(),
        ControlSenalado(
          nombre: Senalado.rutasAsistenteAlmacen,
          child: Selector<String>(
            titulo: 'Almacén del que sale el camión',
            valor: _salida?.id ?? '',
            opciones: [
              for (final a in conUbicacion)
                OpcionSelector(
                  a.id,
                  a.nombre,
                  nota: a.principal ? 'principal' : null,
                ),
            ],
            alElegir: (id) => setState(
              () => _salida = conUbicacion.where((a) => a.id == id).first,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_salida?.direccion ?? ''}  '
          '${_salida?.lat?.toStringAsFixed(5) ?? ''}, '
          '${_salida?.lng?.toStringAsFixed(5) ?? ''}',
          style: TextStyle(color: Colores.gris),
        ),
        // El mapa de 220 px del pliego queda PENDIENTE: `lib/mapas/` (PLAN.md
        // §4.2) todavia no existe y el detalle de la ruta tampoco lo pinta. Se
        // dicen las coordenadas, que es el dato que el mapa ensenaria, en vez de
        // dejar un hueco gris que parece que algo se rompio.
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: BotonPrincipal(
            icono: Icons.arrow_forward,
            iconoAlFinal: true,
            texto: 'Siguiente',
            alPulsar: () => setState(() => _paso = 3),
          ),
        ),
      ],
    );
  }

  Widget _pasoVehiculo() {
    final todos = ref.watch(vehiculosProvider).value ?? const <Vehiculo>[];

    // Sólo los de la sucursal del paso 1. El porqué, en `vehiculosDeLaSucursal`.
    final vehiculos = vehiculosDeLaSucursal(todos, _sucursalId);

    if (vehiculos.isEmpty) {
      // Se distingue «esta sucursal no tiene camiones» de «no hay ninguno»:
      // lo primero se arregla dando de alta uno EN ESA sucursal, y lo segundo
      // dando de alta el primero. Decir lo mismo en los dos casos manda a
      // buscar donde no es.
      // Y un tercer caso desde que hay bajas: la sucursal TIENE camiones pero
      // ninguno se ofrece (inactivos o en el taller). Decir «no tiene ninguno»
      // seria falso y mandaria a dar de alta uno que ya existe.
      final deEstaSucursal = [
        for (final v in todos)
          if (_sucursalId == null || v.branchId == _sucursalId) v,
      ];
      return _SinSalida(
        texto: todos.isEmpty
            ? AsistenteNuevaRuta.sinVehiculos
            : deEstaSucursal.isNotEmpty
            ? 'Los vehículos de esta sucursal están inactivos o en el taller, '
                  'y a una ruta nueva sólo se asigna un vehículo activo. '
                  'Actívalo o sácalo del taller en Vehículos.'
            : 'Esta sucursal no tiene ningún vehículo dado de alta. Los que '
                  'hay son de otras sucursales, y un camión de otra sucursal no '
                  'está donde sale esta ruta.',
        boton: AsistenteNuevaRuta.irAVehiculos,
        icono: Icons.local_shipping_outlined,
        adonde: '/vehicles',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ControlSenalado(
          nombre: Senalado.rutasAsistenteVehiculo,
          child: Selector<String>(
            titulo: 'Vehículo de la ruta',
            valor: _vehiculoId ?? '',
            opciones: [
              const OpcionSelector('', 'Elige el vehículo…'),
              // Se ofrecen los activos y fuera del taller (`seOfreceParaRutasNuevas`).
              // Los ocupados SI salen, con su nota: un camion en ruta puede tener
              // otra ruta planificada para otro dia, y la pantalla no decide por
              // nadie, solo avisa de como anda cada uno.
              for (final v in vehiculos)
                OpcionSelector(
                  v.id,
                  v.name,
                  nota: switch (v.status) {
                    EstadoVehiculo.enUso =>
                      '${v.capacity.toStringAsFixed(0)} kg · en ruta',
                    _ => '${v.capacity.toStringAsFixed(0)} kg',
                  },
                ),
            ],
            alElegir: (id) => setState(() {
              _vehiculoId = id.isEmpty ? null : id;
              // A MANO. Desde aqui lo elige una persona, y a partir de ese
              // momento una zona del tablero ya no se lo pisa sin decirlo.
              _camionAMano = _vehiculoId != null;
            }),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nombre,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: 'Nombre (el código se genera solo)',
          ),
        ),
        const SizedBox(height: 8),
        // EL CALENDARIO DE LA CASA, no `showDatePicker`.
        //
        // Era una ventana modal centrada, y aquí no hay modales: excepción
        // aprobada el 05/09/2026, escrita en `diseno/rango_de_fechas.dart`, en
        // `pantallas.md` §0 y §9.2 y en el §4 del CLAUDE.md. `CampoDeFecha`
        // ancla el calendario al botón, igual que el `Selector`.
        //
        // Y con ella se va una ventana que además no cuadraba con ninguna otra:
        // abría de `hoy−30 días` a `hoy+365`, mientras el filtro del paso 4 de
        // ESTE MISMO asistente abría a 365 días hacia atrás. Ahora las dos usan
        // la de la casa: 2020 → año que viene.
        //
        // La ✕ se pone aparte porque `CampoDeFecha.alElegir` sólo entrega
        // fechas de verdad: es opcional y tiene que poder volver a «—».
        Row(
          children: [
            Expanded(
              child: CampoDeFecha(
                titulo: 'Fecha de entrega',
                valor: _fechaDeEntrega,
                alElegir: (d) => setState(() => _fechaDeEntrega = d),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: BotonPrincipal(
            icono: Icons.arrow_forward,
            iconoAlFinal: true,
            texto: 'Siguiente',
            alPulsar: _vehiculoId == null
                ? null
                : () => setState(() => _paso = 4),
          ),
        ),
      ],
    );
  }

  /// Los filtros de la lista de elegibles (pliego §3, paso 4).
  ///
  /// **El cuadre con la factura NO esta aqui a proposito**: siempre es `cuadra`,
  /// que es lo unico que el armado acepta. Ofrecer lo que luego se rechaza es
  /// fabricar rechazos tardios.
  /// METE UNA ZONA ENTERA del tablero en la seleccion.
  ///
  /// No mete lo que no puede: un pedido que ya no esta disponible —porque entro
  /// en otra ruta, o porque se archivo desde que se armo el tablero— no se
  /// puede repartir hoy, y meterlo seria fabricar un rechazo al guardar. El que
  /// no cabe en el camion tampoco entra.
  ///
  /// **Lo que se queda fuera se DICE, con el numero y el motivo.** Meter nueve
  /// de doce en silencio es la peor version de esto: quien pulsa la zona cree
  /// que lleva la zona entera y se entera en el almacen, cargando.
  void _meterLaZona(
    String nombre,
    List<String> ids,
    List<Pedido> disponibles, {
    String? delCamion,
    String? devuelveElCamion,
  }) {
    final reparto = repartirLaZona(
      ids: ids,
      disponibles: disponibles,
      yaElegidos: _elegidos.keys.toSet(),
      pesoActual: _peso,
      capacidad: _vehiculo?.capacity,
    );

    setState(() {
      for (final pedido in reparto.entran) {
        _elegidos[pedido.id] = pedido;
      }
    });

    final parte = <String>[
      parteDeLaZona(nombre, ids.length, reparto),
      ?delCamion,
    ].join(' · ');

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(parte),
          // Cuando el camion cambia hay algo que leer y algo que decidir, y
          // cuatro segundos no dan para las dos cosas.
          duration: Duration(seconds: devuelveElCamion == null ? 4 : 10),
          action: devuelveElCamion == null
              ? null
              : SnackBarAction(
                  label: 'Dejar el mío',
                  onPressed: () => _dejarMiCamion(devuelveElCamion),
                ),
        ),
      );
  }

  /// ELEGIR UNA ZONA DEL TABLERO EN EL PASO 4: acota, marca y trae el camion.
  ///
  /// Los tres a la vez y en este orden, que es el gesto entero que pidio Jose:
  ///
  /// 1. **el camion primero**, porque su capacidad es la que decide que cabe, y
  ///    repartir con el camion de antes para cambiarlo despues deja fuera
  ///    pedidos que si cabian;
  /// 2. la zona queda puesta como filtro, asi que **la lista de abajo se queda
  ///    solo con sus pedidos** (`soloDeLaZona`, aplicado en `build`);
  /// 3. y se marcan, con `repartirLaZona`, **la misma regla** que usa «Armar la
  ///    ruta de esta zona» desde el tablero.
  ///
  /// Lo que estuviera elegido de otra zona **no se borra**: se pueden juntar dos
  /// zonas en un camion, y quitarle a alguien lo que habia marcado porque toco
  /// un filtro es la clase de cosa de la que uno se entera cargando. Lo que
  /// queda elegido y fuera de la lista lo dice la linea de resumen, que ya

  /// DESHACER el cambio de camion que trajo la zona.
  ///
  /// **No vuelve a repartir a proposito.** Lo elegido se queda elegido: quien
  /// pulsa esto quiere su camion, no que le deshagan la zona que acaba de
  /// meter. Si con el suyo ya no cabe, la barra de peso lo dice en rojo y el
  /// boton de generar no deja pasar — que es donde tiene que verse, y no
  /// quitando marcas por detras.
  void _dejarMiCamion(String vehiculoId) {
    setState(() {
      _vehiculoId = vehiculoId;
      // Vuelve a ser suyo: la siguiente zona tendra que avisar otra vez.
      _camionAMano = true;
    });
  }

  Widget _barraDeFiltros(List<Sucursal> sucursales) {
    final opciones =
        ref.watch(opcionesDeDisponiblesProvider(_filtros)).value ??
        OpcionesDeDisponibles.vacias;

    // EN UN TELEFONO, UN CAMPO POR LINEA.
    //
    // Esto era un `Wrap` con anchos fijos —220 px el buscador, y cada selector
    // lo que ocupara su texto—. En un escritorio se lee como una barra; en 390
    // px se convierte en un revoltijo de cachos de distinto tamano, con dos
    // controles apretados en una fila y uno solo en la siguiente, y la altura
    // saltando cada vez que un texto crece. Palabras de Jose, 16/09/2026:
    // «esta maldito la organizacion esa de campos ahi para el movil».
    //
    // Por debajo del ancho de la tabla de Pedidos (`Anchos.entrega`, §11) cada
    // control ocupa la linea entera. No es por gusto: un selector a ancho
    // completo se pulsa con el pulgar sin mirar, y ocho controles alineados a
    // la izquierda se recorren de un vistazo. Lo que se gasta es sitio
    // vertical, que en una lista con desplazamiento es lo que sobra.
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.entrega;

    // TODOS LOS CONTROLES, EL MISMO ANCHO. El porqué, en `anchoFiltro`.
    final ancho = estrecho ? double.infinity : AsistenteNuevaRuta.anchoFiltro;
    Widget caja(Widget control) => SizedBox(width: ancho, child: control);

    // La sucursal, a ancho completo y encima de todo lo demás: es la que decide
    // qué pedidos hay, no un filtro más de la fila.
    final deQueSucursal = SizedBox(
      width: double.infinity,
      child: Selector<String>(
        titulo: 'Sucursal de la ruta',
        valor: _sucursalId ?? '',
        opciones: [
          const OpcionSelector('', 'Elige la sucursal…'),
          for (final s in sucursales)
            OpcionSelector(s.id, s.name, nota: s.externalId),
        ],
        alElegir: _cambiarSucursal,
      ),
    );

    final controles = <Widget>[
      // LA ZONA DEL TABLERO, EL PRIMERO DE LOS FILTROS.
      //
      // LAS ZONAS YA NO SON UN FILTRO. Estan DENTRO de la lista de pedidos, cada
      // una plegable y con su casilla para marcarla entera — ver
      // `_agruparPorZonas` mas abajo. Jose, 25/09/2026:
      //
      //     «quitalo de filtro, no lo queria como filtro [...] lo quiero junto
      //      a los pedidos, como los pedidos, pero q salga un dropdown con las
      //      zonas y dentro sus pedidos con un checkbox para marcar todos los
      //      de esa zona: es como tener ya los pedidos preparados»
      //
      // Y tenia razon en el fondo, no solo en la forma: como filtro ESCONDIA lo
      // demas y chocaba con los otros filtros. Con «Solo con domicilio» puesto
      // —que viene por defecto— elegir una zona de 3 pedidos dejaba la lista en
      // «No hay pedidos disponibles para rutear», con el selector diciendo «3
      // pedidos · 61 kg» diez pixeles mas arriba. Dos verdades en la misma
      // pantalla y ninguna explicando a la otra.
      // EL CALENDARIO DE LA CASA, no `showDatePicker`. El mismo motivo y las
      // mismas reglas que el del paso 3, unos cientos de lineas mas arriba: no
      // hay modales en esta aplicacion, y las cuatro ventanas de fechas que
      // habia son ahora una sola (2020 → año que viene).
      CampoDeFecha(
        titulo: 'Día de los pedidos',
        valor: _filtros.dia,
        alElegir: (d) => _ponerFiltros(_filtros.copiarCon(dia: d)),
      ),
      // «Todos los días» es un boton propio y no la opcion vacia del anterior:
      // un selector de fecha no tiene forma de decir «ninguna».
      OutlinedButton(
        onPressed: _filtros.dia == null
            ? null
            : () => _ponerFiltros(_filtros.copiarCon(limpiarDia: true)),
        child: const Text('Todos los días'),
      ),
      // La MISMA caja que Pedidos, Clientes, Vehiculos, Rutas y el Tablero.
      // `ancho: null` porque el ancho lo da el `Wrap` de arriba con `caja()`.
      ControlSenalado(
        nombre: Senalado.rutasAsistenteBuscar,
        child: CajaDeBusqueda(
          valor: _filtros.q,
          ancho: null,
          pista: 'Buscar pedido...',
          alBuscar: _buscar,
        ),
      ),
      Selector<String>(
        titulo: 'Vendedor del pedido',
        valor: _filtros.vendedor,
        // Con buscador SIEMPRE: en una sucursal grande son decenas de
        // vendedores y bajar la lista a mano no es buscar.
        buscadorSiempre: true,
        opciones: [
          const OpcionSelector('', 'Todos los vendedores'),
          for (final v in opciones.vendedores) OpcionSelector(v, v),
        ],
        alElegir: (v) => _ponerFiltros(_filtros.copiarCon(vendedor: v)),
      ),
      Selector<String>(
        titulo: 'Municipio del cliente',
        valor: _filtros.municipio,
        opciones: [
          const OpcionSelector('', 'Todos los municipios'),
          for (final m in opciones.municipios) OpcionSelector(m, m),
        ],
        alElegir: (m) => _ponerFiltros(_filtros.copiarCon(municipio: m)),
      ),
      // LOS DOS TOPES TAMPOCO PIDEN YA INTRO: se aplican al salir del campo.
      //
      // No llevan el respiro de la caja de buscar a proposito: tecleando `12`
      // aplicaria primero `1`, que es un numero valido y deja la lista casi
      // vacia. Un numero se aplica entero o no se aplica. El porque entero, en
      // `caja_de_numero.dart`.
      CajaDeNumero(
        valor: _filtros.kmMax,
        ancho: null,
        pista: 'km máx.',
        alAplicar: (km) => _ponerFiltros(
          _filtros.copiarCon(kmMax: km, limpiarKmMax: km == null),
        ),
      ),
      CajaDeNumero(
        valor: _filtros.costoMin,
        ancho: null,
        pista: 'costo mín.',
        alAplicar: (costo) => _ponerFiltros(
          _filtros.copiarCon(costoMin: costo, limpiarCostoMin: costo == null),
        ),
      ),
      Selector<EstadoDelPedido>(
        titulo: 'Estado del pedido en PEDIDO',
        valor: _filtros.estado,
        opciones: [
          for (final e in EstadoDelPedido.values) OpcionSelector(e, e.etiqueta),
        ],
        alElegir: (e) => _ponerFiltros(_filtros.copiarCon(estado: e)),
      ),
      Selector<DomicilioFiltro>(
        titulo: 'Si el pedido lleva entrega a domicilio',
        valor: _filtros.domicilio,
        opciones: [
          for (final d in DomicilioFiltro.values) OpcionSelector(d, d.etiqueta),
        ],
        alElegir: (d) => _ponerFiltros(_filtros.copiarCon(domicilio: d)),
      ),
      Selector<CotizadoDelDomicilio>(
        titulo: 'Si Entrega ya le puso costo de domicilio',
        valor: _filtros.cotizado,
        opciones: [
          for (final c in CotizadoDelDomicilio.values)
            OpcionSelector(c, c.etiqueta),
        ],
        alElegir: (c) => _ponerFiltros(_filtros.copiarCon(cotizado: c)),
      ),
      OutlinedButton(
        onPressed: () {
          // La caja de buscar se vacia sola: `limpios()` deja `q: ''` y la
          // pieza compartida se pone al dia con lo que venga de fuera.
          // **Vuelve a `domicilio = 1`**, no a «sin nada»: una ruta se arma
          // con lo que hay que llevar a casa, y ese es el arranque del pliego.
          _ponerFiltros(_filtros.limpios());
        },
        child: const Text('Limpiar'),
      ),
    ];

    // Un `Wrap` con TODOS los hijos del mismo ancho sale en columnas
    // alineadas, no en pedazos. En un teléfono ese ancho es la línea entera y
    // el mismo `Wrap` da una fila por control, que es lo que ya hacía falta
    // allí.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        deQueSucursal,
        const SizedBox(height: Aire.sm),
        Wrap(
          spacing: Aire.sm,
          runSpacing: Aire.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [for (final control in controles) caja(control)],
        ),
      ],
    );
  }

  /// LA LISTA, EN ORDEN: primero las zonas del tablero con sus pedidos dentro,
  /// y despues lo que no esta en ninguna.
  ///
  /// Devuelve una lista mezclada de [ZonaParaArmar] (cabeceras) y [Pedido]
  /// (filas) para que el `ListView` siga siendo perezoso: con 295 disponibles,
  /// construir de golpe las 295 filas para ensenar seis es justo lo que esta
  /// caja vino a evitar.
  ///
  /// UNA ZONA SIN PEDIDOS VISIBLES SALE IGUAL, Y DICE POR QUE.
  ///
  /// La primera version la escondia, con el argumento de que una cabecera que
  /// dice «3 pedidos» encima de cero filas es una contradiccion. El argumento
  /// era bueno y la conclusion mala: escondida, el trabajo del tablero
  /// desaparece sin dejar rastro. Probado en el telefono de Jose — preparo la
  /// zona «Centro» con 3 pedidos, entro a armar la ruta y no habia ninguna
  /// zona, porque el filtro «Solo con domicilio» que viene puesto por defecto
  /// se los comia.
  ///
  /// Ni esconder ni mentir: la zona sale, con su casilla apagada y con la
  /// razon escrita —«los 3 estan fuera por los filtros»—. Es la regla de la
  /// casa: nada se descarta en silencio.
  List<Object> _agruparPorZonas(
    List<ZonaParaArmar> zonas,
    List<Pedido> disponibles,
  ) {
    final enAlgunaZona = <String>{};
    final filas = <Object>[];

    for (final zona in zonas) {
      final suyos = [
        for (final p in disponibles)
          if (zona.ids.contains(p.id)) p,
      ];
      for (final p in suyos) {
        enAlgunaZona.add(p.id);
      }
      filas.add(zona);
      // SIEMPRE DESPLEGADAS. Se probó con las zonas plegadas y Jose lo cortó en
      // seco: «las zonas primero, siempre desplegadas y ya». Y tiene razón —
      // plegada, una zona obliga a un toque más para ver lo que lleva, y lo que
      // lleva es justo lo que hay que mirar antes de cargarlo en el camión.
      filas.addAll(suyos);
    }

    for (final p in disponibles) {
      if (!enAlgunaZona.contains(p.id)) filas.add(p);
    }
    return filas;
  }

  /// El camion previsto de la zona, si lo tiene y no se eligio otro a mano.
  void _traerElCamionDeLaZona(ZonaParaArmar zona) {
    final todos = ref.read(vehiculosProvider).value ?? const <Vehiculo>[];
    final camion = camionDeLaZona(
      zona: zona,
      elegidoId: _vehiculoId,
      elegidoNombre: _vehiculo?.name,
      elegidoAMano: _camionAMano,
      vehiculosDeLaRuta: vehiculosDeLaSucursal(todos, _sucursalId),
      noSeOfrecen: {
        for (final v in todos)
          if (!seOfreceParaRutasNuevas(v)) v.id,
      },
    );
    if (camion.vehiculoId != null && camion.vehiculoId != _vehiculoId) {
      _vehiculoId = camion.vehiculoId;
    }
  }

  Widget _pasoPedidos({
    required List<Sucursal> sucursales,
    required List<Pedido> disponibles,
    required List<ZonaParaArmar> zonas,
    required bool cargando,
    required double peso,
    required double? capacidad,
  }) {
    final renglones =
        ref.watch(renglonesDeDisponiblesProvider(_filtros)).value ??
        const <String, List<RenglonConPeso>>{};

    final visibles = {for (final p in disponibles) p.id};
    // Los elegidos que ya no salen con los filtros de ahora. Siguen contando: su
    // peso va en el camion igual.
    final fueraDeLaLista = _elegidos.keys
        .where((id) => !visibles.contains(id))
        .length;

    // EL CUERPO DE LA CAJA DE LA LISTA. Los tres casos van DENTRO de la caja,
    // no en su lugar: si el vacío o el «Cargando…» se pintaran fuera, la caja
    // aparecería y desaparecería y lo de debajo daría saltos.
    final Widget dentroDeLaCaja;
    if (cargando && disponibles.isEmpty) {
      dentroDeLaCaja = const Padding(
        padding: EdgeInsets.all(Aire.lg),
        child: Text(AsistenteNuevaRuta.cargandoPedidos),
      );
    } else if (disponibles.isEmpty) {
      dentroDeLaCaja = const EstadoVacio(AsistenteNuevaRuta.sinPedidos);
    } else {
      // `ListView` y no una `Column`: con 295 pedidos una `Column` construye
      // las 295 filas para enseñar seis. Y `shrinkWrap` para que con tres
      // pedidos la caja mida lo que miden los tres, no los 320 px del tope.
      // LO PREPARADO EN EL TABLERO, ARRIBA Y PLEGADO.
      //
      // Cada zona es una cabecera con su casilla: marcarla mete TODOS sus
      // pedidos de una, que es justo lo que el tablero vino a ahorrar. Debajo,
      // plegados, sus pedidos, por si hay que quitar alguno. Y al final los que
      // no estan en ninguna zona, que siguen saliendo como siempre.
      final filas = _agruparPorZonas(zonas, disponibles);

      dentroDeLaCaja = ListView.builder(
        controller: _desplazamientoDeLaLista,
        primary: false,
        padding: const EdgeInsets.symmetric(vertical: Aire.xs),
        shrinkWrap: true,
        itemCount: filas.length,
        itemBuilder: (contexto, i) {
          final fila = filas[i];

          if (fila is ZonaParaArmar) {
            final suyos = disponibles
                .where((p) => fila.ids.contains(p.id))
                .toList();
            final marcados = suyos.where((p) => _elegidos.containsKey(p.id));
            return _CabeceraDeZona(
              zona: fila,
              enLaLista: suyos.length,
              marcados: marcados.length,
              alMarcarTodos: () {
                // Sin ninguno a la vista no hay nada que marcar. La cabecera ya
                // dice por que, y ahi el gesto util es quitar los filtros.
                if (suyos.isEmpty) return;
                // DESMARCAR es simple: fuera los suyos y ya.
                if (marcados.length == suyos.length) {
                  setState(() {
                    for (final p in suyos) {
                      _elegidos.remove(p.id);
                    }
                  });
                  return;
                }
                // MARCAR pasa por `_meterLaZona`, que es quien sabe lo que NO
                // puede entrar —lo que ya va en otra ruta, lo que se archivo,
                // lo que no cabe en el camion— y, sobre todo, quien lo DICE con
                // su numero y su motivo. Meter nueve de doce en silencio es la
                // peor version de esto: se cree que va la zona entera y se
                // descubre en el almacen, cargando.
                _traerElCamionDeLaZona(fila);
                _meterLaZona(fila.nombre, fila.ids, disponibles);
              },
            );
          }

          final pedido = fila as Pedido;
          return _FilaDisponible(
            pedido: pedido,
            renglones: renglones[pedido.id] ?? const <RenglonConPeso>[],
            marcado: _elegidos.containsKey(pedido.id),
            // Lo que no cabe se deshabilita con el motivo a la vista, no se
            // esconde: esconderlo haria pensar que el pedido no existe.
            cabe:
                capacidad == null ||
                _elegidos.containsKey(pedido.id) ||
                peso + pedido.weight <= capacidad,
            alMarcar: () => setState(() {
              if (_elegidos.remove(pedido.id) == null) {
                _elegidos[pedido.id] = pedido;
              }
            }),
          );
        },
      );
    }

    final columnaLista = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _barraDeFiltros(sucursales),
        const SizedBox(height: Aire.md),
        _BarraDePeso(peso: peso, capacidad: capacidad),
        const SizedBox(height: Aire.md),
        Text(
          // «y zonas» porque la lista ya no es solo pedidos sueltos: arriba van
          // las zonas del tablero y debajo lo que no esta en ninguna. Cada
          // pedido sale UNA vez —o dentro de su zona, o en el rabo—, que es lo
          // que pidio Jose: «ya los disponibles no se pueden repetir, o estan
          // en una zona o sin asignar; asi vemos todo mas rapido».
          'Pedidos disponibles y zonas (${disponibles.length})',
          style: Tipos.texto(tamano: 13, peso: FontWeight.w600),
        ),
        const SizedBox(height: Aire.xs),
        // LA LISTA, EN SU PROPIA CAJA Y CON SU PROPIO DESPLAZAMIENTO.
        //
        // Ésta es la pieza que arregla la queja entera. Antes las filas colgaban
        // de esta misma columna, así que la columna medía lo que midieran los
        // pedidos: con 295, el resumen de debajo quedaba a tres pantallas de
        // distancia y había que recorrerlas para llegar a él. Acotada, la lista
        // se desplaza DENTRO y todo lo que va debajo se queda donde está.
        Container(
          key: AsistenteNuevaRuta.claveDeLaLista,
          constraints: const BoxConstraints(
            maxHeight: AsistenteNuevaRuta.altoDeLaLista,
          ),
          decoration: BoxDecoration(
            color: Colores.blanco,
            border: Border.all(color: Colores.linea),
            borderRadius: BorderRadius.circular(Radios.lg),
          ),
          clipBehavior: Clip.antiAlias,
          // El `Material` es obligatorio, no decorativo: un `CheckboxListTile`
          // pinta su fondo y su onda en el `Material` más cercano, y sin éste
          // ese más cercano queda DETRÁS del recuadro de la caja, así que la
          // fila marcada no se vería marcada. Flutter lo dice en voz alta.
          child: Material(
            type: MaterialType.transparency,
            child: dentroDeLaCaja,
          ),
        ),
        const SizedBox(height: Aire.sm),
        // LA LÍNEA DE RESUMEN, justo debajo de la caja y siempre en el mismo
        // sitio: cuántos van a la izquierda y cuánto pesan a la derecha.
        Row(
          key: AsistenteNuevaRuta.claveDelResumen,
          children: [
            Expanded(
              child: Text(
                '${_elegidos.length} '
                '${_elegidos.length == 1 ? 'pedido seleccionado' : 'pedidos seleccionados'}'
                '${fueraDeLaLista == 0 ? '' : ' ($fueraDeLaLista de otro día o filtro, siguen contando)'}',
                style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
              ),
            ),
            const SizedBox(width: Aire.sm),
            Text(
              '${peso.toStringAsFixed(1)} / '
              '${capacidad?.toStringAsFixed(0) ?? '—'} kg',
              style: Tipos.mono(
                tamano: 12,
                peso: FontWeight.w600,
                color: capacidad != null && peso > capacidad
                    ? Colores.rojo
                    : Colores.tintaSuave,
              ),
            ),
          ],
        ),
        if (capacidad != null && peso > capacidad)
          Text(
            'Peso (${peso.toStringAsFixed(1)} kg) supera capacidad del '
            'vehículo (${capacidad.toStringAsFixed(0)} kg)',
            style: TextStyle(color: Colores.rojo),
          ),
      ],
    );

    final columnaPreDespacho = _PreDespachoLateral(
      elegidos: _elegidos.keys.toList(),
      pesoKg: peso,
      capacidad: capacidad,
      sucursal: sucursales.where((s) => s.id == _sucursalId).firstOrNull?.name,
      vehiculo: _vehiculo?.name,
      dia: _filtros.dia,
    );

    // Dos columnas —lista a la izquierda, pre-despacho a la derecha— y una sola
    // cuando no caben las dos sin partir palabras. Lo que se mide es el ancho
    // DE LA TARJETA, no el de la pantalla: la tarjeta vive dentro del cajón y
    // con sus márgenes, y en un portátil de 1.100 px la pantalla dice
    // «escritorio» mientras aquí dentro quedan 900 y pico.
    return LayoutBuilder(
      builder: (contexto, medidas) {
        if (medidas.maxWidth < AsistenteNuevaRuta.anchoDosColumnas) {
          // EN EL MÓVIL EL PRE-DESPACHO VA EN SU CAJÓN — 22/09/2026.
          //
          // Aquí colgaba debajo de la lista, y la lista son doscientos y pico
          // pedidos: para llegar al pre-despacho había que bajar por todos
          // ellos peleándose con dos desplazamientos —el de la lista y el del
          // paso—, con el pie fijo abajo tapando el final. Jose: «y el
          // pre-despacho, que no lo veo».
          //
          // Cajón, como todo lo de este proyecto en móvil. Y el botón lleva
          // dentro lo que hay, para que no haya que abrirlo sólo para ver si
          // hay algo.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              columnaLista,
              const SizedBox(height: Aire.lg),
              Divider(height: 1, thickness: 1, color: Colores.linea),
              const SizedBox(height: Aire.lg),
              _BotonDePreDespacho(
                elegidos: _elegidos.length,
                alAbrir: () => _abrirPreDespacho(contexto, columnaPreDespacho),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: columnaLista),
            const SizedBox(width: Aire.xl),
            SizedBox(
              width: AsistenteNuevaRuta.anchoPreDespacho,
              child: columnaPreDespacho,
            ),
          ],
        );
      },
    );
  }

  /// Abre el pre-despacho en su propio cajón. Es **el mismo cajón** que abre el
  /// botón de Pedidos (`pedidos/vista/vista_pre_despacho.dart`): mismo título,
  /// mismas cuentas en el subtítulo, misma tabla y mismo `Ver e imprimir` en el
  /// pie. Dos pre-despachos distintos serían dos papeles distintos para el
  /// mismo almacén.
  void _abrirPreDespacho(
    BuildContext contexto,
    _PreDespachoLateral preDespacho,
  ) {
    unawaited(abrirCajon<void>(contexto, (_) => preDespacho.cajon()));
  }

  Future<void> _generar() async {
    // El «no» de antes se quita al volver a intentarlo: dejarlo puesto encima
    // del botón mientras se está generando diría que acaba de fallar otra vez.
    setState(() {
      _generando = true;
      _rechazo = null;
    });
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final navegador = Navigator.of(context);
    try {
      final rutaId = await ref
          .read(accionesDeRutaProvider)
          .armar(
            vehiculoId: _vehiculoId,
            pedidoIds: _elegidos.keys.toList(),
            origenLat: _salida?.lat,
            origenLng: _salida?.lng,
            nombre: _nombre.text.trim().isEmpty ? null : _nombre.text.trim(),
            origenDireccion: _salida?.direccion ?? _salida?.nombre,
            sucursalId: _sucursalId,
            fechaDeEntrega: _fechaDeEntrega,
          );
      // Se selecciona sola, igual que en la de Next.
      ref.read(rutaElegidaProvider.notifier).elegir(rutaId);
      navegador.maybePop();
    } on RechazoLocal catch (fallo) {
      // DENTRO del cajón, que es donde está mirando quien pulsó. Y también por
      // el mensajero, para quien tenga el cajón a pantalla completa en un
      // monitor y el pie fuera de su vista.
      if (mounted) setState(() => _rechazo = fallo.mensaje);
      mensajero?.showSnackBar(SnackBar(content: Text(fallo.mensaje)));
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }
}

/// LA BARRA DE PROGRESO: cuatro tramos a lo ancho, uno por paso.
///
/// No es adorno. Con un paso a la vista, sin esto no se sabe si quedan dos o
/// siete; y sobre todo, **es por donde se vuelve atrás**. Eran cuatro enlaces
/// de texto en un `Wrap` —«eso que hay ahí es un wizard, no la mierda que
/// hiciste tú»—, y un enlace de texto no dice ni cuánto llevas ni cuánto falta.
///
/// Los colores dicen tres cosas distintas: **verde** lo que ya tiene respuesta,
/// el color de la marca el paso en el que estás si todavía no la tiene, y gris
/// lo que ni siquiera se puede pulsar. Un tramo hecho se pulsa y se vuelve a él.
class _BarraDePasos extends StatelessWidget {
  const _BarraDePasos({
    required this.actual,
    required this.hechos,
    required this.alIr,
  });

  final int actual;
  final Map<int, bool> hechos;
  final void Function(int) alIr;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final paso in AsistenteNuevaRuta.pasos.entries) ...[
        if (paso.key > 1) const SizedBox(width: Aire.xs),
        Expanded(child: _tramo(paso.key, paso.value)),
      ],
    ],
  );

  Widget _tramo(int numero, String nombre) {
    final hecho = hechos[numero] ?? false;
    final esElActual = numero == actual;
    // Se puede pulsar lo que ya está resuelto y el paso en el que se está. Un
    // paso de más adelante sin resolver no lleva a ninguna parte: saltar al 4
    // sin camión elegido es una pantalla que no se puede terminar.
    final sePuedePulsar = hecho || esElActual;
    final color = hecho
        ? Colores.verde
        : (esElActual ? Colores.primario : Colores.linea);

    return Tooltip(
      message: hecho ? 'Volver a $nombre' : nombre,
      child: InkWell(
        key: AsistenteNuevaRuta.claveDelTramo(numero),
        onTap: sePuedePulsar ? () => alIr(numero) : null,
        borderRadius: BorderRadius.circular(Radios.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(Radios.pastilla),
              ),
            ),
            const SizedBox(height: Aire.xs),
            Text(
              nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tipos.texto(
                tamano: 11,
                peso: esElActual ? FontWeight.w700 : FontWeight.w400,
                color: esElActual ? Colores.tinta : Colores.tintaSuave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// LA TARJETA DEL PASO: el número en su círculo, el título, y dentro el paso.
///
/// Una sola, la del paso que toca. Estaban las cuatro a la vez —tres apagadas y
/// sin poder pulsarse— y eran cuatro cajas grises que no decían qué hacer.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.numero,
    required this.titulo,
    required this.hecho,
    required this.hijo,
    super.key,
  });

  final int numero;
  final String titulo;
  final bool hecho;
  final Widget hijo;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colores.blanco,
      border: Border.all(color: Colores.linea),
      borderRadius: BorderRadius.circular(Radios.xl),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(Aire.md),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hecho ? Colores.verde : Colores.primario,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$numero',
                  style: Tipos.texto(
                    tamano: 12,
                    peso: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: Aire.sm),
              Expanded(
                child: Text(
                  titulo,
                  style: Tipos.texto(
                    tamano: 15,
                    peso: FontWeight.w700,
                    color: Colores.tinta,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: Colores.linea),
        Padding(padding: const EdgeInsets.all(Aire.md), child: hijo),
      ],
    ),
  );
}

/// LA BARRA DE PESO: `115.6 / 10000 kg (1%)` y debajo la barra de verdad.
///
/// El número solo no se lee de un vistazo cuando uno está cargando un camión;
/// la barra sí, y es la misma de la de Next: verde hasta el 80 %, ámbar entre
/// el 80 y el 100, y roja con su «LLENO» al pasarse.
class _BarraDePeso extends StatelessWidget {
  const _BarraDePeso({required this.peso, required this.capacidad});

  final double peso;
  final double? capacidad;

  @override
  Widget build(BuildContext context) {
    final capacidad = this.capacidad;
    if (capacidad == null) {
      return Text(
        'Elige un vehículo para ver la capacidad',
        style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
      );
    }
    final porcentaje = capacidad == 0 ? 0.0 : (peso / capacidad) * 100;
    final color = porcentaje >= 100
        ? Colores.rojo
        : (porcentaje >= 80 ? Colores.ambar : Colores.verde);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${peso.toStringAsFixed(1)} / ${capacidad.toStringAsFixed(0)} '
                'kg (${porcentaje.toStringAsFixed(0)}%)',
                style: Tipos.mono(
                  tamano: 12,
                  peso: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (porcentaje >= 100) Insignia('LLENO', color: Colores.rojo),
          ],
        ),
        const SizedBox(height: Aire.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radios.pastilla),
          child: LinearProgressIndicator(
            value: (porcentaje / 100).clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: Colores.grisFondo,
            color: color,
          ),
        ),
        if (porcentaje >= 100)
          Padding(
            padding: const EdgeInsets.only(top: Aire.xs),
            child: Text(
              'Camión lleno — no cabe más',
              style: Tipos.texto(tamano: 12, color: Colores.rojo),
            ),
          ),
      ],
    );
  }
}

class _FilaDisponible extends StatelessWidget {
  const _FilaDisponible({
    required this.pedido,
    required this.renglones,
    required this.marcado,
    required this.cabe,
    required this.alMarcar,
  });

  final Pedido pedido;
  final List<RenglonConPeso> renglones;
  final bool marcado;
  final bool cabe;
  final VoidCallback alMarcar;

  /// Los articulos, resumidos: el primero con sus empaques y `+n` por el resto,
  /// y la lista entera en el tooltip. Es el mismo resumen de la tabla de
  /// Pedidos, para que el mismo pedido se lea igual en las dos pantallas.
  String get _articulos {
    if (renglones.isEmpty) return '';
    final primero = renglones.first;
    final resto = renglones.length - 1;
    return '${primero.renglon.description} ×${cantidad(primero.empaques)}'
        '${resto > 0 ? '  +$resto' : ''}';
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: cabe
        ? [
            for (final r in renglones)
              '${r.renglon.description} ×${cantidad(r.empaques)}',
          ].join('\n')
        : 'No cabe en el camión',
    child: CheckboxListTile(
      dense: true,
      value: marcado,
      onChanged: cabe ? (_) => alMarcar() : null,
      title: Text(pedido.customerName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${pedido.endAddress ?? pedido.address} · ${kg(pedido.weight)} · '
            // `usd` ya dice `sin cotizar` cuando no hay precio: un `$0.00`
            // seria «este domicilio es gratis», que es otra cosa.
            '${usd(pedido.pedidoCosto)}',
          ),
          if (_articulos.isNotEmpty)
            Text(
              _articulos,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colores.gris, fontSize: 12),
            ),
        ],
      ),
    ),
  );
}

/// El pre-despacho que se suma en vivo segun se van eligiendo pedidos.
class _PreDespachoLateral extends ConsumerWidget {
  const _PreDespachoLateral({
    required this.elegidos,
    required this.pesoKg,
    required this.capacidad,
    required this.sucursal,
    required this.vehiculo,
    required this.dia,
  });

  final List<String> elegidos;
  final double pesoKg;
  final double? capacidad;
  final String? sucursal;
  final String? vehiculo;
  final DateTime? dia;

  /// El dia tal y como lo escribe la hoja de Next: `AAAA-MM-DD`. Se compara
  /// caracter a caracter con la suya, asi que no pasa por `DateFormat` local.
  String? get _diaDeLaHoja => dia == null
      ? null
      : '${dia!.year.toString().padLeft(4, '0')}-'
            '${dia!.month.toString().padLeft(2, '0')}-'
            '${dia!.day.toString().padLeft(2, '0')}';

  /// La suma, en vivo. `null` mientras no hay nada elegido o todavía se está
  /// sumando.
  TotalesPreDespacho? totalesDe(WidgetRef ref) => elegidos.isEmpty
      ? null
      : ref
            .watch(
              preDespachoDeLoElegidoEnElAsistenteProvider(
                ([...elegidos]..sort()).join(','),
              ),
            )
            .value;

  /// EL CAJÓN DEL MÓVIL, con **el mismo cuerpo** que la columna de escritorio y
  /// el mismo que el pre-despacho de Pedidos. Dos pre-despachos distintos serían
  /// dos papeles distintos para el mismo almacén.
  Widget cajon() => Consumer(
    builder: (contexto, ref, _) {
      final totales = totalesDe(ref);
      return CajonDePreDespacho(
        totales: totales,
        pie: totales == null ? null : _resumen(),
        alImprimir: totales == null
            ? null
            : () => _verEImprimir(contexto, totales),
      );
    },
  );

  /// Lo que el asistente añade debajo de la tabla y Pedidos no tiene: el peso
  /// contra la **capacidad del vehículo**, que es de la ruta y no del almacén.
  ///
  /// Los empaques, las unidades y los dos pesos ya los pone
  /// `TotalesDelPreDespacho` dentro de la vista, con su rótulo cada uno.
  /// Repetirlos aquí era pintar los mismos números dos veces con nombres
  /// distintos, que es de donde salen los «tres números para lo mismo».
  Widget _resumen() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Pedidos elegidos: ${elegidos.length}'),
      Text(
        'Capacidad del vehículo: ${pesoKg.toStringAsFixed(1)} / '
        '${capacidad?.toStringAsFixed(0) ?? '—'} kg',
      ),
    ],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La caja está SIEMPRE, con su título y su botón: es el sitio donde se mira
    // lo que hay que sacar del almacén, y un sitio que aparece y desaparece
    // según lo que lleves elegido no se aprende. Lo que cambia es lo de dentro.
    final totales = totalesDe(ref);

    final Widget dentro;
    if (elegidos.isEmpty) {
      dentro = Text(
        AsistenteNuevaRuta.preDespachoVacio,
        style: TextStyle(color: Colores.gris),
      );
    } else if (totales == null) {
      dentro = const Text(AsistenteNuevaRuta.cargandoPedidos);
    } else {
      // LA MISMA TABLA QUE PEDIDOS — 22/09/2026.
      //
      // Aquí había una tabla propia de TRES columnas (`Producto`, `Emp.`,
      // `Uds.`), sin los kg, con otros rótulos y con el aire de `DataTable` sin
      // tocar. La de Pedidos tenía cuatro. Eran dos pre-despachos parecidos
      // para el mismo almacén, que es exactamente como acaban siendo dos
      // papeles distintos.
      dentro = VistaPreDespacho(totales: totales, pie: _resumen());
    }

    return Container(
      key: AsistenteNuevaRuta.claveDelPreDespacho,
      padding: const EdgeInsets.all(Aire.md),
      decoration: BoxDecoration(
        color: Colores.ambarFondo,
        border: Border.all(color: Colores.linea),
        borderRadius: BorderRadius.circular(Radios.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pre-despacho',
                  style: Tipos.texto(tamano: 13, peso: FontWeight.w700),
                ),
              ),
              OutlinedButton(
                onPressed: totales == null
                    ? null
                    : () => _verEImprimir(context, totales),
                child: const Text('Ver e imprimir'),
              ),
            ],
          ),
          const SizedBox(height: Aire.sm),
          dentro,
        ],
      ),
    );
  }

  /// La hoja con la que alguien baja al almacen. Se mira primero y se imprime
  /// desde la propia vista previa: es el orden que tenia la de Next y el que
  /// tiene sentido cuando el que saca la mercancia es otra persona.
  void _verEImprimir(BuildContext context, TotalesPreDespacho totales) {
    final hoja = hojaDePreDespachoDeLaRuta(
      totales: totales,
      sucursal: sucursal ?? '',
      vehiculo: vehiculo ?? '',
      dia: _diaDeLaHoja,
      pedidos: elegidos.length,
      pesoKg: pesoKg,
    );

    abrirCajon<void>(
      context,
      (contexto) => Cajon(
        // `Hoja de pre-despacho`: la vista previa del PDF se abre ENCIMA de la
        // vista del pre-despacho, y con los dos cajones apilados y el mismo
        // título no hay forma de saber cuál se está mirando.
        titulo: PreDespacho.tituloDeLaHoja,
        subtitulo:
            '${elegidos.length} pedido(s) · '
            '${pesoKg.toStringAsFixed(1)} kg',
        ancho: AnchoCajon.xl,
        // EL ALTO SALE DE LA PANTALLA, NO DE UN NÚMERO ESCRITO A MANO.
        //
        // La vista previa quiere todo el alto que le den y el cuerpo del cajón
        // es un desplazable, así que hay que darle uno concreto o la hoja no se
        // pinta. Aquí había un `640` fijo, y a 390x844 el cuerpo útil del cajón
        // ronda los 635: la caja no cabía, y entonces son dos desplazamientos
        // verticales, uno dentro del otro. Con el dedo encima manda el de
        // dentro, el de fuera no se mueve nunca, y la parte de abajo de la hoja
        // **no se alcanza jamás**. El mismo `0.75` que usan las otras dos hojas
        // (Pedidos y el post-despacho del cierre).
        cuerpo: SizedBox(
          height: MediaQuery.sizeOf(contexto).height * 0.75,
          child: VistaPreviaPdf(
            armar: (formato) => pdfPreDespacho(hoja, impresoEn: DateTime.now()),
            nombreDeFichero: 'pre-despacho.pdf',
          ),
        ),
      ),
    );
  }
}

/// UN PASO QUE NO SE PUEDE TERMINAR, CON SU SALIDA.
///
/// Dice qué falta y **lleva al sitio donde se arregla**, cerrando el asistente
/// antes: dejarlo abierto encima de la pantalla a la que se acaba de ir es un
/// cajón tapando justo lo que se venía a hacer.
///
/// Es el mismo criterio del paso a paso del Panel
/// (`lib/pantallas/panel/vista/paso_a_paso.dart`): **botón sólo cuando lleva a
/// donde el problema de verdad se toca**. Lo que no se arregla desde esta
/// aplicación —la tasa, que la mantiene Accesos— no lleva botón, se dice a
/// quién pedírselo; un botón que lleva a un sitio donde el problema no se
/// arregla es peor que no tenerlo.
///
/// **Y no da de alta el camión aquí mismo**, aunque el cajón de Vehículos
/// exista: esa pantalla vive de la red (`POST /api/vehicles`) y el asistente
/// lee la flota de la BASE LOCAL, la que deja la bajada del día. Un camión
/// creado desde aquí no aparecería en el desplegable de al lado hasta la
/// siguiente sincronización, o sea que el paso seguiría sin poder terminarse y
/// encima sin decir por qué.
class _SinSalida extends StatelessWidget {
  const _SinSalida({
    required this.texto,
    required this.boton,
    required this.icono,
    required this.adonde,
  });

  final String texto;
  final String boton;

  /// EL GLIFO DE A DONDE LLEVA, y por eso lo pone quien lo usa y no este widget:
  /// los dos sitios donde se cae aqui son distintos —el camion y el almacen— y
  /// un icono unico diria que los dos llevan al mismo sitio.
  final IconData icono;

  final String adonde;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(texto, style: TextStyle(color: Colores.gris)),
      const SizedBox(height: 12),
      BotonPrincipal(
        icono: icono,
        texto: boton,
        alPulsar: () {
          // El router se coge ANTES de cerrar: despues de `pop` este
          // `context` ya no esta montado y `context.go` reventaria.
          final ir = GoRouter.of(context);
          Navigator.of(context).maybePop();
          ir.go(adonde);
        },
      ),
    ],
  );
}

/// El pre-despacho del asistente.
///
/// El argumento es la lista de ids **ordenada y unida por comas**, y no la lista
/// suelta, porque un `family` compara sus argumentos con `==` y dos `List` con el
/// mismo contenido no son iguales en Dart: con la lista cruda se crearia un
/// provider nuevo en cada repintado y la suma se reharia sin que nada hubiera
/// cambiado.
final preDespachoDeLoElegidoEnElAsistenteProvider =
    FutureProvider.family<TotalesPreDespacho, String>(
      (ref, clave) => ref
          .watch(consultasPedidosProvider)
          .preDespachoDe(clave.isEmpty ? const [] : clave.split(',')),
    );

/// LAS ZONAS DEL TABLERO, ahora en la fila de filtros del paso 4.
///
/// Eran unas fichas encima de los filtros: una por zona, y pulsarla metia sus
/// pedidos en lo elegido. Se quedaron cortas y **son el desplegable de
/// `selector_de_zona.dart`** desde el 22/09/2026, con lo que faltaba:
///
/// > «tengo un seleccionar con dropdown q tenga todos los pedidos y de ahi
/// > selecciono el tablero y ya selecciono los pedidos de ese tablero ya
/// > tendria el camion preparado»
///
/// La ficha marcaba y ya: la lista seguia entera, asi que habia que buscar a
/// mano cuales eran los de la zona, y **el camion previsto de la zona se
/// quedaba en el tablero**. Ahora elegir la zona acota la lista, la marca y
/// trae su camion (`_elegirLaZona`). No se dejan las dos: dos maneras de sacar
/// los pedidos de una zona dan dos resultados distintos el dia que una se quede
/// atras.

/// El botón que abre el pre-despacho en el móvil, con lo que hay dentro.
///
/// Dice cuántos pedidos van contados para que no haya que abrirlo sólo para
/// ver si hay algo, y se apaga sin ninguno: un cajón vacío no es una hoja.
class _BotonDePreDespacho extends StatelessWidget {
  const _BotonDePreDespacho({required this.elegidos, required this.alAbrir});

  final int elegidos;
  final VoidCallback alAbrir;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ControlSenalado(
        nombre: Senalado.rutasPreDespacho,
        child: OutlinedButton.icon(
          key: AsistenteNuevaRuta.claveDelBotonDePreDespacho,
          onPressed: elegidos == 0 ? null : alAbrir,
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          label: Text(
            elegidos == 0
                ? 'Pre-despacho — elige pedidos primero'
                : 'Pre-despacho de los $elegidos elegidos',
          ),
        ),
      ),
    );
  }
}

/// LA CABECERA DE UNA ZONA DEL TABLERO, dentro de la lista de disponibles.
///
/// Es lo que convierte «elegir 12 pedidos uno a uno» en «marcar una zona». El
/// tablero es la preparación del día —se hace con el mapa delante, los
/// kilómetros al almacén y el peso— y aquí es donde se cobra ese trabajo.
/// Jose, 25/09/2026:
///
///     «lo quiero junto a los pedidos, como los pedidos, pero q salga un
///      dropdown con las zonas y dentro sus pedidos con un checkbox para marcar
///      todos los de esa zona: es como tener ya los pedidos preparados»
///
/// La casilla tiene TRES estados y los tres dicen algo distinto: vacía —no hay
/// nada de esta zona—, llena —va entera— y a medias, que es la que importa:
/// alguien quitó uno a mano, o uno no cabía en el camión. Una casilla de dos
/// estados diría «no está entera» y «no hay nada» con el mismo dibujo.
class _CabeceraDeZona extends StatelessWidget {
  const _CabeceraDeZona({
    required this.zona,
    required this.enLaLista,
    required this.marcados,
    required this.alMarcarTodos,
  });

  final ZonaParaArmar zona;

  /// Cuántos de la zona están en la lista de AHORA. Puede ser menos que
  /// `zona.pedidos`: alguno pudo entrar en otra ruta desde que se armó el
  /// tablero, y ése ya no se puede repartir hoy.
  final int enLaLista;
  final int marcados;
  final VoidCallback alMarcarTodos;

  @override
  Widget build(BuildContext context) {
    final todos = marcados == enLaLista && enLaLista > 0;
    final algunos = marcados > 0 && !todos;

    return Material(
      color: Colores.papel,
      child: InkWell(
        onTap: alMarcarTodos,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Aire.sm,
            vertical: Aire.sm,
          ),
          child: Row(
            children: [
              Checkbox(
                value: algunos ? null : todos,
                tristate: true,
                onChanged: (_) => alMarcarTodos(),
              ),
              const SizedBox(width: Aire.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      zona.nombre,
                      style: Tipos.texto(tamano: 14, peso: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      // El camión va aquí y no en el nombre: es lo que hace que
                      // marcar la zona ahorre además el paso 3. Cuando no hay,
                      // se dice que no hay — un hueco se lee como «no lo sé».
                      '${zona.pedidos} ${zona.pedidos == 1 ? 'pedido' : 'pedidos'} · '
                      '${Numeros.kgRedondeado(zona.pesoKg)} · '
                      '${zona.vehiculoNombre == null ? 'sin camión previsto' : 'camión: ${zona.vehiculoNombre}'}',
                      style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // LO QUE FALTA, DICHO. Si los filtros de arriba se están
                    // comiendo pedidos de esta zona, se dice cuántos: sin esta
                    // línea la zona parecería tener menos de lo que preparó
                    // quien la armó, y eso es exactamente lo que no puede pasar.
                    if (enLaLista < zona.pedidos)
                      Text(
                        enLaLista == 0
                            ? 'Los ${zona.pedidos} están fuera por los filtros de arriba'
                            : '${zona.pedidos - enLaLista} fuera por los filtros de arriba',
                        style: Tipos.texto(tamano: 11, color: Colores.ambar),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// LA HOJA DEL PRE-DESPACHO DEL ASISTENTE, como funcion pura.
///
/// Va aparte del widget por lo mismo que su gemela de Pedidos
/// (`pedidos/vista/pantalla_pedidos.dart`, `hojaDePreDespacho`): es lo que de
/// verdad lleva los numeros al papel, y asi se comprueba sin pintar nada.
///
/// ## Por que existe: este camino imprimia OTRA hoja — 28/09/2026
///
/// Lo de aqui dentro estaba escrito a mano dentro de `_verEImprimir`, y cuando
/// el 28/09/2026 el pre-despacho cambio de regla —lo que no se sabe ya no borra
/// la fila: se imprime lo que si se sabe marcado con `≥` y con cuantos renglones
/// faltan— sólo se actualizo el camino de Pedidos. Por este otro, la misma fila
/// salia `26320.0 kg` a secas, como si fueran los kilos enteros de 4.949
/// empaques de MALTA GUAJIRA, mientras la vista del mismo cajon decia
/// `≥ 26320.0 kg (21 renglones sin peso)`. Dos papeles distintos para lo mismo
/// (`CLAUDE.md` §3-bis), y lo que baja al almacen es el papel.
///
/// Suelta, la cubre una prueba. Dentro del widget no la cubria nada.
papel.HojaPreDespacho hojaDePreDespachoDeLaRuta({
  required TotalesPreDespacho totales,
  required String sucursal,
  required String vehiculo,
  required String? dia,
  required int pedidos,
  required double pesoKg,
}) => papel.HojaPreDespacho(
  sucursal: sucursal,
  vehiculo: vehiculo,
  dia: dia,
  pedidos: pedidos,
  pesoKg: pesoKg,
  lineas: [
    for (final linea in totales.lineas)
      papel.LineaPreDespacho(
        producto: linea.producto,
        formatos: linea.empaques,
        unidades: linea.unidades,
        // EL PESO VA TAL CUAL, CON SU NULO — 28/09/2026.
        //
        // Aqui habia un `?? 0` con este comentario: «en el papel el peso es
        // un numero: un producto sin peso resuelto suma cero kilos a la
        // hoja, que es lo que pesa lo que no sabemos». Era verdad cuando la
        // hoja no sabia imprimir un nulo; ya no lo es, y mientras tanto es
        // el cero creible de siempre: en el papel, `0 kg` no se distingue
        // de un producto que de verdad no pesa, y con esta hoja alguien
        // baja al almacen a cargar un camion.
        pesoKg: linea.pesoKg,
        // LOS CONTADORES VIAJAN AL PAPEL, igual que por el otro camino
        // (`pedidos/vista/pantalla_pedidos.dart`). Sin ellos esta hoja
        // imprimia la suma de lo que se sabe COMO SI FUERA EL TOTAL: el
        // mismo filtro decia `≥ 26320.0 kg (21 renglones sin peso)` en la
        // pantalla y `26320.0 kg` a secas en el papel. Dos papeles distintos
        // para lo mismo es el §3-bis, y lo que se lleva al almacen es el
        // papel.
        lineasSinUnidades: linea.lineasSinUnidades,
        lineasSinPeso: linea.lineasSinPeso,
      ),
  ],
);
