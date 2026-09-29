import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/numeros.dart';
import '../../../nucleo/sincro/ciclo.dart';
import '../../../nucleo/sincro/huerfanos.dart';

/// EN QUE ESTADO ESTA EL APARATO, y por tanto que toca ahora.
///
/// **Uno solo, no dos botones.** Antes el Panel ensenaba «Traer el día» y
/// «Entregar el día» a la vez, siempre, y le dejaba al logistico decidir cual de
/// los dos le servia. Eso es trabajo que puede hacer la pantalla: en el patio
/// del almacen sin cobertura no hay nada que decidir, y con veintitres apuntes
/// dentro del telefono tampoco.
///
/// El orden de la lista **es el orden de prioridad**, y no es arbitrario: lo
/// unico que se puede perder es el trabajo hecho. Los datos bajados se vuelven a
/// bajar; una parada marcada a las cuatro de la tarde que nunca subio, no.
enum QueToca {
  /// Bajando. Se dice por donde va.
  trayendo,

  /// Subiendo. Se dice por donde va.
  enviando,

  /// **Sin senal.** No se ofrece un boton que no puede funcionar: se dice el
  /// estado y de que hora son los datos, que es lo que hace falta saber ahi.
  sinConexion,

  /// Hay trabajo dentro del telefono. **Manda sobre todo lo demas.**
  hayQueEnviar,

  /// TRABAJO QUE ESTA AQUI, NO ESTA ARRIBA Y **NO LO VA A SUBIR NADIE**.
  ///
  /// No es lo mismo que [hayQueEnviar] y por eso no se dice con sus palabras:
  /// eso son apuntes en la cola, que suben solos en cuanto haya señal. Esto es
  /// una fila que se quedo **sin ningun apunte que la nombre** —el suyo se
  /// descarto, o se perdio—, asi que la cola esta a cero y el aparato se ve al
  /// dia teniendo dentro el trabajo de una mañana.
  ///
  /// El 24/09/2026 la franja de estado aprendio a nombrarlo, y bien. Pero la
  /// franja es una linea de doce puntos arriba del todo y **justo debajo, en
  /// esta misma pantalla**, la pieza grande seguia diciendo «Todo al dia · no
  /// queda nada sin enviar» en verde y a tamaño titular. La misma pantalla
  /// diciendo dos cosas contrarias, y la que se lee es la grande: es, palabra
  /// por palabra, una de las tres que Jose enumero el 16/09/2026 mirando su
  /// telefono con la zona «Vista» dentro.
  ///
  /// **Sin boton**: no hay nada que pulsar que lo arregle, y ofrecer uno que no
  /// hace nada enseña a desconfiar de los botones. Lo que hace falta es que se
  /// sepa antes de que alguien cierre sesion, olvide la copia o formatee el
  /// telefono.
  trabajoColgado,

  /// Todo entregado, con senal, y los datos VIEJOS: lo que toca es traerlos.
  alDia,

  /// Todo entregado y los datos de ahora mismo. **No hay nada que hacer**, y por
  /// eso no se ofrece boton.
  ///
  /// Jose, 16/09/2026: «tengo todo al dia y me sigue estando activado el boton
  /// de traer el dia… el traer el dia es para si no se ha traido automatico q se
  /// pueda hacer manual».
  ///
  /// Un boton que se pulsa y no cambia nada ensena a desconfiar de los botones,
  /// y ademas gasta la conexion de alla para volver a bajar lo mismo.
  todoAlDia,
}

abstract final class TextosDelDia {
  /// El titulo de la pieza en cada estado.
  static String titulo(QueToca toca, {int sinSubir = 0}) => switch (toca) {
    QueToca.trayendo => 'Trayendo datos...',
    QueToca.enviando => 'Enviando datos...',
    QueToca.sinConexion => 'Trabajando sin conexión',
    QueToca.hayQueEnviar => 'Tienes trabajo sin enviar',
    QueToca.trabajoColgado => 'Hay trabajo que no va a subir solo',
    QueToca.alDia => 'Traer el día',
    QueToca.todoAlDia => 'Todo al día',
  };

  /// El texto del boton. `null` = **no hay boton**, que es el caso de no tener
  /// senal: ofrecer uno que va a fallar es peor que no ofrecer ninguno.
  static String? boton(QueToca toca, {int sinSubir = 0}) => switch (toca) {
    QueToca.trayendo => 'Trayendo datos...',
    QueToca.enviando => 'Enviando datos...',
    QueToca.sinConexion => null,
    QueToca.hayQueEnviar => 'Enviar datos (${Numeros.entero(sinSubir)})',
    // Sin boton: no hay nada que pulsar que lo arregle. Ver
    // [QueToca.trabajoColgado].
    QueToca.trabajoColgado => null,
    QueToca.alDia => 'Traer el día',
    // Sin boton: no hay nada que hacer.
    QueToca.todoAlDia => null,
  };

