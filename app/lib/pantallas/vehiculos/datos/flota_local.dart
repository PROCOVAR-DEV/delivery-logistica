/// LA FLOTA EN EL APARATO — issue 14 de Amado, 16/10/2026.
///
/// «Por la experiencia de hoy, los vehículos no le funcionan offline: no se le
/// muestran ni los tipos, ni los distribuidores, ni los vehículos. No pudo crearlos
/// tampoco. Eso es en la aplicación de Windows.»
///
/// ## La causa
///
/// Las tres pantallas (Vehículos, Tipos de vehículo, Distribuidores) estaban escritas
/// como «sólo con conexión»: pedían la lista al servidor y no tenían cola. Sin red
/// salía «Sin conexión», y los tipos ni siquiera se bajaban (la tabla `vehicle_types`
/// existía y no la llenaba nadie). Contra `CLAUDE.md` §1: la APK y el escritorio
/// trabajan la jornada entera sin señal.
///
/// ## Lo que hace esto
///
/// SOLO EN LA APK Y EL ESCRITORIO (la web sigue directa al servidor):
///  * **lee** de la base local (la bajada trae camiones, tipos y distribuidores);
///  * **escribe** en la base local y encola el apunte con un id `local-…`, como las
///    rutas. La comprobación que se puede hacer aquí se hace con las MISMAS palabras
///    del servidor, para que el «no» no llegue horas después a la bandeja.
///
/// Un camión nuevo apunta a su tipo por NOMBRE (así lo manda la API), no por id, así
/// que no depende de que el tipo nuevo ya haya subido: la cola respeta el orden.
library;

import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/cola/cola_salida.dart';
import '../../../nucleo/cola/provisionales.dart';
import '../../../nucleo/red/fallos.dart';
import '../../distribuidores/datos/repositorio_distribuidores.dart';
import 'vehiculo_api.dart';

/// El «no» de la sucursal que falta, LETRA POR LETRA el del servidor
/// (`msgTipoSinSucursal`, `tipos_vehiculo.go`).
const msgTipoSinSucursal =
    'Elige una sucursal arriba para crear el tipo: los tipos de vehículo son de cada sucursal.';
const msgDistribuidorSinSucursal =
    'Elige una sucursal arriba para crear al distribuidor: es de cada sucursal.';
const msgVehiculoConRutas =
    'No se puede eliminar este vehículo porque tiene rutas asociadas, incluso históricas. '
    'Márcalo como inactivo para impedir que se use en nuevas rutas.';
const msgVehiculoCompartido =
    'Este vehículo es compartido por todas las sucursales: '
    'sólo un SUPER ADMIN o un DESARROLLADOR puede modificarlo, darlo de baja o eliminarlo.';
const msgDistribuidorRepetido =
    'Ya existe un distribuidor con ese nombre en esta sucursal';
const msgTipoRepetido = 'Ya existe un tipo de vehículo con ese nombre';

Rechazo _no(String mensaje) => Rechazo(400, mensaje);

class FlotaLocal {
  FlotaLocal(
    this._base,
    this._cola, {
    required this.sucursalMirada,
    required this.veTodas,
  });

  final BaseLocal _base;
  final ColaDeSalida _cola;

  /// La sucursal elegida arriba, o `null` (= todas / la propia).
  final String? Function() sucursalMirada;

  /// ¿Esta persona ve las ocho sucursales (SUPER ADMIN, DESARROLLADOR)? Esas no
  /// tienen una sola sucursal a la que atribuir un alta hecha sin red, así que sus
  /// altas van al servidor (ver `RepositorioVehiculos`).
  final Future<bool> Function() veTodas;

  // ---------------------------------------------------------------------------
  // LECTURA
  // ---------------------------------------------------------------------------

