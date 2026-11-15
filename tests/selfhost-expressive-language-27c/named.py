#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual named-call native targets and separately authored C0 expansions."""
import argparse
import ast
import re
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, tool_identity, write

TICKS = '''extern(C) int tick(int value);
extern(C) int trace();
extern(C) void reset_trace();
'''
CHOOSE = 'int choose(int first, int middle, int last) { return first*100+middle*10+last; }\n'
PAIR = '''class Pair {
	int first;
	int last;
	init(int first, int last) { this.first = first; this.last = last; }
	int combine(int first, int last) { return first+last+this.first+this.last+33; }
}
'''
ITEM = '''extern(C) void note_drop(int value);
extern(C) int drops();
extern(C) int drop_sum();
class Item {
	int value;
	init(int value) { this.value = value; }
	deinit() { note_drop(this.value); }
}
'''
OWNER = TICKS+ITEM+'''int mark(bool fail) throws Error {
	int ignored = tick(7);
	if (fail) { throw new Error("named operand failure"); }
	return 0;
}
int eat(owned Item left, owned Item right, int marker) {
	return left.value+right.value+marker;
}
int attempt(bool fail) {
	var left = new Item(20);
	var right = new Item(22);
	try {
		@CALL@
	} catch (Error error) { return 42; }
}
int main() {
	reset_trace();
	if (attempt(false) != 42 || trace() != 7 || drops() != 2 || drop_sum() != 42) return 1;
	reset_trace();
	if (attempt(true) != 42 || trace() != 7 || drops() != 4 || drop_sum() != 84) return 2;
	return 42;
}
'''
THROW = TICKS+CHOOSE+'''int risky() throws Error { int ignored = tick(2); throw new Error("operand stop"); }
int main() {
	reset_trace();
	try { @CALL@ }
	catch (Error error) { if (trace() == 12) return 42; }
	return 1;
}
'''
FRESH = ITEM+'''extern(C) int drop_order();
extern(C) void reset_drops();
int mark(bool fail) throws Error {
	if (fail) { throw new Error("fresh operand failure"); }
	return 0;
}
int eat(owned Item left, owned Item right, int marker) {
	return left.value+right.value+marker;
}
owned Item forward(owned Item item, int marker) { return move item; }
int attempt(bool fail) {
	try { @CALL@ }
	catch (Error error) { return 42; }
}
int main() {
	reset_drops();
	if (attempt(false) != 42 || drops() != 2 || drop_sum() != 42 || drop_order() != 2220) return 1;
	reset_drops();
	if (attempt(true) != 42 || drops() != 2 || drop_sum() != 42 || drop_order() != 2022) return 2;
	return 42;
}
'''
FRESH_EXPANDED = '''var right = new Item(22); var left = new Item(20);
	int marker = mark(fail); return eat(move left, move right, marker);'''
CASES = [
	('scalar-order', TICKS+CHOOSE+'''int main() {
	reset_trace();
	if (choose(last: tick(3), first: tick(1), middle: tick(2)) != 123 || trace() != 312) return 1;
	reset_trace();
	if (choose(tick(1), last: tick(3), middle: tick(2)) != 123 || trace() != 132) return 2;
	return 42;
}
''', TICKS+CHOOSE+'''int main() {
	reset_trace();
	int last = tick(3); int first = tick(1); int middle = tick(2);
	if (choose(first, middle, last) != 123 || trace() != 312) return 1;
	reset_trace();
	int other_first = tick(1); int other_last = tick(3); int other_middle = tick(2);
	if (choose(other_first, other_middle, other_last) != 123 || trace() != 132) return 2;
	return 42;
}
''', False),
	('typed-labels', '''int typed(bool enabled, u8 small, f64 wide) {
	if (enabled && small == 2 && wide == 40.0d) return 42;
	return 1;
}
int main() { return typed(wide: 40.0d, small: 2, enabled: true); }
''', '''int typed(bool enabled, u8 small, f64 wide) {
	if (enabled && small == 2 && wide == 40.0d) return 42;
	return 1;
}
int main() { return typed(true, 2, 40.0d); }
''', False),
	('generic-labels', '''T choose_value<T>(bool enabled, T value) { if (enabled) return value; return value; }
int main() {
	if (choose_value(value: 42, enabled: true) != 42) return 1;
	return choose_value<int>(value: 42, enabled: false);
}
''', '''T choose_value<T>(bool enabled, T value) { if (enabled) return value; return value; }
int main() {
	if (choose_value(true, 42) != 42) return 1;
	return choose_value<int>(false, 42);
}
''', False),
	('constructor-method-order', TICKS+PAIR+'''int main() {
	reset_trace();
	var pair = new Pair(last: tick(2), first: tick(4));
	if (trace() != 24 || pair.first != 4 || pair.last != 2) return 1;
	reset_trace();
	int result = pair.combine(last: tick(2), first: tick(1));
	if (trace() != 21) return 2;
	return result;
}
''', TICKS+PAIR+'''int main() {
	reset_trace();
	int last = tick(2); int first = tick(4);
	var pair = new Pair(first, last);
	if (trace() != 24 || pair.first != 4 || pair.last != 2) return 1;
	reset_trace();
	int call_last = tick(2); int call_first = tick(1);
	int result = pair.combine(call_first, call_last);
	if (trace() != 21) return 2;
	return result;
}
''', False),
	('C-ABI-order', TICKS+'''extern(C) int c_sum(int first, int last);
int main() {
	reset_trace();
	int result = c_sum(last: tick(2), first: tick(4));
	if (trace() != 24 || result != 6) return 1;
	return result+36;
}
''', TICKS+'''extern(C) int c_sum(int first, int last);
int main() {
	reset_trace();
	int last = tick(2); int first = tick(4);
	int result = c_sum(first, last);
	if (trace() != 24 || result != 6) return 1;
	return result+36;
}
''', False),
	('owned-call-abort', OWNER.replace('@CALL@', 'return eat(right: move right, left: move left, marker: mark(fail));'), OWNER.replace('@CALL@', 'int marker = mark(fail); return eat(move left, move right, marker);'), True),
	('owner-reservation-written-order', OWNER.replace('int eat(owned Item left, owned Item right, int marker)', 'int eat(int marker, owned Item left, owned Item right)').replace('@CALL@', 'return eat(right: move right, marker: mark(fail), left: move left);'), OWNER.replace('int eat(owned Item left, owned Item right, int marker)', 'int eat(int marker, owned Item left, owned Item right)').replace('@CALL@', 'int marker = mark(fail); return eat(marker, move left, move right);'), True),
	('fresh-owner-abort', FRESH.replace('@CALL@', 'return eat(right: new Item(22), left: new Item(20), marker: mark(fail));'), FRESH.replace('@CALL@', FRESH_EXPANDED), True),
	('fresh-nested-abort', FRESH.replace('@CALL@', 'return eat(right: new Item(22), left: forward(item: new Item(20), marker: mark(fail)), marker: 0);'), FRESH.replace('@CALL@', '''var right = new Item(22); var item = new Item(20);
	int marker = mark(fail); var left = forward(move item, marker); return eat(move left, move right, 0);'''), True),
	('fresh-conditional-abort', FRESH.replace('@CALL@', 'return eat(right: fail ? new Item(22) : new Item(22), left: new Item(20), marker: mark(fail));'), FRESH.replace('@CALL@', FRESH_EXPANDED), True),
	('fresh-match-abort', 'enum Choice { First, Last }\n'+FRESH.replace('@CALL@', 'return eat(right: match (Choice.Last()) { case Choice.First() => new Item(1); case Choice.Last() => new Item(22); }, left: new Item(20), marker: mark(fail));'), FRESH.replace('@CALL@', FRESH_EXPANDED), True),
	('fresh-buffer-abort', '''int mark(bool fail) throws Error { if (fail) { throw new Error("buffer operand failure"); } return 29; }
int eat(owned int[] values, int marker) { return len(values)+marker; }
int attempt(bool fail) { try { return eat(values: new int[13], marker: mark(fail)); } catch (Error error) { return 42; } }
int main() { if (attempt(false) != 42) return 1; return attempt(true); }
''', '''int mark(bool fail) throws Error { if (fail) { throw new Error("buffer operand failure"); } return 29; }
int eat(owned int[] values, int marker) { return len(values)+marker; }
int attempt(bool fail) { try { owned int[] values = new int[13]; int marker = mark(fail); return eat(move values, marker); } catch (Error error) { return 42; } }
int main() { if (attempt(false) != 42) return 1; return attempt(true); }
''', True),
	('caller-expression-label', '''bool observe(int first, int last, [CallerArgumentExpression("first")] string expression) {
	return first == 20 && last == 22 && expression == "10 * 2";
}
int main() { if (observe(last: 22, first: 10 * 2)) return 42; return 1; }
''', '''bool observe(int first, int last, [CallerArgumentExpression("first")] string expression) {
	return first == 20 && last == 22 && expression == "10 * 2";
}
int main() { if (observe(10 * 2, 22)) return 42; return 1; }
''', False),
	('throw-order', THROW.replace('@CALL@', 'int value = choose(first: tick(1), middle: risky(), last: tick(3));'), THROW.replace('@CALL@', 'int first = tick(1); int middle = risky(); int last = tick(3); int value = choose(first, middle, last);'), True),
	('namespace-call', '''int main() { return Helpers.add(last: 22, first: 20); }
''', '''int main() { return Helpers.add(20, 22); }
''', False),
]
NEGATIVE = [
	('duplicate', CHOOSE+'int main() { return choose(first: 1, first: 2, last: 3); }'),
	('missing', CHOOSE+'int main() { return choose(first: 1, last: 3); }'),
	('unknown', CHOOSE+'int main() { return choose(first: 1, middle: 2, missing: 3); }'),
	('positional-tail', CHOOSE+'int main() { return choose(first: 1, 2, 3); }'),
	('positional-label-collision', CHOOSE+'int main() { return choose(1, first: 2, last: 3); }'),
	('wrong-type', CHOOSE+'int main() { return choose(first: true, middle: 2, last: 3); }'),
	('intrinsic-label', 'int main() { int[1] data = {42}; return len(value: data); }'),
	('double-owner', ITEM+'int take(owned Item first, owned Item last) { return first.value+last.value; } int main() { var item = new Item(21); return take(last: move item, first: move item); }'),
	('borrowed-consume', ITEM+'int take(owned Item value) { return value.value; } int inspect(Item value) { return take(value: move value); } int main() { var item = new Item(42); return inspect(item); }'),
	('hidden-receiver-label', PAIR+'int main() { var pair = new Pair(4, 2); return pair.combine(_astra_receiver: pair, first: 1, last: 2); }'),
]

