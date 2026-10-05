/// PINTAR EL MANUAL. De los bloques de `datos/markdown.dart` a lo que se lee.
///
/// Todo esta pensado para **un telefono de 390 px**, que es donde se va a abrir:
/// nada va en una fila que pueda no caber, los pasos llevan su numero en un
/// circulo a la izquierda para que se sigan con el dedo, y las tablas **no se
/// pintan como tablas** —una de cuatro columnas a 390 px no se lee— sino como un
/// bloque por fila con el titulo de cada columna delante.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../datos/markdown.dart';

/// LO QUE EL TEXTO NECESITA SABER DE FUERA PARA PINTARSE: a donde llevan sus
/// enlaces.
///
/// El manual esta escrito con enlaces relativos entre paginas
/// (`../comun/glosario.md#apunte`), que es lo que lo hace legible tambien en el
/// repositorio. Dentro de la aplicacion no hay ficheros, asi que cada enlace se
/// resuelve aqui, y **el que no lleve a ningun sitio se pinta como texto llano**:
/// un enlace que no abre nada es peor que una palabra normal, porque se toca tres
/// veces antes de rendirse.
class EnlacesDelManual {
  const EnlacesDelManual({
    required this.caminoDeLaPagina,
    required this.aDonde,
    required this.alSeguir,
  });

  /// La pagina que se esta pintando, para resolver los `../`.
  final String caminoDeLaPagina;

  /// Contesta si ese destino lleva a algun sitio **en esta forma de la
  /// aplicacion**. Devuelve `null` si no.
  final String? Function(String destino, String desdeLaPagina) aDonde;

  final void Function(String resuelto) alSeguir;

  /// Nadie: todos los enlaces se pintan como texto. Es lo que usan las pruebas
  /// del pintor, que no montan la guia entera.
  static const sinEnlaces = EnlacesDelManual(
    caminoDeLaPagina: '',
    aDonde: _aNingunSitio,
    alSeguir: _nada,
  );

  static String? _aNingunSitio(String destino, String desde) => null;
  static void _nada(String resuelto) {}
}

/// Pinta un documento entero —o el trozo de una tarea— uno debajo del otro.
List<Widget> pintarElManual(String markdown, EnlacesDelManual enlaces) => [
  for (final bloque in bloquesDe(markdown)) _BloquePintado(bloque, enlaces),
];

class _BloquePintado extends StatelessWidget {
  const _BloquePintado(this.bloque, this.enlaces);

  final BloqueDeManual bloque;
  final EnlacesDelManual enlaces;

  @override
  Widget build(BuildContext context) => switch (bloque) {
    Encabezado(:final nivel, :final texto) => Padding(
      // Mas aire ARRIBA que abajo: un titulo pertenece a lo que viene detras, y
      // si se reparte igual se lee pegado a lo de antes.
      padding: EdgeInsets.only(top: nivel <= 2 ? Aire.xl : Aire.lg, bottom: 6),
      child: Text(
        texto,
        style: Tipos.display(
          tamano: switch (nivel) {
            1 => 22,
            2 => 19,
            3 => 16.5,
            _ => 15,
          },
          peso: FontWeight.w700,
          color: Colores.tinta,
        ),
      ),
    ),
    Parrafo(:final texto) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RenglonDelManual(texto, enlaces: enlaces),
    ),
    Punto(:final nivel, :final texto, :final numero) => Padding(
      padding: EdgeInsets.only(left: nivel * 16.0, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (numero != null)
            // EL NUMERO DEL PASO, en su circulo. Son instrucciones que se siguen
            // con el dedo mientras se mira la pantalla de al lado: hay que poder
            // volver y encontrar «el 3» de un vistazo.
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              margin: const EdgeInsets.only(top: 1, right: 10),
              decoration: BoxDecoration(
                color: Colores.primarioTenue,
                shape: BoxShape.circle,
              ),
              child: Text(
                numero,
                style: Tipos.texto(
                  tamano: 11.5,
                  peso: FontWeight.w700,
                  color: Colores.primario,
                ),
              ),
            )
          else
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(top: 8, left: 6, right: 13),
              decoration: BoxDecoration(
                color: Colores.tintaSuave,
                shape: BoxShape.circle,
              ),
            ),
          Expanded(child: RenglonDelManual(texto, enlaces: enlaces)),
        ],
      ),
    ),
    Cita(:final texto) => Container(
      margin: const EdgeInsets.only(bottom: 12, top: 2),
      padding: const EdgeInsets.fromLTRB(Aire.md, 10, Aire.md, 10),
      decoration: BoxDecoration(
        color: Colores.grisFondo,
        border: Border(left: BorderSide(color: Colores.lineaFuerte, width: 3)),
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(Radios.sm),
        ),
      ),
      child: RenglonDelManual(texto, enlaces: enlaces, cursiva: true),
    ),
    Codigo(:final texto) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(Aire.md),
      decoration: BoxDecoration(
        color: Colores.grisFondo,
        border: Border.all(color: Colores.linea),
        borderRadius: BorderRadius.circular(Radios.sm),
      ),
      // A lo ancho y no partido: lo que hay aqui son mensajes de la pantalla y
      // ejemplos de numeros, y partirlos por la mitad los vuelve otra cosa.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          texto,
          style: Tipos.mono(tamano: 12, color: Colores.tinta, alto: 1.5),
        ),
      ),
    ),
    Regla() => Padding(
      padding: const EdgeInsets.symmetric(vertical: Aire.lg),
      child: Divider(height: 1, color: Colores.linea),
    ),
    Tabla(:final encabezados, :final filas) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final fila in filas)
            Container(
              margin: const EdgeInsets.only(bottom: Aire.sm),
              padding: const EdgeInsets.all(Aire.md),
              decoration: BoxDecoration(
                color: Colores.blanco,
                border: Border.all(color: Colores.linea),
                borderRadius: BorderRadius.circular(Radios.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < fila.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    if (i < encabezados.length && encabezados[i].isNotEmpty)
                      Text(
                        encabezados[i].toUpperCase(),
                        style: Tipos.texto(
                          tamano: 10,
                          peso: FontWeight.w700,
                          color: Colores.tintaSuave,
                          interletra: 0.6,
                        ),
                      ),
                    RenglonDelManual(fila[i], enlaces: enlaces),
                  ],
                ],
              ),
            ),
        ],
      ),
    ),
  };
}

