import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../base/base.dart';
import '../registro/registro.dart';
import '../reloj.dart';
import 'apunte.dart';
import 'provisionales.dart';

/// Si el servidor no explica un descarte o un rechazo de la revision, no se deja
/// el campo vacio: un `motivoRevision` nulo en un `enRevision` es «todavia sin
/// intentar», y vacio no distingue «no pudo aplicarlo».
const textoSinMotivoDeRevision = 'El servidor no dio el motivo.';

/// LA COLA DE SALIDA. Es la pieza que hace verdad la regla 2: toda accion se
/// guarda en el aparato y se pinta como hecha; la subida va por detras.
///
/// No hay un «modo sin conexion» que se encienda. La aplicacion se comporta
/// igual siempre: quien tenga red todo el dia simplemente sube a medida que
/// trabaja.
class ColaDeSalida {
  ColaDeSalida(
    this._base, {
    Reloj reloj = relojDelAparato,
    Provisionales? provisionales,
  }) : _reloj = reloj,
       _provisionales = provisionales ?? Provisionales(_base, reloj: reloj);

  final BaseLocal _base;
  final Reloj _reloj;
  final Provisionales _provisionales;

  /// Cuanto se conserva un apunte ya aplicado. Borrarlo al momento deja sin
  /// rastro una subida que el usuario jura que hizo.
  static const conservarAplicados = Duration(days: 7);

  /// Guarda una accion. Devuelve la `clave` (ULID) con la que se la reconoce.
  ///
  /// La clave la pone el APARATO y no el servidor, y ahi esta la idempotencia:
  /// si la subida se corta despues de que el servidor guardara, el reintento
  /// llega con la misma clave y vuelve `repetido` en vez de duplicar la ruta.
  Future<String> encolar({
    required String metodo,
    required String ruta,
    required Map<String, Object?> cuerpo,
    String? provisional,
  }) async {
    final clave = Ulid().toString();
    await _base
        .into(_base.apuntes)
        .insert(
          ApuntesCompanion.insert(
            clave: clave,
            // La hora del APARATO, escrita AHORA. No se toca al subir.
            hechoAt: _reloj(),
            metodo: metodo,
            ruta: ruta,
            cuerpo: jsonEncode(cuerpo),
            provisional: Value(provisional),
          ),
        );
    return clave;
  }

  /// Lo que queda por subir, en el orden en que se hizo.
  ///
  /// `orden` y no `hechoAt`: marcar una parada y luego corregirla son dos
  /// apuntes sobre el mismo pedido, y subirlos al reves deja puesta la primera
  /// marca. Un reloj que se movio no puede provocar eso (caso S3).
  Stream<List<Apunte>> pendientes() =>
      (_base.select(_base.apuntes)
            ..where((a) => a.estado.equalsValue(EstadoApunte.pendiente))
            ..orderBy([(a) => OrderingTerm.asc(a.orden)]))
          .watch();

  /// LO QUE SUBIO BIEN Y AUN ASI DEJO GENTE FUERA, sin leer todavia.
  ///
  /// Son apuntes **aplicados** con motivo puesto: el servidor dijo que si y en
  /// la misma respuesta nombro a los que no entraron (ver [resolver]). No caben
  /// en [rechazados] —esos no subieron y se pueden reintentar— ni en el «N sin
  /// subir» —estos ya subieron—, y por eso son una tercera pregunta: **salio
  /// con menos de lo que pusiste**.
  ///
  /// Se ordena por `orden` descendente, el ultimo primero, igual que la
  /// bandeja: lo de hace cinco minutos es lo que todavia se puede arreglar.
  Stream<List<Apunte>> descartesSinLeer() =>
      (_base.select(_base.apuntes)
            ..where(
              (a) =>
                  a.estado.equalsValue(EstadoApunte.aplicado) &
                  a.motivo.isNotNull(),
            )
            ..orderBy([(a) => OrderingTerm.desc(a.orden)]))
          .watch();

