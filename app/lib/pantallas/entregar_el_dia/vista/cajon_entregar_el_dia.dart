import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/sincro/ciclo.dart';
import '../../../nucleo/sincro/huerfanos.dart';
import '../../../nucleo/sincro/sucursal_del_aparato.dart';
import '../../rutas/estado/proveedores_rutas.dart';
import '../../sincronizacion/vista/fila_de_rechazo.dart';
import '../datos/textos.dart';
import '../estado/entregar_el_dia.dart';

/// Abre EL CAJON de entregar el dia. Si [empezarYa], ademas lo dispara.
///
/// Cajon y no dialogo, tambien en escritorio: regla de la casa de delivery
/// (pliego §9.2). Y aqui hace ademas otra falta — la lista de rechazados puede
/// ser larga, y un modal centrado con scroll interno es peor que un panel a alto
/// completo.
Future<void> abrirCajonDeEntregarElDia(
  BuildContext contexto, {
  bool empezarYa = false,
}) {
  return abrirPanel<void>(
    contexto,
    (_) => _CajonDeEntregarElDia(empezarYa: empezarYa),
  );
}

class _CajonDeEntregarElDia extends ConsumerStatefulWidget {
  const _CajonDeEntregarElDia({required this.empezarYa});

  final bool empezarYa;

  @override
  ConsumerState<_CajonDeEntregarElDia> createState() =>
      _CajonDeEntregarElDiaState();
}

class _CajonDeEntregarElDiaState extends ConsumerState<_CajonDeEntregarElDia> {
  @override
  void initState() {
    super.initState();
    if (widget.empezarYa) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(ref.read(entregarElDiaProvider.notifier).ahora());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final marcha = ref.watch(marchaDelCicloProvider);
    final entrego = ref.watch(entregarElDiaProvider);
    final pendientes = ref.watch(sinSubirProvider).value ?? 0;
    final rechazados = ref.watch(rechazadosProvider).value ?? const <Apunte>[];
    final descartados =
        ref.watch(descartadosProvider).value ?? const <Apunte>[];
    final huerfano =
        ref.watch(trabajoHuerfanoProvider).value ?? const <TrabajoHuerfano>[];

    return Cajon(
      titulo: TextosDeEntregarElDia.titulo,
      subtitulo: TextosDeEntregarElDia.explicacion,
      ancho: AnchoCajon.lg,
      pie: _Pie(corriendo: marcha.enVuelo, pendientes: pendientes),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // DE QUE SUCURSAL ES ESTE APARATO, y sólo cuando hace falta.
          //
          // Quien tiene su sucursal no ve esto nunca: la pone el servidor con la
          // sesión. Quien ve las ocho no tiene ninguna, y sin una el alta del
          // aparato contesta 400 y **no sube ni un apunte** — pasó el
          // 21/09/2026 con una ruta entera hecha sin señal esperando.
          const _DeQueSucursalEsEsteAparato(),
          if (marcha.enVuelo)
            _Subiendo(marcha: marcha)
          else if (entrego != null)
            _ComoQuedo(entrego: entrego)
          else
            _EnCalma(pendientes: pendientes),
          // LO QUE NO VA A SUBIR SOLO, JUSTO DEBAJO DEL RESULTADO.
          //
          // Va aqui y no al final porque contradice a lo de arriba: «Todo
          // entregado» en verde sobre una ruta que solo existe en este aparato
          // es, palabra por palabra, la pantalla del 16/09/2026. Cuando no hay
          // nada colgado no ocupa un pixel.
          if (huerfano.hayAlguno) ...[
            const SizedBox(height: Aire.md),
            _SoloEnEsteAparato(huerfano: huerfano),
          ],
          // LO QUE SUBIO Y SALIO CON MENOS DE LO QUE SE PUSO.
          //
          // Va aqui, entre el resultado y la bandeja, porque es lo mismo que
          // los dos y no es ninguno: subio —asi que «Todo entregado» no
          // miente— y aun asi falta trabajo por mirar. El apunte pudo entrar
          // horas despues con la pantalla cerrada, asi que el aviso tiene que
          // esperar aqui hasta que alguien lo lea.
          //
          // Cuando no hay ninguno no ocupa un pixel: un aviso que sale en cada
          // armado deja de leerse (§3-quinquies).
          if (descartados.isNotEmpty) ...[
            const SizedBox(height: Aire.md),
            _NoSubioTodoAlCamion(descartados: descartados),
          ],
          const SizedBox(height: Aire.xl),
          // LA BANDEJA, SIEMPRE. Tambien con cero dentro: que se vea vacia es lo
          // que ensena que existe, y el dia que aparezca algo alguien ya sabra
          // donde mirar.
          _Bandeja(rechazados: rechazados),
        ],
      ),
    );
  }
}

