import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Variable;
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
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_de_los_dos_lados.dart';
import '../tablero/apoyo.dart';

/// LA RUTA ARMADA **Y COMPLETADA** SIN SEÑAL, CON LA WEB TRABAJANDO A LA VEZ.
///
/// Es el caso que más preocupa y el único que no se llegó a probar a mano el
/// 17/09/2026: se armó la ruta sin señal, sí, pero no se cerró. Palabras de
/// Jose: «se hizo la ruta, se completó con esos pedidos que ya se entregaron,
/// ahí se deberían de borrar esos pedidos de los tableros; creo que ahí diera un
/// problema».
///
/// Lo que se vigila aquí, y en este orden de gravedad:
///
///  1. **Ningún pedido puede estar a la vez en una ruta y en el tablero.** Eso
///     es una entrega doble: dos camiones con el mismo bulto.
///  2. **Nada se pierde**: ni lo que hizo el móvil sin señal ni lo que hizo la
///     web mientras tanto.
///  3. **Un pedido ya entregado no se vuelve a ofrecer** para meterlo en otra
///     ruta.
///
/// La forma es la del `CLAUDE.md` §3-ter: se monta con el tablero de la mañana
/// —el que bajó con señal— y todo lo demás llega DESPUÉS, sin volver a montar.
void main() {
  late Directory carpeta;
  late File fichero;
  late BaseLocal base;
  late ServidorDeLosDosLados servidor;
  late RelojFalso reloj;

  const zonaVista = '0199a1b2-0000-7000-8000-00000000vista';
  const zonaCentro = '0199a1b2-0000-7000-8000-0000000centro';

  /// La hora del patio del almacén, que es donde se cierra la ruta y donde no
  /// hay señal.
  final laHoraDelPatio = DateTime(2026, 9, 14, 16, 5);

  /// Los seis que van en la zona «Vista» desde por la mañana.
  const deLaZona = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'];

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('ruta_completada');
    fichero = File('${carpeta.path}/reparto.sqlite');
    base = BaseLocal.con(NativeDatabase(fichero));
    reloj = RelojFalso(laHoraDelPatio);
    await aparatoYaDeAlta(base);

    servidor = ServidorDeLosDosLados(sucursalId: sucursalStg)
      // CON SU CAMIÓN PREVISTO (`v1`, sembrado tres líneas más abajo). Desde el
      // 28/09/2026 una zona sin camión no arma ruta, y de esta zona salen las
      // tres rutas de este fichero.
      ..laWebCreaZona(zonaVista, 'Vista', vehiculoId: 'v1');

    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarCamion(base, id: 'v1', capacidad: 5000);
    for (final (i, id) in deLaZona.indexed) {
      await sembrarPedido(base, id: id, aGrados: 0.01 * (i + 1), peso: 100);
      // Puestos EN EL SERVIDOR desde por la mañana: el logístico armó el tablero
      // con señal y luego se fue al patio.
      servidor.laWebColoca(id, zonaVista, posicion: i + 1);
    }
    // Un séptimo que no va en la zona: es con el que se comprueba que lo de la
    // web tampoco se pierde.
    await sembrarPedido(base, id: 'p7', aGrados: 0.30, peso: 50);
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

  AccionesDeRuta acciones() => AccionesDeRuta(
    base,
    ColaDeSalida(base, reloj: reloj.leer),
    reloj: reloj.leer,
    sufijoAparato: 'MSI',
  );

  /// Los pedidos que están puestos en alguna zona, se pinte lo que se pinte.
  Future<List<String>> enElTablero() async {
    final filas = await base
        .customSelect('SELECT order_id FROM ${EsquemaTablero.colocaciones}')
        .get();
    return (filas.map((f) => f.read<String>('order_id')).toList())..sort();
  }

  /// Los pedidos que están en una ruta.
  Future<List<String>> enUnaRuta() async {
    final filas = await (base.select(
      base.orders,
    )..where((o) => o.routeId.isNotNull())).get();
    return (filas.map((o) => o.id).toList())..sort();
  }

  /// LA PREGUNTA QUE NO PUEDE CONTESTARSE NUNCA CON UN NOMBRE DENTRO: quién está
  /// a la vez en una ruta y en el tablero.
  Future<List<String>> enLosDosSitios() async {
    final ruta = await enUnaRuta();
    final tablero = await enElTablero();
    return [
      for (final id in ruta)
        if (tablero.contains(id)) id,
    ];
  }

  test('se arma la ruta de la zona y SE COMPLETA sin señal: los seis salen del '
      'tablero, quedan entregados, y nada de lo de la web se pierde al subir', () async {
    // ---- La mañana: el tablero baja del servidor con la zona hecha. -----
    final contenedor = montar();
    addTearDown(contenedor.dispose);

    var tablero = await contenedor.read(tableroProvider.future);
    expect(tablero.columnas.single.nombre, 'Vista');
    expect(tablero.columnas.single.pedidos, 6);
    expect(tablero.sinColocar.pedidos.single.pedidoId, 'p7');

    // ---- La tarde, en el patio y sin señal. -----------------------------
    servidor.hayRed = false;
    servidor.adaptador.vistas.clear();

    final mando = contenedor.read(tableroProvider.notifier);
    final rutaId = await mando.armarRuta(zonaVista);
    expect(rutaId, startsWith('local-'));

    // Armar ya vacía el tablero. Esto es lo que se midió a mano y salió bien.
    expect(await enUnaRuta(), deLaZona);
    expect(await enElTablero(), isEmpty);
    expect(await enLosDosSitios(), isEmpty);

    // ---- Y AQUÍ EMPIEZA LO QUE NO SE LLEGÓ A PROBAR: se completa. -------
    await acciones().cerrar(rutaId, [
      for (final id in deLaZona)
        MarcaDeParada(pedidoId: id, resultado: ResultadoParada.entregado),
    ]);
    await acciones().completar(rutaId);

    final entregados = await base.select(base.orders).get();
    for (final id in deLaZona) {
      final p = entregados.firstWhere((o) => o.id == id);
      expect(p.resultado, ResultadoParada.entregado);
      expect(p.status, EstadoPedido.entregado);
      expect(
        p.deliveredAt,
        laHoraDelPatio,
        reason: 'la hora del APARATO al marcar, no la de la subida',
      );
      expect(p.routeId, rutaId, reason: 'lo entregado no suelta la ruta');
    }
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();
    expect(ruta.status, EstadoRuta.completada);

    // 1 · NADIE EN LOS DOS SITIOS, tampoco después de completar.
    expect(await enLosDosSitios(), isEmpty);
    expect(await enElTablero(), isEmpty);

    // 3 · Y LO ENTREGADO NO SE VUELVE A OFRECER. Ni en la mitad izquierda del
    //     tablero ni en el armador de rutas: las dos preguntas tienen que dar
    //     lo mismo, o el logístico prepara una columna que la ruta rechaza.
    tablero = await contenedor.read(tableroProvider.future);
    expect(tablero.sinColocar.pedidos.map((p) => p.pedidoId).toList(), [
      'p7',
    ], reason: 'los seis entregados no vuelven a «sin colocar»');
    final ofrecidos = await ConsultasRutas(base)
        .disponibles(sucursalId: sucursalStg);
    expect(ofrecidos.map((p) => p.id).toList(), [
      'p7',
    ], reason: 'un pedido ya entregado no se puede meter en otra ruta');
    // Y el tercer camino, el asistente de Rutas, dice lo mismo aunque se le
    // nombre el pedido a mano. Son tres puertas al mismo sitio y las tres
    // tienen que estar cerradas: basta con que una se quede abierta para que
    // salga un segundo camión con un bulto ya entregado.
    //
    // EL MOTIVO, Y NO «ya no están disponibles» — 22/09/2026. Aquí se esperaba
    // el mensaje genérico, y para un pedido ENTREGADO ese mensaje es el que más
    // daño hace: manda a volver a elegirlo, cuando lo que pasa es que el bulto
    // ya está en casa del cliente. Es el mismo literal que contesta el servidor
    // (`api/internal/api/rutas.go`, `porQueNoSeArma`).
    await expectLater(
      acciones().armar(
        vehiculoId: 'v1',
        pedidoIds: ['p1'],
        origenLat: almacenLat,
        origenLng: almacenLng,
        sucursalId: sucursalStg,
      ),
      throwsA(
        isA<RechazoLocal>().having(
          (e) => e.mensaje,
          'mensaje',
          'El pedido elegido no puede ir en esta ruta: '
              'p1 (ya se entregó y no puede volver a un camión).',
        ),
      ),
    );

    // ---- La web, a la misma hora, hace lo suyo en OTRA zona. ------------
    servidor
      ..laWebCreaZona(zonaCentro, 'Centro')
      ..laWebColoca('p7', zonaCentro);

    // ---- Se recupera la señal. Primero NO se baja nada. -----------------
    servidor.hayRed = true;
    await mando.bajarDelServidor();
    // Lo primero es lo que se pierde, no el cartel: para el servidor los seis
    // siguen puestos en «Vista», así que su foto los devolvería al tablero
    // **con la ruta ya entregada** — los mismos seis bultos en dos sitios.
    expect(
      await enElTablero(),
      isEmpty,
      reason:
          'la foto del servidor no sabe nada de la ruta ni del cierre: '
          'bajarla ahora devuelve al tablero seis pedidos ya entregados',
    );
    expect(await enLosDosSitios(), isEmpty);
    expect(await enUnaRuta(), deLaZona, reason: 'sigue todo donde se dejó');
    expect(
      mando.porQueNoSeRefresca,
      '3 cambios sin subir',
      reason: 'y se DICE por qué no se actualizó, o parece que no hizo nada',
    );

    // ---- Y ahora sube todo. --------------------------------------------
    expect(await subirLaCola().ciclo(), 3);
    expect(servidor.aplicados, [
      '/board/columns/$zonaVista/route',
      // El cierre ya NO dice `local-…`: la respuesta de la ruta trajo el id de
      // verdad y `Provisionales` lo sustituyó en la cola antes de mandarlo.
      '/routes/ruta-servidor-1/results',
      '/routes/ruta-servidor-1',
    ]);
    expect(servidor.rutas['ruta-servidor-1'], deLaZona);
    for (final id in deLaZona) {
      expect(servidor.resultados[id], ResultadoParada.entregado);
    }

    // Y aquí abajo la ruta ya no se llama `local-…`: el id de verdad entró en
    // la fila y en los seis pedidos. Sin esa sustitución, el aparato seguiría
    // hablando de una ruta que arriba se llama de otra manera — y el cierre de
    // mañana, o el reintento, se irían a un sitio que no existe (caso S4).
    expect(
      (await base.select(base.routes).get()).single.id,
      'ruta-servidor-1',
      reason:
          'la ruta subió y el servidor devolvió su id: si aquí sigue el '
          '«local-…», el aparato y el servidor hablan de dos rutas distintas',
    );
    final conRutaBuena = await (base.select(
      base.orders,
    )..where((o) => o.routeId.equals('ruta-servidor-1'))).get();
    expect((conRutaBuena.map((o) => o.id).toList()..sort()), deLaZona);
    expect(servidor.puestas.keys.toList(), [
      'p7',
    ], reason: 'armar la ruta saca del tablero del SERVIDOR a los seis');

    // ---- Y por fin baja la foto, con los dos lados dentro. -------------
    await mando.bajarDelServidor();
    expect(mando.porQueNoSeRefresca, isNull);
    tablero = await contenedor.read(tableroProvider.future);

    // 1 · Sigue sin haber nadie en los dos sitios.
    expect(await enLosDosSitios(), isEmpty);

    // 2 · NADA SE PIERDE. Lo del móvil: los seis siguen entregados y en su
    //     ruta. Lo de la web: su zona nueva y su tarjeta están.
    expect(await enUnaRuta(), deLaZona);
    final tras = await base.select(base.orders).get();
    for (final id in deLaZona) {
      final p = tras.firstWhere((o) => o.id == id);
      expect(p.resultado, ResultadoParada.entregado);
      expect(p.deliveredAt, laHoraDelPatio);
    }
    expect(tablero.columnas.map((c) => c.nombre).toList(), ['Vista', 'Centro']);
    expect(
      tablero.deColumna(zonaCentro).single.pedido.pedidoId,
      'p7',
      reason: 'lo que hizo la web mientras tanto tampoco se pierde',
    );
    expect(tablero.deColumna(zonaVista), isEmpty);

    // Y la cola quedó limpia, sin un solo rechazo que nadie fuera a mirar.
    expect(await ColaDeSalida(base).lote(), isEmpty);
    final rechazados = await (base.select(
      base.apuntes,
    )..where((a) => a.estado.equalsValue(EstadoApunte.rechazado))).get();
    expect(rechazados, isEmpty);
  });

  test(
    'la ruta completada sin señal sobrevive a cerrar y reabrir la aplicación, '
    'aunque no haya subido',
    () async {
      // «Eso no lo puede perder por ninguna circunstancia porque es trabajo
      // perdido». La base va a un FICHERO: en memoria esto pasaría sin decir
      // nada de lo que se quiere comprobar.
      var contenedor = montar();
      var tablero = await contenedor.read(tableroProvider.future);
      expect(tablero.columnas.single.pedidos, 6);

      servidor.hayRed = false;
      final rutaId = await contenedor
          .read(tableroProvider.notifier)
          .armarRuta(zonaVista);
      await acciones().cerrar(rutaId, [
        for (final id in deLaZona)
          MarcaDeParada(pedidoId: id, resultado: ResultadoParada.entregado),
      ]);
      await acciones().completar(rutaId);

      // Se cierra la aplicación del todo y se vuelve a abrir el MISMO fichero.
      contenedor.dispose();
      await base.close();
      base = BaseLocal.con(NativeDatabase(fichero));
      contenedor = montar();
      addTearDown(contenedor.dispose);

      tablero = await contenedor.read(tableroProvider.future);
      expect(await enUnaRuta(), deLaZona);
      expect(await enElTablero(), isEmpty);
      expect(await enLosDosSitios(), isEmpty);
      final p1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p1'))).getSingle();
      expect(p1.resultado, ResultadoParada.entregado);
      expect(p1.deliveredAt, laHoraDelPatio);

      // Y los tres apuntes siguen enteros, esperando señal.
      final cola = await ColaDeSalida(base).lote();
      expect(cola.map((a) => a.ruta).toList(), [
        '/board/columns/$zonaVista/route',
        '/routes/$rutaId/results',
        '/routes/$rutaId',
      ]);
      expect(cola.every((a) => a.estado == EstadoApunte.pendiente), isTrue);
    },
  );

  test('la web saca un pedido de la zona mientras el móvil arma y completa esa '
      'ruta: el servidor arma la ruta SIN él, y AHORA se dice quién falta', () async {
    // ESTE ERA EL AGUJERO, y la prueba está para que no se vuelva a abrir.
    //
    // El servidor sólo puede armar la ruta con los pedidos que siguen puestos
    // en esa zona cuando le llega el apunte —horas después, y para entonces la
    // web ya movió una tarjeta—: p3 se fue a «Centro», así que la ruta de allá
    // nace con cinco aunque el móvil entregara seis. Eso no lo arregla la lista
    // de `pedidoIds`: un pedido que ya no está en la zona no se puede enganchar
    // desde aquí.
    //
    // **Lo que sí cambió el 28/09/2026 es que deja de ser mudo.** Con la lista
    // viajando, el servidor sabe que el aparato contaba con p3 y lo NOMBRA en
    // `descartados`; el aparato lo guarda y la franja lo dice. Antes: el móvil
    // entregó seis, el servidor supo de cinco, y no se enteraba nadie.
    final contenedor = montar();
    addTearDown(contenedor.dispose);

    var tablero = await contenedor.read(tableroProvider.future);
    expect(tablero.columnas.single.pedidos, 6);

    // Sin señal: se arma la ruta de la zona y se completa entera.
    servidor.hayRed = false;
    final mando = contenedor.read(tableroProvider.notifier);
    final rutaId = await mando.armarRuta(zonaVista);
    await acciones().cerrar(rutaId, [
      for (final id in deLaZona)
        MarcaDeParada(pedidoId: id, resultado: ResultadoParada.entregado),
    ]);
    await acciones().completar(rutaId);

    // A la vez, en la oficina: p3 se saca de «Vista» y se lleva a otra zona.
    // Para el servidor eso es legal — ahí todavía no existe ninguna ruta.
    servidor
      ..laWebCreaZona(zonaCentro, 'Centro')
      ..laWebColoca('p3', zonaCentro);

    // Vuelve la señal y sube todo.
    servidor.hayRed = true;
    expect(await subirLaCola().ciclo(), 3);

    // LO QUE PASA HOY, dicho sin adornos:
    expect(servidor.rutas['ruta-servidor-1'], [
      'p1',
      'p2',
      'p4',
      'p5',
      'p6',
    ], reason: 'la ruta del servidor se armó con lo que ÉL tenía en la zona');
    expect(
      servidor.resultados.containsKey('p3'),
      isFalse,
      reason:
          'HALLAZGO: p3 se entregó de verdad y su resultado no llega a ningún '
          'sitio — el servidor lo descarta por no ir en esa ruta',
    );
    final rechazados = await (base.select(
      base.apuntes,
    )..where((a) => a.estado.equalsValue(EstadoApunte.rechazado))).get();
    expect(
      rechazados,
      isEmpty,
      reason:
          'y no es un rechazo: el apunte entró, la ruta existe arriba. '
          'Reintentarlo armaría una SEGUNDA ruta',
    );

    // PERO YA NO ES MUDO. El aviso espera a que alguien lo lea, con p3
    // nombrado y con qué hacer: «comprueba si se entregó igual».
    final aviso = (await ColaDeSalida(base).descartesSinLeer().first).single;
    expect(aviso.motivo, contains('p3'));
    expect(
      aviso.motivo,
      contains('ya no estaba en esa zona cuando llegó tu apunte'),
      reason:
          'ÉSE es el pedido que el repartidor puede llevar entregado, y es el '
          'que la ruta del servidor no tiene: si no se dice aquí, no se dice '
          'en ningún sitio',
    );

    // ---- Lo que sí sujeta el aparato, y hay que dejarlo sujeto. ---------
    await mando.bajarDelServidor();
    tablero = await contenedor.read(tableroProvider.future);

    // p3 vuelve a aparecer en el tablero, porque la web lo dejó puesto.
    final tarjeta = tablero.deColumna(zonaCentro).single;
    expect(tarjeta.pedido.pedidoId, 'p3');

    // Pero sale MARCADO —«Ya va en otra ruta»— y esa marca es grave, así que
    // **no se puede volver a meter en una ruta desde aquí**. Es la única
    // barrera que queda contra la entrega doble cuando el servidor deja un
    // entregado suelto en el tablero.
    expect(tarjeta.pedido.marcas, contains(MarcaTarjeta.enOtraRuta));
    expect(
      tarjeta.pedido.repartible,
      isFalse,
      reason:
          'p3 ya se entregó: si esta marca deja de ser grave, la zona lo mete '
          'en otra ruta y sale un segundo camión con el mismo bulto',
    );

    await expectLater(
      mando.armarRuta(zonaCentro),
      throwsA(
        isA<RechazoDelTablero>()
            .having(
              (e) => e.mensaje,
              'mensaje',
              'La columna no tiene ningún pedido que se pueda repartir hoy',
            )
            .having(
              (e) => e.detalles.join(' | '),
              'detalles',
              contains('Ya va en otra ruta'),
            ),
      ),
    );
    expect(
      await base
          .customSelect(
            'SELECT count(*) AS n FROM ${EsquemaTablero.colocaciones} '
            'WHERE order_id = ?1',
            variables: [Variable<String>('p3')],
          )
          .getSingle()
          .then((f) => f.read<int>('n')),
      1,
      reason: 'y se queda puesto y a la vista, no se esconde (§7.2)',
    );

    // El armador de rutas tampoco lo ofrece: sigue teniendo ruta.
    final ofrecidos = await ConsultasRutas(base)
        .disponibles(sucursalId: sucursalStg);
    expect(ofrecidos.map((p) => p.id).toList(), ['p7']);
  });
}
