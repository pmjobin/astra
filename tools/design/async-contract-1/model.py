# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Finite, sequential contract model. No Astra execution or kernel operations."""

from dataclasses import dataclass, replace


class Rejected(ValueError):
	pass


@dataclass(frozen=True)
class Task:
	owner_id: int = -1
	mode: str = "timer"
	waits: int = 1
	parent: int = -1
	borrow: bool = False
	phase: str = "building"
	frame: bool = True
	handle: bool = True
	captured: bool = False
	cancel: bool = False
	dirty: bool = False
	initialized: bool = False
	published: bool = False
	outcome: str = ""
	observations: int = 0
	owner: str = "caller"
	disposals: int = 0
	transfers: int = 0
	consumer_writes: int = 0
	associated: bool = False
	waiter: int = -1


@dataclass(frozen=True)
class Registration:
	task: int
	epoch: int
	mode: str
	submitted: bool = False
	terminal_sent: bool = False
	terminal_seen: bool = False
	release_sent: bool = False
	release_seen: bool = False
	access: bool = False
	more_sent: bool = False
	more_seen: bool = False
	cancel_sent: bool = False
	ack_sent: bool = False
	ack_seen: bool = False
	retired: bool = False
	outcome: str = ""


@dataclass(frozen=True)
class Event:
	registration: int
	kind: str
	outcome: str = ""


@dataclass(frozen=True)
class State:
	tasks: tuple
	registrations: tuple = ()
	work: tuple = ()
	completions: tuple = ()
	queue_capacity: int = 1
	completion_capacity: int = 2
	registration_limit: int = 2
	backing_live: bool = True
	closing: bool = False
	fatal: bool = False
	rotation: int = 0
	enrollment_capacity: int = 2


def initial(*tasks, queue_capacity=1, completion_capacity=2, registration_limit=2, enrollment_capacity=2):
	return State(tuple(replace(task, owner_id=i) for i, task in enumerate(tasks or (Task(),))), queue_capacity=queue_capacity, completion_capacity=completion_capacity, registration_limit=registration_limit, enrollment_capacity=enrollment_capacity)


def require(condition, reason):
	if not condition:
		raise Rejected(reason)


def set_task(state, index, task):
	tasks = list(state.tasks)
	tasks[index] = task
	return replace(state, tasks=tuple(tasks))


def set_registration(state, index, registration):
	registrations = list(state.registrations)
	registrations[index] = registration
	return replace(state, registrations=tuple(registrations))


def enqueue(state, index):
	task = state.tasks[index]
	state = set_task(state, index, replace(task, dirty=True))
	if index not in state.work and len(state.work) < state.queue_capacity:
		state = replace(state, work=state.work + (index,))
	return state


def refill(state):
	for offset in range(len(state.tasks)):
		index = (state.rotation + offset) % len(state.tasks)
		task = state.tasks[index]
		if task.frame and task.dirty and index not in state.work and len(state.work) < state.queue_capacity:
			state = replace(state, work=state.work + (index,))
	return state


def send(state, index, kind, outcome=""):
	require(len(state.completions) < state.completion_capacity, "completion pressure: retain event externally")
	return replace(state, completions=state.completions + (Event(index, kind, outcome),))


def active(state, task):
	return any(r.task == task and not r.retired for r in state.registrations)


def dispose_owner(task):
	if task.owner in ("frame", "result"):
		return replace(task, owner="disposed", disposals=task.disposals + 1)
	return task


def request_cancel(state, index):
	"""Atomic bounded subtree request; native lowering may service recorded turns."""
	for i, task in enumerate(state.tasks):
		ancestor = i
		for _ in state.tasks:
			if ancestor == index:
				if i == index or (task.frame and task.phase not in ("terminal", "failed", "dead")):
					state = set_task(state, i, replace(task, cancel=True, phase="joining" if task.phase == "awaiting" else task.phase))
				break
			ancestor = state.tasks[ancestor].parent
			if ancestor < 0:
				break
	return state


