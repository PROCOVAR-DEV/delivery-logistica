import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/refresco_en_vivo.dart';
import '../../revision/estado/proveedores_revision.dart'
    show clienteDeRevisionProvider;
import '../../sincronizacion/datos/panel_sincronizacion.dart';
import '../../sincronizacion/datos/repositorio_sincronizacion.dart';

/// Lo que el sincronizador sabe de los aparatos, leído en vivo. Es el mismo `GET /sync/estado` del panel de Sincronización, pero con el
/// cliente de la bandeja de revisión: en el navegador va con el Bearer de `/api/me` (la web no tiene cola ni aparato propio, pero un
/// administrador de oficina sí puede MIRAR la actividad de los aparatos), y en la APK y el escritorio con la sesión de siempre.
///
/// Sin reintento automático: un 401/403 es definitivo y repetirlo es el bucle de los treinta `GET /sync/estado` del 22/09/2026.
final actividadDeAparatosProvider =
    FutureProvider.autoDispose<EstadoDelSincronizador>((ref) async {
      refrescarConElAviso(ref, const <String>[]);
      return RepositorioSincronizacion(ref.watch(clienteDeRevisionProvider))
          .leer();
    }, retry: (_, _) => null);
