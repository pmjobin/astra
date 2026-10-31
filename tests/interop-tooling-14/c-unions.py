#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C union and tagged projection calls, in both directions."""
from pathlib import Path
import hashlib
import json
import os
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]

SOURCE = '''[Repr(layout="C-union",members="integer:i64,bits:u64",active="integer")]
struct SignedWord { i64 integer; }
[Repr(layout="C-union",members="integer:i64,bits:u64",active="bits")]
struct UnsignedWord { u64 bits; }
[Repr(layout="C-tagged-union",members="integer:i64,bits:u64",active="integer",tag="1")]
struct SignedPacket { i64 tag; i64 integer; }
[Repr(layout="C-tagged-union",members="integer:i64,bits:u64",active="bits",tag="2")]
struct UnsignedPacket { i64 tag; u64 bits; }
[CImport(name="c_signed",header="union.h",record_abi="value-lp64")]
SignedWord incoming_signed(SignedWord value);
[CImport(name="c_unsigned",header="union.h",record_abi="value-lp64")]
UnsignedWord incoming_unsigned(UnsignedWord value);
[CImport(name="c_packet_signed",header="union.h",record_abi="value-lp64")]
SignedPacket packet_signed(SignedPacket value);
[CImport(name="c_packet_unsigned",header="union.h",record_abi="value-lp64")]
UnsignedPacket packet_unsigned(UnsignedPacket value);
[CExport(name="astra_signed",record_abi="value-lp64")]
SignedWord export_signed(SignedWord value) {
	SignedWord result = incoming_signed(value);
	result.integer = result.integer + (3 as i64); return result;
}
[CExport(name="astra_unsigned",record_abi="value-lp64")]
UnsignedWord export_unsigned(UnsignedWord value) {
	UnsignedWord result = incoming_unsigned(value);
	result.bits = result.bits + (3 as u64); return result;
}
[CExport(name="astra_packet_signed",record_abi="value-lp64")]
SignedPacket export_packet_signed(SignedPacket value) { return packet_signed(value); }
[CExport(name="astra_packet_unsigned",record_abi="value-lp64")]
UnsignedPacket export_packet_unsigned(UnsignedPacket value) { return packet_unsigned(value); }
[CExport(name="astra_invalid_result",record_abi="value-lp64")]
SignedPacket invalid_result(i64 tag) { SignedPacket result = { tag = tag, integer = 42 as i64 }; return result; }
[CExport(name="astra_invalid_argument")]
int invalid_argument() {
	SignedPacket wrong = { tag = 2 as i64, integer = 0 as i64 };
	SignedPacket result = packet_signed(wrong); return result.tag as int;
}
'''

HEADER = '''#ifndef UNION14_H
#define UNION14_H
#include <stdint.h>
#include <stddef.h>
typedef union { int64_t integer; uint64_t bits; } Word;
typedef struct { int64_t tag; Word payload; } Packet;
_Static_assert(sizeof(Word) == 8 && _Alignof(Word) == 8, "union size/alignment");
_Static_assert(offsetof(Word, integer) == 0 && offsetof(Word, bits) == 0, "overlap");
_Static_assert(sizeof(Packet) == 16 && _Alignof(Packet) == 8, "tagged union extent");
_Static_assert(offsetof(Packet, tag) == 0 && offsetof(Packet, payload) == 8, "tag/payload offsets");
Word c_signed(Word);
Word c_unsigned(Word);
Packet c_packet_signed(Packet);
Packet c_packet_unsigned(Packet);
Word astra_signed(Word);
Word astra_unsigned(Word);
Packet astra_packet_signed(Packet);
Packet astra_packet_unsigned(Packet);
Packet astra_invalid_result(int64_t);
int32_t astra_invalid_argument(void);
#endif
'''

PROVIDER = '''#include "union.h"
Word c_signed(Word value) { value.integer += 2; return value; }
Word c_unsigned(Word value) { value.bits += 2; return value; }
Packet c_packet_signed(Packet value) {
	if (value.payload.integer == -99) { value.tag = 2; value.payload.bits = UINT64_MAX; }
	else { value.payload.integer += 7; }
	return value;
}
Packet c_packet_unsigned(Packet value) { value.payload.bits += 11; return value; }
'''