/// La pregunta que faltaba: **¿de qué sucursal es este aparato?**
///
/// Sale sólo si hace falta —no hay ninguna guardada y quien mira no tiene la
/// suya, o sea que está en «Todas»— y se va en cuanto se contesta. No se elige
/// por nadie: un aparato dado de alta en la sucursal equivocada baja los pedidos
/// de otra gente y sube el trabajo a donde no es.
class _DeQueSucursalEsEsteAparato extends ConsumerWidget {
  const _DeQueSucursalEsEsteAparato();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delAparato = ref.watch(sucursalDelAparatoProvider);
    final mirada = ref.watch(sucursalMiradaProvider);
    if (delAparato != null || mirada != null) return const SizedBox.shrink();

    final sucursales = ref.watch(sucursalesProvider).value ?? const [];
    if (sucursales.length < 2) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: Aire.xl),
      padding: const EdgeInsets.all(Aire.lg),
      decoration: BoxDecoration(
        color: Colores.ambarFondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colores.ambar.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TextosDeEntregarElDia.deQueSucursalTitulo,
            style: Tipos.texto(tamano: 15, peso: FontWeight.w600),
          ),
          const SizedBox(height: Aire.sm),
          Text(TextosDeEntregarElDia.deQueSucursalPorque),
          const SizedBox(height: Aire.lg),
          Wrap(
            spacing: Aire.sm,
            runSpacing: Aire.sm,
            children: [
              for (final s in sucursales)
                OutlinedButton(
                  onPressed: () => unawaited(
                    ref.read(sucursalDelAparatoProvider.notifier).poner(s.id),
                  ),
                  child: Text(s.name),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pie extends ConsumerWidget {
  const _Pie({required this.corriendo, required this.pendientes});

  final bool corriendo;
  final int pendientes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Con la cola vacia el boton **no invita a nada**: se apaga. Un boton
    // encendido que no hace nada ensena a desconfiar del que si hace algo.
    final hayQueHacer = pendientes > 0;

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: corriendo || !hayQueHacer
                ? null
                : () => unawaited(
                    ref.read(entregarElDiaProvider.notifier).ahora(),
                  ),
            icon: Icon(
              corriendo ? Icons.hourglass_top : Icons.cloud_upload_outlined,
              size: 20,
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: Aire.lg),
              textStyle: Tipos.texto(tamano: 15, peso: FontWeight.w600),
            ),
            label: Text(
              corriendo
                  ? TextosDeEntregarElDia.subiendo
                  : !hayQueHacer
                  ? TextosDeEntregarElDia.todoEntregado
                  : TextosDeEntregarElDia.boton,
            ),
          ),
        ),
      ],
    );
  }
}

class _Subiendo extends ConsumerWidget {
  const _Subiendo({required this.marcha});

