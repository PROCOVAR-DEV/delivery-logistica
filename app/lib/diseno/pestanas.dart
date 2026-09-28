/// PESTAÑAS EN CARRUSEL: se ve SÓLO en la que estás, y unas bolitas dicen que
/// hay más.
///
/// Jose, 17/09/2026, corrigiendo la primera versión —que era una fila con todas
/// las pestañas y una flecha a cada lado—:
///
/// > «el slice te lo pedí con las opciones sin que aparezcan, que salga la que
/// > está, y entonces que salgan las bolas para que muestre como que hay otras
/// > opciones. Eso es lo que te pedí que hicieras con slices los tabs»
///
/// O sea, lo de las fotos del teléfono: un rótulo con dónde estás y debajo los
/// puntos de página. Las demás pestañas **no se enseñan**; lo único que dice que
/// existen son las bolitas.
///
/// Son dos piezas sueltas a propósito:
///
///  * [CarruselDePestanas] — la cabecera: el rótulo de la actual y las bolitas.
///    No sabe nada del contenido.
///  * [CuerpoDeslizable] — el contenido, que se cambia deslizando el dedo a lo
///    ancho. No sabe nada de la cabecera.
///
/// Las dos hablan por el mismo par `indice` / `alCambiar`, así que quien las usa
/// guarda UN número y las dos van solas.
///
/// # Por qué las flechas siguen ahí, pequeñas y al lado de las bolitas
///
/// Jose no las pidió, y por eso ya no están donde estaban —ni grandes, ni
/// alrededor del rótulo—. Se quedan porque **deslizar no existe en todas
/// partes**: Reportes y Rutas se abren también en un escritorio con ratón, donde
/// no hay dedo que arrastrar, y una fila de puntos no se recorre con el
/// teclado. Las bolitas también se pueden pulsar, pero con doce zonas acertarle
/// a la de al lado es una puntería que nadie tiene que tener.
///
/// # Por qué un `PageView` y no un detector de gestos propio
///
/// Porque el gesto tiene que ser el que la gente ya conoce de su teléfono: se
/// arrastra y el contenido va PEGADO al dedo, se suelta a medias y vuelve, se
/// tira rápido y salta. Eso es un `PageView`, y encima trae la parte delicada
/// resuelta: se lleva bien con el desplazamiento vertical de dentro (los ejes no
/// compiten) y **pierde la arena contra una pulsación larga**, que es lo que
/// deja intacto el arrastre de tarjetas y de cabeceras de columna.
///
/// Ese último punto es el que no se puede romper. `ArrastrableSegunPuntero`
/// (`pantallas/tablero/vista/kit.dart`) arrastra con el dedo mediante un
/// `DelayedMultiDragGestureRecognizer`: si el dedo se queda quieto 200 ms, gana
/// el arrastre; si se mueve antes, gana el deslizamiento. Son gestos distintos y
/// no se pisan. Lo que SÍ se los comería es un arrastre inmediato para el dedo —
/// por eso `punterosQueArrastranDelTiron` no lleva `touch`, y por eso hay una
/// prueba que lo vigila desde este lado.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'colores.dart';

/// Lo que tarda el contenido en llegar a la pestaña nueva cuando el cambio NO
/// viene del dedo (una flecha, una bolita). Lo justo para que se vea hacia dónde
/// se fue.
const Duration loQueTardaElCambio = Duration(milliseconds: 220);

/// Las claves de los mandos del carrusel. Públicas porque las pruebas tienen que
/// poder pulsarlos y mirar si están apagados, y buscarlos por el dibujo ataría
/// la prueba al icono.
abstract final class ClavesDePestanas {
  static const atras = ValueKey('pestanas-atras');
  static const adelante = ValueKey('pestanas-adelante');

  /// La bolita número [i], contando desde cero.
  static ValueKey<String> bola(int i) => ValueKey('pestanas-bola-$i');

  /// El rótulo de la que se está viendo — el único que se pinta.
  static const rotulo = ValueKey('pestanas-rotulo');
}

