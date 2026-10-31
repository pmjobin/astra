#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C-client byte ABI witnesses and fail-closed source controls."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent

def main():
	compiler = Path(sys.argv[1]).resolve()
	out = Path(sys.argv[2]).resolve()
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=True)
	checks = []
	def run(command, succeeds=True):
		result = subprocess.run([str(arg) for arg in command], capture_output=True, timeout=60)
		checks.append(dict(command=[str(arg) for arg in command], exit=result.returncode,
			stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace')))
		(out / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')
		assert (result.returncode == 0) == succeeds, checks[-1]
		return result
	obj = out / 'ffi.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE / 'ffi.c', '-o', obj])
	for level in ['-O0', '-O2']:
		program = out / ('ffi' + level)
		run([compiler, level, '--link-object', obj, '-o', program, HERE / 'ffi.astra'])
		run([program])
	prefix = '[CCode(buffer_abi="u8-i32")] extern(C) '
	bad = {
		'unannotated': 'extern(C) int inspect(borrowed u8[] bytes);',
		'wrong-element': prefix + 'int inspect(borrowed int[] bytes);',
		'not-borrowed': prefix + 'int inspect(u8[] bytes);',
		'owned': prefix + 'int inspect(owned u8[] bytes);',
		'result': prefix + 'u8[] inspect(borrowed u8[] bytes);',
		'no-buffer': prefix + 'int inspect(int n);',
		'wrong-mode': '[CCode(buffer_abi="u8-i64")] extern(C) int inspect(borrowed u8[] bytes);',
		'export': '[CCode(buffer_abi="u8-i32")] export(C) int inspect(borrowed u8[] bytes){return 0;}',
		'null': prefix + 'int inspect(borrowed u8[] bytes); int main(){return inspect(null);}',
		'other-slice': prefix + 'int inspect(borrowed u8[] bytes); int main(){i8[1] x={1};return inspect(slice(x));}',
		'late-consume': prefix + 'int inspect(borrowed u8[] bytes,int later);int take(owned u8[] bytes){return 0;} int main(){var bytes=new u8[3];return inspect(bytes,take(move bytes));}',
		'late-exchange': prefix + 'int inspect(borrowed u8[] bytes,int later);class Box{owned u8[] bytes;init(){this.bytes=new u8[3];}int replace(){this.bytes=new u8[4];return 0;}int bad(){return inspect(this.bytes,this.replace());}}int main(){return 0;}',
		'escape': prefix + 'int inspect(borrowed u8[] bytes);u8[] escape(u8[] bytes){inspect(bytes);return bytes;}',
		'containing-alias-first': prefix + 'int inspect(borrowed u8[] bytes);class Box{owned u8[] bytes;init(){this.bytes=new u8[3];}void replace(){this.bytes=new u8[4];}int bad(Box other){return lend(other.bytes,other);}}int lend(u8[] bytes,Box owner){owner.replace();return inspect(bytes);}int main(){return 0;}',
		'containing-alias-last': prefix + 'int inspect(borrowed u8[] bytes);class Box{owned u8[] bytes;init(){this.bytes=new u8[3];}void replace(){this.bytes=new u8[4];}int bad(Box other){return lend(other,other.bytes);}}int lend(Box owner,u8[] bytes){owner.replace();return inspect(bytes);}int main(){return 0;}',
		'pointer-result': prefix + 'void* inspect(borrowed u8[] bytes);',
	}
	for name, text in bad.items():
		source = out / (name + '.astra')
		source.write_text(text)
		result = run([compiler, '--dump-llvm', source], succeeds=False)
		assert result.returncode == 1 and result.stderr, checks[-1]
		if name.startswith('containing-alias-'):
			assert b'temporary owned-field borrow overlaps' in result.stderr, checks[-1]
		if name == 'pointer-result':
			assert b'C byte buffer imports cannot return pointer-like values' in result.stderr, checks[-1]
	for qualifier in ['', 'owned ']:
		source = out / ('handle-result-' + ('owned' if qualifier else 'unmanaged') + '.astra')
		source.write_text(prefix + qualifier + 'ForeignHandle inspect(borrowed u8[] bytes);')
		result = run([compiler, '--dump-llvm', '--vapi', HERE / 'result-handle.vapi', source], succeeds=False)
		assert result.returncode == 1, checks[-1]
		assert b'C byte buffer imports cannot return pointer-like values' in result.stderr, checks[-1]
	for stage in ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']:
		run([compiler, stage, HERE / 'ffi.astra'])
	print(f'{len(checks)} counted-buffer checks passed')

if __name__ == '__main__':
	main()
