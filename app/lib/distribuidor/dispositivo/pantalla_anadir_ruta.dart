// «AGREGAR RUTA A MANO»: pegar el enlace que mando el logistico, o solo su codigo. Es el
// respaldo si abrir el enlace desde WhatsApp falla, y tambien la puerta de la app (no hay
// usuario ni contrasena): sin ninguna ruta asignada es lo unico que se ve.
//
// El formulario es uno solo y sale en tres sitios: la puerta, el menu y un CAJON desde
// «Mis rutas» (`abrirAgregarRutaAMano`), con y sin rutas.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../diseno/tema.dart';
import '../../navegacion/portero.dart' show porteroProvider;
import '../../nucleo/red/fallos.dart' show FalloDeRed;
import '../../pantallas/pedidos/vista/kit.dart';
import 'cliente_de_dispositivo.dart';
import 'proveedores_dispositivo.dart';

const textoSinRutas = 'Pide a tu logístico que te mande el enlace de tu ruta.';

const tituloAgregarRuta = 'Agregar ruta a mano';

const explicacionDelCodigo =
    'Es la parte final del enlace que te mandaron por WhatsApp. Si te mandaron '
    'https://reparto.procovar.cloud/r/AbC123xyz, el código es AbC123xyz. '
    'También puedes pegar el enlace completo.';

/// Abre el cajon de «Agregar ruta a mano».
Future<void> abrirAgregarRutaAMano(BuildContext contexto) => abrirCajon<void>(
  contexto,
  (_) => Cajon(
    titulo: tituloAgregarRuta,
    ancho: AnchoCajon.md,
    cuerpo: Builder(
      builder: (c) => Padding(
        padding: const EdgeInsets.all(16),
        child: FormularioDeRuta(alTerminar: () => Navigator.of(c).pop()),
      ),
    ),
  ),
);

class FormularioDeRuta extends ConsumerStatefulWidget {
  /// [enlaceInicial] viene de abrir un enlace con la app: se reclama solo.
  /// [alTerminar] se llama al conseguirlo; sin el, se va a «Mis rutas».
  const FormularioDeRuta({this.enlaceInicial, this.alTerminar, super.key});

  final String? enlaceInicial;
  final VoidCallback? alTerminar;

  @override
  ConsumerState<FormularioDeRuta> createState() => _FormularioDeRutaState();
}

class _FormularioDeRutaState extends ConsumerState<FormularioDeRuta> {
  final _enlace = TextEditingController();
  String? _error;
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    final inicial = widget.enlaceInicial;
    if (inicial != null && inicial.isNotEmpty) {
      _enlace.text = inicial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _anadir());
    }
  }

  @override
  void dispose() {
    _enlace.dispose();
    super.dispose();
  }

  Future<void> _pegar() async {
    final datos = await Clipboard.getData(Clipboard.kTextPlain);
    if (datos?.text != null) setState(() => _enlace.text = datos!.text!.trim());
  }

  Future<void> _anadir() async {
    if (_trabajando) return;
    setState(() {
      _trabajando = true;
      _error = null;
    });
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final enrutador = GoRouter.maybeOf(context);
    try {
      await ref.read(anadirRutaProvider).anadir(_enlace.text);
      mensajero?.showSnackBar(const SnackBar(content: Text('Ruta agregada.')));
      _enlace.clear();
      if (widget.alTerminar != null) {
        widget.alTerminar!();
      } else {
        enrutador?.go('/routes');
      }
    } on EnlaceRechazado catch (no) {
      if (mounted) setState(() => _error = no.mensaje);
    } on FalloDeRed {
      if (mounted) {
        setState(
          () => _error =
              'Hace falta conexión para agregar una ruta. Inténtalo con señal.',
        );
      }
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        explicacionDelCodigo,
        key: ValueKey('anadir-ruta-explicacion'),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('anadir-ruta-enlace'),
        controller: _enlace,
        enabled: !_trabajando,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'Código o enlace de la ruta',
          hintText: 'AbC123xyz',
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _error!,
            key: const ValueKey('anadir-ruta-error'),
            style: TextStyle(color: Colores.rojo),
          ),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('anadir-ruta-pegar'),
        onPressed: _trabajando ? null : _pegar,
        icon: const Icon(Icons.content_paste),
        label: const Text('Pegar del portapapeles'),
      ),
      const SizedBox(height: 8),
      BotonPrincipal(
        key: const ValueKey('anadir-ruta-anadir'),
        icono: Icons.add_road,
        texto: _trabajando ? 'Agregando…' : 'Agregar ruta',
        alPulsar: _trabajando ? null : _anadir,
      ),
    ],
  );
}

/// La puerta de la app y la pantalla del menu.
class PantallaAnadirRuta extends ConsumerWidget {
  const PantallaAnadirRuta({this.enlaceInicial, super.key});

  final String? enlaceInicial;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Reparto Distribuidor',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              // Por que se esta en la puerta: p. ej. «Este teléfono fue desvinculado…».
              ListenableBuilder(
                listenable: ref.watch(porteroProvider),
                builder: (_, _) {
                  final aviso = ref.read(porteroProvider).avisoDeSesion;
                  return aviso == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            aviso,
                            key: const ValueKey('anadir-ruta-aviso'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colores.ambar),
                          ),
                        );
                },
              ),
              const Text(
                textoSinRutas,
                key: ValueKey('anadir-ruta-texto'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FormularioDeRuta(enlaceInicial: enlaceInicial),
            ],
          ),
        ),
      ),
    ),
  );
}
