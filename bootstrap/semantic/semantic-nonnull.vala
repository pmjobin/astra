// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.Semantic {
private class NonNullSplit : Object {
	internal NonNullFacts yes;
	internal NonNullFacts no;
	internal NonNullSplit (NonNullFacts yes, NonNullFacts no) {
		this.yes = yes;
		this.no = no;
	}

}
private class NonNullLoop : Object {
	internal CheckedLoopTarget target;
	internal GenericArray<NonNullFacts> exits = new GenericArray<NonNullFacts> ();
	internal GenericArray<NonNullFacts> continues = new GenericArray<NonNullFacts> ();
	internal NonNullLoop (CheckedLoopTarget target) {
		this.target = target;
	}

}
// Source diagnostics only. Core and downstream passes must reconstruct their
// own facts from their own nodes before these contracts can be admitted.
internal class SemanticNonNull : Object {
	private NonNullFacts state = new NonNullFacts ();
	private NonNullProjections projections = new NonNullProjections ();
	private FunctionSymbol function;
	private Diagnostic? diagnostic;
	private GenericArray<NonNullLoop> loops = new GenericArray<NonNullLoop> ();
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
		return (slot is LocalSymbol && (((LocalSymbol) slot).requires_nonnull || (((LocalSymbol) slot).incoming_parameter != null && ((LocalSymbol) slot).incoming_parameter.requires_nonnull))) || (slot is ParameterSymbol && ((ParameterSymbol) slot).requires_nonnull);
	}

	private void require(bool proven, SourceSpan span) {
		if (state.reachable && !proven) {
			fail (span, "nonnull contract requires a current non-null proof; use an explicit null branch or a proven nonnull result");
		}
	}

	public static Diagnostic? check(CheckedProgram program, GenericArray<FunctionSymbol> selected) {
		foreach (var instance in program.native_instances ()) {
			foreach (var field in instance.fields) {
				if (field.requires_nonnull && (!(instance is ClassSymbol) || !field.is_owned_field || !NonNullReferenceTypes.supports (field.semantic_type) || instance.semantic_type is ExactGenericClassType || instance.semantic_type.is_parameterized ())) {
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
			bool needed = selected.find (definition.symbol) || definition.symbol.nonnull_result;
			foreach (var parameter in definition.symbol.parameters) {
				needed = needed || parameter.requires_nonnull;
			}
			foreach (var local in definition.locals) {
				needed = needed || local.requires_nonnull;
			}
			if (!needed) {
				continue;
			}
			if (definition.symbol.nonnull_result && (!NonNullReferenceTypes.supports (definition.symbol.return_type) || (definition.symbol.result_contract != ResultOwnershipContract.OWNED_TRANSFER && definition.symbol.result_contract != ResultOwnershipContract.RECEIVER_BORROW && !(definition.symbol.return_type is FunctionValueType)))) {
				return new Diagnostic (definition.span, "nonnull result requires an exact native owned or established receiver-borrow Class/Resource contract");
			}
			foreach (var parameter in definition.symbol.parameters) {
				if (parameter.requires_nonnull && !NonNullReferenceTypes.supports (parameter.semantic_type)) {
					return new Diagnostic (parameter.span, "nonnull parameter requires an exact Class or Resource reference");
				}
			}
			foreach (var local in definition.locals) {
				if (local.requires_nonnull && !NonNullReferenceTypes.supports (local.semantic_type)) {
					return new Diagnostic (local.span, "nonnull local requires an exact Class or Resource reference");
				}
			}
			bool boundary_contract = definition.symbol.nonnull_result;
			foreach (var parameter in definition.symbol.parameters) {
				boundary_contract = boundary_contract || parameter.requires_nonnull;
			}
			foreach (var exported in program.c_exports) {
				if (boundary_contract && exported.target == definition.symbol) {
					return new Diagnostic (definition.span, "nonnull contract proofs cannot cross an exported C boundary");
				}
			}
			var proof = new SemanticNonNull ();
			proof.function = definition.symbol;
			if (definition.symbol is GenericFunctionSymbol || definition.symbol.dispatch_kind != ClassDispatchKind.DIRECT) {
				return new Diagnostic (definition.span, "nonnull contracts require a concrete direct native definition");
			}
			foreach (var parameter in definition.symbol.parameters) {
				proof.state.assign (parameter, parameter.requires_nonnull);
			}
			foreach (var local in definition.locals) {
				if (local.incoming_parameter != null) {
					proof.state.assign (local, local.incoming_parameter.requires_nonnull);
				}
			}
			proof.statement (definition.body);
			if (proof.diagnostic != null) {
				return proof.diagnostic;
			}
		}
		return null;
	}

	private Object? receiver_key(CheckedExpression? expression) {
		if (expression == null) {
			return null;
		}
		if (expression is CheckedClassUpcast) {
			return receiver_key (((CheckedClassUpcast) expression).reference);
		}
		if (expression is CheckedObjectReceiverExpression) {
			return receiver_key (((CheckedObjectReceiverExpression) expression).reference);
		}
		if (expression is CheckedThisExpression) {
			return ((CheckedThisExpression) expression).receiver;
		}
		if (expression is CheckedObjectReferenceExpression) {
			return ((CheckedObjectReferenceExpression) expression).storage;
		}
		return key (expression);
	}

	private Object? property_key(DirectCallableSymbol? target, CheckedExpression? receiver) {
		var getter = target as PropertyGetterSymbol;
		if (getter == null || !getter.property_symbol.is_borrowed || getter.property_symbol.is_lazy) {
			return null;
		}
		return projections.key (receiver_key (receiver), getter.property_symbol);
	}

	private Object? key(CheckedExpression expression) {
		if (expression is CheckedCallExpression) {
			var call = (CheckedCallExpression) expression;
			return property_key (call.target, call.receiver);
		}
		if (expression is CheckedClassUpcast) {
			return key (((CheckedClassUpcast) expression).reference);
		}
		if (expression is CheckedLocalReferenceExpression) {
			return ((CheckedLocalReferenceExpression) expression).local;
		}
		if (expression is CheckedParameterReferenceExpression) {
			return ((CheckedParameterReferenceExpression) expression).parameter;
		}
		if (expression is CheckedOwnedBorrowValue) {
			return ((CheckedOwnedBorrowValue) expression).source;
		}
		if (expression is CheckedWithReference) {
			return ((CheckedWithReference) expression).contract.source;
		}
		return null;
	}

	private NonNullSplit condition(CheckedExpression expression) {
		if (expression is CheckedShortCircuitExpression) {
			var conditional = (CheckedShortCircuitExpression) expression;
			var left = condition (conditional.left);
			bool conjunction = conditional.operator_kind == ShortCircuitOperator.AND;
			state = conjunction ? left.yes : left.no;
			var right = condition (conditional.right);
			return conjunction ? new NonNullSplit (right.yes, NonNullFacts.join (left.no, right.no)) : new NonNullSplit (NonNullFacts.join (left.yes, right.yes), right.no);
		}
		if (expression is CheckedPrefixExpression && ((CheckedPrefixExpression) expression).operator_kind == PrefixOperator.NOT) {
			var nested = condition (((CheckedPrefixExpression) expression).operand);
			return new NonNullSplit (nested.no, nested.yes);
		}
		value (expression);
		var yes = state.copy ();
		var no = state.copy ();
		var literal = expression as CheckedBooleanExpression;
		if (literal != null) {
			(literal.literal == BooleanLiteral.TRUE ? no : yes).reachable = false;
		}
		var binary = expression as CheckedBinaryExpression;
		if (binary != null && (binary.operator_kind == BinaryOperator.EQUAL || binary.operator_kind == BinaryOperator.NOT_EQUAL)) {
			Object? source = (binary.left is CheckedNullPointerExpression) ? key (binary.right) : (binary.right is CheckedNullPointerExpression) ? key (binary.left) : null;
			if (source != null) {
				(binary.operator_kind == BinaryOperator.NOT_EQUAL ? yes : no).refine (source);
			}
		}
		return new NonNullSplit (yes, no);
	}

	private bool call(DirectCallableSymbol? target, CheckedExpression? receiver, GenericArray<CheckedExpression> arguments, SourceSpan span) {
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
		bool proven = target is FunctionSymbol && ((FunctionSymbol) target).nonnull_result || projection != null && state.knows (projection);
		if (projection == null) {
			projections.invalidate (state);
		}
		return proven;
	}

	private void place(CheckedPlace storage) {
		if (storage is CheckedLocalPlace) {
			return;
		}
		if (storage is CheckedObjectFieldPlace) {
			value (((CheckedObjectFieldPlace) storage).reference);
			return;
		}
		if (storage is CheckedReceiverFieldPlace) {
			value (((CheckedReceiverFieldPlace) storage).receiver);
			return;
		}
		if (storage is CheckedFieldPlace) {
			place (((CheckedFieldPlace) storage).aggregate);
			return;
		}
		if (storage is CheckedArrayElementPlace) {
			value (((CheckedArrayElementPlace) storage).index);
			return;
		}
		if (storage is CheckedSliceElementPlace) {
			value (((CheckedSliceElementPlace) storage).slice);
			value (((CheckedSliceElementPlace) storage).index);
			return;
		}
		fail (storage.span, "nonnull proof does not admit uncertain indirect storage in this definition");
	}

	private void projected_producer(CheckedStructProducer source) {
		if (source is CheckedStructInvocationResult) {
			value (((CheckedStructInvocationResult) source).invocation);
			return;
		}
		if (source is CheckedStructBorrowSnapshot) {
			place (((CheckedStructBorrowSnapshot) source).source);
			return;
		}
		if (source is CheckedStructProjectionProducer) {
			projected_producer (((CheckedStructProjectionProducer) source).source);
		} else if (source is CheckedStructSnapshot) {
			place (((CheckedStructSnapshot) source).source);
		} else if (source is CheckedStructCallResult) {
			var invoked = (CheckedStructCallResult) source;
			call (invoked.target, invoked.receiver, invoked.arguments, source.span);
		} else if (source is CheckedCStructCallResult) {
			var invoked = (CheckedCStructCallResult) source;
			call (invoked.target, null, invoked.arguments, source.span);
		} else if (source is CheckedSlotsRecordRead) {
			var indexed = (CheckedSlotsRecordRead) source;
			place (indexed.store);
			value (indexed.index);
		} else if (source is CheckedStructAwait) {
			value (((CheckedStructAwait) source).operation);
		} else {
			fail (source.span, "nonnull projection proof requires an exact copied producer");
		}
	}

	private bool value(CheckedExpression expression) {
		if (!state.reachable || diagnostic != null) {
			return false;
		}
		if (expression is CheckedStructProjectionValue) {
			projected_producer (((CheckedStructProjectionValue) expression).source);
			return false;
		}
		Object? source = (expression is CheckedCallExpression) ? null : key (expression);
		if (source != null) {
			return state.knows (source);
		}
		if (expression is CheckedOwnershipMove) {
			var moved = ((CheckedOwnershipMove) expression).source;
			bool result = state.knows (moved);
			write (moved, false);
			return result;
		}
		if (expression is CheckedOwnedArgument) {
			var argument = (CheckedOwnedArgument) expression;
			return argument.transfer != null ? value(argument.transfer) : argument.producer != null && value (argument.producer);
		}
		if (expression is CheckedCallExpression) {
			var invoked = (CheckedCallExpression) expression;
			return call (invoked.target, invoked.receiver, invoked.arguments, invoked.span);
		}
		if (expression is CheckedOwnedObjectResultConstruction) {
			var constructed = (CheckedOwnedObjectResultConstruction) expression;
			call (constructed.constructor, null, constructed.arguments, constructed.span);
			return true;
		}
		if (expression is CheckedFunctionAddress) {
			return true;
		}
		if (expression is CheckedFunctionValueCall) {
			var call = (CheckedFunctionValueCall) expression;
			value (call.callee);
			foreach (var argument in call.arguments) {
				value (argument);
			}
			projections.invalidate (state);
			return false;
		}
		if (expression is CheckedObjectReferenceExpression) {
			return !((CheckedObjectReferenceExpression) expression).storage.fallible;
		}
		if (expression is CheckedThisExpression) {
			return true;
		}
		if (expression is CheckedClassUpcast) {
			return value (((CheckedClassUpcast) expression).reference);
		}
		if (expression is CheckedObjectReceiverExpression) {
			value (((CheckedObjectReceiverExpression) expression).reference);
			return true;
		}
		if (expression is CheckedLoadExpression) {
			var load = (CheckedLoadExpression) expression;
			place (load.source);
			return (load.source is CheckedLocalPlace && state.knows (((CheckedLocalPlace) load.source).local)) || (load.source is CheckedReceiverFieldPlace && ((CheckedReceiverFieldPlace) load.source).field.requires_nonnull) || (load.source is CheckedObjectFieldPlace && ((CheckedObjectFieldPlace) load.source).field.requires_nonnull);
		}
		if (expression is CheckedOwnedFieldBorrow) {
			place (((CheckedOwnedFieldBorrow) expression).source);
			return ((CheckedOwnedFieldBorrow) expression).field.requires_nonnull;
		}
		if (expression is CheckedSlotsValue) {
			var slot = (CheckedSlotsValue) expression;
			place (slot.store);
			if (slot.operand != null) {
				value (slot.operand);
			}
			return false;
		}
		if (expression is CheckedShortCircuitExpression) {
			var split = condition (expression);
			state = NonNullFacts.join (split.yes, split.no);
			return false;
		}
		if (expression is CheckedBinaryExpression) {
			value (((CheckedBinaryExpression) expression).left);
			value (((CheckedBinaryExpression) expression).right);
			return false;
		}
		if (expression is CheckedComparisonChain) {
			var chain = (CheckedComparisonChain) expression;
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
		if (expression is CheckedPrefixExpression) {
			value (((CheckedPrefixExpression) expression).operand);
			return false;
		}
		if (expression is CheckedIntegerConversionExpression) {
			value (((CheckedIntegerConversionExpression) expression).operand);
			return false;
		}
		if (expression is CheckedFloatConversionExpression) {
			value (((CheckedFloatConversionExpression) expression).operand);
			return false;
		}
		if (expression is CheckedNumericConversionExpression) {
			value (((CheckedNumericConversionExpression) expression).operand);
			return false;
		}
		if (expression is CheckedTextLengthExpression) {
			value (((CheckedTextLengthExpression) expression).receiver);
			return false;
		}
		if (expression is CheckedLengthExpression) {
			var length = (CheckedLengthExpression) expression;
			if (length.slice != null) {
				value (length.slice);
			}
			return false;
		}
		if (expression is CheckedSliceFromArrayExpression) {
			var slice = (CheckedSliceFromArrayExpression) expression;
			if (slice.start != null) {
				value (slice.start);
			}
			if (slice.count != null) {
				value (slice.count);
			}
			return false;
		}
		if (expression is CheckedOwnedBufferAllocate) {
			var allocation = (CheckedOwnedBufferAllocate) expression;
			value (allocation.count);
			if (allocation.failure_call != null) {
				fail (allocation.span, "nonnull proof excludes uncertain allocation failure actions in this definition");
			}
			return false;
		}
		if (expression is CheckedOwnedBufferBorrow || expression is CheckedIntegerExpression || expression is CheckedFloatExpression || expression is CheckedBooleanExpression || expression is CheckedNullPointerExpression || expression is CheckedTextExpression || expression is CheckedConstantReference || expression is CheckedFieldReferenceExpression || expression is CheckedUtf8FactoryExpression) {
			return false;
		}
		fail (expression.span, "nonnull proof requires a supported synchronous value/effect shape");
		return false;
	}

	private void loop(CheckedWhile loop) {
		var entry = state.copy ();
		var header = entry.copy ();
		for (int round = 0; round < 4096 && diagnostic == null; round++) {
			state = header.copy ();
			var split = condition (loop.condition);
			var frame = new NonNullLoop (loop.target);
			loops.add (frame);
			state = split.yes;
			statement (loop.body);
			foreach (var continued in frame.continues) {
				state = NonNullFacts.join (state, continued);
			}
			if (loop.step != null) {
				statement (loop.step);
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

	private void statement(CheckedStatement node) {
		if (!state.reachable || diagnostic != null) {
			return;
		}
		if (node is CheckedAsyncDelay) {
			value (((CheckedAsyncDelay) node).ticks);
			projections.invalidate (state);
			return;
		}
		if (node is CheckedBlockStatement) {
			foreach (var child in ((CheckedBlockStatement) node).statements) {
				statement (child);
			}
			projections.invalidate (state);
			return;
		}
		if (node is CheckedLocalDeclaration) {
			var local = (CheckedLocalDeclaration) node;
			bool proven = value (local.initializer);
			if (required (local.local)) {
				require (proven, local.initializer.span);
			}
			write (local.local, proven);
			return;
		}
		if (node is CheckedObjectConstruction) {
			var construction = (CheckedObjectConstruction) node;
			var invoked = construction as CheckedConstructorObjectInitialization;
			if (invoked != null) {
				call (invoked.constructor, null, invoked.arguments, invoked.span);
			} else {
				foreach (var field in construction.initializers) {
					value (field.expression);
				}
			} write (construction.local, !construction.storage.fallible);
			return;
		}
		if (node is CheckedAssignment) {
			var assignment = (CheckedAssignment) node;
			bool proven = value (assignment.expression);
			if (required (assignment.target)) {
				require (proven, assignment.expression.span);
			}
			write (assignment.target, proven);
			return;
		}
		if (node is CheckedStore) {
			var store = (CheckedStore) node;
			place (store.target);
			bool proven = value (store.value);
			projections.invalidate (state);
			if (store.target is CheckedLocalPlace) {
				var local = ((CheckedLocalPlace) store.target).local;
				if (required (local)) {
					require (proven, store.value.span);
				}
				write (local, proven);
			}
			return;
		}
		if (node is CheckedOwnershipRearmAssignment) {
			var rearm = (CheckedOwnershipRearmAssignment) node;
			bool proven = value (rearm.incoming);
			if (required (rearm.owner)) {
				require (proven, rearm.incoming.span);
			}
			write (rearm.owner, proven);
			return;
		}
		if (node is CheckedOwnershipRelease) {
			write (((CheckedOwnershipRelease) node).owner, false);
			return;
		}
		if (node is CheckedValueStatement) {
			value (((CheckedValueStatement) node).value);
			return;
		}
		if (node is CheckedCallStatement) {
			var invoked = (CheckedCallStatement) node;
			call (invoked.target, invoked.receiver, invoked.arguments, invoked.span);
			return;
		}
		if (node is CheckedReturnStatement) {
			var returned = ((CheckedReturnStatement) node).expression;
			bool proven = returned != null && value (returned);
			if (function.nonnull_result) {
				require (proven, node.span);
			}
			state.reachable = false;
			return;
		}
		if (node is CheckedOwnershipReturn) {
			var returned = (CheckedOwnershipReturn) node;
			bool proven = returned.transfer != null ? value(returned.transfer) : returned.producer != null && value (returned.producer);
			if (function.nonnull_result) {
				require (proven, node.span);
			}
			state.reachable = false;
			return;
		}
		if (node is CheckedThrow) {
			var thrown = (CheckedThrow) node;
			if (thrown.construction != null) {
				statement (thrown.construction);
			}
			write (thrown.owner, false);
			state.reachable = false;
			return;
		}
		if (node is CheckedIf) {
			var branch = (CheckedIf) node;
			var split = condition (branch.condition);
			state = split.yes;
			statement (branch.then_body);
			var yes = state;
			state = split.no;
			if (branch.else_body != null) {
				statement (branch.else_body);
			}
			state = NonNullFacts.join (yes, state);
			return;
		}
		if (node is CheckedWhile) {
			loop ((CheckedWhile) node);
			return;
		}
		if (node is CheckedBreak || node is CheckedContinue) {
			var target = (node is CheckedBreak) ? ((CheckedBreak) node).target : ((CheckedContinue) node).target;
			for (int i = loops.length - 1; i >= 0; i--) {
				if (loops[i].target == target) {
					((node is CheckedBreak) ? loops[i].exits : loops[i].continues).add (state.copy ());
					state.reachable = false;
					return;
				}
			}
			fail (node.span, "nonnull loop exit lost its exact lexical target");
			return;
		}
		if (node is CheckedTry) {
			var guarded = (CheckedTry) node;
			var entry = state.copy ();
			var parent_writes = writes;
			writes = new GenericArray<Object> ();
			statement (guarded.body);
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
				statement (caught.body);
				merged = NonNullFacts.join (merged, state);
			}
			state = merged;
			return;
		}
		if (node is CheckedFieldInitialize) {
			place (((CheckedFieldInitialize) node).target);
			value (((CheckedFieldInitialize) node).value);
			projections.invalidate (state);
			return;
		}
		if (node is CheckedOwnedFieldTransfer) {
			projections.invalidate (state);
			var transfer = (CheckedOwnedFieldTransfer) node;
			place (transfer.destination);
			bool proven = value (transfer.incoming);
			if (transfer.field.requires_nonnull) {
				require (proven, transfer.incoming.span);
			}
			return;
		}
		if (node is CheckedSlotsAppend) {
			projections.invalidate (state);
			place (((CheckedSlotsAppend) node).store);
			value (((CheckedSlotsAppend) node).incoming);
			return;
		}
		fail (node.span, "nonnull proof requires a supported synchronous statement/effect shape");
	}

}
}
