/// QUE LE FALTA A ESTA SUCURSAL —O A LAS OCHO— PARA PODER ARMAR UNA RUTA.
///
/// No es una lista de tareas inventada. Son las cuatro cosas **sin las cuales el
/// trabajo del dia no se puede hacer**, y las cuatro se saben mirando la base
/// local — ninguna necesita red, que es justo lo que hace que sirvan en el patio
/// del almacen.
///
/// ## Por que cada una, y en este orden
///
///  1. **El punto de partida de la sucursal** (`branches.origin_configured`).
///     Sin el no hay desde donde medir la distancia hasta el cliente, y la
///     cotizacion se salta esos pedidos enteros
///     (`api/internal/api/cotizacion.go`, `sucursal-sin-punto-de-partida`).
///  2. **Al menos un vehiculo.** Sin el no se termina el paso 3 del asistente de
///     rutas y una columna del tablero no puede llevar camion.
///  3. **Al menos un almacen con punto.** De ahi sale lo que se le cobra al
///     cliente por el domicilio; sin el se cobra desde el sitio equivocado.
///  4. **La tasa de cambio.** Sin ella los importes se quedan en USD.
///
/// El orden es el de dependencia y **no se toca**: sin punto de partida no sirve
/// de nada tener camion, y sin almacen no sirve de nada tener tasa.
///
/// ## SE CUENTAN SUCURSALES, NO FILAS
///
/// Con «Todas las sucursales» arriba, un paso esta **hecho sólo si lo esta en
/// todas**, y eso obliga a contar **cuantas sucursales lo tienen**, no cuantas
/// filas hay en la tabla. `COUNT(*) FROM vehicles > 0` decia «hecho» porque
/// habia un camion en Santiago y dejaba a las otras siete sin poder armar una
/// ruta, sin que nada lo dijera. Por eso cada sucursal del alcance trae aqui sus
/// cuatro respuestas —una fila por sucursal— y el paso se resuelve con ellas.
///
/// Y de ahi sale tambien **en cuantas falta**: un aviso que dice «falta
/// configurar esta sucursal» cuando hay ocho a la vista no nombra ninguna, y el
/// que lo lee no sabe ni por donde empezar.
///
/// Con UNA sola sucursal elegida el resultado es exactamente el de antes: una
/// fila, un «lo tiene / no lo tiene». Lo ata una prueba, no este parrafo.
///
/// ## Las consultas son LAS MISMAS que las de quien luego se queja
///
/// El conteo de vehiculos filtra por `branch_id` exactamente como
/// `ConsultasRutas.vehiculos`, y el de almacenes pide activo y con coordenadas
/// exactamente como el paso 2 del asistente. Si aqui se contara de otra forma,
/// el paso a paso diria «hecho» y el asistente diria «no hay ninguno» — dos
/// respuestas para la misma pregunta, y la que alguien cree es siempre la
/// equivocada.
///
/// **Y eso ya no es un comentario suelto** (`CLAUDE.md` §3-bis: un comentario no
/// falla). `test/pantallas/panel/paso_a_paso_test.dart` pregunta las dos cosas
/// sucursal por sucursal y exige la misma respuesta.
library;

import 'package:drift/drift.dart';
// Sólo por `IconData`: el glifo del botón de cada paso viaja con el paso.
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter/material.dart' show Icons;

import '../../../nucleo/almacenes/almacen_de_referencia.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/primera_bajada.dart';

/// Cual de los cuatro. Se usa para probarlos por separado y para que la vista
/// no tenga que comparar textos.
enum ClaveDePaso { puntoDePartida, vehiculo, almacen, tasa }

