# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Directed independent oracles, mutation controls and bounded BFS exploration."""

from collections import Counter, deque
from dataclasses import replace
import argparse
import hashlib
import json
from pathlib import Path

from model import Event, Rejected, Task, candidates, initial, step, violations
from regressions import run_regressions


def apply(state, schedule):
	trace = []
	for item in schedule:
		action = (item, 0, "") if isinstance(item, str) else (*item, "") if len(item) == 2 else item
		state, events = step(state, *action)
		assert not violations(state), (action, violations(state))
		trace.extend(events)
	return state, trace


CREATE = ["capture", "publish_task"]
PENDING = CREATE + ["start", "pump", "suspend", "submit"]
SUCCESS = ["target", "drain", "retire", "pump", "return"]


def directed():
	rows = []
	def witness(name, state, schedule, expected, owner=None):
		state, trace = apply(state, schedule)
		assert trace == expected, (name, trace, expected)
		if owner is not None:
			assert state.tasks[0].owner == owner, (name, state.tasks[0])
		rows.append({"case": name, "trace": trace, "events": len(trace), "disposals": [t.disposals for t in state.tasks], "transfers": [t.transfers for t in state.tasks]})
		return state
	created = ["capture", "publish_task"]
	pending = created + ["start_deferred_body", "resume", "suspend", "submit"]
	success = ["target", "observed_target", "retire", "resume", "result_initialized", "result_published"]
	witness("never_started_drop", initial(), CREATE + ["destroy"], created + ["destroy"], "disposed")
	witness("immediate_owned_result", initial(Task(waits=0)), CREATE + ["start", "pump", "return", "observe", "destroy", "consumer_write", "consumer_dispose"], created + ["start_deferred_body", "resume", "result_initialized", "result_published", "observe", "destroy", "consumer_write", "consumer_dispose"], "disposed")
	witness("scalar_single_observer", initial(Task(mode="scalar", waits=0)), CREATE + ["start", "pump", "return", "observe", "destroy"], created + ["start_deferred_body", "resume", "result_initialized", "result_published", "observe", "destroy"], "disposed")
	witness("timer_owned_input_result", initial(), PENDING + SUCCESS + ["observe", "destroy", "consumer_dispose"], pending + success + ["observe", "destroy", "consumer_dispose"], "disposed")
	witness("discard_completed_payload", initial(), PENDING + SUCCESS + ["destroy"], pending + success + ["destroy"], "disposed")
	witness("partial_construction", initial(), ["capture", "fail_build", "destroy"], ["capture", "fail_build", "destroy"], "disposed")
	witness("failure_before_capture", initial(), ["fail_build", "destroy"], ["fail_build", "destroy"], "caller")
	fatal = witness("fatal_no_unwind", initial(), ["capture", "fatal"], ["capture", "fatal_nonunwinding"], "frame")
	assert fatal.fatal and fatal.tasks[0].disposals == 0
	witness("cancel_before_start", initial(), CREATE + ["cancel", "destroy"], created + ["cancel", "destroy"], "disposed")
	witness("cancel_before_registration", initial(), CREATE + ["start", "pump", "cancel", "return", "observe", "destroy"], created + ["start_deferred_body", "resume", "cancel", "result_initialized", "result_published", "observe", "destroy"], "disposed")
	witness("registration_error", initial(), CREATE + ["start", "pump", "register_error", "return", "destroy"], created + ["start_deferred_body", "resume", "register_error", "result_initialized", "result_published", "destroy"], "disposed")
	witness("owned_error_discard", initial(Task(mode="error_owner")), PENDING + [("target", 0, "error"), "drain", "retire", "pump", "return", "destroy"], pending + success + ["destroy"], "disposed")
	witness("cancel_ack_before_target", initial(), PENDING + ["cancel", "cancel_op", "ack", "drain", "access", ("target", 0, "cancel"), "drain", "retire", "pump", "return", "observe", "destroy"], pending + ["cancel", "cancel_op", "ack", "observed_ack", "access", "target", "observed_target", "retire", "resume", "result_initialized", "result_published", "observe", "destroy"], "disposed")
	witness("cancel_target_before_ack", initial(), PENDING + ["cancel", "cancel_op", ("target", 0, "cancel"), "drain", "ack", "drain", "retire", "pump", "return", "destroy"], pending + ["cancel", "cancel_op", "target", "observed_target", "ack", "observed_ack", "retire", "resume", "result_initialized", "result_published", "destroy"], "disposed")
	witness("completion_queued_then_cancel", initial(), PENDING + ["target", "cancel", "cancel_op", "ack", "drain", "drain", "retire", "pump", "return", "destroy"], pending + ["target", "cancel", "cancel_op", "ack", "observed_target", "observed_ack", "retire", "resume", "result_initialized", "result_published", "destroy"], "disposed")
	witness("cancel_after_result_keeps_success", initial(), PENDING + SUCCESS + ["cancel", "observe", "destroy", "consumer_dispose"], pending + success + ["cancel", "observe", "destroy", "consumer_dispose"], "disposed")
	witness("nonterminal_repeated", initial(Task(mode="repeated")), PENDING + ["more", "drain", "access"] + SUCCESS + ["destroy"], pending + ["more", "observed_more", "access"] + success + ["destroy"], "disposed")
	witness("result_then_late_buffer_release", initial(Task(mode="late")), PENDING + ["target", "drain", "access", "release", "drain", "retire", "pump", "return", "observe", "destroy", "consumer_write", "consumer_dispose"], pending + ["target", "observed_target", "access", "release", "observed_release", "retire", "resume", "result_initialized", "result_published", "observe", "destroy", "consumer_write", "consumer_dispose"], "disposed")
	witness("canceled_target_still_needs_promised_release", initial(Task(mode="late")), PENDING + ["cancel", "cancel_op", "ack", "drain", ("target", 0, "cancel"), "drain", "access", "release", "drain", "retire", "pump", "return", "destroy"], pending + ["cancel", "cancel_op", "ack", "observed_ack", "target", "observed_target", "access", "release", "observed_release", "retire", "resume", "result_initialized", "result_published", "destroy"], "disposed")
	witness("safe_parent_local_borrow", initial(Task(borrow=True)), PENDING + SUCCESS + ["destroy", "end_backing"], pending + success + ["destroy", "backing_released"], "disposed")
	witness("stable_frame_internal_view", initial(), PENDING + ["access"] + SUCCESS + ["destroy"], pending + ["access"] + success + ["destroy"], "disposed")
	witness("two_suspensions", initial(Task(waits=2)), PENDING + ["target", "drain", "retire", "pump", "suspend", ("submit", 1), ("target", 1), "drain", ("retire", 1), "pump", "return", "destroy"], pending + ["target", "observed_target", "retire", "resume", "suspend", "submit", "target", "observed_target", "retire", "resume", "result_initialized", "result_published", "destroy"], "disposed")
	witness("duplicate_wake_during_resume_registration", initial(), CREATE + ["start", "wake", "wake", "pump", "wake", "suspend", "submit", "pump"] + SUCCESS + ["destroy"], created + ["start_deferred_body", "wake_latched", "wake_latched", "resume", "wake_latched", "suspend", "submit", "spurious_wake_drained"] + success + ["destroy"], "disposed")
	witness("queued_retired_identity_after_frame_free", initial(), PENDING + SUCCESS + ["destroy", "replay", "drain"], pending + success + ["destroy", "stale_event_queued", "stale_identity_ignored"], "disposed")
	pressure = initial(Task(waits=0), Task(waits=0))
	schedule = CREATE + [("capture", 1), ("publish_task", 1), "start", ("start", 1), "pump", "wake", "return", "pump", ("return", 1), "destroy", ("destroy", 1)]
	witness("queue_pressure_fair_turn", pressure, schedule, created + created + ["start_deferred_body", "start_deferred_body", "resume", "wake_latched", "result_initialized", "result_published", "resume", "result_initialized", "result_published", "destroy", "destroy"])
	children = initial(Task(waits=0), Task(parent=0))
	schedule = CREATE + [("capture", 1), ("publish_task", 1), ("start", 1), "pump", ("suspend", 1), "submit", "shutdown", "cancel_op", "ack", "drain", ("target", 0, "cancel"), "drain", "retire", "pump", ("return", 1), ("destroy", 1), "destroy"]
	witness("parent_and_executor_shutdown", children, schedule, created + created + ["start_deferred_body", "resume", "suspend", "submit", "shutdown_requested", "cancel_op", "ack", "observed_ack", "target", "observed_target", "retire", "resume", "result_initialized", "result_published", "destroy", "destroy"])
	witness("cancel_prepared_unpublished_registration", initial(), CREATE + ["start", "pump", "suspend", "cancel", "revoke_prepared", "pump", "return", "destroy"], created + ["start_deferred_body", "resume", "suspend", "cancel", "revoke_prepared", "resume", "result_initialized", "result_published", "destroy"], "disposed")
	schedule = CREATE + [("capture", 1), ("publish_task", 1), ("start", 1), "pump", ("suspend", 1), "submit", "start", "pump", "shutdown", "join_children", "cancel_op", ("target", 0, "cancel"), "ack", "drain", "drain", "retire", "pump", ("return", 1), ("destroy", 1), "pump", "return", "destroy"]
	witness("running_parent_cancel_drains_child_first", children, schedule, created + created + ["start_deferred_body", "resume", "suspend", "submit", "start_deferred_body", "resume", "shutdown_requested", "join_children", "cancel_op", "target", "ack", "observed_target", "observed_ack", "retire", "resume", "result_initialized", "result_published", "destroy", "resume", "result_initialized", "result_published", "destroy"])
	return rows


