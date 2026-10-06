import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';
import 'package:reparto/pantallas/tablero/vista/acciones.dart';

class GuardadoControlado extends TableroDelDia {
  final resultado = Completer<String>();
  String? recibido;
  @override
  Future<Tablero> build() async => const Tablero.imposible('Fixture');
  @override
  Future<String> crearColumna(String nombre, {String? vehiculoId}) {
    recibido = nombre;
    return resultado.future;
  }
}

const tarea = TareaDelManual(
  ancla: 'guardar',
  titulo: 'Guardar zona',
  camino: 'apk/prueba.md',
  tituloDeLaPagina: 'Prueba',
  cuerpo: '',
  pasos: [
    PasoGuiado(
      cual: 1,
      deCuantos: 1,
      texto: 'Guardar la zona',
      senala: Senalado.tableroGuardarLaZona,
    ),
  ],
);
Future<void> asentar(WidgetTester t) async {
  for (var i = 0; i < 35; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  for (final exito in [true, false]) {
    testWidgets(
      'guardar zona real espera ${exito ? 'exito' : 'rechazo sin completar'}',
      (t) async {
        addTearDown(Recorrido.salir);
        addTearDown(RegistroDeControles.vaciar);
        late BuildContext contexto;
        final mando = GuardadoControlado();
        await t.pumpWidget(
          ProviderScope(
            overrides: [tableroProvider.overrideWith(() => mando)],
            child: MaterialApp(
              home: Consumer(
                builder: (c, ref, _) {
                  contexto = c;
                  return Scaffold(
                    body: TextButton(
                      onPressed: () => AccionesTablero.crearColumna(c, ref),
                      child: const Text('Crear zona'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await t.tap(find.text('Crear zona'));
        await asentar(t);
        await t.enterText(find.byType(TextField), 'Zona auditada');
        Recorrido.empezarEn(Overlay.of(contexto, rootOverlay: true), tarea);
        await asentar(t);
        await t.tap(find.text('Guardar'));
        await asentar(t);
        expect(mando.recibido, 'Zona auditada');
        expect(
          Recorrido.enMarcha,
          isTrue,
          reason: 'Cerrar formulario no confirma guardado pendiente',
        );
        if (exito) {
          mando.resultado.complete('id-guardado');
        } else {
          mando.resultado.completeError(const RechazoDelTablero('No guardada'));
        }
        await asentar(t);
        expect(
          Recorrido.enMarcha,
          !exito,
          reason: 'Sólo resultado exitoso completa tutorial',
        );
        if (!exito) {
          expect(find.text('No guardada'), findsOneWidget);
        }
        expect(t.takeException(), isNull);
        Recorrido.salir();
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