/// LA CABECERA DE UN CARRUSEL DE PESTAÑAS: dónde estás y cuántas más hay.
///
/// [titulo] es el nombre de la pestaña en la que se está, ya montado por quien
/// la usa (con su cuenta: «Sin colocar (308)»). [cuantas] es cuántas bolitas
/// salen, que es cuántos sitios hay a los que ir — y no tiene por qué coincidir
/// con cuántos títulos distintos hay: en el Tablero las doce zonas son doce
/// bolitas bajo el mismo rótulo de «Zonas».
class CarruselDePestanas extends StatelessWidget {
  const CarruselDePestanas({
    required this.indice,
    required this.cuantas,
    required this.titulo,
    required this.alCambiar,
    this.rotulo,
    this.etiquetas,
    super.key,
  });

  /// En cuál se está, contando desde cero.
  final int indice;

  /// Cuántas bolitas. Con una sola no se pinta ninguna: un carrusel de uno no es
  /// un carrusel, y una bolita suelta sólo ocupa sitio.
  final int cuantas;

  /// El texto de la que se está viendo.
  final String titulo;

  /// Y su dibujo, cuando el rótulo necesita algo más que texto (la insignia con
  /// el número de filas, en Reportes). `null` = se pinta [titulo] y ya.
  final Widget? rotulo;

  /// Los nombres de cada sitio, para el rótulo emergente de su bolita. Puede
  /// faltar o ser más corta: entonces la bolita va sin nombre.
  final List<String>? etiquetas;

  final ValueChanged<int> alCambiar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // SÓLO LA ACTUAL. Las demás no se enseñan: eso es lo que pidió Jose.
        DefaultTextStyle.merge(
          key: ClavesDePestanas.rotulo,
          style: tema.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
          child: rotulo ?? Text(titulo),
        ),
        if (cuantas > 1) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Flecha(
                clave: ClavesDePestanas.atras,
                icono: Icons.chevron_left,
                destino: indice - 1,
                cuantas: cuantas,
                etiquetas: etiquetas,
                alCambiar: alCambiar,
              ),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 0; i < cuantas; i++)
                      _Bola(
                        cual: i,
                        activa: i == indice,
                        nombre: _nombre(i),
                        alCambiar: alCambiar,
                      ),
                  ],
                ),
              ),
              _Flecha(
                clave: ClavesDePestanas.adelante,
                icono: Icons.chevron_right,
                destino: indice + 1,
                cuantas: cuantas,
                etiquetas: etiquetas,
                alCambiar: alCambiar,
              ),
            ],
          ),
        ],
      ],
    );
  }

  String? _nombre(int i) {
    final nombres = etiquetas;
    if (nombres == null || i >= nombres.length) return null;
    return nombres[i];
  }
}

/// Una bolita: dónde estás y cuántas más hay. Se puede pulsar.
class _Bola extends StatelessWidget {
  const _Bola({
    required this.cual,
    required this.activa,
    required this.nombre,
    required this.alCambiar,
  });

  final int cual;
  final bool activa;
  final String? nombre;
  final ValueChanged<int> alCambiar;

  @override
  Widget build(BuildContext context) {
    final bola = AnimatedContainer(
      duration: loQueTardaElCambio,
      width: activa ? 9 : 7,
      height: activa ? 9 : 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // La apagada no se borra: tiene que verse que HAY otra, que es para lo
        // único que están las bolitas.
        color: activa
            ? Colores.primario
            : Colores.primario.withValues(alpha: 0.30),
      ),
    );
    return Tooltip(
      message: nombre ?? 'Pestaña ${cual + 1}',
      child: InkResponse(
        key: ClavesDePestanas.bola(cual),
        onTap: () => alCambiar(cual),
        radius: 14,
        // 7 px de aire por lado: un punto de 7 px con nada alrededor no se puede
        // pulsar con un dedo.
        child: Padding(padding: const EdgeInsets.all(7), child: bola),
      ),
    );
  }
}