def rejection_cases():
	rows = []
	def rejected(name, state, action):
		try:
			step(state, *action)
		except Rejected as error:
			rows.append({"case": name, "reason": str(error)})
		else:
			raise AssertionError(name)
	state, _ = apply(initial(Task(borrow=True)), CREATE)
	rejected("deferred_borrow_escape", state, ("end_backing",))
	state, _ = apply(initial(), PENDING)
	for name, action in [("active_drop", ("destroy",)), ("early_retire", ("retire",)), ("nested_pump", ("pump",))]:
		if name == "nested_pump":
			state_running, _ = apply(initial(), CREATE + ["start", "pump", "wake"])
			rejected(name, state_running, action)
		else:
			rejected(name, state, action)
	state, _ = apply(state, ["cancel", "cancel_op", "ack", "drain"])
	rejected("ack_is_not_target_quiescence", state, ("retire",))
	state, _ = apply(initial(Task(mode="late")), PENDING + ["target", "drain"])
	rejected("result_ready_is_not_buffer_release", state, ("retire",))
	state, _ = apply(initial(Task(waits=0)), CREATE + ["start", "pump", "return", "observe"])
	rejected("second_consumption", state, ("observe",))
	state, _ = apply(initial(), PENDING + ["target"])
	rejected("duplicate_terminal_event", state, ("target",))
	state, _ = apply(initial(Task(mode="late"), completion_capacity=1), PENDING + ["target"])
	rejected("completion_capacity_boundary", state, ("release",))
	state, _ = apply(initial(Task(waits=2), registration_limit=1), PENDING + ["target", "drain", "retire", "pump"])
	rejected("identity_exhaustion_no_reuse", state, ("suspend",))
	return rows