  static String explicacion(QueToca toca) => switch (toca) {
    QueToca.trayendo ||
    QueToca.enviando => 'No cierres la pantalla hasta que acabe.',
    // Se nombra la falta de conexión Y lo que pasa con lo que ya está hecho. Lo
    // segundo es lo que de verdad quita el miedo: quien ve «6 sin subir» lo que
    // quiere saber es si eso se va a perder.
    QueToca.sinConexion =>
      'No hay conexión con el servidor. Puedes seguir trabajando: todo se '
          'guarda aquí y sube solo cuando vuelva la señal.',
    QueToca.hayQueEnviar =>
      'Hasta que no suba, sólo está en este aparato. Es lo único que se puede '
          'perder.',
    // SE DICE QUE HACER, y lo unico que se puede hacer es que no se borre y que
    // alguien lo rehaga arriba. «Hubo un problema» no le sirve a nadie.
    QueToca.trabajoColgado =>
      'Está sólo en este aparato y no le queda ningún apunte que lo suba. No '
          'cierres sesión ni borres esta copia: avisa a la oficina para que lo '
          'rehagan.',
    QueToca.alDia =>
      'Cárgalo donde haya señal y llévatelo: el día entero se trabaja sin '
          'conexión.',
    QueToca.todoAlDia =>
      'Los datos son de ahora mismo y no queda nada sin enviar. Se mantiene '
          'solo mientras haya señal.',
  };

  /// POR DONDE VA, con el verbo del paso que toca.
  static String porDondeVa(AvanceDelCiclo? avance) {
    if (avance == null) return 'Empezando...';
    return switch (avance.paso) {
      PasoDelCiclo.renovar => 'Comprobando la sesión...',
      PasoDelCiclo.subir => 'Subiendo lo que hiciste...',
      PasoDelCiclo.bajar when avance.coleccion == null =>
        'Pidiendo los cambios...',
      PasoDelCiclo.bajar => '${_coleccion(avance.coleccion!)}...',
    };
  }

  /// «datos de las 8:14» — en minuscula porque va detras de otra cosa tantas
  /// veces como sola.
  ///
  /// SON TRES RESPUESTAS Y NO DOS, y por eso esto recibe el `AsyncValue` entero
  /// y no un `DateTime?`.
  ///
  /// El conteo de lo que hay dentro del aparato (`loQueHayProvider`) es una
  /// consulta que tarda: abrir el fichero, las migraciones y nueve conteos sobre
  /// tablas con decenas de miles de renglones. Mientras corre, `.value` es
  /// `null` — y `null` aqui significaba «este aparato no tiene nada». O sea que
  /// el Panel abria diciendo **«sin datos todavía»** encima de una base llena,
  /// justo en el momento en que alguien mira si le hace falta traer el dia antes
  /// de salir al reparto. Es el §3-ter del `CLAUDE.md` en su forma mas corta:
  /// **«no hay» y «no he mirado» son dos cosas distintas**, y colapsar el
  /// `AsyncLoading` en `null` las confunde.
  ///
  /// Ya estaba arreglado en la franja de Pedidos y de Rutas
  /// (`SinMirarTodavia`, en `nucleo/frescura/reloj_de_datos.dart`, con las
  /// mismas palabras) y aqui se habia quedado el literal viejo.
  ///
  /// Recibir el `AsyncValue` no es ceremonia: es lo que impide que el arreglo se
  /// deshaga solo. Con un `DateTime?` cualquiera vuelve a escribir `.value` en
  /// la llamada y el fallo regresa sin que cambie una linea de aqui.
  ///
  /// Y se mira `hasValue`, no `isLoading`: cuando el conteo se rehace porque
  /// entro una bajada, Riverpod deja el valor anterior a la vista mientras
  /// recalcula. Ahi la hora de antes sigue siendo cierta y parpadear a «mirando
  /// qué hay…» seria perder un dato bueno.
  static String datosDeLas(AsyncValue<DateTime?> cuando) {
    if (!cuando.hasValue) return 'mirando qué hay…';
    final hora = cuando.requireValue;
    if (hora == null) return 'sin datos todavía';
    return 'datos de las ${hora.hour}:'
        '${hora.minute.toString().padLeft(2, '0')}';
  }

  static String sinSubir(int cuantos) =>
      cuantos == 1 ? '1 sin subir' : '${Numeros.entero(cuantos)} sin subir';

  /// La linea de estado del aparato: de cuando son los datos y que queda dentro.
  static String deQueHoraYQueQueda(
    AsyncValue<DateTime?> cuando,
    int pendientes,
  ) => <String>[
    datosDeLas(cuando),
    if (pendientes > 0) sinSubir(pendientes),
  ].join(' · ');