MATCH_TAG = 'enum Mode { First, Middle, Last }\n'
NESTED_TAG = 'enum Problem { NotFound, Decode(int code) }\nenum Result { Success(int value), Failure(Problem problem) }\n'
OWNING_TAG = 'enum Packet { Empty, Data(owned int[] data, int count) }\n'
MATCH_CASES = [
	('match-enum-reservation', OWNING_TAG+'''int marker(bool fail) throws Error {
	if (fail) { throw new Error("enum operand failure"); }
	return 13;
}
Packet make(bool fail) throws Error {
	owned int[] data = new int[13];
	return Packet.Data(move data, marker(fail));
}
int inspect(Packet value) => match (move value) {
	case Packet.Empty() => 1;
	case Packet.Data(data, count) => len(data)+count+16;
};
int main() {
	try { var failed = make(true); return 1; } catch (Error error) {}
	try { return inspect(make(false)); } catch (Error error) { return 2; }
}
''', OWNING_TAG+'''int marker(bool fail) throws Error {
	if (fail) { throw new Error("enum operand failure"); }
	return 13;
}
Packet make(bool fail) throws Error {
	owned int[] data = new int[13];
	return Packet.Data(move data, marker(fail));
}
int inspect(Packet value) {
	match (move value) {
		case Packet.Empty(): { return 1; }
		case Packet.Data(data, count): { return len(data)+count+16; }
	}
}
int main() {
	try { var failed = make(true); return 1; } catch (Error error) {}
	try { return inspect(make(false)); } catch (Error error) { return 2; }
}
''', True),
	('match-enum-reserved-read', OWNING_TAG+'''int inspect(Packet value) => match (move value) {
	case Packet.Empty() => 1;
	case Packet.Data(data, count) => len(data)+count+16;
};
int main() {
	owned int[] data = new int[13];
	return inspect(Packet.Data(move data, len(data)));
}
''', OWNING_TAG+'''int inspect(Packet value) {
	match (move value) {
		case Packet.Empty(): { return 1; }
		case Packet.Data(data, count): { return len(data)+count+16; }
	}
}
int main() {
	owned int[] data = new int[13];
	return inspect(Packet.Data(move data, len(data)));
}
''', False),
	('match-consuming-payload', OWNING_TAG+'''owned int[] take(Packet value) => match (move value) {
	case Packet.Empty() => new int[0];
	case Packet.Data(data, count) => move data;
};
int main() {
	var state = Packet.Data(new int[13], 13);
	owned int[] values = take(move state);
	owned int[] empty = take(Packet.Empty());
	return len(values)+len(empty)+29;
}
''', OWNING_TAG+'''owned int[] take(Packet value) {
	match (move value) {
		case Packet.Empty(): { return new int[0]; }
		case Packet.Data(data, count): { return move data; }
	}
}
int main() {
	var state = Packet.Data(new int[13], 13);
	owned int[] values = take(move state);
	owned int[] empty = take(Packet.Empty());
	return len(values)+len(empty)+29;
}
''', False),
	('match-inspecting-owner', OWNING_TAG+'''int inspect(Packet value) {
	int count = match (value) {
		case Packet.Empty() => 0;
		case Packet.Data(data, count) => len(data)+count;
	};
	return count;
}
int main() { return inspect(Packet.Data(new int[13], 29)); }
''', OWNING_TAG+'''int inspect(Packet value) {
	int result = 0;
	match (value) {
		case Packet.Empty(): { result = 0; }
		case Packet.Data(data, count): { result = len(data)+count; }
	}
	return result;
}
int main() { return inspect(Packet.Data(new int[13], 29)); }
''', False),
	('match-consuming-nested', OWNING_TAG+'''enum Envelope { Missing, Child(Packet packet, owned int[] tail) }
owned int[] take(Envelope value) => match (move value) {
	case Envelope.Missing() => new int[0];
	case Envelope.Child(Packet.Empty(), _) => new int[0];
	case Envelope.Child(Packet.Data(data, count), _) => move data;
};
int main() {
	owned int[] values = take(Envelope.Child(Packet.Data(new int[13], 13), new int[7]));
	owned int[] empty = take(Envelope.Child(Packet.Empty(), new int[9]));
	owned int[] missing = take(Envelope.Missing());
	return len(values)+len(empty)+len(missing)+29;
}
''', OWNING_TAG+'''enum Envelope { Missing, Child(Packet packet, owned int[] tail) }
owned int[] take(Envelope value) {
	match (move value) {
		case Envelope.Missing(): { return new int[0]; }
		case Envelope.Child(packet, _): {
			match (move packet) {
				case Packet.Empty(): { return new int[0]; }
				case Packet.Data(data, count): { return move data; }
			}
		}
	}
}
int main() {
	owned int[] values = take(Envelope.Child(Packet.Data(new int[13], 13), new int[7]));
	owned int[] empty = take(Envelope.Child(Packet.Empty(), new int[9]));
	owned int[] missing = take(Envelope.Missing());
	return len(values)+len(empty)+len(missing)+29;
}
''', False),
	('match-consuming-error', OWNING_TAG+'''int fail(int[] data, int count) throws Error {
	if (len(data) == count) { throw new Error("selected payload failure"); }
	return 1;
}
int attempt() throws Error {
	var state = Packet.Data(new int[13], 13);
	return match (move state) {
		case Packet.Empty() => 1;
		case Packet.Data(data, count) => fail(data, count);
	};
}
int main() { try { return attempt(); } catch (Error error) { return 42; } }
''', OWNING_TAG+'''int fail(int[] data, int count) throws Error {
	if (len(data) == count) { throw new Error("selected payload failure"); }
	return 1;
}
int attempt() throws Error {
	var state = Packet.Data(new int[13], 13);
	match (move state) {
		case Packet.Empty(): { return 1; }
		case Packet.Data(data, count): { return fail(data, count); }
	}
}
int main() { try { return attempt(); } catch (Error error) { return 42; } }
''', True),
	('match-constructor-source', MATCH_TAG+'''class Box {
	int value;
	init(Mode mode) {
		this.value = match (mode) {
			case Mode.First() => 20;
			case Mode.Middle() => 22;
			case Mode.Last() => 42;
		};
	}
}
int main() { var box = new Box(Mode.Last()); return box.value; }
''', MATCH_TAG+'''int status(Mode mode) {
	match (mode) {
		case Mode.First(): { return 20; }
		case Mode.Middle(): { return 22; }
		case Mode.Last(): { return 42; }
	}
}
class Box { int value; init(Mode mode) { this.value = status(mode); } }
int main() { var box = new Box(Mode.Last()); return box.value; }
''', False),
	('match-owned-local', ITEM+MATCH_TAG+'''int run(Mode value) {
	var item = match (value) {
		case Mode.First() => new Item(20);
		case Mode.Middle() => new Item(22);
		case Mode.Last() => new Item(42);
	};
	return item.value;
}
int main() { if (run(Mode.Last()) != 42 || drops() != 1 || drop_sum() != 42) return 1; return 42; }
''', ITEM+MATCH_TAG+'''owned Item acquire(Mode value) {
	match (value) {
		case Mode.First(): { var item = new Item(20); return move item; }
		case Mode.Middle(): { var item = new Item(22); return move item; }
		case Mode.Last(): { var item = new Item(42); return move item; }
	}
}
int run(Mode value) { var item = acquire(value); return item.value; }
int main() { if (run(Mode.Last()) != 42 || drops() != 1 || drop_sum() != 42) return 1; return 42; }
''', False),
	('match-owned-error-cleanup', ITEM+MATCH_TAG+'''owned Item build(int value, bool fail) throws Error {
	var item = new Item(value);
	if (fail) { throw new Error("selected match failure"); }
	return move item;
}
int attempt(Mode value) {
	try {
		var item = match (value) {
			case Mode.First() => build(20, true);
			case Mode.Middle() => build(999, false);
			case Mode.Last() => build(42, false);
		};
		return item.value;
	} catch (Error error) { return 42; }
}
int main() {
	if (attempt(Mode.First()) != 42 || drops() != 1 || drop_sum() != 20) return 1;
	if (attempt(Mode.Last()) != 42 || drops() != 2 || drop_sum() != 62) return 2;
	return 42;
}
''', ITEM+MATCH_TAG+'''owned Item build(int value, bool fail) throws Error {
	var item = new Item(value);
	if (fail) { throw new Error("selected match failure"); }
	return move item;
}
owned Item acquire(Mode value) throws Error {
	match (value) {
		case Mode.First(): { return build(20, true); }
		case Mode.Middle(): { return build(999, false); }
		case Mode.Last(): { return build(42, false); }
	}
}
int attempt(Mode value) {
	try { var item = acquire(value); return item.value; }
	catch (Error error) { return 42; }
}
int main() {
	if (attempt(Mode.First()) != 42 || drops() != 1 || drop_sum() != 20) return 1;
	if (attempt(Mode.Last()) != 42 || drops() != 2 || drop_sum() != 62) return 2;
	return 42;
}
''', True),
	('match-payload-alignment', '''enum Payload { Data(bool enabled, u8 small, i64 wide, f64 real), Empty }
int inspect(Payload value) => match (value) {
	case Payload.Data(enabled, small, wide, real) => enabled && small == 2 && wide == 9223372036854775807 && real == 40.0d ? 42 : 1;
	case Payload.Empty() => 0;
};
Payload relay(Payload value) { return value; }
int main() { return inspect(relay(Payload.Data(true, 2, 9223372036854775807, 40.0d))); }
''', '''enum Payload { Data(bool enabled, u8 small, i64 wide, f64 real), Empty }
int inspect(Payload value) {
	match (value) {
		case Payload.Data(enabled, small, wide, real): {
			if (enabled && small == 2 && wide == 9223372036854775807 && real == 40.0d) return 42;
			return 1;
		}
		case Payload.Empty(): { return 0; }
	}
}
Payload relay(Payload value) { return value; }
int main() { return inspect(relay(Payload.Data(true, 2, 9223372036854775807, 40.0d))); }
''', False),
	('match-enum-product', '''enum Bit { Off, On }
enum Both { Pair(Bit left, Bit right) }
int inspect(Both value) => match (value) {
	case Both.Pair(right=Bit.On(), left=Bit.Off()) => 1;
	case Both.Pair(Bit.Off(), Bit.Off()) => 0;
	case Both.Pair(Bit.On(), Bit.Off()) => 2;
	case Both.Pair(Bit.On(), Bit.On()) => 3;
};
int main() {
	if (inspect(Both.Pair(Bit.Off(), Bit.On())) != 1 || inspect(Both.Pair(Bit.Off(), Bit.Off())) != 0 || inspect(Both.Pair(Bit.On(), Bit.Off())) != 2 || inspect(Both.Pair(Bit.On(), Bit.On())) != 3) return 4;
	return 42;
}
''', '''enum Bit { Off, On }
enum Both { Pair(Bit left, Bit right) }
int inspect(Both value) {
	match (value) {
		case Both.Pair(left, right): {
			match (left) {
				case Bit.Off(): { match (right) { case Bit.Off(): { return 0; } case Bit.On(): { return 1; } } }
				case Bit.On(): { match (right) { case Bit.Off(): { return 2; } case Bit.On(): { return 3; } } }
			}
		}
	}
}
int main() {
	if (inspect(Both.Pair(Bit.Off(), Bit.On())) != 1 || inspect(Both.Pair(Bit.Off(), Bit.Off())) != 0 || inspect(Both.Pair(Bit.On(), Bit.Off())) != 2 || inspect(Both.Pair(Bit.On(), Bit.On())) != 3) return 4;
	return 42;
}
''', False),
	('match-nested-payload', NESTED_TAG+'''int status(Result value) => match (value) {
	case Result.Success(result) => result;
	case Result.Failure(Problem.NotFound()) => 1;
	case Result.Failure(Problem.Decode(code)) => code+2;
};
int main() {
	if (status(Result.Success(20)) != 20 || status(Result.Failure(Problem.NotFound())) != 1) return 3;
	return status(Result.Failure(Problem.Decode(40)));
}
''', NESTED_TAG+'''int status(Result value) {
	match (value) {
		case Result.Success(result): { return result; }
		case Result.Failure(problem): {
			match (problem) {
				case Problem.NotFound(): { return 1; }
				case Problem.Decode(code): { return code+2; }
			}
		}
	}
}
int main() {
	if (status(Result.Success(20)) != 20 || status(Result.Failure(Problem.NotFound())) != 1) return 3;
	return status(Result.Failure(Problem.Decode(40)));
}
''', False),
	('match-three-way', MATCH_TAG+'''int status(Mode value) => match (value) {
	case Mode.Last() => 42;
	case Mode.First() => 20;
	case Mode.Middle() => 22;
};
int main() { if (status(Mode.First()) != 20 || status(Mode.Middle()) != 22) return 1; return status(Mode.Last()); }
''', MATCH_TAG+'''int status(Mode value) {
	match (value) {
		case Mode.Last(): { return 42; }
		case Mode.First(): { return 20; }
		case Mode.Middle(): { return 22; }
	}
}
int main() { if (status(Mode.First()) != 20 || status(Mode.Middle()) != 22) return 1; return status(Mode.Last()); }
''', False),
	('match-single-scrutinee', TICKS+MATCH_TAG+'''Mode input() { int ignored = tick(1); return Mode.Middle(); }
int main() {
	reset_trace();
	int result = match (input()) {
		case Mode.First() => tick(3);
		case Mode.Middle() => tick(2)+40;
		case Mode.Last() => tick(4);
	};
	if (trace() != 12) return 1;
	return result;
}
''', TICKS+MATCH_TAG+'''Mode input() { int ignored = tick(1); return Mode.Middle(); }
int main() {
	reset_trace();
	int result = 0;
	match (input()) {
		case Mode.First(): { result = tick(3); }
		case Mode.Middle(): { result = tick(2)+40; }
		case Mode.Last(): { result = tick(4); }
	}
	if (trace() != 12) return 1;
	return result;
}
''', False),
	('match-owned-result', ITEM+MATCH_TAG+'''owned Item make(Mode value) {
	return match (value) {
		case Mode.First() => new Item(20);
		case Mode.Middle() => new Item(22);
		case Mode.Last() => new Item(42);
	};
}
int run() { var item = make(Mode.Last()); return item.value; }
int main() { if (run() != 42 || drops() != 1 || drop_sum() != 42) return 1; return 42; }
''', ITEM+MATCH_TAG+'''owned Item make(Mode value) {
	match (value) {
		case Mode.First(): { var item = new Item(20); return move item; }
		case Mode.Middle(): { var item = new Item(22); return move item; }
		case Mode.Last(): { var item = new Item(42); return move item; }
	}
}
int run() { var item = make(Mode.Last()); return item.value; }
int main() { if (run() != 42 || drops() != 1 || drop_sum() != 42) return 1; return 42; }
''', False),
]
MATCH_NEGATIVE = [
	# Text joins require an outlives proof beyond the bounded copy/owner subset.
	('match-borrowed-text-result', MATCH_TAG+'string name(Mode value) => match (value) { case Mode.First() => "first"; case Mode.Middle() => "middle"; case Mode.Last() => "last"; }; int main() { return 42; }'),
	('match-destination-moved', 'enum E { First, Last } class Box { int value; init() { this.value = 0; } } int consume(owned Box box) { return 42; } int main() { var box = new Box(); box.value = match (E.First()) { case E.First() => consume(move box); case E.Last() => 42; }; return 42; }'),
	('match-owner-alias', ITEM+'enum E { Only } Item choose(owned Item value) { return match (E.Only()) { case E.Only() => value; }; } int main() { var item = choose(new Item(42)); return item.value; }'),
	('match-payload-label', 'enum Pair { Data(int first, int second) } int main() { return match (Pair.Data(20,22)) { case Pair.Data(first=a, missing=b) => a+b; }; }'),
	('match-payload-duplicate-label', 'enum Pair { Data(int first, int second) } int main() { return match (Pair.Data(20,22)) { case Pair.Data(first=a, first=b) => a+b; }; }'),
	('match-inspection-move', OWNING_TAG+'owned int[] take(Packet value) { return match (value) { case Packet.Empty() => new int[0]; case Packet.Data(data, count) => move data; }; } int main() { return 42; }'),
	('match-consumed-use', OWNING_TAG+'int main() { var state = Packet.Data(new int[13], 13); int result = match (move state) { case Packet.Empty() => 0; case Packet.Data(data, count) => len(data); }; return match (state) { case Packet.Empty() => 0; case Packet.Data(data, count) => result+count; }; }'),
	('match-payload-double-move', OWNING_TAG+'int eat(owned int[] first, owned int[] second) { return len(first)+len(second); } int main() { var state = Packet.Data(new int[13], 13); return match (move state) { case Packet.Empty() => 0; case Packet.Data(data, count) => eat(move data, move data); }; }'),
	('match-payload-borrow-escape', OWNING_TAG+'int[] inspect(Packet value) { return match (value) { case Packet.Empty() => new int[0]; case Packet.Data(data, count) => data; }; } int main() { return 42; }'),
	('match-constructor-uninitialized', 'enum E { Data(int value) } class Box { int value; init() { this.value = match (E.Data(this.value)) { case E.Data(value) => value; }; } } int main() { var box = new Box(); return box.value; }'),
	('match-nested-missing', NESTED_TAG+'int main() { return match (Result.Success(42)) { case Result.Success(value) => value; case Result.Failure(Problem.NotFound()) => 1; }; }'),
	('match-nested-overlap', NESTED_TAG+'int main() { return match (Result.Success(42)) { case Result.Success(value) => value; case Result.Failure(problem) => 1; case Result.Failure(Problem.Decode(code)) => code; }; }'),
	('match-nested-wrong-payload', NESTED_TAG+'int main() { return match (Result.Success(42)) { case Result.Success(Problem.NotFound()) => 1; case Result.Failure(problem) => 2; }; }'),
	('match-payload-scope', NESTED_TAG+'int main() { int answer = match (Result.Success(42)) { case Result.Success(value) => value; case Result.Failure(problem) => 2; }; return value; }'),
	('match-nonexhaustive', MATCH_TAG+'int main() { return match (Mode.First()) { case Mode.First() => 42; case Mode.Last() => 3; }; }'),
	('match-overlap', MATCH_TAG+'int main() { return match (Mode.First()) { case Mode.First() => 42; case Mode.First() => 3; case Mode.Last() => 4; }; }'),
	('match-result-type', MATCH_TAG+'int main() { return match (Mode.First()) { case Mode.First() => 42; case Mode.Middle() => true; case Mode.Last() => 3; }; }'),
	('match-foreign-variant', MATCH_TAG+'enum Other { First } int main() { return match (Mode.First()) { case Other.First() => 42; case Mode.Middle() => 2; case Mode.Last() => 3; }; }'),
	('match-borrow-escape', ITEM+MATCH_TAG+'Item choose(Mode value, Item item) { return match (value) { case Mode.First() => item; case Mode.Middle() => item; case Mode.Last() => item; }; } int main() { return 42; }'),
]


