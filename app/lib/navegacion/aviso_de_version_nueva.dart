/// EL AVISO DE QUE HAY VERSION NUEVA. En el armazon, o sea en todas las
/// pantallas.
///
/// ## Por que existe
///
/// Del patron (`delivery`, `src/lib/version-nueva.ts`), que lo dice mejor de lo
/// que se diria aqui:
///
/// > Una pestaña abierta sigue ejecutando el JavaScript que bajo el dia que se
/// > abrio. Aqui las pestañas viven abiertas dias enteros —el armador de rutas,
/// > el panel— y un dia con varios despliegues significa trabajar con codigo de
/// > hace varias versiones sin enterarse. **No se ve como «version vieja»: se ve
/// > como un filtro que no esta, un boton que no hace nada o un arreglo que no
/// > llego.**
///
/// Eso es lo caro: nadie abre un aviso, nadie llama a la oficina. Se trabaja
/// mal y se apunta a otra cosa.
///
/// ## LOS TRES DESTINOS NO DICEN LO MISMO, y no es un detalle de redaccion
///
/// `CLAUDE.md` §1: son tres formas de la misma aplicacion y no se comportan
/// igual. Aqui se nota entero, porque **lo que hay que hacer es distinto**:
///
///  * **La web**: el paquete lo sirve el servidor y no hay nada instalado. Lo
///    unico que hace falta es **recargar**, y eso lo resuelve la propia pestaña
///    en dos segundos. No hay cola que perder —la web no tiene base local
///    (§1)—, asi que recargar no arriesga absolutamente nada. Se dice
///    «Recargar ahora».
///  * **La APK y el escritorio**: ahi no se recarga nada. Hay que **bajarse un
///    fichero e instalarlo**, y eso son 40 MB por la conexion de alla y, si la
///    firma no coincide, desinstalar — que **borra la base local**, o sea el
///    trabajo del dia sin subir (`docs/actualizaciones.md` §4). La palabra
///    «recargar» no aparece nunca por este lado: mandaria a alguien a buscar un
///    boton que no existe.
///
/// Y de ahi sale la asimetria que manda en todo este fichero: **un aviso de mas
/// en la web cuesta dos segundos; en el aparato cuesta una descarga y un
/// riesgo**. Por eso los dos lados no miran lo mismo ni se enteran igual.
///
/// ## QUE SE MIRA EN CADA LADO
///
/// **El aparato** mira `actualizacionProvider`, o sea el bloque `ultima` de
/// `GET /api/version` (`APP_ULTIMA_VERSION`), que es la version de la
/// APLICACION que hay colgada para descargar. No mira el campo `version` de esa
/// misma respuesta: ese es el latido de la api, y las dos se despliegan por
/// separado — comparar contra el mandaria a diez personas a reinstalar una
/// aplicacion que no ha cambiado en cada despliegue de la api. Lo dice
/// `api/internal/api/version.go` con esas palabras.
///
/// **La web** NO puede mirar eso, y esto es lo que hay que entender antes de
/// tocarlo: `APP_ULTIMA_VERSION` solo se pone cuando hay un APK colgado
/// (`docs/actualizaciones.md` §3: sin URL de descarga el servicio ni arranca).
/// Un arreglo desplegado solo en la web —que es la mayoria— no movería ese
/// numero, y la pestaña de ayer seguiria siendo la de ayer sin que nadie se
/// entere. O sea: justo el fallo del que va todo esto.
///
/// Lo que la web mira es **la huella de la compilacion**, la que
/// `deploy/Dockerfile.app` calcula como `md5(main.dart.js)` y pega dentro de
/// `index.html` (`flutter_bootstrap.js?v=<huella>`). Es la unica cosa que:
///
///  * la sirve **el contenedor de la web** y no el de la api, asi que habla del
///    paquete y de nada mas;
///  * cambia **exactamente** cuando cambia el codigo y no cuando no —es md5 del
///    contenido, asi que un redespliegue que no cambia nada da la misma huella
///    y no avisa a nadie (lo dice el propio Dockerfile);
///  * se pide siempre fresca, porque `deploy/nginx.conf` sirve `index.html` con
///    `no-cache` a proposito y ahi hay un incidente del 16/09 detras.
///
/// Y se compara **contra la primera respuesta que se consiguio**, no contra un
/// numero incrustado en el paquete. Tambien eso es del patron, y tambien con su
/// incidente: incrustar la version en el build daba dos valores distintos —19
/// segundos de diferencia— y el aviso salia SIEMPRE. Preguntando la referencia
/// no hace falta que el valor signifique nada; basta con que sea estable
/// mientras el contenedor viva y distinto tras un despliegue.
///
/// ## EL AVISO NO PUEDE SALIR SIEMPRE (`CLAUDE.md` §3-quinquies)
///
/// «Un aviso que sale siempre deja de leerse, y entonces tampoco se lee el dia
/// que importa.» Los cuatro frenos, y los cuatro tienen su prueba en pareja:
///
///  1. **La primera respuesta nunca avisa**: es la referencia, no una novedad.
///  2. **No saber no se cuenta.** Sin red, con un 4xx o con un `index.html` sin
///     huella (el servidor de desarrollo no la lleva) no sale nada. Igual que
///     `NoSeSupo` en el aparato: no saber si hay version nueva no es una
///     noticia para quien esta trabajando.
///  3. **Detectado una vez, se para de mirar.** Con el aviso puesto no queda
///     nada que descubrir.
///  4. **`Ahora no` calla el aviso, no lo mata.** Vuelve a la media hora. Una ✕
///     definitiva lo convierte en algo que se cierra sin leer el primer dia y
///     ya nunca avisa.
///
/// ## Y NUNCA SE INTERRUMPE A MEDIA RUTA
///
/// Es una franja, no un modal: no tapa nada, no roba el foco y no hay que
/// contestarle para seguir trabajando. Y con trabajo sin subir **no se ofrece
/// instalar** — se dice cuanto queda y se calla, porque instalar encima de una
/// cola pendiente es la unica forma de perder el dia de una persona.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../diseno/cajon.dart';
import '../diseno/colores.dart';
import '../diseno/tema.dart';
import '../nucleo/actualizacion/bajada_de_la_actualizacion.dart';
import '../nucleo/actualizacion/comprobador.dart';
import '../nucleo/actualizacion/version_publicada.dart';
import '../nucleo/descarga/en_megas.dart';
import '../nucleo/plataforma.dart';
import '../nucleo/proveedores.dart';
import '../nucleo/registro/registro.dart';
import '../pantallas/ayuda/datos/controles_senalados.dart';
import '../pantallas/ayuda/vista/control_senalado.dart';
import 'recargar_la_pagina.dart';

