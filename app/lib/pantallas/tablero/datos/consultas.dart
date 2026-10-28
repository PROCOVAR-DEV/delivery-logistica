import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../../../nucleo/almacenes/almacen_de_referencia.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/conduce.dart';
import '../../../nucleo/fecha_de_la_factura.dart';
import '../../../nucleo/regla_de_entrada.dart';
import '../../../nucleo/registro/registro.dart';
import 'esquema.dart';
import 'geo.dart';
import 'modelos.dart';
import 'punto_de_salida.dart';

/// Los filtros de la mitad izquierda (§3 «Filtros de la mitad izquierda»).
class FiltrosSinColocar {
  const FiltrosSinColocar({
    this.desde,
    this.hasta,
    this.q,
    this.municipio,
    this.vendedores = const [],
    this.kmMax,
    this.conCobroDeDomicilio,
    this.limite = 200,
  });

  /// La fecha DEL PEDIDO (no la de la factura, que es la del orden), de [desde]
  /// a [hasta], los dos dias incluidos y cada uno opcional. Era UN dia hasta el
  /// 15/10/2026; Amado pidio el rango (issue 13): `nucleo/fecha_de_la_factura.dart`.
  final DateTime? desde;
  final DateTime? hasta;

  /// La misma caja de la lista de pedidos: cliente, operacion, direccion,
  /// municipio, vendedor y el CONTENIDO DE LOS RENGLONES — «¿que pedidos llevan
  /// malta?». Quien la usa no se para a pensar en que campo esta lo que
  /// recuerda.
  final String? q;
  final String? municipio;

  /// UNO O VARIOS vendedores (issue 18 de Amado, 16/10/2026: «pueden haber pocos
  /// domicilios y se combinan los de ambos»): salen los pedidos de CUALQUIERA de
  /// ellos. Vacía = todos.
  final List<String> vendedores;

  /// El corte por kilometros.
  final double? kmMax;

  /// SI EL PEDIDO LLEVA COBRO DE DOMICILIO PUESTO. `null` = los dos.
  ///
  /// El costo lo pone el repartidor desde Entrega, y es lo que decide si un
  /// pedido se puede meter en una ruta: sin el no se sabe lo que cuesta
  /// llevarlo. Quien arma el dia necesita las dos preguntas:
  ///
  ///  * `true` — «ensename lo que YA puedo repartir».
  ///  * `false` — «ensename lo que esta esperando a que le pongan el costo»,
  ///    que es una lista de trabajo para otra persona, no para el.
  ///
  /// Pedido por Jose el 16/09/2026: «falta el filtro de el tablero falto poner
  /// los pedidos con cobro de domicilio».
  final bool? conCobroDeDomicilio;

  /// El tope de lo que se pinta. `total` dice cuantos hay de verdad.
  ///
  /// No es un limite de lo que se puede ver: es cuanto se pinta de una vez, para
  /// no meter dos mil tarjetas en una lista de golpe. Lo que faltaba era el gesto
  /// de pedir la siguiente tanda, y sin el los mas lejanos al almacen —que son
  /// los ultimos de la lista, porque va por cercania— no habia forma de verlos.
  final int limite;

  /// Cuanto sube el tope cada vez que alguien pide ver mas.
  ///
  /// El mismo numero que el tope inicial: es lo que ya se sabe que la pantalla
  /// aguanta pintando de una vez.
  static const tanda = 200;

  FiltrosSinColocar copiaCon({
    DateTime? desde,
    DateTime? hasta,
    String? q,
    String? municipio,
    List<String>? vendedores,
    double? kmMax,
    bool? conCobroDeDomicilio,
    int? limite,
    bool quitarDesde = false,
    bool quitarHasta = false,
    bool quitarMunicipio = false,
    bool quitarKmMax = false,
    bool quitarCobroDeDomicilio = false,
  }) => FiltrosSinColocar(
    desde: quitarDesde ? null : (desde ?? this.desde),
    hasta: quitarHasta ? null : (hasta ?? this.hasta),
    q: q ?? this.q,
    municipio: quitarMunicipio ? null : (municipio ?? this.municipio),
    vendedores: vendedores ?? this.vendedores,
    kmMax: quitarKmMax ? null : (kmMax ?? this.kmMax),
    conCobroDeDomicilio: quitarCobroDeDomicilio
        ? null
        : (conCobroDeDomicilio ?? this.conCobroDeDomicilio),
    limite: limite ?? this.limite,
  );

  bool get hayAlguno =>
      desde != null ||
      hasta != null ||
      (q != null && q!.trim().isNotEmpty) ||
      municipio != null ||
      vendedores.isNotEmpty ||
      kmMax != null ||
      conCobroDeDomicilio != null;
}

/// LAS LECTURAS DEL TABLERO, todas contra la base local.
///
/// Todas: con red y sin ella. La pantalla no mira nunca la respuesta de una
/// peticion —eso lo hace el servicio, que escribe aqui— y asi lo que se ve por
/// la tarde en el patio es exactamente lo mismo que se veia por la manana.
class ConsultasTablero {
  ConsultasTablero(this._base);

  final BaseLocal _base;

  Future<void> _listo() => EsquemaTablero.asegurar(_base);

  /// El nombre de la sucursal, para poder decir «Santiago no tiene ningun
  /// almacen con coordenadas» en vez de un uuid.
  Future<String> nombreDeSucursal(String sucursalId) async {
    final fila = await (_base.select(
      _base.branches,
    )..where((b) => b.id.equals(sucursalId))).getSingleOrNull();
    return fila?.name ?? 'Esta sucursal';
  }