  /// «Ya lo he leido». Quita el aviso y **no borra el apunte**.
  ///
  /// Es un gesto de persona, como el de la bandeja, y por la misma razon: una
  /// lista que solo crece deja de leerse a la tercera semana y entonces el
  /// aviso que SI importaba se pierde entre los viejos. Lo que se quita es el
  /// aviso; el apunte sigue en su sitio hasta que lo pode [podar], que es lo
  /// unico que explica manana por que esa ruta salio con nueve.
  Future<void> darPorLeidoElDescarte(String clave) async {
    final tocadas =
        await (_base.update(_base.apuntes)..where(
              (a) =>
                  a.clave.equals(clave) &
                  a.estado.equalsValue(EstadoApunte.aplicado),
            ))
            .write(const ApuntesCompanion(motivo: Value(null)));
    if (tocadas > 0) {
      Registro.aviso('aviso de descartados dado por leido a mano: $clave');
    }
  }

  /// La bandeja de rechazos. Nada se descarta en silencio (regla 6).
  Stream<List<Apunte>> rechazados() =>
      (_base.select(_base.apuntes)
            ..where((a) => a.estado.equalsValue(EstadoApunte.rechazado))
            ..orderBy([(a) => OrderingTerm.desc(a.orden)]))
          .watch();

  /// LO QUE ESTA ENTREGADO A REVISION y espera decision, el ultimo primero.
  ///
  /// Incluye el que el reparto no pudo aplicar (`motivoRevision` puesto): sigue
  /// en revision y el revisor aun puede decidir. Ver [EstadoApunte.enRevision].
  Stream<List<Apunte>> enRevision() =>
      (_base.select(_base.apuntes)
            ..where((a) => a.estado.equalsValue(EstadoApunte.enRevision))
            ..orderBy([(a) => OrderingTerm.desc(a.orden)]))
          .watch();

  /// LO QUE EL REVISOR YA DECIDIO: lo aplicado por el (`revisadoPor`) y lo
  /// descartado por el, el ultimo primero. Es lo que la persona lee como
  /// «Aplicado por Marta…» y «Descartado por Marta…: motivo».
  Stream<List<Apunte>> decididosPorRevision() =>
      (_base.select(_base.apuntes)
            ..where(
              (a) =>
                  a.estado.equalsValue(EstadoApunte.descartadoPorRevisor) |
                  (a.estado.equalsValue(EstadoApunte.aplicado) &
                      a.revisadoPor.isNotNull()),
            )
            ..orderBy([(a) => OrderingTerm.desc(a.orden)]))
          .watch();

  /// LO QUE SALE EN LA PROXIMA VUELTA, en el orden en que se hizo.
  ///
  /// Se llama «lote» por historia y **ya no es una peticion**: desde el
  /// 01/10/2026 la subida manda estos apuntes **uno a uno**, cada peticion
  /// esperando su respuesta antes de mandar la siguiente, porque una peticion
  /// grande que se corta al 90 % no deja nada arriba y hay que volver a empezar
  /// por el primero (`nucleo/sincro/subida.dart`).
  ///
  /// Lo que NO cambio: veinte apuntes no son veinte peticiones **en paralelo**.
  /// Veinte a la vez al recuperar la senal es justo lo que dispara veinte
  /// renovaciones (caso I1), y eso sigue prohibido. Una detras de otra no es a la
  /// vez: nunca hay dos de esta cola en vuelo.
  ///
  /// El orden es lo que hace que esto se pueda partir en peticiones sueltas sin
  /// perder nada: sale por `orden` ascendente y se manda en ese mismo orden.
  ///
  /// **Solo `pendiente`.** Lo entregado a revision ya esta arriba: volver a
  /// mandarlo por la subida normal, el dia que la persona recupere el permiso,
  /// lo aplicaria por encima de la decision del revisor.
  Future<List<Apunte>> lote({int maximo = 200}) =>
      (_base.select(_base.apuntes)
            ..where((a) => a.estado.equalsValue(EstadoApunte.pendiente))
            ..orderBy([(a) => OrderingTerm.asc(a.orden)])
            ..limit(maximo))
          .get();

  Future<Apunte?> porClave(String clave) => (_base.select(
    _base.apuntes,
  )..where((a) => a.clave.equals(clave))).getSingleOrNull();

  /// El cuerpo del apunte, ya decodificado.
  static Object? cuerpoDe(Apunte a) => jsonDecode(a.cuerpo);

