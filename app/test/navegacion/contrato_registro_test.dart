import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/pantallas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';

/// Lo que garantiza el contrato de registro. Si un agente de pantalla lo rompe,
/// falla aqui y no en la pantalla de alguien.
void main() {
  final pantallas = pantallasDeLaAplicacion();

  test('ninguna ruta repetida', () {
    final rutas = pantallas.map((p) => p.ruta).toList();
    expect(rutas.toSet().length, rutas.length, reason: 'hay una ruta repetida');
  });

  test('todas las rutas empiezan por barra', () {
    for (final p in pantallas) {
      expect(p.ruta.startsWith('/'), isTrue, reason: p.ruta);
    }
  });

  /// NINGUNA PANTALLA PUEDE LLAMARSE COMO UN CAMINO DEL PROXY — 17/09/2026.
  ///
  /// En el servidor, Traefik reparte por camino y **se queda con lo suyo antes
  /// de que la aplicacion vea nada**:
  ///
  /// ```
  /// Host(`reparto.procovar.cloud`) && PathPrefix(`/api`)   -> el reparto
  /// Host(`reparto.procovar.cloud`) && PathPrefix(`/sync`)  -> el sincronizador
  /// Host(`reparto.procovar.cloud`)                         -> esta aplicacion
  /// ```
  ///
  /// La pantalla de Sincronizacion vivia en `/sync`. Navegando por el menu
  /// funcionaba —eso lo resuelve el enrutador dentro del navegador— y por eso
  /// nadie lo vio: el unico camino que falla es **recargar ahi o abrir el
  /// enlace**, y entonces contesta el sincronizador con un `401` que no tiene
  /// nada que ver con la aplicacion.
  ///
  /// Es un fallo que no se ve leyendo el codigo de la aplicacion, porque la
  /// mitad que lo causa esta en el fichero de Traefik. Aqui queda escrito para
  /// que la proxima pantalla que se llame `/api-algo` o `/sync-algo` falle antes
  /// de salir de esta maquina.
  test('ninguna ruta invade un camino del proxy', () {
    // Los prefijos que el servidor NO entrega a la aplicacion.
    const delProxy = <String>['/api', '/sync'];
    for (final p in pantallas) {
      for (final suyo in delProxy) {
        // `startsWith(suyo)` a secas, y no `'$suyo/'`, que era lo que estaba y
        // no cubria nada. `PathPrefix` de Traefik es prefijo de CADENA, no de
        // segmento: con `PathPrefix(`/sync`)`, la direccion `/sync-estado` se la
        // queda el sincronizador igual que `/sync`. Se comprobo poniendo la
        // pantalla en `/sync-estado`: la guarda pasaba en verde y la aplicacion
        // habria vuelto a quedarse fuera.
        expect(
          p.ruta.startsWith(suyo),
          isFalse,
          reason:
              '«${p.ruta}» cae dentro de «$suyo», que en el servidor es del '
              'proxy: recargar ahi no llega a la aplicacion. Ponle otro nombre '
              'a la pantalla; el prefijo no se toca, que es la direccion que '
              'ya usan las APK instaladas.',
        );
      }
    }
  });

  test('las seis del pliego mas el tablero y reportes estan registradas', () {
    final rutas = pantallas.map((p) => p.ruta).toSet();
    expect(
      rutas,
      containsAll(<String>[
        '/dashboard',
        '/routes',
        '/orders',
        '/customers',
        '/vehicles',
        '/warehouses',
        '/reports',
        '/tablero',
        // Se podia borrar `registrarSincronizacion()` entera —sin ruta y sin
        // entrada de menu— y las 788 pruebas seguian verdes. Lo encontro el
        // auditor el 17/09/2026, justo en el cambio que movia esa pantalla de
        // sitio.
        '/sincronizacion',
      ]),
    );
  });

  test('Reportes SI esta en el menu, a proposito', () {
    // Iba en `false` copiando al Next, que no la tiene en su barra lateral y
    // solo se llega desde las acciones rapidas del Panel. Asi copiado, Jose no
    // la encontro: «esa vista de reportes no sale en los links para moverse».
    //
    // Una pantalla entera detras de un atajo del Panel es una pantalla que nadie
    // abre, y esta es la que se usa para cuadrar la caja. El patron se sigue
    // salvo donde se equivoca.
    final reportes = pantallas.firstWhere((p) => p.ruta == '/reports');
    expect(
      reportes.enElMenu,
      isTrue,
      reason: 'si vuelve a salir del menu que sea por una razon, no por copiar',
    );
    expect(reportes.titulo, 'Reportes');
  });

  test('las etiquetas del menu son las literales del pliego', () {
    final porRuta = {for (final p in pantallas) p.ruta: p.titulo};
    expect(porRuta['/dashboard'], 'Panel');
    expect(porRuta['/routes'], 'Rutas');
    expect(porRuta['/orders'], 'Pedidos');
    expect(porRuta['/customers'], 'Clientes');
    expect(porRuta['/vehicles'], 'Vehículos');
    expect(porRuta['/warehouses'], 'Almacenes');
  });

  /// CADA PANTALLA DECLARA LAS COLECCIONES QUE USA — 01/10/2026.
  ///
  /// La franja de arriba se mide contra ellas y SOLO contra ellas. Antes se
  /// medía contra las nueve, y dentro de las nueve va `almacenes`, que se
  /// refresca sola **una vez por hora a propósito**: en el teléfono la franja
  /// decía «Datos de las 8:46» toda la mañana mientras el Tablero decía «Visto
  /// por última vez a las 9:07» y estaba al día. Veintiún minutos, y puede
  /// llegar a cincuenta y nueve. Con el umbral del ámbar en una hora justa, eso
  /// rozaba el borde cada hora **por diseño** — el §3-quinquies tal cual.
  ///
  /// **Olvidarlo no compila**, porque `PantallaRegistrada.colecciones` es
  /// obligatorio y no tiene valor por defecto. Lo que se barre aquí es lo que el
  /// compilador no puede ver: que lo declarado exista y no se repita.
  group('las colecciones de cada pantalla', () {
    /// Las que se pueden declarar. Las nueve de la bajada por diferencias, más
    /// las dos del tablero, que no viajan en ella: se piden aparte con
    /// `GET /api/board`.
    ///
    /// Una pantalla nueva con una colección propia **tiene que añadirla aquí**, y
    /// eso es a propósito: es un paso consciente de una línea, y lo que evita es
    /// que un nombre mal escrito pase sin más. Un `'warehouse'` en singular no
    /// rompe nada visible — `laMasVieja` no encuentra fila, contesta `null`, y la
    /// franja dice «Sin descargar todavía» en ámbar encima de una copia que está
    /// entera.
    const existentes = <String>[
      ...Colecciones.todas,
      ...EsquemaTablero.colecciones,
    ];

    test('ninguna declara una colección que no existe', () {
      for (final p in pantallas) {
        for (final coleccion in p.colecciones) {
          expect(
            existentes,
            contains(coleccion),
            reason:
                '«${p.ruta}» se mide contra «$coleccion», que no es ninguna '
                'colección de la casa. Eso no falla solo: la franja dirá «Sin '
                'descargar todavía» en ámbar sobre una copia entera. Si es nueva '
                'de verdad, añádela a esta lista',
          );
        }
      }
    });

    test('ninguna repite una colección', () {
      for (final p in pantallas) {
        expect(
          p.colecciones.toSet().length,
          p.colecciones.length,
          reason: '«${p.ruta}» tiene una colección dos veces: ${p.colecciones}',
        );
      }
    });

    /// EL CASO DEL 01/10/2026, CLAVADO. Pedidos no pinta ni un almacén.
    ///
    /// Va escrito como prueba y no como comentario porque es justo lo que vuelve
    /// a pasar sin que salte nada: alguien añade `almacenes` «por si acaso» y la
    /// franja de Pedidos vuelve a quedarse media hora por detrás, sin un error,
    /// sin una pantalla en blanco y sin que nadie lo note.
    test('Pedidos NO se mide contra los almacenes', () {
      final pedidos = pantallas.firstWhere((p) => p.ruta == '/orders');
      expect(
        pedidos.colecciones,
        isNot(contains(Colecciones.almacenes)),
        reason:
            'los almacenes se piden una vez por hora a propósito (el 82 % de lo '
            'que se gasta en reposo). En Pedidos, que no pinta ninguno, eso sólo '
            'puede hacer que la franja diga una hora más vieja que la pantalla',
      );
      expect(pedidos.colecciones, contains(Colecciones.pedidos));
    });

    /// Y SU PAREJA: Rutas SÍ, porque de los almacenes sale el punto de partida
    /// de cada ruta. Sin esta mitad, «no midas contra los almacenes» se cumpliría
    /// quitándolos de todas partes, y entonces la franja diría estar **más
    /// fresca** de lo que está — el único lado del que no se puede equivocar.
    test('Rutas SÍ se mide contra los almacenes', () {
      final rutas = pantallas.firstWhere((p) => p.ruta == '/routes');
      expect(
        rutas.colecciones,
        contains(Colecciones.almacenes),
        reason:
            'de los almacenes sale el punto desde el que arranca cada ruta: con '
            'las rutas de hoy y el almacén de anteayer, la distancia es de '
            'anteayer y la franja no puede callarlo',
      );
    });

    /// EL PANEL SE QUEDA CON LAS NUEVE, y es una decisión, no un olvido.
    ///
    /// Su pregunta es «¿le falta algo a este aparato?»: ahí manda la bajada más
    /// vieja de todas, porque es la que decide si hay que traer el día antes de
    /// salir a la calle.
    test('el Panel se mide contra las NUEVE, a propósito', () {
      final panel = pantallas.firstWhere((p) => p.ruta == '/dashboard');
      expect(
        panel.colecciones,
        Colecciones.todas,
        reason:
            'si esto se recorta, que sea con un motivo escrito y no por '
            'parecerse a las demás',
      );
    });

    /// LA FRANJA Y LA CABECERA DEL TABLERO NO PUEDEN DECIR DOS HORAS.
    ///
    /// Las dos salen de `EsquemaTablero.colecciones`, que es una sola lista. Esta
    /// prueba es la que impide que alguien escriba la segunda copia (§3-bis).
    test('el Tablero se mide contra sus DOS colecciones, las mismas que su '
        'cabecera', () {
      final tablero = pantallas.firstWhere((p) => p.ruta == '/tablero');
      expect(tablero.colecciones, EsquemaTablero.colecciones);
      expect(tablero.colecciones, hasLength(2));
    });

    /// LAS QUE NO PINTAN NADA DE LA COPIA LO DICEN CON NOMBRE.
    ///
    /// Es una decisión escrita, no un hueco (§4: «borrar no es decidir»). Y la
    /// franja lo trata como lo que es: no pinta la hora, y **no** se cae a «Sin
    /// descargar todavía», que sería acusar de vacía una copia entera.
    test('las que leen en vivo del servidor declaran «ninguna», no una lista '
        'inventada', () {
      for (final ruta in <String>[
        '/sincronizacion',
        '/mapa-sin-conexion',
      ]) {
        final p = pantallas.firstWhere((p) => p.ruta == ruta);
        expect(
          p.colecciones,
          isEmpty,
          reason:
              '«$ruta» no pinta nada que venga de la copia: una hora de bajada '
              'ahí no significa nada',
        );
      }
    });
  });

  test('todo lo que sale en el menu tiene icono', () {
    for (final p in pantallas.where((p) => p.enElMenu)) {
      expect(p.icono, isNotNull, reason: p.ruta);
    }
  });
}
