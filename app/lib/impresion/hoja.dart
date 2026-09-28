/// Los datos que entran en las dos hojas impresas. Dart puro a proposito: aqui
/// no entra `pdf` ni Flutter, para que la cuenta del post-despacho se pueda
/// probar sin abrir un PDF y para que la vista previa en vivo del cierre de ruta
/// («Queda en el camion») coma exactamente lo mismo que el papel.
///
/// Pliego: `../docs/pantallas.md` §10 y `../docs/reglas-negocio.md` §12.
library;

/// Una linea del pre-despacho: lo que hay que sacar del almacen de un producto.
class LineaPreDespacho {
  const LineaPreDespacho({
    required this.producto,
    required this.formatos,
    required this.unidades,
    required this.pesoKg,
    this.lineasSinUnidades = 0,
    this.lineasSinPeso = 0,
  });

  final String producto;

  /// Empaques. En la hoja la columna se llama `Empaques`, pero el dato viene
  /// de Next con el nombre `formatos`: se conserva para que al cruzar las dos
  /// hojas no haya que ir traduciendo nombres de campo.
  final num formatos;

  /// `null` cuando no se sabe: el catálogo no dice cuántas unidades trae ese
  /// empaque, o el producto no está emparejado. En el papel sale `—`.
  ///
  /// **No es cero, y no es `quantity`.** Esta hoja es con la que alguien baja
  /// al almacén a sacar mercancía: un número equivocado se carga en el camión.
  /// El 22/09/2026 decía «SERVILLETA PROSITO PACA 24P · 7 empaques · 4
  /// unidades» —cuatro unidades dentro de siete pacas—, porque se imprimía
  /// `SUM(quantity)`, que unas veces trae unidades y otras repite los bultos.
  final num? unidades;

  /// `null` cuando el producto no tiene peso resuelto. Antes se mandaba cero
  /// «que es lo que pesa lo que no sabemos», y eso es exactamente el cero
  /// creíble: en el papel no se distingue de un producto que de verdad no pesa.
  final num? pesoKg;

  /// CUÁNTOS RENGLONES DEL PEDIDO QUEDARON FUERA de cada una de las dos cifras
  /// de arriba — 28/09/2026.
  ///
  /// Hasta esa fecha bastaba UNO para que la celda saliera `—`. La intención
  /// era buena y el resultado fue una hoja de almacén con la columna `kg` en
  /// blanco justo en los productos que más se mueven: 21 renglones de 1.149
  /// borraban 4.949 empaques de MALTA GUAJIRA. Y no era pasajero: de los 129
  /// productos de Ventra sólo 57 traen peso.
  ///
  /// Ahora la cifra es la de lo que sí se sabe y el papel la imprime con un
  /// `≥` delante cuando esto no es cero. «Pesa por lo menos esto» sirve para
  /// cargar un camión; una raya no. Y un `≥` no se puede confundir con un
  /// total, que es lo único que la regla vieja protegía de verdad.
  ///
  /// **Tiene que decir lo MISMO que la pantalla, letra por letra**, y eso lo
  /// ata `test/impresion/los_dos_pesos_del_pre_despacho_test.dart`, no este
  /// comentario.
  final int lineasSinUnidades;
  final int lineasSinPeso;

  bool get pesoCompleto => lineasSinPeso == 0;
  bool get unidadesCompletas => lineasSinUnidades == 0;
}

/// La hoja con la que alguien baja al almacen a sacar mercancia.
class HojaPreDespacho {
  const HojaPreDespacho({
    required this.sucursal,
    required this.vehiculo,
    required this.pedidos,
    required this.pesoKg,
    required this.lineas,
    this.dia,
  });

  final String sucursal;
  final String vehiculo;

  /// El dia de los pedidos, `AAAA-MM-DD`, si se filtro por uno. Va tal cual: es
  /// lo que escribe la de Next y se compara caracter a caracter.
  final String? dia;

  final int pedidos;

  /// El peso **de los pedidos**, tal como viene en cada pedido. NO es la suma
  /// de los pesos por producto de [lineas], que sale del catálogo y es otra
  /// cuenta: ver la separación escrita en [TotalesPreDespacho].
  final num pesoKg;

  /// Ya vienen ordenadas de mas a menos empaques; esta hoja no las reordena.
  final List<LineaPreDespacho> lineas;
}

