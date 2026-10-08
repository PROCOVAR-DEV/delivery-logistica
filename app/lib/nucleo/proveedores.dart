import 'package:drift/drift.dart' show TableUpdateQuery;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navegacion/estado_navegacion.dart';
import '../navegacion/portero.dart';
import 'registro/registro.dart';
import 'actualizacion/comprobador.dart';
import 'base/base.dart';
import 'cola/cola_salida.dart';
import 'cola/provisionales.dart';
import 'frescura/frescura.dart';
import 'frescura/primera_bajada.dart';
import 'identidad/almacen_sesion.dart';
import 'identidad/renovador.dart';
import 'plataforma.dart';
import 'red/cliente_api.dart';
import 'red/de_quien_viene.dart';
import 'red/escritura_en_vivo.dart';
import 'red/entorno.dart';
import 'red/eventos.dart';
import 'red/fallos.dart';
import 'red/salud.dart';
import 'red/veredicto_del_sistema.dart';
import 'reloj.dart';
import 'sincro/bajada.dart';
import 'sincro/ciclo.dart';
import 'sincro/huerfanos.dart';
import 'sincro/identidad_del_aparato.dart';
import 'sincro/sucursal_del_aparato.dart';
import 'sincro/recuento.dart';
import 'sincro/subida.dart';
import 'sincro/vigia.dart';

/// El cableado de las cinco piezas transversales.
///
/// Todo lo de aqui es un `Provider` a mano y no generado: son objetos unicos de
/// la aplicacion, sin parametros, y el generador no anade nada. Lo generado se
/// reserva para los providers de pantalla, que si se parametrizan por sucursal y
/// por filtro.

/// DE QUIEN ES LA BASE que esta abierta: el `sub` del token, o `null` si no ha
/// entrado nadie todavia.
///
/// Lo pone el arranque en cuanto lee la sesion guardada, y la pantalla de acceso
/// en cuanto alguien entra. Cambiarlo **cambia de copia**: `baseProvider` lo
/// mira, asi que al moverlo se cierra la base de quien se va y se abre la de
/// quien llega, con su cola y sus datos dentro. El porque, entero, en
/// `nucleo/base/conexion/nombre.dart`.
class DuenoDeLaBase extends Notifier<String?> {
  @override
  String? build() => null;

  /// Se llama ANTES de tocar la base. Poner el mismo que ya estaba no hace nada
  /// —ni cierra ni reabre— porque si no, cada ciclo reabriria el fichero.
  void es(String? sub) {
    final limpio = (sub == null || sub.trim().isEmpty) ? null : sub.trim();
    if (state == limpio) return;
    Registro.info('la base pasa a ser de ${limpio ?? "nadie"}');
    state = limpio;
  }
}

final duenoDeLaBaseProvider = NotifierProvider<DuenoDeLaBase, String?>(
  DuenoDeLaBase.new,
);

/// La base local. Es LA fuente de verdad de la aplicacion: ninguna pantalla mira
/// la respuesta de una peticion, todas miran esto.
///
/// **Una por persona.** El `watch` de [duenoDeLaBaseProvider] es lo que hace que
/// cerrar sesion no borre nada: cambia el dueno, esta base se cierra, se abre la
/// del siguiente y todo lo que cuelga de aqui —la cola, la frescura, la bajada,
/// el ciclo— se rehace apuntando a la copia nueva.
final baseProvider = Provider<BaseLocal>((ref) {
  final base = BaseLocal(dueno: ref.watch(duenoDeLaBaseProvider));
  ref.onDispose(() => cerrarLaBaseSinRuido(base));
  return base;
});

/// CERRAR LA BASE SIN QUE UN FALLO DE DRIFT DEJE A NADIE EN LA PUERTA.
///
/// Esto se llama en el momento exacto en el que alguien ENTRA: el portero pone
/// el nuevo dueno (`duenoDeLaBaseProvider.es(sesion.sub)`), Riverpod tira el
/// `baseProvider` anterior y este `onDispose` cierra la base de antes.
///
/// `GeneratedDatabase.close()` recorre sus consultas vivas para cerrarlas. En
/// ese mismo instante las pantallas se estan rehaciendo contra la copia nueva y
/// alguna se apunta mientras el cierre recorre, asi que revienta con:
///
/// ```
/// Unhandled Exception: Concurrent modification during iteration: _Map len:4.
///   StreamQueryStore.close   GeneratedDatabase.close
/// ```
///
/// **Y eso tiraba a la persona de vuelta a la pantalla de acceso.** Visto el
/// 16/09/2026 en un Galaxy A16, y lo peor era como se veia: el registro de
/// Accesos decia `auth.apk.login` —la contrasena estaba bien y el par de tokens
/// se habia entregado— y en el telefono el formulario se vaciaba SIN UN SOLO
/// MENSAJE. Desde fuera parecia una contrasena mal escrita; era un fallo
/// nuestro al cambiar de base.
///
/// Se traga a proposito. Aqui no hay ningun dato en juego: lo que se estaba
/// cerrando es la copia ANTERIOR, ya escrita en disco y con sus transacciones
/// cerradas —lo pendiente de subir vive en su tabla, no en memoria—. El sistema
/// suelta el fichero igual. Dejar que el fallo suba, en cambio, rompe
/// justamente el gesto de entrar.
Future<void> cerrarLaBaseSinRuido(BaseLocal base) async {
  try {
    await base.close();
  } on Object catch (e) {
    Registro.aviso('la base anterior no cerro limpia: $e');
  }
}

/// El reloj del APARATO. Como provider para poder moverlo en los tests.
final relojProvider = Provider<Reloj>((ref) => relojDelAparato);

final almacenSesionProvider = Provider<AlmacenDeSesion>(
  (ref) => abrirAlmacenDeSesion(),
);

/// El Dio **crudo** de auth: sin `InterceptorSesion`, porque renovar no se
/// renueva a si mismo.
///
/// La base lleva `/api/auth` puesto, que es donde viven las tres puertas de
/// verdad: `POST /api/auth/token`, `/api/auth/refresh` y `/api/auth/logout`
/// (repo `procovar-auth`). `Entorno.authUrl` es el dominio a secas porque auth
/// es de toda Procovar y puede mudarse sin las otras dos.
final dioAuthProvider = Provider<Dio>(
  (ref) =>
      Dio(
          BaseOptions(
            baseUrl: '${Entorno.authUrl}/api/auth',
            // Los mismos plazos que el resto (`red/cliente_api.dart`), y aqui aprieta
            // mas que en ningun sitio: esta es la peticion del ARRANQUE, la que se
            // hace antes de pintar nada. Con los 30 s de antes, abrir la aplicacion
            // con senal mala eran 30 s de pantalla de espera antes de entrar con lo
            // guardado. Renovar no reintenta, asi que este numero ES el peor caso.
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            contentType: Headers.jsonContentType,
          ),
        )
        ..interceptors.add(
          // ESTE CLIENTE TAMBIEN CUENTA PARA LA SALUD DE LA RED, y es el que mas.
          //
          // Renovar es el PRIMER paso del ciclo, antes de subir y de bajar. Sin
          // conexion el ciclo muere aqui, asi que las peticiones de `ClienteApi` —las
          // unicas que contaban intentos— **no llegan a hacerse nunca**. El resultado
          // era el de siempre: la franja tardaba minutos en decir «sin conexion»,
          // porque volvia a depender de contar ciclos enteros.
          //
          // Visto en el Galaxy A16 el 16/09/2026, con el telefono sin salida a
          // internet comprobada: 35 s despues de abrir, la franja seguia callada.
          //
          // Va como interceptor y no envolviendo el cliente porque este Dio es crudo
          // a proposito —renovar no se renueva a si mismo— y eso no se toca.
          InterceptorDeSalud(
            alIntentar: ({required bool llego}) => ref
                .read(saludDeLaRedProvider.notifier)
                .anotarIntento(llego: llego),
          ),
        ),
);

