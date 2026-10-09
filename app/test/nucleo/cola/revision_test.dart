// LO ENTREGADO A REVISION: SUS ESTADOS Y TODO LO QUE DEPENDE DE ELLOS.
//
// `docs/bandeja-de-revision.md` (B.5, «Acoplamientos que NO se pueden olvidar»). Quien
// pierde `delivery.entrar` entrega su cola a un administrador, y el apunte local pasa a
// `enRevision`. Ese estado no es `pendiente` (no sube), no es `rechazado` (nadie lo
// tumbó) y no es `aplicado` (nadie lo ha aplicado): cada lugar de la aplicación que
// pregunta por estados tiene que saber qué hacer con él, y cada uno que se olvida ha
// costado un incidente —el bucle del 29/09/2026 fue exactamente uno—.
//
// Estas pruebas están en PAREJAS a propósito (§3-quinquies): lo que `enRevision` no
// cuenta y lo que sí cuenta. Sembrar la base DENTRO del cuerpo (§3-ter).

import 'package:drift/drift.dart' show Variable;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/arranque/arranque.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/base/personas.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/cola/provisionales.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late RelojFalso reloj;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 10, 8, 14, 32));
    cola = ColaDeSalida(base, reloj: reloj.leer);
  });

  tearDown(() => base.close());

  Future<String> encolar({
    String ruta = '/routes/r-1/results',
    String metodo = 'POST',
    Map<String, Object?> cuerpo = const {'a': 1},
    String? provisional,
  }) => cola.encolar(
    metodo: metodo,
    ruta: ruta,
    cuerpo: cuerpo,
    provisional: provisional,
  );

  /// Un apunte ya entregado, como lo deja la respuesta del servidor.
  Future<String> entregado({
    String ruta = '/routes/r-1/results',
    String metodo = 'POST',
    String? provisional,
    Map<String, Object?> cuerpo = const {'a': 1},
    String entrega = 'ent-1',
  }) async {
    final clave = await encolar(
      ruta: ruta,
      metodo: metodo,
      provisional: provisional,
      cuerpo: cuerpo,
    );
    expect(await cola.marcarEnRevision(clave, entrega: entrega), isTrue);
    return clave;
  }

  Future<void> zonaLocal(String id) => base.customStatement(
    'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
    'updated_at, nacio_aqui) '
    "VALUES (?1, 'hab-1', 'Vista', 1, '2026-10-08T10:00:00.000', "
    "'2026-10-08T10:00:00.000', 1)",
    [id],
  );

  Future<int> naciaAqui(String id) async => (await base
          .customSelect('SELECT nacio_aqui FROM board_columns WHERE id = ?1',
              variables: [Variable.withString(id)])
          .getSingle())
      .read<int>('nacio_aqui');

  group('entregar', () {
    test('un pendiente pasa a enRevision y NO se toca nada más del apunte', () async {
      final clave = await encolar(
        cuerpo: const {'resultados': <Object?>[]},
        provisional: 'local-x',
      );
      final antes = (await cola.porClave(clave))!;

      reloj.avanzar(const Duration(minutes: 3));
      expect(await cola.marcarEnRevision(clave, entrega: 'ent-7'), isTrue);

      final despues = (await cola.porClave(clave))!;
      expect(despues.estado, EstadoApunte.enRevision);
      expect(despues.revision, 'ent-7');
      expect(
        despues.resueltoAt,
        DateTime(2026, 10, 8, 14, 35),
        reason: 'cuándo se entregó: «Entregado a revisión el 8/10, 14:35»',
      );
      // El original TAL CUAL: la huella del servidor es la de estos bytes, y
      // reescribirlos daría `409 huella_distinta` en una reentrega.
      expect(despues.cuerpo, antes.cuerpo);
      expect(despues.ruta, antes.ruta);
      expect(despues.metodo, antes.metodo);
      expect(despues.hechoAt, antes.hechoAt);
      expect(despues.provisional, 'local-x');
      expect(despues.motivo, isNull, reason: '`motivo` no es de la revisión');
      expect(despues.motivoRevision, isNull);
    });

    test('sólo se entrega un pendiente: rechazado, descartado y aplicado no', () async {
      final rechazado = await encolar();
      await cola.resolver(
        rechazado,
        const ResultadoApunte(estado: EstadoResultado.rechazado, motivo: 'no'),
      );
      final descartado = await encolar();
      await cola.resolver(
        descartado,
        const ResultadoApunte(estado: EstadoResultado.rechazado, motivo: 'no'),
      );
      await cola.descartar(descartado);
      final aplicado = await encolar();
      await cola.resolver(
        aplicado,
        const ResultadoApunte(estado: EstadoResultado.aplicado),
      );

      for (final clave in [rechazado, descartado, aplicado]) {
        expect(await cola.marcarEnRevision(clave), isFalse);
      }
      expect((await cola.porClave(rechazado))!.estado, EstadoApunte.rechazado);
      expect((await cola.porClave(descartado))!.estado, EstadoApunte.descartado);
      expect((await cola.porClave(aplicado))!.estado, EstadoApunte.aplicado);
    });
  });

  group('lo que enRevision NO cuenta', () {
    test('no sale en el lote de la subida, ni en pendientes, ni en «N sin subir»', () async {
      final sube = await encolar(ruta: '/routes/r-2');
      await entregado();

      expect(
        (await cola.lote()).map((a) => a.clave),
        [sube],
        reason:
            'lo entregado ya está arriba: subirlo por la vía normal, el día que '
            'recupere el permiso, lo aplicaría por encima de la decisión del revisor',
      );
      expect((await cola.pendientes().first).map((a) => a.clave), [sube]);
      expect(await base.cuantosPendientes(), 1);
      expect(
        await base.cuantosSinSubir(),
        1,
        reason: 'ya está arriba: «N sin subir» no lo cuenta',
      );
      expect(await base.cuantosRechazados(), 0);
      expect(await cola.cuantosQuedanTras(1), 0);
    });

    test('la pareja: SÍ lo cuenta cuantosEnRevision, y es lo único que lo cuenta', () async {
      expect(await base.cuantosEnRevision(), 0);
      await entregado();
      await entregado();
      await encolar(ruta: '/routes/r-3');
      expect(await base.cuantosEnRevision(), 2);
      expect((await cola.enRevision().first).length, 2);
    });

    test('la persona NO puede descartarlo ni reintentarlo: decide el revisor', () async {
      final clave = await entregado();

      await cola.descartar(clave);
      await cola.reintentar(clave);

      final apunte = (await cola.porClave(clave))!;
      expect(
        apunte.estado,
        EstadoApunte.enRevision,
        reason:
            'descartar aquí sería una decisión de la persona que el revisor no ve; '
            'reintentar lo devolvería a la cola para subir por encima de él',
      );
    });

    test('la poda no se lleva lo entregado ni lo descartado por el revisor', () async {
      final pasa = await entregado();
      final descartado = await entregado(ruta: '/routes/r-9/results');
      await cola.resolverRevision(
        descartado,
        const DecisionDeRevision(
          estado: EstadoEnRevision.descartado,
          por: 'Marta Pérez',
          motivo: 'Esa ruta se rehízo en la web',
        ),
      );
      reloj.avanzar(const Duration(days: 40));

      await cola.podar();

      expect((await cola.porClave(pasa))!.estado, EstadoApunte.enRevision);
      expect((await cola.porClave(descartado))!.estado, EstadoApunte.descartadoPorRevisor);
    });
  });

  group('nacio_aqui', () {
    setUp(() => EsquemaTablero.asegurar(base));

    test('enRevision CONSERVA la protección: el trabajo sólo existe aquí', () async {
      await zonaLocal('z-1');
      await entregado(ruta: '/board/columns?branchId=hab-1', provisional: 'z-1');

      expect(
        await naciaAqui('z-1'),
        1,
        reason: 'soltarla deja que la bajada borre de su pantalla lo que aún no está aplicado',
      );
    });

    test('un rechazo del reparto al aplicar tampoco la suelta', () async {
      await zonaLocal('z-1');
      final clave = await entregado(
        ruta: '/board/columns?branchId=hab-1',
        provisional: 'z-1',
      );
      await cola.resolverRevision(
        clave,
        const DecisionDeRevision(
          estado: EstadoEnRevision.rechazado,
          motivo: 'Ya existe una zona con ese nombre',
        ),
      );
      expect(await naciaAqui('z-1'), 1);
    });

    test('aplicado por el revisor la SUELTA: ya está arriba', () async {
      await zonaLocal('z-1');
      final clave = await entregado(
        ruta: '/board/columns?branchId=hab-1',
        provisional: 'z-1',
      );
      await cola.resolverRevision(
        clave,
        const DecisionDeRevision(
          estado: EstadoEnRevision.aplicado,
          por: 'Marta Pérez',
          idCreado: 'col-de-verdad',
        ),
      );
      expect(
        await naciaAqui('col-de-verdad'),
        0,
        reason: 'si queda a 1 la bajada no la toca nunca más: tablero congelado',
      );
    });

    test('descartado por el revisor la SUELTA: no va a subir nunca', () async {
      await zonaLocal('z-1');
      final clave = await entregado(
        ruta: '/board/columns?branchId=hab-1',
        provisional: 'z-1',
      );
      await cola.resolverRevision(
        clave,
        const DecisionDeRevision(
          estado: EstadoEnRevision.descartado,
          por: 'Marta Pérez',
          motivo: 'Esa zona ya existe',
        ),
      );
      expect(await naciaAqui('z-1'), 0);
    });
  });

  group('lo que dice el servidor después', () {
    test('aplicado: quién y cuándo, y NO escribe en `motivo`', () async {
      final clave = await entregado();
      final cuando = DateTime.utc(2026, 10, 9, 9, 10);

      await cola.resolverRevision(
        clave,
        DecisionDeRevision(
          estado: EstadoEnRevision.aplicado,
          por: 'Marta Pérez',
          cuando: cuando,
        ),
      );

      final a = (await cola.porClave(clave))!;
      expect(a.estado, EstadoApunte.aplicado);
      expect(a.revisadoPor, 'Marta Pérez');
      expect(a.revisadoAt, cuando);
      expect(a.motivoRevision, isNull);
      expect(
        a.motivo,
        isNull,
        reason:
            'en un aplicado `motivo` es «salió con menos de lo que pusiste»: '
            'escribir ahí «Aplicado por…» llenaría ese aviso',
      );
      expect(
        await cola.descartesSinLeer().first,
        isEmpty,
        reason: 'un aplicado por el revisor no es un aviso de descartes sin leer',
      );
      expect((await cola.decididosPorRevision().first).single.clave, clave);
      expect(await cola.enRevision().first, isEmpty);
      expect(await base.cuantosEnRevision(), 0);
    });

    test('aplicado: el local-… pasa a ser el id de verdad en las FILAS, pero NO en lo que espera', () async {
      await base
          .into(base.routes)
          .insert(RoutesCompanion.insert(id: 'local-ruta'));
      final crea = await entregado(
        ruta: '/routes',
        metodo: 'POST',
        provisional: 'local-ruta',
        cuerpo: const {'nombre': 'Ruta de hoy'},
      );
      final detras = await encolar(
        ruta: '/routes/local-ruta',
        metodo: 'PATCH',
        cuerpo: const {'status': 'in_progress'},
      );
      final antes = (await cola.porClave(detras))!;

      await cola.resolverRevision(
        crea,
        const DecisionDeRevision(
          estado: EstadoEnRevision.aplicado,
          por: 'Marta Pérez',
          idCreado: 'ruta-de-verdad',
        ),
      );

      expect((await base.select(base.routes).get()).single.id, 'ruta-de-verdad');
      expect((await base.select(base.equivalencias).get()).single.provisional, 'local-ruta');
      final despues = (await cola.porClave(detras))!;
      expect(
        (despues.ruta, despues.cuerpo),
        (antes.ruta, antes.cuerpo),
        reason:
            'el revisor traduce el `local-…` en `sync`: si el aparato reescribe lo que '
            'espera, al entregarlo el servidor ve OTRO contenido con la misma clave '
            '(409 huella_distinta) y queda pendiente para siempre',
      );
    });

    test('descartado: queda ESCRITO con quién, cuándo y el motivo; no se borra', () async {
      final clave = await entregado(cuerpo: const {'x': 'original'});
      final cuando = DateTime.utc(2026, 10, 9, 9, 12);
      final antes = (await cola.porClave(clave))!;

      await cola.resolverRevision(
        clave,
        DecisionDeRevision(
          estado: EstadoEnRevision.descartado,
          por: 'Marta Pérez',
          cuando: cuando,
          motivo: 'Esa ruta se rehízo en la web',
        ),
      );

      final a = (await cola.porClave(clave))!;
      expect(a.estado, EstadoApunte.descartadoPorRevisor);
      expect(a.revisadoPor, 'Marta Pérez');
      expect(a.revisadoAt, cuando);
      expect(a.motivoRevision, 'Esa ruta se rehízo en la web');
      expect(a.cuerpo, antes.cuerpo, reason: 'el original se queda: es la constancia');
      expect((await base.select(base.apuntes).get()).length, 1, reason: 'nada se borra');
      expect(
        (await cola.decididosPorRevision().first).single.motivoRevision,
        'Esa ruta se rehízo en la web',
      );
    });

    test('rechazado por el reparto: SIGUE en revisión, con el literal', () async {
      final clave = await entregado();

      await cola.resolverRevision(
        clave,
        const DecisionDeRevision(
          estado: EstadoEnRevision.rechazado,
          por: 'Marta Pérez',
          motivo: 'Ese pedido ya va en otra ruta',
        ),
      );

      var a = (await cola.porClave(clave))!;
      expect(
        a.estado,
        EstadoApunte.enRevision,
        reason:
            'como `rechazado` local ofrecería «Reintentar»/«Descartar» de la '
            'persona sobre algo que el revisor aún puede aplicar',
      );
      expect(a.motivoRevision, 'Ese pedido ya va en otra ruta');
      expect(await base.cuantosRechazados(), 0);
      expect(await base.cuantosSinSubir(), 0);

      // Y si vuelve a `en_revision` (el revisor reintenta y cae), se limpia.
      await cola.resolverRevision(
        clave,
        const DecisionDeRevision(estado: EstadoEnRevision.enRevision),
      );
      a = (await cola.porClave(clave))!;
      expect(a.estado, EstadoApunte.enRevision);
      expect(a.motivoRevision, isNull);
    });

    test('sin motivo del servidor no se deja el campo vacío', () async {
      final clave = await entregado();
      await cola.resolverRevision(
        clave,
        const DecisionDeRevision(estado: EstadoEnRevision.rechazado),
      );
      expect((await cola.porClave(clave))!.motivoRevision, textoSinMotivoDeRevision);
    });

    test('aplicando y en_revision no mueven nada; lo ya decidido no se reescribe', () async {
      final clave = await entregado();
      await cola.resolverRevision(
        clave,
        const DecisionDeRevision(estado: EstadoEnRevision.aplicando, por: 'Otra'),
      );
      var a = (await cola.porClave(clave))!;
      expect(a.estado, EstadoApunte.enRevision);
      expect(a.revisadoPor, isNull);

      await cola.resolverRevision(
        clave,
        const DecisionDeRevision(estado: EstadoEnRevision.aplicado, por: 'Marta Pérez'),
      );
      // Una respuesta tardía de otra vuelta no cambia lo que ya se leyó.
      await cola.resolverRevision(
        clave,
        const DecisionDeRevision(
          estado: EstadoEnRevision.descartado,
          por: 'Pedro',
          motivo: 'tarde',
        ),
      );
      a = (await cola.porClave(clave))!;
      expect(a.estado, EstadoApunte.aplicado);
      expect(a.revisadoPor, 'Marta Pérez');
      expect(a.motivoRevision, isNull);
    });

    test('un apunte que no es enRevision no lo mueve ninguna decisión', () async {
      final clave = await encolar();
      await cola.resolverRevision(
        clave,
        const DecisionDeRevision(estado: EstadoEnRevision.aplicado, por: 'Marta'),
      );
      expect((await cola.porClave(clave))!.estado, EstadoApunte.pendiente);
      expect((await cola.lote()).map((a) => a.clave), [clave]);
    });
  });

  group('lo entregado no se reescribe', () {
    test('la sustitución de un local-… NO toca el cuerpo de lo entregado', () async {
      // El revisor traduce los `local-…` con su propio traductor al aplicar. Si el
      // aparato reescribe el cuerpo de lo entregado, el servidor ve otra huella.
      final entregadoAntes = await entregado(
        ruta: '/routes/local-ruta',
        metodo: 'PATCH',
        cuerpo: const {'rutaId': 'local-ruta'},
      );
      final pendiente = await encolar(
        ruta: '/routes/local-ruta',
        metodo: 'PATCH',
        cuerpo: const {'rutaId': 'local-ruta'},
      );
      final original = (await cola.porClave(entregadoAntes))!;

      await Provisionales(base).sustituir('local-ruta', 'ruta-real');

      final tras = (await cola.porClave(entregadoAntes))!;
      expect(tras.cuerpo, original.cuerpo);
      expect(tras.ruta, original.ruta);
      expect(
        (await cola.porClave(pendiente))!.cuerpo,
        contains('ruta-real'),
        reason: 'la pareja: lo que sí espera en la cola se sigue sustituyendo',
      );
    });
  });

  group('el servidor contesta en_revision a la subida normal', () {
    // Pasa si la entrega salió, la respuesta se perdió, y después la persona
    // recuperó el permiso: el apunte sigue `pendiente` aquí y la subida normal lo
    // manda. Antes: `FormatException` en cada ciclo, o `rechazado` con «Reintentar».
    test('ResultadoApunte lo entiende y NO es un aplicado', () {
      final r = ResultadoApunte.deJson(const {
        'clave': 'k',
        'estado': 'en_revision',
        'revision': 'ent-3',
      });
      expect(r.estado, EstadoResultado.enRevision);
      expect(r.revision, 'ent-3');
      expect(r.seAplico, isFalse);
      expect(
        () => ResultadoApunte.deJson(const {'estado': 'inventado'}),
        throwsFormatException,
        reason: 'un estado desconocido sigue siendo un error, no un silencio',
      );
    });

    test('resolver lo deja enRevision, no rechazado', () async {
      final clave = await encolar();

      await cola.resolver(
        clave,
        const ResultadoApunte(
          estado: EstadoResultado.enRevision,
          revision: 'ent-3',
        ),
      );

      final a = (await cola.porClave(clave))!;
      expect(a.estado, EstadoApunte.enRevision);
      expect(a.revision, 'ent-3');
      expect(await base.cuantosRechazados(), 0);
    });
  });

  group('DecisionDeRevision.deJson', () {
    test('lee una entrada de `mias`', () {
      final d = DecisionDeRevision.deJson(const {
        'clave': 'k',
        'estado': 'descartado',
        'decididoPorNombre': 'Marta Pérez',
        'decididoAt': '2026-10-09T13:10:00Z',
        'motivo': 'Se rehízo en la web',
        'idCreado': null,
      });
      expect(d.estado, EstadoEnRevision.descartado);
      expect(d.por, 'Marta Pérez');
      expect(d.cuando!.toUtc(), DateTime.utc(2026, 10, 9, 13, 10));
      expect(d.motivo, 'Se rehízo en la web');
      expect(d.idCreado, isNull);
    });

    test('un estado que no conoce lanza, para atraparlo POR APUNTE', () {
      expect(
        () => DecisionDeRevision.deJson(const {'estado': 'inventado'}),
        throwsFormatException,
      );
    });
  });

  group('antes de olvidar a una persona', () {
    test('lo entregado a revisión cuenta y se NOMBRA', () async {
      await entregado();
      await entregado(ruta: '/routes/r-2/results');

      final persona = PersonaEnElAparato(
        sub: 'u1',
        nombre: 'Yasmani',
        pendientes: await base.cuantosPendientes(),
        rechazados: await base.cuantosRechazados(),
        enRevision: await base.cuantosEnRevision(),
      );

      expect(persona.tieneTrabajoSinSubir, isTrue);
      expect(
        persona.queSePierde,
        '2 entregados a revisión que nadie ha decidido',
        reason: 'olvidar la copia se llevaría lo único que dice qué entregó',
      );
    });

    test('PersonaEnElAparato.deLaBase cuenta lo entregado (lo que usan listar y olvidar)', () async {
      await entregado();

      final persona = await PersonaEnElAparato.deLaBase(base, sub: 'u1', nombre: 'Yasmani');

      expect(persona.enRevision, 1);
      expect(persona.pendientes, 0);
      expect(persona.tieneTrabajoSinSubir, isTrue);
    });

    test('la pareja: sin nada en revisión no se dice nada', () async {
      const persona = PersonaEnElAparato(sub: 'u1', nombre: 'Yasmani', pendientes: 0);
      expect(persona.tieneTrabajoSinSubir, isFalse);
      expect(persona.queSePierde, isEmpty);
    });
  });

  group('al arrancar sin sesión', () {
    // `_elAparatoTieneDatos`: «sesión perdida» frente a «aún no ha entrado nadie». Una
    // persona que entregó su cola, cerró sesión y vuelve, tiene datos aunque nada esté
    // `pendiente` ni `rechazado`.
    Future<ResultadoDelArranque> arrancarSinSesion() async {
      final c = ProviderContainer.test(
        overrides: [
          almacenSesionProvider.overrideWithValue(AlmacenEnMemoria(null)),
          baseProvider.overrideWithValue(base),
        ],
      );
      addTearDown(c.dispose);
      return arrancar(c.read(_ref));
    }

    test('con trabajo en revisión, es una sesión PERDIDA', () async {
      await entregado();

      final resultado = await arrancarSinSesion();

      expect(resultado.como, Arranque.fuera);
      expect(
        resultado.sesionPerdida,
        isTrue,
        reason: 'hay un aparato con el trabajo de alguien entregado, no uno vacío',
      );
    });

    test('la pareja: una base vacía no es una sesión perdida', () async {
      final resultado = await arrancarSinSesion();

      expect(resultado.como, Arranque.fuera);
      expect(resultado.sesionPerdida, isFalse);
    });
  });

  group('el cierre de una ruta espera a sus resultados entregados', () {
    // `Subida._cierreSinAceptar`: una hoja pendiente o rechazada retiene el
    // `completed` de su ruta. Una hoja ENTREGADA también: completar la ruta la
    // congela como histórico, y el revisor aplicaría después unos resultados sobre
    // una ruta que ya no admite cambios.
    ({Subida subida, ServidorFalso servidor}) montar() {
      final servidor = ServidorFalso((p) async {
        final a = ((p.cuerpo! as Map<String, Object?>)['apuntes']! as List<Object?>)
            .single as Map<String, Object?>;
        return RespuestaFalsa(200, {
          'resultados': [
            {'clave': a['clave'], 'estado': 'aplicado'},
          ],
        });
      });
      final almacen = AlmacenEnMemoria(
        const Sesion(token: 't', refresh: 'r0', sub: 'u1'),
      );
      final cliente = ClienteApi.montar(
        baseUrl: 'https://sync.test',
        almacen: almacen,
        renovador: Renovador(Dio()..httpClientAdapter = servidor, almacen),
        esperar: (_) async {},
      );
      cliente.dio.httpClientAdapter = servidor;
      return (
        subida: Subida(
          cliente: cliente,
          cola: cola,
          aparato: IdentidadDelAparato(base),
          base: base,
          quienEsta: () async => (await almacen.leer())?.sub,
        ),
        servidor: servidor,
      );
    }

    test('con la hoja entregada, el completed NO sube; sin ella, sí', () async {
      await aparatoYaDeAlta(base);
      final hoja = await encolar(
        ruta: '/routes/r1/results',
        cuerpo: const {'resultados': <Object?>[]},
      );
      final completa = await encolar(
        ruta: '/routes/r1',
        metodo: 'PATCH',
        cuerpo: const {'status': 'completed'},
      );
      await cola.marcarEnRevision(hoja, entrega: 'ent-1');

      final m = montar();
      expect(await m.subida.ciclo(), 0);
      expect(
        m.servidor.vistas,
        isEmpty,
        reason: 'completar una ruta con sus resultados sin aplicar la congela mal',
      );
      expect((await cola.porClave(completa))!.estado, EstadoApunte.pendiente);

      // La pareja: el revisor la descarta y la ruta ya se puede completar.
      await cola.resolverRevision(
        hoja,
        const DecisionDeRevision(
          estado: EstadoEnRevision.descartado,
          por: 'Marta',
          motivo: 'La rehice',
        ),
      );
      expect(await m.subida.ciclo(), 1);
      expect((await cola.porClave(completa))!.estado, EstadoApunte.aplicado);
    });
  });

  test('el enum entero está clasificado en la tabla de este fichero', () {
    // Si alguien añade un estado, esta lista falla y obliga a decidir aquí qué hace
    // con él cada una de las preguntas de arriba.
    expect(
      EstadoApunte.values.map((e) => e.name),
      [
        'pendiente',
        'aplicado',
        'rechazado',
        'descartado',
        'enRevision',
        'descartadoPorRevisor',
      ],
    );
  });
}

final _ref = Provider<Ref>((ref) => ref);
