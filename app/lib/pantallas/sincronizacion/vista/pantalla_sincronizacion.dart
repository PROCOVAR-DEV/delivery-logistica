import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cargando.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tarjeta.dart';
import '../../../diseno/tema.dart';
import '../../../navegacion/estado_navegacion.dart';
import '../../../nucleo/plataforma.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../datos/panel_sincronizacion.dart';
import 'fila_de_rechazo.dart';
import '../estado/proveedores_sincronizacion.dart';

/// SINCRONIZACION — `/sincronizacion`. El panel de `GET /sync/estado`.
///
/// Es lo que hoy no existe en ningun sitio y lo mas valioso de todo: **que se
/// vea que Palma lleva desde el martes sin subir, y se pueda llamar**. Sin esto
/// un logistico cierra el dia, se va a su casa con el cierre de la ruta en el
/// telefono y nadie se entera hasta que no cuadra el inventario.
///
/// Tres cosas que no se negocian y que estan aqui a proposito:
///
///  1. **Lo que lleva mucho sin subir se ve sin leer numeros**: color y marca.
///     Esta pantalla se mira de reojo.
///  2. **«Nunca ha subido» no es «lleva 0 horas»**: otro color, otra marca y
///     otro texto. Y sale el primero, porque asi lo ordena el servidor.
///  3. **Los rechazados salen con su motivo y su hora.** No se descartan en
///     silencio: es la regla de la casa y aqui es donde se ve.
///
/// De escritorio y **con conexion**. Sin red dice que no puede saberlo; no
/// ensena una lectura vieja como si fuera de ahora.
///
/// **En la web no existe nada de esto** (regla 1 de `CLAUDE.md`): ni aparatos,
/// ni cola, ni bandeja, ni la peticion a `/sync/estado`. La ruta si sigue
/// existiendo —el enlace guardado tiene que llevar a algo que se explique, no a
/// un «no hay ninguna pantalla aqui»— y lo que se ve es `_NoVaEnLaWeb`. El
/// porque entero esta en `registro.dart` y en la guarda de `build`.
///
/// SIN `Scaffold` ni `AppBar` propios: los pone el armazon
/// (`navegacion/pantalla_registrada.dart`).
class PantallaSincronizacion extends ConsumerWidget {
  const PantallaSincronizacion({super.key});

  /// `/sincronizacion`, y **no `/sync`, que es del proxy** — 17/09/2026.
  ///
  /// En el servidor, Traefik reparte por camino:
  ///
  /// ```
  /// Host(`reparto.procovar.cloud`) && PathPrefix(`/api`)   -> el reparto
  /// Host(`reparto.procovar.cloud`) && PathPrefix(`/sync`)  -> el sincronizador
  /// Host(`reparto.procovar.cloud`)                         -> esta aplicacion
  /// ```
  ///
  /// Con esta pantalla en `/sync` se llegaba navegando por el menu —eso lo
  /// resuelve el enrutador dentro del navegador, sin pedirle nada al servidor—
  /// pero **recargar ahi, o abrir el enlace, no llegaba nunca a la aplicacion**:
  /// lo atrapaba el sincronizador y contestaba `401`. O sea, la persona se
  /// quedaba fuera mirando un error de un servicio del que no sabe nada.
  ///
  /// Se mueve la pantalla y no el proxy a proposito: el prefijo `/sync` es la
  /// direccion que ya usan las APK instaladas para subir y bajar, y cambiarlo
  /// deja sin sincronizar a todo el que no se haya actualizado.
  static const ruta = '/sincronizacion';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // REGLA 1, Y SE PREGUNTA ANTES DE MIRAR NADA MÁS.
    //
    // La salida es lo primero del método a propósito: mientras no se lea
    // `estadoDelSincronizadorProvider`, ese provider **no se crea**, así que en
    // la web no sale ni una petición a `/sync/estado`. Eso no es una sutileza
    // de Riverpod, es la corrección entera: el sincronizador contesta `401` a
    // un navegador —no es un aparato dado de alta—, el cliente da la sesión por
    // muerta y el portero rebota a `/acceso`, que vuelve a entrar y vuelve a
    // pedir. Treinta peticiones en un minuto, medidas en producción el
    // 22/09/2026. Un rechazo permanente contra un reintentador es un bucle, no
    // una defensa.
    //
    // Y se sale ANTES de la cabecera, no sólo del panel: el subtítulo de esta
    // pantalla («qué aparato lleva sin subir, qué le queda pendiente…») y el
    // «Cargando el estado de los aparatos…» son justo lo que la regla 1 no
    // deja enseñar en un navegador.
    //
    // Se pregunta AQUÍ y en ningún otro sitio. La misma pregunta repetida en el
    // provider sería el §3-bis de `CLAUDE.md` en pequeño: dos guardas que el
    // día que una cambie dejan a la otra mintiendo. La lección es de
    // `pantallas/mapa/pantalla_mapa_sin_conexion.dart`, donde la segunda guarda
    // se quitó al romperla y ver que la prueba seguía verde.
    if (!ref.watch(trabajaSinConexionProvider)) return const _NoVaEnLaWeb();

