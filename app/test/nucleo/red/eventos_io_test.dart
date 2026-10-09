import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/eventos_io.dart';
import 'package:reparto/nucleo/red/eventos.dart'
    show
        PulsoDelCanal,
        avisoDeQueVolvimos,
        avisoDeSesionInvalidada,
        esSesionInvalidada;

/// EL CANAL EN VIVO DEL APARATO, comprobado contra un servidor de verdad.
///
/// El servidor falso de `test/apoyo/servidor_falso.dart` no sirve aqui: contesta
/// con `ResponseBody.fromString`, o sea el cuerpo entero de golpe, y lo que hay
/// que comprobar es justamente lo contrario —que una trama partida en dos trozos
/// por la red se entiende igual—. Asi que se levanta un `HttpServer` de verdad
/// en `127.0.0.1` con puerto 0. Es local: no sale un paquete de esta maquina.
/// EL LATIDO, TAL Y COMO LO MANDA EL SERVIDOR DE VERDAD — 29/09/2026.
///
/// Aqui estaba escrito a mano como `': latido\n\n'`, o sea un **comentario** SSE,
/// que es lo que era hasta hoy. Dejo de serlo porque `EventSource` descarta los
/// comentarios y en la web el latido era invisible: ahora sale como evento con
/// nombre (`api/internal/api/eventos.go`, `bloqueDelLatido`).
///
/// Que esto quede desfasado no falla: la prueba sigue verde probando que
/// **cualquier byte** marca el pulso, que es cierto y es menos de lo que dice su
/// nombre. Por eso se escribe una vez aqui y no cinco veces ahi abajo — y por eso
/// el literal del otro lado lo fija `TestElNombreDelLatidoNoSeRenombraSolo`.
const latidoDeVerdad = 'event: latido\ndata: {}\n\n';

