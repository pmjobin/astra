#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute exact production budget predicates with independent boundary oracles."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from run import BASE, C0_SHA256, ROOT, WORK, git, sha, write


def definition(path, name):
	data = path.read_bytes()
	first = data.index(('bool '+name+'(').encode())
	last = data.index(b'\n}\n', first)+3
	return data[first:last]


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--component', action='append', required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	assert sha(a.compiler) == C0_SHA256
	for path, parent in ((a.build, WORK/'build'), (a.runtime, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve())
		path.mkdir(parents=True, exist_ok=False)
	producer = definition(ROOT/'compiler/semantic/generic.astra', 'generic_syntax_room')
	consumer = definition(ROOT/'compiler/semantic/generic-check.astra', 'generic_syntax_count_valid')
	cases = []
	for originals in (-1, 0, 1, 262143, 262144, 309231, 1000000, 2147221503, 2147483647):
		for generated in (-1, 0, 1, 262143, 262144, 262145):
			total = originals+generated
			if -2147483648 <= total <= 2147483647:
				room = originals >= 0 and originals <= total < min(originals+262144, 2147483647)
				valid = originals >= 0 and originals <= total <= originals+262144
				cases.append(dict(originals=originals, total=total, room=room, valid=valid))
	lines = []
	for row in cases:
		for name, key in (('generic_syntax_room', 'room'), ('generic_syntax_count_valid', 'valid')):
			lines.append('\tif ('+name+'('+str(row['originals'])+', '+str(row['total'])+') != '+str(row[key]).lower()+') return 3;')
	main_source = ('int main() {\n'+'\n'.join(lines)+'\n\treturn 42;\n}\n').encode()
	positive = producer+b'\n'+consumer+b'\n'+main_source
	variants = dict(positive=positive,
		producer_off_by_one=positive.replace(b'total - originals < 262144', b'total - originals <= 262144'),
		consumer_off_by_one=positive.replace(b'total - originals <= 262144', b'total - originals < 262144'),
		originals_counted_again=positive.replace(b'total - originals < 262144', b'total < 262144'))
	assert len(set(variants.values())) == 4
	commands = []
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		with (a.runtime/(name+'.stdout')).open('wb') as out, (a.runtime/(name+'.stderr')).open('wb') as err:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *argv], cwd=a.build, stdout=out, stderr=err, start_new_session=True, env=dict(os.environ, CCACHE_DISABLE='1'))
			try:
				code = process.wait(300)
			except subprocess.TimeoutExpired:
				os.killpg(process.pid, signal.SIGKILL)
				process.wait()
				raise
		commands.append(dict(name=name, argv=argv, exit=code, seconds=time.monotonic()-start, stdout_sha256=sha(a.runtime/(name+'.stdout')), stderr_sha256=sha(a.runtime/(name+'.stderr'))))
		write(a.runtime/'commands.json', commands)
		assert code in allowed, (name, code)
		return code
	profiles = {}
	for value in a.component:
		mode, filename = value.split('=', 1)
		assert mode in ('O0', 'O2') and mode not in profiles
		component = Path(filename)
		identity = json.loads(component.with_suffix('.identity.json').read_text())
		assert sha(component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+mode
		# Reuse the preserved R5 compiler as a baseline translator of these two
		# new functions. Changed implementation paths bind to their original Git
		# bytes, not a false assertion that this is a rebuilt current compiler.
		for group in ('sources', 'tools'):
			for filename, expected in identity['identity'][group].items():
				path = Path(filename)
				if sha(path) != expected:
					assert path.is_relative_to(ROOT)
					assert hashlib.sha256(git('show', BASE+':'+str(path.relative_to(ROOT)))).hexdigest() == expected
		observations = []
		for name, data in variants.items():
			label = mode+'-'+name
			source = a.runtime/(label+'.astra')
			source.write_bytes(data)
			oracle = a.build/(label+'-C0')
			exe = a.build/(label+'-Astra')
			physical = a.build/(label+'.ll')
			obj = a.build/(label+'.o')
			run([a.compiler, '-'+mode, source, '-o', oracle], label+'-C0-build')
			run([component, '--native', physical, source], label+'-Astra-emit')
			run(['opt', '-passes=verify', '-disable-output', physical], label+'-verify')
			run(['opt', '-passes=default<'+mode+'>', '-S', physical, '-o', a.build/(label+'-optimized.ll')], label+'-optimize')
			run(['llc', '-filetype=obj', '-'+mode, a.build/(label+'-optimized.ll'), '-o', obj], label+'-object')
			run(['cc', '-no-pie', obj, '-o', exe], label+'-link')
			expected = 42 if name == 'positive' else 3
			for who, product in (('C0', oracle), ('Astra', exe)):
				run([product], label+'-'+who+'-execute', (expected,))
				if name == 'positive':
					memory = label+'-'+who+'-memory'
					run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], memory, (42,))
					log = (a.runtime/(memory+'.stderr')).read_bytes()
					assert all(marker in log for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
			observations.append(dict(case=name, source_sha256=sha(source), raw_LLVM_sha256=sha(physical), object_sha256=sha(obj), C0_ELF_sha256=sha(oracle), Astra_ELF_sha256=sha(exe), actual_exit=expected))
		profiles[mode] = dict(component_sha256=sha(component), observations=observations)
		print(mode, len(cases), 'boundary pairs; positive and three executable semantic mutants verified', flush=True)
	write(a.runtime/'result.json', dict(status='PASS', cases=cases, producer_sha256=hashlib.sha256(producer).hexdigest(), consumer_sha256=hashlib.sha256(consumer).hexdigest(), profiles=profiles, limitation='Actual production scalar budget definitions execute under C0 and the R5 Astra translator. This helper-only check does not prove complete generic cloning, whole compiler admission, a rebuilt compiler product or any full milestone gate. The three mutants are semantic helpers, not whole-module physical-mutation categories.'))


if __name__ == '__main__':
	main()