def mutations():
	rows = []
	def detected(name, state, required):
		errors = violations(state)
		assert required in errors, (name, errors)
		rows.append({"mutation": name, "detected": errors})
	pending, _ = apply(initial(), PENDING)
	task = pending.tasks[0]
	detected("premature_frame_free", replace(pending, tasks=(replace(task, frame=False, phase="dead"),)), "provider_use_after_release")
	detected("cancel_ack_frees_target", replace(pending, registrations=(replace(pending.registrations[0], access=False),)), "cancel_ack_is_not_quiescence")
	detected("fake_cancel_quiescence", replace(pending, registrations=(replace(pending.registrations[0], retired=True),)), "bad_retirement_or_cancel_ack")
	detected("premature_owner_disposal", replace(pending, tasks=(replace(task, owner="disposed", disposals=1),)), "provider_use_after_release")
	complete, _ = apply(initial(), PENDING + SUCCESS)
	task = complete.tasks[0]
	detected("lost_result_publication", replace(complete, tasks=(replace(task, initialized=False),)), "lost_publication")
	detected("duplicate_consumption", replace(complete, tasks=(replace(task, observations=2),)), "duplicate_owner_or_consumption")
	detected("double_disposal", replace(complete, tasks=(replace(task, disposals=2),)), "duplicate_owner_or_consumption")
	dead, _ = apply(complete, ["destroy"])
	detected("late_wake_reads_freed_frame", replace(dead, work=(0,)), "stale_frame_reference")
	ready, _ = apply(initial(), CREATE + ["start"])
	detected("drop_full_queue_wake_no_progress", replace(ready, work=(), tasks=(replace(ready.tasks[0], dirty=False),)), "lost_wake_progress")
	late, _ = apply(initial(Task(mode="late")), PENDING + ["target", "drain"])
	detected("early_delivery_overwrites_retained_buffer", replace(late, tasks=(replace(late.tasks[0], owner="consumer", observations=1, initialized=True, published=True, consumer_writes=1),)), "consumer_overwrites_retained_payload")
	borrowed, _ = apply(initial(Task(borrow=True)), CREATE)
	detected("forget_deferred_borrow_lease", replace(borrowed, backing_live=False), "released_borrow_backing")
	queued, _ = apply(initial(), PENDING + ["target"])
	detected("retire_with_queued_target", replace(queued, registrations=(replace(queued.registrations[0], terminal_seen=True, retired=True),)), "queued_retired_registration")
	children = initial(Task(waits=0), Task(parent=0))
	detected("parent_cleanup_before_child_join", replace(children, tasks=(replace(children.tasks[0], phase="dead", frame=False), children.tasks[1])), "parent_join_before_cleanup")
	two = initial(Task(), Task())
	detected("two_holders_acquire_same_owner", replace(two, tasks=(two.tasks[0], replace(two.tasks[1], owner_id=two.tasks[0].owner_id))), "duplicate_owner_identity")
	return rows


