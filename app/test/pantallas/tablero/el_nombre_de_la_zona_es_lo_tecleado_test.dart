// EL NOMBRE DE LA ZONA ES EXACTAMENTE LO QUE SE TECLEÓ — 01/10/2026.
//
// El aviso: «al crear una zona en el Tablero el nombre se guarda con dos letras
// de más delante». Medido desde el navegador con automatización (Playwright por
// CDP): se tecleó `QA-FINAL-1117` y en el tablero quedó `fiQA-FINAL-1117`; se
// tecleó `QA-RUTA-1123` y quedó `esQA-RUTA-1123`. Dos de tres veces, y siempre
// «abrir «+ Columna» y escribir enseguida».
//
// El precedente de la casa apuntaba a la pieza compartida: en `CajaDeBusqueda`,
// el eco de la búsqueda anterior reescribía el campo por detrás y `CHAPLIN` se
// quedaba en `CH`. Esto se parecía al mismo mecanismo por el otro lado.
//
// Lo que esta prueba ata es el camino de verdad, por la pantalla y con el dedo:
// abrir «+ Columna», escribir letra a letra SIN dejar que el cajón se asiente
// —que es la condición que se contó— y comprobar que lo que se guarda en la
// base y lo que sale hacia el servidor son los caracteres tecleados, ni uno
// más. No había ninguna prueba que entrara el nombre de una zona por la
// interfaz: `columnas_test.dart` llama a `crearColumna` a pelo, así que todo lo
// que pase entre el `TextField` y el repositorio salía verde por no mirarse.
//
// Se escribe letra a letra a propósito. Un `enterText` de golpe es un solo
// `updateEditingValue` con el texto entero y no ejerce nada: lo que se denunció
// es un campo que arranca con basura dentro y la primera pulsación se le pega
// delante.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

const _escritorio = Size(1400, 900);

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  // Aquí SÓLO se abre la base. Sembrar en el `setUp` de un `testWidgets` es la
  // segunda trampa del §5: lo que Drift deja empezado fuera del reloj falso no
  // avanza dentro y la prueba se cuelga en vez de fallar.
  setUp(() {
    base = BaseLocal.con(NativeDatabase.memory());
    servidor = ServidorFalso((peticion) async => null);
  });

  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget montar() {
    final dio = Dio()..httpClientAdapter = servidor;
    return ProviderScope(
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
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  Future<void> abrirElTablero(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(_escritorio);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await tester.pumpWidget(montar());
    await asentar(tester);
  }

  /// EL CAMPO DEL NOMBRE, Y NO «EL ÚNICO QUE HAY»: con el cajón abierto hay DOS
  /// `TextField` en el árbol —el buscador del tablero, que se queda debajo, y
  /// éste—. `find.byType(TextField)` revienta con «Too many elements», y eso es
  /// lo mejor que puede pasar: una prueba que cogiera el otro campo escribiría
  /// en el buscador y saldría verde sin haber tecleado una letra en la zona.
  final campoDelNombre = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Nombre de la zona',
  );

  /// Teclea [texto] letra a letra, con un respiro de 10 ms entre pulsaciones.
  /// Cada pasada es una pulsación de verdad: si algo repinta el campo por detrás
  /// entre dos letras, aquí se ve.
  Future<void> teclear(WidgetTester tester, String texto) async {
    for (var i = 1; i <= texto.length; i++) {
      await tester.enterText(campoDelNombre, texto.substring(0, i));
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  String loQueDiceElCampo(WidgetTester tester) =>
      tester.widget<TextField>(campoDelNombre).controller!.text;

  testWidgets('«+ Columna» y escribir enseguida guarda lo tecleado, sin basura '
      'delante', (tester) async {
    await abrirElTablero(tester);

    // El «+» de la tira. Sin ninguna zona, el tablero pinta el cartel de «las
    // zonas las pones tú» con su botón.
    await tester.tap(find.text('Nueva columna'));
    // UNA SOLA PASADA, a propósito: el cajón entra en 180 ms y el `autofocus`
    // engancha el campo en la primera. «Escribir enseguida» es justamente esto,
    // y asentar antes de teclear sería no probar la condición que se contó.
    await tester.pump();

    const tecleado = 'QA-FINAL-1117';
    await teclear(tester, tecleado);

    // Lo que el campo tiene por dentro, antes de guardar. Si algo se le hubiera
    // pegado delante, está aquí.
    expect(
      loQueDiceElCampo(tester),
      tecleado,
      reason:
          'el campo tiene que contener exactamente lo tecleado; dos letras de '
          'más delante son las que llegaron a producción como «fiQA-FINAL-1117»',
    );

    await tester.tap(find.text('Guardar'));
    await asentar(tester);

    final columnas = await ConsultasTablero(base).columnas(sucursalStg);
    expect(
      columnas.map((c) => c.nombre).toList(),
      [tecleado],
      reason:
          'el nombre guardado es el que el logístico de Santiago va a ver en su '
          'tablero: con basura delante la zona queda con un nombre inventado',
    );

    // Y lo mismo hacia arriba: la zona que suba al servidor lleva ese nombre.
    final apunte = (await ColaDeSalida(base).lote()).single;
    expect(apunte.cuerpo, contains('"nombre":"$tecleado"'));

    await desmontar(tester);
  });

  testWidgets('renombrar una zona tampoco se arrastra el nombre viejo', (
    tester,
  ) async {
    // El mismo campo sirve para renombrar, y ahí SÍ arranca con texto dentro:
    // es el único sitio del proyecto donde el nombre de una zona parte de algo
    // que ya estaba escrito. Si el campo se pudiera quedar a medio limpiar, se
    // vería aquí.
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await tester.binding.setSurfaceSize(_escritorio);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(montar());
    await asentar(tester);

    await tester.tap(find.text('Nueva columna'));
    await tester.pump();
    await teclear(tester, 'Centro');
    await tester.tap(find.text('Guardar'));
    await asentar(tester);

    await tester.tap(find.byTooltip('Opciones de la columna'));
    await asentar(tester);
    await tester.tap(find.text('Renombrar'));
    await tester.pump();

    expect(
      loQueDiceElCampo(tester),
      'Centro',
      reason: 'renombrar parte del nombre que hay, no de otro',
    );

    // Se borra y se escribe otro, que es lo que hace una persona.
    await tester.enterText(campoDelNombre, '');
    await tester.pump(const Duration(milliseconds: 10));
    await teclear(tester, 'Vista Alegre');
    await tester.tap(find.text('Guardar'));
    await asentar(tester);

    final columnas = await ConsultasTablero(base).columnas(sucursalStg);
    expect(columnas.map((c) => c.nombre).toList(), ['Vista Alegre']);

    await desmontar(tester);
  });
}