BOUNDS = '''struct Bounds { int start; int end; bool inclusive; }
Bounds interval(int first, int last) { Bounds result = {start = first, end = last, inclusive = true}; return result; }
int measure(Bounds value) { return value.end-value.start; }
'''
RANGE_CASES = [
	('range-collect-literal', '''extern(C) int allocation_calls();
extern(C) int allocation_bytes();
int main() {
	var values = (20..=80).step_by(5).collect_array();
	if (len(values) != 13 || allocation_calls() != 1 || allocation_bytes() != 52) return 1;
	int at = 0; int total = 0;
	while (at < len(values)) { if (values[at] != 20+at*5) return 2; total = total+values[at]; at = at+1; }
	if (total != 650) return 3; return 42;
}
''', '''extern(C) int allocation_calls();
extern(C) int allocation_bytes();
int main() {
	owned int[] values = new int[13]; int at = 0; int current = 20;
	while (at < 13) { values[at] = current; at = at+1; if (at < 13) current = current+5; }
	if (len(values) != 13 || allocation_calls() != 1 || allocation_bytes() != 52) return 1;
	at = 0; int total = 0;
	while (at < len(values)) { if (values[at] != 20+at*5) return 2; total = total+values[at]; at = at+1; }
	if (total != 650) return 3; return 42;
}
''', False),
	('range-collect-named', TICKS+'''extern(C) int allocation_calls();
extern(C) int allocation_bytes();
int main() {
	reset_trace(); var interval = tick(1)+19..=tick(2)+78; var sequence = interval.step_by(tick(3)+2);
	var data = sequence.collect_array();
	if (trace() != 123 || len(data) != 13 || allocation_calls() != 1 || allocation_bytes() != 52) return 1;
	int at = 0; int total = 0;
	while (at < len(data)) { if (data[at] != 20+at*5) return 2; total = total+data[at]; at = at+1; }
	int count = 0; int iterated = 0;
	foreach (var item in sequence) { count = count+1; iterated = iterated+item; }
	if (total != 650 || data[0] != 20 || data[12] != 80 || count != 13 || iterated != 650 || allocation_calls() != 1) return 3;
	return 42;
}
''', TICKS+'''extern(C) int allocation_calls();
extern(C) int allocation_bytes();
int main() {
	reset_trace(); int first = tick(1)+19; int end = tick(2)+78; int step = tick(3)+2;
	owned int[] data = new int[13]; int at = 0;
	while (at < 13) { data[at] = first+at*step; at = at+1; }
	if (trace() != 123 || len(data) != 13 || allocation_calls() != 1 || allocation_bytes() != 52) return 1;
	at = 0; int total = 0;
	while (at < len(data)) { if (data[at] != 20+at*5) return 2; total = total+data[at]; at = at+1; }
	int count = 0; int iterated = 0; int item = first;
	while (item <= end) { count = count+1; iterated = iterated+item; if (item == end || end-item < step) break; item = item+step; }
	if (total != 650 || data[0] != 20 || data[12] != 80 || count != 13 || iterated != 650 || allocation_calls() != 1) return 3;
	return 42;
}
''', False),
	('range-fixed', '''extern(C) int allocation_calls();
int main() {
	int[13] values = (20..=80).step_by(5).collect_fixed(); int total = 0; int at = 0;
	while (at < len(values)) { if (values[at] != 20+at*5) return 1; total = total+values[at]; at = at+1; }
	int[5] crossed = (-10..=10).step_by(5).collect_fixed();
	if (crossed[0] != -10 || crossed[2] != 0 || crossed[4] != 10) return 2;
	int[2] odd = (50..=80).step_by(16).collect_fixed(); if (odd[0] != 50 || odd[1] != 66) return 3;
	i64[3] wide = ((-2 as i64)..=(2 as i64)).step_by(2 as i64).collect_fixed();
	if (wide[0] != -2 || wide[1] != 0 || wide[2] != 2 || total != 650 || allocation_calls() != 0) return 4;
	return 42;
}
''', '''extern(C) int allocation_calls();
int main() {
	int[13] values = {20,25,30,35,40,45,50,55,60,65,70,75,80}; int total = 0; int at = 0;
	while (at < len(values)) { if (values[at] != 20+at*5) return 1; total = total+values[at]; at = at+1; }
	int[5] crossed = {-10,-5,0,5,10};
	if (crossed[0] != -10 || crossed[2] != 0 || crossed[4] != 10) return 2;
	int[2] odd = {50,66}; if (odd[0] != 50 || odd[1] != 66) return 3;
	i64[3] wide = {-2,0,2};
	if (wide[0] != -2 || wide[1] != 0 || wide[2] != 2 || total != 650 || allocation_calls() != 0) return 4;
	return 42;
}
''', False),
	('range-collect', TICKS+'''extern(C) int allocation_calls();
extern(C) int allocation_bytes();
owned int[] values() { return (tick(1)+19..=tick(2)+78).step_by(tick(3)+2).collect_array(); }
int main() {
	reset_trace(); var data = values();
	if (trace() != 123 || len(data) != 13 || allocation_calls() != 1 || allocation_bytes() != 52) return 1;
	int index = 0; int total = 0;
	while (index < len(data)) { if (data[index] != 20+index*5) return 2; total = total+data[index]; index = index+1; }
	if (total != 650 || data[0] != 20 || data[12] != 80) return 3;
	var vacant = (20..20).collect_array(); if (len(vacant) != 0 || allocation_calls() != 1) return 4;
	u64 last = 18446744073709551615; var edge = (last..=last).collect_array();
	if (len(edge) != 1 || edge[0] != last || allocation_calls() != 2 || allocation_bytes() != 60) return 5;
	i64 first = -2; i64 end = 2; i64 step = 2; var crossed = (first..=end).step_by(step).collect_array();
	if (len(crossed) != 3 || crossed[0] != first || crossed[1] != 0 || crossed[2] != end) return 6;
	u8 zero = 0; u8 maximum = 255; var complete = (zero..=maximum).collect_array();
	if (len(complete) != 256 || complete[0] != zero || complete[255] != maximum) return 7;
	data = (20..=80).step_by(5).collect_array(); if (len(data) != 13 || data[12] != 80) return 8;
	return 42;
}
''', TICKS+'''extern(C) int allocation_calls();
extern(C) int allocation_bytes();
owned int[] values() {
	int first = tick(1)+19; int last = tick(2)+78; int step = tick(3)+2;
	owned int[] result = new int[13]; int index = 0;
	while (index < 13) { result[index] = first+index*step; index = index+1; }
	return move result;
}
int main() {
	reset_trace(); var data = values();
	if (trace() != 123 || len(data) != 13 || allocation_calls() != 1 || allocation_bytes() != 52) return 1;
	int index = 0; int total = 0;
	while (index < len(data)) { if (data[index] != 20+index*5) return 2; total = total+data[index]; index = index+1; }
	if (total != 650 || data[0] != 20 || data[12] != 80) return 3;
	owned int[] vacant = new int[0]; if (len(vacant) != 0 || allocation_calls() != 1) return 4;
	u64 last = 18446744073709551615; owned u64[] edge = new u64[1]; edge[0] = last;
	if (len(edge) != 1 || edge[0] != last || allocation_calls() != 2 || allocation_bytes() != 60) return 5;
	i64 first = -2; i64 end = 2; i64 step = 2; owned i64[] crossed = new i64[3]; index = 0;
	while (index < 3) { crossed[index] = first+(index as i64)*step; index = index+1; }
	if (len(crossed) != 3 || crossed[0] != first || crossed[1] != 0 || crossed[2] != end) return 6;
	u8 zero = 0; u8 maximum = 255; owned u8[] complete = new u8[256]; index = 0;
	while (index < 256) { complete[index] = index as u8; index = index+1; }
	if (len(complete) != 256 || complete[0] != zero || complete[255] != maximum) return 7;
	data = values(); if (len(data) != 13 || data[12] != 80) return 8;
	return 42;
}
''', False),
	('range-slices', TICKS+'''int read(borrowed int[] values) { return len(values)+values[0]; }
int main() {
	owned int[] data = new int[13]; data[0] = 20; data[12] = 22;
	if (len(data[0..13]) != 13 || data[0..1][0] != 20 || read(data[12..13]) != 23 || len(data[0..13][1..12]) != 11 || len(data[13..13]) != 0) return 1;
	reset_trace(); if (len(data[tick(1)..tick(3)]) != 2 || trace() != 13) return 2;
	owned int[] empty = new int[0]; if (len(empty[0..0]) != 0) return 3;
	int[4] fixed = {20,21,22,23}; if (read(fixed[2..3]) != 23 || len(fixed[4..4]) != 0) return 4;
	return 42;
}
''', TICKS+'''int extent(borrowed int[] values, int first, int end) { if (first < 0 || end < first || end > len(values)) return -1; return end-first; }
int read(borrowed int[] values, int first, int end) { if (first < 0 || end <= first || end > len(values)) return -1; return end-first+values[first]; }
int fixed_read(borrowed int[] values) { return len(values)+values[0]; }
int main() {
	owned int[] data = new int[13]; data[0] = 20; data[12] = 22;
	if (extent(data,0,13) != 13 || data[0] != 20 || read(data,12,13) != 23 || extent(data,1,12) != 11 || extent(data,13,13) != 0) return 1;
	reset_trace(); int first = tick(1); int end = tick(3); if (extent(data,first,end) != 2 || trace() != 13) return 2;
	owned int[] empty = new int[0]; if (extent(empty,0,0) != 0) return 3;
	int[4] fixed = {20,21,22,23}; if (fixed_read(slice(fixed,2,1)) != 23 || len(slice(fixed,4,0)) != 0) return 4;
	return 42;
}
''', False),
	('range-stride', TICKS+'''RangeSequence<int> interval(int first, int last, int stride) { return (first..=last).step_by(stride); }
int total(RangeSequence<int> sequence) { int sum = 0; foreach (var item in sequence) { sum = sum+item; } return sum; }
int main() {
	reset_trace(); var sequence = ((tick(1)+19)..=(tick(2)+78)).step_by(tick(3)+2);
	int count = 0; int first = 0; int last = 0;
	foreach (var item in sequence) { if (count == 0) first = item; last = item; count = count+1; }
	if (count != 13 || first != 20 || last != 80 || total(sequence) != 650 || trace() != 123) return 1;
	if (total(interval(20,80,5)) != 650) return 2;
	u64 limit = 18446744073709551615; u64 begin = limit-6; u64 stride = 4;
	int near = 0; foreach (var item in (begin..=limit).step_by(stride)) { if (near == 0 && item != begin || near == 1 && item != limit-2) return 3; near = near+1; }
	if (near != 2) return 4;
	int minimum = -2147483648; int maximum = 2147483647; int crossing = 0;
	foreach (var item in (minimum..=maximum).step_by(maximum)) { if (crossing == 0 && item != minimum || crossing == 1 && item != -1 || crossing == 2 && item != maximum-1) return 5; crossing = crossing+1; }
	if (crossing != 3) return 6;
	return 42;
}
''', TICKS+'''struct Sequence { int first; int last; bool inclusive; int stride; }
Sequence interval(int first, int last, int stride) { Sequence result = {first = first, last = last, inclusive = true, stride = stride}; return result; }
int total(Sequence sequence) { int sum = 0; int item = sequence.first; while (item <= sequence.last) { sum = sum+item; if (item == sequence.last || (sequence.last as u32)-(item as u32) < sequence.stride as u32) break; item = item+sequence.stride; } return sum; }
int main() {
	reset_trace(); int begin = tick(1)+19; int end = tick(2)+78; int stride = tick(3)+2; var sequence = interval(begin,end,stride);
	int count = 0; int first = 0; int last = 0; int item = sequence.first;
	while (item <= sequence.last) { if (count == 0) first = item; last = item; count = count+1; if (item == sequence.last || sequence.last-item < sequence.stride) break; item = item+sequence.stride; }
	if (count != 13 || first != 20 || last != 80 || total(sequence) != 650 || trace() != 123) return 1;
	if (total(interval(20,80,5)) != 650) return 2;
	u64 limit = 18446744073709551615; u64 start = limit-6; u64 step = 4; u64 current = start;
	int near = 0; while (current <= limit) { if (near == 0 && current != start || near == 1 && current != limit-2) return 3; near = near+1; if (current == limit || limit-current < step) break; current = current+step; }
	if (near != 2) return 4;
	int minimum = -2147483648; int maximum = 2147483647; int crossing = 0; item = minimum;
	while (item <= maximum) { if (crossing == 0 && item != minimum || crossing == 1 && item != -1 || crossing == 2 && item != maximum-1) return 5; crossing = crossing+1; if (item == maximum || (maximum as u32)-(item as u32) < maximum as u32) break; item = item+maximum; }
	if (crossing != 3) return 6;
	return 42;
}
''', False),
	('range-foreach', TICKS+'''int main() {
	reset_trace(); int total = 0;
	foreach (var item in tick(2)..=tick(4)) { total = total+item; }
	if (total != 9 || trace() != 24) return 1;
	int selected = 0;
	foreach (var item in 0..10) { if (item == 2) continue; if (item == 8) break; selected = selected+item; }
	if (selected != 26) return 2;
	int nested = 0; foreach (var left in 0..3) { foreach (var right in 0..2) { nested = nested+1; } }
	if (nested != 6) return 3;
	int empty = 0; foreach (var item in 80..20) { empty = empty+1; } foreach (var item in 20..20) { empty = empty+1; }
	if (empty != 0) return 4;
	i64 last = 9223372036854775807; int count = 0;
	foreach (var item in last..=last) { if (item != last) return 5; count = count+1; }
	u64 unsigned_last = 18446744073709551615;
	foreach (var item in unsigned_last..=unsigned_last) { if (item != unsigned_last) return 6; count = count+1; }
	foreach (var item in -2..=2) { count = count+1; }
	if (count != 7) return 7;
	return 42;
}
''', TICKS+'''int main() {
	reset_trace(); int first = tick(2); int last = tick(4); int total = 0; int item = first;
	while (item <= last) { total = total+item; if (item == last) break; item = item+1; }
	if (total != 9 || trace() != 24) return 1;
	int selected = 0; item = 0;
	while (item < 10) { int value = item; item = item+1; if (value == 2) continue; if (value == 8) break; selected = selected+value; }
	if (selected != 26) return 2;
	int nested = 0; int left = 0; while (left < 3) { int right = 0; while (right < 2) { nested = nested+1; right = right+1; } left = left+1; }
	if (nested != 6) return 3;
	int empty = 0; item = 80; while (item < 20) { empty = empty+1; item = item+1; } item = 20; while (item < 20) { empty = empty+1; item = item+1; }
	if (empty != 0) return 4;
	i64 limit = 9223372036854775807; i64 current = limit; int count = 0;
	while (current <= limit) { if (current != limit) return 5; count = count+1; if (current == limit) break; current = current+1; }
	u64 unsigned_limit = 18446744073709551615; u64 unsigned_current = unsigned_limit;
	while (unsigned_current <= unsigned_limit) { if (unsigned_current != unsigned_limit) return 6; count = count+1; if (unsigned_current == unsigned_limit) break; unsigned_current = unsigned_current+1; }
	item = -2; while (item <= 2) { count = count+1; if (item == 2) break; item = item+1; }
	if (count != 7) return 7;
	return 42;
}
''', False),
	('range-bounds', TICKS+'''Range<int> interval(int first, int last) { return first..=last; }
int measure(Range<int> value) { return value.end-value.start; }
int main() {
	reset_trace(); var values = tick(2)..=tick(4);
	if (trace() != 24 || values.start != 2 || values.end != 4) return 1;
	var copied = values; values = interval(20,62);
	if (copied.start != 2 || copied.end != 4 || measure(values) != 42) return 2;
	if ((20..62).end != 62 || (20..=62).start != 20) return 3;
	return 42;
}
''', TICKS+BOUNDS+'''int main() {
	reset_trace(); int first = tick(2); int last = tick(4);
	Bounds values = {start = first, end = last, inclusive = true};
	if (trace() != 24 || values.start != 2 || values.end != 4) return 1;
	var copied = values; values = interval(20,62);
	if (copied.start != 2 || copied.end != 4 || measure(values) != 42) return 2;
	return 42;
}
''', False),
	('range-domains', '''bool member(int start, int end, int item) { return (start..=end).contains(item); }
int main() {
	var half = 20..80; var closed = 20..=80; var empty = 20..20; var singleton = 20..=20; var reversed = 80..20;
	if (half.is_empty() || closed.is_empty() || !empty.is_empty() || singleton.is_empty() || !reversed.is_empty()) return 1;
	if (half.contains(80) || !closed.contains(80) || !singleton.contains(20) || reversed.contains(40)) return 2;
	if (!member(-20,22,0) || member(-20,22,23)) return 3;
	i64 minimum = -9223372036854775808; i64 maximum = 9223372036854775807;
	var whole = minimum..=maximum;
	if (whole.is_empty() || !whole.contains(minimum) || !whole.contains(maximum)) return 4;
	u64 zero = 0; u64 last = 18446744073709551615;
	var unsigned = zero..=last; var final = last..=last; var absent = last..last;
	if (unsigned.is_empty() || !unsigned.contains(last) || final.is_empty() || !final.contains(last) || !absent.is_empty() || absent.contains(last)) return 5;
	return 42;
}
''', '''bool member(int start, int end, int item) { return item >= start && item <= end; }
int main() {
	int first = 20; int last = 80;
	if (first >= last || first > last || first < first || first > first || last < first) return 1;
	if (last < last || !(last <= last) || !(first >= first && first <= first) || last <= 40 && 40 < first) return 2;
	if (!member(-20,22,0) || member(-20,22,23)) return 3;
	i64 minimum = -9223372036854775808; i64 maximum = 9223372036854775807;
	if (minimum > maximum || !(minimum >= minimum && minimum <= maximum) || !(maximum >= minimum && maximum <= maximum)) return 4;
	u64 zero = 0; u64 limit = 18446744073709551615;
	if (zero > limit || !(limit >= zero && limit <= limit) || limit > limit || !(limit >= limit && limit <= limit) || limit < limit || limit < limit) return 5;
	return 42;
}
''', False),
]
RANGE_CASES.extend([
	('lazy-capture-order', TICKS+'''extern(C) int allocation_calls();
int main() {
	reset_trace(); int bias = 3;
	var values = (0..5).map(i => tick(i+1)+bias).filter(x => tick(x)>5).map(x => x*x);
	bias = 100;
	if (trace() != 0 || allocation_calls() != 0) return 1;
	if (values.sum() != 149 || trace() != 1425364758 || allocation_calls() != 0) return 2;
	reset_trace();
	if (values.sum() != 149 || trace() != 1425364758 || allocation_calls() != 0) return 3;
	return 42;
}
''', TICKS+'''extern(C) int allocation_calls();
int main() {
	reset_trace(); int bias = 3; int captured = bias; bias = 100;
	if (trace() != 0 || allocation_calls() != 0) return 1;
	int pass = 0;
	while (pass < 2) {
		reset_trace(); int total = 0; int i = 0;
		while (i < 5) { int mapped = tick(i+1)+captured; bool accepted = tick(mapped)>5; if (accepted) total = total+mapped*mapped; i = i+1; }
		if (total != 149 || trace() != 1425364758 || allocation_calls() != 0) return 2;
		pass = pass+1;
	}
	return 42;
}
''', False),
	('lazy-borrowed-array', TICKS+'''extern(C) int allocation_calls();
extern(C) int allocation_bytes();
int reduce(borrowed int[] data) { return data.iter().filter(x => tick(x+3)>3).map(x => x*x).sum(); }
int main() {
	var data = new int[6]; int at = 0; while (at < 6) { data[at] = at-2; at = at+1; }
	var deferred = data.iter().filter(x => tick(x+3)>3).map(x => x*x);
	data[5] = 4; if (trace() != 0) return 1;
	if (deferred.sum() != 21 || trace() != 123457 || allocation_calls() != 1 || allocation_bytes() != 24) return 2;
	reset_trace(); if (reduce(data) != 21 || trace() != 123457 || allocation_calls() != 1) return 3;
	return 42;
}
''', TICKS+'''extern(C) int allocation_calls();
extern(C) int allocation_bytes();
int reduce(borrowed int[] data) {
	int total = 0; int at = 0; while (at < len(data)) { int value = data[at]; if (tick(value+3)>3) total = total+value*value; at = at+1; } return total;
}
int main() {
	var data = new int[6]; int at = 0; while (at < 6) { data[at] = at-2; at = at+1; }
	data[5] = 4; if (trace() != 0) return 1;
	if (reduce(data) != 21 || trace() != 123457 || allocation_calls() != 1 || allocation_bytes() != 24) return 2;
	reset_trace(); if (reduce(data) != 21 || trace() != 123457 || allocation_calls() != 1) return 3; return 42;
}
''', False),
	('lazy-width-and-float', '''extern(C) int allocation_calls();
int main() {
	i8 first = -128; i8 last = 127; if ((first..=last).step_by(127).map(x => x).sum() != (-3 as i8)) return 1;
	u64 top = 18446744073709551615; u64 bottom = top-10;
	if ((bottom..=top).step_by(5).map(x => x as u8).sum() != (238 as u8)) return 2;
	if ((0..3).map(i => i==0 ? 16777216.0f : i==1 ? 1.0f : -16777216.0f).sum() != 0.0f) return 3;
	if ((0..5).map(i => (i as f64)*0.5d).filter(x => x>=1.0d).sum() != 4.5d) return 4;
	if (allocation_calls() != 0) return 5; return 42;
}
''', '''extern(C) int allocation_calls();
int main() {
	i8 current = -128; i8 small = 0; int at = 0;
	while (at < 3) { small = small+current; at = at+1; if (at < 3) current = current+127; }
	if (small != -3) return 1;
	u8 narrow = 0; u64 top = 18446744073709551615; u64 value = top-10; at = 0;
	while (at < 3) { narrow = narrow+(value as u8); at = at+1; if (at < 3) value = value+5; }
	if (narrow != 238) return 2;
	f32 rounded = 0.0f; rounded = rounded+16777216.0f; rounded = rounded+1.0f; rounded = rounded-16777216.0f;
	if (rounded != 0.0f) return 3;
	f64 total = 0.0d; at = 0; while (at < 5) { f64 item = (at as f64)*0.5d; if (item>=1.0d) total = total+item; at = at+1; }
	if (total != 4.5d || allocation_calls() != 0) return 4; return 42;
}
''', False),
	('lazy-callback-cleanup', TICKS+ITEM+'''int probe(int value) throws Error {
	int ignored = tick(value+1); if (value == 2) { throw new Error("callback stop"); } return value;
}
int main() {
	reset_trace(); var deferred = (0..5).map(i => probe(i)); if (trace() != 0) return 1;
	try { var item = new Item(42); int value = deferred.sum(); return 2; }
	catch (Error error) { if (trace() == 123 && drops() == 1 && drop_sum() == 42) return 42; } return 3;
}
''', TICKS+ITEM+'''int probe(int value) throws Error {
	int ignored = tick(value+1); if (value == 2) { throw new Error("callback stop"); } return value;
}
int main() {
	reset_trace(); if (trace() != 0) return 1;
	try { var item = new Item(42); int total = 0; int i = 0; while (i < 5) { total = total+probe(i); i = i+1; } return 2; }
	catch (Error error) { if (trace() == 123 && drops() == 1 && drop_sum() == 42) return 42; } return 3;
}
''', True),
])

