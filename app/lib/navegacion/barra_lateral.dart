import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../diseno/anchos.dart';
import '../diseno/colores.dart';
import '../diseno/tema.dart';
import '../nucleo/identidad/sesion.dart';
import '../pantallas/ayuda/datos/controles_senalados.dart';
import '../pantallas/ayuda/vista/control_senalado.dart';
import '../pantallas/mapa/registro.dart' show caminoDelMapaSinConexion;
import '../pantallas/sincronizacion/vista/pantalla_sincronizacion.dart'
    show PantallaSincronizacion;
import 'pantalla_registrada.dart';

/// La barra lateral: 256 px, alto completo, fija a la izquierda en escritorio.
/// Por debajo de 1024 px vive dentro del `Drawer` del `Scaffold` y se abre con
/// el boton de menu de la barra superior.
class BarraLateral extends StatelessWidget {
  const BarraLateral({
    required this.pantallas,
    required this.rutaActual,
    this.quienMira,
    this.dentroDeCajon = false,
    super.key,
  });

  /// Quien tiene la barra delante, para no ensenarle lo que no le toca.
  ///
  /// `null` mientras la sesion se esta leyendo, y entonces se esconde lo que
  /// tenga roles: **el lado seguro es no ensenarlo**. Sale un instante despues,
  /// cuando la sesion resuelve y esto se repinta.
  final Sesion? quienMira;

  /// Que entradas ve quien mira. **Funcion pura y aparte a proposito**: es lo que
  /// se puede probar sin montar la barra ni levantar Riverpod.
  ///
  /// ESTO NO ES UN PERMISO. El rol viaja en el token del aparato y cualquiera con
  /// un editor de texto escribe el que quiera; esconder una entrada no cierra
  /// nada, porque la ruta sigue alcanzable escribiendo la direccion. El cerrojo
  /// esta en la api, que contesta 403. Ver [PantallaRegistrada.soloParaRoles].
  static List<PantallaRegistrada> entradasPara(
    List<PantallaRegistrada> pantallas,
    Sesion? quien,
  ) => [
    for (final p in pantallas)
      if (p.enElMenu &&
          (p.soloParaRoles.isEmpty ||
              (quien?.tieneAlguno(p.soloParaRoles) ?? false)))
        p,
  ];

  final List<PantallaRegistrada> pantallas;
  final String rutaActual;

  /// En movil la barra va dentro del cajon del `Scaffold`, y al elegir una
  /// entrada hay que cerrarlo: **se cierra sola al cambiar de pantalla** (§8.1).
  /// Dejarlo abierto tapa justo la pantalla a la que se acaba de ir.
  final bool dentroDeCajon;

  @override
  Widget build(BuildContext context) {
    final enElMenu = entradasPara(pantallas, quienMira);

    return Container(
      width: Anchos.barraLateral,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colores.blanco,
        border: Border(right: BorderSide(color: Colores.linea)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Aire.xl, Aire.xl, Aire.lg, 20),
              child: Row(
                children: [
                  // EL ISOTIPO DEL REPARTO: cuadrado de 36 px en el oro de la
                  // marca con el camion en tinta — el mismo dibujo que el icono
                  // de la aplicacion (`marca/icono.svg`), para que lo que se ve
                  // en la barra sea lo mismo que se ve en el escritorio del
                  // telefono. Un icono suelto no es una marca; el cuadrado si.
                  //
                  // En tinta y no en blanco: blanco sobre oro no se lee.
                  // Es `isotipo.png` y no `logo.png`: a 36 px el monograma de la
                  // caja mide diez pixeles y ensucia la unica forma que a ese
                  // tamano se lee. El monograma se ve entero en la pantalla de
                  // entrada, que tiene sitio.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radios.lg),
                      boxShadow: Sombras.md,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radios.lg),
                      child: Image.asset(
                        'assets/marca/isotipo.png',
                        width: 36,
                        height: 36,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // `Expanded`: «Plataforma de Delivery» no cabe en los 256 px
                  // junto al camion, y un `Row` sin reparto se sale por la
                  // derecha en vez de recortar.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ProCovar',
                          style: Tipos.display(
                            tamano: 21.6,
                            peso: FontWeight.w800,
                            color: Colores.tinta,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // `text-[11px] uppercase tracking-[0.18em]`: el rotulo
                        // pequeno bajo la marca.
                        Text(
                          'Plataforma de Delivery',
                          overflow: TextOverflow.ellipsis,
                          style: Tipos.texto(
                            tamano: 11,
                            peso: FontWeight.w500,
                            color: Colores.tintaSuave.withValues(alpha: 0.8),
                            interletra: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: Aire.md,
                  vertical: Aire.xs,
                ),
                children: [
                  for (final p in enElMenu)
                    _conSuMarca(
                      p,
                      _Entrada(
                        pantalla: p,
                        activa: rutaActual == p.ruta,
                        dentroDeCajon: dentroDeCajon,
                      ),
                    ),
                ],
              ),
            ),
            // Abajo NO hay nada de la cuenta: cerrar sesion y cambiar de
            // aplicacion viven en el avatar de la barra superior (§8.1).
          ],
        ),
      ),
    );
  }
}