def fair_drain(state, scope=None):
	"""One explicit fair drain strategy, not proof of every fair infinite trace."""
	selected = set(range(len(state.tasks))) if scope is None else {scope} | {i for i, t in enumerate(state.tasks) if t.parent == scope}
	original_closing = state.closing
	unrelated_cancel = {i: t.cancel for i, t in enumerate(state.tasks) if i not in selected}
	state, _ = step(state, "shutdown" if scope is None else "cancel", scope or 0)
	for turns in range(65):
		if scope is not None:
			assert state.closing == original_closing and all(state.tasks[i].cancel == flag for i, flag in unrelated_cancel.items())
		assert not violations(state), violations(state)
		if not any(t.frame for i, t in enumerate(state.tasks) if i in selected) and not state.completions and not state.work:
			assert all(r.retired for r in state.registrations)
			return turns
		actions = []
		if state.completions:
			actions.append(("drain",))
		for i, r in enumerate(state.registrations):
			if r.retired or r.task not in selected:
				continue
			if not r.submitted:
				actions.append(("revoke_prepared", i))
			elif not r.terminal_sent:
				actions.extend([("cancel_op", i), ("target", i, "cancel")])
			if r.cancel_sent and not r.ack_sent:
				actions.append(("ack", i))
			if r.terminal_sent and not r.release_sent:
				actions.append(("release", i))
			actions.append(("retire", i))
		for i, task in reversed(list(enumerate(state.tasks))):
			if i not in selected:
				continue
			if task.phase == "building":
				actions.append(("fail_build", i))
			if task.phase == "running":
				actions.extend([("join_children", i), ("return", i)])
			if task.phase == "terminal" and task.waiter >= 0 and task.observations == 0:
				actions.append(("observe", i))
			if task.phase in ("new", "terminal", "failed"):
				actions.append(("destroy", i))
		actions.append(("pump",))
		for action in actions:
			try:
				next_state, _ = step(state, *action)
			except Rejected:
				continue
			if next_state != state:
				state = next_state
				break
		else:
			raise AssertionError(("no fair drain progress", scope, state))
	raise AssertionError("fair closure bound exceeded")


