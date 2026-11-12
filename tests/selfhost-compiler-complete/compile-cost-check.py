#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Check that compiler-cost factoring preserves every original source branch."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
import subprocess
import sys

from run import ROOT, WORK, C0_SHA256, sha
from acceleration import execute, output_path, run_jobs, write


def definition(text, name):
	start = text.index('bool '+name+'(')
	return text[start:text.index('\nbool ', start)]


def source_branches(current, baseline):
	old = definition(baseline, 'recover_child_with_bindings')
	header, body = old.split('\n', 1)
	assert body.endswith('\treturn false;\n}\n')
	body = body[:-len('\treturn false;\n}\n')]
	a = body.index('\tif (row.kind == 1) {')
	b = body.index('\tif (row.kind == 4 || row.kind == 5) {')
	c = body.index('\tif (row.kind == 6) {')
	d = body.index('\tif (row.kind == 69 || row.kind == 70) return ')
	e = body.index('\tif (row.kind == 7) return ')
	groups = [('scalars', body[a:b], [1, 2, 62, 3]), ('calls', body[b:c], [4, 5, 50]), ('records', body[c:d], [6, 8, 12, 75, 17, 18, 44, 45, 27]), ('control', body[e:], [7, 15, 20, 24, 21, 22, 23, 25, 26])]
	params = header[header.index('(')+1:header.index(') {')]
	args = 'flow, checked, types, child, source, function, handler, caught, seen, edges, bindings, depth, row, kind'
	dispatch = []; helpers = []
	for name, branch, kinds in groups:
		helper = 'recover_child_'+name+'_with_bindings'
		expected = 'bool '+helper+'('+params+', RecoverNode row, SyntaxKind kind) {\n'+branch+'\treturn false;\n}\n'
		assert definition(current, helper) == expected, helper
		dispatch.append('\tif ('+' || '.join('row.kind == '+str(k) for k in kinds)+') return '+helper+'('+args+');\n')
		helpers.append(dict(name=helper, kinds=kinds, unchanged_branch_sha256=sha256(branch.encode()).hexdigest()))
	expected_main = header+'\n'+body[:a]+''.join(dispatch[:3])+body[d:e]+dispatch[3]+'\treturn false;\n}\n'
	assert definition(current, 'recover_child_with_bindings') == expected_main
	assert header+'\n'+body[:a]+''.join(row[1] for row in groups[:3])+body[d:e]+groups[3][1]+'\treturn false;\n}\n' == old
	tags = [kind for _, _, kinds in groups for kind in kinds]
	assert len(tags) == len(set(tags))
	return dict(original_function_sha256=sha256(old.encode()).hexdigest(), groups=helpers, disjoint_dispatch=True, original_function_reconstructs_byte_for_byte=True)


