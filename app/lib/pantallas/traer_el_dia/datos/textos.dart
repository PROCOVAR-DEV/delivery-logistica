import '../../../diseno/numeros.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/red/fallos.dart';
import '../../../nucleo/sincro/ciclo.dart';
import '../../../nucleo/sincro/recuento.dart';
import '../estado/traer_el_dia.dart';

/// Los literales del gesto, en un solo sitio.
///
/// Estan juntos porque son lo que decide si alguien se va al almacen tranquilo o
/// se va enganado, y eso no se revisa leyendo seis `Text()` repartidos por dos
/// ficheros. **Nada de «error desconocido» y nada de «listo»**: cada texto dice
/// que hay, que falta y que hacer.
abstract final class TextosDeTraerElDia {
  static const titulo = 'Traer el día';

  static const explicacion =
      'Cárgalo donde haya señal y llévatelo: el día entero se trabaja sin '
      'conexión.';

  static const boton = 'Traer el día';

  static const botonOtraVez = 'Traer otra vez';
  static const trayendo = 'Trayendo el día...';

  static const yaLoTienes = 'Ya lo tienes';

  /// El texto del caso que mas importa. Se dice **que falta**, no «hubo un
  /// error».
  static const queHacerSinAlgo =
      'Busca señal y vuelve a darle al botón. Lo que ya bajó se queda.';

  static const sinSenalTitulo = 'No hay señal';

  static const sinSenalDetalle =
      'No se intentó nada: el aparato dice que no hay red. Sigues teniendo lo '
      'que bajaste antes.';

  static const sinSesionTitulo = 'Hay que volver a entrar';

  static const sinSesionDetalle =
      'La sesión caducó, así que no se trajo nada. Entra otra vez y vuelve a '
      'darle.';

  /// EL SERVIDOR CORTO LA BAJADA Y NO SE PUDO SEGUIR.
  ///
  /// No es «falta una coleccion»: las colecciones estan, con la mitad de las
  /// filas. `Faltas.de` no lo ve —cuenta las que quedaron a cero— y por eso
  /// hace falta decirlo aparte.
  static const seCortoTitulo = 'El servidor no mandó todo';

  static String seCortoDetalle(String quedoPor) =>
      'La bajada se quedó a medias: $quedoPor. Lo que hay en el aparato está '
      'incompleto aunque las cifras de abajo parezcan normales.';

  static const nuncaSeBajo =
      'Este aparato no ha bajado nada todavía. Dale al botón donde haya señal.';

  /// Lo que se ensena en calma, debajo del boton.
  static const enCalma = 'Esto es lo que te llevas ahora mismo';

  /// Como se llama cada coleccion mientras se baja. En mayuscula y corto: es una
  /// palabra que pasa por delante de los ojos, no una frase.
  static String coleccion(String clave) => switch (clave) {
    Colecciones.pedidos => 'Pedidos',
    Colecciones.renglones => 'Líneas de pedido',
    Colecciones.rutas => 'Rutas',
    Colecciones.clientes => 'Clientes',
    Colecciones.productos => 'Productos',
    Colecciones.vehiculos => 'Vehículos',
    Colecciones.distribuidores => 'Distribuidores',
    Colecciones.tiposDeVehiculo => 'Tipos de vehículo',
    Colecciones.sucursales => 'Sucursales',
    Colecciones.almacenes => 'Almacenes',
    Colecciones.ajustes => 'Ajustes',
    _ => clave,
  };

  /// POR DONDE VA, literal. Es lo que convierte una rueda girando en algo que se
  /// ve avanzar.
  static String porDondeVa(AvanceDelCiclo? avance) {
    if (avance == null) return 'Empezando...';
    return switch (avance.paso) {
      PasoDelCiclo.renovar => 'Comprobando la sesión...',
      PasoDelCiclo.subir => 'Subiendo lo que quedó sin subir...',
      PasoDelCiclo.bajar when avance.coleccion == null =>
        'Pidiendo los cambios...',
      PasoDelCiclo.bajar =>
        avance.tanda > 1
            // Con `truncado` el servidor manda en tandas. Decir en cual va es lo
            // que evita que una primera carga de una sucursal grande parezca
            // colgada: se ve que la cuenta sube.
            ? '${coleccion(avance.coleccion!)}... (tanda ${avance.tanda})'
            : '${coleccion(avance.coleccion!)}...',
    };
  }

  /// Cuanto lleva. En segundos hasta el minuto, y luego en minutos: nadie cuenta
  /// «97 s».
  static String cuantoLleva(Duration cuanto) {
    final segundos = cuanto.inSeconds;
    if (segundos < 60) return '${segundos < 0 ? 0 : segundos} s';
    final minutos = cuanto.inMinutes;
    final resto = segundos - minutos * 60;
    return resto == 0 ? '$minutos min' : '$minutos min $resto s';
  }

