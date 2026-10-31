#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the installed VS Code extension host against an isolated Astra project."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	parser.add_argument('--prefix', type=Path)
	args = parser.parse_args()
	compiler = args.compiler.resolve()
	output = args.output.resolve()
	prefix = args.prefix.resolve() if args.prefix else None
	if prefix:
		assert compiler == prefix / 'bin/astrac'
	sample = prefix / 'share/astra/examples/interop-tooling-14/editor-project' if prefix else ROOT / 'examples/interop-tooling-14/editor-project'
	server = prefix / 'bin/astra-lsp' if prefix else ROOT / 'tools/lsp/astra-lsp.py'
	extension = prefix / 'share/astra/editor' if prefix else ROOT / 'tools/lsp/editor'
	assert sample.is_dir() and server.is_file() and extension.is_dir()
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	compiler_sha = sha(compiler)
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='editor-', dir=output))
	project = work / 'project'
	shutil.copytree(sample, project)
	profile = work / 'user-data'
	(profile / 'User').mkdir(parents=True)
	scratch = work / 'scratch'
	scratch.mkdir()
	settings = {'astra.compilerPath': str(compiler), 'astra.serverPath': str(server),
		'astra.pythonPath': sys.executable, 'astra.scratchDirectory': str(scratch), 'extensions.autoUpdate': False,
		'extensions.autoCheckUpdates': False, 'update.mode': 'none', 'telemetry.telemetryLevel': 'off',
		'workbench.startupEditor': 'none', 'security.workspace.trust.enabled': False}
	(profile / 'User/settings.json').write_text(json.dumps(settings, indent=2) + '\n')
	command = ['code', '--user-data-dir', str(profile), '--extensions-dir', str(work / 'extensions'),
		'--disable-extensions', '--disable-workspace-trust', '--skip-welcome', '--skip-release-notes',
		'--new-window', '--wait', '--extensionDevelopmentPath=' + str(extension),
		'--extensionTestsPath=' + str(ROOT / 'tests/interop-tooling-14/editor-test.js'), str(project)]
	with (work / 'console.log').open('w') as log:
		result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=180,
			env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
	receipt_path = work / 'editor-receipt.json'
	receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
	receipt.update({'command': command, 'exit': result.returncode, 'compiler_sha256': compiler_sha,
		'installed_prefix': str(prefix) if prefix else None,
		'inputs': {str(path): sha(path) for path in [server, extension / 'extension.js', extension / 'package.json', *sorted(sample.glob('*.astra'))]}})
	(work / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
	assert result.returncode == 0 and receipt.get('status') == 'PASS', f'editor failed: {work}'
	receipt['status'] = 'EDITOR_PASS_APPLICATION_PENDING'
	receipt['application_checks'] = []
	def run(command, memory=False):
		assert sha(compiler) == compiler_sha
		p = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True, timeout=60,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		receipt['application_checks'].append({'command': list(map(str, command)), 'exit': p.returncode,
			'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == 0 and p.stdout == '', receipt['application_checks'][-1]
		assert ('ERROR SUMMARY: 0 errors' in p.stderr and 'in use at exit: 0 bytes in 0 blocks' in p.stderr) if memory else not p.stderr
	for level in ('0', '1', '2'):
		binary = work / ('editor-project-O' + level)
		run([compiler, '-O' + level, *sorted(project.glob('*.astra')), '-o', binary])
		run([binary])
		if level in ('0', '2'):
			run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--errors-for-leak-kinds=all', '--error-exitcode=99', binary], memory=True)
		receipt.setdefault('application_variants', []).append({'optimization': level, 'binary_sha256': sha(binary)})
	assert sha(compiler) == compiler_sha
	assert all(sha(path) == sha(project / path.name) for path in sample.glob('*.astra'))
	receipt['status'] = 'PASS'
	(work / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: actual {receipt["client"]}, {len(receipt["checks"])} editor checks; evidence {work}')


if __name__ == '__main__':
	main()
