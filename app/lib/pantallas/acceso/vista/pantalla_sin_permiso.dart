import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../navegacion/aviso_de_version_nueva.dart'
    show abridorDeLaDescargaProvider;
import '../../../navegacion/portero.dart';
import '../../../nucleo/identidad/entrada_por_accesos.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/red/entorno.dart';

/// EL INICIO DE ACCESOS: `AUTH_URL` y su raíz, que es donde la persona ve las
/// aplicaciones a las que SÍ puede entrar (Jose, 08/10/2026: «a su inicio con la
/// ruta rápida»). Con barra final, sin importar cómo se pase `AUTH_URL`.
String get inicioDeAccesos {
  final base = Entorno.authUrl;
  return base.endsWith('/') ? base : '$base/';
}

/// Cuánto se espera en la web antes de irse sola a Accesos.
const segundosHastaAccesos = 3;

/// «NO TIENES PERMISO PARA ENTRAR A REPARTO».
///
/// A ella se llega desde CUALQUIER pantalla en cuanto la API contesta 403
/// `sin_permiso_reparto` (`InterceptorSesion`), también durante la carga
/// inicial. Solo entran ADMINISTRADOR, SUPER ADMIN, DESARROLLADOR y LOGISTICO.
///
///  * **Web**: se va sola a [inicioDeAccesos] a los [segundosHastaAccesos] s,
///    con un contador a la vista y el botón «Ir ahora a Accesos». La salida es
///    una navegación de verdad (`navegadorProvider`), como la del login único.
///  * **APK y escritorio**: no se va sola. «Ir a Accesos» abre el navegador del
///    sistema y «Cerrar sesión» sale como cualquier salida: **no borra la cola**
///    y, si hay apuntes sin subir, lo pregunta antes.
///
/// **No vuelve a lanzar la llamada que dio el 403**, ni se reevalúa sola: el
/// portero se queda en `sinPermiso` hasta que alguien entre de nuevo, así que no
/// hay bucle posible desde aquí. Todo el porqué, en `docs/sin-permiso.md`.
class PantallaSinPermiso extends ConsumerStatefulWidget {
  const PantallaSinPermiso({super.key});

  @override
  ConsumerState<PantallaSinPermiso> createState() => _PantallaSinPermisoState();
}

class _PantallaSinPermisoState extends ConsumerState<PantallaSinPermiso> {
  late final bool _enLaWeb = ref.read(entraPorAccesosProvider);

  Timer? _reloj;
  int _quedan = segundosHastaAccesos;

  /// Se fue (o se está yendo) a Accesos: ni el reloj ni un segundo toque mandan
  /// otra navegación encima.
  bool _yaFui = false;

  @override
  void initState() {
    super.initState();
    if (!_enLaWeb) return;
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_quedan > 1) {
        setState(() => _quedan--);
      } else {
        setState(() => _quedan = 0);
        _irAAccesos();
      }
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  void _irAAccesos() {
    if (_yaFui) return;
    _yaFui = true;
    _reloj?.cancel();
    ref.read(navegadorProvider).irA(inicioDeAccesos);
  }

  Future<void> _cerrarSesion() async {
    final pendientes = await ref.read(baseProvider).cuantosPendientes();
    if (!mounted) return;
    if (pendientes > 0) {
      // Lo mismo que el «Cerrar sesión» de la cuenta: salir NO borra la cola, y
      // lo que sí es verdad es que nadie ve ese trabajo hasta que suba.
      final sigue = await showDialog<bool>(
        context: context,
        builder: (contexto) => AlertDialog(
          title: const Text('Queda trabajo sin subir'),
          content: Text(
            'Hay $pendientes ${pendientes == 1 ? "apunte" : "apuntes"} sin '
            'subir al servidor. Salir NO los borra: se quedan en este aparato '
            'hasta que vuelvas a entrar.\n\nSuben cuando te den acceso a Reparto y '
            'vuelvas a entrar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(contexto).pop(false),
              child: const Text('Me quedo'),
            ),
            TextButton(
              onPressed: () => Navigator.of(contexto).pop(true),
              child: const Text('Salir de todos modos'),
            ),
          ],
        ),
      );
      if (sigue != true || !mounted) return;
    }
    await ref.read(porteroProvider).salir();
  }

  @override
  Widget build(BuildContext context) {
    final cuerpo = Tipos.texto(
      tamano: 14,
      color: Colores.tintaSuave,
      alto: 1.45,
    );
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Aire.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ámbar y no rojo: no es un fallo de quien llega ni de su
                // contraseña, es que su cuenta no tiene esta aplicación.
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colores.ambarFondo,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      size: 24,
                      color: Colores.ambar,
                    ),
                  ),
                ),
                const SizedBox(height: Aire.lg),
                Semantics(
                  header: true,
                  child: Text(
                    'No tienes permiso para entrar a Reparto',
                    textAlign: TextAlign.center,
                    style: Tipos.display(tamano: 22, color: Colores.tinta),
                  ),
                ),
                const SizedBox(height: Aire.md),
                Text(
                  'Reparto es para el personal de logística y la '
                  'administración. Si crees que es un error, pídele acceso a '
                  'un administrador.',
                  textAlign: TextAlign.center,
                  style: cuerpo,
                ),
                const SizedBox(height: Aire.xl),
                if (_enLaWeb) ...[
                  // SE ANUNCIA UNA VEZ, no cada segundo: el lector de pantalla dice
                  // que la página se va sola, y el contador visual queda fuera del
                  // árbol de accesibilidad (si no, anunciaría «3, 2, 1»).
                  Semantics(
                    liveRegion: true,
                    label: 'Te llevamos al inicio de Accesos en unos segundos',
                    child: ExcludeSemantics(
                      child: Text(
                        _quedan > 0
                            ? 'Te llevamos al inicio de Accesos en $_quedan s…'
                            : 'Yendo a Accesos…',
                        textAlign: TextAlign.center,
                        style: Tipos.texto(
                          tamano: 13,
                          peso: FontWeight.w600,
                          color: Colores.tinta,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Aire.md),
                  BotonPrincipal(
                    texto: 'Ir ahora a Accesos',
                    icono: Icons.arrow_forward,
                    iconoAlFinal: true,
                    alPulsar: _irAAccesos,
                  ),
                ] else ...[
                  BotonPrincipal(
                    texto: 'Ir a Accesos',
                    icono: Icons.open_in_new,
                    alPulsar: () => unawaited(
                      ref.read(abridorDeLaDescargaProvider)(inicioDeAccesos),
                    ),
                  ),
                  const SizedBox(height: Aire.md),
                  BotonDestructivo(
                    texto: 'Cerrar sesión',
                    icono: Icons.logout,
                    alPulsar: () => unawaited(_cerrarSesion()),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
