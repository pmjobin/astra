#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify the installed C formatter candidate without changing source or pins."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/format'))
from lanes import stable_format, guard
from lexical import call_interiors


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=False)
	tool = shutil.which('clang-format')
	sha = lambda raw: hashlib.sha256(raw).hexdigest()
	start = time.monotonic()
	rows = []
	for name,row in json.loads((ROOT/'format/scope.json').read_text()).items():
		if row.get('lane') in ('c', 'cpp'):
			before = (ROOT/name).read_bytes()
			after = stable_format(row['lane'], before, name, ROOT, {'clang-format':tool})
			rows.append(dict(path=name, before_sha256=sha(before), after_sha256=sha(after)))
	pilot = b'''#include <stdio.h>
#define SPELL(x) #x
#define VALUE \\
  42
int main(void) { const char *text=SPELL( x  + y ); /* exact */ if(VALUE!=42){return 1;} puts(text); return 42; }
'''
	after = stable_format('c', pilot, 'adversarial.c', ROOT, {'clang-format':tool})
	assert [(ordinal, pilot[start:end]) for ordinal,start,end in call_interiors(pilot)] == [(ordinal, after[start:end]) for ordinal,start,end in call_interiors(after)]
	mutations = [after.replace(b'exact', b'wrong'), after.replace(b'42', b'43'), after.replace(b' x  + y ', b' x  - y '), after.replace(b'#define VALUE', b'#define OTHER')]
	for mutant in mutations:
		assert mutant != after
		try: guard('c', pilot, mutant, 'adversarial.c', {'clang-format':tool})
		except ValueError: pass
		else: raise AssertionError('formatter mutation escaped guard')
	commands = []
	for name,data in (('before', pilot), ('after', after)):
		path = a.runtime/(name+'.c')
		path.write_bytes(data)
		for mode in ('O0', 'O2'):
			exe = a.build/(name+'-'+mode)
			argv = ['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-'+mode, str(path), '-o', str(exe)]
			r = subprocess.run(argv, capture_output=True)
			assert r.returncode == 0, r.stderr
			native = subprocess.run([exe], capture_output=True)
			assert native.returncode == 42 and native.stdout == b'x + y\n' and not native.stderr
			commands.append(dict(argv=argv, executable_sha256=sha(exe.read_bytes()), native_exit=native.returncode, stdout_sha256=sha(native.stdout)))
	result = dict(status='C_FORMATTER_CANDIDATE_QUALIFIED', tool=str(Path(tool).resolve()), sha256=sha(Path(tool).read_bytes()), version=subprocess.check_output([tool, '--version'], text=True).strip(), guarded_sources=rows, rejected_mutations=len(mutations), C_native_profiles=commands, wall_seconds=time.monotonic()-start, scope='Formatting only; LLVM 23.1.4 compiler baseline unchanged', recipe_sha256=sha(Path(__file__).read_bytes()))
	(a.runtime/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(result['status'], len(rows), result['sha256'])


if __name__ == '__main__':
	main()
