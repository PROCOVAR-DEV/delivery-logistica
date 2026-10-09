import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/barra_superior.dart';
import 'package:reparto/navegacion/menu_de_cuenta.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/servidor_falso.dart';

/// CERRAR SESIÓN CON LA COLA LLENA.
///
/// El último tramo de la jornada sin señal y el único en el que una persona
/// puede tirar el día con un dedo. El aviso tiene que decir **cuántos** apuntes
/// quedan, porque «tienes trabajo sin subir» no le dice a nadie si es un gesto
/// suelto o la tarde entera.
///
/// Y va en pareja, que es la regla del §3-quinquies: una prueba de que el aviso
/// SALE cuando toca, y otra de que **NO sale** cuando no. Un aviso que aparece
/// siempre deja de leerse, y entonces tampoco se lee el día que importa.
///
/// La base va a un FICHERO y no a memoria por lo mismo que las de la jornada:
/// lo que se comprueba aquí es que salir NO se lleva por delante lo que vive en
/// el aparato, y eso en memoria no se distingue de nada.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late Directory carpeta;
  late BaseLocal base;
  late AlmacenEnMemoria almacen;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('salir_con_cola');
    base = BaseLocal.con(
      NativeDatabase(File('${carpeta.path}/reparto.sqlite')),
    );
    almacen = AlmacenEnMemoria(
      Sesion.deJson(<String, Object?>{
        'token': tokenDePrueba(nombre: 'Yasmani Cala', correo: 'y@procovar.cu'),
        'refresh_token': 'r-1',
      }),
    );
  });

  tearDown(() async {
    await base.close();
    if (carpeta.existsSync()) await carpeta.delete(recursive: true);
  });

  /// Sólo la barra superior: no hace falta la aplicación entera para probar un
  /// aviso de dos renglones, y montarla arrastraría el portero, el arranque y la
  /// bajada del día a una prueba que va de eso.
  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 17, 18, 40)),
          almacenSesionProvider.overrideWithValue(almacen),
          // NI UNA PETICIÓN A UN DOMINIO DE VERDAD. `dioAuthProvider` sale de
          // `Entorno.authUrl`, que trae producción como valor por defecto: sin
          // esta sustitución, pulsar «Salir» le manda un `POST /logout` a
          // Procovar desde el ordenador de Jose.
          dioAuthProvider.overrideWithValue(
            dioFalso(
              (p) async => RespuestaFalsa(200, const <String, Object?>{}),
            ),
          ),
          clienteApiProvider.overrideWithValue(
            clienteFalso(
              (p) async => RespuestaFalsa(200, const <String, Object?>{}),
            ),
          ),
        ],
        child: MaterialApp(
          theme: temaDeReparto(),
          home: const Scaffold(body: BarraSuperior(titulo: 'Panel')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    // Las consultas de Drift sueltan un temporizador al cancelarse y
    // flutter_test lo comprueba ANTES de los `tearDown`.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Future<void> pulsarCerrarSesion(WidgetTester tester) async {
    await tester.tap(find.byType(MenuDeCuenta));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
  }

  /// La tarde de trabajo que todavía no ha salido del teléfono.
  Future<List<String>> laTardeSinSubir(int cuantos) async {
    final cola = ColaDeSalida(base);
    return [
      for (var i = 1; i <= cuantos; i++)
        await cola.encolar(
          metodo: 'POST',
          ruta: '/routes/r-$i/results',
          cuerpo: <String, Object?>{'n': i},
        ),
    ];
  }

  testWidgets(
    'con la tarde entera sin subir, el aviso dice CUÁNTOS y en plural',
    (tester) async {
      // MONTAR PRIMERO Y SEMBRAR DESPUÉS (§3-ter). Quien cierra sesión lleva la
      // pantalla abierta desde antes: el trabajo se acumuló con ella delante.
      await montar(tester);
      await laTardeSinSubir(7);

      await pulsarCerrarSesion(tester);

      expect(find.text('Queda trabajo sin subir'), findsOneWidget);
      expect(
        find.textContaining('7 apuntes sin subir'),
        findsOneWidget,
        reason:
            'el número es lo único que distingue un gesto suelto de la tarde '
            'entera, y es lo que decide si esa persona se espera o no',
      );
      // «conecta y espera» sigue estando, en minúscula y como consejo, no como
      // amenaza: el texto dejó de decir que salir borra el trabajo, porque desde
      // que cada persona tiene su base eso ya no ocurre.
      expect(find.textContaining('conecta y espera'), findsOneWidget);

      await tester.tap(find.text('Me quedo'));
      await tester.pumpAndSettle();
      await desmontar(tester);
    },
  );

  testWidgets('«Me quedo» no toca NADA: ni la cola, ni la sesión', (
    tester,
  ) async {
    await montar(tester);
    final claves = await laTardeSinSubir(3);

    await pulsarCerrarSesion(tester);
    expect(find.text('Queda trabajo sin subir'), findsOneWidget);
    await tester.tap(find.text('Me quedo'));
    await tester.pumpAndSettle();

    expect(find.text('Queda trabajo sin subir'), findsNothing);
    expect(
      (await ColaDeSalida(base).lote()).map((a) => a.clave).toList(),
      claves,
      reason: 'nada se borra por haber pulsado sin querer',
    );
    expect(
      await almacen.leer(),
      isNotNull,
      reason: 'y la sesión sigue abierta: no se salió a medias',
    );

    await desmontar(tester);
  });

  testWidgets('sin nada pendiente NO pregunta nada: se sale y ya', (
    tester,
  ) async {
    // LA OTRA MITAD DE LA PAREJA. Un aviso que sale en cada salida deja de
    // leerse a la tercera semana, y entonces tampoco se lee el día que de
    // verdad quedaba la tarde entera dentro del teléfono.
    await montar(tester);
    expect(await base.cuantosPendientes(), 0);

    await pulsarCerrarSesion(tester);

    expect(find.text('Queda trabajo sin subir'), findsNothing);
    expect(find.text('Hay cambios sin guardar'), findsNothing);
    expect(find.text('Salir de todos modos'), findsNothing);
    expect(
      await almacen.leer(),
      isNull,
      reason: 'sin nada que avisar, «Cerrar sesión» cierra la sesión',
    );

    await desmontar(tester);
  });

  testWidgets('lo ENTREGADO A REVISIÓN no es «sin subir»: no pregunta, se sale', (
    tester,
  ) async {
    // Ya está arriba, en la bandeja de un administrador: decir «queda trabajo sin subir»
    // de algo que no sube solo es el aviso que nunca se va (`bandeja-de-revision.md`,
    // B.5). Lo que SÍ avisa de ello es olvidar la copia de la persona
    // (`nucleo/cola/revision_test.dart`).
    await montar(tester);
    final cola = ColaDeSalida(base);
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/routes/r-1/results',
      cuerpo: const <String, Object?>{'n': 1},
    );
    await cola.marcarEnRevision(clave, entrega: 'ent-1');
    expect(await base.cuantosPendientes(), 0);
    expect(await base.cuantosEnRevision(), 1);

    await pulsarCerrarSesion(tester);

    expect(find.text('Queda trabajo sin subir'), findsNothing);
    expect(await almacen.leer(), isNull, reason: 'se cerró la sesión');
    expect(
      (await cola.porClave(clave))!.estado,
      EstadoApunte.enRevision,
      reason: 'y lo entregado sigue en el aparato, con su estado',
    );

    await desmontar(tester);
  });

  testWidgets(
    'un apunte RECHAZADO no cuenta como pendiente, pero sigue en su bandeja '
    'después de salir',
    (tester) async {
      // Nada se descarta en silencio (regla 6). Un rechazado no va a subir solo
      // —espera a que una persona decida—, así que avisar de él al salir sería
      // el aviso que sale siempre. Pero tiene que seguir ahí cuando esa persona
      // vuelva a entrar, o lo único que quedaba de un gesto que no llegó
      // desaparece por haber cerrado sesión.
      await montar(tester);
      final cola = ColaDeSalida(base);
      final clave = await cola.encolar(
        metodo: 'PUT',
        ruta: '/board/placements/p-7',
        cuerpo: const <String, Object?>{'columnaId': 'z-1', 'posicion': 0},
      );
      await cola.resolver(
        clave,
        const ResultadoApunte(
          estado: EstadoResultado.rechazado,
          motivo: 'Ese pedido ya va en otra ruta',
        ),
      );

      await pulsarCerrarSesion(tester);
      expect(find.text('Queda trabajo sin subir'), findsNothing);

      // NADA DE `await` SOBRE EL PRIMER VALOR DE UN STREAM DE DRIFT AQUÍ
      // DENTRO. En un widget test el tiempo no avanza solo y la prueba se
      // CUELGA en vez de fallar (`CLAUDE.md` §5): se cazó escribiendo ésta. La
      // bandeja se mira con una consulta, que es lo que contesta sin esperar.
      final bandeja = await (base.select(
        base.apuntes,
      )..where((a) => a.estado.equalsValue(EstadoApunte.rechazado))).get();
      expect(bandeja.single.clave, clave);
      expect(
        bandeja.single.motivo,
        'Ese pedido ya va en otra ruta',
        reason: 'con su motivo literal, que es lo que dice qué hacer',
      );

      await desmontar(tester);
    },
  );

  testWidgets(
    'salir con trabajo dentro NO se lo lleva: sigue en el aparato para cuando '
    'vuelva quien lo hizo',
    (tester) async {
      // Desde el 15/09/2026 cada persona tiene su copia de la base y salir
      // **cambia de copia en vez de borrar** (`nucleo/base/base.dart` y
      // `navegacion/portero.dart`). Lo que no puede pasar de ninguna manera es
      // que salir se lleve por delante una tarde de trabajo: eso es justo lo
      // que el aviso existe para evitar, y si además ocurriera de verdad el
      // aviso sería lo único entre el dedo y el día perdido.
      await montar(tester);
      final claves = await laTardeSinSubir(4);

      await pulsarCerrarSesion(tester);
      await tester.tap(find.text('Salir de todos modos'));
      await tester.pumpAndSettle();

      expect(
        (await ColaDeSalida(base).lote()).map((a) => a.clave).toList(),
        claves,
        reason:
            'la cola se queda entera en la copia de quien se va, y sube el día '
            'que vuelva a entrar con SU token',
      );
      expect(await almacen.leer(), isNull, reason: 'y la sesión sí se cierra');

      await desmontar(tester);
    },
  );

  testWidgets('en la WEB el aviso habla de cambios que no se guardaron', (
    tester,
  ) async {
    // La red ya estaba puesta para esto (`test/navegacion/menu_de_cuenta_test.
    // dart`); aquí se comprueba con la cola LLENA y contando, que es el lado
    // que esta carpeta vigila. En un navegador cada gesto sale en el momento:
    // si algo se quedó dentro no es trabajo esperando a que haya red, es un
    // cambio que NO se pudo guardar.
    await Destino.comoSiFueraWeb(() async {
      await montar(tester);
      await laTardeSinSubir(2);

      await pulsarCerrarSesion(tester);

      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      expect(find.textContaining('2 cambios'), findsOneWidget);
      expect(
        find.textContaining('Conecta y espera'),
        findsNothing,
        reason: 'ya está conectada: es la web',
      );

      await tester.tap(find.text('Me quedo'));
      await tester.pumpAndSettle();
      await desmontar(tester);
    });
  });

  testWidgets('el aviso NO amenaza con perder lo que no se pierde', (
    tester,
  ) async {
    // Decía «se borra lo de este aparato y ese trabajo se pierde». Era verdad
    // cuando había UNA base para todos; desde que cada persona tiene la suya,
    // `salir()` sólo revoca el token y la cola se queda entera — lo demuestra
    // la prueba de aquí al lado, «salir con trabajo dentro NO se lo lleva».
    //
    // Un aviso que amenaza con una pérdida que no ocurre es peor que no
    // avisar: se lee una vez, se comprueba que era mentira, y deja de leerse
    // el día que diga la verdad.
    await laTardeSinSubir(3);
    await montar(tester);
    await pulsarCerrarSesion(tester);

    for (final mentira in const [
      'se borra lo de este aparato',
      'ese trabajo se pierde',
      'Salir y perderlo',
    ]) {
      expect(
        find.textContaining(mentira),
        findsNothing,
        reason: '«$mentira» ya no es verdad y asusta para nada',
      );
    }

    // Y lo que SÍ es verdad tiene que seguir dicho: nadie lo ve hasta que suba.
    expect(find.textContaining('NO los borra'), findsOneWidget);
    expect(find.textContaining('nadie los ve'), findsOneWidget);

    await desmontar(tester);
  });
}