  static String _coleccion(String clave) => switch (clave) {
    'orders' => 'Pedidos',
    'order_items' => 'Líneas de pedido',
    'routes' => 'Rutas',
    'customers' => 'Clientes',
    'products' => 'Productos',
    'vehicles' => 'Vehículos',
    'branches' => 'Sucursales',
    'warehouses' => 'Almacenes',
    'settings' => 'Ajustes',
    _ => clave,
  };
}

/// QUE TOCA AHORA MISMO, en una funcion suelta y probable.
///
/// Esta fuera del widget a proposito: es **una regla**, no pintura. La misma
/// razon por la que `haySesionParaSincronizar` vive suelta en el portero. Una
/// regla metida en un `build` sólo se puede comprobar montando media
/// aplicacion, y lo que hay que comprobar aqui es el ORDEN de cuatro
/// condiciones — que es justo donde estuvo el fallo.
///
/// [vaMal] no es «el aparato cree que no hay wifi»: es que las peticiones no
/// estan llegando, medido (`nucleo/red/salud.dart`). Con una excepcion que se
/// añadio el 22/09/2026: cuando el sistema dice que **no hay ni interfaz**
/// —modo avion— eso se cree al momento, porque su «no» no admite discusion; lo
/// que nunca vale es su «si».
/// CUANTO PUEDE TARDAR UN INTENTO ANTES DE QUE «ENVIANDO» DEJE DE SER VERDAD.
///
/// `vaMal` tarda TRES ciclos en encenderse, y con razon: es el aviso persistente
/// y tiene que ser lento en ponerse para no parpadear (`red/salud.dart`). Pero
/// eso deja un hueco que se ve a la primera, y se vio: al abrir la aplicacion
/// sin red, el contador de fallos empieza en cero, asi que durante todo el
/// primer ciclo —unos 55 s de reintentos— la pantalla dice «Enviando datos...»
/// sin enviar nada. El aviso persistente llega tarde para ESE momento.
///
/// Treinta segundos es el corte, y sale de los numeros de `cliente_api.dart`:
/// una peticion que llega tarda menos de eso incluso con la conexion de alla, y
/// una que no llega se come 10 s de plazo de conexion en el primer intento y ya
/// va por el segundo. O sea: pasados 30 s, o no hay conexion o da igual que la
/// haya, porque quien mira lleva medio minuto esperando sin saberlo.
///
/// No sustituye a `vaMal`: lo acompana. Este mira ESTE intento; aquel mira si la
/// conexion lleva minutos sin servir.
const Duration pacienciaDelIntento = Duration(seconds: 30);

/// LOS SITIOS QUE EL CICLO SABE RESCATAR SOLO, y por eso NO se avisan.
///
/// `Huerfanos.volverAEncolar` corre al principio de cada vuelta del ciclo y
/// rehace **el tablero**: la zona con su marca `nacio_aqui` y las tarjetas
/// sueltas. Eso no necesita red —sólo escribe en la cola de este aparato—, así
/// que una zona huérfana vuelve a estar a la vista como «N sin subir» al tic
/// siguiente, tenga señal o no.
///
/// Avisar de eso sería el aviso que sale casi siempre y que por eso deja de
/// leerse (`CLAUDE.md` §3-quinquies), y encima parpadearía: aparece y a los
/// segundos se va solo.
///
/// Lo que **no** rescata nadie son las rutas, los vehículos y los almacenes: el
/// propio `huerfanos.dart` lo dice —«los demás se cuentan y se dicen»— y contar
/// se contaba, decir no se decía. Ésos se quedan ahí para siempre, y ésos son
/// los que esta pantalla nombra.
const sitiosQueElCicloRescata = <String>{'board_columns', 'board_placements'};

/// De todo lo que cuelga, **lo que no va a subir solo nunca**.
List<TrabajoHuerfano> loQueNadieVaASubir(List<TrabajoHuerfano> colgado) => [
  for (final h in colgado)
    if (!sitiosQueElCicloRescata.contains(h.tabla)) h,
];

/// CUANTO PUEDE IR EL RELOJ DEL TELÉFONO POR DETRÁS DE LA MARCA sin que eso
/// signifique nada.
///
/// La marca de la bajada la pone **el servidor** y la hora la pone **el
/// teléfono**: que no cuadren al segundo es lo normal, no una avería. Cinco
/// minutos deja sitio de sobra para el desfase de dos relojes que nadie
/// sincroniza, y sigue siendo mucho menos que cualquier salto de verdad —los
/// que pasan son de horas o de años, no de minutos.
const margenDelReloj = Duration(minutes: 5);