void main() {
  test('hayCanalDeEventos: en el aparato SI hay canal', () {
    expect(hayCanalDeEventos, isTrue);
  });

  // `sesion-invalidada` EN LA APK Y EL ESCRITORIO — 08/10/2026.
  //
  // La api lo empuja por el mismo `/api/eventos` y cierra esa conexion (a los
  // aparatos solo si el alcance es `todo`). El cliente nativo NO echa a nadie ni
  // cierra su canal por eso: lo SACA por el stream, y el embudo intenta renovar YA
  // (`Portero.renovarPorAviso`, probado en `el_aparato_se_entera_test.dart`). Lo
  // que decide es el refresco, no el aviso. Tras el corte reconecta como tras
  // cualquier corte del proxy, con su `Authorization: Bearer`.
  test('el cliente NATIVO saca `sesion-invalidada` por el stream, no cierra el '
      'canal y reconecta tras el corte', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      final r = abrirSSE(req);
      await escribir(r, 'event: listo\ndata: {"vivo":true}\n\n');
      if (n == 0) {
        await escribir(
          r,
          'event: sesion-invalidada\ndata: {"tipo":"permisos-cambiados"}\n\n',
        );
        await r.close(); // como la api: empuja y corta
      } else {
        await escribir(r, 'event: cambio\ndata: {"tipo":"pedidos"}\n\n');
      }
    });
    addTearDown(servidor.cerrar);

    final recibidos = await recoger(
      escucharEventos(
        servidor.urlBase,
        () async => 'tok',
        esperaInicial: const Duration(milliseconds: 20),
        esperaMaxima: const Duration(milliseconds: 40),
      ),
      durante: const Duration(milliseconds: 800),
    );

    expect(
      recibidos,
      containsAllInOrder([
        avisoDeSesionInvalidada('{"tipo":"permisos-cambiados"}'),
        'pedidos',
      ]),
      reason: 'el aviso sale, y tras el corte el canal vuelve y trae lo suyo',
    );
    expect(servidor.peticiones, greaterThanOrEqualTo(2));
    expect(servidor.autorizaciones, everyElement('Bearer tok'));
  });

  test('PAREJA: un evento de otro nombre se ignora y no sale nada', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      final r = abrirSSE(req);
      await escribir(r, 'event: listo\ndata: {"vivo":true}\n\n');
      await escribir(r, 'event: sesion-cerrada\ndata: {"tipo":"x"}\n\n');
      await escribir(r, 'event: cambio\ndata: {"tipo":"pedidos"}\n\n');
    });
    addTearDown(servidor.cerrar);

    final recibidos = await recoger(
      escucharEventos(servidor.urlBase, () async => 'tok'),
    );

    expect(recibidos.where(esSesionInvalidada), isEmpty);
    expect(soloLosCambios(recibidos), ['pedidos']);
  });

  group('la espera del reintento', () {
    test('empieza corta, crece y tiene tope', () {
      expect(esperaDeReintento(0), const Duration(seconds: 1));
      expect(esperaDeReintento(1), const Duration(seconds: 2));
      expect(esperaDeReintento(3), const Duration(seconds: 8));
      expect(
        esperaDeReintento(10),
        const Duration(minutes: 1),
        reason: 'la espera no puede pasar del tope',
      );
      expect(
        esperaDeReintento(500),
        const Duration(minutes: 1),
        reason: 'un canal caido toda la mañana no puede desbordar la cuenta',
      );
    });

    test('el tope no pasa de un minuto', () {
      expect(
        esperaMaximaDeEventos,
        lessThanOrEqualTo(const Duration(minutes: 1)),
      );
      expect(
        esperaInicialDeEventos,
        greaterThanOrEqualTo(const Duration(milliseconds: 500)),
        reason: 'empezar en cero es un bucle de reconexiones',
      );
    });
  });

  test('una trama partida por la mitad de una línea se entiende igual', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      final r = abrirSSE(req);
      // El corte cae DENTRO de `event: cambio` y otra vez DENTRO del `data`.
      await escribir(r, 'event: listo\ndata: {"vivo":true}\n\nevent: cam');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await escribir(r, 'bio\ndata: {"tipo":"tab');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await escribir(r, 'lero"}\n\n');
    });
    addTearDown(servidor.cerrar);

    final recibidos = await recoger(
      escucharEventos(servidor.urlBase, () async => 'tok'),
    );
    expect(
      soloLosCambios(recibidos),
      ['tablero'],
      reason:
          'los trozos de red no son lineas: hay que acumular hasta el salto de '
          'linea en vez de dar cada trozo por una linea entera',
    );
  });

  // ESTA PRUEBA DECÍA LO CONTRARIO HASTA EL 29/09/2026, y hay que contar por qué
  // cambió: no se relajó, se corrigió.
  //
  // Decía «sólo los cambios; el listo y los latidos son del transporte». Los
  // latidos sí lo son. El `listo` NO: dice **«estuve desconectado»**, y lo que
  // pasara en el servidor mientras tanto no lo vio nadie.
  //
  // Lo que costó tirarlo, medido ese día con el teléfono y la web delante: se
  // creó una zona desde el teléfono, entró en el servidor a las 17:34:55, y la
  // web siguió diciendo «las zonas las pones tú» **tres minutos después**. Su
  // canal se había abierto a las 17:35:22 —27 segundos tarde, porque el proxy
  // había cortado el anterior— y el Tablero no se vuelve a pedir nunca por su
  // cuenta. Un aviso perdido lo dejaba mal para siempre.
  //
  // Los latidos siguen sin salir, y eso también se comprueba aquí: son de verdad
  // del transporte y salen cada veinte segundos.
  test('el listo SÍ sale —es «volví»—, y los latidos no', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      final r = abrirSSE(req);
      await escribir(r, 'event: listo\ndata: {"vivo":true}\n\n');
      await escribir(r, latidoDeVerdad);
      await escribir(r, latidoDeVerdad);
      await escribir(r, 'event: cambio\ndata: {"tipo":"pedidos"}\n\n');
      await escribir(r, latidoDeVerdad);
    });
    addTearDown(servidor.cerrar);

    final recibidos = await recoger(
      escucharEventos(servidor.urlBase, () async => 'tok'),
    );
    expect(
      recibidos,
      [avisoDeQueVolvimos, 'pedidos'],
      reason:
          'el `listo` no sale, y con él se pierde la única señal de que estuvimos '
          'desconectados: quien pide a la red en cada visita se queda con lo que '
          'pintó al abrirse, para siempre. Y va PRIMERO, antes que los cambios: '
          'es el instante en que se recupera el canal',
    );
    expect(
      recibidos.where((t) => t.contains('latido')),
      isEmpty,
      reason: 'los latidos sí son del transporte y no le dicen nada a nadie',
    );
  });

  // ## EL LATIDO NO SALE POR EL STREAM, PERO SÍ MARCA EL PULSO — 29/09/2026
  //
  // Las dos mitades, y hacen falta las dos:
  //
  //  * **No sale**, porque cada aviso que sale de aquí cuesta un ciclo de
  //    sincronización entero, un `GET /api/board` por tablero abierto y la flota
  //    por cada pantalla de vehículos. Un latido cada veinte segundos ahí sería el
  //    polling que todo esto vino a quitar, multiplicado.
  //  * **Marca el pulso**, porque es lo único que demuestra que el canal está
  //    cuando en el servidor no cambia nada. Sin esto, un canal sano por el que no
  //    había cambiado nada en seis minutos se leía como muerto y el reloj del
  //    vigía pedía la vuelta entera (`VigiaDeSincronizacion.elCanalSeDaPorVivo`).
  //
  // Aquí el servidor NO manda ni un `listo` ni un `cambio` a propósito: así lo
  // único que puede haber marcado el pulso es el latido.
  test('un canal que sólo late marca el pulso y no manda ni un aviso', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      final r = abrirSSE(req);
      while (await escribir(r, latidoDeVerdad)) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    addTearDown(servidor.cerrar);

    var ahora = DateTime(2026, 9, 29, 20, 0);
    final pulso = PulsoDelCanal(reloj: () => ahora);
    final recibidos = <String>[];
    final sub = escucharEventos(
      servidor.urlBase,
      () async => 'tok',
      pulso: pulso,
    ).listen(recibidos.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      pulso.ultimo,
      DateTime(2026, 9, 29, 20, 0),
      reason:
          'llegaron latidos y el pulso sigue sin marcarse. Entonces el vigía no '
          'sabe que el canal está y a los seis minutos pide la vuelta entera '
          'contra un canal sano',
    );

    // Y SIGUE marcando: un pulso que se apunta una vez y se olvida da el canal
    // por muerto a los seis minutos igual que si no hubiera ninguno.
    ahora = DateTime(2026, 9, 29, 20, 5);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      pulso.ultimo,
      DateTime(2026, 9, 29, 20, 5),
      reason:
          'el pulso se quedó con el primer latido: con eso el canal se da por '
          'muerto a los seis minutos aunque esté latiendo cada veinte segundos',
    );

    expect(
      recibidos,
      isEmpty,
      reason:
          'un latido NO es un cambio. Si sale por el stream, cada veinte '
          'segundos hay un ciclo de sincronización, un `GET /api/board` por '
          'tablero abierto y la flota por cada pantalla de vehículos abierta',
    );
  });

  // ## EL 401 NO ES PERMANENTE. EL 403 Y EL 404 SÍ.
  //
  // Esto cerraba el canal para toda la sesión en cuanto llegaba cualquier 4xx, y
  // estaba pasando de verdad: dos `401 GET /api/eventos` en el registro de dos
  // horas de producción. El token de acceso dura QUINCE MINUTOS y el aparato
  // sabe renovarlo, así que ahí el 401 dice «ese token ya caducó», no «tú no
  // entras».
  //
  // Y no es un lujo: el consuelo de «queda el temporizador» es falso para
  // Vehículos y Almacenes —piden a la red, no viven de la base local—, así que
  // con el canal caído se quedan clavadas hasta salir y volver a entrar.
  group('el 401 se renueva; el 403 y el 404 no', () {
    test('un 401 renueva la sesión, vuelve a abrir y SIGUE recibiendo', () async {
      final servidor = await ServidorDeEventos.abrir((s, req, n) async {
        if (n == 0) {
          req.response
            ..statusCode = HttpStatus.unauthorized
            ..headers.contentType = ContentType.text
            ..write('Unauthorized');
          await req.response.close();
          return;
        }
        final r = abrirSSE(req);
        await escribir(r, 'event: listo\ndata: {"vivo":true}\n\n');
        // Justo el tipo de la pantalla que el temporizador NO repinta.
        await escribir(r, 'event: cambio\ndata: {"tipo":"vehiculos"}\n\n');
      });
      addTearDown(servidor.cerrar);

      var renovaciones = 0;
      var token = 'caducado';

      final recibidos = await recoger(
        escucharEventos(
          servidor.urlBase,
          () async => token,
          renovarSesion: () async {
            renovaciones++;
            token = 'fresco$renovaciones';
          },
          esperaInicial: const Duration(milliseconds: 20),
          esperaMaxima: const Duration(milliseconds: 40),
        ),
        durante: const Duration(milliseconds: 600),
      );

      expect(
        soloLosCambios(recibidos),
        ['vehiculos'],
        reason:
            'un 401 por token caducado no puede dejar sin canal a Vehículos ni '
            'a Almacenes, que son las dos que el ciclo no repinta',
      );
      expect(renovaciones, 1, reason: 'una renovación, no una por vuelta');
      expect(servidor.autorizaciones.take(2), [
        'Bearer caducado',
        'Bearer fresco1',
      ], reason: 'la segunda apertura tiene que ir con el token NUEVO');
    });

    test('un 403 CIERRA el stream y no reintenta', () async {
      await compruebaQueElRechazoEsPermanente(HttpStatus.forbidden);
    });

    test('un 404 CIERRA el stream y no reintenta', () async {
      await compruebaQueElRechazoEsPermanente(HttpStatus.notFound);
    });

    // FRENO 2, Y ESTA PRUEBA DECÍA «cierra» HASTA EL 29/09/2026.
    //
    // Hay que contar por qué cambió, porque no se relajó: se corrigió. El freno
    // está bien —presentar el mismo token que acaban de rechazar es regalar un
    // 401— pero **cerrar el canal para toda la sesión estaba mal**.
    //
    // Medido ese día en el teléfono de Jose, justo después de reinstalar la APK:
    //
    //     18:59:40  GET /api/eventos  401  0 ms
    //
    // Y ni un segundo intento en media hora. Ese aparato se quedó sin tiempo
    // real hasta que alguien cerrara y volviera a abrir la aplicación, y nadie
    // se enteró: ni error en pantalla, ni aviso, ni nada. Jose: «arregla eso
    // para que no se quede ciego».
    //
    // Un 401 **no es permanente**: el token de acceso dura quince minutos y el
    // ciclo renueva la sesión por su cuenta. Así que ahora se espera lo máximo y
    // se vuelve a mirar, y en cuanto el token cambie entra solo.
    //
    // Lo que NO cambia, y es lo que esta prueba sigue vigilando: mientras la
    // sesión sea la misma, **no se gasta ni una petición ni una renovación**.
    test(
      'un 401 que se repite SIN sesión nueva no gasta nada, pero NO se muere',
      () async {
        final servidor = await ServidorDeEventos.abrir((s, req, n) async {
          req.response.statusCode = HttpStatus.unauthorized;
          await req.response.close();
        });
        addTearDown(servidor.cerrar);

        var renovaciones = 0;
        var cerrado = false;
        final sub = escucharEventos(
          // El mismo token siempre: renovar no cambió nada.
          servidor.urlBase,
          () async => 'el-de-siempre',
          renovarSesion: () async => renovaciones++,
          esperaInicial: const Duration(milliseconds: 20),
          esperaMaxima: const Duration(milliseconds: 40),
        ).listen((_) {}, onDone: () => cerrado = true);
        addTearDown(sub.cancel);

        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(
          cerrado,
          isFalse,
          reason:
              'el canal se cerró para toda la sesión. Un 401 en un mal momento '
              'deja al aparato sin tiempo real hasta que alguien reabra la '
              'aplicación, y nadie se entera',
        );
        expect(renovaciones, 1, reason: 'una renovación como mucho');
        expect(
          servidor.peticiones,
          1,
          reason:
              'si la sesión no cambió, la segunda petición sería idéntica a la '
              'que acaban de rechazar: no se gasta. Esperar y volver a MIRAR no '
              'es volver a pedir',
        );
        // Sigue esperando, que es justo lo que le deja recuperarse solo en
        // cuanto el ciclo renueve la sesión.
        expect(
          temporizadoresDeEventos,
          greaterThan(0),
          reason:
              'sin temporizador no hay recuperación: el canal no vuelve aunque '
              'la sesión se arregle sola cinco minutos después',
        );
      },
    );

    // FRENO 1. El otro bucle posible, más caro: la renovación SÍ da un token
    // nuevo cada vez y el servidor lo rechaza igual. Sin freno, esto es una ida
    // y vuelta a Accesos por vuelta, para siempre.
    //
    // Esta prueba también decía «cierra» hasta el 29/09/2026, y por lo mismo que
    // la de arriba: el freno está bien, morirse no. Lo que se vigila ahora es
    // que **una sola renovación** sigue siendo el tope —eso es lo caro— sin que
    // el canal se quede muerto.
    test('un 401 que se repite CON sesión nueva gasta UNA renovación y espera', () async {
      final servidor = await ServidorDeEventos.abrir((s, req, n) async {
        req.response.statusCode = HttpStatus.unauthorized;
        await req.response.close();
      });
      addTearDown(servidor.cerrar);

      var renovaciones = 0;
      var token = 'tok0';
      var cerrado = false;
      final sub = escucharEventos(
        servidor.urlBase,
        () async => token,
        renovarSesion: () async {
          renovaciones++;
          token = 'tok$renovaciones';
        },
        esperaInicial: const Duration(milliseconds: 20),
        esperaMaxima: const Duration(milliseconds: 40),
      ).listen((_) {}, onDone: () => cerrado = true);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(
        cerrado,
        isFalse,
        reason:
            'el canal se cerró para toda la sesión: el aparato se queda ciego '
            'hasta que alguien reabra la aplicación',
      );
      expect(
        renovaciones,
        1,
        reason: 'UNA renovación por canal, como el reintento del interceptor',
      );
      expect(
        servidor.peticiones,
        2,
        reason:
            'la de siempre y la de después de renovar. Una tercera ya sería el '
            'bucle: sin freno esto es una ida y vuelta a Accesos por vuelta, y '
            'una rotación del refresh, para siempre',
      );
      expect(
        temporizadoresDeEventos,
        greaterThan(0),
        reason: 'sigue esperando, que es lo que le deja recuperarse solo',
      );
    });

    // Lo que manda es el «no» de la renovación, no lo que quede guardado. Por
    // eso aquí el token SÍ cambia y aun así tiene que cerrarse: si sólo valiera
    // el freno del token repetido, una renovación rechazada abriría otra
    // conexión con una sesión que el servidor ya dijo que no acepta. Pasa de
    // verdad cuando otra cosa toca el almacén mientras nuestra renovación se
    // está yendo al suelo.
    test('si la renovación falla, el canal se cierra', () async {
      final servidor = await ServidorDeEventos.abrir((s, req, n) async {
        req.response.statusCode = HttpStatus.unauthorized;
        await req.response.close();
      });
      addTearDown(servidor.cerrar);

      var cerrado = false;
      var token = 'tok0';
      final sub = escucharEventos(
        servidor.urlBase,
        () async => token,
        renovarSesion: () async {
          token = 'tok1';
          throw Exception('la sesión murió');
        },
        esperaInicial: const Duration(milliseconds: 20),
        esperaMaxima: const Duration(milliseconds: 40),
      ).listen((_) {}, onDone: () => cerrado = true);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(
        cerrado,
        isTrue,
        reason: 'una renovación que falla deja el 401 como lo que era: un no',
      );
      expect(
        servidor.peticiones,
        1,
        reason:
            'renovar dijo que no: volver a abrir es pedir con una sesión que el '
            'servidor ya rechazó',
      );
      expect(temporizadoresDeEventos, 0);
    });

    test(
      'sin con qué renovar, un 401 cierra como cualquier otro rechazo',
      () async {
        await compruebaQueElRechazoEsPermanente(
          HttpStatus.unauthorized,
          conRenovacion: false,
        );
      },
    );

    // Cancelar MIENTRAS se está renovando. Es el hueco que abre este arreglo: el
    // 401 llega, se pide la renovación, y en ese rato la persona cierra sesión.
    // Si el canal no se diera por muerto ahí, volvería a abrir una conexión —y
    // con la sesión de quien ya se fue—.
    test('cancelar DURANTE la renovación no deja nada vivo', () async {
      final servidor = await ServidorDeEventos.abrir((s, req, n) async {
        req.response.statusCode = HttpStatus.unauthorized;
        await req.response.close();
      });
      addTearDown(servidor.cerrar);

      var token = 'tok0';
      final sub = escucharEventos(
        servidor.urlBase,
        () async => token,
        renovarSesion: () async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          token = 'tok1';
        },
        esperaInicial: const Duration(milliseconds: 20),
        esperaMaxima: const Duration(milliseconds: 40),
      ).listen((_) {});

      while (servidor.peticiones == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await sub.cancel();

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        servidor.peticiones,
        1,
        reason: 'una renovación en vuelo no puede reabrir un canal ya cerrado',
      );
      expect(temporizadoresDeEventos, 0);
      await servidor.sacudir();
      expect(servidor.conexionesVivas, 0);
    });
  });

  test('un 500 SI se reintenta: eso es el servidor reiniciándose', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      if (n == 0) {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
        return;
      }
      final r = abrirSSE(req);
      await escribir(r, 'event: listo\ndata: {"vivo":true}\n\n');
      await escribir(r, 'event: cambio\ndata: {"tipo":"rutas"}\n\n');
    });
    addTearDown(servidor.cerrar);

    final recibidos = await recoger(
      escucharEventos(
        servidor.urlBase,
        () async => 'tok',
        esperaInicial: const Duration(milliseconds: 20),
        esperaMaxima: const Duration(milliseconds: 40),
      ),
      durante: const Duration(milliseconds: 800),
    );
    expect(soloLosCambios(recibidos), ['rutas']);
    expect(servidor.peticiones, greaterThanOrEqualTo(2));
  });

  test('el servidor cierra el canal: se reconecta', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      final r = abrirSSE(req);
      await escribir(r, 'event: listo\ndata: {"vivo":true}\n\n');
      await escribir(r, 'event: cambio\ndata: {"tipo":"pedidos"}\n\n');
      if (n == 0) {
        await r.close();
        return;
      }
    });
    addTearDown(servidor.cerrar);

    final recibidos = await recoger(
      escucharEventos(
        servidor.urlBase,
        () async => 'tok',
        esperaInicial: const Duration(milliseconds: 20),
        esperaMaxima: const Duration(milliseconds: 40),
      ),
      durante: const Duration(milliseconds: 800),
    );
    expect(
      recibidos.length,
      greaterThanOrEqualTo(2),
      reason: 'si no reconecta, el aparato vuelve a los cinco minutos de reloj',
    );
    expect(servidor.peticiones, greaterThanOrEqualTo(2));
  });

  test('la red se corta a lo bruto: se reconecta', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      if (n == 0) {
        // El socket a pelo, para poder cortarlo A MEDIA TRAMA y sin despedirse
        // —lo que pasa cuando el telefono cambia de antena—. Con `HttpResponse`
        // no se puede: cierra bien y eso es otro camino (el de arriba).
        final socket = await req.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 200 OK\r\n'
          'Content-Type: text/event-stream\r\n'
          'Transfer-Encoding: chunked\r\n\r\n',
        );
        final trama =
            'event: listo\ndata: {"vivo":true}\n\n'
            'event: cambio\ndata: {"tipo":"pedidos"}\n\n';
        socket.write('${trama.length.toRadixString(16)}\r\n$trama\r\n');
        // Un trozo que promete mas bytes de los que va a mandar: el cliente se
        // queda esperando y el socket se muere.
        socket.write('20\r\nevent: cam');
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        socket.destroy();
        return;
      }
      final r = abrirSSE(req);
      await escribir(r, 'event: listo\ndata: {"vivo":true}\n\n');
      await escribir(r, 'event: cambio\ndata: {"tipo":"pedidos"}\n\n');
    });
    addTearDown(servidor.cerrar);

    final recibidos = await recoger(
      escucharEventos(
        servidor.urlBase,
        () async => 'tok',
        esperaInicial: const Duration(milliseconds: 20),
        esperaMaxima: const Duration(milliseconds: 40),
      ),
      durante: const Duration(milliseconds: 800),
    );
    expect(recibidos.length, greaterThanOrEqualTo(2));
    expect(servidor.peticiones, greaterThanOrEqualTo(2));
  });

  test('una conexión muda se da por muerta y se reconecta', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      final r = abrirSSE(req);
      await escribir(r, 'event: listo\ndata: {"vivo":true}\n\n');
      // La primera conexion se queda MUDA: el socket abierto y ni un latido.
      // Sin vigilante, el canal se queda asi para siempre y nadie se entera.
      if (n == 0) return;
      await escribir(r, 'event: cambio\ndata: {"tipo":"tablero"}\n\n');
      // La segunda si late, asi que no se la vuelve a dar por muerta.
      while (await escribir(r, latidoDeVerdad)) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    addTearDown(servidor.cerrar);

    final recibidos = await recoger(
      escucharEventos(
        servidor.urlBase,
        () async => 'tok',
        esperaInicial: const Duration(milliseconds: 20),
        esperaMaxima: const Duration(milliseconds: 40),
        silencioMaximo: const Duration(milliseconds: 150),
      ),
      durante: const Duration(milliseconds: 800),
    );
    expect(
      soloLosCambios(recibidos),
      ['tablero'],
      reason: 'sin vigilante del latido, una conexión muerta no se nota nunca',
    );
    expect(
      servidor.peticiones,
      2,
      reason: 'y con latidos NO se la vuelve a dar por muerta',
    );
  });

  test('el token va en la cabecera, y se pide EN CADA apertura', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      final r = abrirSSE(req);
      await escribir(r, 'event: listo\ndata: {"vivo":true}\n\n');
      if (n == 0) await r.close();
    });
    addTearDown(servidor.cerrar);

    var veces = 0;
    final sub = escucharEventos(
      servidor.urlBase,
      () async {
        veces++;
        return 'tok$veces';
      },
      esperaInicial: const Duration(milliseconds: 20),
      esperaMaxima: const Duration(milliseconds: 40),
    ).listen((_) {});
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(servidor.autorizaciones.take(2), [
      'Bearer tok1',
      'Bearer tok2',
    ], reason: 'un token cogido una sola vez caduca a los quince minutos');
  });

  test('sin sesión no se abre ninguna conexión y el stream cierra', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      await abrirSSE(req).close();
    });
    addTearDown(servidor.cerrar);

    var cerrado = false;
    final sub = escucharEventos(
      servidor.urlBase,
      () async => null,
      esperaInicial: const Duration(milliseconds: 20),
    ).listen((_) {}, onDone: () => cerrado = true);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(cerrado, isTrue);
    expect(servidor.peticiones, 0);
  });

  test('al cancelar no queda nada vivo', () async {
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      final r = abrirSSE(req);
      await escribir(r, 'event: listo\ndata: {"vivo":true}\n\n');
      await escribir(r, 'event: cambio\ndata: {"tipo":"pedidos"}\n\n');
      // Y se queda abierta, como en el servidor de verdad.
    });
    addTearDown(servidor.cerrar);

    final recibidos = <String>[];
    final sub = escucharEventos(
      servidor.urlBase,
      () async => 'tok',
      esperaInicial: const Duration(milliseconds: 20),
      esperaMaxima: const Duration(milliseconds: 40),
      silencioMaximo: const Duration(milliseconds: 120),
    ).listen(recibidos.add);

    while (recibidos.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await sub.cancel();
    final peticionesAlCancelar = servidor.peticiones;

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(
      servidor.peticiones,
      peticionesAlCancelar,
      reason: 'un temporizador vivo despues de salir reconecta sin sesión',
    );

    expect(
      temporizadoresDeEventos,
      0,
      reason: 'ni un temporizador vivo despues de cerrar sesión',
    );

    // Y la conexion, soltada de verdad. Hace falta sacudirla: mientras el
    // servidor no escribe, no se entera de que el otro lado se fue.
    await servidor.sacudir();
    expect(
      servidor.conexionesVivas,
      0,
      reason:
          'la conexión tiene que soltarse de verdad: cancelar la suscripción '
          'del flujo de dio NO cierra el socket, hay que cerrar el cliente',
    );
  });

  test('cancelar DURANTE la espera del reintento no deja el temporizador vivo', () async {
    // El servidor se cae siempre, asi que cuando se cancela hay una reconexion
    // ya programada. Es el caso que se le escapa a la prueba de arriba —alli la
    // conexion estaba viva y no habia ningun temporizador puesto—.
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      req.response.statusCode = HttpStatus.internalServerError;
      await req.response.close();
    });
    addTearDown(servidor.cerrar);

    final sub = escucharEventos(
      servidor.urlBase,
      () async => 'tok',
      esperaInicial: const Duration(milliseconds: 150),
      esperaMaxima: const Duration(milliseconds: 150),
    ).listen((_) {});

    while (servidor.peticiones == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await sub.cancel();
    final alCancelar = servidor.peticiones;

    expect(
      temporizadoresDeEventos,
      0,
      reason:
          'el temporizador del reintento tiene que morir AL CANCELAR, no '
          'quedarse puesto un minuto para luego no hacer nada',
    );

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(
      servidor.peticiones,
      alCancelar,
      reason: 'el reintento programado tiene que morir al cerrar sesión',
    );
  });

  test('cancelar MIENTRAS se está abriendo no deja una reconexión detrás', () async {
    // El servidor tarda en contestar y se cancela en ese hueco. Si el canal no
    // se da por muerto al cancelar, la peticion falla —cancelada— y eso se
    // confunde con un corte de red: reconecta, ya sin sesión.
    final servidor = await ServidorDeEventos.abrir((s, req, n) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final r = abrirSSE(req);
      await escribir(r, 'event: listo\ndata: {"vivo":true}\n\n');
    });
    addTearDown(servidor.cerrar);

    final sub = escucharEventos(
      servidor.urlBase,
      () async => 'tok',
      esperaInicial: const Duration(milliseconds: 20),
      esperaMaxima: const Duration(milliseconds: 40),
    ).listen((_) {});

    while (servidor.peticiones == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await sub.cancel();

    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(
      servidor.peticiones,
      1,
      reason: 'una apertura cancelada no es un corte de red: no se reintenta',
    );
    expect(temporizadoresDeEventos, 0);
  });

  test('en una prueba no se abre el canal contra nada que no sea local', () async {
    // Sin este seguro, `flutter test` abriria una conexion de verdad contra
    // `reparto.procovar.cloud` en cuanto un widget test monte la aplicacion
    // entera — que es por lo que le bloquearon la IP a la oficina. La direccion
    // de aqui no existe a proposito: si el seguro se rompe, no sale ni un
    // paquete a ningun sitio de verdad.
    var cerrado = false;
    final sub = escucharEventos(
      'https://esto.no.existe.invalido/api',
      () async => 'tok',
    ).listen((_) {}, onDone: () => cerrado = true);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      cerrado,
      isTrue,
      reason: 'en pruebas el canal sólo se abre contra 127.0.0.1',
    );
  });
}