/// Una linea del post-despacho: de un producto, lo que salio, lo entregado y lo
/// que tiene que seguir arriba.
class LineaPostDespacho {
  LineaPostDespacho({
    required this.producto,
    this.salio = 0,
    this.entregado = 0,
    this.queda = 0,
  });

  final String producto;

  /// Lo que se cargo: empaques de todas las paradas de la ruta.
  num salio;

  /// Lo de las paradas marcadas como entregadas.
  num entregado;

  /// Lo que tiene que seguir en el camion: lo devuelto, lo cancelado y lo que
  /// nadie marco. Invariante: `salio == entregado + queda`.
  num queda;
}

/// Un producto de una parada que no se entrego, con su numero.
class ProductoDeParada {
  const ProductoDeParada({required this.producto, required this.formatos});

  final String producto;
  final num formatos;
}

/// Una parada que no se entrego: hace falta saber DE QUIEN es lo que vuelve,
/// porque «faltan nueve cajas» no sirve para reclamar.
class ParadaPendiente {
  const ParadaPendiente({
    required this.cliente,
    required this.resultado,
    required this.nota,
    required this.productos,
  });

  final String cliente;

  /// `devuelto`, `cancelado`, o `null` si nadie la marco.
  final String? resultado;
  final String? nota;
  final List<ProductoDeParada> productos;
}

/// La cuenta de lo que tiene que quedar en el camion al volver.
class HojaPostDespacho {
  const HojaPostDespacho({
    required this.ruta,
    required this.sucursal,
    required this.vehiculo,
    required this.entregadas,
    required this.devueltas,
    required this.canceladas,
    required this.sinMarcar,
    required this.lineas,
    required this.pendientes,
    this.salida,
    this.regreso,
  });

  final String ruta;
  final String sucursal;
  final String vehiculo;

  /// Cuando salio y cuando volvio, si se sabe. Textos ya formados: la hoja los
  /// escribe tal cual, igual que la de Next.
  final String? salida;
  final String? regreso;

  final int entregadas;
  final int devueltas;
  final int canceladas;
  final int sinMarcar;

  /// Todas las lineas, ya ordenadas. El papel filtra las de `queda <= 0`;
  /// la lista entera se guarda porque el cierre de ruta la usa para otra cosa.
  final List<LineaPostDespacho> lineas;

  final List<ParadaPendiente> pendientes;

  /// Lo unico que se imprime en la tabla: un producto entregado entero no hay
  /// que contarlo al bajar, y si sale alarga la hoja y esconde las tres lineas
  /// que importan. El umbral `0.0001` es el de la de Next, no `> 0`: con
  /// empaques fraccionados un resto de coma flotante no puede ensuciar la hoja.
  List<LineaPostDespacho> get lineasConResto =>
      lineas.where((l) => l.queda > 0.0001).toList(growable: false);

  /// HAY PARADAS SIN ENTREGAR Y NO SE SABE QUE LLEVABAN — 24/09/2026.
  ///
  /// La tabla sale de los RENGLONES de cada pedido, y un pedido sin renglones
  /// —los hay, y en Pedidos salen con «—» en Artículos— no aporta ninguna. La
  /// hoja imprimia entonces «Nada: se entregó todo lo que salió» en el papel
  /// que firma el almacen, con tres paradas SIN MARCAR listadas dos lineas mas
  /// abajo. Un hueco leido como la afirmacion mas tranquilizadora que hay.
  ///
  /// «No hay lineas» no es «no queda nada»: es **no consta**, y se dice.
  bool get noConstaQueQueda => lineasConResto.isEmpty && pendientes.isNotEmpty;
}

