#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Full originals first; actual source executions remain distinct from stage probes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def original_target_graph(path, driver):
	text = path.read_text()
	functions = dict(re.findall(r'^define[^\n]* @(astra\.e25a\.f\.[0-9]+)\([^\n]*\) \{\n(.*?)^\}', text, re.M | re.S))
	candidates = re.findall(r'^define internal fastcc ptr @(astra\.e25a\.f\.[0-9]+)\(ptr (%[a-zA-Z0-9_.]+), i32 (%[a-zA-Z0-9_.]+)\) \{\n(.*?)^\}', text, re.M | re.S)
	# The complete original population has one checked void function with
	# (borrowed builder, int). Its actual raw body contains both discarded
	# bool calls, with the same source receiver/value and a one-byte space.
	assert len(candidates) == 1, [(row[0], row[1:3]) for row in candidates]
	function, receiver, value, body = candidates[0]
	labels = list(re.finditer(r'^([a-zA-Z0-9_.]+):[^\n]*\n', body, re.M))
	blocks = {label[1]: body[label.end():labels[i+1].start() if i+1 < len(labels) else len(body)] for i, label in enumerate(labels)}
	current, visited, calls = 'entry', set(), []
	while True:
		assert current in blocks and current not in visited and len(visited) < 32
		visited.add(current)
		block = blocks[current]
		calls += re.findall(r'call fastcc i1 @(astra\.e25a\.f\.[0-9]+)\(([^\n]*)\)', block)
		if 'ret ptr null' in block:
			break
		edges = re.findall(r'br label %([a-zA-Z0-9_.]+)', block)
		assert len(edges) == 1
		current = edges[0]
	assert len(calls) == 2 and calls[0][0] != calls[1][0]
	assert calls[0][0] in functions and calls[1][0] in functions
	assert calls[0][1].startswith('ptr '+receiver+', ') and calls[0][1].endswith('i32 1')
	assert calls[1][1] == 'ptr '+receiver+', i32 '+value
	assert 'ret ptr null' in body and '@astra_host_text_byte' in functions[calls[0][0]]
	main = re.search(r'^define i32 @main\([^\n]*\) \{\n(.*?)^\}', text, re.M | re.S)
	assert main is not None
	observed = main[1].count('@'+function+'(')
	expected = Path(driver).read_text().count('flow_number(')
	assert expected > 0 and observed == expected
	return dict(function=function, definition_sha256=hashlib.sha256(body.encode()).hexdigest(), discarded_bool_callees=[row[0] for row in calls], actual_raw_caller_invocations=observed, receiver_operand=receiver, integer_operand=value, classification='Raw Astra module definitions and call operands, independently checked against the unchanged original source contract before optimization. Source hashes, full population and actual ELF execution are separate required evidence.')


