// «ENVIAR A DISTRIBUIDOR», dentro del detalle de la ruta.
//
// Sustituye al enlace de Google Maps (04/11/2026): el logístico le manda al distribuidor, por WhatsApp, un ENLACE por ruta
// (`https://reparto.procovar.cloud/r/<token>`). El teléfono lo reclama y esa ruta queda asignada a ESE teléfono.
//
// ## Siempre en vivo
//
// El enlace lo crea y lo guarda el servidor, también cuando esto corre en la APK o en Windows: una copia local de un enlace que ya
// se soltó mandaría al distribuidor a una ruta que ya no es suya. Sin red, se dice («Sin conexión con el servidor.»); no se finge.
//
// ## Qué dice y qué hace
//
//  * una línea con el ESTADO: «Sin enlace», «Sin reclamar» o «Asignada a <teléfono> el <fecha>»;
//  * WhatsApp / Compartir / Copiar: crean u obtienen el enlace (`POST`, que devuelve el que ya hay) y mandan el mensaje corto;
//  * «Soltar y mandar a otro teléfono» (con confirmación): `renovar`, que suelta la ruta de su teléfono y da un enlace nuevo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart' show EstadoRuta;
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../pedidos/datos/formato.dart';
import '../../rutas/datos/abrir_y_compartir.dart';
import '../../rutas/datos/enlace_de_la_ruta.dart';
import '../../rutas/datos/repositorio_rutas.dart';
import '../datos/api_distribucion.dart';
import '../datos/modelos.dart';

abstract final class TextosDeEnviar {
  static const titulo = 'Enviar a distribuidor';
  static const sinEnlace =
      'Sin enlace: todavía no se le ha mandado esta ruta a nadie.';
  static const sinReclamar =
      'Sin reclamar: el enlace está creado, pero ningún teléfono lo ha abierto todavía.';
  static String asignada(String? telefono, DateTime? cuando) =>
      'Asignada a ${telefono ?? 'un teléfono'}'
      '${cuando == null ? '' : ' el ${fechaYHora(cuando)}'}.';
  static const rutaSinSubir =
      'Esta ruta todavía no ha subido al servidor. Conecta el aparato para que se sincronice y luego envíala.';
  static const rutaCerrada =
      'La ruta ya está cerrada: no se puede enviar a un distribuidor.';
  static const soltar = 'Soltar y mandar a otro teléfono';
  static const copiado = 'Copiado. Ya se puede pegar en un chat.';
  static const noSeAbrioWhatsApp =
      'No se pudo abrir WhatsApp. Comprueba que está instalado; mientras tanto, «Copiar» deja el mensaje en el portapapeles.';
  static const noSeCompartio =
      'Este aparato no ofreció ningún modo de compartir. Con «Copiar» el mensaje queda en el portapapeles.';
  static const soltada =
      'Ruta soltada. Ya puedes mandar el enlace nuevo a otro teléfono.';
}

const claveDeEnviarWhatsApp = ValueKey('enviar-whatsapp');
const claveDeEnviarCompartir = ValueKey('enviar-compartir');
const claveDeEnviarCopiar = ValueKey('enviar-copiar');
const claveDeEstadoDelEnlace = ValueKey('enviar-estado-del-enlace');
const claveDeSoltarLaRuta = ValueKey('enviar-soltar');
const claveDeConfirmarSoltar = ValueKey('enviar-confirmar-soltar');
const claveDeAvisoDelEnlace = ValueKey('enviar-aviso');

final enlaceDeLaRutaProvider = FutureProvider.autoDispose
    .family<EnlaceDeRuta, String>(
      (ref, rutaId) => ref.watch(apiDistribucionProvider).enlaceDe(rutaId),
    );

class EnviarADistribuidor extends ConsumerStatefulWidget {
  const EnviarADistribuidor({required this.ruta, super.key});

  final RutaConTodo ruta;

  @override
  ConsumerState<EnviarADistribuidor> createState() =>
      _EnviarADistribuidorState();
}

class _EnviarADistribuidorState extends ConsumerState<EnviarADistribuidor> {
  bool _ocupado = false;

  /// Lo último que salió mal, con su motivo, a la vista (no un aviso que se va solo).
  String? _fallo;

  String get _rutaId => widget.ruta.ruta.id;

