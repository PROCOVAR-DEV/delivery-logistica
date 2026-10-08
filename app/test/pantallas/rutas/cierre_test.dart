// EL CIERRE DE RUTA SIN CONEXION. Es la prueba que no puede faltar.
//
// Lo que se comprueba, y por que cada cosa:
//
//  * el cierre **queda en la cola** con la **hora del aparato**, no con la de la
//    subida: lo que se marca a las cuatro en el patio tiene que llegar como las
//    cuatro aunque suba a las siete (regla 7, caso S2);
//  * se ve marcado **al reabrir**. Y para que eso signifique algo, la base de
//    esta prueba es un FICHERO de verdad que se cierra y se vuelve a abrir, no
//    una base en memoria: con una en memoria se estaria comprobando que un mapa
//    de Dart conserva lo que se le mete, que es lo que pasa igual cuando la
//    aplicacion no guarda nada (paso 2 del guion del dia sin conexion);
//  * lo que NO se entrega suelta su `routeId` pero **conserva `ultimaRutaId`**, o
//    desaparece de la hoja de lo que bajo del camion;
//  * cuando la ruta se armo sin red, el apunte del cierre apunta a un `local-…`
//    y **deja de apuntarle** en cuanto la ruta sube (caso S4).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/cola/provisionales.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';

import '../../apoyo/reloj_falso.dart';
import '../pedidos/sembrar.dart';

