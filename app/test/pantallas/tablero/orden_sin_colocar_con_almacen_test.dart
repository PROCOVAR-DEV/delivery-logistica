// «SIN COLOCAR» CON UN ALMACÉN ELEGIDO ARRIBA — Jose, 15/10/2026: elegido en la
// cabecera del tablero otro almacén, la lista enseña TODOS los pedidos, pero
// PRIMERO los de ese almacén del más cercano al más lejano, y DESPUÉS los demás
// por la fecha de su factura (el orden de Amado, issue 6).
//
// Lo que se ata aquí, contra `docs/orden-sin-colocar.casos.json`, el MISMO fichero
// que leen el servidor (`orden_sin_colocar_casos_compartidos_test.go`) y Postgres
// (`TestMotorReal_SinColocarConAlmacenElegido`):
//
//  * de qué almacén van primero (`almacenDe` con el preferido de la cabecera):
//    sin elegir o con el de por defecto, de ninguno; con otro, del suyo; con uno
//    sin código, de ninguno;
//  * el orden exacto de la lista local, que es lo que pintan la APK, el escritorio
//    y la web (la web llena su base en memoria y lee la misma);
//  * el contador no cambia con el almacén: el orden no cambia cuántos son;
//  * y el cableado de la pantalla: elegir arriba vuelve a leer la lista en el orden
//    nuevo, y volver al de por defecto devuelve el de siempre.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart'
    show sucursalDeLaSesionProvider;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

const rutaDeLosCasos = '../docs/orden-sin-colocar.casos.json';

final Map<String, dynamic> casos =
    jsonDecode(File(rutaDeLosCasos).readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> lista(String clave) =>
    (casos[clave] as List).cast<Map<String, dynamic>>();

DateTime? fecha(Object? v) => v == null ? null : DateTime.parse(v as String);

/// Los almacenes y los pedidos del fichero, tal cual, en Santiago.
Future<void> sembrarLosCasos(BaseLocal base) async {
  await sembrarSucursal(base);
  for (final a in lista('almacenes')) {
    await base
        .into(base.warehouses)
        .insert(
          WarehousesCompanion.insert(
            id: a['id'] as String,
            sucursalCodigo: codigoStg,
            codigo: Value(a['codigo'] as String?),
            nombre: a['nombre'] as String,
            lat: Value((a['latitud'] as num).toDouble()),
            lng: Value((a['longitud'] as num).toDouble()),
            principal: Value(a['principal'] as bool),
          ),
        );
  }
  for (final p in lista('pedidos')) {
    await sembrarPedido(
      base,
      id: p['id'] as String,
      cliente: p['nombre'] as String,
    );
    await (base.update(
      base.orders,
    )..where((o) => o.id.equals(p['id'] as String))).write(
      OrdersCompanion(
        endLat: Value((p['latitud'] as num).toDouble()),
        endLng: Value((p['longitud'] as num).toDouble()),
        almacenSalidaCodigo: Value(p['almacenCodigo'] as String?),
        facturaAt: Value(fecha(p['facturaAt'])),
        orderDate: Value(fecha(p['orderDate'])),
      ),
    );
  }
}

List<String> nombres(MitadIzquierda m) =>
    m.pedidos.map((p) => p.customerName).toList();

void main() {
  late BaseLocal base;
  late ConsultasTablero consultas;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    await sembrarLosCasos(base);
  });
  tearDown(() => base.close());

  test('el fichero trae casos: una prueba sobre nada sale verde', () {
    expect(lista('casos'), isNotEmpty);
    expect(lista('pedidos'), isNotEmpty);
  });

  for (final caso in lista('casos')) {
    test('${caso['nombre']}', () async {
      final origen = await consultas.almacenDe(
        sucursalStg,
        preferido: caso['elegido'] as String?,
      );
      expect(
        origen.primeroLosDe,
        caso['primeroLosDe'],
        reason:
            'con «${caso['elegido']}» elegido arriba, primero tendrían que ir '
            'los de ${caso['primeroLosDe'] ?? 'ninguno (el orden de siempre)'}',
      );
      final izquierda = await consultas.sinColocar(sucursalStg, origen);
      expect(
        nombres(izquierda),
        (caso['esperado'] as List).cast<String>(),
        reason: '${caso['nota']}',
      );
      expect(
        izquierda.total,
        lista('pedidos').length,
        reason: 'el orden no cambia cuántos son: nadie se esconde',
      );
    });
  }

  test('elegir arriba vuelve a leer la lista en el orden nuevo, y volver al de '
      'por defecto devuelve el de siempre', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba'))
      ..httpClientAdapter = ServidorFalso((_) async => null);
    final contenedor = ProviderContainer.test(
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
        sucursalDeLaSesionProvider.overrideWithValue(sucursalStg),
      ],
    );
    addTearDown(contenedor.dispose);
    final porCaso = {
      for (final c in lista('casos'))
        c['nombre'] as String: (c['esperado'] as List).cast<String>(),
    };
    Future<List<String>> laLista() async =>
        nombres((await contenedor.read(tableroProvider.future)).sinColocar);

    expect(
      await laLista(),
      porCaso['sin-almacen-elegido-el-orden-de-siempre'],
      reason: 'sin tocar la cabecera, el orden de siempre',
    );

    contenedor
        .read(almacenElegidoProvider.notifier)
        .elegir(sucursalStg, 'alm-aurora');
    expect(
      await laLista(),
      porCaso['aurora-elegido-los-suyos-por-cercania-y-luego-los-demas-por-fecha'],
      reason:
          'se eligió AURORA arriba y la lista no puso primero los suyos: la '
          'cabecera diría AURORA sobre una lista que no lo es',
    );

    contenedor
        .read(almacenElegidoProvider.notifier)
        .elegir(sucursalStg, 'alm-pv-stgo');
    expect(
      await laLista(),
      porCaso['el-de-por-defecto-elegido-a-mano-es-el-orden-de-siempre'],
      reason:
          'volver al de por defecto es volver al orden de siempre: la cabecera '
          'no tiene «ninguno»',
    );
  });
}
