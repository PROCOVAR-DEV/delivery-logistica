import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/reloj.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/red/salud.dart';
import 'package:reparto/nucleo/sincro/ciclo.dart';
import 'package:reparto/nucleo/red/veredicto_del_sistema.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/servidor_falso.dart';

/// Un servidor que trae EL DIA ENTERO: las siete colecciones de `cambios` y los
/// almacenes, que van por su propia puerta.
///
/// Es el punto de partida de casi todas las pruebas: cada una lo estropea por un
/// sitio distinto y mira que se dice.
Future<RespuestaFalsa?> servidorQueTraeElDia(PeticionVista p) async {
  if (p.ruta.endsWith('/refresh')) {
    return RespuestaFalsa(200, <String, Object?>{
      'token': tokenDePrueba(),
      'refresh_token': 'r1',
      'sub': 'u1',
    });
  }
  if (p.ruta.endsWith('/aparato')) {
    // El alta la da el servidor y devuelve EL identificador. Sin ella,
    // `POST /sync/subida` contesta 404 y no sube nada.
    return RespuestaFalsa(201, <String, Object?>{
      'aparato': '9f3a0d2e-0000-4000-8000-000000000001',
      'persona': 'u-1',
      'sucursal': 'STG',
    });
  }
  if (p.ruta.endsWith('/subida')) {
    final cuerpo = p.cuerpo! as Map<String, Object?>;
    final apuntes = cuerpo['apuntes']! as List<Object?>;
    return RespuestaFalsa(200, <String, Object?>{
      'resultados': [
        for (final a in apuntes)
          {
            'clave': (a! as Map<String, Object?>)['clave'],
            'estado': 'aplicado',
          },
      ],
    });
  }
  if (p.ruta.endsWith('/almacenes')) {
    return RespuestaFalsa(200, <String, Object?>{
      'sucursales': <Object?>[
        <String, Object?>{
          'codigo': 'STG',
          'almacenes': <Object?>[
            <String, Object?>{
              'id': 'alm-1',
              'nombre': 'Central',
              'principal': true,
            },
          ],
        },
      ],
    });
  }
  return RespuestaFalsa(200, cambiosCompletos());
}

/// La respuesta de `GET /sync/cambios` con todo dentro. [sin] quita colecciones
/// enteras, que es como se simula «el servidor no mando el catalogo».
Map<String, Object?> cambiosCompletos({
  List<String> sin = const <String>[],
  int clientes = 2,
}) {
  final cambios = <String, Object?>{
    Colecciones.pedidos: <String, Object?>{
      'puestos': <Object?>[
        <String, Object?>{
          'id': 'o-1',
          'customerName': 'Yasmani',
          'address': 'Calle 1',
          'weight': 12.0,
          'items': <Object?>[
            <String, Object?>{
              'id': 'it-1',
              'linea': 1,
              'description': 'Aceite',
              'quantity': 3,
            },
          ],
        },
      ],
      'quitados': <Object?>[],
    },
    Colecciones.rutas: <String, Object?>{
      'puestos': <Object?>[
        <String, Object?>{'id': 'r-1', 'name': 'Centro'},
      ],
      'quitados': <Object?>[],
    },
    Colecciones.clientes: <String, Object?>{
      'puestos': <Object?>[
        for (var i = 1; i <= clientes; i++)
          <String, Object?>{
            'id': 'c-$i',
            'name': 'Cliente $i',
            'lat': 20.0,
            'lng': -75.0,
          },
      ],
      'quitados': <Object?>[],
    },
    Colecciones.productos: <String, Object?>{
      'puestos': <Object?>[
        <String, Object?>{'id': 'p-1', 'name': 'Aceite', 'weight': 0.9},
      ],
      'quitados': <Object?>[],
    },
    Colecciones.vehiculos: <String, Object?>{
      'puestos': <Object?>[
        <String, Object?>{'id': 'v-1', 'name': 'Camión 1'},
      ],
      'quitados': <Object?>[],
    },
    Colecciones.sucursales: <String, Object?>{
      'puestos': <Object?>[
        <String, Object?>{
          'id': 'STG',
          'name': 'Santiago',
          'lat': 20.0,
          'lng': -75.8,
        },
      ],
      'quitados': <Object?>[],
    },
    Colecciones.ajustes: <String, Object?>{
      'puestos': <Object?>[
        <String, Object?>{'currency': 'USD', 'cupRate': 320},
      ],
      'quitados': <Object?>[],
    },
  };
  for (final fuera in sin) {
    cambios.remove(fuera);
  }
  return <String, Object?>{
    'hasta': '2026-09-15T08:14:00Z',
    'completa': true,
    'truncado': false,
    'cambios': cambios,
  };
}

