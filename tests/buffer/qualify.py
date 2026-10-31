# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce BUFFER-1 frozen goldens, determinism, order, linkage and memory evidence."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import ROOT, FIXTURES, CASES, STAGES, run

BASELINE = '3dcfbd9c483fb0ebdebe9ce96bcdec0aa5f47654'
EXTENSIONS = {'.syntax', '.semantics', '.core', '.instances', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}
LEGACY = {'semantic', 'core', 'cfg'}


def git(*args):
	return subprocess.check_output(['git', *args], cwd=ROOT)


def write(path, value):
	path.write_text(json.dumps(value, indent='\t')+'\n')


def ordered(text, *patterns):
	position = 0
	for pattern in patterns:
		match = re.search(pattern, text[position:]); assert match, (pattern, text[position:position+150])
		position += match.end()


def ordering(execution):
	def read(name, stage):
		return (execution/(name+'.'+stage)).read_text()
	for stage in ['core', 'cfg', 'ssa']:
		text = read('field-mixed', stage).split('\t(destructor ')[1]
		ordered(text, 'buffer_d', 'resource_c', 'buffer_b', 'resource_a')
	ordered(read('replace', 'ssa'), r'owned-buffer-allocate', r'buffer-initialize', r'owned-buffer-allocate', r'buffer-read', r'buffer-deallocate', r'buffer-store')
	ordered(read('replace', 'ssa').split('buffer-storage #1 owner #1) (PTR %14')[1], r'buffer-disarm', r'buffer-read', r'buffer-deallocate', r'buffer-store')
	ordered(read('field', 'cfg').split('(method #0')[1], r'\(call #0 \"make\"', r'resource-capture', r'cleanup via', r'\(store')
	ordered(read('null-receiver', 'cfg'), r'object-validate', r'resource-capture.*consume-owner', r'cleanup via', r'\(store')
	ordered(read('param', 'ssa'), r'owned-buffer-parameter', r'buffer-initialize', r'owned-buffer-allocate', r'buffer-read', r'buffer-deallocate', r'buffer-store')
	ordered(read('mixed-call', 'ssa').split('"main" -> int')[1], r'"mark".*', r'buffer-borrow', r'"mark".*', r'buffer-disarm', r'buffer-disarm', r'call #0 "mixed"')
	ordered(read('negative-count', 'llvm'), r'icmp slt i32', r'@calloc', r'icmp eq ptr', r'@llvm.trap')
	for name in ['basic', 'bounds-lower', 'bounds-upper']:
		ir = read(name, 'llvm')
		ordered(ir, r'slice.*trap', r'getelementptr double', r'(?:load|store) double')
	return ['mixed Resource/buffer reverse cleanup in Core/CFG/SSA', 'incoming allocation before old deallocation and store', 'whole named-source disarm before destination cleanup', 'receiver before producer/capture/old cleanup', 'parameter replacement matches locals', 'mixed call evaluation and complete commit', 'negative/OOM/bounds before memory access']


def symbols(build, out):
	directory = out/'symbols'; directory.mkdir(exist_ok=True)
	sources = {
		'buffer-free': 'int main(){return 0;}\n',
		'borrowed-only': 'int read(int[] a){return a[0];} int main(){int[1] a={0};return read(slice(a));}\n',
		'buffer-using': 'int main(){owned int[] a=new int[3];a[2]=7;return a[2]-7;}\n',
	}
	records = []
	for name, source in sources.items():
		path = directory/(name+'.astra'); path.write_text(source)
		ir = run([build/'astrac', '--dump-llvm', path]); ll = directory/(name+'.ll'); ll.write_text(ir)
		obj = directory/(name+'.o'); run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', ll, '-o', obj])
		text = run(['nm', '-u', obj]); (directory/(name+'.symbols')).write_text(text)
		allocators = sorted(set(re.findall(r'\b(?:calloc|free|malloc|realloc)\b', text)))
		assert allocators == (['calloc', 'free'] if name == 'buffer-using' else []), (name, text)
		records.append(dict(name=name, allocator_symbols=allocators, object_sha256=hashlib.sha256(obj.read_bytes()).hexdigest()))
	return records


