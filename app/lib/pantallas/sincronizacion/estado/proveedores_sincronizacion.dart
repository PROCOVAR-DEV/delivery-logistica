import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../datos/panel_sincronizacion.dart';
import '../datos/repositorio_sincronizacion.dart';
import '../../../nucleo/refresco_en_vivo.dart';

final repositorioSincronizacionProvider = Provider<RepositorioSincronizacion>(
  (ref) => RepositorioSincronizacion(ref.watch(clienteSyncProvider)),
);

/// Una lectura del panel, **con la hora a la que se leyo**.
///
/// La hora va pegada al dato y no se coge al pintar: si se cogiera al pintar,
/// una pantalla abierta desde ayer diria «leido a las 09:12» de hoy con los
/// numeros de ayer. Eso es justo la clase de mentira que esta pantalla no puede
/// contar.
class LecturaDelPanel {
  const LecturaDelPanel(this.estado, this.leidoA);

  final EstadoDelSincronizador estado;
  final DateTime leidoA;
}

/// El estado del sincronizador. Es una peticion y no un stream sobre la base
/// **porque aqui no hay base**: lo que se ve es lo que el servidor sabe ahora
/// mismo, o no se ve.
///
/// `autoDispose` para que al salir de la pantalla no quede una lectura vieja
/// guardada que la proxima visita ensene un instante como si fuera de ahora.
final estadoDelSincronizadorProvider =
    FutureProvider.autoDispose<LecturaDelPanel>((ref) async {
      // Al cambiar de sucursal en la barra se vuelve a pedir. El alcance lo
      // cierra el servidor; esto solo estrecha, y solo si quien pregunta es el
      // Super Admin.
      // Y AL VOLVER DE UNA DESCONEXION SE VUELVE A PEDIR — 29/09/2026.
      //
      // Esta pantalla pide al sincronizador por RED y no tiene temporizador: lo
      // unico que la refresca es el boton de recargar. O sea el mismo agujero
      // que ya costo una vuelta con Vehiculos y Almacenes el 17/09/2026 — y
      // aqui duele mas, porque es **la pantalla que se abre justamente para ver
      // si algo esta entrando**. Quedarse con una foto de hace un rato en esa
      // pregunta es contestar que no entra nada cuando si entra, o al reves.
      //
      // No se le suma ningun tipo del servidor: lo que esta pantalla mira no lo
      // publica el canal. Lo que si hace falta es enterarse de que estuvimos
      // desconectados, que es lo que `refrescarConElAviso` anade siempre.
      refrescarConElAviso(ref, const <String>[]);

      final sucursal = ref.watch(sucursalMiradaProvider);
      final reloj = ref.watch(relojProvider);
      final estado = await ref
          .watch(repositorioSincronizacionProvider)
          .leer(sucursal: sucursal);
      return LecturaDelPanel(estado, reloj());
    });
