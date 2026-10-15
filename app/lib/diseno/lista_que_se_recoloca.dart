import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// UNA LISTA CUYAS TARJETAS SE DESLIZAN A SU SITIO NUEVO AL REORDENARSE.
///
/// Jose, 15/10/2026: «por favor esto con animaciones, que no sea una cosa pegada
/// ahí y rígida». Al cambiar el orden, las tarjetas saltaban de golpe.
///
/// Es un FLIP: cuando cambian [claves], se apunta dónde se VEÍA cada tarjeta
/// montada (antes de la maquetación nueva); al pintar, cada [SeRecoloca] mide
/// dónde quedó y arranca desplazada a su sitio viejo, y de ahí se desliza al
/// nuevo. La que entra (clave nueva) aparece con un fundido corto. La que sale
/// se va sin más y las de al lado se deslizan a tapar el hueco.
///
/// Sólo mide lo MONTADO: en una lista perezosa son las que se ven (más el margen
/// del `cacheExtent`), no las setecientas. Se mide en el MISMO fotograma, al
/// pintar y no después, para que no se vea un fotograma en el sitio nuevo antes
/// de volver al viejo. Con «reducir animaciones» del sistema no anima nada.
class ListaQueSeRecoloca extends StatefulWidget {
  const ListaQueSeRecoloca({
    required this.claves,
    required this.child,
    super.key,
  });

  /// Las claves de las tarjetas, en el orden en que se pintan. Cuando cambia
  /// esta lista, se recolocan.
  final List<Object> claves;
  final Widget child;

  /// Lo que tarda en deslizarse: corto y sin rebote.
  static const duracion = Duration(milliseconds: 300);
  static const curva = Curves.easeOutCubic;

  @override
  State<ListaQueSeRecoloca> createState() => _ListaQueSeRecolocaState();
}

class _ListaQueSeRecolocaState extends State<ListaQueSeRecoloca> {
  final _montadas = <Object, _SeRecolocaState>{};

  /// Dónde se veía cada tarjeta justo antes del cambio, en pantalla. Vive un
  /// fotograma: lo leen las tarjetas al pintar y se tira después.
  Map<Object, Offset>? _antes;
  Set<Object> _viejas = const {};
  int _cambio = 0;

  @override
  void didUpdateWidget(ListaQueSeRecoloca anterior) {
    super.didUpdateWidget(anterior);
    if (listEquals(anterior.claves, widget.claves)) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    // Aquí la maquetación vieja sigue valiendo: es la foto del «antes».
    _antes = {for (final m in _montadas.entries) m.key: ?m.value.dondeSeVe()};
    _viejas = anterior.claves.toSet();
    _cambio++;
    // Que pinten todas, también las que no cambian de elemento: una tarjeta
    // dentro de un `RepaintBoundary` que sólo se mueve no se vuelve a pintar.
    for (final m in _montadas.values) {
      m.context.findRenderObject()?.markNeedsPaint();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _antes = null);
  }

  @override
  Widget build(BuildContext context) =>
      _Ambito(estado: this, child: widget.child);
}

class _Ambito extends InheritedWidget {
  const _Ambito({required this.estado, required super.child});

  final _ListaQueSeRecolocaState estado;

  @override
  bool updateShouldNotify(_Ambito anterior) => false;
}

/// UNA TARJETA DE [ListaQueSeRecoloca]. [clave] es la estable del pedido, la
/// zona o la parada. Fuera de una [ListaQueSeRecoloca] no hace nada.
class SeRecoloca extends StatefulWidget {
  const SeRecoloca({required this.clave, required this.child, super.key});

  final Object clave;
  final Widget child;

  @override
  State<SeRecoloca> createState() => _SeRecolocaState();
}

