# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bounded proposed enum/error semantics. No Astra parser or runtime."""

from copy import deepcopy
from dataclasses import dataclass, field, replace


class Rejected(Exception):
	pass


@dataclass(frozen=True)
class Owner:
	token: int


@dataclass(frozen=True)
class Value:
	identity: str
	variant: str
	payload: tuple = ()


	# Exact application keys include the nominal definition and canonical arguments.
	# Payload modes belong to the definition, not an alternative SliceType identity.
SCHEMAS = {
	"Colour": {"Red": (), "Blue": ()},
	"Decode": {"Magic": (), "Version": ("int",), "End": ("int", "int")},
	"OtherDecode": {"Magic": (), "Version": ("int",), "End": ("int", "int")},
	"Load": {"IO": ("int",), "Decode": ("Decode",)},
	"Buffer": {"Ready": ("owner",)},
	"BufferState": {"Empty": (), "Ready": ("owner",), "Failed": ("Decode",)},
	"PairOwners": {"Ready": ("owner", "owner", "int")},
	"Result<int,Decode>": {"Success": ("int",), "Error": ("Decode",)},
	"Result<int,OtherDecode>": {"Success": ("int",), "Error": ("OtherDecode",)},
	"Result<Header,Decode>": {"Success": ("Header",), "Error": ("Decode",)},
	"VoidResult<Decode>": {"Success": (), "Error": ("Decode",)},
	"ArrayResult<u8,Decode>": {"Success": ("owner",), "Error": ("Decode",)},
	"FutureOwnedError": {"Reason": ("owner",)},
	"Completion<int,Decode>": {"Success": ("int",), "Error": ("Decode",), "Cancelled": ()},
	"ArrayCompletion<u8,Decode>": {"Success": ("owner",), "Error": ("Decode",), "Cancelled": ()},
}


def copyable(identity):
	if identity in ("int", "Header"):
		return True
	if identity == "owner":
		return False
	return all(copyable(t) for fields in SCHEMAS[identity].values() for t in fields)


def tokens(value):
	if isinstance(value, Owner):
		return [value.token]
	if isinstance(value, Value):
		return [token for part in value.payload for token in tokens(part)]
	return []


@dataclass
class Cell:
	expected: str
	value: Value | None = None
	phase: str = "uninitialized"
	epoch: int = 0
	scope: int = 0
	order: int = 0


@dataclass(frozen=True)
class Loan:
	root: str
	epoch: int
	value: Value
	scope: int


@dataclass(frozen=True)
class Consumer:
	parent: str | None
	scope: int
	phase: str = "pending"


@dataclass(frozen=True)
class Reservation:
	consumer: str
	argument: str


@dataclass(frozen=True)
class Handler:
	domain: str
	target: str
	scope: int
	consumer: str | None = None


@dataclass
class State:
	cells: dict = field(default_factory=dict)
	borrows: dict = field(default_factory=dict)
	reservations: dict = field(default_factory=dict)
	consumers: dict = field(default_factory=dict)
	events: list = field(default_factory=list)
	next_token: int = 0
	next_order: int = 0
	handlers: tuple = ()
	function_error: str | None = None
	exits: list = field(default_factory=list)
	completion: Value | None = None
	evidence: dict = field(default_factory=lambda: dict(target=False, release=False, command=False, registration=False, queue=False))
	command_required: bool = True
	parent_cancelled: bool = False
	consuming_right: int = 1


