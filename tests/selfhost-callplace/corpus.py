#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source programs with independent assertions and disclosed original method views."""
import json
from state import ROOT, RUNTIME, sha, read


def declaration(path, spelling):
	raw = path.read_bytes(); start = raw.index(spelling.encode()); end = raw.index(b'\n}', start)+2
	return raw[start:end].decode()+'\n'


def method(path, spelling):
	raw = path.read_bytes(); start = raw.index(('\t'+spelling).encode()); end = raw.index(b'\n\t}', start)+3
	return raw[start:end].decode()+'\n'


def main():
	leaf = RUNTIME/'corpus-v6'; leaf.mkdir(exist_ok=False)
	model = ROOT/'compiler/semantic/flow-model.astra'
	common = ''.join(declaration(ROOT/path, spelling) for path,spelling in [
		('compiler/semantic/model.astra','struct SymbolId {'),
		('compiler/semantic/model.astra','struct ScopeId {'),
		('compiler/semantic/model.astra','struct BindingReference {'),
		('compiler/semantic/types.astra','SymbolId type_symbol('),
		('compiler/syntax/model.astra','struct SyntaxNodeId {'),
		('compiler/syntax/model.astra','struct SyntaxTokenId {'),
		('compiler/syntax/model.astra','struct SyntaxSourceId {'),
		('compiler/syntax/model.astra','struct SyntaxSpan {'),
		('compiler/semantic/types.astra','struct TypeId {'),
		('compiler/semantic/flow-model.astra','struct FlowSlot {'),
		('compiler/semantic/flow-model.astra','struct FlowEvent {'),
		('compiler/syntax/arena-support.astra','int syntax_grown_capacity(')])
	common += '''void assert_that(bool value) { if (!value) { var a = new int[0]; int bad = a[1]; } }
class FlowGraph {
	owned FlowSlot[] slots;
	owned FlowEvent[] events;
	int slot_count;
	int count;
	int limit;
	bool exhausted;
	init(int limit) { this.slots = new FlowSlot[2]; this.events = new FlowEvent[16]; this.slot_count = 2; this.count = 0; this.limit = limit; this.exhausted = false; }
'''
	methods = {name:method(model, spelling) for name,spelling in [('room','bool room('),('add','int add('),('slot_for','int slot_for(')]}
	common += '\n'.join(methods.values())+'}\n'
	# These are dependency views, not replacements for the original compiler algorithms.
	support = '''class SyntaxArena {
	owned SyntaxNodeId[] nodes;
	int visits;
	init() { this.nodes = new SyntaxNodeId[3]; this.visits = 0; }
	SyntaxTokenId get_token_identifier(SyntaxNodeId node) { this.visits = this.visits + 1; SyntaxTokenId token = {index = node.index + 10}; return token; }
	SyntaxNodeId node_at(int arguments, int i) { this.visits = this.visits + 1; return this.nodes[arguments + i]; }
}
class SyntaxProgram {
	owned SyntaxArena arena;
	init(owned SyntaxArena arena) { this.arena = move arena; }
}
class BindingIndex {
	owned SyntaxProgram program;
	owned BindingReference[] references;
	init(owned SyntaxProgram program) { this.program = move program; this.references = new BindingReference[2]; }
	BindingReference reference(int i) { return this.references[i - 1]; }
}
class CheckedIndex {
	owned BindingIndex bindings;
	owned int[] node_references;
	owned int[] reference_next;
	init(owned BindingIndex bindings) { this.bindings = move bindings; this.node_references = new int[4]; this.reference_next = new int[4]; }
}
FlowEvent make_event(SyntaxNodeId node) { FlowEvent result = {operation = 7, node = node, span = {source = {index = 1}, start = 2, end = 3}, slot = node.index, loan = 0, region = 0, call = 0, next = 0, other = 0, loop_head = 0, input = 0, output = 0, null_kind = 0, field = 0, source_field = 0, producer = {index = 0}, predicate = {index = 0}, required = false}; return result; }
'''
	support += (RUNTIME.parent/'membercall22/reference-v4/original-checked-target.astra').read_text()
	seed = 'FlowSlot slot = {symbol = {index = 11}, type = {index = 1}, flags = 0, region = 0, owner = false, parameter = false}; graph.slots[0] = slot; FlowSlot second = slot; second.symbol.index = 22; graph.slots[1] = second;'
	seed += ' BindingReference ref = {node = {index = 1}, token = {index = 11}, span = {source = {index = 0}, start = 0, end = 0}, scope = {index = 0}, target = {index = 11}, alternative = {index = 0}, state_code = 1, reason = 0, domain = 2, next_reference = 0}; checked.bindings.references[0] = ref; checked.node_references[1] = 1;'
	cases = {}
	for name,index,expected in [('nested-slot-hit',1,1),('nested-slot-miss',2,0)]:
		body = f'''int main() {{ var graph = new FlowGraph(100); var arena = new SyntaxArena(); var program = new SyntaxProgram(move arena); var bindings = new BindingIndex(move program); var checked = new CheckedIndex(move bindings); {seed} SyntaxNodeId direct = {{index = {index}}};
	int result = graph.slot_for(checked_target(checked, direct, checked.bindings.program.arena.get_token_identifier(direct)));
	if (result != {expected} || checked.bindings.program.arena.visits != 1) return 99; return 61; }}
'''
		cases[name] = (common+support+body,61,'Original slot_for/room and complete original checked_target body; synthetic token accessor explicitly disclosed')
	for name,count,limit,expected_count in [('record-add-growth',41,100,41),('record-add-limit',4,3,3)]:
		body = f'''int main() {{ var graph = new FlowGraph({limit}); var arena = new SyntaxArena(); var program = new SyntaxProgram(move arena); var bindings = new BindingIndex(move program); var checked = new CheckedIndex(move bindings); SyntaxNodeId source = {{index = 17}}; checked.bindings.program.arena.nodes[1] = source; int arguments = 0; int i = 1;
	var argument = checked.bindings.program.arena.node_at(arguments, i); var bad = make_event(argument);
	int n = 0; while (n < {count}) {{ int result = graph.add(bad); if (n < {expected_count} && result != n + 1) return 99; n = n + 1; }}
	if (graph.count != {expected_count} || graph.events[0].slot != 17 || graph.events[{expected_count-1}].node.index != 17 || checked.bindings.program.arena.visits != 1) return 98;
	if (graph.exhausted != {'true' if limit < count else 'false'}) return 97; return 62; }}
'''
		cases[name] = (common+support+body,62,'Original add/room; real record buffer copy/growth and once-only nested receiver evaluation')
	meter = '''struct Sample { int amount; }
struct Other { int amount; }
class Meter {
	int stamp;
	owned Sample[] history;
	init() { this.stamp = 0; this.history = new Sample[3]; }
	Sample form(int n) { this.stamp = this.stamp * 10 + 1; Sample result = {amount = n}; return result; }
	int fold(Sample row) { this.stamp = this.stamp * 10 + 2; this.history[1] = row; return row.amount; }
	int merge(int a, int b) { this.stamp = this.stamp * 10 + 3; return a * 10 + b; }
}
class Rack {
	owned Meter instrument;
	init(owned Meter instrument) { this.instrument = move instrument; }
}
'''
	cases['independent-nested-order'] = (meter+'''int main() { var meter = new Meter(); var rack = new Rack(move meter); int result = rack.instrument.fold(rack.instrument.form(7)); if (result != 7 || rack.instrument.stamp != 12 || rack.instrument.history[1].amount != 7) return 99; return 63; }
''',63,'Unrelated Class and nominal record, inner call before outer, owner cleanup')
	cases['independent-inferred-local'] = (meter+'''int main() { var meter = new Meter(); var rack = new Rack(move meter); var row = rack.instrument.form(8); if (rack.instrument.fold(row) != 8 || rack.instrument.stamp != 12) return 99; return 64; }
''',64,'Inferred record result retained in a local')
	cases['multiple-arguments-order'] = (meter+'''int main() { var meter = new Meter(); var rack = new Rack(move meter); int result = rack.instrument.merge(rack.instrument.fold(rack.instrument.form(4)), rack.instrument.fold(rack.instrument.form(5))); if (result != 45 || rack.instrument.stamp != 12123) return 99; return 65; }
''',65,'Two nested argument effects, no duplicated receiver or call')
	cases['borrowed-alias-receiver'] = (meter+'''int twice(borrowed Rack left, borrowed Rack right) { Sample a = {amount = 4}; Sample b = {amount = 5}; return left.instrument.merge(left.instrument.fold(a), right.instrument.fold(b)); }
int main() { var meter = new Meter(); var rack = new Rack(move meter); if (twice(rack, rack) != 45 || rack.instrument.stamp != 223) return 99; return 66; }
''',66,'Same receiver aliased through two nonexclusive borrowed roots')
	clock = '''struct Tick { i64 value; bool ready; }
class Clock {
	i64 total;
	init() { this.total = 0; }
	Tick pulse(i64 n) { this.total = this.total + n; Tick value = {value = this.total, ready = true}; return value; }
	int inspect(Tick value) { if (value.ready && value.value == this.total) return 7; return 0; }
}
class Watch { owned Clock clock; init(owned Clock clock) { this.clock = move clock; } }
'''
	cases['second-family-result'] = (clock+'''int main() { var clock = new Clock(); var watch = new Watch(move clock); var value = watch.clock.pulse(4000000000); if (watch.clock.inspect(value) != 7 || watch.clock.total != 4000000000) return 99; return 67; }
''',67,'Second unrelated Class family with i64 record and distinct method names')
	for name,member in [('specialized-class-concrete','echo'),('specialized-class-generic','identity')]:
		generic = '''struct Token { int value; }
class Echo<T> { owned T[] data; init() { this.data = new T[2]; } T echo(T value) { return value; } U identity<U>(U value) { return value; } }
class Envelope { owned Echo<Token> child; init(owned Echo<Token> child) { this.child = move child; } }
'''
		cases[name] = (generic+f'''int main() {{ var child = new Echo<Token>(); var box = new Envelope(move child); Token input = {{value = 19}}; var result = box.child.{member}{"<Token>" if member == "identity" else ""}(input); if (result.value != 19) return 99; return 68; }}
''',68,'Canonical generic Class specialization and real generic-method substitution')
	cases['field-array-record-result'] = (meter+'''int main() { var meter = new Meter(); var rack = new Rack(move meter); var rows = new Sample[2]; var formed = rack.instrument.form(9); rows[1] = formed; if (rack.instrument.fold(rows[1]) != 9 || rack.instrument.stamp != 12) return 99; return 69; }
''',69,'Call result into indexed record storage, then argument snapshot')
	cases['nested-owner-retirement'] = (meter+'''int compute(owned Rack rack) { var row = rack.instrument.form(3); return rack.instrument.fold(row); }
int main() { var meter = new Meter(); var rack = new Rack(move meter); if (compute(move rack) != 3) return 99; return 70; }
''',70,'Owner transfer and nested owned-field destruction after final borrowed call')
	cases['early-return-cleanup'] = (meter+'''int compute(bool early) { var meter = new Meter(); var rack = new Rack(move meter); var row = rack.instrument.form(6); if (early) return rack.instrument.fold(row); return rack.instrument.fold(row) + 1; }
int main() { if (compute(true) != 6 || compute(false) != 7) return 99; return 71; }
''',71,'Both normal return paths retire owning Class fields')
	selection = []
	for name,(source,expected,oracle) in cases.items():
		path = leaf/(name+'.astra'); path.write_text(source)
		selection.append(dict(name=name,sources=[dict(path=str(path),bytes=path.stat().st_size,sha256=sha(path))],expected_exit=expected,oracle=oracle))
	provider = leaf/'namespace-provider.astra'; provider.write_text('namespace Counter; int twice(int n) { return n + n; }\n')
	entry = leaf/'namespace-main.astra'; entry.write_text('class Gauge { int value; init(int value) { this.value = value; } int read() { return this.value; } } int main() { var gauge = new Gauge(7); return Counter.twice(gauge.read()); }\n')
	selection.append(dict(name='namespace-qualified-continuity',sources=[dict(path=str(p),bytes=p.stat().st_size,sha256=sha(p)) for p in (provider,entry)],expected_exit=14,oracle='Bound namespace function remains distinct from instance receiver resolution'))
	(leaf/'selection.json').write_text(json.dumps(selection,indent=2)+'\n')
	(leaf/'views.json').write_text(json.dumps(dict(original_model=str(model),original_model_sha256=sha(model),methods=methods,disclosure='FlowGraph has only six relevant fields and a bounded constructor; complete room/add/slot_for bodies copied unchanged. Arena, Program, BindingIndex, CheckedIndex and make_event are explicit nonthrowing dependency views; checked_target is the complete original nonthrowing helper, not original whole compiler callers. Original throwing callers are never transformed or executed.'),indent=2)+'\n')
	print(len(selection),'new distinct source programs')


if __name__ == '__main__':
	main()