/// Como esta un paso. **Son TRES y no dos**, y ahi esta todo el asunto:
///
///  * [hecho] — se miro y esta.
///  * [falta] — se miro y no esta. Hay que darlo de alta.
///  * [sinSaber] — **no se miro**, porque este aparato no ha descargado esa
///    coleccion todavia. No es lo mismo que [falta] y no se arregla igual: esto
///    se arregla con «Traer el dia», no dando de alta nada. Pintarlos iguales
///    manda a alguien a crear un camion que ya existe.
enum ComoVa { hecho, falta, sinSaber }

/// «Granma», «Granma y Las Tunas», «Granma, Holguin y Las Tunas».
String enumerarSucursales(List<String> nombres) => switch (nombres.length) {
  0 => '',
  1 => nombres.single,
  _ => '${nombres.sublist(0, nombres.length - 1).join(', ')} y ${nombres.last}',
};

/// Uno de los cuatro pasos, ya resuelto contra la base.
class PasoDeConfiguracion {
  const PasoDeConfiguracion({
    required this.clave,
    required this.como,
    required this.titulo,
    required this.paraQue,
    required this.siFalta,
    required this.coleccion,
    required this.sucursales,
    required this.lasQueFaltan,
    this.ruta,
    this.textoDelBoton,
    this.iconoDelBoton,
    this.dondeSeArregla,
  });

  final ClaveDePaso clave;
  final ComoVa como;

  /// Que es, en una linea y en las palabras del logistico.
  final String titulo;

  /// Por que hace falta. Una linea.
  final String paraQue;

  /// Que pasa si falta. Es la que decide si alguien lo hace hoy o el mes que
  /// viene.
  ///
  /// **Se escribe sin «esta sucursal»**: con las ocho a la vista no hay
  /// ninguna «esta», y el que lo lee acaba abriendo la que no era. Cual es se
  /// dice aparte, en [enCuantasFalta].
  final String siFalta;

  /// La coleccion de la bajada de la que sale el dato. Es lo que permite decir
  /// «no se ha descargado» en vez de «no hay».
  final String coleccion;

  /// Cuantas sucursales hay **en el alcance que se esta mirando**: 1 con una
  /// elegida en la barra, 8 con «Todas las sucursales».
  final int sucursales;

  /// Las del alcance a las que les falta ESTE paso, por su nombre.
  ///
  /// Vacia = lo tienen todas. Sólo se usa para contar y para nombrarlas; quien
  /// decide si el paso esta hecho es [como], que ya viene resuelto.
  final List<String> lasQueFaltan;

  /// A donde lleva. **`null` = no se arregla en esta aplicacion**, y entonces
  /// NO se pinta boton: uno que no lleva a ningun sitio ensena a desconfiar del
  /// que si lleva. En su lugar se dice donde se arregla, en [dondeSeArregla].
  final String? ruta;

  final String? textoDelBoton;

  /// EL GLIFO DE ESE BOTON, y viaja con el paso porque cada paso lleva a una
  /// pantalla distinta: al camion o al almacen. Es el dibujo de **a donde va**,
  /// que aqui es lo que hace el mando. Un icono unico para los cuatro diria que
  /// los cuatro llevan al mismo sitio (`diseno/tema.dart`, [BotonPrincipal]).
  final IconData? iconoDelBoton;

  /// Donde se arregla cuando [ruta] es `null`.
  final String? dondeSeArregla;

  /// EN CUANTAS FALTA, y con pocas, **en cuales**.
  ///
  /// `null` con una sola sucursal a la vista: ahi «en 1 de las 1» es ruido, y
  /// ademas el titulo ya dice de cual se habla. Con varias es lo unico que
  /// convierte un rojo permanente —hoy sólo Habana y Santiago tienen tasa, asi
  /// que ese paso esta pendiente todos los dias— en algo que se puede ir
  /// tachando: seis, luego cuatro, luego ninguna.
  ///
  /// Se nombran hasta tres. Mas es una lista que nadie lee, y con seis de ocho
  /// lo util es el numero.
  String? get enCuantasFalta {
    if (sucursales <= 1 || como != ComoVa.falta || lasQueFaltan.isEmpty) {
      return null;
    }
    final cuenta =
        'Falta en ${lasQueFaltan.length} de las $sucursales '
        'sucursales';
    return lasQueFaltan.length > 3
        ? '$cuenta.'
        : '$cuenta: ${enumerarSucursales(lasQueFaltan)}.';
  }

