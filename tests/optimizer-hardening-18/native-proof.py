#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent native object authority: positive proofs, hostile effects and framing."""
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile


def main():
	checker, build, root = [Path(value).resolve() for value in sys.argv[1:4]]
	for path in [build, root]: path.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix="native-proof-", dir=build))
	receipts = Path(tempfile.mkdtemp(prefix="native-proof-", dir=root))
	commands = []
	passed = False
	def run(args):
		process = subprocess.run([str(a) for a in args], capture_output=True, timeout=20,
			env={**os.environ, "CCACHE_DISABLE": "1"})
		commands.append({"argv": [str(a) for a in args], "exit": process.returncode,
			"stdout": process.stdout.decode(errors="replace"), "stderr": process.stderr.decode(errors="replace")})
		assert process.returncode == 0, commands[-1]
		return process.stdout
	try:
		obj = work / "cases.o"
		run(["cc", "-c", Path(__file__).with_suffix(".S"), "-o", obj])
		for name, result, types, proof in [
			("read32", 4, [32], 11), ("write32", 0, [32, 4], 9),
			("spill32", 4, [32], 11), ("frame32", 4, [32], 11),
			("pure64", 17, [17, 17], 12), ("escape", 8, [32], 0),
			("capture", 0, [32], 0), ("self_capture", 0, [32], 0),
			("compare_pointer", 0, [32], 0), ("wide_read", 8, [32], 0),
			("clobber_saved", 0, [32], 0), ("partial_address", 1, [32], 0),
			("incoming_stack", 8, [], 0), ("atomic", 0, [32], 0),
			("syscall_leaf", 0, [32], 0), ("call_leaf", 0, [32], 0),
			("guarded_read32", 4, [32], 11), ("guarded_tail32", 4, [32], 11),
			("guarded_unused", 4, [32], 11), ("false_guard", 4, [32], 0),
		]:
			assert int(run([checker, obj, name, 0, 4, result, *types])) == proof, name
			# The declaration layout must match the machine access, including width.
		assert int(run([checker, obj, "read32", 4, 4, 4, 32])) == 0
		assert int(run([checker, obj, "read32", 0, 8, 4, 32])) == 0
		for name in ['wrapper32', 'tail32']:
			assert int(run([checker, obj, name, 0, 4, 4, 32, '--', 'read32', '19,4,32'])) == 11
			assert int(run([checker, obj, name, 0, 4, 4, 32])) == 0
		assert int(run([checker, obj, 'wrapper_write32', 0, 4, 0, 32, 4, '--', 'write32', '19,0,32,4'])) == 0
		assert int(run([checker, obj, 'wrapper_write32', 0, 4, 0, 32, 4, '--', 'write32', '17,0,32,4'])) == 9
		assert int(run([checker, obj, 'recursive32', 0, 4, 4, 32, '--', 'recursive32', '19,4,32'])) == 0
		weak = work / 'weak.o'
		run(['objcopy', '--weaken-symbol=read32', obj, weak])
		assert int(run([checker, weak, 'read32', 0, 4, 4, 32])) == 0
		assert int(run([checker, weak, 'wrapper32', 0, 4, 4, 32, '--', 'read32', '19,4,32'])) == 0
		assert int(run([checker, obj, 'comdat_read32', 0, 4, 4, 32])) == 0
		assert int(run([checker, obj, 'conflicting_prefixes', 0, 4, 17, 32])) == 0
		for name, result, types, callee, contract, proof in [
			('conditional32', 4, [32, 1], 'read32', '19,4,32', 11),
			('conditional_null32', 4, [32], 'read32', '19,4,32', 11),
			('conditional_write32', 0, [32, 4, 1], 'write32', '17,0,32,4', 9),
			('conditional_pointer_bits', 4, [32], 'read32', '19,4,32', 0),
			('conditional_false_null', 4, [32], 'read32', '19,4,32', 0),
			('conditional_missing_trap', 4, [32], 'read32', '19,4,32', 0),
			('conditional_stack32', 4, [32, 1], 'read32', '19,4,32', 0),
		]:
			assert int(run([checker, obj, name, 0, 4, result, *types, '--', callee, contract])) == proof, name
		assert int(run([checker, obj, 'conditional_write32', 0, 4, 0, 32, 4, 1, '--', 'write32', '19,0,32,4'])) == 0
		assert int(run([checker, obj, 'conditional32', 0, 4, 4, 32, 1])) == 0
		assert int(run([checker, obj, 'conditional32', 0, 4, 4, 32, '--', 'read32', '19,4,32'])) == 0
		data = obj.read_bytes()
		mutant = work / "mutant.o"
		# Deterministic framing fuzz. No object is executed. Header/section/symbol
		# mutations may preserve a valid proof; every result must remain bounded.
		randomizer = random.Random(1806)
		for attempt in range(256):
			bytes_ = bytearray(data[:randomizer.randrange(len(data)+1)] if attempt < 64 else data)
			for _ in range(randomizer.randrange(1, 5)):
				if bytes_:
					bytes_[randomizer.randrange(len(bytes_))] = randomizer.randrange(256)
			mutant.write_bytes(bytes_)
			assert int(run([checker, mutant, "read32", 0, 4, 4, 32])) in (0, 11)
		passed = True
		print("native object proof: 43 semantic/layout/call/binding cases and 256 framing mutations PASS")
	finally:
		(receipts / "checks.json").write_text(json.dumps({"status": "PASS" if passed else "FAIL", "commands": commands,
			"checker_sha256": hashlib.sha256(checker.read_bytes()).hexdigest(),
			"source_sha256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__), Path(__file__).with_suffix('.S'),
			Path(__file__).with_name('native-proof-driver.c'), Path(__file__).resolve().parents[2] / 'bootstrap/backend/llvm/capi/native-proof.c',
			Path(__file__).resolve().parents[2] / 'bootstrap/backend/llvm/capi/native-proof.h']}}, indent=2)+"\n")


if __name__ == "__main__":
	main()
