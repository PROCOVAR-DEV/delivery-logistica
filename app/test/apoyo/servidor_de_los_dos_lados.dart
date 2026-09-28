import 'servidor_falso.dart';

/// EL SERVIDOR CON LOS DOS LADOS DENTRO.
///
/// El `ServidorFalso` de al lado contesta lo que se le diga y no recuerda nada.
/// Para lo que se prueba aquí eso no vale: el caso es **el móvil sin señal y la
/// web trabajando a la vez sobre los mismos pedidos**, y eso no se puede montar
/// con respuestas fijas. Hace falta un servidor que GUARDE lo que le llega,
/// porque:
///
///  * lo que la web hace es una escritura del servidor que el móvil no ve hasta
///    que baja la foto;
///  * lo que el móvil hizo sin señal llega **después**, de golpe, cuando sube la
///    cola, y se aplica encima de lo que dejó la web;
///  * y lo que se quiere comprobar es **qué queda** al final, que es la pregunta
///    que no contesta ninguna prueba de las que había.
///
/// Es un doble, no el servidor. Lo que sabe hacer sale del contrato que la
/// propia aplicación usa —las rutas que encola `RepositorioTablero` y
/// `AccionesDeRuta`— y de `docs/tablero.md`. **Las guardas de verdad viven en
/// Go** (`api/internal/api/tablero.go` y `rutas.go`) y se prueban allí; aquí lo
/// que se fija es cómo se comporta el APARATO cuando el servidor contesta lo que
/// contesta.
///
/// La red se enciende y se apaga con [hayRed]: apagada, cualquier petición falla
/// como en la calle (el `ServidorFalso` lanza `DioException.connectionError`) y
/// además queda apuntada, que es lo que deja comprobar que un gesto no llama a
/// nadie.
class ServidorDeLosDosLados {
  ServidorDeLosDosLados({required this.sucursalId});

  final String sucursalId;

  /// Con `false` no hay red: ni el móvil sube ni baja nada. Lo que la web haga
  /// sigue entrando, porque la web está EN el servidor.
  bool hayRed = true;

  /// Las zonas del tablero, por id.
  final Map<String, ZonaEnElServidor> zonas = <String, ZonaEnElServidor>{};

  /// Dónde está puesta cada tarjeta. La clave es el pedido: **un pedido sólo
  /// puede estar en un sitio**, igual que la clave primaria de la tabla.
  final Map<String, PuestaEnElServidor> puestas =
      <String, PuestaEnElServidor>{};

  /// Los pedidos de cada ruta, por id de ruta.
  final Map<String, List<String>> rutas = <String, List<String>>{};

  /// Cómo acabó cada parada: pedido → `entregado` | `devuelto` | `cancelado`.
  final Map<String, String> resultados = <String, String>{};

  /// Las rutas de los apuntes que se aplicaron, en orden. Es lo que deja decir
  /// «esto subió» sin mirar la cola del aparato.
  final List<String> aplicados = <String>[];

  /// Un «no» preparado: la ruta del apunte → el motivo literal. Sirve para
  /// montar el día en que el servidor rechaza sin tener que tocar el doble.
  final Map<String, String> rechaza = <String, String>{};

  /// CÓMO NOMBRA EL SERVIDOR A CADA PEDIDO: folio y cliente. Los rellena la
  /// prueba con lo mismo que sembró en la base local.
  ///
  /// Hacen falta porque `descartados` **nombra la tarjeta**, no devuelve un
  /// uuid a secas (`api/internal/api/tablero.go`, `DescartadoSalida`): un uuid
  /// no le dice nada a nadie y no se puede buscar en PEDIDO. Una prueba que
  /// sólo comprobara el id daría por bueno un aviso ilegible.
  final Map<String, String> folios = <String, String>{};
  final Map<String, String> clientes = <String, String>{};

  int _cuantasRutas = 0;

  /// UNO SOLO para todos los clientes de la prueba. El tablero y la subida
  /// hablan por dos `Dio` distintos —dos direcciones base, `/api` y `/sync`—
  /// pero contra el mismo servidor, que es lo que pasa de verdad. Devolviendo
  /// uno nuevo en cada lectura, apagar la red le daría a uno y no al otro, y la
  /// lista de peticiones vistas quedaría partida en dos.
  late final ServidorFalso adaptador = ServidorFalso(responder);

  // ---------------------------------------------------------------------
  // LO QUE HACE LA WEB. Escribe aquí directamente y sin pasar por la cola:
  // la web no tiene cola ni base local, sus gestos salen en el momento.
  // ---------------------------------------------------------------------

