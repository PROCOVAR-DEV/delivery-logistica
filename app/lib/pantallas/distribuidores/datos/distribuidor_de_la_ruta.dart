import '../../../nucleo/base/base.dart';

/// Lo que se escribe en una ruta que no tiene distribuidor. NO es un hueco: es una
/// ruta historica (anterior al 14/10/2026) o armada sin elegir uno, y se dice con
/// esas palabras en vez de dejar un renglon en blanco o inventar a nadie.
const textoSinDistribuidor = 'Sin distribuidor';

/// Lo que se escribe cuando la ruta SI tiene un distribuidor y este aparato no
/// tiene su nombre. Es la bajada que no ha llegado (o la que no trajo la
/// coleccion): decir «Sin distribuidor» seria afirmar lo contrario de lo que sabe
/// el servidor, que es el numero creible y equivocado de siempre con otra cara.
const textoDistribuidorSinBajar = 'Distribuidor sin descargar';

/// QUIEN REPARTE UNA RUTA, en una frase corta para la lista y el detalle.
///
/// [id] es `routes.distribuidor_id`; [conocidos] es lo que el aparato tiene de
/// `distribuidores`, por id. Tres respuestas y ninguna se confunde con otra:
///
///  * sin id -> [textoSinDistribuidor];
///  * con id y con su fila -> el nombre (y « · retirado» si ya no esta en activo:
///    sigue siendo quien reparto esa ruta);
///  * con id y sin su fila -> [textoDistribuidorSinBajar].
String textoDelDistribuidor(String? id, Map<String, Distribuidor> conocidos) {
  if (id == null || id.isEmpty) return textoSinDistribuidor;
  final d = conocidos[id];
  if (d == null) return textoDistribuidorSinBajar;
  return d.activo ? d.nombre : '${d.nombre} · retirado';
}

/// QUIEN REPARTE, PARA LAS HOJAS IMPRESAS (pre y post-despacho): su nombre, o
/// vacio si la ruta no tiene o el aparato no lo ha bajado. En un papel que se
/// firma no se imprime «sin distribuidor» ni se inventa nadie.
///
/// Se lee de la base EN SECO y por id, no de `distribuidoresDeLaBarraProvider`:
/// un `StreamProvider` que nadie observa da `.value == null` y la hoja salia sin
/// el distribuidor (el cierre abierto sin pasar por el detalle). Lo atan
/// `test/pantallas/rutas/el_distribuidor_va_en_las_hojas_test.dart`.
Future<String> nombreDelDistribuidorParaLaHoja(BaseLocal base, String? id) async {
  if (id == null || id.isEmpty) return '';
  final d = await (base.select(
    base.distribuidores,
  )..where((x) => x.id.equals(id))).getSingleOrNull();
  return d?.nombre ?? '';
}
