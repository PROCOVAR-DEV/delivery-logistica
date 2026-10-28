import '../base/base.dart';
import '../cola/cola_salida.dart';
import '../red/cliente_api.dart';
import '../registro/registro.dart';

/// EL CUADRE DEL APARATO CON EL SERVIDOR — 28/10/2026 (Jose: «el sync se hizo para algo»).
///
/// La bajada del día es POR DIFERENCIAS: pide lo que cambió desde su marca y lo que se quitó (`quitados`).
/// Si una lápida no llega, el aparato se queda con filas FANTASMA para siempre: el 21/10/2026 el servidor
/// perdió 828 lápidas de facturas de Santiago (un grupo con la misma hora mayor que el tope) y el aparato de
/// Maikel siguió enseñando facturas que ya no existen, seis días, hasta que las usó. Esto es la red de
/// seguridad, independiente de las lápidas: una vez al día pide al servidor los ids de TODO lo que el aparato
/// debería tener (`GET /api/sync/cuadre`, por las mismas listas que la bajada) y quita lo que sobre.
///
/// LO QUE NO SE TOCA, y por qué cada guarda está aquí:
///  * **una colección que el servidor dice truncada, ausente o VACÍA con filas locales**: una lista a medias
///    borraría filas vivas; una vacía es casi siempre un error, no «no hay nada»;
///  * **lo creado en este aparato y que todavía no subió** (id `local-…`) y **lo que nombra un apunte
///    pendiente**: es trabajo sin subir y la bajada nunca lo pisa;
///  * **un cuadre que borraría casi todo** lo que hay (>95 % con más de 20 filas): algo va mal en la respuesta;
///  * **el tablero** (zonas y colocaciones): se baja como foto entera y se reemplaza, no por diferencias.
/// Si algo se quita de más, el servidor lo vuelve a mandar en la siguiente bajada.
///
/// Y NADA SE HACE EN SILENCIO: lo quitado vuelve en [ResultadoDelCuadre] y la app lo dice (franja de estado).
class Cuadre {
  Cuadre({
    required ClienteApi cliente,
    required BaseLocal base,
    required ColaDeSalida cola,
    required Future<void> Function(String coleccion, String id) quitar,
  }) : _cliente = cliente,
       _base = base,
       _cola = cola,
       _quitar = quitar;

  final ClienteApi _cliente;
  final BaseLocal _base;
  final ColaDeSalida _cola;
  final Future<void> Function(String coleccion, String id) _quitar;

  /// La tabla local de cada colección que se cuadra. `boardColumns` y `boardPlacements` NO están: el tablero se
  /// baja como foto entera (`ServicioTablero.descargar`).
  static const tablas = <String, String>{
    Colecciones.pedidos: 'orders',
    Colecciones.rutas: 'routes',
    Colecciones.clientes: 'customers',
    Colecciones.productos: 'products',
    Colecciones.vehiculos: 'vehicles',
    Colecciones.tiposDeVehiculo: 'vehicle_types',
    Colecciones.distribuidores: 'distribuidores',
    Colecciones.sucursales: 'branches',
  };

  Future<ResultadoDelCuadre> cuadrar({String? sucursal}) async {
    final datos = await _cliente.pedir<Map<String, Object?>>(
      '/sync/cuadre',
      params: <String, Object?>{'sucursal': ?sucursal},
    );
    final delServidor =
        (datos['colecciones'] as Map<Object?, Object?>?) ?? const {};
    final truncadas = {
      for (final c in (datos['truncado'] as List<Object?>?) ?? const []) '$c',
    };

    final enUso = await _loQueNombranLosApuntesPendientes();
    final quitadas = <QuitadaDelCuadre>[];
    final noCuadradas = <String>[];
    final faltaban = <String, int>{};

    for (final entrada in tablas.entries) {
      final coleccion = entrada.key;
      final lista = delServidor[coleccion];
      if (lista is! List<Object?> || truncadas.contains(coleccion)) {
        noCuadradas.add('$coleccion: el servidor no dio la lista entera');
        continue;
      }
      final vivas = {for (final id in lista) '$id'};

      final locales = await _locales(coleccion, entrada.value);
      // LO QUE FALTA: el servidor lo tiene y el aparato no. Un cambio que nunca llegó (un grupo grande con la
      // misma hora, un fallo a medias) deja al aparato SIN esa fila, y la bajada por diferencias no la vuelve a
      // pedir. Se cuenta y, si hay, la bajada fuerza una carga completa (`Bajada._cuadrarSiToca`).
      final loQueHay = {for (final f in locales) f.id};
      final faltan = vivas.where((id) => !loQueHay.contains(id)).length;
      if (faltan > 0) {
        faltaban[coleccion] = faltan;
        Registro.aviso(
          'cuadre: «$coleccion» le faltan al aparato $faltan filas que el servidor sí tiene',
        );
      }
      if (locales.isEmpty) continue;
      if (vivas.isEmpty) {
        noCuadradas.add(
          '$coleccion: el servidor dio una lista vacía y hay filas locales',
        );
        Registro.aviso(
          'cuadre: «$coleccion» llegó vacía con ${locales.length} filas locales; no se toca',
        );
        continue;
      }

      final sobran = [
        for (final f in locales)
          if (!vivas.contains(f.id) &&
              !f.id.startsWith('local-') &&
              !enUso.contains(f.id))
            f,
      ];
      if (sobran.isEmpty) continue;
      if (locales.length > 20 && sobran.length > locales.length * 0.95) {
        noCuadradas.add(
          '$coleccion: iba a quitar ${sobran.length} de ${locales.length}',
        );
        Registro.fallo(
          'cuadre: «$coleccion» quitaría ${sobran.length} de ${locales.length}: no se aplica',
        );
        continue;
      }

      for (final f in sobran) {
        await _quitar(coleccion, f.id);
        if (coleccion == Colecciones.pedidos && await _hayTablero()) {
          await _base.customStatement(
            'DELETE FROM board_placements WHERE order_id = ?1',
            [f.id],
          );
        }
        quitadas.add(
          QuitadaDelCuadre(
            coleccion: coleccion,
            id: f.id,
            etiqueta: f.etiqueta,
          ),
        );
      }
      Registro.info(
        'cuadre: «$coleccion» quitó ${sobran.length} filas que el servidor ya no tiene',
      );
    }

    final cerrados = await _cerrarLosRechazadosDeLoQueYaNoExiste({
      for (final q in quitadas)
        if (q.coleccion == Colecciones.pedidos) q.id,
    });
    return ResultadoDelCuadre(
      quitadas: quitadas,
      apuntesCerrados: cerrados,
      noCuadradas: noCuadradas,
      faltaban: faltaban,
    );
  }