  /// Aplica lo que el servidor contesto de UN apunte.
  ///
  /// Va entero en una transaccion con la sustitucion del `local-…`: si el apunte
  /// quedara marcado como aplicado y la sustitucion fallara, el cierre de la
  /// tarde se iria a una ruta que no existe y nadie volveria a mirar ese apunte.
  Future<void> resolver(String clave, ResultadoApunte resultado) async {
    await _base.transaction(() async {
      final apunte = await (_base.select(
        _base.apuntes,
      )..where((a) => a.clave.equals(clave))).getSingleOrNull();
      if (apunte == null) {
        Registro.aviso('resultado de un apunte que no esta en la cola: $clave');
        return;
      }
      if (apunte.estado != EstadoApunte.pendiente) {
        // Ya estaba resuelto. Volver a aplicarlo reescribiria el motivo o
        // repetiria una sustitucion ya hecha.
        return;
      }

      if (resultado.estado == EstadoResultado.enRevision) {
        // El servidor ya la tiene en la bandeja de revision: ni aplicada ni
        // rechazada. Caer en el `else` de abajo la dejaria `rechazada`, con
        // «Reintentar» y «Descartar» sobre algo que decide otra persona.
        await marcarEnRevision(clave, entrega: resultado.revision);
        return;
      }

      if (resultado.seAplico) {
        await _sustituirProvisional(apunte, resultado.id);
        // LO QUE ACABA DE SUBIR YA NO «NACIO AQUI».
        //
        // `nacio_aqui` es lo que impide que «actualizar» borre trabajo que solo
        // existe en este aparato. Pero era un pestillo de UN SOLO SENTIDO: lo
        // ponia quien creaba, y lo unico que lo quitaba era la bajada del
        // tablero… que se niega a bajar mientras haya un 1. **Una zona que subia
        // perfectamente dejaba el tablero congelado para siempre**, con un cartel
        // diciendo «no esta en el servidor» sobre algo que si estaba.
        //
        // Peor todavia: el ciclo la veia huerfana, la reencolaba, se creaba una
        // segunda zona con el mismo nombre, el indice unico la rechazaba, y un
        // rechazo no se reintenta — atasco permanente y un rechazo falso en la
        // bandeja. Es un fallo mas grave que el que `nacio_aqui` vino a arreglar:
        // aquel perdia datos en un caso de esquina, este rompia el camino normal.
        //
        // Aqui es donde se sabe la verdad: el servidor acaba de decir que si.
        await _yaNoNacioAqui(apunte);

        // LO QUE SE CAYO AUNQUE EL APUNTE ENTRARA — 28/09/2026.
        //
        // Aqui solo se miraba `resultado.id`. El servidor contesta ademas
        // `descartados`, con el pedido nombrado, su motivo y que hacer
        // (`api/internal/api/tablero.go`, `DescartadoSalida`), **y nadie lo
        // leia**: una zona de doce podia parir una ruta de nueve y no quedaba
        // rastro en ningun sitio. Eso es lo que impidio ver el otro fallo del
        // mismo dia —la lista de pedidos que no viajaba— el dia que paso.
        //
        // Se guarda en `motivo` del propio apunte, que es la columna que ya
        // existe para «lo que el servidor dijo de esto», y NO se toca el
        // estado: el apunte se aplico de verdad y marcarlo rechazado ofreceria
        // «reintentar», que aqui armaria una SEGUNDA ruta. Lo que hace falta es
        // que alguien lo lea, no que se vuelva a mandar.
        //
        // Sin descartados no se escribe nada, y eso es la mitad de la regla:
        // un aviso que sale en cada armado deja de leerse (§3-quinquies), y
        // entonces tampoco se lee el dia que importa.
        final aviso = textoDeLosDescartados(resultado.descartados);
        if (aviso.isNotEmpty) {
          Registro.aviso(
            'el servidor dejo fuera ${resultado.descartados.length} '
            'pedido(s) de $clave: $aviso',
          );
        }

        await (_base.update(
          _base.apuntes,
        )..where((a) => a.clave.equals(clave))).write(
          ApuntesCompanion(
            estado: const Value(EstadoApunte.aplicado),
            resueltoAt: Value(_reloj()),
            // `Value.absent()` y no `Value(null)`: sin descartados esta columna
            // NO se toca.
            motivo: aviso.isEmpty ? const Value.absent() : Value(aviso),
          ),
        );
      } else {
        // Rechazado: se queda, con su motivo y su hora, hasta que una persona
        // decida. No se reintenta y no se borra (regla 6, caso S6).
        await (_base.update(
          _base.apuntes,
        )..where((a) => a.clave.equals(clave))).write(
          ApuntesCompanion(
            estado: const Value(EstadoApunte.rechazado),
            motivo: Value(resultado.motivo),
            resueltoAt: Value(_reloj()),
          ),
        );
      }
    });
  }

