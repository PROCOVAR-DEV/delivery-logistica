// La tabla de Pedidos: 12 columnas que se esconden por anchura — y **por debajo
// de 768 px deja de ser una tabla**.
//
// EN UN TELEFONO NO CABE NINGUNA TABLA, por muchas columnas que se escondan.
// Medido el 22/09/2026 en el telefono de Jose (1080x2340, o sea 390 px
// logicos): lo que queda a esa anchura son siete columnas repartiendose 294 px,
// asi que `Completada` salia partida letra a letra —`C o m p l e t a d a` en
// vertical— y `sin cotizar` igual, y **una sola fila ocupaba media pantalla**.
// Un `Expanded` con `flex: 2` sobre 294 px son 39 px de celda, y en 39 px no
// entra ninguna palabra de la interfaz.
//
// Por eso debajo de ese ancho se pinta una TARJETA por pedido: lo importante
// arriba (cliente, folio y fecha), la direccion debajo con dos lineas y elipsis,
// y los estados y las cifras en un `Wrap` — que es lo que garantiza que ninguna
// palabra se parta, porque cada hijo de un `Wrap` recibe el ancho entero y salta
// de linea ENTERO cuando no cabe.
//
// **El escondite es por orden de prescindibilidad, no por hueco disponible**
// (`pantallas.md` §11): `Sucursal` bajo 1536, `Ruta` bajo 1280,
// `Artículos` bajo 1024, `Entrega` bajo 768. **Nunca se van:**
// factura (22/10/2026, Jose: la factura manda), cliente, direccion, peso, precio y estado. Escrito con umbrales fijos y no con
// un `Flexible` que se encoja, porque una columna de 12 px no se lee y ademas
// engana: parece que el dato esta.

import 'package:flutter/material.dart';

import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/conduce.dart' show ConduceDe;
import '../../../nucleo/fecha_de_la_factura.dart' show diaDeLaFacturaEnCuba;
import '../../../nucleo/numero_de_factura.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../../nucleo/regla_de_entrada.dart';
import '../datos/estado_reparto.dart';
import '../datos/formato.dart';
import '../datos/mandar_al_tablero.dart' show domicilioSinCobroSenalado;
import '../datos/repositorio_pedidos.dart';
import 'kit.dart';

/// Que columnas caben a este ancho.
class ColumnasVisibles {
  const ColumnasVisibles(this.ancho, {required this.conSucursal});

  final double ancho;

  /// La columna `Sucursal` sólo sale **si no hay sucursal elegida arriba**:
  /// repetir en cada fila lo que ya dice la barra es gastar el ancho que le hace
  /// falta a la direccion.
  final bool conSucursal;

  /// Debajo de esto no hay tabla que valga: se pinta una tarjeta por pedido.
  ///
  /// El numero es el mismo `Anchos.entrega` (768) del pliego §11 — el ultimo
  /// escalon, donde ya solo quedan siete columnas— pero se escribe aqui y no en
  /// `diseno/anchos.dart` porque esa constante nueva no es de esta tabla sola y
  /// ese fichero lo lleva otro. Si se sube a `Anchos`, se quita de aqui.
  static const enTarjetasBajo = 768.0;

  bool get enTarjetas => ancho < enTarjetasBajo;

  bool get sucursal => conSucursal && ancho >= 1536;
  bool get ruta => ancho >= 1280;
  bool get articulos => ancho >= 1024;

  /// La factura es la fila: no se esconde en ninguna tabla (la tarjeta, bajo 768, la lleva
  /// en su cabecera).
  bool get factura => ancho >= enTarjetasBajo;
  bool get entrega => ancho >= 768;
}

class TablaPedidos extends StatelessWidget {
  const TablaPedidos({
    required this.pedidos,
    required this.renglones,
    required this.rutas,
    required this.seleccion,
    required this.alMarcar,
    required this.alMarcarPagina,
    required this.alAbrir,
    required this.ahora,
    required this.conSucursal,
    this.conduces = const {},
    super.key,
  });

