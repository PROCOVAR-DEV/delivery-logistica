import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/sincro/ciclo.dart';
import '../../../nucleo/sincro/recuento.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../datos/textos.dart';
import '../estado/traer_el_dia.dart';

/// Abre EL CAJON del gesto. Si [empezarYa], ademas lo dispara.
///
/// **Cajon y no dialogo, tambien en escritorio**: es la regla de la casa de
/// delivery (pliego §9.2, excepcion aprobada el 05/09/2026), y aqui ademas
/// resuelve el encargo — el mismo panel, con la misma forma y el mismo sitio,
/// en el telefono de 390 px y en el monitor de 1440. Quien aprende el gesto en
/// uno lo sabe en el otro.
Future<void> abrirCajonDeTraerElDia(
  BuildContext contexto, {
  bool empezarYa = false,
}) {
  return abrirPanel<void>(
    contexto,
    (_) => _CajonDeTraerElDia(empezarYa: empezarYa),
  );
}

class _CajonDeTraerElDia extends ConsumerStatefulWidget {
  const _CajonDeTraerElDia({required this.empezarYa});

  final bool empezarYa;

  @override
  ConsumerState<_CajonDeTraerElDia> createState() => _CajonDeTraerElDiaState();
}

class _CajonDeTraerElDiaState extends ConsumerState<_CajonDeTraerElDia> {
  @override
  void initState() {
    super.initState();
    if (widget.empezarYa) {
      // Despues del primer fotograma: disparar dentro de `initState` escribe en
      // un provider mientras se esta construyendo el arbol.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(ref.read(traerElDiaProvider.notifier).ahora());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final marcha = ref.watch(marchaDelCicloProvider);
    final trajo = ref.watch(traerElDiaProvider);
    final hay = ref.watch(loQueHayProvider).value;

    return Cajon(
      titulo: TextosDeTraerElDia.titulo,
      subtitulo: TextosDeTraerElDia.explicacion,
      ancho: AnchoCajon.lg,
      pie: _Pie(corriendo: marcha.enVuelo),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (marcha.enVuelo)
            _Corriendo(marcha: marcha)
          else if (trajo != null)
            _ComoQuedo(trajo: trajo)
          else
            _EnCalma(hay: hay),
          const SizedBox(height: Aire.xl),
          // Lo que te llevas, SIEMPRE. Tambien mientras corre: ver lo anterior
          // al lado de lo que esta entrando es lo que deja saber si esta
          // bajando algo o esta dando vueltas.
          _LoQueTeLlevas(
            recuento: trajo?.recuento ?? hay,
            faltan: trajo?.faltan ?? const <Falta>[],
          ),
        ],
      ),
    );
  }
}

/// EL BOTON, pegado abajo y siempre a la vista.
class _Pie extends ConsumerWidget {
  const _Pie({required this.corriendo});

  final bool corriendo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trajo = ref.watch(traerElDiaProvider);

