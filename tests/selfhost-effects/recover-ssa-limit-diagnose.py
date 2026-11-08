#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read the actual SSA limit operand without changing execution or verifiers."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--observer', type=Path, required=True)
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	identity = read(a.observer.with_suffix('.identity.json'))
	assert sha(a.observer) == identity['sha256']
	paths = load_module('ssa_limit_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('ssa-limit-'+a.version)
	leaf.mkdir()
	original = read(paths.RUNTIME.parent/'effects25-r5/original-before-O0/result.json')
	inputs = [Path(row['path']) for row in original['inputs']]
	assert all(sha(row['path']) == row['sha256'] for row in original['inputs'])
	disassembly_argv = ['objdump', '-d', '--no-show-raw-insn', str(a.observer)]
	dump = subprocess.check_output(disassembly_argv, text=True)
	(leaf/'observer.disassembly').write_text(dump)
	function = ''
	sites = []
	for line in dump.splitlines():
		if re.match(r'^[0-9a-f]+ <', line):
			function = line
		match = re.match(r'\s*([0-9a-f]+):\s+cmpl\s+\$0x400,0x90\(%rax\)', line)
		if match:
			assert '<astra.fn.' in function
			sites.append(dict(address=match[1], function=function, instruction=line))
	assert len(sites) == 2
	# RecoverCfg is unchanged: two pointer fields and eight 16-byte counted
	# arrays precede block_count, at 16 + 8*16 == 0x90. Both machine sites
	# compare this actual field to the explicit 1024 source guards.
	assert 'int block_count;' in (ROOT/'compiler/cfg/recover-model.astra').read_text()
	script = ['set pagination off', 'set confirm off']
	for site in sites:
		script += ['break *0x'+site['address'], 'commands', 'silent', 'printf "SSA_1024_SITE '+site['address']+' BLOCKS=%d\\n", *(int *)($rax + 0x90)', 'continue', 'end']
	script += ['run']
	command_file = leaf/'read-only.gdb'
	command_file.write_text('\n'.join(script)+'\n')
	argv = ['gdb', '-nx', '-q', '-batch', '-x', str(command_file), '--args', str(a.observer), *map(str, inputs)]
	start = time.monotonic()
	r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/'gdb.time', *argv], cwd=a.observer.parent, env=dict(os.environ), capture_output=True, timeout=300)
	(leaf/'gdb.stdout').write_bytes(r.stdout)
	(leaf/'gdb.stderr').write_bytes(r.stderr)
	counts = [int(value) for value in re.findall(rb'SSA_1024_SITE [0-9a-f]+ BLOCKS=([0-9]+)', r.stdout)]
	result = dict(status='READ_ONLY_SSA_LIMIT_DIAGNOSIS', observer_sha256=sha(a.observer), identity_sha256=sha(a.observer.with_suffix('.identity.json')), source_sha256={str(ROOT/path): identity['identity']['sources'][str(ROOT/path)] for path in ('compiler/cfg/recover-model.astra', 'compiler/ssa/recover.astra')}, inputs=original['inputs'], disassembly_command=disassembly_argv, disassembly_sha256=sha(leaf/'observer.disassembly'), comparison_sites=sites, debugger_command=argv, debugger_exit=r.returncode, start=start, end=time.monotonic(), observed_CFG_block_counts=counts, stdout_sha256=sha(leaf/'gdb.stdout'), stderr_sha256=sha(leaf/'gdb.stderr'), limit_bypassed=False, Astra_native_execution_credit=0, limitation='Debugger reads the actual comparison operand and resumes unchanged execution. It does not change memory/registers, skip the guard, promote a plan or emit a target. Full originals and minimal source view remain distinct acceptance gates.')
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	assert r.returncode == 0 and counts and all(value > 1024 for value in counts) and b'SHARED_CFG_VALID' in r.stdout
	print('Actual full-original CFG blocks:', counts, '; old SSA guard 1024 was executed unchanged', flush=True)


if __name__ == '__main__':
	main()
