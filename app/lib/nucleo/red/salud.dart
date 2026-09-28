/// SI LAS PETICIONES ESTAN LLEGANDO. No «si el aparato cree que hay wifi».
///
/// El caso de verdad en Cuba **no es «sin conexión», es «conexión mala»**: sin
/// conexión la aplicación lo sabe enseguida; con una conexión que va y viene el
/// aparato **cree que está conectado**, lanza la petición, y el logístico se
/// come una rueda girando sin saber si va a funcionar. Eso es peor que un fallo
/// limpio.
///
/// Por eso el estado que se pinta NO sale de `connectivity_plus`. Ese plugin es
/// una pista —está escrito así en el `pubspec.yaml`— y sirve para **intentarlo
/// antes**, nunca para decidir lo que se enseña. Lo que decide es esto: si los
/// ciclos están llegando.
class SaludDeLaRed {
  const SaludDeLaRed({
    this.fallosSeguidos = 0,
    this.ultimaBuena,
    this.sinInterfaz = false,
    this.sinSalida = false,
  });

  static const bienDeSalida = SaludDeLaRed();

  /// Cuantos ciclos seguidos se han caído por red.
  final int fallosSeguidos;

  /// Cuándo salió bien el último. `null` = todavía ninguno en esta sesión.
  final DateTime? ultimaBuena;

  /// EL APARATO NO TIENE NI POR DÓNDE SALIR: modo avión, o ninguna red.
  ///
  /// ## La pista del sistema sólo miente en UN sentido — 22/09/2026
  ///
  /// Arriba está escrito que «sin conexión la aplicación lo sabe enseguida», y
  /// no era verdad: con el modo avión puesto a las 12:21:31, la franja siguió
  /// diciendo «Datos de las 12:20» en gris hasta las 12:23. Dos minutos en los
  /// que el Panel afirmaba «Los datos son de ahora mismo». Una pantalla
  /// mintiendo, que es lo que no puede pasar.
  ///
  /// El motivo de no fiarse de `connectivity_plus` sigue siendo bueno, pero sólo
  /// para una de las dos respuestas: **que diga que hay wifi no significa que
  /// salga un paquete** —el caso de allá— y por eso su «sí» no vale. En cambio
  /// su «no» es del sistema operativo: si no hay ni interfaz, no hay red, y eso
  /// no admite discusión ni hace falta esperar a que tres peticiones se caigan.
  ///
  /// Por eso esto es un campo aparte y no un fallo más: al volver la interfaz se
  /// quita solo, sin afirmar que la conexión sirva — eso lo sigue diciendo una
  /// petición que llegue.
  final bool sinInterfaz;

  /// EL SISTEMA DICE QUE ESTA RED NO LLEGA A INTERNET: el «!» del icono.
  ///
  /// ## Lo que se veia el 28/09/2026
  ///
  /// Jose, con el telefono enganchado a un wifi sin salida y datos moviles
  /// puestos: «me esta diciendo eso q tengo conexion y no tengo conexion ahora
  /// mismo q mierda es eso por q la wifi no esta dando internet». Y al preguntar
  /// como lo sabia el: «si sale la wifi ahora mismo cuando no tiene conexion
  /// sale un icono de wifi con ! este simbolo diciendo q no hay internet».
  ///
  /// **Ese «!» es un dato, no una impresion.** Android prueba cada red que se
  /// engancha y guarda el resultado en `NET_CAPABILITY_VALIDATED`; el icono de
  /// la barra sale de ahi. Lo sabe el sistema, es instantaneo, y hasta hoy la
  /// aplicacion no se lo preguntaba: miraba si habia interfaz —que la habia— y
  /// se ponia a esperar a que se cayeran tres ciclos. Dos minutos y medio
  /// diciendo «Todo al dia» con el telefono sin internet.
  ///
  /// Es un campo aparte y no un fallo mas por lo mismo que [sinInterfaz]: el
  /// sistema habla, no se deduce, asi que **se cree al momento** — con una sola
  /// salvedad, la ventana de sondeo de `veredicto_del_sistema.dart`, porque el
  /// primer instante de una red recien enganchada siempre dice «no valida»
  /// mientras Android todavia la esta probando.
  ///
  /// Y como con [sinInterfaz], **el «si» del sistema no vale para lo contrario**:
  /// que Android valide una red significa que sus paquetes de prueba llegaron a
  /// algun sitio, no que nuestro servidor conteste ni que la linea aguante una
  /// bajada — que es el caso de alla, y el de Starlink con su latencia. El «si»
  /// solo apaga esta bandera; que la conexion sirve lo sigue diciendo una
  /// peticion que llegue.
  final bool sinSalida;

