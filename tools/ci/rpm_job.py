#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Package the authenticated nightly object on a pinned Fedora userland."""
import argparse
import json
from pathlib import Path
import sys

from common import ROOT, clean_environment, external, require, run, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--input', type=Path, required=True)
	p.add_argument('--handoff-sha256', required=True)
	p.add_argument('--work', type=Path, required=True)
	a = p.parse_args()
	handoff = a.input/'handoff.json'
	require(sha(handoff) == a.handoff_sha256, 'handoff differs from producing job output')
	data = json.loads(handoff.read_text())
	require(sha(a.input/'astrac-O2.o') == data['products']['O2']['object_sha256'], 'nightly object altered')
	work = external(a.work)
	env = clean_environment()
	image = json.loads((ROOT/'tools/ci/development-containers.json').read_text())['platforms']['fedora']['image']
	command = 'dnf install -y gcc gcc-c++ git python3 binutils rpm-build llvm-devel llvm-libs time && python3 -B /src/tools/ci/package.py --object /input/astrac-O2.o --handoff /input/handoff.json --system-llvm --development --kind rpm --build /output/package --runtime /output/package-logs'
	run(['docker', 'run', '--rm', '--platform', 'linux/amd64', '--memory', '8g', '--cpus', '2', '-v', str(ROOT)+':/src:ro', '-v', str(a.input.resolve())+':/input:ro', '-v', str(work)+':/output:rw', image, 'sh', '-ec', command], work/'container', env, timeout=1800)
	package = next((work/'package').glob('*.rpm'))
	write(work/'result.json', dict(status='RPM_BUILT_PENDING_FRESH_INSTALL', package_sha256=sha(package), handoff_sha256=a.handoff_sha256, image=image))


if __name__ == '__main__':
	main()
