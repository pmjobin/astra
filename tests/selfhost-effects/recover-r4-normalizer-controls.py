#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Ensure disclosed IR text diagnostics never erase constants or used attributes."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, load_module, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--original', type=Path, required=True); p.add_argument('--alternative', type=Path, required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_normalizer_paths', ROOT/'tests/selfhost-effects/recover-build.py'); recipe = load_module('r4_normalizer_subject', ROOT/'tests/selfhost-effects/recover-r4-retained.py'); leaf = paths.RUNTIME/('normalizer-controls-'+a.version); leaf.mkdir(); commands = []
	original = a.original.read_bytes(); alternative = a.alternative.read_bytes(); assert original != alternative
	# Align fixture framing introduced by the independent alternative writer;
	# the retained-program diagnostic itself never folds whitespace.
	original = re.sub(rb'\n\n(?=attributes #[0-9]+ =)', b'\n', original)
	alternative = re.sub(rb'\n\n(?=attributes #[0-9]+ =)', b'\n', alternative)
	header = b'define internal fastcc ptr @astra.e25a.allocate'; assert alternative.count(header) == 1
	alternative = alternative.replace(header, b'; Function Attrs: noinline\n'+header)
	renumbered = re.sub(rb'#([0-9]+)', lambda match:b'#'+str(int(match[1])+100).encode(), alternative)
	changed_value, count = re.subn(rb'ret i32 42\b', b'ret i32 43', alternative); assert count == 1
	changed_attribute, count = re.subn(rb'\{ nobuiltin \}', b'{ nobuiltin nounwind }', alternative); assert count == 1
	literal = b'\n@r4.normalizer.literal = private constant [3 x i8] c"#1\\00"\n'
	baseline = original+literal
	controls = [('allocator-boundary', alternative+literal, True), ('attribute-numbering', renumbered+literal, True), ('scalar-constant', changed_value+literal, False), ('used-attribute', changed_attribute+literal, False), ('quoted-numbered-bytes', alternative+literal.replace(b'#1', b'#2'), False)]
	rows = []; baseline_path = leaf/'baseline.ll'; baseline_path.write_bytes(baseline)
	for name, raw, expected in [('baseline', baseline, True), *controls]:
		path = baseline_path if name == 'baseline' else leaf/(name+'.ll'); path.write_bytes(raw); argv = ['opt', '-passes=verify', '-disable-output', str(path)]; start = time.monotonic(); env = dict(os.environ); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=ROOT, env=env, capture_output=True, timeout=120); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == 0, r.stderr
		if name == 'baseline': continue
		actual = recipe.resolved_nonallocator_text(raw) == recipe.resolved_nonallocator_text(baseline); assert actual == expected, name
		rows.append(dict(name=name, LLVM_sha256=sha(path), raw_byte_identity=raw == baseline, diagnostic_text_identity=actual, expected=expected)); print(name, 'LLVM-valid; disclosed diagnostic identity', actual, flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_TEXT_DIAGNOSTIC_CONTROLS', original=str(a.original), original_sha256=sha(a.original), alternative=str(a.alternative), alternative_sha256=sha(a.alternative), baseline_sha256=sha(baseline_path), recipe_sha256=sha(ROOT/'tests/selfhost-effects/recover-r4-retained.py'), fixture_framing='Only the test fixtures align blank lines before attribute-group definitions; the alternative also carries the actual noinline helper comment. Retained replay compares original unmodified raw modules.', programs=rows, Astra_native_credit=0, limitation='Independent byte/LLVM-valid controls for an attributed text diagnostic only. Constants and used attribute bodies must remain visible. This is neither raw identity nor a behavioral equivalence proof, stage mutation credit or native program execution.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