def machine_evidence(execution, out):
	selected = {
		'basic': ['astra.fn.0'],
		'move': ['astra.fn.0'],
		'borrow': ['astra.fn.0', 'astra.fn.1'],
		'param': ['astra.fn.0', 'astra.fn.1'],
		'result': ['astra.fn.0', 'astra.fn.1', 'astra.fn.2'],
		'field': ['astra.class.method.0.0', 'astra.dtor.0'],
		'field-mixed': ['astra.dtor.0'],
		'object-result': ['astra.fn.0', 'astra.fn.1', 'astra.fn.2', 'astra.ctor.0', 'astra.dtor.0'],
	}
	parts = ['ASTRA-BUFFER-1 retained x86-64 Linux machine evidence\n', 'LLVM 22.1.8; O0 and callable O2 with +fma.\n', 'Reproduce with tests/buffer/execute.py and tests/buffer/qualify.py.\n', 'All 138 emitted objects reject memcpy/memmove/malloc/realloc symbols.\n', 'Borrow initialization loops are user element mutation, not owner transfer.\n']
	for name, functions in selected.items():
		ir = (execution/(name+'.llvm')).read_text()
		parts.append('\nFIXTURE buffer-'+name+'.astra\n')
		for symbol in functions:
			match = re.search(r'^define [^\n]*@'+re.escape(symbol)+r'\(.*?^}', ir, re.M | re.S); assert match, (name, symbol)
			parts.append('\nLLVM '+symbol+'\n'+match[0]+'\n')
		for mode in ['O0', 'callable-O2-fma']:
			assembly = (execution/(name+'-'+mode+'.machine')).read_text()
			for symbol in functions:
				match = re.search(r'^[0-9a-f]+ <'+re.escape(symbol)+r'>:\n.*?(?=\n[0-9a-f]+ <|\Z)', assembly, re.M | re.S); assert match, (name, mode, symbol)
				parts.append('\nMACHINE '+mode+' '+symbol+'\n'+match[0].rstrip()+'\n')
				# Preserve disassembly bytes/instructions while removing objdump's trailing
				# display padding from continuation lines in the review artifact.
	data = '\n'.join(line.rstrip() for line in ''.join(parts).splitlines())+'\n'; (out/'machine-evidence.txt').write_text(data)
	return dict(fixtures=list(selected), modes=['O0', 'callable-O2-fma'], functions=sum(map(len, selected.values())), sha256=hashlib.sha256(data.encode()).hexdigest())


def audit(build, out, independent):
	log = build/'meson-logs/buffer-final.json'
	tests = [json.loads(line) for line in log.read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text())) and all(row['result'] == 'OK' for row in tests)
	goldens = []
	for name in git('ls-tree', '-r', '--name-only', BASELINE, 'tests').decode().splitlines():
		if Path(name).suffix not in EXTENSIONS:
			continue
		content = (ROOT/name).read_bytes(); assert content == git('show', BASELINE+':'+name), name
		goldens.append(dict(path=name, sha256=hashlib.sha256(content).hexdigest()))
	assert len(goldens) == 1004
	for path in (ROOT/'bootstrap').rglob('*.vala'):
		code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
		if path.parts[-2] in ['syntax', 'semantic', 'core', 'cfg', 'ssa', 'nabi', 'cabi']:
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
		if path.parts[-2] in ['semantic', 'core']:
			# Existing diagnostics say "free calls" for non-method calls. Reject
			# allocator invocations/symbol literals, not that unrelated prose.
			assert not re.search(r'\bcalloc\b|\bfree\s*\(|"free"', code), path
		if path.parts[-2] in ['cfg', 'ssa', 'nabi'] and 'buffer' in path.name:
			assert not re.search(r'\bParser\b|Syntax\b|\bChecked\w*|\.name\s*==|\.identifier\s*==', code), path
	commands = json.loads((build/'compile_commands.json').read_text()); generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	execution = build/'tests/buffer/execution'; native = json.loads((execution/'results.json').read_text()); deterministic = []
	assert independent is not None and (independent/'astrac').exists()
	for name in CASES:
		for stage in STAGES:
			data = run([independent/'astrac', '--dump-'+stage, FIXTURES/('buffer-'+name+'.astra'), *([] if stage == 'syntax' else ['--vapi', FIXTURES/'runtime.vapi'])]).encode()
			assert data == (execution/(name+'.'+stage)).read_bytes(), (name, stage)
			deterministic.append(dict(fixture=name, stage=stage, sha256=hashlib.sha256(data).hexdigest()))
	plans = [int(match[1]) for row in tests if (match := re.search(r'^1\.\.(\d+)$', row.get('stdout', ''), re.M))]
	summary = dict(baseline=BASELINE, meson_tests=len(tests), tap_suites=len(plans), tap_cases=sum(plans), strict_generated_c_commands=len(generated), unchanged_baseline_goldens=len(goldens), changed_baseline_goldens=[], frozen_nabi_goldens=sum(Path(row['path']).suffix == '.nabi' for row in goldens), golden_manifest_sha256=hashlib.sha256(json.dumps(goldens, sort_keys=True).encode()).hexdigest(), native_runs=len(native['runs']), negative_checks=len(json.loads((build/'tests/buffer/negative/results.json').read_text())), independent_build_comparisons=len(deterministic), fresh_process_comparisons=len(native['deterministic']), machine_audits=len(native['machine']), ordering_checks=ordering(execution), allocator_symbols=symbols(build, out), firewall_linkage_tests=sum(any(x in row['name'] for x in ['no-llvm', 'links-qualified-llvm', 'linkage-rejects', 'firewall-rejects']) for row in tests), dependencies_added=0)
	summary['retained_machine_evidence'] = machine_evidence(execution, out)
	write(out/'summary.json', summary); write(out/'unchanged-goldens.json', goldens); write(out/'independent-determinism.json', deterministic)
	print(json.dumps(summary), flush=True)


