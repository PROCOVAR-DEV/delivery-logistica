import '../../../diseno/numeros.dart';
import '../../../nucleo/red/fallos.dart';
import '../../../nucleo/sincro/ciclo.dart';
import '../estado/entregar_el_dia.dart';

/// Los literales del gesto de subir, en un solo sitio.
///
/// La regla es la del otro gesto y no cambia: **nada de «listo» y nada de «error
/// desconocido»**. Aqui ademas hay una cifra que manda sobre todas — cuantos
/// quedan—, porque es la unica que le dice a alguien si se puede ir a su casa.
abstract final class TextosDeEntregarElDia {
  static const titulo = 'Entregar el día';

  static const explicacion =
      'Sube lo que trabajaste sin conexión. Hasta que no suba, sólo está en '
      'este aparato.';

  static const boton = 'Entregar el día';
  static const botonOtraVez = 'Entregar lo que queda';
  static const subiendo = 'Entregando el día...';

  static const todoEntregado = 'Todo entregado';

  static const nadaQueEntregar =
      'No queda nada por subir. Lo que hagas sin conexión aparecerá aquí.';

  static const queHacerSiQueda =
      'Busca señal y vuelve a darle. Nada se ha perdido: lo que no subió sigue '
      'entero en este aparato.';

  static const sinSenalTitulo = 'No hay señal';

  static const sinSenalDetalle =
      'No se intentó nada: el aparato dice que no hay red. Tu trabajo sigue '
      'guardado aquí y no se pierde.';

  static const sinSesionTitulo = 'Hay que volver a entrar';

  static const sinSesionDetalle =
      'La sesión caducó, así que no se subió nada. Entra otra vez y vuelve a '
      'darle: la cola sigue entera.';

  /// LO QUE ESTA AQUI Y NO ARRIBA, Y NO LO VA A SUBIR NADIE.
  ///
  /// No es lo mismo que «sin subir» y por eso no comparte texto con ello: un
  /// apunte pendiente va a subir en cuanto haya señal, y esto **no va a subir
  /// nunca solo**, porque no le queda ningun apunte detras. Es el estado en el
  /// que se quedo la zona «Vista» el 16/09/2026, con tres pantallas diciendo
  /// «Todo al dia» encima.
  ///
  /// Se NOMBRA lo que es —«1 ruta», «2 vehículos»— por lo mismo que se nombra
  /// en el registro: «3 cosas colgadas» no le dice a nadie donde mirar.
  static String soloAqui(String que) => 'Sólo en este aparato: $que';

  static const soloAquiDetalle =
      'Está hecho aquí y en el servidor no está, y no le queda ningún apunte '
      'que lo suba: entregar el día no se lo lleva. Mientras siga saliendo '
      'aquí, para los demás no existe.';

  static const soloAquiQueHacer =
      'Con señal, el sincronizador vuelve a encolar solo lo que sabe rehacer. '
      'Lo que siga saliendo aquí después de subir hay que volver a hacerlo con '
      'conexión.';

  /// EL APUNTE ENTRO Y AUN ASI SALIO CON MENOS.
  ///
  /// No es un rechazo —eso es la bandeja— ni algo sin subir: la ruta esta
  /// arriba, y le faltan pedidos de los que se pusieron en la zona. El servidor
  /// dice quienes y por que; hasta el 28/09/2026 nadie lo leia y la ruta salia
  /// con nueve de doce sin que sonara nada.
  static const noSubioTodo = 'No subió todo al camión';

  static const noSubioTodoDetalle =
      'La ruta se armó arriba, pero con menos pedidos de los que pusiste en la '
      'zona. Esto es lo que el servidor dejó fuera y por qué. Si alguno se '
      'entregó igual, hay que mirarlo antes de que salga en otra ruta.';

  static const noSubioTodoLeido = 'Ya lo he visto';

  static const bandejaTitulo = 'Rechazados, esperando a una persona';

