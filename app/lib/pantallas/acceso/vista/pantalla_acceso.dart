import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../mapa/anuncio_de_mapa.dart' show enMegas;
import '../../../navegacion/aviso_de_version_nueva.dart'
    show abridorDeLaDescargaProvider;
import '../../../navegacion/portero.dart';
import '../../../nucleo/identidad/entrada_por_accesos.dart';
import '../../../nucleo/plataforma.dart';
import '../datos/oferta_de_la_puerta.dart';
import '../datos/servicio_acceso.dart';
import '../estado/estado_acceso.dart';

/// LA PANTALLA DE ACCESO.
///
/// Sin ella la aplicación entra directa al Panel sin sesión, no descarga nada y
/// todas las pantallas dicen «no se ha descargado todavía» — que es exactamente
/// lo que se vio en `reparto.procovar.cloud`.
///
/// ## Y en la WEB casi nunca se ve, a propósito
///
/// Son dos puertas al mismo sitio (`docs/identidad.md`):
///
///  * **APK y escritorio** → usuario y contraseña. Es lo que hay aquí abajo y no
///    se toca: quien entra se va al patio de un almacén y necesita el par
///    guardado para el día entero sin señal. **Es la razón de ser del proyecto.**
///  * **Web** → el login único. Quien ya entró en Accesos aterriza dentro sin
///    escribir nada, así que esta pantalla **se va sola** a
///    `/api/auth/entrar` y lo único que se ve es un «entrando».
///
/// El formulario sólo aparece en la web **cuando el login único falla**, y
/// entonces dice el motivo y deja entrar igual. Es la diferencia con el patrón
/// de Next, que ahí sólo ofrece «volver a intentarlo»: si Accesos está caído o
/// le falta la llave, la oficina no puede quedarse sin poder repartir.
///
/// **No lleva `Scaffold` ni armazón**: la pone el enrutador
/// (`conArmazon: false`), porque aquí no hay barra lateral que enseñar — no hay
/// a dónde ir todavía — ni selector de sucursal que rellenar, que sale de la
/// sesión que aún no existe.
class PantallaAcceso extends ConsumerStatefulWidget {
  const PantallaAcceso({super.key});

  @override
  ConsumerState<PantallaAcceso> createState() => _PantallaAccesoState();
}

class _PantallaAccesoState extends ConsumerState<PantallaAcceso> {
  final _usuario = TextEditingController();
  final _contrasena = TextEditingController();
  final _formulario = GlobalKey<FormState>();
  bool _verContrasena = false;

  /// SE ENTRÓ Y LA SESIÓN NO SE QUEDÓ. No es lo mismo que la comprobación de
  /// antes de escribir la contraseña: esto ya pasó, con esta cuenta, ahora.
  ///
  /// Existe aparte porque en web la comprobación previa no se hace —allí no hay
  /// promesa de día sin señal que cumplir— pero **el fallo de verdad sí se
  /// dice**: si el navegador no guarda, el botón de entrar no haría nada y la
  /// persona se quedaría delante de un formulario mudo probando una contraseña
  /// que era buena.
  bool _noSeGuardo = false;

  /// LA WEB ENTRA SOLA. `false` en la APK y en el escritorio, siempre.
  late final bool _porAccesos = ref.read(entraPorAccesosProvider);
  late final EntradaPorAccesos _entrada = ref.read(entradaPorAccesosProvider);

  /// `true` mientras el navegador se va al login único. No se pinta el
  /// formulario debajo: enseñar durante medio segundo una casilla de contraseña
  /// que nadie tiene que rellenar **enseña a rellenarla por reflejo**, que es lo
  /// mismo que ya costó el parpadeo del arranque.
  bool _yendoAAccesos = false;

  @override
  void initState() {
    super.initState();
    // A Accesos, y sólo si no venimos rebotados de allí: con un motivo puesto,
    // redirigir otra vez sería un bucle entre las dos páginas en el que nadie
    // puede entrar ni enterarse de por qué. Es la misma guarda que el patrón
    // (`delivery`, `login/page.tsx`).
    if (!_porAccesos || _entrada.motivo != null) return;
    _yendoAAccesos = true;
    // Después del primer fotograma: navegar dentro de `initState` deja a medio
    // montar el árbol que se está construyendo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _entrada.aAccesos());
  }

