// CADA PANTALLA SE ENTERA DE LO SUYO EN CUANTO CAMBIA, no sólo el Tablero.
//
// Jose, 17/09/2026: «¿y por qué probamos con tableros solamente? Son todas,
// porque todos deben ser en tiempo real como el tablero cuando las cosas tienen
// conexión».
//
// Hay DOS caminos, y la diferencia entre ellos es justo lo que estaba roto:
//
//  1. **Las pantallas que leen de la base local** —Pedidos, Rutas, Clientes, y
//     el selector de sucursales de la barra— se repintan solas: el aviso
//     dispara un ciclo, el ciclo escribe en la base y el `tableUpdates` de cada
//     pantalla la repinta. Aquí se comprueban los tres eslabones.
//  2. **Las que piden a la red en cada visita** —Vehículos y Almacenes— NO se
//     enteraban de nada: el ciclo les baja una copia a la base que ellas no
//     miran, así que la pantalla seguía enseñando la respuesta que pidió al
//     abrirse. Es el mismo fallo que ya costó una vuelta con el Tablero —el
//     canal funcionaba y en la pantalla no pasaba nada—, en otras dos
//     pantallas.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/eventos.dart' show avisoDeQueVolvimos;
import 'package:reparto/nucleo/refresco_en_vivo.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';
import 'package:reparto/nucleo/sincro/vigia.dart';
import 'package:reparto/pantallas/almacenes/vista/pantalla_almacenes.dart';
import 'package:reparto/pantallas/clientes/vista/pantalla_clientes.dart';
import 'package:reparto/pantallas/vehiculos/vista/pantalla_vehiculos.dart';

import '../apoyo/base_de_prueba.dart';
import '../apoyo/servidor_falso.dart';
import 'almacenes/apoyo_almacenes.dart' as alm;
import 'clientes/apoyo_clientes.dart';
import 'vehiculos/apoyo_vehiculos.dart' as veh;

