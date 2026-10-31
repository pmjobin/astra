#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Prepare read-only media for existing COM baselines; never access a VM.

Actual transfer/execution requires the task's separate native host authorization.
Generated batch files touch only a new Astra16 directory in the guest TEMP root.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	with path.open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--export-receipt', type=Path, required=True)
	parser.add_argument('--import-receipt', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	args = parser.parse_args()
	output = args.output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='windows-baseline-', dir=output))
	media = work / 'media'; media.mkdir()
	receipt = dict(scope='M16 host continuity: legacy COM import/export only',
		recipe_sha256=sha(Path(__file__)), products={}, builds={})
	for kind, source in [('export', args.export_receipt), ('import', args.import_receipt)]:
		source = source.resolve(strict=True)
		build = json.loads(source.read_text())
		assert build['build_status'].startswith('PASS; actual native Windows execution pending')
		assert all(row['exit'] == row.get('expected_exit', 0) for row in build['checks'])
		receipt['builds'][kind] = dict(path=str(source), sha256=sha(source), compiler_sha256=build['compiler_sha256'])
		for name, digest in build['products'].items():
			assert Path(name).name == name and name.endswith(('.exe', '.dll'))
			path = source.parent / 'media' / name
			assert sha(path) == digest
			shutil.copyfile(path, media / name)
			receipt['products'][name] = digest
	batch = r'''@echo off
setlocal EnableExtensions
set "ASTRA16_RUN=%TEMP%\Astra16-baseline-%RANDOM%-%RANDOM%"
if exist "%ASTRA16_RUN%" exit /b 12
mkdir "%ASTRA16_RUN%"
if errorlevel 1 exit /b 13
for %%F in (com-client.exe com-provider-O0.dll com-provider-O1.dll com-provider-O2.dll import-provider.dll import-client-O0.exe import-client-O1.exe import-client-O2.exe) do (
	copy /b "%~dp0%%F" "%ASTRA16_RUN%\%%F" >nul
	if errorlevel 1 exit /b 14
)
cd /d "%ASTRA16_RUN%"
>COM1 echo ASTRA16_BASELINE_BEGIN
(ver & echo architecture=%PROCESSOR_ARCHITECTURE% & echo test_directory=%CD%) >inventory.txt
for %%T in (cl.exe clang.exe clang-cl.exe gcc.exe g++.exe python.exe cmake.exe ninja.exe) do where.exe %%T >>inventory.txt 2>&1
for %%F in (*.exe *.dll) do certutil.exe -hashfile "%%F" SHA256 >>inventory.txt 2>&1
type inventory.txt>COM1
for %%L in (0 1 2) do (
	call :export %%L
	if errorlevel 1 goto failed
	call :import %%L
	if errorlevel 1 goto failed
)
>COM1 echo ASTRA16_BASELINE_EXIT=0
>COM1 echo ASTRA16_BASELINE_END
exit /b 0
:failed
>COM1 echo ASTRA16_BASELINE_EXIT=1
>COM1 echo ASTRA16_BASELINE_END
exit /b 1
:export
com-client.exe "%CD%\com-provider-O%1.dll" >export-O%1.txt 2>&1
set "ASTRA16_EXIT=%ERRORLEVEL%"
type export-O%1.txt>COM1
>COM1 echo ASTRA16_EXPORT_O%1_EXIT=%ASTRA16_EXIT%
exit /b %ASTRA16_EXIT%
:import
import-client-O%1.exe "%CD%\import-provider.dll" >import-O%1.txt 2>&1
set "ASTRA16_EXIT=%ERRORLEVEL%"
type import-O%1.txt>COM1
>COM1 echo ASTRA16_IMPORT_O%1_EXIT=%ASTRA16_EXIT%
exit /b %ASTRA16_EXIT%
'''
	(media / 'run.cmd').write_bytes(batch.replace('\n', '\r\n').encode('ascii'))
	receipt['batch_sha256'] = sha(media / 'run.cmd')
	command = ['genisoimage', '-quiet', '-J', '-R', '-V', 'ASTRA16_BASE', '-o', str(work / 'baseline.iso'), str(media)]
	subprocess.run(command, check=True)
	receipt.update(iso_sha256=sha(work / 'baseline.iso'), iso_command=command)
	(work / 'media.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(work)


if __name__ == '__main__':
	main()
