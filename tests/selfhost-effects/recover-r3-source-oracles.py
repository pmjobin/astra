#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe C0 before admitting receiver, generic and temporary-owner forms."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, sha, bounded_run


def corpus():
	catch = 'catch (Error caught) { if (caught.message == "kept") return 42; return 3; }'
	parcel = 'class Parcel { init() {} int leaf(bool fail) throws Error { if (fail) { throw new Error("kept"); } return 42; } }\n'
	factory = 'owned Parcel make(bool empty) throws Error { if (empty) return null; var value = new Parcel(); return move value; }\n'
	return {
		'null-checked-receiver': parcel+factory+'int main() { try { var value = make(true); return value.leaf(true); } '+catch+' }\n',
		'nonnull-factory-checked-receiver': parcel+factory+'int main() { try { var value = make(false); return value.leaf(false); } '+catch+' }\n',
		'null-receiver-later-error': 'class Parcel { init() {} int leaf(int value) throws Error { return value; } }\n'+factory+'int fail() throws Error { throw new Error("kept"); }\nint main() { try { var value = make(true); return value.leaf(fail()); } '+catch+' }\n',
		'generic-T-scalar-result': 'T leaf<T>(T value, bool fail) throws Error { if (fail) { throw new Error("kept"); } return value; }\nint main() { try { return leaf<int>(42, false); } '+catch+' }\n',
		'generic-T-record-result': 'struct Pair { int left; int right; }\nT leaf<T>(T value, bool fail) throws Error { if (fail) { throw new Error("kept"); } return value; }\nint main() { Pair pair = {left = 17, right = 25}; try { var value = leaf<Pair>(pair, false); return value.left + value.right; } '+catch+' }\n',
		'generic-T-float-result': 'T leaf<T>(T value, bool fail) throws Error { if (fail) { throw new Error("kept"); } return value; }\nint main() { try { if (leaf<f64>(0.5d, false) == 0.5d) return 42; return 3; } '+catch+' }\n',
		'owned-rvalue-later-argument-error': 'owned int[] make() throws Error { var value = new int[2]; return move value; }\nint fail() throws Error { throw new Error("kept"); }\nint consume(owned int[] value, int extra) { return len(value) + extra; }\nint main() { try { return consume(make(), fail()); } '+catch+' }\n',
		'owned-writable-field-assignment': 'class Box { owned int[] data; init() { this.data = new int[1]; } void replace(owned int[] value) { this.data = move value; } int count() { return len(this.data); } }\nowned int[] make() throws Error { var value = new int[2]; return move value; }\nint main() { var box = new Box(); try { var value = make(); box.replace(move value); return box.count() + 40; } '+catch+' }\n',
		'owned-call-local-assignment': 'owned int[] make() throws Error { var value = new int[2]; return move value; }\nint main() { var value = new int[1]; try { value = make(); return len(value) + 40; } '+catch+' }\n',
		'owned-call-field-error': 'owned int[] make() throws Error { throw new Error("kept"); }\nclass Box { owned int[] data; init() { this.data = new int[1]; } void replace() throws Error { this.data = make(); } int count() { return len(this.data); } }\nint main() { var box = new Box(); try { box.replace(); return 3; } catch (Error caught) { return box.count() + 41; } }\n',
		'owned-Class-call-return': 'class Parcel { init() {} }\nowned Parcel make() throws Error { var value = new Parcel(); return move value; }\nowned Parcel relay() throws Error { return make(); }\nint main() { try { var value = relay(); return 42; } '+catch+' }\n',
	}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r3_source_oracle_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('source-oracles-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	def run(argv, name):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	for name, text in corpus().items():
		source = leaf/(name+'.astra'); source.write_text(text); inputs = [source, ROOT/'lib/astra/base/errors.astra']; exe = build/name; c0 = run([C0, '-'+a.mode, *inputs, '-o', exe], name+'-C0-build'); assert c0.returncode in (0, 1); row = dict(name=name, source_sha256=sha(source), C0_build_exit=c0.returncode, diagnostic=c0.stderr.decode() if c0.returncode else None, C0_actual_execution=None, returning_memory=None)
		if c0.returncode == 0:
			executed = run([exe], name+'-C0-execute'); signal = re.search(r'Command terminated by signal ([0-9]+)', (leaf/(name+'-C0-execute.time')).read_text()); row['timing_wrapper_exit'] = executed.returncode; row['terminating_signal'] = int(signal[1]) if signal else None; row['C0_actual_execution'] = -int(signal[1]) if signal else executed.returncode; oracle = run([C0, '-O0', '--dump-llvm', *inputs], name+'-C0-ABI'); assert oracle.returncode == 0; ir = build/(name+'.ll'); ir.write_bytes(oracle.stdout); assert run(['opt', '-passes=verify', '-disable-output', ir], name+'-C0-verify').returncode == 0; row['C0_raw_LLVM_sha256'] = sha(ir)
			if executed.returncode == 42:
				memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-C0-memory'); assert memory.returncode == 42 and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr; row['returning_memory'] = 'zero unsuppressed errors/live allocations'
		rows.append(row); (leaf/'result.json').write_text(json.dumps(dict(status='C0_SOURCE_FORM_OBSERVATIONS', profile=a.mode, C0_sha256=sha(C0), programs=rows, primary_Astra_credit=0, limitation='Build rejections and fatal exits are observations, not returning-path memory passes. These probes never establish Astra source admission.'), indent=2)+'\n'); print(a.mode, name, 'build', c0.returncode, 'native', row['C0_actual_execution'], flush=True)


if __name__ == '__main__':
	main()
