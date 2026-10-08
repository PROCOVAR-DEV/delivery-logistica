/// Las anchuras que deciden que se ve. Estan aqui, con nombre, porque son
/// **reglas del pliego** (§11) y no gustos: un numero suelto dentro de un
/// `if (ancho < 1280)` a los tres meses nadie sabe de donde salio.
abstract final class Anchos {
  /// A partir de aqui la barra lateral es fija. Por debajo se sale de la
  /// pantalla y se abre con el boton de menu.
  static const escritorio = 1024.0;

  /// El umbral estrecho de la barra superior. En el pliego (§11) es el punto
  /// por debajo del cual se oculta el selector de idioma; aqui **no hay
  /// selector de idioma** —la traduccion al ingles se quito entera el
  /// 24/09/2026, ver `lib/idioma.dart`—, pero el numero sigue siendo el que
  /// manda: por debajo de el la barra se compacta (la caja de sucursal pasa de
  /// 220 a 150) para que quepa en un telefono. Sucursal y moneda NO se ocultan
  /// nunca: son los que cambian los numeros.
  ///
  /// Se conserva el nombre para no tocar `barra_superior.dart` y
  /// `menu_de_cuenta.dart` por un renombre, y porque es el umbral del pliego.
  static const idioma = 640.0;

  /// Tabla de Pedidos, por orden de prescindibilidad (§11).
  static const ruta = 1280.0;
  static const articulosYFactura = 1024.0;
  static const entrega = 768.0;

  /// La tabla de Clientes se desplaza ELLA, no la pagina.
  static const minimoTablaClientes = 736.0;

  static const barraLateral = 256.0;
  static const altoBarraSuperior = 64.0;
}

/// Los cuatro anchos de cajon del pliego (§9.2). En movil siempre es la pantalla
/// entera, pase lo que pase.
enum AnchoCajon {
  md(448),
  lg(672),
  xl(896),
  completo(double.infinity);

  const AnchoCajon(this.px);

  final double px;
}
