// LA FICHA DE UN CLIENTE, en cajón.
//
// POR QUE EXISTE ESTE FICHERO — 22/09/2026. En la lista de Clientes se tocaba
// una fila y **no pasaba nada**: ni se abría nada, ni había chevrón, ni ninguna
// otra pista de si aquello se podía pulsar o no. Una fila que no contesta no se
// distingue de una aplicación colgada, así que o abre o no parece pulsable. Y
// aquí sí hay qué enseñar: de cada cliente se guardan trece campos y la lista
// sólo pinta cuatro columnas —en el teléfono, tres líneas—, así que el
// teléfono, la zona, la sucursal y las coordenadas no se veían en ninguna
// pantalla de la aplicación.
//
// **No consulta nada.** Todo lo que pinta sale del `ClienteConKm` que la lista
// ya tiene en la mano. Es a propósito y por dos motivos: abrir la ficha no puede
// depender de que haya red ni base viva, y una consulta de Drift dentro de un
// `testWidgets` **cuelga la prueba en vez de fallar** (CLAUDE.md §5), así que
// una ficha que consulta es una ficha que no se puede probar donde se usa.
//
// Cajón y no modal: excepción aprobada para este proyecto el 05/09/2026
// (CLAUDE.md §4) — aquí es cajón también en escritorio. La ✕ de la cabecera la
// pone `Cajon` y no desaparece nunca.

import 'package:flutter/material.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/tema.dart';
import '../datos/repositorio_clientes.dart';

/// Abre la ficha del cliente. Devuelve cuando se cierra.
Future<void> abrirCajonCliente(BuildContext contexto, ClienteConKm fila) {
  final c = fila.cliente;
  final codigo = c.codigo;
  return abrirCajon<void>(
    contexto,
    titulo: c.name,
    subtitulo: codigo != null && codigo.isNotEmpty ? codigo : c.municipio,
    ancho: AnchoCajon.md,
    cuerpo: (_) => FichaDeCliente(fila: fila),
  );
}

/// El cuerpo de la ficha. Suelto para poder pintarlo sin abrir el cajón.
class FichaDeCliente extends StatelessWidget {
  const FichaDeCliente({required this.fila, super.key});

  final ClienteConKm fila;

  /// El literal de lo que no se sabe. Un hueco se ve y se rellena; un cero o un
  /// vacío se leen como un dato (CLAUDE.md §2).
  static const sinDato = '—';

  @override
  Widget build(BuildContext context) {
    final c = fila.cliente;
    final telefono = c.phone;
    final dePedido = c.source == 'pedido';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Insignia(
          dePedido ? 'PEDIDO' : 'Manual',
          color: dePedido ? Colores.enCurso : Colores.tintaSuave,
          fondo: dePedido ? Colores.enCursoFondo : Colores.grisFondo,
        ),
        const SizedBox(height: Aire.lg),
        // El teléfono primero: es lo único de esta ficha que se usa **antes** de
        // salir con el camión, y un cliente sin él es una entrega que no se
        // puede avisar.
        if (telefono != null && telefono.isNotEmpty)
          _Dato(etiqueta: 'Teléfono', valor: telefono, mono: true)
        else
          const _Dato(
            etiqueta: 'Teléfono',
            valor: 'sin teléfono',
            enAmbar: true,
          ),
        _Dato(etiqueta: 'Código', valor: c.codigo, mono: true),
        _Dato(etiqueta: 'Dirección', valor: c.address),
        _Dato(etiqueta: 'Municipio', valor: c.municipio),
        _Dato(etiqueta: 'Zona de reparto', valor: c.zona),
        _Dato(etiqueta: 'Vendedor', valor: c.vendedor),
        // La misma cifra que la lista, con los mismos decimales: dos números
        // distintos para la misma distancia es lo que hace que no se crea
        // ninguno.
        _Dato(
          etiqueta: 'Distancia al almacén',
          valor: fila.km == null ? null : '${fila.km} km',
          nota: fila.km == null
              ? 'Esta sucursal no tiene ningún almacén con coordenadas.'
              : null,
          mono: true,
        ),
        _Dato(etiqueta: 'Sucursal', valor: c.sucursalCodigo),
        // Las coordenadas son el dato por el que este cliente está en la lista:
        // los de PEDIDO sólo entran cuando tienen geolocalización, y es lo que
        // usa el mapa para colocarlo.
        _Dato(etiqueta: 'Coordenadas', valor: '${c.lat}, ${c.lng}', mono: true),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.etiqueta,
    required this.valor,
    this.nota,
    this.mono = false,
    this.enAmbar = false,
  });

  final String etiqueta;
  final String? valor;
  final String? nota;
  final bool mono;
  final bool enAmbar;

  @override
  Widget build(BuildContext context) {
    final texto = valor == null || valor!.isEmpty
        ? FichaDeCliente.sinDato
        : valor!;
    final color = enAmbar ? Colores.ambar : Colores.tinta;

    return Padding(
      padding: const EdgeInsets.only(bottom: Aire.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiqueta,
            style: Tipos.texto(
              tamano: 11,
              peso: FontWeight.w600,
              color: Colores.tintaSuave,
              interletra: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          // Sin `maxLines`: en la ficha la dirección larga se lee ENTERA, que
          // es justo lo que la lista no puede dar. Lo que se envuelve por
          // palabras nunca se parte letra a letra.
          Text(
            texto,
            style: mono
                ? Tipos.mono(tamano: 13, color: color)
                : Tipos.texto(tamano: 14, color: color),
          ),
          if (nota != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                nota!,
                style: Tipos.texto(tamano: 11.5, color: Colores.tintaSuave),
              ),
            ),
        ],
      ),
    );
  }
}