  /// El `local-…` de lo que este apunte creo pasa a ser el id de verdad.
  ///
  /// [reescribirApuntes] = `false` cuando lo decide un REVISOR: lo entregado a
  /// revision lleva el `local-…` en su original y `sync` lo traduce al aplicar; los
  /// apuntes que aun esperan en el aparato NO se reescriben, o su cuerpo cambia y la
  /// entrega siguiente choca con `409 huella_distinta` para siempre.
  Future<void> _sustituirProvisional(
    Apunte apunte,
    String? real, {
    bool reescribirApuntes = true,
  }) async {
    final provisional = apunte.provisional;
    if (provisional != null && real != null) {
      await _provisionales.sustituir(
        provisional,
        real,
        reescribirApuntes: reescribirApuntes,
      );
    } else if (provisional != null) {
      // Un apunte que CREA algo y vuelve sin id deja el `local-…` puesto
      // para siempre. No se calla.
      Registro.fallo(
        'el servidor aplico ${apunte.clave} pero no devolvio id para $provisional',
      );
    }
  }

  /// ENTREGADO A REVISION: el servidor lo guardo tal cual y lo decidira otra
  /// persona. Devuelve `false` si el apunte no estaba `pendiente`.
  ///
  /// Se llama **con la respuesta del servidor delante** —`en_revision`, o
  /// `repetido` de una entrega anterior— y nunca antes: marcarlo al mandar
  /// perderia el apunte de la cola si la respuesta no llega (queda en un estado
  /// que ni sube ni esta arriba).
  ///
  /// Lo que NO hace, y cada cosa costo o costaria un incidente:
  ///
  ///  * **no toca el cuerpo ni la ruta**: la huella del servidor es la del
  ///    original, y reescribirlo daria `409 huella_distinta` en la reentrega;
  ///  * **no suelta `nacio_aqui`**: el trabajo solo existe aqui y en la bandeja;
  ///    soltarlo deja que la bajada lo borre de la pantalla de la persona;
  ///  * **no borra nada**: es un cambio de estado, no de sitio.
  Future<bool> marcarEnRevision(String clave, {String? entrega}) async {
    final tocadas =
        await (_base.update(_base.apuntes)..where(
              (a) =>
                  a.clave.equals(clave) &
                  a.estado.equalsValue(EstadoApunte.pendiente),
            ))
            .write(
              ApuntesCompanion(
                estado: const Value(EstadoApunte.enRevision),
                revision: Value(entrega),
                // Cuando se entrego: «Entregado a revision el 8/10, 14:32».
                resueltoAt: Value(_reloj()),
              ),
            );
    if (tocadas > 0) {
      Registro.aviso('apunte entregado a revision: $clave (entrega $entrega)');
    }
    return tocadas > 0;
  }

