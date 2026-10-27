/// LOS CONDUCES EN EL APARATO, EN UN SOLO SITIO — 27/10/2026 (`docs/conduces.md`).
///
/// Un conduce es lo que sale con el camión y junta varias FACTURAS del mismo cliente en UNA
/// parada. Cada factura sigue siendo una fila de `orders`; la PRINCIPAL (la primera que se marcó)
/// no lleva nada y los MIEMBROS apuntan a ella con `conduce_principal_id`.
///
/// ## La regla 3 de la especificación: los miembros no salen como filas propias
///
/// [noEsMiembro] y [noEsMiembroSql] son LA condición, escrita UNA vez. La usan la lista de Facturas y
/// su contador (`ConsultasPedidos.donde`), sus facetas, y —por la regla de entrada, que es donde ya se
/// ataban lista y contador— «Sin colocar», los disponibles del asistente, el tablero y el Panel
/// (`entraEnRuta`, `entraEnRutaSql`). `app/test/nucleo/conduce_test.dart` ata que las listas la lleven
/// y que el contador cuente lo mismo que la lista (CLAUDE.md §3-bis: una prueba, no un comentario).
library;

import 'dart:async';

import 'package:drift/drift.dart';

import 'base/base.dart';
import 'numero_de_factura.dart';
import 'regla_de_entrada.dart' show costoDeLaParada;

/// La fila NO es miembro de un conduce: es una factura suelta o la principal de uno.
Expression<bool> noEsMiembro($OrdersTable o) => o.conducePrincipalId.isNull();

/// [noEsMiembro] para el SQL a mano (el alias de `orders` es `o`, como en [entraEnRutaSql]).
const noEsMiembroSql = 'o.conduce_principal_id IS NULL';

/// Los «no» de los conduces, LETRA POR LETRA los del servidor (`docs/contratos-api.md`, «Conduces»):
/// sin señal los dice el aparato y con ella la nube, y el mismo rechazo no puede leerse en dos idiomas
/// (CLAUDE.md §3-quinquies). `<n>` es el número de factura. Si el servidor dice otra cosa, manda él.
abstract final class MotivosDeConduce {
  static const pocas =
      'Marca al menos una factura, además de la principal, para el conduce';
  static const noExiste = 'No encontrado';

  static String sucursales(String n) =>
      'La factura $n es de otra sucursal: un conduce no mezcla sucursales';
  static String clientes(String n, String cliente) =>
      'La factura $n es de otro cliente ($cliente): un conduce junta facturas de un solo cliente';
  static String archivada(String n) => 'La factura $n está archivada';
  static String enRuta(String n, String? codigo) =>
      'La factura $n ya va en la ruta ${codigo ?? 'otra ruta'}';
  static String entregada(String n) => 'La factura $n ya está entregada';
  static String conResultado(String n, String resultado) =>
      'La factura $n ya tiene resultado ($resultado)';
  static String yaMiembro(String n, String principal) =>
      'La factura $n ya es miembro del conduce $principal';
  static String principalEsMiembro(String n, String principal) =>
      'La factura $n es miembro del conduce $principal: no puede ser la principal';
  static String yaEsPrincipal(String n) =>
      'La factura $n ya es la principal de otro conduce';
  static String noEncabeza(String n) =>
      'La factura $n no encabeza ningún conduce';
  static String deshazElOtro(String n, String principal) =>
      'La factura $n es miembro del conduce $principal: deshaz ese';
  static String noEsMiembro(String n) =>
      'La factura $n no es miembro de ese conduce';

  /// Elegir un MIEMBRO suelto para armar, colocar, quitar o marcar: `<principal>` es el número de su principal.
  static String esMiembro(String principal) =>
      'Esa factura va dentro del conduce $principal: arma el conduce entero';
}

/// El número con el que se nombra una factura en una frase.
String numeroDe(Pedido p) =>
    NumeroDeFactura.de(p.facturaNumero) ?? p.operationNumber ?? p.customerName;

/// El «no» de elegir un MIEMBRO suelto (con el número de su principal), o `null` si no es miembro.
Future<String?> motivoDeMiembro(BaseLocal base, Pedido p) async {
  final principalId = p.conducePrincipalId;
  if (principalId == null) return null;
  final principal = await (base.select(
    base.orders,
  )..where((o) => o.id.equals(principalId))).getSingleOrNull();
  return MotivosDeConduce.esMiembro(
    principal == null ? principalId : numeroDe(principal),
  );
}

/// Un conduce tal como se ve: la principal y sus miembros.
class ConduceDe {
  const ConduceDe(
    this.principal,
    this.miembros, [
    this.codigosDeRuta = const {},
  ]);

