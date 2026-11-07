#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent stage and valid-LLVM alternatives for original constructors."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

SEMANTIC = ['base literal conditional type', 'constructed nominal conditional type', 'base literal source identity', 'base literal token identity', 'constructor dynamic nominal', 'constructor result nominal', 'constructor operand cycle', 'missing base message operand', 'base literal handler identity', 'orphaned base literal catch', 'Error construction result role', 'constructed Error owner identity', 'Core constructor nominal correspondence', 'invented constructor field Place', 'CFG constructed owner identity', 'spurious constructor failure edge', 'base literal function routing', 'SSA constructed Error channel', 'SSA counted message type', 'SSA constructor edge identity']
PHYSICAL = ['root descriptor in derived constructor', 'null counted message data', 'truncated literal count', 'absent dynamic descriptor', 'descriptor bytes used as message', 'overlong literal count']


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r3_adversarial_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r3-adversarial-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	declaration = (ROOT/'compiler/source/source.astra').read_bytes()[134:220]
	source = leaf/'fixture.astra'; source.write_bytes(declaration+b'\nint leaf() throws Error { try { throw new SourceBoundsError(); } catch (SourceBoundsError caught) { throw; } }\nint main() { try { return leaf(); } catch (Error caught) { if (caught.message == "invalid source span or offset") return 42; return 4; } }\n')
	inputs = [source, ROOT/'lib/astra/base/errors.astra']; commands = []
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stdout[-2500:], r.stderr[-2500:]); return r
	c0 = build/'C0'; run([C0, '-'+a.mode, *inputs, '-o', c0], 'C0-build'); run([c0], 'C0-execute', (42,))
	ir = build/'positive.ll'; run([a.component, '--native', ir, *inputs], 'positive-emit'); run(['opt', '-passes=verify', '-disable-output', ir], 'positive-verify'); optimized = build/'positive-optimized.ll'; run(['opt', '-passes=default<'+a.mode+'>', '-S', ir, '-o', optimized], 'positive-optimize'); obj = build/'positive.o'; exe = build/'positive'; run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], 'positive-object'); run(['cc', '-no-pie', obj, '-o', exe], 'positive-link'); run([exe], 'positive-execute', (42,))
	for label, program in [('Astra', exe), ('C0', c0)]:
		r = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', program], label+'-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in r.stderr and b'in use at exit: 0 bytes in 0 blocks' in r.stderr and b'(suppressed: 0 from 0)' in r.stderr
	r = run([a.component, '--r3-adversarial', build, *inputs], 'stage-negatives')
	semantic = [(int(c), int(s)) for c, s in re.findall(rb'R3_SEMANTIC_REJECT ([0-9]+) ([0-9]+)', r.stdout)]; physical = [int(c) for c in re.findall(rb'R3_LLVM_VALID_REJECT ([0-9]+)', r.stdout)]
	assert semantic == [(i, 1 if i < 2 else 2 if i < 10 else 3 if i < 14 else 4 if i < 17 else 5) for i in range(20)] and physical == list(range(6))
	variants = []
	for category in physical:
		variant = build/('r3-physical-'+str(category)+'.ll'); assert sha(variant) != sha(ir)
		run(['llvm-as', variant, '-o', build/(str(category)+'.bc')], str(category)+'-assemble'); run(['opt', '-passes=verify', '-disable-output', variant], str(category)+'-verify'); target = build/(str(category)+'-optimized.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', variant, '-o', target], str(category)+'-optimize'); run(['opt', '-passes=verify', '-disable-output', target], str(category)+'-optimized-verify'); variants.append(dict(category=category, meaning=PHYSICAL[category], LLVM_sha256=sha(variant), optimized_sha256=sha(target)))
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_CONSTRUCTOR_CONTROLS', profile=a.mode, component_sha256=sha(a.component), source_sha256=sha(source), semantic=[dict(category=c, stage=s, meaning=SEMANTIC[c]) for c, s in semantic], LLVM_valid_physical=variants, primary_corpus_credit=0, limitation='These source-bound constructor controls do not qualify still-deferred receiver/field/float forms.'), indent=2)+'\n'); print(a.mode, '20 constructor stage mutations and 6 LLVM-valid physical alternatives rejected', flush=True)


if __name__ == '__main__':
	main()