/// Los totales del pie de cada tabla, apartados del dibujo para poder probarlos
/// sin abrir un PDF: es la fila con la que se cuadra el camion.
///
/// ## LOS DOS PESOS SON DOS CUENTAS Y VAN SEPARADOS — 23/09/2026
///
/// **Aquí nos separamos de la hoja de Next a propósito** (`CLAUDE.md` §2: la
/// cuarta separación escrita). Lo que hacía Next, y lo que aquí se copiaba:
/// cada línea imprimía su peso **por producto** —el del catálogo— y el renglón
/// `Total` imprimía `d.pesoKg`, el peso **de los pedidos**. Misma columna,
/// misma unidad, dos cuentas distintas, y nada en el papel que lo dijera.
///
/// El caso concreto, medido en los datos de prueba de `test/impresion`: las
/// líneas suman **300** y el renglón `Total` imprimía **412,5**. En producción
/// se vieron **diez guiones** en la columna `kg` encima de un total de
/// **29.835,4**: un total debajo de diez rayas se lee como la suma de esas
/// rayas. Y quien cuadra el camión **resta esas dos cifras a ojo**.
///
/// Que Next lo haga no lo arregla: **la de Next también está mal**. Y desde el
/// 22/09/2026 la PANTALLA ya los separa en dos renglones rotulados
/// (`TotalesDelPreDespacho`, en `pantallas/pedidos/vista/vista_pre_despacho`),
/// así que copiar a Next dejaba al papel diciendo una cosa y a la pantalla otra
/// —que es peor que cuando los dos mentían igual—. Por eso aquí son **dos
/// campos con dos nombres**, y el papel los imprime en dos renglones con los
/// mismos rótulos que la pantalla.
class TotalesPreDespacho {
  const TotalesPreDespacho({
    required this.formatos,
    required this.unidades,
    required this.pesoDeLosProductos,
    required this.pesoDeLosPedidos,
    required this.productos,
    required this.sinPeso,
    this.sinUnidades = 0,
  });

  factory TotalesPreDespacho.de(HojaPreDespacho h) => TotalesPreDespacho(
    formatos: h.lineas.fold<num>(0, (t, l) => t + l.formatos),
    unidades: _suma(h.lineas.map((l) => l.unidades)),
    pesoDeLosProductos: _suma(
      h.lineas.map((l) => sePuedeSumarElPeso(l.pesoKg) ? l.pesoKg : null),
    ),
    pesoDeLosPedidos: h.pesoKg,
    productos: h.lineas.length,
    // RENGLONES, no productos: un producto con 21 renglones huérfanos de 1.149
    // y otro con los 6 que tiene no son el mismo agujero.
    sinPeso: h.lineas.fold<int>(
      0,
      (n, l) => n + faltan(l.lineasSinPeso, hayCifra: sePuedeSumarElPeso(l.pesoKg)),
    ),
    sinUnidades: h.lineas.fold<int>(
      0,
      (n, l) => n + faltan(l.lineasSinUnidades, hayCifra: l.unidades != null),
    ),
  );

  final num formatos;

  /// La suma de las líneas que SÍ traen unidades, y `null` cuando no las trae
  /// ninguna. Lo que impide que un total corto se lea como completo ya no es un
  /// `null`, es el `≥` que el papel le pone delante mientras [sinUnidades] no
  /// sea cero. Misma regla en la pantalla (`TotalesPreDespacho.unidades`, en
  /// `pantallas/pedidos/datos/repositorio_pedidos.dart`).
  final num? unidades;

  /// La suma de la columna `kg`, que es el peso **por producto**. `null` sólo
  /// cuando no lo sabe ninguna línea; si lo saben unas y otras no, es un MÍNIMO
  /// y se imprime con `≥`, por lo mismo que [unidades]: en la hoja del almacén
  /// un total corto se carga de menos y no se descubre hasta que el camión ya
  /// se fue — pero una columna en blanco tampoco carga nada.
  final num? pesoDeLosProductos;

  /// El peso del CONJUNTO de pedidos, que **no** se suma de las líneas: viene
  /// en cada pedido. Nunca es nulo, y por eso es el que siempre se ha impreso —
  /// en la columna equivocada.
  final num pesoDeLosPedidos;

  /// Cuántas líneas —productos— tiene la hoja. Lo que falta por saber NO se
  /// cuenta aquí: va en [sinPeso] / [sinUnidades], que cuentan renglones.
  final int productos;

  /// Cuántos RENGLONES quedaron fuera de cada suma. Con esto el papel escribe
  /// `≥ 26.320,0 kg (21 renglones sin peso)` en vez de una raya muda: la
  /// primera mitad deja cargar el camión y la segunda dice qué falta por
  /// arreglar. Ver [LineaPreDespacho.lineasSinPeso].
  final int sinPeso;
  final int sinUnidades;

