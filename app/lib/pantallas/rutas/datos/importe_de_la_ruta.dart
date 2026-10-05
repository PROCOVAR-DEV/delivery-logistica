// CUÁNTO SUMA UNA RUTA, Y CUÁNTAS DE SUS PARADAS NO SE SABEN.
//
// ## De dónde salía el `$0.00`
//
// El importe de una ruta se pintaba con `usd(ruta.totalPrice)`, y
// `routes.totalPrice` **no sabe decir «no se sabe»**:
//
//  * en el servidor la columna es `total_price double precision NOT NULL
//    DEFAULT 0` (`api/db/migrations/00001_init.sql:426`);
//  * al armar la ruta se calcula `suma + (p.pedidoCosto ?? 0)`
//    (`pantallas/rutas/datos/acciones_rutas.dart`), o sea que una parada sin
//    cotizar suma cero;
//  * y al bajarla se guarda `_numero(j['totalPrice']) ?? 0`
//    (`nucleo/sincro/bajada.dart`).
//
// Tres `?? 0` seguidos: al final del camino no queda ni rastro de que faltara
// nada. El 22/09/2026, en producción, la ruta `RT-20260921-007` decía **«sin
// cotizar» en sus dos paradas** y **`$0.00`** en su tarjeta y en su cabecera, con
// el camión cotizado a 1,50 USD/km y 10,4 km de recorrido. Eso no dice «no hay
// tarifa»: dice que el reparto fue gratis (`CLAUDE.md` §2).
//
// Así que el importe de una ruta **no se lee de `totalPrice`**: se suma de sus
// paradas, que son las que sí saben decir `null`.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/numeros.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../pedidos/datos/formato.dart';

/// Lo que suma una ruta y lo que le falta por saber.
class ImporteDeRuta {
  const ImporteDeRuta({
    required this.total,
    required this.sinCotizar,
    required this.paradas,
  });

  static const nada = ImporteDeRuta(total: 0, sinCotizar: 0, paradas: 0);

  /// La suma de sus paradas, o `null` si **alguna** no está cotizada.
  ///
  /// Es la misma regla, la misma forma y el mismo motivo que
  /// `TotalesPreDespacho._sumaCompleta` en
  /// `pantallas/pedidos/datos/repositorio_pedidos.dart`: «un total a medias es
  /// peor que ninguno». Sumar lo que hay y callar lo que falta da un importe que
  /// parece completo y se queda corto, y éste es un número que alguien cobra.
  final double? total;

  /// Cuántas paradas entraron sin cotizar. Es lo que convierte el `—` en algo
  /// que se puede arreglar.
  final int sinCotizar;

  /// Cuántas paradas lleva la ruta EN TOTAL, las cotizadas y las que no.
  ///
  /// Está aquí sólo para el denominador del rótulo: «2 de 5 sin cotizar» dice
  /// si esto es un fleco o es que la ruta entera está sin precio, y eso cambia
  /// lo que hace quien lo lee. El numerador solo no lo dice.
  final int paradas;

  bool get completo => total != null;

  /// LO QUE SE ESCRIBE DONDE IBA EL IMPORTE. **Nunca un `$0.00`.**
  ///
  /// El 22/09/2026 la ruta `RT-20260921-007` decía `$0.00` en su tarjeta y en su
  /// cabecera con sus dos paradas marcadas «sin cotizar», el camión a 1,50
  /// USD/km y 10,4 km de recorrido. Un cero es un precio: se lee como que el
  /// reparto salió gratis (`CLAUDE.md` §2), y ninguna pantalla lo desmentía.
  ///
  /// No es `Numeros.totalIncompleto` —que es lo que pinta Informes— porque allí
  /// sólo se sabe el numerador y aquí se sabe el de abajo también. Las dos
  /// palabras, que son las que atan a todas las pantallas a llamar a esto de la
  /// misma manera, salen de la misma constante.
  String get rotulo => total == null
      ? '— ($sinCotizar de $paradas ${Numeros.sinCotizar})'
      : usd(total);

  /// LA FRASE QUE DICE QUÉ HACER, o `null` cuando no falta nada.
  ///
  /// El `—` dice que no se sabe; esto dice a qué ir. Mismo criterio y misma
  /// forma que `_faltanPorCotizar` en la pantalla de Informes.
  ///
  /// **Devuelve `null` cuando el total se sabe**, y eso es la mitad de la
  /// regla: un aviso que sale siempre deja de leerse, y entonces tampoco se lee
  /// el día que importa (`CLAUDE.md` §3-quinquies).
  String? get queFalta => total != null
      ? null
      : sinCotizar == 1
      ? 'Falta cotizar 1 parada de $paradas: sin ella no hay importe de la ruta.'
      : 'Faltan cotizar $sinCotizar paradas de $paradas: sin ellas no hay '
            'importe de la ruta.';

  /// Sobre una lista VACÍA da `0`, no `null`: una ruta sin paradas no es una
  /// ruta con el importe a medias, es una ruta que no lleva nada. «Se sabe y
  /// vale cero» es una cifra.
  static ImporteDeRuta deLasParadas(Iterable<double?> costos) {
    var suma = 0.0;
    var faltan = 0;
    var cuantas = 0;
    for (final costo in costos) {
      cuantas++;
      if (costo == null) {
        faltan++;
      } else {
        suma += costo;
      }
    }
    return ImporteDeRuta(
      total: faltan > 0 ? null : suma,
      sinCotizar: faltan,
      paradas: cuantas,
    );
  }

