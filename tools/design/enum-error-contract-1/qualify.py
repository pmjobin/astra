# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Handwritten traces, independent corruptions, and depth-bounded exploration."""

import argparse
from collections import Counter, deque
from copy import deepcopy
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import sys

from checker import Invalid, check, edge
from model import Handler, Machine, Owner, Rejected, SCHEMAS, Value
from review_regressions import regressions


BOUNDS = dict(explorer_enum_cells=2, explorer_owner_cells=2, explorer_owner_tokens=2, variants=3, payload_nesting=3, handler_depth=2, exploration_steps=6, state_cap_per_domain=20000)
ROWS = []
MUTATIONS = []


def step(machine, operation, *args):
	before = deepcopy(machine.state)
	result = getattr(machine, operation)(*args)
	edge(before, machine.state, operation, args)
	return result


def summary(machine):
	counts = check(machine.state)
	return {k: counts[k] for k in ("acquire", "transfer", "dispose")}


def witness(name, machine, expected, extra=None):
	actual = summary(machine)
	assert actual == dict(zip(("acquire", "transfer", "dispose"), expected)), (name, actual, expected)
	ROWS.append(dict(name=name, events=actual, observation=extra))


def refuses(name, machine, operation, *args):
	before = deepcopy(machine.state)
	try:
		getattr(machine, operation)(*args)
	except Rejected:
		assert machine.state == before, name
		check(machine.state)
		ROWS.append(dict(name=name, refusal="PASS", operation=operation))
		return
	raise AssertionError("accepted invalid operation: " + name)


def mutation(name, valid, corrupt, expected_reason, operation=None, args=(), before=None):
	check(valid)
	candidate = deepcopy(valid)
	corrupt(candidate)
	try:
		if operation is None:
			check(candidate)
		else:
			edge(before, candidate, operation, args)
	except Invalid as error:
		assert expected_reason in str(error), (name, str(error))
		MUTATIONS.append(dict(name=name, detected=str(error), minimal_trace=operation or "valid-state / single corruption / check", restored_control="PASS"))
		check(valid)
		return
	raise AssertionError("undetected corruption: " + name)


def owned_value(identity="BufferState", variant="Ready", scope=0):
	m = Machine()
	step(m, "declare", "value", identity, scope)
	owner = step(m, "acquire", "input", scope)
	step(m, "begin", "value", variant)
	step(m, "append", "value", owner, "input")
	step(m, "publish", "value")
	return m