# Class/generic copies use the same exact range and owner proof machinery.
RANGE_CASES.extend([
	('range-class-foreach', 'class StrideCounter { int offset; init(int offset) { this.offset = offset; } int total() { int result = this.offset; foreach (var value in (20..=80).step_by(5)) { result += value; } return result; } } int main() { var counter = new StrideCounter(-608); int observed = counter.total(); return observed; }\n', 'class StrideCounter { int offset; init(int offset) { this.offset = offset; } int total() { int result = this.offset; int value = 20; while (value <= 80) { result = result + value; value = value + 5; } return result; } } int main() { var counter = new StrideCounter(-608); int observed = counter.total(); return observed; }\n', False),
	('range-generic-foreach', 'int range_total<T>(T marker, int first, int last) { int result = 0; foreach (var value in (first..=last).step_by(5)) { result += value; } return result; } int main() { int observed = range_total<int>(0, 20, 80); return observed - 608; }\n', 'int range_total<T>(T marker, int first, int last) { int result = 0; int value = first; while (value <= last) { result = result + value; value = value + 5; } return result; } int main() { int observed = range_total<int>(0, 20, 80); return observed - 608; }\n', False),
	('range-nested-class-foreach', 'class NestedCounter { int initial; init(int initial) { this.initial = initial; } int total() { int result = this.initial; foreach (var first in 0..3) { foreach (var last in 0..4) { if (last == 1) continue; if (last == 3) break; result += first + last; } } return result; } } int main() { var counter = new NestedCounter(30); int observed = counter.total(); return observed; }\n', 'class NestedCounter { int initial; init(int initial) { this.initial = initial; } int total() { int result = this.initial; int first = 0; while (first < 3) { int last = 0; while (last < 4) { if (last == 1) { last = last + 1; continue; } if (last == 3) break; result = result + first + last; last = last + 1; } first = first + 1; } return result; } } int main() { var counter = new NestedCounter(30); int observed = counter.total(); return observed; }\n', False),
	('range-generic-class-foreach', 'class Item { int value; init(int value) { this.value = value; } } class RangeHolder<T> where T : ExactHeapClass { owned T[slots] entries; init() { this.entries = new T[slots]; } int total(int first, int last) { int result = 0; foreach (var value in (first..=last).step_by(5)) { result += value; } return result; } } int main() { var holder = new RangeHolder<Item>(); int observed = holder.total(20, 80); return observed - 608; }\n', 'class Item { int value; init(int value) { this.value = value; } } class RangeHolder<T> where T : ExactHeapClass { owned T[slots] entries; init() { this.entries = new T[slots]; } int total(int first, int last) { int result = 0; int value = first; while (value <= last) { result = result + value; value = value + 5; } return result; } } int main() { var holder = new RangeHolder<Item>(); int observed = holder.total(20, 80); return observed - 608; }\n', False),
])

