#!/usr/bin/env python3
"""Run only on the VPS, deliberately, after the audited web is verified.

The root agent must first verify the Android manifest and signing certificate,
then copy that exact APK under /var/lib/procovar/apk without replacing a file.
This script does not compile, copy over SSH, delete APKs, or claim deployment done.
Example (fill bytes and SHA from the verified new artifact):
  python3 publish-verified-apk.py --publish --version 1.0.25 --compilation 26 \
    --date 2026-10-06 --file reparto-1.0.25-261006.apk --bytes BYTES --sha256 SHA

Every failed mutating attempt leaves a public journal. Never delete that journal
and blindly retry: inspect the recorded phase, MinIO, env backup and deployment.
MinIO's external writers must remain quiescent while running: mc cp itself has
no conditional object-create guarantee. The flock serializes this script only.
"""

import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import urllib.parse
import urllib.request


APP = "0iQ8gLv5ZIHD1n_DRlzOa"
BASE = "http://127.0.0.1:3000/api"
STORE = "procovar/reparto/apk/"
HOST_DIR = Path("/var/lib/procovar/apk")
SECRET_DIR = Path("/root/secretos")
OLD_VERSION = "1.0.24"
OLD_COMPILATION = 25
OLD_BYTES = 78868528
OLD_SHA = "413b235cb0d2b35850d6f7488ced8fa10f98dd53feaaa4e3e87e97c13dacca09"
OLD_FILE = "reparto-1.0.24-261006.apk"
PREFIX = "https://archivos.procovar.cloud/reparto/apk/"


class Stop(Exception):
    """Messages are fixed or contain only validated public metadata."""


def require(condition, message):
    if not condition:
        raise Stop(message)


def emit(**public):
    print(json.dumps(public, ensure_ascii=False), flush=True)