  /// [vehiculoId] es el CAMIÓN PREVISTO de la zona, y desde el 28/09/2026 no es
  /// decorativo: una zona sin camión no arma ruta ni aquí ni en el servidor
  /// (`repositorio.dart`, `armarRuta`; `api/internal/api/tablero.go`,
  /// `msgZonaSinCamion`). Una prueba que arme la ruta de esta zona tiene que
  /// pasarlo, o medirá ese rechazo en vez de lo suyo.
  void laWebCreaZona(
    String id,
    String nombre, {
    int? posicion,
    String? vehiculoId,
  }) {
    zonas[id] = ZonaEnElServidor(
      id: id,
      nombre: nombre,
      posicion: posicion ?? zonas.length + 1,
      vehiculoId: vehiculoId,
    );
  }

  /// La web coloca —o mueve— un pedido. Devuelve `null` si pudo, o el motivo
  /// literal si el servidor se negó.
  String? laWebColoca(String pedidoId, String zonaId, {int posicion = 1}) {
    final motivo = _porQueNoSePuedeColocar(pedidoId);
    if (motivo != null) return motivo;
    puestas[pedidoId] = PuestaEnElServidor(
      columnaId: zonaId,
      posicion: posicion,
      por: 'web',
    );
    return null;
  }

  /// La web saca un pedido del tablero: vuelve a «sin colocar».
  void laWebQuita(String pedidoId) => puestas.remove(pedidoId);

  /// LA COLOCACIÓN A LA FUERZA, saltándose la guarda.
  ///
  /// Es el servidor que NO tiene el 409 de «ya va en otra ruta». Existe para
  /// poder montar ese día concreto y ver qué hace el aparato con una foto que
  /// pone un pedido en una ruta y en el tablero a la vez.
  void laWebColocaSinGuarda(
    String pedidoId,
    String zonaId, {
    int posicion = 1,
  }) {
    puestas[pedidoId] = PuestaEnElServidor(
      columnaId: zonaId,
      posicion: posicion,
      por: 'web',
    );
  }

  /// En qué ruta va un pedido, si va en alguna.
  String? rutaDe(String pedidoId) {
    for (final entrada in rutas.entries) {
      if (entrada.value.contains(pedidoId)) return entrada.key;
    }
    return null;
  }

  /// La guarda del tablero, dicha con el literal del contrato: un pedido que ya
  /// va en una ruta no se coloca.
  String? _porQueNoSePuedeColocar(String pedidoId) =>
      rutaDe(pedidoId) == null ? null : 'Ese pedido ya va en otra ruta';

  // ---------------------------------------------------------------------
  // Lo que contesta
  // ---------------------------------------------------------------------

  Future<RespuestaFalsa?> responder(PeticionVista p) async {
    if (!hayRed) return null;
    if (p.metodo == 'GET' && p.ruta.endsWith('/board')) {
      return RespuestaFalsa(200, foto());
    }
    if (p.metodo == 'POST' && p.ruta.endsWith('/subida')) {
      final cuerpo = p.cuerpo! as Map<String, Object?>;
      final apuntes = (cuerpo['apuntes']! as List<Object?>)
          .cast<Map<String, Object?>>();
      return RespuestaFalsa(200, <String, Object?>{
        'resultados': [for (final a in apuntes) _aplicar(a)],
      });
    }
    // Un 404 con el nombre de lo que se pidió. Callarse aquí dejaría una prueba
    // en verde sobre una petición que nadie atendió.
    return RespuestaFalsa(404, <String, Object?>{
      'error': 'el doble no sabe de ${p.metodo} ${p.ruta}',
    });
  }

  /// La foto del tablero, tal y como la lee `ServicioTablero`.
  Map<String, Object?> foto() => <String, Object?>{
    'columnas': [
      for (final z in zonas.values)
        <String, Object?>{
          'id': z.id,
          'branchId': sucursalId,
          'nombre': z.nombre,
          'posicion': z.posicion,
          'vehiculoId': z.vehiculoId,
        },
    ],
    'colocados': [
      for (final entrada in puestas.entries)
        <String, Object?>{
          'pedidoId': entrada.key,
          'columnaId': entrada.value.columnaId,
          'posicion': entrada.value.posicion,
          'colocadoPor': entrada.value.por,
        },
    ],
    'vistoAt': '2026-09-14T20:00:00.000Z',
  };