RANGE_NEGATIVE = [
	('range-class-foreach-write', 'class Counter { int initial; init(int initial) { this.initial = initial; } int total() { foreach (var value in 0..3) { value += 1; } return this.initial; } } int main() { var counter = new Counter(42); return counter.total(); }'),
	('range-class-foreach-escape', 'class Counter { int initial; init(int initial) { this.initial = initial; } int total() { foreach (var value in 0..3) { int copied = value; } return value; } } int main() { var counter = new Counter(42); return counter.total(); }'),
	('range-generic-foreach-write', 'int total<T>(T marker) { foreach (var value in 0..3) { value = value + 1; } return 42; } int main() { return total<int>(0); }'),
	('range-fixed-dynamic', 'int main() { int end = 80; int[13] values = (20..=end).step_by(5).collect_fixed(); return 42; }'),
	('range-fixed-count', 'int main() { int[12] values = (20..=80).step_by(5).collect_fixed(); return 42; }'),
	('range-fixed-implicit', 'int main() { var values = (20..=80).step_by(5).collect_fixed(); return 42; }'),
	('range-fixed-argument', 'int main() { int[13] values = (20..=80).step_by(5).collect_fixed(1); return 42; }'),
	('range-fixed-huge', 'int main() { int[1] values = (0..=18446744073709551615 as u64).collect_fixed(); return 42; }'),
	('range-collect-argument', 'int main() { var values = (20..80).collect_array(1); return 42; }'),
	('range-collect-borrow-escape', 'borrowed int[] values() { return (20..80).collect_array(); } int main() { return 42; }'),
	('range-collect-copy-owner', 'int main() { var values = (20..80).collect_array(); var copied = values; return 42; }'),
	('range-slice-retain', 'int main() { owned int[] data = new int[13]; var view = data[0..3]; return len(view)+39; }'),
	('range-slice-write', 'int main() { owned int[] data = new int[13]; data[0..3][0] = 42; return 42; }'),
	('range-slice-inclusive', 'int main() { owned int[] data = new int[13]; return len(data[0..=3]); }'),
	('range-slice-negative', 'int main() { owned int[] data = new int[13]; return len(data[-1..3]); }'),
	('range-slice-reversed', 'int main() { owned int[] data = new int[13]; return len(data[3..1]); }'),
	('range-slice-move-bound', 'int steal(owned int[] data) { return 3; } int main() { owned int[] data = new int[13]; return len(data[0..steal(move data)]); }'),
	('range-slice-move-consumer', 'int use(borrowed int[] view, owned int[] data) { return len(view)+len(data); } int main() { owned int[] data = new int[13]; return use(data[0..3],move data); }'),
	('range-slice-escape', 'borrowed int[] escape(owned int[] data) { return data[0..3]; } int main() { return 42; }'),
	('range-stride-zero', 'int main() { var sequence = (0..10).step_by(0); return 42; }'),
	('range-stride-negative', 'int main() { var sequence = (0..10).step_by(-1); return 42; }'),
	('range-stride-float', 'int main() { var sequence = (0..10).step_by(1.0); return 42; }'),
	('range-stride-label', 'int main() { var sequence = (0..10).step_by(stride: 1); return 42; }'),
	('range-foreach-address', 'int main() { foreach (var item in 0..3) { int* address = &item; } return 42; }'),
	('range-foreach-write', 'int main() { foreach (var item in 0..3) { item = 2; } return 42; }'),
	('range-foreach-escape', 'int main() { foreach (var item in 0..3) {} return item; }'),
	('range-mixed', 'int main() { var value = 0..true; return 42; }'),
	('range-float', 'int main() { var value = 0.0..1.0; return 42; }'),
	('range-type-float', 'int main() { Range<float> value = 0..1; return 42; }'),
	('range-property', 'int main() { var value = 0..1; return value.middle; }'),
	('range-query-arity', 'int main() { var value = 0..1; if (value.is_empty(0)) return 1; return 42; }'),
	('range-query-label', 'int main() { var value = 0..1; if (value.contains(item: 0)) return 1; return 42; }'),
	('range-query-type', 'int main() { var value = 0..1; if (value.contains(true)) return 1; return 42; }'),
	('range-owning', 'owned Range<int> interval() { return 0..1; } int main() { return 42; }'),
]