def original_inputs(paths, run):
	prior = paths.RUNTIME.parent/'effects25-r5'
	full = read(prior/'original-before-O0/result.json')
	minimal = read(prior/'r4-original-view-baseline-O0/result.json')
	for witness in (full, minimal):
		assert all(sha(row['path']) == row['sha256'] for row in witness['inputs'])
	assert len(full['inputs']) == 9 and len(minimal['inputs']) == 8
	source = ROOT/'compiler/semantic/flow-query.astra'
	fragment = source.read_bytes()[1870:2001]
	assert hashlib.sha256(fragment).hexdigest() == '8641d4ff6a1f19cc8bfc0ccbec492a8f7d4248eebcb05373c15479e7114a3e68'
	assert fragment == Path(full['inputs'][0]['path']).read_bytes() == Path(minimal['inputs'][0]['path']).read_bytes()
	views = load_module('native_frontier_AST_views', ROOT/'tests/selfhost-effects/recover-r4-original-view.py')
	for selection in minimal['selections']:
		original, selected = Path(selection['original']), Path(selection['view'])
		assert sha(original) == selection['original_sha256'] and sha(selected) == selection['view_sha256']
		data = original.read_bytes()
		parts = [data[span['start_byte']:span['end_byte']] for span in selection['ranges']]
		assert all(hashlib.sha256(part).hexdigest() == span['sha256'] for part, span in zip(parts, selection['ranges']))
		assert b'\n'.join(parts) == selected.read_bytes()
		old = views.declarations(run([C0, '--dump-syntax', original], selected.stem+'-original-AST').stdout.decode())
		new = views.declarations(run([C0, '--dump-syntax', selected], selected.stem+'-selected-AST').stdout.decode())
		assert all(declaration in old for declaration in new)
		assert hashlib.sha256('\n'.join(new).encode()).hexdigest() == selection['AST_sha256']
	return full, minimal


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--component', type=Path)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--group', choices=('original', 'runtime', 'utf8', 'focused', 'shared', 'owner'), action='append')
	p.add_argument('--case', action='append')
	a = p.parse_args()
	assert a.version.isalnum()
	groups = a.group or ['original', 'runtime', 'utf8', 'focused', 'shared', 'owner']
	identity = None
	if a.component:
		identity = read(a.component.with_suffix('.identity.json'))
		assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	paths = load_module('native_frontier_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('native-frontiers-'+a.version+'-'+a.mode)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	commands = []
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		env = dict(os.environ, CCACHE_DISABLE='1')
		for key in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE'):
			env.pop(key, None)
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=env, capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stdout[-2500:], r.stderr[-2500:])
		return r
	full, minimal = original_inputs(paths, run)
	libraries = load_module('native_frontier_platform', ROOT/'tests/selfhost-typecore/build.py')
	objects = []
	for name in libraries.PROVIDERS:
		source = ROOT/('lib/runtime/platform/'+name+'.c')
		obj = build/(name+'.o')
		run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', source, '-o', obj], name+'-provider')
		objects.append(obj)
	provider = leaf/'provider.c'
	provider.write_text('#include <stdint.h>\nint32_t proof_text_byte(const unsigned char *p, int32_t n, int32_t i) { return i >= 0 && i < n ? p[i] : -1; }\n')
	obj = build/'provider.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', obj], 'counted-text-provider')
	objects.append(obj)
	links = [word for obj in objects for word in ('--link-object', obj)]
	programs = []
	if 'original' in groups:
		# The entire nine-input original population is always attempted first.
		programs += [('full-original-flow-number', [Path(row['path']) for row in full['inputs']], 'FULL_ORIGINAL'), ('minimal-original-flow-number', [Path(row['path']) for row in minimal['inputs']], 'EXACT_REDUCED_VIEW')]
	if 'runtime' in groups:
		corpus = load_module('native_original_runtime', ROOT/'tests/selfhost-effects/recover-original-runtime-sources.py').corpus()
		for name, text in corpus.items():
			source = leaf/(name+'.astra')
			source.write_text(text)
			inputs = [Path(row['path']) for row in full['inputs']]
			inputs[1] = source
			programs.append((name, inputs, 'COMPLETE_ORIGINAL_RUNTIME'))
	if 'utf8' in groups:
		corpus = load_module('native_original_utf8', ROOT/'tests/selfhost-effects/recover-r5-original-oracles.py').corpus()
		for name, (actual_error, text) in corpus.items():
			source = leaf/(name+'.astra')
			source.write_text(text)
			inputs = [Path(row['path']) for row in full['inputs']]
			inputs[1] = source
			programs.append((name, inputs, 'COMPLETE_ORIGINAL_UTF8_ERROR' if actual_error else 'COMPLETE_ORIGINAL_UTF8_SUCCESS'))
	if 'owner' in groups:
		cases = load_module('native_owner_forms', ROOT/'tests/selfhost-effects/recover-owner-form-oracles.py').CASES
		cases['nested-outer-Error-borrow'] = '''string label(int code) { if (code == 20) return "outer"; return "inner"; }
class Detail : Error {
	private int code;
	init(int code) : base(label(code)) { this.code = code; }
	int read() { return this.code; }
}
int fail(int code) throws Detail { throw new Detail(code); }
int main() {
	try {
		try { return fail(20); }
		catch (Detail first) {
			try { return fail(22); }
			catch (Detail last) {
				if (first.message != "outer" || last.message != "inner") return 3;
				return first.read() + last.read();
			}
		}
	} catch (Error caught) { return 4; }
}
'''
		cases.update({
			'derived-error-readonly-field': 'class Detail : Error { private readonly string note; init(string text) : base("detail") { this.note = text; } int read() { if (this.note == "payload") return 42; return 3; } }\nint main() { try { throw new Detail("payload"); } catch (Detail caught) { if (caught.message != "detail") return 4; return caught.read(); } }\n',
			'derived-error-owned-child': 'class Value { private int code; init(int code) { this.code = code; } int read() { return this.code; } }\nclass Detail : Error { private owned Value item; init(owned Value item) : base("detail") { this.item = move item; } int read() { return this.item.read(); } }\nint main() { var value = new Value(42); try { throw new Detail(move value); } catch (Detail caught) { return caught.read(); } }\n',
			'derived-error-owned-buffer': 'class Detail : Error { private owned u8[] data; init(owned u8[] data) : base("detail") { this.data = move data; } int read() { return this.data[0] as int; } }\nint main() { var data = new u8[1]; data[0] = 42; try { throw new Detail(move data); } catch (Detail caught) { return caught.read(); } }\n',
		})
		for name in ('derived-error-field', 'derived-error-computed-base', 'derived-error-snapshot', 'field-receiver', 'owned-result-explicit-transfer', 'nested-outer-Error-borrow', 'derived-error-readonly-field', 'derived-error-owned-child', 'derived-error-owned-buffer'):
			source = leaf/(name+'.astra')
			source.write_text(cases[name])
			programs.append((name, [source, ROOT/'lib/astra/base/errors.astra'], 'C0_VALID_OWNER_FORM'))
	if 'focused' in groups:
		corpus = load_module('native_focused_runtime', ROOT/'tests/selfhost-effects/recover-frontier-source-proof.py').corpus(leaf)
		for name, (text, dependencies) in corpus.items():
			source = leaf/(name+'.astra')
			source.write_text(text)
			programs.append((name, [source, ROOT/'lib/astra/base/errors.astra', *[ROOT/('lib/astra/'+dependency+'.astra') for dependency in dependencies]], 'FOCUSED_SOURCE'))
	if 'shared' in groups:
		corpus = load_module('native_shared_runtime', ROOT/'tests/selfhost-effects/recover-shared-sources.py').corpus()
		for name, text in corpus.items():
			source = leaf/(name+'.astra')
			source.write_text(text)
			programs.append((name, [source, ROOT/'lib/astra/base/errors.astra'], 'SHARED_SOURCE'))
	rows = []
	def memory(exe, name):
		observed = run([exe], name+'-execute', (42,))
		checked = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-memory', (42,))
		assert all(marker in checked.stderr for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		assert checked.stdout == observed.stdout
		return observed
	for name, inputs, domain in programs:
		if a.case and name not in a.case:
			continue
		row = dict(name=name, domain=domain, inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], C0=None, Astra=None)
		oracle = build/(name+'-C0')
		compiled = run([C0, '-'+a.mode, *inputs, *links, '-o', oracle], name+'-C0-build', (0, 1))
		if compiled.returncode == 0:
			c0 = memory(oracle, name+'-C0')
			row['C0'] = dict(ELF_sha256=sha(oracle), exit=42, returning_clean_memory=True)
		else:
			row['C0_rejected_source'] = True
		if a.component and compiled.returncode == 0:
			physical = build/(name+'.ll')
			physical.write_text('Original source native output sentinel\n')
			sentinel = sha(physical)
			emitted = run([a.component, '--native', physical, *inputs], name+'-Astra-emit', (*range(9), 132, -4))
			row['Astra'] = dict(emitted=emitted.returncode == 0, emit_exit=emitted.returncode, actual_execution=None)
			if emitted.returncode == 0:
				run(['opt', '-passes=verify', '-disable-output', physical], name+'-Astra-verify')
				if domain in ('FULL_ORIGINAL', 'EXACT_REDUCED_VIEW') or name == 'flow-boundaries':
					row['original_target_graph'] = original_target_graph(physical, inputs[1])
				optimized = build/(name+'-optimized.ll')
				run(['opt', '-passes=default<'+a.mode+'>', '-S', physical, '-o', optimized], name+'-Astra-optimize')
				run(['opt', '-passes=verify', '-disable-output', optimized], name+'-Astra-optimized-verify')
				obj = build/(name+'.o')
				exe = build/(name+'-Astra')
				run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], name+'-Astra-object')
				run(['cc', '-no-pie', obj, *objects, '-o', exe], name+'-Astra-link')
				actual = memory(exe, name+'-Astra')
				assert actual.stdout == c0.stdout and actual.stderr == c0.stderr
				row['Astra'].update(raw_LLVM_sha256=sha(physical), optimized_LLVM_sha256=sha(optimized), ELF_sha256=sha(exe), actual_execution=42, returning_clean_memory=True)
			else:
				row['Astra']['destination_preserved'] = sha(physical) == sentinel
				assert row['Astra']['destination_preserved']
		rows.append(row)
		(leaf/'result.json').write_text(json.dumps(dict(status='NATIVE_FRONTIER_OBSERVATIONS' if a.component else 'INDEPENDENT_C0_ORIGINAL_ORACLES', profile=a.mode, component_sha256=sha(a.component) if a.component else None, compiler_profile=identity['identity']['argv'][1][1:] if identity else None, selected_groups=groups, case_filter=a.case, programs=rows, original_target=dict(path=str(ROOT/'compiler/semantic/flow-query.astra'), first=1870, last=2001, sha256='8641d4ff6a1f19cc8bfc0ccbec492a8f7d4248eebcb05373c15479e7114a3e68'), minimal_selections=minimal['selections'], limitation='Full original population precedes the separately authenticated reduced view. Compiler source witnesses and independent stage/LLVM consumers bind real source operations. Source emission alone is not execution; only actual matched-profile native executions and returning memory count. These observations do not establish all milestone gates or an overall PASS.'), indent=2)+'\n')
		print(a.mode, name, 'C0 rejected' if row.get('C0_rejected_source') else ('C0/native executed 42' if row['Astra'] and row['Astra']['actual_execution'] == 42 else ('Astra emission stopped '+str(row['Astra']['emit_exit']) if row['Astra'] else 'C0 oracle executed 42')), flush=True)
	assert all(row['C0'] is not None for row in rows), 'Some new oracle fixtures were rejected by C0; their original failed receipts are retained.'
	if a.component:
		assert all(row['Astra'] and row['Astra']['actual_execution'] == 42 for row in rows), 'Actual Astra frontiers remain; inspect each stopped receipt.'


if __name__ == '__main__':
	main()