/// Cuenta cada intento de un Dio crudo para la salud de la red.
///
/// Un error de red cuenta como «no llego». Una respuesta de NUESTRO servidor
/// —incluido un 401 o un 404— cuenta como que SI llego: el servidor contesto.
///
/// ## Y «una respuesta» no basta: tiene que ser la NUESTRA — 28/09/2026
///
/// Este interceptor cuenta la peticion de renovar, que es el primer paso del
/// ciclo y la primera que se hace al abrir la aplicacion. Si algo por el camino
/// contesta esa peticion en vez de auth, habia `Response`, asi que aqui se
/// anotaba `llego: true` **en cada vuelta del ciclo**: el contador de fallos se
/// ponia a cero solo, cada pocos minutos, antes de llegar a tres, y la franja
/// no llegaba a decir «sin conexion» jamas.
///
/// Ahora se le pregunta a `contestoLoNuestro` en los dos lados. Ver
/// `red/de_quien_viene.dart`.
class InterceptorDeSalud extends Interceptor {
  InterceptorDeSalud({required this.alIntentar});

  final void Function({required bool llego}) alIntentar;

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    alIntentar(llego: contestoLoNuestro(response));
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Con respuesta NUESTRA, el servidor contesto: la red esta bien aunque el
    // codigo sea malo. Sin respuesta —o con la de otro—, no se llego.
    // `contestoLoNuestro` ya devuelve `false` cuando no hay ninguna.
    alIntentar(llego: contestoLoNuestro(err.response));
    handler.next(err);
  }
}

/// EL CANDADO. Uno solo en toda la aplicacion — dos instancias son dos candados
/// distintos, y dos candados no son ningun candado.
final renovadorProvider = Provider<Renovador>(
  (ref) => Renovador(
    ref.watch(dioAuthProvider),
    ref.watch(almacenSesionProvider),
    // 403 `sin_permiso` al renovar: la persona perdio el permiso de Reparto.
    // Al portero, sin borrar tokens ni cola (`docs/sin-permiso.md`).
    alFaltarPermiso: () => ref.read(porteroProvider).sinPermiso(),
  ),
);

/// La sucursal que el Super Admin esta mirando. `null` = la suya.
///
/// Cambiarla **no recarga la pagina**: los providers de pantalla la miran, asi
/// que se reconstruyen solos y los numeros cambian en el sitio.
///
/// ## Y SE RECUERDA AL CERRAR LA APLICACION — 16/09/2026
///
/// Antes no. Arrancaba en `null` y se perdia en cada arranque, asi que quien ve
/// las ocho volvia siempre a «Todas». Eso no es solo una molestia: con «Todas»
/// puesto, el Panel dice «Falta configurar esta sucursal, 3 de 4» y los
/// importes no se convierten —la tasa es POR SUCURSAL—, de modo que la
/// aplicacion se abre pareciendo a medio configurar cuando no lo esta. Jose lo
/// vio en su telefono ese dia, con La Habana ya elegida y completa.
///
/// Se guarda en `preferencias`, que es del APARATO: la sucursal que se mira es
/// donde uno esta, no quien uno es.
class SucursalMirada extends Notifier<String?> {
  @override
  String? build() => null;

  void mirar(String? sucursalId) {
    final cambio = state != sucursalId;
    state = sucursalId;
    // Sin esperarlo: quien acaba de tocar el selector ya esta viendo los
    // numeros de la otra sucursal, y una escritura en disco no puede meterse
    // por medio. Si falla, lo peor que pasa es que el proximo arranque abra
    // donde abria antes.
    unawaited(_guardar(ClaveDePreferencia.sucursalMirada, sucursalId));
    if (cambio) unawaited(_traerLaNueva());
  }

  /// LA COPIA ES DE LA SUCURSAL QUE SE ESTABA MIRANDO, asi que al cambiar hay
  /// que volver a traerla ENTERA.
  ///
  /// La bajada es por diferencias: pide «lo que cambio desde ...», y ese «desde»
  /// es el de la bajada anterior — la de la OTRA sucursal—. Los pedidos de la
  /// nueva no han cambiado desde entonces, asi que **no vienen nunca**. No falla
  /// nada: sale un numero, y es mentira.
  ///
  /// Jose, 26/09/2026, cambiando a Camaguey: el Tablero decia «Sin colocar (0)»
  /// y a los dos minutos «(24)» mientras `GET /api/board` contestaba **40**.
  /// Comprobado pidiendoselo al servidor desde la propia pagina. Es el fallo que
  /// mas caro sale aqui, el del `CLAUDE.md` §4: un cero creible que ninguna
  /// pantalla desmiente.
  ///
  /// Olvidar el cursor y disparar el ciclo, en ese orden. Si se dispara primero,
  /// el ciclo lee el cursor viejo y la vuelta se pierde.
  ///
  /// **No se olvida `bajadaAt`**: esa marca dice «esto llego alguna vez aqui», y
  /// con ella puesta las pantallas siguen sabiendo distinguir «no lo tiene» de
  /// «todavia no ha bajado» mientras la bajada nueva corre.
  Future<void> _traerLaNueva() async {
    try {
      await ref.read(frescuraProvider).olvidarElCursor(Colecciones.todas);
      await ref.read(dispararCicloProvider)('cambio de sucursal');
    } on Object catch (e) {
      // Sin red se queda con lo que tiene y el vigia lo reintentara. Lo que no
      // puede es tumbar el cambio de sucursal, que ya esta hecho en la pantalla.
      Registro.aviso('no se pudo traer la sucursal nueva: $e');
    }
  }

  /// Vuelve a poner lo ultimo que se eligio. Se llama al entrar, con la base de
  /// esa persona ya abierta.
  Future<void> restaurar() async {
    try {
      state = await ref
          .read(baseProvider)
          .preferencia(ClaveDePreferencia.sucursalMirada);
    } on Object catch (e) {
      Registro.aviso('no se pudo recordar la sucursal mirada: $e');
    }
  }

  Future<void> _guardar(String clave, String? valor) async {
    try {
      await ref.read(baseProvider).anotarPreferencia(clave, valor);
    } on Object catch (e) {
      Registro.aviso('no se pudo anotar la sucursal mirada: $e');
    }
  }
}

final sucursalMiradaProvider = NotifierProvider<SucursalMirada, String?>(
  SucursalMirada.new,
);

ClienteApi _cliente(Ref ref, String baseUrl) => ClienteApi.montar(
  baseUrl: baseUrl,
  almacen: ref.watch(almacenSesionProvider),
  renovador: ref.watch(renovadorProvider),
  sucursalMirada: () => ref.read(sucursalMiradaProvider),
  // Cada intento cuenta para la salud de la red. Ver `anotarIntento`.
  alIntentar: ({required bool llego}) =>
      ref.read(saludDeLaRedProvider.notifier).anotarIntento(llego: llego),
  // Un 401 que sigue siendo 401 despues de renovar es lo UNICO que echa a
  // alguien a la pantalla de acceso. Un fallo de red, no.
  alMorirLaSesion: () => ref.read(porteroProvider).murio(),
  // Un 403 `sin_permiso_reparto`: la PERSONA no entra a Reparto. A su pantalla,
  // sin cerrar la sesion ni tocar la cola (`docs/sin-permiso.md`).
  alFaltarPermiso: () => ref.read(porteroProvider).sinPermiso(),
);

final clienteApiProvider = Provider<ClienteApi>(
  (ref) => _cliente(ref, Entorno.apiUrl),
);

final clienteSyncProvider = Provider<ClienteApi>(
  (ref) => _cliente(ref, Entorno.syncUrl),
);

