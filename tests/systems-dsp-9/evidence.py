# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compact verified current receipts; never compile, commit or publish results."""
from pathlib import Path
import hashlib
import json
import platform
import subprocess
import sys
from support import ROOT, identity


def digest(text):
	return hashlib.sha256(text.encode()).hexdigest()


def excerpt(text, limit=4000):
	markers = ['volatile ', 'mulpd', 'addpd', 'divpd', 'paddsw', 'syscall', 'llvm.sadd.sat', 'llvm.uadd.sat', 'AArch64', 'ERROR SUMMARY:', 'All heap blocks', 'Breakpoint ', '$1 =']
	witnesses = [line for line in text.splitlines() if any(marker in line for marker in markers)][:60]
	return dict(bytes=len(text.encode()), sha256=digest(text), text=text if len(text) <= limit else text[:limit]+'\n[complete output retained in the external receipt]', selected_witnesses=witnesses)


def git(*args):
	return subprocess.check_output(['git', *args], cwd=ROOT).decode().strip()


def main(build_path, runtime_path, destination):
	build, runtime, destination = Path(build_path).resolve(), Path(runtime_path).resolve(), Path(destination).resolve()
	assert destination.is_relative_to(ROOT)
	compiler = identity(build/'astrac')
	intake = json.loads((runtime/'pm-next-intake.json').read_text())
	initial = json.loads((runtime/'initial-state.json').read_text())
	selected = json.loads((ROOT/'tests/systems-dsp-9/integration-tests.json').read_text())
	meson = build/'meson-logs/systems-dsp-9-qualified.json'
	rows = [json.loads(line) for line in meson.read_text().splitlines() if line.strip()]
	assert len(rows) == len(selected) and all(row['result'] == 'OK' for row in rows)
	assert {row['name'].split(':',1)[-1] for row in rows} == set(selected)
	receipts = []
	for name in ['minimal','numeric','volatile','arena','portability']:
		path = build/'tests/systems-dsp-9'/name/(name+'.json')
		receipt = json.loads(path.read_text())
		assert receipt['status'] == 'PASS' and receipt['compiler'] == compiler
		for row in receipt['files']:
			assert identity(row['path']) == row, ('stale product/source', row)
		commands = []
		for row in receipt['commands']:
			assert row['exit'] == row['expected_exit'], row
			commands.append(dict(command=row['command'], exit=row['exit'], expected_exit=row['expected_exit'],
				expected_stdout=row['expected_stdout'], required_text=row['required_text'], stdout=excerpt(row['stdout']), stderr=excerpt(row['stderr'])))
		receipts.append(dict(name=name, raw_receipt=identity(path), commands=commands, files=receipt['files']))
	options = {row['name']: row['value'] for row in json.loads((build/'meson-info/intro-buildoptions.json').read_text())}
	assert options['werror'] is True
	directories = json.loads((build/'meson-info/meson-info.json').read_text())['directories']
	assert Path(directories['source']).resolve() == ROOT and Path(directories['build']).resolve() == build
	protected = {row['path'] for row in initial['untracked']}
	for row in initial['untracked']:
		path = ROOT/row['path']
		stat = path.stat()
		assert dict(path=row['path'], sha256=hashlib.sha256(path.read_bytes()).hexdigest(), size=stat.st_size, mtime_ns=stat.st_mtime_ns, mode=stat.st_mode) == row
	paths = set(git('ls-files').splitlines()) | (set(git('ls-files','--others','--exclude-standard').splitlines()) - protected)
	paths.discard(str(destination.relative_to(ROOT)))
	sources = [identity(ROOT/path) for path in sorted(paths) if (ROOT/path).is_file()]
	tools = []
	for command in [['uname','-a'],['llvm-config','--version'],['llvm-config','--host-target'],['llvm-config','--targets-built'],
		['clang','--version'],['gcc','--version'],['ld.lld','--version'],['meson','--version'],['valac','--version'],
		['valgrind','--version'],['gdb','--version'],['pkg-config','--modversion','glib-2.0','gobject-2.0']]:
		result = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
		assert result.returncode == 0, command
		tools.append(dict(command=command, exit=result.returncode, stdout=excerpt(result.stdout), stderr=excerpt(result.stderr)))
	build_command = json.loads((runtime/'freeze-build-command-final.json').read_text())
	integration_command = json.loads((runtime/'freeze-integration-command-qualified.json').read_text())
	assert build_command['exit'] == 0 and integration_command['exit'] == 0
	data = dict(format='astra-systems-dsp-evidence/1', milestone=intake['milestone_id'], base=intake['base_commit'],
		compiler=compiler, machine=dict(system=platform.system(), release=platform.release(), architecture=platform.machine()),
		gates={f'S{i}':'PASS within documented finite profile' for i in range(1,8)},
		application_count=8, cross_target='OBJECT_ONLY: aarch64-none-elf, O0/O2, independent Clang layout witness',
		sh4='UNAVAILABLE: installed LLVM registry has no SuperH backend', no_os='NOT_EXECUTED: no qualified startup/runtime image',
		protected_files=len(protected), source_inventory=sources, build_options=dict(werror=options['werror'], buildtype=options['buildtype'], linux_async=options['linux_async']),
		build_command=build_command, integration_command=integration_command, tools=tools,
		selected_tests=[dict(name=row['name'], result=row['result'], command=row['command'], exit=row['returncode'],
		stdout=excerpt(row.get('stdout','')), stderr=excerpt(row.get('stderr',''))) for row in rows], focused_receipts=receipts,
		limitations=['Linux no-libc is OS-dependent.', 'AArch64 objects were not executed; SH-4 and no-OS remain unqualified.',
		'Typed arena storage is an encoded POD plus exact unique-resource side table; initial backing is hosted.',
		'ASan/UBSan cover supplied C boundaries; generated Astra LLVM and installed foreign libraries are not sanitizer-instrumented.',
		'Historical LAZY Q4 remains HELD/INCOMPLETE; this is a selected regression run, not a fresh full registry or all historical apps.'])
	encoded = json.dumps(data,indent=2)+'\n'
	assert len(encoded.encode()) < 2*1024*1024, 'publisher per-source cap'
	destination.write_text(encoded)
	print(f"PASS: {len(rows)} registrations, {sum(len(r['commands']) for r in receipts)} focused commands, {len(sources)} source identities; {len(encoded.encode())} bytes")


if __name__ == '__main__':
	main(*sys.argv[1:])
