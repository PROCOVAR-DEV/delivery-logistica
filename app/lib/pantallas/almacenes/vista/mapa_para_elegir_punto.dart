// EL MAPA PARA PONER EL PUNTO DE UN ALMACEN: la tercera via, la de pulsar.
//
// ═══════════════════════════════════════════════════════════════════════════
// NO TRAE NINGUNA BIBLIOTECA DE MAPAS, Y NO DIBUJA NINGUNA TESELA PROPIA
// ═══════════════════════════════════════════════════════════════════════════
//
// Las dos piezas de fondo son las que ya tiene esta aplicacion y se usan tal
// cual, sin tocarlas:
//
//   * **de donde salen las teselas**: el puerto `FondoDeCalles`
//     (`pantallas/rutas/datos/mapa_en_vivo.dart`). En la APK y en el escritorio
//     `main.dart` le pone delante el paquete de Cuba descargado
//     (`fondoConPaqueteProvider`), asi que **este mapa se pinta sin señal** sin
//     que aqui haya que saber nada de eso. En las pruebas se inyecta
//     [SinCalles] y no sale ni una peticion, que es regla de la casa.
//   * **la proyeccion**: `aLoAncho`, `aLoAlto` y `ladoDeTesela` de
//     `rutas/vista/croquis_de_ruta.dart`. Es Mercator web, la misma con la que
//     se cortaron las teselas; copiarla aqui seria tener dos formulas que
//     **tienen** que dar lo mismo sin nada que las ate (§3-bis del `CLAUDE.md`).
//
// Lo unico propio de este fichero es lo que el croquis de una ruta no hace:
// elegir un punto pulsando, moverse con el dedo y acercarse con dos.
//
// ═══════════════════════════════════════════════════════════════════════════
// LO QUE ESTE MAPA NO PUEDE HACER NUNCA
// ═══════════════════════════════════════════════════════════════════════════
//
//  * **Perder el punto que se pulso.** Del punto de un almacen salen los
//    kilometros de cada cliente de la sucursal y de ahi lo que se le cobra a
//    cada domicilio. El punto se reporta hacia arriba en el mismo gesto,
//    calculado aqui con la proyeccion y sin preguntarle nada a nadie: **pulsar
//    en el mapa funciona sin señal**, porque es geometria, no una peticion.
//  * **Mentir sobre lo que se esta viendo.** Si las teselas no llegan, el
//    recuadro sale liso y [MapaParaElegirPunto.alVerse] lo dice hacia arriba
//    para que el editor escriba la frase. Un mapa en blanco sin explicacion
//    encima de un punto que se va a cobrar es el peor sitio para adivinar.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../diseno/colores.dart';
import '../../rutas/datos/mapa_en_vivo.dart';
import '../../rutas/vista/croquis_de_ruta.dart'
    show aLoAlto, aLoAncho, altoDelMapa, ladoDeTesela;
import '../datos/coordenadas.dart';

/// EL CENTRO POR DEFECTO: Cuba entera.
///
/// Es a donde se abre cuando no hay ningun punto del que tirar — ni el del
/// almacen que se edita, ni el de otro almacen de la misma sucursal. El patron
/// abria en la sucursal de quien mira, y su propio comentario cuenta que eso
/// dejaba a un administrador (que no tiene sucursal) abriendo «en cualquier
/// parte». Cuba entera es honesto: se ve que hay que moverse.
const centroDeCuba = PuntoEnElMapa(21.6, -79.5);

/// La isla entera cabe a este nivel; un punto ya puesto se mira de barrio, que
/// es el `defaultZoom: 15` del patron.
const zoomDeIsla = 6.0;
const zoomDeBarrio = 15.0;

/// Los topes. Por arriba, 18 es donde acaban las teselas de OSM; por abajo, 3
/// es el mundo entero y mas lejos no hay nada que mirar.
const zoomMinimo = 3.0;
const zoomMaximo = 18.0;

/// El lado del mundo en pixeles a un nivel de acercamiento dado.
double mundoEnPixeles(double zoom) => ladoDeTesela * math.pow(2, zoom);

/// DONDE CAE UN PUNTO DENTRO DEL RECUADRO.
///
/// Publica y pura **para poder probarla con numeros**, que es donde se rompe
/// esto: un signo cambiado aqui pone el almacen en el hemisferio de al lado y el
/// mapa se sigue viendo perfectamente normal.
Offset enLaPantalla(
  PuntoEnElMapa punto, {
  required PuntoEnElMapa centro,
  required double zoom,
  required Size tamano,
}) {
  final mundo = mundoEnPixeles(zoom);
  return Offset(
    (aLoAncho(punto.lng) - aLoAncho(centro.lng)) * mundo + tamano.width / 2,
    (aLoAlto(punto.lat) - aLoAlto(centro.lat)) * mundo + tamano.height / 2,
  );
}