/// UN RENGLON con su negrita, su `codigo` y sus enlaces.
///
/// Es un `StatefulWidget` por una razon concreta: cada enlace necesita su
/// `TapGestureRecognizer`, y un reconocedor que no se suelta es una fuga. En una
/// pagina de manual hay decenas, y la guia se abre y se cierra todo el dia.
class RenglonDelManual extends StatefulWidget {
  const RenglonDelManual(
    this.texto, {
    required this.enlaces,
    this.cursiva = false,
    super.key,
  });

  final String texto;
  final EnlacesDelManual enlaces;
  final bool cursiva;

  @override
  State<RenglonDelManual> createState() => _RenglonDelManualState();
}

class _RenglonDelManualState extends State<RenglonDelManual> {
  final _reconocedores = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _reconocedores) {
      r.dispose();
    }
    super.dispose();
  }

  void _soltarLosViejos() {
    for (final r in _reconocedores) {
      r.dispose();
    }
    _reconocedores.clear();
  }

  @override
  Widget build(BuildContext context) {
    _soltarLosViejos();
    final enlaces = widget.enlaces;

    return Text.rich(
      TextSpan(
        children: [
          for (final trozo in trozosDe(widget.texto))
            _spanDe(trozo, enlaces),
        ],
      ),
      style: Tipos.texto(
        tamano: 14.5,
        color: Colores.tinta,
        alto: 1.55,
      ).copyWith(fontStyle: widget.cursiva ? FontStyle.italic : null),
    );
  }

  InlineSpan _spanDe(Trozo trozo, EnlacesDelManual enlaces) {
    if (trozo.codigo) {
      return TextSpan(
        text: trozo.texto,
        style: Tipos.mono(
          tamano: 12.5,
          peso: trozo.fuerte ? FontWeight.w700 : FontWeight.w500,
          color: Colores.tinta,
        ),
      );
    }

    final peso = trozo.fuerte ? FontWeight.w700 : FontWeight.w400;

    final destino = trozo.destino;
    final aDonde = destino == null
        ? null
        : enlaces.aDonde(destino, enlaces.caminoDeLaPagina);
    if (aDonde == null) {
      // Incluye el caso del enlace que no lleva a ningun sitio en esta forma:
      // sale como texto normal, sin color de enlace y sin reaccionar al dedo.
      return TextSpan(text: trozo.texto, style: TextStyle(fontWeight: peso));
    }

    final reconocedor = TapGestureRecognizer()
      ..onTap = () => enlaces.alSeguir(aDonde);
    _reconocedores.add(reconocedor);
    return TextSpan(
      text: trozo.texto,
      recognizer: reconocedor,
      style: TextStyle(
        fontWeight: peso,
        color: Colores.primario,
        decoration: TextDecoration.underline,
        decorationColor: Colores.primario.withValues(alpha: 0.4),
      ),
    );
  }
}
