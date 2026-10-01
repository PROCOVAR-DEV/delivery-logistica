import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/pantallas/entregar_el_dia/datos/textos.dart';
import 'package:reparto/pantallas/entregar_el_dia/estado/entregar_el_dia.dart';
import 'package:reparto/pantallas/traer_el_dia/estado/traer_el_dia.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';
import '../traer_el_dia/apoyo_traer_el_dia.dart';

/// EL GESTO: «entrego el día que trabajé».
///
/// El espejo del otro, y con la misma regla dura: **no se queda verde si algo no
/// subio**, y los numeros salen de la cola y no de lo que el servidor dijo que
/// acepto.
void main() {
  late BaseLocal base;
  late RelojFalso reloj;
  late ColaDeSalida cola;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 15, 17, 40));
    cola = ColaDeSalida(base, reloj: reloj.leer);
  });

  tearDown(() => base.close());

  ProviderContainer montar(
    Future<RespuestaFalsa?> Function(PeticionVista) responder, {
    bool haySesion = true,
    bool hayPista = true,
  }) {
    final caja = montarTraerElDia(
      base: base,
      reloj: reloj.leer,
      responder: responder,
      haySesion: haySesion,
      hayPista: hayPista,
    );
    addTearDown(caja.dispose);
    return caja;
  }

  Future<void> encolar(int cuantos) async {
    for (var i = 1; i <= cuantos; i++) {
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/r-$i/results',
        cuerpo: <String, Object?>{'resultado': 'entregado'},
      );
    }
  }

  /// Un servidor que acepta lo que le llegue, menos las claves de [rechazar].
  Future<RespuestaFalsa?> Function(PeticionVista) servidorQueAcepta({
    Set<String> rechazarRutas = const <String>{},
  }) {
    return (p) async {
      if (!p.ruta.endsWith('/subida')) return servidorQueTraeElDia(p);
      final cuerpo = p.cuerpo! as Map<String, Object?>;
      final apuntes = cuerpo['apuntes']! as List<Object?>;
      return RespuestaFalsa(200, <String, Object?>{
        'resultados': [
          for (final a in apuntes.cast<Map<String, Object?>>())
            if (rechazarRutas.contains(a['ruta']))
              <String, Object?>{
                'clave': a['clave'],
                'estado': 'rechazado',
                'motivo':
                    '3 de los 8 pedidos ya están en otra ruta. Vuelve a '
                    'elegirlos.',
              }
            else
              <String, Object?>{'clave': a['clave'], 'estado': 'aplicado'},
        ],
      });
    };
  }

  group('se le da al boton', () {
    test('sube el dia y al acabar dice CUANTOS, no «listo»', () async {
      await encolar(23);
      final caja = montar(servidorQueAcepta());

      final entrego = await caja.read(entregarElDiaProvider.notifier).ahora();

      expect(entrego.completo, isTrue, reason: '$entrego');
      expect(entrego.subidos, 23);
      expect(entrego.quedan, 0);
      expect(TextosDeEntregarElDia.subieron(23), 'Subieron 23 apuntes');
      expect(TextosDeEntregarElDia.comoQuedo(entrego), 'Todo entregado');
      expect(await base.cuantosPendientes(), 0);
    });

    test('se ve cuanto hay sin subir SIN dar a nada', () async {
      await encolar(23);

      // El numero sale del mismo sitio que la franja de estado, y esta ahi antes
      // de tocar el boton: es lo que se mira de reojo cien veces al dia.
      //
      // Se lee de la BASE y no con `await sinSubirProvider.future`: eso es
      // esperar el primer valor de un stream de Drift, y en este proyecto eso ya
      // colgo una prueba en vez de fallarla. El provider es un `map` sobre
      // exactamente esta consulta.
      final pendientes = await base.cuantosPendientes();

      expect(pendientes, 23);
      expect(
        TextosDeEntregarElDia.cuantoQueda(pendientes),
        '23 apuntes sin subir',
      );
      expect(
        TextosDeEntregarElDia.cuantoQueda(0),
        'Todo entregado',
        reason: 'con cero, el boton no invita a nada',
      );
      expect(TextosDeEntregarElDia.cuantoQueda(1), '1 apunte sin subir');
    });

    test('mientras corre dice por donde va', () async {
      await encolar(2);
      final caja = montar(servidorQueAcepta());

      final visto = <String>[];
      caja.listen(marchaDelCicloProvider, (_, marcha) {
        if (marcha.enVuelo) {
          visto.add(TextosDeEntregarElDia.porDondeVa(marcha.avance));
        }
      }, fireImmediately: true);

      await caja.read(entregarElDiaProvider.notifier).ahora();

      expect(visto, contains('Subiendo lo que hiciste...'));
      expect(
        visto,
        contains('Subido. Ahora trayendo lo nuevo...'),
        reason:
            'subir y bajar van en el mismo ciclo; callar la segunda mitad '
            'haria parecer que se colgo justo despues de subir',
      );
    });
  });

  group('LO QUE MAS IMPORTA: si falla, la cola queda ENTERA', () {
    test('se cae la subida: no sube ninguno y NO queda verde', () async {
      await encolar(23);
      final caja = montar((p) async {
        if (p.ruta.endsWith('/subida')) return null; // ni sale el paquete
        return servidorQueTraeElDia(p);
      });

      final entrego = await caja.read(entregarElDiaProvider.notifier).ahora();

      expect(entrego.fallo, isA<FalloDeRed>());
      expect(entrego.subidos, 0);
      expect(
        entrego.quedan,
        23,
        reason: 'NADA se da por subido: los 23 siguen en el telefono',
      );
      expect(entrego.completo, isFalse);
      expect(
        TextosDeEntregarElDia.comoQuedo(entrego),
        'Quedan 23 sin subir',
        reason:
            'y se dice CUANTOS quedan, que es lo unico que le dice a '
            'alguien si se puede ir a su casa',
      );
      expect(
        await base.cuantosPendientes(),
        23,
        reason: 'la cola, intacta en la base',
      );
    });

    test(
      'el servidor rechaza uno: NO queda verde y el rechazo NO se borra',
      () async {
        await encolar(3);
        final caja = montar(
          servidorQueAcepta(rechazarRutas: {'/api/routes/r-2/results'}),
        );

        final entrego = await caja.read(entregarElDiaProvider.notifier).ahora();

        expect(entrego.quedan, 0, reason: 'los tres se resolvieron');
        expect(entrego.rechazados, 1);
        expect(
          entrego.completo,
          isFalse,
          reason:
              'un apunte rechazado NO subio: sigue ahi esperando a que una '
              'persona decida, y mientras espera el dia no esta entregado',
        );
        expect(
          TextosDeEntregarElDia.comoQuedo(entrego),
          '1 rechazado esperando a que alguien decida',
        );

        // Y sigue en la cola, con su motivo LITERAL. Se lee de la base por lo
        // mismo: nada de esperar el primer valor de un stream de Drift.
        final enLaBandeja = await (base.select(
          base.apuntes,
        )..where((a) => a.estado.equalsValue(EstadoApunte.rechazado))).get();
        expect(enLaBandeja, hasLength(1));
        expect(enLaBandeja.single.ruta, '/api/routes/r-2/results');
        expect(
          enLaBandeja.single.motivo,
          contains('ya están en otra ruta'),
          reason:
              'el motivo del servidor se guarda tal cual: es lo unico que le '
              'dice a alguien que hacer',
        );
      },
    );

    test('una subida a medias deja lo que no subio, y lo dice', () async {
      await encolar(5);
      // SE CORTA A LA MITAD, Y DESDE EL 01/10/2026 ESO TIENE OTRA FORMA.
      //
      // Antes la cola entera iba en UNA peticion y «a medias» era un servidor
      // que contestaba por dos de los cinco apuntes de dentro. Ahora cada apunte
      // es su propia peticion, asi que a medias es lo que de verdad pasa en la
      // calle: las dos primeras llegan y contestan, y en la tercera se va la
      // antena. **Lo que esta prueba vigila no cambia** —que lo que no subio se
      // quede y se diga— y encima ahora los dos primeros estan ARRIBA, que es
      // justo lo que se vino a ganar.
      var contestadas = 0;
      final caja = montar((p) async {
        if (!p.ruta.endsWith('/subida')) return servidorQueTraeElDia(p);
        if (contestadas >= 2) return null;
        contestadas++;
        final cuerpo = p.cuerpo! as Map<String, Object?>;
        final apuntes = (cuerpo['apuntes']! as List<Object?>)
            .cast<Map<String, Object?>>();
        return RespuestaFalsa(200, <String, Object?>{
          'resultados': [
            for (final a in apuntes)
              <String, Object?>{'clave': a['clave'], 'estado': 'aplicado'},
          ],
        });
      });

      final entrego = await caja.read(entregarElDiaProvider.notifier).ahora();

      expect(
        entrego.subidos,
        2,
        reason:
            'los DOS que subieron antes del corte. Un cero aqui, con el «quedan '
            '3» de al lado sacado de la base, serian las dos mitades del mismo '
            'cartel contradiciendose',
      );
      expect(entrego.quedan, 3);
      expect(entrego.completo, isFalse);
      expect(TextosDeEntregarElDia.comoQuedo(entrego), 'Quedan 3 sin subir');
    });
  });

  group('sin sesion y sin senal', () {
    test('sin sesion no se intenta nada y la cola no se toca', () async {
      await encolar(4);
      final rutas = <String>[];
      final caja = montar((p) async {
        rutas.add(p.ruta);
        return servidorQueTraeElDia(p);
      }, haySesion: false);

      final entrego = await caja.read(entregarElDiaProvider.notifier).ahora();

      expect(rutas, isEmpty);
      expect(entrego.sinSesion, isTrue);
      expect(entrego.completo, isFalse);
      expect(entrego.quedan, 4);
      expect(
        TextosDeEntregarElDia.comoQuedo(entrego),
        'Hay que volver a entrar',
      );
    });

    test(
      'sin senal se dice ANTES, y se dice que el trabajo sigue aqui',
      () async {
        await encolar(7);
        final rutas = <String>[];
        final caja = montar((p) async {
          rutas.add(p.ruta);
          return servidorQueTraeElDia(p);
        }, hayPista: false);

        final entrego = await caja.read(entregarElDiaProvider.notifier).ahora();

        expect(rutas, isEmpty, reason: 'no se queda girando');
        expect(entrego.sinSenal, isTrue);
        expect(entrego.quedan, 7);
        expect(entrego.completo, isFalse);
        expect(TextosDeEntregarElDia.comoQuedo(entrego), 'No hay señal');
        expect(
          TextosDeEntregarElDia.sinSenalDetalle,
          contains('sigue guardado'),
          reason:
              'quien le da a esto lleva el dia dentro del telefono y lo '
              'primero que necesita saber es que no se ha ido',
        );
      },
    );
  });

  group('los dos botones a la vez', () {
    test('es UN SOLO ciclo, no dos', () async {
      await encolar(2);
      final rutas = <String>[];
      final caja = montar((p) async {
        rutas.add(p.ruta);
        return servidorQueAcepta()(p);
      });

      // Dar a los dos gestos a la vez es lo que pasa cuando alguien llega a la
      // oficina y quiere las dos cosas. El candado esta en `ciclo.dart` y es el
      // mismo para los dos.
      final entregar = caja.read(entregarElDiaProvider.notifier).ahora();
      final traer = caja.read(traerElDiaProvider.notifier).ahora();
      await Future.wait([entregar, traer]);

      expect(
        rutas.where((r) => r.endsWith('/subida')),
        hasLength(2),
        reason:
            'DOS apuntes, DOS peticiones (la cola sube de uno en uno desde el '
            '01/10/2026) — y ni una más: lo que esto vigila es que los dos '
            'botones no disparen DOS ciclos, que serían cuatro',
      );
      expect(rutas.where((r) => r.endsWith('/refresh')), hasLength(1));
      expect(rutas.where((r) => r.endsWith('/sync/cambios')), hasLength(1));
      expect(caja.read(cicloProvider).enVuelo, isFalse);
    });
  });
}