def directed():
	m = Machine()
	for name in ("a", "b"):
		step(m, "declare", name, "Decode")
	step(m, "construct", "a", "End", (2, 4))
	step(m, "copy", "a", "b")
	assert step(m, "read", "b", 1) == 4
	witness("copyable-payload-snapshot", m, (0, 0, 0))
	m = Machine()
	for name in ("a", "b"):
		step(m, "declare", name, "BufferState")
	step(m, "construct", "a", "Empty")
	refuses("empty-active-case-does-not-grant-copy", m, "copy", "a", "b")
	step(m, "move", "a", "b")
	refuses("use-after-whole-move", m, "read", "a", 0)
	witness("move-empty-case", m, (0, 0, 0))
	m = owned_value()
	step(m, "borrow", "value", "view")
	refuses("retag-borrowed-owner", m, "drop", "value")
	step(m, "declare", "incoming", "BufferState")
	step(m, "construct", "incoming", "Empty")
	refuses("replace-borrowed-owner", m, "replace", "value", "incoming")
	step(m, "end_borrow", "view")
	step(m, "consume", "value", ("bytes",))
	assert step(m, "read", "bytes", 0) == Owner(0)
	refuses("use-after-consuming-match", m, "consume", "value", (None,))
	step(m, "drop", "bytes")
	witness("borrow-release-consume-outlives-enum-slot", m, (1, 2, 1))
	m = owned_value()
	step(m, "consume", "value", (None,))
	witness("deliberately-ignored-owned-payload", m, (1, 1, 1))
	m = owned_value()
	refuses("inactive-payload-read", m, "read", "value", 1)
	refuses("self-move", m, "replace", "value", "value")
	step(m, "declare", "new", "BufferState")
	owner = step(m, "acquire", "second")
	step(m, "begin", "new", "Ready")
	step(m, "append", "new", owner, "second")
	step(m, "publish", "new")
	step(m, "replace", "value", "new")
	step(m, "drop", "value")
	witness("incoming-first-replacement", m, (2, 3, 2))
	m = Machine()
	step(m, "declare", "build", "PairOwners", 1)
	first = step(m, "acquire", "fresh_a", 1)
	second = step(m, "acquire", "fresh_b", 1)
	step(m, "begin", "build", "Ready")
	step(m, "append", "build", first, "fresh_a")
	step(m, "append", "build", second, "fresh_b")
	refuses("incomplete-publication", m, "publish", "build")
	step(m, "drop", "build")
	assert [e[1] for e in m.state.events if e[0] == "dispose"] == [1, 0]
	witness("construction-late-error-cleans-initialized-prefix", m, (2, 2, 2))
	m = Machine()
	step(m, "declare", "pair", "PairOwners")
	first = step(m, "acquire", "fresh_a")
	second = step(m, "acquire", "fresh_b")
	step(m, "begin", "pair", "Ready")
	step(m, "append", "pair", first, "fresh_a")
	step(m, "append", "pair", second, "fresh_b")
	step(m, "append", "pair", 1)
	step(m, "publish", "pair")
	step(m, "consume", "pair", ("bound_a", "bound_b", "scalar"))
	bindings = sorted((n for n in ("bound_a", "bound_b")), key=lambda n: m.state.cells[n].order, reverse=True)
	for name in bindings:
		step(m, "drop", name)
	assert [e[1] for e in m.state.events if e[0] == "dispose"] == [1, 0], "consuming bindings must initialize in declaration order"
	witness("consuming-bindings-reverse-scope-cleanup", m, (2, 4, 2))
	m = owned_value()
	step(m, "declare", "incoming", "BufferState", 1)
	owner = step(m, "acquire", "fresh", 1)
	step(m, "begin", "incoming", "Ready")
	step(m, "append", "incoming", owner, "fresh")
	step(m, "publish", "incoming")
	# The producing function now fails its validation instead of returning this
	# complete candidate. No replacement edge has reached the old destination.
	step(m, "drop", "incoming")
	assert m.state.cells["value"].phase == "live" and m.state.cells["value"].value.payload == (Owner(0),)
	witness("failed-incoming-producer-preserves-old-destination", m, (2, 2, 1))
	m = Machine()
	step(m, "acquire", "named", 0)
	step(m, "begin_consumer", "call")
	step(m, "reserve", "named", "arg0", "call")
	refuses("reserved-name-unavailable-to-later-argument", m, "read", "named", 0)
	step(m, "acquire", "fresh_argument", 1)
	step(m, "abort_arguments", "call")
	step(m, "drop", "fresh_argument")
	assert m.state.cells["named"].phase == "live"
	witness("late-argument-error-local-handler-retains-named-owner", m, (2, 0, 1))
	step(m, "begin_consumer", "retry")
	step(m, "reserve", "named", "arg0", "retry")
	step(m, "commit_arguments", "retry")
	step(m, "drop", "arg0")
	witness("callee-consumes-then-errors", m, (2, 1, 2))
	m = Machine()
	step(m, "acquire", "named", 0)
	step(m, "begin_consumer", "call")
	step(m, "reserve", "named", "arg0", "call")
	step(m, "acquire", "fresh_argument", 1)
	step(m, "declare", "late_error", "Decode", 1)
	step(m, "construct", "late_error", "Magic")
	m.state.handlers = (Handler("Decode", "catch", 0),)
	step(m, "route", "late_error", "call")
	assert m.state.cells["named"].phase == "live"
	witness("late-error-aborts-reservations-at-local-handler", m, (2, 0, 1))
	m = Machine()
	step(m, "acquire", "outer", 0)
	step(m, "acquire", "inner", 1)
	step(m, "declare", "err", "Decode", 1)
	step(m, "construct", "err", "Version", (7,))
	m.state.handlers = (Handler("Decode", "outer_catch", 0), Handler("Load", "wrong_inner", 1))
	step(m, "route", "err")
	assert m.state.cells["outer"].phase == "live" and m.state.cells["inner"].phase == "dropped"
	witness("nearest-exact-handler-skips-other-domain", m, (2, 0, 1))
	m.state.handlers = ()
	m.state.function_error = "Decode"
	step(m, "route", "outer_catch")
	witness("same-domain-rethrow-cleans-remaining-scope", m, (2, 0, 2))
	m = Machine()
	step(m, "declare", "load", "Load", 1)
	step(m, "construct", "load", "Decode", (Value("Decode", "End", (1, 4)),))
	m.state.function_error = "Load"
	step(m, "route", "load")
	witness("explicit-nominal-wrapping", m, (0, 0, 0), "Load.Decode(Decode.End(1,4))")
	m = Machine()
	step(m, "acquire", "local", 1)
	step(m, "declare", "return_expression_error", "Decode", 1)
	step(m, "construct", "return_expression_error", "End", (1, 4))
	m.state.function_error = "Decode"
	step(m, "route", "return_expression_error")
	witness("return-expression-error-cleans-live-locals", m, (1, 0, 1))
	# Future owning-error extension compatibility, not initial ERROR-1 admission.
	m = owned_value("FutureOwnedError", "Reason", 1)
	m.state.function_error = "FutureOwnedError"
	step(m, "route", "value")
	step(m, "drop", "return_error")
	witness("future-owning-error-forward-and-ignore", m, (1, 2, 1))
	m = owned_value("FutureOwnedError", "Reason", 1)
	m.state.handlers = (Handler("FutureOwnedError", "caught", 0),)
	step(m, "route", "value")
	# A handler's new failure goes outside that handler. The first owning error
	# is a local responsibility and is disposed when the handler exits.
	m.state.handlers = ()
	m.state.function_error = "Decode"
	step(m, "declare", "second_error", "Decode", 1)
	step(m, "construct", "second_error", "Magic")
	# Handler locals, including its binding, live inside the handler scope.
	m.state.cells["caught"].scope = 1
	step(m, "route", "second_error")
	witness("handler-fails-cleans-original-owning-error", m, (1, 2, 1))
	for cancelled in (False, True):
		m = Machine()
		if cancelled:
			step(m, "cancel")
		value = Value("Completion<int,Decode>", "Cancelled" if cancelled else "Success", () if cancelled else (3,))
		refuses("retirement-required-" + str(cancelled), m, "publish_completion", value)
		step(m, "retire")
		step(m, "publish_completion", value)
		destination = step(m, "observe_completion", True)
		assert destination == ("cancel_exit" if cancelled else "success")
		refuses("single-observer-" + str(cancelled), m, "observe_completion", True)
		witness("abstract-retired-completion-" + str(cancelled), m, (0, 0, 0))
	m = Machine()
	step(m, "retire")
	step(m, "publish_completion", Value("Completion<int,Decode>", "Error", (Value("Decode", "Magic"),)))
	assert step(m, "observe_completion", True) == "error_handler"
	witness("async-error-only-ordinary-channel", m, (0, 0, 0))


