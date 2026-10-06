import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';

class ControlesTardios extends StatefulWidget {
  const ControlesTardios({super.key});

  @override
  State<ControlesTardios> createState() => _ControlesTardiosState();
}

class _ControlesTardiosState extends State<ControlesTardios> {
  bool _destino = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 32), () {
      if (mounted) setState(() => _destino = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const ControlSenalado(
        nombre: 'origen',
        child: SizedBox(width: 100, height: 40, child: Text('Origen')),
      ),
      if (_destino)
        const ControlSenalado(
          nombre: 'destino',
          child: SizedBox(width: 100, height: 40, child: Text('Destino')),
        ),
    ],
  );
}

void main() {
  testWidgets('espera el destino tardío aunque el origen ya esté montado', (
    tester,
  ) async {
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);
    addTearDown(Recorrido.salir);
    late OverlayState capa;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              capa = Overlay.of(context, rootOverlay: true);
              return const ControlesTardios();
            },
          ),
        ),
      ),
    );
    expect(RegistroDeControles.donde('origen'), isNotNull);
    expect(RegistroDeControles.donde('destino'), isNull);
    Recorrido.empezarEn(
      capa,
      const TareaDelManual(
        camino: 'prueba',
        tituloDeLaPagina: 'Prueba',
        titulo: 'Arrastra',
        ancla: 'arrastra',
        cuerpo: '',
        pasos: [
          PasoGuiado(
            cual: 1,
            deCuantos: 1,
            texto: 'Arrastra del origen al destino.',
            senala: 'origen',
            senalaTambien: ['destino'],
          ),
        ],
      ),
    );
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(RegistroDeControles.donde('destino'), isNotNull);
    expect(
      find.byKey(ClavesDelRecorrido.foco),
      findsNWidgets(2),
      reason: 'el destino aparece dos fotogramas después; esperar sólo al origen deja el arrastre sin los dos focos',
    );
    expect(find.textContaining('no se puede señalar aquí'), findsNothing);
    Recorrido.salir();
    await tester.pumpWidget(const SizedBox());
  });
}
