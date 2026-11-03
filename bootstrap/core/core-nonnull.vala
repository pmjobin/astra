// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
private class CoreNonNullSplit : Object {
	internal NonNullFacts yes;
	internal NonNullFacts no;
	internal CoreNonNullSplit (NonNullFacts yes, NonNullFacts no) {
		this.yes = yes;
		this.no = no;
	}

}
private class CoreNonNullLoop : Object {
	internal CoreLoopTarget target;
	internal GenericArray<NonNullFacts> exits = new GenericArray<NonNullFacts> ();
	internal GenericArray<NonNullFacts> continues = new GenericArray<NonNullFacts> ();
	internal CoreNonNullLoop (CoreLoopTarget target) {
		this.target = target;
	}

}
// Independent reconstruction over Core identities; no checked-model facts
// or predecessor nodes are retained by this proof.
internal class CoreNonNull : Object {
	private NonNullFacts state = new NonNullFacts ();
	private NonNullProjections projections = new NonNullProjections ();
	private CoreFunction function;
	private Diagnostic? diagnostic;
	private GenericArray<CoreNonNullLoop> loops = new GenericArray<CoreNonNullLoop> ();
	private GenericArray<Object> writes = new GenericArray<Object> ();
	private void fail(SourceSpan span, string message) {
		if (diagnostic == null) {
			diagnostic = new Diagnostic (span, message);
		}
	}

	private void write(Object slot, bool proven) {
		projections.invalidate (state);
		state.assign (slot, proven);
		if (!writes.find (slot)) {
			writes.add (slot);
		}
	}

	private bool required(Object slot) {
		return (slot is CoreLocalPlace && (((CoreLocalPlace) slot).requires_nonnull || (((CoreLocalPlace) slot).incoming_parameter != null && ((CoreLocalPlace) slot).incoming_parameter.requires_nonnull))) || (slot is CoreParameter && ((CoreParameter) slot).requires_nonnull);
	}

	private void require(bool proven, SourceSpan span) {
		if (state.reachable && !proven) {
			fail (span, "nonnull contract requires a current non-null proof; use an explicit null branch or a proven nonnull result");
		}
	}

	public static Diagnostic? check(CoreProgram program, GenericArray<CoreFunction> selected) {
		foreach (var instance in program.native_instances ()) {
			foreach (var field in instance.fields) {
				if (field.requires_nonnull && (!(instance is CoreClass) || field.owned_cleanup == null || !NonNullReferenceTypes.supports (field.semantic_type) || instance.semantic_type is ExactGenericClassType || instance.semantic_type.is_parameterized ())) {
					return new Diagnostic (field.span, "nonnull field lost exact owned native Class field contract");
				}
			}
		}
		foreach (var imported in program.c_functions) {
			foreach (var parameter in imported.parameters) {
				if (parameter.requires_nonnull) {
					return new Diagnostic (parameter.span, "foreign nonnull contracts cannot be assumed from an unknown C boundary");
				}
			}
		}
		foreach (var definition in program.all_definitions ()) {
			bool needed = selected.find (definition) || definition.nonnull_result;
			foreach (var parameter in definition.parameters) {
				needed = needed || parameter.requires_nonnull;
			}
			foreach (var local in definition.locals) {
				needed = needed || local.requires_nonnull;
			}
			if (!needed) {
				continue;
			}
			if (definition.nonnull_result && (!NonNullReferenceTypes.supports (definition.return_type) || (definition.result_contract != ResultOwnershipContract.OWNED_TRANSFER && definition.result_contract != ResultOwnershipContract.RECEIVER_BORROW && !(definition.return_type is FunctionValueType)))) {
				return new Diagnostic (definition.span, "nonnull result requires an exact native owned or established receiver-borrow Class/Resource contract");
			}
			foreach (var parameter in definition.parameters) {
				if (parameter.requires_nonnull && !NonNullReferenceTypes.supports (parameter.semantic_type)) {
					return new Diagnostic (parameter.span, "nonnull parameter requires an exact Class or Resource reference");
				}
			}
			foreach (var local in definition.locals) {
				if (local.requires_nonnull && !NonNullReferenceTypes.supports (local.semantic_type)) {
					return new Diagnostic (local.span, "nonnull local requires an exact Class or Resource reference");
				}
			}
			bool boundary_contract = definition.nonnull_result;
			foreach (var parameter in definition.parameters) {
				boundary_contract = boundary_contract || parameter.requires_nonnull;
			}
			foreach (var exported in program.c_exports) {
				if (boundary_contract && exported.target == definition) {
					return new Diagnostic (definition.span, "nonnull contract proofs cannot cross an exported C boundary");
				}
			}
			var proof = new CoreNonNull ();
			proof.function = definition;
			if (definition is CoreGenericFunction || definition.dispatch_kind != ClassDispatchKind.DIRECT) {
				return new Diagnostic (definition.span, "nonnull contracts require a concrete direct native definition");
			}
			foreach (var parameter in definition.parameters) {
				proof.state.assign (parameter, parameter.requires_nonnull);
			}
			proof.block (definition.body);
			if (proof.diagnostic != null) {
				return proof.diagnostic;
			}
		}
		return null;
	}