  /// La tabla de las colocaciones se crea al abrir el tablero por primera vez: puede no existir todavía.
  Future<bool> _hayTablero() async =>
      (await _base
              .customSelect(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'board_placements'",
              )
              .get())
          .isNotEmpty;

  /// El TEXTO de los apuntes que TODAVÍA NO SE RESOLVIERON (pendientes): trabajo sin subir. Un id está «en uso» si
  /// aparece tal cual en alguno (la ruta o el cuerpo): sin suponer cómo es el id.
  Future<_Texto> _loQueNombranLosApuntesPendientes() async {
    final vivos = await (_base.select(
      _base.apuntes,
    )..where((a) => a.estado.equalsValue(EstadoApunte.pendiente))).get();
    return _Texto([for (final a in vivos) '${a.ruta} ${a.cuerpo}']);
  }

  Future<List<_Local>> _locales(String coleccion, String tabla) async {
    final extra = coleccion == Colecciones.pedidos
        ? ', factura_numero AS f, customer_name AS c'
        : '';
    final filas = await _base.customSelect('SELECT id$extra FROM $tabla').get();
    return [
      for (final r in filas)
        _Local(
          r.read<String>('id'),
          coleccion == Colecciones.pedidos
              ? _etiquetaDeFactura(
                  r.readNullable<String>('f'),
                  r.readNullable<String>('c'),
                )
              : null,
        ),
    ];
  }

  static String? _etiquetaDeFactura(String? factura, String? cliente) {
    final f = (factura ?? '').trim();
    final c = (cliente ?? '').trim();
    if (f.isEmpty && c.isEmpty) return null;
    return [if (f.isNotEmpty) 'Factura $f', if (c.isNotEmpty) c].join(' · ');
  }

  /// Un apunte RECHAZADO que nombra una factura que se acaba de quitar ya no tiene a qué aplicarse: la factura
  /// no existe. No se borra (una decisión se ESCRIBE): pasa a `descartado` con su motivo intacto, y la app dice
  /// que lo hizo. Así nadie tiene que ir limpiando la bandeja a mano.
  Future<int> _cerrarLosRechazadosDeLoQueYaNoExiste(Set<String> pedidos) async {
    if (pedidos.isEmpty) return 0;
    final rechazados = await (_base.select(
      _base.apuntes,
    )..where((a) => a.estado.equalsValue(EstadoApunte.rechazado))).get();
    var cerrados = 0;
    for (final a in rechazados) {
      final texto = '${a.ruta} ${a.cuerpo}';
      if (pedidos.any(texto.contains)) {
        await _cola.descartar(a.clave);
        cerrados++;
      }
    }
    if (cerrados > 0) {
      Registro.info(
        'cuadre: $cerrados apuntes rechazados cerrados, su factura ya no existe',
      );
    }
    return cerrados;
  }
}

class _Local {
  const _Local(this.id, this.etiqueta);
  final String id;
  final String? etiqueta;
}

/// Una fila que el aparato tenía y el servidor ya no.
class QuitadaDelCuadre {
  const QuitadaDelCuadre({
    required this.coleccion,
    required this.id,
    this.etiqueta,
  });

  final String coleccion;
  final String id;

  /// «Factura 47636 · Cliente» para las facturas; nulo para el resto.
  final String? etiqueta;
}

class ResultadoDelCuadre {
  const ResultadoDelCuadre({
    this.quitadas = const [],
    this.apuntesCerrados = 0,
    this.noCuadradas = const [],
    this.faltaban = const {},
  });

  static const nada = ResultadoDelCuadre();

  final List<QuitadaDelCuadre> quitadas;

  /// Apuntes rechazados que se cerraron solos porque su factura ya no existe.
  final int apuntesCerrados;

  /// Colecciones que NO se cuadraron, con el motivo (lista truncada, vacía, o un borrado sospechoso).
  final List<String> noCuadradas;

  /// Lo que el servidor tiene y el aparato NO, por colección. La bajada fuerza entonces una carga completa.
  final Map<String, int> faltaban;

  bool get hayQueDecir =>
      quitadas.isNotEmpty || apuntesCerrados > 0 || faltaban.isNotEmpty;

  int get totalQueFaltaba => faltaban.values.fold(0, (a, b) => a + b);

  int get facturas =>
      quitadas.where((q) => q.coleccion == Colecciones.pedidos).length;
}

/// Un montón de textos en los que preguntar «¿sale este id?».
class _Texto {
  const _Texto(this._textos);
  final List<String> _textos;

  bool contains(String id) => _textos.any((t) => t.contains(id));
}
