# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public composed owning-cache, dispatch and child lifetime evidence."""
from pathlib import Path
import hashlib
import json
import os
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='properties-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	source = HERE/'generic-cache.astra'
	vector = ROOT/'lib/astra/collections/vector.astra'
	errors = ROOT/'lib/astra/base/errors.astra'
	vapi = ROOT/'tests/own-field/fixtures/resources.vapi'
	observer_source = ROOT/'tests/owned-state-6/record-resources.c'
	async_source = HERE/'generic-cache-async.astra'
	virtual = ROOT/'lib/astra/async/virtual.astra'
	provider = compiler.parent/'lib/astra/async-virtual.o'
	inputs = ['--vapi', vapi, vector, errors, source]
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler),
		sources={str(path.relative_to(ROOT)): sha(path) for path in [source, async_source, virtual, vector, errors, vapi, observer_source, Path(__file__).resolve()]}, checks=[], products={}, async_provider_sha256=sha(provider))

	def run(argv, expected=0, diagnostic=None, memory=False, dump=False, stdout=b''):
		argv = list(map(str, argv))
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
			passed &= all(text not in result.stderr for text in [b'internal ', b'assertion', b'CRITICAL'])
		elif memory:
			passed &= result.stdout == stdout and all(text in result.stderr for text in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr and (dump or result.stdout == stdout)
		receipt['checks'].append(dict(command=argv, expected_exit=expected, actual_exit=result.returncode,
			stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace'), passed=bool(passed)))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert passed, receipt['checks'][-1]

	for stage in ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *inputs], dump=True)
	observer = out/'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', observer_source, '-o', observer])
	# Failed first initialization retires Packet1. Receiver2 initializes next;
	# successful Receiver1 moves without initializing again and retires first.
	trace = b'+1\n-1\n+2\n+1\nD101\n-1\nD102\n-2\n+3\n-3\n'
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('generic-cache'+level)
		run([compiler, level, *inputs, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], stdout=trace, memory=True)
	formatted = out/'formatted-cache.astra'
	run([compiler, '--format', '-o', formatted, source])
	run([compiler, '--format', '--check', formatted])
	run([compiler, '--dump-llvm', '--vapi', vapi, vector, errors, formatted], dump=True)
	text = source.read_text()
	for name, old, new, diagnostic in [
		('cache-owner-copy', 'return packet_count(this.packets);', 'var stolen = this.packets; return packet_count(stolen);', 'borrowed'),
		('cache-owner-move', 'return packet_count(this.packets);', 'var stolen = move this.packets; return packet_count(stolen);', 'move'),
		('cache-owner-overlap', 'return packet_count(this.packets);', 'return conflicting(this.packets, this.measure());', 'overlaps'),
		('child-owner-copy', 'this.values = move values;', 'this.values = values;', 'persistent alias'),
		('wrong-child-specialization', 'owned Vector<CachedPacket> values;', 'owned Vector<OtherPacket> values;', 'type'),
	]:
		invalid = out/(name+'.astra')
		invalid.write_text(text.replace(old, new, 1)+'\nstruct OtherPacket { int value; }\nint conflicting(Vector<CachedPacket> packets, int other) { return packets.count() + other; }\n')
		for stage in ['--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--vapi', vapi, vector, errors, invalid], expected=1, diagnostic=diagnostic, dump=True)
	for name, cycle in [
		('generic-child-cycle', 'class Root{owned Vector<Packet> child;init(owned Vector<Packet> child){this.child=move child;}}struct Packet{owned Root root;}'),
		('generic-cache-cycle', 'class Root{lazy property owned Vector<Packet> child{get{var values=new Vector<Packet>(0);return move values;}}}struct Packet{owned Root root;}'),
	]:
		invalid = out/(name+'.astra'); invalid.write_text(cycle+'int main(){return 0;}')
		for stage in ['--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, vector, invalid], expected=1, diagnostic='cyclic owned child', dump=True)
	recursive = out/'recursive-generic-cache.astra'
	recursive.write_text(text.replace('var values = new Vector<CachedPacket>(0);', 'if (this.attempts == 1) { bool recursion = same_packets(this.packets, this.packets); } var values = new Vector<CachedPacket>(0);', 1))
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('recursive-generic-cache'+level)
		run([compiler, level, '--vapi', vapi, vector, errors, recursive, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], expected=-signal.SIGILL)
	async_inputs = ['--vapi' , vapi, vector, errors, virtual, async_source]
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *async_inputs], dump=True)
	async_trace = b'+1\n-1\n+1\nD101\nD201\nD301\n-1\n+2\n-2\n+2\nD102\nD202\nD302\n-2\nD900\n+3\n-3\n+3\nD103\nD303\n-3\nD903\n'
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('generic-cache-async'+level)
		run([compiler, level, *async_inputs, '--link-object', observer, '--link-object', provider, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=async_trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], stdout=async_trace, memory=True)
	invalid = out/'suspended-cache-loan.astra'
	invalid.write_text(async_source.read_text()+'\nasync int suspended(Vector<AsyncPacket> packets) throws Error { await delay_ticks(1); return packets.count(); }\n')
	for stage in ['--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, '--vapi', vapi, vector, errors, virtual, invalid], expected=1, diagnostic='require synchronous native', dump=True)
	receipt['status'] = 'PASS' 
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS {len(receipt["checks"])} public property commands; receipt {out / "checks.json"}')


if __name__ == '__main__':
	main(*sys.argv[1:])