  /// LO QUE EL SERVIDOR DICE DESPUES de entregar: aplicado, descartado, o
  /// «sigue en revision». Solo mueve apuntes que estan `enRevision`.
  ///
  ///  * `aplicado` → `aplicado` con quien y cuando, el `local-…` pasa a ser el
  ///    id de verdad y se suelta `nacio_aqui` (ya esta arriba).
  ///  * `descartado` → `descartadoPorRevisor` con el motivo escrito de quien lo
  ///    descarto; tambien suelta `nacio_aqui` —ya no sube nunca—, y se queda
  ///    ahi a la vista: no es un borrado (CLAUDE.md §4).
  ///  * `rechazado` (el reparto no pudo aplicarlo) → **sigue `enRevision`**, con
  ///    el literal en `motivoRevision`. Ver [EstadoApunte.enRevision].
  ///  * `en_revision` → sigue, y se limpia lo que hubiera de un intento anterior.
  ///  * `aplicando` → no se toca nada: alguien lo esta aplicando ahora mismo.
  ///
  /// **Escribe en `motivoRevision`, jamas en `motivo`**: en un `aplicado`,
  /// `motivo` es «salio con menos de lo que pusiste» y ponerle aqui «Aplicado
  /// por …» llenaria ese aviso (`descartesSinLeer`).
  Future<void> resolverRevision(String clave, DecisionDeRevision decision) async {
    await _base.transaction(() async {
      final apunte = await (_base.select(
        _base.apuntes,
      )..where((a) => a.clave.equals(clave))).getSingleOrNull();
      if (apunte == null) {
        Registro.aviso('decision de revision de un apunte que no esta: $clave');
        return;
      }
      // Ya decidido en otra vuelta: reescribirlo falsearia lo que se leyo.
      if (apunte.estado != EstadoApunte.enRevision) return;

      switch (decision.estado) {
        case EstadoEnRevision.aplicando:
          return;
        case EstadoEnRevision.enRevision:
          await (_base.update(
            _base.apuntes,
          )..where((a) => a.clave.equals(clave))).write(
            const ApuntesCompanion(
              revisadoPor: Value(null),
              revisadoAt: Value(null),
              motivoRevision: Value(null),
            ),
          );
        case EstadoEnRevision.rechazado:
          await (_base.update(
            _base.apuntes,
          )..where((a) => a.clave.equals(clave))).write(
            ApuntesCompanion(
              revisadoPor: Value(decision.por),
              revisadoAt: Value(decision.cuando),
              motivoRevision: Value(decision.motivo ?? textoSinMotivoDeRevision),
            ),
          );
        case EstadoEnRevision.aplicado:
          // Primero soltar y luego sustituir: la sustitucion cambia el id de la
          // fila y `_yaNoNacioAqui` la busca por el provisional.
          await _yaNoNacioAqui(apunte);
          await _sustituirProvisional(
            apunte,
            decision.idCreado,
            reescribirApuntes: false,
          );
          // LO QUE SE CAYO AUNQUE ENTRARA: el mismo aviso que la subida normal
          // (`descartesSinLeer`). Es la unica cosa que se escribe en `motivo`.
          final aviso = textoDeLosDescartados(decision.descartados);
          await (_base.update(
            _base.apuntes,
          )..where((a) => a.clave.equals(clave))).write(
            ApuntesCompanion(
              estado: const Value(EstadoApunte.aplicado),
              motivo: aviso.isEmpty ? const Value.absent() : Value(aviso),
              revisadoPor: Value(decision.por),
              revisadoAt: Value(decision.cuando ?? _reloj()),
              motivoRevision: const Value(null),
              resueltoAt: Value(_reloj()),
            ),
          );
        case EstadoEnRevision.descartado:
          await _yaNoNacioAqui(apunte);
          await (_base.update(
            _base.apuntes,
          )..where((a) => a.clave.equals(clave))).write(
            ApuntesCompanion(
              estado: const Value(EstadoApunte.descartadoPorRevisor),
              revisadoPor: Value(decision.por),
              revisadoAt: Value(decision.cuando ?? _reloj()),
              motivoRevision: Value(decision.motivo ?? textoSinMotivoDeRevision),
              resueltoAt: Value(_reloj()),
            ),
          );
      }
    });
  }

  /// Los resultados de una subida entera, en el mismo orden que se mandaron.
  Future<void> resolverLote(Map<String, ResultadoApunte> porClave) async {
    for (final entrada in porClave.entries) {
      await resolver(entrada.key, entrada.value);
    }
  }

  /// Un intento mas para todo el lote. Se cuenta para poder decir en el panel
  /// que un aparato lleva reintentando desde el martes.
  Future<void> anotarIntento(Iterable<String> claves) async {
    if (claves.isEmpty) return;
    await (_base.update(
      _base.apuntes,
    )..where((a) => a.clave.isIn(claves.toList()))).write(
      ApuntesCompanion.custom(
        intentos: _base.apuntes.intentos + const Constant(1),
      ),
    );
  }

