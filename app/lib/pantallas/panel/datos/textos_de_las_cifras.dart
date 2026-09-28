// LO QUE DICEN LAS CUATRO CIFRAS DEL PANEL CUANDO EL NÚMERO NO SE EXPLICA SOLO.
//
// Funciones puras sobre las cifras: ni Flutter ni base de datos. Van aparte del
// widget porque son frases que se comparan letra a letra —lo que lee Jose— y no
// hace falta pintar una pantalla para comprobarlas.
//
// ## De dónde salen, 28/09/2026
//
// Jose, mirando el Panel y el Historial de Rutas:
//
// > «me dice q entregado uno y en hsitorial me sale vacio eso q se entrego si no
// > se ah completado nada»
//
// Los dos números estaban bien. `POR26-260925-3700` se entregó a las 19:44 en la
// ruta `RT-20260928-001`, que sigue **en curso**; el Historial cuenta rutas
// CERRADAS, y la única cerrada que había era de La Habana mientras él miraba
// Santiago. O sea: ningún fallo en las cuentas. El fallo fue que tuvo que
// preguntarlo.
//
// Son dos preguntas distintas y las dos están bien contestadas:
//
//  * «Entregados hoy» cuenta **PEDIDOS** con `delivered_at` desde las 00:00;
//  * el Historial de Rutas cuenta **RUTAS** cerradas, sin ventana de tiempo.
//
// Un camión en la calle con una parada hecha sale en la primera y no en el
// segundo, **y eso es lo normal**.
//
// ## Y por eso la frase NO sale siempre
//
// `CLAUDE.md` §3-quinquies: un aviso que sale siempre deja de leerse, y entonces
// tampoco se lee el día que importa. Con todas las rutas del día cerradas las dos
// cuentas no se contradicen en nada y aquí no hay nada que explicar: la frase
// vuelve a ser `null` y lo único que queda es poder llegar al detalle, que es lo
// que de verdad hacía falta. Las pruebas de esto van en pareja: que salga cuando
// toca y que **no salga** cuando no.

abstract final class TextosDeLasCifras {
  /// El gesto de la tarjeta de «Entregados hoy». Literal aquí para que la prueba
  /// busque lo que se lee —o lo que oye quien usa un lector de pantalla— y no un
  /// identificador interno.
  static const verLosEntregados = 'Ver los pedidos entregados hoy';

  /// Lo que va debajo del número de «Entregados hoy».
  ///
  /// [entregadosHoy] son los PEDIDOS entregados desde las 00:00 y
  /// [enRutaSinCerrar] los que de ésos viajan en una ruta que todavía no se ha
  /// cerrado — o sea, exactamente los que el Historial de Rutas todavía no
  /// enseña.
  ///
  /// `null` en los dos casos en los que no hay nada que aclarar: sin entregas de
  /// hoy, y con todas las rutas del día ya cerradas.
  static String? entregadosHoy({
    required int entregadosHoy,
    required int enRutaSinCerrar,
  }) {
    if (entregadosHoy <= 0 || enRutaSinCerrar <= 0) return null;
    // «sin cerrar» y no «en curso»: lo que hace que el Historial no lo enseñe es
    // que la ruta no esté cerrada, no que esté rodando. Una planificada tampoco
    // sale allí.
    final enRuta = enRutaSinCerrar == 1
        ? 'en una ruta sin cerrar'
        : 'en rutas sin cerrar';
    return '$enRutaSinCerrar $enRuta, aún no en el Historial';
  }

  /// DE QUIÉN SON LAS CIFRAS, encima de las cuatro tarjetas.
  ///
  /// [sucursal] es el nombre de la que está elegida arriba, o `null` cuando están
  /// todas. Y devuelve `null` —o sea, no se escribe nada— cuando hay una
  /// sucursal elegida pero su nombre todavía no ha bajado: mejor una línea que
  /// falta un segundo que una que dice «Cifras de» y se queda a medias.
  static String? deQuienSon({required bool todas, required String? sucursal}) {
    if (todas) return 'Cifras de todas las sucursales';
    if (sucursal == null || sucursal.isEmpty) return null;
    return 'Cifras de $sucursal';
  }
}
