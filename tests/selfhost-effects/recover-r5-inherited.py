#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay 202 inherited identities from authenticated R4 receipts after cleanup."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); p.add_argument('--historical', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r5_inherited_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('inherited-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
	for path, expected in identity['identity']['tools'].items(): assert sha(path) == expected
	for path, expected in identity['identity']['sources'].items():
		if a.historical and Path(path).is_relative_to(ROOT):
			data = subprocess.check_output(['git', 'show', 'c271e0822d0fc12a878a5adc1388aa1a8e147067:'+str(Path(path).relative_to(ROOT))], cwd=ROOT); assert __import__('hashlib').sha256(data).hexdigest() == expected
		else: assert sha(path) == expected
	history = paths.RUNTIME/'r4-history'; prior = history/('runtime/regression-final16-'+a.mode+'/inherited-v1-'+a.mode+'/result.json'); old = read(prior); assert len(old['programs']) == 202
	witnesses = {sha(p): p for p in (history/'inherited-input').rglob('*') if p.is_file()}; companions = load_module('r5_inherited_companions', ROOT/'tests/selfhost-nativeabi/corpus.py'); commands = []; rows = []
	environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('LD_PRELOAD', None); environment.pop('VALGRIND_OPTS', None)
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, capture_output=True, env=environment, timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stdout[-1000:], r.stderr[-2000:]); return r
	for ordinal, program in enumerate(old['programs']):
		mapping = {}; sources = []
		for row in program['sources']:
			source = Path(row['path']) if Path(row['path']).is_file() else witnesses[row['sha256']]
			assert sha(source) == row['sha256']; mapping[row['path']] = str(source); sources.append(dict(original=row['path'], actual=str(source), sha256=row['sha256']))
		raw = build/(str(ordinal)+'.ll'); obj = build/(str(ordinal)+'.o'); exe = build/(str(ordinal)+'-Astra'); c0 = build/(str(ordinal)+'-C0')
		products = program['fresh_products']; emit = next(c for c in old['commands'] if c['name'] == str(ordinal*5)+'-'+str(ordinal)+'-emit')
		argv = [mapping.get(word, word) for word in emit['argv']]; argv[0] = str(a.component); argv[3] = str(raw)
		run(argv, str(ordinal)+'-emit'); run(['opt', '-passes=verify', '-disable-output', raw], str(ordinal)+'-verify'); object_argv = argv.copy(); object_argv[1] = object_argv[1].replace('llvm-raw', 'emit-obj'); object_argv[3] = str(obj); run(object_argv, str(ordinal)+'-object')
		link = next(c['argv'] for c in old['commands'] if c['name'] == str(ordinal*5+3)+'-'+str(ordinal)+'-link'); extra = []
		for missing in link[2:-2]:
			name = Path(missing).name.removesuffix('-gcc.o'); assert name in companions.C_WITNESSES
			text = companions.C_WITNESSES[name]; source = leaf/(name+'.c'); target = build/(name+'-gcc.o')
			if source.exists(): assert source.read_text() == text
			else: source.write_text(text)
			run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-include', ROOT/'tests/selfhost-nativeabi/target.h', '-c', source, '-o', target], str(ordinal)+'-C-provider'); extra.append(target)
		run(['gcc', obj, *extra, '-o', exe], str(ordinal)+'-link')
		if program['name'] in {'c-export-fp', 'c-mixed-pointer', 'c-export-i32-edges', 'c-borrowed-noescape'}:
			c0_obj = build/(str(ordinal)+'-C0.o'); run([C0, '-'+a.mode, '-c', *mapping.values(), '-o', c0_obj], str(ordinal)+'-C0-object'); run(['gcc', c0_obj, *extra, '-o', c0], str(ordinal)+'-C0-link')
		else: run([C0, '-'+a.mode, *mapping.values(), *[word for path in extra for word in ('--link-object', path)], '-o', c0], str(ordinal)+'-C0-build')
		expected = next(c for c in old['commands'] if c['name'] == str(ordinal*5+4)+'-'+str(ordinal)+'-execute'); outputs = []
		memories = {}
		for label, product in [('Astra', exe), ('C0', c0)]:
			r = run([product], str(ordinal)+'-'+label+'-execute', (expected['exit'],)); outputs.append((r.stdout, r.stderr)); assert sha(leaf/(str(ordinal)+'-'+label+'-execute.stdout')) == expected['stdout_sha256'] and sha(leaf/(str(ordinal)+'-'+label+'-execute.stderr')) == expected['stderr_sha256']
			if not a.historical:
				v = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], str(ordinal)+'-'+label+'-memory', (expected['exit'],)); assert v.stdout == r.stdout and b'ERROR SUMMARY: 0 errors' in v.stderr and b'in use at exit: 0 bytes in 0 blocks' in v.stderr and b'(suppressed: 0 from 0)' in v.stderr; memories[label] = sha(leaf/(str(ordinal)+'-'+label+'-memory.stderr'))
		assert outputs[0] == outputs[1]
		rows.append(dict(name=program['name'], sources=sources, raw_LLVM_sha256=sha(raw), raw_R4_identity=sha(raw) == products['raw']['sha256'], ELF_sha256=sha(exe), ELF_R4_identity=sha(exe) == products['native']['sha256'], C0_ELF_sha256=sha(c0), actual_exit=expected['exit'], returning_memory=memories))
		(leaf/'programs.json').write_text(json.dumps(rows, indent=2)+'\n'); print(a.mode, ordinal, program['name'], 'Astra and C0 executed', flush=True)
	assert len(rows) == 202 and len({tuple(s['sha256'] for s in r['sources']) for r in rows}) == 202
	(leaf/'result.json').write_text(json.dumps(dict(status='FRESH_202_INHERITED_EXECUTIONS', profile=a.mode, component_sha256=sha(a.component), historical_compiler=a.historical, receipt=str(prior), receipt_sha256=sha(prior), programs=rows, raw_R4_identical=sum(r['raw_R4_identity'] for r in rows), ELF_R4_identical=sum(r['ELF_R4_identity'] for r in rows), limitation='Exact source bytes, with explicit read-only relocation for cleaned temporary inputs. C providers are rebuilt from the unchanged tracked native-ABI corpus. These 202 Astra programs and their C0 twins execute freshly; separate effects/memory obligations remain separate.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
