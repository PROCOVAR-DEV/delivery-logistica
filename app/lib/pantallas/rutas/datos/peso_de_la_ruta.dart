// CUÁNTO PESA UNA RUTA: LO QUE SUMAN SUS PARADAS, NO LO QUE DICE SU COLUMNA.
//
// ## De dónde salía el «420 kg» encima de 516,5
//
// El 28/09/2026, en la APK 1.0.13 de un SM-A165M, `RT-20260928-003`:
//
//     Planificada · 0.7 km (incl. regreso) · 420 kg · $3.10 · … · Carga total: 2
//     1  POR26-260927-3733   419.7 kg   $2.51
//     2  POR26-260925-3700    96.8 kg   $0.59
//
// 419,7 + 96,8 = 516,5, y la cabecera decía 420 — justo el peso de la primera.
// **Y sólo fallaba el peso**: el importe sumaba las dos (2,51 + 0,59 = 3,10) y
// la carga total contaba las dos. Ésa es la pista entera, y no es que el peso se
// sume mal: es que **el peso era el único número de esa cabecera que NO se
// sumaba de las paradas**. Salía de `routes.total_weight`, y los otros dos de la
// lista que se estaba enseñando justo debajo.
//
// ## Por qué esa columna no puede ser el peso de la ruta
//
// `routes.total_weight` se escribe UNA VEZ, al armar, y después **nadie la
// recalcula**: ni el servidor (`FijarTotalesDeRuta` sólo se llama al armar,
// `api/internal/api/rutas.go` y `api/internal/api/tablero.go`) ni el aparato.
// Es un total congelado, y encima viaja: en la APK la ruta se arma sin señal con
// el peso de aquí, sube, y la bajada escribe encima el que calculó el servidor
// (`nucleo/sincro/bajada.dart`). A partir de ahí la cabecera dice lo que dijo el
// servidor y la lista de paradas dice lo que hay en este aparato, y **nada las
// ata**: son las dos preguntas del §3-bis del `CLAUDE.md` contestadas desde dos
// sitios distintos.
//
// Comprobado que el ARMADO no es lo que falla, en los dos lados y con su prueba:
// `api/internal/api/dos_pedidos_del_mismo_cliente_test.go` y
// `test/pantallas/tablero/dos_pedidos_del_mismo_cliente_test.dart` arman con dos
// pedidos del mismo cliente y la misma dirección y guardan los 516,5. Lo que
// falla es leer ese número más tarde como si siguiera siendo verdad.
//
// ## La decisión, que es la misma que ya se tomó con el importe
//
// El 22/09/2026 `routes.total_price` dejó de ser el importe de la ruta por esto
// mismo, y el importe pasó a sumarse de las paradas
// (`datos/importe_de_la_ruta.dart`). El peso sigue el mismo camino: la columna
// se queda como **espejo de la aritmética del servidor** —para poder
// compararlas— y **el peso que se pinta y con el que se mide el camión sale de
// las paradas**, que son las que la pantalla tiene delante.
//
// Y para que la decisión no se deshaga sola hay una prueba que se pone roja si
// alguna pantalla vuelve a LEER `totalWeight`:
// `test/pantallas/rutas/el_peso_de_la_ruta_test.dart`. Un comentario no falla.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';

/// EL PESO DE TODAS LAS RUTAS DE UNA VEZ, para la lista.
///
/// Se agrupa por `ultima_ruta_id` y no por `route_id` por lo mismo que
/// `paradasPorRuta` e `importePorRuta`: lo que no se entrega suelta su
/// `route_id` para poder ir en la ruta de mañana, y con esa columna una ruta
/// cerrada se iría quedando sin paradas —y por tanto sin peso— según se marcan
/// los devueltos. **Son las MISMAS paradas que enseña «Ver paradas»**, que es lo
/// que hace que el aviso de sobrepeso y la hoja no se puedan contradecir.
///
/// Una ruta sin paradas no sale en el mapa. El cero de verdad lo pone quien
/// llama, que es el único que sabe distinguir «no lleva nada» de «la consulta
/// todavía no ha llegado» — y ese segundo caso no se pinta.
Stream<Map<String, double>> pesoPorRuta(BaseLocal base) {
  // `weight` es `NOT NULL` en las dos bases, así que el `COALESCE` es sólo para
  // que `SUM` sobre cero filas no devuelva `NULL`; con el `GROUP BY` de abajo no
  // puede darse, y se queda porque el día que alguien le añada un filtro sí
  // podría.
  const sql = '''
SELECT ultima_ruta_id AS ruta,
       SUM(COALESCE(weight, 0)) AS peso
  FROM orders
 WHERE ultima_ruta_id IS NOT NULL
 GROUP BY ultima_ruta_id
''';
  return base
      .customSelect(sql, readsFrom: {base.orders})
      .watch()
      .map(
        (filas) => <String, double>{
          for (final fila in filas)
            fila.read<String>('ruta'): fila.read<double?>('peso') ?? 0,
        },
      );
}

/// **Un `Stream`, no un `Future`** (`CLAUDE.md` §3-ter): en la web la base nace
/// vacía en cada carga y se llena un segundo más tarde. Una sola respuesta se
/// quedaría congelada en «esta ruta no lleva nada», que es justo el cero creíble
/// que esto viene a quitar.
final pesoPorRutaProvider = StreamProvider<Map<String, double>>(
  (ref) => pesoPorRuta(ref.watch(baseProvider)),
);

/// LO QUE SE ESCRIBE EN `routes.total_weight`, Y QUE **NO ES EL PESO DE LA
/// RUTA**.
///
/// Es el espejo de la cuenta del servidor: allí `pesoTotal` suma `orders.weight`
/// de los pedidos que entraron (`api/internal/api/rutas.go` y
/// `api/internal/api/tablero.go`), que es exactamente lo que hace esto. Se
/// guarda para poder comparar local y servidor, no para pintarlo.
///
/// **Lo que falta, y es del servidor:** `routes.total_weight` sigue siendo un
/// total congelado también allí, así que quien lea esa columna FUERA de este
/// aparato —un informe en SQL, una exportación— puede ver el peso del día en que
/// se armó y no el de las paradas que la ruta lleva hoy.
double espejoDelPesoDelServidor(Iterable<double> pesos) {
  var suma = 0.0;
  for (final peso in pesos) {
    suma += peso;
  }
  return suma;
}