  @override
  void dispose() {
    _usuario.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!(_formulario.currentState?.validate() ?? false)) return;
    final acceso = await ref
        .read(formularioProvider.notifier)
        .entrar(usuario: _usuario.text, contrasena: _contrasena.text);
    if (acceso == null) return;
    if (!acceso.seGuardo) {
      // ENTRÓ, pero la sesión no se quedó guardada. Se dice AHORA, que es el
      // único momento en el que todavía hay conexión y hay a quién preguntar:
      // descubrirlo mañana es descubrirlo en el patio de un almacén.
      //
      // Y en web se dice igual, aunque allí no haya promesa que romper: sin
      // sesión guardada el interceptor no tiene token que poner y todo
      // respondería 401. Eso es un fallo de verdad, y lo que se quitó de la web
      // es el aparato de PREPARARSE para no tener conexión, no el aviso de que
      // algo acaba de salir mal.
      ref.invalidate(saludDelAlmacenProvider);
      setState(() => _noSeGuardo = true);
      return;
    }
    // Quien mueve la aplicación de sitio es el portero, no esta pantalla.
    await ref.read(porteroProvider).entro(acceso.sesion);
  }

  @override
  Widget build(BuildContext context) {
    // YÉNDOSE A ACCESOS: ni formulario ni promesa ni avisos. Sólo el «un
    // momento», que es la verdad de lo que está pasando.
    if (_yendoAAccesos) return const _YendoAAccesos();

    // POR QUÉ NO SE ENTRÓ SOLA. `null` en la APK y en el escritorio, donde no
    // hay login único que falle, y también en la web cuando todo va bien.
    final motivoDelSSO = _porAccesos ? _entrada.motivo : null;

    final estado = ref.watch(formularioProvider);
    final entrando = estado is Entrando;
    // ¿HAY PROMESA QUE HACER? En web, NO — 15/09/2026.
    //
    // «Una vez dentro, no: puedes seguir trabajando el día entero sin señal» es
    // la regla de la casa y es verdad en la APK y en el escritorio, donde quien
    // entra se va al patio de un almacén. En un navegador es mentira en las dos
    // direcciones: ni hace falta —la web se abre desde internet, siempre— ni se
    // cumple, porque lo que sostiene la sesión ahí es lo que haya en el
    // navegador y nadie le prometió a esa persona un día entero de nada.
    //
    // Y por lo mismo se cae el aviso de «este aparato no guarda la sesión»: sólo
    // existe para decir que la promesa NO se va a poder cumplir. Sin promesa no
    // hay nada que desdecir, y lo que quedaría es un recuadro ámbar diciéndole a
    // alguien que va a tener que volver a entrar en un sitio donde eso es lo
    // normal. **Ni se pinta ni se pregunta**: la comprobación del almacén es una
    // ida y vuelta de verdad, y aquí no la paga nadie.
    final hayPromesaDeDiaSinSenal = ref.watch(trabajaSinConexionProvider);
    // LA OTRA CARA DE LO MISMO: `trabajaSinConexion` es `false` **solo** en la
    // web (`nucleo/plataforma.dart`). Con nombre porque lo que se decide con
    // ella aqui abajo no tiene nada que ver con ninguna promesa: son las dos
    // salidas de la puerta.
    final esLaWeb = !hayPromesaDeDiaSinSenal;
    // LA PROMESA, comprobada. Ver `nucleo/identidad/almacen_sesion.dart`.
    //
    // En web se le pregunta al almacén **sólo si ya falló de verdad**: nada de
    // sondearlo antes por si acaso, que es justo el aparato de prepararse que
    // aquí sobra.
    final salud = (hayPromesaDeDiaSinSenal || _noSeGuardo)
        ? ref.watch(saludDelAlmacenProvider).asData?.value
        : null;
    final guarda = salud?.guarda ?? true;
    // ¿Había datos en el aparato y aun así no hay sesión? Entonces esto no es
    // «entra»: es que la sesión se perdió, y hay que decirlo.
    final sesionPerdida = ref.read(porteroProvider).sesionPerdida;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: Aire.lg,
          vertical: Aire.xxl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(Aire.xl),
            decoration: BoxDecoration(
              color: Colores.blanco,
              border: Border.all(color: Colores.linea),
              borderRadius: BorderRadius.circular(Radios.xl),
              boxShadow: Sombras.md,
            ),
            child: Form(
              key: _formulario,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LA MARCA, y a tamano legible.
                  //
                  // Aqui es donde el logo de PROCOVAR se puede ver de verdad: el
                  // monograma va calado en la caja del camion y a 36 px —lo que
                  // mide el isotipo de la barra lateral— seria una mancha. Esta
                  // pantalla tiene sitio de sobra, y es ademas la primera que ve
                  // cualquiera, asi que es la que tiene que decir de quien es
                  // esto antes de pedir una contrasena.
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radios.xl),
                      child: Image.asset(
                        'assets/marca/logo.png',
                        width: 72,
                        height: 72,
                        // Sin esto el navegador la interpola al encoger y los
                        // trazos del monograma —que son finos— salen sucios.
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                  const SizedBox(height: Aire.md),
                  Text(
                    'Reparto',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: Aire.xs),
                  Text(
                    'Entra con tu usuario de Procovar.',
                    textAlign: TextAlign.center,
                    style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
                  ),
                  if (motivoDelSSO != null) ...[
                    const SizedBox(height: Aire.lg),
                    _NoEntroPorAccesos(
                      motivo: motivoDelSSO,
                      alReintentar: _entrada.aAccesos,
                    ),
                  ],
                  if (sesionPerdida) ...[
                    const SizedBox(height: Aire.lg),
                    const _SesionPerdida(),
                  ],
                  if (!guarda) ...[
                    const SizedBox(height: Aire.lg),
                    _NoGuarda(
                      motivo: salud!.motivo!,
                      hayPromesaDeDiaSinSenal: hayPromesaDeDiaSinSenal,
                    ),
                  ],
                  const SizedBox(height: Aire.xl),
                  TextFormField(
                    controller: _usuario,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    enabled: !entrando,
                    decoration: const InputDecoration(
                      labelText: 'Usuario o correo',
                      prefixIcon: Icon(Icons.person_outline, size: 20),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Escribe tu usuario.'
                        : null,
                  ),
                  const SizedBox(height: Aire.md),
                  TextFormField(
                    controller: _contrasena,
                    autofillHints: const [AutofillHints.password],
                    obscureText: !_verContrasena,
                    enabled: !entrando,
                    // Entrar con la tecla de intro: con guantes en el patio de
                    // un almacén, buscar el botón es un paso de más.
                    onFieldSubmitted: (_) => entrando ? null : _entrar(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(
                        tooltip: _verContrasena ? 'Ocultar' : 'Ver',
                        icon: Icon(
                          _verContrasena
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _verContrasena = !_verContrasena),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Escribe tu contraseña.'
                        : null,
                  ),
                  if (estado is NoEntro) ...[
                    const SizedBox(height: Aire.lg),
                    _Aviso(fallo: estado.fallo),
                  ],
                  const SizedBox(height: Aire.xl),
                  // LA RUEDA BLANCA SE FUE CON EL RELLENO — 28/09/2026.
                  //
                  // Mientras se entraba, el botón cambiaba la palabra por un
                  // `CircularProgressIndicator` **en blanco**, escrito así
                  // porque debajo había un rectángulo macizo del color de la
                  // marca. Quitado el relleno, esa rueda quedaba blanca sobre el
                  // papel crema: invisible, o sea un botón que al pulsarlo se
                  // queda vacío y no dice nada.
                  //
                  // Ahora lo dice con las dos cosas que sí se ven sin fondo: el
                  // rótulo y el glifo. El reloj de arena es el mismo que ya usan
                  // «Traer el día» y «Entregar el día» para lo mismo, así que es
                  // el gesto de esperar que esta aplicación ya tiene.
                  BotonPrincipal(
                    icono: entrando ? Icons.hourglass_top : Icons.login,
                    texto: entrando ? 'Entrando…' : 'Entrar',
                    alPulsar: entrando ? null : _entrar,
                  ),
                  // LA PROMESA DEL DÍA SIN SEÑAL — sólo donde hay día sin señal.
                  // En web no se escribe ninguna frase en su lugar: no hay nada
                  // que avisar, y una línea puesta para llenar el hueco es una
                  // línea que nadie lee.
                  if (hayPromesaDeDiaSinSenal) ...[
                    const SizedBox(height: Aire.md),
                    Text(
                      // La regla de la casa, dicha antes de que haga falta:
                      // quien se queda sin señal en la calle no tiene a quién
                      // preguntar.
                      //
                      // **O se cumple, o no se promete.** Si este aparato no
                      // puede guardar la sesión, la frase de siempre es mentira
                      // y no se escribe: lo que se escribe es lo que de verdad
                      // va a pasar. El aviso de arriba dice el resto.
                      guarda
                          ? 'Para entrar hace falta conexión. Una vez dentro, '
                                'no: puedes seguir trabajando el día entero sin '
                                'señal.'
                          : 'Para entrar hace falta conexión, y en este aparato '
                                'hará falta cada vez que abras la aplicación.',
                      textAlign: TextAlign.center,
                      style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
                    ),
                  ],
                  // LAS DOS SALIDAS DE LA PUERTA — **SOLO EN LA WEB**.
                  //
                  // El porque entero, destino por destino, esta en
                  // `../datos/oferta_de_la_puerta.dart`. En dos lineas: la web
                  // es el unico sitio donde la aplicacion NO esta instalada, y
                  // el unico donde quien mira ya esta en un navegador.
                  //
                  // Este `if` es **la** linea que separa los destinos, y es la
                  // que se rompe para comprobar que hay pruebas que lo cazan
                  // (`test/pantallas/acceso/salidas_de_la_puerta_test.dart`).
                  // Ademas de decidir, evita la peticion: en la APK y en el
                  // escritorio `ofertaDeLaPuertaProvider` no llega a
                  // construirse, asi que no sale nada a la red desde la puerta.
                  if (esLaWeb) ...[
                    const SizedBox(height: Aire.xl),
                    const _SalidasDeLaPuerta(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// BAJARSE LA APLICACION E IRSE AL PORTAL, debajo del formulario de la web.
///
/// Van juntas y debajo de «Entrar» porque son lo segundo: quien llega aqui viene
/// a entrar. Separadas por una linea para que no se lean como parte del
/// formulario.
class _SalidasDeLaPuerta extends ConsumerWidget {
  const _SalidasDeLaPuerta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `asData?.value`: mientras la pregunta esta en vuelo no se pinta nada, y si
    // fallo tampoco. No hay rueda ni hueco reservado — nadie esta esperando
    // esto, y un sitio que parpadea debajo del boton de entrar mueve el boton
    // bajo el dedo de quien iba a pulsarlo.
    final oferta = ref.watch(ofertaDeLaPuertaProvider).asData?.value;
    // El mismo abridor que usa el aviso de version nueva, y por el mismo motivo:
    // dentro de una prueba no hay sistema operativo al otro lado, y lo que hay
    // que poder comprobar es **que se pidio abrir ese enlace**.
    final abrir = ref.read(abridorDeLaDescargaProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: Colores.linea, height: 1),
        const SizedBox(height: Aire.lg),
        // SIN ANUNCIO NO HAY BOTON. Nada de un enlace muerto ni de un boton
        // apagado con una explicacion: nadie vino a descargarse nada.
        if (oferta != null) ...[
          OutlinedButton.icon(
            onPressed: () => unawaited(abrir(oferta.enlace)),
            icon: const Icon(Icons.download_outlined, size: 18),
            // EL TAMANO VA EN EL BOTON, no en la letra de debajo. Son ~77 MB, y
            // con la conexion de alla pulsar sin saberlo es la tarde de datos de
            // alguien. Y «para Android» tambien va en el boton: esta pagina se
            // abre igual desde un ordenador, y ahi este fichero no sirve.
            label: Text(switch (oferta.bytes) {
              final int b =>
                'Descargar la aplicación para Android '
                    '(${enMegas(b)})',
              // Una api anterior al 22/09/2026 no manda `ficheros`. No se
              // inventa un numero ni se escribe «? MB»: se dice abajo que no
              // se sabe.
              null => 'Descargar la aplicación para Android',
            }),
          ),
          const SizedBox(height: Aire.xs),
          Text(
            'Versión ${oferta.version}. Se descarga el APK; ábrelo en el '
            'teléfono para instalarlo. La aplicación instalada trabaja sin '
            'señal; esta página, no.',
            style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
          ),
          if (oferta.bytes == null) ...[
            const SizedBox(height: Aire.xs),
            Text(
              'El servidor no dice cuánto pesa: bájalo con wifi.',
              style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
            ),
          ],
          const SizedBox(height: Aire.md),
        ],
        // EL PORTAL NO DEPENDE DE LA API, asi que sale siempre — tambien el dia
        // que no haya nada colgado o el servidor no conteste.
        TextButton.icon(
          onPressed: () => unawaited(abrir(enlaceDelPortal)),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Ir a procovar.cloud'),
        ),
        const SizedBox(height: Aire.xs),
        Text(
          'El portal de Procovar: desde ahí se entra a las demás aplicaciones.',
          style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
        ),
      ],
    );
  }
}

/// «Entrando con tu cuenta de Procovar», mientras el navegador se va.
///
/// No es un adorno: entre que se decide ir a Accesos y que el navegador cambia
/// de página pasa un instante, y lo que no puede haber ahí es una pantalla en
/// blanco — que es indistinguible de la aplicación rota.
class _YendoAAccesos extends StatelessWidget {
  const _YendoAAccesos();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: Aire.md),
        Text(
          'Entrando con tu cuenta de Procovar…',
          style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
        ),
      ],
    ),
  );
}