def admit(state, task):
	require(not state.closing, "executor closing: cold handle retained")
	require(task.associated or sum(t.frame and t.associated for t in state.tasks) < state.enrollment_capacity, "enrollment capacity: cold handle retained")
	return replace(task, associated=True)


def step(state, action, index=0, value=""):
	"""Application, executor and external-provider actions are separate labels."""
	require(not state.fatal, "process terminated; no subsequent normal transitions")
	log = []
	if action == "shutdown":
		state = replace(state, closing=True)
		for i, task in enumerate(state.tasks):
			if task.frame and task.phase not in ("terminal", "failed"):
				state = request_cancel(state, i)
		return state, ("shutdown_requested",)
	if action == "end_backing":
		require(not any(t.frame and t.borrow for t in state.tasks), "live scoped loan, including deferred capture")
		return replace(state, backing_live=False), ("backing_released",)
	if action == "drain":
		require(bool(state.completions), "no completion")
		event = state.completions[0]
		state = replace(state, completions=state.completions[1:])
		registration = state.registrations[event.registration]
		if registration.retired:
			return state, ("stale_identity_ignored",)
		if event.kind == "more":
			registration = replace(registration, more_seen=True)
		elif event.kind == "target":
			registration = replace(registration, terminal_seen=True, release_seen=registration.mode != "late" or registration.release_seen, outcome=event.outcome)
		elif event.kind == "release":
			registration = replace(registration, release_seen=True)
		elif event.kind == "ack":
			registration = replace(registration, ack_seen=True)
		state = set_registration(state, event.registration, registration)
		return state, ("observed_" + event.kind,)
	if action == "pump":
		state = refill(state)
		require(bool(state.work), "no ready work")
		require(not any(t.phase == "running" for t in state.tasks), "nested drive/concurrent resume")
		index = state.work[0]
		state = replace(state, work=state.work[1:], rotation=(index + 1) % len(state.tasks))
		task = state.tasks[index]
		require(task.frame, "queue requires retained frame")
		if task.phase == "ready":
			task = replace(task, phase="running", dirty=False)
			log.append("resume")
		else:
			task = replace(task, dirty=False)
			log.append("spurious_wake_drained")
		return refill(set_task(state, index, task)), tuple(log)
	if action in ("submit", "target", "more", "release", "cancel_op", "ack", "retire", "replay", "access", "revoke_prepared"):
		require(index < len(state.registrations), "unknown registration")
		registration = state.registrations[index]
		if action == "replay":
			require(registration.retired, "only retired identities replayed")
			return send(state, index, "stale", "success"), ("stale_event_queued",)
		require(not registration.retired, "retired registration")
		task = state.tasks[registration.task]
		if action == "submit":
			require(not registration.submitted, "already submitted")
			registration = replace(registration, submitted=True, access=True)
			state = set_task(state, registration.task, replace(task, phase="pending"))
		elif action == "revoke_prepared":
			require(not registration.submitted and task.cancel, "only unpublished intent is locally revocable")
			registration = replace(registration, terminal_sent=True, terminal_seen=True, release_sent=True, release_seen=True, retired=True, outcome="cancel")
			state = enqueue(set_task(state, registration.task, replace(task, phase="ready", waits=task.waits - 1, outcome="cancel")), registration.task)
		elif action == "target":
			require(registration.submitted and not registration.terminal_sent, "no live target")
			outcome = value or "success"
			require(outcome in ("success", "error", "cancel"), "invalid result")
			require(outcome != "cancel" or registration.cancel_sent, "unsolicited cancellation")
			state = send(state, index, "target", outcome)
			late = registration.mode == "late"
			registration = replace(registration, terminal_sent=True, release_sent=not late, release_seen=False, access=late)
		elif action == "more":
			require(registration.submitted and registration.mode == "repeated" and not registration.more_sent and not registration.terminal_sent, "nonterminal not enabled")
			state = send(state, index, "more")
			registration = replace(registration, more_sent=True)
		elif action == "release":
			require(registration.terminal_sent and not registration.release_sent, "no late release")
			state = send(state, index, "release")
			registration = replace(registration, access=False, release_sent=True)
		elif action == "cancel_op":
			require(task.cancel and registration.submitted and not registration.cancel_sent, "no cancel command")
			registration = replace(registration, cancel_sent=True)
		elif action == "ack":
			require(registration.cancel_sent and not registration.ack_sent, "no cancel acknowledgment")
			state = send(state, index, "ack", value or "absent_or_too_late")
			registration = replace(registration, ack_sent=True)
		elif action == "retire":
			require(registration.terminal_seen and registration.release_seen and not registration.access, "target/payload not quiescent")
			require(not registration.cancel_sent or registration.ack_seen, "cancel command still refers to identity")
			require(not any(e.registration == index for e in state.completions), "queued registration reference")
			registration = replace(registration, retired=True)
			state = enqueue(set_task(state, registration.task, replace(task, phase="ready", waits=task.waits - 1, outcome=registration.outcome)), registration.task)
		elif action == "access":
			require(registration.access, "provider has no access capability")
			require(task.frame and task.owner == "frame" and (not task.borrow or state.backing_live), "access to freed backing")
		return set_registration(state, index, registration), (action,)
	else:
		require(index < len(state.tasks), "unknown task")
		task = state.tasks[index]
		if action == "consumer_dispose":
			require(task.owner == "consumer", "consumer does not own payload")
			return set_task(state, index, replace(task, owner="disposed", disposals=task.disposals + 1)), (action,)
		if action == "consumer_write":
			require(task.owner == "consumer" and not any(r.task == index and (r.access or not r.retired) for r in state.registrations), "provider evidence/payload outstanding")
			return set_task(state, index, replace(task, consumer_writes=task.consumer_writes + 1)), (action,)
		require(task.frame, "frame no longer exists")
		if action == "capture":
			require(task.phase == "building" and not task.captured, "already captured")
			require(not task.borrow or state.backing_live, "dead capture backing")
			task = replace(task, captured=True, owner="frame")
		elif action == "publish_task":
			require(task.phase == "building" and task.captured, "incomplete frame")
			task = replace(task, phase="new")
		elif action == "fail_build":
			require(task.phase == "building", "construction already published")
			task = replace(dispose_owner(task), phase="failed")
		elif action == "fatal":
			return replace(state, fatal=True), ("fatal_nonunwinding",)
		elif action == "start":
			require(task.phase == "new" and not state.closing, "start not admitted")
			state = set_task(state, index, replace(admit(state, task), phase="ready"))
			return enqueue(state, index), ("start_deferred_body",)
		elif action == "wake":
			require(task.phase in ("ready", "running", "registering", "pending"), "terminal wake refused")
			return enqueue(state, index), ("wake_latched",)
		elif action == "await_child":
			require(task.parent >= 0 and task.handle and task.waiter < 0, "no unique child observation right")
			parent = state.tasks[task.parent]
			require(parent.phase == "running" and not parent.cancel, "parent cannot begin await")
			require(task.phase in ("new", "ready", "registering", "pending", "terminal"), "child not awaitable")
			if task.phase == "new":
				task = replace(admit(state, task), phase="ready")
				state = enqueue(set_task(state, index, task), index)
				task = state.tasks[index]
			state = set_task(state, task.parent, replace(parent, phase="awaiting", dirty=False))
			state = replace(state, work=tuple(i for i in state.work if i != task.parent))
			task = replace(task, handle=False, waiter=task.parent)
		elif action == "cancel":
			return request_cancel(state, index), ("cancel",)
		elif action == "suspend":
			require(task.phase == "running" and task.waits > 0 and not task.cancel, "suspension not admitted")
			require(len(state.registrations) < state.registration_limit, "registration identity capacity")
			registration = Registration(index, len(state.registrations) + 1, task.mode)
			state = replace(state, registrations=state.registrations + (registration,))
			task = replace(task, phase="registering")
		elif action == "register_error":
			require(task.phase == "running" and task.waits > 0, "no registration attempt")
			task = replace(task, waits=0, outcome="error")
		elif action == "join_children":
			require(task.phase == "running" and task.cancel and any(t.frame and t.parent == index for t in state.tasks), "no child drain")
			task = replace(task, phase="joining", dirty=False)
			state = replace(state, work=tuple(i for i in state.work if i != index))
		elif action == "return":
			require(task.phase == "running" and (task.waits == 0 or task.cancel), "body not complete")
			require(not active(state, index), "registration outstanding")
			require(not any(t.frame and t.parent == index for t in state.tasks), "child join obligation")
			outcome = "cancel" if task.cancel else task.outcome or "success"
			if outcome == "success" and task.mode != "scalar":
				task = replace(task, owner="result")
			elif outcome == "error" and task.mode == "error_owner":
				task = replace(task, owner="result")
			else:
				task = dispose_owner(task)
			task = replace(task, phase="terminal", initialized=True, published=True, outcome=outcome, dirty=False)
			state = replace(state, work=tuple(i for i in state.work if i != index))
			log.extend(("result_initialized", "result_published"))
		elif action == "observe":
			require(task.phase == "terminal" and (task.handle or task.waiter >= 0) and task.observations == 0, "single consuming observation")
			require(not active(state, index), "observation evidence outstanding")
			require(task.published and task.initialized, "unpublished result")
			owned = task.owner == "result"
			discard = task.waiter >= 0 and state.tasks[task.waiter].cancel
			if discard:
				task = dispose_owner(task)
			task = replace(task, handle=False, observations=1, owner="consumer" if owned and not discard else task.owner, transfers=task.transfers + int(owned and not discard))
		elif action == "destroy":
			require(task.phase in ("new", "terminal", "failed"), "active drop: cancel and join explicitly")
			require(not active(state, index) and index not in state.work and not task.dirty, "retained frame reference")
			require(not any(t.frame and t.parent == index for t in state.tasks), "live child")
			require(task.waiter < 0 or task.observations == 1, "pending consuming right must finish")
			awaited = task.waiter >= 0
			task = replace(dispose_owner(task), frame=False, handle=False, phase="dead", waiter=-1)
			state = set_task(state, index, task)
			if task.parent >= 0:
				parent = state.tasks[task.parent]
				if (parent.phase == "awaiting" and awaited) or (parent.phase == "joining" and not any(t.frame and t.parent == task.parent for t in state.tasks)):
					state = enqueue(set_task(state, task.parent, replace(parent, phase="ready")), task.parent)
			return state, (action,)
		else:
			raise Rejected("unknown action")
		return set_task(state, index, task), tuple(log or (action,))