    final lectura = ref.watch(estadoDelSincronizadorProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Aire.xl),
        children: [
          _Cabecera(
            alRecargar: () => ref.invalidate(estadoDelSincronizadorProvider),
          ),
          const SizedBox(height: 12),
          // El fallo se mira ANTES que el valor, y no al reves: con `value`
          // primero, una recarga que no llega dejaria en pantalla la lectura
          // anterior con pinta de recien traida.
          if (lectura.error case final fallo?)
            _Fallo(
              fallo: fallo,
              alReintentar: () =>
                  ref.invalidate(estadoDelSincronizadorProvider),
            )
          else if (lectura.value case final datos?)
            _Panel(lectura: datos)
          else
            const Cargando(TextosDeSincronizacion.cargando),
        ],
      ),
    );
  }
}

/// LO QUE SE VE EN UN NAVEGADOR, y es todo lo que se ve.
///
/// Sin cabecera de la pantalla, sin botón de «Actualizar» y **sin una sola
/// petición**: no hay nada que actualizar porque no hay nada que leer. La barra
/// lateral del armazón sigue ahí al lado, así que de aquí se sale a cualquier
/// sitio sin necesidad de un botón propio.
///
/// No es un error y no se pinta como tal: en ámbar sería «mira esto», en rojo
/// «esto es un problema», y no es ninguna de las dos. Es una pantalla que en
/// este destino no aplica, y lo dice.
class _NoVaEnLaWeb extends StatelessWidget {
  const _NoVaEnLaWeb();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(Aire.xl),
      children: [
        Tarjeta(
          titulo: TextosDeSincronizacion.enLaWebTitulo,
          child: const EstadoVacio(
            TextosDeSincronizacion.enLaWeb,
            icono: Icons.desktop_windows_outlined,
          ),
        ),
      ],
    ),
  );
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.alRecargar});

  final VoidCallback alRecargar;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TextosDeSincronizacion.titulo,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              TextosDeSincronizacion.explicacion,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      OutlinedButton.icon(
        onPressed: alRecargar,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Actualizar'),
      ),
    ],
  );
}

/// Lo que se ve cuando la lectura no pudo bajar.
///
/// Un `FalloDeRed` aqui **no es «todos al dia»**: es «no lo se». Pintarlo como
/// una lista vacia —o dejar la anterior— seria dar por bueno que nadie esta sin
/// subir justo el dia que no hay forma de comprobarlo.
class _Fallo extends StatelessWidget {
  const _Fallo({required this.fallo, required this.alReintentar});

  final Object fallo;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final texto = switch (fallo) {
      FalloDeRed() => TextosDeSincronizacion.sinConexion,
      final FalloApi f => f.mensaje,
      _ => 'No se pudo leer el estado del sincronizador. $fallo',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AvisoAmbar(texto, icono: Icons.cloud_off),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: alReintentar,
            child: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.lectura});

  final LecturaDelPanel lectura;

  @override
  Widget build(BuildContext context) {
    final estado = lectura.estado;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TextosDeSincronizacion.leidoALas(
            DateFormat('H:mm', 'es').format(lectura.leidoA),
          ),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Colores.gris),
        ),
        const SizedBox(height: 12),
        ControlSenalado(
          nombre: Senalado.sincronizacionCifras,
          child: _Cifras(estado: estado),
        ),
        const SizedBox(height: 16),
        ControlSenalado(
          nombre: Senalado.sincronizacionAparatos,
          child: Tarjeta(
            titulo: 'Aparatos',
            child: estado.aparatos.isEmpty
                ? const EstadoVacio(
                    TextosDeSincronizacion.sinAparatos,
                    icono: Icons.phonelink_off_outlined,
                  )
                : TablaAncha(
                    anchoMinimo: 980,
                    child: _Aparatos(estado: estado),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        ControlSenalado(
          nombre: Senalado.sincronizacionBandeja,
          child: _Bandeja(estado: estado),
        ),
      ],
    );
  }
}

class _Cifras extends StatelessWidget {
  const _Cifras({required this.estado});

  final EstadoDelSincronizador estado;