/// Cada cuanto se vuelve a mirar la huella, en la web. Los mismos cinco minutos
/// del patron.
const cadaCuantoSeMiraElPaquete = Duration(minutes: 5);

/// Cuanto se calla el aviso cuando alguien pulsa «Ahora no». La media hora del
/// patron: bastante para acabar lo que se estaba haciendo, poco para que se
/// olvide.
const cuantoCallaElAhoraNo = Duration(minutes: 30);

// ─────────────────────────────────────────────────────────── la huella servida

/// Lee la huella de la compilacion que el servidor sirve AHORA MISMO, o `null`
/// si no se pudo saber.
typedef LeerLaHuellaServida = Future<String?> Function();

/// Se lee por provider para que una prueba pueda contestar lo que quiera sin
/// levantar un servidor.
final lectorDeLaHuellaProvider = Provider<LeerLaHuellaServida>(
  (ref) => leerLaHuellaServida,
);

final _marcaDeLaHuella = RegExp(r'flutter_bootstrap\.js\?v=([A-Za-z0-9]+)');

/// Saca la huella de un `index.html` servido, o `null` si no la lleva.
///
/// **`null` es un caso normal, no un fallo**: el `index.html` que sale de
/// `flutter build web` tal cual —y el del servidor de desarrollo— no tiene
/// huella ninguna; se la pega `deploy/Dockerfile.app` al construir la imagen.
/// Sin huella no se compara nada y no se avisa nunca, que es el estado seguro.
String? huellaDe(String indexHtml) =>
    _marcaDeLaHuella.firstMatch(indexHtml)?.group(1);