def violations(state):
	"""Independent predicates over responsibilities, never calls step/require."""
	errors = []
	if len(state.work) > state.queue_capacity or len(state.completions) > state.completion_capacity:
		errors.append("capacity")
	if len(set(state.work)) != len(state.work) or sum(t.phase == "running" for t in state.tasks) > 1:
		errors.append("double_execution")
	if len({t.owner_id for t in state.tasks}) != len(state.tasks):
		errors.append("duplicate_owner_identity")
	for i, task in enumerate(state.tasks):
		if task.waiter >= 0 and (task.waiter != task.parent or task.handle or not state.tasks[task.waiter].frame or state.tasks[task.waiter].phase not in ("awaiting", "joining")):
			errors.append("invalid_pending_observation_right")
		if task.frame and not task.handle and task.observations == 0 and task.waiter < 0:
			errors.append("lost_pending_observation_right")
		if task.phase == "awaiting" and sum(t.frame and t.waiter == i for t in state.tasks) != 1:
			errors.append("lost_pending_observation_right")
		if task.frame and task.parent >= 0 and state.tasks[task.parent].cancel and state.tasks[task.parent].phase not in ("terminal", "failed", "dead") and task.phase not in ("terminal", "failed", "dead") and not task.cancel:
			errors.append("missing_scoped_cancel")
		if task.published or task.observations or task.consumer_writes:
			for j, registration in enumerate(state.registrations):
				if registration.task != i:
					continue
				if not registration.terminal_seen:
					errors.append("source_without_observed_target")
				if not registration.release_seen:
					errors.append("source_without_observed_release")
				if registration.cancel_sent and not registration.ack_seen:
					errors.append("source_without_observed_cancel_result")
				if not registration.retired:
					errors.append("source_before_registration_retirement")
				if any(e.registration == j and e.kind != "stale" for e in state.completions):
					errors.append("source_with_queued_registration")
			if i in state.work or task.dirty:
				errors.append("source_with_queued_work")
		if task.disposals > 1 or task.transfers > 1 or task.observations > 1:
			errors.append("duplicate_owner_or_consumption")
		if task.owner == "disposed" and task.disposals != 1:
			errors.append("unexplained_owner")
		if task.owner != "disposed" and task.disposals != 0:
			errors.append("disposed_live_owner")
		if task.owner == "consumer" and (task.observations != 1 or not task.initialized or not task.published):
			errors.append("lost_publication")
		if task.published and not task.initialized:
			errors.append("lost_publication")
		if task.owner == "result" and (not task.initialized or not task.published):
			errors.append("lost_publication")
		if task.phase == "terminal" and task.owner == "frame":
			errors.append("unexplained_owner")
		if not task.frame and (i in state.work or task.dirty or task.phase != "dead"):
			errors.append("stale_frame_reference")
		if not task.frame and task.owner in ("frame", "result") and not state.fatal:
			errors.append("unexplained_owner")
		if task.phase == "terminal" and (not task.published or i in state.work or task.dirty):
			errors.append("illegal_terminal_resume")
		if task.phase == "ready" and not task.dirty:
			errors.append("lost_wake_progress")
		if task.frame and task.borrow and not state.backing_live:
			errors.append("released_borrow_backing")
		if task.frame and task.parent >= 0 and (not state.tasks[task.parent].frame or state.tasks[task.parent].phase == "terminal"):
			errors.append("parent_join_before_cleanup")
	for i, registration in enumerate(state.registrations):
		task = state.tasks[registration.task]
		if registration.submitted and not registration.terminal_sent and not registration.access:
			errors.append("cancel_ack_is_not_quiescence")
		if registration.access and (not task.frame or task.owner != "frame" or (task.borrow and not state.backing_live)):
			errors.append("provider_use_after_release")
		if registration.access and task.consumer_writes:
			errors.append("consumer_overwrites_retained_payload")
		if not registration.retired and not task.frame:
			errors.append("unquiesced_frame")
		if registration.retired and (not registration.terminal_seen or not registration.release_seen or registration.access or (registration.cancel_sent and not registration.ack_seen)):
			errors.append("bad_retirement_or_cancel_ack")
		if registration.retired and any(e.registration == i and e.kind != "stale" for e in state.completions):
			errors.append("queued_retired_registration")
	if sum(t.frame and t.associated for t in state.tasks) > state.enrollment_capacity:
		errors.append("enrollment_capacity")
	if len({r.epoch for r in state.registrations}) != len(state.registrations):
		errors.append("identity_reuse")
	return sorted(set(errors))


def candidates(state):
	"""Fixed small alphabet; rejected environment requests are counted, not hidden."""
	for action in ("pump", "drain", "shutdown", "end_backing"):
		yield action, 0, ""
	for index in range(len(state.tasks)):
		for action in ("capture", "publish_task", "fail_build", "start", "wake", "cancel", "suspend", "register_error", "join_children", "await_child", "return", "observe", "consumer_dispose", "destroy"):
			yield action, index, ""
	for index in range(len(state.registrations)):
		for action in ("submit", "more", "release", "cancel_op", "ack", "retire", "access", "revoke_prepared"):
			yield action, index, ""
		for outcome in ("success", "error", "cancel"):
			yield "target", index, outcome
