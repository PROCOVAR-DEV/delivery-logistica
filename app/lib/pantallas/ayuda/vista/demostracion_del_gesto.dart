import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';

/// Enseña el gesto dos veces y se aparta. Nunca ejecuta acciones ni intercepta
/// el dedo: la persona trabaja sobre los controles reales que hay debajo.
class DemostracionDelGesto extends StatefulWidget {
  const DemostracionDelGesto({required this.focos, super.key});

  final List<Rect> focos;
  static const mano = ValueKey('recorrido-mano');

  @override
  State<DemostracionDelGesto> createState() => _DemostracionDelGestoState();
}

class _DemostracionDelGestoState extends State<DemostracionDelGesto>
    with SingleTickerProviderStateMixin {
  late final _avance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  );
  bool? _sinAnimacion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sinAnimacion = MediaQuery.disableAnimationsOf(context);
    if (_sinAnimacion == sinAnimacion) return;
    _sinAnimacion = sinAnimacion;
    if (sinAnimacion) {
      _avance.value = 1;
    } else {
      _avance.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _avance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _avance,
          builder: (context, _) {
            if (_avance.value == 1 || widget.focos.isEmpty) {
              return const SizedBox.shrink();
            }
            final fase = (_avance.value * 2) % 1;
            final puntos = widget.focos.map((r) => r.center).toList();
            // En el arrastre, primero mantiene pulsado durante 600 ms;
            // después se mueve y permanece un momento en el destino.
            final movimiento = ((fase - 0.3) / 0.5).clamp(0.0, 1.0);
            final tramo = movimiento * (puntos.length - 1);
            final desde = tramo.floor();
            final hasta = math.min(desde + 1, puntos.length - 1);
            final punto = Offset.lerp(
              puntos[desde],
              puntos[hasta],
              Curves.easeInOut.transform(tramo - desde),
            )!;
            final pulso = math.sin(math.pi * fase);
            return Opacity(
              opacity: (pulso * 3).clamp(0.0, 1.0),
              child: Stack(
                children: [
                  if (puntos.length > 1)
                    Positioned.fill(
                      child: CustomPaint(painter: _Trazo(puntos)),
                    ),
                  Positioned(
                    left: punto.dx - 22,
                    top: punto.dy - 22,
                    child: Transform.scale(
                      scale: puntos.length == 1 ? 0.8 + pulso * 0.2 : 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colores.blanco,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colores.marca, width: 2),
                        ),
                        child: SizedBox(
                          key: DemostracionDelGesto.mano,
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.touch_app_outlined,
                            color: Colores.primario,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _Trazo extends CustomPainter {
  _Trazo(this.puntos);
  final List<Offset> puntos;

  @override
  void paint(Canvas canvas, Size size) {
    final tinta = Paint()
      ..color = Colores.marca
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final camino = Path()..moveTo(puntos.first.dx, puntos.first.dy);
    for (final punto in puntos.skip(1)) {
      camino.lineTo(punto.dx, punto.dy);
    }
    canvas.drawPath(camino, tinta);
    final delta = puntos.last - puntos[puntos.length - 2];
    if (delta.distance == 0) return;
    final direccion = delta / delta.distance * 12;
    final lado = Offset(-direccion.dy, direccion.dx) * 0.5;
    canvas.drawLine(puntos.last, puntos.last - direccion + lado, tinta);
    canvas.drawLine(puntos.last, puntos.last - direccion - lado, tinta);
  }

  @override
  bool shouldRepaint(_Trazo oldDelegate) => oldDelegate.puntos != puntos;
}
