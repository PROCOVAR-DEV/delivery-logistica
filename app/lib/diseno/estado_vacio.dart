import 'package:flutter/material.dart';

import '../nucleo/frescura/reloj_de_datos.dart';
import 'colores.dart';
import 'tema.dart';

/// «Aqui no hay nada». Es un DATO: se consulto y salio vacio.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio(this.texto, {this.icono, super.key});

  final String texto;
  final IconData? icono;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: Aire.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icono != null) ...[
          // El icono en su circulo de papel, como los estados vacios de
          // delivery: un icono suelto sobre blanco se lee como un fallo.
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colores.grisFondo,
              shape: BoxShape.circle,
            ),
            child: Icon(icono, size: 24, color: Colores.tintaSuave),
          ),
          const SizedBox(height: Aire.md),
        ],
        Text(
          texto,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Colores.tintaSuave),
        ),
      ],
    ),
  );
}

/// «Esto no se ha descargado». **No es lo mismo que vacio**, y por eso es otro
/// widget y no un parametro: una lista vacia en una coleccion que nunca se bajo
/// es un FALLO que se lee como un dato (caso S7). En ambar, con el texto que
/// dice que se arregla solo.
class PantallaSinDescargar extends StatelessWidget {
  const PantallaSinDescargar({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: Aire.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colores.ambarFondo,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.cloud_download_outlined,
            size: 24,
            color: Colores.ambar,
          ),
        ),
        const SizedBox(height: Aire.md),
        Text(
          SinDescargar.textoDeLaPantallaVacia,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Colores.ambar),
        ),
      ],
    ),
  );
}

/// El aviso ambar de una franja: se usa arriba de los Informes cuando los
/// numeros salen del aparato y no del servidor.
class AvisoAmbar extends StatelessWidget {
  const AvisoAmbar(
    this.texto, {
    this.icono = Icons.warning_amber_outlined,
    super.key,
  });

  final String texto;
  final IconData icono;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: 10),
    decoration: BoxDecoration(
      color: Colores.ambarFondo,
      border: Border.all(color: Colores.ambar.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(Radios.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18, color: Colores.ambar),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colores.ambar),
          ),
        ),
      ],
    ),
  );
}

/// UN VACIO QUE INVITA A ACTUAR. Es lo contrario de «No hay registros».
///
/// Una pantalla vacia es de las pocas que alguien mira sin saber que hacer, y
/// tiene que contestarle tres cosas **en su idioma, no en el de la base**:
///
///  1. **Que es esto** — «Aqui van los camiones con los que se reparte», no
///     «tabla `vehicles`».
///  2. **Que se rompe si sigue vacio** — es la linea que decide si alguien lo
///     hace hoy o el mes que viene.
///  3. **Por donde se empieza** — un boton, y sólo si de verdad lleva a algun
///     sitio.
///
/// Esta en `diseno/` y no dentro de una pantalla porque los vacios de las siete
/// tienen que leerse igual: si cada carpeta pinta el suyo, a los tres meses uno
/// dice «Sin vehiculos» a secas y otro escribe media pagina.
class Invitacion extends StatelessWidget {
  const Invitacion({
    required this.titulo,
    required this.queEs,
    this.siNoEsta,
    this.llamada,
    this.icono,
    this.textoDelBoton,
    this.iconoDelBoton,
    this.alPulsar,
    super.key,
  }) : assert(
         textoDelBoton == null || iconoDelBoton != null,
         'un boton principal lleva SIEMPRE su icono (diseno/tema.dart, '
         '[BotonPrincipal]): si hay textoDelBoton tiene que haber '
         'iconoDelBoton, y el que le toque a ESA accion',
       );

  /// El literal corto de siempre: `Sin vehículos`, `Sin almacenes`. Se conserva
  /// tal cual porque es el del pliego.
  final String titulo;

  /// Que es esto y para que sirve **en el trabajo del logistico**.
  final String queEs;

  /// Que deja de poder hacerse mientras siga vacio.
  final String? siNoEsta;

  /// La linea pegada al boton. Existe para **conservar el literal del pliego**
  /// («Agrega tu primer vehículo para asignarlo a rutas») sin tener que meterlo
  /// donde no dice lo que hace falta: el pliego es el contrato de los textos y
  /// no se le quita una frase para poner otra, se le añade lo que le faltaba.
  final String? llamada;

  /// El glifo grande del circulo gris, el del vacio. **No es el del boton.**
  final IconData? icono;

  /// `null` = **no se pinta boton**. No es lo mismo que uno apagado: uno gris
  /// invita a pulsarlo igual.
  final String? textoDelBoton;

  /// El del boton, que es otro y no se hereda de [icono].
  ///
  /// El del vacio dice **que falta** (un camion, un almacen); este dice **que
  /// hace el boton** (anadir uno). Si se reaprovechara el de arriba, el mando
  /// repetiria el dibujo que ya esta 60 px por encima y no diria nada nuevo.
  final IconData? iconoDelBoton;

  final VoidCallback? alPulsar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final etiqueta = textoDelBoton;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: Aire.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colores.grisFondo,
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 24, color: Colores.tintaSuave),
            ),
            const SizedBox(height: Aire.md),
          ],
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: Tipos.texto(
              tamano: 15,
              peso: FontWeight.w600,
              color: Colores.tinta,
            ),
          ),
          const SizedBox(height: Aire.sm),
          // El ancho se acota: una linea de 1400 px no se lee de un vistazo, y
          // este texto existe justamente para leerse de un vistazo.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                Text(
                  queEs,
                  textAlign: TextAlign.center,
                  style: tema.textTheme.bodyMedium?.copyWith(
                    color: Colores.tintaSuave,
                  ),
                ),
                if (siNoEsta != null) ...[
                  const SizedBox(height: Aire.xs),
                  Text(
                    siNoEsta!,
                    textAlign: TextAlign.center,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: Colores.ambar,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (llamada != null) ...[
            const SizedBox(height: Aire.md),
            Text(
              llamada!,
              textAlign: TextAlign.center,
              style: tema.textTheme.bodySmall?.copyWith(
                color: Colores.tintaSuave,
              ),
            ),
          ],
          if (etiqueta != null) ...[
            const SizedBox(height: Aire.md),
            BotonPrincipal(
              texto: etiqueta,
              icono: iconoDelBoton!,
              alPulsar: alPulsar,
            ),
          ],
        ],
      ),
    );
  }
}

/// LO QUE EL APARATO TIENE BAJADO, dicho debajo de un fallo de red.
///
/// Sin conexion, «Sin conexión» a secas deja sin contestar la pregunta que de
/// verdad importa: **¿y lo que hay dentro del teléfono, qué es?** No es lo mismo
/// un aparato que bajó la flota el lunes que uno que no la ha bajado nunca: el
/// primero puede seguir armando la ruta con lo que tiene; el segundo no, y se
/// arregla trayendo el día, no dando de alta nada.
class LoQueTieneElAparato extends StatelessWidget {
  const LoQueTieneElAparato({
    required this.texto,
    required this.enAmbar,
    super.key,
  });

  final String texto;

  /// Ambar cuando hay algo que mirar: no se bajo nunca, o lo bajado es viejo.
  final bool enAmbar;

  @override
  Widget build(BuildContext context) {
    final color = enAmbar ? Colores.ambar : Colores.tintaSuave;
    return Padding(
      padding: const EdgeInsets.only(top: Aire.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            enAmbar
                ? Icons.cloud_download_outlined
                : Icons.phone_android_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texto,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
