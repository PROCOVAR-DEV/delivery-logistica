// DOS PARADAS EN LA MISMA DIRECCIÓN SON DOS CHINCHETAS, NO UNA.
//
// Lo vio Jose de un vistazo el 29/09/2026, con una ruta suya delante:
//
//     «por qué siguen 2 en vez de 3, son 3 paradas y sólo veo 2»
//
// Tenía razón. Las paradas 2 y 3 eran el mismo cliente en la misma dirección
// —`POR26-260927-3733` y `POR26-260925-3700`, los dos «KIOSKO HABANA CLUB OMAR
// JIMENEZ MONTOYA L2» en Aguilera/San Agustín y Baranda, los dos a 0,4 km— así
// que sus marcadores caían en el mismo punto exacto y el de atrás quedaba
// **tapado** por el de delante. El croquis los pintaba los dos, uno encima del
// otro, y sólo se veía uno.
//
// # Por qué no es cosmético
//
// **Quien lleva el camión cuenta las chinchetas** para saber cuántas paradas le
// quedan. Jose acaba de hacerlo mirando su propia ruta. Con doce paradas donde
// cuatro comparten dirección se ven ocho, y se da por hecho que faltan pedidos
// — o peor: se da la ruta por terminada con cuatro entregas sin hacer.
//
// Un cliente con dos pedidos el mismo día no es un caso raro que haya que
// buscar: la tarjeta del Tablero lo dice con sus propias palabras, «2 pedidos de
// este cliente hoy».
//
// Es la misma familia que lo del 28/09/2026 —dos pedidos del mismo cliente
// contados como uno en el peso de la ruta—, en el mapa en vez de en el peso.
//
// # Por qué se prueba aquí y no pintando
//
// `lasQueCaenJuntas` es Dart puro sobre `Offset`: se comprueba sin montar un
// widget, sin lienzo y sin capturar una imagen. Comparar píxeles de un dibujo es
// lento, frágil y no dice qué está mal cuando falla.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/recorrido.dart';
import 'package:reparto/pantallas/rutas/vista/croquis_de_ruta.dart';

void main() {
  PuntoDelCroquis enPunto(int numero, Offset donde, {bool entregada = false}) =>
      PuntoDelCroquis(
        ParadaDelRecorrido(
          id: 'p$numero',
          numero: numero,
          etiqueta: 'Parada $numero',
          punto: null,
          entregada: entregada,
        ),
        donde,
      );

  test('tres paradas en tres sitios son tres chinchetas', () {
    final juntas = lasQueCaenJuntas([
      enPunto(1, const Offset(10, 10)),
      enPunto(2, const Offset(200, 200)),
      enPunto(3, const Offset(400, 50)),
    ]);

    expect(juntas, hasLength(3));
    expect(
      juntas.map((g) => g.rotulo),
      ['1', '2', '3'],
      reason: 'sin nada que agrupar, cada parada se dibuja como siempre',
    );
  });

  test('dos en el MISMO portal son una chincheta que dice «2·3»', () {
    final juntas = lasQueCaenJuntas([
      enPunto(1, const Offset(10, 10)),
      enPunto(2, const Offset(200, 200)),
      // La 3, en el mismo sitio que la 2: el caso de Jose.
      enPunto(3, const Offset(200, 200)),
    ]);

    expect(
      juntas,
      hasLength(2),
      reason: 'dos paradas en el mismo punto son UNA chincheta, no dos tapadas',
    );
    expect(
      juntas.map((g) => g.rotulo),
      ['1', '2·3'],
      reason:
          'la chincheta no dice que ahí hay dos paradas. Quien conduce cuenta '
          'chinchetas para saber cuántas le quedan: con doce paradas donde '
          'cuatro comparten dirección ve ocho y da la ruta por terminada con '
          'cuatro entregas sin hacer',
    );
  });

  test('a unos píxeles de distancia también se solapan, y también se juntan', () {
    // No hace falta el píxel exacto: la chincheta mide 21 px, así que a diez de
    // distancia una tapa el número de la otra igual.
    final juntas = lasQueCaenJuntas([
      enPunto(1, const Offset(100, 100)),
      enPunto(2, const Offset(108, 104)),
    ]);

    expect(juntas.map((g) => g.rotulo), ['1·2']);
  });

  test('pero dos portales de la misma cuadra NO se juntan', () {
    // La otra mitad, y sin ella el arreglo miente por el otro lado: agrupar dos
    // sitios distintos manda al chofer a uno solo.
    final juntas = lasQueCaenJuntas([
      enPunto(1, const Offset(100, 100)),
      enPunto(2, const Offset(160, 100)),
    ]);

    expect(
      juntas,
      hasLength(2),
      reason:
          'se juntaron dos paradas que están a sesenta píxeles. Son dos sitios '
          'distintos y hay que ir a los dos',
    );
  });

  test('con muchas en el mismo sitio se dice el primero y CUÁNTAS más', () {
    final juntas = lasQueCaenJuntas([
      for (var i = 1; i <= 6; i++) enPunto(i, const Offset(50, 50)),
    ]);

    expect(juntas, hasLength(1));
    expect(
      juntas.single.rotulo,
      '1·2·3+3',
      reason:
          'un «…» no dice cuántas hay, y cuántas es justo lo que hace falta '
          'para saber si la ruta está terminada',
    );
  });

  // EL COLOR DICE LO QUE FALTA, NO LO QUE YA ESTÁ.
  //
  // Con una parada entregada y otra sin entregar en el mismo portal, pintar el
  // grupo del color de «entregada» dice «aquí ya está hecho» sobre una parada
  // que sigue en el camión. Es el mismo modo de fallo de siempre en esta casa:
  // una pantalla verde encima de trabajo sin hacer.
  test('si queda una sin entregar, el grupo NO se pinta de entregado', () {
    final juntas = lasQueCaenJuntas([
      enPunto(1, const Offset(50, 50), entregada: true),
      enPunto(2, const Offset(50, 50)),
    ]);

    final soloEntregadas = lasQueCaenJuntas([
      enPunto(1, const Offset(50, 50), entregada: true),
      enPunto(2, const Offset(50, 50), entregada: true),
    ]);

    expect(
      juntas.single.color,
      isNot(soloEntregadas.single.color),
      reason:
          'con una entregada y otra sin entregar en el mismo portal, el grupo '
          'se pinta igual que si estuvieran las dos hechas: verde sobre trabajo '
          'que sigue en el camión',
    );
  });
}
