import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_de_los_dos_lados.dart';
import 'apoyo.dart';

/// LA MISMA TARJETA MOVIDA EN LOS DOS LADOS A LA VEZ.
///
/// Probado a mano contra producción el 17/09/2026, con un teléfono sin señal y
/// un navegador abierto: el móvil coloca el pedido X en su zona; la web, al
/// mismo tiempo, coloca el MISMO pedido X en otra. Al volver la señal **gana el
/// último que escribe** y no se pierde nada — pero **nadie se entera de que hubo
/// un choque**.
///
/// Esto no lo cubría ninguna prueba. Lo que se fija aquí es lo que hace HOY:
///
///  * la tarjeta **no se duplica** — un pedido, un sitio;
///  * la tarjeta **no se pierde** — no acaba en «sin colocar» ni desaparecida;
///  * **queda donde la puso el último que escribió**, sin importar quién fuera;
///  * y el choque **no se dice en ningún sitio**. Eso último es un `expect` a
///    propósito: si algún día se avisa, esta prueba se cae y la decisión se toma
///    mirándola, no por accidente.
///
/// La forma es la del `CLAUDE.md` §3-ter: se monta con el estado de la MAÑANA y
/// todo lo demás —el gesto sin señal, lo que hace la web, la subida y la
/// bajada— llega DESPUÉS, sin volver a montar nada.
void main() {
  late Directory carpeta;
  late File fichero;
  late BaseLocal base;
  late ServidorDeLosDosLados servidor;

  const zonaNorte = '0199a1b2-0000-7000-8000-00000000norte';
  const zonaSur = '0199a1b2-0000-7000-8000-000000000sur';

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('los_dos_lados');
    fichero = File('${carpeta.path}/reparto.sqlite');
    base = BaseLocal.con(NativeDatabase(fichero));
    await aparatoYaDeAlta(base);

    servidor = ServidorDeLosDosLados(sucursalId: sucursalStg)
      // Las dos zonas ya existen arriba: las hizo alguien por la mañana, con
      // señal. Ninguna de las dos «nació aquí».
      ..laWebCreaZona(zonaNorte, 'Norte')
      ..laWebCreaZona(zonaSur, 'Sur');

    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'p-x', aGrados: 0.01);
    await sembrarPedido(base, id: 'p-y', aGrados: 0.05);
    await sembrarPedido(base, id: 'p-z', aGrados: 0.40);
  });

  tearDown(() async {
    await base.close();
    if (carpeta.existsSync()) await carpeta.delete(recursive: true);
  });

  ProviderContainer montar() {
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
      ..httpClientAdapter = servidor.adaptador;
    return ProviderContainer.test(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        // SIN ESPERAS: sin señal los reintentos por defecto son quince segundos
        // por prueba quemados esperando a una red que no existe.
        clienteApiProvider.overrideWithValue(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: sucursalStg,
            ),
          ),
        ),
        sucursalDeLaSesionProvider.overrideWithValue(sucursalStg),
      ],
    );
  }

  /// La cola sale por el otro `Dio` —otra dirección base, `/sync`— y contra el
  /// mismo servidor, igual que en el aparato.
  Subida subirLaCola() {
    final dio = Dio(BaseOptions(baseUrl: 'https://sync.prueba'))
      ..httpClientAdapter = servidor.adaptador;
    return Subida(
      cliente: ClienteApi(dio: dio, esperas: const <Duration>[]),
      cola: ColaDeSalida(base),
      aparato: IdentidadDelAparato(base),
      base: base,
      quienEsta: () async => 'logistico',
    );
  }

  Future<int> cuantasVecesPuesto(String pedidoId) async {
    final fila = await base
        .customSelect(
          'SELECT count(*) AS n FROM ${EsquemaTablero.colocaciones} '
          'WHERE order_id = ?1',
          variables: [Variable<String>(pedidoId)],
        )
        .getSingle();
    return fila.read<int>('n');
  }

  test('el móvil sin señal y la web mueven la MISMA tarjeta: gana el último que '
      'escribe, no se duplica, no se pierde — y nadie se entera del choque', () async {
    // ---- Por la mañana, con señal: el tablero baja del servidor. --------
    final contenedor = montar();
    addTearDown(contenedor.dispose);

    var tablero = await contenedor.read(tableroProvider.future);
    expect(tablero.columnas.map((c) => c.nombre).toList(), [
      'Norte',
      'Sur',
    ], reason: 'las dos zonas vienen de arriba');
    expect(tablero.sinColocar.total, 3);

    // ---- Por la tarde, en el patio y sin señal. -------------------------
    servidor.hayRed = false;
    servidor.adaptador.vistas.clear();

    final mando = contenedor.read(tableroProvider.notifier);
    await mando.colocar(pedidoId: 'p-x', columnaId: zonaNorte);

    expect(
      servidor.adaptador.vistas,
      isEmpty,
      reason: 'arrastrar escribe aquí; la subida va por detrás',
    );
    tablero = await contenedor.read(tableroProvider.future);
    expect(tablero.deColumna(zonaNorte).single.pedido.pedidoId, 'p-x');

    // ---- A LA MISMA HORA, en la oficina, alguien lo mueve en la web. ----
    //
    // La web no tiene cola ni base local: su gesto entra en el servidor en el
    // momento. El teléfono no se entera de nada.
    expect(
      servidor.laWebColoca('p-x', zonaSur),
      isNull,
      reason: 'para el servidor p-x está libre: lo del móvil no ha subido',
    );

    // ---- Vuelve la señal y sube la cola. -------------------------------
    servidor.hayRed = true;
    expect(await subirLaCola().ciclo(), 1);
    expect(servidor.aplicados, ['/board/placements/p-x']);

    // EL ÚLTIMO QUE ESCRIBE GANA, y aquí el último es el móvil: su gesto es de
    // por la tarde pero llega ahora, encima de lo que dejó la web. El servidor
    // no compara horas ni avisa de nada.
    expect(servidor.puestas['p-x']!.columnaId, zonaNorte);
    expect(servidor.puestas['p-x']!.por, 'aparato');

    // ---- Y se baja la foto, ya sin nada pendiente que pisar. ------------
    await contenedor.read(tableroProvider.notifier).bajarDelServidor();
    tablero = await contenedor.read(tableroProvider.future);

    // 1. NO SE DUPLICA. Un pedido, un sitio: la tabla lo sujeta con la clave
    //    primaria, y el tablero lo enseña una sola vez.
    expect(await cuantasVecesPuesto('p-x'), 1);
    expect(tablero.columnas.map((c) => c.pedidos).toList(), [
      1,
      0,
    ], reason: 'una tarjeta en Norte y ninguna en Sur, no una en cada una');

    // 2. NO SE PIERDE. Ni se cayó a «sin colocar» ni desapareció.
    expect(
      tablero.deColumna(zonaNorte).map((t) => t.pedido.pedidoId).toList(),
      ['p-x'],
    );
    expect(tablero.deColumna(zonaSur), isEmpty);
    expect(tablero.sinColocar.pedidos.map((p) => p.pedidoId).toList(), [
      'p-y',
      'p-z',
    ], reason: 'p-x sigue puesto: no volvió a la mitad izquierda');

    // 3. QUÉ QUEDA: lo del móvil, que fue el último en escribir. Lo de la web
    //    se sobreescribió sin dejar rastro.
    final puesta = await base
        .customSelect(
          'SELECT column_id, colocado_por FROM ${EsquemaTablero.colocaciones} '
          'WHERE order_id = ?1',
          variables: [Variable<String>('p-x')],
        )
        .getSingle();
    expect(puesta.read<String>('column_id'), zonaNorte);
    expect(
      puesta.readNullable<String>('colocado_por'),
      'aparato',
      reason:
          'la fila que queda es la que trajo la foto del servidor con el '
          'gesto del móvil dentro, no la que el móvil escribió sin señal',
    );

    // 4. Y NADIE SE ENTERA DEL CHOQUE.
    //
    // No es un descuido de la prueba: es lo que pasa hoy y hace falta dejarlo
    // escrito. El apunte se aplicó —no hay rechazo—, así que ni la bandeja, ni
    // la franja de la web, ni el cartel del tablero tienen nada que decir. El
    // gesto de la web se deshizo en silencio y quien lo hizo sigue viendo su
    // pantalla vieja hasta que la recargue.
    //
    // Si algún día esto se avisa, esta prueba se cae aquí y hay que venir a
    // cambiarla A PROPÓSITO.
    expect(
      await ColaDeSalida(base).lote(),
      isEmpty,
      reason: 'la cola subió entera',
    );
    final rechazados = await (base.select(
      base.apuntes,
    )..where((a) => a.estado.equalsValue(EstadoApunte.rechazado))).get();
    expect(
      rechazados,
      isEmpty,
      reason: 'HOY un choque de los dos lados no deja rechazo ninguno',
    );
    expect(
      contenedor.read(tableroProvider.notifier).porQueNoSeRefresca,
      isNull,
      reason: 'HOY el tablero no dice nada de que la web tocó esa tarjeta',
    );
  });

  test('la web escribe DESPUÉS de que suba el móvil: entonces gana la web y el '
      'aparato se corrige solo, sin dejar una tarjeta fantasma', () async {
    // La otra mitad de «gana el último»: si no se comprueba en los dos
    // sentidos, una prueba en verde podría estar diciendo «gana el móvil
    // siempre», que es otra regla y no la que hay.
    final contenedor = montar();
    addTearDown(contenedor.dispose);

    var tablero = await contenedor.read(tableroProvider.future);
    expect(tablero.sinColocar.total, 3);

    // Sin señal, el móvil lo pone en Norte…
    servidor.hayRed = false;
    await contenedor
        .read(tableroProvider.notifier)
        .colocar(pedidoId: 'p-x', columnaId: zonaNorte);

    // …sube en cuanto vuelve la señal…
    servidor.hayRed = true;
    expect(await subirLaCola().ciclo(), 1);
    expect(servidor.puestas['p-x']!.columnaId, zonaNorte);

    // …y AHORA la web lo mueve a Sur, con todo ya subido.
    expect(servidor.laWebColoca('p-x', zonaSur), isNull);

    await contenedor.read(tableroProvider.notifier).bajarDelServidor();
    tablero = await contenedor.read(tableroProvider.future);

    expect(await cuantasVecesPuesto('p-x'), 1, reason: 'sigue sin duplicarse');
    expect(tablero.deColumna(zonaSur).map((t) => t.pedido.pedidoId).toList(), [
      'p-x',
    ], reason: 'la web escribió la última: manda ella');
    expect(
      tablero.deColumna(zonaNorte),
      isEmpty,
      reason:
          'la tarjeta no se queda además en Norte: una tarjeta fantasma en '
          'dos zonas es un pedido cargado dos veces',
    );
    expect(tablero.sinColocar.total, 2);
  });

  test('la bajada NO pisa lo que el móvil hizo sin señal, aunque la web haya '
      'movido esa misma tarjeta', () async {
    // Esto es el «no se pierde por ninguna circunstancia» del pliego, en el
    // caso peor: la foto del servidor dice otra cosa y alguien pulsa
    // actualizar ANTES de que la cola haya subido.
    final contenedor = montar();
    addTearDown(contenedor.dispose);

    await contenedor.read(tableroProvider.future);

    servidor.hayRed = false;
    await contenedor
        .read(tableroProvider.notifier)
        .colocar(pedidoId: 'p-x', columnaId: zonaNorte);

    // La web, a la vez, lo pone en Sur. Y vuelve la señal, pero **sin subir la
    // cola**: quien está delante le da a actualizar.
    servidor.laWebColoca('p-x', zonaSur);
    servidor.hayRed = true;

    final mando = contenedor.read(tableroProvider.notifier);
    await mando.bajarDelServidor();

    final tablero = await contenedor.read(tableroProvider.future);
    expect(
      tablero.deColumna(zonaNorte).single.pedido.pedidoId,
      'p-x',
      reason:
          'la foto del servidor habría movido la tarjeta a Sur y borrado el '
          'trabajo de la tarde: no se baja mientras quede algo sin subir',
    );
    expect(
      mando.porQueNoSeRefresca,
      '1 cambio sin subir',
      reason: 'y se DICE por qué no se actualizó, o parece que no hizo nada',
    );

    // La cola sigue entera: negarse a bajar no descarta nada.
    final cola = await ColaDeSalida(base).lote();
    expect(cola.single.ruta, '/board/placements/p-x');
  });
}
