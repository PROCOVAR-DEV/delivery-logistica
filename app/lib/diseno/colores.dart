import 'dart:math' as math;

import 'package:flutter/material.dart';

/// LA PALETA. Sale del logo, y de ella sale todo lo demas.
///
/// `marca/icono.svg` usa DOS colores y no mas: el oro `#E0A52A` y la tinta
/// `#17130E`. Se comprobo trazo a trazo: el `#054C74` de PROCOVAR aparece en ese
/// fichero **en un comentario**, no en ningun dibujo, y darlo por bueno habria
/// metido en la aplicacion un azul que no esta en el logo.
///
/// Los cuatro que faltan —el verde de «entregado», el rojo de «no se puede», el
/// calido de «ojo con esto» y el de «va por la calle»— **no se eligen a ojo**:
/// se sacan del oro girandole el tono y dejandole SU misma saturacion y SU
/// misma luminosidad. Eso es lo que hace que un color parezca de la misma
/// familia que otro en vez de un parche pegado encima, y es lo que significa
/// que una paleta salga del logo.
///
/// ## Que se toca para cambiar el aspecto de la aplicacion
///
/// Estas ocho lineas. Nada mas. Los tonos derivados —el tinte de una insignia,
/// el borde de una tarjeta, el color de las letras de un boton— se CALCULAN de
/// aqui cada vez que arranca la aplicacion.
///
/// Antes no era asi y por eso esta escrito: `primarioTenue` era `#E9EDFC`, o sea
/// el azul viejo al 8 % **congelado en un numero**. El dia que el primario dejo
/// de ser azul, ese token se quedo azul, y con el la entrada activa del menu y
/// la opcion marcada de cada selector. «Cambiar la paleta» era en realidad cazar
/// cuarenta numeros por las pantallas, y siempre sobrevivia alguno.
abstract final class Paleta {
  // ─── Los tres del logo ─────────────────────────────────────────────────────

  /// EL ORO. El color de la aplicacion: lo que se pulsa, lo que esta activo, lo
  /// que tiene el foco.
  ///
  /// Sustituye al azul `#1F4FE0` que venia de delivery, y el motivo no es gusto:
  /// el icono del reparto es oro sobre tinta y los botones salian azules con
  /// letras blancas, de otra aplicacion. El color sale del logo, no del fondo.
  static const oro = Color(0xFFE0A52A);

  /// LA TINTA. El texto, y lo oscuro del logo. Calida, nunca negro puro: sobre
  /// el papel crema un negro puro se ve como un agujero.
  static const tinta = Color(0xFF17130E);

  // ─── El soporte ────────────────────────────────────────────────────────────

  /// EL PAPEL. El fondo. Se queda como estaba: «color del fondo no, color de los
  /// componentes».
  static const papel = Color(0xFFF7F4EF);

  /// El de las tarjetas, la barra lateral y el cajon.
  static const blanco = Color(0xFFFFFFFF);

  // ─── Las cuatro senales, sacadas del oro ───────────────────────────────────

  /// HECHO: entregado, cobrado, cerrado. El oro girado 115 grados.
  static final hecho = _familiaDelOro(155);

  /// IMPIDE: rechazado, pasado de capacidad. El oro girado hacia atras hasta el
  /// rojo, y ADEMAS bajado de luz.
  ///
  /// Es la unica que se sale de la luminosidad de la familia, y hay una prueba
  /// que lo cazo: con la luz del oro, el rojo y el ambar quedaban a 24 grados de
  /// tono, o sea que una insignia de «rechazado» y una de «ojo con esto» se
  /// veian igual de lejos. El tono solo no los separa —un rojo y un ambar son
  /// vecinos de verdad—, asi que lo que los separa es el peso: el que impide es
  /// mas oscuro, que es como se lee «alto» en cualquier sitio.
  static final impide = _oscurecer(_familiaDelOro(358), 0.12);