def explicit_path(identity, variant, payload):
	m = Machine()
	step(m, "declare", "outcome", identity, 1)
	if variant == "Success" and identity.startswith("ArrayResult"):
		owner = step(m, "acquire", "fresh", 1)
		step(m, "begin", "outcome", "Success")
		step(m, "append", "outcome", owner, "fresh")
		step(m, "publish", "outcome")
	else:
		step(m, "construct", "outcome", variant, payload)
		# Explicit policy: success is returned; ordinary error goes to same-domain root.
	if m.state.cells["outcome"].value.variant == "Error":
		step(m, "consume", "outcome", ("error",))
		m.state.function_error = "Decode"
		step(m, "route", "error")
		result = m.state.cells["return_error"].value
	else:
		step(m, "consume", "outcome", ("result",) if payload or identity.startswith("ArrayResult") else ())
		result = payload if not identity.startswith("ArrayResult") else "owned-buffer-0"
		if identity.startswith("ArrayResult"):
			step(m, "drop", "result")
	return m, result


def concise_path(identity, variant, payload):
	m = Machine()
	# Source evaluation count is outside this primitive value/cleanup model.
	step(m, "declare", "channel", identity, 1)
	if variant == "Error":
		step(m, "construct", "channel", "Error", payload)
		step(m, "consume", "channel", ("propagating",))
		m.state.function_error = "Decode"
		step(m, "route", "propagating")
		answer = m.state.cells["return_error"].value
	elif identity.startswith("ArrayResult"):
		owner = step(m, "acquire", "producer", 1)
		step(m, "begin", "channel", "Success")
		step(m, "append", "channel", owner, "producer")
		step(m, "publish", "channel")
		step(m, "consume", "channel", ("extracted",))
		answer = "owned-buffer-0"
		step(m, "drop", "extracted")
	else:
		step(m, "construct", "channel", "Success", payload)
		step(m, "consume", "channel", ("extracted",) if payload else ())
		answer = payload
	return m, answer


