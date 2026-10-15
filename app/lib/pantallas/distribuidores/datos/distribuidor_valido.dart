import '../../../nucleo/base/base.dart';

/// El «no» de asignar a una ruta a quien ya no esta en activo, LETRA POR LETRA el del
/// servidor (`msgDistribuidorRetirado`, `api/internal/api/distribuidores.go`). Sin
/// senal lo dice el aparato y con ella la nube: si no se leen igual, el mismo rechazo
/// ensena dos idiomas (`CLAUDE.md` §3-quinquies).
const msgDistribuidorRetirado =
    'El distribuidor está retirado y no se puede asignar a una ruta.';

/// Un distribuidor que no se puede poner en una ruta, con las palabras del servidor.
/// Quien llama la traduce a SU rechazo (`RechazoLocal` en Rutas, `RechazoDelTablero`
/// en el Tablero), que son dos clases distintas con la misma funcion.
class DistribuidorNoValido implements Exception {
  const DistribuidorNoValido(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// EL DISTRIBUIDOR DE UNA RUTA NUEVA, comprobado contra lo que el aparato tiene
/// bajado. Devuelve `null` si no se pidio ninguno (vacio tambien es «ninguno»).
///
/// Las tres cosas y en este orden, que son las del servidor (`distribuidorDeLaRuta`
/// en `api/internal/api/distribuidores.go`) y con sus mismas palabras:
///
///  1. que EXISTA aqui: un id que el aparato no conoce es el de otra sucursal, el de
///     uno borrado o el de uno que aun no ha bajado, y las tres se dicen igual
///     —«No existe»— porque un aparato acotado no puede distinguirlas (y decir «es de
///     otra sucursal» seria contar algo de ella);
///  2. que sea de la sucursal de la RUTA (solo puede fallar si el aparato ve varias);
///  3. que siga en ACTIVO.
///
/// No es una ayuda de pantalla: el selector solo ofrece a los que cumplen las tres.
/// Es para que una ruta que el selector no deja armar tampoco se arme llamando a
/// `armar` a mano, para atrapar al que se retiro entre que se eligio y se pulso
/// «Generar», y para que el «no» salga AHORA y no horas despues en la bandeja.
Future<Distribuidor?> distribuidorParaUnaRuta(
  BaseLocal base, {
  required String? id,
  required String? sucursalDeLaRuta,
}) async {
  final pedido = id?.trim() ?? '';
  if (pedido.isEmpty) return null;
  final d = await (base.select(
    base.distribuidores,
  )..where((x) => x.id.equals(pedido))).getSingleOrNull();
  if (d == null) throw DistribuidorNoValido("No existe el distribuidor '$pedido'");
  // Como el servidor (`distribuidorDeLaRuta`): sin sucursal de la ruta, o de
  // otra, no vale. Falla cerrado; antes dejaba pasar el nulo y el «no» llegaba
  // horas despues a la bandeja.
  if (d.branchId == null || d.branchId != sucursalDeLaRuta) {
    throw DistribuidorNoValido(
      "El distribuidor '$pedido' no es de la sucursal de esta ruta",
    );
  }
  if (!d.activo) throw const DistribuidorNoValido(msgDistribuidorRetirado);
  return d;
}
