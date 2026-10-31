# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source privacy, alias/escape, syntax-boundary and unchanged public controls."""
# Approved declaration/inference promotions retain exact originals and
# O0/O1/O2 memory-tested counterparts in structural-generics-15/historical-observations.
from pathlib import Path
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LIBS = [ROOT / p for p in ["lib/astra/text/utf8-byte-builder.astra", "lib/astra/text/utf8-message.astra", "lib/astra/base/errors.astra"]]
MODEL = HERE / "privacy-model.astra"
ACCESS = {
	"scalar-read": "return v.secret;",
	"scalar-write": "v.secret = 4; return 0;",
	"bytes-length": "return len(v.bytes);",
	"bytes-read": "return v.bytes[0] as int;",
	"bytes-write": "v.bytes[0] = 120; return 0;",
	"bytes-borrow": "take(v.bytes); return 0;",
	"bytes-replace": "v.bytes = new u8[2]; return 0;",
	"bytes-swap": "var incoming = new u8[2]; swap(v.bytes, incoming); return 0;",
	"text-read": "var text = v.label; return text.byte_length;",
	"text-write": 'v.label = "changed"; return 0;',
	"stored-view": "var alias = v.bytes; return len(alias);",
}


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix="run-", dir=output)); rows = []
	def refuse(label, source, diagnostic, inputs=None, syntax=False):
		path = out / (label + ".astra"); path.write_text(source)
		inputs = list(inputs if inputs is not None else [MODEL, *LIBS])
		for stage in (["syntax", "semantics", "core", "cfg", "ssa", "nabi", "llvm", None] if syntax else ["semantics", "core", "cfg", "ssa", "nabi", "llvm", None]):
			binary = out / label
			command = [str(compiler), *(["--dump-" + stage] if stage else []), str(path), *map(str, inputs)]
			if stage is None: command += ["-o", str(binary)]
			p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30)
			valid = p.returncode == 1 and diagnostic in p.stderr and "internal error" not in p.stderr.lower() and not p.stdout and not binary.exists()
			rows.append(dict(label=label, command=command, actual=p.returncode, stdout=p.stdout, stderr=p.stderr, passed=valid))
			(out / "checks.json").write_text(json.dumps(rows, indent=2) + "\n")
			assert valid, rows[-1]
	for label, body in ACCESS.items():
		refuse(label, "void take(u8[] bytes) {}\nint probe(Vault v) { " + body + " }\nint main(){return 0;}\n", "private field 'Vault.")
	refuse("same-file", MODEL.read_text() + "\nint main(){var v=new Vault(1);return v.secret;}\n", "private field 'Vault.secret'", inputs=LIBS)
	refuse("other-class", "class Outsider { init(){} int read(Vault v){return v.secret;} } int main(){return 0;}", "private field 'Vault.secret'")
	refuse("derived-this", "class Derived : Vault { init():base(1){} int read(){return this.secret;} } int main(){return 0;}", "private field 'Vault.secret'")
	refuse("derived-other", "class Derived : Vault { init():base(1){} int read(Vault v){return v.secret;} } int main(){return 0;}", "private field 'Vault.secret'")
	refuse("named-initializer", "class Sealed {private int secret;} int main(){Sealed s={secret=1};return 0;}", "private field 'Sealed.secret'", inputs=[])
	for field, body in [
		("backing", "return len(v.backing);"), ("used", "v.used=2147483647;return 0;"),
		("backing", "v.append_bytes(v.backing);return 0;"),
		("backing", "var alias=v.backing;return len(alias);"),
	]:
		refuse("builder-" + str(len(rows)), "int probe(Utf8ByteBuilder v){"+body+"}int main(){return 0;}", "private field 'Utf8ByteBuilder."+field+"'")
	refuse("buffer-return", "class Escape {private owned u8[] bytes;init(){this.bytes=new u8[1];}u8[] leak(){return this.bytes;}}int main(){return 0;}", "slice", inputs=[])
	refuse("buffer-property", "class Escape {private owned u8[] bytes;init(){this.bytes=new u8[1];}property u8[] leak {get{return this.bytes;}}}int main(){return 0;}", "property", inputs=[])
	refuse("self-alias", "class Alias {private owned u8[] bytes;init(){this.bytes=new u8[1];}int change(u8[] b){this.bytes=new u8[2];return b[0] as int;}int bad(){return this.change(this.bytes);}}int main(){return 0;}", "borrow", inputs=[])
	refuse("private-struct", "struct S{private int field;}int main(){return 0;}", "private fields require", inputs=[], syntax=True)
	refuse("private-method", "class C{private int method(){return 0;}}int main(){return 0;}", "private applies only", inputs=[], syntax=True)
	refuse("private-property", "class C{private property int value{get{return 1;}}}int main(){return 0;}", "private applies only", inputs=[], syntax=True)
	refuse("discard-snapshot", "int main(){try{var b=new Utf8ByteBuilder();b.snapshot();}catch(InvalidUtf8 error){}return 0;}", "owned")
	refuse("unchecked-snapshot", "int main(){var b=new Utf8ByteBuilder();var m=b.snapshot();return 0;}", "checked")
	refuse("loan-after-release", "int main(){try{var b=new Utf8ByteBuilder();var m=b.snapshot();var view=m.text;release m;return view.byte_length;}catch(InvalidUtf8 error){return 1;}}", "loan")
	refuse("copy-builder-owner", "int main(){var b=new Utf8ByteBuilder();owned Utf8ByteBuilder copy=b;return 0;}", "owned")
	print(json.dumps(dict(output=str(out), cases=len(set(r["label"] for r in rows)), commands=len(rows), all_passed=True)))


if __name__ == "__main__":
	main(*sys.argv[1:])
