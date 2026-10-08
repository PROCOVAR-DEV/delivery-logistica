import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../nucleo/base/conexion/conexion.dart';
import '../nucleo/identidad/entrada_por_accesos.dart';
import '../nucleo/identidad/sesion.dart';
import '../nucleo/proveedores.dart';
import '../nucleo/red/fallos.dart';
import '../nucleo/registro/registro.dart';
import '../nucleo/sincro/huerfanos.dart';

/// Como queda la aplicacion despues de arrancar.
enum Arranque {
  /// Hay sesion y se puede trabajar.
  dentro,

  /// No hay sesion, o murio: a la pantalla de acceso.
  fuera,

  /// Hay sesion guardada pero no se pudo comprobar porque no hay red. **Se
  /// entra igual** (regla 1: para entrar hace falta conexion, una vez dentro
  /// no).
  dentroSinComprobar,

  /// Hay sesion en Accesos y la API dice 403 `sin_permiso_reparto`: la persona
  /// no entra a Reparto. A su pantalla, SIN pasar por el login (bucle).
  sinPermiso,
}

/// Como quedo el arranque, con lo que hace falta para poder DECIRLO.
class ResultadoDelArranque {
  const ResultadoDelArranque(
    this.como, {
    this.sesion,
    this.sesionPerdida = false,
  });

  final Arranque como;

  /// Quien entro. `null` cuando se sale [Arranque.fuera].
  final Sesion? sesion;

  /// **El aparato tiene datos bajados y aun asi no hay sesion.**
  ///
  /// Es el caso que dejo a Jose delante de un formulario mudo el 15/09/2026: se
  /// entro, se bajo el dia, se cerro la aplicacion y al abrirla pedia la
  /// contrasena otra vez. Con los datos ahi mismo, en el disco.
  ///
  /// Se dice aparte porque lo que hay que ensenar es distinto: a quien nunca ha
  /// entrado se le pide la contrasena y ya; a este hay que decirle **que su
  /// sesion se perdio y que hace falta senal para volver a entrar**, porque si
  /// no se queda probando la contrasena buena en el patio de un almacen
  /// pensando que se le olvido.
  final bool sesionPerdida;
}

