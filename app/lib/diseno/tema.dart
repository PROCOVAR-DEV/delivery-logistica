/// EL SISTEMA VISUAL DE DELIVERY, traido tal cual desde la de Next.
///
/// La fuente de verdad es `delivery/src/app/globals.css` y
/// `delivery/tailwind.config.js`. Los numeros de aqui **no son gustos**: son los
/// mismos tokens, convertidos de `rem` a pixeles logicos (1 rem = 16 px).
///
/// El motivo de que exista este fichero es concreto: antes el tema salia de
/// `ColorScheme.fromSeed(seedColor: indigo)`, que se inventa una paleta morada
/// de Material y pinta fondos lilas en los botones, en los menus y en los
/// cajones. Jose abrio la aplicacion desplegada y lo primero que dijo fue «muy
/// cambiado a como esta el de Next». Lo estaba: era otra aplicacion.
///
/// Aqui no hay `fromSeed`. Cada rol del `ColorScheme` esta escrito a mano con el
/// token que le toca.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colores.dart';

/// Los radios del `tailwind.config.js` de delivery, en pixeles.
///
/// `xl: 0.85rem` y `2xl: 1.15rem` estan ahi sobrescritos a proposito: los de
/// Tailwind por defecto (12 y 16) se ven mas duros. Las tarjetas usan `2xl`, los
/// botones y los campos `xl`.
abstract final class Radios {
  /// Lo pequeno: las insignias cuadradas, los chips de una tabla.
  static const double sm = 8;

  /// Los botones de paginacion y los campos dentro de un menu.
  static const double md = 10;

  /// `rounded-xl` — botones, selectores, entradas del menu lateral.
  static const double lg = 13.6;

  /// `rounded-2xl` — LAS TARJETAS. Es el radio que mas se ve.
  static const double xl = 18.4;

  /// `rounded-full`, para las insignias de estado.
  static const double pastilla = 999;
}

