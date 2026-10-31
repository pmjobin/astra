# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compact actual per-command evidence for Git and the native report publisher."""
from pathlib import Path
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]


def main(build_path, runtime_path, output_path):
	build, runtime, output = map(lambda p: Path(p).resolve(), (build_path, runtime_path, output_path))
	assert output.parent == ROOT/'docs'
	sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
	logs = [build/'meson-logs/ecosystem-abi-8-final.json', build/'meson-logs/ecosystem-abi-8-version-final.json']
	tests = {}
	for path in logs:
		for line in path.read_text().splitlines():
			row = json.loads(line)
			assert row['result'] == 'OK' and row['returncode'] == 0, row
			tests[row['name'].split(':')[-1]] = row
	selected = json.loads((ROOT/'tests/ecosystem-abi-8/integration-tests.json').read_text())
	assert set(tests) == set(selected)
	summary = dict(format='astra-ecosystem-abi-8-evidence/1', status='PASS', base_commit='294e801297ac05909daf224229fa2f0ac018592b',
		compiler_sha256=sha(build/'astrac'), selected_registrations=len(tests), all_required_gates='PASS',
		raw_logs={str(p): sha(p) for p in logs}, tests=[], focused={}, commands=[])
	for name in selected:
		row = tests[name]
		summary['tests'].append({k: row.get(k, '') for k in ['name', 'result', 'returncode', 'duration', 'command', 'stdout', 'stderr']})
		if not name.startswith('ecosystem-abi-8-') or name.endswith('-proof'): continue
		match = re.search(r'evidence (/[^\n]+)', row['stdout'])
		assert match, row
		path = Path(match.group(1))/'checks.json'
		receipt = json.loads(path.read_text())
		assert receipt['compiler_sha256'] == summary['compiler_sha256']
		commands = receipt.pop('checks')
		for source, expected in receipt.get('sources', {}).items():
			p = Path(source) if Path(source).is_absolute() else ROOT/source
			assert sha(p) == expected, source
		for product, expected in receipt.get('products', {}).items():
			p = Path(product) if Path(product).is_absolute() else path.parent/product
			assert sha(p) == expected, product
		if 'apps' in receipt:
			for app in receipt['apps'].values():
				for run in app['runs']:
					memory = run.pop('memory')
					run['memory_sha256'] = hashlib.sha256(memory.encode()).hexdigest()
					run['memory_summary'] = memory[-1800:]
		if name.endswith('-gobject'):
			assert not receipt.get('unavailable_sanitizers'), receipt
		summary['focused'][name] = dict(receipt=str(path), receipt_sha256=sha(path), checks=len(commands), **receipt)
		for record in commands:
			assert record['passed'], record
			for field in ('stdout', 'stderr'):
				text = record[field]
				record[field+'_sha256'] = hashlib.sha256(text.encode()).hexdigest()
				limit = 9000 if record['command'][0] == 'gdb' else 2200
				if len(text) > limit: record[field] = text[:500]+'\n[bounded excerpt; complete original hashed above]\n'+text[-limit:]
			summary['commands'].append(dict(test=name, **record))
	inventory = json.loads((runtime/'final-inventory.json').read_text())
	summary['identities'] = inventory['identities']
	summary['source_sha256'] = inventory['source_sha256']
	summary['identity_commands'] = [r for r in inventory['commands'] if not r['command'][:2] == ['git', 'ls-files']]
	summary['uring_probe'] = json.loads((runtime/'final-uring-preflight.json').read_text())
	summary['scope'] = dict(target='GNU x86-64 LP64 Linux', gobject='optional, selected single-threaded Resource/GIR/signal profiles',
		modules='exact-compiler scalar/flat-POD/scalar-field native Class heap-result and borrow profile',
		debug='DWARF4 scalar parameters and addressable locals; optimized variables may disappear',
		memory='new whole-target Valgrind without default suppressions; scoped Clang C ASan/UBSan and allocator interception, not instrumentation of Astra LLVM/system GLib',
		history='LAZY strict Q4 HELD/INCOMPLETE and prior PARTIAL scopes unchanged; no full registry/all-64/SH-4/release/self-hosting claim')
	data = (json.dumps(summary, indent='\t')+'\n').encode()
	assert len(data) < 2*1024*1024, len(data)
	output.write_bytes(data)
	print(f'PASS: {len(tests)} registrations, {len(summary["commands"])} focused commands, {len(data)} bytes: {output}')


if __name__ == '__main__':
	main(*sys.argv[1:])
