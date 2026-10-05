import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/tarjeta.dart';
import '../../../diseno/tema.dart';
import '../../../navegacion/estado_navegacion.dart';
import '../../../nucleo/plataforma.dart';
import '../../../nucleo/proveedores.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../pedidos/datos/filtros_en_la_url.dart';
import '../../pedidos/datos/filtros_pedidos.dart';
import '../datos/consultas_panel.dart';
import '../datos/textos_de_las_cifras.dart';
import '../estado/panel_estado.dart';
import 'estado_del_dia.dart';
import 'paso_a_paso.dart';

/// EL PANEL — la pantalla de la manana (pliego §1).
///
/// Dice cuanto hay pendiente de repartir y por donde empezar. Todo sale de la
/// base local, asi que sirve igual sin conexion; lo unico que cambia es lo que
/// diga la franja de estado de arriba.
class PantallaPanel extends ConsumerWidget {
  const PantallaPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cifras = ref.watch(cifrasDelPanelProvider);
    // Mientras carga, ceros: es lo que hace la de Next y evita que la pantalla
    // salte de vacia a llena cambiando de altura debajo del dedo.
    final c = cifras.value ?? CifrasDelPanel.cero;

    // `p-3 sm:p-6` de delivery: 12 px en el telefono, 24 en pantalla grande.
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.idioma;