/// LA ESCRITURA EN VIVO: **solo en la web**, y ahi siempre.
///
/// Es el unico sitio donde se decide, y por eso la decision es una linea:
/// `trabajaSinConexion` es `true` en la APK y en el escritorio —los que se van
/// al patio de un almacen con el dia dentro— y `false` en un navegador. Quien
/// escribe (`pantallas/rutas/datos/acciones_rutas.dart`,
/// `pantallas/tablero/datos/repositorio.dart`) no pregunta por el destino: le
/// llega esto o le llega `null`, y asi una prueba puede ejercitar los dos mundos
/// sin compilar para web.
///
/// El porque entero esta en `nucleo/red/escritura_en_vivo.dart`. En dos lineas:
/// la cola de la web sale por `/sync`, alli hace falta un aparato dado de alta,
/// en un navegador no hay par de tokens que dar de alta y el alta contestaba
/// 401 — asi que la web no escribia NADA y no lo decia.
final escrituraEnVivoProvider = Provider<EscrituraEnVivo?>(
  (ref) => ref.watch(trabajaSinConexionProvider)
      ? null
      : EscrituraEnVivo(ref.watch(clienteApiProvider)),
);

/// LA BAJADA DEL DIA. Se dispara al entrar y despues de subir la cola.
final bajadaProvider = Provider<Bajada>(
  (ref) => Bajada(
    cliente: ref.watch(clienteApiProvider),
    base: ref.watch(baseProvider),
    frescura: ref.watch(frescuraProvider),
    reloj: ref.watch(relojProvider),
  ),
);

final provisionalesProvider = Provider<Provisionales>(
  (ref) =>
      Provisionales(ref.watch(baseProvider), reloj: ref.watch(relojProvider)),
);

/// Las equivalencias `local-…` → id de verdad, EN VIVO.
///
/// Lo mira quien tenga un id provisional en la mano cuando ese id deja de
/// existir. Ver `Provisionales.mirar()` para el caso concreto.
final equivalenciasProvider = StreamProvider<Map<String, String>>(
  (ref) => ref.watch(provisionalesProvider).mirar(),
);

final colaProvider = Provider<ColaDeSalida>(
  (ref) => ColaDeSalida(
    ref.watch(baseProvider),
    reloj: ref.watch(relojProvider),
    provisionales: ref.watch(provisionalesProvider),
  ),
);

final frescuraProvider = Provider<RegistroDeFrescura>(
  (ref) => RegistroDeFrescura(
    ref.watch(baseProvider),
    reloj: ref.watch(relojProvider),
  ),
);

/// El alta de ESTA instalacion. Va contra `sync` porque el alta la da `sync`
/// (`POST /sync/aparato`) y el identificador lo pone el servidor, no el aparato.
final identidadDelAparatoProvider = Provider<IdentidadDelAparato>(
  (ref) => IdentidadDelAparato(
    ref.watch(baseProvider),
    sync: ref.watch(clienteSyncProvider),
    // Para quien no tiene sucursal propia —el Super Admin—, la del selector de
    // arriba. Se lee al llamar y no al construir: el alta puede pasar mucho
    // despues de que se monte esto.
    // Primero la del APARATO, que es donde esta; la que se mira es a donde
    // mira. Con «Todas» puesto, la mirada es `null` y el alta contestaba 400
    // «Falta la sucursal del aparato» con una ruta entera esperando a subir
    // (21/09/2026, telefono de Jose).
    sucursalElegida: () =>
        ref.read(sucursalDelAparatoProvider) ??
        ref.read(sucursalMiradaProvider),
  ),
);

/// LA SUBIDA DE LA COLA. Va contra `sync`, que es otro servicio y otra URL.
final subidaProvider = Provider<Subida>(
  (ref) => Subida(
    cliente: ref.watch(clienteSyncProvider),
    cola: ref.watch(colaProvider),
    aparato: ref.watch(identidadDelAparatoProvider),
    // Los dos siguientes son LA GUARDA de «la cola de A no sube con el token de
    // B». En web la sesion es la cookie y el almacen devuelve `null` siempre:
    // ahi no hay con que comparar y la guarda deja pasar, que es lo correcto
    // porque en un navegador no hay dos personas compartiendo una base.
    base: ref.watch(baseProvider),
    quienEsta: () async => (await ref.read(almacenSesionProvider).leer())?.sub,
    alFaltarPermiso: () => ref.read(porteroProvider).sinPermiso(),
  ),
);

/// Lo que hay en la base, contado. **De aqui salen los numeros que se ensenan
/// al acabar de traer el dia**, y no de lo que contesto el servidor.
final recontadorProvider = Provider<Recontador>(
  (ref) => Recontador(ref.watch(baseProvider), ref.watch(frescuraProvider)),
);

/// La PISTA de que hay red. Como provider para poder ponerla a `false` en una
/// prueba sin tocar el plugin.
final pistaDeRedProvider = Provider<PistaDeRed>((ref) => hayPistaDeRed);

/// El aviso de red, como provider para poder inyectarlo.
final avisosDeRedProvider = Provider<Stream<bool> Function()>(
  (ref) => avisosDeConnectivityPlus,
);

/// LO QUE DESPIERTA AL VIGIA, que NO es lo mismo que [avisosDeRedProvider].
///
/// Son dos preguntas parecidas y la diferencia costo cinco minutos por subida.
/// [avisosDeRedProvider] es la pista **para pintar**: si el aparato cree que hay
/// red, para no ensenar una rueda a quien no la tiene. Esto otro es para
/// **actuar**: cuando vuelve la salida, subir el dia sin esperar al reloj.
///
/// Medido en el telefono de Jose con la jornada entera dentro: volvia la senal y
/// la subida tardaba cinco minutos, que son exactamente
/// `VigiaDeSincronizacion.periodoPorDefecto`. O sea que no la disparaba la
/// senal. `connectivity_plus` avisa cuando cambia **a que estas enganchado**, y
/// eso en Cuba casi nunca cambia: el telefono se queda pegado al mismo wifi o a
/// los mismos datos y lo que se cae y vuelve esta aguas arriba.
///
/// Asi que se le junta el veredicto de Android —el mismo que enciende el icono
/// de wifi con la exclamacion—, que si se entera. Por que los DOS y no uno, y
/// por que da igual que dispare dos veces: en `juntarAvisosDeRed`.
///
/// Y es un provider propio, y no una linea dentro del vigia, para que una prueba
/// pueda sustituirlo entero — que es como se comprueba que sigue enganchado.
/// LO QUE DESPIERTA AL VIGIA.
///
/// Es el aviso de red de siempre ([avisosDeRedProvider]) y nada mas. Lo que
/// despierta de verdad cuando vuelve la conexion es **el canal**, que al
/// reconectar manda `avisoDeQueVolvimos` — y eso viaja por
/// [avisosDelServidorProvider], no por aqui.
///
/// ## AQUI ESTUVO ENGANCHADO EL VEREDICTO DE ANDROID, Y SE QUITO — 29/09/2026
///
/// Duro unas horas y costo caro. El veredicto nativo se engancho para que volver
/// la senal subiera el dia sin esperar al reloj, y resulto que Android manda uno
/// en **cada `onCapabilitiesChanged`** — que en datos moviles salta sin parar,
/// porque hasta la estimacion de ancho de banda cuenta como cambio. Medido en el
/// telefono de Jose ese mismo dia: ciclos cada 11, 17, 18, 36 y 38 segundos, con
/// un periodo de CINCO MINUTOS, a 3.255 bytes cada uno. **~1,4 MB por hora y por
/// aparato** para no traer nada.
///
/// Se le puso un suelo y funcionaba. Pero la pregunta buena la hizo Jose: «¿y ese
/// Kotlin, si estamos en Dart?». Y tenia razon —
///
///  * **el canal ya da esa misma senal**: cuando la red vuelve, el reintento del
///    canal conecta y manda `listo`, que sale como `avisoDeQueVolvimos`;
///  * lo unico que adelantaba el veredicto era **hasta un minuto**, que es el
///    tope de la espera creciente del canal;
///  * y era codigo nativo **que no se puede probar desde aqui**, que no corre en
///    la web ni en el escritorio, y que ya habia costado un fallo de datos.
///
/// Un minuto de adelanto no paga eso. El veredicto **sigue existiendo** y sigue
/// haciendo lo suyo —decir «sin conexion» cuando la wifi tiene el `!`, que es
/// para lo que se puso el 28/09—: lo que se quito es que dispare ciclos.
final avisosParaElVigiaProvider = Provider<Stream<bool> Function()>(
  (ref) => ref.watch(avisosDeRedProvider),
);

