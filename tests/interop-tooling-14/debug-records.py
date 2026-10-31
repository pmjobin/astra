#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual GDB reads Source aggregate members across an independent C frame."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]

SOURCE = '''struct Report14 { int category; i64 count; f64 total; }
[CImport(name="debug14_foreign",record_abi="natural-lp64")]
int foreign_probe(borrowed Report14* metrics, int input);
int summarize14(int input) {
	Report14 sample = { category = 7, count = input as i64, total = 1.25 };
	sample.total = sample.total + 2.5;
	return foreign_probe(&sample, input);
}
int main() { return summarize14(35) - 42; }
'''

PROVIDER = '''#include <stdint.h>
#include <stddef.h>
typedef struct { int32_t category; int64_t count; double total; } Report14;
_Static_assert(sizeof(Report14) == 24 && offsetof(Report14, count) == 8 && offsetof(Report14, total) == 16, "C layout");
int32_t debug14_foreign(Report14 *metrics, int32_t input) {
	return metrics && metrics->category == 7 && metrics->count == input && metrics->total == 3.75 ? 42 : 99;
}
'''


def main(compiler_arg, output_arg):
	compiler, output = Path(compiler_arg).resolve(), Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='debug-records-', dir=output))
	rows = []
	receipt = {'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'checks': rows}
	def run(command, contains=''):
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=120,
			cwd=work, env=dict(os.environ, CCACHE_DISABLE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == 0 and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	source, provider = work / 'record.astra', work / 'provider.c'
	source.write_text(SOURCE)
	provider.write_text(PROVIDER)
	run(['clang', '-std=c11', '-O0', '-g', '-gdwarf-4', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c', provider, '-o', work / 'provider.o'])
	commands = work / 'debug.gdb'
	commands.write_text('''set pagination off
set confirm off
set debuginfod enabled off
break debug14_foreign
run
bt
python
import gdb
frame = gdb.newest_frame()
assert frame.name() == "debug14_foreign", frame.name()
assert int(gdb.parse_and_eval("metrics->count")) == 35
assert float(gdb.parse_and_eval("metrics->total")) == 3.75
while frame and not (frame.find_sal().symtab and frame.find_sal().symtab.filename.endswith("record.astra")):
	frame = frame.older()
assert frame, "missing real Source caller frame"
frame.select()
assert frame.find_sal().symtab.filename.endswith("record.astra")
assert int(gdb.parse_and_eval("sample.category")) == 7
assert int(gdb.parse_and_eval("sample.count")) == 35
assert float(gdb.parse_and_eval("sample.total")) == 3.75
print("PASS real Source record category=7 count=35 total=3.75 across C frame")
end
continue
''')
	for level in ('0', '1', '2'):
		binary = work / ('record-O' + level)
		run([compiler, '-g', '-O' + level, source, '--link-object', work / 'provider.o', '-o', binary])
		run([binary])
		run(['llvm-dwarfdump', '--verify', binary], contains='No errors.')
		info = run(['llvm-dwarfdump', '--debug-info', binary], contains='DW_TAG_structure_type')
		assert all(name in info for name in ('Report14', 'category', 'count', 'total', 'sample'))
		if level in ('0', '2'):
			out = run(['gdb', '--nx', '--batch', '-x', commands, binary], contains='PASS real Source record')
			assert 'exited normally' in out
	run([compiler, '-O2', source, '--link-object', work / 'provider.o', '-o', work / 'without-astra-debug'])
	info = run(['llvm-dwarfdump', '--debug-info', work / 'without-astra-debug'])
	assert 'record.astra' not in info and 'Astra Stage 0' not in info
	nested = work / 'nested.astra'
	nested.write_text('''struct Report14 { int category; i64 count; f64 total; }
struct Snapshot14 { int code; Report14 inner; }
[CImport(name="debug14_foreign",record_abi="natural-lp64")]
int foreign_probe(borrowed Report14* metrics, int input);
int visit14(Snapshot14 state) {
	Report14 local = state.inner;
	return foreign_probe(&local, local.count as int) + state.code - 9;
}
int nested14(int input) {
	Snapshot14 snapshot = { code = 9, inner = { category = 7, count = input as i64, total = 3.75 } };
	Snapshot14* address = &snapshot;
	if (address->code != 9) { return 99; }
	return visit14(snapshot);
}
int main() { return nested14(35) - 42; }
''')
	nested_commands = work / 'nested.gdb'
	nested_commands.write_text('''set pagination off
set confirm off
set debuginfod enabled off
break debug14_foreign
run
bt
python
import gdb
frame = gdb.newest_frame()
found = False
while frame:
	frame.select()
	try:
		value = gdb.parse_and_eval("snapshot")
		found = True
		break
	except gdb.error:
		frame = frame.older()
assert found, "missing Source nested aggregate"
assert frame.find_sal().symtab.filename.endswith("nested.astra")
assert int(value["code"]) == 9
assert int(value["inner"]["category"]) == 7
assert int(value["inner"]["count"]) == 35
assert float(value["inner"]["total"]) == 3.75
print("PASS real Source nested record code=9 category=7 count=35 total=3.75")
end
continue
''')
	run([compiler, '-g', '-O0', nested, '--link-object', work / 'provider.o', '-o', work / 'nested-O0'])
	run(['llvm-dwarfdump', '--verify', work / 'nested-O0'], contains='No errors.')
	out = run(['gdb', '--nx', '--batch', '-x', nested_commands, work / 'nested-O0'], contains='PASS real Source nested record')
	assert 'exited normally' in out
	receipt['source_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: {len(rows)} Source record DWARF/GDB/foreign-frame and debug-off commands; evidence {work}')


if __name__ == '__main__':
	main(*sys.argv[1:])
