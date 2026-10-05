import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../datos/repositorio_clientes.dart';
import 'cajon_cliente.dart';

/// La lista de Clientes: **tabla de 4 columnas en pantalla grande y una tarjeta
/// por cliente en el teléfono**.
///
/// EN 390 px NO CABE ESTA TABLA, y lo que hacía era peor que no caber
/// (22/09/2026, teléfono de Jose): la dirección se salía por el borde derecho y
/// se quedaba cortada a mitad de palabra —«calle 101 e», «Calzada de»— **sin
/// elipsis**, así que no había forma de saber si faltaba una palabra o el barrio
/// entero. Debajo de [anchoMinimo] se pinta una tarjeta por cliente: el nombre
/// arriba, y debajo el código, el teléfono y la dirección con su elipsis.
///
/// Por encima de ese ancho sigue siendo la tabla, con **desplazamiento propio**
/// (`pantallas.md` §11): el scroll horizontal es de la TABLA, no de la pagina.
/// Si se deja que empuje la pagina, se mueve de lado todo —cabecera, filtros y
/// paginacion— y se pierde el sitio con el dedo.
///
/// Y la fila ABRE. Antes no abría nada y tampoco decía que no: se tocaba el
/// nombre y no pasaba nada (ver `cajon_cliente.dart`).
class TablaClientes extends StatelessWidget {
  const TablaClientes({
    required this.clientes,
    required this.conDistancia,
    this.alAbrir,
    super.key,
  });

  final List<ClienteConKm> clientes;

  /// Los km sólo salen debajo del vendedor **cuando se filtro por distancia**,
  /// que es lo que hace la de Next.
  final bool conDistancia;

  /// Qué pasa al tocar un cliente. Por defecto, el cajón con su ficha; entra por
  /// parámetro sólo para poder comprobar el gesto sin abrir nada.
  final void Function(BuildContext contexto, ClienteConKm fila)? alAbrir;

  /// El ancho por debajo del cual esto deja de ser una tabla.
  static const anchoMinimo = 736.0;

  /// Lo más ancha que se deja la columna de la dirección en la tabla.
  ///
  /// Sin tope, `DataTable` le da a la celda el ancho que pida su texto y la
  /// tabla entera crece hasta donde haga falta: la dirección más larga decide
  /// cuánto hay que arrastrar de lado para ver las otras tres columnas. Con
  /// tope, lo que no cabe se dice con una elipsis, que es una señal, y la ficha
  /// la enseña entera.
  static const anchoDeLaDireccion = 280.0;

  void _abrir(BuildContext contexto, ClienteConKm fila) =>
      (alAbrir ?? (c, f) => abrirCajonCliente(c, f))(contexto, fila);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, medidas) {
      if (medidas.maxWidth < anchoMinimo) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Solo la PRIMERA se deja senalar: hay una tarjeta por cliente y
            // dos marcas con el mismo nombre a la vez no se distinguen. La
            // primera es ademas la que siempre esta construida.
            for (final (cual, fila) in clientes.indexed)
              ControlSenalado(
                nombre: Senalado.clientesAbrirElCliente,
                senalable: cual == 0,
                child: _Tarjeta(
                  // La llave de la tarjeta: es lo que deja medirla en una prueba.
                  key: ValueKey('cliente-${fila.cliente.id}'),
                  fila: fila,
                  conDistancia: conDistancia,
                  alAbrir: () => _abrir(context, fila),
                ),
              ),
          ],
        );
      }

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: medidas.maxWidth),
          child: Theme(
            data: Theme.of(context)
                .copyWith(dataTableTheme: temaDeTabla(context)),
            child: DataTable(
              // Las filas se pulsan, pero NO se marcan: sin esto `DataTable`
              // añade una columna de casillas por su cuenta en cuanto una fila
              // tiene `onSelectChanged`, y aquí no hay nada que hacer con una
              // selección de clientes.
              showCheckboxColumn: false,
              columns: [
                DataColumn(label: cabecera('Cliente')),
                DataColumn(label: cabecera('Dirección')),
                DataColumn(label: cabecera('Vendedor')),
                DataColumn(label: cabecera('Origen')),
              ],
              rows: [
                for (final (cual, c) in clientes.indexed)
                  _fila(context, c, laPrimera: cual == 0),
              ],
            ),
          ),
        ),
      );
    },
  );

  /// `laPrimera` es lo unico que decide si esta fila lleva la marca de la guia.
  ///
  /// La marca va DENTRO de la celda del nombre y no sobre la fila, y no por gusto:
  /// una `DataRow` no es un `Widget` y no se puede envolver. La celda del nombre es
  /// la que el paso nombra —«Clic en la fila», y la fila entera abre— y es la que
  /// se ve a la izquierda, asi que el agujero cae donde esta mirando quien lee.
  DataRow _fila(
    BuildContext context,
    ClienteConKm fila, {
    required bool laPrimera,
  }) {
    final c = fila.cliente;

    return DataRow(
      onSelectChanged: (_) => _abrir(context, fila),
      cells: [
        DataCell(
          ControlSenalado(
            nombre: Senalado.clientesAbrirElCliente,
            senalable: laPrimera,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.name,
                  style: Tipos.texto(tamano: 14, peso: FontWeight.w500),
                ),
                // El codigo en JetBrains Mono, no en la `monospace` del sistema:
                // en Windows esa es Courier New y no se parece a nada de aqui.
                if (c.codigo != null && c.codigo!.isNotEmpty)
                  Text(
                    c.codigo!,
                    style: Tipos.mono(tamano: 11.5, color: Colores.tintaSuave),
                  ),
                if (c.phone != null && c.phone!.isNotEmpty)
                  Text(
                    c.phone!,
                    style: Tipos.mono(tamano: 11.5, color: Colores.tintaSuave),
                  )
                else
                  // En ambar porque un cliente sin telefono es una entrega que no
                  // se puede avisar, y eso se decide antes de salir, no en la
                  // puerta.
                  Text(
                    'sin teléfono',
                    style: Tipos.texto(tamano: 11.5, color: Colores.ambar),
                  ),
              ],
            ),
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: anchoDeLaDireccion),
            child: Text(
              direccionDe(c),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.vendedor?.isNotEmpty ?? false ? c.vendedor! : '—'),
              if (conDistancia && fila.km != null)
                Text(
                  '${fila.km} km',
                  style: Tipos.mono(tamano: 11.5, color: Colores.tintaSuave),
                ),
            ],
          ),
        ),
        DataCell(_Insignia(deSource: c.source)),
      ],
    );
  }
}

