import 'package:flutter/material.dart';

import 'colores.dart';
import 'tema.dart';

/// La caja de siempre: fondo blanco, **borde fino de 1 px del color `--line`**,
/// esquinas de `rounded-2xl` y la sombra `md` calida.
///
/// Las tres cosas juntas, no una: en delivery la tarjeta se despega del papel
/// por la sombra y se recorta contra el por el borde. Con sombra y sin borde se
/// ve difusa; con borde y sin sombra se ve plana, que es como estaba.
class Tarjeta extends StatefulWidget {
  const Tarjeta({
    required this.child,
    this.titulo,
    this.icono,
    this.relleno = const EdgeInsets.all(Aire.xl),
    this.alPulsar,
    this.franja,
    super.key,
  });

  final Widget child;
  final String? titulo;

  /// El icono del titulo, en primario y a la izquierda, como los `h3` de las
  /// tarjetas del panel de delivery.
  final IconData? icono;

  final EdgeInsetsGeometry relleno;
  final VoidCallback? alPulsar;

  /// La FRANJA DE COLOR de 3 px pegada al borde de arriba
  /// (`<span className="absolute inset-x-0 top-0 h-1 …" />`). Es lo que hace que
  /// cuatro tarjetas iguales se distingan de un vistazo.
  final Color? franja;

  @override
  State<Tarjeta> createState() => _TarjetaState();
}

class _TarjetaState extends State<Tarjeta> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final sePulsa = widget.alPulsar != null;
    final radio = BorderRadius.circular(Radios.xl);

    final contenido = Padding(
      padding: widget.relleno,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.titulo != null) ...[
            Row(
              children: [
                if (widget.icono != null) ...[
                  Icon(widget.icono, size: 20, color: Colores.primario),
                  const SizedBox(width: Aire.sm),
                ],
                Expanded(
                  child: Text(widget.titulo!, style: tema.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: Aire.lg),
          ],
          widget.child,
        ],
      ),
    );

    return MouseRegion(
      onEnter: sePulsa ? (_) => setState(() => _encima = true) : null,
      onExit: sePulsa ? (_) => setState(() => _encima = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        // `hover:-translate-y-0.5`: la tarjeta que se puede pulsar se levanta
        // dos pixeles. Es la senal de que se pulsa, sin tener que escribirlo.
        transform: Matrix4.translationValues(0, _encima ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: Colores.blanco,
          borderRadius: radio,
          border: Border.all(color: Colores.linea),
          boxShadow: _encima ? Sombras.lg : Sombras.md,
        ),
        // `ClipRRect` para que la franja de arriba siga la curva de la esquina.
        child: ClipRRect(
          borderRadius: radio,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.alPulsar,
              hoverColor: Colors.transparent,
              child: Stack(
                children: [
                  contenido,
                  if (widget.franja != null)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(height: 3, color: widget.franja),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La tarjeta de cifra del Panel: etiqueta arriba en versalitas, el numero
/// grande en Bricolage y el icono en su cuadrado tintado a la derecha.
///
/// Es la pieza que mas se mira de toda la aplicacion, y es exactamente el
/// `StatCard` de `delivery/src/app/(dashboard)/dashboard/page.tsx`.
class TarjetaDeCifra extends StatelessWidget {
  const TarjetaDeCifra({
    required this.etiqueta,
    required this.valor,
    this.subtexto,
    this.color,
    this.icono,
    this.alPulsar,
    super.key,
  });

  final String etiqueta;
  final String valor;
  final String? subtexto;

  /// QUE UNA CIFRA SE PUEDA TOCAR PARA VER DE QUÉ SALE — 28/09/2026.
  ///
  /// Jose, mirando el Panel: «me dice q entregado uno y en hsitorial me sale
  /// vacio eso q se entrego si no se ah completado nada». Los números estaban
  /// bien —el pedido estaba en una ruta todavía abierta— pero **tuvo que
  /// preguntarlo**, porque un contador que dice «1» y no deja llegar a CUÁL
  /// obliga a adivinar.
  ///
  /// Va aquí y no en la pantalla porque `Tarjeta` ya sabe hacerlo: tiene su
  /// `alPulsar` con la levantada al pasar por encima. Sin esto, quien lo
  /// necesitaba tenía que superponerle un `GestureDetector` y una flecha con un
  /// `Stack`, o sea reconstruir a mano la señal de «esto se pulsa» que el resto
  /// de la aplicación ya da.
  ///
  /// `null` deja la tarjeta como siempre, que es lo correcto para una cifra que
  /// no lleva a ningún sitio: un gesto que acaba en una pantalla vacía es peor
  /// que ninguno.
  final VoidCallback? alPulsar;

  /// En ambar cuando hay algo que mirar; en primario cuando no. Lo decide la
  /// pantalla, no la tarjeta.
  final Color? color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tinte = color ?? Colores.primario;
    return Tarjeta(
      franja: tinte,
      alPulsar: alPulsar,
      relleno: const EdgeInsets.fromLTRB(Aire.xl, Aire.xl, Aire.xl, Aire.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // `text-[11px] font-semibold uppercase tracking-[0.14em]`.
                //
                // **En su literal, sin pasar a mayusculas.** En la de Next las
                // versalitas las pone el CSS y el texto del documento sigue
                // siendo «Pedidos sin ruta»; aqui `toUpperCase()` cambiaria el
                // dato, y los literales de estas cuatro etiquetas se comparan
                // uno a uno contra el pliego (§1). Lo que hace el trabajo de
                // «rotulo» es el tamano, el peso y el interletraje.
                Text(
                  etiqueta,
                  style: Tipos.texto(
                    tamano: 11,
                    peso: FontWeight.w600,
                    color: Colores.tintaSuave,
                    interletra: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                // `text-[2.1rem] font-extrabold font-display tabular-nums`.
                // La cifra va en TINTA, como en la de Next... salvo en ambar.
                //
                // El ambar de esta aplicacion significa «mira esto» (§1: la
                // tarjeta de pedidos sin ruta se pinta en ambar con > 0), y una
                // cifra que avisa tiene que avisar ella, no sólo su franja. Los
                // otros tres tintes —primario, verde, naranja— son de identidad,
                // no de aviso, y se quedan en la franja y en el icono.
                // LA CIFRA SE ENCOGE, NO SE CORTA.
                //
                // Con `ellipsis` a secas, `3.964.352 CUP` salia como
                // `3.964.352 C…` en la tarjeta de Ingresos Totales: un importe
                // a medias en la pantalla que existe para cuadrar caja. En USD
                // no se veia porque el numero es setecientas veces mas corto.
                //
                // `scaleDown` sólo achica cuando no cabe; mientras quepa, el
                // tamano es el del pliego (`text-[2.1rem]`).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    valor,
                    maxLines: 1,
                    style: tema.textTheme.displaySmall?.copyWith(
                      color: tinte == Colores.ambar
                          ? Colores.ambar
                          : Colores.tinta,
                      fontFeatures: Tipos.cifrasEnColumna,
                    ),
                  ),
                ),
                if (subtexto != null) ...[
                  const SizedBox(height: Aire.sm),
                  Text(
                    subtexto!,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: Colores.tintaSuave,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (icono != null) ...[
            const SizedBox(width: Aire.md),
            // El cuadrado tintado del icono: `w-11 h-11 rounded-xl bg-…/10`.
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tinte.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(Radios.lg),
              ),
              child: Icon(icono, size: 24, color: tinte),
            ),
          ],
        ],
      ),
    );
  }
}
