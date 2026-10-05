// LOS FILTROS DE PEDIDOS, EN LA DIRECCIÓN.
//
// Es el contrato de la casa, escrito en `navegacion/pantalla_registrada.dart`:
//
// > **Los filtros van en la URL** (`estado.uri.queryParameters`), que es lo que
// > hace que en web se pueda mandar un enlace a la lista ya filtrada. Lee de
// > ahí y escribe con `context.go(...)`; no guardes el filtro sólo en un
// > `State`.
//
// Pedidos no lo cumplía. Su `_construir` tiraba el `GoRouterState` entero y
// devolvía `const PantallaPedidos()`, y los nueve filtros vivían sólo en el
// `Notifier`. Lo que eso significa para quien está delante, y es lo que se
// arregla aquí:
//
//  * **Un enlace mentía.** `/orders?municipio=Centro` —el ejemplo que está
//    escrito tal cual en `nucleo/identidad/entrada_por_accesos.dart`— abría la
//    pantalla con TODOS los pedidos y sin una palabra que lo dijera. El que lo
//    mandó ve 3 y el que lo recibe ve 46, y los dos creen que miran lo mismo.
//  * **Recargar perdía el filtro.** F5 en la web devolvía la lista entera con
//    la barra de filtros en blanco: el propio caso que el encargo manda probar
//    («entrar por la URL de cada pantalla y recargar estando dentro»).
//
// ## Y lo que el servidor ignora, se DICE
//
// La QA de la API lo encontró por su lado: `?dia=31-12-2026` —una fecha mal
// escrita— el servidor la ignora y contesta con todos los días. Es la dirección
// segura y no va a cambiar. Pero entonces el agujero es de pantalla: si aquí se
// leyera la dirección y lo que no se entiende se tirara callando, la lista
// saldría sin acotar con el enlace diciendo que está acotada. Un resultado
// creíble y equivocado que ninguna pantalla desmiente, que es el fallo que Jose
// pone el primero.
//
// Por eso [LecturaDeLaUrl] devuelve DOS cosas: los filtros que sí se pudieron
// aplicar y **la lista literal de los que no**, con su clave y su valor tal
// como venían. La pantalla los pinta. Nada se descarta en silencio
// (`CLAUDE.md` §4).
//
// ## Qué se considera «no se pudo»
//
//  * un valor que no está entre los del filtro (`reparto=volando`);
//  * una fecha que no es una fecha (`desde=31-12-2026`, `hasta=1900-02-31`);
//  * un rango al revés (`desde` posterior a `hasta`): devuelve cero y parece
//    que no hubo pedidos;
//  * una página que no es un entero de 1 para arriba.
//
// Lo que NO entra: una clave que no conocemos. `?utm_source=whatsapp` no es un
// filtro fallido, es ruido de un enlace pegado, y avisar de eso sería el aviso
// que sale siempre y deja de leerse (`CLAUDE.md` §3-quinquies).

import 'filtros_pedidos.dart';

/// Lo que salió de leer la dirección: los filtros y lo que se quedó fuera.
class LecturaDeLaUrl {
  const LecturaDeLaUrl(this.filtros, this.noSePudieron);

  final FiltrosPedidos filtros;

  /// `clave=valor`, literal, de cada filtro que venía en la dirección y no se
  /// pudo aplicar. Vacía cuando todo entró, que es lo normal.
  final List<String> noSePudieron;

  bool get todoEntro => noSePudieron.isEmpty;
}

abstract final class FiltrosEnLaUrl {
  static const camino = '/orders';

  /// Las claves. Aquí arriba y no repartidas: leer y escribir tienen que usar
  /// las mismas o un enlace hecho por la pantalla no lo entendería la pantalla.
  static const claveQ = 'q';
  static const claveReparto = 'reparto';
  static const claveMunicipio = 'municipio';
  static const claveVendedor = 'vendedor';
  static const claveCotizado = 'cotizado';
  static const claveFactura = 'factura';
  static const claveArchivado = 'archivado';
  static const claveDesde = 'desde';
  static const claveHasta = 'hasta';

