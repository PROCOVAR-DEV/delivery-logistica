import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/barra_superior.dart';
import 'package:reparto/navegacion/menu_de_cuenta.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';

import '../apoyo/apoyo_sesion.dart';
import '../apoyo/base_de_prueba.dart';
import '../apoyo/servidor_falso.dart';

/// El identificador de la fila de la persona en la base de auth. Es LITERAL a
/// proposito: este es el numero que Jose vio en el menu, y la prueba que cuenta
/// aqui es la que falla si vuelve a salir.
const _sub = 'uaoOUHqTXNYUv672kjdLoZLpFrseCz9e';

Sesion _sesionConNombre() => Sesion.deJson(<String, Object?>{
  'token': tokenDePrueba(
    sub: _sub,
    nombre: 'Yoandry Pérez',
    correo: 'yoandry@procovar.cu',
    rol: 'SUPERVISOR',
  ),
  'refresh_token': 'r-1',
});

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Monta SÓLO la barra superior. No hace falta la aplicacion entera para
  /// probar un menu, y montarla arrastraria el portero, el arranque y la bajada
  /// del dia a una prueba que va de dos renglones de texto.
  Future<void> montar(
    WidgetTester tester, {
    Size tamano = const Size(1440, 900),
    Sesion? sesion,
    bool appsCaido = false,
    bool variasApps = false,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 14, 8, 30)),
          almacenSesionProvider.overrideWithValue(
            AlmacenEnMemoria(sesion ?? _sesionConNombre()),
          ),
          clienteApiProvider.overrideWithValue(
            clienteFalso((p) async {
              // `/apps` caido: 500, que es lo que pasa cuando la API esta en el
              // suelo. Lo demas contesta vacio.
              if (p.ruta.endsWith('/apps')) {
                if (appsCaido) return RespuestaFalsa(500, <String, Object?>{});
                return RespuestaFalsa(200, <String, Object?>{
                  'apps': <Object?>[
                    <String, Object?>{
                      'href': 'https://pedidos.procovar.cloud',
                      'icon': 'mdi:clipboard-list-outline',
                      'title': 'PEDIDO',
                      'description': 'Pedidos, clientes y vendedores.',
                    },
                    // La segunda y la tercera solo con `variasApps`: hay pruebas
                    // de aqui que cuentan textos («Ir a», findsOneWidget) y
                    // meterle baldosas a todas cambiaria lo que miden.
                    if (variasApps) ...[
                      <String, Object?>{
                        'href': 'https://analitics.procovar.cloud',
                        'icon': 'mdi:chart-bar',
                        'title': 'analitics',
                        'description': 'Informes de ventas.',
                      },
                      <String, Object?>{
                        'href': 'https://auth.procovar.cloud',
                        'icon': 'mdi:shield-account-outline',
                        'title': 'Accesos',
                        'description': 'Usuarios y sucursales.',
                      },
                    ],
                  ],
                });
              }
              return RespuestaFalsa(200, <String, Object?>{});
            }),
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

  Future<void> abrirElMenu(WidgetTester tester) async {
    await tester.tap(find.byType(MenuDeCuenta));
    await tester.pumpAndSettle();
  }

  testWidgets('el botón enseña el NOMBRE y su inicial, nunca el identificador', (
    tester,
  ) async {
    await montar(tester);

    expect(find.text('Yoandry Pérez'), findsOneWidget);
    expect(find.text('SUPERVISOR'), findsOneWidget);
    // El cuadro del avatar lleva la inicial del nombre, no un icono de persona.
    expect(find.text('Y'), findsOneWidget);
    expect(find.textContaining(_sub), findsNothing);

    await desmontar(tester);
  });

  testWidgets('el menú abierto NO enseña el identificador por ninguna parte', (
    tester,
  ) async {
    // ESTA es la regresion que queremos cazar. El menu de antes ponia el `sub`
    // de primer renglon: un numero de la base en la cara del logistico, que no
    // significa nada para quien lo lee.
    await montar(tester);
    await abrirElMenu(tester);

    expect(find.textContaining(_sub), findsNothing);
    // Y lo que SI tiene que decir: quien eres y como salir.
    expect(find.text('yoandry@procovar.cu'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('con /api/apps caído el menú sigue abriendo, y sin aviso rojo', (
    tester,
  ) async {
    // Las aplicaciones son un extra: el menu es «quien eres y salir». Si no
    // abriera sin red, el logistico del patio del almacen no podria ni salir.
    await montar(tester, appsCaido: true);
    await abrirElMenu(tester);

    expect(find.text('Yoandry Pérez'), findsWidgets);
    expect(find.text('yoandry@procovar.cu'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
    // Sin baldosas y sin rotulo: no ha fallado nada que la persona pidiera.
    expect(find.text('Ir a'), findsNothing);
    expect(find.textContaining('rror'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('con /api/apps en pie salen las aplicaciones, bajo «Ir a»', (
    tester,
  ) async {
    await montar(tester);
    await abrirElMenu(tester);

    expect(find.text('Ir a'), findsOneWidget);
    expect(find.text('PEDIDO'), findsOneWidget);
    expect(find.text('Pedidos, clientes y vendedores.'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('con VARIAS aplicaciones la Guía señala la primera baldosa', (
    tester,
  ) async {
    // El paso 2 de «Ir a otra aplicación de la casa» apunta a la seccion «Ir a»,
    // y hay UNA baldosa por aplicacion. `ControlSenalado` no es un `GlobalKey`:
    // marcar las tres no revienta nada, deja `donde` en `null` y el paso sale
    // **sin foco** con todas las pruebas de este fichero en verde. Esta es la
    // unica que lo caza, y por eso pide tres y no una.
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);

    await montar(tester, variasApps: true);
    await abrirElMenu(tester);

    expect(find.text('analitics'), findsOneWidget, reason: 'son tres baldosas');

    final puesto = RegistroDeControles.donde(Senalado.cuentaIrALaAplicacion);
    expect(
      puesto,
      isNotNull,
      reason:
          'con tres aplicaciones no hay a cuál señalar: la marca está en más de '
          'una baldosa y dos a la vez no se distinguen.',
    );
    expect(
      puesto!.rect.contains(tester.getRect(find.text('PEDIDO')).center),
      isTrue,
      reason: 'el foco no cae en la primera baldosa, que es la que se marcó',
    );
    expect(
      puesto.rect.contains(tester.getRect(find.text('Accesos')).center),
      isFalse,
      reason: 'el foco abarca también la última: no está señalando una baldosa',
    );

    await desmontar(tester);
  });

  testWidgets('antes de salir avisa de lo que queda sin subir, con su número', (
    tester,
  ) async {
    // Lo mejor que tiene este menu y lo unico que no viene de la de Next: salir
    // borra lo del aparato, y lo que no haya subido no lo ha visto nadie.
    await base
        .into(base.apuntes)
        .insert(
          ApuntesCompanion.insert(
            clave: '01J8AAAA',
            hechoAt: DateTime(2026, 9, 14, 7),
            metodo: 'POST',
            ruta: '/api/routes',
            cuerpo: '{}',
          ),
        );

    await montar(tester);
    await abrirElMenu(tester);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Queda trabajo sin subir'), findsOneWidget);
    expect(find.textContaining('1 apunte sin subir'), findsOneWidget);

    // «Me quedo» no sale: nada se borra por haber pulsado sin querer.
    await tester.tap(find.text('Me quedo'));
    await tester.pumpAndSettle();
    expect(find.text('Queda trabajo sin subir'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('sin nombre ni correo en el token: «Tu cuenta», y no se rompe', (
    tester,
  ) async {
    // Una sesion GUARDADA antes de que esto existiera no trae `name` ni `email`.
    // Eso no puede dejar el menu en blanco ni reventar el arranque.
    await montar(
      tester,
      sesion: Sesion.deJson(<String, Object?>{
        'token': tokenDePrueba(sub: _sub),
        'refresh_token': 'r-1',
      }),
    );
    await abrirElMenu(tester);

    expect(find.text('Tu cuenta'), findsWidgets);
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(find.textContaining(_sub), findsNothing);

    await desmontar(tester);
  });

  testWidgets('en móvil el menú es un CAJÓN, con su ✕ y sin nombre al lado', (
    tester,
  ) async {
    // Regla de la casa: cajon por debajo de 1024 px. Y en el boton no cabe el
    // nombre — a 390 px ese sitio es del titulo de la pantalla.
    await montar(tester, tamano: const Size(390, 800));

    expect(find.text('Yoandry Pérez'), findsNothing);
    expect(find.text('Y'), findsOneWidget);

    await abrirElMenu(tester);
    expect(find.text('Yoandry Pérez'), findsOneWidget);
    expect(find.byTooltip('Cerrar'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(find.textContaining(_sub), findsNothing);

    await desmontar(tester);
  });

  testWidgets('en la WEB el aviso de salir habla de cambios que no se guardaron, no de '
      'trabajo sin conexión', (tester) async {
    // La misma cuenta, otras palabras, porque no es lo mismo. En un navegador
    // cada gesto sale en el momento: si algo se quedó en la cola es que NO se
    // pudo guardar, no que esté esperando a que haya red. Decirle ahí «conecta
    // y espera a que suba» es mandarle a hacer algo que ya está hecho.
    //
    // Jose, 17/09/2026: «no sé cuántas veces tengo que decirte que la web
    // siempre está en línea, nunca se desconecta».
    await Destino.comoSiFueraWeb(() async {
      await base
          .into(base.apuntes)
          .insert(
            ApuntesCompanion.insert(
              clave: '01J8BBBB',
              hechoAt: DateTime(2026, 9, 14, 7),
              metodo: 'POST',
              ruta: '/api/routes',
              cuerpo: '{}',
            ),
          );

      await montar(tester);
      await abrirElMenu(tester);
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();

      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      expect(
        find.textContaining('no llegaron al servidor'),
        findsOneWidget,
        reason: 'eso es lo que de verdad pasó',
      );
      expect(
        find.textContaining('Conecta y espera'),
        findsNothing,
        reason: 'ya está conectada: es la web',
      );
      expect(
        find.textContaining('este aparato'),
        findsNothing,
        reason: 'en un navegador no hay «aparato» que guarde nada',
      );

      await tester.tap(find.text('Me quedo'));
      await tester.pumpAndSettle();
      await desmontar(tester);
    });
  });
}