class Machine:
	def __init__(self, state=None):
		self.state = deepcopy(state) if state is not None else State()

	def declare(self, name, identity, scope=0):
		if name in self.state.cells or identity not in SCHEMAS:
			raise Rejected("duplicate cell or unknown nominal identity")
		self.state.cells[name] = Cell(identity, scope=scope, order=self.state.next_order)
		self.state.next_order += 1

	def live(self, name):
		cell = self.state.cells[name]
		if cell.phase != "live":
			raise Rejected("cell is not a live initialized value")
		return cell

	def unlocked(self, name):
		if any(b.root == name for b in self.state.borrows.values()) or name in self.state.reservations:
			raise Rejected("active borrow or pending reservation")

	def acquire(self, name, scope=0):
		self.declare(name, "Buffer", scope)
		token = self.state.next_token
		self.state.next_token += 1
		value = Value("Buffer", "Ready", (Owner(token),))
		self.state.cells[name].value = value
		self.state.cells[name].phase = "live"
		self.state.events.append(("acquire", token, name))
		return Owner(token)

	def construct(self, name, variant, payload=()):
		cell = self.state.cells[name]
		if cell.phase not in ("uninitialized", "moved", "dropped"):
			raise Rejected("construction needs disarmed storage")
		if variant not in SCHEMAS[cell.expected] or len(payload) != len(SCHEMAS[cell.expected][variant]):
			raise Rejected("constructor shape")
		if any(tokens(p) for p in payload):
			raise Rejected("owners require explicit transfer construction")
		cell.value = Value(cell.expected, variant, tuple(payload))
		cell.phase = "live"
		cell.epoch += 1

	def begin(self, name, variant):
		cell = self.state.cells[name]
		if cell.phase not in ("uninitialized", "moved", "dropped") or variant not in SCHEMAS[cell.expected]:
			raise Rejected("invalid construction staging")
		cell.value = Value(cell.expected, variant)
		cell.phase = "staging"
		cell.epoch += 1

	def append(self, name, part, source=None):
		cell = self.state.cells[name]
		if cell.phase != "staging" or len(cell.value.payload) >= len(SCHEMAS[cell.expected][cell.value.variant]):
			raise Rejected("invalid staged field")
		if tokens(part):
			if source is None or self.live(source).value.payload != (part,):
				raise Rejected("owner field needs one exact source")
			self.unlocked(source)
			self._disarm(source)
			for token in tokens(part):
				self.state.events.append(("transfer", token, source, name))
		cell.value = Value(cell.expected, cell.value.variant, cell.value.payload + (part,))

	def publish(self, name):
		cell = self.state.cells[name]
		if cell.phase != "staging" or len(cell.value.payload) != len(SCHEMAS[cell.expected][cell.value.variant]):
			raise Rejected("incomplete publication")
		cell.phase = "live"

	def _disarm(self, name):
		cell = self.state.cells[name]
		cell.phase = "moved"
		cell.value = None
		cell.epoch += 1

	def move(self, source, destination):
		cell = self.live(source)
		self.unlocked(source)
		target = self.state.cells[destination]
		if source == destination or target.phase not in ("uninitialized", "moved", "dropped") or cell.expected != target.expected:
			raise Rejected("move destination or exact identity")
		target.value, target.phase = cell.value, "live"
		target.epoch += 1
		for token in tokens(cell.value):
			self.state.events.append(("transfer", token, source, destination))
		self._disarm(source)

	def copy(self, source, destination):
		cell = self.live(source)
		if not copyable(cell.expected):
			raise Rejected("whole type is move-only")
		target = self.state.cells[destination]
		if target.expected != cell.expected or target.phase not in ("uninitialized", "moved", "dropped"):
			raise Rejected("copy destination")
		target.value, target.phase = cell.value, "live"
		target.epoch += 1
		self.state.events.append(("copy", cell.expected, source, destination))

	def borrow(self, name, binding, scope=None):
		cell = self.live(name)
		scope = cell.scope + 1 if scope is None else scope
		if binding in self.state.borrows or scope < cell.scope:
			raise Rejected("duplicate borrow or extent outside root lifetime")
		self.state.borrows[binding] = Loan(name, cell.epoch, cell.value, scope)

	def end_borrow(self, binding):
		if binding not in self.state.borrows:
			raise Rejected("missing borrow")
		self.state.events.append(("loan_end", binding, self.state.borrows.pop(binding)))

	def read(self, name, ordinal):
		cell = self.live(name)
		if ordinal < 0 or ordinal >= len(cell.value.payload):
			raise Rejected("inactive or missing payload")
		self.state.events.append(("read", cell.value, ordinal))
		return cell.value.payload[ordinal]

	def drop(self, name):
		cell = self.state.cells[name]
		self.unlocked(name)
		if cell.phase not in ("live", "staging"):
			raise Rejected("duplicate or invalid disposal")
			# Prefix-only staging has exactly the fields acquired so far.
		for ordinal in range(len(cell.value.payload) - 1, -1, -1):
			part = cell.value.payload[ordinal]
			for token in reversed(tokens(part)):
				self.state.events.append(("dispose", token, name, cell.value, ordinal))
		cell.value, cell.phase = None, "dropped"
		cell.epoch += 1

	def consume(self, source, bindings):
		cell = self.live(source)
		self.unlocked(source)
		value = cell.value
		if len(bindings) != len(value.payload):
			raise Rejected("pattern must bind or explicitly ignore every field")
		names = [binding for binding in bindings if binding is not None]
		if len(names) != len(set(names)) or any(binding in self.state.cells or binding in self.state.borrows for binding in names):
			raise Rejected("duplicate or existing pattern binding")
			# Ignored owners dispose in reverse payload order at arm entry.
		for ordinal in range(len(bindings) - 1, -1, -1):
			part, binding = value.payload[ordinal], bindings[ordinal]
			if binding is None:
				for token in reversed(tokens(part)):
					self.state.events.append(("dispose", token, source, value, ordinal))
					# Live bindings initialize in declaration order, so normal reverse scope
					# cleanup is also reverse declaration order.
		for ordinal, binding in enumerate(bindings):
			if binding is None:
				continue
			part = value.payload[ordinal]
			identity = SCHEMAS[value.identity][value.variant][ordinal]
			if identity == "owner":
				self.declare(binding, "Buffer", cell.scope + 1)
				self.state.cells[binding].value = Value("Buffer", "Ready", (part,))
				self.state.cells[binding].phase = "live"
			elif isinstance(part, Value):
				self.declare(binding, part.identity, cell.scope + 1)
				self.state.cells[binding].value, self.state.cells[binding].phase = part, "live"
			else:
				self.state.events.append(("bind_copy", identity, binding, part))
			for token in tokens(part):
				self.state.events.append(("transfer", token, source, binding))
		self._disarm(source)
		return value.variant

	def replace(self, destination, incoming):
		self.live(destination)
		self.live(incoming)
		self.unlocked(destination)
		self.unlocked(incoming)
		if destination == incoming or self.state.cells[destination].expected != self.state.cells[incoming].expected:
			raise Rejected("self move or wrong replacement identity")
		self.drop(destination)
		self.move(incoming, destination)

	def begin_consumer(self, name, parent=None, scope=0):
		if name in self.state.consumers or scope < 0:
			raise Rejected("duplicate consumer or invalid scope")
		if parent is not None and (parent not in self.state.consumers or self.state.consumers[parent].phase != "pending" or scope < self.state.consumers[parent].scope):
			raise Rejected("consumer needs a pending enclosing consumer")
		self.state.consumers[name] = Consumer(parent, scope)

	def pending_consumer(self, consumer):
		if consumer not in self.state.consumers or self.state.consumers[consumer].phase != "pending":
			raise Rejected("consumer is not pending")
		return self.state.consumers[consumer]

	def reserve(self, source, argument, consumer):
		self.pending_consumer(consumer)
		self.live(source)
		self.unlocked(source)
		if argument in self.state.cells or any(r.argument == argument for r in self.state.reservations.values()):
			raise Rejected("duplicate argument")
		self.state.reservations[source] = Reservation(consumer, argument)
		self.state.cells[source].phase = "reserved"

	def abort_arguments(self, consumer):
		self.pending_consumer(consumer)
		if any(c.parent == consumer and c.phase == "pending" for c in self.state.consumers.values()):
			raise Rejected("nested consumer still pending")
		pending = [(source, r.argument) for source, r in self.state.reservations.items() if r.consumer == consumer]
		for source, _ in pending:
			self.state.cells[source].phase = "live"
			del self.state.reservations[source]
		self.state.consumers[consumer] = replace(self.state.consumers[consumer], phase="aborted")
		self.state.events.append(("abort", consumer, tuple(pending)))

	def commit_arguments(self, consumer):
		frame = self.pending_consumer(consumer)
		if any(c.parent == consumer and c.phase == "pending" for c in self.state.consumers.values()):
			raise Rejected("nested consumer still pending")
		pending = [(source, r.argument) for source, r in self.state.reservations.items() if r.consumer == consumer]
		if any(argument in self.state.cells for _, argument in pending):
			raise Rejected("argument target already exists")
		for source, argument in pending:
			cell = self.state.cells[source]
			cell.phase = "live"
			del self.state.reservations[source]
			self.declare(argument, cell.expected, frame.scope + 1)
			self.move(source, argument)
		self.state.consumers[consumer] = replace(frame, phase="committed")
		self.state.events.append(("commit", consumer, tuple(pending)))

	def route(self, error, consumer=None):
		# A bounded transaction makes every malformed route refusal atomic.
		candidate = Machine(self.state)
		target = candidate._route(error, consumer)
		self.state = candidate.state
		return target

	def _route(self, error, consumer):
		if consumer is None and any(c.phase == "pending" for c in self.state.consumers.values()):
			raise Rejected("routing with pending consumers requires current identity")
		cell = self.live(error)
		domain = cell.expected
		destination = next((h for h in reversed(self.state.handlers) if h.domain == domain), None)
		if destination is None:
			if domain != self.state.function_error:
				raise Rejected("unhandled checked error")
			destination = Handler(domain, "return_error", -1)
		crossed_consumers = []
		cursor = consumer
		while cursor != destination.consumer:
			if cursor is None:
				raise Rejected("handler consumer is not enclosing")
			frame = self.pending_consumer(cursor)
			crossed_consumers.append(cursor)
			cursor = frame.parent
		if cursor is not None:
			self.pending_consumer(cursor)
		for binding, loan in reversed(list(self.state.borrows.items())):
			if loan.scope > destination.scope:
				self.end_borrow(binding)
		for abandoned in crossed_consumers:
			self.abort_arguments(abandoned)
		self.declare(destination.target, domain, destination.scope)
		self.move(error, destination.target)
		self.state.events.append(("route", domain, destination.target, destination.scope, self.state.handlers, self.state.function_error))
		crossed = sorted(((n, c) for n, c in self.state.cells.items() if c.scope > destination.scope and c.phase in ("live", "staging")), key=lambda p: p[1].order, reverse=True)
		if any(c.scope > destination.scope for n, c in self.state.cells.items() if n in self.state.reservations):
			raise Rejected("scope exit would abandon an unrelated consumer")
		for name, _ in crossed:
			self.drop(name)
		self.state.exits.append((domain, destination.target, destination.scope))
		return destination.target

	def retire(self):
		for name in self.state.evidence:
			self.state.evidence[name] = True

	def cancel(self):
		self.state.parent_cancelled = True

	def publish_completion(self, value):
		if not all(v for k, v in self.state.evidence.items() if k != "command" or self.state.command_required):
			raise Rejected("retirement evidence incomplete")
		if self.state.consuming_right != 1 or self.state.completion is not None:
			raise Rejected("one consuming right")
		if self.state.parent_cancelled and value.variant != "Cancelled":
			raise Rejected("monotone parent cancellation")
		if tokens(value):
			raise Rejected("abstract publication control uses non-owning payloads")
		self.state.completion = value

	def observe_completion(self, concise=False):
		if self.state.completion is None or self.state.consuming_right != 1:
			raise Rejected("completion not observable")
		self.state.consuming_right = 0
		value = self.state.completion
		destination = "cancel_exit" if value.variant == "Cancelled" else "error_handler" if value.variant == "Error" and concise else "explicit" if not concise else "success"
		self.state.events.append(("observe", value.variant, destination))
		return destination