  /// AVISO: mira esto, puede que te este enganando. Datos de mas de un dia,
  /// pedidos sin ruta, capacidad al 80 %.
  ///
  /// Es de la familia del oro **a proposito** —un aviso es calido— y por eso hay
  /// una regla de forma que los separa: el aviso sale SIEMPRE como tinte de
  /// fondo con su texto oscuro encima (una insignia), y la marca sale SIEMPRE
  /// como relleno macizo (un boton). No se cruzan ni en peso ni en forma, asi
  /// que no se confunden aunque compartan familia.
  static final aviso = _familiaDelOro(42);

  /// EN CURSO: la ruta que va por la calle, el vehiculo fuera, el dia bajando.
  /// CIRUELA.
  ///
  /// ## Las dos vueltas que costo, para que no se de una tercera
  ///
  /// Se probo primero con el COMPLEMENTARIO exacto del oro (su tono mas 180, o
  /// sea 220 grados) porque sobre el papel es lo mas correcto: el tono que mas
  /// se separa de la marca. Salia `#1F5BD6`, casi clavado al `#1F4FE0` de
  /// delivery — el azul que se acababa de quitar, volviendo por la puerta de
  /// atras con otro nombre.
  ///
  /// Se movio entonces a 196: petroleo, frio pero sin ser el azul de Material.
  /// **Tampoco.** El 16/09/2026 Jose lo vio en el telefono, en la tarjeta de
  /// «Trayendo datos... Clientes...», y sigue siendo azul para quien lo mira:
  /// «sigo con los azules». Y tiene razon — `#1983AA` es azul, por mucho que en
  /// la rueda se llame petroleo. **El logo no tiene ni una gota de azul y la
  /// aplicacion tampoco puede tenerla.**
  ///
  /// Asi que CIRUELA, a 292. Y no por gusto: **es el unico tono que queda**.
  ///
  /// La mitad calida esta llena —155 verde, 42 ambar, 358 rojo— y lo que hay
  /// entre medias se confunde con ellos. El cobre de 22 parecia lo natural y lo
  /// tumbo la prueba de «las cuatro senales se distinguen entre si»: 20 grados
  /// del ambar, que es la mitad del minimo. El grafito, por el otro lado, acaba
  /// siendo el mismo gris de los subtextos. Y la mitad fria entera esta
  /// prohibida, que es de donde venimos.
  ///
  /// La ciruela queda a 66 grados del rojo, 110 del ambar y 137 del verde: la
  /// unica que se separa de las tres. Oscurecida para que no grite —al
  /// 0,16 es una ciruela sobria, no un magenta— y con la saturacion y la luz de
  /// la familia, que es lo que la hace de esta casa y no un color pegado.
  static final enCurso = _oscurecer(_familiaDelOro(292), 0.16);
}

/// El oro con otro tono, pero con SU saturacion y SU luminosidad.
///
/// Esta es la funcion que convierte «tres colores» en «una paleta»: un verde
/// cualquiera al lado del oro se ve prestado; el verde que tiene exactamente la
/// misma saturacion y la misma luz que el oro se ve de la casa.
/// Baja la luz de un color de la familia sin tocarle el tono ni la saturacion.
Color _oscurecer(Color c, double cuanto) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness - cuanto).clamp(0.0, 1.0)).toColor();
}

Color _familiaDelOro(double tono) {
  final base = HSLColor.fromColor(Paleta.oro);
  return HSLColor.fromAHSL(
    1,
    tono % 360,
    base.saturation,
    base.lightness,
  ).toColor();
}

// ─── La cocina. De aqui para abajo no hay ni un color escrito a mano. ────────

