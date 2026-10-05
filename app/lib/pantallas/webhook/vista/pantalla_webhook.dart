import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/tarjeta.dart';
import '../../../diseno/tema.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../estado/proveedores_webhook.dart';
import '../datos/estado_del_webhook.dart';

/// CÓMO VA EL CANAL CON PEDIDO. Sólo en la web y sólo para el desarrollador.
///
/// Jose, 26/09/2026: «eso me lo dejas en la web solamente» y «que sólo lo pueda ver yo, eso
/// no lo puede ver más nadie, sólo yo, el desarrollador». No está en el menú y el servidor
/// contesta 403 a cualquier otro rol, que es lo único que de verdad lo cierra — el rol que
/// lleva el aparato no decide permisos, lo dice la propia `Sesion`.
///
/// LAS PALABRAS SON LAS MISMAS QUE LAS DE PEDIDO —*esperando*, *sin terminar*, *el más
/// viejo*, *último aviso*—, acordadas entre las dos sesiones. Si una pantalla dice
/// «pendientes» y la otra «esperando», comparar obliga a traducir, y en la traducción es
/// donde se cuela la conclusión equivocada.
///
/// TRES PREGUNTAS Y NO UNA, que es como está partida:
///
///  1. **¿Respira?** Cuánto hace de la última tanda de cada lado. Un canal parado no da
///     ningún error: sólo deja de pasar cosas.
///  2. **¿Llega lo que sale?** Cada tanda con su código y su motivo literal. Un aviso sin
///     mandar puede ser «PEDIDO está caído» o «PEDIDO lo rechazó», y desde fuera se ven
///     igual.
///  3. **¿Se escribe lo que entra?** Cuántos avisos llegaron y cuántos llevaron a algo.
class PantallaWebhook extends ConsumerWidget {
  const PantallaWebhook({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(estadoDelWebhookProvider);

    return estado.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // EL 403 SE DICE CON SUS PALABRAS y no como un error de la aplicación: quien llega
      // aquí sin ser el desarrollador tiene que saber que no está roto, que no es suyo.
      error: (e, _) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // EL 403 SE DICE CON SUS PALABRAS y no como un error de la aplicación: quien
          // llega aquí sin ser el desarrollador tiene que saber que no está roto.
          EstadoVacio(
            '$e'.contains('403')
                ? 'Esta pantalla es del desarrollador.'
                : 'No se pudo leer cómo va el canal.',
          ),
          const SizedBox(height: Aire.md),
          OutlinedButton(
            onPressed: () => ref.invalidate(estadoDelWebhookProvider),
            child: const Text('Volver a mirar'),
          ),
        ],
      ),
      data: (d) => ListView(
        padding: const EdgeInsets.all(Aire.lg),
        children: [
          ControlSenalado(
            nombre: Senalado.canalRespira,
            child: _Respira(d.resumen),
          ),
          const SizedBox(height: Aire.lg),
          ControlSenalado(
            nombre: Senalado.canalSaliendo,
            child: _Saliendo(resumen: d.resumen, tandas: d.enviados),
          ),
          const SizedBox(height: Aire.lg),
          ControlSenalado(
            nombre: Senalado.canalEntrando,
            child: _Entrando(resumen: d.resumen, tandas: d.recibidos),
          ),
          // «Sin terminar» sólo existe cuando hay algo sin terminar, y el paso
          // del manual lo dice igual: «Si hay algo en «Sin terminar»…». Con la
          // lista vacía el recorrido dice que ese control no está, que es la
          // verdad.
          if (d.sinMandar.isNotEmpty) ...[
            const SizedBox(height: Aire.lg),
            ControlSenalado(
              nombre: Senalado.canalSinTerminar,
              child: _SinMandar(d.sinMandar),
            ),
          ],
        ],
      ),
    );
  }
}

/// ¿Respira? Las dos horas, una al lado de la otra.
class _Respira extends StatelessWidget {
  const _Respira(this.r);

  final ResumenDelWebhook r;

  @override
  Widget build(BuildContext context) => Tarjeta(
    titulo: 'El canal con PEDIDO',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Aire.xl,
          runSpacing: Aire.md,
          children: [
            _Dato('Último aviso recibido', _haceCuanto(r.ultimaEntrada)),
            _Dato('Última tanda enviada', _haceCuanto(r.ultimaSalida)),
            _Dato('Escritos hoy', '${r.escritosHoy}'),
          ],
        ),
        if (r.estaAtascado) ...[
          const SizedBox(height: Aire.md),
          Text(
            'Atascado: hay algo esperando desde hace '
            '${_haceCuanto(r.masViejo)}. Con el canal sano no pasa de unos segundos.',
            style: Tipos.texto(tamano: 12, color: Colores.rojo),
          ),
        ],
      ],
    ),
  );
}

class _Saliendo extends StatelessWidget {
  const _Saliendo({required this.resumen, required this.tandas});

  final ResumenDelWebhook resumen;
  final List<TandaEnviada> tandas;