def equivalence():
	rows = []
	for identity, success in [("Result<int,Decode>", (7,)), ("Result<Header,Decode>", ((1, 4),)), ("VoidResult<Decode>", ()), ("ArrayResult<u8,Decode>", ())]:
		for variant, payload in [("Success", success), ("Error", (Value("Decode", "Version", (8,)),))]:
			left, lvalue = explicit_path(identity, variant, payload)
			right, rvalue = concise_path(identity, variant, payload)
			assert (lvalue, summary(left)) == (rvalue, summary(right))
			rows.append(dict(identity=identity, variant=variant, evaluation="SOURCE_OBLIGATION_NOT_EXECUTED", owner_events=summary(left), parity="PASS"))
	return rows


def mutations():
	m = owned_value()
	valid = m.state
	mutation("wrong-nominal-identity", valid, lambda s: setattr(s.cells["value"], "value", Value("Buffer", "Ready", (Owner(0),))), "nominal identity")
	mutation("invalid-tag", valid, lambda s: setattr(s.cells["value"], "value", Value("BufferState", "Bogus")), "valid tag")
	mutation("uninitialized-active-field", valid, lambda s: setattr(s.cells["value"], "value", Value("BufferState", "Ready")), "initialized active")
	mutation("inactive-payload-read", valid, lambda s: s.events.append(("read", Value("BufferState", "Empty"), 0)), "inactive payload read")
	mutation("inactive-payload-drop", valid, lambda s: s.events.append(("dispose", 0, "value", Value("BufferState", "Empty"), 0)), "inactive payload drop")
	def duplicate(s):
		s.cells["input"].phase = "live"
		s.cells["input"].value = Value("Buffer", "Ready", (Owner(0),))
	mutation("duplicated-owner", valid, duplicate, "duplicated owning")
	step(m, "borrow", "value", "view")
	mutation("borrow-retag", m.state, lambda s: setattr(s.cells["value"], "value", Value("BufferState", "Empty")), "borrow invalidated")
	mutation("borrow-replace", m.state, lambda s: setattr(s.cells["value"], "epoch", s.cells["value"].epoch + 1), "borrow invalidated")
	step(m, "end_borrow", "view")
	before = deepcopy(m.state)
	step(m, "consume", "value", (None,))
	mutation("payload-consumed-twice", m.state, lambda s: s.events.append(s.events[-1]), "disposed twice")
	def repeated_match(s):
		pass
	mutation("use-after-consuming-match-edge", m.state, repeated_match, "one consuming match", "consume", ("value", (None,)), m.state)
	m = Machine()
	step(m, "declare", "empty", "BufferState")
	step(m, "construct", "empty", "Empty")
	mutation("copy-move-only-empty", m.state, lambda s: s.events.append(("copy", "BufferState", "empty", "copy")), "copy of whole move-only")
	m = Machine()
	step(m, "declare", "application", "Result<int,Decode>")
	step(m, "construct", "application", "Success", (1,))
	mutation("wrong-generic-application-same-layout", m.state, lambda s: setattr(s.cells["application"], "value", Value("Result<int,OtherDecode>", "Success", (1,))), "nominal identity")
	m = owned_value()
	step(m, "declare", "destination", "BufferState")
	before = deepcopy(m.state)
	step(m, "move", "value", "destination")
	def wrong_instance(s):
		s.cells["destination"].value = Value("BufferState", "Empty")
		# Preserve a globally valid owner ledger while substituting a different
		# valid value for this program's expected source-to-destination edge.
		s.cells["input"].phase = "live"
		s.cells["input"].value = Value("Buffer", "Ready", (Owner(0),))
		s.events[-1] = ("transfer", 0, "value", "input")
	mutation("valid-alternative-wrong-instance-correspondence", m.state, wrong_instance, "whole value movement", "move", ("value", "destination"), before)
	m = Machine()
	step(m, "declare", "pair", "PairOwners")
	a = step(m, "acquire", "a")
	b = step(m, "acquire", "b")
	step(m, "begin", "pair", "Ready")
	step(m, "append", "pair", a, "a")
	step(m, "append", "pair", b, "b")
	step(m, "append", "pair", 1)
	step(m, "publish", "pair")
	before = deepcopy(m.state)
	step(m, "consume", "pair", ("first", "second", None))
	def reverse_bindings(s):
		s.cells["first"].order, s.cells["second"].order = s.cells["second"].order, s.cells["first"].order
	mutation("reversed-consuming-binding-initialization", m.state, reverse_bindings, "binding initialization declaration order", "consume", ("pair", ("first", "second", None)), before)
	m = Machine()
	step(m, "declare", "build", "PairOwners")
	step(m, "begin", "build", "Ready")
	owner = step(m, "acquire", "fresh")
	step(m, "append", "build", owner, "fresh")
	mutation("early-publication-failed-construction", m.state, lambda s: setattr(s.cells["build"], "phase", "live"), "initialized active fields")
	m = Machine()
	step(m, "acquire", "local", 1)
	step(m, "declare", "err", "Decode", 1)
	step(m, "construct", "err", "Magic")
	m.state.function_error = "Decode"
	before = deepcopy(m.state)
	step(m, "route", "err")
	def missing_cleanup(s):
		s.cells["local"] = deepcopy(before.cells["local"])
		s.events = [e for e in s.events if e[0] != "dispose"]
	mutation("missing-cleanup-on-propagation", m.state, missing_cleanup, "missing cleanup", "route", ("err",), before)
	mutation("wrong-error-domain", m.state, lambda s: s.events.append(("route", "OtherDecode", "return_error", -1, (), "Decode")), "wrong function error")
	mutation("wrong-handler-destination", m.state, lambda s: s.events.append(("route", "Decode", "outer", 0, (Handler("Decode", "inner", 1),), "Decode")), "nearest exact handler")
	m = Machine()
	step(m, "retire")
	step(m, "publish_completion", Value("Completion<int,Decode>", "Cancelled"))
	step(m, "observe_completion", True)
	mutation("cancellation-laundered-to-catch", m.state, lambda s: s.events.__setitem__(-1, ("observe", "Cancelled", "error_handler")), "cancellation laundered")
	for obligation in ("target", "release", "command", "registration", "queue"):
		mutation("premature-publication-" + obligation, m.state, lambda s, k=obligation: s.evidence.__setitem__(k, False), "command release" if obligation == "command" else "before retirement")
	mutation("observer-consumed-twice", m.state, lambda s: s.events.append(("observe", "Cancelled", "cancel_exit")), "single consuming observer")
	before = deepcopy(m.state)
	before.parent_cancelled = True
	mutation("parent-cancellation-request-erased", before, lambda s: setattr(s, "parent_cancelled", False), "monotone cancellation", "end_borrow", (), before)