  bool get pesoCompleto => sinPeso == 0;
  bool get unidadesCompletas => sinUnidades == 0;
}

/// Si el peso de una línea entra en el total de la columna `kg`.
///
/// El cero **no** entra, y no es un capricho: el papel ya imprime `—` para un
/// peso cero (`pesoDeFila`, que copia el `l.pesoKg ? … : '—'` de Next, donde el
/// cero es falso), así que si el cero entrara en la suma el total sería la suma
/// de celdas que en el papel no dicen ningún número. **El total de la columna
/// es el total de lo que la columna imprime.**
///
/// Y hace falta de verdad: el asistente de rutas construye la hoja con
/// `pesoKg: linea.pesoKg ?? 0` (`rutas/vista/asistente_nueva_ruta.dart`), así
/// que por ese camino un peso que no se sabe llega como cero. Sumarlo daría un
/// total corto con pinta de completo — el cero creíble de siempre.
///
/// Está atado a `pesoDeFila` con una prueba, no con este comentario:
/// `test/impresion/los_dos_pesos_del_pre_despacho_test.dart`.
bool sePuedeSumarElPeso(num? kg) => kg != null && kg != 0;

/// CUÁNTOS RENGLONES FALTAN EN UNA LÍNEA, y por qué no es «uno por producto» —
/// 28/09/2026, al probarlo.
///
/// Esto contaba `1` por cada producto que no trae la cifra, y con eso el papel
/// decía **«1 renglón sin peso»** donde la pantalla del mismo filtro decía
/// **«21 renglones sin peso»**: los 21 renglones huérfanos de MALTA GUAJIRA se
/// aplastaban a uno solo. Dos números distintos para la misma pregunta, que es
/// el §3-bis otra vez y justo lo que el `≥` venía a evitar.
///
/// Manda el contador de la línea, que es el que cuenta RENGLONES. El `1` se
/// queda **sólo de respaldo**, para quien arma la hoja sin contadores: el
/// asistente de rutas (`rutas/vista/asistente_nueva_ruta.dart`) construye sus
/// líneas con `pesoKg: linea.pesoKg ?? 0` y sin `lineasSinPeso`, y por ese
/// camino lo único que se sabe es que ese producto no aporta nada — pero eso ya
/// basta para que el total no se pueda dar por completo.
///
/// La pantalla hace lo mismo con la misma regla (`TotalesPreDespacho.sinPeso`,
/// en `pantallas/pedidos/datos/repositorio_pedidos.dart`); lo que las ata es
/// `test/impresion/los_dos_pesos_del_pre_despacho_test.dart`, no este
/// comentario.
int faltan(int contados, {required bool hayCifra}) {
  if (contados > 0) return contados;
  return hayCifra ? 0 : 1;
}

/// El pie del post-despacho suma **las filas mostradas**, no todas: si sumara
/// todas, el total no cuadraria con lo que se ve encima.
class TotalesPostDespacho {
  const TotalesPostDespacho({
    required this.salio,
    required this.entregado,
    required this.queda,
  });

  factory TotalesPostDespacho.de(HojaPostDespacho h) {
    final filas = h.lineasConResto;
    return TotalesPostDespacho(
      salio: filas.fold<num>(0, (t, l) => t + l.salio),
      entregado: filas.fold<num>(0, (t, l) => t + l.entregado),
      queda: filas.fold<num>(0, (t, l) => t + l.queda),
    );
  }

  final num salio;
  final num entregado;
  final num queda;
}

/// Suma LO QUE HAY, y `null` sólo cuando no hay nada.
///
/// Antes era «suma sólo si están TODAS», y el motivo era bueno: un total a
/// medias no se distingue de uno completo, y en la hoja del almacén eso es
/// cargar de menos y no descubrirlo hasta que el camión se fue. Lo que cambió
/// el 28/09/2026 no es ese motivo, es que **ahora sí se distingue**: el papel
/// imprime `≥` cuando faltan renglones, y un `≥` no es un total.
///
/// La regla vieja dejaba media hoja en blanco —de 129 productos de Ventra sólo
/// 57 traen peso— y una columna que no sale nunca no protege a nadie.
num? _suma(Iterable<num?> valores) {
  num? suma;
  for (final v in valores) {
    if (v == null) continue;
    suma = (suma ?? 0) + v;
  }
  return suma;
}
