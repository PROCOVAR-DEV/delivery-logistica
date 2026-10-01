import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/numeros.dart';
import '../nucleo/base/base.dart';
import '../nucleo/proveedores.dart';
import '../nucleo/registro/registro.dart';

/// Lo que necesita el armazon y no tiene por que saber ninguna pantalla.

/// Las sucursales que esta persona puede mirar. Salen de la base local, no de la
/// red: la barra tiene que pintarse igual sin conexion.
final sucursalesProvider = StreamProvider<List<Sucursal>>(
  (ref) =>
      (ref.watch(baseProvider).select(ref.watch(baseProvider).branches)
            ..orderBy([(b) => OrderingTerm(expression: b.name)]))
          .watch(),
);

/// La unica fila de ajustes.
///
/// **NO trae la tasa que se usa para convertir**, aunque tenga un `cupRate`: ese
/// campo es el viejo y GLOBAL de delivery, con 320 por defecto, y la tasa es por
/// sucursal. Para convertir se mira [tasaDeLaMiradaProvider].
final ajustesProvider = StreamProvider<Ajustes?>(
  (ref) => ref
      .watch(baseProvider)
      .select(ref.watch(baseProvider).settings)
      .watchSingleOrNull(),
);

/// Si se pueden ver los importes en CUP, y si no, POR QUE NO.
///
/// Se dice siempre el porque, y no es cortesia: «no se puede» a secas es lo unico
/// que nadie sabe arreglar. Los motivos son los mismos literales que contesta
/// `GET /api/tasa` (`api/internal/api/cotizacion.go`), para que la web y el
/// aparato digan lo mismo palabra por palabra.
class TasaDeLaMirada {
  const TasaDeLaMirada._({
    this.cupPorUsd,
    this.traidoAt,
    this.fuente,
    this.fresca = true,
    this.motivo,
    this.aviso,
  });

  /// Hay tasa de ESTA sucursal: se puede ofrecer CUP.
  const TasaDeLaMirada.hay({
    required double cupPorUsd,
    required DateTime traidoAt,
    String? fuente,
    bool fresca = true,
    String? aviso,
  }) : this._(
         cupPorUsd: cupPorUsd,
         traidoAt: traidoAt,
         fuente: fuente,
         fresca: fresca,
         aviso: aviso,
       );

  /// No hay, y [motivo] dice por que. Se queda todo en USD.
  const TasaDeLaMirada.no(String motivo) : this._(motivo: motivo);

  /// Cuantos CUP son 1 USD. `null` cuando no hay tasa.
  final double? cupPorUsd;

  /// Cuando se puso la tasa en Entrega. **Es lo que demuestra que existe**, asi
  /// que nunca es `null` si [cupPorUsd] no lo es.
  final DateTime? traidoAt;

  final String? fuente;

  /// Lo que dijo ACCESOS. Aqui no se calcula ninguna regla de 24 h.
  final bool fresca;

  /// Por que no se puede ver en CUP. `null` cuando si se puede.
  final String? motivo;

  /// El aviso que acompaña a una tasa que SI se puede usar: hoy, «es del dia 9 y
  /// puede estar desfasada». `null` cuando no hay nada que avisar.
  final String? aviso;

  bool get hayCup => cupPorUsd != null;

  /// El importe, ya convertido y con su moneda.
  ///
  /// En CUP **sin decimales**: los precios reales van en cientos o en miles y el
  /// centimo solo ensucia la lectura. En USD, dos, que es lo que lleva el Excel.
  ///
  /// Si piden CUP y no hay tasa se devuelve el importe en USD. No se pinta un
  /// guion ni un cero: es mejor ver el importe en otra moneda que no verlo, y
  /// desde luego mejor que un numero convertido con una tasa que no es de esta
  /// sucursal.
  String importe(double? usd, String moneda) {
    if (usd == null) return '—';
    final tasa = cupPorUsd;
    if (moneda == 'CUP' && tasa != null && tasa > 0) {
      return '${Numeros.entero((usd * tasa).round())} CUP';
    }
    return '${Numeros.importe(usd)} USD';
  }
}