  /// LAS DOS FECHAS DE LA ENTREGA, que son otras. `desde`/`hasta` acotan por la
  /// fecha DEL PEDIDO; éstas por `delivered_at`. Las claves llevan el verbo
  /// delante justo para que no se confundan al leer un enlace pegado.
  static const claveEntregadoDesde = 'entregado_desde';
  static const claveEntregadoHasta = 'entregado_hasta';
  static const claveOrden = 'orden';
  static const clavePagina = 'pagina';

  /// El aviso de la franja, sin la lista. Literal aquí para que la prueba
  /// busque lo que se lee en pantalla.
  static const noSePudieronAplicar =
      'Este enlace traía filtros que no se pudieron aplicar';
  static const yPorEsoLaListaNoEstaAcotada =
      'La lista que estás viendo NO está acotada por ellos.';

  /// LEE LA DIRECCIÓN. Lo que no venga se queda como lo deja el arranque de
  /// [FiltrosPedidos], que es el acotado a lo que puede subir a un camión.
  ///
  /// Sin ningún parámetro devuelve exactamente ese arranque, así que abrir
  /// `/orders` a secas se comporta igual que antes de que esto existiera.
  static LecturaDeLaUrl leer(Map<String, String> parametros) {
    final fuera = <String>[];

    // `clave=` VACÍA NO ES «no venía»: es `cualquiera`, cuyo `param` es la
    // cadena vacía. Tratarlas igual rompía el viaje de ida y vuelta justo en el
    // caso de `Ver todos los pedidos` —`factura=` y `archivado=`—, que es el
    // enlace que uno manda cuando quiere que el otro lo vea TODO: se escribía
    // `?factura=` y al abrirlo volvía el acotado del arranque.
    T? deEnum<T>(String clave, Iterable<T> valores, String Function(T) param) {
      if (!parametros.containsKey(clave)) return null;
      final crudo = parametros[clave] ?? '';
      for (final v in valores) {
        if (param(v) == crudo) return v;
      }
      fuera.add('$clave=$crudo');
      return null;
    }

    DateTime? fecha(String clave) {
      final crudo = parametros[clave];
      if (crudo == null || crudo.isEmpty) return null;
      final d = DateTime.tryParse(crudo);
      if (d == null) {
        // `31-12-2026` no lo traga: devuelve `null`, que es lo que hay que
        // DECIR y no tirar.
        fuera.add('$clave=$crudo');
        return null;
      }
      // Y EL 31 DE FEBRERO SÍ LO TRAGA. `DateTime.tryParse('1900-02-31')` no
      // falla: **desborda** y devuelve el 3 de marzo. O sea que un filtro
      // imposible se convertía en un día de verdad que nadie pidió, y la lista
      // salía acotada por él sin que nada lo dijera. Se comprueba que lo que
      // volvió es lo que se escribió.
      final dia = DateTime(d.year, d.month, d.day);
      final comoSeEscribio = '${_dos4(d.year)}-${_dos(d.month)}-${_dos(d.day)}';
      if (!crudo.startsWith(comoSeEscribio)) {
        fuera.add('$clave=$crudo');
        return null;
      }
      return dia;
    }

    int? pagina() {
      final crudo = parametros[clavePagina];
      if (crudo == null || crudo.isEmpty) return null;
      final n = int.tryParse(crudo);
      // Cero, negativa o `abc`: `offset` negativo o una página que no existe.
      if (n == null || n < 1) {
        fuera.add('$clavePagina=$crudo');
        return null;
      }
      return n;
    }

    var desde = fecha(claveDesde);
    var hasta = fecha(claveHasta);
    // EL RANGO AL REVÉS SE DICE, NO SE ARREGLA A ESCONDIDAS. Darle la vuelta
    // sería enseñar unos pedidos que nadie pidió; aplicarlo tal cual devuelve
    // cero y se lee como «no hubo pedidos ese día».
    if (desde != null && hasta != null && desde.isAfter(hasta)) {
      fuera.add(
        '$claveDesde=${parametros[claveDesde]} > '
        '$claveHasta=${parametros[claveHasta]}',
      );
      desde = null;
      hasta = null;
    }

    // Y EL DE LA ENTREGA SE COMPRUEBA IGUAL, por separado. Son dos rangos
    // independientes: uno al revés no puede llevarse por delante al otro, que
    // sí se entendía.
    var entregadoDesde = fecha(claveEntregadoDesde);
    var entregadoHasta = fecha(claveEntregadoHasta);
    if (entregadoDesde != null &&
        entregadoHasta != null &&
        entregadoDesde.isAfter(entregadoHasta)) {
      fuera.add(
        '$claveEntregadoDesde=${parametros[claveEntregadoDesde]} > '
        '$claveEntregadoHasta=${parametros[claveEntregadoHasta]}',
      );
      entregadoDesde = null;
      entregadoHasta = null;
    }

    final base = const FiltrosPedidos();
    return LecturaDeLaUrl(
      FiltrosPedidos(
        q: parametros[claveQ]?.trim() ?? base.q,
        reparto:
            deEnum(claveReparto, RepartoFiltro.values, (v) => v.param) ??
            base.reparto,
        municipio: parametros[claveMunicipio] ?? base.municipio,
        vendedor: parametros[claveVendedor] ?? base.vendedor,
        cotizado:
            deEnum(claveCotizado, CotizadoFiltro.values, (v) => v.param) ??
            base.cotizado,
        factura:
            deEnum(claveFactura, FacturaFiltro.values, (v) => v.param) ??
            base.factura,
        archivado:
            deEnum(claveArchivado, ArchivadoFiltro.values, (v) => v.param) ??
            base.archivado,
        desde: desde,
        hasta: hasta,
        entregadoDesde: entregadoDesde,
        entregadoHasta: entregadoHasta,
        orden:
            deEnum(claveOrden, OrdenLocal.values, (v) => v.valor) ?? base.orden,
        pagina: pagina() ?? base.pagina,
      ),
      fuera,
    );
  }