    return Row(
      children: [
        Expanded(
          child: ControlSenalado(
            nombre: Senalado.traerElDiaTraer,
            child: FilledButton.icon(
              // Mientras corre no se vuelve a disparar. **El candado de verdad no
              // es este**: esta en `ciclo.dart`, y quien llegue mientras uno va se
              // engancha al que ya corre. Esto es solo no invitar a pulsarlo.
              onPressed: corriendo
                  ? null
                  : () => unawaited(
                      ref.read(traerElDiaProvider.notifier).ahora(),
                    ),
              icon: Icon(
                corriendo ? Icons.hourglass_top : Icons.cloud_download_outlined,
                size: 20,
              ),
              style: FilledButton.styleFrom(
                // Grande: es el gesto principal de la pantalla, y se le da con el
                // pulgar de pie en el almacen.
                padding: const EdgeInsets.symmetric(vertical: Aire.lg),
                textStyle: Tipos.texto(tamano: 15, peso: FontWeight.w600),
              ),
              label: Text(
                corriendo
                    ? TextosDeTraerElDia.trayendo
                    : trajo != null
                    ? TextosDeTraerElDia.botonOtraVez
                    : TextosDeTraerElDia.boton,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// MIENTRAS CORRE: por donde va y cuanto lleva.
///
/// Las dos cosas hacen falta. «Trayendo el día...» a secas durante cuarenta
/// segundos en la conexion de alla es indistinguible de una pantalla colgada, y
/// quien no sabe si se colgo no se va tranquilo al almacen.
class _Corriendo extends ConsumerWidget {
  const _Corriendo({required this.marcha});

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
                  TextosDeTraerElDia.trayendo,
                  style: Tipos.texto(
                    tamano: 15,
                    peso: FontWeight.w600,
                    color: Colores.enCurso,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  TextosDeTraerElDia.porDondeVa(marcha.avance),
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

/// Cuanto lleva, contando de verdad.
///
/// Lleva su propio temporizador porque entre coleccion y coleccion hay una ida y
/// vuelta al servidor: sin el, el numero se quedaria quieto justo en los tramos
/// largos, que son los unicos en los que alguien lo mira. Se apaga en `dispose`
/// — un temporizador vivo despues de cerrar el cajon es un fallo que en las
/// pruebas no dice nada de lo que se estaba probando.
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
      'lleva ${TextosDeTraerElDia.cuantoLleva(lleva)}',
      style: Tipos.mono(tamano: 12, color: Colores.tintaSuave),
    );
  }
}

/// COMO QUEDO. El unico sitio de la aplicacion que puede decir «ya lo tienes».
class _ComoQuedo extends StatelessWidget {
  const _ComoQuedo({required this.trajo});

  final LoQueSeTrajo trajo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    // Verde SOLO con [LoQueSeTrajo.completo]. Es la guarda, y esta escrita en un
    // sitio: si `faltan` trae algo, esto no puede ponerse verde ni aunque el
    // ciclo haya devuelto `bien`.
    final (color, fondo, icono) = trajo.completo
        ? (Colores.verde, Colores.verdeFondo, Icons.check_circle_outline)
        : trajo.sinSenal
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
                  TextosDeTraerElDia.comoQuedo(trajo),
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

          // LOS NUMEROS, siempre. Tambien cuando falta algo: quien tiene los
          // pedidos y los clientes y no el catalogo necesita saber las dos
          // cosas, no solo la mala.
          if (!trajo.sinSesion) ...[
            Text(
              TextosDeTraerElDia.lasTresCifras(trajo.recuento),
              style: Tipos.mono(
                tamano: 15,
                peso: FontWeight.w700,
                color: Colores.tinta,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              TextosDeTraerElDia.deLasHoras(trajo.hora),
              style: tema.textTheme.bodySmall?.copyWith(
                color: Colores.tintaSuave,
              ),
            ),
          ],

          if (trajo.subidos > 0) ...[
            const SizedBox(height: Aire.sm),
            Text(
              'Y de paso subió ${Numeros.entero(trajo.subidos)} '
              '${trajo.subidos == 1 ? 'apunte' : 'apuntes'} que te quedaban.',
              style: tema.textTheme.bodySmall,
            ),
          ],

          // QUE FALTA Y QUE SE ROMPE SIN ELLO. Una linea por cosa.
          if (trajo.faltan.isNotEmpty) ...[
            const SizedBox(height: Aire.md),
            for (final linea in TextosDeTraerElDia.queSeRompe(trajo.faltan))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('· '),
                    Expanded(
                      child: Text(linea, style: tema.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],

          // LA BAJADA SE CORTO Y EL SERVIDOR DIJO POR QUE. Va con las faltas y
          // no con los fallos: no reventó nada, lo que pasa es que el aparato
          // se quedó con parte de los datos y las cifras de arriba parecen
          // normales. Sin esta línea esto era un `Registro.fallo` en un log y
          // un tic verde en la pantalla (`CLAUDE.md` §3).
          if (trajo.quedoPor case final quedoPor?) ...[
            const SizedBox(height: Aire.md),
            Text(
              TextosDeTraerElDia.seCortoDetalle(quedoPor),
              style: tema.textTheme.bodyMedium,
            ),
          ],

          if (trajo.fallo case final fallo?) ...[
            const SizedBox(height: Aire.sm),
            Text(
              TextosDeTraerElDia.motivoDelFallo(fallo),
              style: tema.textTheme.bodySmall,
            ),
          ],

          if (trajo.sinSenal) ...[
            const SizedBox(height: Aire.sm),
            Text(
              TextosDeTraerElDia.sinSenalDetalle,
              style: tema.textTheme.bodyMedium,
            ),
          ],

          if (trajo.sinSesion) ...[
            const SizedBox(height: Aire.sm),
            Text(
              TextosDeTraerElDia.sinSesionDetalle,
              style: tema.textTheme.bodyMedium,
            ),
          ],

          // QUE HACER. Sin esto el aviso es una queja.
          if (!trajo.completo && !trajo.sinSesion) ...[
            const SizedBox(height: Aire.md),
            Text(
              TextosDeTraerElDia.queHacerSinAlgo,
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

/// En calma: lo que ya se tiene, sin haber dado a nada.
class _EnCalma extends StatelessWidget {
  const _EnCalma({required this.hay});

  final RecuentoDeLoQueHay? hay;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final recuento = hay;
    if (recuento == null) return const SizedBox(height: 60);

    final cuando = recuento.laMasVieja;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TextosDeTraerElDia.enCalma,
          style: tema.textTheme.bodySmall?.copyWith(color: Colores.tintaSuave),
        ),
        const SizedBox(height: 4),
        Text(
          TextosDeTraerElDia.lasTresCifras(recuento),
          style: Tipos.mono(
            tamano: 15,
            peso: FontWeight.w700,
            color: Colores.tinta,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          // Sin marca en alguna de las nueve NO se dice una hora: se dice que
          // no se bajo. Una hora ahi seria la de una parte, leida como la del
          // todo.
          cuando == null
              ? TextosDeTraerElDia.nuncaSeBajo
              : TextosDeTraerElDia.deLasHoras(cuando),
          style: tema.textTheme.bodySmall?.copyWith(color: Colores.tintaSuave),
        ),
      ],
    );
  }
}

/// LO QUE TE LLEVAS: las tres que pesan, y lo de siempre en una linea.
///
/// Antes esto eran NUEVE renglones iguales y parecia que la aplicacion se bajaba
/// medio mundo. La realidad es otra y hay que ensenarla: lo que tarda son tres
/// cosas —clientes, productos y los pedidos con sus lineas dentro— y el resto
/// suma menos de veinte filas entre las cuatro. Las rutas no salen: son lo que
/// la aplicacion PRODUCE, no lo que consume (`recuento.dart`, `calladas`).
class _LoQueTeLlevas extends StatelessWidget {
  const _LoQueTeLlevas({required this.recuento, required this.faltan});

  final RecuentoDeLoQueHay? recuento;
  final List<Falta> faltan;

  @override
  Widget build(BuildContext context) {
    final r = recuento;
    if (r == null) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final rotas = {for (final f in faltan) f.coleccion};

    // Lo de siempre esta bien si NINGUNA de las cuatro falta. Se mira entero
    // porque se ensena entero: decir que va bien con los almacenes sin bajar
    // seria lo mismo que callarlo.
    final loDeSiempreBien = !Faltas.loDeSiempre.any(rotas.contains);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final coleccion in Faltas.lasQuePesan)
          _Renglon(
            // El nombre y el numero juntos: «1.423 pedidos», que es como lo
            // dice una persona.
            texto: TextosDeTraerElDia.cifraDe(r, coleccion),
            // Los pedidos traen SUS LINEAS dentro. Se dice al lado y no como
            // otro renglon: contarlas aparte hace creer que son otra descarga.
            nota: coleccion == Colecciones.pedidos
                ? TextosDeTraerElDia.conSusLineas(r)
                : '',
            bien: !rotas.contains(coleccion) && r.seBajo(coleccion),
            sinBajar: !r.seBajo(coleccion),
          ),
        const SizedBox(height: Aire.sm),
        _Renglon(
          texto: TextosDeTraerElDia.loDeSiempre,
          nota: loDeSiempreBien ? TextosDeTraerElDia.loDeSiempreCuantas(r) : '',
          bien: loDeSiempreBien,
          sinBajar: Faltas.loDeSiempre.any((c) => !r.seBajo(c)),
          suave: true,
        ),
        if (!loDeSiempreBien) ...[
          const SizedBox(height: 4),
          Text(
            Faltas.seRompeSinLoDeSiempre,
            style: tema.textTheme.bodySmall?.copyWith(color: Colores.rojo),
          ),
        ],
      ],
    );
  }
}

class _Renglon extends StatelessWidget {
  const _Renglon({
    required this.texto,
    required this.nota,
    required this.bien,
    required this.sinBajar,
    this.suave = false,
  });

  final String texto;
  final String nota;
  final bool bien;

  /// No se bajo NUNCA. **Nunca lleva tic**: un tic verde dice «hecho», y decir
  /// «hecho» al lado de «sin bajar» es contradecirse en el mismo renglon.
  final bool sinBajar;

  final bool suave;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final color = bien ? Colores.verde : Colores.rojo;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            bien ? Icons.check : Icons.remove_circle_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: Aire.sm),
          Expanded(
            child: Text(
              texto,
              style: suave
                  ? tema.textTheme.bodyMedium?.copyWith(
                      color: Colores.tintaSuave,
                    )
                  : Tipos.mono(
                      tamano: 14,
                      peso: FontWeight.w600,
                      color: Colores.tinta,
                    ),
            ),
          ),
          const SizedBox(width: Aire.sm),
          Text(
            // «sin bajar» y no un «0»: un cero se lee como un dato y esto es un
            // fallo (caso S7).
            sinBajar ? 'sin bajar' : nota,
            style: tema.textTheme.bodySmall?.copyWith(
              color: sinBajar ? Colores.rojo : Colores.tintaSuave,
            ),
          ),
        ],
      ),
    );
  }
}