	private Object? receiver_key(CoreValue? expression) {
		if (expression == null) {
			return null;
		}
		if (expression is CoreClassUpcast) {
			return receiver_key (((CoreClassUpcast) expression).reference);
		}
		if (expression is CoreObjectReceiverValue) {
			return receiver_key (((CoreObjectReceiverValue) expression).reference);
		}
		if (expression is CoreReceiverValue) {
			return ((CoreReceiverValue) expression).receiver;
		}
		if (expression is CoreStorageReceiverValue) {
			return ((CoreStorageReceiverValue) expression).storage;
		}
		if (expression is CoreResultStorageReceiverValue) {
			return ((CoreResultStorageReceiverValue) expression).storage;
		}
		return key (expression);
	}

	private Object? property_key(CoreFunction? target, CoreValue? receiver) {
		var getter = target as CorePropertyGetter;
		if (getter == null || !getter.property_member.is_borrowed || getter.property_member.is_lazy) {
			return null;
		}
		return projections.key (receiver_key (receiver), getter.property_member);
	}

	private Object? key(CoreValue expression) {
		if (expression is CoreCallValue) {
			var call = (CoreCallValue) expression;
			return property_key (call.target, call.receiver);
		}
		if (expression is CoreClassUpcast) {
			return key (((CoreClassUpcast) expression).reference);
		}
		if (expression is CoreLoadValue && ((CoreLoadValue) expression).source is CoreLocalPlace) {
			return ((CoreLoadValue) expression).source;
		}
		if (expression is CoreParameterValue) {
			return ((CoreParameterValue) expression).parameter;
		}
		if (expression is CoreOwnedBorrowValue) {
			return ((CoreOwnedBorrowValue) expression).source.place;
		}
		if (expression is CoreWithReference) {
			return ((CoreWithReference) expression).contract.source;
		}
		return null;
	}

	private CoreNonNullSplit condition(CoreValue expression) {
		if (expression is CoreShortCircuitValue) {
			var conditional = (CoreShortCircuitValue) expression;
			var left = condition (conditional.left);
			bool conjunction = conditional.operator_kind == ShortCircuitOperator.AND;
			state = conjunction ? left.yes : left.no;
			var right = condition (conditional.right);
			return conjunction ? new CoreNonNullSplit (right.yes, NonNullFacts.join (left.no, right.no)) : new CoreNonNullSplit (NonNullFacts.join (left.yes, right.yes), right.no);
		}
		if (expression is CorePrefixValue && ((CorePrefixValue) expression).operator_kind == PrefixOperator.NOT) {
			var nested = condition (((CorePrefixValue) expression).operand);
			return new CoreNonNullSplit (nested.no, nested.yes);
		}
		value (expression);
		var yes = state.copy ();
		var no = state.copy ();
		var literal = expression as CoreBooleanValue;
		if (literal != null) {
			(literal.literal == BooleanLiteral.TRUE ? no : yes).reachable = false;
		}
		var binary = expression as CoreBinaryValue;
		if (binary != null && (binary.operator_kind == BinaryOperator.EQUAL || binary.operator_kind == BinaryOperator.NOT_EQUAL)) {
			Object? source = (binary.left is CoreNullPointerValue) ? key (binary.right) : (binary.right is CoreNullPointerValue) ? key (binary.left) : null;
			if (source != null) {
				(binary.operator_kind == BinaryOperator.NOT_EQUAL ? yes : no).refine (source);
			}
		}
		return new CoreNonNullSplit (yes, no);
	}

