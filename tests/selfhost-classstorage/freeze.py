#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze legal oracle programs and preserve all failed baseline observations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import sys
sys.dont_write_bytecode = True
from corpus import CASES, FLOW_TYPES, UNCHANGED_HEAP_CASES
from environment import audit

ROOT = Path(__file__).resolve().parents[2]
C0_SHA = '908f8db9e524cf94b7651f36e9bf0ff32c98ef64cb7eacd737c3b5f680064b45'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def extract(path, marker, stop=None):
	text = path.read_text(); start = text.index(marker)
	if stop:
		end = text.index(stop, start)
		value = text[start:end] + '}\n'
	else:
		opening = text.index('{', start); depth = 1; end = opening + 1
		while depth:
			if text[end] == '{': depth += 1
			if text[end] == '}': depth -= 1
			end += 1
		value = text[start:end] + '\n'
	return value, dict(path=str(path), sha256=sha(path), start=start, end=end, extracted_sha256=hashlib.sha256(value.encode()).hexdigest(), operation='retain prefix and close Class' if stop else 'exact declaration slice')


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'runtime', 'build', 'before-O0', 'before-O2'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--compiler-sha256', default=C0_SHA, help='Explicit qualified oracle identity for a newly rebuilt toolchain')
	a = p.parse_args()
	assert sha(a.compiler) == a.compiler_sha256
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.runtime, a.build))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	commands, rows = [], []
	def run(argv, name):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=a.build, capture_output=True, timeout=180, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		return r
	inputs = []
	for name, texts in CASES.items():
		sources = []
		for i, text in enumerate(texts):
			if text == '@bag': sources.append(ROOT/'lib/astra/collections/bag.astra'); continue
			path = a.runtime/(name+'-'+str(i)+'.astra'); path.write_text(text+'\n'); sources.append(path)
		inputs.append((name, sources, 0))
	pieces, provenance = [], []
	for file, markers in [('compiler/semantic/model.astra', ['struct SymbolId {']), ('compiler/semantic/types.astra', ['struct TypeId {']), ('compiler/syntax/model.astra', ['struct SyntaxNodeId {', 'struct SyntaxSourceId {', 'struct SyntaxSpan {']), ('compiler/syntax/arena-support.astra', ['SyntaxSpan syntax_empty_span() {']), ('compiler/semantic/flow-model.astra', ['struct '+name+' {' for name in FLOW_TYPES])]:
		for marker in markers:
			text, identity = extract(ROOT/file, marker); pieces.append(text); provenance.append(identity)
	text, identity = extract(ROOT/'compiler/semantic/flow-model.astra', 'class FlowGraph {', '\n\tvoid fail(')
	pieces.append(text); provenance.append(identity)
	pieces.append('int main() { SymbolId function = { index = 7 }; var graph = new FlowGraph(function, 1, 1, 1, 8192); var bag = new Bag<FlowGraph>(); if (!bag.reserve(1)) return 2; bag.append(move graph); var result = bag.take(0); if (result.function.index != 7 || result.ordinal != 1 || len(result.events) != 16 || len(result.facts) != 0 || result.limit != 8192 || bag.count() != 0) return 1; return 0; }\n')
	path = a.runtime/'flowgraph-bag.astra'; path.write_text('\n'.join(pieces))
	(a.runtime/'flowgraph-slices.json').write_text(json.dumps(provenance, indent=2)+'\n')
	inputs.append(('flowgraph-bag', [path, ROOT/'lib/astra/collections/bag.astra'], 0))
	inputs.append(('unchanged-owner-relay', [ROOT/'tests/gen-own/fixtures/gen-own-class-nodeinit.astra'], 42))
	# The .init witness above is retained as caller-backed storage evidence; it
	# is not a native heap-profile success premise. These unchanged witnesses
	# exercise actual heap construction and the original collection constraint.
	for name, files, expected in UNCHANGED_HEAP_CASES:
		inputs.append((name, [ROOT/path for path in files], expected))
	proposed = [dict(name=name, sources=[dict(path=str(x), sha256=sha(x), bytes=x.stat().st_size) for x in sources], expected_exit=expected, disposition='PROPOSED_NOT_C0_QUALIFIED') for name, sources, expected in inputs]
	(a.runtime/'proposed.json').write_text(json.dumps(proposed, indent=2)+'\n')
	preflight = audit(a.compiler, [a.before_O0, a.before_O2], a.compiler_sha256)
	(a.runtime/'environment.json').write_text(json.dumps(preflight, indent=2)+'\n')
	if preflight['status'] != 'READY':
		print('ENVIRONMENT_BLOCKED: proposals retained; no C0 or native admission claimed')
		return 2
	for name, sources, expected in inputs:
		parse = run([a.compiler, '--parse', *sources], name+'-parse')
		check = run([a.compiler, '--check', *sources], name+'-check')
		assert parse.returncode in (0, 1) and check.returncode in (0, 1), 'tool failure is not a source disposition'
		row = dict(name=name, sources=[dict(path=str(x), sha256=sha(x), bytes=x.stat().st_size) for x in sources], parse_exit=parse.returncode, check_exit=check.returncode, c0_sha256=a.compiler_sha256, expected_exit=expected, profiles={})
		for mode in ('O0', 'O2'):
			observed = {}; component = getattr(a, 'before_'+mode)
			identity = json.loads(component.with_suffix('.identity.json').read_text())
			assert sha(component) == identity['sha256']
			assert all(sha(x) == h for x, h in identity['identity']['sources'].items())
			if check.returncode == 0:
				product = a.build/(name+'-'+mode)
				built = run([a.compiler, '-'+mode, *sources, '-o', product], name+'-'+mode+'-C0-build')
				observed['build_exit'] = built.returncode
				if built.returncode == 0:
					executed = run([product], name+'-'+mode+'-C0-execute')
					observed.update(execution_exit=executed.returncode, product_sha256=sha(product), matches_expected=executed.returncode == expected and executed.stdout == executed.stderr == b'')
			baseline = run([component, '--nativeabi-admit', mode, a.build/'unused', *sources], name+'-'+mode+'-native-before')
			observed.update(component_sha256=sha(component), admission_exit=baseline.returncode)
			row['profiles'][mode] = observed
		rows.append(row)
		(a.runtime/'selection.json').write_text(json.dumps(rows, indent=2)+'\n')
		print(name, check.returncode, row['profiles'], flush=True)
	assert len({tuple(x['sha256'] for x in row['sources']) for row in rows}) == len(rows)
	print('Frozen', len(rows), 'distinct premises;', sum(all(v.get('matches_expected') for v in row['profiles'].values()) for row in rows), 'C0 runtime matches at both profiles')


if __name__ == '__main__':
	raise SystemExit(main())
