#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Separate C0 native oracles and focused template/Flow observations."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, sha, write
from slots import CASES, ITEM


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--phase', choices=('prepare', 'observe'), required=True)
	p.add_argument('--providers', type=Path)
	p.add_argument('--component', type=Path)
	a = p.parse_args()
	assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('template-cases-'+a.version)
	build = a.build_root/leaf.name
	if a.phase == 'prepare':
		leaf.mkdir(); build.mkdir()
	else:
		assert leaf.is_dir() and build.is_dir() and a.component
	env = dict(os.environ, CCACHE_DISABLE='1')
	for name in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE'):
		env.pop(name, None)
	commands = []
	def run(argv, name, expected=None):
		argv = list(map(str, argv)); start = time.monotonic()
		with (leaf/(name+'.stdout')).open('wb') as out, (leaf/(name+'.stderr')).open('wb') as err:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=build, env=env, stdout=out, stderr=err, start_new_session=True)
			timed_out = False
			try:
				code = process.wait(120)
			except subprocess.TimeoutExpired:
				timed_out = True; os.killpg(process.pid, signal.SIGKILL); code = process.wait()
		commands.append(dict(name=name, argv=argv, exit=code, timed_out=timed_out, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		write(leaf/(a.phase+'-commands.json'), commands)
		assert not timed_out and (expected is None or code == expected), (name, code)
		return code
	def identity(product):
		cache = product.with_suffix('.identity.json'); data = json.loads(cache.read_text())
		assert sha(product) == data['sha256']
		for group in ('sources', 'tools'):
			for path, expected in data['identity'][group].items():
				assert sha(path) == expected, path
		return dict(path=str(product), sha256=sha(product), identity_sha256=sha(cache))
	if a.phase == 'prepare':
		assert a.providers
		objects = [a.providers/(name+'.o') for name in ('args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap')]
		provider_identities = [identity(obj) for obj in objects]
		bag = ROOT/'lib/astra/collections/bag.astra'; bag_bytes = bag.read_bytes()
		(leaf/'original-Bag.astra.txt').write_bytes(bag_bytes)
		client = ITEM+'int main()'+CASES['field-slot-operations'].split('int main()', 1)[1]
		client = client.replace('new Items()', 'new Bag<Item>()')
		vault = bag_bytes.decode().replace('class Bag<', 'class Vault<').replace('entries', 'storage')
		vault = vault.replace('bool reserve(', 'bool ensure(').replace('void append(', 'void put(').replace('owned T take(', 'owned T extract(')
		vault_client = client.replace('new Bag<', 'new Vault<').replace('values.reserve(', 'values.ensure(').replace('values.append(', 'values.put(').replace('values.take(', 'values.extract(')
		insert = vault.rfind('\n}')
		assert insert > 0
		unsupported = vault[:insert]+'\n\tint hidden() { return 40 + 2; }\n'+vault[insert:]
		rows = []
		for name, template, source in (('original-Bag', None, client), ('renamed-Vault', vault, vault_client), ('unused-unsupported', unsupported, vault_client)):
			main_source = leaf/(name+'-main.astra'); main_source.write_text(source)
			template_source = bag
			if template is not None:
				template_source = leaf/(name+'-template.astra'); template_source.write_text(template)
			inputs = [main_source, ROOT/'lib/astra/base/errors.astra', template_source]
			oracle = build/(name+'-C0')
			run([a.compiler, '-O0', *inputs, *[word for obj in objects for word in ('--link-object', obj)], '-o', oracle], name+'-C0-build', 0)
			run([oracle], name+'-C0-execute', 42)
			run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', oracle], name+'-C0-memory', 42)
			assert all(value in (leaf/(name+'-C0-memory.stderr')).read_bytes() for value in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
			rows.append(dict(name=name, inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], oracle=str(oracle), C0_ELF_sha256=sha(oracle), C0_exit=42, C0_unsuppressed_memory=True, template_expected=name != 'unused-unsupported'))
			write(leaf/'oracles.json', dict(status='C0_ORACLES_READY', original_Bag_sha256=sha(bag), providers=provider_identities, compiler_sha256=sha(a.compiler), programs=rows))
		print('C0_ORACLES_READY', len(rows), flush=True)
		return
	data = json.loads((leaf/'oracles.json').read_text()); assert data['status'] == 'C0_ORACLES_READY' and len(data['programs']) == 3
	component = identity(a.component)
	rows = []; complete = True
	for row in data['programs']:
		assert sha(row['oracle']) == row['C0_ELF_sha256']
		inputs = []
		for source in row['inputs']:
			assert sha(source['path']) == source['sha256']; inputs.append(source['path'])
		name = row['name']; positive = row['template_expected']; outcomes = {}
		for mode in ('templates', 'flow', 'mutations') if positive else ('templates', 'flow'):
			label = name+'-'+mode; code = run([a.component, '--'+mode, *inputs], label)
			output = (leaf/(label+'.stdout')).read_text()
			expected = (0 if mode == 'templates' else 42) if positive else (3 if mode == 'templates' else 2)
			valid = code == expected and 'TEMPLATE_COUNT 1\n' in output
			if mode == 'templates':
				members = [line for line in output.splitlines() if line.startswith('MEMBER ')]
				valid = valid and len(members) == (7 if positive else 8)
				valid = valid and (all(' SOURCE 1 ' in line for line in members) if positive else any(line.startswith('MEMBER hidden ') and ' SOURCE 0 ' in line for line in members))
			outcomes[mode] = dict(exit=code, expected_exit=expected, matched=valid)
			complete = complete and valid
		rows.append(dict(name=name, observations=outcomes, C0_ELF_sha256=row['C0_ELF_sha256'], inputs=row['inputs']))
		write(leaf/'result.json', dict(status='FOCUSED_TEMPLATE_FLOW_PASS' if complete and len(rows) == 3 else 'PARTIAL', component=component, programs=rows, target_native_credit=0, limitation='The observer executes current Typecore/Flow source under C0. No target Astra LLVM, object, ELF or full compiler completeness is proved. C0 native oracles and template mutations are separate evidence.'))
		print(name, outcomes, flush=True)
	assert complete


if __name__ == '__main__':
	main()