  /// CUANTOS FALLOS SEGUIDOS HACEN FALTA para decir que la conexión va mal.
  ///
  /// Tres, y el número está pensado. El aviso tiene que ser **lento en ponerse y
  /// rápido en quitarse**: con una conexión que va y viene, un indicador que
  /// cambia con cada petición fallida parpadea todo el día, y una señal que
  /// parpadea deja de leerse a los diez minutos — que es justo lo que le pasa al
  /// ámbar de esta casa si se gasta en balde.
  ///
  /// Y tres no es «tres paquetes perdidos»: cada petición del ciclo reintenta
  /// por dentro tres veces (1 s, 4 s y 10 s, `cliente_api.dart`), así que UN
  /// ciclo caído son cuatro intentos y 15 s de esperas — **unos 55 s cuando la
  /// conexión no llega a establecerse, que es como se cae de verdad allá**, y
  /// hasta ~115 s si el servidor coge la conexión y se queda mudo cada vez.
  /// Tres seguidos siguen significando que la conexión lleva **minutos** sin
  /// servir, no que se perdió un paquete.
  ///
  /// El número se dejó en tres al bajar los plazos el 15/09/2026 y no se subió
  /// a compensar: antes eran ~80 s por ciclo y hacían falta tres para llegar a
  /// «minutos»; ahora son ~55 s y tres siguen siendo minutos. Lo que cambió
  /// para bien es que el aviso aparece antes —dos minutos y medio en vez de
  /// cuatro— y quien está en el patio del almacén se entera de que no hay
  /// señal mientras todavía le sirve de algo.
  static const fallosParaDarlaPorMala = 3;

  /// `true` cuando las peticiones llevan un rato sin llegar, cuando no hay ni
  /// por dónde salir, o cuando el sistema dice que por ahí no se sale.
  ///
  /// Las tres son la misma frase para quien mira la pantalla —«ahora mismo esto
  /// no está subiendo»— y por eso salen por el mismo sitio. Lo que cambia es lo
  /// que cuesta saberlas: las dos primeras las dice el sistema y son
  /// instantáneas; la tercera hay que ganársela con tres intentos caídos.
  bool get vaMal =>
      sinInterfaz || sinSalida || fallosSeguidos >= fallosParaDarlaPorMala;

  /// Un ciclo que llegó. **Se vuelve a normal al momento**: basta UNA buena.
  /// Tardar en recuperarse sería dejar el aviso puesto delante de alguien que ya
  /// tiene señal, y entonces el aviso miente en la otra dirección.
  ///
  /// Y borra TAMBIÉN las dos banderas del sistema, que es lo correcto y no un
  /// descuido de la construcción: una petición nuestra que llegó de verdad es
  /// mejor prueba que cualquier veredicto: si el sistema decía que esta red no
  /// llega y resulta que sí llegamos, manda lo que pasó.
  SaludDeLaRed conUnaBuena(DateTime cuando) =>
      SaludDeLaRed(ultimaBuena: cuando);

  /// El sistema dice que no hay ni interfaz. Se cree **al momento**.
  SaludDeLaRed sinRed() => SaludDeLaRed(
    fallosSeguidos: fallosSeguidos,
    ultimaBuena: ultimaBuena,
    sinInterfaz: true,
    sinSalida: sinSalida,
  );

  /// El sistema dice que esta red NO llega a internet. Ver [sinSalida].
  SaludDeLaRed sinSalidaAInternet() => SaludDeLaRed(
    fallosSeguidos: fallosSeguidos,
    ultimaBuena: ultimaBuena,
    sinInterfaz: sinInterfaz,
    sinSalida: true,
  );

  /// El sistema dice que esta red SÍ llega. Eso **no** dice que la conexión
  /// sirva: apaga la bandera y nada más. Si los intentos seguían cayéndose, el
  /// aviso se queda puesto.
  SaludDeLaRed conSalidaAInternet() => SaludDeLaRed(
    fallosSeguidos: fallosSeguidos,
    ultimaBuena: ultimaBuena,
    sinInterfaz: sinInterfaz,
  );

  /// Volvió la interfaz. Eso NO dice que la conexión sirva: se quita la
  /// certeza de que no hay, y lo demás lo sigue diciendo una petición que
  /// llegue. Si los ciclos seguían cayéndose, el aviso se queda puesto.
  SaludDeLaRed conInterfaz() => SaludDeLaRed(
    fallosSeguidos: fallosSeguidos,
    ultimaBuena: ultimaBuena,
    sinSalida: sinSalida,
  );

  /// Un ciclo que se cayó por red. Los otros fallos —sesión muerta, un rechazo
  /// del servidor— **no cuentan**: esos significan que la petición SÍ llegó.
  ///
  /// ## Y SE QUEDAN LAS DOS BANDERAS DEL SISTEMA — 28/09/2026
  ///
  /// Esto no las arrastraba, y era un agujero por el que el aviso se apagaba
  /// solo: con el modo avión puesto, `sinInterfaz` ponía `vaMal` en `true`; a la
  /// primera petición que alguien intentara —un botón, el canal de avisos— esto
  /// devolvía una salud con `sinInterfaz` en `false` y `fallosSeguidos` en 1, o
  /// sea `vaMal` en `false`. **Un fallo MÁS apagaba el aviso.** Lo que dice el
  /// sistema no lo puede borrar un intento caído; lo borra el sistema, cuando
  /// diga otra cosa, o una petición que llegue (`conUnaBuena`).
  SaludDeLaRed conUnaMala() => SaludDeLaRed(
    fallosSeguidos: fallosSeguidos + 1,
    ultimaBuena: ultimaBuena,
    sinInterfaz: sinInterfaz,
    sinSalida: sinSalida,
  );

  @override
  String toString() =>
      'SaludDeLaRed(fallosSeguidos: $fallosSeguidos, '
      'ultimaBuena: $ultimaBuena, sinInterfaz: $sinInterfaz, '
      'sinSalida: $sinSalida)';
}