/// El codigo de la sucursal que se esta mirando, o `null` si se miran varias.
///
/// **Con una sola sucursal visible, esa es la que se mira**, aunque el selector
/// no tenga nada elegido: la barra ni siquiera pinta un desplegable ahi, pone una
/// etiqueta fija. La regla de «con todas no hay CUP» es que no hay UNA tasa que
/// valga para las ocho; cuando solo hay una, «todas» y «esa» son lo mismo.
///
/// Lo que NO se hace nunca es elegir una de varias.
final tasaDeLaMiradaProvider = Provider<TasaDeLaMirada>((ref) {
  final sucursales = ref.watch(sucursalesProvider).value;
  // Todavia no se ha leido la base. Se dice que no hay y por que, en vez de
  // ofrecer un CUP que se apagaria medio segundo despues.
  if (sucursales == null || sucursales.isEmpty) {
    return const TasaDeLaMirada.no(
      'Todavía no se han descargado las sucursales: los importes sólo se '
      'pueden ver en USD.',
    );
  }

  final elegida = ref.watch(sucursalMiradaProvider);

  // --- Varias sucursales a la vista y ninguna elegida -----------------------
  //
  // NO se elige ninguna tasa. Enseñar la de una sucursal cualquiera cuando se
  // estan viendo todas es el error que mas daño hace: un importe creible
  // convertido con la tasa que no era.
  if (elegida == null && sucursales.length > 1) {
    return const TasaDeLaMirada.no(
      'Elegí una sucursal arriba para ver los importes en CUP: cada una tiene '
      'su tasa.',
    );
  }

  // --- LA GUARDA: la tasa de una sucursal NO se usa para otra ---------------
  //
  // La sucursal que se mira se busca POR SU ID. Si no aparece —el id guardado es
  // de una sucursal que ya no se ve, que pasa de verdad porque el token dura
  // siete dias y lleva dentro la sucursal de cuando se entro— no se coge «la
  // primera» ni «la que tenga tasa»: no hay tasa, y se dice.
  //
  // Es la linea que no se puede tocar. Sin ella, Granma enseñaria los 685 de La
  // Habana como si fueran suyos: un importe asi se lee bien y esta mal, que es lo
  // peor que puede pasarle a un numero que alguien va a cobrar.
  final Sucursal? suya = elegida == null
      ? sucursales.single
      : sucursales.where((s) => s.id == elegida).firstOrNull;

  if (suya == null) {
    return const TasaDeLaMirada.no(
      'La sucursal que estabas mirando ya no está en la lista: elegí otra para '
      'ver los importes en CUP.',
    );
  }

  final quien = suya.name.isEmpty ? 'Esta sucursal' : suya.name;
  final tasa = suya.cupRate;
  final cuando = suya.cupRateTraidoAt;

  // **LA MARCA DE CUANDO, NO EL NUMERO.** Se exigen las dos cosas y la fecha es
  // la que manda: el esquema viejo traia 320 por defecto, asi que un numero no
  // demuestra que nadie haya puesto la tasa; solo la fecha lo demuestra.
  if (tasa == null || tasa <= 0 || cuando == null) {
    return TasaDeLaMirada.no(
      '$quien no tiene tasa de cambio todavía: los importes sólo se pueden ver '
      'en USD.',
    );
  }

  // TASA VIEJA: SE ENSEÑA, CON AVISO. Quien decide si esta pasada es Accesos —son
  // 24 h alli— y aqui solo se pinta lo que dijo. Una tasa de ayer convierte con
  // un error pequeño; sin ninguna no se puede cotizar nada.
  final fresca = suya.cupRateFresca ?? true;
  return TasaDeLaMirada.hay(
    cupPorUsd: tasa,
    traidoAt: cuando,
    fuente: suya.cupRateFuente,
    fresca: fresca,
    aviso: fresca
        ? null
        : 'La tasa es del ${_fechaCorta(cuando)} y puede estar desfasada.',
  );
});