FORMAT_OBSERVE = '''extern(C) void format_allocation_mark();
extern(C) int format_allocations_since();
extern(C) f32 format_f32(int selector);
extern(C) f64 format_f64(int selector);
'''
COLLECTION_OBSERVE = '''extern(C) int allocation_calls();
extern(C) int allocation_bytes();
extern(C) int watched_frees();
extern(C) int visit(int value);
extern(C) int visits();
'''
COLLECTION_CASES = [
	('comprehension-squares', COLLECTION_OBSERVE+'''int main() {
	var values = [for (var i in 0..100) => visit(i*i)];
	if (len(values) != 100 || visits() != 100 || allocation_calls() != 1 || allocation_bytes() != 400) return 1;
	int at = 0; while (at < 100) { if (values[at] != at*at) return 2; at = at+1; }
	return 42;
}
''', COLLECTION_OBSERVE+'''int main() {
	owned int[] values = new int[100]; int at = 0;
	while (at < 100) { values[at] = visit(at*at); at = at+1; }
	if (len(values) != 100 || visits() != 100 || allocation_calls() != 1 || allocation_bytes() != 400) return 1;
	at = 0; while (at < 100) { if (values[at] != at*at) return 2; at = at+1; }
	return 42;
}
''', False),
	('collection-filter-order', COLLECTION_OBSERVE+TICKS+'''int main() {
	int bias = 3; reset_trace(); var pipeline = (0..5).map(i => tick(i+1)+bias).filter(x => tick(x)>5).map(y => y*y); bias = 100;
	if (trace() != 0 || allocation_calls() != 0) return 1;
	var values = pipeline.collect_array();
	if (len(values) != 3 || values[0] != 36 || values[1] != 49 || values[2] != 64 || trace() != 1425364758 || allocation_calls() != 1 || allocation_bytes() != 20) return 2;
	return 42;
}
''', COLLECTION_OBSERVE+TICKS+'''int main() {
	int bias = 3; reset_trace(); int captured = bias; bias = 100;
	if (trace() != 0 || allocation_calls() != 0) return 1;
	// C0's explicit storage oracle carries a separate logical used count.
	// The final buffer has source-count capacity, just as the new collector.
	owned int[] values = new int[5]; int used = 0; int at = 0;
	while (at < 5) { int mapped = tick(at+1)+captured; if (tick(mapped)>5) { values[used] = mapped*mapped; used = used+1; } at = at+1; }
	if (used != 3 || values[0] != 36 || values[1] != 49 || values[2] != 64 || trace() != 1425364758 || allocation_calls() != 1 || allocation_bytes() != 20) return 2;
	return 42;
}
''', False),
	('collection-scalar-widths', COLLECTION_OBSERVE+'''int main() {
	i8[3] input = {-128,0,127}; var narrow = input.iter().map(x => x+(1 as i8)).collect_array();
	if (len(narrow) != 3 || narrow[0] != -127 || narrow[1] != 1 || narrow[2] != -128) return 1;
	int[3] flags = {1,0,1}; var selected = flags.iter().map(bit => bit != 0).filter(flag => flag).collect_array(); if (len(selected) != 2 || !selected[0] || !selected[1]) return 2;
	f64[3] floats = {1.0d,2.0d,3.0d}; var squares = floats.iter().map(value => value*value).collect_array(); if (len(squares) != 3 || squares[0] != 1.0d || squares[1] != 4.0d || squares[2] != 9.0d) return 3;
	if (allocation_calls() != 3 || allocation_bytes() != 30) return 4;
	return 42;
}
''', COLLECTION_OBSERVE+'''int main() {
	i8[3] input = {-128,0,127}; owned i8[] narrow = new i8[3]; int at = 0; while (at < 3) { narrow[at] = input[at]+(1 as i8); at = at+1; }
	if (len(narrow) != 3 || narrow[0] != -127 || narrow[1] != 1 || narrow[2] != -128) return 1;
	// C0 rejects owned bool arrays; bytes provide an explicit one-byte
	// representation oracle with the same logical values and allocation cost.
	u8[3] flags = {1,0,1}; owned u8[] selected = new u8[3]; int used = 0; at = 0; while (at < 3) { if (flags[at] != 0) { selected[used] = flags[at]; used = used+1; } at = at+1; } if (used != 2 || selected[0] != 1 || selected[1] != 1) return 2;
	f64[3] floats = {1.0d,2.0d,3.0d}; owned f64[] squares = new f64[3]; at = 0; while (at < 3) { squares[at] = floats[at]*floats[at]; at = at+1; } if (len(squares) != 3 || squares[0] != 1.0d || squares[1] != 4.0d || squares[2] != 9.0d) return 3;
	if (allocation_calls() != 3 || allocation_bytes() != 30) return 4;
	return 42;
}
''', False),
	('collection-callback-retirement', COLLECTION_OBSERVE+TICKS+ITEM+'''int probe(int value) throws Error { int ignored = tick(value+1); if (value == 2) { throw new Error("collector stop"); } return value; }
int attempt(bool comprehension) {
	try {
		var item = new Item(42);
		if (comprehension) { var values = [for (var i in 0..13) => probe(i)]; return 1; }
		else { var values = (0..13).map(i => probe(i)).collect_array(); return 2; }
	} catch (Error error) { return 42; }
}
int main() {
	reset_trace(); if (attempt(false) != 42 || trace() != 123 || drops() != 1 || drop_sum() != 42 || watched_frees() != 1) return 3;
	reset_trace(); if (attempt(true) != 42 || trace() != 123 || drops() != 2 || drop_sum() != 84 || watched_frees() != 2) return 4;
	return 42;
}
''', COLLECTION_OBSERVE+TICKS+ITEM+'''int probe(int value) throws Error { int ignored = tick(value+1); if (value == 2) { throw new Error("collector stop"); } return value; }
int attempt(bool comprehension) {
	try { var item = new Item(42); owned int[] values = new int[13]; int at = 0; while (at < 13) { values[at] = probe(at); at = at+1; } return 1; }
	catch (Error error) { return 42; }
}
int main() {
	reset_trace(); if (attempt(false) != 42 || trace() != 123 || drops() != 1 || drop_sum() != 42 || watched_frees() != 1) return 3;
	reset_trace(); if (attempt(true) != 42 || trace() != 123 || drops() != 2 || drop_sum() != 84 || watched_frees() != 2) return 4;
	return 42;
}
''', True),
	('comprehension-owned-return', COLLECTION_OBSERVE+'''owned int[] make() { return [for (var i in (20..=80).step_by(5)) => i]; }
int main() {
	var values = make(); if (len(values) != 13 || allocation_calls() != 1 || allocation_bytes() != 52) return 1;
	int at = 0; while (at < 13) { if (values[at] != 20+at*5) return 2; at = at+1; }
	values = [for (var j in 0..13) => j+20];
	if (len(values) != 13 || values[0] != 20 || values[12] != 32 || allocation_calls() != 2 || allocation_bytes() != 104 || watched_frees() != 1) return 3;
	return 42;
}
''', COLLECTION_OBSERVE+'''owned int[] make() { owned int[] values = new int[13]; int at = 0; while (at < 13) { values[at] = 20+at*5; at = at+1; } return move values; }
owned int[] other() { owned int[] values = new int[13]; int at = 0; while (at < 13) { values[at] = at+20; at = at+1; } return move values; }
int main() {
	var values = make(); if (len(values) != 13 || allocation_calls() != 1 || allocation_bytes() != 52) return 1;
	int at = 0; while (at < 13) { if (values[at] != 20+at*5) return 2; at = at+1; }
	values = other();
	if (len(values) != 13 || values[0] != 20 || values[12] != 32 || allocation_calls() != 2 || allocation_bytes() != 104 || watched_frees() != 1) return 3;
	return 42;
}
''', False),
]
COLLECTION_NEGATIVE = [
	('comprehension-runtime-bound', 'int main() { int count = 13; var data = [for (var i in 0..count) => i]; return 42; }'),
	('comprehension-count-limit', 'int main() { var data = [for (var i in 0..1048577) => i]; return 42; }'),
	('comprehension-zero-stride', 'int main() { var data = [for (var i in (0..13).step_by(0)) => i]; return 42; }'),
	('comprehension-owned-element', 'class Item { init() {} } int main() { var data = [for (var i in 0..13) => new Item()]; return 42; }'),
	('comprehension-fixed-context', 'int main() { int[13] data = [for (var i in 0..13) => i]; return 42; }'),
	('comprehension-unqualified-filter', 'int main() { var data = [for (var i in 0..13) if (i>0) => i]; return 42; }'),
	('collection-callback-owner-move', 'int take(owned int[] data) { return len(data); } int main() { owned int[] data = new int[13]; var output = (0..13).map(i => take(move data)).collect_array(); return 42; }'),
	('collection-capture-owner-replacement', 'int main() { owned int[] data = new int[13]; var pipeline = data.iter().map(i => i+1); data = new int[13]; var result = pipeline.collect_array(); return 42; }'),
	('collection-lazy-escape', 'owned int[] bad() { owned int[] data = new int[13]; return data.iter().map(i => i+1); } int main() { return 42; }'),
	('collection-borrow-result', 'borrowed int[] bad() { return (0..13).map(i => i+1).collect_array(); } int main() { return 42; }'),
	('collection-copy-owner', 'int main() { var data = (0..13).map(i => i+1).collect_array(); var copy = data; return 42; }'),
]
NAMED_ENUM = 'enum Parcel { Data(owned int[] first, owned int[] second, int marker) }\n'
ENUM_MARKER = TICKS+'''int mark(bool fail) throws Error { int observed = tick(9); if (fail) { throw new Error("enum operand failure"); } return 22; }
'''
CASES.extend([
	('named-enum-order', TICKS+'''extern(C) int allocation_calls();
enum Pair { Data(int first, int last) }
int main() { reset_trace(); var pair = Pair.Data(last: tick(2), first: tick(4)); if (trace() != 24 || allocation_calls() != 0) return 1; return match (pair) { case Pair.Data(first,last) => first*10+last; }; }
''', TICKS+'''extern(C) int allocation_calls();
enum Pair { Data(int first, int last) }
int main() { reset_trace(); int last = tick(2); int first = tick(4); var pair = Pair.Data(first,last); if (trace() != 24 || allocation_calls() != 0) return 1; match (pair) { case Pair.Data(left,right): { return left*10+right; } } }
''', False),
	('named-enum-mixed-tail', '''enum Mixed { Data(int first, bool enabled, f64 real) }
int main() { var value = Mixed.Data(20, real: 22.0d, enabled: true); return match (value) { case Mixed.Data(first,enabled,real) => enabled && first == 20 && real == 22.0d ? 42 : 1; }; }
''', '''enum Mixed { Data(int first, bool enabled, f64 real) }
int main() { var value = Mixed.Data(20,true,22.0d); match (value) { case Mixed.Data(first,enabled,real): { if (enabled && first == 20 && real == 22.0d) return 42; return 1; } } }
''', False),
	('named-enum-fresh-abort', COLLECTION_OBSERVE+ENUM_MARKER+NAMED_ENUM+'''int main() { try { var value = Parcel.Data(second: new int[13], first: new int[7], marker: mark(true)); return 1; } catch (Error error) { if (trace() == 9 && watched_frees() == 1) return 42; return 2; } }
''', COLLECTION_OBSERVE+ENUM_MARKER+NAMED_ENUM+'''int main() { try { owned int[] second = new int[13]; owned int[] first = new int[7]; int marker = mark(true); var value = Parcel.Data(move first,move second,marker); return 1; } catch (Error error) { if (trace() == 9 && watched_frees() == 1) return 42; return 2; } }
''', True),
	('named-enum-reservation-abort', COLLECTION_OBSERVE+ENUM_MARKER+NAMED_ENUM+'''int attempt() {
	owned int[] first = new int[7]; owned int[] second = new int[13];
	try { var value = Parcel.Data(second: move second, first: move first, marker: mark(true)); return 1; }
	catch (Error error) { if (trace() == 9 && len(first) == 7 && len(second) == 13 && watched_frees() == 0) return 42; return 2; }
}
int main() { int result = attempt(); if (result == 42 && watched_frees() == 1) return 42; return 3; }
''', COLLECTION_OBSERVE+ENUM_MARKER+NAMED_ENUM+'''int attempt() {
	owned int[] first = new int[7]; owned int[] second = new int[13];
	try { int marker = mark(true); var value = Parcel.Data(move first,move second,marker); return 1; }
	catch (Error error) { if (trace() == 9 && len(first) == 7 && len(second) == 13 && watched_frees() == 0) return 42; return 2; }
}
int main() { int result = attempt(); if (result == 42 && watched_frees() == 1) return 42; return 3; }
''', True),
	('named-enum-owned-success', COLLECTION_OBSERVE+NAMED_ENUM+'''int main() { var parcel = Parcel.Data(second: new int[13], first: new int[7], marker: 22); owned int[] values = match (move parcel) { case Parcel.Data(first,_,marker) => move first; }; if (len(values) == 7 && watched_frees() == 1) return 42; return 1; }
''', COLLECTION_OBSERVE+NAMED_ENUM+'''owned int[] take(Parcel parcel) { match (move parcel) { case Parcel.Data(first,second,marker): { return move first; } } }
int main() { owned int[] second = new int[13]; owned int[] first = new int[7]; var parcel = Parcel.Data(move first,move second,22); owned int[] values = take(move parcel); if (len(values) == 7 && watched_frees() == 1) return 42; return 1; }
''', False),
])
NEGATIVE.extend([
	('enum-unknown-label', 'enum E { Data(int first,int last) } int main() { var value = E.Data(first: 20, missing: 22); return 42; }'),
	('enum-payload-wrong-type', 'enum E { Data(int first,bool ready) } int main() { var value = E.Data(ready: 20, first: true); return 42; }'),
	('enum-owned-copy', NAMED_ENUM+'int main() { owned int[] first = new int[7]; var value = Parcel.Data(second: new int[13], first: first, marker: 22); return 42; }'),
	('enum-positional-label-collision', 'enum E { Data(int first,int last) } int main() { var value = E.Data(20, first: 22); return 42; }'),
])