	private bool call(CoreFunction? target, CoreValue? receiver, GenericArray<CoreValue> arguments, SourceSpan span) {
		if (receiver != null) {
			value (receiver);
		}
		if (target == null || arguments.length != target.parameters.length) {
			fail (span, "nonnull proof requires an exact callable and argument grouping");
			return false;
		}
		for (int i = 0; i < arguments.length; i++) {
			bool proven = value (arguments[i]);
			if (target.parameters[i].requires_nonnull) {
				require (proven, arguments[i].span);
			}
		}
		var projection = property_key (target, receiver);
		bool proven = target.nonnull_result || projection != null && state.knows (projection);
		if (projection == null) {
			projections.invalidate (state);
		}
		return proven;
	}

	private void place(CorePlace storage) {
		if (storage is CoreLocalPlace) {
			return;
		}
		if (storage is CoreIndirectFieldPlace) {
			value (((CoreIndirectFieldPlace) storage).pointer);
			return;
		}
		if (storage is CoreFieldPlace) {
			place (((CoreFieldPlace) storage).aggregate);
			return;
		}
		if (storage is CoreArrayElementPlace) {
			value (((CoreArrayElementPlace) storage).index);
			return;
		}
		if (storage is CoreSliceElementPlace) {
			value (((CoreSliceElementPlace) storage).slice);
			value (((CoreSliceElementPlace) storage).index);
			return;
		}
		fail (storage.span, "Core nonnull proof excludes uncertain indirect storage in this definition");
	}

	private bool consume(CoreOwnedLocal owner) {
		bool proven = state.knows (owner.place);
		write (owner.place, false);
		return proven;
	}

	private void projected_producer(CoreStructProducer source) {
		if (source is CoreStructBorrowSnapshot) {
			place (((CoreStructBorrowSnapshot) source).source);
			return;
		}
		if (source is CoreStructProjectionProducer) {
			projected_producer (((CoreStructProjectionProducer) source).source);
		} else if (source is CoreStructSnapshot) {
			place (((CoreStructSnapshot) source).source);
		} else if (source is CoreStructInvocationResult) {
			value (((CoreStructInvocationResult) source).invocation);
		} else if (source is CoreStructCallResult) {
			var invoked = (CoreStructCallResult) source;
			call (invoked.target, invoked.receiver, invoked.arguments, source.span);
		} else if (source is CoreCStructCallResult) {
			foreach (var argument in ((CoreCStructCallResult) source).arguments) {
				value (argument);
			}
			projections.invalidate (state);
		} else if (source is CoreSlotsRecordRead) {
			var indexed = (CoreSlotsRecordRead) source;
			place (indexed.store);
			value (indexed.index);
		} else if (source is CoreStructAwait) {
			value (((CoreStructAwait) source).operation);
		} else {
			fail (source.span, "Core nonnull projection proof requires an exact copied producer");
		}
	}