  final Pedido principal;
  final List<Pedido> miembros;

  /// `routes.id` -> código (`RT-…`) de las rutas en que va alguna de sus facturas, para decirlo en el motivo.
  final Map<String, String?> codigosDeRuta;

  /// La principal primero y luego sus miembros: el orden en que se dicen y se suman.
  List<Pedido> get facturas => [principal, ...miembros];

  /// `47313 + 47314`: los números de factura unidos, la principal primero.
  String get numeros => [
    for (final p in facturas)
      NumeroDeFactura.de(p.facturaNumero) ?? p.operationNumber ?? '—',
  ].join(' + ');

  /// `Conduce 47313 + 47314`.
  String get etiqueta => 'Conduce $numeros';

  /// El peso de TODO el conduce (la principal y sus miembros).
  double get pesoKg => facturas.fold<double>(0, (a, p) => a + p.weight);

  /// El domicilio de la parada: lo que suman sus facturas con costo. Nulo si ninguna lo trae (un
  /// cero inventado se lee como «gratis»).
  double? get domicilioUsd {
    double? suma;
    for (final p in facturas) {
      final c = costoDeLaParada(p.pedidoCosto, p.facturaDomicilio);
      if (c != null) suma = (suma ?? 0) + c;
    }
    return suma;
  }

  /// Lo que impide deshacerlo o sacar a un miembro: alguna de sus facturas va en una ruta o tiene
  /// resultado (los literales del servidor, con el número de la que lo impide). `null` = se puede.
  String? get porQueNoSeToca {
    for (final p in facturas) {
      final n = numeroDe(p);
      if (p.routeId != null) {
        return MotivosDeConduce.enRuta(n, codigosDeRuta[p.routeId]);
      }
      if (p.deliveredAt != null || p.resultado == 'entregado') {
        return MotivosDeConduce.entregada(n);
      }
      if (p.resultado != null) {
        return MotivosDeConduce.conResultado(n, p.resultado!);
      }
    }
    return null;
  }
}

/// Las facturas que van DENTRO de estas principales (sus miembros), una lectura.
Future<List<Pedido>> miembrosDe(BaseLocal base, Iterable<String> principales) {
  final ids = principales.toList();
  if (ids.isEmpty) return Future.value(const <Pedido>[]);
  return (base.select(base.orders)
        ..where((o) => o.conducePrincipalId.isIn(ids))
        ..orderBy([
          (o) => OrderingTerm.asc(o.facturaNumero),
          (o) => OrderingTerm.asc(o.id),
        ]))
      .get();
}

/// Los conduces de estas principales, UNA vez y agrupados: para quien decide en seco (las tarjetas
/// del tablero, el armado). Las que no llevan miembros no salen.
Future<Map<String, ConduceDe>> conducesDeUnaVez(
  BaseLocal base,
  Iterable<String> principales,
) async {
  final miembros = await miembrosDe(base, principales);
  if (miembros.isEmpty) return const <String, ConduceDe>{};
  return _agrupar(base, miembros);
}

Future<Map<String, ConduceDe>> _agrupar(
  BaseLocal base,
  List<Pedido> miembros,
) async {
  final ids = {for (final m in miembros) m.conducePrincipalId!}.toList();
  final cabezas = await (base.select(
    base.orders,
  )..where((o) => o.id.isIn(ids))).get();
  final porId = {for (final c in cabezas) c.id: c};
  final grupos = <String, List<Pedido>>{};
  for (final m in miembros) {
    (grupos[m.conducePrincipalId!] ??= <Pedido>[]).add(m);
  }
  final rutaIds = {
    for (final p in [...cabezas, ...miembros])
      if (p.routeId != null) p.routeId!,
  }.toList();
  final codigos = rutaIds.isEmpty
      ? const <String, String?>{}
      : {
          for (final r in await (base.select(
            base.routes,
          )..where((r) => r.id.isIn(rutaIds))).get())
            r.id: r.routeCode,
        };
  return {
    for (final e in grupos.entries)
      if (porId[e.key] != null)
        e.key: ConduceDe(porId[e.key]!, e.value, codigos),
  };
}

/// LAS PARADAS, como se pintan: cada principal con el peso y el domicilio de TODAS las facturas de su
/// conduce (los miembros no son paradas: van con ella). Las facturas sueltas pasan tal cual. Es una
/// copia para MOSTRAR y sumar —nunca se escribe en la base—; así el peso de la ruta, la tarjeta de la
/// parada y el cierre cuentan lo mismo sin que cada uno sepa de conduces.
Future<List<Pedido>> conMiembrosSumados(
  BaseLocal base,
  List<Pedido> paradas,
) async {
  final conduces = await conducesDeUnaVez(base, [
    for (final p in paradas) p.id,
  ]);
  if (conduces.isEmpty) return paradas;
  return [
    for (final p in paradas)
      if (conduces[p.id] case final c?)
        p.copyWith(weight: c.pesoKg, pedidoCosto: Value(c.domicilioUsd))
      else
        p,
  ];
}

