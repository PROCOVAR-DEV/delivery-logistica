// Lo común de las pruebas de distribución: un servidor de mentira, el cliente montado encima y un recorrido de ejemplo.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/distribucion/datos/api_distribucion.dart';

import '../../apoyo/servidor_falso.dart';

class ApiDePrueba {
  ApiDePrueba(this.contesta) {
    servidor = ServidorFalso((p) => contesta(p));
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
      ..httpClientAdapter = servidor;
    api = ApiDistribucion(ClienteApi(dio: dio, esperas: const <Duration>[]));
  }

  Future<RespuestaFalsa?> Function(PeticionVista) contesta;
  late final ServidorFalso servidor;
  late final ApiDistribucion api;
}

/// La hora `h:m` del 4/11/2026 en UTC, como la manda el servidor.
String utc(int h, int m, [int s = 0]) =>
    DateTime.utc(2026, 11, 4, h, m, s).toIso8601String();

/// Un recorrido de ejemplo con tres paradas: la 1 marcada junto a su punto, la 2 marcada a ~1,1 km, la 3 sin marcar.
Map<String, Object?> trackDeEjemplo({
  String estado = 'completed',
  bool conPuntos = true,
  bool truncado = false,
}) => {
  'ruta': {
    'id': 'R1',
    'codigo': 'RT-001',
    'nombre': 'Reparto Vista',
    'estado': estado,
    'inicio': utc(13, 0),
    'fin': estado == 'completed' ? utc(16, 0) : null,
    'distribuidorId': 'D1',
    'distribuidor': 'Felix',
    'vehiculoId': 'V1',
    'vehiculo': 'Triciclo-Felix',
  },
  'puntos': conPuntos
      ? [
          {
            'id': 'g0',
            'lat': 23.1000,
            'lng': -82.4500,
            'hora': utc(13, 0),
            'evento': 'inicio',
          },
          {'id': 'g1', 'lat': 23.1003, 'lng': -82.4002, 'hora': utc(13, 20)},
          {
            'id': 'g2',
            'lat': 23.1003,
            'lng': -82.4002,
            'hora': utc(13, 40),
            'evento': 'parada',
            'pedidoId': 'o1',
          },
          {
            'id': 'g3',
            'lat': 23.2100,
            'lng': -82.3000,
            'hora': utc(14, 30),
            'evento': 'parada',
            'pedidoId': 'o2',
          },
          {
            'id': 'g4',
            'lat': 23.1000,
            'lng': -82.4500,
            'hora': utc(16, 0),
            'evento': 'fin',
          },
        ]
      : <Object?>[],
  'paradas': [
    {
      'pedidoId': 'o1',
      'factura': 'Factura 1001',
      'cliente': 'Cliente Uno',
      'lat': 23.1003,
      'lng': -82.4002,
      'orden': 1,
      'resultado': 'entregado',
      'resultadoAt': utc(13, 40),
      'nota': 'Dejado en la puerta',
      'cobroEntrega': 'cobrado',
      'cobroEntregaAt': utc(13, 41),
    },
    {
      'pedidoId': 'o2',
      'factura': 'Factura 1002',
      'cliente': 'Cliente Dos',
      'lat': 23.2000,
      'lng': -82.3000,
      'orden': 2,
      'resultado': 'devuelto',
      'resultadoAt': utc(14, 30),
      'cobroEntrega': 'no_cobrado',
    },
    {
      'pedidoId': 'o3',
      'factura': 'Factura 1003',
      'cliente': 'Cliente Tres',
      'lat': 23.15,
      'lng': -82.35,
      'orden': 3,
    },
  ],
  'truncado': truncado,
};

/// Monta [hijo] con la API de mentira, sin tocar la red, el mapa ni la base.
Future<void> montar(
  WidgetTester tester,
  Widget hijo,
  ApiDePrueba api, {
  List<Override> mas = const [],
  Size tamano = const Size(900, 1400),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiDistribucionProvider.overrideWithValue(api.api),
        fondoDeCallesProvider.overrideWithValue(const SinCalles()),
        recorridoPorCallesProvider.overrideWithValue(
          const SinCallesQueSeguir(),
        ),
        ...mas,
      ],
      child: MaterialApp(home: Scaffold(body: hijo)),
    ),
  );
  await asentar(tester);
}

/// Dio contesta con temporizadores: se avanza el reloj falso unos instantes.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
