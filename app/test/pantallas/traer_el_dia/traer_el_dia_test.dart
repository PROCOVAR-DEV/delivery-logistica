import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/sincro/ciclo.dart';
import 'package:reparto/nucleo/sincro/recuento.dart';
import 'package:reparto/pantallas/traer_el_dia/datos/textos.dart';
import 'package:reparto/pantallas/traer_el_dia/estado/traer_el_dia.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo_traer_el_dia.dart';

/// EL GESTO: «cojo el día y me lo llevo».
///
/// Todo con reloj y red inyectados, y **con el ciclo de produccion** —candado
/// incluido— detras. Ni un `sleep` ni un `Future.delayed`.
void main() {
  late BaseLocal base;
  late RelojFalso reloj;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 15, 8, 14));
  });

  tearDown(() => base.close());

  ProviderContainer montar(
    Future<RespuestaFalsa?> Function(PeticionVista) responder, {
    bool haySesion = true,
    bool hayPista = true,
  }) {
    final caja = montarTraerElDia(
      base: base,
      reloj: reloj.leer,
      responder: responder,
      haySesion: haySesion,
      hayPista: hayPista,
    );
    addTearDown(caja.dispose);
    return caja;
  }

  group('se le da al boton', () {
    test('baja el dia y al acabar dice QUE TIENE, con numeros', () async {
      final caja = montar(servidorQueTraeElDia);

      final trajo = await caja.read(traerElDiaProvider.notifier).ahora();

      expect(trajo.completo, isTrue, reason: '$trajo');
      expect(trajo.faltan, isEmpty);
      expect(TextosDeTraerElDia.comoQuedo(trajo), 'Ya lo tienes');

      // Y los numeros son los de la base, uno a uno.
      expect(trajo.recuento.cuantas(Colecciones.pedidos), 1);
      expect(trajo.recuento.cuantas(Colecciones.clientes), 2);
      expect(trajo.recuento.cuantas(Colecciones.productos), 1);
      expect(trajo.recuento.cuantas(Colecciones.almacenes), 1);
      expect(
        TextosDeTraerElDia.lasTresCifras(trajo.recuento),
        '1 factura · 2 clientes · 1 producto',
      );
      expect(TextosDeTraerElDia.deLasHoras(trajo.hora), 'de las 8:14');
    });

    test('mientras corre dice POR DONDE VA, coleccion a coleccion', () async {
      final caja = montar(servidorQueTraeElDia);

      // Se apunta cada marcha para poder mirar lo que se habria pintado. Sin
      // esto lo unico comprobable seria el estado final, que es justo lo que no
      // se ve durante los cuarenta segundos que importan.
      final visto = <String>[];
      caja.listen<Marcha>(marchaDelCicloProvider, (_, marcha) {
        if (marcha.enVuelo) {
          visto.add(TextosDeTraerElDia.porDondeVa(marcha.avance));
        }
      }, fireImmediately: true);

      await caja.read(traerElDiaProvider.notifier).ahora();

      expect(visto, contains('Comprobando la sesión...'));
      expect(visto, contains('Clientes...'));
      expect(visto, contains('Productos...'));
      expect(visto, contains('Almacenes...'));
      expect(
        visto.where((t) => t == 'Empezando...'),
        hasLength(1),
        reason:
            'un fotograma de «Empezando...» mientras arranca, y a partir de '
            'ahi siempre un paso con nombre: una rueda sin texto durante '
            'cuarenta segundos es indistinguible de una pantalla colgada',
      );
      expect(
        visto.length,
        greaterThan(8),
        reason:
            'se ve avanzar coleccion a coleccion, no un salto del principio '
            'al final',
      );
      expect(
        caja.read(marchaDelCicloProvider).enVuelo,
        isFalse,
        reason: 'y al acabar la marcha queda quieta',
      );
    });

    test('lo que quedo sin subir sube de paso, y se dice', () async {
      final cola = ColaDeSalida(base, reloj: reloj.leer);
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/r-1/results',
        cuerpo: <String, Object?>{'resultado': 'entregado'},
      );

      final caja = montar(servidorQueTraeElDia);
      final trajo = await caja.read(traerElDiaProvider.notifier).ahora();

      expect(trajo.subidos, 1);
      expect(trajo.completo, isTrue);
      expect(await base.cuantosPendientes(), 0);
    });
  });

  group('la primera vez NO es lo mismo que un dia cualquiera', () {
    // La PANTALLA de la primera configuracion no es de aqui: es una pantalla
    // entera aparte, del agente que lleva el acceso y el portero. Lo que si vive
    // aqui es el dato con el que esa pantalla decide, y se prueba para que no se
    // le rompa por debajo.
    test('con el aparato vacio, la proxima bajada trae TODO', () async {
      final caja = montar(servidorQueTraeElDia);
      final hay = await caja.read(recontadorProvider).ahora();

      expect(
        hay.vaATraerTodo,
        isTrue,
        reason:
            'sin marca en `orders` no hay `desde` que mandar y el servidor '
            'sirve la carga completa',
      );
    });

    test('despues de la primera, ya son diferencias', () async {
      final caja = montar(servidorQueTraeElDia);
      await caja.read(traerElDiaProvider.notifier).ahora();

      final hay = await caja.read(recontadorProvider).ahora();

      expect(
        hay.vaATraerTodo,
        isFalse,
        reason: 'ya hay marca: la proxima manda `desde` y baja diferencias',
      );
    });
  });

  group('no se puede dar dos veces a la vez', () {
    test('dos pulsaciones seguidas son UN SOLO ciclo', () async {
      final servidor = ServidorFalso(servidorQueTraeElDia);
      final caja = montarTraerElDia(
        base: base,
        reloj: reloj.leer,
        responder: servidorQueTraeElDia,
      );
      addTearDown(caja.dispose);

      // El dedo nervioso del almacen: dos golpes al boton antes de que el
      // primero conteste.
      final primera = caja.read(traerElDiaProvider.notifier).ahora();
      final segunda = caja.read(traerElDiaProvider.notifier).ahora();
      await Future.wait([primera, segunda]);

      expect(
        caja.read(cicloProvider).enVuelo,
        isFalse,
        reason: 'y el candado queda suelto',
      );
      servidor.vistas.clear();
    });

    test('el segundo golpe se engancha: una sola vuelta a la red', () async {
      final rutas = <String>[];
      final caja = montar((p) async {
        rutas.add(p.ruta);
        return servidorQueTraeElDia(p);
      });

      final primera = caja.read(traerElDiaProvider.notifier).ahora();
      final segunda = caja.read(traerElDiaProvider.notifier).ahora();
      await Future.wait([primera, segunda]);

      // renovar + bajar + almacenes. Dos ciclos serian seis peticiones, dos
      // renovaciones con el mismo refresh (que el servidor lee como robo) y dos
      // bajadas pisandose.
      expect(rutas, hasLength(3), reason: 'salieron: $rutas');
      expect(rutas.where((r) => r.endsWith('/refresh')), hasLength(1));
      expect(rutas.where((r) => r.endsWith('/sync/cambios')), hasLength(1));
    });
  });

  group('LO QUE MAS IMPORTA: falta una coleccion', () {
    test('el servidor no manda el catalogo: NO queda verde y dice cual falta', () async {
      // El caso silencioso. El servidor contesta 200, todo queda marcado, y el
      // catalogo de productos esta vacio. No hay ningun fallo que mirar: si la
      // pantalla se fiara del ciclo, diria «ya lo tienes» y alguien se iria al
      // almacen a cargar un camion con los pesos a cero.
      final caja = montar((p) async {
        if (p.ruta.endsWith('/sync/cambios')) {
          return RespuestaFalsa(
            200,
            cambiosCompletos(sin: <String>[Colecciones.productos]),
          );
        }
        return servidorQueTraeElDia(p);
      });

      final trajo = await caja.read(traerElDiaProvider.notifier).ahora();

      expect(
        trajo.fallo,
        isNull,
        reason: 'el ciclo salio entero: por ahi no se entera nadie',
      );
      expect(
        trajo.completo,
        isFalse,
        reason: 'y aun asi NO puede quedarse verde: falta el catalogo',
      );
      expect(trajo.aMedias, isTrue);
      expect(trajo.faltan.map((f) => f.coleccion), [Colecciones.productos]);
      expect(
        TextosDeTraerElDia.comoQuedo(trajo),
        'Falta el catálogo de productos',
      );
      expect(
        TextosDeTraerElDia.queSeRompe(trajo.faltan).single,
        'El catálogo de productos: sin él los pesos van incompletos y el '
        'pre-despacho sale corto.',
      );
      expect(
        TextosDeTraerElDia.queHacerSinAlgo,
        contains('vuelve a darle'),
        reason: 'un aviso sin que hacer es una queja',
      );

      // Y lo que SI bajo se dice igual: quien tiene los pedidos y los clientes
      // necesita saber las dos cosas, no solo la mala.
      expect(trajo.recuento.cuantas(Colecciones.clientes), 2);
    });

    test('se corta la senal antes de los almacenes: faltan, y se nombran', () async {
      // `GET /almacenes` es la ultima peticion del ciclo y va fuera de la
      // transaccion: es justo la que se queda sin bajar cuando la senal se va a
      // mitad de gesto. Es «bajaron los pedidos pero no los almacenes».
      final caja = montar((p) async {
        if (p.ruta.endsWith('/almacenes')) return null;
        return servidorQueTraeElDia(p);
      });

      final trajo = await caja.read(traerElDiaProvider.notifier).ahora();

      expect(trajo.fallo, isA<FalloDeRed>());
      expect(trajo.completo, isFalse);
      expect(trajo.faltan.map((f) => f.coleccion), [Colecciones.almacenes]);
      expect(trajo.faltan.single.porQue, PorQueFalta.nuncaSeBajo);
      // Se dice AGRUPADO: los almacenes son una de las cuatro de «lo de
      // siempre» —menos de veinte filas entre las cuatro—, y darles un renglon
      // propio es hacer leer nueve vinetas para enterarse de una cosa.
      expect(TextosDeTraerElDia.comoQuedo(trajo), 'Falta lo de siempre');
      expect(
        TextosDeTraerElDia.queSeRompe(trajo.faltan).single,
        contains('el domicilio se cobra desde el sitio equivocado'),
        reason: 'y se sigue diciendo QUE cuesta que falte',
      );
      expect(
        TextosDeTraerElDia.motivoDelFallo(trajo.fallo!),
        contains('Se cortó la conexión'),
        reason: 'nada de «error desconocido»',
      );

      // Lo que si entro se queda: una bajada que falla no deja la base peor.
      expect(trajo.recuento.cuantas(Colecciones.pedidos), 1);
      expect(trajo.recuento.cuantas(Colecciones.productos), 1);
    });

    test('se cae la bajada entera: no hay nada y se dice de todo', () async {
      final caja = montar((p) async {
        if (p.ruta.endsWith('/sync/cambios')) return null;
        return servidorQueTraeElDia(p);
      });

      final trajo = await caja.read(traerElDiaProvider.notifier).ahora();

      expect(trajo.completo, isFalse);
      expect(
        trajo.faltan,
        hasLength(Colecciones.todas.length),
        reason: 'no bajo ni una: las nueve estan sin marca',
      );
    });
  });

  group('con la conexion mala: la bajada se corta a la mitad', () {
    test('lo de la primera tanda se queda, y al volver SIGUE desde ahi', () async {
      // Con conexion inestable esto no es la excepcion, es lo normal. Las dos
      // cosas que hay que comprobar son que lo bajado no se tira y que el
      // segundo intento no empieza de cero: en la conexion de alla, volver a
      // bajar ocho mil clientes desde el principio cada vez es no acabar nunca.
      final desdes = <String?>[];
      var tandas = 0;
      final caja = montar((p) async {
        if (!p.ruta.endsWith('/sync/cambios')) return servidorQueTraeElDia(p);
        desdes.add(p.parametros['desde'] as String?);
        tandas++;
        if (tandas == 1) {
          // Primera tanda: trae los clientes y avisa de que hay mas.
          final datos = cambiosCompletos(
            sin: <String>[Colecciones.productos],
            clientes: 2,
          );
          datos['truncado'] = true;
          datos['hasta'] = '2026-09-15T08:20:00Z';
          return RespuestaFalsa(200, datos);
        }
        if (tandas == 2) return null; // se corta aqui
        // Tercer intento, ya en el gesto siguiente: llega el resto.
        return RespuestaFalsa(200, cambiosCompletos());
      });

      final primero = await caja.read(traerElDiaProvider.notifier).ahora();

      expect(primero.fallo, isA<FalloDeRed>());
      expect(
        primero.recuento.cuantas(Colecciones.clientes),
        2,
        reason:
            'lo que entro en la primera tanda NO se tira: una bajada que '
            'falla no deja la base peor que antes',
      );
      expect(
        primero.completo,
        isFalse,
        reason: 'y no se queda verde: falto el catalogo',
      );

      // Y ahora lo que de verdad importa: el segundo intento.
      final segundo = await caja.read(traerElDiaProvider.notifier).ahora();

      expect(segundo.completo, isTrue, reason: '$segundo');
      expect(
        desdes.first,
        isNull,
        reason: 'la primera vez no hay marca y se pide todo',
      );
      expect(
        desdes.last,
        '2026-09-15T08:20:00Z',
        reason:
            'SIGUE DESDE DONDE IBA: la marca de la tanda que si entro se '
            'guardo en su misma transaccion, asi que el intento siguiente no '
            'vuelve a bajar los ocho mil clientes desde el principio',
      );
    });
  });

  group('sin sesion', () {
    test('no se intenta nada y no se acusa a la red', () async {
      final rutas = <String>[];
      final caja = montar((p) async {
        rutas.add(p.ruta);
        return servidorQueTraeElDia(p);
      }, haySesion: false);

      final trajo = await caja.read(traerElDiaProvider.notifier).ahora();

      expect(rutas, isEmpty, reason: 'el ciclo no toca la red sin sesion');
      expect(trajo.sinSesion, isTrue);
      expect(trajo.completo, isFalse);
      expect(
        trajo.faltan,
        isEmpty,
        reason:
            'listar las nueve como «no estan» seria culpar a la red de algo '
            'que es de la puerta',
      );
      expect(TextosDeTraerElDia.comoQuedo(trajo), 'Hay que volver a entrar');
    });
  });

  group('sin senal', () {
    test(
      'se dice ANTES de intentarlo, y se dice de que hora es lo guardado',
      () async {
        // Primero se trae el dia con red, para tener algo guardado.
        final conRed = montar(servidorQueTraeElDia);
        await conRed.read(traerElDiaProvider.notifier).ahora();

        final rutas = <String>[];
        final sinRed = montar((p) async {
          rutas.add(p.ruta);
          return servidorQueTraeElDia(p);
        }, hayPista: false);

        final trajo = await sinRed.read(traerElDiaProvider.notifier).ahora();

        expect(
          rutas,
          isEmpty,
          reason:
              'no se queda girando: si el aparato dice que no hay red, ni se '
              'sale',
        );
        expect(trajo.sinSenal, isTrue);
        expect(trajo.completo, isFalse);
        expect(TextosDeTraerElDia.comoQuedo(trajo), 'No hay señal');
        expect(
          trajo.recuento.cuantas(Colecciones.clientes),
          2,
          reason: 'y lo guardado se sigue diciendo: es lo que se lleva puesto',
        );
        expect(TextosDeTraerElDia.deLasHoras(trajo.hora), 'de las 8:14');
        expect(
          trajo.faltan,
          isEmpty,
          reason:
              'y como no le falta nada, no se inventa una falta por no haber '
              'podido salir',
        );
      },
    );

    test('sin senal tambien se dice lo que FALTA de lo guardado', () async {
      // «¿Que me llevo?» es exactamente igual de valida sin cobertura, y es
      // justo cuando mas se pregunta. Visto en el navegador el 15/09/2026: con
      // el catalogo a cero la tabla lo pintaba en verde con un 0 al lado.
      final caja = montar(servidorQueTraeElDia, hayPista: false);

      final trajo = await caja.read(traerElDiaProvider.notifier).ahora();

      expect(trajo.sinSenal, isTrue);
      expect(
        trajo.faltan.map((f) => f.coleccion),
        containsAll(<String>[Colecciones.productos, Colecciones.clientes]),
        reason:
            'el aparato esta vacio y eso se dice, aunque no se haya podido '
            'salir a la red',
      );
      expect(
        TextosDeTraerElDia.comoQuedo(trajo),
        'No hay señal',
        reason:
            'pero el titular sigue siendo por que no se intento: echarle la '
            'culpa al catalogo cuando el problema es la cobertura manda a '
            'alguien a arreglar lo que no es',
      );
    });

    test(
      'que la pista diga que SI hay red no basta: se intenta de verdad',
      () async {
        // En Cuba el aparato ensena el wifi conectado y no sale un paquete. La
        // pista sirve para ahorrar la espera cuando dice que no, nunca para dar
        // por hecho que la hay.
        final rutas = <String>[];
        final caja = montar((p) async {
          rutas.add(p.ruta);
          return null; // la peticion ni sale
        });

        final trajo = await caja.read(traerElDiaProvider.notifier).ahora();

        expect(rutas, isNotEmpty, reason: 'se intento de verdad');
        expect(trajo.sinSenal, isFalse);
        expect(trajo.fallo, isA<FalloApi>());
        expect(trajo.completo, isFalse);
      },
    );
  });

  group('los numeros salen de la BASE', () {
    test('el servidor dice tres y la base tiene dos: se ensenan dos', () async {
      // Dos de los tres clientes vienen con el mismo id — un espejo de PEDIDO
      // que duplico una fila. La respuesta trae tres «puestos»; la base acaba
      // con dos. Lo que se lleva al almacen es la base.
      final caja = montar((p) async {
        if (p.ruta.endsWith('/sync/cambios')) {
          final datos = cambiosCompletos();
          final cambios = datos['cambios']! as Map<String, Object?>;
          cambios[Colecciones.clientes] = <String, Object?>{
            'puestos': <Object?>[
              <String, Object?>{
                'id': 'c-1',
                'name': 'Uno',
                'lat': 20.0,
                'lng': -75.0,
              },
              <String, Object?>{
                'id': 'c-2',
                'name': 'Dos',
                'lat': 20.0,
                'lng': -75.0,
              },
              <String, Object?>{
                'id': 'c-2',
                'name': 'Dos otra vez',
                'lat': 20.0,
                'lng': -75.0,
              },
            ],
            'quitados': <Object?>[],
          };
          return RespuestaFalsa(200, datos);
        }
        return servidorQueTraeElDia(p);
      });

      final trajo = await caja.read(traerElDiaProvider.notifier).ahora();

      expect(
        trajo.recuento.cuantas(Colecciones.clientes),
        2,
        reason: 'contar lo que el servidor dijo que mando daria 3',
      );
      expect(
        TextosDeTraerElDia.lasTresCifras(trajo.recuento),
        contains('2 clientes'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('la bajada se corta a medias', () {
    /// El servidor dice «queda más» y no manda por dónde seguir. `bajada.dart`
    /// para ahí y lo escribe en `quedoPor`. **Las colecciones bajan igual**, con
    /// parte de sus filas: no hay ninguna vacía, así que `Faltas.de` no ve nada.
    Future<RespuestaFalsa?> servidorQueCorta(PeticionVista p) async {
      if (!p.ruta.contains('/cambios')) return servidorQueTraeElDia(p);
      final datos = Map<String, Object?>.from(cambiosCompletos())
        ..['truncado'] = true
        ..remove('hasta');
      return RespuestaFalsa(200, datos);
    }

    test(
      'NO se pone verde, y se dice POR QUÉ con las palabras del servidor',
      () async {
        final caja = montar(servidorQueCorta);

        final trajo = await caja.read(traerElDiaProvider.notifier).ahora();

        expect(
          trajo.faltan,
          isEmpty,
          reason:
              'ninguna colección quedó a cero: ESTE es el caso que se colaba, '
              'porque `Faltas.de` sólo ve las vacías',
        );
        expect(
          trajo.completo,
          isFalse,
          reason:
              'con 2.000 clientes de 8.034 dentro, «Ya lo tienes» es un número '
              'creíble y equivocado — el fallo del `CLAUDE.md` §3',
        );
        expect(
          trajo.quedoPor,
          contains('no mando la marca'),
          reason: 'el motivo LITERAL, el que escribe `bajada.dart`',
        );
        expect(
          TextosDeTraerElDia.comoQuedo(trajo),
          TextosDeTraerElDia.seCortoTitulo,
        );
        expect(
          TextosDeTraerElDia.seCortoDetalle(trajo.quedoPor!),
          contains('aunque las cifras de abajo parezcan normales'),
        );
      },
    );

    test('y una bajada ENTERA no dice que se cortó nada', () async {
      final caja = montar(servidorQueTraeElDia);

      final trajo = await caja.read(traerElDiaProvider.notifier).ahora();

      expect(trajo.quedoPor, isNull);
      expect(trajo.completo, isTrue);
      expect(
        TextosDeTraerElDia.comoQuedo(trajo),
        'Ya lo tienes',
        reason:
            'el caso de todos los días: inventar un corte que no hubo es un '
            'aviso que sale siempre, y uno que sale siempre deja de leerse',
      );
    });
  });
}