/// Los miembros de [principales] van con ellas a la ruta [rutaId] (`docs/conduces.md` regla 4):
/// misma ruta y mismo intento nuevo —sin resultado—, y SIN `stop_order` propio: la parada es de la
/// principal. Dentro de la transacción de quien arma.
Future<void> llevarLosMiembrosALaRuta(
  BaseLocal base,
  Iterable<String> principales,
  String rutaId,
  DateTime ahora,
) async {
  final ids = principales.toList();
  if (ids.isEmpty) return;
  await (base.update(
    base.orders,
  )..where((o) => o.conducePrincipalId.isIn(ids))).write(
    OrdersCompanion(
      routeId: Value(rutaId),
      ultimaRutaId: Value(rutaId),
      stopOrder: const Value(null),
      resultado: const Value(null),
      resultadoAt: const Value(null),
      resultadoNota: const Value(null),
      deliveredAt: const Value(null),
      updatedAt: Value(ahora),
    ),
  );
}

/// Quitar la principal de su ruta quita a los miembros (regla 4): sueltan `route_id` Y
/// `ultima_ruta_id`, como una parada quitada.
Future<void> soltarLosMiembrosDeLaRuta(
  BaseLocal base,
  Iterable<String> principales,
) async {
  final ids = principales.toList();
  if (ids.isEmpty) return;
  await (base.update(
    base.orders,
  )..where((o) => o.conducePrincipalId.isIn(ids))).write(
    const OrdersCompanion(
      routeId: Value(null),
      ultimaRutaId: Value(null),
      stopOrder: Value(null),
      segmentKm: Value(null),
    ),
  );
}

/// LOS CONDUCES, como STREAM sobre `orders` (CLAUDE.md §3-ter: lo que se pinta y cambia cuando
/// llega la bajada no es un `Future`). [principales] acota a esos conduces (la página de Facturas);
/// [sucursalId] a una sucursal (la pestaña «Conduces»); sin ninguno, todos.
///
/// Un miembro cuya principal no está en este aparato no forma conduce (no se inventa): queda fuera.
Stream<Map<String, ConduceDe>> mirarConduces(
  BaseLocal base, {
  Iterable<String>? principales,
  String? sucursalId,
}) => sobreOrders(base, () async {
  final miembros =
      await (base.select(base.orders)
            ..where((o) {
              Expression<bool> donde = o.conducePrincipalId.isNotNull();
              if (principales != null) {
                donde = donde & o.conducePrincipalId.isIn(principales.toList());
              }
              if (sucursalId != null && sucursalId.isNotEmpty) {
                donde = donde & o.branchId.equals(sucursalId);
              }
              return donde;
            })
            ..orderBy([
              (o) => OrderingTerm.asc(o.facturaNumero),
              (o) => OrderingTerm.asc(o.id),
            ]))
          .get();
  return miembros.isEmpty
      ? const <String, ConduceDe>{}
      : await _agrupar(base, miembros);
});

/// Una lectura que se REPITE con cada escritura en `orders`, y no sólo cuando cambia su propia
/// consulta: un conduce depende de la principal Y de sus miembros, y Drift no vuelve a emitir un
/// `watch` cuyas filas no cambiaron aunque cambiara la otra mitad. Se suscribe a los cambios ANTES de
/// leer (si no, una escritura entre la primera lectura y la suscripción se pierde y la pantalla se queda
/// con la foto vieja) y junta las escrituras que lleguen mientras lee en UNA relectura. Es un Stream,
/// no un Future (CLAUDE.md §3-ter).
Stream<T> sobreOrders<T>(BaseLocal base, Future<T> Function() leer) {
  late final StreamController<T> salida;
  StreamSubscription<Object?>? cambios;
  var leyendo = false;
  var otraVez = false;

  Future<void> releer() async {
    if (leyendo) {
      otraVez = true;
      return;
    }
    leyendo = true;
    try {
      do {
        otraVez = false;
        final valor = await leer();
        if (!salida.isClosed) salida.add(valor);
      } while (otraVez && !salida.isClosed);
    } catch (e, st) {
      if (!salida.isClosed) salida.addError(e, st);
    } finally {
      leyendo = false;
    }
  }

  salida = StreamController<T>(
    onListen: () {
      cambios = base
          .tableUpdates(TableUpdateQuery.onTable(base.orders))
          .listen((_) => releer());
      releer();
    },
    onCancel: () => cambios?.cancel(),
  );
  return salida.stream;
}

