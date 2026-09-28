// LA HOJA DE PRE-DESPACHO DEL ASISTENTE DE RUTAS.
//
// Gemela de «los contadores de renglones viajan a la hoja, y cuentan igual» de
// `test/pantallas/pedidos/imprimir_test.dart`, y existe por lo que ese camino no
// cubría: **son dos caminos al mismo papel** —el de Pedidos y el del asistente—
// y sólo uno estaba probado.
//
// ## Lo que pasó, 28/09/2026
//
// Ese día cambió la regla del pre-despacho. Antes, si a un producto le faltaba
// el peso de UN renglón, la celda salía `—` y la hoja perdía la fila entera: 21
// renglones de 1.149 borraban 4.949 empaques de MALTA GUAJIRA, que es el que más
// se mueve. Ahora se imprime lo que sí se sabe, marcado como mínimo:
// `≥ 26320.0 kg (21 renglones sin peso)`.
//
// El cambio se hizo en el camino de Pedidos y **no en éste**. Por el asistente,
// la misma fila imprimía `26320.0 kg` a secas —como si fueran los kilos enteros
// de los 4.949 empaques— mientras el cajón de al lado, en la misma pantalla,
// decía `≥ 26320.0 kg (21 renglones sin peso)`. Dos papeles distintos para lo
// mismo (`CLAUDE.md` §3-bis), y lo que baja al almacén es el papel.
//
// Los contadores son la mitad que hace honesto el número: sin ellos, el `≥` no
// se puede poner y la cifra se lee como un total.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/impresion/hoja.dart' as papel;
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart';

void main() {
  /// La forma real del incidente: MALTA GUAJIRA con 21 de sus 1.149 renglones
  /// sin peso, y un producto que no sabe nada de ninguno de sus 6.
  TotalesPreDespacho comoElDia28() => TotalesPreDespacho(
    const [
      LineaPreDespacho(
        producto: 'MALTA GUAJIRA 1500 ML BLISTER 6U',
        empaques: 4949,
        unidades: 29694,
        pesoKg: 26320,
        lineasSinPeso: 21,
      ),
      LineaPreDespacho(
        producto: 'VODKA REGIO BLISTER 6U',
        empaques: 364,
        unidades: 2184,
        lineasSinPeso: 6,
      ),
    ],
    pedidos: 264,
    pesoDeLosPedidos: 29835.4,
  );

  papel.HojaPreDespacho hoja() => hojaDePreDespachoDeLaRuta(
    totales: comoElDia28(),
    sucursal: 'La Habana',
    vehiculo: 'Camión 1',
    dia: '2026-09-28',
    pedidos: 264,
    pesoKg: 29835.4,
  );

  test('los contadores de renglones viajan a la hoja, y cuentan igual', () {
    final h = hoja();

    expect(
      h.lineas.first.lineasSinPeso,
      21,
      reason:
          'El contador se quedó en el camino: sin él la fila imprime 26320.0 '
          'como si fuera el peso entero de 4.949 empaques de MALTA GUAJIRA.',
    );
    expect(h.lineas.first.pesoCompleto, isFalse);
    expect(h.lineas.last.lineasSinPeso, 6);

    // Y EL TOTAL DEL PAPEL CUENTA LOS MISMOS RENGLONES QUE LA PANTALLA: 27, no
    // 2. Dos números distintos para la misma pregunta es el §3-bis.
    final enElPapel = papel.TotalesPreDespacho.de(h);
    expect(
      enElPapel.sinPeso,
      comoElDia28().sinPeso,
      reason:
          'La pantalla cuenta ${comoElDia28().sinPeso} renglones sin peso y el '
          'papel ${enElPapel.sinPeso}, con las mismas líneas.',
    );
    expect(enElPapel.sinPeso, 27);
    expect(enElPapel.pesoCompleto, isFalse);
  });

  test('un producto sin peso llega NULO, no en cero', () {
    // Aquí había un `pesoKg: linea.pesoKg ?? 0` con su comentario: «un producto
    // sin peso resuelto suma cero kilos a la hoja, que es lo que pesa lo que no
    // sabemos». Era verdad cuando la hoja no sabía imprimir un nulo; ya no lo
    // es. En el papel, `0 kg` no se distingue de un producto que de verdad no
    // pesa, y con esta hoja alguien baja al almacén a cargar un camión.
    expect(
      hoja().lineas.last.pesoKg,
      isNull,
      reason:
          'un cero ahí se lee como «este producto no pesa», que es un número '
          'creíble y equivocado en el papel con el que se carga el camión',
    );
  });

  test('la hoja del asistente sí lleva el camión, y la de Pedidos no', () {
    // No es un detalle: la de Pedidos sale del almacén y no sabe de camiones
    // (`hojaDePreDespacho` le pone `vehiculo: ''` a propósito). Ésta sale de una
    // ruta que ya tiene el suyo elegido en el paso 3, y esa hoja se le da al
    // que carga.
    expect(hoja().vehiculo, 'Camión 1');
    expect(hoja().sucursal, 'La Habana');
    expect(hoja().pedidos, 264);
  });
}