  /// Cuantos apuntes quedarian pendientes DESPUES de subir [enElLote] de ellos.
  ///
  /// Va en el cuerpo de `POST /sync/subida` porque la cola vive en el telefono:
  /// lo que no ha subido no existe en el servidor, y sin este numero el panel de
  /// control ensenaria a Palma en verde justo el dia que se le corto la subida a
  /// la mitad (`sync/internal/sincro/subida.go`).
  ///
  /// **Con la subida de uno en uno, [enElLote] es 1**, y no el tamano de la cola.
  /// Lo que ya subio ha dejado de ser `pendiente` en la base, asi que esta cuenta
  /// ya lo ha descontado; lo unico que falta por descontar es el que va dentro de
  /// la peticion que se esta armando. Ver `Subida._mandarUno`.
  ///
  /// Un rechazado tampoco cuenta, y esta bien: `cuantosPendientes()` no los mira,
  /// porque no van a subir solos —esperan a que una persona decida— y el servidor
  /// los lleva por su cuenta en su propio contador (`AnotarSubida`, `rechazados`).
  Future<int> cuantosQuedanTras(int enElLote) async {
    final quedan = await _base.cuantosPendientes() - enElLote;
    return quedan > 0 ? quedan : 0;
  }

  /// LO QUE DECIDE UNA PERSONA SOBRE UN RECHAZADO: descartarlo o reintentarlo.
  ///
  /// El pliego dice que un apunte rechazado «se queda a la vista con su motivo
  /// **hasta que una persona decida**», y hasta hoy faltaba justo eso: la
  /// decision. No habia forma de quitarlos ni de volver a intentarlos, asi que
  /// se quedaban en la pantalla para siempre. Jose, 16/09/2026: «no puedo borrar
  /// esas notificaciones».
  ///
  /// Un aparato lo usan VARIAS personas y hay diez repartiendo: una bandeja que
  /// solo crece deja de leerse a la tercera semana, y entonces el rechazo que SI
  /// importaba se pierde entre los viejos.
  ///
  /// Las dos decisiones son distintas a proposito:
  ///
  ///  * **Descartar** da el apunte por cerrado. Se usa cuando ya no aplica —el
  ///    pedido entro en otra ruta, la zona se hizo a mano en la web— o cuando el
  ///    rechazo fue culpa nuestra y ya esta arreglado.
  ///  * **Reintentar** lo devuelve a la cola. Se usa cuando lo que lo tumbaba ya
  ///    no esta: un despliegue que faltaba, un permiso que se dio.
  ///
  /// Ninguna de las dos pasa sola. Eso es lo que no se toca del pliego.
  ///
  /// ## DESCARTAR NO BORRA, Y ESA ES LA CORRECCION DEL 29/09/2026
  ///
  /// Hasta ese dia borraba la fila, y por eso el boton parecia no servir para
  /// nada. Jose: «los errores se acumulan y nunca se borran, se mantienen aunque
  /// se hayan borrado las cosas y solucionado».
  ///
  /// El recorrido completo, que es un circulo:
  ///
  ///  1. se descarta el rechazo y el apunte desaparece;
  ///  2. la zona que ese apunte iba a subir se queda **sin ningun apunte vivo**,
  ///     que es la definicion de huerfana (`nucleo/sincro/huerfanos.dart`);
  ///  3. el ciclo la ve colgada y la vuelve a encolar —para eso esta—;
  ///  4. el servidor vuelve a decir que no, y el rechazo esta otra vez en la
  ///     bandeja, con clave nueva y la misma pinta.
  ///
  /// Nadie miente en ese circulo: cada pieza hace lo suyo. Lo que faltaba es que
  /// **la decision de la persona quedara escrita en algun sitio**, y el unico
  /// sitio donde cabe es el propio apunte. Por eso ahora pasa a `descartado` y se
  /// queda ahi: fuera de la bandeja, fuera del «N sin subir», y visible para lo
  /// huerfano como «esto ya se decidio, no lo vuelvas a encolar».
  ///
  /// **Y hay que soltar la marca de «nacio aqui»**, que es la otra mitad. Esa
  /// marca protege la fila local para que una bajada no borre trabajo que
  /// todavia no subio; en cuanto una persona dice que ese trabajo ya no sube,
  /// protegerla deja de ser proteger y pasa a ser atascar: la bajada no puede
  /// tocar esa zona y el Tablero de ese aparato se queda congelado esperando una
  /// subida que nadie va a hacer. Es el mismo atasco de la zona «Vista» del
  /// 16/09/2026, por el otro lado.
  Future<void> descartar(String clave) async {
    final apunte =
        await (_base.select(_base.apuntes)..where(
              (a) =>
                  a.clave.equals(clave) &
                  a.estado.equalsValue(EstadoApunte.rechazado),
            ))
            .getSingleOrNull();
    if (apunte == null) return;

    await (_base.update(_base.apuntes)..where((a) => a.clave.equals(clave)))
        .write(
          ApuntesCompanion(
            estado: const Value(EstadoApunte.descartado),
            resueltoAt: Value(_reloj()),
          ),
        );
    // EL MOTIVO NO SE TOCA. Es lo unico que explica manana por que ese cierre no
    // llego, y la persona que lo descarta hoy no es la que preguntara el lunes.
    await _yaNoNacioAqui(apunte);

    // Queda dicho: si manana alguien pregunta por que no llego un cierre, esto
    // es lo unico que lo explica.
    Registro.aviso('rechazo descartado a mano: $clave');
  }