/// Un rechazo que renovar NO arregla: el canal se cierra y no se vuelve a pedir.
///
/// Sirve para el 403 y el 404 —que son permanentes de verdad— y para el 401
/// cuando nadie pasó con qué renovar, que para este fichero es lo mismo.
Future<void> compruebaQueElRechazoEsPermanente(
  int codigo, {
  bool conRenovacion = true,
}) async {
  final servidor = await ServidorDeEventos.abrir((s, req, n) async {
    req.response
      ..statusCode = codigo
      ..headers.contentType = ContentType.text
      ..write('no');
    await req.response.close();
  });
  addTearDown(servidor.cerrar);

  var cerrado = false;
  var renovaciones = 0;
  var token = 'tok0';
  final sub = escucharEventos(
    servidor.urlBase,
    () async => token,
    // CON con qué renovar en la mano, que es lo que distingue este caso del
    // 401: no basta con que se cierre, tiene que cerrarse SIN haber ido a
    // Accesos a por una sesión que aquí no arregla nada.
    renovarSesion: conRenovacion
        ? () async {
            renovaciones++;
            token = 'tok$renovaciones';
          }
        : null,
    esperaInicial: const Duration(milliseconds: 20),
    esperaMaxima: const Duration(milliseconds: 40),
  ).listen((_) {}, onDone: () => cerrado = true);
  addTearDown(sub.cancel);

  await Future<void>.delayed(const Duration(milliseconds: 400));
  expect(
    cerrado,
    isTrue,
    reason: 'un $codigo es un rechazo permanente: el stream se cierra',
  );
  expect(
    servidor.peticiones,
    1,
    reason: 'reintentar contra un rechazo permanente es un bucle',
  );
  expect(
    renovaciones,
    0,
    reason:
        'un $codigo no se arregla con una sesión nueva: ni se pide. Renovar '
        'gasta una ida y vuelta a Accesos y rota el refresh para nada',
  );
  expect(temporizadoresDeEventos, 0);
}

