import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/frescura/copia_bajada.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/selector.dart';
import '../../../diseno/tema.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../rutas/datos/mapa_en_vivo.dart';
import '../datos/almacen_api.dart';
import '../datos/coordenadas.dart';
import '../datos/geocodificar.dart';
import '../estado/estado_almacenes.dart';
import 'almacenes_de_la_ultima_bajada.dart';
import 'editor_almacen.dart';

/// Almacenes — `/warehouses`. Pliego: `pantallas.md` §6.
///
/// **Sólo con conexion, y se dice.** El almacen vive en Accesos y hay una sola
/// copia: no se encola. Se configura una vez, en la oficina. Sin red la pantalla
/// avisa y no acepta cambios, en vez de guardar algo que nadie va a poder
/// cotizar.
class PantallaAlmacenes extends ConsumerStatefulWidget {
  const PantallaAlmacenes({super.key});

  static const ruta = '/warehouses';

  @override
  ConsumerState<PantallaAlmacenes> createState() => _PantallaAlmacenesState();
}

class _PantallaAlmacenesState extends ConsumerState<PantallaAlmacenes> {
  bool _guardando = false;

  /// La regla vive en [cualSeConfigura], que es donde se prueba. Aqui solo se
  /// le dan las dos piezas: lo elegido en el desplegable de la pantalla y lo
  /// elegido en la barra de arriba.
  SucursalDeAccesos? _sucursal(List<SucursalDeAccesos> todas) =>
      cualSeConfigura(
        todas,
        elegidaEnLaPantalla: ref.watch(sucursalElegidaProvider),
        codigoDeLaBarra: ref.watch(codigoDeLaSucursalMiradaProvider),
      );

  /// Guarda **la lista completa** de la sucursal. Todo cambio pasa por aqui:
  /// alta, edicion y baja son la misma llamada con una lista distinta.
  Future<bool> _mandar(
    SucursalDeAccesos sucursal,
    List<AlmacenDeAccesos> lista,
  ) async {
    setState(() => _guardando = true);
    final bien = await ref
        .read(controlAlmacenesProvider.notifier)
        .guardar(sucursal.codigo, lista);
    if (mounted) setState(() => _guardando = false);
    return bien;
  }

  /// DONDE ABRIR EL MAPA de un almacen que todavia no tiene punto.
  ///
  /// El de otro almacen de la misma sucursal, si lo hay. El patron abria en la
  /// sucursal de quien mira —y su propio comentario cuenta que un administrador
  /// no tiene ninguna, asi que abria «en cualquier parte»—; aqui no hay
  /// coordenadas de sucursal en ningun sitio, pero sus almacenes SI las tienen y
  /// estan a dos calles. Si no hay ninguno con punto se abre en Cuba entera, que
  /// al menos se ve que hay que moverse.
  PuntoEnElMapa? _centroDeLaSucursal(SucursalDeAccesos sucursal, int? indice) {
    for (final (i, a) in sucursal.almacenes.indexed) {
      if (i == indice || a.sinPunto) continue;
      return PuntoEnElMapa(a.latitud!, a.longitud!);
    }
    return null;
  }