/// Pide `index.html` y devuelve su huella.
///
/// Va contra `/index.html` en la raiz del origen y no contra la direccion
/// actual: `deploy/nginx.conf` elige el `no-cache` **por direccion**, y esa es
/// la que casa con su regla. Pedir `/rutas/3` acabaria tambien en el mismo
/// fichero (por `@aplicacion`), pero dependiendo de una segunda regla que puede
/// cambiar sin que nadie se acuerde de esto.
///
/// La marca de tiempo en la direccion es contra un proxy por medio, no contra
/// nginx: ahi el `no-cache` ya esta puesto.
///
/// **No lanza nunca.** Esto corre cada cinco minutos por detras mientras
/// alguien trabaja; un fallo aqui no puede llegar a ninguna pantalla.
Future<String?> leerLaHuellaServida() async {
  try {
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final destino = Uri.base.removeFragment().replace(
      path: '/index.html',
      queryParameters: <String, String>{
        'huella': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    final respuesta = await dio.getUri<String>(destino);
    final cuerpo = respuesta.data;
    if (cuerpo == null) return null;
    return huellaDe(cuerpo);
  } on Object catch (e) {
    // Sin red, o el servidor contestando algo raro. Se mira dentro de cinco
    // minutos y no se le cuenta a nadie.
    Registro.info('no se pudo leer la huella del paquete: $e');
    return null;
  }
}

// ─────────────────────────────────────────────────── el vigia del paquete (web)

/// ¿El servidor sirve ya un paquete distinto del que corre esta pestaña?
///
/// `false` mientras no se sepa que si — y «no se sabe» incluye no haber podido
/// preguntar, que es lo que hace que un dia sin red no se vea como un dia con
/// version nueva.
final hayPaqueteNuevoProvider = NotifierProvider<VigiaDelPaquete, bool>(
  VigiaDelPaquete.new,
);

/// Pregunta por la huella, guarda la primera como referencia y avisa cuando
/// cambia.
///
/// **No es `autoDispose` a proposito.** La referencia tiene que sobrevivir a
/// cambiar de pantalla: el armazon es un `ShellRoute` y se reconstruye en cada
/// navegacion. Con `autoDispose`, un instante sin nadie mirando tiraria la
/// referencia y la huella nueva pasaria a ser la referencia — o sea, esa pestaña
/// no volveria a avisar nunca.
class VigiaDelPaquete extends Notifier<bool> {
  /// La primera huella que se consiguio. Todo lo demas se compara con esta.
  String? _referencia;
  Timer? _reloj;
  bool _mirando = false;
  bool _vivo = false;

  @override
  bool build() {
    _reloj?.cancel();
    _reloj = null;
    _vivo = true;
    ref.onDispose(() {
      _vivo = false;
      _reloj?.cancel();
      _reloj = null;
    });

    // EN EL APARATO AQUI NO SE MIRA NADA. Alla la version nueva se instala, no
    // se recarga, y de eso se entera `actualizacionProvider` con UNA peticion al
    // arrancar. Un sondeo cada cinco minutos en el patio de un almacen es gastar
    // la bateria y los datos de alguien para nada.
    if (ref.watch(trabajaSinConexionProvider)) return false;

    // La referencia se coge YA, no dentro de cinco minutos: si un despliegue
    // cayera en ese rato se tomaria como referencia la huella nueva y esta
    // pestaña no volveria a avisar.
    unawaited(_mirar());
    return false;
  }

  Future<void> _mirar() async {
    if (!_vivo || _mirando) return;
    _mirando = true;
    try {
      final servida = await ref.read(lectorDeLaHuellaProvider)();
      if (!_vivo) return;

      // FRENO 2: no saber no se cuenta.
      if (servida == null) return;

      // FRENO 1: la primera respuesta es la referencia, no una novedad.
      if (_referencia == null) {
        _referencia = servida;
        return;
      }

      // LA CONDICION DEL AVISO. Es la linea que se rompe para comprobar que hay
      // una prueba que lo caza: si esto se quita, el aviso sale con la misma
      // huella de siempre, o sea siempre.
      if (servida == _referencia) return;

      state = true;
    } finally {
      _mirando = false;
      // FRENO 3: con el aviso puesto se deja de mirar.
      if (_vivo && !state) _reloj = Timer(cadaCuantoSeMiraElPaquete, _mirar);
    }
  }
}

// ───────────────────────────────────────────────── abrir la descarga (aparato)

/// Abre la descarga del APK o del paquete de escritorio.
///
/// Va por provider y no llamando a `launchUrl` desde el boton por lo mismo que
/// `pantallas/rutas/datos/abrir_y_compartir.dart`: dentro de una prueba no hay
/// sistema operativo al otro lado, y lo que interesa comprobar es **que se
/// pidio abrir ese enlace**, no que Android lo abriera.
final abridorDeLaDescargaProvider = Provider<Future<void> Function(String)>(
  (ref) => _abrirLaDescarga,
);

Future<void> _abrirLaDescarga(String enlace) async {
  final destino = Uri.tryParse(enlace);
  if (destino == null) return;
  try {
    await launchUrl(destino, mode: LaunchMode.externalApplication);
  } on Object catch (e) {
    // Que no se pueda abrir no puede tumbar la pantalla de alguien que esta
    // repartiendo. Se anota y ya; la version vieja sigue funcionando.
    Registro.aviso('no se pudo abrir la descarga $enlace: $e');
  }
}

// ──────────────────────────────────────────────────────────────── lo que se ve

/// LO QUE DICE LA FRANJA, ya decidido. Un solo sitio donde mirar qué se le
/// enseña a cada destino.
@immutable
class LoQueDiceElAviso {
  const LoQueDiceElAviso({
    required this.firma,
    required this.titular,
    required this.detalle,
    this.textoDeAccion,
    this.iconoDeAccion,
    this.accion,
  });

  /// QUE aviso es este. Cambia cuando cambia el mensaje —de «sube primero» a
  /// «hay una nueva», o de una version a otra—, y al cambiar **se levanta el
  /// «Ahora no»**: lo que se pospuso fue el aviso de antes, no este.
  final String firma;

  final String titular;
  final String detalle;

  /// El texto del boton. `null` cuando no hay nada que ofrecer todavia — es el
  /// caso de «primero sube»: ahi no se ofrece instalar.
  final String? textoDeAccion;

  /// EL GLIFO DE ESE BOTON, y viaja con el texto porque los dos destinos no
  /// ofrecen lo mismo: la web recarga la pestana y el aparato ensena como se
  /// instala. Un icono unico para los dos volveria a decir que es el mismo
  /// gesto, que es lo que este fichero entero existe para no decir
  /// (`diseno/tema.dart`, [BotonPrincipal]).
  final IconData? iconoDeAccion;

  final void Function(BuildContext)? accion;
}

/// LA FRANJA, en el armazon, encima de todo.
///
/// Se monta en el armazon (`navegacion/armazon.dart`) y no en cada pantalla por lo mismo que el patron lo
/// mete en `layout.tsx`: el aviso tiene que salir estando en Rutas, en Pedidos o
/// en el Panel, porque quien tiene la pestaña de ayer la tiene abierta en la
/// pantalla en la que trabaja, no en la que se acuerde de visitar.
class AvisoDeVersionNueva extends ConsumerStatefulWidget {
  const AvisoDeVersionNueva({super.key});

  @override
  ConsumerState<AvisoDeVersionNueva> createState() => _EstadoDelAviso();
}

class _EstadoDelAviso extends ConsumerState<AvisoDeVersionNueva> {
  /// La firma del aviso que se pospuso, o `null` si no hay ninguno callado.
  String? _calladoPara;
  Timer? _vuelve;

  @override
  void dispose() {
    _vuelve?.cancel();
    super.dispose();
  }

  void _ahoraNo(String firma) {
    setState(() => _calladoPara = firma);
    _vuelve?.cancel();
    // VUELVE SOLO. No hay forma de quitarlo del todo, y es a proposito: una ✕
    // definitiva la pulsa todo el mundo el primer dia sin leer.
    _vuelve = Timer(cuantoCallaElAhoraNo, () {
      if (!mounted) return;
      setState(() => _calladoPara = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    // La misma capacidad con nombre de todo lo demas (`nucleo/plataforma.dart`),
    // y no un `kIsWeb` suelto: lo que se pregunta aqui es «¿este destino lleva
    // el trabajo dentro?», que es justo la diferencia entre recargar e instalar.
    final enElAparato = ref.watch(trabajaSinConexionProvider);
    final dice = enElAparato ? _enElAparato() : _enLaWeb();

    if (dice == null) return const SizedBox.shrink();
    if (_calladoPara == dice.firma) return const SizedBox.shrink();

    return _Franja(dice: dice, alAhoraNo: () => _ahoraNo(dice.firma));
  }

  /// LA WEB: recargar.
  LoQueDiceElAviso? _enLaWeb() {
    if (!ref.watch(hayPaqueteNuevoProvider)) return null;

    return LoQueDiceElAviso(
      firma: 'recargar',
      titular: 'Hay una versión nueva',
      // Se dice que no se pierde nada porque es verdad Y porque es lo que
      // frena a alguien: en la web no hay copia ni cola (`CLAUDE.md` §1), asi
      // que recargar no puede costarle nada a nadie.
      detalle:
          'Esta pestaña lleva abierta desde antes del último cambio. Recarga '
          'para tenerlo; aquí no hay nada sin guardar que se pueda perder.',
      textoDeAccion: 'Recargar ahora',
      iconoDeAccion: Icons.refresh,
      accion: (_) => unawaited(recargarLaPagina()),
    );
  }

  /// EL APARATO: instalar, y solo cuando no queda trabajo sin subir.
  LoQueDiceElAviso? _enElAparato() {
    _volverAMirarAlTerminarUnaSubida();

    final estado = ref.watch(actualizacionProvider).value;

    // LO QUE ESTE PASANDO CON LA DESCARGA MANDA SOBRE EL AVISO — 05/10/2026.
    //
    // Y no es un adorno: **el cajon se cierra**. Quien lo cierra a mitad de una
    // descarga de 75 MB no la ha cancelado, y sin esto se quedaria sin ninguna
    // forma de saber como va ni de volver a ella. La franja esta en las siete
    // pantallas, asi que es el unico sitio donde eso se puede decir siempre.
    if (estado is SePuedeActualizar) {
      final enMarcha = _laBajadaEnMarcha(estado);
      if (enMarcha != null) return enMarcha;
    }
    // El numero SE LEE DE LA COLA, en vivo, y no del que traia el estado: ese es
    // de cuando se pregunto, y entre medias la persona sube. Un «te quedan 14»
    // encima de una cola de 3 es un numero creible y equivocado.
    //
    // Y CUENTA TAMBIEN LOS RECHAZADOS — 24/09/2026. `ComprobadorDeActualizacion`
    // ya pregunta por los dos (`BaseLocal.cuantosSinSubir`), asi que leer aqui
    // solo los pendientes dejaba el arreglo muerto: un aparato cuyo unico
    // trabajo sin subir es un cierre rechazado devolvia `PrimeroSube` y esta
    // guarda lo tiraba al `_ => null`. Instalar encima puede llevarselo, y ese
    // ademas no se arregla con señal: espera a que alguien decida.
    final sinSubir = ref.watch(sinSubirDeVerdadProvider).value ?? 0;

    return switch (estado) {
      // `AlDia`, `NoAplica`, `NoSeSupo` y el `null` de mientras se pregunta: no
      // se enseña NADA. `NoSeSupo` es el que importa de los cuatro — no saber si
      // hay version nueva no es una noticia para quien esta repartiendo.
      SePuedeActualizar(:final publicada) => LoQueDiceElAviso(
        firma: 'instalar:${publicada.version}',
        titular: 'Hay una versión nueva: ${publicada.version}',
        detalle:
            publicada.notas ??
            'Se instala a mano: primero se descarga el fichero y después se '
                'instala encima.',
        textoDeAccion: 'Cómo instalarla',
        iconoDeAccion: Icons.install_mobile,
        accion: (contexto) => _abrirElCajon(contexto, estado),
      ),
      // PRIMERO SUBE, y sin boton de instalar. `docs/actualizaciones.md` §1.1:
      // instalar con cola pendiente puede llevarse la base local por delante, y
      // la base local es el trabajo del dia de una persona. Con el numero
      // delante —«te quedan 14»— se sabe que hacer; «no puedes actualizar» no
      // dice nada.
      //
      // Y no se interrumpe: el boton de subir ya esta a dos dedos, en la franja
      // de estado de aqui al lado.
      PrimeroSube(:final publicada) when sinSubir > 0 => LoQueDiceElAviso(
        firma: 'sube:${publicada.version}',
        titular: 'Hay una versión nueva, pero antes hay que subir el trabajo',
        detalle:
            'Te quedan $sinSubir cosas por subir. Instalar ahora puede '
            'llevárselas: primero sube, después actualiza.',
      ),
      // `PrimeroSube` con la cola ya vacia no se enseña: el estado es de antes
      // de la subida y lo que viene detras es el aviso bueno, el de instalar.
      // Repintar «te quedan 0 cosas por subir» seria decirle a alguien que no
      // hizo lo que acaba de hacer.
      _ => null,
    };
  }

  /// LA FRANJA CUANDO LA DESCARGA YA ESTA EN MARCHA (o parada, o lista).
  ///
  /// Devuelve `null` cuando no hay nada bajandose: entonces manda el aviso de
  /// siempre. **Cada caso lleva su accion**, porque un aviso sin accion es un
  /// aviso que se queda puesto para siempre (`CLAUDE.md` §4): hasta el de «Android
  /// esta instalando» ofrece volver a intentarlo, que es lo que hace falta si la
  /// persona cancelo esa pantalla del sistema sin querer.
  LoQueDiceElAviso? _laBajadaEnMarcha(SePuedeActualizar nueva) {
    final version = nueva.publicada.version;
    return switch (ref.watch(bajadaDeLaActualizacionProvider)) {
      SinEmpezar() => null,
      BajandoLaActualizacion(:final bajados, :final total) => LoQueDiceElAviso(
        // La firma NO lleva los bytes: con ellos cambiaria cada por ciento y el
        // «Ahora no» se levantaria solo al segundo siguiente.
        firma: 'bajando:$version',
        titular: 'Bajando la versión $version',
        detalle:
            '${enMegas(bajados)} de ${enMegas(total)}. Puedes seguir '
            'trabajando; si se corta la conexión, continúa desde donde iba.',
        textoDeAccion: 'Ver la descarga',
        iconoDeAccion: Icons.downloading_outlined,
        accion: (contexto) => _abrirElCajon(contexto, nueva),
      ),
      BajadaComprobada() => LoQueDiceElAviso(
        firma: 'instalar-ya:$version',
        titular: 'La versión $version está descargada',
        detalle:
            'Falta instalarla. Android enseñará su pantalla de «¿instalar?»: '
            'hay que confirmar ahí, eso no lo puede hacer la aplicación.',
        textoDeAccion: 'Instalar',
        iconoDeAccion: Icons.install_mobile,
        accion: (_) => unawaited(
          ref.read(bajadaDeLaActualizacionProvider.notifier).instalar(),
        ),
      ),
      FaltaElPermisoParaInstalar() => LoQueDiceElAviso(
        firma: 'permiso:$version',
        titular: 'La versión $version está descargada, falta un permiso',
        detalle:
            'Android no deja instalar a una aplicación que no lo tenga. Es un '
            'ajuste del sistema, se da una vez y no hay que volver a bajar nada.',
        textoDeAccion: 'Dar el permiso',
        iconoDeAccion: Icons.lock_open_outlined,
        accion: (contexto) => _abrirElCajon(contexto, nueva),
      ),
      ElInstaladorEstaEnPantalla() => LoQueDiceElAviso(
        firma: 'instalando:$version',
        titular: 'Android está instalando la versión $version',
        detalle:
            'Si cerraste esa pantalla sin instalar, el fichero sigue aquí: toca '
            'otra vez y vuelve a salir. No hay que bajar nada de nuevo.',
        textoDeAccion: 'Instalar',
        iconoDeAccion: Icons.install_mobile,
        accion: (_) => unawaited(
          ref.read(bajadaDeLaActualizacionProvider.notifier).instalar(),
        ),
      ),
      NoSePudoInstalarla(:final motivo) => LoQueDiceElAviso(
        firma: 'no-instalo:$version',
        titular: 'No se pudo instalar la versión $version',
        // EL MOTIVO LITERAL, que ya dice que paso y que se conserva.
        detalle: motivo,
        textoDeAccion: 'Intentar de nuevo',
        iconoDeAccion: Icons.refresh,
        accion: (contexto) => _abrirElCajon(contexto, nueva),
      ),
      FalloLaBajada(:final motivo, :final sePuedeReanudar) => LoQueDiceElAviso(
        firma: 'fallo:$version',
        titular: 'La descarga de la versión $version no terminó',
        detalle: motivo,
        // «Seguir descargando» cuando de verdad sigue, y «Empezar de nuevo»
        // cuando no: prometer que continúa y que empiece de cero es lo que hace
        // que nadie se fíe del botón.
        textoDeAccion: sePuedeReanudar
            ? 'Seguir descargando'
            : 'Empezar de nuevo',
        iconoDeAccion: Icons.download_outlined,
        accion: (contexto) => _abrirElCajon(contexto, nueva),
      ),
    };
  }

  /// EL PENDIENTE HERMANO de `docs/integracion-pendiente.md`: al terminar una
  /// subida se vuelve a preguntar.
  ///
  /// Sin esto, un `PrimeroSube` se queda puesto hasta el siguiente arranque
  /// **despues de que la persona hizo justo lo que se le pidio**, que es la
  /// forma mas rapida de enseñar a no hacer caso de los avisos.
  ///
  /// Se engancha a la cola y no al gesto de entregar el dia a proposito: la cola
  /// tambien la vacia el vigia por su cuenta cuando vuelve la señal, y ese es el
  /// caso mas comun de los dos. Lo que cambia la respuesta es que la cola llegue
  /// a cero, venga de donde venga.
  ///
  /// Y solo entonces: invalidar en cada movimiento de la cola seria una peticion
  /// de red por cada apunte que sube, para preguntar algo cuya respuesta no ha
  /// cambiado.
  void _volverAMirarAlTerminarUnaSubida() {
    ref.listen<AsyncValue<int>>(sinSubirProvider, (antes, ahora) {
      if (ahora.value != 0) return;
      // Que ya estuviera a cero no es «acaba de subir»: es que no habia nada.
      if ((antes?.value ?? 0) == 0) return;
      // Y si el aviso no era «primero sube», la respuesta no cambia por vaciar
      // la cola.
      if (ref.read(actualizacionProvider).value is! PrimeroSube) return;

      ref.invalidate(actualizacionProvider);
    });
  }

  void _abrirElCajon(BuildContext contexto, SePuedeActualizar nueva) {
    // Cajon, como todo en este proyecto — tambien en escritorio, que es la
    // excepcion aprobada el 05/09/2026 (`diseno/cajon.dart`).
    //
    // `abrirPanel` y no `abrirCajon`: en `abrirCajon` el cuerpo y el pie se
    // construyen UNA vez, y aqui los dos cambian con la descarga —la barra sube,
    // el boton pasa de «Descargar» a «Detener» y de ahi a «Instalar»—. Con el
    // cuerpo construido una vez, la barra se quedaria clavada en el cero y el
    // boton nunca cambiaria: es el §3-ter otra vez, lo que se pinta y puede
    // cambiar no puede pedirse una sola vez.
    unawaited(
      abrirPanel<void>(contexto, (_) => _CajonDeLaVersion(nueva: nueva)),
    );
  }
}

/// EL CAJON DE LA VERSION NUEVA: lo que va a pasar, y el boton que lo hace.
///
/// Es un `ConsumerWidget` aparte y no un trozo del aviso porque **mira la
/// descarga en vivo**: el estado vive en `bajadaDeLaActualizacionProvider` y no
/// aqui dentro, para que cerrar el cajon no se lleve la descarga por delante.
class _CajonDeLaVersion extends ConsumerWidget {
  const _CajonDeLaVersion({required this.nueva});

  final SePuedeActualizar nueva;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // SE BAJA LA ULTIMA QUE HAYA AHORA, NO LA QUE HABIA AL ABRIR ESTO.
    //
    // Paso el 25/09/2026: se publico la 1.0.6, y quince minutos despues la 1.0.7
    // con los arreglos de lo que Jose acababa de contar. El pulso en los dos
    // momentos y se bajo las dos:
    //
    //     «me mando a descargar la 1.06 y la 1.07 [...] te dije q la ultima»
    //     «no quiero q actualize todo el tramo»
    //
    // Son 75 MB cada una. Lo que llego por parametro solo se usa si en este
    // instante no hay respuesta: quedarse sin descarga seria peor que bajar una
    // version de hace un minuto.
    final ahora = ref.watch(actualizacionProvider).value;
    final ultima = ahora is SePuedeActualizar ? ahora : nueva;
    final publicada = ultima.publicada;
    final fichero = publicada.ficheroPara(Plataforma.deEsteAparato());
    final bajada = ref.watch(bajadaDeLaActualizacionProvider);

    // LA COLA MANDA TAMBIEN AQUI — `docs/actualizaciones.md` §1.1.
    //
    // `actualizacionProvider` se pregunta UNA vez al arrancar, asi que no se
    // entera de que la cola creció despues: alguien puede bajarse la version por
    // la mañana, trabajar el dia entero sin señal —la cola crece— y encontrarse
    // el boton de instalar puesto por la tarde. Instalar encima con trabajo sin
    // subir puede llevarselo, y eso no se arregla con nada.
    //
    // Se lee EN VIVO de la cola y contando los rechazados, por lo mismo que la
    // franja: un rechazado es trabajo que no esta arriba y que ademas no se
    // arregla solo.
    final sinSubir = ref.watch(sinSubirDeVerdadProvider).value ?? 0;

    // SE BAJA DENTRO SOLO SI SE SABE QUE SE BAJA.
    //
    // Sin `bytes` y sin `sha256` no hay barra honesta ni forma de saber si llego
    // entero —el `Content-Length` no llega (ver `bajada_de_la_actualizacion.dart`)
    // y la huella no se puede inventar—, asi que una api anterior al 22/09/2026
    // se queda con el navegador. **No se quita lo que funciona hoy.**
    final dentro =
        Plataforma.deEsteAparato() == Plataforma.android && fichero != null;

    return Cajon(
      titulo: 'Versión ${publicada.version}',
      subtitulo: publicada.compilacion == null
          ? null
          : 'compilación ${publicada.compilacion}',
      pie: dentro
          ? _PieDeDentro(
              bajada: bajada,
              enlace: ultima.enlace,
              fichero: fichero,
              version: publicada.version,
              sinSubir: sinSubir,
            )
          : _PieDelNavegador(enlace: ultima.enlace),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (publicada.notas != null) ...[
            Text(publicada.notas!, style: Tipos.texto(tamano: 14)),
            const SizedBox(height: Aire.lg),
          ],
          Text(
            'Qué va a pasar',
            style: Tipos.texto(tamano: 13, peso: FontWeight.w700),
          ),
          const SizedBox(height: Aire.xs),
          Text(
            _queVaAPasar(dentro: dentro, fichero: fichero),
            style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
          ),
          // PRIMERO SUBE. Va antes que el estado de la descarga a proposito: es
          // lo que decide si el boton de instalar esta vivo, asi que tiene que
          // leerse antes de buscarlo.
          if (sinSubir > 0)
            ..._elMotivo(
              clave: claveDeLaColaPendiente,
              'Te quedan $sinSubir cosas por subir. Instalar ahora puede '
              'llevárselas, así que el botón de instalar está apagado: primero '
              'sube el trabajo (desde la franja de arriba o la pantalla de '
              'Sincronización) y después instala. Lo descargado se queda aquí.',
            ),
          ..._comoVa(bajada),
          const SizedBox(height: Aire.md),
          Text(
            'Instálalo con señal y con la cola vacía. No hace falta que sea '
            'ahora: la versión de ahora sigue funcionando.',
            style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
          ),
        ],
      ),
    );
  }

  /// LO QUE VA A PASAR, dicho antes de pulsar.
  ///
  /// **CUANTO PESA SALE DEL ANUNCIO DE LA API**, no de la respuesta: el
  /// 22/09/2026 la descarga enseñaba «30 MB/?» porque el tamaño salia del
  /// `Content-Length`, que Cloudflare quita. Quien esta en la calle con datos
  /// contados tiene que poder decidir **antes**.
  ///
  /// Y LA PANTALLA DE ANDROID SE AVISA. No se puede saltar: Android enseña su
  /// «¿instalar?» y ahi confirma la persona. Dicho antes es un paso; sin decir,
  /// parece un error y se cancela.
  String _queVaAPasar({
    required bool dentro,
    required FicheroPublicado? fichero,
  }) {
    if (dentro) {
      return 'Son ${enMegas(fichero!.bytes)} y se descargan aquí dentro, con su '
          'barra: no hace falta salir al navegador ni buscar el fichero después. '
          'Si se corta la conexión, continúa desde donde iba. Al terminar, '
          'Android enseña su propia pantalla de «¿instalar?» y ahí hay que '
          'confirmar: eso no lo puede hacer la aplicación.';
    }
    // El navegador, que es lo que hay en el escritorio y con una api anterior.
    // Una api sin `ficheros` no manda el tamaño: no se inventa un número ni se
    // escribe «? MB», se dice lo demás y ya.
    final pesa = fichero == null ? '' : 'Son ${enMegas(fichero.bytes)}. ';
    return '${pesa}Se abre el navegador y se descarga el fichero. La descarga no '
        'toca esta aplicación: lo que tengas dentro sigue aquí mientras no '
        'instales.';
  }

  /// LA BARRA Y EL MOTIVO. Nada de esto sale cuando no hay nada que contar.
  List<Widget> _comoVa(ComoVaLaActualizacion bajada) => switch (bajada) {
    SinEmpezar() || ElInstaladorEstaEnPantalla() => const [],
    // LA BARRA SABE CUANTO FALTA, asi que lo dice. Un `value` nulo —la rueda que
    // da vueltas— seria fingir que no se sabe teniendo el dato.
    BajandoLaActualizacion(:final bajados, :final total, :final parte) => [
      const SizedBox(height: Aire.lg),
      Text(
        'Bajando ${enMegas(bajados)} de ${enMegas(total)} '
        '(${(parte * 100).round()} %)',
        key: claveDeLoQueVaBajado,
        style: Tipos.texto(tamano: 13, peso: FontWeight.w700),
      ),
      const SizedBox(height: Aire.xs),
      LinearProgressIndicator(value: parte, key: claveDeLaBarraDeLaBajada),
    ],
    BajadaComprobada(:final bytes) => [
      const SizedBox(height: Aire.lg),
      Text(
        'Descargada y comprobada: ${enMegas(bytes)}. Falta instalarla.',
        style: Tipos.texto(tamano: 13, peso: FontWeight.w700),
      ),
    ],
    // EL MOTIVO LITERAL, que es lo unico accionable (`CLAUDE.md` §4).
    FalloLaBajada(:final motivo) => _elMotivo(motivo),
    FaltaElPermisoParaInstalar() => _elMotivo(
      'Android no deja instalar a una aplicación que no tenga el permiso de '
      '«instalar aplicaciones desconocidas». Es un ajuste del sistema, se da '
      'una vez y lo descargado no se pierde.',
    ),
    NoSePudoInstalarla(:final motivo) => _elMotivo(motivo),
  };

  /// UN AVISO ÁMBAR con su motivo.
  ///
  /// La clave viaja por parámetro y no va fija dentro: con la cola pendiente y una
  /// descarga fallada salen **dos** de éstos como hermanos en la misma columna, y
  /// dos hermanos con la misma `Key` es un error de Flutter en pantalla. Se
  /// descubrió leyendo, no probando — y en producción la combinación es de las
  /// normales: se cortó la descarga y además queda trabajo sin subir.
  List<Widget> _elMotivo(
    String motivo, {
    Key clave = claveDelMotivoDeLaBajada,
  }) => [
    const SizedBox(height: Aire.lg),
    DecoratedBox(
      decoration: BoxDecoration(
        color: Colores.ambarFondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(motivo, key: clave, style: Tipos.texto(tamano: 12)),
      ),
    ),
  ];
}

/// Para encontrar las piezas desde las pruebas sin depender de un literal.
const claveDeLaBarraDeLaBajada = Key('barra-de-la-bajada');
const claveDeLoQueVaBajado = Key('lo-que-va-bajado');
const claveDelMotivoDeLaBajada = Key('motivo-de-la-bajada');
const claveDeLaColaPendiente = Key('cola-pendiente-no-instalar');

/// EL PIE CUANDO SE BAJA DENTRO. Un boton por estado, y ninguno sin salida.
class _PieDeDentro extends ConsumerWidget {
  const _PieDeDentro({
    required this.bajada,
    required this.enlace,
    required this.fichero,
    required this.version,
    required this.sinSubir,
  });

  final ComoVaLaActualizacion bajada;
  final String enlace;
  final FicheroPublicado? fichero;
  final String version;

  /// Cuanto trabajo queda sin subir. Con uno solo, **no se instala**: el cuerpo
  /// del cajon dice por que y el boton se queda apagado.
  final int sinSubir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mando = ref.read(bajadaDeLaActualizacionProvider.notifier);

    // BAJAR SI, INSTALAR NO: bajar no toca nada de lo que hay dentro, y tenerlo
    // bajado es justo lo que hace falta para instalar en cuanto suba la cola.
    void bajar() => unawaited(
      mando.bajar(enlace: enlace, fichero: fichero!, version: version),
    );
    final instalar = sinSubir > 0 ? null : () => unawaited(mando.instalar());

    // EL NAVEGADOR NO SE QUITA. Es la salida cuando el permiso no esta, cuando el
    // instalador no arranca y cuando la descarga lleva tres fallos seguidos:
    // quitar la unica forma que funciona hoy seria cambiar un problema por otro.
    Widget elNavegador() => TextButton(
      onPressed: () {
        Navigator.of(context).maybePop();
        unawaited(ref.read(abridorDeLaDescargaProvider)(enlace));
      },
      child: const Text('Abrir en el navegador'),
    );

    final botones = switch (bajada) {
      // UNA DESCARGA POR TOQUE, NO DOS. Jose, 25/09/2026: «cuando le doy a
      // descargar me dispara dos descargas en ves de una». La guarda de verdad
      // esta en `BajadaDeLaActualizacion.bajar` —`_enMarcha`, que se pone antes
      // del primer `await`, asi que los dos toques de un doble toque no pasan
      // los dos—; aqui el boton ademas se va en cuanto hay estado, que es lo que
      // se VE.
      SinEmpezar() => [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Ahora no'),
        ),
        const SizedBox(width: Aire.sm),
        ControlSenalado(
          nombre: Senalado.cajonDescargarEInstalar,
          child: BotonPrincipal(
            texto: 'Descargar e instalar',
            icono: Icons.download_outlined,
            alPulsar: bajar,
          ),
        ),
      ],
      BajandoLaActualizacion() => [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          // Cerrar NO para la descarga, y se dice: lo contrario es que alguien
          // cierre creyendo que cancela, o que no cierre por miedo a cancelar.
          child: const Text('Cerrar y seguir bajando'),
        ),
        const SizedBox(width: Aire.sm),
        OutlinedButton.icon(
          onPressed: mando.detener,
          icon: const Icon(Icons.stop_outlined, size: 18),
          label: const Text('Detener'),
        ),
      ],
      BajadaComprobada() => [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Ahora no'),
        ),
        const SizedBox(width: Aire.sm),
        BotonPrincipal(
          texto: 'Instalar',
          icono: Icons.install_mobile,
          alPulsar: instalar,
        ),
      ],
      ElInstaladorEstaEnPantalla() => [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Cerrar'),
        ),
        const SizedBox(width: Aire.sm),
        BotonPrincipal(
          texto: 'Instalar',
          icono: Icons.install_mobile,
          alPulsar: instalar,
        ),
      ],
      // SIN PERMISO: las tres salidas a la vez, porque las tres hacen falta.
      // Ir al ajuste; volver y decir que ya esta; o el navegador de siempre.
      FaltaElPermisoParaInstalar() => [
        elNavegador(),
        const SizedBox(width: Aire.sm),
        OutlinedButton.icon(
          onPressed: instalar,
          icon: const Icon(Icons.install_mobile, size: 18),
          label: const Text('Ya lo di: instalar'),
        ),
        const SizedBox(width: Aire.sm),
        BotonPrincipal(
          texto: 'Dar el permiso',
          icono: Icons.lock_open_outlined,
          alPulsar: () => unawaited(mando.pedirElPermiso()),
        ),
      ],
      NoSePudoInstalarla() => [
        elNavegador(),
        const SizedBox(width: Aire.sm),
        BotonPrincipal(
          texto: 'Intentar de nuevo',
          icono: Icons.refresh,
          alPulsar: instalar,
        ),
      ],
      FalloLaBajada(:final sePuedeReanudar, :final seOfreceElNavegador) => [
        if (seOfreceElNavegador) ...[
          elNavegador(),
          const SizedBox(width: Aire.sm),
        ],
        BotonPrincipal(
          // Lo que dice el boton es lo que va a hacer: si lo bajado ya no sirve,
          // no se promete que continua.
          texto: sePuedeReanudar ? 'Seguir descargando' : 'Empezar de nuevo',
          icono: Icons.download_outlined,
          alPulsar: bajar,
        ),
      ],
    };

    // `Wrap` y no `Row`: a 390 px las tres salidas del caso sin permiso no caben
    // en una linea, y lo que se pierde al no caber es justo el que explica como
    // salir.
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: Aire.xs,
      runSpacing: Aire.xs,
      children: botones,
    );
  }
}

