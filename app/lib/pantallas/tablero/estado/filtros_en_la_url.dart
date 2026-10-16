import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'proveedores.dart';

/// Lo que salió de leer la direccion: los filtros y lo que se quedó fuera.
///
/// El mismo par que en Pedidos (`pantallas/pedidos/datos/filtros_en_la_url.dart`),
/// y por el mismo motivo: ver [FiltrosEnLaUrl.leer].
class LecturaDeLaUrl {
  const LecturaDeLaUrl(this.filtros, this.noSePudieron);

  final FiltrosSinColocar filtros;

  /// `clave=valor`, literal, de cada filtro que venia en la direccion y no se
  /// pudo aplicar. Vacia cuando todo entro, que es lo normal.
  final List<String> noSePudieron;

  bool get todoEntro => noSePudieron.isEmpty;
}

/// LOS FILTROS VIVEN EN LA DIRECCION.
///
/// Es el contrato de la casa (`navegacion/pantalla_registrada.dart`) y aqui
/// vale igual que en Pedidos: en web, un logistico manda «mira estos, los de
/// Songo a menos de 10 km» pegando un enlace, y el enlace tiene que llevar al
/// mismo tablero. Guardar el filtro sólo en memoria convierte eso en una
/// explicacion por teléfono.
///
/// ## Y LO QUE NO SE PUEDE APLICAR, SE DICE — 24/09/2026
///
/// Esto leia la direccion con `DateTime.tryParse` y `double.tryParse` a pelo, y
/// **lo que no se entendia se tiraba callando**:
///
///  * `?dia=31-12-2026` —una fecha mal escrita, que es como se escribe una fecha
///    en Cuba— dejaba el tablero **sin acotar por dia** y nada lo decia. El que
///    manda el enlace ve el dia de ayer y el que lo abre ve los 300 de la
///    semana, y los dos creen que miran lo mismo.
///  * `?kmMax=NaN`, `?kmMax=-5` y `?kmMax=Infinity` pasaban enteros. Un `NaN`
///    no es igual ni a si mismo, asi que **ninguna comparacion lo deja pasar**:
///    la columna sale vacia y se lee como «no hay nada que colocar», que es el
///    cero creible y equivocado del §4.
///  * `?cobro=quizas` se convertia en «los dos» sin decir nada, o sea en un
///    filtro que el enlace pedia y no estaba puesto.
///
/// Y EL 31 DE FEBRERO SI LO TRAGA `DateTime.tryParse`: `'1900-02-31'` no falla,
/// **desborda** y devuelve el 3 de marzo de 1900. Una fecha imposible se
/// convertia en un dia de verdad que nadie pidio, y el tablero salia acotado por
/// él. Se comprueba que lo que volvió es lo que se escribió.
///
/// Por eso [leer] devuelve DOS cosas: los filtros que si se pudieron aplicar y
/// **la lista literal de los que no**, con su clave y su valor tal como venian.
/// La pantalla los pinta encima del conteo (`vista/pantalla_tablero.dart`).
/// Nada se descarta en silencio (`CLAUDE.md` §4).
///
/// ## Lo que NO entra
///
/// Una clave que no conocemos. `?utm_source=whatsapp` no es un filtro fallido,
/// es ruido de un enlace pegado por WhatsApp, y avisar de eso seria el aviso que
/// sale siempre y deja de leerse (`CLAUDE.md` §3-quinquies).
abstract final class FiltrosEnLaUrl {
  static const camino = '/tablero';

  /// Las claves. Aqui arriba y no repartidas: leer y escribir tienen que usar
  /// las mismas o un enlace hecho por la pantalla no lo entenderia la pantalla.
  static const claveQ = 'q';
  static const claveMunicipio = 'municipio';
  static const claveVendedor = 'vendedor';
  static const claveDesde = 'desde';
  static const claveHasta = 'hasta';

  /// El dia suelto de antes del rango (issue 13 de Amado, 15/10/2026). Ya no se
  /// escribe, pero un enlace viejo con `?dia=` sigue llevando a ese dia: se lee
  /// como `desde` = `hasta` = ese dia.
  static const claveDia = 'dia';
  static const claveKmMax = 'kmMax';
  static const claveCobro = 'cobro';

  /// El aviso de la franja, sin la lista. Literal aqui para que la prueba busque
  /// lo que se lee en pantalla.
  static const noSePudieronAplicar =
      'Este enlace traía filtros que no se pudieron aplicar';
  static const yPorEsoLaListaNoEstaAcotada =
      'La lista que estás viendo NO está acotada por ellos.';

