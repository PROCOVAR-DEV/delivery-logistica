import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../base/base.dart';
import '../proveedores.dart';

/// QUE COLECCIONES USA CADA PANTALLA. **La franja se mide contra ESTAS.**
///
/// ## El caso, con fecha — 01/10/2026
///
/// En el telefono, la franja de arriba decia **«Datos de las 8:46»** toda la
/// manana mientras el Tablero, dos centimetros mas abajo, decia **«Visto por
/// ultima vez a las 9:07»** y estaba al dia. Veintiun minutos de diferencia, y
/// puede llegar a **cincuenta y nueve**.
///
/// Ninguna de las dos mentia, y eso es lo que lo hacia dificil de ver:
///
///  * la franja salia de `RegistroDeFrescura.laMasVieja` **sobre las NUEVE
///    colecciones** ([Colecciones.todas]), con el motivo —bueno— de que «una
///    pantalla no esta al dia si una de las colecciones que usa no lo esta»;
///  * y dentro de esas nueve va `almacenes`, que **se refresca sola una vez por
///    hora a proposito** (`nucleo/sincro/bajada.dart`: «el 82 % de lo que se
///    gasta en reposo son los almacenes, que no cambian casi nunca»);
///  * el Tablero, en cambio, ya preguntaba sólo por **las dos colecciones que EL
///    usa**, y por eso si seguia al tablero.
///
/// El resultado es el **§3-quinquies** del `CLAUDE.md` tal cual: con el umbral
/// del ambar en una hora justa (`reloj_de_datos.dart`), la franja rozaba el borde
/// **cada hora, por diseno**. Un aviso que sale siempre deja de leerse, y
/// entonces tampoco se lee el dia que importa.
///
/// ## La regla
///
/// Una pantalla se mide contra **lo que ella pinta**, no contra la copia entera.
/// Y porque medir de menos es la unica forma de que esto vuelva a mentir —y esta
/// vez **al reves, diciendose mas fresca de lo que esta**, que es el lado
/// peligroso—, la lista de una pantalla lleva **todas** las colecciones de las
/// que sale algo de lo que se ve en ella, aunque sea un dato de al lado.
///
/// ## Donde se declara, y por que no se puede olvidar
///
/// En `PantallaRegistrada.colecciones`, que es **obligatorio en el constructor**.
/// No hay valor por defecto a proposito: un defecto silencioso es justamente lo
/// que deja a la pantalla nueva midiendo contra otra cosa sin que nada falle. Una
/// pantalla que no lo declare **no compila**, y lo que declara lo barre
/// `test/navegacion/contrato_registro_test.dart`.
///
/// Las listas viven aqui y no en cada pantalla porque hay dos que comparten
/// —`clientes` las mira tambien para su propio reloj— y dos copias de una lista
/// se separan sin que salte nada (§3-bis). La excepcion es el **Tablero**, que
/// usa colecciones suyas que `nucleo/` no conoce: las declara el propio
/// `pantallas/tablero/registro.dart`, contra la misma constante que usa su
/// `vistoAtProvider`.
abstract final class ColeccionesDePantalla {
  /// Pedidos: la lista, sus renglones y el catalogo del que sale el peso.
  ///
  /// **`almacenes` NO entra**, y es el arreglo entero: esta pantalla no pinta ni
  /// un almacen, asi que la hora a la que bajaron los almacenes no dice nada de
  /// si estos pedidos estan al dia.
  static const pedidos = <String>[
    Colecciones.pedidos,
    Colecciones.renglones,
    Colecciones.productos,
  ];

  /// Rutas: las rutas, sus pedidos, los camiones y **los almacenes**, que aqui si
  /// entran —de ellos sale el punto de partida de cada ruta—. Esta pantalla si
  /// puede decir «datos de hace 1 h» con razon.
  static const rutas = <String>[
    Colecciones.rutas,
    Colecciones.pedidos,
    Colecciones.vehiculos,
    Colecciones.almacenes,
  ];