/// EL VEREDICTO DEL SISTEMA, en tres piezas inyectables.
///
/// Las tres son providers por lo mismo que las dos de arriba: el canal nativo no
/// existe en una prueba, y el temporizador de la ventana de sondeo tiene que
/// poder dispararlo la prueba a mano — un `Timer` de verdad dentro de una prueba
/// es una prueba que se cuelga en vez de fallar (`CLAUDE.md` §5).
final veredictoAhoraProvider = Provider<VeredictoAhora>(
  (ref) => veredictoDelSistemaAhora,
);
final avisosDeVeredictoProvider = Provider<AvisosDeVeredicto>(
  (ref) => avisosDelVeredictoDelSistema,
);
final crearEsperaDelSondeoProvider = Provider<CrearEspera>((ref) => Timer.new);

/// SI EL SISTEMA DICE QUE POR AQUI SE SALE A INTERNET, en vivo y ya filtrado.
///
/// Empieza por la pregunta de una vez y sigue con los avisos, igual que
/// [hayRedProvider] y por el mismo motivo: el caso del repartidor es **abrir la
/// aplicacion con la red ya muerta**, y ahi no hay ningun cambio que avisar.
///
/// Lo que sale de aqui ya pasó por la ventana de sondeo, asi que un «no valida»
/// de este stream es uno que se mantuvo. Ver `red/veredicto_del_sistema.dart`.
final veredictoDeLaRedProvider = StreamProvider<Veredicto>((ref) {
  final ahora = ref.watch(veredictoAhoraProvider);
  final avisos = ref.watch(avisosDeVeredictoProvider);
  Stream<Veredicto> crudos() async* {
    yield await ahora();
    yield* avisos();
  }

  return losQueSePuedenCreer(
    crudos(),
    crearEspera: ref.watch(crearEsperaDelSondeoProvider),
  );
});

/// SI EL APARATO CREE QUE HAY RED, en vivo.
///
/// Sirve **para decidir que ensenar**, no para decidir si se sale a la red. La
/// regla de `pubspec.yaml` no cambia —«PISTA de que hay red, nunca la verdad»—:
/// en Cuba el telefono ensena el wifi conectado y no sale un paquete. Lo que
/// esto permite es no ofrecerle a alguien, en el patio del almacen, un boton que
/// no puede funcionar; y cuando la pista se equivoque por el otro lado, el cajon
/// sigue estando a un toque y desde ahi se intenta de verdad.
///
/// Empieza por la pregunta de una vez y sigue con los avisos: sin lo primero, la
/// pantalla se quedaria sin saber nada hasta que la red cambiara.
final hayRedProvider = StreamProvider<bool>((ref) async* {
  yield await ref.watch(pistaDeRedProvider)();
  yield* ref.watch(avisosDeRedProvider)();
});

/// SI LAS PETICIONES ESTAN LLEGANDO. Es lo que decide el estado que se pinta,
/// y **no** `connectivity_plus` (ver `red/salud.dart`).
class LaSalud extends Notifier<SaludDeLaRed> {
  @override
  SaludDeLaRed build() {
    // EL «NO» DEL SISTEMA SE CREE AL MOMENTO — 22/09/2026.
    //
    // La pista de `connectivity_plus` no vale para decir que hay red —en Cuba
    // el teléfono enseña el wifi conectado y no sale un paquete—, pero su «no
    // hay ni interfaz» es del sistema operativo y no admite discusión. Sin
    // esto, con el modo avión puesto había que esperar a que tres peticiones se
    // cayeran: dos minutos con el Panel diciendo «Los datos son de ahora
    // mismo». Ver `SaludDeLaRed.sinInterfaz`.
    //
    // Y SE CREE TAMBIÉN AL NACER, no sólo al cambiar — 22/09/2026. El caso del
    // repartidor no es «se va la red con la aplicación abierta»: es **abrir la
    // aplicación con el modo avión ya puesto**, saliendo del almacén sin
    // cobertura. Ahí no hay ningún cambio que avisar, porque el sistema ya
    // estaba diciendo que no hay interfaz antes de que nadie preguntara; si esto
    // sólo escuchara los cambios, la salud nacería «bien» y se quedaría así
    // hasta que alguien pidiera algo y se cayera.
    //
    // Por eso el `fireImmediately`, y por eso lo de `naciendo`: durante `build`
    // TODAVÍA NO HAY `state`. Leerlo ahí dentro revienta con «Tried to read the
    // state of an uninitialized provider», y escribirlo no serviría de nada
    // porque el `return` de abajo lo pisaría. Así que mientras se nace, el
    // estado se lleva en la mano y se devuelve; después ya es `state`.
    var naciendo = true;
    var alNacer = SaludDeLaRed.bienDeSalida;

    // Las dos pistas del sistema cambian la salud igual, asi que se escribe una
    // sola vez lo de «mientras se nace, en la mano; despues, en `state`».
    void cambiar(SaludDeLaRed Function(SaludDeLaRed) como) {
      if (naciendo) {
        alNacer = como(alNacer);
        return;
      }
      state = como(state);
    }

    ref.listen<AsyncValue<bool>>(hayRedProvider, (_, ahora) {
      final hay = ahora.value;
      if (hay == null) return;
      cambiar((salud) => hay ? salud.conInterfaz() : salud.sinRed());
    }, fireImmediately: true);

    // EL «!» DEL ICONO DEL WIFI — 28/09/2026.
    //
    // La otra cosa que el sistema sabe y nosotros no: si esta red LLEGA a
    // internet. Jose, con el telefono enganchado a un wifi sin salida: «me esta
    // diciendo eso q tengo conexion y no tengo conexion ahora mismo q mierda es
    // eso por q la wifi no esta dando internet». Sin esto habia que esperar a
    // que se cayeran tres ciclos: dos minutos y medio de «Todo al dia» con el
    // telefono sin internet. Ver `red/veredicto_del_sistema.dart`.
    ref.listen<AsyncValue<Veredicto>>(veredictoDeLaRedProvider, (_, ahora) {
      switch (ahora.value) {
        case Veredicto.noValida:
          cambiar((salud) => salud.sinSalidaAInternet());
        case Veredicto.valida:
          // Solo APAGA la bandera. Que Android valide una red no dice que
          // nuestro servidor conteste; eso lo sigue diciendo una peticion.
          cambiar((salud) => salud.conSalidaAInternet());
        case Veredicto.sinRed:
          // NO TOCA NADA, y es a proposito. «No hay red» ya lo dice `sinInterfaz`
          // por el otro camino; apagar aqui la bandera de salida dejaria un hueco
          // —el instante entre que se pierde la red y `connectivity_plus` se
          // entera— con el aviso quitado sin que nadie tenga salida.
          break;
        case Veredicto.noLoSe:
        case null:
          // Windows, Linux y la web contestan esto SIEMPRE. No es «va mal», es
          // «aqui no hay nada que preguntar», y por eso no enciende ni apaga
          // nada: lo contrario dejaria el escritorio con el aviso puesto para
          // siempre. `null` es el `AsyncLoading` del arranque, lo mismo.
          break;
      }
    }, fireImmediately: true);

    naciendo = false;
    return alNacer;
  }