  final Marcha marcha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Aire.lg),
      decoration: BoxDecoration(
        color: Colores.enCursoFondo,
        borderRadius: BorderRadius.circular(Radios.lg),
        border: Border.all(color: Colores.enCurso.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colores.enCurso,
            ),
          ),
          const SizedBox(width: Aire.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TextosDeEntregarElDia.subiendo,
                  style: Tipos.texto(
                    tamano: 15,
                    peso: FontWeight.w600,
                    color: Colores.enCurso,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  TextosDeEntregarElDia.porDondeVa(marcha.avance),
                  style: tema.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                _Cronometro(desde: marcha.empezadoA),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuanto lleva. Se apaga en `dispose`: un temporizador vivo despues de cerrar
/// el cajon es un fallo que en las pruebas no dice nada de lo que se probaba.
class _Cronometro extends ConsumerStatefulWidget {
  const _Cronometro({required this.desde});

  final DateTime? desde;

  @override
  ConsumerState<_Cronometro> createState() => _CronometroState();
}

class _CronometroState extends ConsumerState<_Cronometro> {
  Timer? _tic;

  @override
  void initState() {
    super.initState();
    _tic = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tic?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desde = widget.desde;
    if (desde == null) return const SizedBox.shrink();
    final lleva = ref.read(relojProvider)().difference(desde);
    return Text(
      'lleva ${TextosDeEntregarElDia.cuantoLleva(lleva)}',
      style: Tipos.mono(tamano: 12, color: Colores.tintaSuave),
    );
  }
}

/// COMO QUEDO. Cuantos subieron, y sobre todo **cuantos quedan**.
class _ComoQuedo extends StatelessWidget {
  const _ComoQuedo({required this.entrego});

  final LoQueSeEntrego entrego;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    // Verde SOLO con [LoQueSeEntrego.completo]. La cuenta vive en un sitio: si
    // queda un apunte sin subir —o uno rechazado esperando—, esto no se pone
    // verde aunque el ciclo haya devuelto `bien`.
    final (color, fondo, icono) = entrego.completo
        ? (Colores.verde, Colores.verdeFondo, Icons.check_circle_outline)
        : entrego.sinSenal
        ? (Colores.ambar, Colores.ambarFondo, Icons.signal_wifi_off_outlined)
        : (Colores.rojo, Colores.rojoFondo, Icons.error_outline);

    return Container(
      padding: const EdgeInsets.all(Aire.lg),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(Radios.lg),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, size: 22, color: color),
              const SizedBox(width: Aire.sm),
              Expanded(
                child: Text(
                  TextosDeEntregarElDia.comoQuedo(entrego),
                  style: Tipos.texto(
                    tamano: 17,
                    peso: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Aire.md),

          // CUANTOS SUBIERON, con numero. No «listo».
          if (!entrego.sinSesion && !entrego.sinSenal) ...[
            Text(
              TextosDeEntregarElDia.subieron(entrego.subidos),
              style: Tipos.mono(
                tamano: 15,
                peso: FontWeight.w700,
                color: Colores.tinta,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              TextosDeEntregarElDia.deLasHoras(entrego.hora),
              style: tema.textTheme.bodySmall?.copyWith(
                color: Colores.tintaSuave,
              ),
            ),
          ],

          if (entrego.sinSenal) ...[
            Text(
              TextosDeEntregarElDia.cuantoQueda(entrego.quedan),
              style: Tipos.mono(
                tamano: 15,
                peso: FontWeight.w700,
                color: Colores.tinta,
              ),
            ),
            const SizedBox(height: Aire.sm),
            Text(
              TextosDeEntregarElDia.sinSenalDetalle,
              style: tema.textTheme.bodyMedium,
            ),
          ],

          if (entrego.sinSesion) ...[
            Text(
              TextosDeEntregarElDia.sinSesionDetalle,
              style: tema.textTheme.bodyMedium,
            ),
          ],

          if (entrego.fallo case final fallo?) ...[
            const SizedBox(height: Aire.sm),
            Text(
              TextosDeEntregarElDia.motivoDelFallo(fallo),
              style: tema.textTheme.bodySmall,
            ),
          ],

          // QUE HACER. Sin esto el aviso es una queja.
          if (!entrego.completo && !entrego.sinSesion) ...[
            const SizedBox(height: Aire.md),
            Text(
              TextosDeEntregarElDia.queHacerSiQueda,
              style: Tipos.texto(
                tamano: 13,
                peso: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// En calma: cuanto hay sin subir, **sin haber dado a nada**.
class _EnCalma extends StatelessWidget {
  const _EnCalma({required this.pendientes});

  final int pendientes;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final hay = pendientes > 0;
    return Container(
      padding: const EdgeInsets.all(Aire.lg),
      decoration: BoxDecoration(
        color: hay ? Colores.ambarFondo : Colores.verdeFondo,
        borderRadius: BorderRadius.circular(Radios.lg),
        border: Border.all(
          color: (hay ? Colores.ambar : Colores.verde).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hay ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
            size: 22,
            color: hay ? Colores.ambar : Colores.verde,
          ),
          const SizedBox(width: Aire.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TextosDeEntregarElDia.cuantoQueda(pendientes),
                  style: Tipos.texto(
                    tamano: 17,
                    peso: FontWeight.w700,
                    color: hay ? Colores.ambar : Colores.verde,
                  ),
                ),
                if (!hay) ...[
                  const SizedBox(height: 4),
                  Text(
                    TextosDeEntregarElDia.nadaQueEntregar,
                    style: tema.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// TRABAJO QUE ESTA AQUI, NO ESTA ARRIBA Y NO LO VA A SUBIR NADIE.
///
/// La cola no compara los dos lados: reenvia apuntes. En cuanto un apunte
/// desaparece —descartado a mano desde la bandeja de abajo, o perdido— la fila
/// local se queda sin nadie que la suba, y hasta hoy eso no salia en ninguna
/// pantalla: ni en el «sin subir» de arriba, porque no le queda apunte; ni en la
/// bandeja,
/// porque nadie la rechazo. Ver `nucleo/sincro/huerfanos.dart`.
class _SoloEnEsteAparato extends StatelessWidget {
  const _SoloEnEsteAparato({required this.huerfano});

  final List<TrabajoHuerfano> huerfano;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Aire.lg),
      decoration: BoxDecoration(
        color: Colores.ambarFondo,
        borderRadius: BorderRadius.circular(Radios.lg),
        border: Border.all(color: Colores.ambar.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.report_problem_outlined, size: 22, color: Colores.ambar),
          const SizedBox(width: Aire.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TextosDeEntregarElDia.soloAqui(huerfano.texto),
                  style: Tipos.texto(
                    tamano: 17,
                    peso: FontWeight.w700,
                    color: Colores.ambar,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  TextosDeEntregarElDia.soloAquiDetalle,
                  style: tema.textTheme.bodyMedium,
                ),
                const SizedBox(height: Aire.sm),
                // QUE HACER. Sin esto el aviso es una queja.
                Text(
                  TextosDeEntregarElDia.soloAquiQueHacer,
                  style: Tipos.texto(
                    tamano: 13,
                    peso: FontWeight.w600,
                    color: Colores.ambar,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// LO QUE SUBIO BIEN Y AUN ASI DEJO PEDIDOS FUERA.
///
/// ## Por que esto se ensena aqui y no en el Tablero
///
/// El caso que lo origina es **la APK sin señal**: se arma la zona a las ocho
/// de la mañana, el apunte sube a las cuatro de la tarde y para entonces la
/// pantalla del Tablero hace horas que se cerro. Un aviso que se pinte al armar
/// no lo ve nadie, porque cuando se sabe la respuesta ya no hay nadie delante.
///
/// Asi que vive donde ya viven las otras dos preguntas de «¿que me falta por
/// entregar?» —el «N sin subir» y la bandeja de rechazos—, que es el sitio al
/// que se va justamente a comprobar que el dia salio entero, y espera ahi hasta
/// que alguien lo da por leido. Y para que nadie tenga que acordarse de abrir
/// el cajon, la franja de estado —que esta en las siete pantallas— dice en
/// ambar que hay algo que mirar y lleva aqui (`navegacion/franja_de_estado.dart`).
///
/// **No se ofrece «reintentar»** y ahi esta la diferencia con la bandeja: el
/// apunte se aplico de verdad, la ruta existe arriba, y volver a mandarlo
/// armaria una SEGUNDA ruta con el mismo camion.
class _NoSubioTodoAlCamion extends ConsumerWidget {
  const _NoSubioTodoAlCamion({required this.descartados});

  final List<Apunte> descartados;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final formato = DateFormat('d/M/y, H:mm', 'es');
    return Container(
      padding: const EdgeInsets.all(Aire.lg),
      decoration: BoxDecoration(
        color: Colores.ambarFondo,
        borderRadius: BorderRadius.circular(Radios.lg),
        border: Border.all(color: Colores.ambar.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.local_shipping_outlined,
                size: 22,
                color: Colores.ambar,
              ),
              const SizedBox(width: Aire.sm),
              Expanded(
                child: Text(
                  TextosDeEntregarElDia.noSubioTodo,
                  style: Tipos.texto(
                    tamano: 17,
                    peso: FontWeight.w700,
                    color: Colores.ambar,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            TextosDeEntregarElDia.noSubioTodoDetalle,
            style: tema.textTheme.bodyMedium,
          ),
          for (final a in descartados) ...[
            const SizedBox(height: Aire.md),
            // EL MOTIVO LITERAL DEL SERVIDOR, con el pedido nombrado y que
            // hacer. Se pinta entero: es lo unico que le dice a alguien si esa
            // entrega hay que ir a buscarla.
            Text(a.motivo ?? '', style: tema.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              'armado ${formato.format(a.hechoAt)}'
              '${a.resueltoAt == null ? '' : ' · subió ${formato.format(a.resueltoAt!)}'}',
              style: tema.textTheme.bodySmall?.copyWith(
                color: Colores.tintaSuave,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => unawaited(
                  ref.read(colaProvider).darPorLeidoElDescarte(a.clave),
                ),
                icon: const Icon(Icons.check, size: 18),
                label: const Text(TextosDeEntregarElDia.noSubioTodoLeido),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// LA BANDEJA de este aparato: lo que el servidor rechazo, con su motivo.
class _Bandeja extends ConsumerWidget {
  const _Bandeja({required this.rechazados});

  final List<Apunte> rechazados;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final formato = DateFormat('d/M/y, H:mm', 'es');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                rechazados.isEmpty
                    ? TextosDeEntregarElDia.bandejaTitulo
                    : '${TextosDeEntregarElDia.bandejaTitulo} '
                          '(${Numeros.entero(rechazados.length)})',
                style: Tipos.texto(
                  tamano: 14,
                  peso: FontWeight.w700,
                  color: Colores.tinta,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          TextosDeEntregarElDia.bandejaExplicacion,
          style: tema.textTheme.bodySmall?.copyWith(color: Colores.tintaSuave),
        ),
        const SizedBox(height: Aire.md),
        if (rechazados.isEmpty)
          const EstadoVacio(
            'No hay nada rechazado. Lo que se rechace sale aquí con su motivo '
            'y su hora, y no se va solo.',
            icono: Icons.inbox_outlined,
          )
        else
          for (final a in rechazados)
            FilaDeRechazo(
              motivo: a.motivo ?? 'El servidor lo rechazó sin decir por qué.',
              // En el cajon del propio aparato no hay a quien atribuirlo: es de
              // quien esta mirando la pantalla.
              quien: '',
              horas: <String>[
                'hecho ${formato.format(a.hechoAt)}',
                if (a.resueltoAt != null)
                  'rechazado ${formato.format(a.resueltoAt!)}',
              ].join(' · '),
              peticion: '${a.metodo} ${a.ruta}',
              // LAS DOS DECISIONES. Aqui SI se pueden tomar: es la bandeja de
              // ESTE aparato, o sea la de quien esta mirando. En la pantalla de
              // Sincronizacion, que ensena la de los diez, no se ofrecen.
              alReintentar: () =>
                  unawaited(ref.read(colaProvider).reintentar(a.clave)),
              alDescartar: () =>
                  unawaited(ref.read(colaProvider).descartar(a.clave)),
            ),
      ],
    );
  }
}
