"""Fetch the four pinned, hash-verified robot sources needed by software co-simulation."""
import hashlib
import json
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parent
FILES = ('include/robot/core.hpp', 'src/kinematics.cpp', 'src/world.cpp', 'src/lidar.cpp')
PREFIX = '02_ROBOTICS_NAVIGATION/robot_core/'


def download_sources(manifest):
    revision = manifest['revision']
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Dependency must name an exact commit SHA')
    if set(manifest['files']) != {PREFIX + name for name in FILES}:
        raise ValueError('Unexpected dependency file selection')
    sources = {}
    for name, expected in manifest['files'].items():
        url = f'https://raw.githubusercontent.com/nabwei/engineering-portfolio/{revision}/{name}'
        with urllib.request.urlopen(url, timeout=30) as response:
            payload = response.read()
        if hashlib.sha256(payload).hexdigest() != expected:
            raise ValueError(f'Dependency hash mismatch: {name}')
        sources[name] = payload
    return sources


def install_sources(sources):
    for name, payload in sources.items():
        target = ROOT / name
        if target.exists() and target.read_bytes() != payload:
            raise ValueError(f'Refusing to replace a modified dependency: {name}')
    for name, payload in sources.items():
        target = ROOT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            with target.open('xb') as stream:
                stream.write(payload)


if __name__ == '__main__':
    manifest = json.loads((ROOT / 'robot_dependency.json').read_text(encoding='utf-8'))
    install_sources(download_sources(manifest))
    print('PASS: four published robot dependency files verified against pinned SHA-256 values')
