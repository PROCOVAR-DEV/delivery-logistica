// LA TASA DE CAMBIO DE CADA SUCURSAL, Y LA BARRA QUE LA ENSEÑA.
//
// El fallo que esto cierra: el selector de moneda se quedaba PERMANENTEMENTE en la
// pastilla ambar «esta sucursal no tiene tasa de cambio todavia», en las ocho
// sucursales, tuvieran tasa o no. Leia la tabla local `currencies`, que no llenaba
// nadie — la bajada del dia no la trae.
//
// Y no se veia porque degradaba a un estado legitimo: «esta sucursal no tiene tasa»
// es una frase que puede ser verdad, asi que nadie la iba a cuestionar.
//
// La regla de las tres aplicaciones, que es lo que estas pruebas cuidan: **sin tasa
// de ESA sucursal no se convierte nada.** No se cae a la de otra ni a un numero por
// defecto. Se queda en USD y se dice por que.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/selector.dart';
import 'package:reparto/navegacion/barra_superior.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';

import '../apoyo/base_de_prueba.dart';

// El dato de produccion de hoy: solo HAB y STG tienen tasa (700 CUP/USD, del
// 09/09/2026, que Accesos da por NO fresca). Las otras seis no tienen.
const _tasaDeHoy = 700.0;
final _del9 = DateTime(2026, 9, 9, 22, 3, 4);

