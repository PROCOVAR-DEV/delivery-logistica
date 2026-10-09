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
  pruebaDelRechazo();
  pruebasDeSesionInvalidada();
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

/// UN 401 NO MATA EL CANAL. Se reintenta y vuelve.
///
/// # El caso, con la hora del registro del servidor — 29/09/2026
///
/// ```
/// 21:30:45  GET /api/eventos  200
/// 21:30:47  GET /api/eventos  200
/// 21:30:50  GET /api/eventos  401   <- aqui se murio
///           ... CINCO MINUTOS SIN UNA SOLA PETICION ...
/// 21:35:49  GET /api/eventos  200
/// ```
///
/// Jose creo una zona desde el telefono a las **21:32:10**, dentro de ese
/// agujero, y en la web no aparecio nunca. No es que el aviso llegara tarde:
/// **no habia nadie escuchando**. Sus palabras: «la aplicacion hace cosas y no
/// sale en la web».
///
/// La causa era `cerrarDelTodo`, que ante un rechazo cerraba el canal **para
/// toda la pestaña** — sin error en consola, sin aviso en pantalla y sin un solo
/// reintento. La APK ya lo tenia arreglado esa misma tarde y este lado se quedo
/// con el camino viejo.
///
/// Esta prueba levanta el rechazo a proposito: el servidor de mentira contesta
/// **401 al primer intento** y abre al segundo. Si el cliente no reintenta, el
/// `cambio` no llega nunca y esto falla.
void pruebaDelRechazo() {
  test('un 401 no mata el canal: se reintenta y el cambio acaba llegando', () async {
    final recibidos = <String>[];
    final sub = escucharEventos(
      '$urlBase/rechaza-una-vez',
      // Sin token, como la web de verdad con el acceso unico.
      () async => null,
      // Y SIN con que renovar, que es el camino que antes cerraba en seco.
      renovarSesion: null,
    ).listen(recibidos.add);

    // La espera del primer reintento es de un segundo; se le dan cuatro para que
    // el segundo intento abra y mande su `listo` y su `cambio`.
    await Future<void>.delayed(const Duration(seconds: 4));
    await sub.cancel();

    expect(
      recibidos,
      contains('tablero'),
      reason:
          'tras un 401 el canal no volvio a intentarlo: la web se queda muda y '
          'lo que haga el telefono no aparece nunca. Es el fallo del 29/09/2026, '
          'cinco minutos sin una sola peticion.',
    );
  });
}

/// ACCESOS CERRO LA SESION O CAMBIO LOS PERMISOS — 08/10/2026. SOLO LA WEB.
///
/// El servidor de mentira hace lo que la api: `listo`, `event: sesion-invalidada`
/// y CIERRA la conexion. Si el cliente no hace `close()` el navegador reconecta
/// solo, y la segunda conexion le trae un `cambio` de tipo `reconecto` que estas
/// pruebas ven. El prefijo del aviso y sus mensajes se prueban en
/// `test/navegacion/portero_sesion_invalidada_test.dart`.
void pruebasDeSesionInvalidada() {
  /// Lo que sale del canal en [durante] y si el stream se cerro.
  Future<({List<String> recibidos, bool cerrado})> alCaso(
    String caso, {
    Duration durante = const Duration(milliseconds: 1500),
  }) async {
    final recibidos = <String>[];
    var cerrado = false;
    final sub = escucharEventos(
      '$urlBase/invalida/$caso',
      // Sin token, como la web de verdad con el acceso unico.
      () async => null,
    ).listen(recibidos.add, onDone: () => cerrado = true);
    await Future<void>.delayed(durante);
    await sub.cancel();
    return (recibidos: recibidos, cerrado: cerrado);
  }

  test('sesion-invalidada SALE como aviso, el canal se cierra y NO reconecta', () async {
    // Cuatro segundos y medio: la espera del reintento propio es de un segundo
    // y la reconexion automatica de Chrome, de unos tres.
    final r = await alCaso(
      'cerrada',
      durante: const Duration(milliseconds: 4500),
    );

    expect(
      r.recibidos,
      [avisoDeQueVolvimos, 'sesion-invalidada:sesion-cerrada'],
      reason:
          'o el evento no se escucha (la web sigue como si nada y es la sesion '
          'zombi que esto viene a quitar), o el canal reconecto contra una '
          'sesion muerta: `reconecto` en la lista es un 401 cada pocos segundos',
    );
    expect(r.cerrado, isTrue, reason: 'tras el aviso el canal se acaba');
  });

  test('permisos-cambiados sale con su tipo', () async {
    final r = await alCaso('permisos');
    expect(r.recibidos, [
      avisoDeQueVolvimos,
      'sesion-invalidada:permisos-cambiados',
    ]);
  });

  test('un data roto sale como sesion-cerrada', () async {
    final r = await alCaso('roto');
    expect(r.recibidos, [
      avisoDeQueVolvimos,
      'sesion-invalidada:sesion-cerrada',
    ]);
  });

  test('dos eventos seguidos son UN aviso', () async {
    final r = await alCaso('dos');
    expect(r.recibidos.where(esSesionInvalidada), [
      'sesion-invalidada:sesion-cerrada',
    ], reason: 'dos avisos son dos navegaciones; vale el primero');
  });

  test(
    'PAREJA: un evento de OTRO nombre no hace nada y el canal sigue',
    () async {
      final r = await alCaso('otro-nombre');
      expect(r.recibidos, [avisoDeQueVolvimos]);
      expect(r.cerrado, isFalse);
    },
  );
}
