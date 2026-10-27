// Lo que los CONDUCES escriben: crear, deshacer, sacar un miembro (`docs/conduces.md`, 27/10/2026).
//
// Las TRES formas de la aplicación (`CLAUDE.md` §1), como `AccionesDePedido`:
//
//  * WEB ([EscrituraEnVivo] no nulo): va al servidor y ESPERA. Con un 4xx sale su motivo LITERAL
//    (`RechazoLocal`) y no se escribe nada; con un 2xx se refleja en la base de la pestaña.
//  * APK y ESCRITORIO: se validan aquí las mismas reglas que el servidor, y en UNA transacción se
//    escribe `conduce_principal_id` y se encola el apunte (`POST /conduces`, `DELETE /conduces/{id}`,
//    `DELETE /conduces/{id}/miembros/{id}`). Si el servidor lo rechaza al subir, el apunte queda en la
//    bandeja con su motivo literal: nada se descarta en silencio (CLAUDE.md §4).
//
// El servidor manda: la bajada trae la verdad de `conducePrincipalId` y pisa lo que se escribió aquí.

import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/cola/cola_salida.dart';
import '../../../nucleo/conduce.dart';
import '../../../nucleo/red/escritura_en_vivo.dart';
import '../../../nucleo/reloj.dart';
import '../../rutas/datos/acciones_rutas.dart' show RechazoLocal;
import '../../tablero/datos/esquema.dart';

class AccionesDeConduce {
  AccionesDeConduce(
    this._base,
    this._cola, {
    Reloj reloj = relojDelAparato,
    EscrituraEnVivo? enVivo,
  }) : _reloj = reloj,
       _enVivo = enVivo;

  final BaseLocal _base;
  final ColaDeSalida _cola;
  final Reloj _reloj;

  /// `null` en la APK y el escritorio. Se decide en `proveedores_pedidos.dart`.
  final EscrituraEnVivo? _enVivo;

  /// Lo que ya va de camino, por acción: un clic duplicado no manda dos veces lo mismo.
  final Map<String, Future<void>> _enVuelo = <String, Future<void>>{};

  Future<void> _unaSola(String clave, Future<void> Function() accion) {
    final yaVa = _enVuelo[clave];
    if (yaVa != null) return yaVa;
    final vuelo = accion();
    _enVuelo[clave] = vuelo;
    vuelo.whenComplete(() {
      if (_enVuelo[clave] == vuelo) _enVuelo.remove(clave);
    }).ignore();
    return vuelo;
  }

  /// JUNTA las facturas [idsEnOrden] en un conduce: **la primera es la principal**, las demás van con
  /// ella. El orden es el de marcado de la pantalla.
  Future<void> crear(List<String> idsEnOrden) => _unaSola(
    'crear:${idsEnOrden.join(',')}',
    () async {
      final filas = await (_base.select(
        _base.orders,
      )..where((o) => o.id.isIn(idsEnOrden))).get();
      final porId = {for (final f in filas) f.id: f};
      if (idsEnOrden.any((id) => porId[id] == null)) {
        throw const RechazoLocal(MotivosDeConduce.noExiste);
      }
      final elegidas = [for (final id in idsEnOrden) porId[id]!];
      final contexto = await contextoParaJuntar(_base, elegidas);
      final no = porQueNoSePuedeJuntar(
        elegidas,
        principalesDeConduce: contexto.principales,
        codigosDeRuta: contexto.codigosDeRuta,
        numerosDePrincipal: contexto.numerosDePrincipal,
      );
      if (no != null) throw RechazoLocal(no);

      final principalId = idsEnOrden.first;
      final miembros = idsEnOrden.skip(1).toList();
      final cuerpo = <String, Object?>{
        'principalId': principalId,
        'ids': miembros,
      };
      final enVivo = _enVivo;
      if (enVivo != null) {
        final respuesta = await _mandar(
          enVivo,
          metodo: 'POST',
          ruta: '/conduces',
          cuerpo: cuerpo,
        );
        await _ligar(principalId, _idsDe(respuesta, 'miembros') ?? miembros);
        return;
      }
      await _base.transaction(() async {
        await _ligar(principalId, miembros);
        await _cola.encolar(metodo: 'POST', ruta: '/conduces', cuerpo: cuerpo);
      });
    },
  );

