#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Package qualified Windows executables onto task-owned read-only media."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser=argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--build',type=Path,required=True)
	parser.add_argument('--additional-build',type=Path,action='append',default=[])
	parser.add_argument('--output',type=Path,required=True)
	parser.add_argument('--case-offset',type=int,default=0)
	parser.add_argument('--case-count',type=int,default=48)
	args=parser.parse_args();output=args.output.resolve();assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='windows-c-media-',dir=output));media=work/'media';media.mkdir()
	build=json.loads(args.build.read_text());assert build['status']=='CROSS_BUILD_PASS; native Windows execution pending'
	assert all(row['exit']==0 for row in build['checks'])
	locations={name:args.build.parent/'media'/name for name in build['products']}
	for path in args.additional_build:
		other=json.loads(path.read_text());assert other['status']==build['status'] and other['compiler_sha256']==build['compiler_sha256'] and all(row['exit']==0 for row in other['checks'])
		assert not (set(other['products']) & set(build['products']))
		build['products'].update(other['products']);build['execution_expectations'].update(other['execution_expectations']);locations.update({name:path.parent/'media'/name for name in other['products']})
	assert args.case_offset>=0 and 1<=args.case_count<=48
	products=dict(sorted(build['products'].items())[args.case_offset:args.case_offset+args.case_count]);assert products
	for name,digest in products.items():
		assert Path(name).name==name and name.endswith('.exe')
		path=locations[name];assert sha(path)==digest;shutil.copyfile(path,media/name)
	batch=r'''@echo off
setlocal EnableExtensions
set "ASTRA16_RUN=%TEMP%\Astra16-C-%RANDOM%-%RANDOM%"
if exist "%ASTRA16_RUN%" exit /b 12
mkdir "%ASTRA16_RUN%"
if errorlevel 1 exit /b 13
copy /b "%~dp0*.exe" "%ASTRA16_RUN%\" >nul
if errorlevel 1 exit /b 14
cd /d "%ASTRA16_RUN%"
>COM1 echo ASTRA16_C_BEGIN
(ver & echo architecture=%PROCESSOR_ARCHITECTURE% & echo test_directory=%CD%) >inventory.txt
type inventory.txt>COM1
for %%F in (*.exe) do (
 call :one "%%F"
 if errorlevel 1 goto failed
)
>COM1 echo ASTRA16_C_EXIT=0
>COM1 echo ASTRA16_C_END
exit /b 0
:failed
>COM1 echo ASTRA16_C_EXIT=1
>COM1 echo ASTRA16_C_END
exit /b 1
:one
>COM1 echo ASTRA16_C_HASH=%~1
certutil.exe -hashfile "%~1" SHA256 >hash.txt 2>&1
type hash.txt>COM1
"%~1" >case.txt 2>&1
set "ASTRA16_EXIT=%ERRORLEVEL%"
type case.txt>COM1
>COM1 echo ASTRA16_C_CASE=%~1 EXIT=%ASTRA16_EXIT%
if not "%ASTRA16_EXIT%"=="0" exit /b 1
exit /b 0
'''
	(media/'run.cmd').write_bytes(batch.replace('\n','\r\n').encode('ascii'))
	command=['genisoimage','-quiet','-J','-R','-V','ASTRA16_C','-o',str(work/'test.iso'),str(media)];subprocess.run(command,check=True)
	receipt=dict(scope='native Windows declarations-v1 test media; execution not inferred',recipe_sha256=sha(Path(__file__)),build_receipt=dict(path=str(args.build.resolve()),sha256=sha(args.build)),compiler_sha256=build['compiler_sha256'],case_offset=args.case_offset,total_build_products=len(build['products']),products=products,execution_expectations={name:build['execution_expectations'][name] for name in products},batch_sha256=sha(media/'run.cmd'),iso_command=command,iso_sha256=sha(work/'test.iso'))
	if args.additional_build:receipt['additional_build_receipts']=[dict(path=str(path.resolve()),sha256=sha(path)) for path in args.additional_build]
	(work/'media.json').write_text(json.dumps(receipt,indent=2)+'\n');print(work/'media.json')


if __name__=='__main__':main()
