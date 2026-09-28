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
import '../nucleo/actualizacion/comprobador.dart';
import '../mapa/anuncio_de_mapa.dart' show enMegas;
import '../nucleo/actualizacion/version_publicada.dart';
import '../nucleo/plataforma.dart';
import '../nucleo/proveedores.dart';
import '../nucleo/registro/registro.dart';
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
      SePuedeActualizar(:final publicada, :final enlace) => LoQueDiceElAviso(
        firma: 'instalar:${publicada.version}',
        titular: 'Hay una versión nueva: ${publicada.version}',
        detalle:
            publicada.notas ??
            'Se instala a mano: primero se descarga el fichero y después se '
                'instala encima.',
        textoDeAccion: 'Cómo instalarla',
        iconoDeAccion: Icons.install_mobile,
        accion: (contexto) => _abrirElCajon(contexto, publicada, enlace),
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

  void _abrirElCajon(
    BuildContext contexto,
    VersionPublicada publicada,
    String enlace,
  ) {
    // Cajon, como todo en este proyecto — tambien en escritorio, que es la
    // excepcion aprobada el 05/09/2026 (`diseno/cajon.dart`).
    unawaited(
      abrirCajon<void>(
        contexto,
        titulo: 'Versión ${publicada.version}',
        subtitulo: publicada.compilacion == null
            ? null
            : 'compilación ${publicada.compilacion}',
        cuerpo: (dentro) => Column(
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
            Text(switch (publicada.ficheroPara(Plataforma.deEsteAparato())) {
              // CUÁNTO PESA, ANTES DE PULSAR. Quien está en la calle con datos
              // contados tiene que poder decidir. El 22/09/2026 la descarga
              // enseñaba «30 MB/?» porque el tamaño salía del `Content-Length`
              // y Cloudflare lo quita: ahora sale del anuncio de la api.
              final f? =>
                'Son ${enMegas(f.bytes)}. Se abre el navegador y se '
                    'descarga el fichero. La descarga no toca esta aplicación: '
                    'lo que tengas dentro sigue aquí mientras no instales.',
              // Una api anterior no lo manda. No se inventa un número ni se
              // escribe «? MB»: se dice lo demás y ya.
              null =>
                'Se abre el navegador y se descarga el fichero. La '
                    'descarga no toca esta aplicación: lo que tengas dentro '
                    'sigue aquí mientras no instales.',
            }, style: Tipos.texto(tamano: 13, color: Colores.tintaSuave)),
            const SizedBox(height: Aire.md),
            Text(
              'Instálalo con señal y con la cola vacía. No hace falta que sea '
              'ahora: la versión de ahora sigue funcionando.',
              style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
            ),
          ],
        ),
        // UNA DESCARGA POR TOQUE, NO DOS.
        //
        // Jose, 25/09/2026: «cuando le doy a descargar me dispara dos descargas
        // en ves de una». El botón no tenía nada que impidiera dispararse dos
        // veces: un doble toque —o un toque con rebote, que en una pantalla
        // usada con prisa pasa— llamaba dos veces a `launchUrl` y Android
        // arrancaba dos bajadas del mismo APK. Son 78 MB cada una, y con la
        // conexión de allá eso no es un detalle: es la mitad de la tarde.
        //
        // La guarda va en el propio botón y no en el abridor porque lo que hay
        // que impedir es el SEGUNDO TOQUE, no la segunda llamada: apagándolo se
        // ve además que ya se pulsó.
        pie: (dentro) => _PieDeLaDescarga(
          alDescargar: () {
            // SE BAJA LA ÚLTIMA QUE HAYA AHORA, NO LA QUE HABÍA AL ABRIR ESTO.
            //
            // El enlace llega por parámetro desde el momento en que se pintó la
            // franja, y entre eso y el toque puede haber salido otra versión.
            // Pasó el 25/09/2026: se publicó la 1.0.6, y quince minutos después
            // la 1.0.7 con los arreglos de lo que Jose acababa de contar. Él
            // pulsó en los dos momentos y se bajó las dos:
            //
            //     «me mando a descargar la 1.06 y la 1.07 [...] te dije q la
            //      ultima» · «no quiero q actualize todo el tramo»
            //
            // Son 78 MB cada una. Al tocar se vuelve a preguntar cuál es la
            // última AHORA; el `enlace` de antes sólo se usa si en este
            // instante no hay respuesta —quedarse sin descarga sería peor que
            // bajar una versión de hace un minuto—.
            final ahora = ref.read(actualizacionProvider).value;
            final ultimo = ahora is SePuedeActualizar ? ahora.enlace : enlace;

            Navigator.of(dentro).maybePop();
            unawaited(ref.read(abridorDeLaDescargaProvider)(ultimo));
          },
          alCerrar: () => Navigator.of(dentro).maybePop(),
        ),
      ),
    );
  }
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
                        BotonPrincipal(
                          texto: dice.textoDeAccion!,
                          icono: dice.iconoDeAccion!,
                          alPulsar: () => dice.accion?.call(context),
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
      BotonPrincipal(
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
    ],
  );
}