class _SeRecolocaState extends State<SeRecoloca>
    with SingleTickerProviderStateMixin {
  late final _mando = AnimationController(
    vsync: this,
    duration: ListaQueSeRecoloca.duracion,
    value: 1,
  );
  _ListaQueSeRecolocaState? _lista;
  Offset _desde = Offset.zero;
  bool _entra = false;
  int _cambioVisto = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lista = context.getInheritedWidgetOfExactType<_Ambito>()?.estado;
    if (lista == _lista) return;
    _soltar();
    _lista = lista;
    // Recién montada en mitad de un cambio: el «antes» de su clave ya está
    // apuntado (lo dejó la que tenía su sitio viejo), y lo leerá al pintar.
    if (lista != null) {
      lista._montadas[widget.clave] = this;
      _cambioVisto = lista._antes == null ? lista._cambio : -1;
    }
  }

  @override
  void didUpdateWidget(SeRecoloca anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.clave == widget.clave) return;
    _soltar(anterior.clave);
    _lista?._montadas[widget.clave] = this;
  }

  void _soltar([Object? clave]) {
    final lista = _lista;
    if (lista != null && lista._montadas[clave ?? widget.clave] == this) {
      lista._montadas.remove(clave ?? widget.clave);
    }
  }

  // Una inactiva (la que arrastra el `ReorderableListView`, la que se va) no
  // tiene caja que medir: fuera mientras lo esté.
  @override
  void deactivate() {
    _soltar();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _lista?._montadas[widget.clave] = this;
  }

  @override
  void dispose() {
    _soltar();
    _mando.dispose();
    super.dispose();
  }

  double get _t => ListaQueSeRecoloca.curva.transform(_mando.value);

  Offset get _desplazamiento => _entra ? Offset.zero : _desde * (1 - _t);

  /// Dónde se ve AHORA en pantalla, con lo que le quede de deslizarse.
  Offset? dondeSeVe() {
    final caja = context.findRenderObject();
    if (caja is! RenderBox || !caja.attached || !caja.hasSize) return null;
    return caja.localToGlobal(Offset.zero) + _desplazamiento;
  }

  /// Se llama al pintar, con la maquetación nueva ya hecha: si su lista acaba
  /// de cambiar, mide el salto y arranca.
  void _alPintar(RenderBox caja) {
    final lista = _lista;
    final antes = lista?._antes;
    if (lista == null || antes == null || _cambioVisto == lista._cambio) return;
    _cambioVisto = lista._cambio;
    final donde = antes[widget.clave];
    if (donde != null) {
      final salto = donde - caja.localToGlobal(Offset.zero);
      if (salto.distanceSquared < .25) return;
      _entra = false;
      _desde = salto;
      _mando.forward(from: 0);
    } else if (!lista._viejas.contains(widget.clave)) {
      _entra = true;
      _mando.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) =>
      _Pintor(estado: this, child: widget.child);
}

class _Pintor extends SingleChildRenderObjectWidget {
  const _Pintor({required this.estado, super.child});

  final _SeRecolocaState estado;

  @override
  _RenderPintor createRenderObject(BuildContext context) =>
      _RenderPintor(estado);

  @override
  void updateRenderObject(BuildContext context, _RenderPintor caja) =>
      caja.estado = estado;
}

/// Pinta al hijo desplazado sin reconstruir nada: el deslizamiento es sólo de
/// pintura, así que no mueve la maquetación ni el desplazamiento de la lista.
class _RenderPintor extends RenderProxyBox {
  _RenderPintor(this._estado) {
    _estado._mando.addListener(_latido);
  }

  _SeRecolocaState _estado;
  set estado(_SeRecolocaState nuevo) {
    if (nuevo == _estado) return;
    _estado._mando.removeListener(_latido);
    _estado = nuevo.._mando.addListener(_latido);
    markNeedsPaint();
  }

  /// El arranque avisa en mitad de la pintura, y ahí no se puede pedir otra.
  bool _pintando = false;
  void _latido() {
    if (!_pintando) markNeedsPaint();
  }

  @override
  void dispose() {
    _estado._mando.removeListener(_latido);
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    _pintando = true;
    try {
      _estado._alPintar(this);
    } finally {
      _pintando = false;
    }
    final desplazado = offset + _estado._desplazamiento;
    if (_estado._entra && _estado._mando.value < 1) {
      context.pushOpacity(
        desplazado,
        (255 * _estado._t).round(),
        (context, offset) => context.paintChild(child!, offset),
      );
    } else {
      context.paintChild(child!, desplazado);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _estado._desplazamiento,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final d = _estado._desplazamiento;
    transform.translateByDouble(d.dx, d.dy, 0, 1);
  }
}