  Future<void> _abrirEditor(SucursalDeAccesos sucursal, {int? indice}) async {
    final almacen = indice == null ? null : sucursal.almacenes[indice];
    await abrirPanel<void>(
      context,
      (contexto) => StatefulBuilder(
        builder: (contexto, repintar) => EditorAlmacen(
          almacen: almacen,
          sucursal: sucursal.nombre,
          guardando: _guardando,
          // Las dos piezas de fuera, inyectadas desde aqui. El editor no las
          // busca el solo: asi se prueba entero sin que salga una peticion.
          geocodificador: ref.read(geocodificadorProvider),
          // El MISMO puerto que el mapa de la ruta, asi que en la APK y en el
          // escritorio esto ya trae el paquete de Cuba descargado por la linea
          // de `main.dart`, sin que aqui haya que saberlo.
          fondoDelMapa: ref.read(fondoDeCallesProvider),
          centroDelMapa: _centroDeLaSucursal(sucursal, indice),
          alQuitar: indice == null
              ? null
              : () async {
                  final quedan = [...sucursal.almacenes]..removeAt(indice);
                  final bien = await _mandar(sucursal, quedan);
                  if (bien && contexto.mounted) Navigator.of(contexto).pop();
                },
          alGuardar: (editado) async {
            repintar(() {});
            var lista = [...sucursal.almacenes];
            if (indice == null) {
              lista.add(editado);
            } else {
              lista[indice] = editado;
            }
            // Un solo principal: al marcar uno se desmarcan los demas, sobre la
            // lista entera y antes de mandarla.
            if (editado.principal) {
              lista = conUnSoloPrincipal(lista, indice ?? lista.length - 1);
            }
            final bien = await _mandar(sucursal, lista);
            if (bien && contexto.mounted) Navigator.of(contexto).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final datos = ref.watch(almacenesProvider);

    ref.listen<AvisoAlmacenes?>(controlAlmacenesProvider, (_, aviso) {
      if (aviso == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(aviso.texto),
            backgroundColor: aviso.esFallo ? tema.colorScheme.error : null,
          ),
        );
    });

    // SIN `Scaffold` propio: lo pone el armazon.
    //
    // Esta pantalla se escribio antes de que existiera el armazon, que ya trae barra
    // lateral, barra superior con el titulo y la franja de estado. Un `Scaffold` dentro de
    // otro apila dos superficies de Material y deja los avisos emergentes colgando del de
    // dentro, que es el que no se ve entero.
    //
    // Ver el contrato en `lib/navegacion/pantalla_registrada.dart`.
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Aire.xl),
        children: [
          Text('Almacenes', style: tema.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'El punto desde el que se mide cada domicilio. Un almacén sin '
            'coordenadas no sirve para cotizar: la distancia se mide desde '
            'aquí.',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          // DE CUÁNDO SON LOS QUE TIENE EL APARATO. Esta pantalla lee de Accesos
          // en vivo, pero lo que el aparato usa para medir el domicilio es su
          // copia, y esa es de la última vez que hubo red. Mirar aquí una lista
          // recién traída y salir a la calle con otra distinta es exactamente el
          // caso que esto dice en voz alta. En la web no pinta nada (regla 1).
          const AlmacenesDeLaUltimaBajada(),
          if (datos.error case final fallo?)
            _Fallo(
              fallo: fallo,
              // QUE TIENE EL APARATO DENTRO. «Sin conexión» a secas no dice si
              // el almacén está bajado o si este aparato no lo ha visto nunca,
              // y son dos cosas distintas: con la copia se sigue midiendo el
              // domicilio; sin ella no hay desde dónde.
              //
              // **En la web, nada de esto.** Allí la base nace vacía en cada
              // carga de la página, así que «este aparato no ha descargado los
              // almacenes todavía» es verdad siempre y no significa nada: no
              // hay aparato al que traerle el día ni copia del lunes con la que
              // seguir midiendo. Contarlo sería acusar de un problema que no
              // existe (`nucleo/plataforma.dart`, regla 1).
              enElAparato: ref.watch(trabajaSinConexionProvider)
                  ? ref.watch(almacenesEnElAparatoProvider).value
                  : null,
              enWeb: !ref.watch(trabajaSinConexionProvider),
              alReintentar: () => ref.invalidate(almacenesProvider),
            )
          else if (datos.value case final sucursales?)
            _Contenido(
              sucursales: sucursales,
              sucursal: _sucursal(sucursales),
              alElegirSucursal: (codigo) =>
                  ref.read(sucursalElegidaProvider.notifier).poner(codigo),
              alAbrir: _abrirEditor,
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Cargando…')),
            ),
        ],
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({
    required this.sucursales,
    required this.sucursal,
    required this.alElegirSucursal,
    required this.alAbrir,
  });

  final List<SucursalDeAccesos> sucursales;
  final SucursalDeAccesos? sucursal;
  final ValueChanged<String> alElegirSucursal;
  final void Function(SucursalDeAccesos sucursal, {int? indice}) alAbrir;

  @override
  Widget build(BuildContext context) {
    if (sucursales.isEmpty || sucursal == null) {
      // Tampoco es un callejon: se dice por que no hay nada que ensenar y donde
      // se arregla. **Sin boton**, porque el codigo de la sucursal se pone en
      // Accesos y desde aqui no se toca.
      return const Invitacion(
        icono: Icons.store_outlined,
        titulo: 'No hay ninguna sucursal a la vista con código en Accesos.',
        queEs:
            'Los almacenes son de la sucursal, y la sucursal se reconoce por '
            'su código (STG, HAB, CAM…). Sin ese código no hay a quién '
            'preguntarle por sus almacenes.',
        llamada:
            'Se arregla en Accesos, poniéndole el código a la sucursal. Si te '
            'debería salir alguna, pídelo a administración.',
      );
    }

    final actual = sucursal!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Con una sola sucursal se pinta su nombre sin desplegable: un
            // selector de una opcion no elige nada.
            if (sucursales.length == 1)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.store, size: 18),
                  const SizedBox(width: 6),
                  Text(actual.nombre),
                ],
              )
            else
              // EL `Selector` DE LA CASA Y NO UN `DropdownButton` — 28/09/2026.
              //
              // Jose, viendo `/warehouses` en un monitor con el desplegable
              // abierto: «q te dije de los dropdowns flotantes q los pusieras
              // como drawer».
              //
              // Esto era un `DropdownButton<String>` de Material a pelo, o sea
              // la unica pieza de elegir-una-opcion de toda la aplicacion que
              // no pasaba por `diseno/selector.dart`: por eso no se parecia a
              // ninguna otra, abria su menu flotante por su cuenta y en el
              // telefono es un cajon en todas las demas pantallas y aqui no.
              //
              // Y ademas NO CABIA. Medido a 390 px con `tester.getRect`
              // (`test/pantallas/almacenes/cuadra_con_el_borde_test.dart`): su
              // fila interna es un `Row(mainAxisSize: min)` sin nada flexible
              // dentro, asi que con «Almacén central · 2» se desbordaba **86 px
              // por la derecha** —la cebra amarilla y negra— y su icono de
              // tienda se pintaba en x=427,8 con la pantalla acabando en 390:
              // fuera de la pantalla, invisible y sin forma de llegar a el.
              //
              // El `Selector` no tiene ninguno de los dos problemas: encoge su
              // etiqueta con elipsis, y en el telefono abre cajon.
              //
              // Se conserva **lo que decia**: «Granma · 1» cuando tiene
              // almacenes y «X · sin almacenes» cuando no, que es lo que hace
              // que se vea de un vistazo cual hay que rellenar. Va en la `nota`
              // y no pegado al nombre porque el `Selector` ya tiene sitio para
              // eso, y asi la cuenta sale en gris al lado del nombre en vez de
              // alargar la etiqueta.
              ControlSenalado(
                nombre: Senalado.almacenesSucursal,
                child: Selector<String>(
                  icono: Icons.store,
                  tooltip: 'Sucursal',
                  etiquetaVacia: 'Elige sucursal',
                  valor: actual.codigo,
                  opciones: [
                    for (final s in sucursales)
                      OpcionSelector<String>(
                        valor: s.codigo,
                        etiqueta: s.nombre,
                        nota: s.almacenes.isEmpty
                            ? 'sin almacenes'
                            : '${s.almacenes.length}',
                      ),
                  ],
                  alElegir: alElegirSucursal,
                ),
              ),
            ControlSenalado(
              nombre: Senalado.almacenesNuevo,
              child: BotonPrincipal(
                icono: Icons.add,
                texto: 'Nuevo almacén',
                alPulsar: () => alAbrir(actual),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (actual.almacenes.isEmpty)
          // EL VACIO ES UNA INVITACION. Aqui se llega con Accesos contestando y
          // diciendo que esa sucursal no tiene ninguno: es un vacio de verdad,
          // y por eso se puede invitar a darlo de alta. El «no se ha
          // descargado» vive en `_Fallo` y dice otra cosa.
          //
          // El literal del pliego (§6) se conserva entero como llamada; lo que
          // se añade es que ES un almacén para quien reparte y que se rompe
          // mientras no haya ninguno.
          Invitacion(
            icono: Icons.warehouse_outlined,
            titulo: 'Sin almacenes en ${actual.nombre}',
            queEs:
                'El almacén es el sitio del que sale el camión y desde el que '
                'se mide la distancia hasta cada cliente. Lleva su dirección y '
                'su punto en el mapa.',
            siNoEsta:
                'Sin ninguno no hay desde dónde medir: los domicilios de esta '
                'sucursal salen sin precio y el asistente de rutas no pasa del '
                'punto de partida.',
            llamada:
                'Esta sucursal no tiene ninguno: sus domicilios no se pueden '
                'cotizar.',
            textoDelBoton: 'Nuevo almacén',
            iconoDelBoton: Icons.add,
            alPulsar: () => alAbrir(actual),
          )
        else
          for (final (indice, a) in actual.almacenes.indexed)
            // Sólo el primero se deja senalar por la Guia: hay uno por almacen y
            // dos con el mismo nombre no se pueden distinguir.
            ControlSenalado(
              nombre: Senalado.almacenesAbrir,
              senalable: indice == 0,
              child: ListTile(
                // SIN LA SANGRIA DE `ListTile` — 28/09/2026.
                //
                // `ListTile` trae 16 px de relleno propio a cada lado. Con el, en
                // esta pantalla el ojo bajaba por cuatro verticales distintas:
                // «Almacenes» y el selector de sucursal empezaban en x=24 —el
                // relleno de la lista— y el icono de cada almacen en x=40, con su
                // chevron acabando en 342 cuando el borde del contenido esta en
                // 366. Medido con `tester.getRect` a 390 px.
                //
                // La sangria de `ListTile` esta pensada para una lista que ocupa
                // la pantalla entera, sin nada al lado con que cuadrar. Aqui hay
                // un titulo, un parrafo y dos mandos encima, y todos empiezan
                // donde acaba el relleno de la lista: el que sobraba era este.
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  a.principal ? Icons.star : Icons.warehouse,
                  color: a.principal ? Colores.ambar : Colores.tintaSuave,
                ),
                title: Text(a.titulo),
                subtitle: Text(
                  [
                    a.direccion?.trim().isNotEmpty ?? false
                        ? a.direccion!.trim()
                        : 'sin dirección',
                    if (a.sinPunto) 'sin punto',
                    a.codigo?.trim().isNotEmpty ?? false
                        ? 'código ${a.codigo!.trim()}'
                        : 'sin código',
                    if (!a.activo) 'inactivo',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => alAbrir(actual, indice: indice),
              ),
            ),
      ],
    );
  }
}

class _Fallo extends StatelessWidget {
  const _Fallo({
    required this.fallo,
    required this.alReintentar,
    this.enElAparato,
    this.enWeb = false,
  });

  final Object fallo;
  final VoidCallback alReintentar;

  /// Lo que la bajada del dia dejo en la base. `null` mientras se mira, y
  /// siempre `null` en la web: alli no hay copia de la que hablar.
  final CopiaBajada? enElAparato;

  /// Si esto se esta viendo en un navegador. Cambia las PALABRAS, no la regla:
  /// el fallo se cuenta igual, pero sin mandar a mirar una señal que quien esta
  /// sentado en la oficina ya tiene (`nucleo/plataforma.dart`, `TextosDeCaida`).
  final bool enWeb;

  @override
  Widget build(BuildContext context) {
    final texto = switch (fallo) {
      // Literal NUEVO. Lo importante es la segunda frase: aqui no hay copia
      // local que editar, asi que sin red no hay nada que hacer en esta
      // pantalla y mas vale decirlo que dejar a alguien tecleando.
      //
      // En la web el titular cambia entero: si la pagina cargo, conexion hay, y
      // el que no contesta es el servidor. Es el mismo fallo de fondo que el del
      // 16/09/2026, cuando un CORS mal puesto se contaba como «comprueba la
      // señal» a alguien que estaba en la oficina.
      FalloDeRed() when enWeb =>
        'Accesos no contesta. La página cargó, así que conexión hay: los '
            'almacenes viven en Accesos y ahora mismo no responde. Prueba otra '
            'vez y, si sigue igual, avisa a la oficina.',
      FalloDeRed() =>
        'Sin conexión. Los almacenes viven en Accesos y se configuran con '
            'conexión: aquí no se guarda nada en el aparato. Vuelve a '
            'intentarlo cuando haya red.',
      // El literal del pliego cuando Accesos contesta que no.
      final FalloApi f => f.mensaje,
      _ =>
        'No se pudieron traer los almacenes de Accesos. Lo de abajo está vacío '
            'por eso, no porque no haya ninguno.',
    };
    // LO QUE HAY DENTRO DEL TELEFONO, y **sólo si el fallo es de red**: cuando
    // Accesos contesta y dice que no, la copia local no viene al caso.
    final copia = enElAparato;
    final Widget? dentro = (fallo is! FalloDeRed || copia == null)
        ? null
        : copia.seDescargo
        ? LoQueTieneElAparato(
            texto: copia.cuantos == 0
                ? 'La última bajada tampoco trajo ningún almacén: están vacíos, '
                      'no sin descargar.'
                : 'El aparato tiene ${copia.cuantos} almacén(es) de la última '
                      'bajada: desde ésos se sigue midiendo el domicilio '
                      'aunque esta pantalla no cargue.',
            enAmbar: copia.cuantos == 0,
          )
        : const LoQueTieneElAparato(
            texto:
                'Este aparato no ha descargado los almacenes todavía. No es '
                'que no haya ninguno: es que no están aquí. Bajan solos al '
                'traer el día desde el Panel.',
            enAmbar: true,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Text(texto, textAlign: TextAlign.center),
          ?dentro,
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: alReintentar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
