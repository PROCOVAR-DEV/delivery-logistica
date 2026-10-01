import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';
import 'package:reparto/nucleo/sincro/ciclo.dart';
import 'package:reparto/nucleo/sincro/huerfanos.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

/// LA JORNADA ENTERA SIN SEÑAL, DE PUNTA A PUNTA.
///
/// Hay piezas probadas sueltas —la cola, la subida, el ciclo, los huérfanos— y
/// cada una pasa con lo suyo delante. Lo que no probaba nadie es el día: se
/// trabaja a las diez sin cobertura, se cierra la aplicación a la una, se vuelve
/// a abrir a las tres todavía sin señal, y a las seis, al pasar por donde hay
/// antena, tiene que salir TODO y en el orden en que se hizo. Palabras de Jose:
/// «eso no lo puede perder por ninguna circunstancia porque es trabajo perdido».
///
/// **La base va a un FICHERO y no a memoria.** Una base en memoria pasa estas
/// pruebas enteras sin decir una palabra de lo que se quiere comprobar: lo que
/// distingue «guarda en memoria» de «vive en el aparato» es justamente cerrarla y
/// volver a abrirla, y en memoria ese paso no existe.
///
/// **Y se siembra DESPUÉS de montar, no en el `setUp`** (`CLAUDE.md` §3-ter):
/// cada prueba arranca con lo que había antes del corte y hace que lo nuevo
/// llegue encima.
void main() {
  late Directory carpeta;
  late File fichero;
  late RelojFalso reloj;
  late _Servidor servidor;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('jornada_sin_senal');
    fichero = File('${carpeta.path}/reparto.sqlite');
    reloj = RelojFalso(DateTime(2026, 9, 17, 10));
    servidor = _Servidor();
  });

  tearDown(() async {
    if (carpeta.existsSync()) await carpeta.delete(recursive: true);
  });

  /// El aparato, abierto sobre el MISMO fichero de siempre. Volver a llamarla es
  /// exactamente «cerrar la aplicación y volver a abrirla».
  Future<_Aparato> abrirElAparato() async {
    final base = BaseLocal.con(NativeDatabase(fichero));
    await aparatoYaDeAlta(base);
    return _Aparato.sobre(base, servidor: servidor, reloj: reloj);
  }

  // ---------------------------------------------------------------------------
  // TRAMO 1 · Se pierde la señal A MITAD del gesto, no al empezar.
  // ---------------------------------------------------------------------------

  group('se cae la señal a mitad', () {
    test(
      'lo escrito queda, el apunte queda en la cola y la pantalla dice cuántos '
      'faltan',
      () async {
        final a = await abrirElAparato();
        addTearDown(a.cerrar);

        // ---- Diez de la mañana, con antena: el primer gesto sube. ----------
        await a.sembrarRuta('r-manana');
        final subioBien = await a.cola.encolar(
          metodo: 'PATCH',
          ruta: '/routes/r-manana',
          cuerpo: const {'status': 'in_progress'},
        );
        expect(await a.subida.ciclo(), 1);
        expect(await a.cola.lote(), isEmpty);

        // LA PANTALLA MIRANDO, desde antes de que pase nada. Es la forma del
        // §3-ter: lo que se comprueba es que se entera de lo que llega DESPUÉS,
        // no de lo que ya estaba cuando se montó.
        final loQueVeLaPantalla = <int>[];
        final mirando = a.cola.pendientes().listen(
          (lista) => loQueVeLaPantalla.add(lista.length),
        );
        addTearDown(mirando.cancel);
        await _unRespiro();
        expect(loQueVeLaPantalla.last, 0, reason: 'a las diez no faltaba nada');

        // ---- Mediodía. Se cierra la ruta y la señal se va A MITAD. ---------
        //
        // No al empezar: el gesto se escribe, el apunte se encola, la subida
        // SALE —el servidor la ve llegar— y la contestación no vuelve nunca.
        // Es el corte que de verdad ocurre: el camión entra en el patio del
        // almacén con la petición en vuelo.
        await a.marcarEntrega('r-manana', 'p-1', entregado: true);
        final aMitad = (await a.cola.lote()).last.clave;

        servidor.hayRed = false;
        await expectLater(a.subida.ciclo(), throwsA(isA<FalloDeRed>()));

        // 1 · EL SERVIDOR LA VIO SALIR. Sin esto la prueba estaría midiendo un
        // gesto que ni siquiera lo intentó, que es el caso fácil.
        expect(
          servidor.intentos,
          2,
          reason: 'la subida salió: se cortó en vuelo, no antes de empezar',
        );

        // 2 · LO ESCRITO QUEDA. El resultado del pedido está en la base del
        // aparato, con señal o sin ella.
        expect(await a.resultadoDe('p-1'), ResultadoParada.entregado);

        // 3 · EL APUNTE QUEDA EN LA COLA, con SU clave, pendiente y entero.
        final pendientes = await a.cola.lote();
        expect(pendientes.map((x) => x.clave).toList(), [aMitad]);
        expect(pendientes.single.estado, EstadoApunte.pendiente);
        expect(
          pendientes.single.ruta,
          '/routes/r-manana/results',
          reason: 'un apunte no se reescribe por no haber podido subir',
        );
        // Y el de la mañana no volvió a la cola.
        expect(
          (await a.cola.porClave(subioBien))!.estado,
          EstadoApunte.aplicado,
        );

        // 4 · Y LA PANTALLA LO DICE, sin que nadie la vuelva a montar.
        await _unRespiro();
        expect(
          loQueVeLaPantalla.last,
          1,
          reason:
              'el «N sin subir» es lo único que delata un gesto que no llegó; '
              'si se queda en 0 nadie se entera hasta que no cuadra el '
              'inventario',
        );
      },
    );

    test('el servidor lo guardó y el aparato no lo oyó: al volver la red NO se '
        'aplica dos veces', () async {
      final a = await abrirElAparato();
      addTearDown(a.cerrar);

      await a.sembrarRuta('r-1');
      await a.marcarEntrega('r-1', 'p-1', entregado: true);
      final clave = (await a.cola.lote()).single.clave;

      // El corte de después de guardar: el servidor aplica y la respuesta se
      // pierde en el camino. Es el caso exacto para el que existe la `clave`.
      servidor.guardaYSeCalla = true;
      await expectLater(a.subida.ciclo(), throwsA(isA<FalloDeRed>()));
      expect(servidor.aplicados, hasLength(1));

      // Vuelve la red. El reintento sale con LA MISMA clave.
      servidor.guardaYSeCalla = false;
      expect(await a.subida.ciclo(), 1);

      expect(
        servidor.aplicados,
        hasLength(1),
        reason:
            'la misma clave vuelve `repetido`, no duplica el cierre de la '
            'ruta: dos cierres del mismo camión no se ven hasta el inventario',
      );
      expect(servidor.repetidos, 1);
      expect(await a.cola.lote(), isEmpty);

      // Y AQUÍ ES DONDE HAY QUE MIRAR, que es lo que esta prueba no miraba:
      // `repetido` **no es un error**. Tratarlo como un «no» del servidor deja
      // la cola igual de vacía y el número de subidos igual de bueno —los dos
      // primeros expects pasan tal cual—, pero mete en la bandeja de rechazos,
      // con el motivo en blanco, un trabajo que SÍ llegó. Y de la bandeja no
      // sale nada hasta que una persona decida, así que ese cierre se queda
      // ahí para siempre pareciendo perdido.
      expect(
        (await a.cola.porClave(clave))!.estado,
        EstadoApunte.aplicado,
        reason: '«repetido» es exactamente para lo que existe la clave',
      );
      expect(
        await a.cola.rechazados().first,
        isEmpty,
        reason: 'lo que llegó no puede acabar en la bandeja de rechazos',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // TRAMO 2 · Se cierra la aplicación y se vuelve a abrir, todavía sin señal.
  // ---------------------------------------------------------------------------

  group('se cierra la aplicación y se vuelve a abrir sin señal', () {
    test('la cola sigue entera, con las mismas claves y en el mismo orden, con '
        'gestos de tipos distintos', () async {
      servidor.hayRed = false;

      // ---- La tarde entera en el patio, sin una raya de cobertura. -------
      var a = await abrirElAparato();
      await a.sembrarRuta('r-tarde');
      await a.sembrarZonaDelTablero('z-vista', pedidos: ['p-1', 'p-2']);

      // CINCO gestos y de CUATRO clases distintas. Con uno solo, cualquier
      // cosa que conserve «el último» pasa la prueba.
      final claves = <String>[
        // Crea algo: lleva provisional, y eso es lo que hace de bisagra.
        await a.cola.encolar(
          metodo: 'POST',
          ruta: '/board/columns?branchId=suc-stg',
          cuerpo: const {'id': 'z-vista', 'nombre': 'Vista'},
          provisional: 'z-vista',
        ),
        // Coloca: va detrás de la zona y depende de ella.
        await a.cola.encolar(
          metodo: 'PUT',
          ruta: '/board/placements/p-1',
          cuerpo: const {'columnaId': 'z-vista', 'posicion': 0},
        ),
        await a.cola.encolar(
          metodo: 'PUT',
          ruta: '/board/placements/p-2',
          cuerpo: const {'columnaId': 'z-vista', 'posicion': 1},
        ),
        // Cambia el estado de una ruta.
        await a.cola.encolar(
          metodo: 'PATCH',
          ruta: '/routes/r-tarde',
          cuerpo: const {'status': 'in_progress'},
        ),
        // Y el cierre de la tarde, que es el que lleva el trabajo del día.
        await a.cola.encolar(
          metodo: 'POST',
          ruta: '/routes/r-tarde/results',
          cuerpo: const {
            'resultados': [
              {'orderId': 'p-1', 'resultado': ResultadoParada.entregado},
            ],
          },
        ),
      ];
      final rutas = (await a.cola.lote()).map((x) => x.ruta).toList();
      await a.cerrar();

      // ---- Se cierra la aplicación del todo y se vuelve a abrir. ---------
      a = await abrirElAparato();
      addTearDown(a.cerrar);

      final trasReabrir = await a.cola.lote();
      expect(
        trasReabrir.map((x) => x.clave).toList(),
        claves,
        reason: 'las MISMAS claves: ni una nueva, ni una perdida',
      );
      expect(
        trasReabrir.map((x) => x.ruta).toList(),
        rutas,
        reason: 'y en el mismo orden, que es el orden en que se hicieron',
      );
      expect(
        trasReabrir.every((x) => x.estado == EstadoApunte.pendiente),
        isTrue,
      );
      expect(
        trasReabrir.first.provisional,
        'z-vista',
        reason:
            'sin el provisional, las colocaciones de detrás suben a una zona '
            'que no existe en ningún sitio',
      );
      expect(jsonDecode(trasReabrir.last.cuerpo), {
        'resultados': [
          {'orderId': 'p-1', 'resultado': ResultadoParada.entregado},
        ],
      }, reason: 'el cuerpo del cierre vuelve igual que se guardó');
      expect(
        servidor.intentos,
        0,
        reason: 'sin señal no se molesta a nadie: ni al abrir, ni al cerrar',
      );

      // ---- Seis de la tarde: pasa por donde hay antena. ------------------
      servidor.hayRed = true;
      expect(await a.subida.ciclo(), 5);

      expect(
        servidor.aplicados.map((x) => x['ruta']).toList(),
        rutas,
        reason: 'sube lo de la tarde entero y en su orden',
      );
      expect(await a.cola.lote(), isEmpty);

      // Y otra vuelta del ciclo no lo sube otra vez.
      expect(await a.subida.ciclo(), 0);
      expect(servidor.aplicados, hasLength(5));
    });
  });

  // ---------------------------------------------------------------------------
  // TRAMO 3 · Vuelve la señal y sube un lote de VARIOS apuntes EN ORDEN.
  // ---------------------------------------------------------------------------

  group('vuelve la señal', () {
    test('marcar una parada y luego corregirla sube en ese orden, no al revés', () async {
      servidor.hayRed = false;
      final a = await abrirElAparato();
      addTearDown(a.cerrar);
      await a.sembrarRuta('r-1');

      // Las dos caras del mismo pedido, hechas con veinte minutos de diferencia
      // y sin señal ninguna de las dos. Subirlas al revés deja puesta la
      // PRIMERA marca: el pedido queda «no entregado» en el servidor y el
      // repartidor jura que lo entregó.
      await a.cola.encolar(
        metodo: 'POST',
        ruta: '/routes/r-1/results',
        cuerpo: const {
          'resultados': [
            {'orderId': 'p-1', 'resultado': ResultadoParada.devuelto},
          ],
        },
      );
      reloj.avanzar(const Duration(minutes: 20));
      await a.cola.encolar(
        metodo: 'POST',
        ruta: '/routes/r-1/results',
        cuerpo: const {
          'resultados': [
            {'orderId': 'p-1', 'resultado': ResultadoParada.entregado},
          ],
        },
      );

      servidor.hayRed = true;
      expect(await a.subida.ciclo(), 2);

      expect(
        servidor.intentos,
        2,
        reason:
            'dos apuntes SON dos peticiones desde el 01/10/2026, una detras de '
            'otra: lo que sube se queda arriba aunque la segunda se caiga. Lo '
            'que importa aqui es que el ORDEN se respeta igual, y lo dice el '
            '`resultadosDe` de abajo',
      );
      expect(servidor.resultadosDe('p-1'), [
        ResultadoParada.devuelto,
        ResultadoParada.entregado,
      ]);
      expect(
        servidor.ultimoResultadoDe('p-1'),
        ResultadoParada.entregado,
        reason:
            'la corrección es la que manda; al revés, el pedido se queda «no '
            'entregado» arriba y nadie lo sabe',
      );
    });

    test(
      'doce apuntes salen en DOCE peticiones, una detrás de otra y en su orden',
      () async {
        servidor.hayRed = false;
        final a = await abrirElAparato();
        addTearDown(a.cerrar);

        for (var i = 1; i <= 12; i++) {
          await a.cola.encolar(
            metodo: 'PATCH',
            ruta: '/routes/r-$i',
            cuerpo: {'n': i},
          );
        }

        servidor.hayRed = true;
        expect(await a.subida.ciclo(), 12);
        expect(
          servidor.intentos,
          12,
          reason:
              'una jornada entera sin señal son ~12 apuntes, y van de uno en '
              'uno: si la antena se va en el séptimo, los seis de antes ya '
              'están arriba',
        );
        expect(servidor.aplicados.map((x) => x['ruta']).toList(), [
          for (var i = 1; i <= 12; i++) '/routes/r-$i',
        ]);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // TRAMO 4 · Un apunte del lote lo rechaza el servidor y los demás no.
  // ---------------------------------------------------------------------------

  group('el servidor rechaza UNO del lote', () {
    test('el rechazado se queda con su motivo literal y los demás suben igual', () async {
      servidor.hayRed = false;
      final a = await abrirElAparato();
      addTearDown(a.cerrar);

      final primera = await a.cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r-1',
        cuerpo: const {'status': 'in_progress'},
      );
      final mala = await a.cola.encolar(
        metodo: 'PUT',
        ruta: '/board/placements/p-7',
        cuerpo: const {'columnaId': 'z-1', 'posicion': 0},
      );
      final tercera = await a.cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r-2',
        cuerpo: const {'status': 'completed'},
      );
      final cuarta = await a.cola.encolar(
        metodo: 'POST',
        ruta: '/routes/r-2/results',
        cuerpo: const {'resultados': <Object?>[]},
      );

      // EL MOTIVO LITERAL DEL SERVIDOR. «Ese pedido ya va en otra ruta» le dice
      // a alguien qué hacer; «no se pudo guardar» no le dice nada.
      servidor.rechaza['/board/placements/p-7'] =
          'Ese pedido ya va en otra ruta';
      servidor.hayRed = true;

      // ACEPTADOS, NO RESUELTOS. Un rechazado también se resuelve —queda en la
      // bandeja— pero NO subió; contarlo aquí es lo que ponía «Subieron 4
      // apuntes» encima de «1 rechazado esperando a que alguien decida».
      expect(await a.subida.ciclo(), 3);

      // El lote NO se corta: los tres siguen adelante, también el que iba
      // DETRÁS del rechazado.
      expect(servidor.aplicados.map((x) => x['ruta']).toList(), [
        '/routes/r-1',
        '/routes/r-2',
        '/routes/r-2/results',
      ], reason: 'un «no» a uno no puede tirar el trabajo del día entero');
      for (final clave in [primera, tercera, cuarta]) {
        expect((await a.cola.porClave(clave))!.estado, EstadoApunte.aplicado);
      }

      final rechazado = (await a.cola.porClave(mala))!;
      expect(rechazado.estado, EstadoApunte.rechazado);
      expect(
        rechazado.motivo,
        'Ese pedido ya va en otra ruta',
        reason: 'TAL CUAL lo dijo el servidor, sin envolver en «hubo un error»',
      );
      expect(
        await a.cola.lote(),
        isEmpty,
        reason: 'un rechazo es final: no vuelve al lote a machacar al servidor',
      );

      // Y otra vuelta no lo reintenta ni lo vuelve a mandar.
      expect(await a.subida.ciclo(), 0);
      expect(
        servidor.intentos,
        4,
        reason:
            'las CUATRO de la primera vuelta y ni una más: la segunda vuelta no '
            'vuelve a llamar por nadie',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // TRAMO 5 · La bandeja de rechazados. Nada se descarta en silencio.
  // ---------------------------------------------------------------------------

  group('la bandeja de rechazados', () {
    test('lo rechazado se ve con su motivo y su hora, y no desaparece solo', () async {
      servidor.hayRed = false;
      var a = await abrirElAparato();
      await a.cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r-9',
        cuerpo: const {'status': 'completed'},
      );

      // LA BANDEJA MIRANDO DESDE ANTES, con la cola todavía limpia. El rechazo
      // llega DESPUÉS, con la pantalla ya abierta: es el caso que el
      // `CLAUDE.md` §4-bis dice que no se cazaba por sembrarlo en el `setUp`.
      final bandeja = <List<Apunte>>[];
      final mirando = a.cola.rechazados().listen(bandeja.add);
      addTearDown(mirando.cancel);
      await _unRespiro();
      expect(bandeja.last, isEmpty);

      servidor.rechaza['/routes/r-9'] = 'Esa ruta ya está cerrada';
      servidor.hayRed = true;
      reloj.ahora = DateTime(2026, 9, 17, 18, 42);
      await a.subida.ciclo();

      // 1 · SE VE, sin volver a montar nada.
      await _unRespiro();
      expect(bandeja.last, hasLength(1));
      final visto = bandeja.last.single;
      expect(visto.motivo, 'Esa ruta ya está cerrada');
      expect(
        visto.resueltoAt,
        DateTime(2026, 9, 17, 18, 42),
        reason: 'con su hora: sin ella no se sabe si es de hoy o del martes',
      );
      expect(
        visto.ruta,
        '/routes/r-9',
        reason: 'y qué gesto era, o no hay nada que ir a mirar',
      );

      // 2 · NO DESAPARECE SOLO. Ni con más vueltas del ciclo…
      await a.subida.ciclo();
      await a.subida.ciclo();
      expect(await a.cola.rechazados().first, hasLength(1));

      // …ni con la poda, que es lo único que borra apuntes por su cuenta.
      reloj.avanzar(const Duration(days: 30));
      expect(await a.cola.podar(), 0);
      expect(await a.cola.rechazados().first, hasLength(1));

      // 3 · Ni al cerrar y volver a abrir la aplicación.
      final clave = visto.clave;
      await a.cerrar();
      a = await abrirElAparato();
      addTearDown(a.cerrar);
      final trasReabrir = await a.cola.rechazados().first;
      expect(trasReabrir.single.clave, clave);
      expect(trasReabrir.single.motivo, 'Esa ruta ya está cerrada');
    });

    test('sólo se va cuando una PERSONA decide', () async {
      servidor.hayRed = false;
      final a = await abrirElAparato();
      addTearDown(a.cerrar);
      await a.cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r-9',
        cuerpo: const {'status': 'completed'},
      );
      servidor.rechaza['/routes/r-9'] = 'Esa ruta ya está cerrada';
      servidor.hayRed = true;
      await a.subida.ciclo();

      final clave = (await a.cola.rechazados().first).single.clave;

      // Reintentar: vuelve a la cola limpio y sale en el próximo envío.
      await a.cola.reintentar(clave);
      expect((await a.cola.lote()).single.clave, clave);
      expect((await a.cola.porClave(clave))!.motivo, isNull);

      // Y si el servidor ya no lo tumba, sube y se acabó.
      servidor.rechaza.remove('/routes/r-9');
      expect(await a.subida.ciclo(), 1);
      expect(await a.cola.rechazados().first, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // TRAMO 6 · Huérfanos: trabajo en el aparato SIN ningún apunte que lo suba.
  // ---------------------------------------------------------------------------

  group('huérfanos', () {
    test('la zona «Vista» con sus cinco pedidos, sin apunte ninguno, la vuelve a '
        'encolar el ciclo y sube sola', () async {
      servidor.hayRed = true;
      final a = await abrirElAparato();
      addTearDown(a.cerrar);

      // ---- El aparato al día: no hay nada colgado. -----------------------
      var resumen = await a.ciclo.ahora(motivo: 'la primera vuelta');
      expect(resumen.bien, isTrue);
      expect(await Huerfanos(a.base).mirar(), isEmpty);

      // ---- Y AHORA aparece el trabajo colgado, con el ciclo ya montado. --
      //
      // La zona está en el teléfono con su marca de «sólo existe aquí» y sus
      // cinco pedidos, y NO le queda ningún apunte que la suba: el suyo se
      // descartó. Así se vio el 16/09/2026 — el Tablero enseñándola, entregar
      // el día diciendo «Todo entregado» y el Panel diciendo «Todo al día»,
      // mientras el servidor decía «nunca ha subido».
      await a.sembrarZonaDelTablero(
        'z-vista',
        nombre: 'Vista',
        pedidos: ['p-1', 'p-2', 'p-3', 'p-4', 'p-5'],
      );
      expect(await a.cola.lote(), isEmpty, reason: 'ni un apunte que la suba');
      expect((await Huerfanos(a.base).mirar()).texto, '1 zona del tablero');

      // ---- El ciclo solo, sin que nadie pulse nada. ----------------------
      servidor.vaciar();
      resumen = await a.ciclo.ahora(motivo: 'volvió la red');
      expect(resumen.bien, isTrue);

      expect(
        servidor.aplicados.map((x) => x['ruta']).toList(),
        [
          '/board/columns?branchId=suc-stg',
          '/board/placements/p-1',
          '/board/placements/p-2',
          '/board/placements/p-3',
          '/board/placements/p-4',
          '/board/placements/p-5',
        ],
        reason:
            'la zona primero y sus cinco pedidos detrás, en su orden de '
            'visita: una zona vacía arriba es peor que no subir nada, porque '
            'parece que el trabajo llegó',
      );
      expect(
        servidor.aplicados.first['cuerpo'],
        containsPair('id', 'z-vista'),
        reason:
            'el id va en el cuerpo, o el servidor crea una SEGUNDA zona con '
            'el mismo nombre y el índice único la rechaza: un rechazo falso y '
            'un atasco permanente',
      );
      expect(await a.cola.lote(), isEmpty);
      expect(
        await Huerfanos(a.base).mirar(),
        isEmpty,
        reason: 'ya no está colgada: el servidor dijo que sí',
      );
      expect(
        await a.nacioAqui('z-vista'),
        0,
        reason:
            'y se le quita la marca, que es lo que desatasca la bajada del '
            'tablero',
      );

      // ---- Y NO LO HACE DOS VECES. --------------------------------------
      servidor.vaciar();
      resumen = await a.ciclo.ahora(motivo: 'el tic de los cinco minutos');
      expect(resumen.bien, isTrue);
      expect(
        servidor.aplicados,
        isEmpty,
        reason: 'el ciclo corre cada pocos minutos: la cola crecería sola',
      );
    });

    test('una tarjeta colocada sobre una zona que SÍ está arriba también sube '
        'sola', () async {
      servidor.hayRed = true;
      final a = await abrirElAparato();
      addTearDown(a.cerrar);
      expect((await a.ciclo.ahora(motivo: 'al día')).bien, isTrue);

      // El mismo atasco por el otro lado: la zona ya subió, la tarjeta se
      // arrastró encima sin señal y su apunte se perdió. El barrido de zonas
      // no la coge, porque va por zonas.
      await a.sembrarZonaDelTablero('z-arriba', yaSubida: true);
      await a.sembrarTarjeta('p-9', zona: 'z-arriba', sitio: 3);

      servidor.vaciar();
      expect((await a.ciclo.ahora(motivo: 'volvió la red')).bien, isTrue);

      expect(servidor.aplicados.map((x) => x['ruta']).toList(), [
        '/board/placements/p-9',
      ]);
      expect(
        servidor.aplicados.single['cuerpo'],
        containsPair('posicion', 3),
        reason: 'el sitio importa: es el orden de visita del camión',
      );
    });

    test('una RUTA armada sin señal y sin apunte no la sube nadie, PERO SE '
        'DICE', () async {
      // ESTA PRUEBA ERA EL `HALLAZGO ·`, y afirmaba el comportamiento de
      // entonces: la ruta ni subía ni salía en ningún sitio. Se le dio la
      // vuelta el 24/09/2026, que es lo que pedía.
      //
      // Lo que NO ha cambiado: `Huerfanos` mira cuatro sitios —`board_columns`,
      // `routes`, `vehicles` y `warehouses`— pero `volverAEncolar` sólo sabe
      // reconstruir el tablero, así que una ruta huérfana **sigue sin subir**.
      // Eso está bien y es deliberado: es mejor un aviso que nombra lo que hay
      // que mirar que un apunte inventado a medias.
      //
      // Lo que SÍ ha cambiado es la otra mitad, la que decía el comentario de
      // `huerfanos.dart` —«los demás se cuentan y **se dicen**»— y que no
      // estaba: contar se contaba y decirse no se decía, porque `mirar()` no lo
      // llamaba nadie en `lib/`. Ahora lo lee `trabajoHuerfanoProvider` y lo
      // pintan la franja de estado y el cajón de «Entregar el día»
      // (`test/navegacion/la_franja_dice_lo_que_no_sube_test.dart`).
      //
      // El día que el desatasco sepa rehacer una ruta, la mitad de «no sube»
      // se pondrá roja y hay que cambiarla por la de arriba, no borrarla.
      servidor.hayRed = true;
      final a = await abrirElAparato();
      addTearDown(a.cerrar);
      expect((await a.ciclo.ahora(motivo: 'al día')).bien, isTrue);

      await a.base.customStatement(
        "INSERT INTO routes (id, status) VALUES ('local-9f3a2b7c', 'planned')",
      );

      // Se cuenta, y con nombre de persona: eso sí está.
      final colgado = await Huerfanos(a.base).mirar();
      expect(colgado.texto, '1 ruta');

      servidor.vaciar();
      expect((await a.ciclo.ahora(motivo: 'volvió la red')).bien, isTrue);

      expect(
        servidor.aplicados,
        isEmpty,
        reason:
            'HOY NO SUBE. Cuando el desatasco sepa rehacer una ruta, esta '
            'prueba se pondrá roja: entonces hay que cambiarla por la de '
            'arriba, no borrarla',
      );
      expect(
        await a.cola.lote(),
        isEmpty,
        reason: 'y no queda ni un apunte que la nombre',
      );
      expect(
        (await Huerfanos(a.base).mirar()).texto,
        '1 ruta',
        reason: 'sigue colgada vuelta tras vuelta',
      );

      // ---- Y AHORA LA MITAD QUE FALTABA: **se dice**. ---------------------
      //
      // Es lo que mira la pantalla, no `Huerfanos` a pelo: entre las dos cosas
      // estaba el agujero. El provider es el cable, y sin él la ruta seguía
      // existiendo sólo en el teléfono de alguien que la daba por hecha.
      final contenedor = ProviderContainer.test(
        overrides: [baseProvider.overrideWith((ref) => a.base)],
      );
      addTearDown(contenedor.dispose);
      // Suscrito ANTES de preguntar: un `StreamProvider` que nadie escucha se
      // queda en «cargando» y `.future` no se resuelve nunca.
      final quita = contenedor.listen(trabajoHuerfanoProvider, (_, _) {});
      addTearDown(quita.close);
      expect(
        (await contenedor.read(trabajoHuerfanoProvider.future)).texto,
        '1 ruta',
        reason:
            'se NOMBRA lo que es. Si esto vuelve a salir vacío, la ruta está '
            'en el aparato, no está arriba, no la sube nadie y **no sale en '
            'ninguna pantalla**: el caso que este fichero entero venía a '
            'cerrar',
      );
    });

    test('si el servidor vuelve a decir que no, se queda en la bandeja y NO se '
        'encola en bucle', () async {
      servidor.hayRed = true;
      final a = await abrirElAparato();
      addTearDown(a.cerrar);
      expect((await a.ciclo.ahora(motivo: 'al día')).bien, isTrue);

      await a.sembrarZonaDelTablero('z-vista', pedidos: ['p-1']);
      servidor.rechaza['/board/columns?branchId=suc-stg'] =
          'Ya hay una zona con ese nombre';

      servidor.vaciar();
      expect((await a.ciclo.ahora(motivo: 'volvió la red')).bien, isTrue);
      final enLaBandeja = await a.cola.rechazados().first;
      expect(enLaBandeja.single.motivo, 'Ya hay una zona con ese nombre');

      // Y la vuelta siguiente NO la vuelve a encolar: un rechazado cuenta como
      // apunte vivo, está esperando a que una persona decida. Encolarla otra
      // vez sería insistirle a un servidor que ya dijo que no.
      servidor.vaciar();
      expect((await a.ciclo.ahora(motivo: 'el tic')).bien, isTrue);
      expect(
        servidor.aplicados.where(
          (x) => x['ruta'] == '/board/columns?branchId=suc-stg',
        ),
        isEmpty,
      );
      expect(await a.cola.rechazados().first, hasLength(1));
    });
  });
}

/// Un respiro para que los `Stream` de Drift emitan.
///
/// Nada de `await` sobre el primer valor dentro de un widget test: ahí el tiempo
/// no avanza y la prueba se CUELGA en vez de fallar (`CLAUDE.md` §5). Aquí son
/// `test()` normales, así que un `Future.delayed` de verdad basta y termina.
Future<void> _unRespiro() =>
    Future<void>.delayed(const Duration(milliseconds: 40));

/// EL APARATO ENTERO sobre un fichero: su base, su cola, su subida y su ciclo.
class _Aparato {
  _Aparato({
    required this.base,
    required this.cola,
    required this.subida,
    required this.ciclo,
  });

  factory _Aparato.sobre(
    BaseLocal base, {
    required _Servidor servidor,
    required RelojFalso reloj,
  }) {
    final adaptador = servidor.adaptador();
    final almacen = AlmacenEnMemoria(
      const Sesion(token: 't', refresh: 'r0', sub: 'u1'),
    );
    final auth = Dio(BaseOptions(baseUrl: 'https://auth.test/api/auth'))
      ..httpClientAdapter = adaptador;
    final renovador = Renovador(auth, almacen);

    ClienteApi contra(String baseUrl) {
      final cliente = ClienteApi.montar(
        baseUrl: baseUrl,
        almacen: almacen,
        renovador: renovador,
        // SIN ESPERAS. Los reintentos de 1 s, 4 s y 10 s en una prueba son
        // quince segundos quemados esperando a una red que no existe, y
        // `flutter test` se corta a los 300 s.
        esperas: const <Duration>[],
      );
      cliente.dio.httpClientAdapter = adaptador;
      return cliente;
    }

    final cola = ColaDeSalida(base, reloj: reloj.leer);
    final subida = Subida(
      cliente: contra('https://sync.test'),
      cola: cola,
      aparato: IdentidadDelAparato(base),
      base: base,
      quienEsta: () async => (await almacen.leer())?.sub,
    );
    return _Aparato(
      base: base,
      cola: cola,
      subida: subida,
      ciclo: CicloDeSincronizacion(
        almacen: almacen,
        renovador: renovador,
        subida: subida,
        bajada: Bajada(
          cliente: contra('https://api.test'),
          base: base,
          frescura: RegistroDeFrescura(base, reloj: reloj.leer),
          reloj: reloj.leer,
        ),
        huerfanos: Huerfanos(base),
        cola: cola,
        haySesion: () => true,
      ),
    );
  }

  final BaseLocal base;
  final ColaDeSalida cola;
  final Subida subida;
  final CicloDeSincronizacion ciclo;

  Future<void> cerrar() => base.close();

  /// Una ruta con un pedido dentro, como la dejó el armador por la mañana.
  Future<void> sembrarRuta(String id) async {
    await base
        .into(base.routes)
        .insertOnConflictUpdate(RoutesCompanion.insert(id: id));
    await base
        .into(base.orders)
        .insertOnConflictUpdate(
          OrdersCompanion.insert(
            id: 'p-1',
            customerName: 'Yasmani',
            address: 'Calle 1',
          ),
        );
  }

  /// El gesto de marcar una entrega: escribe AQUÍ y encola. Es lo que hace
  /// `AccionesDeRutas.marcar`, con lo que esta prueba mira y nada más.
  Future<void> marcarEntrega(
    String rutaId,
    String pedidoId, {
    required bool entregado,
  }) async {
    await (base.update(base.orders)..where((o) => o.id.equals(pedidoId))).write(
      OrdersCompanion(
        resultado: Value(
          entregado ? ResultadoParada.entregado : ResultadoParada.devuelto,
        ),
        status: Value(
          entregado ? EstadoPedido.entregado : EstadoPedido.pendiente,
        ),
      ),
    );
    await cola.encolar(
      metodo: 'POST',
      ruta: '/routes/$rutaId/results',
      cuerpo: <String, Object?>{
        'resultados': [
          {
            'orderId': pedidoId,
            'resultado': entregado
                ? ResultadoParada.entregado
                : ResultadoParada.devuelto,
          },
        ],
      },
    );
  }

  Future<String?> resultadoDe(String pedidoId) async {
    final fila = await (base.select(
      base.orders,
    )..where((o) => o.id.equals(pedidoId))).getSingle();
    return fila.resultado;
  }

  /// Una zona del tablero en el aparato. Las tablas del Tablero no son de Drift:
  /// las crea la propia pantalla la primera vez que se abre.
  Future<void> sembrarZonaDelTablero(
    String id, {
    String nombre = 'Vista',
    String sucursal = 'suc-stg',
    List<String> pedidos = const [],
    bool yaSubida = false,
  }) async {
    await EsquemaTablero.asegurar(base);
    await base.customStatement(
      'INSERT OR REPLACE INTO board_columns (id, branch_id, nombre, posicion, '
      'created_at, updated_at, nacio_aqui) '
      "VALUES (?1, ?2, ?3, 1, '2026-09-17T10:00:00.000', "
      "'2026-09-17T10:00:00.000', ?4)",
      [id, sucursal, nombre, yaSubida ? 0 : 1],
    );
    for (var i = 0; i < pedidos.length; i++) {
      await sembrarTarjeta(pedidos[i], zona: id, sitio: i);
    }
  }

  Future<void> sembrarTarjeta(
    String pedidoId, {
    required String zona,
    required int sitio,
  }) async {
    await EsquemaTablero.asegurar(base);
    await base
        .into(base.orders)
        .insertOnConflictUpdate(
          OrdersCompanion.insert(
            id: pedidoId,
            customerName: 'Cliente $pedidoId',
            address: 'Calle 1',
          ),
        );
    await base.customStatement(
      'INSERT OR REPLACE INTO board_placements (order_id, column_id, posicion, '
      'colocado_at, updated_at, nacio_aqui) '
      "VALUES (?1, ?2, ?3, '2026-09-17T10:00:00.000', "
      "'2026-09-17T10:00:00.000', 1)",
      [pedidoId, zona, sitio],
    );
  }

  /// La marca de «esto sólo existe aquí» de una zona.
  Future<int> nacioAqui(String id) async {
    final fila = await base
        .customSelect(
          'SELECT nacio_aqui AS m FROM board_columns WHERE id = ?1',
          variables: [Variable<String>(id)],
        )
        .getSingle();
    return fila.read<int>('m');
  }
}

/// EL SERVIDOR DE LA CALLE: se va, vuelve, guarda y a veces dice que no.
///
/// Guarda por `clave` a propósito, que es lo único que hace que esta prueba
/// pueda distinguir «subió» de «subió DOS VECES». Un servidor que aplicara todo
/// lo que le llega dejaría pasar exactamente el fallo que más caro sale aquí.
class _Servidor {
  bool hayRed = true;

  /// Guarda lo que le llega y **se calla**: el corte de después de aplicar, que
  /// es para lo que existe la `clave`.
  bool guardaYSeCalla = false;

  /// Rutas que el servidor rechaza, con su motivo literal.
  final Map<String, String> rechaza = <String, String>{};

  /// Lo que de verdad quedó guardado arriba, en el orden en que se aplicó.
  final List<Map<String, Object?>> aplicados = <Map<String, Object?>>[];

  /// Cuántas peticiones llegaron, hayan contestado o no.
  int intentos = 0;

  /// Cuántas veces contestó `repetido` — o sea, cuántas veces la idempotencia
  /// hizo su trabajo.
  int repetidos = 0;

  final Set<String> _yaAplicadas = <String>{};

  void vaciar() {
    aplicados.clear();
    intentos = 0;
    repetidos = 0;
  }

  /// Los resultados que le llegaron de un pedido, en orden.
  List<String> resultadosDe(String pedidoId) => [
    for (final a in aplicados)
      for (final r
          in (a['cuerpo'] as Map<String, Object?>?)?['resultados']
                  as List<Object?>? ??
              const <Object?>[])
        if ((r! as Map<String, Object?>)['orderId'] == pedidoId)
          (r as Map<String, Object?>)['resultado']! as String,
  ];

  String? ultimoResultadoDe(String pedidoId) =>
      resultadosDe(pedidoId).isEmpty ? null : resultadosDe(pedidoId).last;

  ServidorFalso adaptador() => ServidorFalso(_responder);

  Future<RespuestaFalsa?> _responder(PeticionVista p) async {
    if (p.ruta.endsWith('/subida')) intentos++;
    if (!hayRed) return null;

    if (p.ruta.endsWith('/refresh')) {
      return RespuestaFalsa(200, <String, Object?>{
        'token': 't-nuevo',
        'refresh_token': 'r1',
        'sub': 'u1',
      });
    }

    if (p.ruta.endsWith('/subida')) {
      final cuerpo = p.cuerpo! as Map<String, Object?>;
      final apuntes = (cuerpo['apuntes']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final resultados = <Map<String, Object?>>[];
      for (final a in apuntes) {
        final clave = a['clave']! as String;
        final ruta = a['ruta']! as String;
        final motivo = rechaza[ruta];
        if (motivo != null) {
          resultados.add({
            'clave': clave,
            'estado': 'rechazado',
            'motivo': motivo,
          });
          continue;
        }
        if (!_yaAplicadas.add(clave)) {
          // LA IDEMPOTENCIA. Ya estaba de un intento que se cortó antes de
          // contestar: no es un error, es exactamente para lo que existe la
          // clave.
          repetidos++;
          resultados.add({'clave': clave, 'estado': 'repetido'});
          continue;
        }
        aplicados.add(a);
        resultados.add({
          'clave': clave,
          'estado': 'aplicado',
          if (a['provisional'] != null) 'id': a['provisional'],
        });
      }
      // El corte de después de guardar: quedó aplicado arriba y la respuesta no
      // llegó nunca.
      if (guardaYSeCalla) return null;
      return RespuestaFalsa(200, <String, Object?>{'resultados': resultados});
    }

    if (p.ruta.endsWith('/almacenes')) {
      return RespuestaFalsa(200, <String, Object?>{'sucursales': <Object?>[]});
    }

    // La bajada por diferencias: sin novedades.
    return RespuestaFalsa(200, <String, Object?>{
      'hasta': '2026-09-17T18:00:00Z',
      'completa': true,
      'truncado': false,
      'cambios': <String, Object?>{},
    });
  }
}