  /// Lo que se lee debajo del titulo segun como este, **en el aparato**.
  String get explicacion => explicacionEn(PorQueEstaVacio.noSeDescargo);

  /// Lo mismo, sabiendo POR QUE esta vacia la copia.
  ///
  /// Sólo cambia el caso [ComoVa.sinSaber], que es el unico que habla de la
  /// bajada. Los otros dos son del negocio y se dicen igual en los tres
  /// destinos: un almacen que falta, falta en el navegador y en el telefono.
  String explicacionEn(PorQueEstaVacio porQue) => switch (como) {
    ComoVa.hecho => paraQue,
    // Primero EN CUANTAS y luego POR QUE IMPORTA. El porque nunca se quita: es
    // lo que hace que alguien lo arregle hoy y no el mes que viene.
    ComoVa.falta => switch (enCuantasFalta) {
      null => siFalta,
      final donde => '$donde $siFalta',
    },
    ComoVa.sinSaber => switch (porQue) {
      PorQueEstaVacio.noSeDescargo => textoSinDescargar,
      // En la web no hay «aparato» ni gesto de traer el dia: la unica verdad es
      // que esto no llego.
      //
      // Los dos casos de web dicen lo MISMO a proposito, y no es pereza:
      // mientras la bajada va en camino este paso **no se pinta siquiera**
      // (`paso_a_paso.dart`), asi que si se llega hasta aqui es porque ya se
      // dejo de esperar. Un tercer literal seria uno que nadie lee nunca.
      PorQueEstaVacio.todaviaBajando ||
      PorQueEstaVacio.noPudoBajar => textoNoLlego,
    },
  };

  /// El literal de «esto no se ha bajado». Es de la pieza, no de la pantalla,
  /// para que diga lo mismo en los cuatro pasos.
  static const textoSinDescargar =
      'Este aparato no lo ha descargado todavía, así que no se sabe si falta. '
      'Se arregla trayendo el día, no dando nada de alta.';

  /// EL MISMO ESTADO, EN LA WEB. Se dice, sin mandar a nadie a mirar la señal
  /// ni a traer ningun dia: ninguna de las dos cosas existe en un navegador.
  static const textoNoLlego =
      'Esto no se pudo traer, así que no se sabe si falta. No es que no esté '
      'dado de alta: es que no llegó. Prueba a recargar y, si sigue igual, '
      'avisa a la oficina.';
}

/// Los cuatro pasos y la regla de cuando se ensenan.
class ElPasoAPaso {
  const ElPasoAPaso(
    this.pasos, {
    required this.sucursales,
    required this.sucursalesConAlgoQueFalta,
  });

  final List<PasoDeConfiguracion> pasos;

  /// Cuantas sucursales se estan mirando: 1 con una elegida arriba, 8 con
  /// «Todas las sucursales».
  final int sucursales;

  /// A cuantas de ellas les falta **algo que se miro y no estaba**.
  ///
  /// No cuenta lo que todavia no ha bajado, por lo mismo que [faltaAlgoDeVerdad]
  /// no lo cuenta: acusar de estar a medio configurar a una sucursal cuya
  /// coleccion no ha llegado manda a alguien a dar de alta lo que ya existe.
  final int sucursalesConAlgoQueFalta;

  PasoDeConfiguracion paso(ClaveDePaso clave) =>
      pasos.firstWhere((p) => p.clave == clave);

  List<PasoDeConfiguracion> get pendientes =>
      pasos.where((p) => p.como != ComoVa.hecho).toList();

  List<PasoDeConfiguracion> get hechos =>
      pasos.where((p) => p.como == ComoVa.hecho).toList();

