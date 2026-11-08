#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe allocation/argument/base/field order in unchanged C0."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, sha, bounded_run

PREFIX = '''[CCode(text_abi = "utf8-i32")]
extern(C) int proof_error_step(borrowed string name, int value);
string message_value() { proof_error_step("arg", 42); return "computed"; }
int argument_value() { return proof_error_step("arg", 42); }
string base_value(int code) { proof_error_step("base", code); return "computed"; }
int field_value(int code) { return proof_error_step("field", code); }
'''


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('error_order_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('error-order-oracles-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	commands = []
	def run(argv, name, environment=None, allowed=(0,)):
		argv = list(map(str, argv))
		env = dict(os.environ, CCACHE_DISABLE='1')
		for key in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE'):
			env.pop(key, None)
		invocation = ['/usr/bin/env', *[key+'='+value for key, value in environment.items()], *argv] if environment else argv
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *invocation], cwd=build, env=env, capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=invocation, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stderr[-1500:])
		return r
	provider = leaf/'provider.c'
	provider.write_text('#include <stdint.h>\n#include <unistd.h>\nint32_t proof_error_step(const unsigned char *p, int32_t n, int32_t value) { if (n < 0 || n > 10) _exit(88); if (write(1, p, (unsigned)n) != n || write(1, "\\n", 1) != 1) _exit(89); return value; }\n')
	obj = build/'provider.o'
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', obj], 'provider-build')
	lifetime = load_module('error_order_interposer', ROOT/'tests/selfhost-effects/recover-r4-lifetime.py')
	observer = leaf/'observe.c'
	observer.write_text(lifetime.INTERPOSER)
	library = build/'observe.so'
	run(['cc', '-std=c11', '-O2', '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror', observer, '-o', library], 'observer-build')
	derived = 'class Detail : Error { private int code; init(int code) : base(base_value(code)) { this.code = field_value(code); } int read() { return this.code; } }\n'
	rows = []
	for name, text, object_size, expected in [
		('root-argument', PREFIX+'int main() { try { throw new Error(message_value()); } catch (Error caught) { if (caught.message == "computed") return 42; return 3; } }\n', 32, b'arg\n'),
		('derived-argument', PREFIX+derived+'int main() { try { throw new Detail(argument_value()); } catch (Detail caught) { if (caught.message != "computed") return 3; return caught.read(); } }\n', 40, b'arg\nbase\nfield\n'),
		('derived-base', PREFIX+derived+'int main() { try { throw new Detail(42); } catch (Detail caught) { if (caught.message != "computed") return 3; return caught.read(); } }\n', 40, b'base\nfield\n'),
	]:
		source = leaf/(name+'.astra')
		source.write_text(text)
		profiles = []
		for mode in ('O0', 'O2'):
			exe = build/(name+'-'+mode)
			run([C0, '-'+mode, source, ROOT/'lib/astra/base/errors.astra', '--link-object', obj, '-o', exe], name+'-'+mode+'-build')
			observed = run([exe], name+'-'+mode+'-execute', allowed=(42,))
			assert observed.stdout == expected
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-'+mode+'-memory', allowed=(42,))
			assert memory.stdout == expected and all(marker in memory.stderr for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
			failures = []
			for size in (object_size, 8):
				failure = run([exe], name+'-'+mode+'-fail-'+str(size), {'LD_PRELOAD':str(library), 'ASTRA_R4_FAIL_SIZE':str(size)}, (132, -4))
				assert ('R4 X 0 '+str(size)+'\n').encode() in failure.stderr
				failures.append(dict(size=size, exit=failure.returncode, observed_stdout=failure.stdout.decode(), returning_memory_credit=False))
			profiles.append(dict(mode=mode, ELF_sha256=sha(exe), exit=42, stdout=observed.stdout.decode(), failures=failures))
		rows.append(dict(name=name, source_sha256=sha(source), profiles=profiles))
		(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_C0_ERROR_EVALUATION_ORDER', programs=rows, provider_source_sha256=sha(provider), interposer_source_sha256=sha(observer), Astra_native_execution_credit=0, limitation='Observable original C0 allocation-failure, argument, base and field evaluation order. Returning Valgrind is unsuppressed and uses no interposer; fatal observations earn no returning memory credit. No Astra source execution is inferred.'), indent=2)+'\n')
		print(name, [(row['mode'], row['failures']) for row in profiles], flush=True)


if __name__ == '__main__':
	main()