  @override
  Widget build(BuildContext context) {
    final tarjetas = <Widget>[
      TarjetaDeCifra(
        // La etiqueta NO es el literal de la fila («Nunca ha subido»): son dos
        // cosas distintas —una cuenta, una fila— y compartir el texto haria
        // creer que el numero grande es el estado de alguien.
        etiqueta: 'Sin subir nunca',
        valor: Numeros.entero(estado.nuncaSubieron),
        subtexto: 'Dados de alta y sin una sola subida',
        color: estado.nuncaSubieron > 0 ? Colores.rojo : Colores.verde,
        icono: Icons.cloud_off,
      ),
      TarjetaDeCifra(
        etiqueta: 'Más de un día sin subir',
        valor: Numeros.entero(estado.llevanMasDeUnDia),
        subtexto: 'Estos son los de llamar',
        color: estado.llevanMasDeUnDia > 0 ? Colores.rojo : Colores.verde,
        icono: Icons.error_outline,
      ),
      TarjetaDeCifra(
        etiqueta: 'Apuntes pendientes',
        valor: Numeros.entero(estado.pendientesEnTotal),
        subtexto: 'Trabajo hecho que sigue en los teléfonos',
        color: estado.pendientesEnTotal > 0 ? Colores.ambar : Colores.verde,
        icono: Icons.upload_outlined,
      ),
      TarjetaDeCifra(
        etiqueta: TextosDeSincronizacion.bandejaTitulo,
        valor: Numeros.entero(estado.sinAtenderEnTotal),
        subtexto: 'Esperando a que una persona decida',
        color: estado.sinAtenderEnTotal > 0 ? Colores.rojo : Colores.verde,
        icono: Icons.block_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, medidas) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final t in tarjetas)
            SizedBox(
              width: medidas.maxWidth < Anchos.articulosYFactura
                  ? medidas.maxWidth
                  : (medidas.maxWidth - 36) / 4,
              child: t,
            ),
        ],
      ),
    );
  }
}

/// La tabla de aparatos, **en el orden en que vino**.
///
/// El servidor la ordena por urgencia (`subida_at ASC NULLS FIRST`): el que
/// nunca subio, primero. Reordenarla aqui por sucursal o por nombre dejaria a
/// Palma enterrada entre nueve filas verdes.
class _Aparatos extends StatelessWidget {
  const _Aparatos({required this.estado});

  final EstadoDelSincronizador estado;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Encabezado(),
      Divider(height: 1, color: Colores.borde),
      for (final aparato in estado.aparatos) _FilaAparato(aparato: aparato),
    ],
  );
}

/// Los anchos de las columnas, compartidos por el encabezado y las filas.
const _pesos = <int>[4, 4, 3, 3, 4, 2, 2];
const _columnas = <String>[
  'Sin subir',
  'Aparato',
  'Persona',
  'Sucursal',
  'Última subida',
  'Pendientes',
  'Rechazados',
];