void main() {
  late Directory carpeta;
  late File fichero;
  late BaseLocal base;
  late ColaDeSalida cola;
  late AccionesDeRuta acciones;
  late RelojFalso reloj;

  /// **La hora del patio.** El cierre se marca a las 16:05 y la subida, si llega,
  /// sera horas despues.
  final laHoraDelPatio = DateTime(2026, 9, 14, 16, 5);

  void abrir() {
    base = BaseLocal.con(NativeDatabase(fichero));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    acciones = AccionesDeRuta(
      base,
      cola,
      reloj: reloj.leer,
      sufijoAparato: 'MSI',
    );
  }

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('reparto_cierre');
    fichero = File('${carpeta.path}/reparto.sqlite');
    reloj = RelojFalso(laHoraDelPatio);
    abrir();

    await sembrarCatalogo(base);
    await sembrarRuta(
      base,
      id: 'R1',
      estado: EstadoRuta.enCurso,
      codigo: 'RT-001',
    );
    for (final (i, nombre) in <String>['Ana', 'Beto', 'Carla'].indexed) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: nombre,
        rutaId: 'R1',
        orden: i + 1,
        peso: 10,
      );
      await sembrarRenglon(
        base,
        id: 'ri${i + 1}',
        pedidoId: 'p${i + 1}',
        producto: 'Arroz',
        unidades: 10,
        empaques: 2,
      );
    }
  });

  tearDown(() async {
    await base.close();
    await carpeta.delete(recursive: true);
  });

  test(
    'sin conexion: el cierre queda en la cola con la hora del aparato',
    () async {
      final cierre = await acciones.cerrar('R1', const [
        MarcaDeParada(pedidoId: 'p1', resultado: ResultadoParada.entregado),
        MarcaDeParada(
          pedidoId: 'p2',
          resultado: ResultadoParada.devuelto,
          nota: '  no había nadie  ',
        ),
        // p3 no se marca: cuenta como que sigue en el camion.
      ]);

      // ---- 1. La cola: UN apunte, con la hora del patio.
      final pendientes = await cola.pendientes().first;
      expect(
        pendientes.length,
        1,
        reason: 'un cierre es UN apunte, no uno por parada',
      );

      final apunte = pendientes.single;
      expect(apunte.clave, cierre.claveDelApunte);
      expect(apunte.metodo, 'POST');
      expect(apunte.ruta, '/routes/R1/results');
      expect(apunte.estado, EstadoApunte.pendiente);
      expect(
        apunte.hechoAt,
        laHoraDelPatio,
        reason: 'la hora es la del APARATO al marcar, no la de la subida',
      );

      final cuerpo = ColaDeSalida.cuerpoDe(apunte)! as Map<String, Object?>;
      final resultados = cuerpo['resultados']! as List<Object?>;
      expect(resultados.length, 2);
      final segunda = resultados[1]! as Map<String, Object?>;
      expect(segunda['orderId'], 'p2');
      expect(segunda['resultado'], ResultadoParada.devuelto);
      // La nota va recortada, como la recorta el servidor.
      expect(segunda['nota'], 'no había nadie');

      // ---- 2. Y ya esta pintado como hecho, sin haber hablado con nadie.
      final p1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p1'))).getSingle();
      expect(p1.resultado, ResultadoParada.entregado);
      expect(p1.resultadoAt, laHoraDelPatio);
      expect(p1.deliveredAt, laHoraDelPatio);
      expect(p1.status, EstadoPedido.entregado);
      expect(p1.routeId, 'R1', reason: 'lo entregado no suelta la ruta');

      final p2 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p2'))).getSingle();
      expect(p2.resultado, ResultadoParada.devuelto);
      expect(p2.deliveredAt, isNull);
      expect(p2.status, EstadoPedido.pendiente);
      expect(
        p2.routeId,
        isNull,
        reason: 'lo que vuelve suelta el camion para poder ir mañana',
      );
      expect(
        p2.ultimaRutaId,
        'R1',
        reason: 'pero conserva en que ruta viajo, o desaparece de la hoja',
      );
      expect(p2.stopOrder, 2, reason: '`stopOrder` no se toca nunca');
    },
  );

  test('AL REABRIR sigue todo marcado y el cierre sigue en la cola', () async {
    await acciones.cerrar('R1', const [
      MarcaDeParada(pedidoId: 'p1', resultado: ResultadoParada.entregado),
      MarcaDeParada(
        pedidoId: 'p2',
        resultado: ResultadoParada.devuelto,
        nota: 'el cliente cerró',
      ),
    ]);

    // Cerrar la base y volver a abrir el MISMO fichero es lo que le pasa a la
    // aplicacion cuando alguien la desliza fuera y la vuelve a abrir, o cuando el
    // telefono se apaga en el patio.
    await base.close();
    reloj.ahora = DateTime(2026, 9, 15, 7, 30); // al dia siguiente
    abrir();

    final p1 = await (base.select(
      base.orders,
    )..where((o) => o.id.equals('p1'))).getSingle();
    expect(p1.resultado, ResultadoParada.entregado);
    expect(p1.deliveredAt, laHoraDelPatio);

    final p2 = await (base.select(
      base.orders,
    )..where((o) => o.id.equals('p2'))).getSingle();
    expect(p2.resultado, ResultadoParada.devuelto);
    expect(p2.resultadoNota, 'el cliente cerró');

    final pendientes = await cola.pendientes().first;
    expect(pendientes.length, 1);
    expect(
      pendientes.single.hechoAt,
      laHoraDelPatio,
      reason: 'al dia siguiente sigue diciendo la hora a la que se marco',
    );
  });

  test(
    'corregir una parada ya marcada: manda la ultima, y el orden lo da la cola',
    () async {
      await acciones.cerrar('R1', const [
        MarcaDeParada(pedidoId: 'p1', resultado: ResultadoParada.entregado),
      ]);

      // El reloj SALTA HACIA ATRAS —se cambio a mano, se fue la bateria—: no puede
      // reordenar el trabajo. El orden lo da `orden`, el autoincremento.
      reloj.ahora = laHoraDelPatio.subtract(const Duration(hours: 3));
      await acciones.cerrar('R1', const [
        MarcaDeParada(
          pedidoId: 'p1',
          resultado: ResultadoParada.devuelto,
          nota: 'me equivoqué',
        ),
      ]);

      final pendientes = await cola.pendientes().first;
      expect(pendientes.length, 2);
      expect(pendientes.first.orden < pendientes.last.orden, isTrue);
      final ultimo =
          ColaDeSalida.cuerpoDe(pendientes.last)! as Map<String, Object?>;
      final resultado =
          (ultimo['resultados']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(resultado['resultado'], ResultadoParada.devuelto);

      // Y en local ya se ve la correccion, sin esperar a subir nada.
      final p1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p1'))).getSingle();
      expect(p1.resultado, ResultadoParada.devuelto);
      expect(p1.routeId, isNull);
    },
  );

  test(
    'una ruta armada sin red: el cierre deja de decir `local-` cuando sube',
    () async {
      // Un pedido suelto con coordenadas, para armar la ruta aqui mismo.
      await sembrarPedido(
        base,
        id: 'p9',
        cliente: 'Dani',
        peso: 5,
        endLat: 0,
        endLng: 0.1,
      );
      final rutaId = await acciones.armar(
        vehiculoId: 'V1',
        pedidoIds: ['p9'],
        origenLat: 0,
        origenLng: 0,
        sucursalId: 'B1',
      );
      expect(rutaId, startsWith('local-'));

      await acciones.cerrar(rutaId, const [
        MarcaDeParada(pedidoId: 'p9', resultado: ResultadoParada.entregado),
      ]);

      var pendientes = await cola.pendientes().first;
      expect(pendientes.length, 2);
      expect(pendientes.last.ruta, '/routes/$rutaId/results');

      // Sube la creacion de la ruta y el servidor devuelve el id de verdad.
      await cola.resolver(
        pendientes.first.clave,
        const ResultadoApunte(estado: EstadoResultado.aplicado, id: 'cm2xreal'),
      );

      pendientes = await cola.pendientes().first;
      expect(pendientes.length, 1);
      expect(
        pendientes.single.ruta,
        '/routes/cm2xreal/results',
        reason:
            'sin esto el cierre se perderia JUSTO DESPUES de subir (caso S4)',
      );
      expect(pendientes.single.ruta, isNot(contains('local-')));

      // Y la fila local tambien deja de decir `local-`.
      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals('cm2xreal'))).getSingleOrNull();
      expect(ruta, isNotNull);
      expect(await Provisionales(base).real(rutaId), 'cm2xreal');
    },
  );

  test('un cierre vacio no se encola', () async {
    expect(
      () => acciones.cerrar('R1', const []),
      throwsA(
        isA<RechazoLocal>().having(
          (r) => r.mensaje,
          'mensaje',
          'No vino ningún resultado',
        ),
      ),
    );
  });

  test('una parada que no es de esta ruta no aborta el resto', () async {
    await sembrarPedido(base, id: 'ajeno', cliente: 'Zoe');
    await acciones.cerrar('R1', const [
      MarcaDeParada(pedidoId: 'ajeno', resultado: ResultadoParada.entregado),
      MarcaDeParada(pedidoId: 'p3', resultado: ResultadoParada.entregado),
    ]);

    final apunte = (await cola.pendientes().first).single;
    final cuerpo = ColaDeSalida.cuerpoDe(apunte)! as Map<String, Object?>;
    expect((cuerpo['resultados']! as List<Object?>).length, 1);

    final ajeno = await (base.select(
      base.orders,
    )..where((o) => o.id.equals('ajeno'))).getSingle();
    expect(ajeno.resultado, isNull);
  });
}