/// EL LOGIN ÚNICO NO PUDO. Se dice el motivo y se ofrecen las dos salidas.
///
/// Ámbar y no rojo: no es un fallo de quien entra y su contraseña no tiene nada
/// que ver. Y debajo se queda el formulario de siempre, que aquí es la puerta de
/// respaldo — si Accesos está caído, la oficina tiene que poder repartir igual.
class _NoEntroPorAccesos extends StatelessWidget {
  const _NoEntroPorAccesos({required this.motivo, required this.alReintentar});

  final String motivo;
  final void Function() alReintentar;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Recuadro(
        icono: Icons.shield_outlined,
        titulo: 'No se pudo entrar con tu cuenta de Procovar.',
        detalle: EntradaPorAccesos.textoDelMotivo(motivo),
      ),
      const SizedBox(height: Aire.md),
      OutlinedButton.icon(
        onPressed: alReintentar,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Volver a intentarlo'),
      ),
    ],
  );
}

/// LA SESIÓN SE PERDIÓ, y el aparato tiene datos dentro.
///
/// El caso del 15/09/2026: se entró, se bajó el día, se cerró la aplicación y al
/// abrirla pedía la contraseña otra vez con los datos ahí mismo, en el disco. Un
/// formulario mudo deja a esa persona probando su contraseña buena una y otra
/// vez en el patio de un almacén, convencida de que se le olvidó.
class _SesionPerdida extends StatelessWidget {
  const _SesionPerdida();