  /// DE DONDE SE MIDE LA CERCANIA.
  ///
  /// La regla entera —que condiciones tiene que cumplir un almacen y cual se
  /// elige— vive en [AlmacenDeReferencia], **y no aqui**: la comparten el paso a
  /// paso del Panel y la ficha de Clientes, que hacen la misma pregunta sobre el
  /// mismo dato. Tenerla escrita tres veces es como llegamos al 22/09/2026 con
  /// tres pantallas contestando cosas distintas de la misma sucursal
  /// (`CLAUDE.md` §3-bis).
  ///
  /// Sale de `warehouses`, que es lo que bajo por la manana: asi el orden por
  /// cercania no depende de preguntarle a nadie.
  ///
  /// Lanza [SinAlmacenConCoordenadas], y en DOS formas que no son la misma:
  /// «no tiene» —se miro y no hay— y «todavia no ha bajado» —no se pudo mirar—.
  /// La segunda no acusa a nadie de un hueco que no tiene.
  ///
  /// ## Y SE PUEDE ELEGIR OTRO A MANO — 26/09/2026
  ///
  /// [preferido] es el almacen que el logistico ha elegido en la cabecera del
  /// tablero. Manda sobre la eleccion automatica, **pero solo si sirve para
  /// medir**: un preferido guardado que se haya quedado sin coordenadas —o que
  /// Accesos haya dado de baja— se ignora y se vuelve al de siempre, porque la
  /// alternativa es medir desde un punto que no existe y cobrar el domicilio con
  /// esos kilometros.
  ///
  /// La pantalla ya no deja elegir uno que no sirva, asi que llegar aqui con un
  /// preferido invalido significa que el dato cambio DESPUES de elegirlo. No se
  /// calla: se deja dicho en el registro, porque de otro modo los kilometros
  /// cambian solos y nadie sabe por que.
  ///
  /// ## Y SI NO ES EL DE POR DEFECTO, SUS PEDIDOS VAN PRIMERO — 15/10/2026
  ///
  /// Jose: elegido arriba otro almacén, «Sin colocar» enseña primero los pedidos
  /// que salen de él, del más cercano al más lejano, y luego los demás por fecha.
  /// Lo marca [AlmacenOrigen.primeroLosDe] con su código. Volver a elegir el de por
  /// defecto es volver al orden de siempre (la cabecera no tiene «ninguno»), y un
  /// almacén sin código no tiene pedidos suyos. La misma regla que el servidor
  /// (`almacenDeLaCabecera`), atada por `docs/orden-sin-colocar.casos.json`.
  Future<AlmacenOrigen> almacenDe(
    String sucursalId, {
    String? preferido,
  }) async {
    final sucursal = await (_base.select(
      _base.branches,
    )..where((b) => b.id.equals(sucursalId))).getSingleOrNull();

    // `warehouses` guarda la sucursal por CODIGO (`STG`), no por id: viene de
    // Accesos, que es otra base. Si la sucursal no tiene codigo no se adivina
    // nada — se queda sin tablero, que es lo honesto.
    final codigo = sucursal?.externalId;
    if (preferido != null && preferido.isNotEmpty) {
      final filas = await _almacenesCrudos(codigo);
      final elegidoAMano = filas.firstWhereOrNull((a) => a.id == preferido);
      // `elegir` sobre una lista de uno: asi las condiciones de «sirve para
      // medir» se preguntan en UN solo sitio, el mismo que decide cuando nadie
      // ha elegido nada. Escribirlas aqui otra vez es como llegamos al
      // 22/09/2026 con tres pantallas contestando cosas distintas.
      final sirve = elegidoAMano == null
          ? null
          : AlmacenDeReferencia.elegir([elegidoAMano]);
      if (sirve != null) {
        return AlmacenOrigen(
          id: sirve.id,
          nombre: sirve.nombre,
          lat: sirve.lat!,
          lng: sirve.lng!,
          // Un código vacío no casa con nada: lo descarta `_codigoDeAlmacen`.
          primeroLosDe: AlmacenDeReferencia.elegir(filas)?.id == sirve.id
              ? null
              : sirve.codigo,
        );
      }
      Registro.aviso(
        'el almacén elegido a mano ($preferido) ya no sirve para medir: se '
        'vuelve al de siempre. Los kilómetros del tablero van a cambiar.',
      );
    }
    final elegido = await AlmacenDeReferencia.de(_base, codigo);
    if (elegido == null) {
      final nombre = await nombreDeSucursal(sucursalId);
      if (await _noHayConQueAfirmarlo(codigo)) {
        throw SinAlmacenConCoordenadas.todaviaNoHaBajado(nombre);
      }
      throw SinAlmacenConCoordenadas(nombre);
    }
    return AlmacenOrigen(
      id: elegido.id,
      nombre: elegido.nombre,
      lat: elegido.lat!,
      lng: elegido.lng!,
    );
  }

