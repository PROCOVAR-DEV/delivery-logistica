// DESCARTAR UN RECHAZO TIENE QUE QUEDARSE DESCARTADO.
//
// Jose, 29/09/2026, mirando el cajón de entregar el día en su teléfono:
//
//     «los errores se acumulan y nunca se borran se mantienen aunq se allan
//      borrado las cosas y solucionado nunca se borran en la parte de entrega
//      del dia»
//
// Y el botón de «Descartar» estaba puesto, se pintaba, y borraba de verdad. Por
// eso costó verlo: cada pieza hacía bien lo suyo, y el círculo lo formaban las
// tres juntas.
//
//   1. Se descarta el rechazo y el apunte se borra.
//   2. La zona que ese apunte iba a subir se queda **sin ningún apunte que hable
//      de ella**, que es, palabra por palabra, la definición de huérfana
//      (`nucleo/sincro/huerfanos.dart`).
//   3. El ciclo la ve colgada y la vuelve a encolar — para eso está, y el día
//      que se escribió eso arregló un atasco de verdad.
//   4. El servidor repite su no, y el mismo rechazo vuelve a la bandeja con
//      clave nueva y la misma pinta.
//
// Nadie miente ahí dentro. Lo que faltaba es que **la decisión de la persona
// quedara escrita en algún sitio**, y el único sitio donde cabe es el propio
// apunte: por eso `descartar` ya no borra, marca `descartado`.
//
// Esta prueba recorre el círculo entero, que es la única forma de cazarlo: cada
// paso por separado salía verde el 28/09/2026 y el fallo estaba en la junta.

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/sincro/huerfanos.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late Huerfanos huerfanos;

  setUp(() async {
    base = baseDePrueba();
    // Las tablas del Tablero las crea la propia pantalla la primera vez que se
    // abre; aquí se piden a mano porque esto las mira sin pasar por ella.
    await EsquemaTablero.asegurar(base);
    cola = ColaDeSalida(base);
    huerfanos = Huerfanos(base);
  });

  tearDown(() => base.close());

  /// Una zona creada sin señal, con el apunte que la sube, y el servidor
  /// diciendo que no. Es el estado exacto en el que Jose se encuentra la
  /// bandeja.
  var cuantasVan = 0;

  Future<String> unaZonaRechazada({String id = 'z-1'}) async {
    // Nombre y sitio propios: las zonas de una sucursal no pueden repetir
    // ninguno de los dos, y la prueba de «no toca al de al lado» pide dos.
    cuantasVan++;
    final nombre = 'Zona $cuantasVan';
    await base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
      'updated_at, nacio_aqui) '
      "VALUES (?1, 'stg-1', ?2, ?3, '2026-09-29T08:00:00.000', "
      "'2026-09-29T08:00:00.000', 1)",
      [id, nombre, cuantasVan],
    );
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/board/columns?branchId=stg-1',
      cuerpo: <String, Object?>{'id': id, 'nombre': nombre},
      provisional: id,
    );
    await cola.resolver(
      clave,
      const ResultadoApunte(
        estado: EstadoResultado.rechazado,
        motivo: 'Ya existe una zona con ese nombre',
      ),
    );
    return clave;
  }

  Future<int> nacioAqui(String id) async {
    final fila = await base
        .customSelect(
          'SELECT nacio_aqui AS marca FROM board_columns WHERE id = ?1',
          variables: [Variable<String>(id)],
        )
        .getSingle();
    return fila.read<int>('marca');
  }

  test('lo descartado NO vuelve a la bandeja por la puerta de atrás', () async {
    final clave = await unaZonaRechazada();

    // Antes de decidir: está en la bandeja, y NO es huérfano. Un rechazado
    // espera a una persona, así que nadie lo encola por detrás.
    expect(await base.cuantosRechazados(), 1);
    expect(
      await huerfanos.mirar(),
      isEmpty,
      reason:
          'un rechazo a la espera de una persona no es trabajo colgado: si '
          'esto lo encola, se le insiste a un servidor que ya dijo que no',
    );

    // La persona decide.
    await cola.descartar(clave);

    expect(
      await base.cuantosRechazados(),
      0,
      reason: 'se descartó y sigue en la bandeja: es lo que Jose ve',
    );

    // AQUÍ ESTABA EL FALLO. Antes del 29/09/2026 esto devolvía «1 zona del
    // tablero», y de ahí salía el rechazo repetido cinco minutos después.
    expect(
      await huerfanos.mirar(),
      isEmpty,
      reason:
          'tras descartarlo, la zona se da por huérfana. Eso la vuelve a '
          'encolar, el servidor repite su no y el rechazo reaparece: es el '
          'círculo entero, y desde fuera se lee como «no se borran nunca»',
    );

    // Y la comprobación que no se fía de `mirar()`: que el ciclo, llamado de
    // verdad, no ponga ni un apunte.
    expect(
      await huerfanos.volverAEncolar(cola),
      0,
      reason: 'el desatascador encoló trabajo que una persona acababa de cerrar',
    );
    expect(
      await base.cuantosPendientes(),
      0,
      reason: 'quedó algo en la cola: en el próximo envío vuelve el mismo no',
    );
    expect(
      await base.cuantosRechazados(),
      0,
      reason: 'la bandeja volvió a llenarse sola',
    );
  });

  test('descartar suelta la zona para que la bajada pueda pasar', () async {
    final clave = await unaZonaRechazada(id: 'z-2');
    expect(
      await nacioAqui('z-2'),
      1,
      reason: 'mientras espera decisión, la marca protege el trabajo sin subir',
    );

    await cola.descartar(clave);

    // LA OTRA MITAD, y sin ella el arreglo deja un atasco en vez de un bucle.
    // `nacio_aqui` existe para que una bajada no borre trabajo que todavía no
    // subió. En cuanto una persona dice que ese trabajo ya no sube, seguir
    // protegiéndolo deja de ser proteger: la bajada no puede tocar esa zona y
    // el Tablero de ese aparato se queda congelado esperando una subida que
    // nadie va a hacer. Es el atasco de la zona «Vista» del 16/09/2026, por el
    // otro lado.
    expect(
      await nacioAqui('z-2'),
      0,
      reason:
          'la zona sigue marcada como «nació aquí» después de descartarla. La '
          'bajada no la va a tocar nunca y el Tablero no se actualiza más',
    );
  });

  // LA RUTA, Y AQUÍ ESTÁ LA LÍNEA FINA DE TODO ESTO.
  //
  // El primer arreglo del 29/09/2026 hizo que descartar apagara también el aviso
  // de «sólo en este aparato», y estaba MAL. Lo cazó una prueba que ya existía
  // —`navegacion/la_franja_dice_lo_que_no_sube_test.dart`—, que se puso roja
  // diciendo exactamente lo que pasaba: descartar dejaba la ruta sin nada que la
  // subiera, y eso hay que decirlo.
  //
  // Son DOS preguntas y se parecen demasiado:
  //
  //   «¿hay que volver a encolarlo?»  → un descartado, NO. Ahí estaba el bucle.
  //   «¿esto existe sólo aquí?»       → un descartado, SÍ. Sigue sin subir.
  //
  // Juntarlas se lleva una de las dos por delante: o el rechazo vuelve solo, o
  // el aviso miente. Así que descartar quita el rechazo de la bandeja y **deja
  // el aviso ámbar puesto**, que es verdad — y ese aviso tiene su propio botón,
  // «Dar por perdido», que es el otro gesto y dice otra cosa.
  test('una ruta descartada NO se reencola, pero sigue avisando', () async {
    await base
        .into(base.routes)
        .insert(
          RoutesCompanion.insert(
            id: 'local-r1',
            name: const Value('Ruta del lunes'),
            branchId: const Value('stg-1'),
          ),
        );
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/routes',
      cuerpo: const <String, Object?>{'nombre': 'Ruta del lunes'},
      provisional: 'local-r1',
    );
    await cola.resolver(
      clave,
      const ResultadoApunte(
        estado: EstadoResultado.rechazado,
        motivo: 'Ese pedido ya va en otra ruta',
      ),
    );
    expect(await huerfanos.mirar(), isEmpty);

    await cola.descartar(clave);

    // LO QUE NO PUEDE PASAR: que se reencole. Eso devuelve el rechazo.
    expect(
      await huerfanos.volverAEncolar(cola),
      0,
      reason:
          'se volvió a encolar algo que una persona acaba de descartar: el '
          'servidor repetirá su no y el rechazo estará de vuelta en la bandeja',
    );
    expect(await base.cuantosRechazados(), 0);
    expect(await base.cuantosPendientes(), 0);

    // Y LO QUE SÍ TIENE QUE PASAR: que se siga diciendo. Esa ruta está aquí, no
    // está arriba y ya no va a subir. Apagar el aviso al descartar sería cambiar
    // un error por un silencio, que es peor.
    expect(
      (await huerfanos.mirar()).map((h) => h.texto),
      ['1 ruta'],
      reason:
          'descartar apagó el aviso de «sólo en este aparato». La ruta sigue sin '
          'haber subido y ya no va a subir: callarlo es la pantalla verde sobre '
          'trabajo perdido que el §4 prohíbe',
    );

    // Y el aviso se cierra con SU gesto, que dice otra cosa: «ya no hace falta».
    expect(await huerfanos.darPorPerdido(Huerfanos.rutas), 1);
    expect(
      await huerfanos.mirar(),
      isEmpty,
      reason: 'darlo por perdido es la decisión, y tiene que quitar el aviso',
    );
  });

  // LA SEGUNDA LÍNEA DE DEFENSA, y hay que explicar por qué existe.
  //
  // Descartar hace DOS cosas: marca el apunte `descartado` y suelta la marca de
  // «nació aquí». En un día normal basta con la segunda — sin marca, la zona ya
  // no se cuenta como colgada— y por eso el estado del apunte parece no pintar
  // nada. Pero soltar la marca **puede fallar en silencio**: `_yaNoNacioAqui` va
  // dentro de un `try` que sólo apunta el fallo en el registro, a propósito,
  // porque un aparato que nunca abrió el Tablero no tiene esas tablas y eso no
  // puede tumbar la subida del día.
  //
  // El día que ese `try` se coma un fallo de verdad, la marca se queda puesta y
  // sin esta guarda vuelve el círculo entero: la zona se da por colgada, el
  // ciclo la encola, el servidor repite su no y el rechazo está de vuelta.
  //
  // Aquí se pone la marca a mano justo después de descartar, que es exactamente
  // el estado en el que quedaría ese aparato.
  test('si la marca se queda puesta, el estado del apunte todavía lo para', () async {
    final clave = await unaZonaRechazada(id: 'z-5');
    await cola.descartar(clave);
    await base.customStatement(
      'UPDATE board_columns SET nacio_aqui = 1 WHERE id = ?1',
      ['z-5'],
    );

    expect(
      await huerfanos.mirar(),
      isNotEmpty,
      reason: 'con la marca puesta la zona SÍ está colgada: eso es cierto',
    );
    expect(
      await huerfanos.volverAEncolar(cola),
      0,
      reason:
          'se volvió a encolar una zona que una persona había descartado. Sin '
          'esta guarda, el día que soltar la marca falle en silencio vuelve el '
          'círculo: se encola, el servidor repite su no, y el mismo rechazo '
          'está otra vez en la bandeja',
    );
    expect(await base.cuantosPendientes(), 0);
  });

  test('descartar uno no toca al de al lado', () async {
    final unoDeAntes = await unaZonaRechazada(id: 'z-3');
    final elOtro = await unaZonaRechazada(id: 'z-4');

    await cola.descartar(unoDeAntes);

    expect(
      await base.cuantosRechazados(),
      1,
      reason:
          'descartar uno se llevó por delante al otro. La bandeja es de varias '
          'personas y un turno no decide por el siguiente',
    );
    expect((await cola.porClave(elOtro))?.estado, EstadoApunte.rechazado);
    expect(
      await nacioAqui('z-4'),
      1,
      reason: 'se soltó la protección de una zona sobre la que nadie decidió',
    );
  });
}