  void _decir(String texto) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(texto), duration: const Duration(seconds: 5)),
  );

  /// Crea o trae el enlace y arma el mensaje. `null` = no se pudo (y [_fallo] dice por qué).
  Future<String?> _mensaje() async {
    setState(() {
      _ocupado = true;
      _fallo = null;
    });
    try {
      final enlace = await ref
          .read(apiDistribucionProvider)
          .crearEnlace(_rutaId);
      final url = enlace.url;
      if (url == null) {
        if (mounted) {
          setState(
            () => _fallo = 'El servidor no devolvió el enlace de la ruta.',
          );
        }
        return null;
      }
      ref.invalidate(enlaceDeLaRutaProvider(_rutaId));
      final r = widget.ruta.ruta;
      return mensajeParaElDistribuidor(
        codigo: r.routeCode ?? r.id,
        nombre: r.name,
        fecha: fechaCorta(r.deliveryDate),
        paradas: widget.ruta.paradas.length,
        url: url,
      );
    } on Object catch (e) {
      if (mounted) setState(() => _fallo = motivoDelFallo(e));
      return null;
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _whatsapp() async {
    final mensaje = await _mensaje();
    if (mensaje == null || !mounted) return;
    if (!await ref
        .read(abrirYCompartirProvider)
        .abrir(enlaceDeWhatsApp(mensaje))) {
      _decir(TextosDeEnviar.noSeAbrioWhatsApp);
    }
  }

  Future<void> _compartir() async {
    final mensaje = await _mensaje();
    if (mensaje == null || !mounted) return;
    final r = widget.ruta.ruta;
    if (!await ref
        .read(abrirYCompartirProvider)
        .compartir(texto: mensaje, asunto: 'Ruta ${r.routeCode ?? r.id}')) {
      _decir(TextosDeEnviar.noSeCompartio);
    }
  }

  Future<void> _copiar() async {
    final mensaje = await _mensaje();
    if (mensaje == null || !mounted) return;
    if (await ref.read(abrirYCompartirProvider).copiar(mensaje)) {
      _decir(TextosDeEnviar.copiado);
    }
  }

  Future<void> _soltar() async {
    final seguro = await abrirCajon<bool>(
      context,
      titulo: 'Soltar la ruta',
      cuerpo: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'El teléfono que tiene esta ruta la pierde y su enlace deja de servir. Se crea un enlace nuevo para mandárselo a '
            'otro teléfono. Lo que ya marcó ese teléfono no se borra.',
          ),
          const SizedBox(height: 20),
          BotonDestructivo(
            key: claveDeConfirmarSoltar,
            texto: 'Sí, soltar la ruta',
            icono: Icons.link_off,
            alPulsar: () => Navigator.of(c).pop(true),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('No, dejarla como está'),
          ),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    setState(() {
      _ocupado = true;
      _fallo = null;
    });
    try {
      await ref
          .read(apiDistribucionProvider)
          .crearEnlace(_rutaId, renovar: true);
      ref.invalidate(enlaceDeLaRutaProvider(_rutaId));
      if (mounted) _decir(TextosDeEnviar.soltada);
    } on Object catch (e) {
      if (mounted) setState(() => _fallo = motivoDelFallo(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.ruta.ruta.status;
    final cerrada =
        estado == EstadoRuta.completada || estado == EstadoRuta.cancelada;
    final enElServidor = rutaYaEstaEnElServidor(_rutaId);
    final enlace = enElServidor
        ? ref.watch(enlaceDeLaRutaProvider(_rutaId))
        : null;
    final tema = Theme.of(context);

    final bloqueo = !enElServidor
        ? TextosDeEnviar.rutaSinSubir
        : cerrada
        ? TextosDeEnviar.rutaCerrada
        : null;
    final puede = bloqueo == null && !_ocupado;

    final linea = switch (enlace) {
      null => null,
      AsyncValue(:final error?) =>
        'No se pudo comprobar el enlace: ${motivoDelFallo(error)}',
      AsyncData(:final value) => switch (value.estado) {
        EstadoDelEnlace.sinEnlace => TextosDeEnviar.sinEnlace,
        EstadoDelEnlace.sinReclamar => TextosDeEnviar.sinReclamar,
        EstadoDelEnlace.reclamado => TextosDeEnviar.asignada(
          value.dispositivo,
          value.reclamadoAt,
        ),
      },
      _ => 'Comprobando el enlace…',
    };
    final reclamada =
        enlace?.value?.estado == EstadoDelEnlace.reclamado &&
        !cerrada &&
        enElServidor;

    return ControlSenalado(
      nombre: Senalado.rutasEnviarADistribuidor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TextosDeEnviar.titulo,
            style: tema.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          if (linea != null)
            Text(
              linea,
              key: claveDeEstadoDelEnlace,
              style: tema.textTheme.bodySmall,
            ),
          if (bloqueo != null)
            Text(
              bloqueo,
              style: tema.textTheme.bodySmall?.copyWith(color: Colores.ambar),
            ),
          if (_fallo != null) ...[
            const SizedBox(height: 6),
            DecoratedBox(
              key: claveDeAvisoDelEnlace,
              decoration: BoxDecoration(
                color: Colores.ambarFondo,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  _fallo!,
                  style: TextStyle(fontSize: 12, color: Colores.tinta),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ControlSenalado(
                nombre: Senalado.rutasWhatsApp,
                child: FilledButton.icon(
                  key: claveDeEnviarWhatsApp,
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text('WhatsApp'),
                  onPressed: puede ? _whatsapp : null,
                ),
              ),
              ControlSenalado(
                nombre: Senalado.rutasCompartir,
                child: OutlinedButton.icon(
                  key: claveDeEnviarCompartir,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Compartir'),
                  onPressed: puede ? _compartir : null,
                ),
              ),
              ControlSenalado(
                nombre: Senalado.rutasCopiar,
                child: OutlinedButton.icon(
                  key: claveDeEnviarCopiar,
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('Copiar'),
                  onPressed: puede ? _copiar : null,
                ),
              ),
              if (reclamada)
                TextButton.icon(
                  key: claveDeSoltarLaRuta,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text(TextosDeEnviar.soltar),
                  onPressed: _ocupado ? null : _soltar,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
