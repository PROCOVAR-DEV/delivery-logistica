/// LO QUE PERMITE SENALAR UN BOTON DE VERDAD, encima de la aplicacion de verdad.
///
/// ## El encargo, con las palabras de Jose — 05/10/2026
///
/// > «las cosas q tienen botones me mueven a la página pero no me dice paso a
/// > paso con sus tooltips señalándome paso a paso en la aplicación cada botón q
/// > debo tocar en cada tarea con sus pasos»
/// > «q las tareas enseñen algo de verdad no mierda textual q la gente no quiere
/// > leer quiere q le enseñes donde ir donde tocar para cada cosa»
///
/// Llevarle a la pantalla no basta. El paso tiene que **senalar el control
/// concreto**, y para eso el recorrido necesita saber **donde esta ese control en
/// pixeles**. Esto es esa pieza, y es la unica forma en Flutter que no obliga a
/// que cada pantalla declare una tabla de coordenadas: el control se envuelve
/// donde esta, y el que senala le pregunta por su rectangulo.
///
/// ## Por que un registro de contextos y no un `GlobalKey` por control
///
/// Un `GlobalKey` es unico en todo el arbol: dos instancias del mismo control
/// montadas a la vez —y pasa, una pantalla ancha con la lista y la ficha al
/// lado— **revientan la aplicacion** con un «Duplicate GlobalKey». Eso convierte
/// un fallo de la guia en un fallo de la pantalla que se estaba guiando, y la
/// guia no puede costarle a nadie la pantalla en la que trabaja.
///
/// Con un registro de contextos, dos instancias no rompen nada: [donde] devuelve
/// `null` y el recorrido **lo dice** en vez de senalar a una de las dos a cara o
/// cruz (§4 de `CLAUDE.md`: nada se descarta en silencio, y un recorrido que
/// apunta al boton equivocado es peor que uno que no apunta).
///
/// Cuando un control se repite legitimamente por fila o por columna —el selector
/// de camion de cada zona del Tablero—, **la pantalla marca solo el primero**
/// ([ControlSenalado.senalable] a `false` en los demas). La decision es de la
/// pantalla porque es la unica que sabe cual es el primero; aqui lo unico que se
/// sabe es que dos a la vez no se pueden distinguir.
library;

import 'package:flutter/material.dart';

/// DONDE ESTA CADA CONTROL MARCADO, ahora mismo.
///
/// Es estado global a proposito y no un `InheritedWidget`: quien pregunta es una
/// capa del `Overlay` de la raiz, que **no es descendiente** de la pantalla que
/// esta mirando. Un `InheritedWidget` no cruza ese limite.
abstract final class RegistroDeControles {
  /// Nombre -> los contextos montados con ese nombre. Es un `Set` y no un solo
  /// contexto porque dos a la vez es un caso que hay que poder **detectar**, no
  /// uno que haya que tapar guardando el ultimo.
  static final Map<String, Set<BuildContext>> _puestos =
      <String, Set<BuildContext>>{};

  static void poner(String nombre, BuildContext contexto) {
    _puestos.putIfAbsent(nombre, () => <BuildContext>{}).add(contexto);
  }

  static void quitar(String nombre, BuildContext contexto) {
    final cuales = _puestos[nombre];
    if (cuales == null) return;
    cuales.remove(contexto);
    if (cuales.isEmpty) _puestos.remove(nombre);
  }

  /// Si esta puesto, y donde. `null` quiere decir **no se puede senalar**, y son
  /// cuatro casos distintos que el recorrido cuenta igual porque la consecuencia
  /// es la misma:
  ///
  ///  * el control no esta marcado en ninguna pantalla;
  ///  * esta marcado pero esta pantalla no es la que lo tiene;
  ///  * esta montado dos veces y no se puede saber a cual se referia el paso;
  ///  * esta montado pero todavia sin medir (un fotograma antes de su `layout`);
  ///  * **esta dentro de una lista perezosa y todavia no se ha construido.** Un
  ///    `ListView.builder` solo monta lo que cabe en la vista mas su margen, asi
  ///    que un control en la fila 200 no existe hasta que alguien desplaza hasta
  ///    alli. Por eso las pantallas marcan la PRIMERA fila y no una del medio: la
  ///    primera siempre esta construida.
  static ({Rect rect, BuildContext contexto})? donde(String nombre) {
    final cuales = _puestos[nombre];
    if (cuales == null || cuales.length != 1) return null;
    final contexto = cuales.first;
    if (!contexto.mounted) return null;
    final caja = contexto.findRenderObject();
    if (caja is! RenderBox || !caja.hasSize || !caja.attached) return null;
    if (caja.size.isEmpty) return null;
    return (
      rect: caja.localToGlobal(Offset.zero) & caja.size,
      contexto: contexto,
    );
  }

  /// Los que hay puestos ahora mismo. Para las pruebas, y para poder contar.
  static Set<String> get puestos => _puestos.keys.toSet();

  /// Sólo para las pruebas: deja el registro como recién nacido. Sin esto, una
  /// prueba que no desmonta deja contextos muertos y la siguiente ve «dos a la
  /// vez» donde hay uno.
  @visibleForTesting
  static void vaciar() => _puestos.clear();
}

/// ENVUELVE UN CONTROL PARA QUE EL RECORRIDO PUEDA SENALARLO.
///
/// No pinta nada, no cambia el tamano de su hijo y no le pone un `Semantics`
/// nuevo: es un envoltorio transparente. Lo unico que hace es decirle al
/// [RegistroDeControles] «el control que se llama `nombre` esta aqui».
///
/// ```dart
/// ControlSenalado(
///   nombre: Senalado.vehiculosAgregar,
///   child: BotonPrincipal(texto: 'Nuevo vehículo', icono: Icons.add, ...),
/// )
/// ```
class ControlSenalado extends StatefulWidget {
  const ControlSenalado({
    required this.nombre,
    required this.child,
    this.senalable = true,
    super.key,
  });

  /// El nombre con el que el manual lo nombra: `<!-- señala: vehiculos-nuevo -->`.
  /// Sale de `datos/controles_senalados.dart` y no se escribe a mano.
  final String nombre;

  final Widget child;

  /// `false` deja el envoltorio puesto y **no lo registra**.
  ///
  /// Es para los controles que se repiten por fila: la pantalla marca el primero
  /// y pasa `false` en los demas, y asi nunca hay dos con el mismo nombre. Dejar
  /// el envoltorio en vez de quitarlo mantiene el arbol igual en todas las filas,
  /// que es lo que evita que un `AnimatedList` las vea cambiar de forma.
  final bool senalable;

  @override
  State<ControlSenalado> createState() => _ControlSenaladoState();
}

class _ControlSenaladoState extends State<ControlSenalado> {
  @override
  void initState() {
    super.initState();
    if (widget.senalable) RegistroDeControles.poner(widget.nombre, context);
  }

  @override
  void didUpdateWidget(ControlSenalado anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.nombre == widget.nombre &&
        anterior.senalable == widget.senalable) {
      return;
    }
    if (anterior.senalable) {
      RegistroDeControles.quitar(anterior.nombre, context);
    }
    if (widget.senalable) RegistroDeControles.poner(widget.nombre, context);
  }

  @override
  void dispose() {
    if (widget.senalable) RegistroDeControles.quitar(widget.nombre, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
