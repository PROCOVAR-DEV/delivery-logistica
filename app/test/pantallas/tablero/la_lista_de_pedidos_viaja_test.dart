import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_de_los_dos_lados.dart';
import 'apoyo.dart';

/// LA LISTA DE PEDIDOS VIAJA, Y LO QUE SE CAE SE DICE — 28/09/2026.
///
/// Son los dos fallos encadenados de ese día, y el segundo es el que impidió
/// ver el primero. Los dos son el §4: **nada se descarta en silencio.**
///
/// ## 1 · El apunte de armar no mandaba los pedidos que el aparato eligió
///
/// `RepositorioTablero.armarRuta` encolaba `{nombre, vehiculoId, optimizar,
/// deliveryDate}` y nada más, con un comentario al lado diciendo que la lista sí
/// viajaba —un comentario que miente, que aquí es peor que ninguno—. Sin ella el
/// servidor arma la zona con **lo que ÉL tenga puesto en ese momento**, y un
/// apunte hecho sin señal llega horas después:
///
///  * si mientras tanto la web metió una tarjeta en esa zona, sube a la ruta un
///    pedido que **nadie cargó en ese camión**;
///  * si se llevó una, la ruta nace sin ella, el servidor devuelve SU peso, y la
///    bajada lo escribe encima del que calculó el aparato. Lo que se vio: la
///    cabecera con el peso de uno y las dos paradas debajo.
///
/// ## 2 · Los descartados se tiraban en silencio
///
/// El servidor contesta quién se cayó y por qué —bien, con nombre y motivo— y
/// `ColaDeSalida.resolver` sólo miraba `resultado.id`. Por eso lo primero no se
/// vio el día que pasó: la ruta salió con menos pedidos de los que el logístico
/// puso y no hubo ni un aviso en ningún sitio.
///
/// ## La forma de estas pruebas
///
/// En pareja, que es lo que pide el §3-quinquies: una que el aviso salga cuando
/// de verdad se cayó alguien, y otra que **NO salga** cuando no se cayó nadie.
/// Un aviso que sale siempre deja de leerse, y entonces tampoco se lee el día
/// que importa.
void main() {
  late Directory carpeta;
  late BaseLocal base;
  late ServidorDeLosDosLados servidor;
  late RelojFalso reloj;

  const zona = '0199a1b2-0000-7000-8000-00000000vista';
  final laHoraDelPatio = DateTime(2026, 9, 28, 8, 5);

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('lista_viaja');
    base = BaseLocal.con(
      NativeDatabase(File('${carpeta.path}/reparto.sqlite')),
    );
    reloj = RelojFalso(laHoraDelPatio);
    await aparatoYaDeAlta(base);

    servidor = ServidorDeLosDosLados(sucursalId: sucursalStg)
      ..laWebCreaZona(zona, 'Vista', vehiculoId: 'v1');

    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarCamion(base, id: 'v1', capacidad: 5000);

    // Los DOS del logístico, con el peso que hace los 516,5 kg del incidente.
    await sembrarPedido(
      base,
      id: 'p1',
      operacion: 'X-2992',
      cliente: 'Ana Pérez',
      aGrados: 0.01,
      peso: 258.25,
    );
    await sembrarPedido(
      base,
      id: 'p2',
      operacion: 'X-3001',
      cliente: 'Luis Mora',
      aGrados: 0.02,
      peso: 258.25,
    );
    for (final (id, folio, cliente) in const [
      ('p1', 'X-2992', 'Ana Pérez'),
      ('p2', 'X-3001', 'Luis Mora'),
      ('p3', 'X-3100', 'Marta Ruiz'),
    ]) {
      servidor.folios[id] = folio;
      servidor.clientes[id] = cliente;
    }
    servidor
      ..laWebColoca('p1', zona, posicion: 1)
      ..laWebColoca('p2', zona, posicion: 2);
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
      ],
    );
  }

  Subida subirLaCola() {
    final dio = Dio(BaseOptions(baseUrl: 'https://sync.prueba'))
      ..httpClientAdapter = servidor.adaptador;
    return Subida(
      cliente: ClienteApi(dio: dio, esperas: const <Duration>[]),
      cola: ColaDeSalida(base, reloj: reloj.leer),
      aparato: IdentidadDelAparato(base),
      base: base,
      quienEsta: () async => 'logistico',
    );
  }

  /// Los avisos de «subió con menos de lo que pusiste» que esperan a que alguien
  /// los lea. Es lo mismo que mira la franja de estado y el cajón.
  Future<List<Apunte>> avisos() =>
      ColaDeSalida(base, reloj: reloj.leer).descartesSinLeer().first;

  test('la APK arma sin señal y la web mete OTRA tarjeta en la zona: la ruta '
      'del servidor lleva los DOS que eligió el aparato, y el tercero se dice', () async {
    final contenedor = montar();
    addTearDown(contenedor.dispose);

    final tablero = await contenedor.read(tableroProvider.future);
    expect(tablero.columnas.single.pedidos, 2);

    // ---- El patio, sin señal: se arma la zona con sus dos. --------------
    servidor.hayRed = false;
    final rutaId = await contenedor
        .read(tableroProvider.notifier)
        .armarRuta(zona);

    // Lo que el aparato escribió en su base: dos paradas y su peso.
    final local = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();
    expect(local.totalWeight, 516.5);
    expect(
      await (base.select(base.orders)..where((o) => o.routeId.isNotNull()))
          .get()
          .then((l) => (l.map((o) => o.id).toList())..sort()),
      ['p1', 'p2'],
    );

    // ---- Mientras tanto, en la oficina: entra un tercero en esa zona. ---
    await sembrarPedido(
      base,
      id: 'p3',
      operacion: 'X-3100',
      cliente: 'Marta Ruiz',
      aGrados: 0.03,
      peso: 90,
    );
    servidor.laWebColoca('p3', zona, posicion: 3);

    // ---- Vuelve la señal y sube el apunte, horas después. ---------------
    servidor.hayRed = true;
    expect(await subirLaCola().ciclo(), 1);

    // (a) LA RUTA DEL SERVIDOR LLEVA LOS DOS QUE EL APARATO ELIGIÓ.
    //
    // Sin `pedidoIds` en el cuerpo llevaría TRES: el servidor arma con lo que
    // tenga puesto, y p3 entró después de que el camión saliera. Un bulto que
    // nadie cargó, contado como repartido.
    expect(
      servidor.rutas['ruta-servidor-1'],
      ['p1', 'p2'],
      reason:
          'la ruta tiene que ser EXACTAMENTE la que armó el aparato: p3 entró '
          'en la zona después y no va en ese camión',
    );

    // (b) Y EL TERCERO SE DICE, con su folio, su cliente y qué hacer.
    final aviso = (await avisos()).single;
    expect(aviso.motivo, contains('X-3100'));
    expect(aviso.motivo, contains('Marta Ruiz'));
    expect(
      aviso.motivo,
      contains('lo pusieron en la zona después de que armaras'),
    );
    expect(aviso.motivo, contains('arma otra vez si tiene que salir hoy'));
  });

  test('la web se lleva uno de los dos mientras la APK está sin señal: la ruta '
      'sale con uno y el que falta se NOMBRA, con qué hacer', () async {
    final contenedor = montar();
    addTearDown(contenedor.dispose);
    await contenedor.read(tableroProvider.future);

    servidor.hayRed = false;
    await contenedor.read(tableroProvider.notifier).armarRuta(zona);

    // La oficina saca p2 de la zona. Para el servidor es legal: ahí todavía no
    // existe ninguna ruta.
    servidor.laWebQuita('p2');

    servidor.hayRed = true;
    expect(await subirLaCola().ciclo(), 1);

    expect(servidor.rutas['ruta-servidor-1'], ['p1']);

    // ESE es el pedido que su repartidor puede llevar entregado, así que hay
    // que decirlo con su nombre y no con un uuid.
    final aviso = (await avisos()).single;
    expect(aviso.motivo, contains('X-3001'));
    expect(aviso.motivo, contains('Luis Mora'));
    expect(
      aviso.motivo,
      contains('ya no estaba en esa zona cuando llegó tu apunte'),
    );
    expect(aviso.motivo, contains('comprueba si se entregó igual'));

    // Y NO es un rechazo: el apunte entró, la ruta existe arriba. Marcarlo
    // rechazado ofrecería «reintentar», que aquí armaría una SEGUNDA ruta.
    final apunte = await ColaDeSalida(base).porClave(aviso.clave);
    expect(apunte!.estado, EstadoApunte.aplicado);
    expect(
      await ColaDeSalida(base, reloj: reloj.leer).rechazados().first,
      isEmpty,
    );

    // Y una persona puede darlo por leído: una lista que sólo crece deja de
    // leerse a la tercera semana.
    await ColaDeSalida(
      base,
      reloj: reloj.leer,
    ).darPorLeidoElDescarte(aviso.clave);
    expect(await avisos(), isEmpty);
  });

  test('NO se cae nadie: el armado sube entero y no sale ni un aviso', () async {
    // La otra mitad del §3-quinquies. Un aviso que sale en CADA armado deja de
    // leerse, y entonces tampoco se lee el día que importa.
    final contenedor = montar();
    addTearDown(contenedor.dispose);
    await contenedor.read(tableroProvider.future);

    servidor.hayRed = false;
    await contenedor.read(tableroProvider.notifier).armarRuta(zona);

    servidor.hayRed = true;
    expect(await subirLaCola().ciclo(), 1);

    expect(servidor.rutas['ruta-servidor-1'], ['p1', 'p2']);
    expect(
      await avisos(),
      isEmpty,
      reason:
          'nadie se cayó, así que no hay nada que decir: el aviso que sale '
          'siempre es el que no se lee el día que importa',
    );
  });
}
