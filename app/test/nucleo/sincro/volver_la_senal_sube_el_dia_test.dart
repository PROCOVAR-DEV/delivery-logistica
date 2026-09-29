// VOLVER LA SEÑAL TIENE QUE SUBIR EL DÍA, sin esperar al reloj.
//
// Medido en el teléfono de Jose: con la jornada entera dentro del aparato, se
// recupera la señal y la subida tarda **cinco minutos**. Cinco minutos es, al
// segundo, `VigiaDeSincronizacion.periodoPorDefecto`, así que no la disparaba la
// señal: la disparaba el reloj, y la señal no se enteraba de nada.
//
// El motivo, y es del sitio en el que se usa esto. El vigía escuchaba sólo a
// `connectivity_plus`, que avisa cuando cambia **a qué estás enganchado**. En
// Cuba eso casi nunca cambia: el teléfono se queda pegado al mismo wifi o a los
// mismos datos toda la mañana, y lo que se cae y vuelve está aguas arriba — la
// línea, la antena, el proveedor. Para el plugin no ha pasado nada y no emite
// ni una vez.
//
// Desde el 28/09/2026 sí hay quien se entera: el canal nativo que lee el
// veredicto del propio Android, el mismo que enciende ese icono de wifi con la
// exclamación. Estaba puesto para pintar la franja y nada más. Aquí se une al
// otro.
//
// Jose, el 28/09 y sobre esa misma pantalla: «si sale la wifi ahora mismo cuando
// no tiene conexión sale un icono de wifi con ! este símbolo diciendo que no hay
// internet».

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/veredicto_del_sistema.dart';
import 'package:reparto/nucleo/sincro/vigia.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../pantallas/traer_el_dia/apoyo_traer_el_dia.dart';

void main() {
  late StreamController<bool> connectivity;
  late StreamController<bool> veredicto;

  setUp(() {
    connectivity = StreamController<bool>.broadcast();
    veredicto = StreamController<bool>.broadcast();
  });

  tearDown(() async {
    await connectivity.close();
    await veredicto.close();
  });

  Stream<bool> juntas() => juntarAvisosDeRed([
    () => connectivity.stream,
    () => veredicto.stream,
  ]);

  // LA PRUEBA QUE VALE POR TODAS: el plugin callado, que es el caso real.
  test('el veredicto de Android dispara el ciclo con el plugin callado', () async {
    final disparos = <String>[];
    final vigia = VigiaDeSincronizacion(
      ciclo: (motivo) async => disparos.add(motivo),
      avisosDeRed: juntas,
      // Temporizador de mentira que NO toca nunca: si el ciclo se dispara, ha
      // sido por la señal. Con uno de verdad esta prueba pasaría aunque el
      // arreglo no estuviera, sólo que cinco minutos más tarde.
      crearTemporizador: (_, _) => _NuncaToca(),
    );
    vigia.arrancar();
    addTearDown(vigia.parar);

    veredicto.add(true);
    await Future<void>.delayed(Duration.zero);

    expect(
      disparos,
      ['volvio la red'],
      reason:
          'volvió la señal y no subió nada. El plugin de conectividad no emite '
          'porque el teléfono sigue enganchado al mismo sitio: si el vigía no '
          'escucha además el veredicto de Android, el día espera al reloj — '
          'cinco minutos, que es justo lo que se midió',
    );
  });

  test('y el aviso de siempre sigue disparando, que es el de escritorio', () async {
    final disparos = <String>[];
    final vigia = VigiaDeSincronizacion(
      ciclo: (motivo) async => disparos.add(motivo),
      avisosDeRed: juntas,
      crearTemporizador: (_, _) => _NuncaToca(),
    );
    vigia.arrancar();
    addTearDown(vigia.parar);

    connectivity.add(true);
    await Future<void>.delayed(Duration.zero);

    expect(
      disparos,
      ['volvio la red'],
      reason:
          'se perdió el aviso de siempre al añadir el nuevo. En escritorio y en '
          'la web el veredicto de Android no existe: allí éste es el único que '
          'hay, y quedarse sin él es cambiar un agujero por otro',
    );
  });

  test('una fuente que revienta no se lleva a la otra por delante', () async {
    final visto = <bool>[];
    final rota = StreamController<bool>();
    final sana = StreamController<bool>();
    addTearDown(sana.close);

    final sub = juntarAvisosDeRed([
      () => rota.stream,
      () => sana.stream,
    ]).listen(visto.add);
    addTearDown(sub.cancel);

    rota.addError(StateError('el canal nativo no contestó'));
    await Future<void>.delayed(Duration.zero);
    sana.add(true);
    await Future<void>.delayed(Duration.zero);

    expect(
      visto,
      [true],
      reason:
          'un destino sin canal nativo dejaría al aparato sin NINGÚN aviso de '
          'red: el fallo de una fuente no puede cerrar el stream de la otra',
    );
  });

  test('no se escucha nada hasta que alguien escucha', () async {
    var abiertas = 0;
    final juntadas = juntarAvisosDeRed([
      () {
        abiertas++;
        return const Stream<bool>.empty();
      },
    ]);

    expect(
      abiertas,
      0,
      reason:
          'las fuentes se abren al construir. El vigía arranca y para con la '
          'sesión, y esto deja al aparato sondeando la red sin nadie dentro',
    );

    final sub = juntadas.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(abiertas, 1);

    await sub.cancel();
  });

  test('cancelar suelta las dos fuentes', () async {
    final sub = juntas().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(connectivity.hasListener, isTrue);
    expect(veredicto.hasListener, isTrue);

    await sub.cancel();
    await Future<void>.delayed(Duration.zero);

    expect(
      connectivity.hasListener || veredicto.hasListener,
      isFalse,
      reason:
          'quedó una fuente escuchando tras parar el vigía. Cerrar sesión deja '
          'el aparato hablando con la red por su cuenta',
    );
  });

  _elEnganche();
  _elCicloDeVerdad();
}

