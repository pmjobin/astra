# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fixed directed domains for E01–E03; independent forged-edge controls."""

from copy import deepcopy
from dataclasses import replace

from checker import Invalid, check, edge
from model import Cell, Handler, Machine, Owner, Rejected, Value


def regressions():
	rows, mutations, refusals = [], [], []
	traces = {}

	def step(m, operation, *args):
		before = deepcopy(m.state)
		result = getattr(m, operation)(*args)
		edge(before, m.state, operation, args)
		traces.setdefault(id(m), []).append((operation, repr(args)))
		return result

	def positive(name, m, expected, observation):
		counts = check(m.state)
		actual = [counts[k] for k in ("acquire", "transfer", "dispose")]
		assert actual == list(expected), (name, actual, expected)
		rows.append(dict(name=name, owner_events=actual, observation=observation, trace=list(traces[id(m)])))

	def exercise(m, operation, args, controls):
		before = deepcopy(m.state)
		step(m, operation, *args)
		valid = deepcopy(m.state)
		for name, corrupt, reason, globally_valid in controls:
			edge(before, valid, operation, args)
			forged = deepcopy(valid)
			corrupt(forged)
			if globally_valid:
				check(forged)
			try:
				edge(before, forged, operation, args)
			except Invalid as error:
				assert reason in str(error), (name, reason, str(error))
				mutations.append(dict(name=name, detected=str(error), global_state_check="PASS" if globally_valid else "NOT_REQUIRED", trace=list(traces[id(m)]), correct_before="PASS", restored_edge="PASS"))
			else:
				raise AssertionError("accepted forged edge: " + name)
			edge(before, valid, operation, args)
		return before, valid

	def refuse(name, m, operation, *args):
		before = deepcopy(m.state)
		try:
			getattr(m, operation)(*args)
		except Rejected as error:
			assert m.state == before, (name, "partial refusal")
			check(m.state)
			refusals.append(dict(name=name, operation=operation, reason=str(error), state_unchanged=True))
			return
		raise AssertionError("accepted malformed request: " + name)

	def pair():
		m = Machine()
		traces[id(m)] = []
		step(m, "declare", "pair", "PairOwners")
		a = step(m, "acquire", "a")
		b = step(m, "acquire", "b")
		step(m, "begin", "pair", "Ready")
		step(m, "append", "pair", a, "a")
		step(m, "append", "pair", b, "b")
		step(m, "append", "pair", 7)
		step(m, "publish", "pair")
		return m

	def error(m, scope, target, handler_scope, consumer=None):
		step(m, "declare", "error", "Decode", scope)
		step(m, "construct", "error", "Magic")
		m.state.handlers = (Handler("Decode", target, handler_scope, consumer),)

	def swap_owners(s):
		s.cells["left"].value, s.cells["right"].value = s.cells["right"].value, s.cells["left"].value
		s.events = [(e[0], e[1], e[2], {"left": "right", "right": "left"}[e[3]]) if e[0] == "transfer" and e[2] == "pair" else e for e in s.events]

	def substitute_target(s):
		s.cells["unrelated"] = s.cells.pop("left")
		s.events = [(*e[:3], "unrelated") if e[0] == "transfer" and e[2:] == ("pair", "left") else e for e in s.events]

	def substitute_existing_target(s):
		bound = s.cells.pop("left")
		s.cells["a"].value, s.cells["a"].phase = bound.value, "live"
		s.events = [(*e[:3], "a") if e[0] == "transfer" and e[2:] == ("pair", "left") else e for e in s.events]

	m = pair()
	controls = [
		("E01-coherent-owner-field-swap", swap_owners, "selected payload binding correspondence", True),
		("E01-missing-requested-target", substitute_target, "binding initialization declaration order", True),
		("E01-bound-field-into-unrelated-existing-cell", substitute_existing_target, "binding initialization declaration order", True),
		("E01-undeclared-extra-binding", lambda s: s.cells.__setitem__("extra", Cell("Colour", Value("Colour", "Red"), "live")), "selected payload binding correspondence", True),
	]
	exercise(m, "consume", ("pair", ("left", "right", None)), controls)
	assert m.state.cells["left"].value.payload[0].token == 0 and m.state.cells["right"].value.payload[0].token == 1
	step(m, "drop", "right")
	step(m, "drop", "left")
	assert [e[1] for e in m.state.events if e[0] == "dispose"] == [1, 0]
	positive("E01-selected-two-owners-reverse-arm-cleanup", m, (2, 4, 2), "left=0, right=1; source disarmed")

	m = pair()
	def redirect_ignored(s):
		s.cells["a"].phase = "live"
		s.cells["a"].value = Value("Buffer", "Ready", (Owner(0),))
		s.events = [("transfer", 0, "pair", "a") if e[0] == "dispose" and e[1] == 0 else e for e in s.events]
	exercise(m, "consume", ("pair", (None, "right", "tag")), [("E01-ignored-owner-redirected-to-existing-cell", redirect_ignored, "selected payload binding correspondence", True)])
	positive("E01-ignore-owning-field-and-copy-scalar", m, (2, 3, 1), "owner 0 disposed; owner 1 bound; tag=7")
	m = pair()
	def reversed_disposal(s):
		indices = [i for i, e in enumerate(s.events) if e[0] == "dispose"]
		s.events[indices[0]], s.events[indices[1]] = s.events[indices[1]], s.events[indices[0]]
	exercise(m, "consume", ("pair", (None, None, "tag")), [("E01-ignore-disposal-order", reversed_disposal, "selected payload event delta/order", True)])
	positive("E01-ignore-both-owners", m, (2, 2, 2), "ignored active owners dispose 1 then 0")

	for name, identity, variant, payload, bindings in [
		("scalar", "Decode", "End", (2, 4), ("at", "need")),
		("record", "Result<Header,Decode>", "Success", ((1, 4),), ("header",)),
		("nested", "Load", "Decode", (Value("Decode", "End", (2, 4)),), ("cause",)),
	]:
		m = Machine()
		traces[id(m)] = []
		step(m, "declare", "value", identity)
		step(m, "construct", "value", variant, payload)
		def wrong_snapshot(s):
			if name == "nested":
				s.cells["cause"].value = Value("Decode", "End", (4, 2))
			else:
				indices = [i for i, e in enumerate(s.events) if e[0] == "bind_copy"]
				if name == "scalar":
					for i in indices:
						e = s.events[i]
						s.events[i] = (*e[:3], 4 if e[3] == 2 else 2)
				else:
					i = indices[0]
					s.events[i] = (*s.events[i][:3], (4, 1))
		exercise(m, "consume", ("value", bindings), [("E01-" + name + "-snapshot-correspondence", wrong_snapshot, "selected payload binding" if name == "nested" else "selected payload event delta/order", True)])
		positive("E01-correct-" + name + "-snapshot", m, (0, 0, 0), repr(payload))
		if name == "scalar":
			error(m, 2, "catch", 0)
			step(m, "route", "error")
			assert not m.state.borrows
			positive("E02-scalar-snapshots-create-no-loan", m, (0, 0, 0), "copied scalar values do not keep a root loan")
	m = pair()
	refuse("E01-duplicate-binding-atomic", m, "consume", "pair", ("same", "same", None))
	refuse("E01-existing-binding-atomic-before-ignore", m, "consume", "pair", (None, "a", None))

	# Exited inspection loans and surviving loans use distinct lexical extents.
	m = Machine()
	traces[id(m)] = []
	step(m, "declare", "value", "BufferState", 1)
	owner = step(m, "acquire", "input", 1)
	step(m, "begin", "value", "Ready")
	step(m, "append", "value", owner, "input")
	step(m, "publish", "value")
	step(m, "borrow", "value", "arm", 2)
	error(m, 2, "catch", 0)
	def cleanup_first(s):
		end = next(i for i, e in enumerate(s.events) if e[0] == "loan_end")
		dispose = next(i for i, e in enumerate(s.events) if e[0] == "dispose")
		s.events[end], s.events[dispose] = s.events[dispose], s.events[end]
	exercise(m, "route", ("error",), [("E02-owner-cleanup-before-loan-end", cleanup_first, "scoped route event order", True)])
	assert not m.state.borrows and m.state.cells["value"].phase == "dropped"
	positive("E02-error-exits-arm-and-owner", m, (1, 1, 1), "arm loan ends before owner disposal and handler entry")

	m = Machine()
	traces[id(m)] = []
	step(m, "acquire", "outer", 0)
	step(m, "borrow", "outer", "outer_view", 1)
	error(m, 2, "catch", 1)
	def premature_end(s):
		s.events.append(("loan_end", "outer_view", s.borrows.pop("outer_view")))
	exercise(m, "route", ("error",), [("E02-premature-surviving-loan-end", premature_end, "scoped loan exit mapping", True)])
	assert "outer_view" in m.state.borrows
	positive("E02-handler-inside-same-arm", m, (1, 0, 0), "outer_view remains live")
	refuse("E02-surviving-loan-still-blocks-drop", m, "drop", "outer")
	step(m, "end_borrow", "outer_view")
	step(m, "drop", "outer")
	positive("E02-ordinary-arm-completion", m, (1, 0, 1), "ordinary end then owner cleanup")

	m = Machine()
	traces[id(m)] = []
	step(m, "acquire", "outer", 0)
	step(m, "borrow", "outer", "outer_view", 1)
	step(m, "acquire", "inner", 2)
	step(m, "borrow", "inner", "inner_view", 3)
	error(m, 3, "catch", 1)
	def wrong_loan_mapping(s):
		s.events.append(("loan_end", "outer_view", s.borrows.pop("outer_view")))
	exercise(m, "route", ("error",), [("E02-crossed-and-surviving-loan-map", wrong_loan_mapping, "scoped loan exit mapping", True)])
	assert set(m.state.borrows) == {"outer_view"}
	positive("E02-inner-loan-exits-outer-loan-survives", m, (2, 0, 1), "inner disposed once; outer retains its loan")
	m.state.handlers = (Handler("Decode", "outer", 0),)
	refuse("E02-route-target-conflict-atomic", m, "route", "catch")
	m.state.handlers = (Handler("Decode", "new_catch", 1),)
	step(m, "borrow", "catch", "error_view", 1)
	refuse("E02-surviving-error-loan-refusal-atomic", m, "route", "catch")

	# Consumer ancestry, including equal-depth independent consumers, is exact.
	def pending_pair():
		m = Machine()
		traces[id(m)] = []
		step(m, "acquire", "a", 0)
		step(m, "acquire", "b", 0)
		step(m, "begin_consumer", "outer", None, 0)
		step(m, "begin_consumer", "other", None, 0)
		step(m, "reserve", "a", "outer_arg", "outer")
		step(m, "reserve", "b", "other_arg", "other")
		step(m, "begin_consumer", "inner", "outer", 1)
		return m

	m = pending_pair()
	error(m, 2, "catch", 1, "outer")
	def wrong_consumer(s):
		r = s.reservations.pop("a")
		s.cells["a"].phase = "live"
		frame = s.consumers["outer"]
		s.consumers["outer"] = replace(frame, phase="aborted")
		s.events.append(("abort", "outer", (("a", r.argument),)))
	def expose_early(s):
		del s.reservations["a"]
		s.cells["a"].phase = "live"
	controls = [("E03-wrong-consumer-abort", wrong_consumer, "route consumer abort authority", True), ("E03-surviving-reservation-exposed-early", expose_early, "route consumer abort authority", True)]
	exercise(m, "route", ("error", "inner"), controls)
	assert set(m.state.reservations) == {"a", "b"}
	positive("E03-inner-recovery-preserves-two-pending-consumers", m, (2, 0, 0), "consume_pair(move a, recover_second()); outer and other remain reserved")
	refuse("E03-surviving-reservation-not-usable", m, "read", "a", 0)
	before_commit = deepcopy(m.state)
	def missing_commit(s):
		s.__dict__.update(deepcopy(before_commit.__dict__))
	def duplicate_commit(s):
		s.events.append(s.events[-1])
	controls = [
		("E03-missing-later-commit", missing_commit, "consumer commit/abort authority", True),
		("E03-duplicate-commit-event", duplicate_commit, "consumer event delta/commit once", True),
	]
	exercise(m, "commit_arguments", ("outer",), controls)
	refuse("E03-duplicate-commit-request", m, "commit_arguments", "outer")
	assert m.state.cells["a"].phase == "moved" and m.state.cells["outer_arg"].value.payload[0].token == 0
	step(m, "commit_arguments", "other")
	positive("E03-surviving-consumers-each-commit-once", m, (2, 2, 0), "outer_arg=0; other_arg=1")

	m = pending_pair()
	error(m, 2, "catch", 0)
	def abort_other(s):
		r = s.reservations.pop("b")
		s.cells["b"].phase = "live"
		frame = s.consumers["other"]
		s.consumers["other"] = replace(frame, phase="aborted")
		s.events.append(("abort", "other", (("b", r.argument),)))
	exercise(m, "route", ("error", "inner"), [("E03-same-scope-unrelated-consumer-abort", abort_other, "route consumer abort authority", True)])
	assert m.state.cells["a"].phase == "live" and set(m.state.reservations) == {"b"}
	positive("E03-error-escapes-aborts-only-enclosing-invocation", m, (2, 0, 0), "a restored; independent b remains reserved")
	step(m, "begin_consumer", "retry")
	step(m, "reserve", "a", "retry_arg", "retry")
	step(m, "commit_arguments", "retry")
	positive("E03-same-scope-abort-retry", m, (2, 1, 0), "retry delivers owner 0 exactly once")

	for escapes in (False, True):
		m = Machine()
		traces[id(m)] = []
		step(m, "acquire", "a", 0)
		step(m, "acquire", "b", 0)
		step(m, "begin_consumer", "outer")
		step(m, "reserve", "a", "outer_arg", "outer")
		step(m, "begin_consumer", "committed_inner", "outer", 1)
		step(m, "reserve", "b", "inner_arg", "committed_inner")
		step(m, "commit_arguments", "committed_inner")
		step(m, "declare", "effect", "Buffer", 0)
		step(m, "move", "inner_arg", "effect")
		step(m, "begin_consumer", "recover", "outer", 1)
		error(m, 2, "catch", 0 if escapes else 1, None if escapes else "outer")
		def resurrect_committed(s):
			s.cells["b"].phase = "live"
			s.cells["b"].value = s.cells["effect"].value
			s.cells["effect"].value, s.cells["effect"].phase = None, "moved"
			s.events.append(("transfer", 1, "effect", "b"))
		exercise(m, "route", ("error", "recover"), [("E03-committed-owner-resurrection-" + str(escapes), resurrect_committed, "route cell cleanup/restoration", True)])
		assert m.state.cells["b"].phase == "moved" and m.state.cells["effect"].phase == "live"
		assert m.state.cells["a"].phase == ("live" if escapes else "reserved")
		positive("E03-nested-committed-effect-survives-" + str(escapes), m, (2, 2, 0), "committed inner move remains an effect; b never resurrects")

	m = Machine()
	traces[id(m)] = []
	step(m, "acquire", "a", 1)
	step(m, "begin_consumer", "outer", None, 1)
	step(m, "reserve", "a", "arg", "outer")
	error(m, 2, "catch", 0)
	step(m, "route", "error", "outer")
	assert m.state.cells["a"].phase == "dropped"
	positive("E03-aborted-source-scope-exits", m, (1, 0, 1), "restore responsibility then dispose exactly once")

	m = pending_pair()
	error(m, 2, "catch", 1, "other")
	refuse("E03-missing-current-consumer-atomic", m, "route", "error")
	refuse("E03-handler-is-not-enclosing-consumer-atomic", m, "route", "error", "inner")
	refuse("E03-pending-child-prevents-early-commit", m, "commit_arguments", "outer")
	refuse("E03-reserve-wrong-consumer-atomic", m, "reserve", "a", "bad", "unknown")
	return dict(status="PASS", bounds=dict(kind="fixed directed programs; no call-stack exploration", owner_tokens_per_program=2, consumer_ancestry_depth=2, loan_extents_per_program=2, payload_nesting=3), directed=rows, mutations=mutations, refusals=refusals)
