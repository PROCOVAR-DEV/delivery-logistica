import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';
import 'package:reparto/pantallas/vehiculos/estado/estado_vehiculos.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo_vehiculos.dart';

/// **La prueba que no se negocia.**
///
/// Vehiculos es de las pantallas que sólo funcionan con conexion. Lo que aqui se
/// comprueba no es que salga un cartel bonito: es que sin red **no queda rastro
/// de un guardado que no ocurrio**. Ni un apunte en la cola, ni una fila en la
/// base, ni un mensaje de exito.
///
/// Si alguien anade un dia un `cola.encolar(...)` en el camino de guardar, este
/// fichero se pone rojo. Ese es su trabajo.
void main() {
  late Banco banco;

  setUp(() => banco = Banco.sinRed());
  tearDown(() => banco.cerrar());

  const camionNuevo = DatosVehiculo(
    nombre: 'Camión #9',
    tipo: 'truck',
    capacidad: 1000,
    estado: 'available',
  );

  test('crear sin conexión NO finge que guardó', () async {
    final control = banco.contenedor.read(controlVehiculosProvider.notifier);

    final guardo = await control.crear(camionNuevo);

    // 1. Contesta que NO.
    expect(guardo, isFalse);

    // 2. Lo dice, y dice lo unico que importa: que no se guardo nada.
    final aviso = banco.contenedor.read(controlVehiculosProvider);
    expect(aviso, isNotNull);
    expect(aviso!.esFallo, isTrue);
    expect(aviso.texto, contains('Sin conexión'));
    expect(aviso.texto, contains('no se guardó nada'));

    // 3. **La cola sigue vacia.** Esto es el corazon de la prueba: un vehiculo
    //    encolado se subiria solo mas tarde y nadie sabria de donde salio.
    expect(await banco.base.cuantosPendientes(), 0);
    expect(await banco.base.select(banco.base.apuntes).get(), isEmpty);

    // 4. Y no se escribio una fila local que luego la bajada tendria que
    //    desmentir.
    expect(await banco.base.select(banco.base.vehicles).get(), isEmpty);
  });

  test('editar, eliminar, marcar disponible y domicilio: lo mismo', () async {
    final control = banco.contenedor.read(controlVehiculosProvider.notifier);

    expect(await control.editar('v1', camionNuevo), isFalse);
    expect(await control.eliminar('v1'), isFalse);
    expect(await control.marcarDisponible('v1'), isFalse);
    expect(await control.usarParaDomicilio('v1'), isFalse);
    expect(
      await control.guardarTipos(const [
        TipoDeVehiculo(nombre: 'Camión'),
      ], abiertos: const []),
      isFalse,
    );

    // Cinco acciones, cero apuntes. Ninguna se guardo «para luego».
    expect(await banco.base.cuantosPendientes(), 0);
  });

  test(
    'la lista sin conexión sale como FalloDeRed, no como lista vacía',
    () async {
      // Son cosas distintas y pintarlas igual hace creer que la flota se borro.
      // Lo que la pantalla hace con esto se comprueba en `pantalla_test.dart`.
      await expectLater(
        banco.contenedor.read(repositorioVehiculosProvider).listar(),
        throwsA(isA<FalloDeRed>()),
      );
    },
  );

  test(
    'un rechazo del servidor se enseña LITERAL, y tampoco se encola',
    () async {
      final conRechazo = Banco(
        (p) async => RespuestaFalsa(400, {'error': 'Vehicle name is required'}),
      );
      addTearDown(conRechazo.cerrar);

      final guardo = await conRechazo.contenedor
          .read(controlVehiculosProvider.notifier)
          .crear(const DatosVehiculo(nombre: ''));

      expect(guardo, isFalse);
      expect(
        conRechazo.contenedor.read(controlVehiculosProvider)!.texto,
        'Vehicle name is required',
      );
      // Un `Rechazo` no se reintenta jamas y tampoco se guarda: el servidor ya
      // dijo que no.
      expect(await conRechazo.base.cuantosPendientes(), 0);
      expect(conRechazo.servidor.cuantas('POST', '/vehicles'), 1);
    },
  );

  test('con conexión sí guarda, y sólo entonces dice que guardó', () async {
    final conRed = Banco((p) async => RespuestaFalsa(201, {'id': 'v9'}));
    addTearDown(conRed.cerrar);

    final guardo = await conRed.contenedor
        .read(controlVehiculosProvider.notifier)
        .crear(camionNuevo);

    expect(guardo, isTrue);
    final aviso = conRed.contenedor.read(controlVehiculosProvider)!;
    expect(aviso.esFallo, isFalse);
    expect(aviso.texto, 'Vehículo agregado.');
    // El cuerpo va con los nombres del contrato.
    final cuerpo =
        conRed.servidor.vistas.single.cuerpo! as Map<String, Object?>;
    expect(cuerpo['name'], 'Camión #9');
    expect(cuerpo['capacity'], 1000);
    expect(cuerpo['status'], 'available');
  });
}
