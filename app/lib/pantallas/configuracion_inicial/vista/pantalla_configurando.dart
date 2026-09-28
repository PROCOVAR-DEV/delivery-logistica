import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../navegacion/portero.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/sincro/bajada.dart';
import '../../../nucleo/sincro/ciclo.dart';
import '../../../nucleo/sincro/recuento.dart';

/// «CONFIGURANDO REPARTO» — lo primero que se ve la primera vez.
///
/// Palabras de Jose, 15/09/2026:
///
/// > «q cuando inicie diga configurando reparto y ya esa es la primera y
/// > despues entonces ya apareceria eso traer el dia»
/// > «aparecio algo en el medio de la pantalla q dijera trayendo datos en caso
/// > de q no tenga; en caso de q lo tenga arranca normal la apk»
///
/// O sea: **entrar ES configurarse el aparato**, y la primera vez eso se ve.
///
/// ## Las cuatro reglas de esta pantalla
///
///  1. **En medio de la pantalla y con el avance a la vista.** No el Panel en
///     ceros mientras las cosas aparecen por detrás: un Panel a cero es
///     indistinguible de una sucursal sin nada que repartir, y con esa pantalla
///     en la mano alguien se va al almacén.
///  2. **Si el aparato ya tiene los datos, no se ve.** Quien decide es el
///     portero mirando la base, no la red (`navegacion/portero.dart`).
///  3. **Si falta algo, se dice y se puede reintentar.** No se entra fingiendo
///     que está.
///  4. **Aquí NO hay botón de «Traer el día».** Ése es para después y vive en
///     otro sitio. Éste es el momento en el que todavía no hay nada.
class PantallaConfigurando extends ConsumerStatefulWidget {
  const PantallaConfigurando({super.key});

  @override
  ConsumerState<PantallaConfigurando> createState() =>
      _PantallaConfigurandoState();
}

class _PantallaConfigurandoState extends ConsumerState<PantallaConfigurando> {
  /// El avance NO RETROCEDE.
  ///
  /// Con el servidor sirviendo en tandas, la segunda vuelta empieza otra vez por
  /// los pedidos y el porcentaje literal volvería al 15 %. Una barra que va
  /// hacia atrás se lee como «algo se ha roto», y lo que está pasando es lo
  /// contrario: que hay tantos datos que no caben de una vez.
  double _masLejos = 0;

