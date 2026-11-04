// UNA RUTA RECIÉN ARMADA TIENE SUS PARADAS **EN EL MOMENTO**.
//
// Jose, 21/09/2026, armando rutas con el teléfono delante: «se sigue creando la
// ruta sin paradas y tiene paradas». El detalle se abría solo y decía «Ver
// paradas (0)» y «Carga total: 0» encima de una ruta de tres pedidos, con sus
// «17.1 km (incl. regreso) · 212.0 kg» en la misma línea — o sea que los
// kilómetros y los kilos SÍ salían de esos mismos pedidos.
//
// «No, eso no puede pasar, eso es al momento».
//
// Esta prueba no monta pantalla: pregunta a la consulta que la pantalla usa
// (`mirarParadasDe`), que es donde hay que empezar a mirar. Si aquí salen las
// paradas, el fallo está en la pantalla; si no salen, está en el armado.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';

import '../../apoyo/reloj_falso.dart';
import '../pedidos/sembrar.dart';

void main() {
  late Directory carpeta;
  late BaseLocal base;
  late AccionesDeRuta acciones;
  late RelojFalso reloj;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('paradas');
    base = BaseLocal.con(
      NativeDatabase(File('${carpeta.path}/base.sqlite')),
      dueno: 'jose',
    );
    reloj = RelojFalso(DateTime.utc(2026, 9, 21, 16, 54));
    acciones = AccionesDeRuta(
      base,
      ColaDeSalida(base, reloj: reloj.leer),
      reloj: reloj.leer,
    );
  });

  tearDown(() async {
    await base.close();
    await carpeta.delete(recursive: true);
  });

  test('las tres paradas están ahí en cuanto se arma, sin subir nada', () async {
    await sembrarCatalogo(base);
    for (final (id, lat, lng) in const [
      ('p1', 23.10, -82.36),
      ('p2', 23.12, -82.34),
      ('p3', 23.08, -82.38),
    ]) {
      await sembrarPedido(
        base,
        id: id,
        cliente: 'Cliente $id',
        peso: 70,
        endLat: lat,
        endLng: lng,
      );
    }

    final rutaId = await acciones.armar(
      vehiculoId: 'V1',
      pedidoIds: ['p1', 'p2', 'p3'],
      origenLat: 23.11,
      origenLng: -82.37,
      sucursalId: 'B1',
    );

    final paradas = await ConsultasRutas(base).mirarParadasDe(rutaId).first;
    expect(
      paradas.map((p) => p.id).toSet(),
      {'p1', 'p2', 'p3'},
      reason:
          'LA RUTA SE ARMÓ SIN PARADAS: los kilómetros y los kilos salen de esos '
          'mismos pedidos, así que el dato está y la pantalla enseña cero. Es lo '
          'que vio Jose el 21/09/2026.',
    );

    // Y la ruta guardada tiene los kilómetros del circuito, que es de donde se
    // sabe que el orden se calculó sobre esas tres paradas.
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();
    expect(ruta.totalDistance, greaterThan(0));
    expect(ruta.totalWeight, 210);
  });
}
