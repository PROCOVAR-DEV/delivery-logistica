#!/usr/bin/env python3
"""Genera los guiones de publicación de Reparto de la versión N+1 a partir de los de la N.

Hasta la 1.0.51 se copiaban a mano de versión en versión, cambiando ~10 constantes, y la 1.0.51 paró en `allow-windows` («Cambió la
política»): esa lista de políticas es ACUMULADA (una línea `before['Statement'].append` por cada Windows ya publicado) y hay que
AÑADIR la de la versión anterior, no sustituirla. Aquí está escrito una vez.

  deploy/plantillar-publicacion.py --desde 1.0.50 --a 1.0.51 --compilacion 52 --apk app/build/app/outputs/flutter-apk/app-release.apk \
      --salida /tmp/w51 [--origen DIR]

Sin `--origen` lee los guiones de la N del servidor (`ssh vps-vpn`, `…/rutas-historico/publicacion-N/`) y los hashes de la N de su
evidencia (`/var/lib/procovar/apk/.publish-windows-N.json`). No sube nada: deja los ficheros en `--salida` y el resto de la cadena
(`scp`, `transfer-ci-vps.py`, `verify-ci-artifact.py`, `stage`, `allow`, `publicar-windows-verificada.py`, `update-portal-*`) sigue como
en `docs/compilar.md`.
"""
import argparse, hashlib, json, pathlib, re, subprocess, sys

HISTORICO = '/var/lib/procovar/verificacion-guia-20261006/rutas-historico'
POLITICA = "before['Statement'].append("