FORMAT_CASES = [
	('format-sink-scalars', FORMAT_OBSERVE+'''int main() {
		try {
			var builder = new Utf8ByteBuilder(); if (!builder.reserve(512)) return 1;
			i8 small = -128; u8 byte = 255; i16 short_value = -32768; u16 word = 65535;
			i64 low = -9223372036854775808; u64 high = 18446744073709551615; u32 full = 4294967295;
			f32 single = format_f32(1); f64 wide = format_f64(1);
			string fragment = "\\u00e9\\0";
			format_allocation_mark();
			if (!format_into(builder, $"{{{small},{byte},{short_value},{word},{-2147483648},{full},{low},{high},{true},{false},{single},{wide},{fragment}}}")) return 2;
			if (format_allocations_since() != 0) return 3;
			var message = builder.snapshot();
			if (message.text != "{-128,255,-32768,65535,-2147483648,4294967295,-9223372036854775808,18446744073709551615,true,false,-0x1.8p+0,0x1.0p+0,\\u00e9\\0}") return 4;
			return 42;
		} catch (Error error) { return 5; }
	}
''', FORMAT_OBSERVE+'''int main() {
		try {
			var builder = new Utf8ByteBuilder(); if (!builder.reserve(512)) return 1;
			format_allocation_mark();
			if (!builder.append_text("{") || !append_int(builder, -128) || !builder.append_text(",") || !append_u32(builder, 255) || !builder.append_text(",") || !append_int(builder, -32768) || !builder.append_text(",") || !append_u32(builder, 65535) || !builder.append_text(",") || !append_int(builder, -2147483648) || !builder.append_text(",") || !append_u32(builder, 4294967295) || !builder.append_text(",") || !append_i64(builder, -9223372036854775808) || !builder.append_text(",") || !append_u64(builder, 18446744073709551615) || !builder.append_text(",") || !append_bool(builder, true) || !builder.append_text(",") || !append_bool(builder, false) || !builder.append_text(",") || !builder.append_text("-0x1.8p+0,0x1.0p+0,\\u00e9\\0}")) return 2;
			if (format_allocations_since() != 0) return 3;
			var message = builder.snapshot();
			if (message.text != "{-128,255,-32768,65535,-2147483648,4294967295,-9223372036854775808,18446744073709551615,true,false,-0x1.8p+0,0x1.0p+0,\\u00e9\\0}") return 4;
			return 42;
		} catch (Error error) { return 5; }
	}
''', True),
	('format-order-and-message', FORMAT_OBSERVE+TICKS+'''int main() {
		try {
			var builder = new Utf8ByteBuilder(); if (!builder.reserve(64)) return 1;
			u8[2] bytes = {195, 169}; var fragment = utf8_message(slice(bytes)); reset_trace();
			format_allocation_mark();
			if (!format_into(builder, $"{tick(3)}:{fragment}:{tick(1)}:{tick(2)}")) return 2;
			if (trace() != 312 || format_allocations_since() != 0) return 3;
			var message = builder.snapshot(); if (message.text != "3:\\u00e9:1:2") return 4;
			return 42;
		} catch (Error error) { return 5; }
	}
''', FORMAT_OBSERVE+TICKS+'''int main() {
		try {
			var builder = new Utf8ByteBuilder(); if (!builder.reserve(64)) return 1;
			u8[2] bytes = {195, 169}; var fragment = utf8_message(slice(bytes)); reset_trace();
			format_allocation_mark(); int first = tick(3); int middle = tick(1); int last = tick(2);
			if (!append_int(builder, first) || !builder.append_text(":") || !builder.append_text(fragment.text) || !builder.append_text(":") || !append_int(builder, middle) || !builder.append_text(":") || !append_int(builder, last)) return 2;
			if (trace() != 312 || format_allocations_since() != 0) return 3;
			var message = builder.snapshot(); if (message.text != "3:\\u00e9:1:2") return 4;
			return 42;
		} catch (Error error) { return 5; }
	}
''', True),
	('format-operand-error', TICKS+'''int risky() throws Error { int ignored = tick(2); throw new Error("format operand stop"); }
	int main() {
		var builder = new Utf8ByteBuilder(); if (!builder.append_text("before")) return 1; reset_trace();
		try { bool ignored = format_into(builder, $"prefix {tick(1)}:{risky()}:{tick(3)}"); return 2; }
		catch (Error error) {
			try { var text = builder.snapshot(); if (trace() == 12 && text.text == "before") return 42; }
			catch (Error snapshot_error) { return 3; }
		}
		return 4;
	}
''', TICKS+'''int risky() throws Error { int ignored = tick(2); throw new Error("format operand stop"); }
	int main() {
		var builder = new Utf8ByteBuilder(); if (!builder.append_text("before")) return 1; reset_trace();
		try { int first = tick(1); int middle = risky(); int last = tick(3); return 2; }
		catch (Error error) {
			try { var text = builder.snapshot(); if (trace() == 12 && text.text == "before") return 42; }
			catch (Error snapshot_error) { return 3; }
		}
		return 4;
	}
''', True),
	('format-owned-text', TICKS+'''owned Utf8Message make() throws Error { return format_text($"value {tick(4)}:{tick(2)}"); }
	int main() {
		try { reset_trace(); var text = make(); if (text.text != "value 4:2" || trace() != 42) return 1; return 42; }
		catch (Error error) { return 2; }
	}
''', TICKS+'''owned Utf8Message make() throws Error {
		int first = tick(4); int last = tick(2); var builder = new Utf8ByteBuilder();
		if (!builder.append_text("value ") || !append_int(builder, first) || !builder.append_text(":") || !append_int(builder, last)) { throw new FormatError(); }
		var text = builder.snapshot(); return move text;
	}
	int main() {
		try { reset_trace(); var text = make(); if (text.text != "value 4:2" || trace() != 42) return 1; return 42; }
		catch (Error error) { return 2; }
	}
''', True),
	('format-nonfinite', FORMAT_OBSERVE+TICKS+'''int main() {
		try {
			var builder = new Utf8ByteBuilder(); if (!builder.reserve(64) || !builder.append_text("before")) return 1;
			f32 nan = format_f32(2); f64 infinity = format_f64(2); reset_trace();
			format_allocation_mark();
			if (format_into(builder, $"prefix {tick(1)}:{nan}:{tick(2)}") || trace() != 12 || format_allocations_since() != 0) return 2;
			if (format_into(builder, $"{infinity}")) return 3;
			var text = builder.snapshot(); if (text.text != "before") return 4;
			try { var rejected = format_text($"{nan}"); return 5; }
			catch (FormatError failure) { return 42; }
		} catch (Error error) { return 6; }
	}
''', FORMAT_OBSERVE+TICKS+'''int main() {
		try {
			var builder = new Utf8ByteBuilder(); if (!builder.reserve(64) || !builder.append_text("before")) return 1; reset_trace();
			format_allocation_mark(); int first = tick(1); int last = tick(2);
			if (trace() != 12 || format_allocations_since() != 0) return 2;
			var text = builder.snapshot(); if (text.text != "before") return 4;
			try { throw new FormatError(); }
			catch (FormatError failure) { return 42; }
		} catch (Error error) { return 6; }
	}
''', True),
	('format-utf8-error', '''int main() {
		var builder = new Utf8ByteBuilder(); u8[1] invalid = {255};
		if (!builder.append_bytes(slice(invalid)) || !format_into(builder, $"valid {42}")) return 1;
		try { var rejected = builder.snapshot(); return 2; } catch (InvalidUtf8 error) { return 42; }
	}
''', '''int main() {
		var builder = new Utf8ByteBuilder(); u8[1] invalid = {255};
		if (!builder.append_bytes(slice(invalid)) || !builder.append_text("valid ") || !append_int(builder, 42)) return 1;
		try { var rejected = builder.snapshot(); return 2; } catch (InvalidUtf8 error) { return 42; }
	}
''', True),
	('format-fresh-owner-abort', FORMAT_OBSERVE+ITEM+'''int eat(owned Utf8Message text, owned Item item) { return item.value; }
	int main() {
		f64 infinity = format_f64(2);
		try { return eat(item: new Item(22), text: format_text($"{infinity}")); }
		catch (FormatError error) { if (drops() == 1 && drop_sum() == 22) return 42; }
		catch (Error error) { return 2; }
		return 1;
	}
''', FORMAT_OBSERVE+ITEM+'''int main() {
		try { var item = new Item(22); throw new FormatError(); }
		catch (FormatError error) { if (drops() == 1 && drop_sum() == 22) return 42; }
		catch (Error error) { return 2; }
		return 1;
	}
''', True),
]
FORMAT_NEGATIVE = [
	('format-escaping-plan', 'int main() { var plan = $"value {42}"; return 42; }'),
	('format-unhandled-owned', 'int main() { var text = format_text($"value {42}"); return 42; }'),
	('format-wrong-sink', 'int main() { int sink = 0; bool ok = format_into(sink, $"value {42}"); return 42; }'),
	('format-labeled-plan', 'int main() { var sink = new Utf8ByteBuilder(); bool ok = format_into(sink, plan: $"value {42}"); return 42; }'),
	('format-unsupported-object', ITEM+'int main() { var sink = new Utf8ByteBuilder(); var item = new Item(42); bool ok = format_into(sink, $"{item}"); return 42; }'),
	('format-temporary-message', 'owned Utf8Message temporary() throws Error { u8[1] bytes = {42}; var text = utf8_message(slice(bytes)); return move text; } int main() { try { var sink = new Utf8ByteBuilder(); bool ok = format_into(sink, $"{temporary()}"); return 42; } catch (Error error) { return 1; } }'),
	('format-interpolation-return', 'string message() { return $"{42}"; } int main() { return 42; }'),
]