  /// TODOS LOS ALMACENES DE LA SUCURSAL, para poder elegir desde cuál se mide.
  ///
  /// **Sin filtrar por coordenadas a propósito.** Los que no las tienen salen
  /// igual, marcados y sin poder elegirse: el porqué entero está en
  /// [AlmacenDeLaSucursal]. En dos líneas: seis de los catorce almacenes de
  /// verdad están hoy sin ubicación porque la ponen los logísticos de cada
  /// sucursal, y esconderlos es descartar en silencio (`CLAUDE.md` §4).
  ///
  /// Lo que SÍ se filtra es `activo`: un almacén que Accesos dio de baja no es
  /// uno al que le falte un paso, es uno que ya no está. Enseñarlo en la lista
  /// invitaría a elegir algo que no existe, y no hay nada que el logístico pueda
  /// hacer con él.
  ///
  /// El orden es el mismo que usa la elección automática —`principal` primero y
  /// luego el nombre—, para que la lista se lea en el orden en que se decide.
  Future<List<AlmacenDeLaSucursal>> almacenesDeLaSucursal(
    String sucursalId,
  ) async {
    final sucursal = await (_base.select(
      _base.branches,
    )..where((b) => b.id.equals(sucursalId))).getSingleOrNull();
    final filas = await _almacenesCrudos(sucursal?.externalId);
    return [
      for (final a in filas)
        if (a.activo)
          AlmacenDeLaSucursal(
            id: a.id,
            nombre: a.nombre,
            principal: a.principal,
            // La pregunta se le hace a quien la sabe: una lista de uno contra
            // la misma regla que elige el de siempre.
            sirveParaMedir: AlmacenDeReferencia.elegir([a]) != null,
          ),
    ];
  }

  /// DE DÓNDE SALE CADA ZONA de [sucursalId], con una sola lectura de sus
  /// almacenes. La regla es [puntoDeSalida], la misma que la del servidor.
  Future<({AlmacenOrigen? sale, String? no}) Function(String? almacenId)>
  puntosDe(String sucursalId) async {
    final sucursal = await (_base.select(
      _base.branches,
    )..where((b) => b.id.equals(sucursalId))).getSingleOrNull();
    final almacenes = await _almacenesCrudos(sucursal?.externalId);
    final nombre = sucursal?.name ?? 'Esta sucursal';
    return (String? almacenId) {
      final r = puntoDeSalida(
        almacenId: almacenId,
        deLaSucursal: almacenes,
        sucursal: nombre,
      );
      final a = r.sale;
      return (
        sale: a == null
            ? null
            : AlmacenOrigen(
                id: a.id,
                nombre: a.nombre,
                lat: a.lat!,
                lng: a.lng!,
              ),
        no: r.no,
      );
    };
  }

  /// Las filas de `warehouses` de esa sucursal, tal cual y ya ordenadas.
  Future<List<Almacen>> _almacenesCrudos(String? codigo) async {
    if (codigo == null || codigo.isEmpty) return const <Almacen>[];
    return (_base.select(_base.warehouses)
          ..where((w) => w.sucursalCodigo.equals(codigo))
          // `principal` primero: en SQLite es 1/0, así que descendente.
          ..orderBy([
            (w) => OrderingTerm.desc(w.principal),
            (w) => OrderingTerm.asc(w.nombre),
          ]))
        .get();
  }

  /// ¿SE PUEDE AFIRMAR que esta sucursal no tiene almacén? `true` = NO se puede.
  ///
  /// Decir «Camagüey no tiene ningún almacén con coordenadas» manda a alguien a
  /// dar de alta lo que ya existe, y deja el Tablero en blanco mientras tanto.
  /// Eso sólo se dice con la copia delante, nunca a medio rehacer.
  ///
  /// LA GUARDA DE ANTES ERA DEMASIADO FLOJA y por eso salía el mensaje falso.
  /// Pedía que la tabla estuviese vacía **y** que los almacenes no hubiesen
  /// bajado nunca. Pero `bajadaAt` se pone la primera vez y ya no se quita:
  /// pasado ese momento, cualquier instante con la tabla vacía caía en la rama
  /// que acusa. Y la tabla se vaciaba en cada ciclo —o sea, en cada cambio de
  /// sucursal— porque la bajada borraba antes de rellenar. Jose, 25/09/2026:
  /// «me sale ahora en tablero q santiago no tiene ninguna sucursal activa por
  /// q razon me sale eso». Reproducido en la web con Granma, Holguín y
  /// Camagüey, y contrastado contra Accesos: las tres lo tienen.
  ///
  /// Son tres cosas distintas y ninguna es culpa de la sucursal:
  ///
  ///  1. **Sin código no se ha podido ni preguntar.** `warehouses` guarda la
  ///     sucursal por código (`STG`) y el código vive en `branches`. Una
  ///     sucursal cuya fila todavía no ha llegado entera no se puede juzgar.
  ///  2. **La tabla está vacía del todo.** Ocho sucursales no pierden su
  ///     almacén a la vez: una tabla vacía es una copia rehaciéndose —o una que
  ///     no ha llegado todavía—, jamás un hecho sobre una sucursal. Esto es lo
  ///     que faltaba, y cubre también el «no ha bajado nunca» sin preguntar por
  ///     la marca de frescura: sin bajada no hay filas.
  ///
  /// Lo que SÍ se afirma, y se sigue afirmando: hay almacenes de otras
  /// sucursales y de ésta no hay ninguno que sirva. Eso es un hueco de verdad
  /// —le pasa a Moa y a Palma Soriano— y hay que decirlo.
  Future<bool> _noHayConQueAfirmarlo(String? codigo) async {
    if (codigo == null || codigo.isEmpty) return true;
    final alguno =
        await (_base.selectOnly(_base.warehouses)
              ..addColumns([_base.warehouses.id])
              ..limit(1))
            .get();
    // Con una fila delante —de la sucursal que sea— la copia está, y entonces
    // sí se puede afirmar. Sin ninguna, no.
    return alguno.isEmpty;
  }

