# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent state/edge obligations; never calls a Machine transition."""

from collections import Counter
from copy import deepcopy
from dataclasses import replace

from model import Cell, Consumer, Loan, Owner, Reservation, SCHEMAS, Value


class Invalid(AssertionError):
	pass


def demand(condition, reason):
	if not condition:
		raise Invalid(reason)


def shape(value, expected, partial=False, depth=0):
	demand(depth <= 3, "payload nesting bound")
	if expected == "int":
		demand(type(value) is int, "exact scalar payload")
		return []
	if expected == "Header":
		demand(type(value) is tuple and len(value) == 2 and all(type(x) is int for x in value), "record snapshot")
		return []
	if expected == "owner":
		demand(isinstance(value, Owner) and type(value.token) is int and value.token >= 0, "owner token")
		return [value.token]
	demand(isinstance(value, Value) and value.identity == expected, "nominal identity")
	demand(expected in SCHEMAS and value.variant in SCHEMAS[expected], "declared valid tag")
	fields = SCHEMAS[expected][value.variant]
	demand(len(value.payload) <= len(fields) if partial else len(value.payload) == len(fields), "initialized active fields")
	result = []
	for part, kind in zip(value.payload, fields):
		result.extend(shape(part, kind, False, depth + 1))
	return result


def may_copy(identity):
	# Independently search all alternatives for ownership, including empty active cases.
	work, visited = [identity], set()
	while work:
		kind = work.pop()
		if kind == "owner":
			return False
		if kind in visited or kind in ("int", "Header"):
			continue
		visited.add(kind)
		for fields in SCHEMAS[kind].values():
			work.extend(fields)
	return True


