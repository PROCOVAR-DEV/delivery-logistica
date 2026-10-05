// La geometria del recorrido, calcada de `../../../../docs/reglas-negocio.md` §1.
//
// **Por que vive aqui y no en `lib/nucleo/geo/`:** el nucleo de geometria es de
// otra ola y todavia no existe; esta tarea sólo escribe dentro de
// `lib/pantallas/`. Cuando se cree, este fichero se mueve tal cual —es Dart puro,
// sin Drift ni Flutter dentro— y sólo cambian los `import`.
//
// **Por que se calca en vez de pedirselo al servidor:** armar la ruta es lo que
// pasa en el patio del almacen, donde no hay senal. Si los km y el orden de
// visita los pusiera el servidor, la ruta no se podria armar sin conexion, que es
// justo el caso de uso principal del proyecto.

import 'dart:math' as math;

/// Un punto en el mapa. Deliberadamente tonto: lo unico que hace falta para
/// medir.
class Punto {
  const Punto(this.lat, this.lng);

  final double lat;
  final double lng;
}

/// Una parada: un punto con su identificador.
class Parada {
  const Parada(this.id, this.lat, this.lng);

  final String id;
  final double lat;
  final double lng;

  Punto get punto => Punto(lat, lng);
}

/// Radio terrestre en km. La misma constante que el servidor.
const radioTierraKm = 6371.0;

double _aRadianes(double grados) => grados * math.pi / 180;

/// Haversine. **Sin redondeo**, igual que `pricing.ts`: el redondeo lo pone
/// quien enseña el numero, no quien lo calcula. Redondear aqui hace que la suma
/// de diez tramos no cuadre con la suma que hace el servidor.
double haversineKm(Punto a, Punto b) {
  final dLat = _aRadianes(b.lat - a.lat);
  final dLng = _aRadianes(b.lng - a.lng);
  final s =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_aRadianes(a.lat)) *
          math.cos(_aRadianes(b.lat)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(s), math.sqrt(1 - s));
  return radioTierraKm * c;
}

/// Como se mide la distancia entre dos paradas. Se pasa por fuera **para dejar
/// la puerta abierta al enrutador por calles**: el dia que la matriz salga de
/// `lib/mapa/` en vez de la linea recta, se cambia esta funcion y el orden de
/// visita no se entera. Mientras tanto el valor por defecto es `haversineKm` y
/// nada de aqui depende de que exista ese enrutador.
typedef DistanciaKm = double Function(Punto a, Punto b);

/// La mejora minima, en km, para dar por bueno un movimiento.
///
/// **NUNCA se compara con `> 0` a secas, y no es celo.** Dos recorridos de la
/// misma longitud no dan exactamente el mismo `double`: el orden en que se
/// suman los tramos cambia el ultimo bit, asi que A «mejora» a B por 1e-16 km y
/// B «mejora» a A por otro tanto. Con `> 0` eso es un bucle que no termina, y
/// —peor— no termina IGUAL en Dart que en Go, porque el `sin`/`cos` de cada
/// lenguaje redondea distinto en el ultimo bit. 1e-9 km es un micrometro: se
/// traga ese ruido entero y no se traga ninguna mejora de verdad.
const mejoraMinimaKm = 1e-9;

/// Tope de pasadas de mejora. La pantalla del logistico es la que espera.
///
/// Con 60 paradas una pasada son ~13.000 medidas (11 ms medidos en este equipo,
/// `geo_test.dart` los imprime), y ni con 10, ni con 30, ni con 60 paradas hace
/// falta mas de 3 pasadas. El tope esta para que un caso patologico
/// —o un `mejoraMinimaKm` que alguien baje— no deje la pantalla colgada: se
/// devuelve el mejor orden encontrado hasta ahi, que siempre es mejor o igual
/// que el del vecino mas proximo.
const topeDePasadasDeMejora = 50;