  /// [vendedores] son los `vendedor=` de la dirección, TODOS (`vendedor=Ana&vendedor=Luis`):
  /// un `Map<String, String>` se queda con uno solo. Sin ellos se lee el de
  /// `parametros`, que es el enlace de antes de que fuera de varios (issue 18 de
  /// Amado, 16/10/2026) y sigue valiendo.
  /// Lo que lee la pantalla: los `vendedor=` salen de TODOS los de la dirección.
  static LecturaDeLaUrl leerDeUri(Uri uri) => leer(
    uri.queryParameters,
    vendedores: uri.queryParametersAll[claveVendedor],
  );

  static LecturaDeLaUrl leer(
    Map<String, String> parametros, {
    List<String>? vendedores,
  }) {
    final fuera = <String>[];

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
      // Y el 31 de febrero SI lo traga: desborda al 3 de marzo. Lo unico que lo
      // caza es comprobar que lo que volvio es lo que se escribio.
      final comoSeEscribio =
          '${_cuatro(d.year)}-${_dos(d.month)}-${_dos(d.day)}';
      if (!crudo.startsWith(comoSeEscribio)) {
        fuera.add('$clave=$crudo');
        return null;
      }
      return DateTime(d.year, d.month, d.day);
    }

    final diaViejo = fecha(claveDia);

    double? kmMax() {
      final crudo = parametros[claveKmMax];
      if (crudo == null || crudo.isEmpty) return null;
      final km = double.tryParse(crudo);
      // `NaN` e `Infinity` los parsea `double.tryParse` sin rechistar, y un
      // negativo tambien. Los tres dejan la columna vacia sin una palabra.
      if (km == null || km.isNaN || !km.isFinite || km < 0) {
        fuera.add('$claveKmMax=$crudo');
        return null;
      }
      return km;
    }

    // `cobro=si` / `cobro=no`. Sin el parametro son los dos, que es lo que
    // significa `null` — y por eso NO se lee como un booleano suelto: un `false`
    // por defecto convertiria «todos» en «sin cobro» al abrir un enlace viejo.
    bool? cobro() {
      if (!parametros.containsKey(claveCobro)) return null;
      final crudo = parametros[claveCobro] ?? '';
      if (crudo == 'si') return true;
      if (crudo == 'no') return false;
      fuera.add('$claveCobro=$crudo');
      return null;
    }

    return LecturaDeLaUrl(
      FiltrosSinColocar(
        q: parametros[claveQ],
        municipio: parametros[claveMunicipio],
        vendedores: _vendedores(vendedores ?? [?parametros[claveVendedor]]),
        desde: fecha(claveDesde) ?? diaViejo,
        hasta: fecha(claveHasta) ?? diaViejo,
        kmMax: kmMax(),
        conCobroDeDomicilio: cobro(),
      ),
      fuera,
    );
  }

  /// Sin vacíos ni repetidos, y en el orden en que venían.
  static List<String> _vendedores(List<String> crudos) => [
    for (final v
        in crudos.map((v) => v.trim()).where((v) => v.isNotEmpty).toSet())
      v,
  ];

  /// Un `vendedor` repetido por cada uno (`Uri` lo escribe así si el valor es una
  /// lista), así que un nombre con coma viaja entero.
  static Map<String, Object> escribir(FiltrosSinColocar f) {
    final km = f.kmMax;
    return <String, Object>{
      if (f.q != null && f.q!.trim().isNotEmpty) claveQ: f.q!.trim(),
      if (f.municipio != null) claveMunicipio: f.municipio!,
      if (f.vendedores.isNotEmpty) claveVendedor: f.vendedores,
      if (f.desde != null) claveDesde: _dia(f.desde!),
      if (f.hasta != null) claveHasta: _dia(f.hasta!),
      if (km != null) claveKmMax: '$km',
      if (f.conCobroDeDomicilio != null)
        claveCobro: f.conCobroDeDomicilio! ? 'si' : 'no',
    };
  }

  static bool iguales(FiltrosSinColocar a, FiltrosSinColocar b) =>
      escribir(a).toString() == escribir(b).toString();

  /// Pone los filtros **en los dos sitios**: el provider, que es lo que lee la
  /// consulta, y la direccion, que es lo que se puede mandar.
  ///
  /// Si no hay enrutador —un test de widget que pinta la pantalla suelta— se
  /// queda sólo con el provider en vez de reventar: la pantalla tiene que poder
  /// probarse sin arrastrar media aplicacion.
  static void poner(
    BuildContext contexto,
    WidgetRef ref,
    FiltrosSinColocar filtros,
  ) {
    ref.read(filtrosTableroProvider.notifier).poner(filtros);
    if (GoRouter.maybeOf(contexto) == null) return;
    contexto.go(
      Uri(path: camino, queryParameters: escribir(filtros)).toString(),
    );
  }

  static String _dia(DateTime d) =>
      '${_cuatro(d.year)}-${_dos(d.month)}-${_dos(d.day)}';

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static String _cuatro(int n) => n.toString().padLeft(4, '0');
}