  /// LOS NUMEROS, que es lo que convierte el gesto en confianza.
  ///
  /// Las tres que se dicen son las tres con las que se trabaja el dia: lo que
  /// hay que repartir, a quien, y con que pesos. Las otras seis salen en la
  /// tabla de debajo, no en la linea que se lee de un vistazo.
  static String lasTresCifras(RecuentoDeLoQueHay r) => <String>[
    _plural(r.cuantas(Colecciones.pedidos), 'pedido', 'pedidos'),
    _plural(r.cuantas(Colecciones.clientes), 'cliente', 'clientes'),
    _plural(r.cuantas(Colecciones.productos), 'producto', 'productos'),
  ].join(' · ');

  /// El renglon de una de las tres: el nombre y su numero.
  static String cifraDe(RecuentoDeLoQueHay r, String coleccion) =>
      switch (coleccion) {
        Colecciones.pedidos => _plural(
          r.cuantas(Colecciones.pedidos),
          'pedido',
          'pedidos',
        ),
        Colecciones.clientes => _plural(
          r.cuantas(Colecciones.clientes),
          'cliente',
          'clientes',
        ),
        Colecciones.productos => _plural(
          r.cuantas(Colecciones.productos),
          'producto',
          'productos',
        ),
        _ => Numeros.entero(r.cuantas(coleccion)),
      };

  /// Los pedidos traen SUS LINEAS dentro: no es otra descarga, es la misma.
  static String conSusLineas(RecuentoDeLoQueHay r) {
    final lineas = r.cuantas(Colecciones.renglones);
    return lineas == 1 ? 'con 1 línea' : 'con ${Numeros.entero(lineas)} líneas';
  }

  /// LO DE SIEMPRE, en UNA linea. Menos de veinte filas entre las cinco: no
  /// merecen cinco renglones, pero hacen falta las cinco.
  static const loDeSiempre =
      'Y lo de siempre: vehículos, distribuidores, sucursales, almacenes y '
      'ajustes.';

  static String loDeSiempreCuantas(RecuentoDeLoQueHay r) {
    final total = Faltas.loDeSiempre.fold<int>(
      0,
      (suma, c) => suma + r.cuantas(c),
    );
    return total == 1 ? '1 fila' : '${Numeros.entero(total)} filas';
  }

  static String deLasHoras(DateTime cuando) =>
      'de las ${cuando.hour}:${cuando.minute.toString().padLeft(2, '0')}';

  /// **El titulo del aviso cuando falta algo.** Nombra lo que falta, no el
  /// error — y **agrupado**: las tres que pesan por su nombre, y todo lo demas
  /// como «lo de siempre». Nueve vinetas para decir que fallo todo son un aviso
  /// que nadie lee.
  static String faltaTitulo(List<Falta> faltan) {
    if (faltan.isEmpty) return '';
    if (Faltas.faltaTodo(faltan)) return 'No bajó nada';

    final nombres = Faltas.agrupar(faltan);
    if (nombres.length == 1) {
      // «Falta el catálogo de productos» y «Faltan los almacenes». El verbo
      // concuerda con el nombre, que ya viene con su articulo: leer «Falta los
      // almacenes» en un aviso hace dudar de todo lo demas que diga la pantalla.
      final uno = nombres.first;
      final plural = uno.startsWith('los ') || uno.startsWith('las ');
      return '${plural ? 'Faltan' : 'Falta'} $uno';
    }
    final ultimo = nombres.removeLast();
    return 'Faltan ${nombres.join(', ')} y $ultimo';
  }

  /// **Que se rompe sin cada cosa.** Una linea por cosa, ya agrupada: las que
  /// pesan con su consecuencia, y lo de siempre con la suya, junta.
  static List<String> queSeRompe(List<Falta> faltan) => <String>[
    for (final f in faltan)
      if (Faltas.lasQuePesan.contains(f.coleccion))
        '${_mayuscula(f.queEs)}: ${f.consecuencia}.',
    if (faltan.any((f) => !Faltas.lasQuePesan.contains(f.coleccion)))
      Faltas.seRompeSinLoDeSiempre,
  ];

  /// El motivo del fallo, en palabras de la casa. **Nunca «error
  /// desconocido»**: si no se reconoce, se dice lo que se sabe y que hacer.
  static String motivoDelFallo(Object fallo) => switch (fallo) {
    FalloDeRed() =>
      'Se cortó la conexión a mitad. El aparato puede decir que hay wifi y no '
          'salir un paquete: eso es esto.',
    SesionMuerta() => sinSesionDetalle,
    final FalloApi f => f.mensaje,
    _ => 'El servidor contestó algo que no se entiende: $fallo',
  };

  /// La linea que resume como quedo, para la franja y para el banner.
  static String comoQuedo(LoQueSeTrajo trajo) {
    if (trajo.sinSenal) return sinSenalTitulo;
    if (trajo.sinSesion) return sinSesionTitulo;
    if (trajo.faltan.isNotEmpty) return faltaTitulo(trajo.faltan);
    if (trajo.quedoPor != null) return seCortoTitulo;
    if (trajo.fallo != null) return 'No se pudo traer el día entero';
    return yaLoTienes;
  }

  static String _plural(int cuantos, String uno, String muchos) =>
      '${Numeros.entero(cuantos)} ${cuantos == 1 ? uno : muchos}';

  static String _mayuscula(String texto) =>
      texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);
}