// Y LA PRUEBA QUE HABRIA CAZADO ESTO EL PRIMER DIA.
//
// Todo lo anterior mira piezas. Ésta monta **el cableado de producción entero**
// —el de `montarTraerElDia`, con el servidor cambiado y nada más— y comprueba lo
// único que le importa a quien lleva el teléfono: que al volver la salida, el
// día sale del aparato sin que nadie toque nada y sin esperar cinco minutos.
//
// Se comprobó quitando el `avisosDeRed:` de `vigiaProvider` el 29/09/2026: sin
// esta prueba, las 118 del sincronizador seguían en verde con el arreglo
// desconectado. Que es, palabra por palabra, cómo llegó aquí el problema.
void _elCicloDeVerdad() {
  test('al volver la salida, el día sube solo', () async {
    final base = baseDePrueba();
    addTearDown(base.close);

    final delSistema = StreamController<Veredicto>.broadcast();
    addTearDown(delSistema.close);

    final pedidas = <String>[];
    final caja = montarTraerElDia(
      base: base,
      reloj: () => DateTime(2026, 9, 29, 10),
      // EL PLUGIN, CALLADO Y EN «NO». Es el caso real: el teléfono no cambia de
      // enganche, así que por ahí no llega ni un aviso. Si esto se deja en
      // `true`, dispara el ciclo por su cuenta y la prueba sale verde sin
      // comprobar nada.
      hayPista: false,
      responder: (peticion) async {
        pedidas.add(peticion.ruta);
        return null;
      },
      veredictoAhora: () async => Veredicto.noLoSe,
      avisosDeVeredicto: () => delSistema.stream,
      esperaDelSondeo: (_, alTocar) => _AlMomento(alTocar),
    );
    addTearDown(caja.dispose);

    // Vivo mientras dure la prueba, como lo tiene la aplicación: en Riverpod 3
    // un `read` a secas lo construye y lo desecha en el mismo salto, y el
    // `ref.onDispose` para el vigía antes de que llegue nada.
    final vivo = caja.listen(vigiaProvider, (_, _) {});
    addTearDown(vivo.close);
    vivo.read().arrancar();
    await _asentar();
    pedidas.clear();

    // Android dice que por aquí SÍ se sale. Es el instante exacto en el que se
    // apaga el icono de wifi con la exclamación.
    delSistema.add(Veredicto.valida);
    await _asentar();

    expect(
      pedidas,
      isNotEmpty,
      reason:
          'volvió la salida y el aparato no habló con el servidor. Con la '
          'jornada dentro, eso son los cinco minutos que midió Jose: el día se '
          'queda esperando al reloj en vez de salir en cuanto hay por dónde',
    );
  });
}