void main() {
  /// El canal en vivo, en la mano. Es de difusión porque lo escuchan varios
  /// proveedores a la vez, igual que el de verdad.
  late StreamController<String> enVivo;

  setUp(() => enVivo = StreamController<String>.broadcast());
  tearDown(() => enVivo.close());

  /// Deja pasar el aviso y repinta. No es `pumpAndSettle`: el `RelojDeDatos`
  /// tiene un giro sin fin mientras actualiza y `pumpAndSettle` se quedaría
  /// esperándolo.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Desmonta DENTRO de la prueba: los `Stream` de Drift dejan un temporizador
  /// de cero al cerrarse, y si el árbol muere después de que la prueba acabe,
  /// falla por «queda un Timer» sin que haya nada roto.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  // -------------------------------------------------------------------------
  // 1. VEHÍCULOS
  // -------------------------------------------------------------------------

  Future<void> pintarVehiculos(WidgetTester tester, veh.Banco banco) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(banco.base),
          clienteApiProvider.overrideWithValue(
            banco.contenedor.read(clienteApiProvider),
          ),
          // El canal, en la mano. Sin este override el proveedor abriría el de
          // verdad contra `Entorno.apiUrl`, que es PRODUCCIÓN.
          avisosDelServidorProvider.overrideWithValue(enVivo.stream),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaVehiculos())),
      ),
    );
    await asentar(tester);
  }

  testWidgets('Vehículos: con el aviso de «vehiculos» vuelve a pedir la flota '
      'y repinta', (tester) async {
    var nombre = 'Camión viejo';
    final banco = veh.Banco((p) async {
      if (p.ruta.endsWith('/settings')) {
        return RespuestaFalsa(200, const <String, Object?>{
          'tiposVehiculo': <Object?>[],
          'cupRate': 320,
        });
      }
      return RespuestaFalsa(200, [
        <String, Object?>{
          'id': 'v1',
          'name': nombre,
          'type': 'truck',
          'capacity': 1000,
          'status': 'available',
        },
      ]);
    });
    addTearDown(banco.cerrar);
    await pintarVehiculos(tester, banco);

    expect(find.text('Camión viejo'), findsOneWidget);
    final pedidasAlAbrir = banco.servidor.cuantas('GET', '/vehicles');
    expect(pedidasAlAbrir, greaterThan(0));

    // Alguien da de alta un camión desde otro aparato.
    nombre = 'Camión nuevo';
    enVivo.add(CambioEnVivo.vehiculos);
    await asentar(tester);

    expect(
      banco.servidor.cuantas('GET', '/vehicles'),
      greaterThan(pedidasAlAbrir),
      reason:
          'llegó el aviso de «vehiculos» y esta pantalla NO volvió a pedir la '
          'flota. Pide a la red y no a la base, así que el ciclo de '
          'sincronización tampoco la repinta: se queda con lo de hace un rato '
          'hasta que alguien salga de la pantalla y vuelva a entrar',
    );
    expect(
      find.text('Camión nuevo'),
      findsOneWidget,
      reason:
          'volvió a pedir pero no se repintó, que para quien mira es lo '
          'mismo que no haberse enterado',
    );

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------------
  // Y LA MITAD QUE FALTABA: QUÉ PASA CON LO QUE OCURRIÓ MIENTRAS NO ESCUCHÁBAMOS
  // ---------------------------------------------------------------------------
  //
  // Todo lo de arriba comprueba que un aviso que LLEGA repinta. El 29/09/2026 se
  // vio el otro lado, probando la web y el teléfono a la vez:
  //
  //   se creó una zona desde el teléfono → entró en el servidor a las 17:34:55
  //   → y la web siguió diciendo «las zonas las pones tú» TRES MINUTOS DESPUÉS.
  //
  // Jose: «cómo que la web no se entera de lo que pasa en otro aparato, si eso
  // te dije que tiene que saberse en todos».
  //
  // De los registros de la api salió el mecanismo, y son tres cosas que sólo
  // juntas hacen el fallo: la web tarda ~50 s desde que carga hasta que abre el
  // canal (la zona se creó a las 17:34:55 y el canal se abrió a las 17:35:22);
  // el proxy corta el canal cada 300 s exactos; y estas pantallas **no tienen
  // temporizador ninguno** — piden a la red al abrirse y nada más.
  //
  // O sea que un aviso perdido no las deja viejas «hasta la vuelta siguiente»:
  // las deja viejas **para siempre**, sin un error, sin un registro y con la
  // misma cara que si estuvieran bien.
  //
  // El arreglo es que el canal diga cuándo vuelve (`avisoDeQueVolvimos`) y que
  // esto se sume SOLO al tipo de cada pantalla, sin que nadie tenga que
  // acordarse: olvidarlo no falla, y ése es justo el modo de fallo que hay que
  // cerrar.
  testWidgets('Vehículos: al volver el canal se pone al día, aunque no haya '
      'llegado ningún aviso suyo', (tester) async {
    var nombre = 'Camión viejo';
    final banco = veh.Banco((p) async {
      if (p.ruta.endsWith('/settings')) {
        return RespuestaFalsa(200, const <String, Object?>{
          'tiposVehiculo': <Object?>[],
          'cupRate': 320,
        });
      }
      return RespuestaFalsa(200, [
        <String, Object?>{
          'id': 'v1',
          'name': nombre,
          'type': 'truck',
          'capacity': 1000,
          'status': 'available',
        },
      ]);
    });
    addTearDown(banco.cerrar);
    await pintarVehiculos(tester, banco);

    expect(find.text('Camión viejo'), findsOneWidget);
    final pedidasAlAbrir = banco.servidor.cuantas('GET', '/vehicles');

    // MIENTRAS EL CANAL ESTABA CAÍDO alguien renombró el camión desde otro
    // aparato. El aviso de «vehiculos» salió y no lo recibió nadie: no se
    // simula, porque el caso real es justo ése — no llega.
    nombre = 'Camión nuevo';

    // Y el canal vuelve.
    enVivo.add(avisoDeQueVolvimos);
    await asentar(tester);

    expect(
      banco.servidor.cuantas('GET', '/vehicles'),
      greaterThan(pedidasAlAbrir),
      reason:
          'volvió el canal y esta pantalla no volvió a pedir la flota. Lo que '
          'cambiara mientras estuvo caído no lo vio nadie, y aquí no hay '
          'temporizador que lo arregle después: se queda así para siempre',
    );
    expect(
      find.text('Camión nuevo'),
      findsOneWidget,
      reason:
          'volvió a pedir pero no se repintó, que para quien mira es lo mismo '
          'que no haberse enterado',
    );

    await desmontar(tester);
  });

  testWidgets(
    'Vehículos: un aviso de OTRA pantalla no le cuesta una petición',
    (tester) async {
      final banco = veh.Banco((p) async {
        if (p.ruta.endsWith('/settings')) {
          return RespuestaFalsa(200, const <String, Object?>{
            'tiposVehiculo': <Object?>[],
            'cupRate': 320,
          });
        }
        return RespuestaFalsa(200, const <Object?>[]);
      });
      addTearDown(banco.cerrar);
      await pintarVehiculos(tester, banco);

      final antes = banco.servidor.cuantas('GET', '/vehicles');
      enVivo
        ..add(CambioEnVivo.clientes)
        ..add(CambioEnVivo.tablero)
        ..add(CambioEnVivo.rutas);
      await asentar(tester);

      expect(
        banco.servidor.cuantas('GET', '/vehicles'),
        antes,
        reason:
            'se mira el TIPO del aviso: un cambio de clientes no puede costar '
            'una petición de la flota en cada navegador de la oficina, con la '
            'conexión de allá',
      );

      await desmontar(tester);
    },
  );

  testWidgets('Vehículos: el aviso de «ajustes» vuelve a pedir la tasa', (
    tester,
  ) async {
    final banco = veh.Banco((p) async {
      if (p.ruta.endsWith('/settings')) {
        return RespuestaFalsa(200, const <String, Object?>{
          'tiposVehiculo': <Object?>[],
          'cupRate': 320,
        });
      }
      return RespuestaFalsa(200, const <Object?>[]);
    });
    addTearDown(banco.cerrar);
    await pintarVehiculos(tester, banco);

    final antes = banco.servidor.cuantas('GET', '/settings');
    expect(antes, greaterThan(0));

    enVivo.add(CambioEnVivo.ajustes);
    await asentar(tester);

    expect(
      banco.servidor.cuantas('GET', '/settings'),
      greaterThan(antes),
      reason:
          'con la tasa se convierte TODO importe que se pinta: una tasa vieja '
          'no se ve rota, se ve como un número creíble y equivocado',
    );

    await desmontar(tester);
  });

  // -------------------------------------------------------------------------
  // 2. ALMACENES
  // -------------------------------------------------------------------------

  Future<void> pintarAlmacenes(WidgetTester tester, alm.Banco banco) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(banco.base),
          clienteApiProvider.overrideWithValue(
            banco.contenedor.read(clienteApiProvider),
          ),
          avisosDelServidorProvider.overrideWithValue(enVivo.stream),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaAlmacenes())),
      ),
    );
    await asentar(tester);
  }

  testWidgets('Almacenes: con el aviso de «almacenes» vuelve a preguntarle a '
      'Accesos y repinta', (tester) async {
    var nombre = 'Central';
    final banco = alm.Banco(
      (_) async => RespuestaFalsa(200, <String, Object?>{
        'sucursales': [
          {
            'codigo': 'STG',
            'nombre': 'Santiago',
            'almacenes': [
              {
                'id': 'w1',
                'nombre': nombre,
                'principal': true,
                'activo': true,
                'latitud': 20.0,
                'longitud': -75.8,
              },
            ],
          },
        ],
      }),
    );
    addTearDown(banco.cerrar);
    await pintarAlmacenes(tester, banco);

    expect(find.text('Central'), findsWidgets);
    final antes = banco.servidor.cuantas('GET', '/almacenes');
    expect(antes, greaterThan(0));

    // Otra persona le corrige el punto al almacén desde el teléfono.
    nombre = 'Central (patio nuevo)';
    enVivo.add(CambioEnVivo.almacenes);
    await asentar(tester);

    expect(
      banco.servidor.cuantas('GET', '/almacenes'),
      greaterThan(antes),
      reason:
          'llegó el aviso de «almacenes» y no se volvió a preguntar. Y aquí es '
          'peor que en las demás: los almacenes NI SIQUIERA viajan en '
          '`GET /api/sync/cambios` —salen en `faltan`—, así que tampoco los '
          'traía el ciclo a tiempo. El domicilio se cobra por la distancia '
          'DESDE ese punto',
    );
    expect(find.text('Central (patio nuevo)'), findsWidgets);

    await desmontar(tester);
  });

  testWidgets('Almacenes: un aviso de pedidos no le cuesta una petición', (
    tester,
  ) async {
    final banco = alm.Banco(
      (_) async => RespuestaFalsa(200, const <String, Object?>{
        'sucursales': [
          {'codigo': 'STG', 'nombre': 'Santiago', 'almacenes': <Object?>[]},
        ],
      }),
    );
    addTearDown(banco.cerrar);
    await pintarAlmacenes(tester, banco);

    final antes = banco.servidor.cuantas('GET', '/almacenes');
    enVivo
      ..add(CambioEnVivo.pedidos)
      ..add(CambioEnVivo.catalogo);
    await asentar(tester);

    expect(banco.servidor.cuantas('GET', '/almacenes'), antes);

    await desmontar(tester);
  });

  // -------------------------------------------------------------------------
  // 3. CLIENTES — y con ella todas las que viven de la base
  // -------------------------------------------------------------------------
  //
  // Aquí la cadena tiene tres eslabones y hay que comprobar los tres, porque el
  // fallo que ya pasó una vez con el Tablero fue justo un eslabón roto en
  // medio: el aviso llegaba, el ciclo corría, y la colección no viajaba en él.

  test('eslabón 1: cualquier aviso del servidor dispara un ciclo, también el '
      'de clientes', () async {
    final motivos = <String>[];
    final avisos = StreamController<String>();
    addTearDown(avisos.close);

    final vigia = VigiaDeSincronizacion(
      ciclo: (motivo) async => motivos.add(motivo),
      avisosDeRed: Stream<bool>.empty,
      avisosDelServidor: () => avisos.stream,
      // Un temporizador de verdad dejaría la prueba colgada por algo que no
      // tiene nada que ver con lo que se está probando.
      crearTemporizador: (_, _) => Timer(const Duration(days: 1), () {}),
    );
    addTearDown(vigia.parar);
    vigia.arrancar();

    avisos.add(CambioEnVivo.clientes);
    await Future<void>.delayed(Duration.zero);

    expect(
      motivos,
      ['cambió clientes en el servidor'],
      reason:
          'sin esto, la pantalla de Clientes espera al reloj: dos minutos en '
          'la web, cinco en la APK',
    );
  });

  test('eslabón 2: el ciclo baja de verdad las colecciones de esas pantallas', () {
    // Es el eslabón que ya se rompió una vez: un aviso que dispara un ciclo que
    // NO trae esa colección no sirve de nada, y no da ningún error.
    for (final coleccion in [
      Colecciones.clientes,
      Colecciones.pedidos,
      Colecciones.rutas,
      Colecciones.productos,
      Colecciones.vehiculos,
      Colecciones.sucursales,
      Colecciones.ajustes,
    ]) {
      expect(
        Bajada.colecciones,
        contains(coleccion),
        reason:
            '«$coleccion» no viaja en la bajada por diferencias: su aviso '
            'dispararía un ciclo que no trae nada de lo suyo',
      );
    }
    // Los almacenes NO van ahí y eso es a propósito —se piden aparte al final
    // del ciclo—, que es justamente por lo que su pantalla necesita el aviso en
    // vivo más que ninguna.
    expect(Bajada.colecciones, isNot(contains(Colecciones.almacenes)));
  });

  testWidgets('eslabón 3: cuando la bajada escribe un cliente, la pantalla de '
      'Clientes se repinta sola', (tester) async {
    final base = baseDePrueba();
    addTearDown(base.close);
    await sembrarSucursal(base);
    await base
        .into(base.frescura)
        .insertOnConflictUpdate(
          FrescuraCompanion.insert(
            coleccion: Colecciones.clientes,
            bajadaAt: Value(DateTime(2026, 9, 17, 8)),
            completa: const Value(true),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 17, 9)),
          avisosDelServidorProvider.overrideWithValue(enVivo.stream),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaClientes())),
      ),
    );
    await asentar(tester);
    expect(find.text('Bodega del Tívoli'), findsNothing);

    // Esto es lo que deja el ciclo al aplicar la bajada.
    await sembrarCliente(
      base,
      id: 'c-1',
      nombre: 'Bodega del Tívoli',
      lat: 20.01,
      lng: -75.83,
    );
    await asentar(tester);

    expect(
      find.text('Bodega del Tívoli'),
      findsWidgets,
      reason:
          'la pantalla lee de la base con un `tableUpdates` debajo: si no se '
          'repinta al escribir la bajada, el aviso en vivo no sirve de nada '
          'aunque llegue',
    );

    await desmontar(tester);
  });
}