/// Lo que llega por el canal durante [durante]. Se cancela al terminar, asi que
/// no queda ni conexion ni temporizador para la prueba siguiente.
Future<List<String>> recoger(
  Stream<String> canal, {
  Duration durante = const Duration(milliseconds: 500),
}) async {
  final recibidos = <String>[];
  final sub = canal.listen(recibidos.add);
  await Future<void>.delayed(durante);
  await sub.cancel();
  return recibidos;
}

/// Las cabeceras del flujo, tal cual las manda `api/internal/api/eventos.go`.
HttpResponse abrirSSE(HttpRequest peticion) {
  final r = peticion.response;
  r.statusCode = HttpStatus.ok;
  r.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
  r.headers.set(HttpHeaders.cacheControlHeader, 'no-store, no-transform');
  r.headers.set('X-Accel-Buffering', 'no');
  // Sin esto el propio servidor de la prueba junta los trozos y la prueba de la
  // trama partida no comprueba nada.
  r.bufferOutput = false;
  return r;
}

/// Escribe un trozo y lo suelta. Devuelve `false` cuando ya no se puede
/// escribir —el cliente se fue—, que a veces es justo lo que la prueba provoca.
Future<bool> escribir(HttpResponse r, String trozo) async {
  try {
    r.write(trozo);
    await r.flush();
    return true;
  } on Object {
    return false;
  }
}