  @override
  Widget build(BuildContext context) {
    final portero = ref.read(porteroProvider);
    final configuracion = portero.configuracion;
    final marcha = ref.watch(marchaDelCicloProvider);
    final avance = _cuanto(marcha.avance);
    if (avance > _masLejos) _masLejos = avance;
    final faltoAlgo = configuracion?.faltoAlgo ?? false;

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radios.xl),
                    child: Image.asset(
                      'assets/marca/logo.png',
                      width: 72,
                      height: 72,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
                const SizedBox(height: Aire.md),
                Text(
                  // EL TITULO, literal y sin adornos. Es lo que pidió Jose y es
                  // además lo que de verdad está pasando: no se está «cargando»
                  // una pantalla, se está dejando el aparato listo para trabajar
                  // un día entero sin señal.
                  'Configurando Reparto',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: Aire.xs),
                Text(
                  faltoAlgo
                      ? 'La configuración se quedó a medias.'
                      : 'Es la primera vez en este aparato: se está trayendo '
                            'todo lo del día. Sólo pasa una vez.',
                  textAlign: TextAlign.center,
                  style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
                ),
                const SizedBox(height: Aire.xl),
                if (faltoAlgo)
                  _Falto(configuracion: configuracion!)
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radios.sm),
                    child: LinearProgressIndicator(
                      // Determinada, no un giro eterno: lo que hace falta ver es
                      // que la cosa avanza y por dónde va. Una rueda girando
                      // cuarenta segundos no dice nada.
                      value: _masLejos == 0 ? null : _masLejos,
                      minHeight: 8,
                      backgroundColor: Colores.linea,
                      color: Colores.primario,
                    ),
                  ),
                  const SizedBox(height: Aire.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _porDondeVa(marcha.avance),
                          style: Tipos.texto(
                            tamano: 13,
                            color: Colores.tintaSuave,
                          ),
                        ),
                      ),
                      Text(
                        '${(_masLejos * 100).round()} %',
                        style: Tipos.texto(
                          tamano: 13,
                          peso: FontWeight.w600,
                          color: Colores.tinta,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Aire.xl),
                if (faltoAlgo)
                  BotonPrincipal(
                    icono: Icons.refresh,
                    texto: 'Reintentar',
                    alPulsar: () {
                      setState(() => _masLejos = 0);
                      ref.read(porteroProvider).configurar();
                    },
                  )
                else
                  Text(
                    'No cierres la aplicación. Cuando termine entra sola.',
                    textAlign: TextAlign.center,
                    style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
                  ),
                const SizedBox(height: Aire.md),
                TextButton(
                  onPressed: () => ref.read(porteroProvider).salir(),
                  child: const Text('Salir'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Cuánto se lleva, de 0 a 1.
  ///
  /// Los tres pasos del ciclo no pesan lo mismo ni de lejos: renovar y subir son
  /// una ida y vuelta cada uno, y bajar son ocho mil clientes por la conexión de
  /// allá. Por eso los dos primeros se llevan el 10 % y la bajada el resto.
  static double _cuanto(AvanceDelCiclo? avance) {
    if (avance == null) return 0;
    return switch (avance.paso) {
      PasoDelCiclo.renovar => 0.03,
      PasoDelCiclo.subir => 0.08,
      PasoDelCiclo.bajar => 0.10 + 0.90 * _delaBajada(avance.coleccion),
    };
  }

  /// Por qué colección va, de 0 a 1. Los almacenes van al final porque son la
  /// última petición del ciclo y van fuera de la transacción de las diferencias.
  static double _delaBajada(String? coleccion) {
    if (coleccion == null) return 0;
    final orden = <String>[...Bajada.colecciones, Colecciones.almacenes];
    final donde = orden.indexOf(coleccion);
    if (donde < 0) return 0;
    return (donde + 1) / orden.length;
  }

  static String _porDondeVa(AvanceDelCiclo? avance) {
    if (avance == null) return 'Preparando…';
    final tanda = avance.tanda > 1 ? ' (tanda ${avance.tanda})' : '';
    return switch (avance.paso) {
      PasoDelCiclo.renovar => 'Comprobando la sesión…',
      PasoDelCiclo.subir => 'Subiendo lo que quedaba…',
      PasoDelCiclo.bajar =>
        'Trayendo ${Faltas.comoSeLlama(avance.coleccion ?? "")}…$tanda',
    };
  }
}

/// Lo que faltó, y qué hacer. **No se entra fingiendo que está.**
class _Falto extends StatelessWidget {
  const _Falto({required this.configuracion});

  final ConfiguracionInicial configuracion;

  /// El motivo, en el orden en que importa: el del ciclo, el de la bajada
  /// cortada, y —cuando no hay ninguno— el único caso que queda.
  static String _elMotivo(ConfiguracionInicial configuracion) {
    if (configuracion.fallo != null) {
      return 'Comprueba la señal y vuelve a probar. Lo que ya se trajo se '
          'queda: no hay que empezar de cero.';
    }
    if (configuracion.quedoPor case final quedoPor?) {
      return 'La bajada se cortó: $quedoPor. Vuelve a probar; lo que ya se '
          'trajo se queda.';
    }
    // Sin fallo y sin corte sólo queda el otro motivo del portero: la bajada
    // terminó entera y el aparato sigue sin nada. Decir aquí «el servidor no
    // terminó de mandar los datos» sería falso.
    return 'La bajada terminó y el aparato sigue vacío. Vuelve a probar; si '
        'sigue igual, esta sucursal no tiene datos que traer.';
  }

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
        Icon(Icons.wifi_off_outlined, size: 18, color: Colores.ambar),
        const SizedBox(width: Aire.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No se pudo traer todo.',
                style: Tipos.texto(
                  tamano: 13,
                  peso: FontWeight.w600,
                  color: Colores.ambar,
                ),
              ),
              const SizedBox(height: Aire.xs),
              Text(
                // Lo que faltó, no «hubo un error». Es lo único que le dice a
                // alguien si puede irse al almacén o no.
                //
                // Y EL MOTIVO VA LITERAL, el que escribe `bajada.dart`. Aquí
                // se tiraba: llegaba «se llegó al tope de 20 tandas y el
                // servidor seguía diciendo que queda más» y se pintaba «El
                // servidor no terminó de mandar los datos», que no nombra nada
                // y con lo que no se puede hacer nada (`CLAUDE.md` §3).
                _elMotivo(configuracion),
                style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
