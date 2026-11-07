#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Concrete source forms for generic, inferred construction and FP carriers."""
import sys
from state import ROOT, load_module


def corpus():
	catch = 'catch (Error caught) { if (caught.message == "kept") return 42; return 4; }'
	rows = {}
	for fail in (False, True):
		flag = str(fail).lower(); suffix = '-error' if fail else '-success'
		for result in ('int', 'void'):
			returned = ' return 17;' if result == 'int' else ''
			call = 'return value.leaf('+flag+') + 25;' if result == 'int' else 'value.leaf('+flag+'); return 42;'
			rows['receiver-'+result+suffix] = 'class Parcel { init() {} '+result+' leaf(bool fail) throws Error { if (fail) { throw new Error("kept"); }'+returned+' } }\nint main() { var value = new Parcel(); try { '+call+' } '+catch+' }\n'
		rows['receiver-nested'+suffix] = 'class Parcel { init() {} int leaf(bool fail) throws Error { if (fail) { throw new Error("kept"); } return 42; } int relay(bool fail) throws Error { return this.leaf(fail); } }\nint main() { var value = new Parcel(); try { return value.relay('+flag+'); } '+catch+' }\n'
		rows['receiver-floating'+suffix] = 'class Parcel { init() {} f64 leaf(f64 value, bool fail) throws Error { if (fail) { throw new Error("kept"); } return value; } }\nint main() { var value = new Parcel(); try { if (value.leaf(0.5d, '+flag+') == 0.5d) return 42; return 3; } '+catch+' }\n'
		leaf = 'T leaf<T>(T value, bool fail) throws Error { if (fail) { throw new Error("kept"); } return value; }\n'
		rows['generic-scalar'+suffix] = leaf+'int main() { try { return leaf<int>(42, '+flag+'); } '+catch+' }\n'
		rows['generic-record'+suffix] = 'struct Pair { int left; int right; }\n'+leaf+'int main() { Pair input = {left = 17, right = 25}; try { var result = leaf<Pair>(input, '+flag+'); return result.left + result.right; } '+catch+' }\n'
		rows['generic-nested'+suffix] = leaf+'T relay<T>(T value, bool fail) throws Error { return leaf<T>(value, fail); }\nint main() { try { return relay<int>(42, '+flag+'); } '+catch+' }\n'
		rows['generic-floating'+suffix] = leaf+'int main() { try { if (leaf<f64>(0.5d, '+flag+') == 0.5d) return 42; return 3; } '+catch+' }\n'
		rows['inferred-parenthesized'+suffix] = 'class Parcel { init() {} }\nint leaf(bool fail) throws Error { var value = (new Parcel()); if (fail) { throw new Error("kept"); } return 42; }\nint main() { try { return leaf('+flag+'); } '+catch+' }\n'
		for kind, literal in [('f32', '0.5f'), ('f64', '0.5d')]:
			rows['floating-'+kind+suffix] = kind+' leaf(bool fail) throws Error { if (fail) { throw new Error("kept"); } return '+literal+'; }\nint main() { try { if (leaf('+flag+') == '+literal+') return 42; return 3; } '+catch+' }\n'
		rows['floating-buffer'+suffix] = 'owned f32[] make(bool fail) throws Error { var value = new f32[2]; if (fail) { throw new Error("kept"); } return move value; }\nint main() { try { var value = make('+flag+'); return len(value) + 40; } '+catch+' }\n'
		rows['floating-record'+suffix] = 'struct Mixed { f32 fraction; int value; f64 wide; }\nMixed make(bool fail) throws Error { Mixed value = {fraction = 0.5f, value = 42, wide = 1.5d}; if (fail) { throw new Error("kept"); } return value; }\nint main() { try { var value = make('+flag+'); if (value.fraction != 0.5f) return 3; if (value.wide != 1.5d) return 3; return value.value; } '+catch+' }\n'
		rows['Class-call-result-return'+suffix] = 'class Parcel { init() {} }\nowned Parcel make(bool fail) throws Error { var value = new Parcel(); if (fail) { throw new Error("kept"); } return move value; }\nowned Parcel relay(bool fail) throws Error { return make(fail); }\nint main() { try { var value = relay('+flag+'); return 42; } '+catch+' }\n'
	rows['floating-signed-zero-success'] = 'f64 leaf(f64 value) throws Error { return -value; }\nint main() { try { var value = leaf(0.0d); if (value == -0.0d) return 42; return 3; } catch (Error caught) { return 4; } }\n'
	rows['floating-NaN-success'] = 'f64 leaf() throws Error { return 0.0d / 0.0d; }\nint main() { try { var value = leaf(); if (value != value) return 42; return 3; } catch (Error caught) { return 4; } }\n'
	rows['floating-strict-arithmetic-success'] = 'f32 leaf(f32 value) throws Error { return (value + 0.5f) * 2.0f - 1.0f; }\nint main() { try { if (leaf(1.0f) == 2.0f) return 42; return 3; } catch (Error caught) { return 4; } }\n'
	make = 'owned int[] make(int count, bool fail) throws Error { var result = new int[count]; if (fail) { throw new Error("kept"); } return move result; }\n'
	rows['owned-call-assignment-success'] = make+'int main() { var value = new int[1]; try { value = make(2, false); return len(value) + 40; } catch (Error caught) { return 4; } }\n'
	rows['owned-call-assignment-error'] = make+'int main() { var value = new int[1]; try { value = make(2, true); return 3; } catch (Error caught) { if (caught.message != "kept") return 4; return len(value) + 41; } }\n'
	rows['owned-call-assignment-loop-success'] = make+'int main() { var value = new int[1]; int count = 1; try { while (count < 4) { value = make(count, false); count = count + 1; } return len(value) + 39; } catch (Error caught) { return 4; } }\n'
	rows['owned-call-assignment-self-transfer-success'] = 'owned int[] identity(owned int[] input) throws Error { return move input; }\nint main() { var value = new int[2]; try { value = identity(move value); return len(value) + 40; } catch (Error caught) { return 4; } }\n'
	return rows


def main():
	prefix = None
	if '--prefix' in sys.argv:
		position = sys.argv.index('--prefix'); prefix = sys.argv[position+1]; del sys.argv[position:position+2]
	def selected():
		rows = corpus(); result = {name:text for name, text in rows.items() if prefix is None or name.startswith(prefix)}; assert result; return result
	if '--oracle-only' in sys.argv:
		oracle = load_module('r3_domain_oracle', ROOT/'tests/selfhost-effects/recover-frontier.py'); oracle.corpus = selected; oracle.main(); return
	runner = load_module('r3_domain_runner', ROOT/'tests/selfhost-effects/recover-qualify.py'); runner.expanded_corpus = selected; sys.argv += ['--expanded']; runner.main()


if __name__ == '__main__':
	main()
