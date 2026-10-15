import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// LA PRUEBA QUE NO PUEDE FALTAR.
///
/// Arrastrar una tarjeta sin conexión tiene que hacer tres cosas y ninguna más:
/// escribir en la base del aparato, dejar el apunte en la cola y **no llamar a
/// nadie**. Y lo que quede escrito tiene que seguir ahí después de cerrar la
/// aplicación y volver a abrirla, que es lo que distingue «guarda en memoria»
/// de «vive en el aparato» (PLAN.md §5.1, pasos 2 y 6).
///
/// Por eso la base va a un FICHERO y no a memoria: una base en memoria pasaría
/// esta prueba sin decir nada de lo que de verdad se quiere comprobar.
void main() {
  late Directory carpeta;
  late File fichero;
  late ServidorFalso servidor;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('tablero_sin_red');
    fichero = File('${carpeta.path}/reparto.sqlite');
    servidor = ServidorFalso(
      // Sin red: cualquier petición que se escape falla como en la calle. Y
      // además se apunta, que es lo que se comprueba.
      (peticion) async => null,
    );
  });

  tearDown(() async {
    if (carpeta.existsSync()) await carpeta.delete(recursive: true);
  });

  BaseLocal abrirBase() => BaseLocal.con(NativeDatabase(fichero));

  ProviderContainer montar(BaseLocal base) {
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.invalido'))
      ..httpClientAdapter = servidor;
    return ProviderContainer.test(
      overrides: [
        // Sin `onDispose`: la base la cierra la prueba, que es justo lo que
        // quiere simular.
        baseProvider.overrideWith((ref) => base),
        // SIN ESPERAS. El tablero pide la foto del servidor al abrirse y aquí no
        // hay servidor: con los reintentos por defecto son 1+4+10 segundos por
        // prueba —quince en total— quemados esperando a una red que no existe, y
        // `comprobar.sh` corta el `flutter test` entero a 300 s.
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

  test('arrastrar sin conexión: se escribe aquí, va a la cola, no llama a nadie '
      'y sobrevive a cerrar y reabrir la aplicación', () async {
    // ---- Por la mañana, con red: bajó el día. -------------------------
    var base = abrirBase();
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    // Cada uno de una hora de factura distinta, del más viejo al más reciente:
    // es el orden de «sin colocar» desde el 14/10/2026 (antes, por cercanía).
    await sembrarPedido(
      base,
      id: 'p-cerca',
      aGrados: 0.01,
      peso: 120,
      facturaAt: DateTime(2026, 9, 14, 8),
    );
    await sembrarPedido(
      base,
      id: 'p-medio',
      aGrados: 0.05,
      peso: 80,
      facturaAt: DateTime(2026, 9, 14, 9),
    );
    await sembrarPedido(
      base,
      id: 'p-lejos',
      aGrados: 0.40,
      peso: 60,
      facturaAt: DateTime(2026, 9, 14, 10),
    );

    var contenedor = montar(base);
    var tablero = await contenedor.read(tableroProvider.future);
    expect(tablero.sinColocar.total, 3);
    expect(tablero.sinColocar.pedidos.map((p) => p.pedidoId).toList(), [
      'p-cerca',
      'p-medio',
      'p-lejos',
    ], reason: 'el de la factura más vieja primero');

    // ---- Por la tarde, en el patio y sin señal. -----------------------
    //
    // Se olvida lo que se haya intentado hasta aquí: al ABRIR el tablero sí se
    // le pide la foto al servidor —con conexión manda el servidor y no la
    // copia—, y eso es correcto. Lo que esta prueba vigila es el GESTO: que
    // arrastrar no hable con nadie. Sin este borrado se estaría midiendo la
    // apertura y no el arrastre.
    servidor.vistas.clear();

    final mando = contenedor.read(tableroProvider.notifier);
    final columnaId = await mando.crearColumna('Centro');
    // El id lo pone el APARATO, aquí mismo y sin señal: un UUIDv7 definitivo.
    // No hay nada que sustituir después, y subirlo dos veces no crea dos zonas.
    expect(
      columnaId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );

    await mando.colocar(pedidoId: 'p-cerca', columnaId: columnaId);
    await mando.colocar(pedidoId: 'p-medio', columnaId: columnaId);

    // 1. EL GESTO NO LLAMA A NADIE. Arrastrar escribe aquí y va a la cola.
    //
    // Sobre TODAS las peticiones y no sólo las de `/board`: se probó a filtrar por
    // esa ruta y no cazaba nada que no cazara ya el `clear()` de arriba — lo único
    // que hacía era dejar de vigilar todo lo demás, como un `/auth/refresh` que un
    // gesto disparara sin querer.
    expect(
      servidor.vistas,
      isEmpty,
      reason: 'arrastrar escribe aquí; la subida va por detrás',
    );

    // 2. Se ve movido, ya.
    tablero = await contenedor.read(tableroProvider.future);
    expect(tablero.columnas.single.pedidos, 2);
    expect(tablero.columnas.single.pesoKg, 200);
    expect(tablero.sinColocar.total, 1);
    expect(
      tablero.deColumna(columnaId).map((t) => t.pedido.pedidoId).toList(),
      ['p-cerca', 'p-medio'],
    );

    // 3. Y está en la cola, en orden, con el cuerpo del contrato.
    final cola = ColaDeSalida(base);
    var lote = await cola.lote();
    expect(lote.map((a) => a.ruta).toList(), [
      '/board/columns?branchId=$sucursalStg',
      '/board/placements/p-cerca',
      '/board/placements/p-medio',
    ]);
    expect(lote.first.provisional, columnaId);
    expect(jsonDecode(lote[1].cuerpo), {'columnaId': columnaId, 'posicion': 1});
    final claves = lote.map((a) => a.clave).toList();

    // ---- Se cierra la aplicación del todo y se vuelve a abrir. --------
    contenedor.dispose();
    await base.close();

    base = abrirBase();
    contenedor = montar(base);
    tablero = await contenedor.read(tableroProvider.future);

    // Las tarjetas siguen donde se dejaron…
    expect(tablero.columnas.single.nombre, 'Centro');
    expect(tablero.columnas.single.pedidos, 2);
    expect(
      tablero.deColumna(columnaId).map((t) => t.pedido.pedidoId).toList(),
      ['p-cerca', 'p-medio'],
    );
    expect(tablero.sinColocar.pedidos.single.pedidoId, 'p-lejos');

    // …y la cola también, con las mismas claves: nada se subió dos veces ni
    // se perdió por el camino.
    lote = await ColaDeSalida(base).lote();
    expect(lote.map((a) => a.clave).toList(), claves);
    expect(lote.every((a) => a.estado == EstadoApunte.pendiente), isTrue);
    expect(servidor.vistas, isEmpty);

    await base.close();
  });

  test('cuando la columna sube, su «local-…» se sustituye en la cola y en el '
      'tablero', () async {
    final base = abrirBase();
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'p1');
    final contenedor = montar(base);
    await contenedor.read(tableroProvider.future);

    final mando = contenedor.read(tableroProvider.notifier);
    final provisional = await mando.crearColumna('Vista Alegre');
    await mando.colocar(pedidoId: 'p1', columnaId: provisional);

    // Sube la creación de la columna y el servidor devuelve el id de verdad.
    final cola = ColaDeSalida(base);
    final creacion = (await cola.lote()).first;
    await cola.resolver(
      creacion.clave,
      const ResultadoApunte(
        estado: EstadoResultado.aplicado,
        id: 'col-de-verdad',
      ),
    );

    // Sin esto, las colocaciones que van detrás irían a una columna que no
    // existe en ningún sitio y se perderían justo después de subirse.
    final pendientes = await cola.lote();
    expect(pendientes.single.ruta, '/board/placements/p1');
    expect(jsonDecode(pendientes.single.cuerpo), {
      'columnaId': 'col-de-verdad',
      'posicion': 1,
    });

    // Y la pantalla deja de enseñar el provisional.
    await contenedor.read(tableroProvider.notifier).refrescar();
    final tablero = contenedor.read(tableroProvider).value!;
    expect(tablero.columnas.single.id, 'col-de-verdad');
    // La ZONA subió, pero su pedido no: sigue «sin subir», y eso es lo correcto.
    // El prefijo `local-…` de antes no sabía contar esto —con el id de verdad ya
    // puesto daba la zona por entregada con cinco pedidos todavía en la cola—, y
    // por eso la marca pasó a salir de la cola y no del id.
    expect(
      tablero.columnas.single.faltaPorSubir,
      isTrue,
      reason: 'le queda la colocación de p1 por subir',
    );
    expect(tablero.deColumna('col-de-verdad').single.pedido.pedidoId, 'p1');

    await base.close();
  });

  test('sin sucursal elegida no se enseña «todo»', () async {
    final base = abrirBase();
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    final dio = Dio()..httpClientAdapter = servidor;
    final contenedor = ProviderContainer.test(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        // SIN ESPERAS. El tablero pide la foto del servidor al abrirse y aquí no
        // hay servidor: con los reintentos por defecto son 1+4+10 segundos por
        // prueba —quince en total— quemados esperando a una red que no existe, y
        // `comprobar.sh` corta el `flutter test` entero a 300 s.
        clienteApiProvider.overrideWithValue(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
        almacenSesionProvider.overrideWithValue(AlmacenEnMemoria()),
      ],
    );

    final tablero = await contenedor.read(tableroProvider.future);
    // No se enseña «todo», que es lo que parecería razonable y sería lo peor:
    // un tablero con las diez sucursales mezcladas ordenaría los pedidos de
    // Holguín por su distancia al almacén de Santiago.
    expect(tablero.problema, 'Elige una sucursal para ver su tablero');
    expect(tablero.columnas, isEmpty);
    expect(tablero.sinColocar.pedidos, isEmpty);
    await base.close();
  });
}