/// LA VUELTA: que punto del mundo hay debajo de un sitio del recuadro.
///
/// Es la inversa exacta de [enLaPantalla] y **es la que convierte un dedo en las
/// coordenadas que se van a guardar**. La prueba las hace ir y volver.
PuntoEnElMapa puntoDeLaPantalla(
  Offset donde, {
  required PuntoEnElMapa centro,
  required double zoom,
  required Size tamano,
}) {
  final mundo = mundoEnPixeles(zoom);
  final x = aLoAncho(centro.lng) + (donde.dx - tamano.width / 2) / mundo;
  final y = aLoAlto(centro.lat) + (donde.dy - tamano.height / 2) / mundo;
  return PuntoEnElMapa(_latDe(y), _lngDe(x));
}

/// `0..1` a lo ancho → longitud. Se envuelve por el antimeridiano en vez de
/// recortarse: arrastrar el mapa mas alla de 180° no puede dar `NaN`.
double _lngDe(double x) {
  final envuelto = (x % 1 + 1) % 1;
  return envuelto * 360 - 180;
}

/// `0..1` a lo alto → latitud. La inversa de `aLoAlto`, que es
/// `0.5 − artanh(sen φ)/2π`.
double _latDe(double y) {
  // Fuera de `0..1` no hay mundo: Mercator no llega a los polos. Se recorta al
  // limite de siempre (85.0511°) en vez de dejar que el logaritmo se vaya al
  // infinito y el punto salga `NaN` — un `NaN` se guarda igual de bien que un
  // numero y luego no hay quien lo lea.
  final acotado = y.clamp(0.0, 1.0);
  final n = math.pi * (1 - 2 * acotado);
  return 180 / math.pi * math.atan(_senoHiperbolico(n));
}

double _senoHiperbolico(double x) => (math.exp(x) - math.exp(-x)) / 2;

/// LO QUE SE ESTA VIENDO, reportado hacia arriba para que la pantalla lo DIGA.
/// El mismo patron que `QueSeVe` del croquis de la ruta.
typedef QueSeVeEnElMapa = ({bool conCalles});

/// EL MAPA. Recibe el punto y avisa del que se pulse; **no guarda el punto él**:
/// el dueño del dato es el editor, que es quien lo va a mandar a Accesos.
class MapaParaElegirPunto extends StatefulWidget {
  const MapaParaElegirPunto({
    required this.fondo,
    this.punto,
    this.centroPorDefecto = centroDeCuba,
    this.alElegir,
    this.alVerse,
    super.key,
  });

  /// De donde salen las teselas. Inyectado: en las pruebas es [SinCalles] y no
  /// sale ni una peticion.
  final FondoDeCalles fondo;

  /// El punto que hay puesto ahora mismo, venga de donde venga (escrito a mano,
  /// geocodificado o pulsado). `null` = todavia no hay ninguno.
  final PuntoEnElMapa? punto;

  /// Donde abrir cuando no hay punto. La pantalla le pasa el de otro almacen de
  /// la misma sucursal si lo hay; si no, Cuba entera.
  final PuntoEnElMapa centroPorDefecto;

  /// **La tercera via.** `null` deja el mapa de sólo mirar.
  final ValueChanged<PuntoEnElMapa>? alElegir;

  final void Function(QueSeVeEnElMapa)? alVerse;

  /// La clave con la que lo encuentran las pruebas, como el croquis.
  static const clave = ValueKey('mapa-para-elegir-punto');

  @override
  State<MapaParaElegirPunto> createState() => _MapaParaElegirPuntoState();
}

class _MapaParaElegirPuntoState extends State<MapaParaElegirPunto> {
  late PuntoEnElMapa _centro = widget.punto ?? widget.centroPorDefecto;
  late double _zoom = widget.punto == null ? zoomDeIsla : zoomDeBarrio;

  /// Las teselas que han llegado, con su sello.
  ///
  /// El sello no es adorno: comparar `viejo.teselas.length != teselas.length` es
  /// comparar un mapa consigo mismo cuando el pintor viejo y el nuevo sostienen
  /// el MISMO objeto, y entonces Flutter se ahorra el repintado y se queda una
  /// sola tesela dibujada arriba a la izquierda. Pasó en el croquis el
  /// 21/09/2026 y esta escrito alli; aqui se copia con sello desde el principio.
  final _teselas = <String, ui.Image>{};
  int _sello = 0;
  String? _laVistaQueSePidio;

