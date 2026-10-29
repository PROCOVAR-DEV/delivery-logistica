import 'id_del_aparato_web.dart'
    if (dart.library.io) 'id_del_aparato_nativo.dart'
    as destino;

/// EL ID DEL APARATO — 29/10/2026 (Accesos, «Dispositivos»).
///
/// Un UUID **v7** (Jose: «no uuidv4, uuid7») que se crea UNA vez al instalar y
/// no cambia con las actualizaciones; se va al desinstalar, y entonces la
/// instalación nueva es otro aparato. Va en `X-Aparato-Id` en cada petición a
/// Accesos (`/token`, `/refresh`, `/logout`): identifica, no autentica.
///
/// **La web no lo manda** (devuelve `null`): Accesos no deja esa cabecera en
/// CORS y añadirla pondría un preflight al login. Aparatos son la APK y el
/// escritorio.
///
/// Nunca lanza: sin id, la petición sale como siempre.
Future<String?> idDelAparato() => destino.idDelAparato();

/// Cómo se llama el aparato (`Samsung SM-A166B`, el nombre del PC): `X-Aparato-Nombre`.
Future<String?> nombreDelAparato() => destino.nombreDelAparato();

/// La HUELLA del aparato físico — `X-Aparato-Huella`: sha256 en hexadecimal de
/// `procovar:` + el id de la máquina (ANDROID_ID, MachineGuid, machine-id).
///
/// Cada APK guarda su propio [idDelAparato] (Android aísla el almacenamiento por
/// app), así que Reparto y el CRM de una misma tablet son dos instalaciones; la
/// huella es lo que Accesos usa para verlas como UN aparato. Identifica, no
/// autentica. `ANDROID_ID` solo coincide entre apps firmadas con la MISMA clave
/// (`procovar-reparto.jks`). `null` en la web y si no se puede leer.
Future<String?> huellaDelAparato() => destino.huellaDelAparato();