/// Abre la base de quien corresponda, lee la sesion e intenta RENOVAR.
///
/// **No se comprueba el token de acceso por su cuenta.** Dura minutos, asi que
/// casi siempre estara caducado al abrir, y eso no significa que la sesion haya
/// muerto. Se intenta renovar, que hace las dos cosas a la vez: si el par sirve
/// devuelve uno nuevo, y si no, no sirve (`identidad.md`).
///
/// ## El orden, que cambio el 15/09/2026
///
/// PRIMERO la sesion y DESPUES la base, y no al reves. Ahora hay **una base por
/// persona** (`nucleo/base/conexion/nombre.dart`): hasta no saber quien entro no
/// se sabe que fichero abrir, y abrir uno cualquiera «para ir tirando» es abrir
/// los datos del ultimo que estuvo.
Future<ResultadoDelArranque> arrancar(Ref ref) async {
  // Las fechas en espanol. Va aqui y no en cada formato porque `DateFormat` con
  // un locale sin cargar lanza, y hacerlo al pintar seria descubrirlo en la
  // pantalla de alguien.
  await initializeDateFormatting('es');

  final almacen = ref.read(almacenSesionProvider);
  // `leer()` no lanza nunca (`almacen_sesion.dart`). Antes si podia, y una
  // excepcion aqui subia hasta el portero, que la traducia a «no hay sesion»
  // sin decir una palabra.
  final Sesion? guardada = await almacen.leer();

  // ¿Y SI LA SESION NO LA LLEVA EL APARATO?
  //
  // En la WEB la sesion es la cookie `httpOnly` que dejo Accesos, y desde aqui
  // no se puede ni leer: el almacen devuelve `null` aunque haya sesion. Quien lo
  // sabe es el servidor, asi que se le pregunta —`GET /api/me`— ANTES de dar a
  // nadie por fuera. Sin esta pregunta, quien ya entro en Accesos aterriza en un
  // formulario de contrasena que en la web no pinta nada (`docs/identidad.md`).
  //
  // ## Y SE PREGUNTA SIEMPRE, TAMBIEN CON UN PAR GUARDADO — 24/09/2026
  //
  // Antes esto era `guardada == null && …`: lo guardado mandaba y no se
  // preguntaba nada. El motivo era bueno —si el login unico fallo y se entro por
  // la puerta de respaldo, ese par es la sesion— pero dejaba un agujero que mata
  // la web entera y **en verde**:
  //
  // un `reparto.sesion` viejo en `localStorage` —de una prueba, de la puerta de
  // respaldo de hace un mes— gana sobre una cookie de Accesos VALIDA. Se intenta
  // renovarlo contra `{AUTH_URL}/api/auth/refresh`, eso falla por RED (no con un
  // 401), y el arranque caia en [Arranque.dentroSinComprobar] —que es la regla
  // del APARATO— dejando la web dentro con un token muerto: `/api/eventos` y
  // `/api/sync/cambios` contestando 401 cada diez segundos para siempre, la
  // barra superior con una identidad fantasma, «Cargando los pedidos…» eterno y
  // **ni un error en pantalla**. Ni una sola llamada a `/api/me`. Borrando el
  // `localStorage` funcionaba al instante.
  //
  // La cookie es lo que el SERVIDOR reconoce, y en un navegador siempre se le
  // puede preguntar. Asi que gana ella, y el par guardado se queda de respaldo
  // para cuando no hay cookie — que es justo para lo que existe.
  //
  // En la APK y en el escritorio esto no corre nunca. Alli se entra con usuario
  // y contrasena, y esa es la razon de ser del proyecto.
  final QuienSoy? porAccesos = ref.read(entraPorAccesosProvider)
      ? await ref.read(entradaPorAccesosProvider).quienSoy()
      : null;
  if (porAccesos is HaySesion && guardada != null) {
    // EL PAR VIEJO SE VA. Si se queda, la proxima carga vuelve a preferirlo, y
    // el ciclo sigue pidiendo `POST /api/auth/refresh` desde el navegador cada
    // pocos minutos contra un par que no vale — la web no tiene par que renovar.
    Registro.aviso(
      'web: habia una sesion guardada en el navegador y ademas cookie de '
      'Accesos; manda la cookie y se borra el par guardado',
    );
    await almacen.borrar();
  }
  if (porAccesos is SinPermiso) {
    return const ResultadoDelArranque(Arranque.sinPermiso);
  }
  final Sesion? quienEsta = porAccesos is HaySesion
      ? porAccesos.sesion
      : guardada;

  // LA BASE DE QUIEN ENTRO, y solo entonces.
  ref.read(duenoDeLaBaseProvider.notifier).es(quienEsta?.sub);
  // Tocar la base la abre. Si en web cayo a memoria, aqui es donde se entera.
  await ref.read(baseProvider).cuantosPendientes();

  if (porAccesos is HaySesion) {
    // Dentro sin escribir nada, que es de lo que se trata. No se renueva: no hay
    // par que renovar y la cookie la renueva Accesos por su cuenta.
    Registro.info('dentro por la cookie de Accesos: ${porAccesos.sesion.sub}');
    return ResultadoDelArranque(Arranque.dentro, sesion: porAccesos.sesion);
  }

  if (guardada == null) {
    // ¿Este aparato tenia trabajo dentro? Si lo tenia, esto no es «todavia no ha
    // entrado nadie»: es una sesion que se perdio, y hay que decirlo.
    //
    // En la web NO se pregunta: alli la base nace vacia en cada carga (`CLAUDE.md`
    // §1), asi que la respuesta seria siempre «no» y ademas no hay nada que
    // contar — el navegador se va a Accesos y vuelve dentro.
    final perdida = porAccesos == null && await _elAparatoTieneDatos(ref);
    // SIN ESPERARLO. Mirar el disco es una llamada al sistema que en algunos
    // destinos arranca un proceso, y el arranque no puede quedarse parado en
    // una linea de registro: lo que hay detras de este `await` es la pantalla
    // que la persona esta mirando.
    unawaited(_mirarSiQuedoLaBaseDeAntes());
    return ResultadoDelArranque(Arranque.fuera, sesionPerdida: perdida);
  }

  try {
    final nueva = await ref.read(renovadorProvider).renovar(guardada);
    return ResultadoDelArranque(Arranque.dentro, sesion: nueva);
  } on SesionMuerta {
    // El refresh ya no vale. Los tokens los borro el propio renovador. La base
    // vuelve a ser de nadie: lo de esa persona se queda en su fichero, entero,
    // para cuando vuelva a entrar.
    final perdida = await _elAparatoTieneDatos(ref);
    ref.read(duenoDeLaBaseProvider.notifier).es(null);
    return ResultadoDelArranque(Arranque.fuera, sesionPerdida: perdida);
  } on FalloDeRed {
    // EN LA WEB NO SE ENTRA A CIEGAS. NUNCA. (§1)
    //
    // «Con sesion guardada se entra aunque no se pueda comprobar» es la regla
    // del APARATO, y existe por una razon que en un navegador no pasa: el
    // logistico sale del almacen sin cobertura con el dia dentro del telefono.
    // La web siempre tiene internet y tiene `/api/me` ahi mismo; si no se puede
    // comprobar la sesion, lo que hay detras no es una caida pasajera, es un
    // par que no vale. Entrar ahi en verde deja la aplicacion entera contestando
    // 401 sin decir una palabra, que es justo lo que se vio el 24/09/2026.
    //
    // Se va a la puerta Y SE BORRA el par: si se queda, la carga siguiente
    // vuelve a intentarlo y el bucle contra `auth` no para nunca.
    if (ref.read(entraPorAccesosProvider)) {
      Registro.aviso(
        'web: la sesion guardada no se pudo comprobar y no hay cookie; a la '
        'puerta, y se borra el par para no repetir el intento en cada carga',
      );
      await almacen.borrar();
      ref.read(duenoDeLaBaseProvider.notifier).es(null);
      return const ResultadoDelArranque(Arranque.fuera);
    }
    // Sin red al arrancar se entra con lo guardado. Borrar la sesion aqui seria
    // dejar a alguien fuera en la calle por una caida pasajera.
    Registro.aviso('arranque sin red: se entra con la sesion guardada');
    return ResultadoDelArranque(Arranque.dentroSinComprobar, sesion: guardada);
  }
}