def versioned_oracle_libraries(manifest_path):
	manifest_path = Path(manifest_path)
	assert manifest_path.is_file() and not manifest_path.is_symlink()
	manifest = json.loads(manifest_path.read_text())
	assert manifest.get('format') == 'astra-current-inputs/1'
	revision = manifest.get('revision', '')
	assert re.fullmatch('[0-9a-f]{40}', revision)
	assert subprocess.check_output(['git', '-C', ROOT, 'rev-parse', '--verify', revision+'^{commit}'], text=True).strip() == revision
	assert subprocess.run(['git', '-C', ROOT, 'merge-base', '--is-ancestor', revision, 'HEAD'], capture_output=True).returncode == 0
	definition = ROOT/'tests/selfhost-typecore/build.py'
	model = ast.parse(definition.read_text())
	libraries = next(ast.literal_eval(n.value) for n in model.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'LIBRARIES' for t in n.targets))
	expected = {'lib/astra/'+name+'.astra' for name in libraries}
	assert len(expected) == len(libraries) == 10
	selected = {}; rows = []
	for path, digest in manifest['inputs'].items():
		marker = '/source-inputs/lib/astra/'
		if marker not in path: continue
		relative = 'lib/astra/'+path.split(marker, 1)[1]
		assert relative in expected and relative not in selected
		source = Path(path)
		assert source.is_absolute() and source.resolve().is_relative_to((WORK/'runtime').resolve())
		assert not any(p.is_symlink() for p in (source, *source.parents))
		assert source.is_file() and source.stat().st_mode & 0o222 == 0 and sha(source) == digest
		blob = subprocess.check_output(['git', '-C', ROOT, 'rev-parse', revision+':'+relative], text=True).strip()
		assert subprocess.check_output(['git', '-C', ROOT, 'hash-object', '--no-filters', source], text=True).strip() == blob
		selected[relative] = source
		rows.append(dict(repository_path=relative, snapshot_path=str(source), sha256=digest, git_blob=blob, bytes=source.stat().st_size))
	assert set(selected) == expected
	mapping = {str(ROOT/name):path for name,path in selected.items()}
	identity = dict(format='astra-versioned-oracle-libraries/1', manifest=str(manifest_path), manifest_sha256=sha(manifest_path), revision=revision, library_definition=dict(path=str(definition), sha256=sha(definition)), libraries=sorted(rows, key=lambda row:row['repository_path']), scope='Only C0 expanded references use these explicit immutable legacy libraries. Actual Astra targets use current repository libraries. This is not C0 acceptance of current modern library source.')
	return mapping, identity


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for n in ('compiler', 'c0', 'link', 'build', 'runtime'): p.add_argument('--'+n, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True); p.add_argument('--c0-sha256', required=True)
	p.add_argument('--oracle-only', action='store_true'); p.add_argument('--case', action='append')
	p.add_argument('--oracle-library-inputs', type=Path, help='Explicit Git/hash-checked immutable ten-library inputs.json for C0 expanded references; Astra uses current libraries')
	p.add_argument('--freestanding-only', action='store_true', help='Range/fixed targets linked with a syscall entry only, without libc or allocator')
	p.add_argument('--feature', choices=('named', 'match', 'range', 'format', 'collection'), default='named')
	a = p.parse_args()
	assert sha(a.compiler) == a.compiler_sha256 and sha(a.c0) == a.c0_sha256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	build = output_path(a.build, WORK/'build'); build.mkdir(parents=True, exist_ok=False)
	runtime = output_path(a.runtime, WORK/'runtime'); runtime.mkdir(parents=True, exist_ok=False)
	providers = {n:h for n,h in json.loads(a.link.read_text())['objects'].items() if Path(n).name not in ('llvm-capi.o', 'arguments.o')}
	assert len(providers) == 5 and all(sha(n) == h for n,h in providers.items())
	tools = tool_identity([a.compiler, a.c0, sys.executable, *[shutil.which(n) for n in ('gcc', 'cc', 'opt', 'readelf', 'valgrind', 'llvm-config')]])
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	inputs = {str(Path(__file__)):sha(__file__), str(a.link):sha(a.link)}; products = {}; commands = []
	oracle_libraries = {}; oracle_library_identity = None
	if a.oracle_library_inputs is not None:
		oracle_libraries, oracle_library_identity = versioned_oracle_libraries(a.oracle_library_inputs)
		inputs.update({str(path):sha(path) for path in [a.oracle_library_inputs, ROOT/'tests/selfhost-typecore/build.py', *oracle_libraries.values()]})
		write(runtime/'oracle-libraries.json', oracle_library_identity)
	def run(name, argv, expected=0):
		r = execute(argv, runtime/name, expected=expected, timeout=900, env=env)
		commands.append(dict(name=name, argv=list(map(str, argv)), result=r)); write(runtime/'commands.json', commands)
		print(name, r['status'], round(r['seconds'], 3), flush=True)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
	def memory(name, argv, expected):
		run(name, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv], expected)
		log = (runtime/name/'stderr').read_bytes()
		assert all(m in log for m in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	if a.freestanding_only:
		assert a.feature == 'range' and not a.oracle_only and not a.case
		tools.update(tool_identity([shutil.which(n) for n in ('ld', 'nm')]))
		startup = runtime/'entry.S'; startup.write_text('.text\n.globl _start\n_start:\n xor %ebp,%ebp\n and $-16,%rsp\n call main\n mov %eax,%edi\n mov $60,%eax\n syscall\n.section .note.GNU-stack,"",@progbits\n')
		inputs[str(startup)] = sha(startup); entry = build/'entry.o'
		run('entry-assemble', ['cc', '-c', '-x', 'assembler', startup, '-o', entry]); products[str(entry)] = sha(entry)
		cases = [
			('range-unused', 'int main() { var interval = (20..=80).step_by(5); return 42; }', 'int main() { return 42; }'),
			('range-loop', 'int main() { int total = 0; int count = 0; foreach (var item in (20..=80).step_by(5)) { total = total+item; count = count+1; } if (count != 13 || total != 650) return 1; return 42; }', 'int main() { int total = 0; int count = 0; int item = 20; while (item <= 80) { total = total+item; count = count+1; item = item+5; } if (count != 13 || total != 650) return 1; return 42; }'),
			('range-fixed', 'int main() { int[13] values = (20..=80).step_by(5).collect_fixed(); int at = 0; int total = 0; while (at < 13) { if (values[at] != 20+at*5) return 1; total = total+values[at]; at = at+1; } if (total != 650) return 2; return 42; }', 'int main() { int[13] values = {20,25,30,35,40,45,50,55,60,65,70,75,80}; int at = 0; int total = 0; while (at < 13) { if (values[at] != 20+at*5) return 1; total = total+values[at]; at = at+1; } if (total != 650) return 2; return 42; }'),
		]
		for name, modern, expanded in cases:
			source = runtime/(name+'.astra'); source.write_text('language astra27b;\n'+modern+'\n')
			oracle = runtime/(name+'-expanded.astra'); oracle.write_text(expanded+'\n')
			inputs.update({str(n):sha(n) for n in (source, oracle)}); write(runtime/'inputs.json', inputs)
			for producer, compiler, src, modes in [('C0', a.c0, oracle, ('O0',)), ('Astra', a.compiler, source, ('O0','O2'))]:
				for mode in modes:
					label = name+'-'+producer+'-'+mode; obj = build/(label+'.o'); target = build/label
					arguments = ['--entry-object'] if producer == 'C0' else []
					if producer == 'Astra': arguments = ['-'+mode, '-o', obj, src]
					else: arguments = [*arguments, '-'+mode, src, '-o', obj]
					run(label+'-compile', [compiler, '-c', *arguments])
					run(label+'-object-imports', ['nm','-u',obj])
					assert not (runtime/(label+'-object-imports')/'stdout').read_bytes().strip(), 'freestanding object imports a runtime/allocator'
					run(label+'-link', ['ld', '-static', '-nostdlib', '-e', '_start', entry, obj, '-o', target])
					run(label+'-target-imports', ['nm','-u',target]); assert not (runtime/(label+'-target-imports')/'stdout').read_bytes().strip()
					run(label+'-ELF-header', ['readelf','-h',target]); header = (runtime/(label+'-ELF-header')/'stdout').read_text()
					assert 'ELF64' in header and 'Advanced Micro Devices X86-64' in header
					run(label+'-ELF-segments', ['readelf','-l',target]); segments = (runtime/(label+'-ELF-segments')/'stdout').read_text()
					run(label+'-ELF-dynamic', ['readelf','-d',target]); dynamic = (runtime/(label+'-ELF-dynamic')/'stdout').read_text()
					assert 'INTERP' not in segments and 'NEEDED' not in dynamic and 'There is no dynamic section' in dynamic
					run(label+'-native', [target], 42); memory(label+'-memory', [target], 42)
					products.update({str(n):sha(n) for n in (obj, target)})
			ir = build/(name+'.ll'); memory(name+'-compiler-memory', [a.compiler, '--emit-llvm', '-o', ir, source], 0)
			run(name+'-LLVM-verify', ['opt','-passes=verify','-disable-output',ir]); products[str(ir)] = sha(ir)
		allocating = runtime/'owning-collect.astra'; allocating.write_text('language astra27b;\nint main() { var values = (20..=80).step_by(5).collect_array(); return values[0]+values[12]-58; }\n')
		inputs[str(allocating)] = sha(allocating); write(runtime/'inputs.json', inputs)
		for mode in ('O0','O2'):
			label = 'owning-collect-'+mode; obj = build/(label+'.o'); target = build/label
			run(label+'-compile', [a.compiler,'-c','-'+mode,'-o',obj,allocating]); products[str(obj)] = sha(obj)
			run(label+'-object-imports', ['nm','-u',obj]); imports = (runtime/(label+'-object-imports')/'stdout').read_bytes()
			assert b'calloc' in imports and b'free' in imports
			run(label+'-no-allocator-reject', ['ld','-static','-nostdlib','-e','_start',entry,obj,'-o',target], 1)
			assert not target.exists() and b'calloc' in (runtime/(label+'-no-allocator-reject')/'stderr').read_bytes()
		assert all(sha(n) == h for n,h in {**inputs, **tools, **products}.items())
		write(runtime/'identity.json', dict(inputs=inputs, tools=tools, products=products, linked_providers=[], entry='x86-64 syscall exit only; no libc, allocator, dynamic interpreter or undefined object symbols'))
		write(runtime/'result.json', dict(status='SELECTED_FREESTANDING_RANGE_FIXED_NATIVE_AND_MEMORY_PASS', compiler_sha256=a.compiler_sha256, cases=[r[0] for r in cases], target_modes=['O0','O2'], no_allocator_owning_collect_refusals=2, identity_sha256=sha(runtime/'identity.json'), commands_sha256=sha(runtime/'commands.json'), limitation='Selected range/fixed no-runtime targets only; raw LLVM may contain unused private helpers. Owning collect requires its actual allocator and is not executed without one. No complete source, generation or milestone credit.'))
		return
	bridge = runtime/'observe.c'
	bridge.write_text('#include <stdint.h>\n#include <string.h>\nstatic int seen, retired, sum, visited;\nstatic unsigned order;\nint tick(int v) { seen = seen*10+v; return v; }\nint trace(void) { return seen; }\nvoid reset_trace(void) { seen = 0; }\nvoid note_drop(int v) { ++retired; sum += v; order = order*100+v; }\nint drops(void) { return retired; }\nint drop_sum(void) { return sum; }\nint drop_order(void) { return order; }\nvoid reset_drops(void) { retired = 0; sum = 0; order = 0; }\nint c_sum(int first, int last) { return first+last; }\nint visit(int value) { ++visited; return value; }\nint visits(void) { return visited; }\nfloat format_f32(int selector) { uint32_t bits = selector == 1 ? UINT32_C(3217031168) : UINT32_C(2143289344); float value; memcpy(&value, &bits, sizeof value); return value; }\ndouble format_f64(int selector) { uint64_t bits = selector == 1 ? UINT64_C(4607182418800017408) : UINT64_C(9218868437227405312); double value; memcpy(&value, &bits, sizeof value); return value; }\n')
	inputs[str(bridge)] = sha(bridge); bridge_object = build/'observe.o'
	run('C-observer', ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', bridge, '-o', bridge_object])
	objects = [*providers, str(bridge_object)]
	allocation_source = runtime/'allocation-observer.c'
	allocation_source.write_text('#include <stddef.h>\nvoid *__real_calloc(size_t, size_t);\nvoid *__real_malloc(size_t);\nvoid *__real_realloc(void *, size_t);\nvoid __real_free(void *);\nstatic int calls, bytes, total, mark, frees;\nstatic void *watched[32];\nvoid *__wrap_calloc(size_t count, size_t size) { ++calls; ++total; bytes += (int)(count*size); void *result = __real_calloc(count,size); if (count*size==52) { for (int i=0; i<32; ++i) { if (!watched[i]) { watched[i]=result; break; } } } return result; }\nvoid *__wrap_malloc(size_t size) { ++total; return __real_malloc(size); }\nvoid *__wrap_realloc(void *pointer, size_t size) { ++total; return __real_realloc(pointer,size); }\nvoid __wrap_free(void *pointer) { if (pointer) { for (int i=0; i<32; ++i) { if (pointer==watched[i]) { ++frees; watched[i]=NULL; break; } } } __real_free(pointer); }\nint allocation_calls(void) { return calls; }\nint allocation_bytes(void) { return bytes; }\nint watched_frees(void) { return frees; }\nvoid format_allocation_mark(void) { mark = total; }\nint format_allocations_since(void) { return total-mark; }\n')
	inputs[str(allocation_source)] = sha(allocation_source); allocation_object = build/'allocation-observer.o'
	run('C-allocation-observer', ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', allocation_source, '-o', allocation_object])
	cases = [r for r in CASES if not a.case or r[0] in a.case]
	negatives = NEGATIVE
	if a.feature == 'match':
		cases = [r for r in MATCH_CASES if not a.case or r[0] in a.case]
		negatives = MATCH_NEGATIVE
	if a.feature == 'range':
		cases = [r for r in RANGE_CASES if not a.case or r[0] in a.case]
		negatives = RANGE_NEGATIVE
	format_sources = [ROOT/('lib/astra/'+n+'.astra') for n in ('base/errors', 'base/diagnostics', 'text/utf8-message', 'text/utf8-byte-builder', 'text/scalar-format', 'hosted/text-ops', 'collections/bag', 'hosted/text')]
	if a.feature == 'format':
		cases = [r for r in FORMAT_CASES if not a.case or r[0] in a.case]
		negatives = FORMAT_NEGATIVE
	if a.feature == 'collection':
		cases = [r for r in COLLECTION_CASES if not a.case or r[0] in a.case]
		negatives = COLLECTION_NEGATIVE
	assert cases and (not a.case or set(a.case) == {r[0] for r in cases})
	for name, modern, expanded, errors in cases:
		source = runtime/(name+'.astra'); source.write_text('language astra27b;\n'+modern)
		oracle = runtime/(name+'-expanded.astra'); oracle.write_text(expanded)
		extra = [ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/hosted/text.astra'] if errors else []
		if a.feature == 'format': extra = format_sources
		if name == 'namespace-call':
			helper = runtime/'Helpers.astra'; helper.write_text('namespace Helpers;\nint add(int first, int last) { return first+last; }\n')
			extra.append(helper)
		oracle_extra = [oracle_libraries.get(str(path), path) for path in extra]
		inputs.update({str(n):sha(n) for n in [source, oracle, *extra, *oracle_extra]}); write(runtime/'inputs.json', inputs)
		reference = build/(name+'-C0'); links = [arg for n in objects for arg in ('--link-object', n)]
		observed = name in ('range-collect', 'range-collect-literal', 'range-collect-named', 'range-fixed') or name.startswith(('lazy-', 'format-', 'collection-', 'comprehension-', 'named-enum-')); allocation_links = ['-Wl,--wrap=calloc', '-Wl,--wrap=malloc', '-Wl,--wrap=realloc', '-Wl,--wrap=free', allocation_object] if observed else []
		if observed:
			oracle_object = build/(name+'-C0.o')
			run(name+'-C0-compile', [a.c0, '-c', '--entry-object', '-O0', oracle, *oracle_extra, '-o', oracle_object])
			run(name+'-C0-link', ['cc', '-no-pie', oracle_object, *objects, *allocation_links, '-o', reference])
		else:
			run(name+'-C0-compile', [a.c0, '-O0', oracle, *oracle_extra, *links, '-o', reference])
		run(name+'-C0-native', [reference], 42); products[str(reference)] = sha(reference)
		if a.feature in ('format', 'collection') or name.startswith('named-enum-'): memory(name+'-C0-memory', [reference], 42)
		if a.oracle_only: continue
		for mode in ('O0', 'O2'):
			obj = build/(name+'-'+mode+'.o'); target = build/(name+'-'+mode)
			run(name+'-'+mode+'-compile', [a.compiler, '-c', '-'+mode, '-o', obj, source, *extra])
			run(name+'-'+mode+'-link', ['cc', '-no-pie', obj, *objects, *allocation_links, '-o', target])
			elf = subprocess.check_output(['readelf', '-h', target], text=True)
			assert 'ELF64' in elf and 'Advanced Micro Devices X86-64' in elf
			run(name+'-'+mode+'-native', [target], 42); memory(name+'-'+mode+'-memory', [target], 42)
			products[str(target)] = sha(target); products[str(obj)] = sha(obj)
		ir = build/(name+'.ll')
		memory(name+'-compiler-memory', [a.compiler, '--emit-llvm', '-o', ir, source, *extra], 0)
		run(name+'-LLVM-verify', ['opt', '-passes=verify', '-disable-output', ir]); products[str(ir)] = sha(ir)
		write(runtime/'products.json', products)
	for name, text in [] if a.oracle_only else negatives:
		source = runtime/(name+'-negative.astra'); source.write_text('language astra27b;\n'+text+'\n')
		inputs[str(source)] = sha(source); write(runtime/'inputs.json', inputs)
		target = build/(name+'-sentinel.ll'); marker = b'ASTRA27C_NAMED_REFUSAL_SENTINEL\n'; target.write_bytes(marker)
		extra = format_sources if a.feature == 'format' else []
		inputs.update({str(n):sha(n) for n in extra}); write(runtime/'inputs.json', inputs)
		run(name+'-reject', [a.compiler, '--emit-llvm', '-o', target, source, *extra], 1)
		assert target.read_bytes() == marker and (runtime/(name+'-reject/stderr')).stat().st_size > 0
		if name in ('range-class-foreach-write', 'range-generic-foreach-write'):
			assert b'foreach element binding is immutable' in (runtime/(name+'-reject/stderr')).read_bytes()
		if name == 'range-class-foreach-escape':
			assert b'generic body syntax lacks a concrete specialization contract' not in (runtime/(name+'-reject/stderr')).read_bytes()
	assert all(sha(n) == h for n,h in {**inputs, **providers, **tools, **products}.items())
	identity = dict(inputs=inputs, providers=providers, tools=tools, products=products, environment={n:env.get(n) for n in ('PATH', 'LD_LIBRARY_PATH', 'PYTHONHOME', 'LIBRARY_PATH', 'LC_ALL', 'LANG')})
	if oracle_library_identity is not None: identity['oracle_libraries'] = oracle_library_identity
	write(runtime/'identity.json', identity)
	result = dict(status='EXPANDED_C0_ORACLES_ONLY' if a.oracle_only else 'SELECTED_EXPRESSIVE_NATIVE_AND_MEMORY_PASS', feature=a.feature, compiler_sha256=a.compiler_sha256, oracle_only=a.oracle_only, cases=[r[0] for r in cases], negatives=0 if a.oracle_only else len(negatives), identity_sha256=sha(runtime/'identity.json'), commands_sha256=sha(runtime/'commands.json'), limitation='Selected actual source behavior only. Independent source/owner/LLVM corruptions and full current compiler qualification remain separate gates.')
	if oracle_library_identity is not None:
		result['oracle_library_revision'] = oracle_library_identity['revision']
		result['limitation'] += ' C0 expanded references use explicitly versioned legacy libraries; no C0 acceptance of current modern library source is claimed.'
	write(runtime/'result.json', result)


if __name__ == '__main__': main()