/// El nombre de un cliente como se compara: minúsculas y espacios colapsados, SIN plegar tildes
/// (`contratos-api.md`: «Pérez» y «Perez» son dos clientes).
String clienteNormalizado(String nombre) =>
    nombre.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// POR QUÉ NO SE PUEDEN JUNTAR estas facturas (la primera es la principal), o `null` si se puede.
///
/// Es la misma pregunta, en el mismo orden y con las mismas palabras que el servidor (422 antes que
/// 409). La usan el botón «Crear conduce» (apagado, con el motivo) y la acción (que vuelve a preguntar
/// antes de apuntar): no pueden contestar distinto. [principalesDeConduce] son los ids que ya son
/// principal de un conduce (la principal SÍ puede serlo: se le añaden miembros; las demás NO).
/// [codigosDeRuta] da el `RT-…` de las rutas en que van.
String? porQueNoSePuedeJuntar(
  List<Pedido> elegidas, {
  Set<String> principalesDeConduce = const {},
  Map<String, String?> codigosDeRuta = const {},
  Map<String, String> numerosDePrincipal = const {},
}) {
  if (elegidas.length < 2) return MotivosDeConduce.pocas;
  final principal = elegidas.first;
  final cliente = clienteNormalizado(principal.customerName);
  // 422: datos que no valen.
  for (final p in elegidas.skip(1)) {
    if (p.branchId != principal.branchId) {
      return MotivosDeConduce.sucursales(numeroDe(p));
    }
  }
  for (final p in elegidas.skip(1)) {
    if (clienteNormalizado(p.customerName) != cliente) {
      return MotivosDeConduce.clientes(numeroDe(p), principal.customerName);
    }
  }
  // 409: el estado.
  for (final p in elegidas) {
    final n = numeroDe(p);
    if (p.archivado) return MotivosDeConduce.archivada(n);
    if (p.routeId != null) {
      return MotivosDeConduce.enRuta(n, codigosDeRuta[p.routeId]);
    }
    if (p.deliveredAt != null || p.resultado == 'entregado') {
      return MotivosDeConduce.entregada(n);
    }
    if (p.resultado != null) {
      return MotivosDeConduce.conResultado(n, p.resultado!);
    }
  }
  if (principal.conducePrincipalId != null) {
    return MotivosDeConduce.principalEsMiembro(
      numeroDe(principal),
      numerosDePrincipal[principal.conducePrincipalId!] ??
          principal.conducePrincipalId!,
    );
  }
  for (final p in elegidas.skip(1)) {
    if (p.conducePrincipalId != null && p.conducePrincipalId != principal.id) {
      return MotivosDeConduce.yaMiembro(
        numeroDe(p),
        numerosDePrincipal[p.conducePrincipalId!] ?? p.conducePrincipalId!,
      );
    }
    if (principalesDeConduce.contains(p.id)) {
      return MotivosDeConduce.yaEsPrincipal(numeroDe(p));
    }
  }
  return null;
}

/// Lo que [porQueNoSePuedeJuntar] necesita saber de la base sobre [elegidas]: cuáles ya son principal de
/// un conduce, el `RT-…` de las rutas en que van y el número de las principales de las que son miembro.
/// Una sola lectura para la acción y para el cajón: no pueden contestar distinto.
Future<
  ({
    Set<String> principales,
    Map<String, String?> codigosDeRuta,
    Map<String, String> numerosDePrincipal,
  })
>
contextoParaJuntar(BaseLocal base, List<Pedido> elegidas) async {
  final ids = [for (final p in elegidas) p.id];
  final principales = {
    for (final m in await miembrosDe(base, ids)) m.conducePrincipalId!,
  };
  final rutaIds = [
    for (final p in elegidas)
      if (p.routeId != null) p.routeId!,
  ];
  final rutas = rutaIds.isEmpty
      ? const <Ruta>[]
      : await (base.select(
          base.routes,
        )..where((r) => r.id.isIn(rutaIds))).get();
  final deQuien = {
    for (final p in elegidas)
      if (p.conducePrincipalId != null) p.conducePrincipalId!,
  }.toList();
  final cabezas = deQuien.isEmpty
      ? const <Pedido>[]
      : await (base.select(
          base.orders,
        )..where((o) => o.id.isIn(deQuien))).get();
  return (
    principales: principales,
    codigosDeRuta: {for (final r in rutas) r.id: r.routeCode},
    numerosDePrincipal: {for (final c in cabezas) c.id: numeroDe(c)},
  );
}
