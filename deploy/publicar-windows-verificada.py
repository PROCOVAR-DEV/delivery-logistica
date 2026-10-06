#!/usr/bin/env python3
"""VPS only. Publish Windows files proved by a successful Windows CI run.

Never compile, overwrite an object, delete old versions, or retry an upload
blindly. A failed attempt must be inspected; only an uploaded journal with the
same verified files and unchanged API deployments permits --mode resume.
The Windows runner's installer check does not prove login or offline work.
External MinIO writers must remain quiescent; flock serializes publishers only.
"""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request

HOST = Path('/var/lib/procovar/apk')
SECRET = Path('/root/secretos')
ANDROID_FILE = 'reparto-1.0.25-261006.apk'
PREFIX = 'https://archivos.procovar.cloud/reparto/windows/'
STORE = 'procovar/reparto/windows/'
REPO = 'jose22072000/delivery-logistica'
ANDROID_SHA = '7b46b44c0ac82ca87bea1ec098b2a993bd89ea4510cc0bc613e08ca7c27ae714'
spec = importlib.util.spec_from_file_location('android_publisher', Path(__file__).with_name('publicar-apk-verificada.py'))
android = importlib.util.module_from_spec(spec)
spec.loader.exec_module(android)
require = android.require
command = android.command


def public_json(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'Dart/3.13 (dart:io)'})
    with urllib.request.urlopen(request, timeout=30) as response:
        require(response.status == 200 and response.geturl() == url, 'JSON público no da 200 directo')
        return json.load(response)


def verify_baseline(value):
    require(value.get('version') == '1.0.25' and value.get('compilacion') == 26,
            'la versión Android cambió; detenerse')
    require(value.get('ficheros', {}).get('android') == {'bytes': 78868528, 'sha256': ANDROID_SHA},
            'el artefacto Android cambió; detenerse')
    require(value.get('descargas', {}).get('android') == 'https://archivos.procovar.cloud/reparto/apk/reparto-1.0.25-261006.apk',
            'el enlace Android cambió; detenerse')


def inventory():
    keys = set()
    raw = command(['mc-procovar', 'ls', '--recursive', '--json', 'procovar/reparto/'], 'inventario Reparto')
    for line in raw.splitlines():
        row = json.loads(line)
        require(row.get('status') == 'success' and isinstance(row.get('key'), str) and bool(row['key']), 'inventario incompleto')
        keys.add(row['key'])
    require(any(k == ANDROID_FILE or k.endswith('/' + ANDROID_FILE) for k in keys),
            'inventario no conserva Android actual')
    return keys


