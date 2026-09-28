import 'package:flutter/material.dart';

/// LO QUE VA PEGADO AL BORDE DEL CONTENIDO DE UNA TARJETA — 28/09/2026.
///
/// Jose, mirando una tarjeta de la lista de Rutas:
///
///     «mira ahi en curso no esta ni alinieado con eliminar q es como deberia
///      estar por q es en la esquina derecha de arriba»
///     «es q eliminar es el q esta correcto» · «la insignia de el estado es la
///      q esta mal» · «esta corrida hacia la izquierda en ves de estar a la
///      esquina»
///
/// Y detras, el encargo de verdad: «y creo q eso pasa con varias cosas
/// compruebalas q no quiero q esto pase con mas nada q este todo uniforme como
/// debe estar respetando patrones de diseño».
///
/// # El problema, dicho con numeros
///
/// En una tarjeta hay dos clases de cosas en el borde y NO se colocan igual:
///
///   · **Las que tienen caja** —una insignia, un `Chip`, un `FilledButton`, la
///     caja gris de una cifra—. Su borde visible ES su rectangulo, asi que
///     pegarlas al borde del contenido las deja donde toca.
///   · **Las que no la tienen** —un `TextButton`, un `IconButton`—. Ahi lo
///     unico que se ve es el texto o el glifo, y Material le pone **12 px de
///     aire propio** entre su rectangulo y su texto. Pegar el rectangulo al
///     borde deja el texto 12 px mas adentro, y el ojo lee eso como un diente
///     de sierra.
///
/// Medido el 28/09/2026 en la tarjeta de ruta a 390 px, con
/// `test/sonda/` (`tester.getRect`, no a ojo):
///
///   · borde del contenido de la tarjeta: x = 374;
///   · `TextButton` de «Eliminar»: su caja acaba en 374 y **su texto en 362**.
///
/// Los 12 px son la sangria del propio boton. Y por eso esto **no se arregla
/// con un `Padding(right: 4)` puesto a ojo en cada fichero**: el numero no es un
/// gusto, es lo que ese mando trae dentro, y escrito una vez aqui se puede
/// medir, mutar y cambiar de golpe.
///
/// # Como se usa
///
/// ```dart
/// TextButton(
///   style: PegadoAlBorde.aLaDerecha(),   // el ultimo de un `Row`
///   onPressed: …,
///   child: const Text('Eliminar'),
/// )
/// ```
///
/// # LO TACTIL NO SE SACRIFICA POR ALINEAR
///
/// Esto **quita el aire de un solo lado**, no lo encoge por los dos ni le toca
/// el alto:
///
///   · **el alto no lo toca**, ni para bien ni para mal: el area tactil sigue
///     siendo exactamente la que le de su renglon. En la tarjeta de ruta son 32
///     px porque el renglon es un `SizedBox(height: 32)` —eso viene de antes y
///     no es cosa de esto—, y donde el boton va suelto son los 48 que le pone
///     `_InputPadding`;
///   · el ancho se queda en 124,8 px («Eliminar», medido) contra los 136,8 de
///     antes, muy por encima de los 48 de minimo. Y el trozo que se quita es el
///     aire que habia **fuera del texto por el lado del borde**: quien apunta a
///     la palabra sigue dandole igual.
///
/// Si alguna vez un mando se quedara por debajo de 48 en cualquiera de los dos
/// lados, esto NO es lo que hay que usar: se aparta el mando del borde y se deja
/// que sea la caja de al lado la que cuadre.
///
/// # Y por eso NO se aplica a los `IconButton`
///
/// Un boton de icono es un cuadrado de 40x40 con un glifo de 20 en el centro:
/// quitarle el aire de un lado lo deja en 28 px de ancho de toque, por debajo
/// del minimo, y ademas descentra el glifo dentro de su propio circulo de
/// pulsacion. Ahi la regla es la contraria —se deja donde esta— y lo que se
/// cuadra con el es lo de al lado.
abstract final class PegadoAlBorde {
  /// El aire que Material mete entre el borde de un boton de texto y su texto.
  ///
  /// Es el valor de `TextButton` en Material 3 y esta **medido**, no copiado de
  /// la documentacion: `test/diseno/pegado_al_borde_test.dart` monta un
  /// `TextButton` del tema de la casa y compara su rectangulo con el de su
  /// texto. Si Flutter lo cambia, esa prueba lo dice.
  static const double sangriaDelBotonDeTexto = 12;

  /// Un boton de texto que es **lo ultimo de un renglon**: su texto acaba justo
  /// en el borde del contenido, como la insignia de arriba.
  static ButtonStyle aLaDerecha() => TextButton.styleFrom(
    padding: const EdgeInsets.only(left: sangriaDelBotonDeTexto),
  );

  /// Un boton de texto que es **lo primero de un renglon**: su texto empieza
  /// justo en el borde del contenido, como el resto de la columna.
  static ButtonStyle aLaIzquierda() => TextButton.styleFrom(
    padding: const EdgeInsets.only(right: sangriaDelBotonDeTexto),
  );
}
