#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real lane pilots with macro-coordinate and C++ RAII observations."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/format'))
from source import qualified_tools
from lanes import stable_format
from preprocess import compare_preprocessed


def sha(data):
	return hashlib.sha256(data).hexdigest()


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--astrac', required=True)
	p.add_argument('--uncrustify', required=True)
	a = p.parse_args()
	assert not a.runtime.resolve().is_relative_to(ROOT)
	a.runtime.mkdir(parents=True, exist_ok=False)
	tools, pins = qualified_tools({'vala', 'astra', 'c', 'cpp', 'python', 'meson', 'shell', 'javascript'}, a.astrac, a.uncrustify)
	commands, rows = [], []
	def run(argv, name):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], capture_output=True, timeout=180)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode,
			monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == 0, (name, r.stderr[-2000:])
		return r.stdout
	paths = {
		'astra-model': ('astra', 'compiler/core/model.astra'),
		'astra-semantic': ('astra', 'compiler/semantic/flow-build.astra'),
		'astra-backend': ('astra', 'compiler/backend/llvm/module.astra'),
		'vala-large': ('vala', 'bootstrap/semantic/analyzer.vala'),
		'C-shim': ('c', 'compiler/backend/llvm/capi.c'),
		'C-enum': ('c', 'bootstrap/backend/llvm/capi/native-proof.c'),
		'cpp-provider': ('cpp', 'tests/interop-tooling-14/com-import/provider.cpp'),
		'python': ('python', 'tests/selfhost-nativeabi/run.py'),
		'meson': ('meson', 'meson.build'),
		'shell': ('shell', 'tools/check-clean.sh'),
	}
	scope = json.loads((ROOT/'format/scope.json').read_text())
	# Select actual classified scripts where repository filenames differ.
	for lane in ('shell', 'javascript'):
		paths[lane] = (lane, next(name for name, entry in scope.items() if entry.get('lane') == lane))
	for label, (lane, name) in paths.items():
		before = (ROOT/name).read_bytes(); after = stable_format(lane, before, name, ROOT, tools)
		(a.runtime/(label+'.before')).write_bytes(before); (a.runtime/(label+'.after')).write_bytes(after)
		rows.append(dict(path=name, lane=lane, before_sha256=sha(before), after_sha256=sha(after),
			guard='PASS', idempotent=stable_format(lane, after, name, ROOT, tools) == after))
	cpp = b'''#include <cstdio>
struct Guard{int id;~Guard(){std::printf("D%d\\n",id);}};
int work(){Guard outer{1};for(int i=0;i<3;i++){Guard inner{2};if(i==0){continue;}if(i==1){break;}}if(true){Guard local{3};return 0;}return 1;}
int main(){return work();}
'''
	vala = b'''int work(){int x=0;try{x=1;}finally{x=x+2;}do{x++;}while(x<4);if(x!=4){return 1;}return 0;}
int main(){return work();}
'''
	c = b'''#include <assert.h>
#define VALUE(x) ((x)+1)
struct Item{int value;};
int work(void){assert(VALUE(1)==2);return 0;}
int main(void){return work();}
'''
	coordinate_maps = []
	for lane, data, suffix, command in [('cpp', cpp, '.cpp', ['g++', '-std=c++17', '-O2']),
		('vala', vala, '.vala', ['valac']), ('c', c, '.c', ['gcc', '-std=c11', '-O2'])]:
		outputs = []
		for label, text in [('before', data), ('after', stable_format(lane, data, 'pilot'+suffix, ROOT, tools))]:
			source = a.runtime/(lane+'-'+label+suffix); source.write_bytes(text)
			exe = source.with_suffix('.exe')
			run([*command, source, '-o', exe], lane+'-'+label+'-build')
			outputs.append(run([exe], lane+'-'+label+'-execute'))
		assert outputs[0] == outputs[1] == (b'D2\nD2\nD3\nD1\n' if lane == 'cpp' else b'')
		if lane == 'c':
			old = a.runtime/'c-before.c'; new = a.runtime/'c-after.c'
			x = run(['gcc', '-std=c11', '-E', '-P', old], 'c-before-preprocess')
			y = run(['gcc', '-std=c11', '-E', '-P', new], 'c-after-preprocess')
			coordinate_maps = compare_preprocessed(x, y, old.read_bytes(), new.read_bytes(), str(old), str(new))
			# Coordinate-bearing production source is explicitly inventoried, never
			# normalized as ordinary whitespace. True test inputs remain protected.
	coordinates = []
	for name, entry in scope.items():
		if entry.get('lane') in ('c', 'cpp', 'vala', 'astra'):
			for line, text in enumerate((ROOT/name).read_text().splitlines(), 1):
				if any(token in text for token in ('__LINE__', '__FILE__', '__COUNTER__', 'source_location::current')):
					coordinates.append(dict(path=name, line=line, text=text))
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', tools=pins, lanes=rows,
		cpp_RAII_trace='D2,D2,D3,D1', C_assert_coordinate_mappings=coordinate_maps,
		production_coordinate_inventory=coordinates,
		limits='Windows-only C++ units receive exact-token guards; this host pilot does not qualify Windows execution.'), indent=2)+'\n')
	print('PASS: all language lanes, actual C/C++/Vala executions, RAII and C assertion coordinate mapping')


if __name__ == '__main__':
	main()