/// Un servidor SSE de verdad, en `127.0.0.1` y con puerto 0 —el que haya libre—.
class ServidorDeEventos {
  ServidorDeEventos._(this._servidor);

  final HttpServer _servidor;
  final autorizaciones = <String?>[];
  final _respuestas = <HttpResponse>[];
  int _peticiones = 0;

  /// [atender] recibe el servidor, la peticion y el numero de conexion (la
  /// primera es la 0), que es lo que deja escribir «la primera se cae y la
  /// segunda va bien».
  static Future<ServidorDeEventos> abrir(
    FutureOr<void> Function(ServidorDeEventos, HttpRequest, int) atender,
  ) async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final servidor = ServidorDeEventos._(http);
    http.listen((peticion) {
      final n = servidor._peticiones;
      servidor._peticiones++;
      servidor.autorizaciones.add(
        peticion.headers.value(HttpHeaders.authorizationHeader),
      );
      servidor._respuestas.add(peticion.response);
      unawaited(Future<void>.sync(() => atender(servidor, peticion, n)));
    });
    return servidor;
  }

  /// Tal cual la usa la aplicacion: `…/api`, y el canal cuelga de `/eventos`.
  String get urlBase => 'http://127.0.0.1:${_servidor.port}/api';

  /// Cuantas conexiones se pidieron.
  int get peticiones => _peticiones;

  /// Cuantas conexiones TCP sigue teniendo el servidor. Es el oraculo de que
  /// el cliente solto la suya de verdad: `HttpResponse.done` no sirve, no
  /// termina por que el otro lado se vaya.
  int get conexionesVivas => _servidor.connectionsInfo().total;

  /// Escribe a lo bestia por todas las conexiones y espera a que el servidor se
  /// entere de las que ya no estan.
  ///
  /// Hace falta porque un socket que el otro lado cerro **no se nota hasta que
  /// se escribe**: `HttpResponse.done` no termina y `connectionsInfo` sigue
  /// contando la conexion. Si el cliente sigue ahi, se traga los bytes y la
  /// conexion se queda; si se fue, el servidor la suelta.
  Future<void> sacudir() async {
    for (final r in _respuestas) {
      for (var i = 0; i < 60; i++) {
        try {
          r.write('x' * 65536);
          await r.flush().timeout(const Duration(milliseconds: 200));
        } on Object {
          break;
        }
      }
    }
    for (var i = 0; i < 20 && conexionesVivas > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> cerrar() => _servidor.close(force: true);
}

/// LOS CAMBIOS, SIN EL «volví» DEL TRANSPORTE.
///
/// Desde el 29/09/2026 el canal emite [avisoDeQueVolvimos] en cada (re)conexión
/// —es lo que evita que una pantalla se quede vieja para siempre cuando el proxy
/// corta—. Las pruebas que van de OTRA cosa —una trama partida, un 401 que se
/// renueva, un 500 que se reintenta, una conexión muda— no tienen por qué
/// repetirlo en cada `expect`: lo que comprueban es que el CAMBIO llegue.
///
/// Que salga o no salga lo vigila `el listo SÍ sale —es «volví»—, y los latidos
/// no`, aquí mismo. Filtrarlo allí sería quedarse sin quien lo mire.
List<String> soloLosCambios(List<String> recibidos) =>
    recibidos.where((t) => t != avisoDeQueVolvimos).toList();