  /// LO QUE SE ESCRIBE EN `routes.total_price`, Y QUE **NO ES EL IMPORTE**.
  ///
  /// ## Por qué esto existe y no es otro `?? 0` de los de tapar
  ///
  /// `routes.total_price` no sabe decir «no se sabe», y no lo sabe en NINGUNO de
  /// los dos lados:
  ///
  ///  * en el servidor es `double precision NOT NULL DEFAULT 0`
  ///    (`api/db/migrations/00001_init.sql:426`);
  ///  * aquí es `real().withDefault(const Constant(0))`
  ///    (`nucleo/base/tablas/dominio.dart`).
  ///
  /// Se miró hacer nulable la columna de aquí, y **no arregla nada por sí sola**:
  /// el nulo local viviría hasta la siguiente bajada, porque el servidor vuelve a
  /// mandar su `0` y `bajada.dart` lo escribe encima. Y en la web no llega ni a
  /// nacer: allí la ruta la crea el servidor y lo que se guarda es lo que él
  /// devolvió. Para que un nulo sobreviviera habría que cambiar la columna del
  /// servidor, su DTO y todas las APK instaladas a la vez.
  ///
  /// ## La decisión: ese número deja de ser el importe de la ruta
  ///
  /// Como no puede decir la verdad, **no se lee**. El importe de una ruta sale de
  /// [deLasParadas] / [importePorRuta], que suman `orders.pedido_costo` y sí saben
  /// decir `null`. Esta columna se queda como **espejo de la aritmética del
  /// servidor**, para que local y servidor se puedan comparar: allí
  /// `precioTotal` suma sólo los `pedidoCosto` no nulos
  /// (`api/internal/api/rutas.go:810-814`), que es exactamente lo que hace esto.
  ///
  /// Y para que la decisión no se deshaga sola, hay una prueba que se pone roja
  /// si alguna pantalla vuelve a LEER `totalPrice`:
  /// `test/pantallas/rutas/el_cero_que_se_escribe_test.dart`. Un comentario no
  /// falla (`CLAUDE.md` §3-bis).
  ///
  /// **Lo que falta, y es del servidor:** que `total_price` pueda decir «no se
  /// sabe», o que la ruta guarde cuántas paradas entraron sin cotizar. Mientras
  /// no lo haga, cualquiera que lea esa columna FUERA de este aparato —un
  /// informe en SQL, una exportación— sigue viendo un cero que no distingue de
  /// un reparto gratis. Está dicho en el informe del 23/09/2026.
  static double espejoDelTotalDelServidor(Iterable<double?> costos) {
    var suma = 0.0;
    for (final costo in costos) {
      if (costo != null) suma += costo;
    }
    return suma;
  }
}

/// El importe de TODAS las rutas de una vez, para la lista.
///
/// Se agrupa por `ultima_ruta_id` y no por `route_id` por lo mismo que
/// `paradasPorRuta`: lo que no se entrega suelta su `route_id` para poder ir en
/// la ruta de mañana, y con esa columna una ruta cerrada se quedaría sin
/// paradas y, por tanto, con un importe de cero.
Stream<Map<String, ImporteDeRuta>> importePorRuta(BaseLocal base) {
  // El `COALESCE` de dentro es inofensivo **porque la suma se tira entera** en
  // cuanto `sin_cotizar` no es cero: no se usa nunca un total al que le falte
  // un sumando. Está para que `SUM` no devuelva `NULL` y haya que distinguir
  // dos nulos distintos en el mismo sitio.
  const sql = '''
SELECT ultima_ruta_id AS ruta,
       SUM(COALESCE(pedido_costo, 0)) AS total,
       SUM(CASE WHEN pedido_costo IS NULL THEN 1 ELSE 0 END) AS sin_cotizar,
       COUNT(*) AS paradas
  FROM orders
 WHERE ultima_ruta_id IS NOT NULL
 GROUP BY ultima_ruta_id
''';
  return base
      .customSelect(sql, readsFrom: {base.orders})
      .watch()
      .map(
        (filas) => <String, ImporteDeRuta>{
          for (final fila in filas)
            fila.read<String>('ruta'): ImporteDeRuta(
              sinCotizar: fila.read<int>('sin_cotizar'),
              paradas: fila.read<int>('paradas'),
              total: fila.read<int>('sin_cotizar') > 0
                  ? null
                  : (fila.read<double?>('total') ?? 0),
            ),
        },
      );
}

/// **Un `Stream`, no un `Future`** (`CLAUDE.md` §3-ter): en la web la base nace
/// vacía en cada carga y se llena un segundo más tarde. Una sola respuesta se
/// quedaría congelada en «esta ruta no tiene paradas», que es justo el cero que
/// esto viene a quitar.
final importePorRutaProvider = StreamProvider<Map<String, ImporteDeRuta>>(
  (ref) => importePorRuta(ref.watch(baseProvider)),
);