  @override
  Widget build(BuildContext context) => const _Recuadro(
    icono: Icons.history_toggle_off,
    titulo: 'Tu sesión se perdió.',
    detalle:
        'Los datos que bajaste siguen en el aparato. Para volver a entrar hace '
        'falta señal; no es tu contraseña.',
  );
}

/// ESTE APARATO NO GUARDA LA SESIÓN.
///
/// En la APK y en el escritorio se dice **antes** de escribir la contraseña,
/// porque lo que está en juego es la promesa del día entero sin señal y hay que
/// desdecirla a tiempo. En web no se dice nunca por adelantado —allí no hay tal
/// promesa— y sólo aparece cuando el navegador ya se ha negado a guardar de
/// verdad, que ahí es otra cosa: sin sesión guardada no hay token que poner en
/// las peticiones y la página no sirve para nada.
class _NoGuarda extends StatelessWidget {
  const _NoGuarda({
    required this.motivo,
    required this.hayPromesaDeDiaSinSenal,
  });

  final String motivo;

  /// `true` en la APK y el escritorio. En web cambia qué se explica, porque lo
  /// que se rompe no es lo mismo.
  final bool hayPromesaDeDiaSinSenal;

  @override
  Widget build(BuildContext context) => _Recuadro(
    icono: Icons.lock_open_outlined,
    titulo: motivo,
    detalle: hayPromesaDeDiaSinSenal
        ? 'Vas a poder trabajar todo el día sin señal, pero al cerrar la '
              'aplicación tendrás que entrar otra vez, y para eso hace falta '
              'conexión. Avisa a la oficina antes de irte al almacén.'
        : 'Puede ser una ventana privada o el navegador con los datos del sitio '
              'bloqueados. Ábrelo en una ventana normal y vuelve a entrar: sin '
              'guardar la sesión, la página no se puede quedar dentro.',
  );
}

