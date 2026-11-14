#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual named-call native targets and separately authored C0 expansions."""
import argparse
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
RANGE_NEGATIVE = [
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


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for n in ('compiler', 'c0', 'link', 'build', 'runtime'): p.add_argument('--'+n, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True); p.add_argument('--c0-sha256', required=True)
	p.add_argument('--oracle-only', action='store_true'); p.add_argument('--case', action='append')
	p.add_argument('--feature', choices=('named', 'match', 'range'), default='named')
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
	def run(name, argv, expected=0):
		r = execute(argv, runtime/name, expected=expected, timeout=900, env=env)
		commands.append(dict(name=name, argv=list(map(str, argv)), result=r)); write(runtime/'commands.json', commands)
		print(name, r['status'], round(r['seconds'], 3), flush=True)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
	def memory(name, argv, expected):
		run(name, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv], expected)
		log = (runtime/name/'stderr').read_bytes()
		assert all(m in log for m in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	bridge = runtime/'observe.c'
	bridge.write_text('static int seen, retired, sum;\nstatic unsigned order;\nint tick(int v) { seen = seen*10+v; return v; }\nint trace(void) { return seen; }\nvoid reset_trace(void) { seen = 0; }\nvoid note_drop(int v) { ++retired; sum += v; order = order*100+v; }\nint drops(void) { return retired; }\nint drop_sum(void) { return sum; }\nint drop_order(void) { return order; }\nvoid reset_drops(void) { retired = 0; sum = 0; order = 0; }\nint c_sum(int first, int last) { return first+last; }\n')
	inputs[str(bridge)] = sha(bridge); bridge_object = build/'observe.o'
	run('C-observer', ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', bridge, '-o', bridge_object])
	objects = [*providers, str(bridge_object)]
	allocation_source = runtime/'allocation-observer.c'
	allocation_source.write_text('#include <stddef.h>\nvoid *__real_calloc(size_t, size_t);\nstatic int calls, bytes;\nvoid *__wrap_calloc(size_t count, size_t size) { ++calls; bytes += (int)(count*size); return __real_calloc(count,size); }\nint allocation_calls(void) { return calls; }\nint allocation_bytes(void) { return bytes; }\n')
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
	assert cases and (not a.case or set(a.case) == {r[0] for r in cases})
	for name, modern, expanded, errors in cases:
		source = runtime/(name+'.astra'); source.write_text('language astra27b;\n'+modern)
		oracle = runtime/(name+'-expanded.astra'); oracle.write_text(expanded)
		extra = [ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/hosted/text.astra'] if errors else []
		if name == 'namespace-call':
			helper = runtime/'Helpers.astra'; helper.write_text('namespace Helpers;\nint add(int first, int last) { return first+last; }\n')
			extra.append(helper)
		inputs.update({str(n):sha(n) for n in [source, oracle, *extra]}); write(runtime/'inputs.json', inputs)
		reference = build/(name+'-C0'); links = [arg for n in objects for arg in ('--link-object', n)]
		observed = name == 'range-collect'; allocation_links = ['-Wl,--wrap=calloc', allocation_object] if observed else []
		if observed:
			oracle_object = build/(name+'-C0.o')
			run(name+'-C0-compile', [a.c0, '-c', '--entry-object', '-O0', oracle, *extra, '-o', oracle_object])
			run(name+'-C0-link', ['cc', '-no-pie', oracle_object, *objects, *allocation_links, '-o', reference])
		else:
			run(name+'-C0-compile', [a.c0, '-O0', oracle, *extra, *links, '-o', reference])
		run(name+'-C0-native', [reference], 42); products[str(reference)] = sha(reference)
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
		run(name+'-reject', [a.compiler, '--emit-llvm', '-o', target, source], 1)
		assert target.read_bytes() == marker and (runtime/(name+'-reject/stderr')).stat().st_size > 0
	assert all(sha(n) == h for n,h in {**inputs, **providers, **tools, **products}.items())
	write(runtime/'identity.json', dict(inputs=inputs, providers=providers, tools=tools, products=products, environment={n:env.get(n) for n in ('PATH', 'LD_LIBRARY_PATH', 'PYTHONHOME', 'LIBRARY_PATH', 'LC_ALL', 'LANG')}))
	write(runtime/'result.json', dict(status='EXPANDED_C0_ORACLES_ONLY' if a.oracle_only else 'SELECTED_EXPRESSIVE_NATIVE_AND_MEMORY_PASS', feature=a.feature, compiler_sha256=a.compiler_sha256, oracle_only=a.oracle_only, cases=[r[0] for r in cases], negatives=0 if a.oracle_only else len(negatives), identity_sha256=sha(runtime/'identity.json'), commands_sha256=sha(runtime/'commands.json'), limitation='Selected actual source behavior only. Independent source/owner/LLVM corruptions and full current compiler qualification remain separate gates.'))


if __name__ == '__main__': main()