/// ¿Hay algo bajado o algo sin subir en la base que esta abierta?
///
/// Las dos cosas y no solo la primera: un aparato al que se le bajo el dia y
/// otro que ademas tiene veintitres apuntes esperando son los dos «aqui habia
/// alguien trabajando», y el segundo mas todavia.
Future<bool> _elAparatoTieneDatos(Ref ref) async {
  try {
    final base = ref.read(baseProvider);
    // `cuantosSinSubir` y no `cuantosPendientes`: un cierre RECHAZADO es
    // trabajo que no llego al servidor igual que uno pendiente, y con la
    // pregunta estrecha un aparato cuyo unico trabajo era ese contestaba «aqui
    // no habia nadie» y no se decia «sesion perdida» (24/09/2026).
    if (await base.cuantosSinSubir() > 0) return true;
    // Y LO HUERFANO, que ni siquiera esta en `apuntes`: una ruta armada sin
    // señal que se quedo sin su apunte es el caso mas claro de «aqui habia
    // alguien trabajando», y es ademas el que no se arregla solo.
    if ((await Huerfanos(base).mirar()).hayAlguno) return true;
    final recuento = await ref.read(recontadorProvider).ahora();
    return !recuento.vaATraerTodo;
  } on Object catch (e) {
    Registro.aviso('no se pudo mirar si el aparato tiene datos: $e');
    return false;
  }
}

/// Deja dicho en el registro si quedo el fichero de cuando habia UNA SOLA base
/// por aparato. Ver `nombreDeLaBaseDeAntes`.
Future<void> _mirarSiQuedoLaBaseDeAntes() async {
  if (!await hayBaseDeAntes()) return;
  Registro.aviso(
    'queda el fichero $nombreDeLaBaseDeAntes.sqlite de la version de una sola '
    'base por aparato: ya no se abre, y si llevaba cola sin subir, esa cola no '
    'la va a mandar nadie',
  );
}