  @override
  Widget build(BuildContext context) => Tarjeta(
    titulo: 'Saliendo · lo que el reparto le cuenta a PEDIDO',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Aire.xl,
          runSpacing: Aire.md,
          children: [
            _Dato('Esperando', '${resumen.esperando}'),
            _Dato('El más viejo', _haceCuanto(resumen.masViejo)),
            // RECHAZADO NO ES «FALLÓ»: llegó perfectamente y PEDIDO dijo que no. No se
            // reintenta, así que es una bandeja que alguien tiene que mirar.
            _Dato('Rechazados por PEDIDO', '${resumen.rechazados}'),
          ],
        ),
        const SizedBox(height: Aire.md),
        if (tandas.isEmpty)
          const Text('Todavía no ha salido ninguna tanda.')
        else
          for (final t in tandas.take(8))
            _Linea(
              cuando: t.cuando,
              texto:
                  '${t.mandados} avisos · ${t.aceptados} aceptados'
                  '${t.rechazados > 0 ? ' · ${t.rechazados} no' : ''}'
                  '${t.http == null ? '' : ' · HTTP ${t.http}'}'
                  ' · ${t.duracionMs} ms',
              // El motivo LITERAL de PEDIDO. «no se pudo» no le dice nada a nadie;
              // «no existe aquí (¿otra sucursal?)» dice dónde mirar.
              detalle: t.motivo,
              malo: !t.llegoBien,
            ),
      ],
    ),
  );
}

class _Entrando extends StatelessWidget {
  const _Entrando({required this.resumen, required this.tandas});

  final ResumenDelWebhook resumen;
  final List<TandaRecibida> tandas;

  @override
  Widget build(BuildContext context) => Tarjeta(
    titulo: 'Entrando · lo que PEDIDO le cuenta al reparto',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tandas.isEmpty)
          const Text(
            'Todavía no ha entrado ninguna tanda. Si PEDIDO está avisando y esto '
            'sigue vacío, mira que el grupo de lectura exista.',
          )
        else
          for (final t in tandas.take(8))
            _Linea(
              cuando: t.cuando,
              texto:
                  '${t.comoSeLlama} · ${t.traidos} avisos · '
                  '${t.escritos} llevaron a algo'
                  '${t.rechazados > 0 ? ' · ${t.rechazados} sin efecto' : ''}'
                  ' · ${t.duracionMs} ms',
              detalle: t.motivos,
              // SIN EFECTO NO ES ROJO, y es a propósito: un repetido en la misma tanda o
              // un traer que un borrado anuló es el sistema haciendo lo correcto.
              // Pintarlo de rojo enseña a ignorar el rojo, y entonces el rojo de verdad
              // tampoco se mira.
              malo: false,
            ),
      ],
    ),
  );
}

class _SinMandar extends StatelessWidget {
  const _SinMandar(this.avisos);

  final List<AvisoSinMandar> avisos;

  @override
  Widget build(BuildContext context) => Tarjeta(
    titulo: 'Sin terminar · ${avisos.length}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lo que no llegó a PEDIDO. Los rechazados NO se reintentan: repetir lo '
          'mismo da lo mismo, así que se quedan aquí hasta que alguien decida.',
        ),
        const SizedBox(height: Aire.md),
        for (final a in avisos.take(20))
          _Linea(
            cuando: a.cuando,
            texto:
                '${a.folio ?? a.pedidoId} · ${a.estado} · '
                '${a.situacion}${a.intentos > 0 ? ' · ${a.intentos} intentos' : ''}',
            detalle: a.motivo,
            malo: a.loRechazaron,
          ),
      ],
    ),
  );
}

class _Dato extends StatelessWidget {
  const _Dato(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(rotulo, style: Tipos.texto(tamano: 11, color: Colores.tintaSuave)),
      const SizedBox(height: 2),
      Text(valor, style: Tipos.texto(tamano: 16, peso: FontWeight.w700)),
    ],
  );
}

class _Linea extends StatelessWidget {
  const _Linea({
    required this.cuando,
    required this.texto,
    this.detalle,
    this.malo = false,
  });

  final DateTime cuando;
  final String texto;
  final String? detalle;
  final bool malo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_haceCuanto(cuando)} · $texto',
          style: Tipos.texto(tamano: 12, color: malo ? Colores.rojo : null),
        ),
        if (detalle != null && detalle!.trim().isNotEmpty)
          Text(
            detalle!,
            style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
          ),
      ],
    ),
  );
}

/// «hace 3 min». **`null` es «nunca»**, y se dice así: no es lo mismo que «hace mucho», y
/// un canal que nunca recibió nada y uno que lleva seis horas parado se arreglan en sitios
/// distintos.
String _haceCuanto(DateTime? t) {
  if (t == null) return 'nunca';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'hace ${d.inSeconds} s';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 48) return 'hace ${d.inHours} h';
  return 'hace ${d.inDays} días';
}
