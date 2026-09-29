// EL CANAL DE LA **WEB**, ejecutado en un navegador de verdad.
//
// `eventos_web.dart` sólo compila para web, así que las pruebas de la máquina
// virtual —o sea todas las demás de esta carpeta— **no lo tocan ni de lejos**:
// `eventos_io_test.dart` prueba el transporte de la APK y el escritorio, y con
// eso en verde el de la web podía estar roto entero sin que nadie se enterara.
// Y la web es justo donde Jose vio el fallo del 29/09/2026: se creó una zona
// desde el teléfono, entró en el servidor a las 17:34:55 y el navegador siguió
// diciendo «las zonas las pones tú» tres minutos después.
//
// Se corre con Chrome SIN VENTANA —`--platform chrome` arranca headless— y con
// el servidor de mentira levantado aparte, porque esto vive dentro del navegador
// y ahí no hay `dart:io` con el que abrir un puerto:
//
//     dart test/apoyo/servidor_sse_del_navegador.dart 8123 &
//     timeout 300 flutter test --platform chrome test/nucleo/red/eventos_web_test.dart
//     kill %1
//
// El `@TestOn('browser')` es lo que la deja fuera del `flutter test` normal: sin
// él, la máquina virtual intenta compilar `dart:js_interop` y revienta. Y por eso
// mismo **esto no entra en `./comprobar.sh`**: hay que lanzarlo a mano al tocar
// `eventos_web.dart`. Comprobado el 29/09/2026: con el `listo` quitado de ahí, las
// 111 pruebas de la máquina virtual siguen en verde.
@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/eventos.dart';

/// El servidor de mentira. Va en 127.0.0.1 y NO en un dominio de Procovar: la
/// regla de la casa prohíbe cualquier petición a `*.procovar.cloud` desde este
/// ordenador.
const urlBase = 'http://127.0.0.1:8123/api';

void main() {
  test('en la web se elige el transporte de la web, no el vacío del stub', () {
    expect(
      hayCanalDeEventos,
      isTrue,
      reason:
          'la importación condicional cayó en `eventos_stub.dart`: entonces el '
          'canal no existe en la web, no llega ningún aviso y manda el reloj de '
          'dos minutos — que es exactamente lo de antes',
    );
  });

  test('el `listo` del servidor SALE como «volví», y antes que ningún cambio', () async {
    final recibidos = <String>[];
    final primeros = Completer<void>();
    final sub = escucharEventos(urlBase, () async => 'tok').listen((t) {
      recibidos.add(t);
      if (recibidos.length >= 2 && !primeros.isCompleted) primeros.complete();
    });
    addTearDown(sub.cancel);

    await primeros.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail(
        'el canal de la web no emitió dos avisos en diez segundos. Recibidos: '
        '$recibidos. Si está vacío, o el servidor de mentira no está levantado '
        'en 8123, o el `listo` se sigue tirando en `eventos_web.dart` y la web '
        'no se entera de que estuvo desconectada',
      ),
    );

    expect(
      recibidos.first,
      avisoDeQueVolvimos,
      reason:
          'lo primero que sale del canal de la web tiene que ser «volví». Sin '
          'eso, lo que pasara en el servidor mientras el canal estuvo caído '
          '—el proxy lo corta cada 300 s— no lo ve nadie, y el Tablero y '
          'Vehículos y Almacenes se quedan viejos para siempre, porque no se '
          'vuelven a pedir por su cuenta',
    );
    expect(
      recibidos[1],
      'tablero',
      reason: 'el `cambio` de siempre dejó de salir por reenviar el `listo`',
    );
  });
}