/// El orden de visita **bueno**: vecino mas proximo y despues 2-opt y Or-opt
/// sobre el circuito CERRADO, hasta que no mejore.
///
/// **Por que se cambio (21/09/2026).** Jose, viendo una planificada: «esa
/// planificada esta mal, no hace ruta logica ni nada». Y tenia razon: el vecino
/// mas proximo a secas se come los caramelos cercanos y deja los lejanos
/// sueltos, asi que la ruta cruza sobre si misma y el ultimo tramo es un viaje
/// entero de vuelta al almacen. No estaba rota: es lo que hace ese algoritmo.
///
/// **Sobre el circuito cerrado, no sobre la ida.** El camion vuelve al almacen y
/// esos km ya se cobran (`kmDelCircuito`). Mejorar solo la ida deja justo el
/// tramo que mas duele —el regreso— fuera de la cuenta.
///
/// Los dos movimientos, y por que hacen falta los dos:
///
///  * **2-opt** invierte un trozo del recorrido. Es lo unico que deshace un
///    cruce: dos tramos que se cortan siempre son mas largos que los dos que
///    salen de invertir lo que hay entre ellos.
///  * **Or-opt** mueve 1, 2 o 3 paradas seguidas a otro sitio SIN invertir nada.
///    Es lo que recoloca al cliente que se quedo solo en medio de la nada
///    —eso 2-opt no lo arregla, porque mover una sola parada no es invertir un
///    trozo.
///
/// **Determinismo, que es la parte que se rompe sin que salte nada:** el mismo
/// orden de entrada da el mismo orden de salida aqui y en `api/internal/api/
/// rutas.go` (`ordenDeVisita`), porque las dos hacen las pasadas en el mismo
/// orden, aplican la PRIMERA mejora que encuentran y comparan con
/// `mejoraMinimaKm`. Lo ata `docs/orden-de-paradas.casos.json`, que leen la
/// prueba de aqui y la de Go: si alguien toca un lado y no el otro, se pone
/// rojo.
List<String> ordenDeVisita(
  Punto origen,
  List<Parada> paradas, {
  DistanciaKm distancia = haversineKm,
}) {
  final circuito = _Circuito(
    origen,
    _porVecinoMasProximo(origen, paradas, distancia),
    distancia,
  );
  var pasadas = 0;
  while (pasadas < topeDePasadasDeMejora) {
    pasadas++;
    // Las dos pasadas SIEMPRE, sin cortocircuito: si se escribiera
    // `dosOpt() || orOpt()`, el Or-opt no correria en cuanto el 2-opt mejorara
    // algo, y el resultado dependeria de cual encontro antes.
    final movioDosOpt = circuito.pasadaDeDosOpt();
    final movioOrOpt = circuito.pasadaDeOrOpt();
    if (!movioDosOpt && !movioOrOpt) break;
  }
  return [for (final p in circuito.paradas) p.id];
}

/// El orden de visita por **vecino mas proximo**, sin 2-opt ni nada despues.
///
/// Se queda tal cual, y no por nostalgia: es el punto de partida de
/// [ordenDeVisita] y es **la vara con la que se mide** que la mejora mejora de
/// verdad (`geo_test.dart`). Quien arma una ruta llama a [ordenDeVisita].
///
/// Dos detalles que hay que conservar letra a letra o el orden cambia:
///
///  * los casos limite son explicitos: 0 paradas → `[]`, 1 parada → `[su id]`;
///  * **el desempate lo gana la PRIMERA de la lista** (la comparacion es `<`
///    estricta, no `<=`). Con dos clientes a la misma distancia, el orden de
///    salida del camion tiene que ser el mismo aqui y en el servidor, o la
///    paridad falla sin que nada este roto.
List<String> vecinoMasCercano(Punto origen, List<Parada> paradas) => [
  for (final p in _porVecinoMasProximo(origen, paradas, haversineKm)) p.id,
];

/// El greedy de siempre, devolviendo las paradas en vez de sus ids: [ordenDeVisita]
/// necesita las coordenadas para seguir midiendo. Es el MISMO bucle que usaba
/// `vecinoMasCercano`, no una copia: dos greedy escritos en paralelo terminan
/// desempatando distinto, que es justo lo que no puede pasar.
List<Parada> _porVecinoMasProximo(
  Punto origen,
  List<Parada> paradas,
  DistanciaKm distancia,
) {
  if (paradas.isEmpty) return const [];
  if (paradas.length == 1) return [paradas.first];

  final quedan = [...paradas];
  final orden = <Parada>[];
  var actual = origen;

  while (quedan.isNotEmpty) {
    var masCerca = 0;
    var distanciaMinima = double.infinity;
    for (var i = 0; i < quedan.length; i++) {
      final km = distancia(actual, quedan[i].punto);
      if (km < distanciaMinima) {
        distanciaMinima = km;
        masCerca = i;
      }
    }
    final elegida = quedan.removeAt(masCerca);
    orden.add(elegida);
    actual = elegida.punto;
  }
  return orden;
}

/// El recorrido a medio mejorar. El almacen NO esta en la lista: es el nodo
/// -1 y el nodo n a la vez, que es lo que hace que el circuito este cerrado sin
/// tener que meter el almacen como parada (si estuviera dentro, 2-opt podria
/// moverlo y la ruta dejaria de empezar en el almacen).
class _Circuito {
  _Circuito(this.origen, List<Parada> paradas, this.distancia)
    : paradas = [...paradas];