def check(state):
	locations = {}
	for name, cell in state.cells.items():
		demand(cell.expected in SCHEMAS, "cell declared identity")
		demand(cell.phase in ("live", "staging", "reserved", "uninitialized", "moved", "dropped"), "storage state")
		if cell.phase in ("live", "staging", "reserved"):
			for token in shape(cell.value, cell.expected, cell.phase == "staging"):
				demand(token not in locations, "duplicated owning payload")
				locations[token] = name
		else:
			demand(cell.value is None, "disarmed storage cannot expose a payload")
	for loan in state.borrows.values():
		demand(isinstance(loan, Loan) and loan.root in state.cells, "loan root identity")
		cell = state.cells[loan.root]
		demand(cell.phase == "live" and cell.epoch == loan.epoch and cell.value == loan.value, "borrow invalidated")
		demand(type(loan.scope) is int and loan.scope >= cell.scope, "loan extent within root lifetime")
	for name, consumer in state.consumers.items():
		demand(isinstance(consumer, Consumer) and consumer.phase in ("pending", "committed", "aborted"), "consumer state")
		seen, cursor = {name}, consumer.parent
		while cursor is not None:
			demand(cursor in state.consumers and cursor not in seen, "consumer ancestry")
			seen.add(cursor)
			parent = state.consumers[cursor]
			demand(parent.scope <= consumer.scope, "consumer enclosing scope")
			if consumer.phase == "pending":
				demand(parent.phase == "pending", "pending consumer enclosing authority")
			cursor = parent.parent
	arguments = []
	for source, reservation in state.reservations.items():
		demand(isinstance(reservation, Reservation) and reservation.consumer in state.consumers and state.consumers[reservation.consumer].phase == "pending", "reservation consumer authority")
		demand(state.cells[source].phase == "reserved", "pending reservation responsibility")
		arguments.append(reservation.argument)
		demand(reservation.argument not in state.cells, "reservation target already initialized")
	demand(len(arguments) == len(set(arguments)), "duplicate reservation target")
	demand({n for n, c in state.cells.items() if c.phase == "reserved"} == set(state.reservations), "orphan reservation")
	ledger, acquired, disposed = {}, set(), set()
	observations = 0
	for event in state.events:
		kind = event[0]
		if kind == "acquire":
			_, token, name = event
			demand(token not in acquired, "duplicate acquisition")
			acquired.add(token)
			ledger[token] = name
		elif kind == "transfer":
			_, token, source, target = event
			demand(token in ledger and ledger[token] == source, "transfer exact owner correspondence")
			ledger[token] = target
		elif kind == "dispose":
			_, token, name, witness, ordinal = event
			shape(witness, witness.identity, True)
			demand(0 <= ordinal < len(witness.payload), "inactive payload drop")
			demand(token in shape(witness.payload[ordinal], SCHEMAS[witness.identity][witness.variant][ordinal]), "drop active field correspondence")
			demand(token in ledger and ledger[token] == name and token not in disposed, "payload disposed twice or wrong owner")
			del ledger[token]
			disposed.add(token)
		elif kind == "read":
			_, witness, ordinal = event
			shape(witness, witness.identity)
			demand(0 <= ordinal < len(SCHEMAS[witness.identity][witness.variant]), "inactive payload read")
		elif kind == "copy":
			demand(may_copy(event[1]), "copy of whole move-only type")
		elif kind == "route":
			_, domain, target, scope, handlers, function = event
			applicable = [h for h in handlers if h.domain == domain]
			if applicable:
				demand((target, scope) == (applicable[-1].target, applicable[-1].scope), "nearest exact handler destination")
			else:
				demand(domain == function and target == "return_error" and scope == -1, "wrong function error domain")
		elif kind == "observe":
			observations += 1
			demand(event[1] != "Cancelled" or event[2] in ("cancel_exit", "explicit"), "cancellation laundered through ordinary catch")
		else:
			demand(kind in ("bind_copy", "loan_end", "abort", "commit"), "known semantic event")
	demand(ledger == locations, "lost owner or missing cleanup/transfer")
	demand(acquired == set(range(state.next_token)), "acquisition accounting")
	for domain, target, scope in state.exits:
		demand(state.cells[target].expected == domain, "error payload exact destination type")
	if state.completion is not None:
		shape(state.completion, state.completion.identity)
		demand(all(state.evidence[k] for k in ("target", "release", "registration", "queue")), "publication before retirement")
		demand(not state.command_required or state.evidence["command"], "missing observed command release")
		demand(not state.parent_cancelled or state.completion.variant == "Cancelled", "parent cancellation erased")
	demand(state.consuming_right in (0, 1) and observations == 1 - state.consuming_right, "single consuming observer")
	return Counter(e[0] for e in state.events)


def edge(before, after, operation, args):
	check(before)
	check(after)
	if operation in ("move", "consume", "drop", "replace"):
		invalidated = args[0]
		demand(not any(b.root == invalidated for b in before.borrows.values()), "borrow invalidation edge")
	if operation == "move":
		source, target = args
		demand(before.cells[source].phase == "live" and after.cells[source].phase == "moved", "use after move/consuming match")
		demand(before.cells[source].value == after.cells[target].value, "whole value movement")
	if operation == "consume":
		consuming_edge(before, after, *args)
	if operation == "copy":
		demand(may_copy(before.cells[args[0]].expected), "copy empty case of owning type")
		demand(before.cells[args[0]].value == after.cells[args[1]].value and before.cells[args[0]] == after.cells[args[0]], "copy exact snapshot")
	if operation == "publish":
		cell = before.cells[args[0]]
		shape(cell.value, cell.expected)
	if operation == "replace":
		target, incoming = args
		demand(before.cells[target].expected == before.cells[incoming].expected and target != incoming, "replacement identity or self move")
		demand(after.cells[target].value == before.cells[incoming].value and after.cells[incoming].phase == "moved", "incoming-first complete replacement")
	if operation == "borrow":
		name, binding = args[:2]
		cell = before.cells[name]
		scope = args[2] if len(args) == 3 and args[2] is not None else cell.scope + 1
		expected = dict(before.borrows, **{binding: Loan(name, cell.epoch, cell.value, scope)})
		demand(after.borrows == expected, "inspection loan source/extent mapping")
	if operation == "end_borrow" and args:
		expected = deepcopy(before)
		binding = args[0]
		loan = expected.borrows.pop(binding)
		expected.events.append(("loan_end", binding, loan))
		demand(after == expected, "ordinary loan end correspondence")
	if operation == "begin_consumer":
		name = args[0]
		parent = args[1] if len(args) > 1 else None
		scope = args[2] if len(args) > 2 else 0
		expected = deepcopy(before)
		expected.consumers[name] = Consumer(parent, scope)
		demand(after == expected, "consumer declaration/parent correspondence")
	if operation == "reserve":
		source, argument, consumer = args
		expected = deepcopy(before)
		expected.reservations[source] = Reservation(consumer, argument)
		expected.cells[source].phase = "reserved"
		demand(after == expected, "reservation exact consumer/source mapping")
	if operation in ("abort_arguments", "commit_arguments"):
		consumer_edge(before, after, args[0], operation == "commit_arguments")
	if operation == "route":
		routing_edge(before, after, args[0], args[1] if len(args) == 2 else None)
	demand(not before.parent_cancelled or after.parent_cancelled, "monotone cancellation request")