  /// ESCRIBE LA DIRECCIÓN. Sólo lo que está puesto de verdad: un enlace con
  /// `archivado=0&factura=con_factura&orden=recientes&pagina=1` colgando es
  /// ilegible, y esos son los valores de arranque.
  ///
  /// **`factura` y `archivado` sí salen cuando no son los del arranque**, que
  /// es como se manda «mira también los archivados».
  static Map<String, String> escribir(FiltrosPedidos f) {
    const base = FiltrosPedidos();
    return <String, String>{
      if (f.q.trim().isNotEmpty) claveQ: f.q.trim(),
      if (f.reparto != base.reparto) claveReparto: f.reparto.param,
      if (f.municipio.isNotEmpty) claveMunicipio: f.municipio,
      if (f.vendedor.isNotEmpty) claveVendedor: f.vendedor,
      if (f.cotizado != base.cotizado) claveCotizado: f.cotizado.param,
      if (f.factura != base.factura) claveFactura: f.factura.param,
      if (f.archivado != base.archivado) claveArchivado: f.archivado.param,
      if (f.desde != null) claveDesde: _dia(f.desde!),
      if (f.hasta != null) claveHasta: _dia(f.hasta!),
      if (f.entregadoDesde != null)
        claveEntregadoDesde: _dia(f.entregadoDesde!),
      if (f.entregadoHasta != null)
        claveEntregadoHasta: _dia(f.entregadoHasta!),
      if (f.orden != base.orden) claveOrden: f.orden.valor,
      if (f.pagina != base.pagina) clavePagina: '${f.pagina}',
    };
  }

  /// La dirección entera, lista para `context.go`.
  static String direccion(FiltrosPedidos f) {
    final q = escribir(f);
    return q.isEmpty
        ? camino
        : Uri(path: camino, queryParameters: q).toString();
  }

  /// `cualquiera` se escribe con cadena vacía en su `param`, y una clave con
  /// valor vacío en la dirección se lee luego como «no venía». Son lo mismo, y
  /// por eso [escribir] las omite comparando contra el arranque y no contra la
  /// cadena.
  static String _dia(DateTime d) => '${d.year}-${_dos(d.month)}-${_dos(d.day)}';

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static String _dos4(int n) => n.toString().padLeft(4, '0');
}