void main() {
  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Mete una sucursal tal como la dejaria la bajada del dia.
  Future<void> sucursal(
    String id,
    String nombre, {
    String? codigo,
    double? cupRate,
    DateTime? traidoAt,
    bool? fresca,
    String? fuente,
  }) => base
      .into(base.branches)
      .insertOnConflictUpdate(
        BranchesCompanion.insert(
          id: id,
          name: nombre,
          lat: 20,
          lng: -75,
          externalId: Value(codigo),
          cupRate: Value(cupRate),
          cupRateTraidoAt: Value(traidoAt),
          cupRateFresca: Value(fresca),
          cupRateFuente: Value(fuente),
        ),
      );

  /// Lee el provider con la sucursal elegida que se le diga.
  ///
  /// **Nada de `await` sobre el primer valor de un stream de Drift**: se monta un
  /// contenedor, se espera a que el stream entregue con `pump` del propio
  /// `sucursalesProvider` y se lee. Un `await` sobre `.first` dentro de un widget
  /// test no vuelve nunca si el stream ya emitio.
  Future<TasaDeLaMirada> mirar({String? elegida}) async {
    final contenedor = ProviderContainer(
      overrides: [baseProvider.overrideWithValue(base)],
    );
    addTearDown(contenedor.dispose);
    contenedor.read(sucursalMiradaProvider.notifier).mirar(elegida);
    // Se deja el stream vivo y se le da una vuelta al bucle de eventos para que
    // Drift entregue la primera lista.
    final quita = contenedor.listen(sucursalesProvider, (_, _) {});
    addTearDown(quita.close);
    await Future<void>.delayed(Duration.zero);
    return contenedor.read(tasaDeLaMiradaProvider);
  }

  // -------------------------------------------------------------------------
  // La regla, caso por caso
  // -------------------------------------------------------------------------

  test('sucursal CON tasa: se ofrece CUP, con su nota y su fecha', () async {
    await sucursal(
      'hab',
      'La Habana',
      codigo: 'HAB',
      cupRate: _tasaDeHoy,
      traidoAt: _del9,
      fresca: false,
      fuente: 'entrega',
    );
    await sucursal('gr', 'Granma', codigo: 'GR');

    final t = await mirar(elegida: 'hab');
    expect(t.hayCup, isTrue);
    expect(t.cupPorUsd, _tasaDeHoy);
    expect(t.traidoAt, _del9);
    expect(t.fuente, 'entrega');
    expect(t.motivo, isNull);
  });

  test('sucursal SIN tasa: USD, y el motivo lleva su nombre dentro', () async {
    await sucursal(
      'hab',
      'La Habana',
      codigo: 'HAB',
      cupRate: _tasaDeHoy,
      traidoAt: _del9,
      fresca: true,
    );
    await sucursal('gr', 'Granma', codigo: 'GR');

    final t = await mirar(elegida: 'gr');
    expect(t.hayCup, isFalse);
    // Se nombra SIEMPRE a la sucursal: «no hay tasa» a secas obliga a adivinar
    // cual de las ocho falta, que es lo que no se puede arreglar.
    expect(t.motivo, contains('Granma'));
    expect(t.motivo, contains('sólo se pueden ver en USD'));
  });

  test('«todas las sucursales»: no hay CUP aunque alguna tenga tasa', () async {
    await sucursal(
      'hab',
      'La Habana',
      codigo: 'HAB',
      cupRate: _tasaDeHoy,
      traidoAt: _del9,
      fresca: true,
    );
    await sucursal('gr', 'Granma', codigo: 'GR');

    // Sin elegir ninguna. No hay UNA tasa que valga para las dos.
    final t = await mirar();
    expect(t.hayCup, isFalse);
    expect(t.cupPorUsd, isNull);
    expect(t.motivo, contains('Elegí una sucursal'));
  });

  // ESTA ES LA IMPORTANTE.
  //
  // «A» va primera por nombre y tiene tasa; «B» va segunda y no tiene. Se mira B.
  // Si la guarda de «la tasa es de ESTA sucursal» se cayera —si se cogiera «la
  // primera», o «la que tenga tasa»— aqui saldria la tasa de A, que es exactamente
  // Granma enseñando los 685 de La Habana como si fueran suyos.
  test('la tasa de una sucursal NO se usa para otra', () async {
    await sucursal(
      'a',
      'A — con tasa',
      codigo: 'AAA',
      cupRate: _tasaDeHoy,
      traidoAt: _del9,
      fresca: true,
    );
    await sucursal('b', 'B — sin tasa', codigo: 'BBB');

    final t = await mirar(elegida: 'b');
    expect(
      t.cupPorUsd,
      isNull,
      reason:
          'se le aplico a «B — sin tasa» la tasa de «A — con tasa»: un importe '
          'convertido con la tasa de otra sucursal se lee bien y esta mal, que '
          'es lo peor que le puede pasar a un numero que alguien va a cobrar',
    );
    expect(t.motivo, contains('B — sin tasa'));
    expect(t.motivo, isNot(contains('A — con tasa')));
  });

  test('tasa vieja: se ofrece igual, CON aviso y con la fecha', () async {
    await sucursal(
      'stg',
      'Santiago',
      codigo: 'STG',
      cupRate: _tasaDeHoy,
      traidoAt: _del9,
      fresca: false,
    );

    final t = await mirar(elegida: 'stg');
    expect(t.hayCup, isTrue, reason: 'una tasa vieja convierte; ninguna, no');
    expect(t.fresca, isFalse);
    expect(t.aviso, 'La tasa es del 9/9/2026 y puede estar desfasada.');
  });

  test('tasa fresca: se ofrece SIN aviso', () async {
    await sucursal(
      'stg',
      'Santiago',
      codigo: 'STG',
      cupRate: _tasaDeHoy,
      traidoAt: DateTime(2026, 9, 15, 7),
      fresca: true,
    );

    final t = await mirar(elegida: 'stg');
    expect(t.hayCup, isTrue);
    expect(t.aviso, isNull);
  });

  // LA MARCA DE CUANDO, NO EL NUMERO (regla 3). El esquema viejo traia 320 por
  // defecto, asi que un numero suelto no demuestra que nadie haya puesto la tasa.
  test('un numero sin fecha NO es una tasa', () async {
    await sucursal('stg', 'Santiago', codigo: 'STG', cupRate: 320);

    final t = await mirar(elegida: 'stg');
    expect(
      t.hayCup,
      isFalse,
      reason:
          'un 320 sin fecha es el valor por defecto del esquema viejo, no '
          'una tasa que alguien haya puesto',
    );
    expect(t.motivo, contains('Santiago'));
  });

  test('una sola sucursal visible: esa es la que se mira', () async {
    // El logistico de una sucursal no elige nada —la barra le pone una etiqueta
    // fija— y aun asi tiene que poder ver CUP: «todas» y «la suya» son lo mismo
    // cuando solo hay una. La regla prohibida es elegir UNA de VARIAS.
    await sucursal(
      'stg',
      'Santiago',
      codigo: 'STG',
      cupRate: _tasaDeHoy,
      traidoAt: _del9,
      fresca: true,
    );

    final t = await mirar();
    expect(t.hayCup, isTrue);
    expect(t.cupPorUsd, _tasaDeHoy);
  });

  test('la sucursal elegida ya no esta en la lista: no hay tasa', () async {
    // El token dura siete dias y lleva dentro la sucursal de cuando se entro.
    await sucursal(
      'hab',
      'La Habana',
      codigo: 'HAB',
      cupRate: _tasaDeHoy,
      traidoAt: _del9,
      fresca: true,
    );
    await sucursal('gr', 'Granma', codigo: 'GR');

    final t = await mirar(elegida: 'una-que-ya-no-existe');
    expect(t.hayCup, isFalse);
    expect(t.motivo, contains('ya no está en la lista'));
  });

  test('sin sucursales bajadas todavia: USD, diciendolo', () async {
    final t = await mirar();
    expect(t.hayCup, isFalse);
    expect(t.motivo, contains('descargado'));
  });

  // -------------------------------------------------------------------------
  // Lo que se pinta
  // -------------------------------------------------------------------------

  group('el importe', () {
    final conTasa = TasaDeLaMirada.hay(cupPorUsd: 700, traidoAt: _del9);
    const sinTasa = TasaDeLaMirada.no('no hay');

    test('en CUP va SIN decimales', () {
      // Los precios reales van en cientos o miles y el centimo solo ensucia la
      // lectura.
      expect(conTasa.importe(12.34, 'CUP'), '8.638 CUP');
    });

    test('en USD van dos decimales', () {
      expect(conTasa.importe(12.3, 'USD'), '12,30 USD');
    });

    test('pedir CUP sin tasa devuelve el importe en USD, no un cero', () {
      expect(sinTasa.importe(12.34, 'CUP'), '12,34 USD');
    });

    test('sin importe, un guion y no un cero', () {
      expect(conTasa.importe(null, 'CUP'), '—');
    });
  });

  group('la barra superior', () {
    Future<void> montar(WidgetTester tester, {String? elegida}) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // La sucursal elegida se pone ANTES de montar, en el contenedor, y no
      // dentro de un `build`: tocar un provider mientras se construye el arbol
      // es un error de Riverpod, y con razon — dos widgets que miren lo mismo
      // acabarian viendo estados distintos.
      final contenedor = ProviderContainer(
        overrides: [baseProvider.overrideWithValue(base)],
      );
      addTearDown(contenedor.dispose);
      contenedor.read(sucursalMiradaProvider.notifier).mirar(elegida);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: contenedor,
          child: const MaterialApp(
            home: Scaffold(
              appBar: BarraSuperior(titulo: 'Panel'),
              body: SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('con tasa: el selector ofrece CUP con su fecha al lado', (
      tester,
    ) async {
      await sucursal(
        'stg',
        'Santiago',
        codigo: 'STG',
        cupRate: _tasaDeHoy,
        traidoAt: _del9,
        fresca: false,
      );
      await montar(tester);

      // Se mira el selector en el arbol y no se abre el desplegable: abrirlo es
      // una animacion de menu que en un test se pelea con el `IntrinsicWidth` de
      // la lista, y lo que hay que comprobar aqui es QUE opciones ofrece, no que
      // Flutter sepa pintar un menu.
      final selectores = tester
          .widgetList<Selector<String>>(find.byType(Selector<String>))
          .toList();
      expect(
        selectores,
        isNotEmpty,
        reason: 'con tasa tiene que haber un selector, no la pastilla ambar',
      );
      final moneda = selectores.last;
      final cup = moneda.opciones.where((o) => o.valor == 'CUP');
      expect(
        cup,
        hasLength(1),
        reason: 'con tasa se tiene que poder elegir CUP',
      );
      // La NOTA lleva la tasa Y SU FECHA. La fecha no es un adorno: es lo unico
      // que demuestra que la tasa es de verdad, y hoy la que hay es del dia 9.
      expect(cup.first.nota, contains('1 USD = 700'));
      expect(cup.first.nota, contains('del 9/9/2026'));
      // Y ninguna otra moneda: aqui no hay lista de monedas con tasas globales.
      expect(moneda.opciones.map((o) => o.valor), <String>['USD', 'CUP']);
    });

    testWidgets('sin tasa: pastilla ambar con el MOTIVO de verdad dentro', (
      tester,
    ) async {
      await sucursal('gr', 'Granma', codigo: 'GR');
      await montar(tester);

      final aviso = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message ?? '')
          .where((m) => m.contains('Granma'));
      expect(
        aviso,
        isNotEmpty,
        reason:
            'la pastilla ambar tiene que decir QUE sucursal no tiene tasa; el '
            'mensaje fijo de antes valia para las ocho y por eso nadie lo '
            'cuestionaba',
      );
      expect(aviso.first, contains('no tiene tasa de cambio todavía'));
    });

    testWidgets('«todas»: no se ofrece CUP y el motivo lo explica', (
      tester,
    ) async {
      await sucursal(
        'hab',
        'La Habana',
        codigo: 'HAB',
        cupRate: _tasaDeHoy,
        traidoAt: _del9,
        fresca: true,
      );
      await sucursal('gr', 'Granma', codigo: 'GR');
      await montar(tester);

      expect(find.text('CUP'), findsNothing);
      final avisos = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message ?? '');
      expect(avisos.where((m) => m.contains('Elegí una sucursal')), isNotEmpty);
    });

    // LA GUIA SEÑALA UNA OPCION DE DENTRO, no solo la caja que la abre.
    //
    // Tres pasos del manual apuntan ahi: «Elige de la lista. La primera opción es
    // «Todas (8)»» y «La opción de CUP lleva la tasa». El envoltorio lo pone
    // `Selector` cuando la pantalla le pasa `OpcionSelector.senalado`
    // (`diseno/selector.dart`), y ese cable **no lo vigila la prueba de contrato**
    // de `pantallas/ayuda/`: esa compara textos, y con `senalado:` escrito y el
    // envoltorio quitado sigue saliendo verde. Esto es lo unico que lo caza.
    //
    // Se abre el cajon de verdad: la opcion no existe hasta que se abre, y eso
    // tambien forma parte de lo que se esta comprobando.
    testWidgets('la opción «Todas» y la opción CUP se pueden señalar', (
      tester,
    ) async {
      RegistroDeControles.vaciar();
      addTearDown(RegistroDeControles.vaciar);

      await sucursal(
        'stg',
        'Santiago',
        codigo: 'STG',
        cupRate: _tasaDeHoy,
        traidoAt: _del9,
        fresca: true,
      );
      await sucursal(
        'hab',
        'La Habana',
        codigo: 'HAB',
        cupRate: _tasaDeHoy,
        traidoAt: _del9,
        fresca: true,
      );
      await montar(tester, elegida: 'stg');

      // Con el cajon cerrado no hay ninguna opcion montada, y por eso no se
      // puede senalar. Que es la verdad, y se comprueba para que la de abajo
      // signifique algo.
      expect(
        RegistroDeControles.donde(Senalado.barraElegirSucursal),
        isNull,
        reason: 'sin abrir el desplegable esa opción no existe todavía',
      );

      await tester.tap(find.text('Santiago'));
      await tester.pumpAndSettle();

      final todas = RegistroDeControles.donde(Senalado.barraElegirSucursal);
      expect(
        todas,
        isNotNull,
        reason:
            'el paso «Elige de la lista. La primera opción es «Todas (8)»» no '
            'tiene a qué apuntar: `OpcionSelector.senalado` no está llegando a '
            'un `ControlSenalado`.',
      );
      expect(
        todas!.rect.contains(
          tester.getRect(find.text('Todas las sucursales (2)')).center,
        ),
        isTrue,
        reason: 'el foco no cae en la opción de «todas», que es la marcada',
      );

      // Y la de CUP, que es la SEGUNDA de su lista: no vale con marcar «la
      // primera opción» y darlo por hecho.
      Navigator.of(tester.element(find.text('Santiago').last)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();

      final cup = RegistroDeControles.donde(Senalado.barraElegirMoneda);
      expect(
        cup,
        isNotNull,
        reason: 'el paso «La opción de CUP lleva la tasa» no tiene foco',
      );
      expect(
        cup!.rect.contains(tester.getRect(find.text('CUP').last).center),
        isTrue,
        reason: 'el foco de la moneda no cae en la fila de CUP',
      );
    });
  });
}
