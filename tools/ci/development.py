#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build one public-seed generation and two explicitly unqualified Linux packages."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

from common import ROOT, clean_environment, external, require, run, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--predecessor-deb', type=Path)
	p.add_argument('--predecessor-rpm', type=Path)
	p.add_argument('--predecessor-deb-sha256')
	p.add_argument('--predecessor-rpm-sha256')
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	platform = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
	require(platform['ID'].strip('"') == 'ubuntu' and platform['VERSION_ID'].strip('"') == '26.04', 'development DEB builder must be Ubuntu 26.04')
	build, runtime = external(a.build), external(a.runtime)
	env = clean_environment()
	head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
	def script(name, args, label=None):
		return run([sys.executable, '-B', ROOT/'tools/ci'/name, *args], runtime/('controller-'+(label or name[:-3])), env, cwd=ROOT, timeout=10800)
	try:
		script('runner.py', ['--output', runtime/'runner.json'])
		script('trust.py', ['--manifest', ROOT/'tools/ci/llvm-linux.json', '--output', build/'llvm'])
		llvm = build/'llvm/unpacked'
		script('llvm_dylib.py', ['--llvm', llvm, '--manifest', ROOT/'tools/ci/llvm-linux.json', '--build', build/'library', '--runtime', runtime/'library'])
		script('bootstrap.py', ['--commit', head, '--llvm', llvm, '--library', build/'library/libLLVM.so.23.1', '--library-receipt', runtime/'library/result.json', '--build', build/'bootstrap', '--runtime', runtime/'bootstrap', '--stages', '1', '--profiles', 'O2', '--jobs', '1'])
		script('handoff.py', ['--products', runtime/'bootstrap/result.json', '--identity', runtime/'bootstrap/identity.json', '--output', build/'handoff.json', '--system-llvm'])
		script('package.py', ['--object', build/'bootstrap/stage1/astrac-O2.o', '--handoff', build/'handoff.json', '--system-llvm', '--kind', 'deb', '--development', '--build', build/'deb', '--runtime', runtime/'deb'])
		transfer = build/'fedora-input'
		transfer.mkdir()
		shutil.copyfile(build/'bootstrap/stage1/astrac-O2.o', transfer/'astrac-O2.o')
		shutil.copyfile(build/'handoff.json', transfer/'handoff.json')
		require(sha(transfer/'astrac-O2.o') == json.loads((build/'handoff.json').read_text())['products']['O2']['object_sha256'], 'cross-distro object transfer mismatch')
		fedora = json.loads((ROOT/'tools/ci/development-containers.json').read_text())['platforms']['fedora']['image']
		(build/'fedora').mkdir()
		(runtime/'fedora').mkdir()
		command = 'dnf install -y gcc gcc-c++ python3 binutils rpm-build git llvm-devel llvm-libs time && python3 -B /src/tools/ci/package.py --object /input/astrac-O2.o --handoff /input/handoff.json --system-llvm --kind rpm --development --build /build/package --runtime /logs/package'
		run(['docker', 'run', '--rm', '--platform', 'linux/amd64', '--memory', '8g', '--cpus', '2', '-v', str(ROOT)+':/src:ro', '-v', str(transfer)+':/input:ro', '-v', str(build/'fedora')+':/build:rw', '-v', str(runtime/'fedora')+':/logs:rw', fedora, 'sh', '-ec', command], runtime/'controller-fedora', env, timeout=1800)
		packages = {'deb':next((build/'deb').glob('*.deb')), 'rpm':next((build/'fedora/package').glob('*.rpm'))}
		# Local/hosted build has no authorization to distribute newly rebuilt binaries.
		# The authenticated predecessor is an explicit lifecycle input, never a
		# network fallback to the old public artifact or a fake migration fixture.
		if not (a.predecessor_deb and a.predecessor_rpm):
			write(runtime/'result.json', dict(status='PARTIAL', packages={kind:dict(path=str(path), sha256=sha(path)) for kind, path in packages.items()}, qualification='DEVELOPMENT_UNQUALIFIED', reason='Build only: authenticated predecessor packages and full fresh lifecycle/memory acceptance still required; no binary distribution authorized'))
			return
		for kind, package in packages.items():
			old = a.predecessor_deb if kind == 'deb' else a.predecessor_rpm
			oracle = build/'deb/llvm-oracle' if kind == 'deb' else build/'fedora/package/llvm-oracle'
			script('clean_install.py', ['--package', package, '--sha256', sha(package), '--kind', kind, '--development', '--system-llvm', '--oracle', oracle, '--predecessor', old, '--predecessor-sha256', a.predecessor_deb_sha256 if kind == 'deb' else a.predecessor_rpm_sha256, '--work', runtime/(kind+'-install'), '--build', build/(kind+'-install')], kind+'-install')
		write(runtime/'result.json', dict(status='INSTALL_SMOKE_PASS', qualification='DEVELOPMENT_UNQUALIFIED', original_LLVM_strict_memory='NOT_PASS', source_commit=head, compiler_generations=1, compiler_profile='O2', target_profiles=['O0', 'O2'], cross_distro_object='Fedora reuses the authenticated Ubuntu-produced object; C providers recompile and distribution LLVM links independently on Fedora 45', packages={kind:dict(path=str(path), sha256=sha(path)) for kind, path in packages.items()}, public_artifacts='REQUIRES_SEPARATE_OWNER_APPROVAL'))
	except BaseException as error:
		write(runtime/'result.json', dict(status='ENGINEERING_FAILED', qualification='DEVELOPMENT_UNQUALIFIED', source_commit=head, error=str(error), failed_evidence='All completed and failed command records retained; no package publication'))
		raise


if __name__ == '__main__':
	main()