	private bool value(CoreValue expression) {
		if (!state.reachable || diagnostic != null) {
			return false;
		}
		if (expression is CoreStructProjectionValue) {
			projected_producer (((CoreStructProjectionValue) expression).source);
			return false;
		}
		Object? source = (expression is CoreCallValue) ? null : key (expression);
		if (source != null) {
			return state.knows (source);
		}
		if (expression is CoreOwnedArgumentValue) {
			var argument = (CoreOwnedArgumentValue) expression;
			return argument.source != null ? consume(argument.source) : argument.producer != null && value (argument.producer);
		}
		if (expression is CoreCCallValue) {
			foreach (var argument in ((CoreCCallValue) expression).arguments) {
				value (argument);
			}
			projections.invalidate (state);
			return false;
		}
		if (expression is CoreCallValue) {
			var invoked = (CoreCallValue) expression;
			return call (invoked.target, invoked.receiver, invoked.arguments, invoked.span);
		}
		if (expression is CoreOwnedObjectResultConstruction) {
			var constructed = (CoreOwnedObjectResultConstruction) expression;
			call (constructed.constructor, null, constructed.arguments, constructed.span);
			return true;
		}
		if (expression is CoreClosureBind) {
			consume (((CoreClosureBind) expression).source);
			projections.invalidate (state);
			return false;
		}
		if (expression is CoreClosureCall) {
			var invoked = (CoreClosureCall) expression;
			value (invoked.callee);
			foreach (var argument in invoked.arguments) {
				value (argument);
			}
			projections.invalidate (state);
			return false;
		}
		if (expression is CoreRetainedOperation) {
			var operation = (CoreRetainedOperation) expression;
			value (operation.callee);
			foreach (var argument in operation.arguments) {
				value (argument);
			}
			projections.invalidate (state);
			return false;
		}
		if (expression is CoreSharedOperation) {
			var operation = (CoreSharedOperation) expression;
			if (operation.action == SharedAction.ACQUIRE && operation.source != null) {
				consume (operation.source);
			} else {
				value (operation.operand);
			} projections.invalidate (state);
			return false;
		}
		if (expression is CoreFunctionAddress) {
			return true;
		}
		if (expression is CoreFunctionValueCall) {
			var call = (CoreFunctionValueCall) expression;
			value (call.callee);
			foreach (var argument in call.arguments) {
				value (argument);
			}
			projections.invalidate (state);
			return false;
		}
		if (expression is CoreStorageReceiverValue) {
			return !((CoreStorageReceiverValue) expression).storage.fallible;
		}
		if (expression is CoreResultStorageReceiverValue || expression is CoreReceiverValue) {
			return true;
		}
		if (expression is CoreClassUpcast) {
			return value (((CoreClassUpcast) expression).reference);
		}
		if (expression is CoreObjectReceiverValue) {
			value (((CoreObjectReceiverValue) expression).reference);
			return true;
		}
		if (expression is CoreLoadValue) {
			var load = (CoreLoadValue) expression;
			place (load.source);
			return (load.source is CoreLocalPlace && state.knows (load.source)) || (load.source is CoreIndirectFieldPlace && ((CoreIndirectFieldPlace) load.source).field.requires_nonnull);
		}
		if (expression is CoreOwnedFieldBorrow) {
			place (((CoreOwnedFieldBorrow) expression).source);
			return ((CoreOwnedFieldBorrow) expression).source.field.requires_nonnull;
		}
		if (expression is CoreSlotsValue) {
			var slot = (CoreSlotsValue) expression;
			place (slot.store);
			if (slot.operand != null) {
				value (slot.operand);
			}
			return false;
		}
		if (expression is CoreShortCircuitValue) {
			var split = condition (expression);
			state = NonNullFacts.join (split.yes, split.no);
			return false;
		}
		if (expression is CoreBinaryValue) {
			value (((CoreBinaryValue) expression).left);
			value (((CoreBinaryValue) expression).right);
			return false;
		}
		if (expression is CoreComparisonChain) {
			var chain = (CoreComparisonChain) expression;
			NonNullFacts? exits = null;
			for (int i = 0; i < chain.operands.length; i++) {
				value (chain.operands[i]);
				if (i >= 1) {
					exits = exits == null ? state.copy() : NonNullFacts.join (exits, state);
				}
			}
			if (exits != null) {
				state = NonNullFacts.join (exits, state);
			}
			return false;
		}
		if (expression is CorePrefixValue) {
			value (((CorePrefixValue) expression).operand);
			return false;
		}
		if (expression is CoreIntegerConversionValue) {
			value (((CoreIntegerConversionValue) expression).operand);
			return false;
		}
		if (expression is CoreFloatConversionValue) {
			value (((CoreFloatConversionValue) expression).operand);
			return false;
		}
		if (expression is CoreNumericConversionValue) {
			value (((CoreNumericConversionValue) expression).operand);
			return false;
		}
		if (expression is CoreTextLengthValue) {
			value (((CoreTextLengthValue) expression).receiver);
			return false;
		}
		if (expression is CoreSliceLengthValue) {
			value (((CoreSliceLengthValue) expression).slice);
			return false;
		}
		if (expression is CoreSliceFromArrayValue) {
			var slice = (CoreSliceFromArrayValue) expression;
			if (slice.start != null) {
				value (slice.start);
			}
			if (slice.count != null) {
				value (slice.count);
			}
			return false;
		}
		if (expression is CoreOwnedBufferAllocate) {
			var allocation = (CoreOwnedBufferAllocate) expression;
			value (allocation.count);
			if (allocation.failure_call != null) {
				fail (allocation.span, "nonnull proof excludes uncertain allocation failure actions in this definition");
			}
			return false;
		}
		if (expression is CoreOwnedBufferBorrow || expression is CoreIntegerValue || expression is CoreFloatValue || expression is CoreBooleanValue || expression is CoreNullPointerValue || expression is CoreTextValue || expression is CoreUtf8FactoryValue) {
			return false;
		}
		fail (expression.span, "nonnull proof requires a supported synchronous value/effect shape");
		return false;
	}