  /// Las columnas con sus totales. Los totales salen de la BASE y no de sumar
  /// las tarjetas pintadas (§3).
  ///
  /// **Sólo las ACTIVAS**, salvo con [inactivas]: una zona inactiva no sale en el
  /// tablero, ni al colocar, ni al armar (issue 15 de Amado). Todo el que quiera
  /// «las zonas» pasa por aquí, y por eso el filtro vive aquí y en ningún otro sitio.
  Future<List<ColumnaTablero>> columnas(
    String sucursalId, {
    bool inactivas = false,
  }) async {
    await _listo();
    final filas = await _base
        .customSelect(
          '''
SELECT c.id, c.branch_id, c.nombre, c.posicion, c.vehicle_id, c.almacen_id,
       v.name     AS vehiculo_nombre,
       v.plate    AS vehiculo_matricula,
       v.capacity AS vehiculo_capacidad,
       -- Los MIEMBROS de un conduce no son tarjetas (`nucleo/conduce.dart`): no se cuentan.
       (SELECT count(*) FROM ${EsquemaTablero.colocaciones} p
         WHERE p.column_id = c.id
           AND NOT EXISTS (SELECT 1 FROM orders o
                            WHERE o.id = p.order_id
                              AND o.conduce_principal_id IS NOT NULL)) AS pedidos,
       -- Las que arriba SI estan puestas y este aparato no puede guardar por no
       -- tener el pedido. No suman a `pedidos` (no hay tarjeta que pintar) pero
       -- borrar la zona las cuenta, igual que el servidor.
       (SELECT count(*) FROM ${EsquemaTablero.sinPedido} s
         WHERE s.column_id = c.id
           AND NOT EXISTS (SELECT 1 FROM ${EsquemaTablero.colocaciones} p
                            WHERE p.order_id = s.order_id)) AS sin_pedido,
       -- El peso y el costo de la zona suman TODAS las filas de cada conduce: la principal puesta
       -- y sus miembros (`orders.conduce_principal_id` apunta a ella).
       (SELECT coalesce(sum(o.weight), 0) FROM orders o
         WHERE o.id IN (SELECT p.order_id FROM ${EsquemaTablero.colocaciones} p
                         WHERE p.column_id = c.id)
            OR o.conduce_principal_id IN (SELECT p.order_id FROM ${EsquemaTablero.colocaciones} p
                                           WHERE p.column_id = c.id)) AS peso_kg,
       (SELECT coalesce(sum(${costoDeLaParadaSql('o.')}), 0) FROM orders o
         WHERE o.id IN (SELECT p.order_id FROM ${EsquemaTablero.colocaciones} p
                         WHERE p.column_id = c.id)
            OR o.conduce_principal_id IN (SELECT p.order_id FROM ${EsquemaTablero.colocaciones} p
                                           WHERE p.column_id = c.id)) AS costo_usd,
       -- «SIN SUBIR» SALE DE LA COLA, no del id.
       --
       -- Antes se leia del prefijo `local-…`, y eso dejo de valer el 16/09/2026:
       -- ahora el aparato pone el id definitivo (un UUIDv7) al crear la zona,
       -- este o no este arriba. El id ya no dice nada de si subio.
       --
       -- Lo que de verdad lo dice es si le queda algun apunte por resolver. Y de
       -- paso arregla lo que el prefijo nunca supo contar: una zona que subio y
       -- que despues se renombro sin senal tambien esta «sin subir», y con el id
       -- de verdad puesto el prefijo la daba por entregada.
       --
       -- Se mira en los TRES sitios donde puede aparecer el id de la zona, y los
       -- tres hacen falta: `provisional` la ata a su creacion, `ruta` a lo que se
       -- hace sobre ella —renombrar, borrar, armar su ruta— y `cuerpo` a las
       -- COLOCACIONES, que la nombran ahi dentro y en ningun otro sitio. Sin el
       -- cuerpo, una zona ya subida con cinco pedidos todavia en la cola se
       -- pintaria como entregada.
       EXISTS (SELECT 1 FROM apuntes a
                WHERE (a.provisional = c.id
                       OR a.ruta LIKE '%' || c.id || '%'
                       OR a.cuerpo LIKE '%' || c.id || '%')
                  AND a.estado = 'pendiente') AS sin_subir,
       EXISTS (SELECT 1 FROM apuntes a
                WHERE (a.provisional = c.id
                       OR a.ruta LIKE '%' || c.id || '%'
                       OR a.cuerpo LIKE '%' || c.id || '%')
                  AND a.estado = 'rechazado') AS rechazada
FROM ${EsquemaTablero.columnas} c
LEFT JOIN vehicles v ON v.id = c.vehicle_id
WHERE c.branch_id = ?1 AND c.activa = ?2
ORDER BY c.posicion ASC, c.created_at ASC''',
          variables: [
            Variable<String>(sucursalId),
            Variable<int>(inactivas ? 0 : 1),
          ],
        )
        .get();

    final puntoDe = await puntosDe(sucursalId);
    return filas
        .map((f) {
          final almacenId = f.readNullable<String>('almacen_id');
          final punto = puntoDe(almacenId);
          return ColumnaTablero(
            id: f.read<String>('id'),
            branchId: f.read<String>('branch_id'),
            nombre: f.read<String>('nombre'),
            posicion: f.read<int>('posicion'),
            almacenId: almacenId,
            sale: punto.sale,
            noPuedeSalir: punto.no,
            vehiculoId: f.readNullable<String>('vehicle_id'),
            vehiculoNombre: f.readNullable<String>('vehiculo_nombre'),
            vehiculoMatricula: f.readNullable<String>('vehiculo_matricula'),
            vehiculoCapacidad: f.readNullable<double>('vehiculo_capacidad'),
            pedidos: f.read<int>('pedidos'),
            sinPedido: f.read<int>('sin_pedido'),
            activa: !inactivas,
            pesoKg: f.read<double>('peso_kg'),
            costoUsd: f.read<double>('costo_usd'),
            sinSubir: f.read<bool>('sin_subir'),
            rechazada: f.read<bool>('rechazada'),
          );
        })
        .toList(growable: false);
  }

