#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute real bounds failures and independently classify unsupported effects."""
import argparse
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import time
from state import ROOT, RUNTIME, sha
from corpus import STORE


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0)); p = argparse.ArgumentParser()
	for name in ('component', 'runtime', 'build'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	assert a.runtime.resolve().is_relative_to(RUNTIME) and a.build.resolve().is_relative_to(ROOT.parent/'codex/work/astra/build/indexpath18')
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	c0 = ROOT.parent/'codex/work/astra/build/llvm23-migration/production-final/astrac'; commands = []; rows = []
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', a.runtime/(name+'.time'), *map(str, argv)], cwd=a.build, capture_output=True, timeout=180, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic())); (a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	for name, count, index in [('negative', 2, -1), ('past-end', 2, 2), ('empty', 0, 0)]:
		for twin, subscript, expected in [('fault', index, -4), ('valid', 0, 0)]:
			if count == 0 and twin == 'valid': continue
			label = name+'-'+twin; source = a.runtime/(label+'.astra'); source.write_text(STORE+'int main() { var s = new Store('+str(count)+'); int index = '+str(subscript)+'; return s.items[index].code; }\n')
			obj = a.build/(label+'.o'); native = a.build/label; oracle = a.build/(label+'.c0')
			assert run([c0, '-'+a.mode, source, '-o', oracle], label+'-C0-build').returncode == 0
			assert run([a.component, '--classstorage-emit-obj', a.mode, obj, source], label+'-native-object').returncode == 0
			assert run(['gcc', obj, '-o', native], label+'-link').returncode == 0
			# /usr/bin/time normalizes signal termination to 128+signal.
			want = 132 if expected == -4 else expected
			n = run([native], label+'-native-execute'); c = run([oracle], label+'-C0-execute'); assert n.returncode == c.returncode == want, (label, n.returncode, c.returncode)
			rows.append(dict(name=label, source_sha256=sha(source), native_sha256=sha(native), C0_sha256=sha(oracle), expected_exit=want, native_exit=n.returncode, C0_exit=c.returncode, classification='FATAL_NO_UNWIND_MEMORY_NOT_NORMAL_EXIT' if expected == -4 else 'VALID_BOUND_TWIN'))
	unsupported = {
		'effectful-index': STORE+'int choose(Store s) { s.items[0] = s.items[0]; return 0; } int main() { var s = new Store(1); return s.items[choose(s)].code; }',
		'wide-index': STORE+'int main() { var s = new Store(1); u64 index = 0; return s.items[index].code; }',
		'readonly-member-store': 'struct Cell { readonly int value; } class Table { owned Cell[] rows; init() { this.rows = new Cell[1]; } } int main() { var t = new Table(); t.rows[0].value = 1; return 0; }',
		'owner-invalidating-index': STORE+'int abandon(owned Store s) { return 0; } int main() { var s = new Store(1); return s.items[abandon(move s)].code; }',
	}
	for name, text in unsupported.items():
		source = a.runtime/(name+'.astra'); source.write_text(text+'\n'); c = run([c0, '--check', source], name+'-C0-check')
		sentinel = a.build/(name+'.o'); shutil.copy2(a.build/'negative-valid.o', sentinel); original = sha(sentinel)
		n = run([a.component, '--classstorage-emit-obj', a.mode, sentinel, source], name+'-native-refusal'); assert n.returncode != 0 and sha(sentinel) == original
		rows.append(dict(name=name, source_sha256=sha(source), C0_status=c.returncode, native_status=n.returncode, destination_preserved=original, native_diagnostic=n.stderr.decode(), C0_diagnostic=c.stderr.decode(), classification='C0_REFUSED' if c.returncode else 'C0_ADMITTED_NATIVE_UNQUALIFIED'))
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), recipe_sha256=sha(__file__), cases=rows, limitation='Fatal traps have no unwind or normal-exit leak qualification. Wide index channels, effectful indexes and indexed field writes are not admitted by this bounded native implementation.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