  /// Lo llama el ciclo al acabar, TODOS los ciclos — tambien los que dispara el
  /// vigia sin que nadie mire, que son los que de verdad dicen si la conexion
  /// sirve.
  void anotar(ResumenDelCiclo resumen) {
    // Sin sesion no se intento nada: eso no dice nada de la red.
    if (resumen.sinSesion) return;

    final fallo = resumen.fallo;

    // El fallo DE RED es el unico que cuenta en contra. `ContestoOtroServidor`
    // —el wifi que contesta su propia pagina— hereda de `FalloDeRed`, asi que
    // entra por aqui sin nombrarlo.
    if (fallo is FalloDeRed) {
      state = state.conUnaMala();
      return;
    }

    // DAR LA RED POR BUENA PIDE UNA PRUEBA, NO LA FALTA DE UNA — 28/09/2026.
    //
    // Esto era `fallo is FalloDeRed ? mala : buena`, y ese `else` se tragaba
    // TODO lo que no fuera red: un parseo que revienta, una excepcion de la
    // base local, un `TypeError` del `as T` de `cliente_api.dart`… todos
    // decian «la conexion sirve» y borraban el aviso que ya estaba puesto.
    // Ninguno de ellos ha visto un paquete llegar.
    //
    // Lo que SI es prueba de que la peticion llego son tres cosas y se nombran
    // una a una: el ciclo entero salio bien, el servidor dijo que no
    // (`Rechazo`), o el servidor dijo que esta sesion ya no vale
    // (`SesionMuerta`). **El 401 se queda dentro a proposito**: sigue estando
    // documentado en `red/fallos.dart` que una sesion muerta no es una red
    // muerta, y contarla como caida mandaria a mirar el wifi por un problema
    // de la puerta.
    if (fallo == null || fallo is Rechazo || fallo is SesionMuerta) {
      state = state.conUnaBuena(ref.read(relojProvider)());
      return;
    }

    // Y lo demas NO MUEVE NADA, ni a bien ni a mal. Contarlo como caida seria
    // poner «sin conexion» por un fallo de programacion con la red perfecta, y
    // un aviso que salta en falso deja de leerse (`CLAUDE.md` §3-quinquies).
    // Quien de verdad sabe si los paquetes llegan es `anotarIntento`, que cuenta
    // peticion a peticion.
    Registro.aviso(
      'el ciclo cayó por algo que no dice nada de la red: '
      '${fallo.runtimeType}. La salud no se toca.',
    );
  }

  /// UN INTENTO SUELTO, no un ciclo entero.
  ///
  /// Lo llama `ClienteApi` en cada peticion. Contando ciclos hacian falta
  /// minutos para decir «sin conexion»; contando intentos, los tres que hacen
  /// falta caben dentro de UN ciclo, porque cada peticion reintenta a 1 s, 4 s
  /// y 10 s. El aviso pasa de varios minutos a menos de medio.
  ///
  /// El motivo por el que hacen falta tres y no uno sigue en pie y esta escrito
  /// en `SaludDeLaRed.fallosParaDarlaPorMala`: un aviso que parpadea con cada
  /// paquete perdido deja de leerse.
  void anotarIntento({required bool llego}) {
    state = llego
        ? state.conUnaBuena(ref.read(relojProvider)())
        : state.conUnaMala();
  }
}

final saludDeLaRedProvider = NotifierProvider<LaSalud, SaludDeLaRed>(
  LaSalud.new,
);

/// POR DONDE VA el ciclo que corre ahora, para quien lo este mirando.
///
/// Lo alimenta [cicloProvider] y lo mira el boton de traer el dia. Esta aqui
/// —y no en la pantalla— porque el candado de «uno en vuelo» hace que el ciclo
/// que mira el boton pueda ser uno que arranco el vigia: si la pantalla se
/// inventara su propia marcha, ese ciclo correria sin que se viera.
class MarchaDelCiclo extends Notifier<Marcha> {
  @override
  Marcha build() => Marcha.quieto;

  void empieza(DateTime cuando) {
    // Si ya hay uno en vuelo **no se reinicia el cronometro**: el segundo aviso
    // se engancha al ciclo que ya va (el candado esta en `ciclo.dart`), y poner
    // la cuenta a cero enseñaria 2 s de algo que lleva cuarenta.
    if (state.enVuelo) return;
    state = Marcha(empezadoA: cuando);
  }

  void avanza(AvanceDelCiclo avance) =>
      state = Marcha(empezadoA: state.empezadoA, avance: avance);

  void termina() => state = Marcha.quieto;
}

final marchaDelCicloProvider = NotifierProvider<MarchaDelCiclo, Marcha>(
  MarchaDelCiclo.new,
);

/// EL LATIDO DEL INTENTO: un tic mientras hay un ciclo en vuelo, y nada cuando
/// no lo hay.
///
/// Existe por un motivo concreto. La tarjeta del Panel deja de decir «Enviando
/// datos...» cuando el intento pasa de medio minuto (`pacienciaDelIntento`),
/// pero eso es una comparacion contra el reloj: **sin nada que redibuje, la
/// pantalla no se entera de que el tiempo paso**. Y justo en ese caso no hay
/// nada que la redibuje, porque un ciclo atascado contra una red muerta no
/// avanza de coleccion ni de tanda.
///
/// Cinco segundos: bastante fino para que el aviso salga a los 30 s y no a los
/// 60, y bastante grueso para no repintar por gusto. **No corre cuando no hay
/// ciclo**: un temporizador eterno en una aplicacion que vive todo el dia
/// abierta en el patio de un almacen se nota en la bateria.
final latidoDelIntentoProvider = StreamProvider<DateTime>((ref) {
  if (!ref.watch(marchaDelCicloProvider).enVuelo) {
    return const Stream<DateTime>.empty();
  }
  final reloj = ref.watch(relojProvider);
  return Stream<DateTime>.periodic(const Duration(seconds: 5), (_) => reloj());
});

/// LO QUE ESTE APARATO TIENE Y ARRIBA NO, sin preguntarle nada al servidor.
///
/// Se lee de la base local a proposito: la pregunta hay que poder contestarla
/// **sin conexion**, que es justo cuando se acumula el trabajo. Ver
/// `nucleo/sincro/huerfanos.dart`.
final huerfanosProvider = Provider<Huerfanos>(
  (ref) => Huerfanos(ref.watch(baseProvider)),
);

/// LO HUERFANO, YA CONTADO Y LISTO PARA PINTARLO. **Esto es la mitad que
/// faltaba.**
///
/// `huerfanos.dart` dice, palabra por palabra, que lo que el desatasco no sabe
/// rehacer «se cuenta y se dice». Contar se contaba: `Huerfanos.mirar()` estaba
/// escrito, probado y **no lo llamaba nadie en `lib/`**. El unico que tocaba
/// `huerfanosProvider` era el ciclo, y solo para `volverAEncolar`, que hoy
/// unicamente sabe reconstruir las zonas del tablero.
///
/// O sea: una RUTA armada sin señal cuyo apunte se perdio existia en el
/// telefono, no existia arriba, no la subia nadie **y no salia en ninguna
/// pantalla**. El repartidor la veia en su aparato y la daba por hecha. Es la
/// zona «Vista» del 16/09/2026 otra vez, con la diferencia de que esta ni
/// siquiera se desatasca sola.
///
/// Lo tenia apuntado el propio repo: la prueba `HALLAZGO ·` de
/// `test/nucleo/sincro/jornada_entera_sin_senal_test.dart` afirmaba ese
/// comportamiento y pedia que se le diera la vuelta el dia que se arreglara.
/// Esto es ese dia.
///
/// **Stream y no Future** (§3-ter). Lo huerfano aparece justo cuando nadie esta
/// preguntando: un apunte se descarta a mano desde la bandeja, o se pierde, y en
/// ese instante la fila local se queda sin nada que la suba. Un `Future` se leia
/// al pintar y no se enteraba nunca — que es exactamente el fallo del §4-bis,
/// «una guarda que solo se recalcula al bajar la foto no se entera de lo que
/// pasa despues».
///
/// Se vigila `apuntes` ademas de las tablas de datos porque **estar huerfano es
/// una propiedad de la cola**, no de la fila: la fila no cambia, lo que cambia
/// es que deja de quedarle un apunte vivo detras.
///
/// **Se vigilan tambien las dos tablas del Tablero** (24/09/2026). No son de
/// Drift —las crea la pantalla— asi que van por nombre; sus escrituras si
/// avisan, con `EsquemaTablero.avisarDeCambio`. Sin ellas, una zona que se
/// quedaba huerfana no salia hasta el tic siguiente del ciclo.
///
/// **En la web sale vacio siempre y no hace falta apagarlo:** alli no se escribe
/// una fila hasta que el servidor la acepta, los ids son los suyos y
/// `nacio_aqui` vale 0 (`pantallas/tablero/datos/repositorio.dart`), asi que no
/// hay nada que pueda quedarse huerfano. Lo vigila
/// `la_web_coloca_de_verdad_test.dart`.
/// Las dos tablas del Tablero, por nombre. Ver [trabajoHuerfanoProvider].
const tablaDeZonasDelTablero = 'board_columns';
const tablaDeTarjetasDelTablero = 'board_placements';