  /// TODO lo que esta puesto, se pueda repartir o no.
  ///
  /// Este `WHERE` **no lleva** las condiciones de «repartible» a proposito: la
  /// tarjeta que dejo de servir se marca, no se esconde. Por eso se leen
  /// `factura_estado`, `archivado`, `route_id` y `resultado` crudos (§7.2), mas
  /// `factura_domicilio` y `delivered_at`, que `armarRuta` necesita para decidir
  /// con la misma regla que el servidor (`TarjetaPedido.motivoDeNoSubir`).
  Future<List<TarjetaColocada>> colocados(
    String sucursalId,
    AlmacenOrigen origen,
  ) async {
    await _listo();
    final filas = await _base
        .customSelect(
          '''
SELECT p.order_id, p.column_id, p.posicion, p.colocado_at, c.almacen_id,
       o.operation_number, o.customer_name, o.customer_phone, o.address,
       o.end_address, o.end_lat, o.end_lng, o.weight, o.pedido_costo,
       o.municipio, o.vendedor, o.order_date, o.factura_estado, o.archivado,
       o.factura_numero, o.factura_at, o.requiere_domicilio,
       o.route_id, o.resultado, o.factura_domicilio, o.delivered_at
FROM ${EsquemaTablero.colocaciones} p
JOIN ${EsquemaTablero.columnas} c ON c.id = p.column_id
JOIN orders o ON o.id = p.order_id
WHERE c.branch_id = ?1 AND $noEsMiembroSql
ORDER BY c.posicion ASC, p.posicion ASC''',
          variables: [Variable<String>(sucursalId)],
        )
        .get();

    final conduces = await conducesDeUnaVez(_base, [
      for (final f in filas) f.read<String>('order_id'),
    ]);
    final repes = <String, int>{};
    for (final f in filas) {
      final clave = f.read<String>('customer_name').trim().toLowerCase();
      repes[clave] = (repes[clave] ?? 0) + 1;
    }

    // LOS KM DE LO PUESTO, DESDE EL PUNTO DE SU ZONA si sirve; si no, desde
    // [origen] (el de arriba). Igual que `kmAlAlmacen` de `GET /api/board`: si
    // no, el «desde X» de la zona y los km de sus tarjetas no casan.
    final puntoDe = await puntosDe(sucursalId);
    return filas
        .map((f) {
          final nombre = f.read<String>('customer_name');
          final desde =
              puntoDe(f.readNullable<String>('almacen_id')).sale ?? origen;
          return TarjetaColocada(
            columnaId: f.read<String>('column_id'),
            posicion: f.read<int>('posicion'),
            colocadoAt: f.readNullable<DateTime>('colocado_at'),
            pedido: TarjetaPedido(
              pedidoId: f.read<String>('order_id'),
              operationNumber: f.readNullable<String>('operation_number'),
              customerName: nombre,
              customerPhone: f.readNullable<String>('customer_phone'),
              address:
                  f.readNullable<String>('end_address') ??
                  f.read<String>('address'),
              weight:
                  conduces[f.read<String>('order_id')]?.pesoKg ??
                  f.read<double>('weight'),
              conduce: conduces[f.read<String>('order_id')],
              pedidoCosto: f.readNullable<double>('pedido_costo'),
              municipio: f.readNullable<String>('municipio'),
              vendedor: f.readNullable<String>('vendedor'),
              orderDate: f.readNullable<DateTime>('order_date'),
              facturaEstado: f.readNullable<String>('factura_estado'),
              facturaNumero: f.readNullable<String>('factura_numero'),
              facturaAt: f.readNullable<DateTime>('factura_at'),
              facturaDomicilio: f.readNullable<double>('factura_domicilio'),
              requiereDomicilio: f.readNullable<bool>('requiere_domicilio'),
              archivado: f.read<int>('archivado') != 0,
              rutaId: f.readNullable<String>('route_id'),
              resultado: f.readNullable<String>('resultado'),
              deliveredAt: f.readNullable<DateTime>('delivered_at'),
              kmAlAlmacen: _km(
                desde,
                f.readNullable<double>('end_lat'),
                f.readNullable<double>('end_lng'),
              ),
              mismoCliente: repes[nombre.trim().toLowerCase()] ?? 1,
            ),
          );
        })
        .toList(growable: false);
  }