/// Las sombras del `tailwind.config.js`. Todas tiran a la tinta calida
/// (`rgba(23,19,14,·)`), nunca al negro puro: sobre el papel `#F7F4EF` una
/// sombra negra se ve gris sucio y es lo que hace que una pantalla parezca de
/// Material por defecto.
abstract final class Sombras {
  static final List<BoxShadow> sm = [
    BoxShadow(
      color: Colores.tintaCon(0.05),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// `shadow-md` — la de las tarjetas del panel.
  static final List<BoxShadow> md = [
    BoxShadow(
      color: Colores.tintaCon(0.10),
      blurRadius: 20,
      spreadRadius: -6,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Colores.tintaCon(0.06),
      blurRadius: 6,
      spreadRadius: -2,
      offset: Offset(0, 2),
    ),
  ];

  /// `shadow-lg` — la tarjeta con el raton encima.
  static final List<BoxShadow> lg = [
    BoxShadow(
      color: Colores.tintaCon(0.14),
      blurRadius: 36,
      spreadRadius: -10,
      offset: Offset(0, 16),
    ),
    BoxShadow(
      color: Colores.tintaCon(0.08),
      blurRadius: 10,
      spreadRadius: -4,
      offset: Offset(0, 4),
    ),
  ];

  /// `shadow-2xl` — el cajon lateral y los menus flotantes.
  static final List<BoxShadow> xl = [
    BoxShadow(
      color: Colores.tintaCon(0.20),
      blurRadius: 56,
      spreadRadius: -14,
      offset: Offset(0, 28),
    ),
  ];
}

/// El aire. Delivery respira en multiplos de 4, y las pantallas grandes usan 24
/// (`p-6`) donde el telefono usa 12 (`p-3`).
abstract final class Aire {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Las tres tipografias REALES de delivery (`src/app/layout.tsx`).
///
/// Los `.ttf` estan embebidos en `assets/google_fonts/`, asi que
/// `allowRuntimeFetching` se apaga: esto se abre en el patio de un almacen y una
/// tipografia que se baja por red es una pantalla que sale con otra letra.
abstract final class Tipos {
  /// Bricolage Grotesque. Los titulos y las cifras grandes.
  static TextStyle display({
    double? tamano,
    FontWeight peso = FontWeight.w700,
    Color? color,
    double? interletra,
    double? alto,
  }) => GoogleFonts.bricolageGrotesque(
    fontSize: tamano,
    fontWeight: peso,
    color: color,
    // `letter-spacing: -0.018em` del `globals.css`, en pixeles.
    letterSpacing: interletra ?? (tamano == null ? null : -0.018 * tamano),
    height: alto,
  );

  /// Hanken Grotesk. Todo el texto corrido.
  static TextStyle texto({
    double? tamano,
    FontWeight peso = FontWeight.w400,
    Color? color,
    double? interletra,
    double? alto,
  }) => GoogleFonts.hankenGrotesk(
    fontSize: tamano,
    fontWeight: peso,
    color: color,
    letterSpacing: interletra,
    height: alto,
  );

  /// JetBrains Mono, **con cifras de ancho fijo**.
  ///
  /// Lo de `tabular-nums` no es un adorno: los folios, los kilos y los importes
  /// van en columna, y con cifras de ancho variable el `1` es mas estrecho que
  /// el `8` y las unidades dejan de estar alineadas entre filas.
  static TextStyle mono({
    double? tamano,
    FontWeight peso = FontWeight.w500,
    Color? color,
    double? alto,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: tamano,
    fontWeight: peso,
    color: color,
    height: alto,
    letterSpacing: tamano == null ? null : -0.01 * tamano,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Cifras de ancho fijo **sin cambiar de familia**: para los numeros que van
  /// dentro de un texto normal o de una cifra de titular.
  static const List<FontFeature> cifrasEnColumna = [
    FontFeature.tabularFigures(),
  ];
}

/// La escala de texto, con los tamanos que usa delivery de verdad.
///
/// Los nombres son los de Material porque es lo que leen los widgets
/// (`textTheme.titleMedium`), pero lo que hay dentro sale de la de Next:
///
///   displaySmall   2.1rem w800  la cifra de una tarjeta del panel
///   headlineSmall  1.5rem w700  los titulares de una pantalla
///   titleLarge     1.4rem w700  el titulo de la barra superior
///   titleMedium    1.125rem w700  el titulo de un cajon y de una tarjeta
///   titleSmall     0.95rem w700  la cabecera de una tabla
///   bodyMedium     0.875rem w400  `text-sm`, el tamano por defecto de todo
///   bodySmall      0.75rem w400  `text-xs`, las notas
///   labelSmall     0.6875rem w600 `text-[11px]`, las insignias
TextTheme _escala() => TextTheme(
  displayLarge: Tipos.display(tamano: 44, peso: FontWeight.w800, alto: 1.05),
  displayMedium: Tipos.display(tamano: 38, peso: FontWeight.w800, alto: 1.05),
  displaySmall: Tipos.display(tamano: 33.6, peso: FontWeight.w800, alto: 1),
  headlineLarge: Tipos.display(tamano: 30, peso: FontWeight.w700, alto: 1.1),
  headlineMedium: Tipos.display(tamano: 26, peso: FontWeight.w700, alto: 1.15),
  headlineSmall: Tipos.display(tamano: 24, peso: FontWeight.w700, alto: 1.15),
  titleLarge: Tipos.display(tamano: 22.4, peso: FontWeight.w700, alto: 1.2),
  titleMedium: Tipos.display(tamano: 18, peso: FontWeight.w700, alto: 1.25),
  titleSmall: Tipos.display(tamano: 15.2, peso: FontWeight.w700, alto: 1.3),
  bodyLarge: Tipos.texto(tamano: 15, alto: 1.5),
  bodyMedium: Tipos.texto(tamano: 14, alto: 1.5),
  bodySmall: Tipos.texto(tamano: 12.5, alto: 1.45),
  labelLarge: Tipos.texto(tamano: 14, peso: FontWeight.w600, alto: 1.2),
  labelMedium: Tipos.texto(tamano: 12, peso: FontWeight.w600, alto: 1.2),
  labelSmall: Tipos.texto(
    tamano: 11,
    peso: FontWeight.w600,
    alto: 1.2,
    interletra: 0.2,
  ),
);

/// El tema de la aplicacion.
/// EL ANILLO DEL FOCO, para que se vea por donde va el tabulador.
///
/// Sin esto, quien recorre la pantalla con el teclado no sabe donde esta parado:
/// pulsar Tab no ensena nada y hay que adivinar. Se descubrio mirandolo en el
/// navegador el 15/09/2026, y es la clase de fallo que no aparece en ninguna
/// prueba porque nadie prueba con el teclado.
///
/// Va en TINTA y no en el primario: el primario es el fondo del boton relleno, y
/// un anillo azul sobre azul no es un anillo. Dos pixeles, que es lo que se ve
/// de reojo sin pedir la vista cuando no hay foco.
///
/// [enCalma] es el borde que ya tenia el boton cuando NO esta enfocado — el
/// contorno fino del `OutlinedButton`, por ejemplo. Sin el, enfocar y soltar le
/// borraria su borde de siempre.
WidgetStateProperty<BorderSide?> anilloDeFoco({BorderSide? enCalma}) =>
    WidgetStateProperty.resolveWith<BorderSide?>(
      (estados) => estados.contains(WidgetState.focused)
          ? const BorderSide(color: Colores.tinta, width: 2)
          : enCalma,
    );

/// LOS TRES NIVELES DE BOTON — 28/09/2026. AQUI VIVE LA DECISION.
///
/// Jose, y **no era la primera vez que lo decia**:
///
///     «y arregla los botones te dije bien claro q sin background y de colores
///      y los bordes y iconos lo difrerenciaban»
///
/// **Los botones van SIN FONDO.** Lo que separa uno de otro es el **color**, el
/// **borde** y el **icono**, nunca un rectangulo relleno. Esta escrito tambien
/// en el §4 del `CLAUDE.md` de la raiz, porque la vez anterior se perdio por no
/// estar escrito en ninguna parte y costo que lo repitiera.
///
/// # Por que esto esta AQUI y no en cada pantalla
///
/// El dia que se escribio esto habia **51 `FilledButton`** repartidos por la
/// aplicacion. Cambiarlos a mano uno a uno es garantizar que dentro de un mes
/// conviven dos aspectos y nadie sabe cual es el bueno — es exactamente lo que
/// paso con `primarioTenue`, contado en `colores.dart`: un token congelado en un
/// numero sobrevivio a que la marca cambiara de color. Un relleno suelto en un
/// fichero es la misma trampa con otra ropa.
///
/// Asi que el tema manda: `filledButtonTheme` y `elevatedButtonTheme` toman
/// [principal], `outlinedButtonTheme` toma [secundario], y lo destructivo —que
/// Material no tiene— sale de [BotonDestructivo], que ademas le obliga a llevar
/// su icono.
///
/// # EL ICONO NO LO PUEDE PONER UN `ButtonStyle`, Y ESE ERA EL AGUJERO
///
/// De los tres rasgos, el tema solo sabe poner dos. El icono es un hijo del
/// widget, no una propiedad del estilo, asi que el 28/09/2026 —el mismo dia que
/// se quitaron los rellenos— la aplicacion se quedo con **25 `FilledButton(`
/// sin icono contra 9 `FilledButton.icon(`**: la mayoria de las acciones
/// principales tenian dos rasgos de los tres, y el que faltaba era justo el que
/// se lee de reojo, con sol y sin distinguir colores.
///
/// Por eso el principal entra por [BotonPrincipal], igual que lo destructivo
/// entra por [BotonDestructivo]: **el icono es obligatorio en el constructor**.
/// Un `FilledButton(...)` pelado no puede volver a aparecer sin que alguien lo
/// escriba a proposito, y hay una prueba que barre `lib/` buscandolos
/// (`el_principal_lleva_su_icono_test.dart`).
///
/// Y el icono es **el de la accion**, uno por uno: guardar una papeleta, anadir
/// un mas, imprimir una impresora, reintentar una flecha en redondo. El mismo
/// glifo en los veinticinco no diferencia nada, que es exactamente lo que se
/// vino a arreglar. Si una accion no tiene glifo honesto, **no se le pone uno
/// cualquiera**: se dice y se decide.
///
/// # La jerarquia no desaparece, CAMBIA DE MATERIAL
///
/// Antes se leia por relleno: el principal iba macizo y el resto no. Ahora se
/// lee por tres cosas a la vez, y las tres tienen que sostenerla solas porque
/// no todo el mundo distingue los colores igual:
///
/// | nivel | color | borde | icono |
/// |---|---|---|---|
/// | principal (`+ Nueva Ruta`, `Guardar`) | [Colores.primario], el oro legible | **2 px** del mismo oro | **obligatorio**, y es el de SU accion — lo pone [BotonPrincipal] |
/// | secundario (`Cierre`, `Cancelar`) | [Colores.tinta] | **1 px** de [Colores.lineaFuerte] | opcional |
/// | destructivo (`Eliminar`, `Borrar la columna`) | [Colores.rojo] | **2 px** rojo | **obligatorio**, y es una papelera |
///
/// El grosor separa el principal del secundario **sin mirar el color** (2 contra
/// 1), y el color separa el principal del destructivo **sin mirar el grosor**
/// (el oro y el rojo estan a 66 grados de tono, que es la misma distancia que
/// `paleta_test.dart` ya exige entre dos insignias). El destructivo queda a dos
/// senales de distancia del secundario: color y grosor. Ninguno de los tres
/// depende de un solo rasgo.
///
/// # EL CONTRASTE NO ES UN GUSTO
///
/// Esto se usa en la calle, con sol y con un telefono barato. Un contorno flojo
/// sobre el crema del papel **no existe**, y un boton que no se ve es un boton
/// que no se pulsa.
///
/// Por eso el principal va en [Colores.primario] —el oro **oscurecido hasta que
/// se lee**— y NO en [Colores.marca]: el oro tal cual da 2,0 de contraste sobre
/// el papel, o sea que como contorno es una raya que se adivina. Eso ya estaba
/// escrito en `colores.dart` para el texto («lo que se pulsa lleva marca y lo
/// que se escribe lleva primario») y hoy cambia de lado: **si el boton no tiene
/// relleno, todo lo que se ve de el es texto y linea**, asi que todo el boton va
/// en el tono de texto. `botones_sin_fondo_test.dart` mide los tres contra el
/// papel y contra el blanco de una tarjeta.
///
/// # EL AREA DE TOQUE NO ENCOGE
///
/// Quitar el fondo no puede quitar sitio donde poner el dedo. El aire de dentro
/// se queda igual que antes (16/12 el principal, 12/10 el secundario) y
/// `tapTargetSize` sigue en `padded`, que es lo que garantiza los 48 px de
/// Material aunque el boton se dibuje mas bajo. Hay una prueba que lo **mide**
/// con `tester.getRect` a 390 y a 1400, porque esto es justo lo que se pierde
/// sin darse cuenta.
///
/// Y de ahi sale una regla de al lado: **`VisualDensity.compact` en un boton con
/// texto esta prohibido**. Le quita 8 px a cada lado del blanco tactil y deja el
/// objetivo en 40; con un relleno detras al menos se veia donde apuntar, sin el
/// no se ve nada. Se quito el 28/09/2026 de los dos botones del aviso de version
/// nueva, que eran **los dos unicos botones con texto** que lo llevaban en toda
/// la aplicacion.
///
/// Los `IconButton` y los `Chip` que lo siguen llevando —la paginacion, la ✕ de
/// un filtro, el menu de una columna— son otra cosa y se quedan: ahi el objetivo
/// es un cuadrado con un glifo dentro y la regla de al lado es la contraria, la
/// del apartado de aqui abajo. Esto no los cubre, y **sus 40 px siguen siendo
/// una deuda**, pero no es la deuda que se paga quitando rellenos.
///
/// # LO QUE TIENE CAJA SE PEGA AL BORDE; LO QUE NO LA TIENE, NO
///
/// Esto se midio el 28/09/2026 y vivia en una pieza aparte de `diseno/`, escrita
/// por la manana para alinear el «Eliminar» de una tarjeta de ruta. Al darle caja
/// y borde a los botones esa pieza se quedo con cero usos y se borro entera —el
/// §4 del `CLAUDE.md`, «quitar algo es quitarlo ENTERO»—, **pero lo que sabia
/// no**: es lo unico de todo aquello que estaba medido, y sigue mandando sobre
/// lo que se coloca en el borde de una tarjeta. Por eso esta aqui y no alli.
///
/// En una tarjeta hay dos clases de cosas en el borde y **no se colocan igual**:
///
///   · **Las que tienen caja** —una insignia, un `Chip`, y desde hoy CUALQUIER
///     boton de [Botones], que va con su contorno—. Su borde visible ES su
///     rectangulo, asi que pegar el rectangulo al borde del contenido las deja
///     donde toca.
///   · **Las que no la tienen** —un `TextButton` pelado, un `IconButton`—. Ahi
///     lo unico que se ve es el texto o el glifo, y Material le pone **12 px de
///     aire propio** entre su rectangulo y su texto. Pegar el rectangulo al
///     borde deja el texto 12 px mas adentro, y el ojo lee eso como un diente de
///     sierra.
///
/// Los numeros, medidos con `tester.getRect` en la tarjeta de ruta a 390 px y no
/// a ojo: el borde del contenido de la tarjeta estaba en **x = 374**; la caja
/// del `TextButton` de «Eliminar» acababa tambien en 374 y **su texto en 362**.
/// Esos 12 px son la sangria que el propio mando trae dentro — no un gusto, y
/// por eso no se arregla con un `Padding(right: 4)` puesto a ojo en cada
/// fichero.
///
/// Hoy, con contorno, el caso se da la vuelta: el borde ES el rectangulo, asi
/// que quitarle la sangria pondria la palabra encima de su propia linea. Lo que
/// sigue vivo de esto es la regla de arriba, y su excepcion: **a un `IconButton`
/// no se le quita el aire de un lado nunca** —es un cuadrado de 40x40 con un
/// glifo de 20 dentro; quitarle 12 lo deja en 28 de ancho de toque y ademas
/// descentra el glifo dentro de su propio circulo de pulsacion—. Ahi lo que se
/// aparta es lo de al lado.
abstract final class Botones {
  /// El grosor del contorno de una accion principal y de una destructiva.
  ///
  /// Dos pixeles, no uno: es lo que hace que el borde se lea como «esto es el
  /// boton» y no como «esto es una caja». Un pixel es lo que lleva cualquier
  /// campo y cualquier tarjeta de la aplicacion, asi que un principal de 1 px se
  /// confundiria con el fondo de la pantalla.
  static const double grosorFuerte = 2;

  /// El contorno de una accion secundaria. Uno, el mismo de las tarjetas.
  static const double grosorFino = 1;

  /// EL MINIMO QUE MIDE UN BOTON POR DONDE SE TOCA. Los 48 px de Material, y no
  /// son negociables.
  ///
  /// Esta escrito con nombre y no repetido a ojo porque es lo primero que se
  /// pierde al quitar rellenos: un boton sin fondo parece mas pequeno, y de ahi
  /// a meterlo en un renglon de 32 hay un paso. Lo que le da los 48 a un boton
  /// suelto es `tapTargetSize: padded`; este numero es para cuando el boton va
  /// dentro de una caja de alto fijo —una fila de tarjeta, una barra— y la caja
  /// manda. `botones_sin_fondo_test.dart` lo **mide** con `tester.getRect`.
  static const double altoTactilMinimo = 48;

  /// El aire de un boton principal o destructivo. Es **el de antes**: quitar el
  /// fondo no toca el sitio donde cae el dedo.
  static const EdgeInsets aireDelPrincipal = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  );

  /// El aire de un boton secundario. Tambien el de antes.
  static const EdgeInsets aireDelSecundario = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  );

  /// LA ACCION PRINCIPAL de una pantalla: `+ Nueva Ruta`, `Armar la ruta de
  /// esta zona`, `Guardar`. Oro legible, contorno de 2 px del mismo oro.
  static ButtonStyle principal() => _nivel(
    tono: Colores.primario,
    grosor: grosorFuerte,
    aire: aireDelPrincipal,
    peso: FontWeight.w600,
    radio: Radios.lg,
  );

  /// LA ACCION SECUNDARIA: `Cierre`, `Ver e imprimir`, `Cancelar`. Tinta, con el
  /// contorno fino de la casa. No compite con la principal y aun asi se ve que
  /// es un boton y no una etiqueta.
  ///
  /// El borde va en [Colores.lineaDeMando] y no en [Colores.linea] ni en
  /// [Colores.lineaFuerte]. Esas dos son para una raya que ACOMPANA a algo que
  /// ya se ve —el canto de una tarjeta, el contorno de una casilla vacia—; aqui
  /// la raya **es** el mando, porque debajo no hay relleno ninguno. La fuerte da
  /// 1,7 de contraste sobre el papel, o sea que al sol no esta; lo cazo
  /// `botones_sin_fondo_test.dart` el mismo dia que se escribio esto, midiendo,
  /// y de ahi salio el token nuevo.
  static ButtonStyle secundario() => _nivel(
    tono: Colores.tinta,
    borde: Colores.lineaDeMando,
    grosor: grosorFino,
    aire: aireDelSecundario,
    peso: FontWeight.w500,
    radio: Radios.lg,
  );

  /// LA ACCION DESTRUCTIVA: `Eliminar`, `Borrar la columna`. Rojo de «impide»,
  /// contorno de 2 px del mismo rojo, y **siempre con icono de papelera** — eso
  /// ultimo no lo puede poner un `ButtonStyle`, lo pone [BotonDestructivo], que
  /// es por donde tiene que entrar.
  ///
  /// Antes esto era el unico boton con el relleno cambiado
  /// (`backgroundColor: Colores.rojo` en `tablero/vista/acciones.dart`) y era lo
  /// que lo separaba de los demas. **Se sigue separando**: es el unico rojo de
  /// la pantalla y el unico que ensena una papelera.
  static ButtonStyle destructivo() => _nivel(
    tono: Colores.rojo,
    grosor: grosorFuerte,
    aire: aireDelPrincipal,
    peso: FontWeight.w600,
    radio: Radios.lg,
  );

  /// EL ELEGIDO DE UN GRUPO DE TRES, en el color de su estado.
  ///
  /// Es lo que usa el cierre de ruta para «Entregado / Devuelto / Cancelado»:
  /// ahi el color no dice jerarquia, dice **que estado es**, y lo que hay que
  /// ver de un vistazo es cual de los tres esta marcado. Se marcaba rellenando
  /// el elegido; ahora se marca con el contorno de 2 px en su color y un visto
  /// delante, contra el contorno fino y el texto apagado de los otros dos.
  static ButtonStyle elegidoDelGrupo(Color color) => _nivel(
    tono: color,
    grosor: grosorFuerte,
    aire: aireDelSecundario,
    peso: FontWeight.w700,
    radio: Radios.lg,
  );

  /// Uno del grupo que NO esta elegido.
  static ButtonStyle sueltoDelGrupo(Color color) => _nivel(
    tono: Colores.tintaSuave,
    borde: color.withValues(alpha: 0.30),
    grosor: grosorFino,
    aire: aireDelSecundario,
    peso: FontWeight.w400,
    radio: Radios.lg,
  );

  /// El texto y el contorno de un boton apagado.
  ///
  /// Apagado tiene que leerse como apagado **y seguir leyendose**: un gris que
  /// no se distingue del papel deja al de al lado sin saber si el boton esta ahi
  /// o no. Es la tinta suave a media asta, que sobre papel sigue por encima del
  /// 3 que pide un texto grande.
  static final Color apagado = Colores.tintaSuave.withValues(alpha: 0.45);

  static ButtonStyle _nivel({
    required Color tono,
    required double grosor,
    required EdgeInsets aire,
    required FontWeight peso,
    required double radio,
    Color? borde,
  }) {
    final tonoDelBorde = borde ?? tono;
    return ButtonStyle(
      // ─── SIN FONDO ──────────────────────────────────────────────────────
      //
      // Escrito para TODOS los estados y no solo para el de reposo. Si aqui
      // fuera un `resolveWith` que solo contesta en calma, Material rellenaria
      // el boton al pasarle el raton por encima y volveriamos a tener un
      // rectangulo macizo, justo lo que se vino a quitar. Lo que pinta el paso
      // del dedo es `overlayColor`, que es un velo del propio tono y no un
      // fondo.
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      foregroundColor: WidgetStateProperty.resolveWith(
        (e) => e.contains(WidgetState.disabled) ? apagado : tono,
      ),
      // El icono va del MISMO color que el texto. Sin esta linea Material le
      // pone el `iconTheme` de la aplicacion —tinta suave— y el icono de un
      // boton destructivo saldria gris al lado de una palabra roja.
      iconColor: WidgetStateProperty.resolveWith(
        (e) => e.contains(WidgetState.disabled) ? apagado : tono,
      ),
      overlayColor: WidgetStateProperty.resolveWith((e) {
        if (e.contains(WidgetState.pressed)) {
          return tono.withValues(alpha: 0.18);
        }
        if (e.contains(WidgetState.hovered)) {
          return tono.withValues(alpha: 0.10);
        }
        return null;
      }),
      // EL BORDE, que ahora es la mitad de lo que se ve del boton — y el anillo
      // del foco, que sigue mandando sobre el cuando el tabulador pasa por aqui
      // (el porque, en [anilloDeFoco]).
      side: WidgetStateProperty.resolveWith((e) {
        if (e.contains(WidgetState.focused)) {
          return const BorderSide(color: Colores.tinta, width: 2);
        }
        if (e.contains(WidgetState.disabled)) {
          return BorderSide(color: Colores.linea, width: grosor);
        }
        return BorderSide(color: tonoDelBorde, width: grosor);
      }),
      padding: WidgetStatePropertyAll(aire),
      textStyle: WidgetStatePropertyAll(Tipos.texto(tamano: 14, peso: peso)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
      ),
      // 18 y no 20: el glifo va al lado de un texto de 14 y con 20 pesa mas que
      // la palabra que explica.
      iconSize: const WidgetStatePropertyAll(18),
      // LOS 48 PX. Es lo unico que los garantiza cuando el boton se dibuja mas
      // bajo que eso, y por eso esta escrito aqui y no se hereda: quitar el
      // relleno no puede quitar sitio donde poner el dedo.
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      alignment: Alignment.center,
    );
  }
}

/// LA ACCION PRINCIPAL DE UNA PANTALLA, con su icono puesto — 28/09/2026.
///
/// Es el hermano de [BotonDestructivo] y existe por lo mismo: **el icono es uno
/// de los tres rasgos que diferencian un nivel** ([Botones]) y un `ButtonStyle`
/// no puede poner un icono. Mientras lo principal se pidiera con
/// `FilledButton(...)`, el color y el borde los ponia el tema y el icono lo
/// ponia quien se acordara — y no se acordaba casi nadie: 25 de 34.
///
/// Por aqui no se puede olvidar. [icono] **no tiene valor por defecto**, y eso
/// es la pieza entera:
///
///   · en [BotonDestructivo] la papelera SI es el valor por defecto, porque
///     borrar es siempre lo mismo y el glifo de borrar es siempre el mismo;
///   · aqui no hay «el icono del principal». Guardar no se parece a Imprimir ni
///     a Reintentar, y un glifo unico repetido veinticinco veces es ruido que
///     ademas **miente**: dice que las veinticinco acciones son la misma.
///
/// Asi que el compilador pregunta cual, una por una. Y cuando la respuesta
/// honesta sea «ninguno», eso **no se tapa con un glifo de relleno**: se dice, y
/// se decide si ese mando era de verdad una accion principal o era otra cosa
/// vestida de boton. Paso una vez, con la pestana elegida de
/// `diseno/pestanas.dart`: `Planificadas` no hace nada —dice donde estas— y no
/// existe su glifo. No es un [BotonPrincipal], y lo que lleva no es el icono de
/// una accion sino el visto de «esta es la elegida», el mismo que marca al
/// elegido del grupo de tres del cierre de ruta ([Botones.elegidoDelGrupo]).
/// Escrito aparte y explicado alli.
///
/// El estilo no se escribe aqui: lo pone `filledButtonTheme`, que es
/// [Botones.principal]. Un `style:` suelto en este widget seria el segundo sitio
/// donde mirar, que es justo lo que [Botones] existe para no tener.
class BotonPrincipal extends StatelessWidget {
  const BotonPrincipal({
    required this.texto,
    required this.icono,
    required this.alPulsar,
    this.iconoAlFinal = false,
    this.enUnaLinea = false,
    super.key,
  });

  final String texto;

  /// EL ICONO DE ESTA ACCION. Sin valor por defecto, y a proposito: ver arriba.
  final IconData icono;

  /// `null` lo apaga.
  final VoidCallback? alPulsar;

  /// El glifo al otro lado de la palabra.
  ///
  /// Es para los mandos que **llevan hacia adelante** —«Siguiente» de un
  /// asistente—: una flecha que apunta a la derecha puesta a la izquierda de la
  /// palabra se lee al reves de lo que hace. Con `Icons.arrow_back` de «Volver a
  /// la lista» pasa lo contrario, y por eso ese va delante y este detras.
  final bool iconoAlFinal;

  /// El rotulo en una sola linea, con puntos suspensivos si no cabe.
  ///
  /// Sólo donde el boton vive dentro de un `Flexible` y el texto cambia de largo
  /// solo («Generando ruta...»): ahi, sin esto, a 390 px el renglon se parte y
  /// el boton crece hacia abajo.
  final bool enUnaLinea;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: alPulsar,
    icon: Icon(icono),
    iconAlignment: iconoAlFinal ? IconAlignment.end : IconAlignment.start,
    label: enUnaLinea
        ? Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis)
        : Text(texto),
  );
}

/// UN BOTON DE BORRAR, con su icono puesto.
///
/// Existe por una razon muy concreta: **el icono es uno de los tres rasgos que
/// diferencian un nivel**, y un `ButtonStyle` no puede poner un icono. Si lo
/// destructivo se pidiera con `FilledButton.icon(style: Botones.destructivo())`,
/// el dia que alguien escriba `FilledButton(...)` a secas sale un boton rojo sin
/// papelera y nadie se entera. Por aqui no se puede: el icono es parte del
/// widget.
///
/// El icono por defecto es la papelera. Se puede cambiar —`Icons.logout` para
/// salir de la sesion, por ejemplo— pero **no se puede quitar**, que es lo que
/// vigila `botones_sin_fondo_test.dart`.
class BotonDestructivo extends StatelessWidget {
  const BotonDestructivo({
    required this.texto,
    required this.alPulsar,
    this.icono = Icons.delete_outline,
    super.key,
  });

