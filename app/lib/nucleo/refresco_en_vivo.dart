import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'proveedores.dart';
import 'red/eventos.dart' show avisoDeQueVolvimos;

/// LOS TIPOS DE AVISO, escritos UNA vez.
///
/// Son los mismos textos que publica el servidor (`api/internal/api/eventos.go`).
/// El aviso dice **qué** cambió y no lleva los datos dentro: quien lo recibe
/// vuelve a pedir lo suyo, y esa peticion si va acotada a su sucursal.
///
/// Estaban escritos a mano en cada pantalla, y eso funciona hasta que alguien
/// escribe `'vehiculo'` en singular: no falla nada, no hay error, simplemente ese
/// aviso no le llega nunca a esa pantalla y nadie sabe por que.
///
/// ## QUIEN ATA ESTA LISTA CON LA DEL SERVIDOR — 17/09/2026
///
/// `api/internal/api/protocolo_avisos_test.go`, una prueba de Go que lee ESTE
/// fichero y compara sus literales con las constantes `Cambio…` de
/// `eventos.go`, en los dos sentidos. Antes no habia nada: renombrar
/// `CambioVehiculos = "vehiculos"` a `"vehiculo"` dejaba toda la suite de Go en
/// verde y Flutter ni se enteraba.
///
/// **El `assert` de `refrescarConElAviso` no es red de eso**: valida contra
/// `todos`, o sea contra esta misma lista. Un tipo mal escrito aqui pasa por el
/// sin decir ni pio.
///
/// Y lo que esa prueba NO ata: a quien no use estas constantes. Hoy no queda
/// ninguno —el Tablero paso a `CambioEnVivo.tablero` el 17/09/2026—, pero un
/// literal nuevo escrito a mano manana se le escaparia.
abstract final class CambioEnVivo {
  static const pedidos = 'pedidos';
  static const catalogo = 'catalogo';
  static const rutas = 'rutas';
  static const clientes = 'clientes';
  static const tablero = 'tablero';
  static const vehiculos = 'vehiculos';
  static const almacenes = 'almacenes';
  static const sucursales = 'sucursales';
  static const ajustes = 'ajustes';

  /// Se movio algo en el canal con PEDIDO: entro un aviso, o salio una tanda.
  ///
  /// Jose, 26/09/2026: «SSE con todo esto igual, nada de polling». La pantalla del
  /// canal contesta «¿esta entrando algo?», y a esa pregunta no se le contesta con
  /// una foto de hace un rato: hay que ver el aviso APARECER.
  ///
  /// Lo publican las DOS mitades desde la api —la entrada del webhook y el drenaje
  /// del buzon—, tambien cuando se rechaza: un PEDIDO que manda y un reparto que
  /// rechaza todo es la situacion que hay que ver cuanto antes.
  ///
  /// Lo que NO lo publica es el consumidor de la cola: corre en otro proceso y el
  /// bus vive en la memoria de la api, igual que le pasa a [clientes]. Mientras las
  /// dos puertas convivan, lo que entre por la cola se vera en la vuelta siguiente.
  static const canal = 'canal';

  static const todos = <String>[
    pedidos,
    catalogo,
    rutas,
    clientes,
    tablero,
    vehiculos,
    almacenes,
    sucursales,
    ajustes,
    canal,
  ];
}

/// **VUELVE A PEDIR LO TUYO EN CUANTO EL SERVIDOR DIGA QUE CAMBIÓ.**
///
/// Se llama desde dentro de un proveedor que pide a la red, y lo unico que hace
/// es invalidarlo cuando llega un aviso DE SU TIPO.
///
/// ## Por que hace falta, si el vigia ya dispara un ciclo con cualquier aviso
///
/// Porque **el ciclo sólo repinta lo que vive en la base local**. Las pantallas
/// que leen de la base —Pedidos, Rutas, Clientes— se repintan solas cuando la
/// bajada escribe: tienen un `tableUpdates` debajo. Las que piden a la red en
/// cada visita —Vehiculos y Almacenes— **no se enteran de nada**: el ciclo baja
/// su copia a la base, nadie la mira, y la pantalla sigue enseñando la respuesta
/// que pidio al abrirse.
///
/// Es exactamente el fallo que ya costo una vuelta con el Tablero el 17/09/2026:
/// el canal funcionaba, el servidor registraba la conexion abierta, y en la
/// pantalla no pasaba nada. Se vio con el telefono delante.
///
/// Y con los almacenes es peor todavia: **no viajan en `GET /api/sync/cambios`**
/// —salen en `faltan`— y se piden aparte al final del ciclo.
///
/// ## Se mira el TIPO, no «llego algo»
///
/// Un cambio de clientes no puede costar una peticion de la flota. Son ocho
/// navegadores en la oficina y la conexion de alla.
///
/// No sustituye al temporizador: donde no hay canal, esto no se dispara nunca y
/// el reloj del vigia sigue trayendo el trabajo. Un aviso que no llega no puede
/// dejar a nadie con la pantalla vieja para siempre.
/// ## Y SIEMPRE AL VOLVER DE UNA DESCONEXION — 29/09/2026
///
/// Al tipo que pida cada pantalla se le suma [avisoDeQueVolvimos], y no es
/// opcional: **mientras el canal estuvo caido, los avisos que pasaran no los vio
/// nadie**. Sin esto, uno solo perdido deja esa pantalla mal para siempre — no
/// hasta el temporizador, para siempre, porque quien pide a la red en cada visita
/// no tiene temporizador ninguno.
///
/// Medido ese dia: una zona creada desde el telefono, en el servidor a las
/// 17:34:55, y la web sin enterarse tres minutos despues. El canal se habia
/// abierto a las 17:35:22 — veintisiete segundos tarde— porque el anterior lo
/// corto el proxy. Todo el detalle, en [avisoDeQueVolvimos].
///
/// No se le pide a quien llama que lo incluya, y es a proposito: **olvidarlo no
/// falla**, deja la pantalla vieja y nadie sabe por que. Es el mismo modo de
/// fallo que esta lista de constantes vino a cerrar.
void refrescarConElAviso(Ref ref, List<String> tipos) {
  assert(
    tipos.every(CambioEnVivo.todos.contains),
    'un tipo que el servidor no publica no se recibe nunca, y eso no falla: '
    'la pantalla se queda con el temporizador y nadie sabe por que. Tipos: '
    '$tipos',
  );
  final losSuyosYAlVolver = {...tipos, avisoDeQueVolvimos};
  final suscripcion = ref
      .watch(avisosDelServidorProvider)
      .where(losSuyosYAlVolver.contains)
      // `invalidateSelf` vuelve a ejecutar el proveedor, que vuelve a pedir y a
      // suscribirse. No hay bucle: pedir no publica ningun aviso.
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(suscripcion.cancel);
}