class _Flecha extends StatelessWidget {
  const _Flecha({
    required this.clave,
    required this.icono,
    required this.destino,
    required this.cuantas,
    required this.etiquetas,
    required this.alCambiar,
  });

  final Key clave;
  final IconData icono;

  /// A dónde iría esta flecha. Fuera de `0..cuantas-1` = no hay a dónde ir.
  final int destino;
  final int cuantas;
  final List<String>? etiquetas;
  final ValueChanged<int> alCambiar;

  @override
  Widget build(BuildContext context) {
    // EL EXTREMO: la flecha se queda APAGADA, no desaparece.
    //
    // Quitarla mueve la fila entera cada vez que se cambia de pestaña y además
    // deja sin decir por qué no se puede seguir. Apagada dice las dos cosas de
    // un vistazo: por aquí hay más, por aquí se acabó.
    final puede = destino >= 0 && destino < cuantas;
    final nombres = etiquetas;
    final nombre = puede && nombres != null && destino < nombres.length
        ? nombres[destino]
        : null;
    return IconButton(
      key: clave,
      icon: Icon(icono, size: 18),
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      visualDensity: VisualDensity.compact,
      tooltip: nombre == null ? null : 'Ir a «$nombre»',
      onPressed: puede ? () => alCambiar(destino) : null,
    );
  }
}

/// EL CONTENIDO DE UNAS PESTAÑAS, QUE SE CAMBIA DESLIZANDO EL DEDO.
///
/// [indice] manda: si lo cambia alguien de fuera (una flecha, una bolita) el
/// contenido se desliza hasta él; si lo cambia el dedo, sale por [alCambiar] y
/// quien lo guarda se entera.
///
/// Las páginas se construyen **una a una** (`PageView.builder`) y no todas de
/// golpe: en el tablero cada página es una zona con su lista de tarjetas dentro,
/// y doce zonas construidas a la vez es justo lo que el `ListView.builder` de
/// antes evitaba.
class CuerpoDeslizable extends StatefulWidget {
  const CuerpoDeslizable({
    required this.indice,
    required this.cuantas,
    required this.pagina,
    required this.alCambiar,
    super.key,
  });

  final int indice;
  final int cuantas;
  final IndexedWidgetBuilder pagina;
  final ValueChanged<int> alCambiar;

  @override
  State<CuerpoDeslizable> createState() => _CuerpoDeslizableState();
}

class _CuerpoDeslizableState extends State<CuerpoDeslizable> {
  late final PageController _mando = PageController(
    initialPage: widget.indice.clamp(0, widget.cuantas - 1),
  );