/// d/m/aaaa, sin ceros a la izquierda: el mismo formato que pone la API.
String _fechaCorta(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// La moneda en la que se PINTAN los importes. Los datos se guardan en USD
/// siempre y el CUP se calcula al pintarlo; guardar los dos seria tener dos
/// verdades que se separan en cuanto se mueva la tasa.
class MonedaMirada extends Notifier<String> {
  @override
  String build() => 'USD';

  void mirar(String codigo) {
    state = codigo;
    // Se recuerda igual que la sucursal, y por lo mismo: quien trabaja en CUP
    // trabaja en CUP todos los dias, y volver a USD en cada arranque es hacerle
    // tocar el selector cada manana. Sin esperarlo — ver `SucursalMirada`.
    unawaited(_guardar(codigo));
  }

  /// Vuelve a poner la moneda de la ultima vez. Si la sucursal de ahora no tiene
  /// tasa, [monedaEfectivaProvider] la cae a USD sola: esto recuerda la
  /// ELECCION, no fuerza la conversion.
  Future<void> restaurar() async {
    try {
      final guardada = await ref
          .read(baseProvider)
          .preferencia(ClaveDePreferencia.monedaMirada);
      if (guardada != null) state = guardada;
    } on Object catch (e) {
      Registro.aviso('no se pudo recordar la moneda: $e');
    }
  }

  Future<void> _guardar(String codigo) async {
    try {
      await ref
          .read(baseProvider)
          .anotarPreferencia(ClaveDePreferencia.monedaMirada, codigo);
    } on Object catch (e) {
      Registro.aviso('no se pudo anotar la moneda: $e');
    }
  }
}

final monedaMiradaProvider = NotifierProvider<MonedaMirada, String>(
  MonedaMirada.new,
);

/// La moneda que DE VERDAD se puede pintar.
///
/// Es [monedaMiradaProvider] con un respaldo: si estaba puesto CUP y se cambia a
/// una sucursal sin tasa, se cae a USD. La eleccion se queda guardada al cambiar
/// de sucursal, asi que sin esto se seguiria pidiendo CUP y se convertiria con
/// una tasa que no existe — todos los importes en cero o en NaN, que es peor que
/// verlos en dolares.
final monedaEfectivaProvider = Provider<String>((ref) {
  final elegida = ref.watch(monedaMiradaProvider);
  if (elegida == 'USD') return 'USD';
  return ref.watch(tasaDeLaMiradaProvider).hayCup ? elegida : 'USD';
});

/// Cuantas consultas hay en vuelo. Es un CONTADOR y no un booleano por lo mismo
/// que el bloqueo de scroll del cajon se lleva por contador: con dos ciclos
/// solapados, el primero en terminar apagaria el giro mientras el segundo sigue
/// trabajando, y la barra diria «al dia» con la bajada a medias.
class EnVuelo extends Notifier<int> {
  @override
  int build() => 0;

  void empieza() => state = state + 1;

  void termina() => state = state > 0 ? state - 1 : 0;
}

final enVueloProvider = NotifierProvider<EnVuelo, int>(EnVuelo.new);

/// El giro y `actualizando…` de la barra superior (pliego §8.2).
final actualizandoProvider = Provider<bool>(
  (ref) => ref.watch(enVueloProvider) > 0,
);

/// DE QUE HORA ES LA COPIA ENTERA: la bajada **mas vieja** de las nueve
/// colecciones.
///
/// **Ya NO es lo que mide la franja de arriba** — 01/10/2026. Lo era, y dentro de
/// las nueve va `almacenes`, que se refresca sola una vez por hora a proposito:
/// la franja decia «Datos de las 8:46» toda la manana encima de un Tablero al dia
/// a las 9:07. Ahora cada pantalla declara lo suyo
/// (`PantallaRegistrada.colecciones`) y la franja se mide contra eso.
///
/// Esto se queda, y con su sitio: lo miran el **Panel** y **Reportes**, donde la
/// pregunta de verdad es «¿le falta algo a este aparato?» —de eso sale si hay que
/// traer el dia antes de salir a la calle—, y el cajon de traer el dia para
/// repintarse cuando llega la bajada. Ahi manda la peor de todas, y es correcto.
final frescuraGlobalProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(frescuraProvider).laMasVieja(),
);

/// EL CÓDIGO de la sucursal elegida en la barra de arriba, o `null` si está en
/// «Todas» (o si las sucursales todavía no han bajado).
///
/// [sucursalMiradaProvider] guarda el **id** de la sucursal, y media aplicación
/// trabaja con su **código** (`branches.external_id`: `CAM`, `STG`…), que es el
/// que usan Accesos, los almacenes y los clientes. Traducirlo estaba repetido a
/// mano en cada sitio que lo necesitaba, y donde faltaba no fallaba nada: la
/// pantalla se quedaba mirando otra sucursal.
///
/// Eso es justo lo que pasó el 29/09/2026 en Almacenes. Con **Santiago** elegido
/// arriba, la pantalla enseñaba los almacenes de **Camagüey**: su selector
/// interno arrancaba vacío y caía en «el primero de la lista», y la lista, para
/// quien ve las ocho, viene con las ocho —`GET /api/almacenes` las devuelve
/// todas a propósito, para que al cambiar de sucursal el aparato no se quede sin
/// copia—. Nadie mentía: la pantalla, simplemente, no miraba la barra.
///
/// Y no es cosmético. El domicilio se cobra por la distancia DESDE el almacén:
/// editar ahí es editar el punto de cobro de otra provincia.
///
/// Sale de la base local, como [sucursalesProvider], para que valga sin conexión.
final codigoDeLaSucursalMiradaProvider = Provider<String?>((ref) {
  final id = ref.watch(sucursalMiradaProvider);
  if (id == null) return null;
  final sucursales = ref.watch(sucursalesProvider).value;
  if (sucursales == null) return null;
  final suya = sucursales.firstWhereOrNull((s) => s.id == id);
  final codigo = suya?.externalId?.trim();
  // Una sucursal sin `external_id` no se traduce, y **no se adivina**: se dice
  // que no hay código. Quien llame decidirá; lo que no puede es recibir el de
  // otra.
  return (codigo == null || codigo.isEmpty) ? null : codigo;
});
