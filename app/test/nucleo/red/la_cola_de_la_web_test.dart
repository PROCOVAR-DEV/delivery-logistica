// LA COLA DEL NAVEGADOR (04/11/2026): las escrituras de la web salen de UNA en UNA y en el orden en que se pidieron; un gesto que
// falla no bloquea a los siguientes; y el reintento de un corte de red manda el MISMO cuerpo (el mismo `id` que puso la web).

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';

import '../../apoyo/servidor_falso.dart';

void main() {
  late List<Completer<RespuestaFalsa?>> abiertas;
  late ServidorFalso servidor;
  late EscrituraEnVivo web;

  setUp(() {
    abiertas = [];
    servidor = ServidorFalso((_) {
      final c = Completer<RespuestaFalsa?>();
      abiertas.add(c);
      return c.future;
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
      ..httpClientAdapter = servidor;
    web = EscrituraEnVivo(ClienteApi(dio: dio, esperas: const [Duration.zero, Duration.zero], ordenarEscrituras: true));
  });

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('el segundo gesto no sale hasta que el primero termina, y salen en orden', () async {
    final alta = web.mandar(metodo: 'POST', ruta: '/routes', cuerpo: {'id': 'r1'});
    final cierre = web.mandar(metodo: 'POST', ruta: '/routes/r1/results');
    await tick();
    expect(servidor.vistas.map((p) => p.ruta), ['/routes'], reason: 'el cierre espera al alta');

    abiertas[0].complete(RespuestaFalsa(201, const {'id': 'r1'}));
    await alta;
    await tick();
    expect(servidor.vistas.map((p) => p.ruta), ['/routes', '/routes/r1/results']);
    abiertas[1].complete(RespuestaFalsa(200, const <String, Object?>{}));
    await cierre;
  });

  test('un gesto que falla no bloquea a los siguientes', () async {
    final malo = web.mandar(metodo: 'POST', ruta: '/routes', cuerpo: {'id': 'r1'});
    final bueno = web.mandar(metodo: 'POST', ruta: '/vehicles', cuerpo: {'id': 'v1'});
    final fallo = expectLater(malo, throwsA(isA<RechazoDelServidor>()));
    await tick();
    abiertas[0].complete(RespuestaFalsa(409, const {'error': 'Ese pedido ya va en otra ruta'}));
    await fallo;
    await tick();
    expect(servidor.vistas.last.ruta, '/vehicles');
    abiertas[1].complete(RespuestaFalsa(201, const {'id': 'v1'}));
    await bueno;
  });

  test('en la APK y el escritorio (sin ordenar) no se serializa nada: esa cola es la de disco', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))..httpClientAdapter = servidor;
    final aparato = ClienteApi(dio: dio, esperas: const []);
    final a = aparato.mandar<Object?>('POST', '/uno', null);
    final b = aparato.mandar<Object?>('POST', '/dos', null);
    await tick();
    expect(servidor.vistas.map((p) => p.ruta), ['/uno', '/dos'], reason: 'las dos salen a la vez');
    for (final c in abiertas) {
      c.complete(RespuestaFalsa(200, const <String, Object?>{}));
    }
    await Future.wait([a, b]);
  });

  test('un corte de red se reintenta con el MISMO cuerpo, o sea con el mismo id', () async {
    final f = web.mandar(metodo: 'POST', ruta: '/vehicles', cuerpo: {'id': 'v1', 'name': 'Camión'});
    await tick();
    abiertas[0].complete(null); // sin red
    await tick();
    abiertas[1].complete(RespuestaFalsa(201, const {'id': 'v1'}));
    await f;
    expect(servidor.vistas.length, 2);
    expect(servidor.vistas[0].cuerpo, servidor.vistas[1].cuerpo);
    expect((servidor.vistas[1].cuerpo as Map)['id'], 'v1');
  });
}