def key(state):
	data = asdict(state)
	# Read/bind/copy administration has no owner effect. Preserve owner ledger and
	# every storage/borrow/reservation fact; no failing state is pruned before check.
	data["events"] = [e for e in data["events"] if e[0] in ("acquire", "transfer", "dispose")]
	return repr(data)


def actions(state, identity):
	for name, cell in state.cells.items():
		if name.startswith("o"):
			continue
		if cell.phase in ("uninitialized", "moved", "dropped"):
			for variant, fields in SCHEMAS[identity].items():
				if "owner" not in fields:
					payload = tuple(1 if t == "int" else Value("Decode", "Magic") for t in fields)
					yield ("construct", (name, variant, payload))
				else:
					yield ("begin", (name, variant))
		elif cell.phase == "staging":
			if len(cell.value.payload) == len(SCHEMAS[identity][cell.value.variant]):
				yield ("publish", (name,))
			else:
				for owner_name, owner in state.cells.items():
					if owner.expected == "Buffer" and owner.phase == "live":
						yield ("append", (name, owner.value.payload[0], owner_name))
			yield ("drop", (name,))
		elif cell.phase == "live":
			yield ("drop", (name,))
			yield ("borrow", (name, "view"))
			yield ("consume", (name, (None,) * len(cell.value.payload)))
			for other, target in state.cells.items():
				if other == name or target.expected != identity:
					continue
				if target.phase in ("uninitialized", "moved", "dropped"):
					yield ("move", (name, other))
					yield ("copy", (name, other))
				elif target.phase == "live":
					yield ("replace", (name, other))
	if "view" in state.borrows:
		yield ("end_borrow", ("view",))
	if any("owner" in fields for fields in SCHEMAS[identity].values()) and state.next_token < BOUNDS["explorer_owner_tokens"]:
		yield ("acquire", ("o" + str(state.next_token),))