	private void loop(CoreWhile loop) {
		var entry = state.copy ();
		var header = entry.copy ();
		for (int round = 0; round < 4096 && diagnostic == null; round++) {
			state = header.copy ();
			var split = condition (loop.condition);
			var frame = new CoreNonNullLoop (loop.target);
			loops.add (frame);
			state = split.yes;
			block (loop.body);
			foreach (var continued in frame.continues) {
				state = NonNullFacts.join (state, continued);
			}
			if (loop.step != null) {
				block (loop.step);
			}
			loops.remove_index (loops.length - 1);
			var next = NonNullFacts.join (entry, state);
			if (next.same (header)) {
				state = split.no;
				foreach (var exited in frame.exits) {
					state = NonNullFacts.join (state, exited);
				}
				return;
			}
			header = next;
		}
		if (diagnostic == null) {
			fail (loop.span, "nonnull loop proof did not converge within its bounded fact domain");
		}
	}

	private void block(CoreBlock body) {
		foreach (var node in body.statements) {
			statement (node);
		}
		projections.invalidate (state);
	}

	private void statement(CoreStatement node) {
		if (!state.reachable || diagnostic != null) {
			return;
		}
		if (node is CoreActorSend) {
			var send = (CoreActorSend) node;
			value (send.sender);
			if (send.scalar != null) {
				value (send.scalar);
			}
			if (send.message != null) {
				consume (send.message);
			}
			projections.invalidate (state);
			return;
		}
		if (node is CoreAsyncDelay) {
			value (((CoreAsyncDelay) node).ticks);
			projections.invalidate (state);
			return;
		}
		if (node is CoreScope) {
			block (((CoreScope) node).body);
			return;
		}
		if (node is CoreInitialize) {
			var initial = (CoreInitialize) node;
			place (initial.target);
			bool proven = value (initial.value);
			projections.invalidate (state);
			if (initial.target is CoreLocalPlace) {
				var local = (CoreLocalPlace) initial.target;
				if (required (local)) {
					require (proven, initial.value.span);
				}
				write (local, proven);
			}
			return;
		}
		if (node is CoreObjectConstruction) {
			var construction = (CoreObjectConstruction) node;
			var invoked = construction as CoreConstructorObjectInitialization;
			if (invoked != null) {
				call (invoked.constructor, null, invoked.arguments, invoked.span);
			} else {
				foreach (var field in construction.initializers) {
					value (field.value);
				}
			} write (construction.target, !construction.storage.fallible);
			return;
		}
		if (node is CoreStore) {
			var store = (CoreStore) node;
			place (store.target);
			bool proven = value (store.value);
			projections.invalidate (state);
			if (store.target is CoreLocalPlace) {
				var local = (CoreLocalPlace) store.target;
				if (required (local)) {
					require (proven, store.value.span);
				}
				write (local, proven);
			}
			return;
		}
		if (node is CoreOwnershipTransfer) {
			var transfer = (CoreOwnershipTransfer) node;
			bool proven = consume (transfer.source);
			if (required (transfer.destination.place)) {
				require (proven, transfer.span);
			}
			write (transfer.destination.place, proven);
			return;
		}
		if (node is CoreOwnershipRearm) {
			var rearm = (CoreOwnershipRearm) node;
			bool proven = rearm.source != null ? consume(rearm.source) : rearm.producer != null && value (rearm.producer);
			if (required (rearm.owner.place)) {
				require (proven, rearm.span);
			}
			write (rearm.owner.place, proven);
			return;
		}
		if (node is CoreOwnershipRelease) {
			write (((CoreOwnershipRelease) node).owner.place, false);
			return;
		}
		if (node is CoreValueStatement) {
			value (((CoreValueStatement) node).value);
			return;
		}
		if (node is CoreCallStatement) {
			var invoked = (CoreCallStatement) node;
			call (invoked.target, invoked.receiver, invoked.arguments, invoked.span);
			return;
		}
		if (node is CoreCCallStatement) {
			foreach (var argument in ((CoreCCallStatement) node).arguments) {
				value (argument);
			}
			projections.invalidate (state);
			return;
		}
		if (node is CoreReturn) {
			var returned = ((CoreReturn) node).value;
			bool proven = returned != null && value (returned);
			if (function.nonnull_result) {
				require (proven, node.span);
			}
			state.reachable = false;
			return;
		}
		if (node is CoreOwnershipReturn) {
			var returned = (CoreOwnershipReturn) node;
			bool proven = returned.source != null ? consume(returned.source) : returned.producer != null && value (returned.producer);
			if (function.nonnull_result) {
				require (proven, node.span);
			}
			state.reachable = false;
			return;
		}
		if (node is CoreThrow) {
			write (((CoreThrow) node).source, false);
			state.reachable = false;
			return;
		}
		if (node is CoreIf) {
			var branch = (CoreIf) node;
			var split = condition (branch.condition);
			state = split.yes;
			block (branch.then_block);
			var yes = state;
			state = split.no;
			if (branch.else_block != null) {
				block (branch.else_block);
			}
			state = NonNullFacts.join (yes, state);
			return;
		}
		if (node is CoreWhile) {
			loop ((CoreWhile) node);
			return;
		}
		if (node is CoreBreak || node is CoreContinue) {
			var target = (node is CoreBreak) ? ((CoreBreak) node).target : ((CoreContinue) node).target;
			for (int i = loops.length - 1; i >= 0; i--) {
				if (loops[i].target == target) {
					((node is CoreBreak) ? loops[i].exits : loops[i].continues).add (state.copy ());
					state.reachable = false;
					return;
				}
			}
			fail (node.span, "Core nonnull loop exit lost its target");
			return;
		}
		if (node is CoreTry) {
			var guarded = (CoreTry) node;
			var entry = state.copy ();
			var parent_writes = writes;
			writes = new GenericArray<Object> ();
			block (guarded.body);
			var changed = writes;
			writes = parent_writes;
			foreach (var slot in changed) {
				if (!writes.find (slot)) {
					writes.add (slot);
				}
			}
			var merged = state;
			foreach (var caught in guarded.catches) {
				state = entry.copy ();
				foreach (var slot in changed) {
					if (!required (slot)) {
						state.assign (slot, false);
					}
				}
				state.assign (caught.binding, true);
				block (caught.body);
				merged = NonNullFacts.join (merged, state);
			}
			state = merged;
			return;
		}
		if (node is CoreOwnedFieldTransfer) {
			projections.invalidate (state);
			var transfer = (CoreOwnedFieldTransfer) node;
			place (transfer.destination);
			bool proven = transfer.source != null ? consume(transfer.source) : transfer.producer != null && value (transfer.producer);
			if (transfer.destination.field.requires_nonnull) {
				require (proven, transfer.span);
			}
			return;
		}
		if (node is CoreSlotsAppend) {
			projections.invalidate (state);
			place (((CoreSlotsAppend) node).store);
			consume (((CoreSlotsAppend) node).incoming);
			return;
		}
		fail (node.span, "Core nonnull proof requires a supported synchronous statement/effect shape");
	}

}
}