/// EL PIE DEL NAVEGADOR: el de siempre, para el escritorio y para una api que no
/// anuncia ni el tamaño ni la huella.
class _PieDelNavegador extends ConsumerWidget {
  const _PieDelNavegador({required this.enlace});

  final String enlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PieDeLaDescarga(
    alDescargar: () {
      // La ultima que haya AHORA, igual que arriba.
      final ahora = ref.read(actualizacionProvider).value;
      final ultimo = ahora is SePuedeActualizar ? ahora.enlace : enlace;
      Navigator.of(context).maybePop();
      unawaited(ref.read(abridorDeLaDescargaProvider)(ultimo));
    },
    alCerrar: () => Navigator.of(context).maybePop(),
  );
}

/// La franja en si. Ambar, a lo ancho, debajo de la barra superior.
///
/// Ambar y no rojo: esto no impide trabajar. Y va arriba y no flotando abajo
/// —donde lo pone el patron— porque aqui abajo esta el pulgar y las pantallas
/// tienen sus propias acciones ahi; arriba ya existe el sitio de las franjas que
/// hablan del estado de la aplicacion.
class _Franja extends StatelessWidget {
  const _Franja({required this.dice, required this.alAhoraNo});

  final LoQueDiceElAviso dice;
  final VoidCallback alAhoraNo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(Aire.lg, Aire.sm, Aire.sm, Aire.sm),
        decoration: BoxDecoration(
          color: Colores.ambarFondo,
          border: Border(
            bottom: BorderSide(color: Colores.ambar.withValues(alpha: 0.25)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.system_update_alt,
                size: 16,
                color: Colores.ambar,
              ),
            ),
            const SizedBox(width: Aire.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dice.titular,
                    style: Tipos.texto(
                      tamano: 13,
                      peso: FontWeight.w700,
                      color: Colores.ambar,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dice.detalle,
                    style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
                  ),
                  const SizedBox(height: Aire.xs),
                  // Los botones en su propia linea y no al lado del texto: en
                  // 390 px, al lado, o se recorta el texto o no caben los dos
                  // botones, y las dos mitades hacen falta.
                  Wrap(
                    spacing: Aire.sm,
                    children: [
                      if (dice.textoDeAccion != null)
                        // SIN `VisualDensity.compact` — 28/09/2026. Los dos
                        // botones de esta franja eran los unicos de la
                        // aplicacion que lo llevaban, y `compact` le quita 8 px
                        // a cada lado del blanco tactil: el objetivo se quedaba
                        // en 40, ocho por debajo del minimo de Material. Con un
                        // relleno macizo detras al menos se veia donde apuntar;
                        // sin el —que es lo que se acaba de quitar de toda la
                        // aplicacion— no se ve nada, asi que encoger el sitio
                        // donde cae el dedo deja de tener excusa. El aire lo
                        // decide el tema y nadie mas.
                        // SEÑALADO PARA LA GUIA. La tarea «Actualizar la
                        // aplicacion» empieza aqui, y este boton cambia de
                        // palabra segun el estado —«Como instalarla»,
                        // «Instalar», «Dar el permiso», «Seguir descargando»—:
                        // el nombre es del SITIO, no de la palabra, que es
                        // justo por lo que un nombre de control no puede ser el
                        // texto del boton.
                        ControlSenalado(
                          nombre: Senalado.franjaVersionNueva,
                          child: BotonPrincipal(
                            texto: dice.textoDeAccion!,
                            icono: dice.iconoDeAccion!,
                            alPulsar: () => dice.accion?.call(context),
                          ),
                        ),
                      TextButton(
                        onPressed: alAhoraNo,
                        child: const Text('Ahora no'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El pie del cajón de la versión nueva: «Ahora no» y «Descargar».
///
/// Es un widget con estado por UNA razón concreta: la descarga tiene que
/// dispararse **una sola vez**, y para eso hace falta recordar que ya se pulsó.
/// Con una bandera dentro de un `builder` no vale —se reinicia en cada
/// repintado—, y ése es justo el error que hay que no cometer aquí.
class _PieDeLaDescarga extends StatefulWidget {
  const _PieDeLaDescarga({required this.alDescargar, required this.alCerrar});

  final VoidCallback alDescargar;
  final VoidCallback alCerrar;

  @override
  State<_PieDeLaDescarga> createState() => _PieDeLaDescargaState();
}

class _PieDeLaDescargaState extends State<_PieDeLaDescarga> {
  bool _yaSePulso = false;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      TextButton(
        onPressed: _yaSePulso ? null : widget.alCerrar,
        child: const Text('Ahora no'),
      ),
      const SizedBox(width: Aire.sm),
      ControlSenalado(
        // El «Descargar» del cajon del ESCRITORIO, que sigue saliendo al
        // navegador: alli la APK no se instala sola. Nombre distinto del de la
        // APK a proposito — son dos botones que hacen dos cosas, y el manual de
        // cada forma cuenta la suya.
        nombre: Senalado.cajonDescargarAlNavegador,
        child: BotonPrincipal(
          // `null` apaga el botón: el segundo toque ya no llega a ningún sitio.
          // Son 78 MB por descarga; dos son media tarde de la conexión de allá.
          // La guarda va DENTRO de la función, no sólo en el ternario de fuera.
          //
          // El ternario se evalúa al CONSTRUIR el botón, así que dos toques en el
          // mismo fotograma —que es justo lo que es un doble toque— ejecutan la
          // MISMA función dos veces: el widget no ha tenido tiempo de volver a
          // construirse con el botón ya apagado. El `if` de dentro sí corre en
          // cada toque, y es el que de verdad impide la segunda descarga.
          //
          // El ternario se queda porque es lo que se VE: el botón apagado dice
          // que ya se pulsó.
          alPulsar: _yaSePulso
              ? null
              : () {
                  if (_yaSePulso) return;
                  setState(() => _yaSePulso = true);
                  widget.alDescargar();
                },
          icono: Icons.download_outlined,
          texto: 'Descargar',
        ),
      ),
    ],
  );
}
