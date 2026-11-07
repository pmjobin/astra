#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent field roots/layouts, owner publication and physical alternatives."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

SEMANTIC = ['missing receiver', 'zero owner slot', 'out-of-range owner slot', 'non-field nominal member', 'field ordinal', 'field byte offset', 'reverse cleanup rank', 'writable authority', 'constructor authority', 'equal-size different nominal Class', 'layout offset', 'payload extent', 'field qualifier identity', 'store receiver binding', 'load source type', 'Core receiver Place', 'Core ownership role', 'CFG missing value', 'CFG wrong source operation', 'CFG skipped initialization/cleanup', 'SSA field type', 'SSA field definition']
PHYSICAL = ['undersized Class allocation', 'different same-type field GEP', 'wrong field value', 'null substituted receiver', 'containing object freed as child payload', 'containing object retirement omitted', 'buffer exchange publishes its old left descriptor', 'buffer exchange overwrites only its left destination', 'zero-buffer branch selects count one', 'nonempty buffer allocation loses its actual count']


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--public-controls', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_adversarial_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-adversarial-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	corpus = load_module('r4_adversarial_fixture', ROOT/'tests/selfhost-effects/recover-r4-qualify.py'); vault = corpus.VAULT.replace('\tvoid replace(', '\tvoid exchange(owned int[] replacement) { swap(this.data, replacement); }\n\tvoid replace(')
	vault = vault.replace('\tprivate bool enabled;', '\tprivate bool enabled;\n\tprivate int alternate;').replace('this.enabled = false;', 'this.enabled = false; this.alternate = 0;')
	text = 'class Twin { owned int[] data; int count; bool enabled; int alternate; init(owned int[] data, int count) { this.data = move data; this.count = count; this.enabled = false; this.alternate = 0; } }\n'+vault+'int main() { var data = new int[1]; var value = new Vault(move data, 37); var replacement = new int[3]; value.exchange(move replacement); try { value.touch(false); value.touch(true); return 3; } catch (Error caught) { if (caught.message != "kept") return 4; return value.value(); } }\n'
	if a.public_controls: text = text.replace('private ', '')
	source = leaf/'fixture.astra'; source.write_text(text); inputs = [source, ROOT/'lib/astra/base/errors.astra']
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stdout[-2500:], r.stderr[-2500:]); return r
	c0 = build/'C0'; run([C0, '-'+a.mode, *inputs, '-o', c0], 'C0-build'); run([c0], 'C0-execute', (42,))
	ir = build/'positive.ll'; run([a.component, '--native', ir, *inputs], 'positive-emit'); run(['opt', '-passes=verify', '-disable-output', ir], 'positive-verify'); optimized = build/'optimized.ll'; run(['opt', '-passes=default<'+a.mode+'>', '-S', ir, '-o', optimized], 'positive-optimize'); obj = build/'positive.o'; exe = build/'positive'; run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], 'positive-object'); run(['cc', '-no-pie', obj, '-o', exe], 'positive-link'); run([exe], 'positive-execute', (42,))
	for label, program in [('Astra', exe), ('C0', c0)]:
		r = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', program], label+'-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in r.stderr and b'in use at exit: 0 bytes in 0 blocks' in r.stderr and b'(suppressed: 0 from 0)' in r.stderr
	r = run([a.component, '--r4-field-adversarial', build, *inputs], 'stage-negatives')
	semantic = [(int(c), int(s)) for c, s in re.findall(rb'R4_FIELD_REJECT ([0-9]+) ([0-9]+)', r.stdout)]; physical = [int(c) for c in re.findall(rb'R4_FIELD_LLVM_REJECT ([0-9]+)', r.stdout)]
	assert semantic == [(i, 2 if i < 15 else 3 if i < 17 else 4 if i < 20 else 5) for i in range(22)] and physical == list(range(10))
	variants = []
	for category in physical:
		variant = build/('field-physical-'+str(category)+'.ll'); assert sha(variant) != sha(ir); run(['llvm-as', variant, '-o', build/(str(category)+'.bc')], str(category)+'-assemble'); run(['opt', '-passes=verify', '-disable-output', variant], str(category)+'-verify'); target = build/(str(category)+'-optimized.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', variant, '-o', target], str(category)+'-optimize'); run(['opt', '-passes=verify', '-disable-output', target], str(category)+'-optimized-verify'); variants.append(dict(category=category, meaning=PHYSICAL[category], LLVM_sha256=sha(variant), optimized_sha256=sha(target)))
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_FIELD_CONTROLS', profile=a.mode, component_sha256=sha(a.component), source_sha256=sha(source), public_diagnostic_fixture=a.public_controls, semantic=[dict(category=c, stage=s, meaning=SEMANTIC[c]) for c, s in semantic], LLVM_valid_physical=variants, primary_corpus_credit=0, limitation='Public diagnostic fixtures are unrelated authored controls, never altered original declarations. Original builder/function execution and remaining field/effect forms require separate evidence.'), indent=2)+'\n'); print(a.mode, '22 field-stage mutations and 10 LLVM-valid physical alternatives rejected', flush=True)


if __name__ == '__main__':
	main()
