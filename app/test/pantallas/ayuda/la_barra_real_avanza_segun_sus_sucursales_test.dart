import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/barra_superior.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/navegacion/menu_de_cuenta.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';

class MiradaSinIO extends SucursalMirada {
  @override
  String? build() => null;
  @override
  void mirar(String? id) {
    state = id;
  }
}

const hab = Sucursal(
  id: 'hab',
  name: 'Habana',
  externalId: 'HAB',
  lat: 20,
  lng: -75,
  areaKm2: 0,
  originConfigured: false,
);
const stg = Sucursal(
  id: 'stg',
  name: 'Santiago',
  externalId: 'STG',
  lat: 20,
  lng: -75,
  areaKm2: 0,
  originConfigured: false,
);
const tarea = TareaDelManual(
  ancla: 'sucursal',
  titulo: 'Comprobar sucursal',
  camino: 'apk/prueba.md',
  tituloDeLaPagina: 'Prueba',
  cuerpo: '',
  pasos: [
    PasoGuiado(
      cual: 1,
      deCuantos: 2,
      texto: 'Abrir selector',
      senala: Senalado.barraSucursal,
    ),
    PasoGuiado(
      cual: 2,
      deCuantos: 2,
      texto: 'Elegir sucursal',
      senala: Senalado.barraElegirSucursal,
    ),
  ],
);
Future<void> asentar(WidgetTester t) async {
  for (var i = 0; i < 35; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  for (final varias in [true, false]) {
    testWidgets(
      'BarraSuperior real ${varias ? 'varias elige y completa' : 'unica no ofrece otras'}',
      (t) async {
        addTearDown(Recorrido.salir);
        addTearDown(RegistroDeControles.vaciar);
        await t.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final container = ProviderContainer(
          overrides: [
            sucursalesProvider.overrideWith(
              (ref) => Stream.value(varias ? [hab, stg] : [hab]),
            ),
            sucursalMiradaProvider.overrideWith(MiradaSinIO.new),
            sesionParaElMenuProvider.overrideWith(
              (ref) async => Sesion(
                token: 't',
                refresh: 'r',
                sub: 'fixture',
                rol: varias ? 'SUPERADMIN' : 'OPERADOR',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        late BuildContext contexto;
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: temaDeReparto(),
              home: Builder(
                builder: (c) {
                  contexto = c;
                  return const Scaffold(
                    appBar: BarraSuperior(titulo: 'Panel'),
                    body: SizedBox(),
                  );
                },
              ),
            ),
          ),
        );
        await asentar(t);
        expect(
          t.takeException(),
          isNull,
          reason: 'Header montado antes de tutorial',
        );
        expect(RegistroDeControles.donde(Senalado.barraSucursal), isNotNull);
        Recorrido.empezarEn(Overlay.of(contexto, rootOverlay: true), tarea);
        await asentar(t);
        expect(
          t.takeException(),
          isNull,
          reason: 'Tutorial sobre header inicial',
        );
        final centro = RegistroDeControles.donde(Senalado.barraSucursal)!
            .rect
            .center;
        await t.tapAt(centro);
        await asentar(t);
        expect(t.takeException(), isNull, reason: 'Cajón abierto por header');
        if (varias) {
          expect(find.text('2 de 2'), findsOneWidget);
          await t.tap(find.text('Habana'));
          await asentar(t);
          expect(container.read(sucursalMiradaProvider), 'hab');
          expect(Recorrido.enMarcha, isFalse);
        } else {
          expect(find.text('1 de 2'), findsOneWidget);
          expect(
            RegistroDeControles.donde(Senalado.barraElegirSucursal),
            isNull,
          );
          expect(find.text('Santiago'), findsNothing);
          expect(container.read(sucursalMiradaProvider), isNull);
        }
        expect(t.takeException(), isNull);
        Recorrido.salir();
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