  /// El nombre del tipo sale del tipo (por `vehicle_type_id`) y, si no esta bajado
  /// (un camion compartido), del `type` que mando el servidor: renombrar un tipo no
  /// mueve el `updated_at` de sus camiones, asi que ese texto puede estar viejo.
  ///
  /// La flota de la sucursal que se mira, con los camiones compartidos (sin
  /// sucursal) como los sirve el servidor. Cada camión lleva su ruta abierta y
  /// cuántas rutas y pedidos tiene EN ESTE APARATO.
  Stream<List<VehiculoDeLaApi>> vehiculos({String? sucursal}) {
    final filtro = (sucursal == null || sucursal.isEmpty)
        ? ''
        : 'WHERE v.branch_id = ?1 OR v.branch_id IS NULL';
    return _base
        .customSelect(
          '''
SELECT v.id, v.name, coalesce(vt.nombre, v.tipo_nombre) AS tipo_nombre, v.plate, v.capacity, v.costo_km_usd,
       v.usar_para_domicilio, v.status, v.is_active, v.notes,
       (SELECT count(*) FROM routes r WHERE r.vehicle_id = v.id) AS rutas,
       (SELECT count(*) FROM orders o JOIN routes r ON r.id = o.route_id
         WHERE r.vehicle_id = v.id) AS pedidos,
       ra.id AS ruta_id, ra.name AS ruta_name, ra.route_code AS ruta_code,
       ra.status AS ruta_status
FROM vehicles v
LEFT JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
LEFT JOIN routes ra ON ra.id = (
  SELECT r.id FROM routes r
  WHERE r.vehicle_id = v.id AND r.status NOT IN ('completed', 'cancelled')
  ORDER BY (r.status = 'in_progress') DESC, r.delivery_date IS NULL,
           r.delivery_date ASC, r.created_at ASC
  LIMIT 1)
$filtro
ORDER BY v.created_at DESC, v.name ASC
''',
          variables: [if (filtro.isNotEmpty) Variable<String>(sucursal!)],
          readsFrom: {_base.vehicles, _base.vehicleTypes, _base.routes, _base.orders},
        )
        .watch()
        .map(
          (filas) => [
            for (final f in filas)
              VehiculoDeLaApi(
                id: f.read<String>('id'),
                nombre: f.read<String>('name'),
                capacidad: f.read<double>('capacity'),
                estado: f.read<String>('status'),
                activo: f.read<bool>('is_active'),
                tipo: f.readNullable<String>('tipo_nombre'),
                placa: f.readNullable<String>('plate'),
                costoKmUsd: f.readNullable<double>('costo_km_usd'),
                usarParaDomicilio: f.read<bool>('usar_para_domicilio'),
                notas: f.readNullable<String>('notes'),
                rutas: f.read<int>('rutas'),
                pedidos: f.read<int>('pedidos'),
                rutaActiva: f.readNullable<String>('ruta_id') == null
                    ? null
                    : RutaDelVehiculo(
                        id: f.readNullable<String>('ruta_id'),
                        nombre: f.readNullable<String>('ruta_name'),
                        codigo: f.readNullable<String>('ruta_code'),
                        estado: f.readNullable<String>('ruta_status'),
                      ),
              ),
          ],
        );
  }

  /// Los tipos de la sucursal que se mira, retirados incluidos (como
  /// `GET /api/vehicle-types`). Sin sucursal elegida: quien ve las ocho sólo ve los
  /// «de todas»; quien tiene una sola, todos los que le bajaron.
  Stream<List<TipoDeVehiculo>> tipos({String? sucursal}) {
    final consulta = _base.select(_base.vehicleTypes)
      ..orderBy([(t) => OrderingTerm.asc(t.nombre)]);
    if (sucursal != null && sucursal.isNotEmpty) {
      consulta.where((t) => t.branchId.equals(sucursal));
    }
    return consulta.watch().asyncMap((filas) async {
      final sinElegir = sucursal == null || sucursal.isEmpty;
      final soloDeTodas = sinElegir && await veTodas();
      return [
        for (final t in filas)
          if (!soloDeTodas || t.branchId == null)
            TipoDeVehiculo(
              id: t.id,
              nombre: t.nombre,
              costoKmUsd: t.costoKmUsd,
              activo: t.activo,
            ),
      ];
    });
  }

  /// La tasa de los ajustes del aparato, para el ayudante del costo por km.
  Stream<double> cupRate() => (_base.select(_base.settings)..limit(1))
      .watch()
      .map((f) => f.isEmpty ? 320 : f.first.cupRate);