final trabajoHuerfanoProvider = StreamProvider<List<TrabajoHuerfano>>((ref) {
  final base = ref.watch(baseProvider);
  final huerfanos = ref.watch(huerfanosProvider);

  return () async* {
    yield await huerfanos.mirar();
    yield* base
        .tableUpdates(
          TableUpdateQuery.allOf([
            // LA COLA PRIMERO: es la que convierte una fila normal en una
            // huerfana al quedarse sin su apunte.
            TableUpdateQuery.onTable(base.apuntes),
            TableUpdateQuery.onTable(base.equivalencias),
            TableUpdateQuery.onTable(base.routes),
            TableUpdateQuery.onTable(base.vehicles),
            TableUpdateQuery.onTable(base.warehouses),
            // Y LAS DEL TABLERO, QUE NO SON DE DRIFT.
            //
            // Las crea la propia pantalla (`pantallas/tablero/datos/
            // esquema.dart`), asi que aqui no hay objeto que pasar y van por
            // nombre. Los cambios SI se anuncian —`EsquemaTablero.avisarDeCambio`
            // hace `notifyUpdates` despues de cada escritura de verdad—, que es
            // lo que hace que esto funcione; lo que no avisa es un
            // `customStatement` suelto, y eso pasa en una prueba, no en la
            // aplicacion.
            //
            // Los nombres van escritos porque `nucleo/` no depende de
            // `pantallas/`. Estan atados a los de `EsquemaTablero` por una
            // prueba y no por un comentario (§3-bis), igual que los mira
            // `Huerfanos._dondeMirar`.
            TableUpdateQuery.onTableName(tablaDeZonasDelTablero),
            TableUpdateQuery.onTableName(tablaDeTarjetasDelTablero),
            // Y LO QUE UNA PERSONA DA POR PERDIDO. Tampoco es de Drift —la crea
            // `BaseLocal` al abrir— y `Huerfanos.darPorPerdido` avisa a mano.
            // Sin vigilarla, se pulsa el boton y el aviso ambar sigue puesto:
            // se lee como que no ha servido de nada.
            TableUpdateQuery.onTableName(tablaDeRenuncias),
          ]),
        )
        .asyncMap((_) => huerfanos.mirar());
  }();
});

/// LA ULTIMA BAJADA QUE VOLVIO A MEDIAS, con su motivo LITERAL. `null` = entera.
///
/// `ResumenDeBajada.quedoPor` existia y lo leia **un solo sitio**:
/// `navegacion/portero.dart`, o sea la configuracion inicial. Cualquier ciclo
/// posterior —el del vigia, el del aviso del canal, el de volver al primer
/// plano— podia volver con 2.000 clientes de 8.034 y no decirlo en ninguna
/// pantalla: solo un `Registro.fallo` en un log que nadie abre. Era el §3
/// cumplido el primer dia y en ningun otro.
///
/// El motivo va tal cual viene de `bajada.dart` —«se llego al tope de N tandas y
/// el servidor seguia diciendo que queda mas»— porque es lo unico que dice que
/// pasó. «No se pudo traer todo» no le sirve a nadie.
class LaBajadaAMedias extends Notifier<String?> {
  @override
  String? build() => null;

  void anotar(ResumenDelCiclo resumen) {
    // UNA VUELTA QUE NI LLEGO A BAJAR NO BORRA EL AVISO ANTERIOR.
    //
    // Si el ciclo muere antes de bajar —sin red, sesion caida— viene con
    // `ResumeDeBajada.nada`, y `nada.quedoPor` es `null`. Creerselo apagaria el
    // aviso de la bajada truncada de antes, que **sigue siendo verdad**: al
    // aparato le siguen faltando esos clientes. Que no haya red ya se dice por
    // su lado.
    if (resumen.bajada.tandas == 0) return;
    state = resumen.bajada.quedoPor;
  }
}

final bajadaAMediasProvider = NotifierProvider<LaBajadaAMedias, String?>(
  LaBajadaAMedias.new,
);

/// EL CICLO: comprobar la diferencia → renovar → subir → bajar. Uno solo en toda la aplicacion, porque el
/// candado de «un solo ciclo en vuelo» vive dentro: dos instancias son dos
/// candados, y dos candados no son ninguno.
/// DISPARAR UN CICLO, como funcion suelta.
///
/// Existe por lo mismo que el vigia recibe `ciclo:` en vez de leer el provider:
/// [CicloDeSincronizacion] es una clase concreta con cinco piezas dentro, asi
/// que montarla en una prueba obliga a montar la subida, la bajada, el
/// renovador y los huerfanos para comprobar una sola cosa — y entonces la
/// prueba deja de probar lo que dice y pasa a probar el montaje.
///
/// Lo usa [SucursalMirada], que al cambiar de sucursal tiene que olvidar el
/// cursor **y luego** bajar, en ese orden.
final dispararCicloProvider = Provider<Future<void> Function(String motivo)>(
  (ref) =>
      (motivo) => ref.read(cicloProvider).ahora(motivo: motivo),
);

final cicloProvider = Provider<CicloDeSincronizacion>(
  (ref) => CicloDeSincronizacion(
    almacen: ref.watch(almacenSesionProvider),
    renovador: ref.watch(renovadorProvider),
    subida: ref.watch(subidaProvider),
    bajada: ref.watch(bajadaProvider),
    // Quien comprueba la DIFERENCIA entre lo que este aparato tiene y lo que hay
    // arriba. Va dentro del ciclo porque es trabajo del sincronizador, no de una
    // pantalla: tiene que pasar solo en cuanto haya señal.
    huerfanos: ref.watch(huerfanosProvider),
    cola: ref.watch(colaProvider),
    // Quien sabe si hay sesion es el portero, y no el almacen: en web el almacen
    // devuelve `null` SIEMPRE porque alli la sesion es la cookie. Preguntarle a
    // el dejaria la web sin sincronizar nunca.
    //
    // La regla de QUE estados cuentan vive en `haySesionParaSincronizar`, con
    // nombre y probada suelta: escrita a mano aqui ya costo un fallo que dejaba
    // la configuracion inicial en el 0 % para siempre.
    haySesion: () => haySesionParaSincronizar(ref.read(porteroProvider).estado),
    alMorirLaSesion: () => ref.read(porteroProvider).murio(),
    // El giro de la barra superior. Es un contador, asi que dos ciclos
    // solapados no se apagan el uno al otro.
    alEmpezar: () {
      ref.read(enVueloProvider.notifier).empieza();
      ref
          .read(marchaDelCicloProvider.notifier)
          .empieza(ref.read(relojProvider)());
    },
    alTerminar: () {
      ref.read(enVueloProvider.notifier).termina();
      ref.read(marchaDelCicloProvider.notifier).termina();
    },
    alAvanzar: (avance) =>
        ref.read(marchaDelCicloProvider.notifier).avanza(avance),
    alAcabar: ref.watch(alAcabarElCicloProvider),
  ),
);

