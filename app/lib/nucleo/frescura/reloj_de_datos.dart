import 'package:flutter/material.dart';

import '../../diseno/colores.dart';
import '../plataforma.dart';

import 'package:intl/intl.dart';

/// En que tramo cae lo que se esta viendo.
///
/// Es una funcion pura y por eso se puede probar con el reloj movido a mano, sin
/// pintar nada.
sealed class EstadoFrescura {
  const EstadoFrescura();

  /// CUANTO PUEDE IR EL RELOJ DEL APARATO POR DETRAS DE LA MARCA sin que eso
  /// signifique nada.
  ///
  /// La marca de la bajada la pone **el servidor** y la hora la pone **el
  /// aparato**: que no cuadren al segundo es lo normal, no una averia. Cinco
  /// minutos dejan sitio de sobra para el desfase de dos relojes que nadie
  /// sincroniza, y siguen siendo mucho menos que cualquier salto de verdad —los
  /// que pasan son de horas o de años, no de minutos.
  ///
  /// **Vive aqui porque aqui es donde se decide.** El Panel tiene el mismo
  /// numero en `pantallas/panel/datos/textos_del_dia.dart`, y los dos estan
  /// atados por una prueba y no por un comentario (§3-bis): dos copias que se
  /// separen dan un Panel en ambar sobre una franja en gris, o al reves.
  static const margenDelReloj = Duration(minutes: 5);

  /// El tramo que toca, con el reloj del aparato.
  ///
  /// [bajadaAt] a `null` **no es** «hace mucho»: es que no se bajo NUNCA, y es
  /// un estado distinto que hay que decir con otras palabras.
  factory EstadoFrescura.de(DateTime? bajadaAt, {required DateTime ahora}) {
    if (bajadaAt == null) return const SinDescargar();
    // EL RELOJ DEL APARATO POR DETRAS DE SUS PROPIOS DATOS — 24/09/2026.
    //
    // Al repartidor se le apaga el telefono en la calle y vuelve con el reloj de
    // fabrica; o alguien le cambia la hora; o se queda una mañana sin hora de
    // red. A partir de ahi `ahora` es ANTERIOR a la marca de la ultima bajada,
    // que la pone el servidor.
    //
    // Sin esta rama, `desde` sale NEGATIVO — y un negativo es menor que una
    // hora, asi que contestaba [DatosRecientes]: «Datos de las 16:40», una hora
    // que todavia no ha pasado, en gris y con `enAmbar` a `false`. El Panel arma
    // `hayQueTraer` con ese mismo `enAmbar`, asi que decia «todo al dia» **y no
    // ofrecia el boton de Traer el dia**: con los pedidos de anteayer dentro y
    // el gesto que lo arregla quitado de en medio.
    //
    // Una diferencia negativa no es «reciente»: es que el reloj de este aparato
    // no cuadra, y eso es un estado propio que hay que nombrar y pintar en
    // ambar.
    if (bajadaAt.difference(ahora) > margenDelReloj) {
      return RelojQueNoCuadra(bajadaAt);
    }
    final desde = ahora.difference(bajadaAt);
    if (desde < const Duration(hours: 1)) return DatosRecientes(bajadaAt);
    if (desde < const Duration(hours: 24)) return DatosDeHoras(desde.inHours);
    return DatosViejos(bajadaAt, desde.inDays);
  }

  /// El texto de la barra, literal.
  String get texto;

  /// En ambar = «mira esto». Sólo lo que de verdad puede enganar: lo de hace
  /// mas de un dia y lo que no se bajo nunca. Pintarlo todo en ambar es no
  /// pintar nada.
  bool get enAmbar;
}

