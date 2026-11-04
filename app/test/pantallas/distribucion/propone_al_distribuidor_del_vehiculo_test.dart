// AL ARMAR UNA RUTA CON UN VEHÍCULO SE PROPONE SU DISTRIBUIDOR (tarea 7).
//
// Se propone solo si ese distribuidor es de la sucursal de la ruta y está en activo; se ve elegido y con su motivo; se puede cambiar;
// y sin red (o sin distribuidor por defecto) no se propone nada y la ruta se arma igual.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/distribucion/datos/api_distribucion.dart';
import 'package:reparto/pantallas/distribuidores/vista/selector_de_distribuidor.dart';

import '../../apoyo/base_de_prueba.dart';

class _Anfitrion extends StatefulWidget {
  const _Anfitrion({required this.vehiculoId});

  final String? vehiculoId;

  @override
  State<_Anfitrion> createState() => _AnfitrionState();
}

class _AnfitrionState extends State<_Anfitrion> {
  String? elegido;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SelectorDeDistribuidor(
        sucursalId: 'B1',
        elegido: elegido,
        vehiculoId: widget.vehiculoId,
        alElegir: (id) => setState(() => elegido = id),
      ),
      Text('ELEGIDO=${elegido ?? 'nadie'}'),
    ],
  );
}

void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> sembrar() async {
    for (final (id, nombre, sucursal, activo) in const [
      ('d-juan', 'Juan', 'B1', true),
      ('d-pedro', 'Pedro', 'B1', false),
      ('d-luis', 'Luis', 'B2', true),
    ]) {
      await base
          .into(base.distribuidores)
          .insert(
            DistribuidoresCompanion.insert(
              id: id,
              nombre: nombre,
              activo: Value(activo),
              branchId: Value(sucursal),
            ),
          );
    }
    await RegistroDeFrescura(base).marcar(
      Colecciones.distribuidores,
      hasta: null,
      bajadaAt: DateTime(2026, 11, 4, 9),
      completa: true,
    );
  }

  Future<void> pintar(
    WidgetTester tester, {
    required String? vehiculoId,
    required Future<Map<String, String?>> Function() quienLoLleva,
  }) async {
    await sembrar();
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          distribuidorDeCadaVehiculoProvider.overrideWith(
            (ref) => quienLoLleva(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: _Anfitrion(vehiculoId: vehiculoId)),
        ),
      ),
    );
    await asentar(tester);
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'con un vehículo que lo lleva Juan, queda Juan elegido y se dice por qué',
    (tester) async {
      await pintar(
        tester,
        vehiculoId: 'V1',
        quienLoLleva: () async => {'V1': 'd-juan'},
      );
      expect(find.text('ELEGIDO=d-juan'), findsOneWidget);
      expect(
        find.byKey(SelectorDeDistribuidor.claveDeLoPropuesto),
        findsOneWidget,
      );
      await desmontar(tester);
    },
  );

  testWidgets('un distribuidor retirado o de otra sucursal NO se propone', (
    tester,
  ) async {
    await pintar(
      tester,
      vehiculoId: 'V1',
      quienLoLleva: () async => {'V1': 'd-pedro'},
    );
    expect(find.text('ELEGIDO=nadie'), findsOneWidget);
    expect(find.byKey(SelectorDeDistribuidor.claveDeLoPropuesto), findsNothing);
    await desmontar(tester);
  });

  testWidgets('un vehículo sin distribuidor por defecto no propone nada', (
    tester,
  ) async {
    await pintar(
      tester,
      vehiculoId: 'V2',
      quienLoLleva: () async => {'V1': 'd-juan'},
    );
    expect(find.text('ELEGIDO=nadie'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('sin red no se propone nada y el selector sigue sirviendo', (
    tester,
  ) async {
    await pintar(
      tester,
      vehiculoId: 'V1',
      quienLoLleva: () async => throw StateError('sin red'),
    );
    expect(find.text('ELEGIDO=nadie'), findsOneWidget);
    expect(find.byKey(SelectorDeDistribuidor.claveDelSelector), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('sin vehículo elegido no se pregunta nada', (tester) async {
    var preguntas = 0;
    await pintar(
      tester,
      vehiculoId: null,
      quienLoLleva: () async {
        preguntas++;
        return {};
      },
    );
    expect(preguntas, 0);
    await desmontar(tester);
  });
}
