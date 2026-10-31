#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Capture an explicitly authorized existing serial console; no guest control."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import select
import termios
import time
import tty


def main():
	parser=argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--serial',required=True)
	parser.add_argument('--media-receipt',type=Path,required=True)
	parser.add_argument('--output',type=Path,required=True)
	args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=False)
	media=json.loads(args.media_receipt.read_text());data=bytearray()
	with (args.output/'serial.txt').open('xb') as sink:
		fd=os.open(args.serial,os.O_RDONLY|os.O_NONBLOCK|os.O_NOCTTY);state=termios.tcgetattr(fd)
		try:
			tty.setraw(fd);deadline=time.monotonic()+120;print('Listening on authorized existing serial console',flush=True)
			while time.monotonic()<deadline and len(data)<500000:
				if select.select([fd],[],[],1)[0]:
					chunk=os.read(fd,4096)
					if not chunk:break
					data.extend(chunk);sink.write(chunk);sink.flush()
					if b'ASTRA16_C_END' in data:break
		finally:
			termios.tcsetattr(fd,termios.TCSANOW,state);os.close(fd)
	text=data.decode('utf8',errors='replace');markers=['ASTRA16_C_BEGIN','ASTRA16_C_EXIT=0','ASTRA16_C_END','architecture=AMD64',*media['products'].values()]
	markers+=['ASTRA16_C_CASE='+name+' EXIT=0' for name in media['products']]
	missing=[m for m in markers if m.lower() not in text.lower()]
	case_counts={name:text.count('ASTRA16_C_CASE='+name+' EXIT=0') for name in media['products']}
	hash_checks={name:False for name in media['products']}
	for block in text.split('ASTRA16_C_HASH=')[1:]:
		name=block.splitlines()[0].strip()
		if name in hash_checks:
			hash_checks[name]=media['products'][name].lower() in block.lower() and ('ASTRA16_C_CASE='+name+' EXIT=0') in block
	expected={}
	for row in media['execution_expectations'].values():
		for marker in row['pass_markers']:expected[marker]=expected.get(marker,0)+1
	observed={marker:text.count(marker) for marker in expected}
	passed=not missing and all(n==1 for n in case_counts.values()) and all(hash_checks.values()) and expected==observed and 'FAIL ' not in text
	receipt=dict(scope='native Windows execution of the exact declarations-v1 products and assertions listed in this receipt; final M16 gates remain separate',status='C_MATRIX_NATIVE_WINDOWS_PASS' if passed else 'FAILED_OR_INCOMPLETE',recipe_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),serial_sha256=hashlib.sha256(data).hexdigest(),media_receipt_sha256=hashlib.sha256(args.media_receipt.read_bytes()).hexdigest(),media=media,missing_markers=missing,case_counts=case_counts,hash_checks=hash_checks,expected_pass_markers=expected,observed_pass_markers=observed)
	(args.output/'result.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],cases=len(case_counts),missing_markers=missing,expected_pass_markers=expected,observed_pass_markers=observed)))
	return 0 if passed else 1


if __name__=='__main__':raise SystemExit(main())