def losses(text):
	text = re.sub(r'^==\d+== ?', '', text, flags=re.M)
	records = re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)', text, flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+', 'ADDRESS', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', record)) for record in records]


def memory(build, out, baseline):
	logs = out/'valgrind'; logs.mkdir(exist_ok=True); jobs = []
	stages = {'buffer-'+name for name in ['parser', 'semantic', 'core-standalone', 'cfg-standalone', 'ssa-standalone', 'nabi', 'pipeline', 'llvm']}
	for root, prefix, names in [(build, '', stages | LEGACY), (baseline, 'baseline-', LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names:
				jobs.append((prefix+test['name'], test['cmd'], test['workdir'] or str(root), dict(os.environ, **test['env']), 0))
	for name in ['basic', 'zero', 'replace', 'borrow', 'param', 'result', 'field', 'field-mixed', 'deinit', 'object-result', 'generic-owner', 'cad', 'resource-replace', 'release', 'param-move']:
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi']:
			jobs.append(('dump-'+name+'-'+stage, [str(build/'astrac'), '--dump-'+stage, str(FIXTURES/('buffer-'+name+'.astra')), '--vapi', str(FIXTURES/'runtime.vapi')], str(ROOT), os.environ, 0))
		for mode in ['O0', 'callable-O2-fma']:
			jobs.append(('run-'+name+'-'+mode, [str(build/'tests/buffer/execution'/(name+'-'+mode))], str(ROOT), os.environ, 0))
	for name in ['forward', 'object-result', 'generic-owner']:
		for mode in ['O0', 'callable-O2-fma']:
			jobs.append(('identity-'+name+'-'+mode, [str(build/'tests/buffer/execution'/(name+'-identity-'+mode))], str(ROOT), os.environ, 0))

	def measure(job):
		name, argv, cwd, env, expected = job
		command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(logs/(name+'.log')), *argv]
		r = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True); (logs/(name+'.stdout')).write_text(r.stdout); (logs/(name+'.stderr')).write_text(r.stderr)
		text = (logs/(name+'.log')).read_text(); assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text); return int(match[1].replace(',', '')) if match else 0
		return dict(name=name, exit=r.returncode, expected_exit=expected, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) from'), lost_records=losses(text))

	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure, jobs))
	write(logs/'results.json', rows); by_name = {row['name']: row for row in rows}
	for row in rows:
		if row['name'].removeprefix('baseline-') in LEGACY:
			assert row['exit'] == 99 and row['errors'] == 1 and row['definite'] == 16384 and row['indirect'] == row['possible'] == row['suppressed'] == 0, row
			assert len(row['lost_records']) == 1 and 'g_malloc' in row['lost_records'][0] and 'call_init' in row['lost_records'][0], row
			if not row['name'].startswith('baseline-'):
				assert row['lost_records'] == by_name['baseline-'+row['name']]['lost_records'], row
		else:
			assert row['exit'] == row['expected_exit'] and row['errors'] == row['definite'] == row['indirect'] == row['possible'] == row['suppressed'] == 0, row
	summary = dict(current_runs=len(rows)-len(LEGACY), baseline_runs=len(LEGACY), matching_legacy_startup_losses=len(LEGACY), new_astra_errors=0, new_astra_lost_bytes=0)
	write(logs/'summary.json', summary); print(json.dumps(summary), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser(); parser.add_argument('build', type=Path); parser.add_argument('--independent-build', type=Path); parser.add_argument('--baseline-build', type=Path); parser.add_argument('--memory', action='store_true'); args = parser.parse_args()
	build = args.build.resolve(); out = build/'qualification-buffer'; out.mkdir(exist_ok=True)
	if args.memory:
		assert args.baseline_build is not None
		memory(build, out, args.baseline_build.resolve())
	else:
		audit(build, out, args.independent_build.resolve() if args.independent_build else None)
