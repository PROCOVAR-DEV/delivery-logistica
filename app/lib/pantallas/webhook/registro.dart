import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import '../../nucleo/plataforma.dart';
import 'vista/pantalla_webhook.dart';

/// La ruta de esta pantalla. Bajo `/admin` a propósito: dice de qué va sin abrirla.
const rutaDelWebhook = '/admin/webhook';

/// Los roles a los que se les ENSEÑA en el menú. Ver [rolesQueVenElCanal].
const rolesQueVenElCanal = <String>['DESARROLLADOR', 'SUPER ADMIN'];

/// CÓMO VA EL CANAL CON PEDIDO. **Sólo en la web, y en el menú sólo para dos roles.**
///
/// Jose, 26/09/2026, y en este orden —la historia importa porque explica por qué está como
/// está—:
///
///  1. «eso me lo dejas en la web solamente, no lo pongas en más ningún lado»;
///  2. «que sólo lo pueda ver yo, eso no lo puede ver más nadie, sólo yo, el desarrollador»
///     — y se cerró a `DESARROLLADOR` a secas, **fuera del menú**;
///  3. al ver que su propia cuenta es `SUPER ADMIN`: «ponle para super admin también, de
///     todas formas yo limpiaré eso después»;
///  4. y entrando por la dirección porque no la encontraba: **«tampoco agregaste el link en
///     el menú para poder verlo como super admin»**, «en el sidebar», «no lo veo».
///
/// Así que ahora SÍ va en el menú, y sólo para esos dos. Los otros cinco roles de la casa
/// —GERENTE, ADMINISTRADOR, SUPERVISOR, GESTOR, OPERADOR— no la ven ahí.
///
/// TRES COSAS, Y **SÓLO UNA CIERRA**:
///
///  1. **En el menú sale sólo para dos roles.** Para no estorbar: quien no tiene nada que
///     hacer en una pantalla de colas, reintentos y códigos HTTP de otro sistema no
///     tropieza con ella. **NO es un permiso**, y da igual cuántas veces se lea como si lo
///     fuera: el rol viaja en el token del aparato y cualquiera con un editor de texto
///     escribe el que quiera. Lo dice la propia `Sesion`.
///  2. **No existe fuera de la web.** En la APK y en el escritorio ni siquiera se registra:
///     el repartidor está en la calle, y además la APK trabaja sin señal, donde este dato no
///     significa nada.
///  3. **El servidor contesta 403 a todo el que no sea DESARROLLADOR o SUPER ADMIN.** Ése
///     es el único que de verdad cierra, y vive en `auth.PuedeMirarElCanal`, probado allí
///     con los siete roles uno a uno. Si algún día hay que cerrar o abrir esto, **se cambia
///     ahí** — cambiarlo sólo aquí esconde la entrada y deja la puerta abierta.
PantallaRegistrada? registrarWebhook() {
  // `trabajaSinConexion` es `false` SÓLO en la web. Es el único `kIsWeb` de todo esto y
  // está en un sitio, que es lo que permite probar las dos plataformas.
  if (Destino.trabajaSinConexion) return null;
  return PantallaRegistrada(
    ruta: rutaDelWebhook,
    titulo: 'Canal con PEDIDO',
    enElMenu: true,
    soloParaRoles: rolesQueVenElCanal,
    icono: Icons.cable_outlined,
    // NINGUNA: el estado del canal se pregunta al servidor en vivo.
    colecciones: ColeccionesDePantalla.ninguna,
    construir: (contexto, estado) => const PantallaWebhook(),
  );
}