  static const bandejaExplicacion =
      'El servidor dijo que no por algo. No se reintentan solos y no se borran: '
      'quedan aquí con su motivo hasta que alguien decida.';

  /// Cuanto hay sin subir, **sin tener que dar a nada**. Es la linea que se lee
  /// de reojo cien veces al dia.
  static String cuantoQueda(int pendientes) => pendientes == 0
      ? todoEntregado
      : '${Numeros.entero(pendientes)} '
            '${pendientes == 1 ? 'apunte sin subir' : 'apuntes sin subir'}';

  /// POR DONDE VA. El paso que importa aqui es el de subir; los otros dos se
  /// dicen igual porque el ciclo es el mismo y callarlos dejaria la pantalla
  /// quieta durante la renovacion.
  static String porDondeVa(AvanceDelCiclo? avance) {
    if (avance == null) return 'Empezando...';
    return switch (avance.paso) {
      PasoDelCiclo.renovar => 'Comprobando la sesión...',
      PasoDelCiclo.subir => 'Subiendo lo que hiciste...',
      // Subir y bajar van en el mismo ciclo a proposito: quien entrega el dia
      // tambien quiere las rutas nuevas. Se dice, para que no parezca que se
      // colgo despues de subir.
      PasoDelCiclo.bajar => 'Subido. Ahora trayendo lo nuevo...',
    };
  }

  static String cuantoLleva(Duration cuanto) {
    final segundos = cuanto.inSeconds;
    if (segundos < 60) return '${segundos < 0 ? 0 : segundos} s';
    final minutos = cuanto.inMinutes;
    final resto = segundos - minutos * 60;
    return resto == 0 ? '$minutos min' : '$minutos min $resto s';
  }

  /// CUANTOS SUBIERON. No «listo».
  static String subieron(int cuantos) => cuantos == 0
      ? 'No subió ninguno'
      : 'Subieron ${Numeros.entero(cuantos)} '
            '${cuantos == 1 ? 'apunte' : 'apuntes'}';

  static String quedan(int cuantos) => cuantos == 0
      ? 'No queda ninguno'
      : 'Quedan ${Numeros.entero(cuantos)} sin subir';

  static String hayRechazados(int cuantos) => cuantos == 1
      ? '1 rechazado esperando a que alguien decida'
      : '${Numeros.entero(cuantos)} rechazados esperando a que alguien decida';

  static String deLasHoras(DateTime cuando) =>
      'de las ${cuando.hour}:${cuando.minute.toString().padLeft(2, '0')}';

  static String motivoDelFallo(Object fallo) => switch (fallo) {
    FalloDeRed() =>
      'Se cortó la conexión a mitad. El aparato puede decir que hay wifi y no '
          'salir un paquete: eso es esto.',
    SesionMuerta() => sinSesionDetalle,
    final FalloApi f => f.mensaje,
    _ => 'El servidor contestó algo que no se entiende: $fallo',
  };

  /// La linea que resume como quedo.
  static String comoQuedo(LoQueSeEntrego entrego) {
    if (entrego.sinSenal) return sinSenalTitulo;
    if (entrego.sinSesion) return sinSesionTitulo;
    if (entrego.quedan > 0) return quedan(entrego.quedan);
    if (entrego.fallo != null) return 'No se pudo entregar el día entero';
    if (entrego.rechazados > 0) return hayRechazados(entrego.rechazados);
    return todoEntregado;
  }

  /// La pregunta que evita el «No subió ninguno» del 21/09/2026.
  static const deQueSucursalTitulo = '¿De qué sucursal es este aparato?';
  static const deQueSucursalPorque =
      'Un aparato pertenece a una sola sucursal, y hasta que no lo diga no '
      'puede subir lo que se trabajó sin señal. Se pregunta una vez. No es la '
      'sucursal que estás mirando: es dónde está el aparato.';
}