def llvm_branches(baseline):
	start = baseline.index('bool recover_llvm_check(')
	header, body = baseline[start:].split('\n', 1)
	parameters = [part.strip() for part in header[header.index('(')+1:header.rindex(')')].split(',')]
	f_open = '\tint f = 0;\n\twhile (f < len(functions)) {\n'
	b_open = '\tint b = 0;\n\twhile (b < ssa.cfg.block_count) {\n'
	fs = body.index(f_open); bs = body.index(b_open)
	f_body = body[fs+len(f_open):bs]
	f_tail = '\t\tf = f + 1;\n\t}\n'
	assert f_body.endswith(f_tail)
	f_body = f_body[:-len(f_tail)]
	b_tail = '\t\tb = b + 1;\n\t}\n\treturn true;\n}\n'
	assert body.endswith(b_tail)
	b_body = body[bs+len(b_open):-len(b_tail)]
	assert not re.search(r'\bf\b', b_body)
	def dedent(text):
		return ''.join(line[1:] if line.startswith('\t') else line for line in text.splitlines(keepends=True))
	f_inner = dedent(f_body)
	old_unreachable = '\t\t\tb = b + 1;\n\t\t\tcontinue;\n'
	assert b_body.count(old_unreachable) == 1
	b_inner = dedent(b_body.replace(old_unreachable, '\t\t\treturn true;\n'))
	count_start = b_inner.index('\tint instruction_count = 1;\n')
	owner_start = b_inner.index('\tif (op == 9) {\n')
	count_end = b_inner.index('\tif (recover_llvm_instruction_count(physical) != instruction_count) return false;\n')
	value_body = b_inner[count_start+len('\tint instruction_count = 1;\n'):owner_start]
	owner_body = b_inner[owner_start:count_end]
	# The first family contains only these opcode predicates. Other opcodes
	# skip every first-family body in the original function, and conversely.
	value_tags = [2, 10, 3, 15, 4, 54, 55, 56, 57, 58, 61, 64, 76, 51, 52, 53, 62, 50, 8, 12, 75, 69, 70, 68]
	owner_guards = '\n'.join(line for line in owner_body.splitlines() if line.startswith('\tif '))
	owner_tags = {int(n) for n in re.findall(r'\bop == (\d+)', owner_guards)}
	assert not owner_tags.intersection(value_tags)
	setup = b_inner.splitlines(keepends=True)[0]+b_inner[b_inner.index('\tSyntaxNodeId absent'):count_start]
	helpers = []; receipts = []
	def helper(name, result, statements, index):
		selected = [parameter for parameter in parameters if re.search(r'\b'+re.escape(parameter.rsplit(' ', 1)[-1])+r'\b', statements)]
		args = ', '.join([p.rsplit(' ', 1)[-1] for p in selected]+[index])
		helpers.append(result+' '+name+'('+', '.join([*selected, 'int '+index])+') throws Error {\n'+statements+'}\n')
		receipts.append(dict(name=name, body_sha256=sha256(statements.encode()).hexdigest()))
		return name+'('+args+')'
	f_call = helper('recover_llvm_function_verified', 'bool', f_inner+'\treturn true;\n', 'f')
	# Every block has a terminator. A successful physical inventory is at
	# least one instruction; zero therefore retains the old false result.
	v_call = helper('recover_llvm_value_instructions', 'int', setup+'\tint instruction_count = 1;\n'+value_body.replace('return false;', 'return 0;')+'\treturn instruction_count;\n', 'b')
	o_call = helper('recover_llvm_owner_instructions', 'int', setup+'\tint instruction_count = 1;\n'+owner_body.replace('return false;', 'return 0;')+'\treturn instruction_count;\n', 'b')
	count = '\tint instruction_count = 0;\n\tif ('+' || '.join('op == '+str(tag) for tag in value_tags)+') instruction_count = '+v_call+';\n\telse {\n\t\tinstruction_count = '+o_call+';\n\t}\n\tif (instruction_count == 0) return false;\n'
	b_call = helper('recover_llvm_block_verified', 'bool', b_inner[:count_start]+count+b_inner[count_end:]+'\treturn true;\n', 'b')
	main = header+'\n'+body[:fs]+f_open+'\t\tif (!'+f_call+') return false;\n'+f_tail+b_open+'\t\tif (!'+b_call+') return false;\n'+b_tail
	# The retained statements reconstruct the entire old loop bodies exactly;
	# only their enclosing loops and false-result transport move to callers.
	assert body[:fs]+f_open+f_body+f_tail+b_open+b_body+b_tail == body
	return baseline[:start]+main+'\n'+'\n'.join(helpers), dict(groups=receipts, value_opcode_tags=value_tags, owner_opcode_tags=sorted(owner_tags), disjoint_dispatch=True, original_loop_bodies_reconstruct_byte_for_byte=True)