  @override
  void dispose() {
    _mando.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CuerpoDeslizable anterior) {
    super.didUpdateWidget(anterior);
    if (widget.indice == anterior.indice) return;
    // DESPUÉS DEL FOTOGRAMA, no dentro.
    //
    // `didUpdateWidget` corre en plena construcción del árbol, y arrancar ahí
    // una animación de desplazamiento avisa a los oyentes del `Scrollable` en
    // mitad del `build`: es el «markNeedsBuild called during build» clásico.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mando.hasClients) return;
      final destino = widget.indice;
      if (destino < 0 || destino >= widget.cuantas) return;
      // Si llegó deslizando ya está donde toca: animar otra vez sería un tirón.
      if (_mando.page?.round() == destino) return;
      unawaited(
        _mando.animateToPage(
          destino,
          duration: loQueTardaElCambio,
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => PageView.builder(
    controller: _mando,
    // A LO ANCHO, y sólo a lo ancho.
    //
    // Dentro de cada página hay listas que se desplazan hacia arriba y hacia
    // abajo —las tarjetas de una zona, los pedidos sin colocar—. Son dos ejes
    // distintos, así que ninguno se come al otro: el dedo que baja la lista baja
    // la lista y no cambia de pestaña. Poner esto en vertical sería cambiar un
    // fallo por otro.
    scrollDirection: Axis.horizontal,
    itemCount: widget.cuantas,
    onPageChanged: widget.alCambiar,
    itemBuilder: widget.pagina,
  );
}

/// LAS PESTAÑAS QUE SE ADAPTAN AL SITIO QUE HAY.
///
/// Jose, 17/09/2026, viendo el carrusel en la web: «en la web el slice sí puede
/// ser como estaba antes, que salían los tabs; los tabs así como están eran para
/// el móvil, que casi no tiene espacio».
///
/// Tenía razón y el fallo fue mío al repartirlo: el carrusel resuelve un
/// problema que **sólo existe en un teléfono** —tres etiquetas con sus cuentas
/// no caben en 390 px—. En un monitor caben de sobra, y esconder dos de tres
/// detrás de unas bolitas es quitarle información a quien tiene sitio para
/// verla. Lo mismo que el Tablero ya hacía con su guarda de 900.
///
/// Por debajo de [anchoDeLasPestanas], carrusel. Por encima, las tres a la vez,
/// la de en medio marcada. El contenido no cambia: el `CuerpoDeslizable` de
/// debajo sigue deslizándose igual, que en un portátil con pantalla táctil
/// también se usa.
class PestanasQueCaben extends StatelessWidget {
  const PestanasQueCaben({
    required this.indice,
    required this.etiquetas,
    required this.alCambiar,
    this.rotulo,
    this.anchoParaTodas,
    super.key,
  });

  /// El ancho a partir del cual caben todas. Es el mismo que usa el Tablero
  /// para partirse en dos mitades: si cabe un tablero de dos columnas, caben
  /// tres etiquetas.
  ///
  /// **Es el valor por DEFECTO, no una ley** — ver [anchoParaTodas].
  static const anchoDeLasPestanas = 900.0;

  /// EL UMBRAL DE ESTA PANTALLA, cuando 900 se queda largo — 28/09/2026.
  ///
  /// Los 900 de arriba son prudentes a propósito: los comparten Reportes y el
  /// Tablero, cuyas pestañas llevan rótulos largos. Pero en Rutas los mandos se
  /// metieron dentro del panel de la lista —de unos 530 px en un monitor— y ahí
  /// `Planificadas (0) · En curso (1) · Historial (0)` miden unos 420 px
  /// JUNTAS: caben de sobra, y aun así el umbral fijo las convertía en
  /// carrusel, que es esconder dos de tres detrás de unas bolitas teniendo
  /// sitio para verlas.
  ///
  /// Y no se arregla repartiendo la pantalla de otra manera: ni al 50/50 en un
  /// monitor de 1600 sale una columna de 900.
  ///
  /// Se pasa por parámetro y NO se baja el valor común: bajarlo a ojo por una
  /// pantalla puede partir las otras dos, que tienen rótulos más largos y a las
  /// que nadie está mirando ahora mismo. Quien conoce sus etiquetas es la
  /// pantalla.
  final double? anchoParaTodas;

  final int indice;
  final List<String> etiquetas;
  final ValueChanged<int> alCambiar;

  /// El dibujo del rótulo cuando hace falta algo más que texto (la insignia con
  /// el número de filas de Reportes). Sólo se usa en el carrusel.
  final Widget? rotulo;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, medidas) {
      if (medidas.maxWidth < (anchoParaTodas ?? anchoDeLasPestanas)) {
        return CarruselDePestanas(
          indice: indice,
          cuantas: etiquetas.length,
          titulo: etiquetas[indice],
          etiquetas: etiquetas,
          rotulo: rotulo,
          alCambiar: alCambiar,
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < etiquetas.length; i++)
            _Pestana(
              texto: etiquetas[i],
              elegida: i == indice,
              alPulsar: () => alCambiar(i),
            ),
        ],
      );
    },
  );
}

class _Pestana extends StatelessWidget {
  const _Pestana({
    required this.texto,
    required this.elegida,
    required this.alPulsar,
  });

  final String texto;
  final bool elegida;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) => elegida
      ? FilledButton(onPressed: alPulsar, child: Text(texto))
      : OutlinedButton(onPressed: alPulsar, child: Text(texto));
}