  /// Los tres contadores de arriba, contados en la base y no sobre lo pintado.
  Future<AvisosTablero> avisos(String sucursalId) async {
    await _listo();
    final fila = await _base
        .customSelect(
          '''
SELECT
  coalesce(sum(CASE WHEN o.archivado <> 0 THEN 1 ELSE 0 END), 0) AS archivados,
  coalesce(sum(CASE WHEN o.route_id IS NOT NULL THEN 1 ELSE 0 END), 0) AS en_otra_ruta,
  coalesce(sum(CASE WHEN o.factura_estado IS NULL
                      OR o.factura_estado = 'sin_factura' THEN 1 ELSE 0 END), 0) AS sin_factura,
  coalesce(sum(CASE WHEN o.factura_estado = 'cambiado' THEN 1 ELSE 0 END), 0) AS cambiados,
  count(*) AS colocados
FROM ${EsquemaTablero.colocaciones} p
JOIN ${EsquemaTablero.columnas} c ON c.id = p.column_id
JOIN orders o ON o.id = p.order_id
WHERE c.branch_id = ?1 AND $noEsMiembroSql''',
          variables: [Variable<String>(sucursalId)],
        )
        .getSingle();
    return AvisosTablero(
      archivados: fila.read<int>('archivados'),
      enOtraRuta: fila.read<int>('en_otra_ruta'),
      sinFactura: fila.read<int>('sin_factura'),
      cambiados: fila.read<int>('cambiados'),
      colocados: fila.read<int>('colocados'),
    );
  }