/// El recuadro ámbar de los dos avisos de arriba. Ámbar y no rojo a propósito:
/// no es un fallo de quien escribe, y volver a probar la contraseña no lo
/// arregla.
class _Recuadro extends StatelessWidget {
  const _Recuadro({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Aire.md),
    decoration: BoxDecoration(
      color: Colores.ambarFondo,
      border: Border.all(color: Colores.ambar.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(Radios.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18, color: Colores.ambar),
        const SizedBox(width: Aire.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: Tipos.texto(
                  tamano: 13,
                  peso: FontWeight.w600,
                  color: Colores.ambar,
                ),
              ),
              const SizedBox(height: Aire.xs),
              Text(
                detalle,
                style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// El fallo, en cristiano y con lo que hay que hacer.
///
/// El 403 `sin_sucursal` se pinta en ámbar y no en rojo **a propósito**: no es
/// un fallo de quien escribe, la contraseña era buena. Es una cuenta sin
/// sucursal, y lo que la arregla es una llamada a la oficina, no volver a
/// probar.
class _Aviso extends ConsumerWidget {
  const _Aviso({required this.fallo});

  final FalloDeAcceso fallo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lee el destino por provider y no llamando a `Destino` para que la prueba
    // de la pareja —«en web no sale / en aparato si sale»— pueda ponerse en el
    // otro lado sin compilar para web.
    final sinConexion = ref.watch(trabajaSinConexionProvider);
    final esAviso =
        fallo.motivo == MotivoDeAcceso.sinSucursal ||
        fallo.motivo == MotivoDeAcceso.cuentaDeBaja ||
        fallo.motivo == MotivoDeAcceso.sinConexion;

    final color = esAviso ? Colores.ambar : Colores.rojo;
    final fondo = esAviso ? Colores.ambarFondo : Colores.rojoFondo;

    return Container(
      padding: const EdgeInsets.all(Aire.md),
      decoration: BoxDecoration(
        color: fondo,
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(Radios.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            switch (fallo.motivo) {
              // El icono tambien cambia: en la web no se dibuja una antena
              // tachada para decir que el servidor no contesta.
              MotivoDeAcceso.sinConexion when !sinConexion =>
                Icons.cloud_off_outlined,
              MotivoDeAcceso.sinConexion => Icons.wifi_off_outlined,
              MotivoDeAcceso.sinSucursal => Icons.store_outlined,
              MotivoDeAcceso.cuentaDeBaja => Icons.no_accounts_outlined,
              _ => Icons.error_outline,
            },
            size: 18,
            color: color,
          ),
          const SizedBox(width: Aire.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fallo.mensaje,
                  style: Tipos.texto(
                    tamano: 13,
                    peso: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (_queHacer(fallo.motivo, sinConexion) != null) ...[
                  const SizedBox(height: Aire.xs),
                  Text(
                    _queHacer(fallo.motivo, sinConexion)!,
                    style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _queHacer(
    MotivoDeAcceso motivo,
    bool sinConexion,
  ) => switch (motivo) {
    MotivoDeAcceso.sinSucursal =>
      'No es un fallo de la aplicación: tu cuenta entró bien. Pide en la '
          'oficina que te den de alta en tu sucursal y vuelve a entrar.',
    MotivoDeAcceso.cuentaDeBaja =>
      'Pregunta en la oficina: la cuenta está dada de baja.',
    MotivoDeAcceso.demasiadosIntentos =>
      'El servidor corta los intentos seguidos para proteger la cuenta.',
    // En la WEB no se habla de señal ni de lo que hay guardado en el aparato.
    // La web se abre desde un navegador con internet: si la pagina cargo, la
    // conexion hay. Lo que falla es el servidor, y decirle «comprueba la señal»
    // a quien esta en la oficina lo manda a mirar donde no es.
    //
    // Paso el 16/09: el acceso de la web fallaba por CORS —auth no autorizaba el
    // origen del reparto— y la pantalla lo contaba como falta de señal. Un fallo
    // de configuracion disfrazado de problema de cobertura.
    MotivoDeAcceso.sinConexion => TextosDeCaida.queHacer(
      sinConexion: sinConexion,
    ),
    _ => null,
  };
}