  /// Nada bajado: el aparato no sabe nada de nada.
  bool get noSeSabeNada => pasos.every((p) => p.como == ComoVa.sinSaber);

  /// Hay algun paso que **no se ha llegado a mirar**.
  ///
  /// En el aparato es un estado tranquilo —falta traer el dia—; en la web es el
  /// segundo que tarda en entrar la primera bajada, y ahi no se puede
  /// diagnosticar nada todavia. Ver `frescura/primera_bajada.dart`.
  bool get algoSinMirar => pasos.any((p) => p.como == ComoVa.sinSaber);

  /// Hay algo que de verdad FALTA: se miro y no esta.
  ///
  /// Es lo que separa «falta configurar esta sucursal» de «esto todavia no ha
  /// bajado». Sin esta distincion, un aparato al que sólo le falta una
  /// coleccion por bajar acusaba a la sucursal de estar a medio configurar.
  bool get faltaAlgoDeVerdad => pasos.any((p) => p.como == ComoVa.falta);

  /// SI SE PINTA O NO. Las dos unicas veces que no:
  ///
  ///  * **Cuando no falta nada.** Un asistente que sigue ahi cuando ya no hace
  ///    falta es ruido para siempre, y el ruido de siempre se deja de leer.
  ///  * **Cuando el aparato no ha bajado NADA.** Ahi no hay nada que configurar
  ///    todavia: lo primero es traer el dia, y de eso ya se ocupa
  ///    `EstadoDelDia`, que es lo primero de la pantalla. Poner los cuatro pasos
  ///    en «no se sabe» encima del gesto que los resolveria es tapar la
  ///    respuesta con la pregunta.
  bool get seEnsena => pendientes.isNotEmpty && !noSeSabeNada;
}

/// El detector. Una sola consulta y un solo `watch`.
class ConfiguracionPendiente {
  ConfiguracionPendiente(this._base);

  final BaseLocal _base;