  final Punto origen;
  final DistanciaKm distancia;
  List<Parada> paradas;

  /// El almacen por los dos extremos: fuera del rango, el nodo es el origen.
  Punto _nodo(int i) =>
      (i < 0 || i >= paradas.length) ? origen : paradas[i].punto;

  double _paso(int i, int j) => distancia(_nodo(i), _nodo(j));

  /// **2-opt**: invertir el trozo `[i..j]` y quedarse con la inversion si acorta
  /// el circuito. Los dos tramos que cambian son el de entrada al trozo y el de
  /// salida; lo de dentro se recorre al reves y mide lo mismo.
  ///
  /// Se aplica la PRIMERA mejora que aparece (no la mejor de todas) y se sigue
  /// barriendo desde donde iba. Es lo mismo en Go, linea por linea: quedarse con
  /// «la mejor» obligaria a desempatar entre dos mejoras iguales, y ahi es donde
  /// los dos lenguajes se separarian.
  bool pasadaDeDosOpt() {
    var movio = false;
    for (var i = 0; i < paradas.length - 1; i++) {
      for (var j = i + 1; j < paradas.length; j++) {
        final cambio =
            _paso(i - 1, j) +
            _paso(i, j + 1) -
            _paso(i - 1, i) -
            _paso(j, j + 1);
        if (cambio < -mejoraMinimaKm) {
          _invertir(i, j);
          movio = true;
        }
      }
    }
    return movio;
  }

  void _invertir(int desde, int hasta) {
    var a = desde;
    var b = hasta;
    while (a < b) {
      final t = paradas[a];
      paradas[a] = paradas[b];
      paradas[b] = t;
      a++;
      b--;
    }
  }

  /// **Or-opt**: sacar 1, 2 o 3 paradas seguidas y volverlas a meter en otro
  /// sitio, en el mismo sentido.
  ///
  /// El hueco de insercion `p` se cuenta sobre la lista YA SIN el trozo, asi que
  /// `p == inicio` es dejarlo donde estaba: se salta a proposito. Su cambio da
  /// cero exacto —son las mismas tres medidas restadas— pero saltarlo deja claro
  /// que no hay ningun movimiento nulo que pueda «mejorar» por redondeo.
  bool pasadaDeOrOpt() {
    var movio = false;
    for (var largo = 1; largo <= 3; largo++) {
      for (var inicio = 0; inicio + largo <= paradas.length; inicio++) {
        final trozo = paradas.sublist(inicio, inicio + largo);
        final resto = [
          ...paradas.sublist(0, inicio),
          ...paradas.sublist(inicio + largo),
        ];
        // Lo que se ahorra al sacar el trozo: los dos tramos que lo sujetaban
        // menos el que queda al juntar sus vecinos.
        final ahorro =
            _paso(inicio - 1, inicio) +
            _paso(inicio + largo - 1, inicio + largo) -
            distancia(_nodo(inicio - 1), _nodo(inicio + largo));
        for (var p = 0; p <= resto.length; p++) {
          if (p == inicio) continue;
          final antes = p == 0 ? origen : resto[p - 1].punto;
          final despues = p == resto.length ? origen : resto[p].punto;
          final costo =
              distancia(antes, trozo.first.punto) +
              distancia(trozo.last.punto, despues) -
              distancia(antes, despues);
          if (costo - ahorro < -mejoraMinimaKm) {
            paradas = [...resto.sublist(0, p), ...trozo, ...resto.sublist(p)];
            movio = true;
            break; // el `resto` ya no vale: se rehace en la vuelta siguiente.
          }
        }
      }
    }
    return movio;
  }
}

/// Las distancias consecutivas `origen→p1, p1→p2, …`, una por parada.
///
/// **No cierra el circuito**: el regreso al origen lo suma quien llame, porque
/// hay dos numeros distintos y el pliego pinta el de «incl. regreso».
List<double> tramos(Punto origen, List<Parada> ordenadas) {
  final salida = <double>[];
  var actual = origen;
  for (final parada in ordenadas) {
    salida.add(haversineKm(actual, parada.punto));
    actual = parada.punto;
  }
  return salida;
}

/// Los km del camion: los tramos **mas el regreso al origen**. Es un circuito
/// cerrado, y es el numero que la pantalla enseña como `<km> km (incl. regreso)`.
double kmDelCircuito(Punto origen, List<Parada> ordenadas) {
  if (ordenadas.isEmpty) return 0;
  final ida = tramos(origen, ordenadas).fold<double>(0, (a, b) => a + b);
  return ida + haversineKm(ordenadas.last.punto, origen);
}