class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
    child: Row(
      children: [
        for (var i = 0; i < _columnas.length; i++)
          Expanded(
            flex: _pesos[i],
            child: Text(
              _columnas[i],
              style: Theme.of(context).textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    ),
  );
}

/// El color y la marca de cada gravedad, en un solo sitio.
///
/// El ambar de esta casa SIGNIFICA «mira esto»; el rojo, «esto ya es un
/// problema». Que «nunca» y «mas de un dia» compartan el rojo es a proposito —
/// los dos son de llamar—, pero **no comparten la marca**: el icono y el texto
/// los separan sin leer numeros.
({Color color, Color fondo, IconData icono}) _pintura(GravedadSincro g) =>
    switch (g) {
      GravedadSincro.nunca => (
        color: Colores.rojo,
        fondo: Colores.rojoFondo,
        icono: Icons.cloud_off,
      ),
      GravedadSincro.tarde => (
        color: Colores.rojo,
        fondo: Colores.rojoFondo,
        icono: Icons.error_outline,
      ),
      GravedadSincro.atencion => (
        color: Colores.ambar,
        fondo: Colores.ambarFondo,
        icono: Icons.warning_amber_outlined,
      ),
      GravedadSincro.alDia => (
        color: Colores.verde,
        fondo: Colores.verdeFondo,
        icono: Icons.cloud_done_outlined,
      ),
    };

class _FilaAparato extends ConsumerWidget {
  const _FilaAparato({required this.aparato});

  final AparatoDelPanel aparato;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final pinta = _pintura(aparato.gravedad);
    final sucursales = ref.watch(sucursalesProvider).value;
    final sucursal =
        sucursales
            ?.where((s) => s.id == aparato.sucursal)
            .map((s) => s.name)
            .firstOrNull ??
        AparatoDelPanel.corto(aparato.sucursal);

    final celdas = <Widget>[
      // PRIMERA columna a proposito: es la que se mira de reojo.
      Row(
        children: [
          Icon(pinta.icono, size: 16, color: pinta.color),
          const SizedBox(width: 6),
          Flexible(
            child: Insignia(
              TextosDeSincronizacion.sinSubir(aparato),
              color: pinta.color,
              fondo: pinta.fondo,
            ),
          ),
        ],
      ),
      Text(
        aparato.comoSeLlama,
        style: tema.textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      Text(
        aparato.persona,
        style: tema.textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      Text(
        sucursal,
        style: tema.textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      // «Nunca» tampoco se pinta como una fecha vacia: un guion se lee como
      // «no lo se», y aqui si se sabe.
      aparato.nuncaSubio
          ? Text(
              TextosDeSincronizacion.nunca,
              style: tema.textTheme.bodySmall?.copyWith(
                color: Colores.rojo,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            )
          : Text(
              DateFormat('EEEE d/M, H:mm', 'es').format(aparato.subida!),
              style: tema.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
      _Numero(
        valor: aparato.pendientes,
        color: aparato.pendientes > 0 ? Colores.ambar : Colores.gris,
      ),
      _Numero(
        valor: aparato.rechazados,
        color: aparato.rechazados > 0 ? Colores.rojo : Colores.gris,
      ),
    ];

    return Container(
      // La banda de color del borde izquierdo: es lo que deja recorrer la
      // tabla sin leer una sola palabra.
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: pinta.color, width: 4),
          bottom: BorderSide(color: Colores.borde),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(6, 8, 4, 8),
      child: Row(
        children: [
          for (var i = 0; i < celdas.length; i++)
            Expanded(flex: _pesos[i], child: celdas[i]),
        ],
      ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({required this.valor, required this.color});

  final int valor;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    Numeros.entero(valor),
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: color,
      fontWeight: valor > 0 ? FontWeight.bold : FontWeight.normal,
    ),
  );
}

/// LA BANDEJA. Lo que el servidor rechazo y sigue esperando a que una persona
/// decida, con **su motivo y su hora**.
///
/// `rechazado` no se reintenta y no se borra. Un apunte que desaparece solo es
/// trabajo perdido que nadie sabe que perdio, y esta lista es donde se ve.
class _Bandeja extends StatelessWidget {
  const _Bandeja({required this.estado});

  final EstadoDelSincronizador estado;

  @override
  Widget build(BuildContext context) {
    final cuantos = estado.bandeja.length;
    return Tarjeta(
      titulo: cuantos == 0
          ? TextosDeSincronizacion.bandejaTitulo
          : '${TextosDeSincronizacion.bandejaTitulo} ($cuantos)',
      child: cuantos == 0
          ? const EstadoVacio(
              TextosDeSincronizacion.bandejaVacia,
              icono: Icons.inbox_outlined,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in estado.bandeja) _FilaRechazo(rechazo: r),
              ],
            ),
    );
  }
}

class _FilaRechazo extends ConsumerWidget {
  const _FilaRechazo({required this.rechazo});

  final RechazoDelPanel rechazo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sucursales = ref.watch(sucursalesProvider).value;
    final sucursal =
        sucursales
            ?.where((s) => s.id == rechazo.sucursal)
            .map((s) => s.name)
            .firstOrNull ??
        AparatoDelPanel.corto(rechazo.sucursal);
    final formato = DateFormat('d/M/y, H:mm', 'es');

    final quien = [
      rechazo.nombre?.trim().isNotEmpty ?? false
          ? rechazo.nombre!.trim()
          : 'Aparato ${AparatoDelPanel.corto(rechazo.aparato)}',
      rechazo.persona,
      sucursal,
    ].join(' · ');

    // Las DOS horas, y las dos hacen falta: `hecho` es la del aparato —cuando
    // se hizo de verdad— y `rechazado` la del servidor. Con ocho horas sin
    // señal de por medio, no son la misma tarde.
    final horas = <String>[
      if (rechazo.hecho != null) 'hecho ${formato.format(rechazo.hecho!)}',
      if (rechazo.rechazadoEl != null)
        'rechazado ${formato.format(rechazo.rechazadoEl!)}',
    ].join(' · ');

    // La pinta es la de `FilaDeRechazo`, compartida con el cajon de entregar el
    // dia: los dos sitios que ensenan un rechazo tienen que verse igual.
    return FilaDeRechazo(
      motivo: rechazo.motivo,
      quien: quien,
      horas: horas,
      peticion: '${rechazo.metodo} ${rechazo.ruta}',
    );
  }
}
