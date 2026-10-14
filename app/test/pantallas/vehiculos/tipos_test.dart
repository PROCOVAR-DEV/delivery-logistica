// LOS TIPOS DE VEHICULO, QUE SON LOS QUE COTIZAN EL DOMICILIO.
//
// Dos fallos que juntos cerraban el camino:
//
//  1. `+ Crear tipo nuevo…` sólo hacia `setState`. El tipo se elegia, se veia en
//     el desplegable y se perdia al cerrar la ficha — **sin un solo error**. Es
//     el mismo fallo que ya paso en delivery y que cuenta
//     `docs/esquema-cambios.md`.
//  2. El cajon de «Tipos de vehículo» sólo enseñaba los que hay en ajustes, asi
//     que `truck` —el tipo por defecto de TODO vehiculo nuevo— no aparecia en
//     ninguna lista donde ponerle su costo por km.
//
// Resultado en produccion: `vehicle_types.costo_km_usd` en NULL en los cinco
// tipos. Y ese numero es el que cotiza el domicilio que se le cobra al cliente.

// MUTACIONES (14/10/2026): cada guarda de abajo se rompio a proposito en
// `repositorio_vehiculos.dart`, `vehiculo_api.dart` o `pantalla_vehiculos.dart`
// y SALIO ROJA. Quien toque esas guardas, que repita la que corresponda:
//
//  * DELETE traga cualquier rechazo (`if (e.codigo != 404) rethrow` vaciado) ->
//    «un DELETE que contesta 403/409 NO se traga». Y sin ni el 404 -> «el 404
//    del DELETE es ya estaba» y «FALLO A MEDIAS».
//  * Sin `throw GuardadoAMedias` -> «FALLO A MEDIAS». Con `aplicadas >= 0` ->
//    «un 5xx ... sigue diciendo no se guardó nada».
//  * `_reactivar` sin `'activo': true`, o con `costoKmUsd: null` siempre ->
//    las pruebas de reactivar (cajon, ficha, tipo en uso).
//  * `existente.activo` quitado en `guardarTipos` -> reactivar desde el cajon;
//    `!t.activo` quitado en `crearTipo` -> «crearTipo con el nombre de uno
//    VIVO»; `crearTipo` sin buscar retirados -> «+ Crear tipo nuevo…» con un
//    RETIRADO.
//  * Nombre siempre / nunca en el PATCH, costo siempre -> «cambiar sólo el
//    costo» y «RENOMBRAR».
//  * `previo` salido del servidor de AHORA en vez de `abiertos` -> SOLO la
//    prueba de EDICION AJENA (furgoneta 1.5).
//  * El servidor mirado ANTES de borrar -> «quitar y volver a escribir».
//  * `paraElCajon` sin filtrar activos, `conocidos` sin retirados, `deJson` sin
//    leer `activo` o sin `id` -> «un tipo RETIRADO no sale ...». `activo = false`
//    por defecto lo caza el grupo «los tipos que se enseñan».
//  * La guarda de `_crearTipo` de la pantalla mirando tambien retirados, o
//    quitada -> las dos pruebas de «+ Crear tipo nuevo…».
//
// NO se mutó (no es de este fichero ni estaba permitido): la rama
// `on GuardadoAMedias` de `estado_vehiculos.dart`. Sin ella el texto seria el
// de `on Object` («NO se guardó nada»), que la prueba de FALLO A MEDIAS rechaza.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/vehiculos/estado/estado_vehiculos.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';
import 'package:reparto/pantallas/vehiculos/vista/ficha_vehiculo.dart';
import 'package:reparto/pantallas/vehiculos/vista/pantalla_vehiculos.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo_vehiculos.dart';