/// TODAVIA NO SE HA MIRADO. Gris, y **no es [SinDescargar]** — 28/09/2026.
///
/// Jose, abriendo la aplicacion sin senal en un SM-A165M: el renglon de frescura
/// decia que no habia nada durante unos **cuatro segundos** y despues se
/// asentaba en «datos de las 15:03», encima de una base que si tenia cosas.
///
/// Lo que pasa: la consulta que dice de cuando son los datos es un stream sobre
/// la base, y en un telefono de gama baja la primera respuesta tarda —abrir el
/// fichero, las migraciones y nueve conteos sobre tablas con decenas de miles de
/// renglones—. Mientras tanto no se sabe NADA, y lo que se pintaba era el estado
/// que significa «este aparato no ha bajado nunca»: en ambar, que es la senal de
/// «mira esto», y ofreciendo traer el dia que ya estaba dentro.
///
/// **«No hay nada» y «todavia no he mirado» son dos cosas.** Es el §3-ter del
/// `CLAUDE.md` en su forma mas corta: un estado vacio que se lee como otro. Que
/// dure cuatro segundos no lo hace menor —es justo el momento en que alguien
/// abre la aplicacion y decide si le hace falta traer el dia antes de salir—.
///
/// Va en GRIS y sin diagnostico, por lo mismo que `PorQueEstaVacio.todaviaBajando`
/// (`frescura/primera_bajada.dart`): todavia no se ha mirado nada, asi que no hay
/// nada que acusar.
class SinMirarTodavia extends EstadoFrescura {
  const SinMirarTodavia();

  @override
  String get texto => 'Mirando qué hay…';

  @override
  bool get enAmbar => false;
}

/// Nunca se bajo. Ambar.
class SinDescargar extends EstadoFrescura {
  const SinDescargar();

  @override
  String get texto => 'Sin descargar todavía';

  @override
  bool get enAmbar => true;

  /// El estado vacio de una coleccion que nunca se bajo. **No es el mismo que
  /// «no hay nada»**, y por eso tiene su propio texto: una lista vacia ahi es un
  /// fallo, no un dato (caso S7).
  static const textoDeLaPantallaVacia =
      'Esta pantalla no se ha descargado todavía. Con conexión baja sola.';
}

/// EL RELOJ DEL APARATO VA POR DETRAS DE LA MARCA DE SU PROPIA BAJADA. **Ambar.**
///
/// No se dice la hora, y es a proposito: la hora es justo lo que no vale. Decir
/// «Datos de las 16:40» cuando son las 14:00 es escribir una hora del futuro con
/// cara de dato.
///
/// Lo que se dice es lo unico cierto y lo unico con lo que se puede hacer algo:
/// **este aparato no sabe que hora es**, asi que de cuando son los datos no lo
/// sabe nadie — y por eso va en ambar, que es lo que enciende el gesto de traer
/// el dia.
class RelojQueNoCuadra extends EstadoFrescura {
  const RelojQueNoCuadra(this.bajadaAt);

  /// La marca que dejo la bajada. No se pinta: se guarda para poder decirlo en
  /// el registro y para que quien quiera comparar tenga con que.
  final DateTime bajadaAt;

  @override
  String get texto => 'El reloj de este aparato no cuadra';

  @override
  bool get enAmbar => true;
}

/// Menos de una hora. Gris. Se dice la hora porque a esa distancia es util.
class DatosRecientes extends EstadoFrescura {
  const DatosRecientes(this.bajadaAt);

  final DateTime bajadaAt;

  @override
  String get texto => 'Datos de las ${DateFormat('H:mm').format(bajadaAt)}';

  @override
  bool get enAmbar => false;
}

/// Entre una hora y un dia. Gris. Se dice la distancia, que es lo que importa.
class DatosDeHoras extends EstadoFrescura {
  const DatosDeHoras(this.horas);

  final int horas;

  @override
  String get texto => 'Datos de hace $horas h';

  @override
  bool get enAmbar => false;
}

/// Mas de un dia. **Ambar.** Aqui es donde se arma la ruta de anteayer.
class DatosViejos extends EstadoFrescura {
  const DatosViejos(this.bajadaAt, this.dias);

  final DateTime bajadaAt;
  final int dias;

  @override
  String get texto {
    final dia = DateFormat('EEEE', 'es').format(bajadaAt);
    final cuantos = dias == 1 ? 'hace 1 día' : 'hace $dias días';
    return 'Datos del $dia — $cuantos';
  }

  @override
  bool get enAmbar => true;
}