def explore(identity):
	m = Machine()
	for name in ("x", "y"):
		step(m, "declare", name, identity)
	queue = deque([(m.state, ())])
	seen = {key(m.state)}
	edges, refusals, depth_frontier = 0, 0, 0
	while queue:
		state, trace = queue.popleft()
		check(state)
		if len(trace) == BOUNDS["exploration_steps"]:
			depth_frontier += 1
			continue
		for operation, args in actions(state, identity):
			candidate = Machine(state)
			try:
				getattr(candidate, operation)(*args)
			except Rejected:
				refusals += 1
				assert candidate.state == state, (trace, operation, args)
				continue
			new_trace = trace + ((operation, repr(args)),)
			try:
				edge(state, candidate.state, operation, args)
			except Invalid as error:
				raise AssertionError(dict(identity=identity, minimal_trace=new_trace, reason=str(error))) from error
			edges += 1
			fingerprint = key(candidate.state)
			if fingerprint in seen:
				continue
			if len(seen) == BOUNDS["state_cap_per_domain"]:
				return dict(identity=identity, states=len(seen), edges=edges, refusals=refusals, cap_hit=True, status="INCOMPLETE")
			seen.add(fingerprint)
			queue.append((candidate.state, new_trace))
	return dict(identity=identity, states=len(seen), edges=edges, refusals=refusals, depth_frontier=depth_frontier, cap_hit=False, status="PASS_WITHIN_DECLARED_DEPTH")


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("--output", type=Path, required=True)
	args = parser.parse_args()
	directed()
	parity = equivalence()
	mutations()
	review = regressions()
	exploration = [explore(t) for t in ("Decode", "BufferState", "ArrayResult<u8,Decode>")]
	status = "INCOMPLETE" if any(r["cap_hit"] for r in exploration) else "PASS"
	data = dict(status=status, scope="Proposed bounded semantics; no compiler, native ownership or universal proof", bounds=BOUNDS, directed=ROWS, equivalence=parity, mutations=MUTATIONS, review_regressions=review, explorer=exploration, python=sys.version, source_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(Path(__file__).parent.glob("*.py"))})
	args.output.parent.mkdir(parents=True, exist_ok=True)
	args.output.write_text(json.dumps(data, indent="\t") + "\n")
	print(json.dumps(dict(status=status, directed=len(ROWS), equivalence=len(parity), mutations=len(MUTATIONS), review_directed=len(review["directed"]), review_mutations=len(review["mutations"]), atomic_refusals=len(review["refusals"]), explorer=exploration)))
	return 0 if status == "PASS" else 1


if __name__ == "__main__":
	raise SystemExit(main())
