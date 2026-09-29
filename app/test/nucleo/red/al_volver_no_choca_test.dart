// EL «VOLVÍ» DEL TRANSPORTE NO PUEDE LLAMARSE COMO UN AVISO DEL SERVIDOR.
//
// `avisoDeQueVolvimos` viaja por el MISMO `Stream<String>` que los tipos que
// publica el servidor (`CambioEnVivo.pedidos`, `.tablero`…). Son dos cosas
// distintas —uno dice «cambió X», el otro «estuve desconectado»— y comparten
// tubería, así que el día que coincidan en el texto pasan dos cosas a la vez y
// ninguna se ve:
//
//  * cada reconexión se leería como un cambio de esa colección, y son ocho
//    navegadores en la oficina con la conexión de allá, cada cinco minutos;
//  * y al revés: ese cambio del servidor dispararía el refresco de TODAS las
//    pantallas, porque `refrescarConElAviso` suma este aviso a todos los tipos.
//
// Nada de eso falla. Se paga en datos y en batería, y se descubre mirando el
// registro de red con mucha atención.
//
// Va aparte de `protocolo_avisos_test.go` a propósito: aquella prueba ata las
// dos LISTAS —el servidor y `CambioEnVivo`— y este aviso no está en ninguna de
// las dos, precisamente porque no lo publica el servidor.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/eventos.dart' show avisoDeQueVolvimos;
import 'package:reparto/nucleo/refresco_en_vivo.dart';

void main() {
  test('«al volver» no es ninguno de los tipos que publica el servidor', () {
    expect(
      CambioEnVivo.todos,
      isNot(contains(avisoDeQueVolvimos)),
      reason:
          '`$avisoDeQueVolvimos` coincide con un tipo del servidor. Entonces '
          'cada reconexión —una cada cinco minutos, que es lo que tarda el '
          'proxy en cortar— se lee como un cambio de esa colección, y ese '
          'cambio de verdad refresca todas las pantallas. No falla nada: se '
          'paga en datos y en batería',
    );
  });

  test('y lleva guion, que es lo que lo mantiene fuera del convenio', () {
    // Los tipos del servidor son una palabra sin separadores (`pedidos`,
    // `tablero`, `sucursales`). Mientras éste lleve guion no puede chocar con
    // uno nuevo por descuido.
    expect(
      avisoDeQueVolvimos,
      contains('-'),
      reason:
          'sin el guion, el próximo tipo que publique el servidor puede '
          'coincidir con éste sin que nadie lo note al escribirlo',
    );
    expect(
      CambioEnVivo.todos.where((t) => t.contains('-')),
      isEmpty,
      reason:
          'un tipo del servidor empezó a llevar guion: entonces el guion ya no '
          'distingue nada y hace falta otra forma de separarlos',
    );
  });
}