/// El reloj de datos. **Siempre visible, en las 7 pantallas** (caso S8).
///
/// Dice dos cosas y sólo dos: **de que hora son los datos** y **cuantos apuntes
/// quedan sin subir**.
///
/// Lo que NO dice es `actualizando…`. Lo decia, y el resultado era dos ruedas
/// girando a la vez en la misma pantalla: una junto al titulo de la barra
/// superior y otra dentro de la franja de debajo, diciendo lo mismo una encima
/// de la otra. El sitio de «hay algo en vuelo» es la barra superior —es lo que
/// hace la de Next (`Navbar.tsx`, `useIsFetching() > 0` al lado del titulo)—, y
/// **es el unico**. Aqui se quito el parametro entero en vez de dejarlo apagado
/// con un `if`: un parametro que nadie pone vuelve solo a los seis meses.
///
/// Recibe todo por parametro y no lee providers: asi se prueba con el reloj
/// donde haga falta y no arrastra media aplicacion a un test de widget.
class RelojDeDatos extends StatelessWidget {
  const RelojDeDatos({
    required this.estado,
    this.sinSubir = 0,
    this.alPulsarPendientes,
    super.key,
  });

  final EstadoFrescura estado;

  /// Cuantos apuntes quedan en la cola. Pulsable: lleva a la bandeja.
  final int sinSubir;

  final VoidCallback? alPulsarPendientes;

  // AQUI HABIA DOS COLORES COPIADOS A MANO —`#96560A` y `#5C544A`— con el
  // motivo de que «nucleo/ no depende de diseno/». El motivo era bueno y el
  // resultado malo: el dia que la paleta paso a salir del oro del logo, estos
  // dos se quedaron con el ambar y el gris viejos, y este reloj era el unico
  // sitio de la aplicacion pintado de la paleta anterior.
  //
  // `diseno/colores.dart` no arrastra nada: es un fichero de tokens que solo
  // importa `material`. Se importa y se acabo la copia.

  @override
  Widget build(BuildContext context) {
    // EN LA WEB ESTO NO PINTA NADA, Y ES LA REGLA 1 — 17/09/2026.
    //
    // Este reloj dice dos cosas: de que hora es **tu copia** y cuanto te queda
    // **sin subir**. Las dos son del mundo de no tener senal. En un navegador no
    // hay copia que pueda envejecer ni cola que pueda atascarse: se lee del
    // servidor y lo que se hace sale en el momento.
    //
    // Asi que ahi «Datos de las 10:36» no informa de nada — y el dia que la
    // marca se quede atras por cualquier motivo, informa de algo FALSO, que es
    // peor.
    //
    // Va aqui y no en las siete pantallas que lo llaman a proposito: en siete
    // sitios se olvida uno, y el que se olvide es el que vera Jose. Van ya cinco
    // veces que hay que repetirselo: «la web siempre esta en linea, nunca se
    // desconecta; quita todo lo que tenga que ver con eso».
    //
    // Lo que SI se queda en la web es la pantalla de Sincronizacion, que es otra
    // cosa: no habla de esta maquina, habla de **los telefonos**, y existe para
    // ver desde el servidor cual lleva sin subir y desde cuando.
    //
    // Se lee `Destino` y no un provider a proposito: es un booleano de
    // plataforma, no arrastra medio arbol a una prueba de widget, y
    // `Destino.comoSiFueraWeb` deja probar los dos lados.
    if (!Destino.trabajaSinConexion) return const SizedBox.shrink();

    final tema = Theme.of(context);
    final color = estado.enAmbar ? Colores.ambar : Colores.tintaSuave;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          estado.texto,
          style: tema.textTheme.bodySmall?.copyWith(color: color),
        ),
        if (sinSubir > 0) ...[
          const SizedBox(width: 8),
          // Nada se descarta en silencio: lo que queda sin subir se ve y se
          // puede abrir.
          TextButton(
            onPressed: alPulsarPendientes,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: Colores.ambar,
              textStyle: tema.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text('$sinSubir sin subir'),
          ),
        ],
      ],
    );
  }
}