  /// Con que aparato se esta tocando. Hace falta para una sola decision, la de
  /// mas abajo: con raton un arrastre mueve el mapa, con un dedo no.
  PointerDeviceKind? _ultimoAparato;

  double _zoomAlEmpezar = 1;
  PuntoEnElMapa? _bajoElFocoAlEmpezar;
  bool _elGestoEsDelMapa = false;

  @override
  void didUpdateWidget(MapaParaElegirPunto viejo) {
    super.didUpdateWidget(viejo);
    final ahora = widget.punto;
    if (ahora == null || ahora == viejo.punto) return;
    // EL MAPA SIGUE AL PUNTO **sólo cuando el punto se ha ido de la vista**.
    //
    // Hace falta porque las otras dos vias mueven el punto desde fuera: escribir
    // las coordenadas a mano o buscar una direccion tiene que llevar el mapa
    // hasta alli, o la pantalla enseña un mapa de un sitio y unas coordenadas de
    // otro. Y es «sólo si se fue» porque recentrar en cada tecleo da un mapa que
    // salta mientras alguien escribe.
    final caja = _ultimoTamano;
    if (caja != null) {
      final donde = enLaPantalla(
        ahora,
        centro: _centro,
        zoom: _zoom,
        tamano: caja,
      );
      final dentro =
          donde.dx >= 0 &&
          donde.dy >= 0 &&
          donde.dx <= caja.width &&
          donde.dy <= caja.height;
      if (dentro) return;
    }
    setState(() {
      _centro = ahora;
      if (_zoom < zoomDeBarrio) _zoom = zoomDeBarrio;
    });
  }

  Size? _ultimoTamano;

  /// Pide las teselas que hacen falta para lo que se esta viendo. **Despues de
  /// pintar**, nunca antes: el recuadro ya esta dibujado sin ellas.
  void _pedirLasTeselas(Size tamano) {
    if (!mounted) return;
    final z = _zoomDeLasTeselas;
    final mundo = mundoEnPixeles(z.toDouble());
    final escala = math.pow(2, _zoom - z).toDouble();
    final cx = aLoAncho(_centro.lng) * mundo;
    final cy = aLoAlto(_centro.lat) * mundo;
    final desdeX = ((cx - tamano.width / 2 / escala) / ladoDeTesela).floor();
    final hastaX = ((cx + tamano.width / 2 / escala) / ladoDeTesela).floor();
    final desdeY = ((cy - tamano.height / 2 / escala) / ladoDeTesela).floor();
    final hastaY = ((cy + tamano.height / 2 / escala) / ladoDeTesela).floor();
    final vista = '$z/$desdeX-$hastaX/$desdeY-$hastaY';
    final hacenFalta = <String>[];
    final tope = 1 << z;
    for (var x = desdeX; x <= hastaX; x++) {
      for (var y = desdeY; y <= hastaY; y++) {
        if (y < 0 || y >= tope) continue;
        hacenFalta.add('$z/${((x % tope) + tope) % tope}/$y');
      }
    }
    // Lo que se esta viendo AHORA, no lo que haya en memoria de otra vista: una
    // tesela guardada de otro sitio no es «el mapa cargó». Es el mismo arreglo
    // que lleva el croquis.
    widget.alVerse?.call((conCalles: hacenFalta.any(_teselas.containsKey)));
    if (_laVistaQueSePidio == vista) return;
    _laVistaQueSePidio = vista;
    for (final clave in hacenFalta) {
      if (_teselas.containsKey(clave)) continue;
      final partes = clave.split('/');
      widget.fondo
          .tesela(
            int.parse(partes[0]),
            int.parse(partes[1]),
            int.parse(partes[2]),
          )
          .then((imagen) {
            if (!mounted || imagen == null) return;
            setState(() {
              _teselas[clave] = imagen;
              // Las dos cosas SIEMPRE juntas, por eso van en la misma linea:
              // guardar sin subir el sello es no repintar.
              _sello++;
            });
            widget.alVerse?.call((conCalles: true));
          });
    }
  }

  int get _zoomDeLasTeselas =>
      _zoom.round().clamp(zoomMinimo.toInt(), zoomMaximo.toInt());

