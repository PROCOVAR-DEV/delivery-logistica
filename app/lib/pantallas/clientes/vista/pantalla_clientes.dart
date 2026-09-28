import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/frescura/primera_bajada.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/barra_de_filtros.dart';
import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tema.dart';
import '../datos/repositorio_clientes.dart';
import '../estado/estado_clientes.dart';
import 'paginacion.dart';
import 'selector.dart';
import 'tabla_clientes.dart';

/// Clientes — `/customers`. Pliego: `pantallas.md` §4.
///
/// **Se mira sin conexion.** Todo lo que hay aqui sale de la base local,
/// incluida la distancia al almacen, que se calcula en el aparato. Lo unico que
/// cambia sin red es lo que dice el `RelojDeDatos` de arriba: de que hora es la
/// foto que se esta mirando. No escribe nada, asi que no hay nada que encolar.
class PantallaClientes extends ConsumerStatefulWidget {
  const PantallaClientes({super.key});

  static const ruta = '/customers';

  @override
  ConsumerState<PantallaClientes> createState() => _PantallaClientesState();
}

class _PantallaClientesState extends ConsumerState<PantallaClientes> {
  /// EL RESPIRO Y EL CONTROLADOR YA NO SON DE AQUI — 22/09/2026.
  ///
  /// Estaban copiados a mano en esta pantalla, otra vez en Vehiculos, otra en
  /// el asistente, y en el Tablero directamente no estaban: alli habia que dar
  /// Intro. Copiar un temporizador cinco veces es como se llega a «en una
  /// pantalla hay que dar Intro y en otra no». Todo eso vive ahora en
  /// `CajaDeBusqueda`, con sus pruebas.
  void _buscar(String texto) {
    final filtros = ref.read(filtrosClientesProvider);
    ref
        .read(filtrosClientesProvider.notifier)
        .poner(filtros.copiar(q: texto.trim().isEmpty ? null : texto.trim()));
  }

  void _cambiar(FiltrosClientes nuevos) =>
      ref.read(filtrosClientesProvider.notifier).poner(nuevos);

