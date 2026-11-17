#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Install on a fresh pinned image with only the package, QA script and log mount."""
import argparse
import json
from pathlib import Path
import shutil

from common import ROOT, clean_environment, external, require, run, sha, verify, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--package', type=Path, required=True)
	p.add_argument('--sha256', required=True)
	p.add_argument('--kind', choices=('deb', 'rpm'), required=True)
	p.add_argument('--work', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--engine', choices=('docker', 'podman'), default='docker')
	p.add_argument('--engine-root', type=Path)
	p.add_argument('--engine-runroot', type=Path)
	p.add_argument('--development', action='store_true')
	p.add_argument('--llvm', type=Path, help='Authenticated headers for the independent installed LLVM oracle')
	a = p.parse_args()
	require(sha(a.package) == a.sha256, 'artifact changed since builder receipt')
	work = external(a.work)
	build = external(a.build)
	qa = work/'qa'
	qa.mkdir()
	shutil.copyfile(ROOT/'tests/install/lifecycle.py', qa/'lifecycle.py')
	for name in ('getting-started.md', 'tooling.md'):
		shutil.copyfile(ROOT/'docs/guide'/name, qa/name)
	if a.development:
		require(a.llvm, 'development memory oracle requires authenticated public LLVM headers')
		pins = json.loads((ROOT/'tools/ci/llvm-linux.json').read_text())['files']
		for name, pin in pins.items():
			if name.startswith('include/'):
				verify(a.llvm/name, pin)
				target = qa/name
				target.parent.mkdir(parents=True, exist_ok=True)
				shutil.copyfile(a.llvm/name, target)
		for name in ('llvm-direct.c', 'llvm-instcombine.ll'):
			shutil.copyfile(ROOT/'tests/install/diagnostics'/name, qa/name)
		shutil.copyfile(ROOT/'tests/install/development_memory.py', qa/'development_memory.py')
		shutil.copyfile(ROOT/'tests/books/values.astra', qa/'values.astra')
		write(work/'qa-inputs.json', {str(path.relative_to(qa)):sha(path) for path in qa.rglob('*') if path.is_file()})
	engine = [a.engine]
	if a.engine_root:
		require(a.engine == 'podman' and a.engine_runroot, 'private engine roots require podman')
		engine += ['--root', str(a.engine_root), '--runroot', str(a.engine_runroot)]
	distro = 'ubuntu' if a.kind == 'deb' else 'fedora'
	image = json.loads((ROOT/'tools/ci'/('development-containers.json' if a.development else 'containers.json')).read_text())['platforms'][distro]['image']
	argv = [*engine, 'run', '--rm', '--platform', 'linux/amd64', '--security-opt', 'label=disable', '--memory', '4g', '--cpus', '2', '-v', str(a.package.resolve())+':/package/'+a.package.name+':ro', '-v', str(qa)+':/qa:ro', '-v', str(work)+':/logs:rw', '-v', str(build)+':/build:rw', '-e', 'TMPDIR=/build', image, 'sh', '-ec']
	# The base images do not promise Python. Obtain only the test interpreter
	# before the package manager installs the package's declared dependencies.
	setup = 'apt-get update && apt-get install -y --no-install-recommends python3 sudo time' if a.kind == 'deb' else 'dnf install -y python3 sudo time'
	argv += [setup+' && python3 -B /qa/lifecycle.py --kind "$1" --package "$2" --sha256 "$3" --output /logs/lifecycle --memory'+(' --development' if a.development else ''), 'install-test', a.kind, '/package/'+a.package.name, a.sha256]
	run(argv, work/'container', clean_environment(), timeout=1800)
	result = json.loads((work/'lifecycle/result.json').read_text())
	require(result['status'] == 'CLEAN_INSTALL_SMOKE_REINSTALL_UNINSTALL_PASS', 'installation acceptance absent')
	write(work/'result.json', dict(status=result['status'], package_sha256=a.sha256, image=image, lifecycle_sha256=sha(work/'lifecycle/result.json'), qualification=result.get('qualification'), strict_memory=result.get('strict_memory'), scope='Fresh container userland; shared host kernel. Not a VM or Windows test.'))


if __name__ == '__main__':
	main()
