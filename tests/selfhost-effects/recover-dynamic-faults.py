#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual dynamic bounds/numeric faults, with separate C0 and Astra ELFs."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

PROVIDER = '''#include <stdint.h>
#include <unistd.h>
int32_t observed_value(const unsigned char *text, int32_t count, int32_t which) {
 (void)text; (void)count;
 switch (which) { case 1: return 1; case 2: return -1; case 3: return INT32_MIN; case 4: return INT32_MAX; case 5: return 256; default: return 0; }
}
int32_t observed_rhs(const unsigned char *text, int32_t count) { return write(1, text, count) == count ? 42 : 3; }
'''
PREFIX = '''[CCode(text_abi = "utf8-i32")]
extern(C) int observed_value(borrowed string text, int which);
[CCode(text_abi = "utf8-i32")]
extern(C) int observed_rhs(borrowed string text);
int dynamic_input(int which) { return observed_value("dynamic", which); }
int dynamic_rhs() { return observed_rhs("RHS\\n"); }
'''


def corpus():
	cases = {}
	for backing, declaration in [('fixed', 'u8[1] bytes = {42};'), ('buffer', 'var bytes = new u8[1]; bytes[0] = 42;')]:
		for label, index in [('end', 1), ('negative', 2)]:
			cases[backing+'-read-'+label] = PREFIX+'int main() { '+declaration+' return bytes[dynamic_input('+str(index)+')] as int; }\n'
			cases[backing+'-write-'+label] = PREFIX+'int main() { '+declaration+' bytes[dynamic_input('+str(index)+')] = dynamic_rhs() as u8; return 42; }\n'
	box = 'class Bytes { owned u8[] data; init() { this.data = new u8[1]; this.data[0] = 42; } }\n'
	cases['stored-buffer-write-end'] = PREFIX+box+'int main() { var bytes = new Bytes(); bytes.data[dynamic_input(1)] = dynamic_rhs() as u8; return 42; }\n'
	cases['constructor-field-normal'] = PREFIX+box+'int main() { var bytes = new Bytes(); return bytes.data[0] as int; }\n'
	cases['constructor-error-field-normal'] = PREFIX+'class Detail : Error { owned u8[] data; init() : base("detail") { this.data = new u8[1]; this.data[0] = 42; } int read() { return this.data[0] as int; } }\nint main() { try { throw new Detail(); } catch (Detail caught) { if (caught.message != "detail") return 3; return caught.read(); } }\n'
	for name, start, count in [('slice-negative-start', 'dynamic_input(2)', '0'), ('slice-start-past', 'dynamic_input(1) + 1', '0'), ('slice-count-past', '0', 'dynamic_input(1) + 1'), ('slice-empty-end', 'dynamic_input(1)', '0')]:
		cases[name] = PREFIX+'int count(u8[] bytes) { return len(bytes) + 42; }\nint main() { u8[1] bytes = {42}; return count(slice(bytes, '+start+', '+count+')); }\n'
	for type_name in ('int', 'i64', 'u32', 'u64'):
		for name, operator in [('divide', '/'), ('modulo', '%')]:
			cases[type_name+'-'+name+'-zero'] = PREFIX+'int main() { '+type_name+' left = 37; '+type_name+' right = dynamic_input(0) as '+type_name+'; return (left '+operator+' right) as int; }\n'
	for type_name, minimum in [('int', '-2147483648'), ('i64', '-9223372036854775808')]:
		cases[type_name+'-minimum-minus-one'] = PREFIX+'int main() { '+type_name+' left = '+minimum+'; '+type_name+' right = dynamic_input(2) as '+type_name+'; if (left / right != left || left % right != 0) return 3; return 42; }\n'
	for name, expression in [('cast-negative-byte', '(dynamic_input(2) as u8) as int == 255'), ('cast-overflow-byte', '(dynamic_input(5) as u8) as int == 0'), ('cast-signed-extend', '(dynamic_input(2) as i8) as int == -1'), ('cast-unsigned-extend', '(dynamic_input(2) as u8) as i64 == 255'), ('cast-wide-roundtrip', '(dynamic_input(2) as u64) as i64 == -1'), ('add-overflow', 'dynamic_input(4) + 1 == -2147483648'), ('subtract-underflow', 'dynamic_input(3) - 1 == 2147483647')]:
		cases[name] = PREFIX+'int main() { if ('+expression+') return 42; return 3; }\n'
	assert len(cases) == len(set(cases.values())) == 32
	return cases


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path)
	a = p.parse_args(); assert a.version.isalnum()
	if a.component:
		identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	paths = load_module('dynamic_fault_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('dynamic-faults-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	commands, programs, failed = [], [], []
	def run(argv, name):
		argv = list(map(str, argv)); env = dict(os.environ, CCACHE_DISABLE='1')
		for key in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE'): env.pop(key, None)
		start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=env, capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		return r
	provider = leaf/'provider.c'; provider.write_text(PROVIDER); obj = build/'provider.o'
	assert run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', obj], 'provider-build').returncode == 0
	for name, text in corpus().items():
		source = leaf/(name+'.astra'); source.write_text(text); inputs = [source, ROOT/'lib/astra/base/errors.astra']
		c0 = build/(name+'-C0'); compiled = run([C0, '-'+a.mode, *inputs, '--link-object', obj, '-o', c0], name+'-C0-build')
		row = dict(name=name, inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], C0_build_exit=compiled.returncode, profiles={})
		if compiled.returncode != 0: failed.append(name+'-C0-source')
		else:
			products = [('C0', c0)]
			if a.component:
				if name in ('stored-buffer-write-end', 'constructor-field-normal', 'constructor-error-field-normal'):
					stages = run([a.component, '--shared-stages', *inputs], name+'-source-stage-mutations')
					row['constructor_stage_exit'] = stages.returncode
					row['constructor_stage_markers'] = [line for line in stages.stdout.decode().splitlines() if line.startswith('SEMANTIC constructor-array-')]
					if stages.returncode != 42 or len(row['constructor_stage_markers']) != 4: failed.append(name+'-constructor-mutations')
				physical = build/(name+'.ll'); physical.write_text('Dynamic fault output sentinel\n'); sentinel = sha(physical)
				emitted = run([a.component, '--native', physical, *inputs], name+'-Astra-emit'); row['Astra_emit_exit'] = emitted.returncode
				if emitted.returncode != 0: row['destination_preserved'] = sha(physical) == sentinel; failed.append(name+'-Astra-emission')
				else:
					optimized, native_obj, exe = build/(name+'-optimized.ll'), build/(name+'.o'), build/(name+'-Astra')
					for label, argv in [('verify', ['opt', '-passes=verify', '-disable-output', physical]), ('optimize', ['opt', '-passes=default<'+a.mode+'>', '-S', physical, '-o', optimized]), ('optimized-verify', ['opt', '-passes=verify', '-disable-output', optimized]), ('object', ['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', native_obj]), ('link', ['cc', '-no-pie', native_obj, obj, '-o', exe])]: assert run(argv, name+'-Astra-'+label).returncode == 0
					row.update(raw_LLVM_sha256=sha(physical), optimized_LLVM_sha256=sha(optimized)); products.append(('Astra', exe))
			for producer, exe in products:
				label = name+'-'+producer; observed = run([exe], label+'-execute')
				assert observed.returncode in (42, 132, 136, -4, -8), (label, observed.returncode, observed.stdout, observed.stderr)
				fatal = observed.returncode != 42; signal = re.findall(r'Command terminated by signal ([0-9]+)', (leaf/(label+'-execute.time')).read_text())
				assert bool(signal) == fatal
				if fatal and '-write-' in name: assert observed.stdout == b'', (label, 'C0 bounds precede the observable RHS', observed.stdout)
				if not fatal:
					memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], label+'-memory')
					assert memory.returncode == 42 and all(marker in memory.stderr for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)')) and memory.stdout == observed.stdout
				row['profiles'][producer] = dict(ELF_sha256=sha(exe), exit=observed.returncode, signal=int(signal[0]) if signal else None, fatal=fatal, returning_clean_memory=not fatal, stdout_sha256=sha(leaf/(label+'-execute.stdout')), stderr_sha256=sha(leaf/(label+'-execute.stderr')))
			if a.component and 'Astra' in row['profiles']:
				left, right = row['profiles']['C0'], row['profiles']['Astra']; assert {k:v for k,v in left.items() if k!='ELF_sha256'} == {k:v for k,v in right.items() if k!='ELF_sha256'}, row
		programs.append(row); (leaf/'result.json').write_text(json.dumps(dict(status='DYNAMIC_SOURCE_FAULTS_PARTIAL' if failed else 'ACTUAL_DYNAMIC_SOURCE_FAULT_CONTROLS' if a.component else 'INDEPENDENT_C0_DYNAMIC_FAULT_ORACLES', profile=a.mode, component_sha256=sha(a.component) if a.component else None, C0_sha256=sha(C0), provider_sha256=sha(provider), provider_object_sha256=sha(obj), programs=programs, complete=len(programs)==32 and not failed, failed=failed, limitation='Dynamic values use the approved counted-text C input ABI and a separate C object, preventing source constant substitution. Each accepted source has independent C0/actual Astra LLVM/ELF executions and exact output/exit/signal comparison. Three actual constructor sources require initialization/owner/type/receiver mutation twins. Fatal controls get zero returning-memory credit; normal paths require unsuppressed returning Valgrind. Counts do not replace original or retained populations.'), indent=2)+'\n')
		print(a.mode, name, {k:v['exit'] for k,v in row['profiles'].items()}, flush=True)
	assert not failed, failed


if __name__ == '__main__':
	main()