  @override
  Widget build(BuildContext context) {
    final pagina = ref.watch(clientesProvider);
    final filtros = ref.watch(filtrosClientesProvider);
    final frescura = ref.watch(frescuraClientesProvider);
    final sinSubir = ref.watch(sinSubirProvider).value ?? 0;
    // POR QUE ESTA VACIA LA COPIA. En la web la base nace vacia en cada carga de
    // la pagina, asi que el primer segundo esta pantalla acusaba al servidor de
    // no haber mandado nada («Esta pantalla no se ha descargado todavía. Con
    // conexión baja sola») y el reloj de arriba lo repetia en ambar. Las dos
    // cosas eran mentira: los clientes entraban un segundo despues.
    final porQue = ref.watch(porQueEstaVacioProvider);

    // SIN `Scaffold` propio: lo pone el armazon.
    //
    // Esta pantalla se escribio antes de que existiera el armazon, que ya trae barra
    // lateral, barra superior con el titulo y la franja de estado. Un `Scaffold` dentro de
    // otro apila dos superficies de Material y deja los avisos emergentes colgando del de
    // dentro, que es el que no se ve entero.
    //
    // Ver el contrato en `lib/navegacion/pantalla_registrada.dart`.
    // `p-3 sm:p-6` de delivery.
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.idioma;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.all(estrecho ? Aire.md : Aire.xl),
        children: [
          _Cabecera(
            // Mientras no hay dato todavia no se sabe de cuando es: se dice
            // «sin descargar» y no una hora inventada.
            estado: frescura.value ?? const SinDescargar(),
            sinSubir: sinSubir,
            pagina: pagina.value,
          ),
          const SizedBox(height: Aire.lg),
          _Filtros(
            filtros: filtros,
            datos: pagina.value,
            alBuscar: _buscar,
            alCambiar: _cambiar,
            // `quitar()` deja `q` en null, y la caja se vacia sola con el: el
            // texto de la caja manda desde fuera. Antes hacia falta acordarse
            // de limpiar el controlador a mano aqui.
            alQuitar: ref.read(filtrosClientesProvider.notifier).quitar,
          ),
          const SizedBox(height: Aire.lg),
          // El dato viejo NO se borra mientras refresca: el giro de
          // `actualizando…` ya lo dice arriba, y quitar la lista de golpe deja
          // a alguien mirando un hueco con el dedo en la fila que iba a leer.
          if (pagina.error case final fallo?)
            _Aviso(texto: 'No se pudo leer la lista local. $fallo')
          else if (pagina.value case final datos?)
            _Lista(
              datos: datos,
              filtros: filtros,
              porQue: porQue,
              alIr: (n) =>
                  ref.read(filtrosClientesProvider.notifier).aPagina(n),
            )
          else
            const _Aviso(texto: 'Cargando…'),
        ],
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.estado,
    required this.sinSubir,
    required this.pagina,
  });

  final EstadoFrescura estado;
  final int sinSubir;
  final PaginaClientes? pagina;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final total = pagina?.total ?? 0;
    // EL PAGINADOR VA CON SU TABLA, Y AQUI ARRIBA NO VA NADA — 28/09/2026.
    //
    // Jose, en `/customers`: «por q el paginador esta alla arriba tan distante
    // a su table anormal».
    //
    // Tenia razon y no era sólo distancia: entre el «‹ 5 / 55 ›» del subtitulo
    // y la tabla que paginaba estaba **la barra de filtros entera**, asi que
    // los dos mandos que mueven la lista quedaban por encima de cinco que la
    // filtran, y no se leian como suyos. Pedidos y Rutas no hacen eso: su
    // paginacion es el pie de su tabla y nada mas. Clientes ya tenia ese pie
    // —`PaginacionLarga`, dentro de la misma `TarjetaDeTabla`—, asi que lo de
    // arriba era un segundo juego de mandos para lo mismo.
    //
    // Se va **entero**: los botones, y tambien el «· página 5 de 55» del
    // subtitulo, que sin botones al lado sólo dice donde estas sin dejarte ir a
    // ningun sitio — y el pie ya lo dice, pegado a los botones que lo mueven.
    // Lo que se queda arriba es lo que NO esta abajo: cuantos hay en total.
    //
    // El pliego (`pantallas.md` §4) pedia los dos juegos «para no tener que
    // subir 50 filas»; esa es la razon por la que se puso y por la que se
    // queda el de abajo. Nos separamos de ahi a proposito y por lo que se ve en
    // pantalla: con 50 filas y la barra de filtros en medio, el de arriba no
    // ahorraba el viaje, lo confundia.
    final subtitulo = StringBuffer(
      'Clientes de PEDIDO (sincronizados, sólo con geo) + los manuales de '
      'delivery. $total en total',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Clientes', style: tema.textTheme.headlineSmall),
            ),
            // Siempre visible, en las 7 pantallas (caso S8): sin esto, unos
            // datos de anteayer son indistinguibles de unos al dia.
            //
            // **En la web no pinta nada, y lo decide el propio widget** — asi
            // no hay que acordarse en las siete pantallas. Ahi «Sin descargar
            // todavía» en ámbar, durante el segundo que tarda en entrar la
            // primera bajada, era el mismo mensaje falso de abajo puesto arriba
            // del todo y en el color que pide que lo miren.
            RelojDeDatos(estado: estado, sinSubir: sinSubir),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitulo.toString(),
          style: tema.textTheme.bodySmall?.copyWith(color: Colores.tintaSuave),
        ),
      ],
    );
  }
}

class _Filtros extends StatelessWidget {
  const _Filtros({
    required this.filtros,
    required this.datos,
    required this.alBuscar,
    required this.alCambiar,
    required this.alQuitar,
  });