/// La dirección tal y como se lee en la lista: calle y municipio con un punto en
/// medio. Fuera de la clase porque la pintan la fila y la tarjeta.
String direccionDe(Cliente c) {
  final partes = [
    c.address,
    c.municipio,
  ].where((t) => t != null && t.isNotEmpty).join(' · ');
  return partes.isEmpty ? '—' : partes;
}

/// UN CLIENTE EN UN TELEFONO.
///
/// Todo lo de una línea lleva `maxLines` con elipsis: es lo que convierte
/// «calle 101 e» cortado contra el borde en «calle 101 entre…», que dice que hay
/// más y que se abre para verlo. Y el chevrón, que es la pista de que abre —sin
/// él, tocar y que no pase nada y tocar y que abra se parecen demasiado.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.fila,
    required this.conDistancia,
    required this.alAbrir,
    super.key,
  });

  final ClienteConKm fila;
  final bool conDistancia;
  final VoidCallback alAbrir;

  @override
  Widget build(BuildContext context) {
    final c = fila.cliente;
    final codigo = c.codigo;
    final telefono = c.phone;

    return InkWell(
      onTap: alAbrir,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colores.linea)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Aire.lg,
          vertical: Aire.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tipos.texto(tamano: 14, peso: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  // Código y teléfono en un `Wrap`: cada uno recibe el ancho
                  // entero y salta de línea ENTERO cuando no cabe, que es lo
                  // que evita que una palabra se parta letra a letra.
                  Wrap(
                    spacing: Aire.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (codigo != null && codigo.isNotEmpty)
                        Text(
                          codigo,
                          style: Tipos.mono(
                            tamano: 11.5,
                            color: Colores.tintaSuave,
                          ),
                        ),
                      if (telefono != null && telefono.isNotEmpty)
                        Text(
                          telefono,
                          style: Tipos.mono(
                            tamano: 11.5,
                            color: Colores.tintaSuave,
                          ),
                        )
                      else
                        Text(
                          'sin teléfono',
                          style: Tipos.texto(
                            tamano: 11.5,
                            color: Colores.ambar,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    direccionDe(c),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Tipos.texto(tamano: 13, color: Colores.tinta),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: Aire.sm,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Insignia(deSource: c.source),
                      if (c.vendedor?.isNotEmpty ?? false)
                        Text(
                          c.vendedor!,
                          style: Tipos.texto(
                            tamano: 12,
                            color: Colores.tintaSuave,
                          ),
                        ),
                      if (conDistancia && fila.km != null)
                        Text(
                          '${fila.km} km',
                          style: Tipos.mono(
                            tamano: 11.5,
                            color: Colores.tintaSuave,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, left: Aire.sm),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: Colores.tintaSuave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Insignia extends StatelessWidget {
  const _Insignia({required this.deSource});

  final String? deSource;

  @override
  Widget build(BuildContext context) {
    final dePedido = deSource == 'pedido';
    return Insignia(
      dePedido ? 'PEDIDO' : 'Manual',
      color: dePedido ? Colores.enCurso : Colores.tintaSuave,
      fondo: dePedido ? Colores.enCursoFondo : Colores.grisFondo,
    );
  }
}