def consuming_edge(before, after, source, bindings):
	cell = before.cells[source]
	demand(cell.phase == "live" and after.cells[source].phase == "moved", "one consuming match")
	value = cell.value
	fields = SCHEMAS[cell.expected][value.variant]
	demand(len(bindings) == len(fields), "selected pattern field count")
	names = [b for b in bindings if b is not None]
	demand(len(names) == len(set(names)) and not set(names) & (set(before.cells) | set(before.borrows)), "fresh requested bindings")
	expected = deepcopy(before)
	# Derive disposal from the selected active fields, never from after's events.
	ignored = [i for i, binding in enumerate(bindings) if binding is None]
	for i in reversed(ignored):
		for token in reversed(shape(value.payload[i], fields[i])):
			expected.events.append(("dispose", token, source, value, i))
	for i, binding in enumerate(bindings):
		if binding is None:
			continue
		part, kind = value.payload[i], fields[i]
		if kind == "owner" or isinstance(part, Value):
			identity = "Buffer" if kind == "owner" else kind
			bound = Value("Buffer", "Ready", (part,)) if kind == "owner" else part
			demand(binding in after.cells and after.cells[binding].order == expected.next_order, "binding initialization declaration order")
			expected.cells[binding] = Cell(identity, bound, "live", 0, cell.scope + 1, expected.next_order)
			expected.next_order += 1
		else:
			expected.events.append(("bind_copy", kind, binding, part))
		for token in shape(part, kind):
			expected.events.append(("transfer", token, source, binding))
	expected.cells[source] = replace(cell, value=None, phase="moved", epoch=cell.epoch + 1)
	demand(after.cells == expected.cells, "selected payload binding correspondence")
	demand(after.events == expected.events, "selected payload event delta/order correspondence")
	demand(after == expected, "consuming edge unrelated state/disarm correspondence")


def consumer_edge(before, after, consumer, commit):
	frame = before.consumers[consumer]
	demand(frame.phase == "pending", "one pending consumer commit/abort")
	demand(not any(c.parent == consumer and c.phase == "pending" for c in before.consumers.values()), "unfinished nested consumer")
	pending = [(n, r.argument) for n, r in before.reservations.items() if r.consumer == consumer]
	expected = deepcopy(before)
	expected.reservations = {n: r for n, r in before.reservations.items() if r.consumer != consumer}
	expected.consumers[consumer] = replace(frame, phase="committed" if commit else "aborted")
	for source, argument in pending:
		cell = before.cells[source]
		if commit:
			demand(argument not in before.cells, "fresh committed argument target")
			expected.cells[source] = replace(cell, phase="moved", value=None, epoch=cell.epoch + 1)
			expected.cells[argument] = Cell(cell.expected, cell.value, "live", 1, frame.scope + 1, expected.next_order)
			expected.next_order += 1
			for token in shape(cell.value, cell.expected):
				expected.events.append(("transfer", token, source, argument))
		else:
			expected.cells[source] = replace(cell, phase="live")
	expected.events.append(("commit" if commit else "abort", consumer, tuple(pending)))
	demand(after.consumers == expected.consumers and after.reservations == expected.reservations, "consumer commit/abort authority")
	demand(after.cells == expected.cells, "consumer transfer/restoration correspondence")
	demand(after == expected, "consumer event delta/commit once correspondence")