/// LO QUE SE ANOTA CUANDO UN CICLO ACABA. **Son tres, y las tres hacen falta.**
///
/// Va como provider con nombre y no como una lambda dentro de [cicloProvider]
/// por el mismo motivo que `haySesionParaSincronizar`: escrito a pelo ahi
/// dentro no hay forma de probarlo sin montar el ciclo entero —con su red, su
/// sesion y su portero—, y lo que no se puede probar se queda a medias sin que
/// nadie lo note.
///
///  * **La salud de la red** decide lo que dice la franja de arriba.
///  * **La primera bajada** es lo que hace que la web deje de decir «cargando».
///    Da igual si el ciclo salio bien o mal: lo que este aviso cierra es el
///    «todavia no se sabe» con el que nace la web en cada carga de la pagina
///    (`frescura/primera_bajada.dart`). Sin esto, una bajada que falla de verdad
///    dejaria una rueda girando sin fin — que es peor que el mensaje falso que
///    todo esto vino a quitar.
///  * **La bajada a medias** es lo unico que dice, fuera del primer arranque,
///    que el aparato se quedo con la mitad de los clientes.
final alAcabarElCicloProvider = Provider<void Function(ResumenDelCiclo)>(
  (ref) => (resumen) {
    ref.read(saludDeLaRedProvider.notifier).anotar(resumen);
    ref.read(primeraBajadaProvider.notifier).anotar(resumen);
    // **Y LA TERCERA, desde el 24/09/2026.** Una bajada que vuelve a medias lo
    // decia SOLO la configuracion inicial; los ciclos de despues —que son casi
    // todos— se lo callaban. Ver [bajadaAMediasProvider].
    ref.read(bajadaAMediasProvider.notifier).anotar(resumen);
  },
);

/// LO QUE CAMBIO EN EL SERVIDOR, para quien quiera enterarse. UN solo canal.
///
/// Es de DIFUSION —`asBroadcastStream`— porque lo escuchan dos: el vigia, que
/// dispara un ciclo de sincronizacion, y el Tablero, que vuelve a pedir su foto.
/// Con un canal por oyente serian dos conexiones abiertas contra el servidor para
/// traer exactamente lo mismo.
///
/// ## Y hacen falta los DOS, que fue el fallo — 17/09/2026
///
/// Al principio sólo lo escuchaba el vigia, y parecia razonable: llega el aviso,
/// se dispara el ciclo, se baja todo. **Pero el tablero no viaja en el ciclo**: la
/// bajada por diferencias (`/sync/cambios`) sirve pedidos, clientes, rutas y
/// catalogo, y las zonas se piden aparte con `GET /api/board`, que sólo se llama
/// al abrir la pantalla.
///
/// Asi que el canal funcionaba —el servidor registraba la conexion abierta— y en
/// la pantalla no pasaba nada. Se comprobo con el telefono delante: la zona subia
/// con un 201 y la web seguia igual hasta que pasaba el temporizador.
/// COMO SE ABRE EL CANAL. Se pasa por un proveedor para poder cambiarlo en una
/// prueba: la funcion de verdad va contra `Entorno.apiUrl`, que es una constante
/// de compilacion y no se puede sustituir.
final escuchaDeEventosProvider = Provider<EscuchaDeEventos>(
  (ref) => escucharEventos,
);

/// EL PULSO DEL CANAL: «sigo vivo», y nada mas.
///
/// Uno solo para toda la aplicacion, porque hay un solo canal. Lo marca el
/// transporte con cada señal que llega —el latido de cada veinte segundos
/// incluido— y lo lee el vigia para callar el reloj. **No es un stream a
/// proposito**: por el stream de los avisos cada cosa que pasa cuesta una bajada,
/// y un latido cada veinte segundos ahi seria el polling que esto vino a quitar.
/// Todo el porque, en [PulsoDelCanal].
final pulsoDelCanalProvider = Provider<PulsoDelCanal>(
  (ref) => PulsoDelCanal(reloj: ref.read(relojProvider)),
);

final avisosDelServidorProvider = Provider<Stream<String>>((ref) {
  // ## SE ABRE AL PRIMER OYENTE Y SE VUELVE A ABRIR SI VUELVEN — 17/09/2026
  //
  // Antes esto era `escucharEventos(…).asBroadcastStream()`, y tenia un agujero
  // que no se ve hasta que alguien sale y vuelve a entrar **sin cerrar la
  // aplicacion**: al cerrar sesion el vigia cancela su suscripcion, el
  // `asBroadcastStream` suelta la de abajo, y al volver a entrar el proveedor —
  // que es el mismo objeto, un `Provider` no se reconstruye— devuelve el mismo
  // stream, que ya **no vuelve a abrir nada**. Ni error, ni aviso: la pantalla
  // se queda con el temporizador, cinco minutos en el aparato, y nadie sabe por
  // que. Comprobado: re-escuchar no lanza, simplemente no llama a `onListen`.
  //
  // Con un controlador de difusion el ciclo se cierra bien: al primer oyente se
  // abre el canal, al ultimo que se va se suelta —conexion incluida— y si
  // vuelven se abre otra vez.
  StreamSubscription<String>? fuente;
  /// Cuando salio el ultimo «volví». Ver `sueloEntreVolver`.
  DateTime? ultimoVolver;
  final control = StreamController<String>.broadcast();
  control
    ..onListen = () {
      fuente = ref
          .read(escuchaDeEventosProvider)(
            Entorno.apiUrl,
            () async => (await ref.read(almacenSesionProvider).leer())?.token,
            // QUE UN 401 NO MATE EL CANAL PARA TODA LA SESION — 17/09/2026
            //
            // El token de acceso dura quince minutos. Sin esto, el primer 401 del
            // canal lo cerraba hasta que alguien cerrara y volviera a abrir la
            // aplicacion — y en el registro de produccion hay `401 GET
            // /api/eventos` de verdad.
            //
            // Es el `Renovador` de siempre, con su candado de una sola renovacion
            // en vuelo: si el ciclo esta renovando en este mismo instante, esta
            // llamada reutiliza su resultado en vez de gastar otro refresh. Los
            // frenos para que esto no sea un bucle estan en `red/eventos_io.dart`.
            renovarSesion: () async {
              final guardada = await ref.read(almacenSesionProvider).leer();
              if (guardada == null) {
                // Sin par guardado no hay nada que renovar desde aqui. Lanzar es
                // lo que cierra el canal, que es justo lo que toca.
                throw const SesionMuerta(
                  '401 en el canal de eventos y no hay sesión que renovar',
                );
              }
              await ref.read(renovadorProvider).renovar(guardada);
            },
            // LO QUE DICE QUE EL CANAL VIVE, y que NO pasa por este stream. Ver
            // `pulsoDelCanalProvider`.
            pulso: ref.read(pulsoDelCanalProvider),
          )
          .listen(
            (tipo) {
              // EL SUELO DEL «volví» — 29/09/2026.
              //
              // Va aqui y no en cada transporte porque este es el unico embudo
              // por el que pasan los dos: escribirlo dos veces es tenerlo
              // distinto dentro de un mes.
              //
              // Lo que cierra: un servidor que acepta, manda el `listo` y se
              // muere reinicia la espera creciente, asi que reconecta al
              // segundo — y cada vuelta costaria un ciclo entero, un
              // `GET /api/board` por tablero abierto y la flota por cada
              // pantalla de vehiculos. Cientos de peticiones por minuto contra
              // un servidor que ya se esta cayendo. El porque entero, en
              // `sueloEntreVolver`.
              if (tipo == avisoDeQueVolvimos) {
                final ahora = ref.read(relojProvider)();
                final antes = ultimoVolver;
                if (antes != null &&
                    ahora.difference(antes) < sueloEntreVolver) {
                  // NO EN SILENCIO: el dia que alguien se pregunte por que una
                  // pantalla no se refresco, esto lo explica.
                  Registro.info(
                    'canal de eventos: se reconectó otra vez en menos de '
                    '${sueloEntreVolver.inSeconds} s, no se reenvía el «volví»',
                  );
                  return;
                }
                ultimoVolver = ahora;
              }
              control.add(tipo);
            },
            // El canal no lanza nunca, pero si algun dia lanzara no puede
            // tumbar al vigia: queda el temporizador.
            onError: (Object e) =>
                Registro.aviso('canal de eventos: se cayó el canal: $e'),
            cancelOnError: false,
          );
    }
    ..onCancel = () async {
      // NO QUEDA NADA VIVO cuando se va el ultimo: ni la suscripcion ni la
      // conexion que hay debajo.
      final s = fuente;
      fuente = null;
      await s?.cancel();
    };
  ref.onDispose(() {
    unawaited(fuente?.cancel());
    fuente = null;
    unawaited(control.close());
  });
  return control.stream;
});

