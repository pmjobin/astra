#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Finite natural POD pointer / named synchronous C callback qualification."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
	compiler, out = (Path(x).resolve() for x in sys.argv[1:3])
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=True)
	checks = []
	products = {}

	def run(command, succeeds=True, output=None):
		result = subprocess.run([str(x) for x in command], capture_output=True, timeout=120)
		checks.append(dict(command=[str(x) for x in command], exit=result.returncode,
			stdout=result.stdout.decode(errors="replace"), stderr=result.stderr.decode(errors="replace")))
		(out / "checks.json").write_text(json.dumps(checks, indent=2) + "\n")
		assert (result.returncode == 0) == succeeds, checks[-1]
		if output is not None:
			assert result.stdout == output, checks[-1]
		return result

	c_compilers = [x for x in ["gcc", "clang-22"] if shutil.which(x)]
	assert c_compilers
	for cc in c_compilers:
		provider = out / (cc + "-provider.o")
		run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-c", HERE / "cabi-provider.c", "-o", provider])
		layout = out / (cc + "-layout")
		run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-DCABI_LAYOUT_MAIN", HERE / "cabi-provider.c", "-o", layout])
		run([layout], output=b"CRecord=72/8 offsets=0,8,16,24,32,40,48,56,60,64,68,70 Capture=16/8 offsets=0,8,12\n")
		for feature in ["record", "callback"]:
			source = HERE / ("cabi-" + feature + ".astra")
			for optimization in ["-O0", "-O1", "-O2"]:
				prefix = out / (cc + "-" + feature + optimization)
				native = prefix.with_suffix(".native")
				run([compiler, optimization, "--link-object", provider, "-o", native, source])
				run([native], output=b"")
				obj = prefix.with_suffix(".o")
				run([compiler, optimization, "-c", "-o", obj, source])
				client = prefix.with_suffix(".client")
				run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-DCABI_" + feature.upper(), HERE / "cabi-client.c", obj, provider, "-o", client])
				for seed in [-19, 0, 23, 1007]:
					expected = (f"record:{seed}:72:8\n" if feature == "record" else f"callback:{seed}:{154 + seed * 6}:6:2\n").encode()
					run([client, seed], output=expected)
				products[str(native)] = hashlib.sha256(native.read_bytes()).hexdigest()
				products[str(obj)] = hashlib.sha256(obj.read_bytes()).hexdigest()
				products[str(client)] = hashlib.sha256(client.read_bytes()).hexdigest()
				if shutil.which("valgrind") and optimization != "-O1":
					log = prefix.with_suffix(".valgrind.log")
					run(["valgrind", "--error-exitcode=88", "--leak-check=full", "--show-leak-kinds=all", "--errors-for-leak-kinds=all", "--log-file=" + str(log), client, 23])
					report = log.read_text()
					assert "ERROR SUMMARY: 0 errors" in report, report
					assert "All heap blocks were freed" in report, report
	pod = "struct P{u8 tag;i64 total;int calls;}"
	decl = '[CCode(record_abi="natural-lp64")] extern(C) '
	callback = '[CCode(record_abi="natural-lp64",callback="apply",callback_abi="i32-context-i32-sync")] extern(C) int provider(borrowed P* p,int x);'
	good_callback = "int apply(borrowed P* p,int x){return x;}"
	bad = {
		"unannotated-record": pod + "extern(C) int provider(borrowed P* p);",
		"unmanaged-record": pod + decl + "int provider(P* p);",
		"owned-record": pod + decl + "int provider(owned P* p);",
		"by-value": pod + decl + "int provider(P p);",
		"record-result": pod + decl + "P provider(borrowed P* p);",
		"pointer-result": pod + decl + "P* provider(borrowed P* p);",
		"false-owner-result": pod + decl + "void* provider(borrowed P* p);",
		"bool-field": "struct P{bool value;}" + decl + "int provider(borrowed P* p);",
		"pointer-field": "struct P{void* value;}" + decl + "int provider(borrowed P* p);",
		"nested-field": "struct Inner{int value;}struct P{Inner inner;}" + decl + "int provider(borrowed P* p);",
		"empty-record": "struct P{}" + decl + "int provider(borrowed P* p);",
		"no-record": decl + "int provider(int value);",
		"packed-mode": pod + '[CCode(record_abi="packed")] extern(C) int provider(borrowed P* p);',
		"alignment-mode": pod + '[CCode(record_abi="align16")] extern(C) int provider(borrowed P* p);',
		"union": "union P{int value;}" + decl + "int provider(borrowed P* p);",
		"bitfield": "struct P{int value:3;}" + decl + "int provider(borrowed P* p);",
		"variadic": pod + decl + "int provider(borrowed P* p,...);",
		"callback-missing": pod + callback,
		"callback-unmanaged-context": pod + callback + "int apply(P* p,int x){return x;}",
		"callback-wrong-context": pod + "struct Q{int value;}" + callback + "int apply(borrowed Q* p,int x){return x;}",
		"callback-wrong-input": pod + callback + "int apply(borrowed P* p,i64 x){return 0;}",
		"callback-wrong-result": pod + callback + "void apply(borrowed P* p,int x){}",
		"callback-retained": pod + callback.replace("i32-context-i32-sync", "retained") + good_callback,
		"callback-unpaired-name": pod + callback.replace(',callback_abi="i32-context-i32-sync"', "") + good_callback,
		"callback-unpaired-mode": pod + callback.replace(',callback="apply"', "") + good_callback,
		"callback-wrong-import-input": pod + callback.replace("P* p,int x", "P* p,i64 x") + good_callback,
		"callback-throws": '[ExceptionRoot]class E{readonly string text;init(string t){this.text=t;}virtual property string message{get{return this.text;}}}' + pod + callback + "int apply(borrowed P* p,int x) throws E{return x;}",
		"callback-owner-context": "class P{int value;}" + callback + good_callback,
		"callback-pointer-escape": pod + callback + "P* apply(borrowed P* p,int x){return p;}",
		"callback-copy-context": pod + callback + "int apply(borrowed P* p,int x){P* copy=p;return x;}",
	}
	for name, text in bad.items():
		source = out / (name + ".astra")
		source.write_text(text)
		result = run([compiler, "--dump-llvm", source], succeeds=False)
		assert result.returncode == 1 and result.stderr, checks[-1]
	for feature in ["record", "callback"]:
		for stage in ["--dump-semantics", "--dump-core", "--dump-cfg", "--dump-ssa", "--dump-nabi", "--dump-cabi", "--dump-llvm"]:
			result = run([compiler, stage, HERE / ("cabi-" + feature + ".astra")])
			(out / (feature + stage + ".txt")).write_bytes(result.stdout)
	receipt = dict(checks=len(checks), c_compilers={cc: dict(path=shutil.which(cc), version=subprocess.check_output([cc, "--version"], text=True).splitlines()[0]) for cc in c_compilers}, product_sha256=products,
		compiler=dict(path=str(compiler), sha256=hashlib.sha256(compiler.read_bytes()).hexdigest()),
		sources={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in HERE.glob("cabi-*") if p.is_file()},
		limits="x86-64 Linux LP64 natural scalar POD borrowed pointers; exact named nonthrowing synchronous callback only; no arbitrary retained closure or by-value aggregate ABI")
	(out / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
	print(f"{len(checks)} POD/callback checks passed; compilers={','.join(c_compilers)}")


if __name__ == "__main__":
	main()