  /// Los conduces de esta página, por principal (`docs/conduces.md`): la fila de una principal dice
  /// «Conduce 47313 + 47314» y suma el peso y el domicilio de todas sus facturas. Sus miembros no
  /// están en [pedidos]: la consulta los esconde (`noEsMiembro`).
  final Map<String, ConduceDe> conduces;

  final List<Pedido> pedidos;
  final Map<String, List<RenglonConPeso>> renglones;

  /// Las rutas por id: de aqui salen el codigo que pinta la columna `Ruta` y el
  /// estado del que depende `En despacho` / `En ruta`.
  final Map<String, Ruta> rutas;
  final Set<String> seleccion;
  final void Function(String id) alMarcar;
  final void Function(List<String> ids, bool marcar) alMarcarPagina;
  final void Function(Pedido) alAbrir;
  final DateTime ahora;
  final bool conSucursal;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (contexto, medidas) {
      final columnas = ColumnasVisibles(
        medidas.maxWidth,
        conSucursal: conSucursal,
      );
      final ids = [for (final p in pedidos) p.id];
      final todosMarcados = ids.isNotEmpty && ids.every(seleccion.contains);

      if (columnas.enTarjetas) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CabeceraDeTarjetas(
              cuantos: ids.length,
              todosMarcados: todosMarcados,
              alMarcarPagina: (marcar) => alMarcarPagina(ids, marcar),
            ),
            Divider(height: 1, thickness: 1, color: Colores.linea),
            for (final (cual, pedido) in pedidos.indexed)
              _Tarjeta(
                esLaPrimera: cual == 0,
                // La llave de la tarjeta entera: es lo que deja MEDIRLA en una
                // prueba (`tester.getRect`), que es la unica forma de ver que
                // una fila ya no ocupa media pantalla.
                key: ValueKey('tarjeta-${pedido.id}'),
                pedido: pedido,
                conduce: conduces[pedido.id],
                estadoDeSuRuta: pedido.routeId == null
                    ? null
                    : rutas[pedido.routeId]?.status,
                codigoDeRuta: pedido.routeId == null
                    ? null
                    : rutas[pedido.routeId]?.routeCode,
                marcado: seleccion.contains(pedido.id),
                alMarcar: () => alMarcar(pedido.id),
                alAbrir: () => alAbrir(pedido),
                ahora: ahora,
              ),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cabecera(
            columnas: columnas,
            todosMarcados: todosMarcados,
            alMarcarPagina: (marcar) => alMarcarPagina(ids, marcar),
          ),
          Divider(height: 1, thickness: 1, color: Colores.linea),
          for (final (cual, pedido) in pedidos.indexed)
            _Fila(
              esLaPrimera: cual == 0,
              pedido: pedido,
              conduce: conduces[pedido.id],
              columnas: columnas,
              renglones: renglones[pedido.id] ?? const [],
              estadoDeSuRuta: pedido.routeId == null
                  ? null
                  : rutas[pedido.routeId]?.status,
              codigoDeRuta: pedido.routeId == null
                  ? null
                  : rutas[pedido.routeId]?.routeCode,
              marcado: seleccion.contains(pedido.id),
              alMarcar: () => alMarcar(pedido.id),
              alAbrir: () => alAbrir(pedido),
              ahora: ahora,
            ),
        ],
      );
    },
  );
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.columnas,
    required this.todosMarcados,
    required this.alMarcarPagina,
  });

  final ColumnasVisibles columnas;
  final bool todosMarcados;
  final void Function(bool) alMarcarPagina;

  @override
  Widget build(BuildContext context) {
    // `text-[11px] uppercase tracking-…` sobre papel: la cabecera de una tabla
    // de delivery no es una fila mas, es un rotulo.
    final estilo = Tipos.texto(
      tamano: 11,
      peso: FontWeight.w600,
      color: Colores.tintaSuave,
      interletra: 0.4,
    );
    return Container(
      color: Colores.papel,
      padding: const EdgeInsets.symmetric(horizontal: Aire.sm, vertical: 10),
      child: Row(
        children: [
          ControlSenalado(
            nombre: Senalado.pedidosMarcarTodos,
            child: Semantics(
              label: 'Elegir todos los de esta página',
              child: Checkbox(
                value: todosMarcados,
                onChanged: (v) => alMarcarPagina(v ?? false),
              ),
            ),
          ),
          if (columnas.factura)
            _celda(flex: 4, hijo: Text('Factura', style: estilo)),
          _celda(flex: 2, hijo: Text('Fecha factura', style: estilo)),
          if (columnas.sucursal)
            _celda(flex: 2, hijo: Text('Sucursal', style: estilo)),
          _celda(flex: 3, hijo: Text('Pedido', style: estilo)),
          _celda(flex: 5, hijo: Text('Cliente', style: estilo)),
          if (columnas.ruta) _celda(flex: 2, hijo: Text('Ruta', style: estilo)),
          if (columnas.articulos)
            _celda(flex: 2, hijo: Text('Artículos', style: estilo)),
          _celda(
            flex: 2,
            hijo: Text('Peso', style: estilo, textAlign: TextAlign.right),
          ),
          // PESO Y PRECIO SON NÚMEROS Y VAN A LA DERECHA, los dos, en la cabecera y en la fila (Jose,
          // 21/10/2026: «ten consistencia en las columnas, no uno para la izquierda y otro para la derecha»).
          _celda(
            flex: 2,
            hijo: Text('Domicilio', style: estilo, textAlign: TextAlign.right),
          ),
          if (columnas.entrega)
            _celda(flex: 2, hijo: Text('Entrega', style: estilo)),
          const SizedBox(width: 32),
        ],
      ),
    );
  }
}