  /// Los distribuidores de la sucursal que se mira, retirados incluidos, con
  /// cuántas rutas del aparato los usan.
  Stream<List<DistribuidorDelServidor>> distribuidores({String? sucursal}) {
    final filtro = (sucursal == null || sucursal.isEmpty)
        ? ''
        : 'WHERE d.branch_id = ?1';
    return _base
        .customSelect(
          '''
SELECT d.id, d.nombre, d.activo, d.branch_id, b.name AS sucursal,
       (SELECT count(*) FROM routes r WHERE r.distribuidor_id = d.id) AS rutas
FROM distribuidores d LEFT JOIN branches b ON b.id = d.branch_id
$filtro
ORDER BY d.nombre ASC
''',
          variables: [if (filtro.isNotEmpty) Variable<String>(sucursal!)],
          readsFrom: {_base.distribuidores, _base.branches, _base.routes},
        )
        .watch()
        .map(
          (filas) => [
            for (final f in filas)
              DistribuidorDelServidor(
                id: f.read<String>('id'),
                nombre: f.read<String>('nombre'),
                activo: f.read<bool>('activo'),
                sucursalId: f.readNullable<String>('branch_id'),
                sucursal: f.readNullable<String>('sucursal'),
                rutas: f.read<int>('rutas'),
              ),
          ],
        );
  }

  Future<List<DistribuidorDelServidor>> listarDistribuidores() =>
      distribuidores(sucursal: sucursalMirada()).first;

  // ---------------------------------------------------------------------------
  // ESCRITURA: fila local + apunte, en UNA transaccion
  // ---------------------------------------------------------------------------

  /// A QUE SUCURSAL SE ATRIBUYE UN ALTA hecha en el aparato: la que se mira, o la
  /// única que el aparato tiene bajada. `null` = no se sabe cuál (quien ve las ocho
  /// y no eligió ninguna).
  Future<String?> sucursalDeAlta() async {
    final mirada = sucursalMirada();
    if (mirada != null && mirada.isNotEmpty) return mirada;
    final propias = await _base.select(_base.branches).get();
    return propias.length == 1 ? propias.single.id : null;
  }