  /// Mira la base y devuelve los cuatro pasos, en vivo.
  ///
  /// [sucursalId] es la sucursal de la barra superior; `null` = todas las que
  /// esta persona ve. Con varias a la vista, un paso esta **hecho sólo si lo
  /// esta en todas**: decir que esta hecho porque lo esta en una deja a las
  /// otras siete sin cotizar y sin que nada lo diga.
  ///
  /// El alcance sale de la base, no del parametro: en `branches` sólo estan las
  /// sucursales que esta persona ve, porque es lo unico que bajo. Un GERENTE de
  /// Camaguey tiene una fila; un SUPER ADMIN, ocho.
  Stream<ElPasoAPaso> mirar({String? sucursalId}) {
    // UNA FILA POR SUCURSAL DEL ALCANCE, con sus cuatro respuestas.
    //
    // No se agregan aqui a proposito: quien decide si un paso esta «hecho»,
    // «falta» o «no se sabe» es `_leer`, en un sitio y con las mismas tres
    // reglas para los cuatro pasos. Sumar en SQL obligaria a repetir alli la
    // regla de la bajada y serian dos sitios que se separan.
    //
    // El `LEFT JOIN` contra la sub-consulta de frescura es lo que garantiza
    // **una fila aunque no haya ni una sucursal**: en un aparato recien puesto
    // no hay `branches` todavia, y aun asi hay que poder decir «esto no ha
    // bajado» en vez de «no hay».
    //
    // `?1 IS NULL OR …` en vez de dos consultas, como en `consultas_panel.dart`:
    // una sola sentencia, y la version «todas las sucursales» no puede quedarse
    // atras de la filtrada porque son el mismo SQL.
    //
    // Los nombres de coleccion van interpolados y no como variables porque son
    // constantes de `Colecciones`, escritas en el codigo: no viene de fuera ni
    // una letra.
    final sql =
        '''
SELECT
  baj.bajo_sucursales AS bajo_sucursales,
  baj.bajo_vehiculos  AS bajo_vehiculos,
  baj.bajo_almacenes  AS bajo_almacenes,
  baj.bajo_ajustes    AS bajo_ajustes,
  b.id   AS sucursal_id,
  b.name AS sucursal_nombre,
  (b.origin_configured = 1) AS con_punto,
  -- EL MISMO FILTRO QUE `ConsultasRutas.vehiculos`: por `branch_id` y nada mas.
  -- Un camion de otra sucursal no tapa este hueco, ni aqui ni en el asistente.
  EXISTS (
    SELECT 1 FROM vehicles v WHERE v.branch_id = b.id
  ) AS con_vehiculo,
  -- LAS MISMAS CONDICIONES QUE EL TABLERO Y QUE CLIENTES, porque es la misma
  -- pregunta: «¿hay un almacen del que salir?». No se escriben aqui: se
  -- interpolan de `AlmacenDeReferencia`, que es donde viven, para que no puedan
  -- separarse. Se separaron —a este le faltaba descartar el (0,0)— y el 22/09/2026
  -- el Panel decia ✓ donde el Tablero decia que no habia tablero.
  EXISTS (
    SELECT 1 FROM warehouses w
     WHERE b.external_id IS NOT NULL
       AND w.sucursal_codigo = b.external_id
       AND ${AlmacenDeReferencia.sqlSirveParaMedir}
  ) AS con_almacen,
  -- LA TASA ES DE LA SUCURSAL, y por eso sale de `branches` y no de `settings`.
  --
  -- Este paso se llama «la tasa de cambio de la sucursal» y miraba
  -- `settings.cup_rate`, que es la GLOBAL y vieja de delivery — la que hacía que
  -- Granma enseñara los 685 de La Habana. La API lo dice con todas las letras
  -- (`api/internal/api/ajustes.go`): «los ajustes son GLOBALES… la tasa POR
  -- SUCURSAL es otra cosa y vive en Accesos, no aquí».
  --
  -- Y se exige la FECHA, no el número: `cup_rate` puede traer un valor sin que
  -- nadie haya puesto nada, y un número sin fecha no es una tasa.
  (b.cup_rate_traido_at IS NOT NULL AND b.cup_rate > 0) AS con_tasa
FROM (
  SELECT
    (SELECT COUNT(*) FROM frescura f
      WHERE f.bajada_at IS NOT NULL
        AND f.coleccion = '${Colecciones.sucursales}') AS bajo_sucursales,
    (SELECT COUNT(*) FROM frescura f
      WHERE f.bajada_at IS NOT NULL
        AND f.coleccion = '${Colecciones.vehiculos}') AS bajo_vehiculos,
    (SELECT COUNT(*) FROM frescura f
      WHERE f.bajada_at IS NOT NULL
        AND f.coleccion = '${Colecciones.almacenes}') AS bajo_almacenes,
    (SELECT COUNT(*) FROM frescura f
      WHERE f.bajada_at IS NOT NULL
        AND f.coleccion = '${Colecciones.ajustes}') AS bajo_ajustes
) baj
LEFT JOIN branches b ON (?1 IS NULL OR b.id = ?1)
ORDER BY b.name
''';

    return _base
        .customSelect(
          sql,
          variables: [Variable<String>(sucursalId)],
          readsFrom: {
            _base.branches,
            _base.vehicles,
            _base.warehouses,
            _base.settings,
            _base.frescura,
          },
        )
        .watch()
        .map(_leer);
  }