    return ListView(
      padding: EdgeInsets.all(estrecho ? Aire.md : Aire.xl),
      children: [
        // EL PASO A PASO DE LA PUESTA EN MARCHA, **por encima del estado del
        // dia**, y sólo cuando falta algo.
        //
        // Los dos no compiten nunca por el primer sitio, y esa es toda la regla:
        // este widget se pinta sólo si el aparato YA TIENE datos y aun asi falta
        // configuracion. Sin datos no se sabe que falta y manda `EstadoDelDia`,
        // que es el que trae el dia; con datos y sin camiones, traer el dia otra
        // vez no va a hacer aparecer ninguno, asi que lo primero es configurar.
        // El porque entero, en `paso_a_paso.dart`.
        const ControlSenalado(
          nombre: Senalado.panelPasoAPaso,
          child: PasoAPaso(),
        ),

        // EL ESTADO DEL DIA, lo primero de la pantalla y por encima de las
        // cifras. **Una sola pieza y no dos botones**: la pantalla ya sabe si
        // toca traer, enviar o solo decir que se esta trabajando sin conexion,
        // y eso es trabajo que no tiene por que hacer el logistico. El porque
        // de que este aqui y no en `/sincronizacion` esta en el propio widget.
        //
        // **En web no se monta**: alli no hay dia que traer a mano —se
        // sincroniza solo— y «Trabajando sin conexion» es una frase que a quien
        // abre un navegador no le va a pasar nunca (`nucleo/plataforma.dart`).
        if (ref.watch(trabajaSinConexionProvider)) ...[
          const EstadoDelDia(),
          const SizedBox(height: Aire.xl),
        ],
        // DE QUIÉN SON LAS CIFRAS. Las siete salen de la sucursal del selector
        // de arriba, y eso no se veía. El 28/09/2026 fue la mitad de la
        // confusión: la ruta completada que Jose buscaba existía, pero era de La
        // Habana y él estaba mirando Santiago.
        //
        // Es un rótulo, no un aviso: dice el alcance de los números que vienen
        // debajo, igual que la hoja del almacén dice de dónde sale la mercancía.
        const _DeQuienSonLasCifras(),
        _Cifras(c),
        // `mb-8`: las cuatro cifras de arriba respiran mas que el resto, que es
        // lo que las separa de «el detalle».
        const SizedBox(height: Aire.xxl),
        LayoutBuilder(
          builder: (context, medidas) {
            // Por debajo de 768 px las dos tarjetas de abajo se apilan: una
            // lista de sucursales a media anchura no deja sitio ni al nombre.
            if (medidas.maxWidth < Anchos.entrega) {
              return Column(
                children: [
                  _PendientePorSucursal(cifras: c),
                  const SizedBox(height: Aire.xl),
                  const _AccionesRapidas(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _PendientePorSucursal(cifras: c)),
                const SizedBox(width: Aire.xl),
                const Expanded(child: _AccionesRapidas()),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// LA LÍNEA QUE DICE DE QUÉ SUCURSAL SON LAS CUATRO CIFRAS.
class _DeQuienSonLasCifras extends ConsumerWidget {
  const _DeQuienSonLasCifras();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final texto = TextosDeLasCifras.deQuienSon(
      todas: (ref.watch(sucursalMiradaProvider) ?? '').isEmpty,
      sucursal: ref.watch(nombreDeLaSucursalMiradaProvider).value,
    );
    // Mientras el nombre no haya bajado no se escribe nada, y tampoco se deja el
    // hueco: en la web eso dura un segundo y una línea vacía que aparece y
    // desaparece mueve las cuatro tarjetas debajo del dedo.
    if (texto == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Aire.md),
      child: Text(
        texto,
        style: Tipos.texto(
          tamano: 12,
          peso: FontWeight.w600,
          color: Colores.tintaSuave,
          interletra: 0.3,
        ),
      ),
    );
  }
}

/// Las 4 tarjetas: en fila en escritorio, **1 columna en movil** (§1).
class _Cifras extends ConsumerWidget {
  const _Cifras(this.c);

  final CifrasDelPanel c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tarjetas = <Widget>[
      TarjetaDeCifra(
        etiqueta: 'Pedidos sin ruta',
        valor: Numeros.entero(c.sinRuta),
        subtexto: '${Numeros.kgRedondeado(c.pesoPendiente)} por mover',
        // Ambar con > 0: hay trabajo parado. Con 0, primario: no hay nada que
        // mirar y pintarlo en ambar seria gastar la senal.
        color: c.sinRuta > 0 ? Colores.ambar : null,
        icono: Icons.inventory_2_outlined,
      ),
      TarjetaDeCifra(
        etiqueta: 'Rutas en marcha',
        valor: Numeros.entero(c.rutasActivas),
        icono: Icons.route_outlined,
      ),
      // Cada tarjeta con SU color de marca, como en la de Next: entregados en
      // el verde del `--secondary`, flota en el naranja del `--accent`. Cuatro
      // franjas azules iguales obligan a leer la etiqueta cada vez.
      _EntregadosHoy(
        c,
        medianoche: ref.watch(consultasPanelProvider).medianoche,
      ),
      TarjetaDeCifra(
        etiqueta: 'Vehículos',
        valor: '${c.vehiculosEnRuta} / ${c.totalVehiculos}',
        subtexto: 'en ruta / total',
        color: Colores.acento,
        icono: Icons.local_shipping_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, medidas) {
        if (medidas.maxWidth < Anchos.entrega) {
          return Column(
            children: [
              for (final t in tarjetas)
                Padding(
                  padding: const EdgeInsets.only(bottom: Aire.lg),
                  child: SizedBox(width: double.infinity, child: t),
                ),
            ],
          );
        }
        // `IntrinsicHeight` para que las cuatro midan lo mismo aunque solo una
        // tenga subtexto. Sin el, `stretch` dentro de un `ListView` pide altura
        // infinita y la pantalla no llega a pintarse.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tarjetas.length; i++) ...[
                if (i > 0) const SizedBox(width: Aire.lg),
                Expanded(child: tarjetas[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// «ENTREGADOS HOY», Y SE PUEDE LLEGAR A LO QUE SE ENTREGÓ.
///
/// El 28/09/2026 Jose miró esta tarjeta y el Historial de Rutas:
///
/// > «me dice q entregado uno y en hsitorial me sale vacio eso q se entrego si no
/// > se ah completado nada»
///
/// Los números estaban bien los dos. El pedido se entregó a las 19:44 en una ruta
/// que sigue **en curso**, y el Historial cuenta rutas CERRADAS; encima la única
/// cerrada que había era de otra sucursal. **El fallo no estaba en las cuentas:
/// estaba en que un contador que dice «1» y no deja ver CUÁL obliga a adivinar o
/// a preguntar.**
///
/// Se arregla como ya lo hacen las acciones rápidas de abajo: `context.go` a la
/// pantalla que tiene el detalle, con los filtros en la dirección. Los filtros
/// los arma `filtrosDeEntregadosDesde` —en el fichero de los filtros, junto a
/// ellos— con la MISMA medianoche que usa la consulta de este contador, que es lo
/// que hace que la lista no pueda decir otro número. Atado con
/// `test/pantallas/pedidos/entregados_hoy_cuadra_test.dart` (`CLAUDE.md` §3-bis:
/// una prueba, no un comentario).
///
/// **Con cero no se toca**: no hay lista que enseñar, y un gesto que lleva a una
/// pantalla vacía es peor que ninguno.
class _EntregadosHoy extends StatelessWidget {
  const _EntregadosHoy(this.c, {required this.medianoche});

  final CifrasDelPanel c;

  /// Las 00:00 de hoy **con el reloj del aparato**, tal cual las calcula
  /// `ConsultasPanel`. Entra por parámetro y no se vuelve a calcular aquí: dos
  /// medianoches son dos verdades, y la que sobra es la que alguien mira.
  final DateTime medianoche;

  @override
  Widget build(BuildContext context) {
    // LA TARJETA SE PULSA Y YA ESTÁ — 28/09/2026, por la noche.
    //
    // Esto nació con un `GestureDetector` + `MouseRegion` + `Semantics` + un
    // `Stack` con una flecha encima, porque `TarjetaDeCifra` no llevaba gesto
    // propio y era del sistema de diseño. O sea: reconstruir a mano la señal de
    // «esto se pulsa» que `Tarjeta` ya sabe dar —con su levantada al pasar por
    // encima— y que el resto de la aplicación usa.
    //
    // En cuanto el fichero quedó libre se le puso `alPulsar` a `TarjetaDeCifra`
    // y todo aquello sobra. Está contado en `diseno/tarjeta.dart`.
    //
    // **Con cero entregados NO se pulsa**: un gesto que acaba en una pantalla
    // vacía es peor que ninguno.
    return TarjetaDeCifra(
      key: c.entregadosHoy > 0
          ? const ValueKey(TextosDeLasCifras.verLosEntregados)
          : null,
      etiqueta: 'Entregados hoy',
      valor: Numeros.entero(c.entregadosHoy),
      subtexto: TextosDeLasCifras.entregadosHoy(
        entregadosHoy: c.entregadosHoy,
        enRutaSinCerrar: c.entregadosHoyEnRutaSinCerrar,
      ),
      color: Colores.secundario,
      icono: Icons.check_circle_outline,
      alPulsar: c.entregadosHoy <= 0
          ? null
          : () => context.go(
              FiltrosEnLaUrl.direccion(filtrosDeEntregadosDesde(medianoche)),
            ),
    );
  }
}

class _PendientePorSucursal extends ConsumerWidget {
  const _PendientePorSucursal({required this.cifras});

  final CifrasDelPanel cifras;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final filas = ref.watch(pendientePorSucursalProvider);

    // EL IMPORTE, EN LA MONEDA QUE SE ESTA MIRANDO. Se guarda siempre en USD y
    // el CUP se calcula aqui, al pintarlo: guardar los dos seria tener dos
    // verdades que se separan en cuanto se mueva la tasa.
    //
    // La tasa es la de ESTA sucursal o no hay ninguna. Con «todas» o con una
    // sucursal sin tasa, `monedaEfectivaProvider` se queda en USD y el porque
    // lo dice la barra de arriba; lo que no pasa nunca es convertir con la de
    // otra.
    final tasa = ref.watch(tasaDeLaMiradaProvider);
    final moneda = ref.watch(monedaEfectivaProvider);

    return Tarjeta(
      titulo: 'Pendiente por sucursal',
      icono: Icons.location_city_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          switch (filas) {
            AsyncValue<List<PendienteDeSucursal>>(:final value?)
                when value.isEmpty =>
              EstadoVacio('No queda nada sin ruta.'),
            AsyncValue<List<PendienteDeSucursal>>(:final value?) => Column(
              children: [
                for (final f in value)
                  // Cada sucursal, separada de la siguiente por la linea fina
                  // (`border-b last:border-0` de la de Next).
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colores.linea)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              f.sucursal,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Los kg y el conteo, EN COLUMNA: son dos numeros que
                          // se comparan de arriba abajo, no dos palabras.
                          SizedBox(
                            width: 90,
                            child: Text(
                              Numeros.kgRedondeado(f.pesoKg),
                              textAlign: TextAlign.right,
                              style: Tipos.mono(
                                tamano: 12,
                                color: Colores.tintaSuave,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              Numeros.entero(f.pedidos),
                              textAlign: TextAlign.right,
                              style: Tipos.mono(
                                tamano: 14,
                                peso: FontWeight.w600,
                                color: Colores.tinta,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            _ => SizedBox(height: 48),
          },
          Divider(height: Aire.xl, color: Colores.linea),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Domicilios cobrados',
                  style: tema.textTheme.bodyMedium?.copyWith(
                    color: Colores.tintaSuave,
                  ),
                ),
              ),
              // El dinero cobrado va en el verde de marca y en mono: es la
              // unica cifra de la tarjeta que se apunta.
              Text(
                tasa.importe(cifras.totalDomicilios, moneda),
                style: Tipos.mono(
                  tamano: 14,
                  peso: FontWeight.w700,
                  color: Colores.secundario,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccionesRapidas extends StatelessWidget {
  const _AccionesRapidas();

  @override
  Widget build(BuildContext context) => Tarjeta(
    titulo: 'Acciones Rápidas',
    icono: Icons.bolt_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cada una con SU color, como los tres bloques tintados de la de Next
        // (`bg-blue-50`, `bg-green-50`, `bg-yellow-50`): tres filas grises
        // iguales no se distinguen y hay que leerlas cada vez.
        _Accion(
          'Planificar Rutas',
          '/routes',
          Icons.route_outlined,
          Colores.enCurso,
          Colores.enCursoFondo,
        ),
        SizedBox(height: Aire.md),
        _Accion(
          'Ver Reportes',
          '/reports',
          Icons.assessment_outlined,
          Colores.verde,
          Colores.verdeFondo,
        ),
        SizedBox(height: Aire.md),
        _Accion(
          'Gestionar Flota',
          '/vehicles',
          Icons.local_shipping_outlined,
          Colores.ambar,
          Colores.ambarFondo,
        ),
      ],
    ),
  );
}

class _Accion extends StatelessWidget {
  const _Accion(this.texto, this.ruta, this.icono, this.color, this.fondo);

  final String texto;
  final String ruta;
  final IconData icono;
  final Color color;
  final Color fondo;

  @override
  Widget build(BuildContext context) => Material(
    color: fondo,
    borderRadius: BorderRadius.circular(Radios.lg),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radios.lg),
      // `Ver Reportes` es una de las DOS puertas a `/reports`: la otra es
      // escribir la URL. Reportes no esta en el menu (§8.1), asi que si este
      // enlace se cae, la pantalla deja de existir para quien no sepa la
      // direccion.
      onTap: () => context.go(ruta),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Aire.md,
          vertical: Aire.md,
        ),
        child: Row(
          children: [
            Icon(icono, size: 20, color: color),
            const SizedBox(width: Aire.md),
            Expanded(
              child: Text(
                texto,
                style: Tipos.texto(
                  tamano: 14,
                  peso: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: color.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    ),
  );
}