  final String texto;

  /// `null` lo apaga.
  final VoidCallback? alPulsar;

  /// La papelera, salvo que la accion sea otra clase de destruccion.
  final IconData icono;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: alPulsar,
    style: Botones.destructivo(),
    icon: Icon(icono),
    label: Text(texto),
  );
}

ThemeData temaDeReparto() {
  // Nada de bajar tipografias por red: estan en `assets/google_fonts/`.
  GoogleFonts.config.allowRuntimeFetching = false;

  final texto = _escala().apply(
    bodyColor: Colores.tinta,
    displayColor: Colores.tinta,
  );

  final esquema = ColorScheme(
    brightness: Brightness.light,
    // `primary` es EL RELLENO —el oro del logo—, no el tono de texto: Material
    // lo usa de fondo del `FilledButton` y pone `onPrimary` encima. El tono de
    // texto es `Colores.primario`, que es otra cosa y va en `onPrimaryContainer`.
    //
    // Y `onPrimary` NO se escribe: lo contesta `letrasSobre`. Aqui ponia
    // `Colors.white`, y de ahi salia el «azul con letras blancas». Sobre el oro
    // el blanco da 2,2 de contraste —ilegible— y la tinta da 7,6.
    primary: Colores.marca,
    onPrimary: Colores.sobreMarca,
    primaryContainer: Colores.primarioTenue,
    onPrimaryContainer: Colores.primario,
    secondary: Colores.secundario,
    onSecondary: letrasSobre(Colores.secundario),
    secondaryContainer: Colores.verdeFondo,
    onSecondaryContainer: Colores.verde,
    tertiary: Colores.acento,
    onTertiary: letrasSobre(Colores.acento),
    tertiaryContainer: Colores.ambarFondo,
    onTertiaryContainer: Colores.ambar,
    error: Colores.rojo,
    onError: letrasSobre(Colores.rojo),
    errorContainer: Colores.rojoFondo,
    onErrorContainer: Colores.rojo,
    // El papel y la tinta. `surface` es BLANCO y `scaffoldBackgroundColor` es el
    // papel: es lo que hace que una tarjeta se despegue del fondo sin sombra.
    surface: Colores.blanco,
    onSurface: Colores.tinta,
    surfaceContainerLowest: Colores.blanco,
    surfaceContainerLow: Colores.papel,
    surfaceContainer: Colores.papel,
    surfaceContainerHigh: Colores.grisFondo,
    surfaceContainerHighest: Colores.grisFondo,
    onSurfaceVariant: Colores.tintaSuave,
    outline: Colores.linea,
    outlineVariant: Colores.linea,
    shadow: Colores.tinta,
    scrim: Colores.tinta,
    inverseSurface: Colores.tinta,
    onInverseSurface: Colores.papel,
    inversePrimary: Colores.primarioClaro,
  );

  final bordeFino = OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radios.lg),
    borderSide: BorderSide(color: Colores.linea),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    textTheme: texto,
    // La tipografia por defecto de CUALQUIER `Text` sin estilo: Hanken, no la
    // Roboto del sistema.
    fontFamily: texto.bodyMedium?.fontFamily,
    // TRANSPARENTE a proposito: el papel y su rejilla los pinta [FondoDePapel],
    // que va por debajo de todo en el `builder` de `MaterialApp`. Un `Scaffold`
    // opaco encima taparia la rejilla y volveriamos al gris plano.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colores.papel,
    dividerColor: Colores.linea,
    dividerTheme: DividerThemeData(
      color: Colores.linea,
      thickness: 1,
      space: 1,
    ),
    // Sin efecto de rebote en las tablas: con desplazamiento horizontal propio
    // el rebote hace creer que la tabla se acabo cuando queda media a la derecha.
    splashFactory: InkSparkle.splashFactory,
    // El velo del cajon: negro al 40 %, el del pliego §9.2.
    dialogTheme: DialogThemeData(
      backgroundColor: Colores.blanco,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.xl),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colores.blanco,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.xl),
        side: BorderSide(color: Colores.linea),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colores.papel,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colores.tinta,
      elevation: 0,
      titleTextStyle: texto.titleLarge,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: Colores.blanco,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Border(right: BorderSide(color: Colores.linea)),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: texto.bodyMedium,
      subtitleTextStyle: texto.bodySmall?.copyWith(color: Colores.tintaSuave),
      iconColor: Colores.tintaSuave,
      selectedColor: Colores.primario,
      selectedTileColor: Colores.primarioTenue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.md),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colores.blanco,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colores.tintaCon(0.20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
        side: BorderSide(color: Colores.linea),
      ),
      textStyle: texto.bodyMedium,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colores.blanco),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radios.lg),
            side: BorderSide(color: Colores.linea),
          ),
        ),
      ),
    ),
    // EL ROTULO EMERGENTE. Jose, 17/09/2026: «los tooltips no se ven casi, qué
    // mierda es esto en negro».
    //
    // Era tinta (#17130E, casi negro) con el texto en papel a 12 y peso normal,
    // encima de un mapa a todo color. Tres cosas contra la lectura a la vez:
    // pequeño, delgado y sin nada que lo despegue del fondo. Ahora va a 13 con
    // peso medio, en blanco puro, con su sombra y un reborde tenue — sigue
    // siendo oscuro, que es lo que toca sobre un mapa claro, pero ya se lee.
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Colores.tinta,
        borderRadius: BorderRadius.circular(Radios.sm),
        border: Border.all(color: Colores.blanco.withValues(alpha: 0.18)),
        boxShadow: Sombras.sm,
      ),
      textStyle: Tipos.texto(
        tamano: 13,
        color: Colores.blanco,
        peso: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      waitDuration: const Duration(milliseconds: 300),
    ),
    // LOS BOTONES. Radio `xl` (13.6) y la tipografia de texto, no la de titular:
    // en delivery los botones son `text-sm font-medium`.
    //
    // **NINGUNO LLEVA FONDO**, y eso no se decide aqui: sale de [Botones], que
    // es donde esta contado el porque y la tabla de los tres niveles. Aqui solo
    // se enchufa, y se enchufa a los tres temas de golpe **para que los 51
    // `FilledButton` de la aplicacion cambien de una vez** en vez de fichero a
    // fichero, que es como se acaba con dos aspectos conviviendo.
    //
    // `FilledButton` y `ElevatedButton` son la accion PRINCIPAL; `OutlinedButton`
    // es la SECUNDARIA. No se renombra ningun widget: el que ya escribio
    // `FilledButton` pidiendo «el boton importante» sigue pidiendo lo mismo, y
    // lo que cambia es con que se dibuja.
    //
    // **Todos llevan anillo de foco** ([anilloDeFoco], dentro de [Botones]). Sin
    // el, quien recorre la pantalla con el tabulador no sabe donde esta parado:
    // se ve pasar nada. Visto en el navegador el 15/09/2026, pulsando Tab por el
    // Panel entero.
    filledButtonTheme: FilledButtonThemeData(style: Botones.principal()),
    elevatedButtonTheme: ElevatedButtonThemeData(style: Botones.principal()),
    outlinedButtonTheme: OutlinedButtonThemeData(style: Botones.secundario()),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colores.primario,
        textStyle: Tipos.texto(tamano: 14, peso: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radios.md),
        ),
      ).copyWith(side: anilloDeFoco()),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: Colores.tintaSuave,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radios.lg),
        ),
      ).copyWith(side: anilloDeFoco()),
    ),
    iconTheme: IconThemeData(color: Colores.tintaSuave, size: 20),
    // Los campos: fondo blanco, borde fino de `--line`, y el foco en primario
    // — el mismo `outline` del `globals.css`.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colores.blanco,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintStyle: Tipos.texto(tamano: 14, color: Colores.tintaSuave),
      labelStyle: Tipos.texto(tamano: 14, color: Colores.tintaSuave),
      floatingLabelStyle: Tipos.texto(
        tamano: 13,
        peso: FontWeight.w600,
        color: Colores.primario,
      ),
      prefixIconColor: Colores.tintaSuave,
      suffixIconColor: Colores.tintaSuave,
      border: bordeFino,
      enabledBorder: bordeFino,
      disabledBorder: bordeFino,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
        borderSide: BorderSide(color: Colores.primario, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
        borderSide: BorderSide(color: Colores.rojo),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
        borderSide: BorderSide(color: Colores.rojo, width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colores.grisFondo,
      side: BorderSide(color: Colores.linea),
      labelStyle: Tipos.texto(tamano: 12, peso: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.pastilla),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: Colores.lineaFuerte, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(Colores.linea),
      thumbColor: const WidgetStatePropertyAll(Colores.blanco),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: Colores.primario,
      linearTrackColor: Colores.grisFondo,
      circularTrackColor: Colores.grisFondo,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Colores.tinta,
      contentTextStyle: Tipos.texto(tamano: 14, color: Colores.papel),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
      ),
    ),
    // Las barras de desplazamiento finas y calidas del `globals.css`
    // (`scrollbar-color: #cfc7ba transparent`).
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(9),
      radius: const Radius.circular(Radios.pastilla),
      thumbColor: WidgetStateProperty.resolveWith(
        (e) => e.contains(WidgetState.hovered)
            ? Colores.barraEncima
            : Colores.barra,
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: Tipos.texto(
        tamano: 11,
        peso: FontWeight.w600,
        color: Colores.tintaSuave,
        interletra: 0.6,
      ),
      dataTextStyle: texto.bodyMedium,
      dividerThickness: 1,
      headingRowColor: const WidgetStatePropertyAll(Colores.papel),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Colores.primario,
      // El 18 % del `::selection` de delivery, pero de la marca de AHORA: antes
      // era `0x2E1F4FE0`, el azul viejo congelado en un numero.
      selectionColor: Colores.marca.withValues(alpha: 0.28),
      selectionHandleColor: Colores.primario,
    ),
  );
}