/// EL RELOJ DE ESTE APARATO ESTÁ DETRÁS DE SUS PROPIOS DATOS.
///
/// Al repartidor se le apaga el teléfono en la calle y vuelve con el reloj de
/// fábrica; o alguien le cambia la hora; o se queda una mañana sin hora de red.
/// A partir de ahí `ahora` es ANTERIOR a la marca de la última bajada.
///
/// `EstadoFrescura.de` hace `ahora.difference(bajadaAt)`, y con el reloj detrás
/// eso sale negativo: un negativo es menor que una hora, así que contesta
/// `DatosRecientes` —«Datos de las 16:40», una hora que aún no ha pasado— y sin
/// ámbar. El Panel arma `hayQueTraer` con ese mismo `enAmbar`, así que se
/// plantaba en [QueToca.todoAlDia]: verde, «los datos son de ahora mismo», **y
/// sin botón de Traer el día**, porque ese estado no ofrece ninguno. Con los
/// pedidos de anteayer dentro y el gesto para arreglarlo quitado.
///
/// Aquí se tapa lo del Panel, que es lo que le quita el gesto a alguien. **El
/// arreglo de fondo va en `nucleo/frescura/reloj_de_datos.dart`**, que es quien
/// escribe la hora del futuro en la franja de las siete pantallas: una
/// diferencia negativa no es «reciente», es un estado propio que hay que
/// nombrar.
bool elRelojNoCuadra(DateTime? bajadaAt, {required DateTime ahora}) {
  if (bajadaAt == null) return false;
  return bajadaAt.difference(ahora) > margenDelReloj;
}

QueToca queTocaAhora({
  required bool enVuelo,
  required PasoDelCiclo? paso,
  required bool vaMal,
  required int pendientes,
  Duration? llevaEnVuelo,
  bool hayQueTraer = true,
  bool hayTrabajoColgado = false,
}) {
  // Un intento que lleva mas de medio minuto no se anuncia como si estuviera
  // saliendo bien. Ver `pacienciaDelIntento`.
  if (enVuelo && llevaEnVuelo != null && llevaEnVuelo >= pacienciaDelIntento) {
    return QueToca.sinConexion;
  }
  // SIN CONEXION MANDA, TAMBIEN MIENTRAS SE INTENTA. Y este orden es el
  // arreglo, no un detalle.
  //
  // Antes `enVuelo` iba primero, asi que la comprobacion de la red **no se
  // llegaba a mirar nunca** mientras habia un intento en marcha. Visto en un
  // Galaxy A16 el 16/09/2026, con el wifi puesto y sin salida a internet: la
  // tarjeta se quedo mas de un minuto diciendo «Enviando datos... Subiendo lo
  // que hiciste...» sin subir absolutamente nada, y sin nombrar la conexion ni
  // una vez. Palabras de Jose: «tienes q notificar q estas sin conexion ok la
  // aplicacion tiene q informar eso».
  //
  // No es que se viera raro: es que la pantalla estaba diciendo una cosa que
  // no era verdad, en el unico sitio donde alguien mira para saber si su
  // trabajo salio del telefono. Y dura mucho, porque el cliente reintenta con
  // esperas crecientes antes de rendirse — o sea que el minuto de mentira es
  // el caso NORMAL, no el raro.
  //
  // `vaMal` no es «el aparato cree que no hay wifi»: es que las peticiones no
  // estan llegando, medido (`red/salud.dart`). Un ciclo en vuelo con la red
  // caida no es progreso, es un reintento condenado, y decirlo es lo unico
  // honesto. Al empezar `vaMal` todavia es false y se dice «Enviando datos»,
  // que entonces SI es verdad; en cuanto empieza a fallar, cambia.
  if (vaMal) return QueToca.sinConexion;
  if (enVuelo) {
    // Mientras el ciclo esta en el paso de subir se dice «enviando», porque es
    // lo que esta pasando. Los tres pasos son el mismo ciclo.
    return paso == PasoDelCiclo.subir ? QueToca.enviando : QueToca.trayendo;
  }
  if (pendientes > 0) return QueToca.hayQueEnviar;
  // VA DETRAS DE `hayQueEnviar` Y DELANTE DE LOS DOS VERDES, y las dos cosas a
  // proposito.
  //
  //  * Detras, porque `hayQueEnviar` ya es un aviso y ademas trae un boton que
  //    hace algo. Taparlo con uno que no tiene boton seria quitarle a alguien la
  //    unica accion que le queda.
  //  * Delante, porque lo que no puede pasar de ninguna manera es que con
  //    trabajo colgado dentro esta pieza se pinte VERDE diciendo «no queda nada
  //    sin enviar». Ese es el caso entero.
  if (hayTrabajoColgado) return QueToca.trabajoColgado;
  // Con los datos de ahora mismo no se ofrece traerlos otra vez. Ver
  // `QueToca.todoAlDia`.
  return hayQueTraer ? QueToca.alDia : QueToca.todoAlDia;
}