  /// LOS PEDIDOS SIN COLOCAR, DEL MAS VIEJO AL MAS RECIENTE POR LA FECHA DE SU
  /// FACTURA — 14/10/2026.
  ///
  /// Amado, issue 6, punto 2: «la lista de facturas (pedidos) debe salir
  /// ordenada cronologicamente de lo mas viejo a lo mas reciente». La fecha es
  /// `facturaAt` y, si el pedido no la trae, `orderDate`; sin ninguna de las
  /// dos va AL FINAL (un pedido sin fecha no es «el mas viejo»); y el desempate
  /// es el id, que es lo que impide que las tarjetas bailen entre dos lecturas
  /// delante de quien las esta arrastrando. Es el MISMO orden que el servidor
  /// (`ListarPedidosSinColocar`, `coalesce(factura_at, order_date) ASC NULLS
  /// LAST, id ASC`).
  ///
  /// HASTA ESE DIA IBA POR CERCANIA AL ALMACEN, y era deliberado: es como se
  /// decide que se reparte hoy cuando no cabe todo —lo que esta cerca sale igual,
  /// porque cuesta poco; lo que esta lejos espera al dia en que haya suficiente
  /// para ese lado—. **Lo que se pierde:** ya no hay un «lo mas cerca arriba».
  /// Los kilometros siguen en cada tarjeta y en el filtro `kmMax`, pero ver lo
  /// cercano de un golpe ya no es mirar la cabeza de la lista. Las dos cosas a la
  /// vez llegaron el 15/10/2026 por la cabecera: con otro almacén elegido arriba
  /// ([AlmacenOrigen.primeroLosDe]) van primero sus pedidos, del más cercano al
  /// más lejano, y después los demás por fecha. Cambiaron juntos este método, el
  /// SQL del servidor y su cursor.
  ///
  /// **El orden se hace aqui, en el aparato**, y no en la consulta, porque la
  /// pantalla tiene que dar el mismo orden sin conexion: es la hora a la que se
  /// usa. Son los pedidos de UNA sucursal, no del pais.
  ///
  /// Las condiciones son LAS DE LA LISTA DEL SERVIDOR (`ListarPedidosSinColocar`
  /// y su contador `ContarPedidosSinColocar`), ni una mas ni una menos: si el
  /// tablero ofreciera algo que luego no se puede colocar o que la ruta rechaza,
  /// el logistico prepararia una columna entera para que al final del dia le
  /// digan que no. Desde el 07/10/2026 (Amado) entran **tambien** el domicilio
  /// cobrado (`facturaDomicilio > 0`) y el domicilio cotizado (`pedidoCosto` no
  /// nulo) si el vendedor lo marco (issue 10, 15/10/2026): sin ellos la tarjeta
  /// se ofrecia aqui y `colocar` la rechazaba (`porQueNoSePuedeColocar`), o se
  /// colocaba y fallaba al armar la zona.
  /// LAS FACTURAS QUE NO TIENEN PUNTO DE ENTREGA y por eso no salen en [sinColocar] (28/10/2026, Jose: «que las
  /// que vengan sin punto el logístico pueda poner la dirección él mismo… desde el tablero, sin salir»).
  ///
  /// Sin coordenadas no hay parada: no se puede colocar en una zona ni meter en una ruta. Ventra manda la
  /// dirección en texto y el punto sale del padrón de clientes por código o por nombre; si el vendedor
  /// escribió mal la referencia («GONZALES» por «GONZALEZ») o la factura no trae cliente, queda sin punto y
  /// hasta hoy NO SE VEÍA EN EL TABLERO. Las condiciones son las de [sinColocar] MENOS las coordenadas: en
  /// cuanto se ubica una, sale de aquí y entra en la lista de al lado.
  Stream<List<FacturaSinUbicar>> sinUbicar(String sucursalId) async* {
    await _listo();
    final o = _base.orders;
    final consulta = _base.select(o)
      ..where(
        (t) =>
            t.branchId.equals(sucursalId) &
            t.source.equals(Procedencia.pedido) &
            t.routeId.isNull() &
            t.deliveredAt.isNull() &
            t.archivado.equals(false) &
            (t.endLat.isNull() | t.endLng.isNull()) &
            entraEnRuta(t),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.orderDate)]);
    yield* consulta.watch().map(
      (filas) => [
        for (final f in filas)
          FacturaSinUbicar(
            pedidoId: f.id,
            factura: f.facturaNumero,
            cliente: f.customerName,
            direccion: f.endAddress ?? f.address,
          ),
      ],
    );
  }

  Future<MitadIzquierda> sinColocar(
    String sucursalId,
    AlmacenOrigen origen, {
    FiltrosSinColocar filtros = const FiltrosSinColocar(),
  }) async {
    await _listo();
    final o = _base.orders;

    final consulta = _base.select(o)
      ..where(
        (t) =>
            t.branchId.equals(sucursalId) &
            t.source.equals(Procedencia.pedido) &
            t.routeId.isNull() &
            t.endLat.isNotNull() &
            t.endLng.isNotNull() &
            // LA REGLA DE ENTRADA A UNA RUTA (`nucleo/regla_de_entrada.dart`):
            // facturado (`igual` o `cambiado`), domicilio cobrado y, si el
            // vendedor lo marco, cotizado. La misma que el servidor en su lista y
            // en su contador, y que la lista de disponibles de Rutas.
            //
            // VA AQUI ADEMAS DE EN EL SQL DEL SERVIDOR, y no es duplicar por
            // gusto: esta pantalla NO le pregunta a la api, se lo pregunta a su
            // propia base local —que es lo que la hace funcionar sin senal—.
            //
            // Ya NO va `requiereDomicilio = true` (25/09/2026, «sin domicilio no
            // los pongas»): lo que dice que un pedido lleva domicilio es el cobro
            // de la factura, y con la casilla aqui PBF26-2610131268 —sin marcar y
            // con 1.31 de domicilio cobrado— no salia nunca (issue 10 de Amado,
            // 15/10/2026).
            entraEnRuta(t),
      );
    // «Sin colocar» = no esta en ninguna columna. Del tablero de NADIE: un
    // pedido es de una sucursal y sólo puede estar en el suyo.
    //
    // `NOT EXISTS` contra la tabla y no `isNotIn` con la lista de ids: aquello
    // era una consulta más para traerse los colocados y luego UN PARÁMETRO POR
    // PEDIDO COLOCADO, y SQLite tiene tope de parámetros por sentencia. Medido
    // igual de rápido (26/09/2026); lo que se gana es que no tiene techo. Tira
    // de la clave primaria `board_placements.order_id`.
    consulta.where(
      (t) => const CustomExpression<bool>(
        'NOT EXISTS (SELECT 1 FROM ${EsquemaTablero.colocaciones} p '
        'WHERE p.order_id = "orders"."id")',
      ),
    );

    final q = filtros.q?.trim();
    if (q != null && q.isNotEmpty) {
      final patron = '%$q%';
      consulta.where(
        (t) =>
            t.customerName.like(patron) |
            t.operationNumber.like(patron) |
            // La factura de Ventra; con dos («47061, 47062») el LIKE encuentra cualquiera.
            t.facturaNumero.like(patron) |
            t.endAddress.like(patron) |
            t.address.like(patron) |
            t.municipio.like(patron) |
            t.vendedor.like(patron) |
            // La pregunta del despacho: «¿que pedidos llevan malta?».
            existsQuery(
              _base.selectOnly(_base.orderItems)
                ..addColumns([_base.orderItems.id])
                ..where(
                  _base.orderItems.orderId.equalsExp(t.id) &
                      _base.orderItems.description.like(patron),
                ),
            ),
      );
    }
    final municipio = filtros.municipio;
    if (municipio != null && municipio.isNotEmpty) {
      consulta.where((t) => t.municipio.equals(municipio));
    }
    if (filtros.vendedores.isNotEmpty) {
      consulta.where((t) => t.vendedor.isIn(filtros.vendedores));
    }
    // EL COBRO DEL DOMICILIO es `pedidoCosto`, el que puso el repartidor desde
    // Entrega, y es el MISMO numero que la tarjeta ensena al lado del peso.
    // **No es `deliveryPrice`**: ese es el viaje dedicado, otra cosa, y hoy
    // esta vacio en los 3.313 pedidos del servidor. Preguntando por el, «Con
    // cobro» daba 0 mientras la lista de al lado ensenaba «0,04 $» en una
    // tarjeta — 16/09/2026, Jose: «tiene q haber hay uno por q no me sale q
    // tiene precio de domicilio». Confundir los dos es cobrar uno por el otro,
    // que es lo que ya avisa la consulta de las columnas del tablero.
    //
    // Un costo NULO es «todavia no se lo han puesto»; un cero no lo es, y por
    // eso se pregunta por nulo y no por «> 0»: un domicilio de cero es una
    // decision de alguien, no un hueco.
    final conCobro = filtros.conCobroDeDomicilio;
    if (conCobro != null) {
      // Desde el 16/10/2026 (Jose, con la regla «entra todo lo facturado»): «con cobro» es el precio
      // de Entrega O lo cobrado en la factura (`facturaDomicilio > 0`); «sin cobro», ninguno de los dos.
      consulta.where((t) {
        // `coalesce`: un cobro vacío no es «desconocido» sino «sin cobro» (si no, el `not` lo pierde).
        final cobrado =
            t.pedidoCosto.isNotNull() |
            coalesce([t.facturaDomicilio, const Constant<double>(0)])
                .isBiggerThanValue(0);
        return conCobro ? cobrado : cobrado.not();
      });
    }
    // Con `created_at` de repuesto: un pedido sin fecha de PEDIDO no puede
    // desaparecer del rango en que entro. La regla vive en un sitio.
    final fecha = fechaDeLaFacturaEntre(o, filtros.desde, filtros.hasta);
    if (fecha != null) consulta.where((_) => fecha);

    final filas = await consulta.get();
    // El orden, sobre las filas y antes de armar las tarjetas: el filtro por
    // kilometros de mas abajo quita elementos pero no reordena.
    //
    // PRIMERO LOS DEL ALMACÉN ELEGIDO ARRIBA, si lo hay (15/10/2026): su cercanía
    // es la distancia a él, la de la tarjeta, y la de los demás es infinito, así
    // que van detrás todos empatados y entre ellos manda la fecha. Es la misma
    // clave que el servidor (`cercania_de_orden`), con los mismos casos
    // (`docs/orden-sin-colocar.casos.json`).
    final primero = _codigoDeAlmacen(origen.primeroLosDe);
    final cercania = <String, double>{
      for (final p in filas)
        p.id:
            primero != null &&
                _codigoDeAlmacen(p.almacenSalidaCodigo) == primero
            ? _km(origen, p.endLat, p.endLng)
            : double.infinity,
    };
    filas.sort((a, b) {
      final porCercania = cercania[a.id]!.compareTo(cercania[b.id]!);
      return porCercania != 0 ? porCercania : _porFechaDeFactura(a, b);
    });

    final conduces = await conducesDeUnaVez(_base, [
      for (final p in filas) p.id,
    ]);
    final repes = <String, int>{};
    for (final p in filas) {
      final clave = p.customerName.trim().toLowerCase();
      repes[clave] = (repes[clave] ?? 0) + 1;
    }

    var tarjetas = filas
        .map(
          (p) => TarjetaPedido(
            pedidoId: p.id,
            operationNumber: p.operationNumber,
            customerName: p.customerName,
            customerPhone: p.customerPhone,
            address: p.endAddress ?? p.address,
            weight: conduces[p.id]?.pesoKg ?? p.weight,
            conduce: conduces[p.id],
            pedidoCosto: p.pedidoCosto,
            municipio: p.municipio,
            vendedor: p.vendedor,
            orderDate: p.orderDate ?? p.createdAt,
            facturaEstado: p.facturaEstado,
            facturaNumero: p.facturaNumero,
            facturaAt: p.facturaAt,
            facturaDomicilio: p.facturaDomicilio,
            requiereDomicilio: p.requiereDomicilio,
            archivado: p.archivado,
            rutaId: p.routeId,
            resultado: p.resultado,
            deliveredAt: p.deliveredAt,
            kmAlAlmacen: _km(origen, p.endLat, p.endLng),
            mismoCliente: repes[p.customerName.trim().toLowerCase()] ?? 1,
          ),
        )
        .toList();

    final kmMax = filtros.kmMax;
    if (kmMax != null) {
      tarjetas = tarjetas.where((t) => t.kmAlAlmacen <= kmMax).toList();
    }

    return MitadIzquierda(
      total: tarjetas.length,
      pedidos: tarjetas.take(filtros.limite).toList(growable: false),
    );
  }

  /// Los municipios y vendedores que hay de verdad, para los desplegables.
  Future<(List<String> municipios, List<String> vendedores)> facetas(
    String sucursalId,
  ) async {
    final filas =
        await (_base.select(_base.orders)..where(
              (t) =>
                  t.branchId.equals(sucursalId) &
                  t.routeId.isNull() &
                  noEsMiembro(t),
            ))
            .get();
    final municipios =
        filas
            .map((p) => p.municipio)
            .whereType<String>()
            .where((m) => m.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final vendedores =
        filas
            .map((p) => p.vendedor)
            .whereType<String>()
            .where((v) => v.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return (municipios, vendedores);
  }

  /// Los que se llevo la cascada y todavia no se han avisado (§7.5).
  Future<List<PedidoDesaparecido>> desaparecidos() async {
    await _listo();
    final filas = await _base
        .customSelect(
          'SELECT order_id, operation_number, customer_name, columna '
          'FROM ${EsquemaTablero.desaparecidos} ORDER BY visto_at ASC',
        )
        .get();
    return filas
        .map(
          (f) => PedidoDesaparecido(
            pedidoId: f.read<String>('order_id'),
            operationNumber: f.readNullable<String>('operation_number'),
            customerName: f.readNullable<String>('customer_name'),
            columna: f.readNullable<String>('columna'),
          ),
        )
        .toList(growable: false);
  }

  /// `ORDER BY coalesce(factura_at, order_date) ASC NULLS LAST, id ASC`, repetido
  /// tal cual del servidor. Estatico y con nombre propio para que el orden sea UNA
  /// cosa que se lee, y no un `sort` enterrado en un metodo de doscientas lineas.
  static int _porFechaDeFactura(Pedido a, Pedido b) {
    final fa = a.facturaAt ?? a.orderDate;
    final fb = b.facturaAt ?? b.orderDate;
    if (fa != null && fb != null) {
      final cual = fa.compareTo(fb);
      if (cual != 0) return cual;
    } else if (fa == null && fb != null) {
      return 1; // sin fecha, detras de cualquiera con fecha
    } else if (fa != null && fb == null) {
      return -1;
    }
    return a.id.compareTo(b.id);
  }

  /// El código de un almacén tal como se compara: sin espacios y en mayúsculas,
  /// igual que `upper(btrim(…))` en el servidor. Vacío es `null`: un almacén sin
  /// código no casa con un pedido sin almacén.
  static String? _codigoDeAlmacen(String? codigo) {
    final c = codigo?.trim().toUpperCase();
    return (c == null || c.isEmpty) ? null : c;
  }

  /// Sin coordenadas no hay distancia. `infinity` y no `0`: un pedido sin
  /// coordenadas no puede salir el primero de la lista de «lo mas cerca».
  static double _km(AlmacenOrigen origen, double? lat, double? lng) =>
      (lat == null || lng == null)
      ? double.infinity
      : kmHaversine(origen.lat, origen.lng, lat, lng);
}