/// EL PAPEL CON SU REJILLA.
///
/// El `body::before` del `globals.css`: una cuadricula calida de 32 px al 2,5 %
/// de tinta, que se desvanece hacia abajo con una mascara elíptica. Sin esto el
/// fondo es un gris plano y la aplicacion **se ve de Material**, por muy bien
/// que esten los colores: es la unica pieza del sistema que no se consigue con
/// un `ThemeData`.
///
/// El grano de pelicula del `body::after` no se copia: en Flutter habria que
/// pintar ruido por pixel en cada fotograma y en el portatil de un almacen eso
/// se nota. La rejilla es lo que se lee a simple vista.
class FondoDePapel extends StatelessWidget {
  const FondoDePapel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: Colores.papel),
    child: CustomPaint(
      painter: const _Rejilla(),
      // `isComplex` + `willChange: false`: la rejilla no cambia nunca, asi que
      // se guarda en cache y no se vuelve a trazar en cada fotograma.
      isComplex: true,
      willChange: false,
      child: child,
    ),
  );
}

class _Rejilla extends CustomPainter {
  const _Rejilla();

  /// `background-size: 32px 32px`.
  static const double _paso = 32;

  @override
  void paint(Canvas lienzo, Size medida) {
    if (medida.isEmpty) return;

    // `mask-image: radial-gradient(ellipse 120% 90% at 50% 0%, #000 35%,
    // transparent 100%)`. Se pinta la rejilla y se le aplica la mascara con
    // `dstIn`, que es lo mismo que hace el navegador.
    lienzo.saveLayer(Offset.zero & medida, Paint());

    final trazo = Paint()
      ..color = Colores.tintaCon(0.025)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= medida.width; x += _paso) {
      lienzo.drawLine(Offset(x, 0), Offset(x, medida.height), trazo);
    }
    for (var y = 0.0; y <= medida.height; y += _paso) {
      lienzo.drawLine(Offset(0, y), Offset(medida.width, y), trazo);
    }

    // `ellipse 120% 90% at 50% 0%`: el radio vertical es el 90 % del alto. Se
    // usa un circulo de ESE radio y no una elipse porque `RadialGradient` de
    // Flutter no es eliptico, y lo que se lee a simple vista es el desvanecido
    // de arriba abajo, no el de los lados. El rect va cuadrado a proposito:
    // `createShader` toma el radio del lado corto, y con un rect ancho en un
    // telefono estrecho el degradado saldria la mitad de alto.
    final radio = medida.height * 0.9;
    final elipse = Rect.fromCircle(
      center: Offset(medida.width / 2, 0),
      radius: radio,
    );
    lienzo.drawRect(
      Offset.zero & medida,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const RadialGradient(
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.35, 1],
        ).createShader(elipse),
    );

    lienzo.restore();
  }

  @override
  bool shouldRepaint(_Rejilla anterior) => false;
}