  /// DESHACE el conduce de [principalId]: todos sus miembros vuelven a ser facturas sueltas.
  Future<void> deshacer(String principalId) =>
      _unaSola('deshacer:$principalId', () async {
        final conduce = (await conducesDeUnaVez(_base, [
          principalId,
        ]))[principalId];
        if (conduce == null) {
          throw RechazoLocal(await _porQueNoEncabeza(principalId));
        }
        final no = conduce.porQueNoSeToca;
        if (no != null) throw RechazoLocal(no);
        final enVivo = _enVivo;
        if (enVivo != null) {
          final respuesta = await _mandar(
            enVivo,
            metodo: 'DELETE',
            ruta: '/conduces/$principalId',
          );
          await _soltar(
            _idsDe(respuesta, 'liberados') ??
                [for (final m in conduce.miembros) m.id],
          );
          return;
        }
        await _base.transaction(() async {
          await _soltar([for (final m in conduce.miembros) m.id]);
          await _cola.encolar(
            metodo: 'DELETE',
            ruta: '/conduces/$principalId',
            cuerpo: const <String, Object?>{},
          );
        });
      });

  /// SACA a [miembroId] de su conduce (el de [principalId]).
  Future<void> sacar(String principalId, String miembroId) =>
      _unaSola('sacar:$principalId:$miembroId', () async {
        final conduce = (await conducesDeUnaVez(_base, [
          principalId,
        ]))[principalId];
        if (conduce == null) {
          throw RechazoLocal(await _porQueNoEncabeza(principalId));
        }
        if (!conduce.miembros.any((m) => m.id == miembroId)) {
          final f = await (_base.select(
            _base.orders,
          )..where((o) => o.id.equals(miembroId))).getSingleOrNull();
          throw RechazoLocal(
            f == null
                ? MotivosDeConduce.noExiste
                : MotivosDeConduce.noEsMiembro(numeroDe(f)),
          );
        }
        final no = conduce.porQueNoSeToca;
        if (no != null) throw RechazoLocal(no);
        final enVivo = _enVivo;
        if (enVivo != null) {
          await _mandar(
            enVivo,
            metodo: 'DELETE',
            ruta: '/conduces/$principalId/miembros/$miembroId',
          );
          await _soltar([miembroId]);
          return;
        }
        await _base.transaction(() async {
          await _soltar([miembroId]);
          await _cola.encolar(
            metodo: 'DELETE',
            ruta: '/conduces/$principalId/miembros/$miembroId',
            cuerpo: const <String, Object?>{},
          );
        });
      });

  /// Por qué [principalId] no tiene conduce que tocar: no existe, es miembro de otro o no encabeza ninguno.
  Future<String> _porQueNoEncabeza(String principalId) async {
    final f = await (_base.select(
      _base.orders,
    )..where((o) => o.id.equals(principalId))).getSingleOrNull();
    if (f == null) return MotivosDeConduce.noExiste;
    final suPrincipal = f.conducePrincipalId;
    if (suPrincipal == null) return MotivosDeConduce.noEncabeza(numeroDe(f));
    final p = await (_base.select(
      _base.orders,
    )..where((o) => o.id.equals(suPrincipal))).getSingleOrNull();
    return MotivosDeConduce.deshazElOtro(
      numeroDe(f),
      p == null ? suPrincipal : numeroDe(p),
    );
  }

  /// Escribe en la base local que [miembros] van con [principalId]. Un miembro que estuviera puesto
  /// en una zona del tablero deja la zona: va con su principal, no suelto.
  Future<void> _ligar(String principalId, List<String> miembros) async {
    await (_base.update(_base.orders)..where((o) => o.id.isIn(miembros))).write(
      OrdersCompanion(
        conducePrincipalId: Value(principalId),
        updatedAt: Value(_reloj()),
      ),
    );
    await EsquemaTablero.asegurar(_base);
    for (final id in miembros) {
      await _base.customStatement(
        'DELETE FROM ${EsquemaTablero.colocaciones} WHERE order_id = ?1',
        [id],
      );
    }
    EsquemaTablero.avisarDeCambio(_base);
  }

  Future<void> _soltar(List<String> miembros) =>
      (_base.update(_base.orders)..where((o) => o.id.isIn(miembros))).write(
        OrdersCompanion(
          conducePrincipalId: const Value(null),
          updatedAt: Value(_reloj()),
        ),
      );

  /// Los ids de la lista [campo] de la respuesta del servidor (cada elemento, un id o un objeto con
  /// `id`), o `null` si no vino: entonces se usa lo que se mandó.
  List<String>? _idsDe(Object? respuesta, String campo) {
    if (respuesta is! Map<Object?, Object?>) return null;
    final lista = respuesta[campo];
    if (lista is! List<Object?>) return null;
    return [
      for (final e in lista)
        if (e is String)
          e
        else if (e is Map<Object?, Object?> && e['id'] is String)
          e['id']! as String,
    ];
  }

  Future<Object?> _mandar(
    EscrituraEnVivo enVivo, {
    required String metodo,
    required String ruta,
    Map<String, Object?> cuerpo = const <String, Object?>{},
  }) async {
    try {
      return await enVivo.mandar(metodo: metodo, ruta: ruta, cuerpo: cuerpo);
    } on RechazoDelServidor catch (no) {
      throw RechazoLocal(no.motivo);
    }
  }
}