  final FiltrosClientes filtros;
  final PaginaClientes? datos;
  final ValueChanged<String> alBuscar;
  final ValueChanged<FiltrosClientes> alCambiar;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    final municipios = datos?.municipios ?? const <Faceta>[];
    final zonas = datos?.zonas ?? const <Faceta>[];
    final vendedores = datos?.vendedores ?? const <Faceta>[];

    // La colocación la decide `BarraDeFiltros`, igual que en Pedidos, Tablero y
    // Rutas. Antes era un `Wrap` propio con 12/12 de separación —Pedidos usaba
    // 8/8 y Almacenes 12/8—, y los seis filtros se apilaban en escalones
    // desiguales en el teléfono. Ver `lib/diseno/barra_de_filtros.dart`.
    //
    // Los 260 de la caja se quedan: la pista es larga y con los 220 de por
    // defecto se cortaría. En el teléfono da igual, porque ahí la caja ocupa
    // todo el ancho pase lo que pase (`caja_de_busqueda.dart`).
    return BarraDeFiltros(
      margen: EdgeInsets.zero,
      busqueda: CajaDeBusqueda(
        valor: filtros.q ?? '',
        ancho: 260,
        pista: 'Buscar por nombre, dirección o municipio…',
        alBuscar: alBuscar,
      ),
      accionFinal: filtros.hayQueQuitar
          ? TextButton.icon(
              onPressed: alQuitar,
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Quitar filtros'),
            )
          : null,
      filtros: [
        // Los selectores de la base sólo aparecen si tienen mas de una opcion:
        // un desplegable con una sola opcion no filtra nada y ocupa sitio.
        if (municipios.length > 1)
          SelectorFiltro<String>(
            titulo: 'Municipio del cliente',
            textoTodos: 'Todos los municipios',
            icono: Icons.location_city,
            valor: filtros.municipio,
            opciones: [
              for (final f in municipios)
                OpcionSelector(
                  valor: f.valor,
                  etiqueta: f.valor,
                  nota: '${f.clientes}',
                ),
            ],
            alElegir: (v) => alCambiar(filtros.copiar(municipio: v)),
          ),
        if (vendedores.length > 1)
          SelectorFiltro<String>(
            titulo: 'Vendedor que lo atiende',
            textoTodos: 'Todos los vendedores (${vendedores.length})',
            icono: Icons.person,
            valor: filtros.vendedor,
            opciones: [
              for (final f in vendedores)
                OpcionSelector(
                  valor: f.valor,
                  etiqueta: f.valor,
                  nota: '${f.clientes}',
                ),
            ],
            alElegir: (v) => alCambiar(filtros.copiar(vendedor: v)),
          ),
        SelectorFiltro<double>(
          titulo: 'A qué distancia del almacén',
          textoTodos: 'A cualquier distancia',
          icono: Icons.straighten,
          valor: filtros.kmMax,
          opciones: const [
            OpcionSelector(valor: 5.0, etiqueta: 'Hasta 5 km'),
            OpcionSelector(valor: 10.0, etiqueta: 'Hasta 10 km'),
            OpcionSelector(valor: 20.0, etiqueta: 'Hasta 20 km'),
            OpcionSelector(valor: 50.0, etiqueta: 'Hasta 50 km'),
          ],
          alElegir: (v) => alCambiar(filtros.copiar(kmMax: v)),
        ),
        SelectorFiltro<bool>(
          titulo: 'Si tiene teléfono',
          textoTodos: 'Con y sin teléfono',
          icono: Icons.phone,
          valor: filtros.telefono,
          opciones: [
            const OpcionSelector(valor: true, etiqueta: 'Con teléfono'),
            OpcionSelector(
              valor: false,
              etiqueta: 'Sin teléfono',
              nota: '${datos?.sinTelefono ?? 0}',
            ),
          ],
          alElegir: (v) => alCambiar(filtros.copiar(telefono: v)),
        ),
        if (zonas.length > 1)
          SelectorFiltro<String>(
            titulo: 'Zona de reparto',
            textoTodos: 'Todas las zonas',
            icono: Icons.map,
            valor: filtros.zona,
            opciones: [
              for (final f in zonas)
                OpcionSelector(
                  valor: f.valor,
                  etiqueta: f.valor,
                  nota: '${f.clientes}',
                ),
            ],
            alElegir: (v) => alCambiar(filtros.copiar(zona: v)),
          ),
        SelectorFiltro<OrigenCliente>(
          titulo: 'De dónde salió el cliente',
          textoTodos: 'De PEDIDO y manuales',
          icono: Icons.input,
          valor: filtros.origen,
          opciones: const [
            OpcionSelector(
              valor: OrigenCliente.pedido,
              etiqueta: 'Sólo los de PEDIDO',
            ),
            OpcionSelector(
              valor: OrigenCliente.manual,
              etiqueta: 'Sólo los manuales',
            ),
          ],
          alElegir: (v) => alCambiar(filtros.copiar(origen: v)),
        ),
      ],
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({
    required this.datos,
    required this.filtros,
    required this.porQue,
    required this.alIr,
  });

  final PaginaClientes datos;
  final FiltrosClientes filtros;

  /// Por que esta vacia la copia: el aparato no la bajo, la web todavia la
  /// espera, o la web no la pudo traer. Ver `frescura/primera_bajada.dart`.
  final PorQueEstaVacio porQue;

  final ValueChanged<int> alIr;

  @override
  Widget build(BuildContext context) {
    if (datos.clientes.isEmpty) {
      // Cuatro vacios distintos y se confunden con facilidad. Los de la bajada
      // van primero porque son los unicos que NO son un dato: son un fallo
      // disfrazado de lista vacia (caso S7) — o, en la web, ni siquiera eso.
      if (!datos.seDescargo) {
        return switch (porQue) {
          PorQueEstaVacio.noSeDescargo => const _Aviso(
            texto: SinDescargar.textoDeLaPantallaVacia,
          ),
          // La web, el primer segundo: **cargando y nada mas**. No se acusa a
          // nadie de nada porque todavia no se ha mirado nada.
          PorQueEstaVacio.todaviaBajando => const _Aviso(texto: 'Cargando…'),
          // Y si de verdad no llego, se dice y se deja entrar: los filtros de
          // arriba siguen puestos y la pagina se puede recargar.
          PorQueEstaVacio.noPudoBajar => _Aviso(
            texto: TextosDeLaWeb.noPudoBajar('los clientes'),
          ),
        };
      }
      if (filtros.hayQueQuitar ||
          filtros.kmMax != null ||
          filtros.telefono != null ||
          filtros.vendedor != null) {
        return const _Aviso(texto: 'Sin resultados.');
      }
      return const _Aviso(
        texto:
            'Sin clientes todavía. Los de PEDIDO aparecen solos cuando '
            'tengan geolocalización.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (datos.almacenDeReferencia == null)
          const _Aviso(
            texto:
                'Esta sucursal no tiene ningún almacén con coordenadas: '
                'aquí no se puede medir la distancia.',
          ),
        // La tabla y su paginacion, en la MISMA caja: en delivery la
        // paginacion es el pie de la tabla, no una barra suelta debajo.
        TarjetaDeTabla(
          pie: PaginacionLarga(
            pagina: datos.pagina,
            paginas: datos.paginas,
            desde: datos.desde,
            hasta: datos.hasta,
            total: datos.total,
            alIr: alIr,
          ),
          child: TablaClientes(
            clientes: datos.clientes,
            conDistancia: filtros.kmMax != null,
          ),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: Aire.lg),
    child: Text(
      texto,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Colores.tintaSuave),
    ),
  );
}
