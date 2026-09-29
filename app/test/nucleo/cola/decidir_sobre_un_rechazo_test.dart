import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';

import '../../apoyo/base_de_prueba.dart';

/// LAS DOS DECISIONES SOBRE UN RECHAZO: descartarlo o reintentarlo.
///
/// El pliego dice que un apunte rechazado «se queda a la vista con su motivo
/// **hasta que una persona decida**», y hasta hoy faltaba justo eso: la
/// decisión. No había forma de quitarlos ni de volver a intentarlos, así que se
/// quedaban en la pantalla para siempre. Jose, 16/09/2026: «no puedo borrar esas
/// notificaciones».
///
/// Con diez repartidores y varios turnos por aparato, una bandeja que sólo crece
/// deja de leerse a la tercera semana — y entonces el rechazo que SÍ importaba
/// se pierde entre los viejos.
void main() {
  late BaseLocal base;
  late ColaDeSalida cola;

  setUp(() {
    base = baseDePrueba();
    cola = ColaDeSalida(base);
  });

  tearDown(() => base.close());

  Future<String> unRechazado() async {
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/board/columns',
      cuerpo: const <String, Object?>{'nombre': 'Vista'},
    );
    await cola.resolver(
      clave,
      const ResultadoApunte(
        estado: EstadoResultado.rechazado,
        motivo: 'El servidor dijo que no',
      ),
    );
    return clave;
  }

  // ESTA PRUEBA DECÍA `isNull` HASTA EL 29/09/2026, y por eso hay que contar por
  // qué cambió: no se relajó, se corrigió. Descartar borraba la fila, y con la
  // fila borrada nada quedaba que dijera que una persona ya había decidido. Lo
  // huérfano volvía a encolar el trabajo, el servidor repetía su no, y el mismo
  // rechazo estaba de vuelta en la bandeja minutos después. Jose sólo veía el
  // final: «los errores se acumulan y nunca se borran».
  //
  // El círculo entero se ata en `descartar_no_lo_devuelve_test.dart`. Aquí se
  // guarda su mitad: la decisión queda ESCRITA.
  test('descartar lo saca de la bandeja y deja la decisión escrita', () async {
    final clave = await unRechazado();
    expect((await cola.porClave(clave))?.estado, EstadoApunte.rechazado);

    await cola.descartar(clave);

    final tras = await cola.porClave(clave);
    expect(
      tras,
      isNotNull,
      reason:
          'el apunte se borró. Sin él no queda nada que diga que alguien ya '
          'decidió, y lo huérfano lo vuelve a encolar: es el círculo del '
          '29/09/2026',
    );
    expect(
      tras?.estado,
      EstadoApunte.descartado,
      reason: 'descartar es la decisión de «esto ya no aplica»',
    );
    expect(
      tras?.motivo,
      isNotNull,
      reason:
          'el motivo se perdió al descartar. Es lo único que explica el lunes '
          'por qué ese cierre no llegó, y quien pregunta no es quien descartó',
    );
    // Y lo que de verdad pedía Jose: que se vaya de donde lo está mirando.
    expect(
      await base.cuantosRechazados(),
      0,
      reason: 'sigue contando en la bandeja después de descartarlo',
    );
    expect(
      await base.cuantosSinSubir(),
      0,
      reason:
          'un descartado no es trabajo pendiente: contarlo ahí deja la franja '
          'en ámbar para siempre por algo que ya se decidió',
    );
  });

  test('reintentar lo devuelve a la cola, limpio', () async {
    final clave = await unRechazado();

    await cola.reintentar(clave);

    final vuelto = await cola.porClave(clave);
    expect(vuelto?.estado, EstadoApunte.pendiente);
    expect(
      vuelto?.motivo,
      isNull,
      reason: 'el motivo viejo no puede quedarse pegado: ya no es cierto',
    );
    expect(
      vuelto?.intentos,
      0,
      reason: 'vuelve a empezar: si no, se rendiría antes de tiempo',
    );
    // Y sale en el próximo envío, que es de lo que se trata.
    expect((await cola.lote()).map((a) => a.clave), contains(clave));
  });

  test('ninguna de las dos toca lo que NO está rechazado', () async {
    // Un apunte pendiente no se descarta ni se «reintenta» por error: sería
    // tirar trabajo que todavía iba a subir solo.
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/board/columns',
      cuerpo: const <String, Object?>{'nombre': 'Otra'},
    );

    await cola.descartar(clave);
    expect(
      (await cola.porClave(clave))?.estado,
      EstadoApunte.pendiente,
      reason: 'descartar sólo vale sobre un rechazado',
    );

    await cola.reintentar(clave);
    expect((await cola.porClave(clave))?.estado, EstadoApunte.pendiente);
  });
}