CLIENT = '''#include "union.h"
#include <stdio.h>
int main(int argc, char **argv) {
	if (argc > 1) {
		Packet p = {1, {.integer = 3}};
		switch (argv[1][0]) {
			case '1': p.tag = 2; (void)astra_packet_signed(p); break;
			case '2': p.payload.integer = -99; (void)astra_packet_signed(p); break;
			case '3': (void)astra_invalid_result(2); break;
			case '4': (void)astra_invalid_argument(); break;
			default: return 90;
		}
		return 91;
	}
	const int64_t values[] = {-INT64_C(9000000000000), -7, 0, 42, INT64_C(9000000000000)};
	for (size_t i = 0; i < sizeof(values)/sizeof(values[0]); ++i) {
		Word in = {.integer = values[i]}, out = astra_signed(in);
		if (out.integer != values[i] + 5 || in.integer != values[i]) return 1;
		Packet p = {1, {.integer = values[i]}}, q = astra_packet_signed(p);
		if (q.tag != 1 || q.payload.integer != values[i] + 7 || p.payload.integer != values[i]) return 2;
	}
	Word in = {.bits = UINT64_C(0xf123456789abcdef)}, out = astra_unsigned(in);
	if (out.bits != in.bits + 5) return 3;
	Packet p = {2, {.bits = in.bits}}, q = astra_packet_unsigned(p);
	if (q.tag != 2 || q.payload.bits != p.payload.bits + 11) return 4;
	q = astra_invalid_result(1);
	if (q.tag != 1 || q.payload.integer != 42) return 5;
	puts("PASS: real C signed/unsigned union and tagged union by-value calls; no inactive-member read");
	return 0;
}
'''


def main(compiler_arg, output_arg):
	compiler = Path(compiler_arg).resolve()
	output = Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='c-unions-', dir=output))
	rows = []
	receipt = {'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'checks': rows}
	def run(command, expected=0, contains=''):
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=90,
			cwd=work, env=dict(os.environ, CCACHE_DISABLE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode,
			'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == expected and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	for name, content in [('boundary.astra', SOURCE), ('union.h', HEADER), ('provider.c', PROVIDER), ('client.c', CLIENT)]:
		(work / name).write_text(content)
	source = work / 'boundary.astra'
	for cc in ('gcc', 'clang'):
		for name in ('provider', 'client'):
			run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c', work / (name + '.c'), '-o', work / (cc + '-' + name + '.o')])
	for level in ('0', '1', '2'):
		obj = work / ('astra-O' + level + '.o')
		run([compiler, '-O' + level, '-c', source, '-o', obj])
		for cc in ('gcc', 'clang'):
			binary = work / (cc + '-O' + level)
			run([cc, obj, work / (cc + '-provider.o'), work / (cc + '-client.o'), '-o', binary])
			run([binary], contains='PASS: real C')
			for mode in ('1', '2', '3', '4'):
				run([binary, mode], expected=-signal.SIGILL)
			if level in ('0', '2'):
				run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	bad = work / 'invalid.astra'
	for text, reason in [
		(SOURCE.replace('active="integer"', 'active="missing"', 1), 'C union projection requires'),
		(SOURCE.replace('integer:i64,bits:u64', 'integer:f64,bits:u64', 1), 'C union projection requires'),
		(SOURCE.replace('members="integer:i64,bits:u64",', '', 1), 'explicit members/active'),
		(SOURCE.replace('tag="1"', 'tag="2147483648"'), 'C union projection requires'),
		(SOURCE.replace('result.integer = result.integer', 'result.bits = result.bits'), 'bits'),
		(SOURCE.replace('return packet_unsigned(value);', 'return packet_signed(value);'), 'SignedPacket'),
		(SOURCE + '[CImport(record_abi="natural-lp64")] int alias(borrowed SignedWord* value);', 'borrowed mutable union aliases'),
	]:
		bad.write_text(text)
		run([compiler, '--check', bad], expected=1, contains=reason)
	for mode in ('semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi'):
		run([compiler, '--dump-' + mode, source], contains='C-union')
	run([compiler, '--check', source])
	receipt['source_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: {len(rows)} independent GCC/Clang union, tagged-union, trap, memory and refusal commands; evidence {work}')


if __name__ == '__main__':
	main(*sys.argv[1:])
