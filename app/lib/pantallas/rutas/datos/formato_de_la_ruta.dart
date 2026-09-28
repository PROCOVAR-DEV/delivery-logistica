// LOS DOS NUMEROS DE UNA RUTA QUE SE ESTABAN LEYENDO DE DOS MANERAS.
//
// Este fichero existe por lo que Jose vio en el telefono el 28/09/2026 en
// `RT-20260928-001` (3 paradas, Santiago), y son dos cosas distintas con la
// misma raiz: **la pantalla de Rutas escribia lo mismo que el Tablero, pero de
// otra forma, y ademas dejaba en blanco un dato que el Tablero ya sabe
// calcular solo**.
//
// ## 1. «— desde partida» en TODAS las paradas
//
// La insignia de cada parada decia `'${km(parada.segmentKm)} desde partida'`, o
// sea que se leia **de la columna `segment_km` de la base local y de ningun
// otro sitio**. Esa columna se rellena en tres caminos —el armado local
// (`acciones_rutas.armar`), la ruta que vuelve del servidor
// (`_guardarLaRutaQueVolvio`) y la bajada (`nucleo/sincro/bajada.dart`)— pero
// **hay un cuarto que no la escribe**: armar la ruta de una zona desde el
// Tablero en el aparato (`pantallas/tablero/datos/repositorio.dart`, donde se
// escriben `routeId`, `ultimaRutaId`, `vehicleId` y `stopOrder` **y nada mas**).
// Y ese cuarto camino es justo el principal: el dia se arma por zonas desde el
// Tablero. Resultado: ruta recien armada, tres paradas, `segment_km` nulo en
// las tres y una raya muda en cada una hasta que la siguiente bajada trajera
// del servidor el numero que el aparato ya podia calcular.
//
// El arreglo NO es escribir en la base desde aqui —eso es de otra pantalla y de
// otro agente—, sino **dejar de depender de que alguien lo haya escrito**: las
// coordenadas estan en el aparato (el origen en `routes.origin_lat/lng` y el
// cliente en `orders.end_lat/lng`), son las mismas con las que se pinta el
// mapa, y la cuenta es la de siempre.
//
// ## Y de paso, el nombre mentia
//
// `segment_km` **NO es el tramo del recorrido ni la distancia acumulada**: es la
// RADIAL del punto de partida a ese cliente, la misma con la que se cobra el
// domicilio. Se hereda asi de delivery y esta escrito en tres sitios del
// servidor (`api/internal/api/rutas.go:563`, `tablero.go:1605` y
// `db/queries/routes.sql:278`). «desde partida», a secas y debajo de un numero
// de paradas ordenadas, se lee como «llevas X km de ruta», que es otra cosa y
// mas grande. Por eso el rotulo ahora dice **en recta**.
//
// ## 2. El mismo peso escrito de dos maneras
//
// La zona del Tablero decia «516 kg» y el detalle de la misma ruta «516.5 kg».
// Es el mismo bulto y el mismo `double` (516,45 y pico): el Tablero lo pasa por
// `Numeros.kgRedondeado` —entero, con la coma de `es`— y el detalle lo pasaba
// por `kg()` de Pedidos —un decimal, con punto—. Ninguno de los dos esta mal
// por si solo; lo que esta mal es que el mismo peso se llame de dos maneras en
// dos pantallas que se miran seguidas.
//
// Se unifica **hacia el Tablero** y no al reves, por un motivo practico: el
// formato del Tablero lo comparten hoy la columna, la tarjeta y el menu de
// acciones, y esta pantalla es una. Y se ata con una prueba y no con este
// comentario, que es lo que manda el §3-bis del `CLAUDE.md`: el 17/09/2026 el
// comentario que avisaba del «Sin colocar (722) encima de una lista de 293» ya
// estaba escrito y no sirvio de nada, **porque un comentario no falla**.
library;

import '../../../diseno/numeros.dart';
import 'geo.dart';

/// EL PESO DE UNA RUTA, con el MISMO formato que la zona del Tablero.
///
/// Es un rodeo de una linea a proposito: lo que ata este formato al del Tablero
/// es `app/test/pantallas/rutas/el_mismo_peso_escrito_igual_test.dart`, que
/// compara esta funcion con `pesoBonito` del Tablero sobre una tabla de valores.
/// Si alguien cambia cualquiera de las dos, se pone rojo.
///
/// **Es para el peso de la RUTA ENTERA**, no para el de una parada suelta. El
/// peso de una parada se sigue escribiendo con un decimal (`kg()` de Pedidos) y
/// eso es a proposito: redondear 516,45 kg de camion a 516 no pierde nada, pero
/// redondear un bulto de 0,4 kg lo deja en «0 kg», y un cero creible es el fallo
/// que mas caro sale aqui (`CLAUDE.md` §2 y §4).
String pesoDeLaRuta(double kg) => Numeros.kgRedondeado(kg);

/// LO QUE UNA PARADA DICE QUE HAY DESDE LA PARTIDA, o por que no lo dice.
///
/// Devuelve el rotulo entero de la insignia, no solo el numero, porque **los
/// tres casos sin numero tambien son un rotulo** y ninguno puede ser una raya
/// muda: quien la lee tiene que saber si falta el almacen o falta el cliente.
///
/// Las palabras no son nuevas: «sin punto de partida» es lo que ya escribe la
/// tarjeta de la lista de rutas cuando una ruta no tiene origen, y «sin ubicar»
/// es lo que escribe el Tablero (`kmBonito`) sobre un pedido sin coordenadas.
///
/// [guardado] es `orders.segment_km` y **manda cuando existe**: es el numero con
/// el que se repartio la carga y con el que se cobro el domicilio, y si algun
/// dia el origen de la ruta cambiara, el de la base sigue siendo el del cobro.
/// Cuando no existe se calcula, y da lo mismo: las dos cuentas son la misma
/// haversine (lo ata `km_desde_la_partida_test.dart`).
String rotuloDesdeLaPartida({
  double? guardado,
  double? origenLat,
  double? origenLng,
  double? lat,
  double? lng,
}) {
  final km = kmDeLaParadaDesdeLaPartida(
    guardado: guardado,
    origenLat: origenLat,
    origenLng: origenLng,
    lat: lat,
    lng: lng,
  );
  if (km != null) return '${Numeros.km(km)} en recta desde la partida';
  if (lat == null || lng == null) return 'sin ubicar';
  return 'sin punto de partida';
}

/// La RADIAL de la partida a la parada, en km, o `null` si no se puede saber.
///
/// **No es el tramo del recorrido ni lo que se lleva andado**: es la linea recta
/// del origen a ese cliente, igual que `segment_km` en el servidor e igual que
/// `kmAlAlmacen` en las tarjetas del Tablero. Para los km del camion —los
/// tramos mas el regreso— esta [kmDelCircuito] en `geo.dart`, que es otro numero
/// y no se pueden confundir.
double? kmDeLaParadaDesdeLaPartida({
  double? guardado,
  double? origenLat,
  double? origenLng,
  double? lat,
  double? lng,
}) {
  if (guardado != null) return guardado;
  if (origenLat == null || origenLng == null) return null;
  if (lat == null || lng == null) return null;
  return haversineKm(Punto(origenLat, origenLng), Punto(lat, lng));
}