def routing_edge(before, after, error, consumer):
	demand(consumer is not None or not any(c.phase == "pending" for c in before.consumers.values()), "explicit current consumer identity")
	cell = before.cells[error]
	demand(cell.phase == "live", "live routed error")
	applicable = [h for h in before.handlers if h.domain == cell.expected]
	if applicable:
		handler = applicable[-1]
		target, scope, survivor = handler.target, handler.scope, handler.consumer
	else:
		demand(cell.expected == before.function_error, "unhandled checked error")
		target, scope, survivor = "return_error", -1, None
	demand(target not in before.cells, "fresh handler binding")
	# Scope determines loan extent; exact consumer ancestry determines abort
	# authority. Equal scope numbers alone cannot authorize another consumer.
	ancestors = []
	cursor = consumer
	while cursor != survivor:
		demand(cursor is not None and cursor in before.consumers and cursor not in ancestors, "handler consumer ancestry")
		demand(before.consumers[cursor].phase == "pending", "pending error consumer")
		ancestors.append(cursor)
		cursor = before.consumers[cursor].parent
	expected = deepcopy(before)
	exited = [(b, loan) for b, loan in before.borrows.items() if loan.scope > scope]
	expected.borrows = {b: loan for b, loan in before.borrows.items() if loan.scope <= scope}
	for binding, loan in reversed(exited):
		expected.events.append(("loan_end", binding, loan))
	for abandoned in ancestors:
		pending = [(n, r.argument) for n, r in before.reservations.items() if r.consumer == abandoned]
		expected.consumers[abandoned] = replace(before.consumers[abandoned], phase="aborted")
		for name, _ in pending:
			expected.cells[name].phase = "live"
			del expected.reservations[name]
		expected.events.append(("abort", abandoned, tuple(pending)))
	expected.cells[error] = replace(cell, phase="moved", value=None, epoch=cell.epoch + 1)
	expected.cells[target] = Cell(cell.expected, cell.value, "live", 1, scope, before.next_order)
	expected.next_order += 1
	for token in shape(cell.value, cell.expected):
		expected.events.append(("transfer", token, error, target))
	expected.events.append(("route", cell.expected, target, scope, before.handlers, before.function_error))
	crossed = [n for n, c in expected.cells.items() if c.scope > scope and c.phase in ("live", "staging")]
	for name in sorted(crossed, key=lambda n: expected.cells[n].order, reverse=True):
		crossed_cell = expected.cells[name]
		witness = crossed_cell.value
		for i in reversed(range(len(witness.payload))):
			for token in reversed(shape(witness.payload[i], SCHEMAS[witness.identity][witness.variant][i])):
				expected.events.append(("dispose", token, name, witness, i))
		expected.cells[name] = replace(crossed_cell, value=None, phase="dropped", epoch=crossed_cell.epoch + 1)
	expected.exits.append((cell.expected, target, scope))
	demand(after.borrows == expected.borrows, "scoped loan exit mapping")
	demand(after.consumers == expected.consumers and after.reservations == expected.reservations, "route consumer abort authority")
	demand(not any(c.phase in ("live", "staging", "reserved") and c.scope > scope for c in after.cells.values()), "missing cleanup on propagation")
	demand(after.cells == expected.cells, "route cell cleanup/restoration correspondence")
	demand(after.events == expected.events, "scoped route event order/correspondence")
	demand(after == expected, "route destination/exit correspondence")