  /// Clientes: los clientes y los almacenes, que son el punto desde el que se
  /// mide la distancia a cada domicilio.
  ///
  /// Es la MISMA lista que mira el reloj de dentro de la pantalla
  /// (`pantallas/clientes/estado/estado_clientes.dart`): dos sitios diciendo de
  /// cuando son los mismos datos tienen que salir de una sola lista, o un dia
  /// dicen horas distintas en la misma ventana.
  static const clientes = <String>[
    Colecciones.clientes,
    Colecciones.almacenes,
  ];

  /// Vehiculos: la flota, y lo que decide el estado de cada camion —las rutas y
  /// sus pedidos— mas los ajustes, de donde sale el costo por km.
  static const vehiculos = <String>[
    Colecciones.vehiculos,
    Colecciones.rutas,
    Colecciones.pedidos,
    Colecciones.ajustes,
  ];

  /// Almacenes: los almacenes y nada mas.
  ///
  /// Esta es la pantalla que de verdad puede estar cincuenta y nueve minutos por
  /// detras, porque los almacenes se piden una vez por hora. Aqui decirlo **es lo
  /// correcto**: es su dato, y quien va a editar la ubicacion de un almacen tiene
  /// que saber de cuando es lo que esta mirando.
  static const almacenes = <String>[Colecciones.almacenes];

  /// Reportes: lo que se cuadra son pedidos, rutas y camiones.
  static const informes = <String>[
    Colecciones.pedidos,
    Colecciones.rutas,
    Colecciones.vehiculos,
  ];

  /// EL PANEL: las NUEVE, y **a proposito**.
  ///
  /// No es el caso perezoso: es que la pregunta del Panel es exactamente «¿le
  /// falta algo a este aparato?». Ahi manda la bajada mas vieja de todas, porque
  /// es la que decide si hay que traer el dia antes de salir a la calle. Si algun
  /// dia esto se recorta, se recorta con un motivo escrito, no por parecerse a
  /// las demas.
  static const panel = Colecciones.todas;

  /// NINGUNA: esta pantalla no pinta nada que venga de la copia.
  ///
  /// Es un estado de verdad y no un hueco. La puerta de acceso no tiene copia
  /// todavia; Sincronizacion y el canal con PEDIDO leen **en vivo del servidor**
  /// —`GET /sync/estado` y el estado del webhook—, asi que una hora de bajada ahi
  /// no significa nada; y el mapa de Cuba son teselas en disco, que no son una
  /// coleccion de la sincronizacion.
  ///
  /// La franja lo trata como lo que es: **no pinta la hora** —no hay hora que
  /// pintar— y sigue diciendo todo lo demas (sin conexion, lo que queda sin
  /// subir, lo huerfano). Lo que NO hace es caerse a «Sin descargar todavia», que
  /// seria una acusacion sobre algo que nadie ha mirado.
  static const ninguna = <String>[];
}

/// DE CUANDO SON LOS DATOS **DE UNAS COLECCIONES**: la bajada mas vieja de ellas.
///
/// `null` tiene los dos significados que ya tenia en `laMasVieja` y se
/// distinguen fuera: una coleccion sin fila es «no se bajo nunca».
///
/// Con la lista vacia —una pantalla que no pinta nada de la copia— contesta
/// `null` sin preguntarle a la base. Y hace falta decirlo aqui: `laMasVieja` con
/// una lista vacia **revienta** (`fechas.first` sobre una lista sin nada), asi
/// que sin este atajo la pantalla se iria a estado de error.
final frescuraDeLaPantallaProvider = StreamProvider.family<
  DateTime?,
  List<String>
>((ref, colecciones) {
  if (colecciones.isEmpty) return Stream<DateTime?>.value(null);
  return ref.watch(frescuraProvider).laMasVieja(colecciones);
});