void main() {
  /// Un servidor falso **con memoria**, con la tabla de verdad: lo que
  /// `POST/PATCH/DELETE /vehicle-types` cambia es lo que `GET /vehicle-types`
  /// contesta despues. Sin esa memoria no se puede comprobar lo unico que
  /// importa aqui, que es si el tipo SIGUE ESTANDO al volver a mirar.
  ///
  /// Habla el CONTRATO REAL de `api/internal/api/tipos_vehiculo.go`:
  ///
  ///  * `nombre` es UNIQUE y exacto, **retirados incluidos**: un POST o un PATCH
  ///    que lo repite contesta 409 «Ya existe un tipo de vehículo con ese
  ///    nombre».
  ///  * `DELETE` de un id que no existe contesta 404.
  ///  * `DELETE` de un tipo que algun camion usa ([usados], por id) NO lo borra:
  ///    lo RETIRA (`activo: false`) y contesta `retirado: true`. `GET` lo sigue
  ///    devolviendo, con `activo: false`.
  ///  * Los tipos sembrados admiten `'activo': false`.
  ///
  /// [forzar] contesta antes que nada a las peticiones de `/vehicle-types` que le
  /// interesen (un 403, un 500); devolver `null` deja pasar a la tabla.
  ///
  /// `PUT /settings` contesta 200 y NO guarda tipos, igual que el servidor de
  /// verdad: es el fallo de Amado (14/10/2026), que la app seguia mandando los
  /// tipos ahi y el 200 hacia creer que se habian guardado.
  ({Banco banco, List<Map<String, Object?>> tipos}) montarServidor({
    List<Map<String, Object?>> tipos = const [],
    List<Map<String, Object?>> vehiculos = const [],
    Set<String> usados = const {},
    RespuestaFalsa? Function(PeticionVista)? forzar,
  }) {
    var siguiente = 0;
    final guardados = [
      for (final t in tipos)
        <String, Object?>{'id': 't${siguiente++}', 'activo': true, ...t},
    ];
    const yaExiste = <String, Object?>{
      'error': 'Ya existe un tipo de vehículo con ese nombre',
    };
    bool repetido(Object? nombre, {String? salvo}) =>
        guardados.any((t) => t['nombre'] == nombre && t['id'] != salvo);
    final banco = Banco((p) async {
      if (p.ruta.contains('/vehicle-types')) {
        final forzada = forzar?.call(p);
        if (forzada != null) return forzada;
        final id = p.ruta.split('/').last;
        final cuerpo = p.cuerpo as Map<String, Object?>?;
        final fila = guardados.where((t) => t['id'] == id).firstOrNull;
        switch (p.metodo) {
          case 'POST':
            if (repetido(cuerpo!['nombre'])) {
              return RespuestaFalsa(409, yaExiste);
            }
            final nuevo = <String, Object?>{
              'id': 't${siguiente++}',
              'activo': true,
              ...cuerpo,
            };
            guardados.add(nuevo);
            return RespuestaFalsa(201, nuevo);
          case 'PATCH':
            if (fila == null) {
              return RespuestaFalsa(404, const <String, Object?>{
                'error': 'Not found',
              });
            }
            if (cuerpo!.containsKey('nombre') &&
                repetido(cuerpo['nombre'], salvo: id)) {
              return RespuestaFalsa(409, yaExiste);
            }
            fila.addAll(cuerpo);
            return RespuestaFalsa(200, fila);
          case 'DELETE':
            if (fila == null) {
              return RespuestaFalsa(404, const <String, Object?>{
                'error': 'Not found',
              });
            }
            final enUso = usados.contains(id);
            if (enUso) {
              fila['activo'] = false;
            } else {
              guardados.remove(fila);
            }
            return RespuestaFalsa(200, <String, Object?>{
              'success': true,
              'retirado': enUso,
            });
        }
        return RespuestaFalsa(200, guardados);
      }
      if (p.ruta.endsWith('/settings')) {
        return RespuestaFalsa(200, const <String, Object?>{'cupRate': 320});
      }
      return RespuestaFalsa(200, vehiculos);
    });
    return (banco: banco, tipos: guardados);
  }

  /// Lo guardado sin los ids que pone el servidor, para comparar lo que importa.
  List<Map<String, Object?>> sinIds(List<Map<String, Object?>> tipos) => [
    for (final t in tipos)
      {'nombre': t['nombre'], 'costoKmUsd': t['costoKmUsd']},
  ];

  Future<void> pintar(WidgetTester tester, Banco banco) async {
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
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaVehiculos())),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> abrirCajon(WidgetTester tester) async {
    await tester.tap(find.text('Tipos de vehículo'));
    await tester.pumpAndSettle();
  }

  /// Lo que SALIO al servidor y no era una lectura, en orden.
  List<String> escrituras(Banco banco) => [
    for (final p in banco.servidor.vistas)
      if (p.metodo != 'GET') '${p.metodo} ${p.ruta}',
  ];

  /// Los cuerpos de las peticiones de ese metodo, en orden.
  List<Object?> cuerpos(Banco banco, String metodo) => [
    for (final p in banco.servidor.vistas)
      if (p.metodo == metodo) p.cuerpo,
  ];

  ControlVehiculos controlDe(Banco banco) =>
      banco.contenedor.read(controlVehiculosProvider.notifier);

  AvisoVehiculos? avisoDe(Banco banco) =>
      banco.contenedor.read(controlVehiculosProvider);

  // ---------------------------------------------------------------------------
  // 1. El cajon de Tipos siembra los que YA usan los vehiculos
  // ---------------------------------------------------------------------------

  testWidgets('el cajon de Tipos enseña `truck` aunque no esté en ajustes', (
    tester,
  ) async {
    final montaje = montarServidor(
      // Ajustes VACIO de tipos, que es lo que hay en produccion.
      vehiculos: const [
        <String, Object?>{
          'id': 'v1',
          'name': 'Camión #1',
          'type': 'truck',
          'capacity': 1000,
          'status': 'available',
        },
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);

    await tester.tap(find.text('Tipos de vehículo'));
    await tester.pumpAndSettle();

    // El cajon abierto, con una fila para `truck` y su hueco de costo/km.
    expect(find.text('Tipos de vehículo'), findsWidgets);
    expect(
      find.widgetWithText(TextField, 'truck'),
      findsOneWidget,
      reason:
          'El cajon de Tipos no enseña `truck`, que es el tipo por defecto de '
          'todo vehiculo nuevo y el que usan los vehiculos que ya existen. Sin '
          'esa fila no hay NINGUNA lista donde ponerle su costo por km, y ese '
          'costo es el que cotiza el domicilio que se le cobra al cliente.',
    );
    expect(find.text('Sin tipos. Agrega el primero.'), findsNothing);

    // Y se le puede poner el costo y guardar: eso es lo que arregla los NULL.
    await tester.enterText(
      find.widgetWithText(TextField, 'truck').first,
      'truck',
    );
    final costo = find.widgetWithText(TextField, 'Costo/km (USD)');
    await tester.enterText(costo, '1.65');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(sinIds(montaje.tipos), [
      <String, Object?>{'nombre': 'truck', 'costoKmUsd': 1.65},
    ]);

    await desmontar(tester);
  });

  testWidgets('el tipo que ya tiene costo lo trae puesto', (tester) async {
    final montaje = montarServidor(
      vehiculos: const [
        <String, Object?>{
          'id': 'v1',
          'name': 'Camión #1',
          'type': 'truck',
          'capacity': 1000,
          'status': 'available',
          'costoKmUsd': 2.5,
        },
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);

    await tester.tap(find.text('Tipos de vehículo'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '2.5'), findsOneWidget);

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------------
  // 2. `+ Crear tipo nuevo…` GUARDA
  // ---------------------------------------------------------------------------

  testWidgets('se crea un tipo nuevo y SIGUE AHÍ al reabrir', (tester) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);

    // --- Se crea desde la ficha del vehiculo ---------------------------------
    // Hay dos botones con ese texto —el de la cabecera y el del vacio— y los
    // dos abren la misma ficha.
    await tester.tap(
      find.widgetWithText(FilledButton, 'Agregar Vehículo').first,
    );
    await tester.pumpAndSettle();

    // El desplegable de `Tipo`, no el de `Estado del vehículo`.
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Tipo'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Crear tipo nuevo…').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del tipo'),
      'Rastra',
    );
    // El `Costo por km (USD)` DEL TIPO, que en el arbol va justo debajo del
    // desplegable; el del vehiculo viene mas abajo.
    await tester.enterText(
      find.widgetWithText(TextField, 'Costo por km (USD)').first,
      '3.25',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Crear tipo'));
    await tester.pumpAndSettle();

    // SALIO AL SERVIDOR. Esto es lo que antes no pasaba: el tipo vivia en un
    // `setState` y se perdia al cerrar la ficha, sin un solo error.
    expect(
      montaje.banco.servidor.cuantas('POST', '/vehicle-types'),
      1,
      reason:
          '`Crear tipo` no mando el tipo a /vehicle-types: sólo existe en la '
          'pantalla y se pierde al cerrarla, sin un solo error. Es el fallo '
          'que ya paso en delivery (docs/esquema-cambios.md).',
    );
    expect(
      montaje.banco.servidor.cuantas('PUT', '/settings'),
      0,
      reason:
          '`PUT /settings` ya no guarda tipos: contesta 200 y los tira, y la '
          'pantalla dice «guardado». Fue lo que vio Amado el 14/10/2026.',
    );
    expect(sinIds(montaje.tipos), [
      <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
      <String, Object?>{'nombre': 'Rastra', 'costoKmUsd': 3.25},
    ]);
    // Y queda elegido, con su costo heredado en el campo del vehiculo.
    expect(find.widgetWithText(TextField, '3.25'), findsOneWidget);

    // --- Se cierra la ficha y se abre el cajon de Tipos ----------------------
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tipos de vehículo'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextField, 'Rastra'),
      findsOneWidget,
      reason:
          'El tipo recien creado no está en el catalogo al volver a mirar: se '
          'guardó sólo en la pantalla.',
    );

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------------
  // 2-bis. El cajon edita el catalogo TIPO A TIPO
  // ---------------------------------------------------------------------------

  testWidgets('cambiar el costo de un tipo que existe lo PATCHea por su id', (
    tester,
  ) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
        <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 3.0},
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);
    await abrirCajon(tester);

    await tester.enterText(find.widgetWithText(TextField, '0.9'), '1.1');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    final peticiones = montaje.banco.servidor.vistas
        .where((p) => p.metodo != 'GET')
        .toList();
    expect(peticiones.map((p) => '${p.metodo} ${p.ruta}').toList(), [
      'PATCH /vehicle-types/t0',
    ], reason: 'Sólo cambio uno: no hay que crear ni tocar el otro.');
    expect(sinIds(montaje.tipos), [
      <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 1.1},
      <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 3.0},
    ]);

    await desmontar(tester);
  });

  // (c) Lo que viaja en cada PATCH es SÓLO lo que esta persona cambio.
  testWidgets('cambiar sólo el costo manda SÓLO el costo (no el nombre)', (
    tester,
  ) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);
    await abrirCajon(tester);

    await tester.enterText(find.widgetWithText(TextField, '0.9'), '1.1');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(
      cuerpos(montaje.banco, 'PATCH'),
      [
        <String, Object?>{'costoKmUsd': 1.1},
      ],
      reason:
          'cambio el costo y viajo tambien el nombre: se compara contra algo '
          'que no es lo que habia al abrir el cajon',
    );

    await desmontar(tester);
  });

  testWidgets('RENOMBRAR un tipo manda SÓLO el nombre (no el costo)', (
    tester,
  ) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
        <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 3.0},
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);
    await abrirCajon(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'furgoneta'),
      'furgoneta grande',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(escrituras(montaje.banco), ['PATCH /vehicle-types/t0']);
    expect(
      cuerpos(montaje.banco, 'PATCH'),
      [
        <String, Object?>{'nombre': 'furgoneta grande'},
      ],
      reason:
          'renombrar no puede mandar el costo (ni al reves): cada campo viaja '
          'sólo si esta persona lo cambio',
    );
    expect(sinIds(montaje.tipos), [
      <String, Object?>{'nombre': 'furgoneta grande', 'costoKmUsd': 0.9},
      <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 3.0},
    ]);

    await desmontar(tester);
  });

  testWidgets('vaciar el costo de un tipo lo deja VACÍO (null viaja)', (
    tester,
  ) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);
    await abrirCajon(tester);

    await tester.enterText(find.widgetWithText(TextField, '0.9'), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(montaje.tipos.single['costoKmUsd'], isNull);

    await desmontar(tester);
  });

  testWidgets('quitar un tipo manda su DELETE y deja los demás', (
    tester,
  ) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
        <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 3.0},
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);
    await abrirCajon(tester);

    await tester.tap(find.byTooltip('Quitar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(montaje.banco.servidor.cuantas('DELETE', '/vehicle-types/t0'), 1);
    expect(sinIds(montaje.tipos), [
      <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 3.0},
    ]);

    await desmontar(tester);
  });

  testWidgets('un tipo que creó OTRA persona mientras el cajón estaba abierto '
      'NO se borra por no estar en él', (tester) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);
    await abrirCajon(tester);

    // Otra persona crea `moto` mientras este cajon sigue abierto.
    montaje.tipos.add(<String, Object?>{
      'id': 'ajeno',
      'nombre': 'moto',
      'costoKmUsd': 0.4,
      'activo': true,
    });

    await tester.enterText(find.widgetWithText(TextField, '0.9'), '1.0');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(montaje.banco.servidor.cuantas('DELETE', '/vehicle-types/ajeno'), 0);
    expect(montaje.tipos.map((t) => t['nombre']), ['furgoneta', 'moto']);

    await desmontar(tester);
  });

  // (d) EDICION AJENA. El costo por km es el que cotiza el domicilio: que una
  // fila que NO tocaste pise el cambio de otra persona es un numero creible y
  // equivocado.
  testWidgets('lo que OTRA persona cambió mientras el cajón estaba abierto NO '
      'se pisa por una fila que esta persona no tocó', (tester) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
        <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 3.0},
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);
    await abrirCajon(tester);

    // Otra persona sube la furgoneta a 1.5 con este cajon ya abierto.
    montaje.tipos.firstWhere((t) => t['nombre'] == 'furgoneta')['costoKmUsd'] =
        1.5;

    // Esta persona sólo toca la rastra.
    await tester.enterText(find.widgetWithText(TextField, '3.0'), '4.0');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(escrituras(montaje.banco), ['PATCH /vehicle-types/t1']);
    expect(
      sinIds(montaje.tipos),
      [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 1.5},
        <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 4.0},
      ],
      reason: 'la furgoneta volvio a 0.9: se pisó el cambio de la otra persona',
    );

    await desmontar(tester);
  });

  // (a) UN TIPO RETIRADO NO SE ENSEÑA. Lo retiro el servidor porque un camion lo
  // usa; seguir ofreciendolo es ofrecer algo que se quito a proposito.
  testWidgets('un tipo RETIRADO no sale ni en el cajón ni en el desplegable '
      '«Tipo» de la ficha', (tester) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
        <String, Object?>{
          'nombre': 'vieja',
          'costoKmUsd': 2.0,
          'activo': false,
        },
      ],
      // Un camion lo usa (por eso esta retirado y no borrado): sin esto el
      // nombre no se volveria a sembrar aunque `conocidos` lo olvidara.
      vehiculos: const [
        <String, Object?>{
          'id': 'v1',
          'name': 'Camión #1',
          'type': 'vieja',
          'capacity': 1000,
          'status': 'available',
        },
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);

    await abrirCajon(tester);
    expect(find.widgetWithText(TextField, 'furgoneta'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'vieja'),
      findsNothing,
      reason: 'el cajón enseña un tipo retirado',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, 'Agregar Vehículo').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Tipo'),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is DropdownMenuItem<String> && w.value == 'furgoneta',
      ),
      findsWidgets,
      reason: 'sin el tipo vivo en el desplegable esta prueba no mira nada',
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is DropdownMenuItem<String> && w.value == 'vieja',
      ),
      findsNothing,
      reason: 'el desplegable «Tipo» de la ficha ofrece un tipo retirado',
    );

    await desmontar(tester);
  });

  // (b) ESCRIBIR EN EL CAJON EL NOMBRE DE UN RETIRADO LO REACTIVA. Antes: POST,
  // 409 «ya existe» y un tipo que el desplegable no enseñaba: callejon sin salida.
  Future<({Banco banco, List<Map<String, Object?>> tipos})> reactivarEnElCajon(
    WidgetTester tester, {
    String? costo,
  }) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
        <String, Object?>{
          'nombre': 'vieja',
          'costoKmUsd': 2.0,
          'activo': false,
        },
      ],
      vehiculos: const [
        <String, Object?>{
          'id': 'v1',
          'name': 'Camión #1',
          'type': 'vieja',
          'capacity': 1000,
          'status': 'available',
        },
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);
    await abrirCajon(tester);

    await tester.tap(find.text('Agregar tipo'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre').last,
      'vieja',
    );
    if (costo != null) {
      await tester.enterText(
        find.widgetWithText(TextField, 'Costo/km (USD)').last,
        costo,
      );
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    return montaje;
  }

  testWidgets('escribir el nombre de un RETIRADO lo reactiva: PATCH `activo`, '
      'sin POST ni 409, y NO manda el costo si la fila no trae uno', (
    tester,
  ) async {
    final montaje = await reactivarEnElCajon(tester);

    expect(escrituras(montaje.banco), ['PATCH /vehicle-types/t1']);
    expect(
      cuerpos(montaje.banco, 'PATCH'),
      [
        <String, Object?>{'activo': true},
      ],
      reason:
          'reactivar sin costo escrito manda SÓLO `activo`: mandar '
          '`costoKmUsd: null` borra el costo que el retirado tenia guardado',
    );
    final vieja = montaje.tipos.firstWhere((t) => t['nombre'] == 'vieja');
    expect(vieja['activo'], isTrue, reason: 'no se reactivó');
    expect(
      vieja['costoKmUsd'],
      2.0,
      reason: 'el costo guardado del retirado se perdió al reactivarlo',
    );
    expect(find.text('Tipos guardados.'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('reactivar un RETIRADO con costo escrito SÍ manda el costo', (
    tester,
  ) async {
    final montaje = await reactivarEnElCajon(tester, costo: '4.5');

    expect(escrituras(montaje.banco), ['PATCH /vehicle-types/t1']);
    expect(cuerpos(montaje.banco, 'PATCH'), [
      <String, Object?>{'activo': true, 'costoKmUsd': 4.5},
    ]);
    final vieja = montaje.tipos.firstWhere((t) => t['nombre'] == 'vieja');
    expect(vieja['activo'], isTrue);
    expect(vieja['costoKmUsd'], 4.5);

    await desmontar(tester);
  });

  // (g) Lo mismo pero desde la FICHA, por `+ Crear tipo nuevo…`.
  testWidgets('«+ Crear tipo nuevo…» con el nombre de un RETIRADO lo reactiva '
      '(PATCH, sin POST ni 409) y queda ELEGIDO', (tester) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
        <String, Object?>{
          'nombre': 'vieja',
          'costoKmUsd': 2.0,
          'activo': false,
        },
      ],
      vehiculos: const [
        <String, Object?>{
          'id': 'v1',
          'name': 'Camión #1',
          'type': 'vieja',
          'capacity': 1000,
          'status': 'available',
        },
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Agregar Vehículo').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Tipo'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Crear tipo nuevo…').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del tipo'),
      'vieja',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Crear tipo'));
    await tester.pumpAndSettle();

    expect(
      escrituras(montaje.banco),
      ['PATCH /vehicle-types/t1'],
      reason:
          'un POST con el nombre de un retirado da 409 «ya existe» mientras el '
          'desplegable no lo enseña: callejon sin salida',
    );
    expect(cuerpos(montaje.banco, 'PATCH'), [
      <String, Object?>{'activo': true},
    ]);
    expect(
      find.text('Ya existe un tipo de vehículo con ese nombre'),
      findsNothing,
    );
    final vieja = montaje.tipos.firstWhere((t) => t['nombre'] == 'vieja');
    expect(vieja['activo'], isTrue);
    expect(vieja['costoKmUsd'], 2.0);

    // QUEDA ELEGIDO: el vehiculo que se guarda ahora lleva ese tipo.
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del Vehículo *'),
      'Camión #9',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(FichaVehiculo),
        matching: find.widgetWithText(FilledButton, 'Agregar Vehículo'),
      ),
    );
    await tester.pumpAndSettle();
    final alta = cuerpos(montaje.banco, 'POST')
        .whereType<Map<String, Object?>>()
        .where((c) => c['name'] == 'Camión #9')
        .single;
    expect(
      alta['type'],
      'vieja',
      reason: 'el tipo reactivado no quedó elegido',
    );

    await desmontar(tester);
  });

  // La pareja de (g): si el nombre ya se VE en el catalogo, no hay nada que crear.
  testWidgets(
    '«+ Crear tipo nuevo…» con el nombre de uno que YA se ve no manda '
    'nada, no da 409, y lo elige',
    (tester) async {
      final montaje = montarServidor(
        tipos: [
          <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
        ],
      );
      addTearDown(montaje.banco.cerrar);
      await pintar(tester, montaje.banco);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Agregar Vehículo').first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Tipo'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Crear tipo nuevo…').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre del tipo'),
        'furgoneta',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Crear tipo'));
      await tester.pumpAndSettle();

      expect(
        escrituras(montaje.banco),
        isEmpty,
        reason: 'ya estaba en el catalogo: un POST daria 409 «ya existe»',
      );
      expect(
        find.text('Ya existe un tipo de vehículo con ese nombre'),
        findsNothing,
      );
      // Elegido: el vehiculo que se guarda lleva ese tipo.
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre del Vehículo *'),
        'Camión #9',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(FichaVehiculo),
          matching: find.widgetWithText(FilledButton, 'Agregar Vehículo'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        cuerpos(
          montaje.banco,
          'POST',
        ).whereType<Map<String, Object?>>().single['type'],
        'furgoneta',
      );

      await desmontar(tester);
    },
  );

  // Cazados por la auditoria del 14/10/2026, a nivel de la accion (sin pantalla).
  //
  // `abiertos` es lo que el cajon tenia AL ABRIRSE (con sus ids): de ahi sale lo
  // que se quito y lo que esta persona cambio.
  group('guardarTipos, sin pantalla', () {
    const van = TipoDeVehiculo(id: 't0', nombre: 'van', costoKmUsd: 1.0);
    const rastra = TipoDeVehiculo(id: 't1', nombre: 'rastra', costoKmUsd: 3.0);

    test(
      'quitar un tipo y volver a escribir el MISMO nombre lo deja existiendo',
      () async {
        final montaje = montarServidor(
          tipos: [
            <String, Object?>{'nombre': 'van', 'costoKmUsd': 1.0},
          ],
        );
        addTearDown(montaje.banco.cerrar);
        final control = controlDe(montaje.banco);

        // El cajon tenia `t0`; se quita y se escribe otra fila `van`, sin id.
        final bien = await control.guardarTipos(
          const [TipoDeVehiculo(nombre: 'van', costoKmUsd: 1.0)],
          abiertos: const [van],
        );

        expect(bien, isTrue);
        expect(
          sinIds(montaje.tipos),
          [
            <String, Object?>{'nombre': 'van', 'costoKmUsd': 1.0},
          ],
          reason:
              'Comparar con la foto de ANTES de borrar encontraba el `van` viejo, '
              'no mandaba nada y el tipo se quedaba sin existir.',
        );
      },
    );

    test('quitar un tipo EN USO (el servidor lo RETIRA) y volver a escribirlo '
        'lo reactiva, sin POST ni 409', () async {
      final montaje = montarServidor(
        tipos: [
          <String, Object?>{'nombre': 'van', 'costoKmUsd': 1.0},
        ],
        usados: {'t0'},
      );
      addTearDown(montaje.banco.cerrar);

      final bien = await controlDe(montaje.banco).guardarTipos(
        const [TipoDeVehiculo(nombre: 'van', costoKmUsd: 1.0)],
        abiertos: const [van],
      );

      expect(bien, isTrue, reason: avisoDe(montaje.banco)?.texto);
      expect(escrituras(montaje.banco), [
        'DELETE /vehicle-types/t0',
        'PATCH /vehicle-types/t0',
      ]);
      expect(montaje.tipos.single['activo'], isTrue);
      expect(montaje.tipos.single['costoKmUsd'], 1.0);
    });

    test('una fila nueva cuyo nombre YA existe y está vivo (lo creó otra '
        'persona, o es un reintento) no se repite', () async {
      final montaje = montarServidor(
        tipos: [
          <String, Object?>{'nombre': 'moto', 'costoKmUsd': 0.4},
        ],
      );
      addTearDown(montaje.banco.cerrar);

      final bien = await controlDe(montaje.banco).guardarTipos(const [
        TipoDeVehiculo(nombre: 'moto', costoKmUsd: 0.4),
      ], abiertos: const []);

      expect(bien, isTrue, reason: avisoDe(montaje.banco)?.texto);
      expect(
        escrituras(montaje.banco),
        isEmpty,
        reason:
            'ya existia: un POST daria 409 y un PATCH `activo` tocaria una '
            'fila que nadie retiro',
      );
    });

    test('crearTipo con el nombre de uno VIVO no lo «reactiva»: sale el 409 '
        'del servidor', () async {
      final montaje = montarServidor(
        tipos: [
          <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
        ],
      );
      addTearDown(montaje.banco.cerrar);

      final bien = await controlDe(
        montaje.banco,
      ).crearTipo(const TipoDeVehiculo(nombre: 'furgoneta', costoKmUsd: 5.0));

      expect(bien, isFalse);
      expect(
        avisoDe(montaje.banco)!.texto,
        'Ya existe un tipo de vehículo con ese nombre',
      );
      expect(escrituras(montaje.banco), ['POST /vehicle-types']);
      expect(montaje.tipos.single['costoKmUsd'], 0.9);
    });

    test('un reintento tras un fallo a medias termina: el 404 del DELETE es '
        '«ya estaba»', () async {
      final montaje = montarServidor(
        tipos: [
          <String, Object?>{'nombre': 'van', 'costoKmUsd': 1.0},
          <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 3.0},
        ],
      );
      addTearDown(montaje.banco.cerrar);
      // La primera vuelta ya borro `t0` y se cayo antes del PATCH: se simula
      // dejando el servidor como estaria.
      montaje.tipos.removeWhere((t) => t['id'] == 't0');

      final bien = await controlDe(montaje.banco).guardarTipos(
        const [TipoDeVehiculo(id: 't1', nombre: 'rastra', costoKmUsd: 9.0)],
        abiertos: const [van, rastra],
      );

      expect(
        bien,
        isTrue,
        reason: 'el DELETE de lo ya borrado dio 404 y paró todo',
      );
      expect(sinIds(montaje.tipos), [
        <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 9.0},
      ]);
    });

    // (e) El DELETE sólo traga el 404. Cualquier otro «no» es un fallo y se dice.
    for (final codigo in [403, 409]) {
      test('un DELETE que contesta $codigo NO se traga: devuelve false y el '
          'aviso dice el motivo', () async {
        final motivo = 'motivo literal del $codigo';
        final montaje = montarServidor(
          tipos: [
            <String, Object?>{'nombre': 'van', 'costoKmUsd': 1.0},
            <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 3.0},
          ],
          forzar: (p) => p.metodo == 'DELETE'
              ? RespuestaFalsa(codigo, <String, Object?>{'error': motivo})
              : null,
        );
        addTearDown(montaje.banco.cerrar);

        final bien = await controlDe(montaje.banco)
            .guardarTipos(const [rastra], abiertos: const [van, rastra]);

        expect(bien, isFalse, reason: 'se tragó un $codigo y dijo «guardado»');
        final aviso = avisoDe(montaje.banco)!;
        expect(aviso.esFallo, isTrue);
        expect(aviso.texto, motivo);
        expect(aviso.texto, isNot(contains('Tipos guardados')));
        expect(montaje.tipos.map((t) => t['nombre']), ['van', 'rastra']);
      });
    }

    // (f) FALLO A MEDIAS: no es atomico, y «no se guardó nada» seria mentira.
    test('FALLO A MEDIAS: quitar `a` y renombrar `b` al nombre de `c` (409) '
        'dice «Se guardó sólo una parte», no «no se guardó nada»; y arreglado '
        'el nombre, el reintento termina', () async {
      final montaje = montarServidor(
        tipos: [
          <String, Object?>{'nombre': 'a', 'costoKmUsd': 1.0},
          <String, Object?>{'nombre': 'b', 'costoKmUsd': 2.0},
          <String, Object?>{'nombre': 'c', 'costoKmUsd': 3.0},
        ],
      );
      addTearDown(montaje.banco.cerrar);
      final control = controlDe(montaje.banco);
      const abiertos = [
        TipoDeVehiculo(id: 't0', nombre: 'a', costoKmUsd: 1.0),
        TipoDeVehiculo(id: 't1', nombre: 'b', costoKmUsd: 2.0),
        TipoDeVehiculo(id: 't2', nombre: 'c', costoKmUsd: 3.0),
      ];

      final bien = await control.guardarTipos(const [
        TipoDeVehiculo(id: 't1', nombre: 'c', costoKmUsd: 2.0),
        TipoDeVehiculo(id: 't2', nombre: 'c', costoKmUsd: 3.0),
      ], abiertos: abiertos);

      expect(bien, isFalse);
      expect(montaje.tipos.map((t) => t['nombre']), [
        'b',
        'c',
      ], reason: 'el DELETE de `a` ya entró: el servidor ya perdió ese tipo');
      final aviso = avisoDe(montaje.banco)!;
      expect(aviso.esFallo, isTrue);
      expect(aviso.texto, contains('Se guardó sólo una parte'));
      expect(
        aviso.texto,
        contains('Ya existe un tipo de vehículo con ese nombre'),
      );
      expect(
        aviso.texto.toLowerCase(),
        isNot(contains('no se guardó nada')),
        reason:
            'sí se guardó algo (el borrado de `a`): decir «no se guardó nada» '
            'es mentir y manda a repetir lo que ya está hecho',
      );

      // Se corrige el nombre y se vuelve a guardar CON EL MISMO CAJON (mismos
      // `abiertos`): el DELETE de `a` ahora da 404 y es «ya estaba».
      final reintento = await control.guardarTipos(const [
        TipoDeVehiculo(id: 't1', nombre: 'b2', costoKmUsd: 2.0),
        TipoDeVehiculo(id: 't2', nombre: 'c', costoKmUsd: 3.0),
      ], abiertos: abiertos);

      expect(reintento, isTrue, reason: avisoDe(montaje.banco)?.texto);
      expect(sinIds(montaje.tipos), [
        <String, Object?>{'nombre': 'b2', 'costoKmUsd': 2.0},
        <String, Object?>{'nombre': 'c', 'costoKmUsd': 3.0},
      ]);
    });

    // (h) La pareja de (f): si NADA entró, el aviso de «sólo una parte» no sale.
    test('un 5xx en el PATCH sin nada aplicado antes sigue diciendo «no se '
        'guardó nada»', () async {
      final montaje = montarServidor(
        tipos: [
          <String, Object?>{'nombre': 'van', 'costoKmUsd': 1.0},
          <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 3.0},
        ],
        forzar: (p) => p.metodo == 'PATCH'
            ? RespuestaFalsa(500, const <String, Object?>{'error': 'boom'})
            : null,
      );
      addTearDown(montaje.banco.cerrar);

      final bien = await controlDe(montaje.banco).guardarTipos(
        const [
          TipoDeVehiculo(id: 't0', nombre: 'van', costoKmUsd: 2.0),
          rastra,
        ],
        abiertos: const [van, rastra],
      );

      expect(bien, isFalse);
      final aviso = avisoDe(montaje.banco)!;
      expect(aviso.esFallo, isTrue);
      expect(aviso.texto, contains('no se guardó nada'));
      expect(
        aviso.texto,
        isNot(contains('sólo una parte')),
        reason: 'no entró ningún cambio: decir «sólo una parte» es mentir',
      );
      expect(sinIds(montaje.tipos), [
        <String, Object?>{'nombre': 'van', 'costoKmUsd': 1.0},
        <String, Object?>{'nombre': 'rastra', 'costoKmUsd': 3.0},
      ]);
    });
  });

  testWidgets('si el servidor rechaza, NO dice «guardado» y el cajón sigue', (
    tester,
  ) async {
    final banco = Banco((p) async {
      if (p.metodo == 'POST') {
        return RespuestaFalsa(409, const <String, Object?>{
          'error': 'Ya existe un tipo de vehículo con ese nombre',
        });
      }
      if (p.ruta.contains('/vehicle-types')) {
        return RespuestaFalsa(200, const <Object?>[]);
      }
      if (p.ruta.endsWith('/settings')) {
        return RespuestaFalsa(200, const <String, Object?>{'cupRate': 320});
      }
      return RespuestaFalsa(200, const <Object?>[]);
    });
    addTearDown(banco.cerrar);
    await pintar(tester, banco);
    await abrirCajon(tester);

    await tester.tap(find.text('Agregar tipo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'moto');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Tipos guardados.'), findsNothing);
    expect(
      find.text('Ya existe un tipo de vehículo con ese nombre'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'moto'), findsOneWidget);

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------------
  // 3. La mezcla, sin montar nada
  // ---------------------------------------------------------------------------

  group('los tipos que se enseñan', () {
    const deAjustes = [TipoDeVehiculo(nombre: 'furgoneta', costoKmUsd: 0.9)];

    test('son los de ajustes MAS los que usan los vehiculos', () {
      final tipos = TipoDeVehiculo.paraElCajon(
        deAjustes: deAjustes,
        vehiculos: const [
          VehiculoDeLaApi(
            id: 'v1',
            nombre: 'a',
            capacidad: 1000,
            estado: 'available',
            tipo: 'truck',
            costoKmUsd: 1.65,
          ),
          VehiculoDeLaApi(
            id: 'v2',
            nombre: 'b',
            capacidad: 1000,
            estado: 'available',
            tipo: 'furgoneta',
          ),
        ],
      );
      // `furgoneta` NO se repite: ya estaba en ajustes.
      expect(tipos.map((t) => t.nombre).toList(), ['furgoneta', 'truck']);
      // El costo sembrado sale de un vehiculo de ese tipo que ya lo tenga.
      expect(tipos.last.costoKmUsd, 1.65);
      // Y el de ajustes se respeta, no se pisa con el del vehiculo.
      expect(tipos.first.costoKmUsd, 0.9);
    });

    test('sin costo en ningun vehiculo se deja VACIO, no en cero', () {
      final tipos = TipoDeVehiculo.paraElCajon(
        deAjustes: const [],
        vehiculos: const [
          VehiculoDeLaApi(
            id: 'v1',
            nombre: 'a',
            capacidad: 1000,
            estado: 'available',
            tipo: 'truck',
          ),
        ],
      );
      // Un cero guardado se lee como «el kilometro es gratis» — un numero
      // creible y equivocado. Un hueco se ve y se rellena.
      expect(tipos.single.nombre, 'truck');
      expect(tipos.single.costoKmUsd, isNull);
    });

    test('un vehiculo sin tipo no siembra nada', () {
      expect(
        TipoDeVehiculo.paraElCajon(
          deAjustes: deAjustes,
          vehiculos: const [
            VehiculoDeLaApi(
              id: 'v1',
              nombre: 'a',
              capacidad: 1000,
              estado: 'available',
            ),
            VehiculoDeLaApi(
              id: 'v2',
              nombre: 'b',
              capacidad: 1000,
              estado: 'available',
              tipo: '  ',
            ),
          ],
        ).map((t) => t.nombre).toList(),
        ['furgoneta'],
      );
    });
  });
}
