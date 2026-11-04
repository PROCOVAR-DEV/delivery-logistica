// QUIEN ORDENO LAS PARADAS, Y QUE LA RUTA LO DIGA — el lado del aparato.
//
// `optimized` es la firma de quien decidio el orden de visita. Se guardaba
// `true` SIEMPRE, tambien cuando el orden era el que puso la persona a mano.
//
// El dano no se ve el dia que pasa: se ve despues. La pantalla no ofrece
// reoptimizar «lo que ya esta optimizado», el informe cuenta esa ruta entre las
// calculadas, y el orden que puso alguien que conoce las calles de su distrito
// queda indistinguible del que saca el greedy. Es el mismo fallo de familia que
// el `price: pedido_costo || 0`: un dato creible y falso que nadie desmiente.
//
// **Las dos pruebas van EN PAREJA a proposito.** Una sola —«respetar el orden
// deja `false`»— la haria pasar entera un `optimized: false` clavado, que es el
// mismo fallo del reves y marcaria en falso todas las rutas de la calle.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late AccionesDeRuta acciones;

  setUp(() async {
    base = baseDePrueba();
    final reloj = RelojFalso(DateTime.utc(2026, 9, 21, 9));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    acciones = AccionesDeRuta(
      base,
      cola,
      reloj: reloj.leer,
    );
    await sembrarCatalogo(base);

    // Tres paradas en el ecuador a 0.1 / 0.3 / 0.2 grados del origen (0,0). El
    // orden por cercania es q1, q3, q2; cualquier otro delata que no se ordeno.
    await sembrarPedido(
      base,
      id: 'q1',
      cliente: 'Ana',
      folio: 'F-001',
      peso: 10,
      endLat: 0,
      endLng: 0.1,
    );
    await sembrarPedido(
      base,
      id: 'q2',
      cliente: 'Beto',
      folio: 'F-002',
      peso: 10,
      endLat: 0,
      endLng: 0.3,
    );
    await sembrarPedido(
      base,
      id: 'q3',
      cliente: 'Carla',
      folio: 'F-003',
      peso: 10,
      endLat: 0,
      endLng: 0.2,
    );
  });

  tearDown(() => base.close());

  Future<String> armar({required bool? optimizar}) => acciones.armar(
    vehiculoId: 'V1',
    // Se mandan en el orden que NO sacaria el greedy: si el aparato reordenara,
    // las posiciones guardadas lo delatan.
    pedidoIds: ['q2', 'q1', 'q3'],
    origenLat: 0,
    origenLng: 0,
    origenDireccion: 'Almacén central',
    sucursalId: 'B1',
    optimizar: optimizar ?? true,
  );

  Future<Map<int?, String>> paradasDe(String rutaId) async {
    final filas = await (base.select(
      base.orders,
    )..where((o) => o.ultimaRutaId.equals(rutaId))).get();
    return {for (final p in filas) p.stopOrder: p.id};
  }

  test('dejando que ordene la maquina, la ruta queda optimizada', () async {
    final rutaId = await armar(optimizar: true);
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();

    expect(
      ruta.optimized,
      isTrue,
      reason: 'lo ordeno la maquina: decir que no lo hizo esconde el calculo',
    );
    // Y el orden es el del calculo, no el de la lista que llego.
    expect(await paradasDe(rutaId), {1: 'q1', 2: 'q3', 3: 'q2'});
  });

  test('respetando el orden del logistico, NO queda optimizada', () async {
    final rutaId = await armar(optimizar: false);
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();

    expect(
      ruta.optimized,
      isFalse,
      reason:
          'el orden lo puso una persona; guardarlo como calculado es la firma '
          'falsa que nadie desmiente hasta que alguien decide no reoptimizar',
    );
    // Y el orden es EL SUYO, tal cual llego.
    expect(await paradasDe(rutaId), {1: 'q2', 2: 'q1', 3: 'q3'});
  });

  test('el apunte que sube lleva quien ordeno, en los dos casos', () async {
    // La mitad de este arreglo vive en el servidor: si el cuerpo no lo dice, el
    // servidor da por calculado lo que no lo esta y la ruta vuelve a mentir en
    // cuanto suba. Por eso `optimizar` viaja SIEMPRE, tambien cuando es `true`.
    await armar(optimizar: false);
    final primero = (await cola.pendientes().first).single;
    final cuerpo = ColaDeSalida.cuerpoDe(primero)! as Map<String, Object?>;
    expect(cuerpo['optimizar'], isFalse);
    expect(cuerpo['orderIds'], ['q2', 'q1', 'q3']);
  });

  test('sin decir nada se ordena y se firma como calculada, como siempre', () async {
    // El valor por defecto: es lo que hacen hoy el asistente y las APK
    // instaladas, y tiene que seguir siendo `true` — su orden SI lo calculo el
    // aparato.
    final rutaId = await armar(optimizar: null);
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();
    expect(ruta.optimized, isTrue);
    expect(await paradasDe(rutaId), {1: 'q1', 2: 'q3', 3: 'q2'});
  });
}