/// EL VIGIA: el aviso de red y el reloj. Lo arranca y lo para `app.dart` segun
/// lo que diga el portero — nada vivo sin sesion.
final vigiaProvider = Provider<VigiaDeSincronizacion>((ref) {
  final vigia = VigiaDeSincronizacion(
    ciclo: (motivo, avisoDe) =>
        ref.read(cicloProvider).ahora(motivo: motivo, avisoDe: avisoDe),
    avisosDeRed: ref.watch(avisosParaElVigiaProvider),
    // LO QUE ENTRA EN LA COLA SE INTENTA SUBIR YA, sin esperar al reloj. Se
    // escucha la tabla y no se avisa desde quien encola: asi entra cualquier
    // gesto, lo escriba quien lo escriba, y la cola no tiene que saber nada del
    // ciclo —que ademas seria un ciclo de dependencias, porque el ciclo necesita
    // la cola—.
    avisosDeLaCola: () => ref
        .read(baseProvider)
        .tableUpdates(TableUpdateQuery.onTable(ref.read(baseProvider).apuntes)),
    // EL CANAL EN VIVO. Lo que cambia en el servidor se sabe en cuanto cambia, en
    // vez de esperar al reloj —dos minutos en la web, cinco en la APK—.
    //
    // Es una MEJORA y no un cimiento: donde no hay canal devuelve un stream
    // vacío y manda el temporizador, que es lo que había. Ver `red/eventos.dart`.
    avisosDelServidor: () => ref.read(avisosDelServidorProvider),
    // EL LATIDO, que no viaja por el stream de arriba. Sin esto, un canal sano
    // por el que no ha cambiado nada en seis minutos se lee como canal muerto y
    // el reloj pide la vuelta entera: el polling seguia ahi, sólo que mas
    // espaciado. Ver `VigiaDeSincronizacion.elCanalSeDaPorVivo`.
    pulso: ref.read(pulsoDelCanalProvider),
    // EL RITMO, segun el destino. En web es lo UNICO que trae los cambios —alli
    // no queda ni un gesto para traer el dia a mano—, asi que va mas seguido; en
    // la APK cada tic se paga en bateria y datos por la conexion de alla. El
    // porque de cada numero, en `vigia.dart`.
    periodo: ref.read(trabajaSinConexionProvider)
        ? VigiaDeSincronizacion.periodoPorDefecto
        : VigiaDeSincronizacion.periodoEnWeb,
    reloj: ref.read(relojProvider),
    // LO QUE ACOTA EL VOLVER AL PRIMER PLANO. Sin esto, cada alt-tab es un ciclo
    // entero y la barra superior dice «actualizando…» sin parar.
    //
    // Las dos preguntas son de una sola consulta cada una y ninguna es un
    // stream: aqui no hay nada que pintar, y un `await` sobre el primer valor de
    // un stream de Drift lo deja abierto detras.
    loQueHay: () async => EstadoDeLoQueHay(
      bajadaAt: await ref.read(frescuraProvider).laMasViejaAhora(),
      sinSubir: await ref.read(colaProvider).cuantosQuedanTras(0),
    ),
  );
  ref.onDispose(vigia.parar);
  return vigia;
});

/// Cuantos apuntes quedan EN LA COLA esperando a subir. Lo pinta el
/// `RelojDeDatos`, y ahi ese es el numero bueno: es el que baja a cero cuando
/// uno entrega el dia. **No cuenta los rechazados**, que tienen su propia
/// bandeja y no se arreglan con señal.
final sinSubirProvider = StreamProvider<int>(
  (ref) => ref.watch(colaProvider).pendientes().map((lista) => lista.length),
);

/// LO QUE SUBIO Y AUN ASI SALIO CON MENOS: los descartados del servidor.
///
/// Tercera pregunta, distinta de las otras dos y por eso su propio proveedor:
/// [sinSubirProvider] es lo que todavia no ha salido del aparato, la bandeja es
/// lo que el servidor rechazo entero, y esto es **un apunte que entro dejando
/// gente fuera** — armar una zona de doce y que salgan nueve.
///
/// Vive en `nucleo/` y no en la pantalla del cajon porque lo miran dos sitios:
/// el cajon, que lo cuenta entero, y la franja de estado, que esta en las siete
/// pantallas y es lo unico que hace que alguien abra el cajon. Ver
/// `ColaDeSalida.descartesSinLeer`.
final descartadosProvider = StreamProvider<List<Apunte>>(
  (ref) => ref.watch(colaProvider).descartesSinLeer(),
);

/// TRABAJO QUE NO ESTA ARRIBA, contando **tambien los rechazados**.
///
/// No es lo mismo que [sinSubirProvider] y la diferencia importa justo antes de
/// hacer algo irreversible: instalar una version nueva encima, o borrar una
/// copia. Un apunte rechazado es trabajo que **no llego al servidor** —es lo
/// unico que queda de un cierre que no entro— y con la pregunta estrecha contaba
/// cero. Ver `BaseLocal.cuantosSinSubir`.
final sinSubirDeVerdadProvider = StreamProvider<int>((ref) {
  final base = ref.watch(baseProvider);
  return () async* {
    yield await base.cuantosSinSubir();
    yield* base
        .tableUpdates(TableUpdateQuery.onTable(base.apuntes))
        .asyncMap((_) => base.cuantosSinSubir());
  }();
});

/// El cliente con el que se mira la versión, aparte del de las pantallas.
///
/// Es OTRO `ClienteApi` y no el de siempre por una sola razón: `sinEsperas`. El
/// de las pantallas reintenta 1 s, 4 s, 15 s y 60 s, que es lo correcto para el
/// trabajo de alguien y lo peor posible para una comprobación de versión al
/// arrancar — ochenta segundos de espera para averiguar algo que puede esperar a
/// mañana.
final clienteVersionProvider = Provider<ClienteApi>(
  (ref) => ClienteApi.montar(
    baseUrl: Entorno.apiUrl,
    almacen: ref.watch(almacenSesionProvider),
    renovador: ref.watch(renovadorProvider),
    esperas: ComprobadorDeActualizacion.sinEsperas,
  ),
);

final comprobadorProvider = Provider<ComprobadorDeActualizacion>(
  (ref) => ComprobadorDeActualizacion(
    cliente: ref.watch(clienteVersionProvider),
    base: ref.watch(baseProvider),
  ),
);

/// El aviso de versión nueva, para que lo mire la pantalla.
///
/// `FutureProvider` y no algo que se dispare solo: se comprueba cuando alguien
/// lo mira, UNA vez por arranque. Para volver a mirar —después de subir la cola,
/// por ejemplo— se invalida este provider. Ver `docs/actualizaciones.md`.
///
/// **Quién lo mira:** `navegacion/aviso_de_version_nueva.dart`, montado en el
/// armazón, o sea en todas las pantallas. Y **sólo en la APK y en el
/// escritorio**: en la web `comprobar()` devuelve `NoAplica` en la primera línea
/// sin llamar siquiera al servidor, porque allí una versión nueva no se instala,
/// se recarga — y eso lo mira otra cosa (`hayPaqueteNuevoProvider`, la huella
/// del paquete).
///
/// **Y quién lo invalida:** ese mismo fichero, cuando la cola de salida llega a
/// cero teniendo el aviso puesto en `PrimeroSube`. Sin eso, un «sube primero» se
/// queda pegado hasta el siguiente arranque después de que la persona hizo justo
/// lo que se le pidió. No se invalida en cada movimiento de la cola: sería una
/// petición de red por cada apunte que sube para preguntar algo cuya respuesta
/// no ha cambiado.
final actualizacionProvider = FutureProvider<EstadoDeActualizacion>(
  (ref) => ref.watch(comprobadorProvider).comprobar(),
);