/// LAS ENTRADAS QUE EL MANUAL SENALA, por su ruta.
///
/// Hay pasos cuyo unico contenido es «**Menú → «Clientes».**», y el control del
/// que hablan es esta entrada. No llevan todas marca: solo las que algun paso
/// nombra, porque un nombre en el catalogo que ningun paso use lo caza
/// `los_pasos_senalan_controles_que_existen_test.dart`.
///
/// Las demas entradas se devuelven tal cual: `ControlSenalado` es transparente,
/// pero un envoltorio por entrada que nadie va a preguntar no paga nada.
///
/// **Aqui no hay dos a la vez**: en escritorio el armazon pone `drawer: null` y
/// esta barra se monta una sola vez; por debajo de `Anchos.escritorio` se monta
/// solo dentro del cajon. En un telefono, con el cajon cerrado, el recorrido dice
/// «el control de este paso no está en esta pantalla» — que es la verdad.
Widget _conSuMarca(PantallaRegistrada pantalla, Widget entrada) =>
    switch (pantalla.ruta) {
      '/customers' => ControlSenalado(
        nombre: Senalado.menuClientes,
        child: entrada,
      ),
      '/reports' => ControlSenalado(
        nombre: Senalado.menuReportes,
        child: entrada,
      ),
      PantallaSincronizacion.ruta => ControlSenalado(
        nombre: Senalado.menuSincronizacion,
        child: entrada,
      ),
      caminoDelMapaSinConexion => ControlSenalado(
        nombre: Senalado.menuMapa,
        child: entrada,
      ),
      _ => entrada,
    };

class _Entrada extends StatelessWidget {
  const _Entrada({
    required this.pantalla,
    required this.activa,
    required this.dentroDeCajon,
  });

  final PantallaRegistrada pantalla;
  final bool activa;
  final bool dentroDeCajon;

  @override
  Widget build(BuildContext context) {
    final color = activa ? Colores.primario : Colores.tintaSuave;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        // `bg-primary/[0.08]` la activa; las demas, transparentes.
        color: activa ? Colores.primarioTenue : Colors.transparent,
        borderRadius: BorderRadius.circular(Radios.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radios.lg),
          hoverColor: Colores.tinta.withValues(alpha: 0.035),
          onTap: () {
            if (dentroDeCajon) Navigator.of(context).pop();
            context.go(pantalla.ruta);
          },
          child: Stack(
            children: [
              // La barra vertical a la izquierda de la activa (§8.1). Redonda
              // y de 20 px de alto, como la de `Sidebar.tsx`
              // (`h-5 w-1 rounded-full bg-primary`).
              if (activa)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colores.primario,
                        borderRadius: BorderRadius.circular(Radios.pastilla),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Aire.lg, 10, Aire.md, 10),
                child: Row(
                  children: [
                    Icon(
                      pantalla.icono ?? Icons.circle_outlined,
                      size: 20,
                      color: color,
                    ),
                    const SizedBox(width: Aire.md),
                    Expanded(
                      child: Text(
                        pantalla.titulo,
                        overflow: TextOverflow.ellipsis,
                        style: Tipos.texto(
                          tamano: 14,
                          peso: activa ? FontWeight.w600 : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
