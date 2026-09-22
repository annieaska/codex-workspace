#!/usr/bin/env python3
import json
import socket
import subprocess
import sys
from pathlib import Path

CFG = Path('/opt/ops-monitor/conf/extra_targets.json')
CERT_PROBE = ['/usr/local/bin/check-lovewhowho-wildcard-cert.sh', '--probe']


def probe_ping(host: str):
    rc = subprocess.run(['ping', '-c', '1', '-W', '1', host], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    return ('UP' if rc == 0 else 'DOWN', f'ping={host}')


def probe_tcp(host: str, port: int):
    try:
        with socket.create_connection((host, int(port)), timeout=1.5):
            return ('UP', f'tcp={host}:{port}')
    except Exception:
        return ('DOWN', f'tcp={host}:{port}')


def probe_http(url: str, expect_codes):
    try:
        code = subprocess.check_output(['curl', '-k', '-s', '-o', '/dev/null', '-w', '%{http_code}', url], text=True).strip()
    except Exception:
        code = '000'
    ok = str(code) in {str(x) for x in expect_codes}
    return ('UP' if ok else 'DOWN', f'http={code} url={url}')


def probe_lovewhowho_certificate():
    try:
        result = subprocess.run(
            CERT_PROBE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=20,
            check=False,
        )
        rc = result.returncode
    except Exception:
        rc = 255
    return ('UP' if rc == 0 else 'DOWN', f'certificate_check_rc={rc}')


def main():
    if not CFG.exists():
        return 0
    data = json.loads(CFG.read_text(encoding='utf-8'))
    targets = data.get('targets', [])
    for t in targets:
        tid = t.get('id', '').strip()
        if not tid:
            continue
        probe = t.get('probe', '').strip().lower()
        if probe == 'ping':
            status, metric = probe_ping(t.get('host', '').strip())
        elif probe == 'tcp':
            status, metric = probe_tcp(t.get('host', '').strip(), int(t.get('port', 0)))
        elif probe == 'http':
            status, metric = probe_http(t.get('url', '').strip(), t.get('expect_codes', [200]))
        elif probe == 'lovewhowho_certificate':
            status, metric = probe_lovewhowho_certificate()
        else:
            status, metric = ('DOWN', f'unsupported_probe={probe}')
        print(f'{tid}|{status}|{metric}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
