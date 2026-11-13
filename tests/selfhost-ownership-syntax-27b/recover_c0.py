#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce the explicitly authorized, separately identified replacement C0."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

from support import execute, output_path, sha, tool_identity, write

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
BASE = 'e750030baa139481d89946b2b2182dbe72628d31'


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--build', type=Path, required=True); p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--jobs', type=int, default=6); p.add_argument('--plan-only', action='store_true')
	a = p.parse_args(); assert 1 <= a.jobs <= 6
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	build = output_path(a.build, WORK/'build'); runtime = output_path(a.runtime, WORK/'runtime')
	assert not build.exists(); runtime.mkdir(parents=True, exist_ok=False)
	names = subprocess.check_output(['git', '-C', ROOT, 'ls-files', 'bootstrap', 'meson.build', 'meson.options'], text=True).splitlines()
	inputs = {}
	for name in names:
		path = ROOT/name
		assert path.read_bytes() == subprocess.check_output(['git', '-C', ROOT, 'show', BASE+':'+name]), 'unchanged bootstrap source required: '+name
		inputs[str(path)] = sha(path)
	header = runtime/'glib-public-free.h'; header.write_text('#include <glib.h>\n#undef g_free\n')
	flags = '-include '+str(header)+' '+subprocess.check_output(['pkg-config', '--cflags', 'glib-2.0'], text=True).strip()
	commands = [['meson', 'setup', str(build), str(ROOT), '-Doptimization=0', '-Dstage0_optimization=2', '-Ddebug=true', '-Db_ndebug=false', '-Dwerror=true', '-Dc_args='+flags], ['ninja', '-C', str(build), '-j', str(a.jobs), 'astrac']]
	tools = tool_identity([shutil.which(name) for name in ('meson', 'ninja', 'valac', 'gcc', 'pkg-config', 'llvm-config')])
	write(runtime/'plan.json', dict(status='PLAN_ONLY' if a.plan_only else 'BUILD_REQUIRES_INDEPENDENT_QUALIFICATION', bootstrap_reference=BASE, inputs=inputs, compatibility_header_sha256=sha(header), tools=tools, commands=commands, scope='The GLib public unsized free is a build compatibility setting. No source, historical C0 pin or language/ABI semantics are edited. A new output hash never inherits qualification from an older C0.'))
	if a.plan_only: return
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	rows = []
	for name, argv in zip(('configure', 'compile'), commands):
		r = execute(argv, runtime/name, timeout=1800, env=env); rows.append(dict(name=name, argv=argv, result=r)); write(runtime/'commands.json', rows)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
	assert all(sha(path) == h for path, h in {**inputs, **tools}.items())
	write(runtime/'result.json', dict(status='REPLACEMENT_C0_BUILT_NOT_QUALIFIED', product=dict(path=str(build/'astrac'), sha256=sha(build/'astrac')), original_deleted_C0_sha256='e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b', original_binary_identity_claimed=False, plan_sha256=sha(runtime/'plan.json'), commands_sha256=sha(runtime/'commands.json'), limitation='Run semantic, native oracle, ABI and memory qualification separately. GLib/LLVM process-global reachable registries receive no strict all-kinds memory PASS.'))


if __name__ == '__main__': main()