Widget _celda({required int flex, required Widget hijo}) => Expanded(
  flex: flex,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: hijo,
  ),
);

class _Fila extends StatelessWidget {
  const _Fila({
    required this.pedido,
    required this.conduce,
    required this.columnas,
    required this.renglones,
    required this.estadoDeSuRuta,
    required this.codigoDeRuta,
    required this.marcado,
    required this.alMarcar,
    required this.alAbrir,
    required this.ahora,
    this.esLaPrimera = false,
  });

  /// SI ESTA ES LA PRIMERA DE LA PAGINA.
  ///
  /// Sólo para la Guia: hay una fila por pedido —cincuenta en una pagina— y el
  /// recorrido sólo puede senalar un control por nombre. Marcando la primera,
  /// senala una y no tiene que elegir
  /// (`pantallas/ayuda/vista/control_senalado.dart`).
  final bool esLaPrimera;

  final Pedido pedido;
  final ConduceDe? conduce;
  final ColumnasVisibles columnas;
  final List<RenglonConPeso> renglones;
  final String? estadoDeSuRuta;
  final String? codigoDeRuta;
  final bool marcado;
  final VoidCallback alMarcar;
  final VoidCallback alAbrir;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final reparto = estadoDeReparto(pedido, estadoDeSuRuta);
    // Lo que cuesta el domicilio de esta parada: el precio de Entrega si lo hay y, si no, lo que
    // cobró la propia factura. Antes sólo miraba Entrega y salía «sin cotizar» en todas las filas.
    final costo = conduce != null
        ? conduce!.domicilioUsd
        : costoDeLaParada(pedido.pedidoCosto, pedido.facturaDomicilio);