  /// LOS `local-…` QUE YA TIENEN ID DE VERDAD, dentro de ESTE lote.
  ///
  /// No es un adorno del doble: es lo que hace el sincronizador de verdad
  /// (`sync/internal/sincro/provisionales.go`). El apunte que crea la ruta y el
  /// que la cierra suben JUNTOS, en el mismo envío, y el segundo viaja todavía
  /// con el `local-…` dentro — la sustitución del aparato ocurre al resolver la
  /// respuesta, o sea después. Sin traducir aquí, el cierre de la tarde llegaría
  /// contra `/routes/local-9f3a/results`, que no existe en ningún sitio, y se
  /// perdería el trabajo del día JUSTO DESPUÉS de haberlo subido bien.
  final Map<String, String> _traduccion = <String, String>{};

  static final RegExp _local = RegExp('local-[A-Za-z0-9]+');

  /// Cambia los `local-…` por su id bueno. [propio] es el que este mismo apunte
  /// está creando: ése no se traduce, porque todavía no existe.
  String _traducir(String s, String? propio) => s.replaceAllMapped(_local, (m) {
    final token = m.group(0)!;
    if (token == propio) return token;
    return _traduccion[token] ?? token;
  });

  Map<String, Object?> _aplicar(Map<String, Object?> apunte) {
    final clave = apunte['clave']! as String;
    final metodo = apunte['metodo']! as String;
    final propio = apunte['provisional'] as String?;
    final ruta = _traducir(apunte['ruta']! as String, propio);
    final cuerpo =
        (apunte['cuerpo'] as Map<String, Object?>?) ??
        const <String, Object?>{};

    Map<String, Object?> no(String motivo) => <String, Object?>{
      'clave': clave,
      'estado': 'rechazado',
      'motivo': motivo,
    };
    Map<String, Object?> si([String? id, List<Object?>? descartados]) {
      aplicados.add(ruta);
      if (propio != null && id != null) _traduccion[propio] = id;
      return <String, Object?>{
        'clave': clave,
        'estado': 'aplicado',
        'id': ?id,
        // QUIÉN SE CAYÓ AUNQUE EL APUNTE ENTRARA. Va en el resultado del
        // apunte porque es por donde llega de verdad: el reparto lo escribe en
        // el 201 y `sync/internal/sincro/subida.go` lo reenvía tal cual.
        // Ausente cuando no hay ninguno, igual que el `omitempty` de allí.
        if (descartados != null && descartados.isNotEmpty)
          'descartados': descartados,
      };
    }

    final preparado = rechaza[ruta];
    if (preparado != null) return no(preparado);

    final sinQuery = ruta.split('?').first;

    if (metodo == 'POST' && sinQuery == '/board/columns') {
      // El id lo pone el aparato y el servidor lo usa tal cual: subir dos veces
      // no crea dos zonas.
      final id = cuerpo['id'] as String? ?? 'zona-${zonas.length + 1}';
      zonas[id] = ZonaEnElServidor(
        id: id,
        nombre: cuerpo['nombre'] as String? ?? 'Zona',
        posicion: zonas.length + 1,
        vehiculoId: cuerpo['vehiculoId'] as String?,
      );
      return si(id);
    }

    if (metodo == 'PUT' && sinQuery.startsWith('/board/placements/')) {
      final pedidoId = sinQuery.substring('/board/placements/'.length);
      final motivo = _porQueNoSePuedeColocar(pedidoId);
      if (motivo != null) return no(motivo);
      puestas[pedidoId] = PuestaEnElServidor(
        columnaId: cuerpo['columnaId']! as String,
        posicion: (cuerpo['posicion'] as num?)?.toInt() ?? 1,
        por: 'aparato',
      );
      return si();
    }

    if (metodo == 'DELETE' && sinQuery.startsWith('/board/placements/')) {
      puestas.remove(sinQuery.substring('/board/placements/'.length));
      return si();
    }

    if (metodo == 'POST' && sinQuery.endsWith('/route')) {
      // `POST /board/columns/{id}/route`.
      //
      // Lo que hay puesto en esa zona **en el servidor** no tiene por qué ser
      // lo que había en el aparato: entre que se armó sin señal y llegó el
      // apunte pasan horas y la web no para. Por eso el aparato manda
      // `pedidoIds` con lo que ÉL eligió, y entonces manda esa lista.
      //
      // La lista es OPCIONAL y así tiene que seguir: las APK ya instaladas no
      // la mandan y volverla obligatoria las dejaría sin poder armar de golpe
      // (`api/internal/api/tablero.go`, `cuerpoArmar.PedidoIds`). Sin ella se
      // arma con lo que haya, como siempre.
      //
      // Y al armar, esas tarjetas salen del tablero: es lo que impide que un
      // pedido quede en una ruta y en el tablero a la vez.
      final zonaId = sinQuery.substring(
        '/board/columns/'.length,
        sinQuery.length - '/route'.length,
      );
      final dentro = [
        for (final e in puestas.entries)
          if (e.value.columnaId == zonaId) e.key,
      ]..sort((a, b) => puestas[a]!.posicion.compareTo(puestas[b]!.posicion));

      final crudo = cuerpo['pedidoIds'] ?? cuerpo['orderIds'];
      final elegidos = crudo is List ? crudo.cast<String>() : null;
      // Un `"pedidoIds": []` es un aparato diciendo que no eligió nada: cuerpo
      // mal formado, no una orden de armar con todo lo que haya.
      if (elegidos != null && elegidos.isEmpty) {
        return no('La lista de pedidos vino vacía');
      }

      final descartados = <Object?>[];
      Map<String, Object?> descarte(
        String pedidoId,
        String motivo,
        String queHacer,
      ) => <String, Object?>{
        'pedidoId': pedidoId,
        'operationNumber': folios[pedidoId],
        'customerName': clientes[pedidoId] ?? '',
        'motivo': motivo,
        'queHacer': queHacer,
      };

      final van = <String>[];
      if (elegidos == null) {
        van.addAll(dentro);
      } else {
        for (final pedidoId in dentro) {
          if (elegidos.contains(pedidoId)) {
            van.add(pedidoId);
          } else {
            // Llegó a la zona DESPUÉS de que el aparato armara. No sube a ese
            // camión: nadie lo cargó. Se queda en la zona y se dice.
            descartados.add(
              descarte(
                pedidoId,
                'lo pusieron en la zona después de que armaras',
                'No iba en tu camión, así que no ha subido. Se queda en la '
                    'zona: arma otra vez si tiene que salir hoy.',
              ),
            );
          }
        }
        // Y lo que él eligió y ya no está puesto aquí. ÉSE es el que su
        // repartidor puede llevar entregado.
        for (final pedidoId in elegidos) {
          if (dentro.contains(pedidoId)) continue;
          descartados.add(
            descarte(
              pedidoId,
              'ya no estaba en esa zona cuando llegó tu apunte',
              'Se movió o se quitó de la zona mientras tu aparato estaba sin '
                  'señal. NO ha subido a este camión: comprueba si se entregó '
                  'igual y míralo antes de que salga en otra ruta.',
            ),
          );
        }
      }

      if (van.isEmpty) {
        return no(
          'La columna no tiene ningún pedido que se pueda repartir hoy',
        );
      }
      final rutaId = 'ruta-servidor-${++_cuantasRutas}';
      rutas[rutaId] = van;
      for (final pedidoId in van) {
        puestas.remove(pedidoId);
      }
      return si(rutaId, descartados);
    }

    if (metodo == 'POST' && sinQuery.endsWith('/results')) {
      final rutaId = sinQuery.substring(
        '/routes/'.length,
        sinQuery.length - '/results'.length,
      );
      final deLaRuta = rutas[rutaId];
      if (deLaRuta == null) return no('No encontrada');
      for (final r
          in (cuerpo['resultados'] as List<Object?>? ?? const [])
              .cast<Map<String, Object?>>()) {
        final pedidoId = r['orderId']! as String;
        // Lo que no va en esta ruta no se guarda y no aborta el resto, igual
        // que hace el aparato al cerrar.
        if (!deLaRuta.contains(pedidoId)) continue;
        resultados[pedidoId] = r['resultado']! as String;
      }
      return si();
    }

    if (metodo == 'PATCH') return si();

    return no('el doble no sabe aplicar $metodo $ruta');
  }
}

class ZonaEnElServidor {
  ZonaEnElServidor({
    required this.id,
    required this.nombre,
    required this.posicion,
    this.vehiculoId,
  });

  final String id;
  final String nombre;
  final int posicion;
  final String? vehiculoId;
}

class PuestaEnElServidor {
  const PuestaEnElServidor({
    required this.columnaId,
    required this.posicion,
    required this.por,
  });

  final String columnaId;
  final int posicion;

  /// Quién la puso: `web` o `aparato`. No lo usa la aplicación para decidir
  /// nada —y ahí está el asunto—, pero deja que la prueba diga de quién era el
  /// gesto que ganó.
  final String por;
}