def cfg_comparison(args, leaf):
	jobs = []; sources = []
	for label, path in [('baseline', args.cfg_baseline), ('current', args.cfg_current)]:
		path = output_path(path, WORK/'runtime'); plan = json.loads(path.read_text())
		assert plan['argv'][0] == str(args.compiler) and sha(args.compiler) == C0_SHA256
		assert all(sha(path) == digest for group in ('sources', 'tools') for path, digest in plan[group].items())
		inputs = [name for name in plan['argv'] if name.endswith('.astra')]
		assert len(inputs) == 208
		def relative(name):
			return name.split('/source-inputs/', 1)[1] if '/source-inputs/' in name else str(Path(name).relative_to(ROOT))
		sources.append({relative(name):sha(name) for name in inputs})
		jobs.append(dict(id=label, argv=[str(args.compiler), '--dump-cfg', *inputs], inputs={name:sha(name) for name in inputs}, tools=plan['tools'], environment=plan['environment'], expected_exit=0, timeout_seconds=600, estimated_RSS_bytes=2*1024**3, cache='fresh', required_stdout=['(cfg-program', '"recover_llvm_check"', '"recover_child_with_bindings"']))
	assert list(sources[0]) == list(sources[1])
	changed = [name for name in sources[0] if sources[0][name] != sources[1][name]]
	assert set(changed) == {'compiler/backend/llvm/recover-check.astra', 'compiler/semantic/recover-check.astra'}
	spec = dict(format='astra-native-jobs/1', jobs=jobs)
	write(leaf/'cfg-jobs.json', spec)
	result = run_jobs(spec, leaf/'cfg', output_path(args.build_root/leaf.name, WORK/'build'), args.runtime_root/'cfg-cost-cache', jobs=2, max_jobs=2, reserve_bytes=8*1024**3, reuse=False)
	assert not result['failed_jobs']
	counts = {}
	for label in ('baseline', 'current'):
		functions = {}; current = None
		for line in (leaf/'cfg'/label/'stdout').read_text().splitlines():
			if line.startswith('\t('):
				match = re.match(r'^\t\(function #\d+ "([^"]+)"', line)
				current = match[1] if match else None
				if current:
					functions.setdefault(current, []).append(0)
			if current and line.startswith('\t\t(block #'): functions[current][-1] += 1
		counts[label] = functions
	families = {}
	def unique(label, name):
		assert len(counts[label][name]) == 1
		return counts[label][name][0]
	for name, additions in [('recover_llvm_check', ['recover_llvm_function_verified', 'recover_llvm_value_instructions', 'recover_llvm_owner_instructions', 'recover_llvm_block_verified']), ('recover_child_with_bindings', ['recover_child_'+part+'_with_bindings' for part in ('scalars', 'calls', 'records', 'control')])]:
		families[name] = dict(baseline_CFG_blocks=unique('baseline', name), current_CFG_blocks={helper:unique('current', helper) for helper in [name, *additions]})
	write(leaf/'cfg-comparison.json', dict(status='C0_CFG_SIZES_OBSERVED', changed_sources=changed, source_hashes=sources, profiles={label:result['jobs'][label]['metrics'] for label in ('baseline', 'current')}, families=families, full_original_native_credit=0, limitation='Matched C0 CFG-stage observations on all208 inputs, with only the two factored files changed. Graph sizes are a compilation-cost proxy, not measured SSA verification speedup, whole cold-build speedup or Astra native qualification. SSA/native timing remains separate.'))
	print(json.dumps(families, indent=2), flush=True)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--cfg-baseline', type=Path)
	p.add_argument('--cfg-current', type=Path)
	p.add_argument('--build-root', type=Path)
	p.add_argument('--capsule-prefix', type=Path)
	p.add_argument('--inside-capsule', action='store_true', help=argparse.SUPPRESS)
	a = p.parse_args(); assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	if a.capsule_prefix and not a.inside_capsule:
		assert a.capsule_prefix.resolve().is_relative_to((WORK/'runtime').resolve())
		raise SystemExit(subprocess.call([*json.loads(a.capsule_prefix.read_text()), '--', sys.executable, '-B', str(Path(__file__).resolve()), '--inside-capsule', *sys.argv[1:]]))
	leaf = output_path(a.runtime_root/('compile-cost-check-'+a.version), WORK/'runtime'); leaf.mkdir()
	revision = '0823591d894dcd3f22b2c5712e796ba3b25259a0'
	name = 'compiler/semantic/recover-check.astra'
	baseline = subprocess.check_output(['git', 'show', revision+':'+name], cwd=ROOT).decode()
	current = (ROOT/name).read_text()
	proof = source_branches(current, baseline)
	llvm_name = 'compiler/backend/llvm/recover-check.astra'
	llvm_baseline = subprocess.check_output(['git', 'show', revision+':'+llvm_name], cwd=ROOT).decode()
	llvm_current = (ROOT/llvm_name).read_text()
	expected_llvm, llvm_proof = llvm_branches(llvm_baseline)
	assert llvm_current == expected_llvm
	for label, raw in [('baseline', baseline), ('current', current)]:
		path = leaf/(label+'.astra'); path.write_text(raw)
		result = execute([a.compiler, '--dump-syntax', path], leaf/(label+'-syntax'))
		assert result['status'] == 'EXPECTED_OUTCOME'
	for label, raw in [('LLVM-baseline', llvm_baseline), ('LLVM-current', llvm_current)]:
		path = leaf/(label+'.astra'); path.write_text(raw)
		result = execute([a.compiler, '--dump-syntax', path], leaf/(label+'-syntax'))
		assert result['status'] == 'EXPECTED_OUTCOME'
	assert (ROOT/name).read_text() == current
	assert (ROOT/llvm_name).read_text() == llvm_current
	write(leaf/'result.json', dict(status='UNCHANGED_SOURCE_BRANCHES_VERIFIED', reference_revision=revision, reference_source_sha256=sha256(baseline.encode()).hexdigest(), current_source_sha256=sha256(current.encode()).hexdigest(), source_proof=proof, llvm_source_sha256=sha256(llvm_current.encode()).hexdigest(), llvm_proof=llvm_proof, recipe_sha256=sha(__file__), full_original_native_credit=0, limitation='Mechanical source-branch preservation and original C0 syntax only. Common entry checks, tag partitions, recursive arguments, binding/seen/edge arrays and all original branch statements are retained. LLVM false results travel as zero instruction counts; all original statements and loop ordering reconstruct exactly. No measured cold-build improvement, current native product or milestone acceptance follows.'))
	print('UNCHANGED_SOURCE_BRANCHES_VERIFIED', leaf, flush=True)
	if a.cfg_baseline or a.cfg_current:
		assert a.cfg_baseline and a.cfg_current and a.build_root
		cfg_comparison(a, leaf)


if __name__ == '__main__':
	main()