/// El cableado de verdad, con el servidor y el reloj cambiados.
///
/// **El ciclo que se monta aqui es el de produccion**, con su candado dentro:
/// lo unico que se sustituye es de donde salen las peticiones, quien dice la
/// hora y si hay sesion. Montar un ciclo de mentira dejaria sin probar justo lo
/// que hay que probar — que dos pulsaciones son un solo ciclo.
ProviderContainer montarTraerElDia({
  required BaseLocal base,
  required Reloj reloj,
  required Future<RespuestaFalsa?> Function(PeticionVista) responder,
  bool haySesion = true,
  bool hayPista = true,
  // EL VEREDICTO DEL SISTEMA, en sus tres piezas. Se anadio el 29/09/2026 para
  // poder montar este mismo cableado con los canales puestos a mano y comprobar
  // que volver la senal dispara un ciclo de verdad — no que la pieza exista, que
  // existia y estaba desconectada.
  //
  // Van como TRES parametros con su tipo y no como una lista de overrides
  // sueltos, y no es capricho: **`Override` no es un tipo publico en Riverpod
  // 3.1** —no lo exporta ni `flutter_riverpod` ni `riverpod`—, asi que una lista
  // asi no se puede declarar sin `dynamic`, y con `dynamic` el analizador la
  // rechaza. Con tipo propio, pasar lo que no es falla al escribirlo.
  VeredictoAhora? veredictoAhora,
  AvisosDeVeredicto? avisosDeVeredicto,
  CrearEspera? esperaDelSondeo,
}) {
  final almacen = AlmacenEnMemoria(
    const Sesion(token: 't-viejo', refresh: 'r0', sub: 'u1'),
  );

  return ProviderContainer(
    overrides: [
      baseProvider.overrideWithValue(base),
      relojProvider.overrideWithValue(reloj),
      almacenSesionProvider.overrideWithValue(almacen),
      dioAuthProvider.overrideWithValue(dioFalso(responder)),
      clienteApiProvider.overrideWithValue(
        clienteFalso(responder, baseUrl: 'https://api.test'),
      ),
      clienteSyncProvider.overrideWithValue(
        clienteFalso(responder, baseUrl: 'https://sync.test'),
      ),
      pistaDeRedProvider.overrideWithValue(() async => hayPista),
      // El aviso de red tambien se inyecta: sin esto el plugin no existe en una
      // prueba, el stream revienta y la pantalla se queda sin saber si hay red.
      avisosDeRedProvider.overrideWithValue(() => Stream<bool>.value(hayPista)),
      // La MISMA construccion que `proveedores.dart`, con `haySesion` a mano
      // para no tener que arrastrar el portero entero a una prueba de esto.
      cicloProvider.overrideWith(
        (ref) => CicloDeSincronizacion(
          almacen: ref.watch(almacenSesionProvider),
          renovador: ref.watch(renovadorProvider),
          subida: ref.watch(subidaProvider),
          bajada: ref.watch(bajadaProvider),
          huerfanos: ref.watch(huerfanosProvider),
          cola: ref.watch(colaProvider),
          haySesion: () => haySesion,
          alEmpezar: () {
            ref.read(enVueloProvider.notifier).empieza();
            ref
                .read(marchaDelCicloProvider.notifier)
                .empieza(ref.read(relojProvider)());
          },
          alTerminar: () {
            ref.read(enVueloProvider.notifier).termina();
            ref.read(marchaDelCicloProvider.notifier).termina();
          },
          alAvanzar: (avance) =>
              ref.read(marchaDelCicloProvider.notifier).avanza(avance),
        ),
      ),
      // `?` y no un `if`: lo que no pase la prueba se queda con el de siempre.
      ?veredictoAhora != null
          ? veredictoAhoraProvider.overrideWithValue(veredictoAhora)
          : null,
      ?avisosDeVeredicto != null
          ? avisosDeVeredictoProvider.overrideWithValue(avisosDeVeredicto)
          : null,
      ?esperaDelSondeo != null
          ? crearEsperaDelSondeoProvider.overrideWithValue(esperaDelSondeo)
          : null,
    ],
  );
}

/// Deja la conexion **dada por mala**, como si se hubieran caido tres ciclos
/// seguidos por red.
///
/// Se hace con el camino de verdad —`LaSalud.anotar`— y no poniendo un booleano:
/// asi la prueba comprueba tambien el umbral, que es lo que decide si el aviso
/// parpadea todo el dia o no.
void darLaConexionPorMala(ProviderContainer caja) {
  for (var i = 0; i < SaludDeLaRed.fallosParaDarlaPorMala; i++) {
    caja
        .read(saludDeLaRedProvider.notifier)
        .anotar(const ResumenDelCiclo(fallo: FalloDeRed()));
  }
}