def command(argv, label, timeout=60):
    try:
        result = subprocess.run(argv, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise Stop(label + ": no terminó; no repetir a ciegas") from None
    require(result.returncode == 0, label + ": falló; salida privada suprimida")
    return result.stdout


def store_keys():
    raw = command(["mc-procovar", "ls", "--json", STORE], "listado MinIO")
    keys = set()
    for line in raw.splitlines():
        row = json.loads(line)
        require(row.get("status") == "success", "listado MinIO incompleto")
        key = row.get("key")
        require(isinstance(key, str) and bool(key), "listado MinIO sin clave")
        keys.add(key.rsplit("/", 1)[-1])
    return keys


def api_version():
    raw = command(["curl", "--silent", "--show-error", "--fail", "--max-time", "25",
                   "--header", "Host: reparto.procovar.cloud", "--insecure",
                   "https://127.0.0.1/api/version"], "anuncio API")
    value = json.loads(raw)
    require(isinstance(value, dict), "anuncio API inválido")
    return value.get("ultima") or {}


def verify_old_announcement():
    latest = api_version()
    artifact = (latest.get("ficheros") or {}).get("android") or {}
    require(latest.get("version") == OLD_VERSION
            and latest.get("compilacion") == OLD_COMPILATION
            and artifact.get("bytes") == OLD_BYTES
            and artifact.get("sha256") == OLD_SHA
            and (latest.get("descargas") or {}).get("android") == PREFIX + OLD_FILE,
            "producción cambió respecto de 1.0.24+25 verificada; detenerse")


def digest_file(path):
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
            size += len(block)
    return size, digest.hexdigest()


def verify_public(url, size, expected_sha):
    # The app is the second witness: its actual HTTP client must be able to
    # resume and verify the whole download. Cloudflare rejects urllib's default
    # bot User-Agent here, while the Android client's User-Agent is accepted.
    client_headers = {"User-Agent": "Dart/3.13 (dart:io)",
                      "Accept-Encoding": "identity"}
    require(url.startswith(PREFIX) and "/" not in url[len(PREFIX):],
            "destino APK fuera del almacén esperado")
    metadata = json.loads(command(
        ["mc-procovar", "stat", "--json", STORE + url[len(PREFIX):]],
        "metadatos APK de origen"))
    headers = {key.lower(): value for key, value in metadata.get("metadata", {}).items()}
    origin_cache = headers.get("cache-control", "").lower()
    require(metadata.get("status") == "success" and metadata.get("size") == size,
            "APK de origen no corresponde al tamaño esperado")
    require("private" in origin_cache and "no-store" in origin_cache,
            "APK de origen no conserva private, no-store")
    request = urllib.request.Request(url, headers={"Range": "bytes=0-15",
                                                  **client_headers})
    with urllib.request.urlopen(request, timeout=45) as response:
        require(response.geturl() == url, "APK redirige a otro destino")
        require(response.status == 206, "APK no permite reanudar por rango")
        require(response.headers.get("Content-Range") == f"bytes 0-15/{size}",
                "rango APK no corresponde al fichero")
        beginning = response.read(17)
        require(len(beginning) == 16 and beginning[:4] == b"PK\x03\x04",
                "rango APK no contiene los 16 bytes ZIP esperados")
    digest = hashlib.sha256()
    total = 0
    request = urllib.request.Request(url, headers=client_headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        require(response.geturl() == url and response.status == 200,
                "descarga pública APK no da 200 directo")
        require(response.headers.get_content_type() == "application/vnd.android.package-archive",
                "tipo de contenido APK incorrecto")
        public_cache = response.headers.get("Cache-Control", "").lower()
        cache_state = response.headers.get("CF-Cache-Status", "").upper()
        # Cloudflare's Browser TTL rewrites no-store to private,max-age=14400.
        # Do not change the whole zone or pretend the public header is no-store.
        # Require private delivery and proof that its edge did not cache it,
        # in addition to the origin policy, actual range, bytes and SHA below.
        require("private" in public_cache and "public" not in public_cache
                and cache_state in ("BYPASS", "DYNAMIC"),
                "APK permite caché compartida o se sirvió desde caché CDN")
        while True:
            block = response.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
            total += len(block)
            require(total <= size, "descarga APK supera el tamaño esperado")
    require(total == size and digest.hexdigest() == expected_sha,
            "descarga pública APK no coincide en bytes y SHA256")
    emit(stage="public_download_verified", http=200, range_http=206,
         bytes=total, sha256=digest.hexdigest(), origin_cache_control=origin_cache,
         public_cache_control=public_cache, edge_cache_status=cache_state)


def update_env(original, replacements):
    # Preserve all untouched lines and their line endings byte-for-byte.
    lines = original.splitlines(keepends=True)
    seen = set()
    result = []
    untouched_before, untouched_after = [], []
    for line in lines:
        content = line.rstrip("\r\n")
        ending = line[len(content):]
        key = content.split("=", 1)[0]
        if key in replacements:
            require(key not in seen, "variables del anuncio duplicadas; no reescribir")
            seen.add(key)
            result.append(key + "=" + replacements[key] + ending)
        else:
            result.append(line)
            untouched_before.append(line)
            untouched_after.append(result[-1])
    missing = [key for key in replacements if key not in seen]
    if missing:
        # Appending a separator would change an existing unterminated last line.
        require(not original or original.endswith("\n"),
                "env sin salto final y variables ausentes; revisar manualmente")
        result.extend(key + "=" + replacements[key] + "\n" for key in missing)
    require(untouched_before == untouched_after, "otras variables cambiaron")
    return "".join(result)


def verified_uploaded_journal(path, expected, deployment_ids):
    require(path.is_file() and not path.is_symlink(), "diario de subida ausente o enlace")
    evidence = json.loads(path.read_text())
    require(evidence.get("phase") == "uploaded", "sólo se puede retomar una subida sin anuncio")
    require(all(evidence.get(key) == value for key, value in expected.items()),
            "diario corresponde a otra APK; no retomar")
    require(evidence.get("production_verified") is False,
            "diario ya marca producción verificada; no retomar")
    require(evidence.get("old_deployment_ids") == deployment_ids,
            "despliegues API cambiaron desde la subida; revisar antes de retomar")
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", action="store_true", required=True)
    parser.add_argument("--resume-uploaded", action="store_true",
                        help="retomar sólo diario uploaded verificado; no vuelve a subir")
    parser.add_argument("--version", required=True)
    parser.add_argument("--compilation", type=int, required=True)
    parser.add_argument("--date", required=True)
    parser.add_argument("--file", required=True)
    parser.add_argument("--bytes", type=int, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--notes", help="optional new public release notes")
    args = parser.parse_args()
    require(args.version == "1.0.25" and args.compilation == 26,
            "este guion sólo publica la revisión deliberada 1.0.25+26")
    date = datetime.date.fromisoformat(args.date)
    require(args.file == f"reparto-{args.version}-{date:%y%m%d}.apk", "nombre APK no coincide")
    require(re.fullmatch(r"[a-f0-9]{64}", args.sha256) is not None, "SHA256 inválido")
    require(args.bytes > 0, "bytes inválidos")
    if args.notes is not None:
        require("\n" not in args.notes and "\r" not in args.notes,
                "notas deben caber en una variable de una línea")
    require(os.geteuid() == 0 and (SECRET_DIR / "dokploy.key").is_file()
            and HOST_DIR.is_dir(), "ejecutar sólo como root dentro del VPS")
    source = HOST_DIR / args.file
    require(source.is_file() and not source.is_symlink(), "fichero host ausente o enlace")
    require(digest_file(source) == (args.bytes, args.sha256), "fichero host distinto del firmado")
    require(digest_file(HOST_DIR / OLD_FILE) == (OLD_BYTES, OLD_SHA),
            "la APK anterior del host cambió")

    lock = os.open(HOST_DIR / ".publication.lock", os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise Stop("otra publicación está en curso") from None
    journal_path = HOST_DIR / f".publish-{args.file}.json"
    if not args.resume_uploaded:
        require(not journal_path.exists(), "hay diario previo: inspeccionarlo antes de cualquier reintento")
    verify_old_announcement()

    key = (SECRET_DIR / "dokploy.key").read_text().strip()
    require(bool(key), "clave Dokploy vacía")

    def dokploy(route, data=None):
        body = None if data is None else json.dumps(data).encode()
        request = urllib.request.Request(BASE + route, data=body,
            headers={"x-api-key": key, "Content-Type": "application/json"},
            method="GET" if data is None else "POST")
        with urllib.request.urlopen(request, timeout=45) as response:
            raw = response.read()
        return json.loads(raw) if raw.strip() else None

    query = "?" + urllib.parse.urlencode({"applicationId": APP})
    application = dokploy("/application.one" + query)
    require(isinstance(application, dict) and application.get("applicationId") == APP,
            "Dokploy devolvió otra aplicación")
    original_env = application.get("env")
    require(isinstance(original_env, str) and bool(original_env), "env de Dokploy vacío")
    old_expected = {
        "APP_ULTIMA_VERSION": OLD_VERSION,
        "APP_ULTIMA_COMPILACION": str(OLD_COMPILATION),
        "APP_DESCARGA_ANDROID": PREFIX + OLD_FILE,
        "APP_DESCARGA_ANDROID_BYTES": str(OLD_BYTES),
        "APP_DESCARGA_ANDROID_SHA256": OLD_SHA,
    }
    old_actual = {}
    for line in original_env.splitlines():
        name, separator, value = line.partition("=")
        if name in old_expected:
            require(separator and name not in old_actual,
                    "env contiene un anuncio duplicado o inválido")
            old_actual[name] = value
    require(old_actual == old_expected, "anuncio persistente no es la versión verificada")
    deployments = dokploy("/deployment.all" + query)
    require(isinstance(deployments, list), "inventario despliegues inválido")
    require(all(row.get("status") not in ("running", "queued") for row in deployments),
            "hay un despliegue API en curso")
    old_ids = [row.get("deploymentId") for row in deployments]
    changes = {
        "APP_ULTIMA_VERSION": args.version,
        "APP_ULTIMA_COMPILACION": str(args.compilation),
        "APP_ULTIMA_PUBLICADA": args.date,
        "APP_DESCARGA_ANDROID": PREFIX + args.file,
        "APP_DESCARGA_ANDROID_BYTES": str(args.bytes),
        "APP_DESCARGA_ANDROID_SHA256": args.sha256,
    }
    if args.notes is not None:
        changes["APP_ULTIMA_NOTAS"] = args.notes
    replacement_env = update_env(original_env, changes)
    before_keys = store_keys()
    require(OLD_FILE in before_keys, "MinIO no conserva la APK anterior")
    if args.resume_uploaded:
        require(args.file in before_keys, "objeto subido desapareció; no retomar")
    else:
        require(args.file not in before_keys, "el objeto nuevo ya existe: no sobrescribir")

    evidence = {"version": args.version, "compilation": args.compilation,
                "file": args.file, "bytes": args.bytes, "sha256": args.sha256,
                "url": PREFIX + args.file, "old_deployment_ids": old_ids,
                "production_verified": False}
    if args.resume_uploaded:
        evidence = verified_uploaded_journal(journal_path, {
            "version": args.version, "compilation": args.compilation,
            "file": args.file, "bytes": args.bytes, "sha256": args.sha256,
            "url": PREFIX + args.file,
        }, old_ids)
    else:
        journal_fd = os.open(journal_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(journal_fd)

    def record(phase):
        evidence["phase"] = phase
        with journal_path.open("w") as journal:
            json.dump(evidence, journal, ensure_ascii=False, indent=2)
            journal.write("\n")
            journal.flush()
            os.fsync(journal.fileno())
        emit(stage=phase, version=args.version, compilation=args.compilation)

    if args.resume_uploaded:
        record("resume_uploaded_verified")
    else:
        record("upload_attempt")
        command(["mc-procovar", "cp", "--attr",
                 "Content-Type=application/vnd.android.package-archive;Cache-Control=private, no-store",
                 "/host/apk/" + args.file, STORE + args.file], "subida MinIO", timeout=300)
        after_keys = store_keys()
        require(before_keys.issubset(after_keys) and args.file in after_keys,
                "inventario APK no conserva las versiones previas")
        record("uploaded")
    verify_public(PREFIX + args.file, args.bytes, args.sha256)
    record("download_verified")
    verify_old_announcement()
    require(dokploy("/application.one" + query).get("env") == original_env,
            "env cambió durante la descarga; no pisar cambios de otra persona")

    require(SECRET_DIR.is_dir() and not SECRET_DIR.is_symlink(), "directorio secretos inválido")
    backup_path = SECRET_DIR / f"reparto-api-before-{args.version}-{date:%y%m%d}.env"
    backup_fd = os.open(backup_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(backup_fd, "w", newline="") as backup:
        backup.write(original_env)
        backup.flush()
        os.fsync(backup.fileno())
    require(stat.S_IMODE(backup_path.stat().st_mode) == 0o600,
            "copia del env no tiene permisos 0600")
    with backup_path.open("r", newline="") as backup:
        require(backup.read() == original_env, "copia del env no coincide")
    record("env_update_attempt")
    dokploy("/application.update", {"applicationId": APP, "env": replacement_env})
    require(dokploy("/application.one" + query).get("env") == replacement_env,
            "Dokploy no conserva exactamente el env nuevo; no redesplegar")
    record("env_verified")
    current_deployments = dokploy("/deployment.all" + query)
    require(isinstance(current_deployments, list)
            and all(row.get("status") not in ("running", "queued")
                    for row in current_deployments),
            "otro despliegue API arrancó; no lanzar otro")
    record("redeploy_attempt")
    dokploy("/application.redeploy", {
        "applicationId": APP,
        "title": f"APK {args.version}+{args.compilation} verificada {args.date}",
        "description": "Sólo anuncio Android; objeto, rango, bytes y SHA verificados en VPS.",
    })
    record("redeploy_requested")
    emit(stage="await_external_verification", version=args.version,
         compilation=args.compilation, journal=str(journal_path),
         require_new_deployment=True, require_api_version=True,
         production_verified=False)


if __name__ == "__main__":
    try:
        main()
    except Stop as error:
        emit(stage="stopped", reason=str(error), production_verified=False)
        sys.exit(1)
    except Exception as error:
        # HTTP bodies, subprocess output, env and exception text may contain secrets.
        emit(stage="stopped", error_type=type(error).__name__,
             reason="detalle privado suprimido; inspeccionar fase antes de reintentar",
             production_verified=False)
        sys.exit(1)