def verify_download(file):
    name, size, sha = file['file'], file['bytes'], file['sha256']
    url = PREFIX + name
    mime = 'application/octet-stream' if name.endswith('.exe') else 'application/zip'
    magic = b'MZ' if name.endswith('.exe') else b'PK\x03\x04'
    metadata = json.loads(command(['mc-procovar', 'stat', '--json', STORE + name], 'metadatos Windows'))
    headers = {k.lower(): v for k, v in metadata.get('metadata', {}).items()}
    cache = headers.get('cache-control', '').lower()
    require(metadata.get('status') == 'success' and metadata.get('size') == size,
            'objeto Windows distinto')
    require('private' in cache and 'no-store' in cache and headers.get('content-type') == mime,
            'metadatos Windows incorrectos')
    client = {'User-Agent': 'Dart/3.13 (dart:io)', 'Accept-Encoding': 'identity'}
    with urllib.request.urlopen(urllib.request.Request(url, headers={**client, 'Range': 'bytes=0-15'}), timeout=45) as r:
        require(r.geturl() == url and r.status == 206 and r.headers.get('Content-Range') == f'bytes 0-15/{size}',
                'descarga Windows no permite rango exacto')
        beginning = r.read(17)
        require(len(beginning) == 16 and beginning.startswith(magic), 'cabecera Windows incorrecta')
    total, digest = 0, hashlib.sha256()
    with urllib.request.urlopen(urllib.request.Request(url, headers=client), timeout=90) as r:
        require(r.geturl() == url and r.status == 200 and r.headers.get_content_type() == mime,
                'descarga Windows no da fichero directo')
        cache = r.headers.get('Cache-Control', '').lower()
        edge = r.headers.get('CF-Cache-Status', '').upper()
        require('private' in cache and 'public' not in cache and edge in ('BYPASS', 'DYNAMIC'),
                'descarga Windows servida desde caché compartida')
        for block in iter(lambda: r.read(1024 * 1024), b''):
            total += len(block)
            require(total <= size, 'descarga Windows supera tamaño esperado')
            digest.update(block)
    require(total == size and digest.hexdigest() == sha, 'descarga Windows distinta en tamaño o SHA')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['publish', 'resume', 'verify'], required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--run', type=int, required=True)
    args = parser.parse_args()
    require(re.fullmatch('[a-f0-9]{40}', args.source) is not None and args.run > 0, 'fuente CI inválida')
    require(args.manifest.is_file() and not args.manifest.is_symlink(), 'manifiesto inválido')
    meta = json.loads(args.manifest.read_text(encoding='utf-8-sig'))
    require(meta.get('version') == '1.0.25' and meta.get('compilation') == 26
            and meta.get('source_commit') == args.source and meta.get('flutter_version') == '3.47.4'
            and meta.get('installer_files_verified') is True, 'Windows no tiene prueba de instalación CI')
    run = public_json(f'https://api.github.com/repos/{REPO}/actions/runs/{args.run}')
    require(run.get('head_sha') == args.source and run.get('status') == 'completed'
            and run.get('conclusion') == 'success'
            and run.get('path') == '.github/workflows/reparto-windows.yml'
            and run.get('head_repository', {}).get('full_name') == REPO, 'el trabajo Windows no terminó correctamente')
    files = meta.get('files')
    expected_names = {'reparto-1.0.25-windows-setup.exe', 'reparto-1.0.25-windows.zip'}
    require(isinstance(files, list) and len(files) == 2
            and {f.get('file') for f in files} == expected_names, 'inventario Windows inesperado')
    for file in files:
        require(type(file.get('bytes')) is int and file['bytes'] > 0
                and re.fullmatch('[a-f0-9]{64}', file.get('sha256', '')) is not None, 'huellas Windows inválidas')
        path = HOST / file['file']
        require(path.is_file() and not path.is_symlink(), 'fichero Windows ausente o enlace')
        require(android.digest_file(path) == (file['bytes'], file['sha256']), 'fichero Windows distinto del manifiesto')
    lock = (HOST / '.publish.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    journal = HOST / '.publish-windows-1.0.25.json'
    require(SECRET.is_dir() and not SECRET.is_symlink(), 'directorio secretos inválido')
    key = (SECRET / 'dokploy.key').read_text().strip()

    def dokploy(path, body=None):
        request = urllib.request.Request('http://127.0.0.1:3000/api' + path,
            data=json.dumps(body).encode() if body is not None else None,
            headers={'x-api-key': key, 'Content-Type': 'application/json'}, method='POST' if body is not None else 'GET')
        with urllib.request.urlopen(request, timeout=30) as response:
            require(response.status == 200, 'Dokploy no aceptó la operación')
            # Este POST puede contestar sin JSON. El 200 sólo acredita la petición;
            # verify exige después un despliegue único done y el anuncio exacto.
            if path == '/application.redeploy':
                return None
            return json.load(response)

    query = '?' + urllib.parse.urlencode({'applicationId': android.APP})
    deployments = dokploy('/deployment.all' + query)
    require(isinstance(deployments, list), 'despliegues API inválidos')
    title = 'Windows 1.0.25+26 verificado 2026-10-06'

    def record(evidence, phase):
        evidence['phase'] = phase
        with journal.open('w') as stream:
            json.dump(evidence, stream, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        print(json.dumps({'phase': phase, 'production_verified': evidence['production_verified']}), flush=True)

    if args.mode == 'verify':
        require(journal.is_file() and not journal.is_symlink(), 'diario Windows ausente o enlace')
        evidence = json.loads(journal.read_text())
        require(evidence.get('phase') in ('redeploy_requested', 'production_verified')
                and evidence.get('files') == files and evidence.get('source') == args.source
                and evidence.get('run') == args.run, 'diario Windows distinto')
        ours = [d for d in deployments if d.get('title') == title and d.get('deploymentId') not in evidence['old_deployment_ids']]
        require(len(ours) == 1 and ours[0].get('status') == 'done', 'despliegue Windows todavía no verificado')
        application = dokploy('/application.one' + query)
        require(application.get('applicationId') == android.APP
                and isinstance(application.get('env'), str)
                and hashlib.sha256(application['env'].encode()).hexdigest() == evidence.get('replacement_env_sha256'),
                'entorno Windows verificado distinto')
        installer = next(f for f in files if f['file'].endswith('.exe'))
        expected = json.loads(json.dumps(evidence['old_announcement']))
        expected['descargas']['windows'] = PREFIX + installer['file']
        expected.setdefault('ficheros', {})['windows'] = {k: installer[k] for k in ['bytes', 'sha256']}
        require(android.api_version() == expected and public_json('https://reparto.procovar.cloud/api/version')['ultima'] == expected,
                'anuncio Windows distinto o cambió otro dato')
        for file in files:
            verify_download(file)
        require(set(evidence['old_store_keys']).issubset(inventory()), 'faltan versiones anteriores')
        evidence.update(production_verified=True, new_deployment_id=ours[0]['deploymentId'],
                        physical_installation_verified=False)
        record(evidence, 'production_verified')
        return

    require(all(d.get('status') not in ('running', 'queued') for d in deployments), 'otro despliegue API está activo')
    application = dokploy('/application.one' + query)
    require(application.get('applicationId') == android.APP, 'Dokploy devolvió otra aplicación')
    original = application.get('env')
    require(isinstance(original, str), 'entorno API inválido')
    announcement = android.api_version()
    verify_baseline(announcement)
    require('windows' not in announcement.get('descargas', {}), 'Windows ya está anunciado; revisar antes de cambiarlo')
    android_expected = {
        'APP_ULTIMA_VERSION': '1.0.25', 'APP_ULTIMA_COMPILACION': '26',
        'APP_DESCARGA_ANDROID': announcement['descargas']['android'],
        'APP_DESCARGA_ANDROID_BYTES': '78868528', 'APP_DESCARGA_ANDROID_SHA256': ANDROID_SHA,
    }
    android_actual = {}
    values = {}
    for line in original.splitlines():
        name, separator, value = line.partition('=')
        if name in android_expected:
            require(separator and name not in android_actual, 'variables Android duplicadas o inválidas')
            android_actual[name] = value
        if name.startswith('APP_DESCARGA_WINDOWS'):
            require(separator and name not in values and value in ('', '""', "''"), 'variables Windows ya configuradas o duplicadas')
            values[name] = value
    require(android_actual == android_expected, 'entorno Android distinto del anunciado')
    before = inventory()
    if args.mode == 'resume':
        require(journal.is_file() and not journal.is_symlink(), 'diario de subida Windows ausente o enlace')
        evidence = json.loads(journal.read_text())
        require(evidence.get('phase') == 'uploaded' and evidence.get('production_verified') is False
                and evidence.get('files') == files and evidence.get('source') == args.source and evidence.get('run') == args.run
                and evidence.get('old_deployment_ids') == [d['deploymentId'] for d in deployments]
                and evidence.get('original_env_sha256') == hashlib.sha256(original.encode()).hexdigest()
                and evidence.get('old_announcement') == announcement
                and isinstance(evidence.get('old_store_keys'), list)
                and set(evidence['old_store_keys']).issubset(before)
                and all(any(k == f['file'] or k.endswith('/' + f['file']) for k in before) for f in files),
                'no se puede retomar este diario Windows')
    else:
        require(not journal.exists(), 'existe intento previo; no repetir a ciegas')
        require(all(not any(k.endswith('/' + f['file']) or k == f['file'] for k in before) for f in files),
                'objeto Windows ya existe; no sobrescribir')
        evidence = dict(files=files, source=args.source, run=args.run, old_announcement=announcement,
                        old_deployment_ids=[d['deploymentId'] for d in deployments], old_store_keys=sorted(before),
                        original_env_sha256=hashlib.sha256(original.encode()).hexdigest(), production_verified=False)
        fd = os.open(journal, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(fd)
        record(evidence, 'upload_attempt')
        for file in files:
            mime = 'application/octet-stream' if file['file'].endswith('.exe') else 'application/zip'
            command(['mc-procovar', 'cp', '--attr', f'Content-Type={mime};Cache-Control=private, no-store;Content-Disposition=attachment',
                     '/host/apk/' + file['file'], STORE + file['file']], 'subida Windows', timeout=300)
        after = inventory()
        require(before.issubset(after)
                and all(any(k == f['file'] or k.endswith('/' + f['file']) for k in after) for f in files),
                'inventario incompleto tras subida')
        record(evidence, 'uploaded')
    for file in files:
        verify_download(file)
    require(android.api_version() == announcement and dokploy('/application.one' + query).get('env') == original,
            'producción cambió durante la descarga; no pisar cambios')
    installer = next(f for f in files if f['file'].endswith('.exe'))
    # Los tres campos nuevos necesitan separar la última línea del entorno.
    # La copia de seguridad conserva original exacto, incluso sin salto final.
    separated = original if original.endswith('\n') else original + '\n'
    replacement = android.update_env(separated, {
        'APP_DESCARGA_WINDOWS': PREFIX + installer['file'],
        'APP_DESCARGA_WINDOWS_BYTES': str(installer['bytes']),
        'APP_DESCARGA_WINDOWS_SHA256': installer['sha256'],
    })
    current = dokploy('/deployment.all' + query)
    require(isinstance(current, list) and [d['deploymentId'] for d in current] == evidence['old_deployment_ids']
            and all(d.get('status') not in ('running', 'queued') for d in current),
            'despliegues cambiaron; no modificar entorno')
    backup = SECRET / 'reparto-api-before-windows-1.0.25-261006.env'
    fd = os.open(backup, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, 'w', newline='') as stream:
        stream.write(original)
        stream.flush()
        os.fsync(stream.fileno())
    with backup.open('r', newline='') as stream:
        require(stream.read() == original, 'copia del entorno distinta')
    evidence['replacement_env_sha256'] = hashlib.sha256(replacement.encode()).hexdigest()
    record(evidence, 'env_update_attempt')
    dokploy('/application.update', {'applicationId': android.APP, 'env': replacement})
    require(dokploy('/application.one' + query).get('env') == replacement, 'entorno nuevo no coincide')
    require(all(d.get('status') not in ('running', 'queued') for d in dokploy('/deployment.all' + query)),
            'otro despliegue arrancó; no lanzar uno más')
    record(evidence, 'redeploy_attempt')
    dokploy('/application.redeploy', {'applicationId': android.APP, 'title': title,
                                   'description': 'Instalador Windows comprobado por CI; descarga íntegra, rango y huellas verificados.'})
    record(evidence, 'redeploy_requested')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'production_verified': False, 'error_type': type(error).__name__,
                          'reason': str(error) if isinstance(error, android.Stop) else 'detalle privado suprimido; inspeccionar diario antes de retomar'}))
        sys.exit(1)