    return ControlSenalado(
      nombre: Senalado.pedidosAbrirElPedido,
      senalable: esLaPrimera,
      child: InkWell(
        // La fila entera abre el detalle; la casilla no lo abre.
        onTap: alAbrir,
        hoverColor: Colores.papel,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colores.linea)),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Aire.sm,
            vertical: 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ControlSenalado(
                nombre: Senalado.pedidosMarcarUno,
                senalable: esLaPrimera,
                child: Checkbox(value: marcado, onChanged: (_) => alMarcar()),
              ),
              // Flex 4: la celda lleva DOS marcas, el numero y el cobro del
              // domicilio, y con menos la segunda bajaba de linea (21/10/2026).
              if (columnas.factura)
                // A la izquierda: sin esto la insignia se estira a todo el ancho de la celda.
                _celda(
                  flex: 4,
                  hijo: Align(
                    alignment: Alignment.centerLeft,
                    child: _Factura(
                      pedido: pedido,
                      conCobro: false,
                      conduce: conduce,
                    ),
                  ),
                ),
              _celda(flex: 2, hijo: _Fecha(pedido: pedido)),
              if (columnas.sucursal)
                _celda(flex: 2, hijo: Text(pedido.sucursalCodigo ?? '—')),
              // DE QUÉ PEDIDO VIENE LA FACTURA (21/10/2026, Jose: «ya no son pedidos, son
              // facturas; el pedido es un extra»). La fila es la factura; esta celda dice si
              // viene de un pedido de PEDIDO y cuál (su folio, entero en el tooltip). Sin folio no
              // hay pedido (o este aparato aún no lo ha puesto al día): un guion. El estado del
              // pedido ya no se enseña aquí: con las facturas de Ventra como fuente nadie lo
              // actualiza, y un «En proceso» que no cambia nunca es un dato creíble y falso.
              _celda(
                flex: 3,
                hijo: pedido.folio == null
                    ? Tooltip(
                        message:
                            'Esta factura no viene de ningún pedido de PEDIDO.',
                        child: Text(
                          '—',
                          style: Tipos.texto(
                            tamano: 12.5,
                            color: Colores.tintaSuave,
                          ),
                        ),
                      )
                    : Tooltip(
                        message: 'Pedido de PEDIDO: ${pedido.folio}',
                        child: Text(
                          pedido.folio!,
                          key: ValueKey('fila-pedido-${pedido.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Tipos.mono(tamano: 12, color: Colores.tinta),
                        ),
                      ),
              ),
              // EL CLIENTE Y, DEBAJO, A DÓNDE SE LLEVA: era otra columna («Dirección») y dejaba
              // las dos truncadas a media palabra. El número de factura ya tiene su columna, así
              // que no se repite bajo el nombre (sólo baja aquí cuando esa columna se esconde).
              _celda(
                flex: 5,
                hijo: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pedido.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tipos.texto(
                        tamano: 14,
                        peso: FontWeight.w600,
                        color: Colores.tinta,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        pedido.endAddress ?? pedido.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tipos.texto(
                          tamano: 12.5,
                          color: Colores.tintaSuave,
                        ),
                      ),
                    ),
                    // UNA FACTURA SIN PEDIDO NO TRAE EL PUNTO DEL CLIENTE (21/10/2026, Jose): sin
                    // coordenadas no hay parada, y el logístico tiene que saber que la dirección
                    // se la pone él. Es el aviso; lo que lo arregla es «Ubicar la entrega».
                    if (pedido.endLat == null || pedido.endLng == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Sin ubicación: es obligatoria para ir en una ruta. Ponla en «Ubicar la entrega»',
                          key: ValueKey('fila-sin-ubicacion-${pedido.id}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Tipos.texto(
                            tamano: 11.5,
                            color: Colores.ambar,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (columnas.ruta)
                _celda(
                  flex: 2,
                  hijo: codigoDeRuta == null
                      ? const Text('—')
                      : Insignia(codigoDeRuta!, color: Colores.enCurso),
                ),
              if (columnas.articulos)
                _celda(flex: 3, hijo: _Articulos(renglones: renglones)),
              // El peso y el precio, en mono: son las dos columnas que se leen de
              // arriba abajo para decidir que cabe en el camion.
              _celda(
                flex: 2,
                hijo: Text(
                  kg(conduce?.pesoKg ?? pedido.weight),
                  textAlign: TextAlign.right,
                  style: Tipos.mono(tamano: 13, color: Colores.tinta),
                ),
              ),
              // El domicilio de la parada. Si la factura trae la línea de entrega pero con el precio en
              // $0, se dice aquí («sin precio»), en una sola línea: antes era una marca gris apilada en
              // la celda de la factura y partía la fila en dos.
              _celda(
                flex: 2,
                hijo: costo != null
                    ? Text(
                        usd(costo),
                        textAlign: TextAlign.right,
                        style: Tipos.mono(tamano: 13, color: Colores.tinta),
                      )
                    : Tooltip(
                        message:
                            'La factura trae la línea ENTREGA A DOMICILIO pero con el precio '
                            'en \$0: no se puso el precio. No impide ir a una ruta.',
                        child: Text(
                          'sin precio',
                          textAlign: TextAlign.right,
                          style: Tipos.mono(
                            tamano: 13,
                            color: Colores.tintaSuave,
                          ),
                        ),
                      ),
              ),
              if (columnas.entrega)
                _celda(
                  flex: 2,
                  hijo: Insignia(
                    reparto.etiqueta,
                    color: _colorDeReparto(reparto),
                  ),
                ),
              SizedBox(
                width: 32,
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colores.tintaSuave,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los colores de las dos insignias de estado. Sueltos aqui porque los pintan
/// **dos** sitios —la fila de la tabla y la tarjeta del telefono— y dos switch
/// copiados acaban con un verde en uno y un ambar en el otro.
Color _colorEnPedido(EstadoEnPedidoVisto estado) => switch (estado) {
  EstadoEnPedidoVisto.completada => Colores.verde,
  EstadoEnPedidoVisto.expirada => Colores.rojo,
  EstadoEnPedidoVisto.enProceso => Colores.ambar,
};

Color _colorDeReparto(EstadoReparto reparto) => switch (reparto) {
  EstadoReparto.entregado => Colores.verde,
  EstadoReparto.enRuta => Colores.enCurso,
  EstadoReparto.enDespacho => Colores.primario,
  EstadoReparto.devuelto || EstadoReparto.cancelado => Colores.ambar,
  EstadoReparto.sinEntregar => Colores.tintaSuave,
};

/// La cabecera cuando hay tarjetas: **solo el `elegir todos`**.
///
/// Los rotulos de columna no pintan nada encima de unas tarjetas —no hay
/// columnas debajo— pero la casilla de marcar la pagina entera si, que es como
/// se arma un pre-despacho de golpe y es el gesto que se perderia al cambiar de
/// forma.
class _CabeceraDeTarjetas extends StatelessWidget {
  const _CabeceraDeTarjetas({
    required this.cuantos,
    required this.todosMarcados,
    required this.alMarcarPagina,
  });

  final int cuantos;
  final bool todosMarcados;
  final void Function(bool) alMarcarPagina;

  @override
  Widget build(BuildContext context) => Container(
    color: Colores.papel,
    padding: const EdgeInsets.only(right: Aire.sm),
    child: Row(
      children: [
        ControlSenalado(
          nombre: Senalado.pedidosMarcarTodos,
          child: Semantics(
            label: 'Elegir todos los de esta página',
            child: Checkbox(
              value: todosMarcados,
              onChanged: (v) => alMarcarPagina(v ?? false),
            ),
          ),
        ),
        Expanded(
          child: Text(
            'Elegir los $cuantos de esta página',
            style: Tipos.texto(
              tamano: 12,
              peso: FontWeight.w600,
              color: Colores.tintaSuave,
            ),
          ),
        ),
      ],
    ),
  );
}

/// UN PEDIDO EN UN TELEFONO. Lo importante arriba y lo demas debajo.
///
/// Las reglas de aqui dentro, que son las que evitan el `C o m p l e t a d a`:
///
///  - todo lo que es de UNA linea lleva `maxLines: 1` con elipsis. Sin elipsis,
///    una direccion larga se corta a mitad de palabra contra el borde y no se
///    sabe si falta poco o mucho;
///  - la direccion lleva dos lineas, que es lo que hace falta para leer un
///    reparto, y elipsis en la segunda;
///  - las insignias y las cifras van en un `Wrap`, **nunca en `Expanded`**: un
///    `Expanded` reparte el ancho a partes y le puede tocar una celda de 39 px,
///    que es exactamente como se rompe una palabra letra a letra.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.pedido,
    required this.conduce,
    required this.estadoDeSuRuta,
    required this.codigoDeRuta,
    required this.marcado,
    required this.alMarcar,
    required this.alAbrir,
    required this.ahora,
    this.esLaPrimera = false,
    super.key,
  });

  /// SI ESTA ES LA PRIMERA DE LA PAGINA.
  ///
  /// Sólo para la Guia: hay una fila por pedido —cincuenta en una pagina— y el
  /// recorrido sólo puede senalar un control por nombre. Marcando la primera,
  /// senala una y no tiene que elegir
  /// (`pantallas/ayuda/vista/control_senalado.dart`).
  final bool esLaPrimera;

  final Pedido pedido;
  final ConduceDe? conduce;
  final String? estadoDeSuRuta;
  final String? codigoDeRuta;
  final bool marcado;
  final VoidCallback alMarcar;
  final VoidCallback alAbrir;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final reparto = estadoDeReparto(pedido, estadoDeSuRuta);
    final enPedido = estadoEnPedido(pedido, ahora: ahora);
    final folio = pedido.operationNumber ?? '';

    return ControlSenalado(
      nombre: Senalado.pedidosAbrirElPedido,
      senalable: esLaPrimera,
      child: InkWell(
        // La tarjeta entera abre el detalle; la casilla no lo abre.
        onTap: alAbrir,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colores.linea)),
          ),
          padding: const EdgeInsets.fromLTRB(0, Aire.sm, Aire.sm, Aire.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ControlSenalado(
                nombre: Senalado.pedidosMarcarUno,
                senalable: esLaPrimera,
                child: Checkbox(value: marcado, onChanged: (_) => alMarcar()),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    // EL NÚMERO DE FACTURA ES EL TÍTULO DE LA TARJETA — Amado, issue 8
                    // (14/10/2026: «los logísticos operan con número de factura») e
                    // issue 12 (15/10/2026: más importante que el cliente). El cliente
                    // va debajo, en negrita y al tamaño del cuerpo: `FacturaYCliente`.
                    FacturaYCliente(
                      facturaNumero: pedido.facturaNumero,
                      cliente: pedido.customerName,
                      facturadaEl: pedido.facturaAt,
                      claveDeLaFactura: ValueKey(
                        'tarjeta-factura-${pedido.id}',
                      ),
                      conduce: conduce?.etiqueta,
                    ),
                    const SizedBox(height: 2),
                    // Folio y fecha en la misma linea mientras quepan, y en dos
                    // cuando no: es un `Wrap`, asi que saltan enteros.
                    Wrap(
                      spacing: Aire.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (folio.isNotEmpty)
                          Text(
                            folio,
                            style: Tipos.mono(
                              tamano: 11.5,
                              color: Colores.tintaSuave,
                            ),
                          ),
                        _Fecha(pedido: pedido),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pedido.endAddress ?? pedido.address,
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
                        Text(
                          kg(conduce?.pesoKg ?? pedido.weight),
                          style: Tipos.mono(tamano: 13, color: Colores.tinta),
                        ),
                        Text(
                          usd(
                            conduce != null
                                ? conduce!.domicilioUsd
                                : pedido.pedidoCosto,
                          ),
                          style: Tipos.mono(
                            tamano: 13,
                            color:
                                (conduce != null
                                        ? conduce!.domicilioUsd
                                        : pedido.pedidoCosto) ==
                                    null
                                ? Colores.tintaSuave
                                : Colores.tinta,
                          ),
                        ),
                        Insignia(
                          enPedido.etiqueta,
                          color: _colorEnPedido(enPedido),
                          tooltip: pedido.archivado
                              ? 'Archivado en PEDIDO'
                              : null,
                        ),
                        Insignia(
                          reparto.etiqueta,
                          color: _colorDeReparto(reparto),
                        ),
                        if (codigoDeRuta != null)
                          Insignia(codigoDeRuta!, color: Colores.enCurso),
                        // Sin el número: ya está arriba, con su rótulo. La insignia
                        // se queda con lo que SÓLO ella dice, que es el estado
                        // (verde cuadra, ámbar cambió) y la marca del domicilio.
                        _Factura(
                          pedido: pedido,
                          conNumero: false,
                          conduce: conduce,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colores.tintaSuave,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fecha extends StatelessWidget {
  const _Fecha({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    // La columna se llama «Fecha factura»: con número de factura, el día de la FACTURA en hora de Cuba.
    if (diaDeLaFacturaEnCuba(pedido.facturaAt) case final dia?
        when NumeroDeFactura.de(pedido.facturaNumero) != null) {
      return Text(
        dia,
        key: ValueKey('fila-fecha-factura-${pedido.id}'),
        style: Tipos.mono(tamano: 12.5, color: Colores.tinta),
      );
    }
    final propia = pedido.orderDate;
    if (propia != null) {
      return Text(
        fechaCorta(propia),
        style: Tipos.mono(tamano: 12.5, color: Colores.tinta),
      );
    }
    // Sin `orderDate` se pinta la del espejo con un `≈`: decirlo a medias es
    // peor que decirlo, porque el dia del pedido es con lo que se cuadra.
    return Tooltip(
      message:
          'Factura copiada antes de que se guardara su fecha: '
          'ésta es la del espejo.',
      child: Text(
        '≈ ${fechaCorta(pedido.createdAt)}',
        style: Tipos.mono(tamano: 12.5, color: Colores.tintaSuave),
      ),
    );
  }
}

class _Articulos extends StatelessWidget {
  const _Articulos({required this.renglones});

  final List<RenglonConPeso> renglones;

  @override
  Widget build(BuildContext context) {
    if (renglones.isEmpty) return const Text('—');
    final primero = renglones.first;
    final resto = renglones.length - 1;
    return Tooltip(
      message: [
        for (final r in renglones)
          '${r.renglon.description} ×${cantidad(r.empaques)}',
      ].join('\n'),
      child: Text(
        '${primero.renglon.description} ×${cantidad(primero.empaques)}'
        '${resto > 0 ? '  +$resto' : ''}',
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Factura extends StatelessWidget {
  const _Factura({
    required this.pedido,
    this.conNumero = true,
    this.conCobro = true,
    this.conduce,
  });

  final Pedido pedido;

  /// Si la fila es la principal de un conduce, la insignia dice «Conduce 47313 + 47314».
  final ConduceDe? conduce;

  /// Si la celda lleva, además del número, la marca del domicilio (la tarjeta del teléfono). La TABLA no:
  /// el domicilio tiene su columna («Precio») y dos marcas apiladas en una celda estrecha partían la fila
  /// en dos líneas (Jose, 21/10/2026: «la primera fila se baja sus datos una encima de otro»).
  final bool conCobro;

  Widget _conMarca(Widget numero) =>
      conCobro ? _ConCobro(pedido: pedido, numero: numero) : numero;

  /// Si la insignia lleva el número (la tabla) o sólo el estado (la tarjeta del teléfono,
  /// donde el número ya sale en la cabecera con su rótulo «Factura»).
  final bool conNumero;

  @override
  Widget build(BuildContext context) {
    // El MISMO texto que la tarjeta, la ficha, el tablero y los reportes (`NumeroDeFactura`):
    // crudo, la comilla de Excel de una factura que bajó antes del arreglo se veía aquí
    // y en ningún otro sitio.
    final numero =
        conduce?.etiqueta ?? NumeroDeFactura.de(pedido.facturaNumero) ?? '—';
    switch (pedido.facturaEstado) {
      case EstadoFactura.igual:
        return _conMarca(
          Insignia(
            conNumero ? numero : 'Cuadra',
            color: Colores.verde,
            tooltip: 'Cuadra con lo pedido: se puede repartir tal cual.',
          ),
        );
      case EstadoFactura.cambiado:
        return _conMarca(
          Insignia(
            conNumero ? '$numero !' : 'Cambió !',
            color: Colores.ambar,
            // Ya no dice «no puede ir en una ruta» (issue 10 de Amado, 15/10/2026):
            // `cambiado` entra y al camión sube lo facturado.
            tooltip:
                'Se facturó algo distinto de lo pedido: al camión va lo '
                'facturado.',
          ),
        );
      case EstadoFactura.sinFactura:
        return Text(
          'sin facturar',
          style: Tipos.texto(tamano: 12.5, color: Colores.tintaSuave),
        );
      default:
        // NULL no es `sin_factura`: es que el cotejo no ha pasado por aqui.
        return Tooltip(
          message:
              'El cotejo contra Ventra no ha pasado por esta factura todavía.',
          child: Text(
            'sin cotejar',
            style: Tipos.texto(tamano: 12.5, color: Colores.tintaSuave),
          ),
        );
    }
  }
}

/// EL NUMERO DE FACTURA Y, DEBAJO O AL LADO, SI EL DOMICILIO ESTA COBRADO.
///
/// Amado, 08/10/2026: «en la tabla no está claro qué pedidos han sido facturados
/// y cobrados». Un pedido con la factura cotejada puede NO traer la linea
/// «ENTREGA A DOMICILIO» (`factura_domicilio` nulo, tambien en PEDIDO), y la
/// regla del 07/10 no lo deja entrar en una ruta ni en una zona del tablero:
/// «No se puede asociar al tablero: la factura no tiene un cobro de domicilio
/// registrado». El rechazo era correcto pero la causa no se veia en ninguna
/// parte; ahora se ve aqui, ANTES de marcar el pedido.
///
/// **El ambar sale solo si ESE es lo que frena al pedido**
/// ([frenaElDomicilioSinCobrar], que pregunta a la misma pieza que el arrastre
/// y no repite la regla). Un entregado, uno que ya va en una ruta o uno
/// archivado no tienen nada que colocar, y decirles «no puede ir a una ruta» es
/// falso: un aviso que sale siempre deja de leerse. Esos llevan solo el numero,
/// o el verde si la factura SI cobro (el importe es un dato, no la regla).
///
/// Es un `Wrap` y no una `Column` para que lo mismo valga en la celda de la
/// tabla y dentro del `Wrap` de la tarjeta del telefono: si no cabe al lado, baja
/// entero. Solo se pinta con factura `igual` o `cambiado`; `sin facturar` y
/// `sin cotejar` ya lo dicen todo.
class _ConCobro extends StatelessWidget {
  const _ConCobro({required this.numero, required this.pedido});

  final Widget numero;
  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final importe = pedido.facturaDomicilio;
    final Widget? marca;
    if (domicilioSinCobroSenalado(pedido)) {
      marca = Insignia(
        'Domicilio sin precio puesto',
        color: Colores.gris,
        tooltip:
            'La factura trae la línea ENTREGA A DOMICILIO pero con el precio '
            'en \$0: no se puso el precio. No impide ir a una ruta.',
      );
    } else if (importe != null && importe > 0) {
      marca = Insignia(
        'Dom. ${usd(importe)}',
        color: Colores.verde,
        tooltip:
            'La factura trae la línea ENTREGA A DOMICILIO: '
            'el domicilio está cobrado.',
      );
    } else {
      marca = null;
    }
    if (marca == null) return numero;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [numero, marca],
    );
  }
}
