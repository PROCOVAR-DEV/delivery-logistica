import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

/// LA COLA SUBE DE UNO EN UNO, Y UN CORTE A MITAD NO TIRA LO QUE YA SUBIO.
///
/// Jose, 01/10/2026: «recuerda q las subidas sin conexion es por cola para q no
/// caiga todo de una y suba uno a uno las cosas q se hicieron».
///
/// Hasta ese dia no era asi, y se midio en su telefono: tres gestos hechos sin
/// cobertura salieron en **una sola** `POST /sync/subida` de 6.368 bytes (una
/// vuelta vacia trae 579). El registro lo cantaba:
///
/// ```
/// 09:17:57.300  ciclo: ya hay uno en vuelo, no se lanza otro (se hizo algo)
/// 09:17:58.278  ciclo hecho (volvio la red): 3 apuntes subidos
/// ```
///
/// **Por que importa, y no es elegancia:** el reparto trabaja en Cuba con
/// conexion mala, y una peticion grande que se corta al 90 % no deja NADA. La
/// cola se queda entera y hay que volver a empezar por el primero. De uno en uno,
/// lo que ya paso se queda arriba y solo se reintenta lo que falta. Con una
/// jornada entera de trabajo dentro del telefono, esa diferencia es el dia.
///
/// **Y lo que NO se hace:** N peticiones en PARALELO. Eso es lo que el caso I1
/// prohibe —veinte a la vez al recuperar la senal son veinte 401 a la vez contra
/// el candado de renovacion— y es otro diseno. Lo prueba
/// «nunca hay dos peticiones en vuelo a la vez».
void main() {
  late BaseLocal base;
  late ColaDeSalida cola;

  setUp(() {
    base = baseDePrueba();
    cola = ColaDeSalida(base, reloj: RelojFalso(DateTime(2026, 10, 1, 9)).leer);
  });

  setUp(() => aparatoYaDeAlta(base));

  tearDown(() => base.close());

  ({Subida subida, ServidorFalso servidor}) montar(
    Future<RespuestaFalsa?> Function(PeticionVista) responder,
  ) {
    final servidor = ServidorFalso(responder);
    final almacen = AlmacenEnMemoria(
      const Sesion(token: 't', refresh: 'r0', sub: 'u1'),
    );
    final auth = Dio()..httpClientAdapter = servidor;
    final cliente = ClienteApi.montar(
      baseUrl: 'https://sync.test',
      almacen: almacen,
      renovador: Renovador(auth, almacen),
      // SIN REINTENTOS. Aqui se cuentan PETICIONES, y los tres reintentos de
      // `esperasPorDefecto` convertirian «se cayo en el tercero» en cuatro
      // peticiones indistinguibles de un cuarto apunte.
      esperas: const <Duration>[],
    );
    cliente.dio.httpClientAdapter = servidor;
    return (
      subida: Subida(
        cliente: cliente,
        cola: cola,
        aparato: IdentidadDelAparato(base),
        base: base,
        quienEsta: () async => (await almacen.leer())?.sub,
      ),
      servidor: servidor,
    );
  }

  /// Lo que iba dentro de una peticion a `/subida`, apunte a apunte.
  List<Map<String, Object?>> apuntesDe(PeticionVista p) =>
      ((p.cuerpo! as Map<String, Object?>)['apuntes']! as List<Object?>)
          .cast<Map<String, Object?>>();

  /// Las tres marcas de la manana de Jose, en el orden en que las hizo.
  Future<List<String>> tresGestos() async => <String>[
    await cola.encolar(
      metodo: 'PATCH',
      ruta: '/routes/r-1',
      cuerpo: const {'status': 'in_progress'},
    ),
    await cola.encolar(
      metodo: 'PUT',
      ruta: '/board/placements/p-7',
      cuerpo: const {'columnaId': 'z-1', 'posicion': 0},
    ),
    await cola.encolar(
      metodo: 'POST',
      ruta: '/routes/r-1/results',
      cuerpo: const {'resultados': <Object?>[]},
    ),
  ];

  group('tres gestos sin conexion', () {
    test('son TRES envios, uno por apunte y en orden', () async {
      final claves = await tresGestos();
      final m = montar(
        (p) async => RespuestaFalsa(200, {
          'resultados': [
            for (final a in apuntesDe(p))
              {'clave': a['clave'], 'estado': 'aplicado'},
          ],
        }),
      );

      expect(await m.subida.ciclo(), 3);

      // LOS NUMEROS A MANO: tres gestos, tres peticiones.
      expect(
        m.servidor.vistas.where((p) => p.ruta.endsWith('/subida')),
        hasLength(3),
        reason:
            'tres gestos en UNA peticion es lo que habia, y un corte al 90 % de '
            'esa peticion no deja ni uno arriba',
      );
      expect(
        [for (final p in m.servidor.vistas) apuntesDe(p).single['clave']],
        claves,
        reason:
            'uno por peticion y EN ORDEN: dos apuntes del mismo pedido subidos '
            'al reves dejan puesta la primera marca',
      );
      expect(await cola.lote(), isEmpty);
    });

    test('si el TERCERO se cae, los dos de antes se quedan ARRIBA y solo el '
        'tercero sigue pendiente', () async {
      // Es el caso entero por el que se cambio el diseno, y el que no puede
      // fallar nunca: a mitad de cola, lo que ya paso no se vuelve a hacer y lo
      // que falta no se pierde.
      final claves = await tresGestos();
      final m = montar((p) async {
        final clave = apuntesDe(p).single['clave'];
        // La senal se va justo antes del tercero. El servidor no lo ve llegar.
        if (clave == claves[2]) return null;
        return RespuestaFalsa(200, {
          'resultados': [
            {'clave': clave, 'estado': 'aplicado'},
          ],
        });
      });

      await expectLater(m.subida.ciclo(), throwsA(isA<FalloDeRed>()));

      // 1 · SE INTENTARON LOS TRES, no se corto antes de empezar.
      expect(m.servidor.vistas, hasLength(3));

      // 2 · LOS DOS PRIMEROS ESTAN ARRIBA. Con el lote unico estarian los dos
      //     abajo, pendientes, y la manana entera volveria a salir.
      expect(
        (await cola.porClave(claves[0]))!.estado,
        EstadoApunte.aplicado,
        reason: 'lo que ya subio no se desdice porque la red se cayera despues',
      );
      expect((await cola.porClave(claves[1]))!.estado, EstadoApunte.aplicado);

      // 3 · Y EL TERCERO SIGUE PENDIENTE, con SU clave y SU cuerpo enteros.
      final quedan = await cola.lote();
      expect(quedan.map((a) => a.clave).toList(), [claves[2]]);
      expect(quedan.single.estado, EstadoApunte.pendiente);
      expect(
        quedan.single.ruta,
        '/routes/r-1/results',
        reason: 'un apunte no se reescribe por no haber podido subir',
      );
      expect(
        await base.cuantosPendientes(),
        1,
        reason:
            'el «N sin subir» tiene que decir UNO: ni cero —seria un gesto '
            'perdido en silencio— ni tres —serian dos subidas de mas—',
      );

      // 4 · Y LA VUELTA SIGUIENTE SOLO MANDA ESE.
      final m2 = montar(
        (p) async => RespuestaFalsa(200, {
          'resultados': [
            {'clave': apuntesDe(p).single['clave'], 'estado': 'aplicado'},
          ],
        }),
      );
      expect(await m2.subida.ciclo(), 1);
      expect(m2.servidor.vistas, hasLength(1));
      expect(apuntesDe(m2.servidor.vistas.single).single['clave'], claves[2]);
    });

    test('lo que ya subio se cuenta aunque la subida acabe lanzando', () async {
      // `alSubirUno` existe para esto y para nada mas: una excepcion no puede
      // devolver un numero. Sin esto, el cajon de «Entregar el dia» pinta
      // «Subieron 0 apuntes» encima de dos que SI subieron, con el «quedan 1»
      // —que sale de la base— al lado contradiciendolo.
      final claves = await tresGestos();
      final m = montar((p) async {
        final clave = apuntesDe(p).single['clave'];
        if (clave == claves[2]) return null;
        return RespuestaFalsa(200, {
          'resultados': [
            {'clave': clave, 'estado': 'aplicado'},
          ],
        });
      });

      final visto = <int>[];
      await expectLater(
        m.subida.ciclo(alSubirUno: visto.add),
        throwsA(isA<FalloDeRed>()),
      );
      expect(
        visto,
        [1, 2],
        reason:
            'se avisa segun suben y con el total que va: quien escucha se queda '
            'con 2, que es la verdad',
      );
    });

    test('el `pendientes` que viaja al servidor cuenta hacia atras, uno por '
        'peticion', () async {
      // Lo mira el panel de control para decir «Palma lleva desde el martes sin
      // subir». Con el lote unico se mandaba «los que quedan tras TODO el lote»,
      // o sea cero desde la primera peticion. De uno en uno eso seria un cero en
      // la primera de tres, y un cero ahi es la pinta exacta de «esta al dia».
      await tresGestos();
      final mandados = <Object?>[];
      final m = montar((p) async {
        mandados.add((p.cuerpo! as Map<String, Object?>)['pendientes']);
        return RespuestaFalsa(200, {
          'resultados': [
            {'clave': apuntesDe(p).single['clave'], 'estado': 'aplicado'},
          ],
        });
      });

      await m.subida.ciclo();

      expect(
        mandados,
        [2, 1, 0],
        reason:
            'dos quedan tras el primero, uno tras el segundo, ninguno tras el '
            'tercero',
      );
    });

    test('nunca hay dos peticiones de la cola en vuelo a la vez', () async {
      // LA LINEA QUE SEPARA ESTO DEL CASO I1. Veinte apuntes de uno en uno no
      // son veinte a la vez: con un `await` por apunte, un 401 a mitad de cola
      // es UN 401 y el candado de renovacion no ve veinte juntos.
      for (var i = 1; i <= 8; i++) {
        await cola.encolar(metodo: 'POST', ruta: '/api/x/$i', cuerpo: {'n': i});
      }
      var enVuelo = 0;
      var aLaVez = 0;
      final m = montar((p) async {
        enVuelo++;
        if (enVuelo > aLaVez) aLaVez = enVuelo;
        // Un respiro de verdad: sin el, la respuesta vuelve en el mismo turno
        // del bucle de eventos y hasta un codigo en paralelo pareceria serial.
        await Future<void>.delayed(const Duration(milliseconds: 2));
        enVuelo--;
        return RespuestaFalsa(200, {
          'resultados': [
            {'clave': apuntesDe(p).single['clave'], 'estado': 'aplicado'},
          ],
        });
      });

      expect(await m.subida.ciclo(), 8);
      expect(
        aLaVez,
        1,
        reason:
            'ocho a la vez al recuperar la senal son ocho 401 a la vez contra el '
            'candado de renovacion (caso I1): eso sigue prohibido',
      );
    });

    test('un rechazo de uno no para la cola ni se salta a los de detras en '
        'silencio', () async {
      // El rechazado NO es un corte: se resuelve, se queda en la bandeja con su
      // motivo literal, y los de detras salen igual. Lo que no puede pasar es
      // que un «no» a uno tire el trabajo del dia entero.
      final claves = await tresGestos();
      final m = montar((p) async {
        final a = apuntesDe(p).single;
        if (a['clave'] == claves[1]) {
          return RespuestaFalsa(200, {
            'resultados': [
              {
                'clave': a['clave'],
                'estado': 'rechazado',
                'motivo': 'Ese pedido ya va en otra ruta',
              },
            ],
          });
        }
        return RespuestaFalsa(200, {
          'resultados': [
            {'clave': a['clave'], 'estado': 'aplicado'},
          ],
        });
      });

      expect(
        await m.subida.ciclo(),
        2,
        reason:
            'ACEPTADOS, no resueltos: contar el rechazado pone «Subieron 3» '
            'encima de «1 rechazado esperando a que alguien decida»',
      );
      expect(m.servidor.vistas, hasLength(3), reason: 'los tres salieron');

      final malo = (await cola.porClave(claves[1]))!;
      expect(malo.estado, EstadoApunte.rechazado);
      expect(
        malo.motivo,
        'Ese pedido ya va en otra ruta',
        reason: 'TAL CUAL lo dijo el servidor: eso le dice a alguien que hacer',
      );
      expect((await cola.porClave(claves[2]))!.estado, EstadoApunte.aplicado);
      expect(
        await cola.lote(),
        isEmpty,
        reason: 'un rechazo es final: no vuelve al lote a machacar al servidor',
      );
    });

    test('una respuesta que habla de OTRA clave no resuelve nada', () async {
      // De uno en uno esto vale mas que antes: la respuesta de esta peticion solo
      // puede hablar del apunte que iba dentro. Creerle marcaria como rechazado
      // un apunte que nadie mando, y eso no da ningun error: solo trabajo
      // perdido en el sitio que no es.
      final claves = await tresGestos();
      final m = montar(
        (p) async => RespuestaFalsa(200, const {
          'resultados': [
            {'clave': 'una-clave-que-no-es-de-nadie', 'estado': 'aplicado'},
          ],
        }),
      );

      expect(await m.subida.ciclo(), 0);
      for (final clave in claves) {
        expect(
          (await cola.porClave(clave))!.estado,
          EstadoApunte.pendiente,
          reason: 'sin respuesta propia se queda pendiente y se reintenta',
        );
      }
    });
  });

  group('el tope de la vuelta', () {
    test('con 250 pendientes salen 200 peticiones y quedan 50', () async {
      // EL TOPE SIGUE EXISTIENDO Y HAY QUE COMPROBARLO (§3 del CLAUDE.md). Con el
      // lote unico era «cuantos caben en una peticion»; ahora es «cuantas
      // peticiones seguidas», y lo que sobra NO espera al temporizador: la vuelta
      // acaba bien, queda cola, y `CicloDeSincronizacion` lanza otra en el acto.
      //
      // 200 y 250 escritos a mano, no `topeDeLaVuelta`: una prueba que repite la
      // constante del codigo no comprueba el numero, comprueba que sabe copiarlo.
      for (var i = 1; i <= 250; i++) {
        await cola.encolar(metodo: 'POST', ruta: '/api/x/$i', cuerpo: {'n': i});
      }
      final m = montar(
        (p) async => RespuestaFalsa(200, {
          'resultados': [
            {'clave': apuntesDe(p).single['clave'], 'estado': 'aplicado'},
          ],
        }),
      );

      expect(await m.subida.ciclo(), 200);
      expect(m.servidor.vistas, hasLength(200));
      expect(
        await base.cuantosPendientes(),
        50,
        reason: 'los 50 que sobran siguen en la cola, no se pierden ni se callan',
      );
      // Y la peticion numero 200 avisa de los 50 que quedan, que es lo que el
      // panel lee para no pintar a nadie en verde antes de hora.
      expect(
        (m.servidor.vistas.last.cuerpo! as Map<String, Object?>)['pendientes'],
        50,
      );
    });
  });
}