  Future<void> crearVehiculo(DatosVehiculo d) async {
    final nombre = d.nombre.trim();
    if (nombre.isEmpty) throw _no('Vehicle name is required');
    _numerosValidos(d.capacidad, d.costoKmUsd);
    final sucursal = await sucursalDeAlta();
    final tipo = d.tipo ?? 'truck';
    await _tipoExiste(tipo, sucursal);
    final id = Provisionales.nuevoId();
    await _base.transaction(() async {
      if (d.usarParaDomicilio == true) await _desmarcarReferencia(sucursal, id);
      await _base
          .into(_base.vehicles)
          .insert(
            VehiclesCompanion.insert(
              id: id,
              name: nombre,
              tipoNombre: Value(tipo),
              plate: Value(_vacioANulo(d.placa)),
              capacity: Value(d.capacidad ?? 1000),
              costoKmUsd: Value(d.costoKmUsd),
              usarParaDomicilio: Value(d.usarParaDomicilio == true),
              status: Value(d.estado ?? 'available'),
              isActive: Value(d.activo ?? true),
              notes: Value(_vacioANulo(d.notas)),
              branchId: Value(sucursal),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
      await _cola.encolar(
        metodo: 'POST',
        ruta: '/vehicles',
        cuerpo: d.aJson(),
        provisional: id,
      );
    });
  }

  Future<void> editarVehiculo(String id, DatosVehiculo d) async {
    final v = await _vehiculo(id);
    await _puedeTocar(v);
    if (d.nombre.trim().isEmpty) throw _no('Vehicle name is required');
    _numerosValidos(d.capacidad, d.costoKmUsd);
    final tipo = d.tipo;
    if (tipo != null && tipo != v.tipoNombre) {
      await _tipoExiste(tipo, v.branchId);
    }
    await _base.transaction(() async {
      if (d.usarParaDomicilio == true) await _desmarcarReferencia(v.branchId, id);
      await (_base.update(_base.vehicles)..where((x) => x.id.equals(id))).write(
        VehiclesCompanion(
          name: Value(d.nombre.trim()),
          tipoNombre: tipo == null ? const Value.absent() : Value(tipo),
          plate: Value(_vacioANulo(d.placa)),
          capacity: d.capacidad == null
              ? const Value.absent()
              : Value(d.capacidad!),
          costoKmUsd: Value(d.costoKmUsd),
          usarParaDomicilio: d.usarParaDomicilio == null
              ? const Value.absent()
              : Value(d.usarParaDomicilio!),
          status: d.estado == null ? const Value.absent() : Value(d.estado!),
          isActive: d.activo == null ? const Value.absent() : Value(d.activo!),
          notes: Value(_vacioANulo(d.notas)),
        ),
      );
      await _cola.encolar(
        metodo: 'PATCH',
        ruta: '/vehicles/$id',
        cuerpo: d.aJson(),
      );
    });
  }

  Future<void> cambiarVehiculo(String id, Map<String, Object?> cambios) async {
    final v = await _vehiculo(id);
    await _puedeTocar(v);
    await _base.transaction(() async {
      if (cambios['usarParaDomicilio'] == true) {
        await _desmarcarReferencia(v.branchId, id);
      }
      await (_base.update(_base.vehicles)..where((x) => x.id.equals(id))).write(
        VehiclesCompanion(
          status: cambios['status'] is String
              ? Value(cambios['status']! as String)
              : const Value.absent(),
          usarParaDomicilio: cambios['usarParaDomicilio'] is bool
              ? Value(cambios['usarParaDomicilio']! as bool)
              : const Value.absent(),
        ),
      );
      await _cola.encolar(metodo: 'PATCH', ruta: '/vehicles/$id', cuerpo: cambios);
    });
  }

  Future<void> eliminarVehiculo(String id) async {
    final v = await _vehiculo(id);
    await _puedeTocar(v);
    final rutas = await (_base.select(_base.routes)
          ..where((r) => r.vehicleId.equals(id)))
        .get();
    if (rutas.isNotEmpty) throw _no(msgVehiculoConRutas);
    await _base.transaction(() async {
      await (_base.delete(_base.vehicles)..where((x) => x.id.equals(id))).go();
      await _cola.encolar(
        metodo: 'DELETE',
        ruta: '/vehicles/$id',
        cuerpo: const <String, Object?>{},
      );
    });
  }

  Future<void> crearTipo(TipoDeVehiculo tipo) async {
    final sucursal = await sucursalDeAlta();
    if (sucursal == null) throw _no(msgTipoSinSucursal);
    final nombre = tipo.nombre.trim();
    if (nombre.isEmpty) throw _no('El nombre del tipo es obligatorio');
    _numerosValidos(null, tipo.costoKmUsd);
    final existente = await (_base.select(_base.vehicleTypes)
          ..where((t) => t.branchId.equals(sucursal) & t.nombre.equals(nombre)))
        .getSingleOrNull();
    if (existente != null && existente.activo) throw _no(msgTipoRepetido);
    await _base.transaction(() async {
      if (existente != null) {
        // Un retirado que se vuelve a escribir se REACTIVA, como hace la pantalla
        // con conexion: sin esto chocaria con su nombre.
        await (_base.update(_base.vehicleTypes)
              ..where((t) => t.id.equals(existente.id)))
            .write(
          VehicleTypesCompanion(
            activo: const Value(true),
            costoKmUsd: tipo.costoKmUsd == null
                ? const Value.absent()
                : Value(tipo.costoKmUsd),
          ),
        );
        await _cola.encolar(
          metodo: 'PATCH',
          ruta: '/vehicle-types/${existente.id}',
          cuerpo: <String, Object?>{
            'activo': true,
            'costoKmUsd': ?tipo.costoKmUsd,
          },
        );
        return;
      }
      final id = Provisionales.nuevoId();
      await _base
          .into(_base.vehicleTypes)
          .insert(
            VehicleTypesCompanion.insert(
              id: id,
              nombre: nombre,
              costoKmUsd: Value(tipo.costoKmUsd),
              branchId: Value(sucursal),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
      await _cola.encolar(
        metodo: 'POST',
        ruta: '/vehicle-types',
        cuerpo: <String, Object?>{'nombre': nombre, 'costoKmUsd': tipo.costoKmUsd},
        provisional: id,
      );
    });
  }

  Future<void> cambiarTipo(String id, Map<String, Object?> cambios) async {
    final nombre = (cambios['nombre'] as String?)?.trim();
    if (cambios.containsKey('nombre') && (nombre == null || nombre.isEmpty)) {
      throw _no('El nombre del tipo es obligatorio');
    }
    if (cambios['costoKmUsd'] is num) {
      _numerosValidos(null, (cambios['costoKmUsd']! as num).toDouble());
    }
    await _base.transaction(() async {
      await (_base.update(_base.vehicleTypes)..where((t) => t.id.equals(id)))
          .write(
        VehicleTypesCompanion(
          nombre: nombre == null ? const Value.absent() : Value(nombre),
          costoKmUsd: cambios.containsKey('costoKmUsd')
              ? Value((cambios['costoKmUsd'] as num?)?.toDouble())
              : const Value.absent(),
          activo: cambios['activo'] is bool
              ? Value(cambios['activo']! as bool)
              : const Value.absent(),
        ),
      );
      await _cola.encolar(
        metodo: 'PATCH',
        ruta: '/vehicle-types/$id',
        cuerpo: cambios,
      );
    });
  }

  /// Borra si ningun camion lo usa, y si no lo RETIRA: lo que decide el servidor.
  Future<void> quitarTipo(String id) async {
    final t = await (_base.select(_base.vehicleTypes)
          ..where((x) => x.id.equals(id)))
        .getSingleOrNull();
    if (t == null) return; // «ya estaba borrado»
    final lo = await (_base.select(_base.vehicles)
          ..where((v) => v.vehicleTypeId.equals(id) | v.tipoNombre.equals(t.nombre)))
        .get();
    await _base.transaction(() async {
      if (lo.isEmpty) {
        await (_base.delete(_base.vehicleTypes)..where((x) => x.id.equals(id))).go();
      } else {
        await (_base.update(_base.vehicleTypes)..where((x) => x.id.equals(id)))
            .write(const VehicleTypesCompanion(activo: Value(false)));
      }
      await _cola.encolar(
        metodo: 'DELETE',
        ruta: '/vehicle-types/$id',
        cuerpo: const <String, Object?>{},
      );
    });
  }

  Future<DistribuidorDelServidor> crearDistribuidor(String crudo) async {
    final sucursal = await sucursalDeAlta();
    if (sucursal == null) throw _no(msgDistribuidorSinSucursal);
    final nombre = crudo.trim().split(RegExp(r'\s+')).join(' ');
    if (nombre.isEmpty) throw _no('El nombre del distribuidor es obligatorio');
    await _sinRepetir(sucursal, nombre, salvo: null);
    final id = Provisionales.nuevoId();
    await _base.transaction(() async {
      await _base
          .into(_base.distribuidores)
          .insert(
            DistribuidoresCompanion.insert(
              id: id,
              nombre: nombre,
              branchId: Value(sucursal),
              updatedAt: Value(DateTime.now()),
            ),
          );
      await _cola.encolar(
        metodo: 'POST',
        ruta: '/distribuidores',
        cuerpo: <String, Object?>{'nombre': nombre},
        provisional: id,
      );
    });
    return DistribuidorDelServidor(
      id: id,
      nombre: nombre,
      activo: true,
      sucursalId: sucursal,
    );
  }

  Future<void> cambiarDistribuidor(
    String id, {
    String? nombre,
    bool? activo,
  }) async {
    final d = await (_base.select(_base.distribuidores)
          ..where((x) => x.id.equals(id)))
        .getSingleOrNull();
    if (d == null) throw const Rechazo(404, 'No encontrado');
    String? limpio;
    if (nombre != null) {
      limpio = nombre.trim().split(RegExp(r'\s+')).join(' ');
      if (limpio.isEmpty) throw _no('El nombre del distribuidor es obligatorio');
      await _sinRepetir(d.branchId, limpio, salvo: id);
    }
    await _base.transaction(() async {
      await (_base.update(_base.distribuidores)..where((x) => x.id.equals(id)))
          .write(
        DistribuidoresCompanion(
          nombre: limpio == null ? const Value.absent() : Value(limpio),
          activo: activo == null ? const Value.absent() : Value(activo),
        ),
      );
      await _cola.encolar(
        metodo: 'PATCH',
        ruta: '/distribuidores/$id',
        cuerpo: <String, Object?>{'nombre': ?limpio, 'activo': ?activo},
      );
    });
  }

  Future<ResultadoDeQuitar> quitarDistribuidor(String id) async {
    final usado = await (_base.select(_base.routes)
          ..where((r) => r.distribuidorId.equals(id)))
        .get();
    await _base.transaction(() async {
      if (usado.isEmpty) {
        await (_base.delete(_base.distribuidores)..where((x) => x.id.equals(id)))
            .go();
      } else {
        await (_base.update(_base.distribuidores)..where((x) => x.id.equals(id)))
            .write(const DistribuidoresCompanion(activo: Value(false)));
      }
      await _cola.encolar(
        metodo: 'DELETE',
        ruta: '/distribuidores/$id',
        cuerpo: const <String, Object?>{},
      );
    });
    return usado.isEmpty
        ? ResultadoDeQuitar.borrado
        : ResultadoDeQuitar.retirado;
  }

  // ---------------------------------------------------------------------------
  // Las comprobaciones, con las palabras del servidor
  // ---------------------------------------------------------------------------

  Future<Vehiculo> _vehiculo(String id) async {
    final v = await (_base.select(_base.vehicles)..where((x) => x.id.equals(id)))
        .getSingleOrNull();
    if (v == null) throw const Rechazo(404, 'Not found');
    return v;
  }

  /// Un camion COMPARTIDO (sin sucursal) solo lo toca quien ve las ocho
  /// (`puedeTocarElCamion` del servidor).
  Future<void> _puedeTocar(Vehiculo v) async {
    if (v.branchId != null) return;
    if (!await veTodas()) throw _no(msgVehiculoCompartido);
  }

  void _numerosValidos(double? capacidad, double? costo) {
    if (capacidad != null && !(capacidad > 0 && capacidad.isFinite)) {
      throw _no(
        "La capacidad del camión tiene que ser un número de kilos mayor que cero, y llegó '$capacidad'",
      );
    }
    if (costo != null && !(costo >= 0 && costo.isFinite)) {
      throw _no(
        "El costo por kilómetro no puede ser negativo, y llegó '$costo'. "
        'Déjalo vacío si todavía no se sabe: un hueco se ve y se rellena.',
      );
    }
  }

  /// El tipo tiene que existir y ser de la sucursal del camion (`tipoPorNombre`).
  Future<void> _tipoExiste(String nombre, String? sucursal) async {
    final hay = await (_base.select(_base.vehicleTypes)
          ..where((t) => t.nombre.equals(nombre)))
        .get();
    if (hay.isEmpty) throw _no("No existe el tipo de vehículo '$nombre'");
    if (!hay.any((t) => t.branchId == sucursal)) {
      throw _no("El tipo '$nombre' no es de la sucursal de este camión");
    }
  }

  /// Un solo camion de referencia por sucursal, en la misma transaccion.
  Future<void> _desmarcarReferencia(String? sucursal, String salvo) =>
      (_base.update(_base.vehicles)..where(
            (v) =>
                v.usarParaDomicilio.equals(true) &
                v.id.equals(salvo).not() &
                (sucursal == null
                    ? v.branchId.isNull()
                    : v.branchId.equals(sucursal)),
          ))
          .write(const VehiclesCompanion(usarParaDomicilio: Value(false)));

  Future<void> _sinRepetir(String? sucursal, String nombre, {String? salvo}) async {
    final todos = await _base.select(_base.distribuidores).get();
    final choca = todos.any(
      (d) =>
          d.branchId == sucursal &&
          d.id != salvo &&
          d.nombre.trim().toLowerCase() == nombre.toLowerCase(),
    );
    if (choca) throw const Rechazo(409, msgDistribuidorRepetido);
  }

  static String? _vacioANulo(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}