  /// Quita la marca de «solo existe aqui» a lo que este apunte acaba de subir.
  ///
  /// Se identifica por donde el apunte lo nombra, que son dos sitios y nada mas:
  ///
  ///  * `provisional` — la zona que el apunte CREA.
  ///  * la ruta `/board/placements/{pedido}` — la tarjeta que coloca.
  ///
  /// Silencioso a proposito si las tablas no existen: un aparato que nunca abrio
  /// el Tablero no las tiene, y eso no puede tumbar la subida del dia.
  Future<void> _yaNoNacioAqui(Apunte apunte) async {
    try {
      final provisional = apunte.provisional;
      if (provisional != null) {
        await _base.customStatement(
          'UPDATE board_columns SET nacio_aqui = 0 WHERE id = ?1',
          [provisional],
        );
      }
      const prefijo = '/board/placements/';
      if (apunte.ruta.startsWith(prefijo)) {
        // Sin la query, si algun dia la lleva.
        final pedido = apunte.ruta.substring(prefijo.length).split('?').first;
        if (pedido.isNotEmpty) {
          await _base.customStatement(
            'UPDATE board_placements SET nacio_aqui = 0 WHERE order_id = ?1',
            [pedido],
          );
        }
      }
    } on Object catch (e) {
      Registro.info('no se pudo limpiar «nacio aqui» de ${apunte.clave}: $e');
    }
  }

  /// Devuelve un rechazado a la cola. Vuelve a salir en el proximo envio.
  Future<void> reintentar(String clave) async {
    final tocadas =
        await (_base.update(_base.apuntes)..where(
              (a) =>
                  a.clave.equals(clave) &
                  a.estado.equalsValue(EstadoApunte.rechazado),
            ))
            .write(
              ApuntesCompanion(
                estado: const Value(EstadoApunte.pendiente),
                motivo: const Value(null),
                resueltoAt: const Value(null),
                intentos: const Value(0),
              ),
            );
    if (tocadas > 0) {
      Registro.aviso('rechazo devuelto a la cola a mano: $clave');
    }
  }

  /// Poda los aplicados viejos. Los rechazados NO se podan nunca: son la unica
  /// constancia de algo que no llego a pasar.
  ///
  /// **Y tampoco los que llevan un aviso sin leer** ([descartesSinLeer]). Es la
  /// misma razon que la de los rechazados: ese apunte es lo unico que explica
  /// por que una ruta salio con nueve de doce, y borrarlo a los siete dias
  /// porque «ya subio» es descartarlo en silencio con un temporizador. Se va en
  /// cuanto una persona lo da por leido, que es lo que quita el motivo.
  Future<int> podar() {
    final limite = _reloj().subtract(conservarAplicados);
    return (_base.delete(_base.apuntes)..where(
          (a) =>
              a.estado.equalsValue(EstadoApunte.aplicado) &
              a.resueltoAt.isSmallerThanValue(limite) &
              a.motivo.isNull(),
        ))
        .go();
  }
}