def ssh(cmd):
    return subprocess.run(['ssh', 'vps-vpn', cmd], check=True, capture_output=True, text=True).stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--desde', required=True)
    ap.add_argument('--a', required=True)
    ap.add_argument('--compilacion', required=True, type=int)
    ap.add_argument('--apk', required=True)
    ap.add_argument('--fecha-apk', default=None, help='AAMMDD de la APK nueva (por defecto, la de hoy, como en publicar-apk.sh)')
    ap.add_argument('--salida', required=True)
    ap.add_argument('--origen', default=None, help='directorio con los guiones de la N (si no, el servidor)')
    a = ap.parse_args()
    n, m = a.desde, a.a
    sufijo_n, sufijo_m = n.replace('.0.', '').replace('.', ''), m.replace('.0.', '').replace('.', '')  # 1.0.50 -> 150 (solo para nombres)
    num_n, num_m = n.split('.')[-1], m.split('.')[-1]  # '50', '51'
    comp_n = a.compilacion - 1
    out = pathlib.Path(a.salida); out.mkdir(parents=True, exist_ok=True)

    # 1 · los guiones de la N
    if a.origen:
        origen = {p.name: p.read_text() for p in pathlib.Path(a.origen).iterdir() if p.suffix in ('.py', '.cjs')}
    else:
        nombres = ssh(f"cd {HISTORICO}/publicacion-{n} && ls *.py *.cjs").split()
        origen = {x: ssh(f"cat {HISTORICO}/publicacion-{n}/{x}") for x in nombres}

    # 2 · lo que cambia de «la anterior» (N-1) a «la anterior» (N): APK y Windows de la N
    apk = pathlib.Path(a.apk).read_bytes()
    apk_sha, apk_bytes = hashlib.sha256(apk).hexdigest(), len(apk)
    ev = json.loads(ssh(f"cat /var/lib/procovar/apk/.publish-windows-{n}.json"))
    nuevo_win = {x['file']: (x['bytes'], x['sha256']) for x in ev['files']}
    setup_n, zip_n = nuevo_win[f'reparto-{n}-windows-setup.exe'], nuevo_win[f'reparto-{n}-windows.zip']

    # el apk de la N (sha y bytes) y los Windows de la N-1 están escritos en los guiones de la N: se leen de ahí
    def uno(patron, texto, que):
        r = re.findall(patron, texto)
        if not r:
            sys.exit(f'No encuentro {que} en los guiones de la {n}')
        return r[0]
    todo = '\n'.join(origen.values())
    apk_sha_n = uno(r"ANDROID_SHA = '([0-9a-f]{64})'", todo, 'ANDROID_SHA')
    win_prev = {}  # los de la N-1, tal como los trae allow-windows (old_files)
    for f, b, s in re.findall(r"\{'file':'(reparto-[\d.]+-windows(?:-setup\.exe|\.zip))','bytes':(\d+),'sha256':'([0-9a-f]{64})'\}", todo):
        win_prev[f] = (int(b), s)
    pares = [(str(win_prev[k][0]), str(setup_n[0]) if 'setup' in k else str(zip_n[0])) for k in win_prev] + \
            [(win_prev[k][1], setup_n[1] if 'setup' in k else zip_n[1]) for k in win_prev]

    for nombre, texto in origen.items():
        lineas_politica = [l for l in texto.splitlines(keepends=True) if l.startswith(POLITICA)]
        cuerpo = ''.join(l for l in texto.splitlines(keepends=True) if not l.startswith(POLITICA))
        # a) todo lo «anterior» (N-1 -> N) y lo «nuevo» (N -> M), sin pisarse entre sí
        prev_n1 = f'1.0.{int(num_n) - 1}'
        cuerpo = cuerpo.replace(prev_n1, '@P@')
        fecha_n1 = re.findall(r'reparto-@P@-(\d{6})\.apk', cuerpo)
        cuerpo = cuerpo.replace(n, m)
        cuerpo = cuerpo.replace('@P@', n)
        for f in set(fecha_n1):
            cuerpo = cuerpo.replace(f'reparto-{n}-{f}.apk', f'reparto-{n}-@FN@.apk')
        fecha_n = re.findall(rf'reparto-{re.escape(m)}-(\d{{6}})\.apk', cuerpo)
        fecha_m = a.fecha_apk or __import__('time').strftime('%y%m%d')
        for f in set(fecha_n):
            cuerpo = cuerpo.replace(f'reparto-{m}-{f}.apk', f'reparto-{m}-{fecha_m}.apk')
        cuerpo = cuerpo.replace('@FN@', fecha_n[0] if fecha_n else fecha_m)
        # b) hashes: Windows de la N-1 -> los de la N; APK de la N -> la nueva
        for viejo, nuevo in pares:
            cuerpo = cuerpo.replace(viejo, nuevo)
        cuerpo = cuerpo.replace(apk_sha_n, apk_sha)
        # c) compilación
        cuerpo = re.sub(rf"(==\s?){comp_n}\b", lambda mo: f"{mo.group(1)}{a.compilacion}", cuerpo)
        cuerpo = cuerpo.replace(f"'APP_ULTIMA_COMPILACION': '{comp_n}'", f"'APP_ULTIMA_COMPILACION': '{a.compilacion}'")
        cuerpo = cuerpo.replace(f"{{'{m}': {comp_n}}}", f"{{'{m}': {a.compilacion}}}")
        # d) la política ACUMULADA: se conservan todas las líneas y se AÑADE la de la N
        if lineas_politica:
            propia = lineas_politica[-1].replace(prev_n1, n)
            assert propia.count(f'reparto-{n}-') == 2, 'no pude escribir la línea de la política'
            ya = any(f'reparto-{n}-windows-setup.exe' in l for l in lineas_politica)
            ancla = next(i for i, l in enumerate(cuerpo.splitlines(keepends=True)) if l.startswith('source,runid'))
            ls = cuerpo.splitlines(keepends=True)
            ls[ancla:ancla] = lineas_politica + ([] if ya else [propia])
            cuerpo = ''.join(ls)
        # e) el nombre del fichero lleva el número de la versión
        nombre_nuevo = nombre.replace(f'{num_n}.py', f'{num_m}.py')
        (out / nombre_nuevo).write_text(cuerpo)
    print(f'Listo en {out}: {len(origen)} guiones de la {m} (compilación {a.compilacion}); APK {apk_bytes} B sha {apk_sha[:12]}…')


main()