def explore(seed, depth_limit=16, state_limit=100000, scoped_parent=None):
	queue = deque([(seed, 0)])
	seen = {seed}
	accepted = 0
	rejected = Counter()
	boundary = 0
	max_shutdown_turns = 0
	max_scoped_turns = 0
	scoped_states = 0
	while queue:
		state, depth = queue.popleft()
		assert not violations(state), violations(state)
		max_shutdown_turns = max(max_shutdown_turns, fair_drain(state))
		if scoped_parent is not None and state.tasks[scoped_parent].frame:
			max_scoped_turns = max(max_scoped_turns, fair_drain(state, scoped_parent))
			scoped_states += 1
		if depth == depth_limit:
			boundary += 1
			continue
		for action in candidates(state):
			try:
				next_state, _ = step(state, *action)
			except Rejected as error:
				rejected[str(error)] += 1
				continue
			accepted += 1
			assert not violations(next_state), (action, violations(next_state))
			if next_state not in seen:
				seen.add(next_state)
				assert len(seen) <= state_limit, "prospective state cap exceeded; qualification incomplete"
				queue.append((next_state, depth + 1))
	return {"states": len(seen), "accepted_transitions": accepted, "rejected_actions": sum(rejected.values()), "rejection_reasons": dict(sorted(rejected.items())), "depth_boundary_states": boundary, "depth_limit": depth_limit, "state_limit": state_limit, "conditional_fair_shutdown_states": len(seen), "maximum_shutdown_actions": max_shutdown_turns, "conditional_scoped_cancel_states": scoped_states, "maximum_scoped_cancel_actions": max_scoped_turns}


def run(output):
	assert not output.exists(), "retain earlier evidence; use a fresh output path"
	rows = directed()
	negative = rejection_cases()
	controls = mutations()
	new_rows, new_rejections, new_controls = run_regressions(apply)
	rows.extend(new_rows)
	negative.extend(new_rejections)
	controls.extend(new_controls)
	domains = [("one_timer", initial()), ("one_repeated", initial(Task(mode="repeated"))), ("one_late_release", initial(Task(mode="late"))), ("one_scoped_borrow", initial(Task(borrow=True))), ("two_immediate_tasks", initial(Task(waits=0), Task(waits=0))), ("timer_with_runnable_sibling", initial(Task(), Task(waits=0))), ("parent_child", initial(Task(waits=0), Task(parent=0)))]
	exploration = {name: explore(seed, scoped_parent=0 if name == "parent_child" else None) for name, seed in domains}
	result = {"status": "PASS", "model": "portable sequential lifecycle plus abstract provider access", "directed": rows, "rejections": negative, "negative_controls": controls, "exploration": exploration, "bounds": {"tasks": 2, "directed_scoped_tasks": 3, "directed_enrollment_capacity": [1, 2, 3], "enrollment_capacity": 2, "owners_per_task": 1, "registration_identities": 2, "work_capacity": 1, "completion_capacity": 2, "explorer_steps": 16, "directed_waits": 2, "repeated_nonterminal_events": 1}, "source_identities": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__), Path(__file__).with_name('model.py'), Path(__file__).with_name('regressions.py')]}, "limits": ["No kernel, Astra, allocator or thread execution", "Abstract events are atomic; shared-ring memory ordering is outside model", "Depth-bounded safety, not all schedules", "Progress needs recurring fair pump/drain, finite cooperative turns and eventual target/payload/cancel-command completions", "No fatal cleanup promise", "Borrow admission is modeled permission, not compiler proof", "Replay tokens tested directly; no ID wrap or reuse in finite exploration"]}
	output.parent.mkdir(parents=True, exist_ok=True)
	output.write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps({"status": result['status'], "directed": len(rows), "rejections": len(negative), "negative_controls": len(controls), "exploration": {k: {f: v[f] for f in ['states', 'accepted_transitions', 'rejected_actions', 'depth_boundary_states']} for k, v in exploration.items()}}))


if __name__ == "__main__":
	parser = argparse.ArgumentParser()
	parser.add_argument("--output", type=Path, required=True)
	run(parser.parse_args().output)
