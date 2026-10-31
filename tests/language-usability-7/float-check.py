# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent decimal/bit oracles through public Astra APIs and instrumented LLVM."""
from pathlib import Path
import hashlib
import json
import math
import os
import re
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PLATFORM = ROOT/'lib/runtime/platform'
LIBS = [ROOT/'lib/astra/text/float-format.astra', ROOT/'lib/astra/text/utf8-message.astra',
	ROOT/'lib/astra/base/errors.astra']


def oracle_source():
	bits32 = [0, 0x80000000, 1, 0x80000001, 0x007fffff, 0x00800000, 0x7f7fffff,
		0xff7fffff, 0x3f800000, 0x3f800001, 0x3f800002, 0x7f800000, 0xff800000,
		0x7fc12345, 0xffc00001, 0x3dcccccd]
	bits64 = [0, 0x8000000000000000, 1, 0x8000000000000001, 0x000fffffffffffff,
		0x0010000000000000, 0x7fefffffffffffff, 0xffefffffffffffff, 0x3ff0000000000000,
		0x3ff0000000000001, 0x3ff0000000000002, 0x7ff0000000000000,
		0xfff0000000000000, 0x7ff8000000012345, 0xfff8000000000001, 0x3fb999999999999a]
	for index in range(16, 320):
		bits32.append(((index & 1) << 31) | (((index * 47) % 255) << 23) | ((index * 2654435761) & 0x7fffff))
		bits64.append(((index & 1) << 63) | (((index * 7) % 2047) << 52) | ((index * 11400714819323198485) & ((1 << 52)-1)))
	def spell(bits, width):
		value = struct.unpack('<f' if width == 32 else '<d', bits.to_bytes(width//8, 'little'))[0]
		return 'nan' if math.isnan(value) else format(value, '.9g' if width == 32 else '.17g')
	data = []
	for width, bits in [(32, bits32), (64, bits64)]:
		data.append(f'static const uint{width}_t bits{width}[] = {{'+','.join(f'UINT{width}_C({b})' for b in bits)+'};')
		data.append(f'static const char *text{width}[] = {{'+','.join(json.dumps(spell(b, width)) for b in bits)+'};')
	return '\n'.join([
		'#include "float-text-posix.h"', '#include <assert.h>', '#include <fenv.h>',
		'#include <locale.h>', '#include <math.h>', '#include <stdint.h>', '#include <string.h>',
		*data,
		'int32_t numeric_oracle_count(void) { return 320; }',
		'float numeric_oracle_f32(int32_t i) { assert(i>=0 && i<320); float v; memcpy(&v, &bits32[i], 4); return v; }',
		'double numeric_oracle_f64(int32_t i) { assert(i>=0 && i<320); double v; memcpy(&v, &bits64[i], 8); return v; }',
		'int32_t numeric_oracle_check_f32(float v, int32_t i) { uint32_t b; memcpy(&b, &v, 4); return isnan(numeric_oracle_f32(i)) ? !isnan(v) : b!=bits32[i]; }',
		'int32_t numeric_oracle_check_f64(double v, int32_t i) { uint64_t b; memcpy(&b, &v, 8); return isnan(numeric_oracle_f64(i)) ? !isnan(v) : b!=bits64[i]; }',
		'int32_t numeric_oracle_text(int32_t width, int32_t i, const unsigned char *p, int32_t n) { assert(i>=0 && i<320); const char *expected=width==32 ? text32[i] : text64[i]; return (size_t)n!=strlen(expected) || memcmp(p,expected,(size_t)n)!=0; }',
		'int32_t numeric_oracle_locale(int32_t mode) { return setlocale(LC_NUMERIC, mode ? "fr_CA.utf8" : "C")==NULL || strcmp(localeconv()->decimal_point,mode ? "," : ".")!=0; }',
		'int32_t numeric_oracle_separator(void) { return strcmp(localeconv()->decimal_point,",")==0 ? 1 : strcmp(localeconv()->decimal_point,".")==0 ? 0 : -1; }',
		'int32_t numeric_oracle_rounding(int32_t nearest) { return nearest==2 ? fegetround()!=FE_DOWNWARD : fesetround(nearest ? FE_TONEAREST : FE_DOWNWARD); }',
	])+'\n'


def main(compiler_path, emitter_path, output_path):
	compiler, emitter, output = [Path(p).resolve() for p in [compiler_path, emitter_path, output_path]]
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='float-', dir=output))
	sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
	rows = []
	receipt = dict(compiler_sha256=sha(compiler), emitter_sha256=sha(emitter), checks=rows,
		oracle_values_per_width=320, locales=['C', 'fr_CA.utf8'], products={},
		memory_scope='Valgrind native; ASan native LLVM; ASan/UBSan C providers; no native arithmetic UBSan',
		sources={str(p.relative_to(ROOT)): sha(p) for p in [*LIBS, HERE/'float-text.astra', HERE/'float-check.py',
		PLATFORM/'float-text-posix.c', PLATFORM/'float-text-posix.h', HERE/'observer.c', HERE/'float-provider-edges.c']})
	def save(): (out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	def run(argv, stdout=b'', target=None, memory=False):
		argv = list(map(str, argv))
		p = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=180,
			env=dict(os.environ, CCACHE_DISABLE='1', ASAN_OPTIONS='detect_leaks=1:halt_on_error=1',
			UBSAN_OPTIONS='halt_on_error=1', PYTHONDONTWRITEBYTECODE='1'))
		valid = p.returncode == 0 and (target is not None or p.stdout == stdout)
		valid &= all(x in p.stderr for x in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks',
			b'(suppressed: 0 from 0)']) if memory else not p.stderr
		row = dict(command=argv, exit=p.returncode, stderr=p.stderr.decode(errors='replace'), passed=bool(valid))
		if target:
			target.write_bytes(p.stdout); row.update(stdout_file=str(target), stdout_sha256=sha(target))
		else: row['stdout'] = p.stdout.decode(errors='replace')
		rows.append(row); save(); assert valid, row
		return p
	oracle = out/'oracle.c'; oracle.write_text(oracle_source())
	receipt['oracle_sha256'] = sha(oracle)
	providers = []
	for name, path in [('numeric', PLATFORM/'float-text-posix.c'), ('oracle', oracle), ('observer', HERE/'observer.c')]:
		obj = out/(name+'.o'); providers += ['--link-object', obj]
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fno-fast-math', '-ffp-contract=off',
			'-I', PLATFORM, '-c', path, '-o', obj])
	inputs = [HERE/'float-text.astra', *LIBS]
	trace = b'700\n701\n702\n'
	for opt in ['-O0', '-O1', '-O2']:
		exe = out/('float'+opt)
		run([compiler, opt, *inputs, *providers, '--link-library', 'm', '-o', exe])
		receipt['products'][exe.name] = sha(exe); save()
		run([exe], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', exe], stdout=trace, memory=True)
	for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
		run([compiler, '--dump-'+stage, *inputs], target=out/('float.'+stage))
		# Instrument the independently verified generated LLVM with the existing
		# public test emitter, retaining the actual executable entry wrapper.
	asan_providers = []
	for name, path in [('numeric', PLATFORM/'float-text-posix.c'), ('oracle', oracle), ('observer', HERE/'observer.c')]:
		obj = out/(name+'-asan.o'); asan_providers.append(obj)
		run(['clang', '-std=c11', '-g', '-O1', '-Wall', '-Wextra', '-Werror', '-fno-fast-math',
			'-ffp-contract=off', '-fsanitize=address,undefined', '-I', PLATFORM, '-c', path, '-o', obj])
	edges = out/'provider-edges'
	run(['clang', '-std=c11', '-g', '-O1', '-Wall', '-Wextra', '-Werror', '-fno-fast-math',
		'-ffp-contract=off', '-fsanitize=address,undefined', '-I', PLATFORM,
		HERE/'float-provider-edges.c', asan_providers[0], '-lm', '-o', edges])
	run([edges])
	raw, marked, instrumented, obj, exe = [out/('float'+s) for s in ['-raw.ll', '-marked.ll', '-asan.ll', '-asan.o', '-asan']]
	run([emitter, '--emit', raw, *inputs])
	assert 'define i32 @main(' in raw.read_text()
	text, count = re.subn(r'^(define [^\n]+)\{$', r'\1sanitize_address {', raw.read_text(), flags=re.M)
	assert count > 0; marked.write_text(text)
	run(['opt', '-passes=verify', '-disable-output', marked])
	run(['opt', '-passes=default<O2>,asan', '-S', marked, '-o', instrumented])
	assert '__asan_report_' in instrumented.read_text()
	run(['opt', '-passes=verify', '-disable-output', instrumented])
	run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', instrumented, '-o', obj])
	run(['clang', '-fsanitize=address,undefined', obj, *asan_providers, '-lm', '-o', exe])
	run([exe], stdout=trace)
	receipt['products'][exe.name] = sha(exe); save()
	print(f'{len(rows)} numeric checks; 320 values per width; C/fr_CA locales; O0/O1/O2, Valgrind and native ASan: {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