// Y LA MITAD QUE DE VERDAD SE PUEDE PERDER: que siga ENGANCHADO.
//
// Todo lo de arriba comprueba la pieza. Una pieza correcta y desconectada es
// justo el estado en el que estaba esto hasta hoy: el canal nativo llevaba un
// día puesto, funcionando y contestando, y sólo pintaba una franja. Así que
// aquí se monta el proveedor de verdad, con el canal falso por debajo, y se
// mira que un veredicto de Android salga por donde bebe el vigía.
void _elEnganche() {
  test('un veredicto válido de Android sale por donde bebe el vigía', () async {
    final delSistema = StreamController<Veredicto>.broadcast();
    addTearDown(delSistema.close);

    final contenedor = ProviderContainer(
      overrides: [
        // El canal nativo no existe en una prueba: las tres piezas del veredicto
        // son providers precisamente para esto (`proveedores.dart`).
        veredictoAhoraProvider.overrideWithValue(
          () async => Veredicto.noLoSe,
        ),
        avisosDeVeredictoProvider.overrideWithValue(() => delSistema.stream),
        // La ventana de sondeo dispara a mano: un `Timer` de verdad dentro de
        // una prueba la cuelga en vez de fallarla (§5 del CLAUDE.md).
        crearEsperaDelSondeoProvider.overrideWithValue(
          (_, alTocar) => _AlMomento(alTocar),
        ),
        // El plugin de conectividad tampoco existe aquí. Callado, que es
        // además el caso real del teléfono de Jose.
        avisosDeRedProvider.overrideWithValue(
          () => const Stream<bool>.empty(),
        ),
      ],
    );
    addTearDown(contenedor.dispose);

    final visto = <bool>[];
    // SE MANTIENE VIVO COMO LO MANTIENE EL VIGIA: con una escucha. Un `read` a
    // secas lo construye y lo tira en el mismo salto —Riverpod 3 desecha por
    // defecto— y entonces el `ref.onDispose` cierra el controlador antes de que
    // llegue nada. Fallaría por eso, no por lo que mide.
    final vivo = contenedor.listen(avisosParaElVigiaProvider, (_, _) {});
    addTearDown(vivo.close);
    final sub = vivo.read()().listen(visto.add);
    addTearDown(sub.cancel);
    // HAY QUE DEJAR QUE LA CADENA SE ENCHUFE ANTES DE EMPUJAR NADA, y son
    // varios saltos: el `ref.listen` monta el `StreamProvider`, éste construye
    // el stream crudo, que empieza con un `await` a la pregunta de una vez, y
    // sólo entonces se engancha a los avisos. `delSistema` es de difusión, así
    // que lo que se emita antes de ese momento no lo recibe nadie — y la prueba
    // fallaría por el `await` que falta, no por el enganche que mide.
    await _asentar();

    delSistema.add(Veredicto.valida);
    await _asentar();

    expect(
      visto,
      [true],
      reason:
          'el veredicto de Android no llega al vigía. La pieza puede estar '
          'perfecta y desconectada — es exactamente como estuvo el canal '
          'nativo su primer día: contestaba bien y sólo pintaba una franja',
    );

    // Y el otro lado, que es lo que evita que esto se convierta en un ciclo por
    // cada parpadeo de la antena.
    delSistema.add(Veredicto.noValida);
    await _asentar();
    expect(
      visto,
      [true],
      reason:
          'perder la salida dispara un ciclo. Sin red no hay nada que hacer, y '
          'un intento a tumba abierta gasta batería para acabar en FalloDeRed',
    );
  });
}

/// Unos cuantos saltos del bucle, para que una cadena de streams con `await`
/// dentro termine de enchufarse. Sin reloj de verdad: aquí no se espera a nada
/// que tarde, se espera a que las suscripciones estén puestas.
Future<void> _asentar() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// La espera de la ventana de sondeo, disparada al momento.
class _AlMomento implements Timer {
  _AlMomento(void Function() alTocar) {
    alTocar();
  }

  @override
  void cancel() {}
  @override
  bool get isActive => false;
  @override
  int get tick => 0;
}

/// Un temporizador que no toca NUNCA. Así, un ciclo disparado sólo puede venir
/// de la señal, que es lo único que se comprueba aquí.
class _NuncaToca implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => true;
  @override
  int get tick => 0;
}