  /// Acerca o aleja **dejando quieto lo que hay debajo del dedo**. Sin esto, el
  /// sitio que se quiere mirar se escapa hacia una esquina en cuanto se acerca y
  /// hay que acercar y arrastrar a la vez.
  void _acercarHacia(Offset foco, double nuevoZoom, Size tamano) {
    final z = nuevoZoom.clamp(zoomMinimo, zoomMaximo);
    if (z == _zoom) return;
    final bajoElFoco = puntoDeLaPantalla(
      foco,
      centro: _centro,
      zoom: _zoom,
      tamano: tamano,
    );
    setState(() {
      _zoom = z;
      _centro = puntoDeLaPantalla(
        Offset(tamano.width - foco.dx, tamano.height - foco.dy),
        centro: bajoElFoco,
        zoom: z,
        tamano: tamano,
      );
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, cajon) {
      final tamano = Size(cajon.maxWidth, altoDelMapa(cajon.maxWidth));
      _ultimoTamano = tamano;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _pedirLasTeselas(tamano),
      );
      return DecoratedBox(
        key: MapaParaElegirPunto.clave,
        decoration: BoxDecoration(
          color: Colores.blanco,
          border: Border.all(color: Colores.linea),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.fromSize(
            size: tamano,
            child: Listener(
              onPointerDown: (evento) => _ultimoAparato = evento.kind,
              onPointerSignal: (senal) {
                // El pellizco del trackpad, que NO es una rueda: el navegador lo
                // manda como `PointerScaleEvent`. Sin esto, el gesto mas natural
                // del portatil no hace nada (pasó en el croquis, 17/09/2026).
                if (senal is PointerScaleEvent) {
                  _acercarHacia(
                    senal.localPosition,
                    _zoom + math.log(senal.scale) / math.ln2,
                    tamano,
                  );
                  return;
                }
                if (senal is! PointerScrollEvent) return;
                // **SOLO CON CTRL**, como el croquis y por lo mismo: este mapa
                // vive dentro del cuerpo desplazable de un cajon, y una rueda
                // que acerca en vez de desplazar deja los botones de Guardar y
                // Cerrar fuera del alcance de quien tiene el raton encima.
                if (!HardwareKeyboard.instance.isControlPressed &&
                    !HardwareKeyboard.instance.isMetaPressed) {
                  return;
                }
                _acercarHacia(
                  senal.localPosition,
                  _zoom + (senal.scrollDelta.dy < 0 ? 0.5 : -0.5),
                  tamano,
                );
              },
              child: RawGestureDetector(
                gestures: <Type, GestureRecognizerFactory>{
                  ScaleGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        ScaleGestureRecognizer
                      >(ScaleGestureRecognizer.new, (reconocedor) {
                        reconocedor
                          ..onStart = (gesto) {
                            _zoomAlEmpezar = _zoom;
                            _bajoElFocoAlEmpezar = puntoDeLaPantalla(
                              gesto.localFocalPoint,
                              centro: _centro,
                              zoom: _zoom,
                              tamano: tamano,
                            );
                            // DE QUIEN ES EL ARRASTRE, y es la unica decision
                            // fina de este widget.
                            //
                            // El mapa esta dentro del cuerpo desplazable de un
                            // cajon. Con UN dedo el arrastre es del cajon: si se
                            // lo quedara el mapa, no habria forma de llegar a
                            // los botones de abajo — que es exactamente el fallo
                            // del 17/09/2026 en el detalle de la ruta. Con DOS
                            // dedos no hay duda, y con raton tampoco (la rueda
                            // del raton sigue desplazando el cajon).
                            _elGestoEsDelMapa =
                                gesto.pointerCount >= 2 ||
                                _ultimoAparato == PointerDeviceKind.mouse;
                          }
                          ..onUpdate = (gesto) {
                            if (!_elGestoEsDelMapa && gesto.pointerCount < 2) {
                              return;
                            }
                            _elGestoEsDelMapa = true;
                            final origen = _bajoElFocoAlEmpezar;
                            if (origen == null) return;
                            final z =
                                (_zoomAlEmpezar +
                                        math.log(gesto.scale) / math.ln2)
                                    .clamp(zoomMinimo, zoomMaximo);
                            // El punto que se agarro se queda debajo de los
                            // dedos: la cuenta se hace SIEMPRE contra donde se
                            // posaron, nunca contra el fotograma anterior, que
                            // redondea y hace que el mapa se vaya solo.
                            setState(() {
                              _zoom = z;
                              _centro = puntoDeLaPantalla(
                                Offset(
                                  tamano.width - gesto.localFocalPoint.dx,
                                  tamano.height - gesto.localFocalPoint.dy,
                                ),
                                centro: origen,
                                zoom: z,
                                tamano: tamano,
                              );
                            });
                          };
                      }),
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: widget.alElegir == null
                      ? null
                      : (toque) => widget.alElegir!(
                          puntoDeLaPantalla(
                            toque.localPosition,
                            centro: _centro,
                            zoom: _zoom,
                            tamano: tamano,
                          ),
                        ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _PintorDelMapa(
                            teselas: _teselas,
                            sello: _sello,
                            centro: _centro,
                            zoom: _zoom,
                            zoomDeLasTeselas: _zoomDeLasTeselas,
                            punto: widget.punto,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Column(
                          children: [
                            _BotonDeZoom(
                              icono: Icons.add,
                              rotulo: 'Acercar',
                              alPulsar: () => _acercarHacia(
                                Offset(tamano.width / 2, tamano.height / 2),
                                _zoom + 1,
                                tamano,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _BotonDeZoom(
                              icono: Icons.remove,
                              rotulo: 'Alejar',
                              alPulsar: () => _acercarHacia(
                                Offset(tamano.width / 2, tamano.height / 2),
                                _zoom - 1,
                                tamano,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _BotonDeZoom extends StatelessWidget {
  const _BotonDeZoom({
    required this.icono,
    required this.rotulo,
    required this.alPulsar,
  });

  final IconData icono;
  final String rotulo;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: rotulo,
    child: Material(
      color: Colores.blanco,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colores.linea),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: alPulsar,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icono, size: 18, semanticLabel: rotulo),
        ),
      ),
    ),
  );
}

class _PintorDelMapa extends CustomPainter {
  _PintorDelMapa({
    required this.teselas,
    required this.sello,
    required this.centro,
    required this.zoom,
    required this.zoomDeLasTeselas,
    required this.punto,
  });

  final Map<String, ui.Image> teselas;
  final int sello;
  final PuntoEnElMapa centro;
  final double zoom;
  final int zoomDeLasTeselas;
  final PuntoEnElMapa? punto;

  @override
  void paint(Canvas lienzo, Size tamano) {
    lienzo.drawRect(
      Offset.zero & tamano,
      Paint()..color = ColoresDelMapa.fondo,
    );
    final z = zoomDeLasTeselas;
    final escala = math.pow(2, zoom - z).toDouble();
    final mundo = mundoEnPixeles(z.toDouble());
    final cx = aLoAncho(centro.lng) * mundo;
    final cy = aLoAlto(centro.lat) * mundo;
    final tope = 1 << z;
    final desdeX = ((cx - tamano.width / 2 / escala) / ladoDeTesela).floor();
    final hastaX = ((cx + tamano.width / 2 / escala) / ladoDeTesela).floor();
    final desdeY = ((cy - tamano.height / 2 / escala) / ladoDeTesela).floor();
    final hastaY = ((cy + tamano.height / 2 / escala) / ladoDeTesela).floor();
    for (var x = desdeX; x <= hastaX; x++) {
      for (var y = desdeY; y <= hastaY; y++) {
        if (y < 0 || y >= tope) continue;
        final imagen = teselas['$z/${((x % tope) + tope) % tope}/$y'];
        if (imagen == null) continue;
        final izquierda = (x * ladoDeTesela - cx) * escala + tamano.width / 2;
        final arriba = (y * ladoDeTesela - cy) * escala + tamano.height / 2;
        lienzo.drawImageRect(
          imagen,
          Rect.fromLTWH(
            0,
            0,
            imagen.width.toDouble(),
            imagen.height.toDouble(),
          ),
          Rect.fromLTWH(
            izquierda,
            arriba,
            ladoDeTesela * escala,
            ladoDeTesela * escala,
          ),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    }
    final p = punto;
    if (p == null) return;
    final donde = enLaPantalla(p, centro: centro, zoom: zoom, tamano: tamano);
    // La chincheta: un circulo con su aro blanco para que se vea sobre las
    // calles y sobre el papel liso.
    lienzo
      ..drawCircle(donde, 9, Paint()..color = Colores.blanco)
      ..drawCircle(donde, 6, Paint()..color = ColoresDelMapa.salida)
      ..drawLine(
        Offset(donde.dx, donde.dy - 20),
        Offset(donde.dx, donde.dy + 20),
        Paint()
          ..color = ColoresDelMapa.salida.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      )
      ..drawLine(
        Offset(donde.dx - 20, donde.dy),
        Offset(donde.dx + 20, donde.dy),
        Paint()
          ..color = ColoresDelMapa.salida.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(_PintorDelMapa viejo) =>
      viejo.sello != sello ||
      viejo.zoom != zoom ||
      viejo.centro != centro ||
      viejo.punto != punto;
}
