# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""R3 expected scoped traces and independent evidence/right corruption controls."""

from dataclasses import replace

from model import Rejected, Task, initial, step, violations


CREATE = ["capture", "publish_task"]
PENDING = CREATE + ["start", "pump", "suspend", "submit"]
CHILD_PENDING = CREATE + [("capture", 1), ("publish_task", 1), ("start", 1), "pump", ("suspend", 1), "submit", "start", "pump"]
CREATED = ["capture", "publish_task"]
PENDING_TRACE = CREATED + ["start_deferred_body", "resume", "suspend", "submit"]
CHILD_TRACE = CREATED + CREATED + ["start_deferred_body", "resume", "suspend", "submit", "start_deferred_body", "resume"]
PUBLISHED = ["result_initialized", "result_published"]
DRAIN_CANCEL = ["cancel_op", ("target", 0, "cancel"), "ack", "drain", "drain", "retire", "pump", ("return", 1)]
DRAIN_TRACE = ["cancel_op", "target", "ack", "observed_target", "observed_ack", "retire", "resume"] + PUBLISHED


def run_regressions(apply):
	rows, controls, rejections = [], [], []
	def witness(name, seed, schedule, expected):
		state, trace = apply(seed, schedule)
		assert trace == expected, (name, trace, expected)
		rows.append({"case": name, "trace": trace, "events": len(trace), "disposals": [t.disposals for t in state.tasks], "transfers": [t.transfers for t in state.tasks]})
		return state
	def detected(name, state, required):
		errors = violations(state)
		assert required in errors, (name, errors)
		controls.append({"mutation": name, "detected": errors})
	def rejected(name, state, action):
		try:
			step(state, *action)
		except Rejected as error:
			rejections.append({"case": name, "reason": str(error)})
		else:
			raise AssertionError(name)
	children = initial(Task(waits=0), Task(parent=0))
	schedule = CHILD_PENDING + ["cancel", "join_children"] + DRAIN_CANCEL + [("destroy", 1), "pump", "return", "destroy"]
	state = witness("scoped_parent_only_cancel", children, schedule, CHILD_TRACE + ["cancel", "join_children"] + DRAIN_TRACE + ["destroy", "resume"] + PUBLISHED + ["destroy"])
	assert not state.closing and all(t.outcome == "cancel" for t in state.tasks)
	awaiting, _ = apply(children, CHILD_PENDING + [("await_child", 1)])
	assert awaiting.tasks[0].phase == "awaiting" and not awaiting.tasks[1].handle and awaiting.tasks[1].waiter == 0 and awaiting.tasks[1].observations == 0
	cancelled, _ = apply(awaiting, ["cancel"])
	assert cancelled.tasks[0].phase == "joining" and cancelled.tasks[1].cancel and cancelled.tasks[1].waiter == 0
	schedule = CHILD_PENDING + [("await_child", 1), "cancel"] + DRAIN_CANCEL + [("observe", 1), ("destroy", 1), "pump", "return", "destroy"]
	state = witness("cancel_while_consuming_await_pending", children, schedule, CHILD_TRACE + ["await_child", "cancel"] + DRAIN_TRACE + ["observe", "destroy", "resume"] + PUBLISHED + ["destroy"])
	assert not state.closing and state.tasks[1].observations == 1 and state.tasks[1].transfers == 0
	witness("cancel_pending_parent_local_loan", initial(Task(waits=0), Task(parent=0, borrow=True)), schedule + ["end_backing"], CHILD_TRACE + ["await_child", "cancel"] + DRAIN_TRACE + ["observe", "destroy", "resume"] + PUBLISHED + ["destroy", "backing_released"])
	state = witness("pending_await_owned_result_outlives_child_frame", children, CHILD_PENDING + [("await_child", 1), "target", "drain", "retire", "pump", ("return", 1), ("observe", 1), ("destroy", 1), ("consumer_write", 1), "pump", "return", "destroy", ("consumer_dispose", 1)], CHILD_TRACE + ["await_child", "target", "observed_target", "retire", "resume"] + PUBLISHED + ["observe", "destroy", "consumer_write", "resume"] + PUBLISHED + ["destroy", "consumer_dispose"])
	assert state.tasks[1].transfers == 1
	schedule = CHILD_PENDING + [("await_child", 1), "target", "drain", "retire", "pump", ("return", 1), "cancel", ("observe", 1), ("destroy", 1), "pump", "return", "destroy"]
	state = witness("cancel_waiter_after_child_publication_discards_once", children, schedule, CHILD_TRACE + ["await_child", "target", "observed_target", "retire", "resume"] + PUBLISHED + ["cancel", "observe", "destroy", "resume"] + PUBLISHED + ["destroy"])
	assert state.tasks[1].outcome == "success" and not state.tasks[1].cancel and state.tasks[1].disposals == 1 and state.tasks[1].transfers == 0
	cold = CREATE + [("capture", 1), ("publish_task", 1), "start", "pump"]
	witness("scoped_new_child_disposal", children, cold + ["cancel", "join_children", ("destroy", 1), "pump", "return", "destroy"], CREATED + CREATED + ["start_deferred_body", "resume", "cancel", "join_children", "destroy", "resume"] + PUBLISHED + ["destroy"])
	witness("direct_await_enrolls_cold_child", initial(Task(waits=0), Task(waits=0, parent=0)), cold + [("await_child", 1), "pump", ("return", 1), ("observe", 1), ("destroy", 1), "pump", "return", "destroy", ("consumer_dispose", 1)], CREATED + CREATED + ["start_deferred_body", "resume", "await_child", "resume"] + PUBLISHED + ["observe", "destroy", "resume"] + PUBLISHED + ["destroy", "consumer_dispose"])
	terminal_prefix = CREATE + [("capture", 1), ("publish_task", 1), ("start", 1), "pump", ("return", 1), "start", "pump"]
	terminal_trace = CREATED + CREATED + ["start_deferred_body", "resume"] + PUBLISHED + ["start_deferred_body", "resume"]
	state = witness("scoped_already_terminal_child_preserves_success", initial(Task(waits=0), Task(waits=0, parent=0)), terminal_prefix + ["cancel", "join_children", ("destroy", 1), "pump", "return", "destroy"], terminal_trace + ["cancel", "join_children", "destroy", "resume"] + PUBLISHED + ["destroy"])
	assert state.tasks[1].outcome == "success" and not state.tasks[1].cancel
	witness("scoped_target_queued_before_cancel", children, CHILD_PENDING + ["target", "cancel", "join_children", "cancel_op", "ack", "drain", "drain", "retire", "pump", ("return", 1), ("destroy", 1), "pump", "return", "destroy"], CHILD_TRACE + ["target", "cancel", "join_children", "cancel_op", "ack", "observed_target", "observed_ack", "retire", "resume"] + PUBLISHED + ["destroy", "resume"] + PUBLISHED + ["destroy"])
	witness("scoped_ack_before_target", children, CHILD_PENDING + ["cancel", "join_children", "cancel_op", "ack", "drain", ("target", 0, "cancel"), "drain", "retire", "pump", ("return", 1), ("destroy", 1), "pump", "return", "destroy"], CHILD_TRACE + ["cancel", "join_children", "cancel_op", "ack", "observed_ack", "target", "observed_target", "retire", "resume"] + PUBLISHED + ["destroy", "resume"] + PUBLISHED + ["destroy"])
	three = initial(Task(waits=0), Task(parent=0), Task(waits=0), enrollment_capacity=3)
	schedule = CHILD_PENDING + [("capture", 2), ("publish_task", 2), ("start", 2), "cancel", "join_children", "cancel_op", ("target", 0, "cancel"), "ack", "drain", "drain", "retire", "pump", ("return", 2), "pump", ("return", 1), ("destroy", 1), "pump", "return", "destroy", ("destroy", 2)]
	expected = CHILD_TRACE + CREATED + ["start_deferred_body", "cancel", "join_children", "cancel_op", "target", "ack", "observed_target", "observed_ack", "retire", "resume"] + PUBLISHED + ["resume"] + PUBLISHED + ["destroy", "resume"] + PUBLISHED + ["destroy", "destroy"]
	state = witness("scoped_cancel_unrelated_runnable_progresses", three, schedule, expected)
	assert not state.closing and not state.tasks[2].cancel and state.tasks[2].outcome == "success"
	removed = replace(cancelled, tasks=(cancelled.tasks[0], replace(cancelled.tasks[1], cancel=False)))
	detected("remove_scoped_propagation", removed, "missing_scoped_cancel")
	detected("lose_pending_await_right", replace(awaiting, tasks=(awaiting.tasks[0], replace(awaiting.tasks[1], waiter=-1))), "lost_pending_observation_right")
	detected("lose_cancelled_pending_await_right", replace(cancelled, tasks=(cancelled.tasks[0], replace(cancelled.tasks[1], waiter=-1))), "lost_pending_observation_right")
	detected("duplicate_pending_await_handle", replace(awaiting, tasks=(awaiting.tasks[0], replace(awaiting.tasks[1], handle=True))), "invalid_pending_observation_right")
	detected("retire_scoped_child_early", replace(cancelled, registrations=(replace(cancelled.registrations[0], retired=True),)), "bad_retirement_or_cancel_ack")
	rejected("observe_pending_moved_right", awaiting, ("observe", 1))
	for name, seed, prefix, required, suffix in [
		("undrained_target", initial(), PENDING + ["target"], "source_without_observed_target", ["drain", "retire", "pump", "return", "observe", "destroy", "consumer_write", "consumer_dispose"]),
		("undrained_release", initial(Task(mode="late")), PENDING + ["target", "drain", "release"], "source_without_observed_release", ["drain", "retire", "pump", "return", "observe", "destroy", "consumer_write", "consumer_dispose"]),
		("undrained_cancel_result", initial(), PENDING + ["cancel", "cancel_op", ("target", 0, "cancel"), "drain", "ack"], "source_without_observed_cancel_result", ["drain", "retire", "pump", "return", "observe", "destroy"])
	]:
		legitimate, _ = apply(seed, prefix)
		for consumed in (False, True):
			forged = replace(legitimate, work=(), tasks=(replace(legitimate.tasks[0], phase="terminal", initialized=True, published=True, owner="consumer" if consumed else "result", observations=int(consumed), transfers=int(consumed), consumer_writes=int(consumed), handle=not consumed, outcome="success", dirty=False),))
			detected(name + ("_consumption" if consumed else "_publication"), forged, required)
			assert "source_before_registration_retirement" in violations(forged)
			assert "source_with_queued_registration" in violations(forged)
			if not consumed:
				rejected(name + "_observe_rejected", forged, ("observe",))
			else:
				rejected(name + "_consumer_use_rejected", forged, ("consumer_write",))
		first = {"undrained_target": "observed_target", "undrained_release": "observed_release", "undrained_cancel_result": "observed_ack"}[name]
		expected = [first, "retire", "resume"] + PUBLISHED + ["observe", "destroy"] + ([] if name == "undrained_cancel_result" else ["consumer_write", "consumer_dispose"])
		complete = witness(name + "_valid_retirement_control", legitimate, suffix, expected)
		assert not complete.tasks[0].frame and complete.tasks[0].observations == 1 and all(r.retired for r in complete.registrations)
	cold, _ = apply(initial(Task(waits=0), Task(waits=0), enrollment_capacity=1), CREATE + [("capture", 1), ("publish_task", 1), "start"])
	rejected("start_capacity_preserves_cold_handle", cold, ("start", 1))
	assert cold.tasks[1].handle and cold.tasks[1].frame and not cold.tasks[1].associated and cold.tasks[1].phase == "new"
	cold_await, _ = apply(initial(Task(waits=0), Task(parent=0), enrollment_capacity=1), CREATE + [("capture", 1), ("publish_task", 1), "start", "pump"])
	rejected("await_capacity_preserves_parent_and_cold_right", cold_await, ("await_child", 1))
	consuming_failure, trace = apply(cold_await, [("destroy", 1)])
	assert consuming_failure.tasks[1].phase == "dead" and consuming_failure.tasks[1].disposals == 1 and not consuming_failure.tasks[1].associated
	assert consuming_failure.tasks[0] == cold_await.tasks[0] and trace == ["destroy"]
	rows.append({"case": "consuming_admission_failure_cold_disposal_refinement", "trace": trace, "events": len(trace), "disposals": [t.disposals for t in consuming_failure.tasks], "transfers": [t.transfers for t in consuming_failure.tasks]})
	observed, _ = apply(initial(), PENDING + ["target", "drain"])
	forged = replace(observed, work=(), tasks=(replace(observed.tasks[0], phase="terminal", initialized=True, published=True, owner="result", dirty=False),))
	detected("observed_evidence_without_retirement", forged, "source_before_registration_retirement")
	assert not any(e.startswith("source_without_observed") for e in violations(forged))
	return rows, rejections, controls