/// Contraste WCAG entre dos colores: de 1 (invisible) a 21 (negro sobre
/// blanco). El minimo para texto normal es 4.5; para texto grande o un icono, 3.
double contrasteEntre(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Mezcla [encima] sobre [debajo] con esa opacidad. Es lo que hace un tinte: el
/// rojo al 14 % sobre papel es el fondo de una insignia roja.
Color _mezcla(Color encima, Color debajo, double parte) =>
    Color.alphaBlend(encima.withValues(alpha: parte), debajo);

/// Mueve la luz de [c] —hacia abajo o hacia arriba, la que haga falta— hasta que
/// se lea sobre [fondo] con al menos [minimo] de contraste.
///
/// Esto es lo que deja cambiar la paleta sin mirar: pongas el tono que pongas en
/// [Paleta], su version de texto sale legible. No hay forma de dejar un color
/// ilegible cambiando un numero de arriba.
Color _legibleSobre(Color c, Color fondo, {double minimo = 4.5}) {
  // Si el fondo es claro hay que oscurecer; si es oscuro, aclarar.
  final paso = fondo.computeLuminance() > 0.4 ? -0.02 : 0.02;
  var hsl = HSLColor.fromColor(c);
  var salida = hsl.toColor();
  for (var i = 0; i < 50 && contrasteEntre(salida, fondo) < minimo; i++) {
    final luz = (hsl.lightness + paso).clamp(0.0, 1.0);
    if (luz == hsl.lightness) break;
    hsl = hsl.withLightness(luz);
    salida = hsl.toColor();
  }
  return salida;
}

/// EL COLOR DE LAS LETRAS QUE VAN ENCIMA DE [fondo]: tinta o blanco, el que se
/// lea mejor. **No se escribe «blanco» a mano en ningun boton.**
///
/// Sobre el oro contesta tinta (7,6 de contraste, contra el 2,2 que daria el
/// blanco), y ahi se acabo el «azul con letras blancas»: el dia que la marca
/// vuelva a ser un color oscuro, esta funcion contesta blanco ella sola.
Color letrasSobre(Color fondo) =>
    contrasteEntre(Paleta.tinta, fondo) >= contrasteEntre(Paleta.blanco, fondo)
    ? Paleta.tinta
    : Paleta.blanco;

/// Una senal entera: su tinte de fondo, su tono de texto y su tono vivo.
///
/// Las cinco se construyen con esta misma clase, asi que no puede quedarse
/// ninguna sin ajustar cuando se cambie su color en [Paleta].
final class Senal {
  Senal(this.base)
    : fondo = _mezcla(base, Paleta.papel, 0.14),
      fuerte = _legibleSobre(base, _mezcla(base, Paleta.papel, 0.14)),
      vivo = _legibleSobre(base, Paleta.blanco, minimo: 3);

  /// El color tal cual sale de [Paleta].
  final Color base;

  /// El tinte: el fondo de la insignia.
  final Color fondo;

  /// El texto y el icono que van sobre [fondo]. Garantizado 4.5 de contraste.
  final Color fuerte;

  /// El tono vivo para cifras grandes, puntos y barras sobre blanco, donde basta
  /// con el 3 que pide el texto grande.
  final Color vivo;
}

/// Los colores con nombre y con motivo. **Todo sale de [Paleta].**
abstract final class Colores {
  // ─── La marca ──────────────────────────────────────────────────────────────

  /// EL RELLENO. El oro tal cual: fondo del boton principal, barra activa,
  /// relleno de la casilla marcada, anillo del foco.
  static const marca = Paleta.oro;

  /// LAS LETRAS QUE VAN ENCIMA DE [marca]. Calculado, no elegido.
  static final sobreMarca = letrasSobre(Paleta.oro);

  /// EL PRIMARIO DE TEXTO: el oro oscurecido hasta que se lee sobre papel.
  ///
  /// Hacen falta los dos, y no es un capricho. El oro macizo con letras de tinta
  /// se lee de maravilla; el mismo oro **como texto** sobre blanco da 2,0 de
  /// contraste y no se lee. Asi que lo que se pulsa lleva [marca] y lo que se
  /// escribe lleva [primario].
  static final primario = _legibleSobre(Paleta.oro, Paleta.papel);

  /// El oro al 10 % sobre papel: fondo de la entrada activa del menu y de la
  /// opcion elegida de un selector.
  static final primarioTenue = _mezcla(Paleta.oro, Paleta.papel, 0.10);

  /// El oro aclarado, para lo que va encima de tinta.
  static final primarioClaro = _legibleSobre(Paleta.oro, Paleta.tinta);

  /// El oro, con el nombre con el que se llama en `marca/generar.sh` y en el
  /// icono de la aplicacion.
  static const oro = Paleta.oro;

  /// El verde del dinero cobrado, vivo: para las cifras grandes.
  static final secundario = _hecho.vivo;

  /// El calido de la flota, vivo.
  static final acento = _aviso.vivo;

  // ─── El papel y la tinta ───────────────────────────────────────────────────

  /// EL FONDO. Papel calido, no el `#F9FAFB` azulado de Material.
  static const papel = Paleta.papel;

  /// El de las tarjetas, la barra lateral y el cajon.
  static const blanco = Paleta.blanco;

  /// El texto.
  static const tinta = Paleta.tinta;

  /// Lo secundario: subtextos, etiquetas, notas. Es la tinta subida de luz hasta
  /// que se nota que es secundaria sin bajar del 4.5 sobre papel. Sale de la
  /// tinta, asi que si la tinta cambia de matiz, el subtexto cambia con ella.
  static final tintaSuave = HSLColor.fromColor(Paleta.tinta)
      .withLightness(0.33)
      .toColor();

  /// EL BORDE FINO de 1 px que llevan todas las tarjetas: tinta al 9 % sobre
  /// papel. Nace del fondo, asi que si el papel cambia, el borde lo sigue.
  static final linea = _mezcla(Paleta.tinta, Paleta.papel, 0.09);

  /// La misma linea, mas marcada: el borde de una casilla vacia, que con [linea]
  /// a secas no se ve sobre blanco.
  static final lineaFuerte = _mezcla(Paleta.tinta, Paleta.papel, 0.24);

  /// EL CONTORNO DE UN BOTON SECUNDARIO, y hace falta que sea SUYO — 28/09/2026.
  ///
  /// Desde que los botones van sin fondo (`tema.dart`, [Botones]), de un boton
  /// secundario sólo se ven dos cosas: la palabra y la raya de alrededor. La
  /// palabra va en tinta y se lee de sobra; la raya iba en [lineaFuerte] y
  /// **daba 1,7 de contraste sobre el papel**, o sea que al sol no estaba. Lo
  /// cazó `botones_sin_fondo_test.dart` el mismo día, midiendo.
  ///
  /// [linea] y [lineaFuerte] siguen valiendo para lo que nacieron —separar una
  /// tarjeta del fondo, marcar una casilla vacía—, donde la raya acompaña a algo
  /// que ya se ve. Aquí la raya **es** el mando, así que sube hasta el 3 que
  /// pide WCAG para lo que no es texto: la tinta al 50 % sobre papel, 3,4 contra
  /// el papel y 3,7 contra el blanco de una tarjeta.
  static final lineaDeMando = _mezcla(Paleta.tinta, Paleta.papel, 0.50);

  /// LA TINTA CON UNA OPACIDAD. De aqui salen las sombras, el velo que oscurece
  /// la pantalla detras de un cajon y la rejilla del papel: todo lo translucido
  /// tira a la tinta calida y nunca al negro puro, porque sobre papel crema una
  /// sombra negra se ve gris sucio y es lo que hace que una pantalla parezca de
  /// Material por defecto.
  static Color tintaCon(double opacidad) =>
      Paleta.tinta.withValues(alpha: opacidad);

  /// El velo del cajon.
  static final velo = tintaCon(0.32);

  /// EL VELO DEL RECORRIDO GUIADO, **mas oscuro que el del cajon** — 05/10/2026.
  ///
  /// El del cajon oscurece para apartar lo de detras; este tiene un agujero, y lo
  /// que hace es **apagar todo menos un boton**. Al 32 % el resto de la pantalla
  /// sigue leyendose igual de bien que el control senalado y el agujero no se ve:
  /// el foco deja de serlo. Al 60 % lo de alrededor se sigue reconociendo —hace
  /// falta, porque el paso dice «arriba, a la izquierda de tu avatar»— y el hueco
  /// canta.
  static final veloDelRecorrido = tintaCon(0.6);

  /// El pulgar de la barra de desplazamiento, y el mismo con el raton encima.
  /// Son la linea de las tarjetas, dos pasos mas marcada.
  static final barra = _mezcla(Paleta.tinta, Paleta.papel, 0.22);
  static final barraEncima = _mezcla(Paleta.tinta, Paleta.papel, 0.34);

  // ─── Las cinco senales ─────────────────────────────────────────────────────

  static final _hecho = Senal(Paleta.hecho);
  static final _aviso = Senal(Paleta.aviso);
  static final _impide = Senal(Paleta.impide);
  static final _enCurso = Senal(Paleta.enCurso);
  static final _neutra = Senal(Paleta.tinta);

  /// AVISO = atencion. Datos de mas de un dia, pedidos sin ruta, rutas
  /// `planned`, capacidad al 80 %, informes que no estan al dia.
  static final ambar = _aviso.fuerte;
  static final ambarFondo = _aviso.fondo;

  /// HECHO = cerrado, cobrado, entregado.
  static final verde = _hecho.fuerte;
  static final verdeFondo = _hecho.fondo;

  /// EN CURSO = en marcha. El complementario del oro.
  static final enCurso = _enCurso.fuerte;
  static final enCursoFondo = _enCurso.fondo;

  /// IMPIDE = rechazado o pasado de capacidad.
  static final rojo = _impide.fuerte;
  static final rojoFondo = _impide.fondo;

  /// GRIS = lo normal, lo que no hay que mirar. Gris CALIDO, porque sale de la
  /// tinta: un gris azulado sobre papel crema se ve sucio.
  static final gris = tintaSuave;
  static final grisFondo = _neutra.fondo;

  // ─── Los nombres de siempre ────────────────────────────────────────────────

  /// El borde fino. Alias de [linea].
  static final borde = linea;

  /// El fondo de la aplicacion. Alias de [papel].
  static const fondo = Paleta.papel;
}

/// LOS COLORES DEL MAPA, y por qué no salen de la paleta de la marca.
///
/// La paleta de Procovar nace del oro: funciona en un botón, en una insignia y
/// en una cabecera, que es para lo que se eligió. **Sobre un mapa no funciona**,
/// y por dos motivos distintos:
///
///  * El fondo ya tiene sus colores. OSM pinta las carreteras principales en
///    rosa y naranja y los parques en verde; una línea de recorrido en la
///    ciruela de la casa se confunde con una autopista. Jose, 17/09/2026: «ese
///    morado, ¿quién te mandó a ponerlo?, sigue sin entenderse cuándo se va y
///    cuándo se vira».
///  * Un mapa pintado en oro y tinta no se lee como un mapa. El agua tiene que
///    verse como agua.
///
/// Viven AQUÍ y no sueltos en la pantalla del mapa por la misma razón que todo
/// lo demás: la paleta sólo sirve de algo si es el único sitio donde hay
/// colores, y un `Color(0x…)` escrito en una vista sobrevive a cambiar la
/// paleta. Lo vigila `test/diseno/paleta_test.dart`.
///
/// Lo único que se comparte con la marca es el papel del fondo, para que el
/// mapa no parezca una ventana de otra aplicación pegada dentro.
abstract final class ColoresDelMapa {
  /// El recorrido de ida, y sus flechas de sentido.
  static const recorrido = Color(0xFF2563EB);

  /// El regreso al depósito, a rayas.
  static const regreso = Color(0xFFF97316);

  /// El alfiler de salida y las paradas ya entregadas.
  static const salida = Color(0xFF16A34A);

  /// El importe dentro del globo negro de una parada. Es un verde **claro**: el
  /// de la paleta está elegido para leerse sobre papel y sobre negro se apaga.
  static const importeEnGlobo = Color(0xFF7BE29A);

  // --- El dibujo del paquete de Cuba -------------------------------------
  static const fondo = Colores.papel;

  /// EL AGUA. Los embalses, las lagunas, los ríos anchos **y el mar**.
  ///
  /// Que sea uno solo y no dos es la decisión: el agua es agua, y un océano de
  /// un azul y una bahía de otro sólo dice que alguien los sacó de sitios
  /// distintos. Lo dibuja `fondo_del_paquete.dart`, que desde el 22/09/2026
  /// saca el mar de cerrar la línea de costa contra el borde de la tesela —el
  /// paquete no trae el océano por ningún lado, y por eso hasta esa fecha el
  /// Atlántico salía del crema de [fondo], indistinguible de tierra firme.
  ///
  /// Va flojo y cerca del papel, como los rellenos de al lado: el mapa es el
  /// fondo sobre el que se lee la ruta, y con esto detrás la línea azul del
  /// recorrido tiene que seguir mandando.
  static const agua = Color(0xFFCFE0EA);

  /// La raya de la costa, encima del encuentro entre [agua] y [fondo]. Sigue
  /// haciendo falta con el mar pintado: es lo que marca el borde exacto cuando
  /// los dos tonos se parecen, y a zoom bajo es lo que dibuja la forma de Cuba.
  static const costa = Color(0xFF7FA3B5);
  static const calle = Color(0xFFBCB2A4);
  static const via = Color(0xFF9A8C77);
  static const troncal = Color(0xFFD9A441);
  static const nucleo = Colores.tinta;

  /// El nombre de una calle escrito sobre su trazo. Es un tono más flojo que el
  /// de un núcleo **a propósito**: en una tesela de La Habana entran veinte
  /// nombres de calle y dos de barrio, y con la misma tinta los veinte gritan
  /// igual que los dos y se pierde de un vistazo dónde está uno.
  static const rotuloDeCalle = Color(0xFF5B5346);

  // --- Las capas de relleno, desde el 21/09/2026 --------------------------
  //
  // Jose, comparando el mapa con conexión contra el nuestro: «ya ves como esta
  // ese mapa mucho mejor necesito uno asi». Lo que veía de más era esto: el
  // suelo y las manzanas. Sin ellas, entre calle y calle sólo hay papel, y un
  // barrio de La Habana y uno de Holguín se dibujan igual.
  //
  // Los tonos van FLOJOS y cerca del papel a propósito: esto es el fondo sobre
  // el que se lee la ruta, y una mancha fuerte se come la línea azul. En un
  // mapa, lo que se mira es el camino; el resto está para saber dónde cae.
  static const bosque = Color(0xFFDCE6D2);
  static const parque = Color(0xFFD6E7C8);
  static const hierba = Color(0xFFE3EBDA);

  /// EL HUMEDAL. La Ciénaga de Zapata y los otros 362 que entraron el
  /// 21/09/2026 al coserse los multipolígonos.
  ///
  /// **No es un verde más.** Hasta el 22/09/2026 esta clase no existía aquí y
  /// caía en el `_ =>` de la tabla del pintor, o sea que la ciénaga más grande
  /// del Caribe salía pintada **del color de un prado**: por un prado se mete un
  /// camión y por una ciénaga no, y el mapa lo decía al revés.
  ///
  /// El tono es el punto medio de lo que es una ciénaga —tierra encharcada—, y
  /// eso es también lo que lo separa de sus dos vecinos: la `hierba` es verde
  /// amarillento (tono 88) y el `agua` es azul (tono 202); éste es un verde
  /// azulado a 159, o sea a 70 grados de una y a 44 del otro. Y va **un pelo más
  /// oscuro** que la hierba a propósito: el mapa es el fondo sobre el que se lee
  /// la ruta, así que no puede gritar, pero una mancha que dice «por aquí no se
  /// pasa» tampoco puede ser la más flojita de la capa.
  static const humedal = Color(0xFFCCE3DB);

  static const urbano = Color(0xFFEDE7DE);
  static const industrial = Color(0xFFE6E0E6);
  static const portuario = Color(0xFFE2DCE8);

  /// Las manzanas. Un pelo más oscuras que lo urbano —que es la mancha sobre la
  /// que caen— o no se distinguirían de ella.
  static const edificio = Color(0xFFDCD3C6);

  /// La vía del tren. Gris azulado y fina: cruza el mapa y no puede competir
  /// con las carreteras, pero es una referencia que se reconoce desde el
  /// camión.
  static const tren = Color(0xFF8C8A93);
}