  ElPasoAPaso _leer(List<QueryRow> filas) {
    // La frescura viene repetida en todas las filas —es la misma sub-consulta—,
    // asi que se lee de la primera. Si no hubiera ni una fila (no puede pasar
    // con el `LEFT JOIN`), «no ha bajado nada», que es el estado prudente.
    final cabecera = filas.isEmpty ? null : filas.first;
    bool bajo(String columna) => (cabecera?.read<int>(columna) ?? 0) > 0;

    final bajoSucursales = bajo('bajo_sucursales');
    final bajoVehiculos = bajo('bajo_vehiculos');
    final bajoAlmacenes = bajo('bajo_almacenes');

    // Una fila por sucursal del alcance. Sin ninguna sucursal, el `LEFT JOIN`
    // deja una fila con el id a nulo: es la de la frescura, no una sucursal.
    final deLasSucursales = [
      for (final f in filas)
        if (f.read<String?>('sucursal_id') != null) f,
    ];
    final sucursales = deLasSucursales.length;

    bool leFalta(QueryRow f, String columna) => f.read<int?>(columna) != 1;

    /// Los nombres de las sucursales del alcance a las que les falta [columna].
    List<String> sinEsto(String columna) => [
      for (final f in deLasSucursales)
        if (leFalta(f, columna))
          f.read<String?>('sucursal_nombre') ?? 'sin nombre',
    ];

    ComoVa como({required bool bajada, required bool esta}) => !bajada
        ? ComoVa.sinSaber
        : esta
        ? ComoVa.hecho
        : ComoVa.falta;

    // HECHO = LO TIENEN TODAS. Con cero sucursales no lo tiene ninguna: falta, y
    // se dice. Un «hecho» sobre una lista vacia seria una division por cero
    // disfrazada de buena noticia.
    final sinPunto = sinEsto('con_punto');
    final sinVehiculo = sinEsto('con_vehiculo');
    final sinAlmacen = sinEsto('con_almacen');
    final sinTasa = sinEsto('con_tasa');

    // A CUANTAS SUCURSALES LES FALTA ALGO QUE SE MIRO.
    //
    // Sólo cuentan las columnas cuya coleccion bajo, exactamente las mismas que
    // pueden acabar en `ComoVa.falta`. Asi el titulo y los cuatro pasos cuentan
    // lo mismo: si el titulo dijera «en 6 de las 8» y ningun paso estuviera en
    // rojo, el numero no lo podria comprobar nadie.
    final miradas = <String>[
      if (bajoSucursales) 'con_punto',
      if (bajoVehiculos) 'con_vehiculo',
      if (bajoAlmacenes) 'con_almacen',
      // La tasa viaja con la SUCURSAL, no con los ajustes.
      if (bajoSucursales) 'con_tasa',
    ];
    final conAlgoQueFalta = deLasSucursales
        .where((f) => miradas.any((c) => leFalta(f, c)))
        .length;

    return ElPasoAPaso(
      [
        PasoDeConfiguracion(
          clave: ClaveDePaso.puntoDePartida,
          coleccion: Colecciones.sucursales,
          sucursales: sucursales,
          lasQueFaltan: sinPunto,
          como: como(
            bajada: bajoSucursales,
            esta: sucursales > 0 && sinPunto.isEmpty,
          ),
          titulo: 'El punto de partida de la sucursal',
          paraQue: 'Es el sitio desde el que se mide la distancia hasta cada cliente.',
          siFalta:
              'Sin él no hay desde dónde medir: esos domicilios se quedan sin '
              'cotizar y los pedidos salen sin precio.',
          // NO lleva a ningun sitio, y por eso no hay boton: el punto de partida
          // lo deja puesto quien da de alta la sucursal en delivery
          // (`POST /api/branches` pone `originConfigured: true`). Ni Almacenes ni
          // ninguna otra pantalla de esta aplicacion lo toca — mandar ahi seria un
          // boton que lleva a un sitio donde el problema no se arregla, que es
          // peor que no tener boton.
          dondeSeArregla:
              'No se pone aquí: lo deja hecho quien da de alta la sucursal. '
              'Pídelo a administración y baja solo con el día.',
        ),
        PasoDeConfiguracion(
          clave: ClaveDePaso.vehiculo,
          coleccion: Colecciones.vehiculos,
          sucursales: sucursales,
          lasQueFaltan: sinVehiculo,
          // **CUANTAS SUCURSALES TIENEN CAMION, no cuantos camiones hay.** Esto
          // era `COUNT(*) FROM vehicles > 0`: con las ocho a la vista, un solo
          // camion en Santiago daba el paso por hecho para las otras siete.
          como: como(
            bajada: bajoVehiculos,
            esta: sucursales > 0 && sinVehiculo.isEmpty,
          ),
          titulo: 'Al menos un vehículo',
          paraQue: 'Es el camión al que se le carga la ruta del día.',
          siFalta:
              'Sin ninguno no se puede terminar el paso 3 del asistente de rutas, '
              'y una columna del tablero no puede llevar camión.',
          ruta: '/vehicles',
          textoDelBoton: 'Agregar el primer vehículo',
          iconoDelBoton: Icons.local_shipping_outlined,
        ),
        PasoDeConfiguracion(
          clave: ClaveDePaso.almacen,
          coleccion: Colecciones.almacenes,
          sucursales: sucursales,
          lasQueFaltan: sinAlmacen,
          // Igual que el vehiculo: sucursales cubiertas, no filas de
          // `warehouses`.
          como: como(
            bajada: bajoAlmacenes,
            esta: sucursales > 0 && sinAlmacen.isEmpty,
          ),
          titulo: 'Al menos un almacén con su punto puesto',
          paraQue:
              'Del almacén sale lo que se le cobra al cliente por el domicilio, '
              'y de ahí arranca el camión.',
          siFalta:
              'Sin él se cobra desde el sitio equivocado y el asistente de rutas '
              'no tiene de dónde salir. Un almacén sin coordenadas tampoco sirve.',
          ruta: '/warehouses',
          textoDelBoton: 'Poner el almacén',
          iconoDelBoton: Icons.warehouse_outlined,
        ),
        PasoDeConfiguracion(
          clave: ClaveDePaso.tasa,
          coleccion: Colecciones.ajustes,
          sucursales: sucursales,
          lasQueFaltan: sinTasa,
          como: como(
            // La tasa viaja con la SUCURSAL, no con los ajustes: se mira si
            // bajaron las sucursales.
            bajada: bajoSucursales,
            // **La marca de cuando, no el numero.** `cup_rate` puede traer un
            // valor sin que nadie haya puesto nada; sólo `cup_rate_traido_at`
            // —el `traidoAt` que da Accesos— demuestra que hay tasa de verdad.
            //
            // Y todas, no alguna: hoy en Accesos sólo tienen tasa Habana y
            // Santiago. Con «todas» a la vista, decir «hecho» porque dos de las
            // ocho la tienen deja a las otras seis en dolares sin que nadie lo
            // sepa.
            esta: sucursales > 0 && sinTasa.isEmpty,
          ),
          titulo: 'La tasa de cambio de la sucursal',
          paraQue: 'Es lo que pasa los importes de USD a CUP.',
          siFalta:
              'Sin ella los importes sólo se ven en USD. No se convierte nada: '
              'convertir sin tasa es inventarse un número, y un número inventado '
              'acaba cobrado.',
          // Tampoco lleva a ningun sitio, y es la razon por la que existe la
          // regla: la tasa la mantiene Accesos, que la trae de Entrega. Aqui no
          // hay ninguna copia editable a proposito (`reglas-negocio.md` §8): dos
          // tasas para lo mismo se separan en cuanto una se olvida, y el mismo
          // domicilio vale distinto segun donde se mire.
          dondeSeArregla:
              'No se pone aquí: la mantiene Accesos, que la trae de Entrega. '
              'Se arregla allí y baja sola con el día.',
        ),
      ],
      sucursales: sucursales,
      sucursalesConAlgoQueFalta: conAlgoQueFalta,
    );
  }
}
