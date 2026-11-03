// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Core {
internal class CoreEffectCall : Object {
	internal CoreFunction scope;
	internal CoreFunction target;
	internal GenericArray<CoreValue> arguments;
	internal bool protected_call;
	internal CoreEffectCall (CoreFunction scope, CoreFunction target, GenericArray<CoreValue> arguments, bool protected_call) {
		this.scope = scope;
		this.target = target;
		this.arguments = arguments;
		this.protected_call = protected_call;
	}

}

// Reconstruct code-value flow from Core identities, never Source summaries.
internal class CoreCodeOrigins : Object {
	private Astra.Code.CodeOrigins graph = new Astra.Code.CodeOrigins ();
	private ReadonlyCallContext call_context = new ReadonlyCallContext ();
	private GenericArray<CoreFunctionValueCall> indirect_calls = new GenericArray<CoreFunctionValueCall> ();
	private GenericArray<CoreEffectCall> effect_calls = new GenericArray<CoreEffectCall> ();
	private CoreFunction? current_scope;
	internal CoreCodeOrigins (CoreProgram program) {
		foreach (var owner in program.native_instances ()) {
			call_context.add_type (owner.semantic_type);
			foreach (var field in owner.fields) {
				call_context.add_field (owner.semantic_type, field.semantic_type);
			}
			foreach (var property in owner.properties) {
				if (property.is_owned_lazy) {
					call_context.add_field (owner.semantic_type, property.semantic_type);
				}
			}
			foreach (var field in owner.fields) {
				if (field.semantic_type is FunctionValueType) {
					graph.storage (field);
				}
			}
		}
		foreach (var exported in program.c_exports) {
			if (exported.target == null) {
				continue;
			}
			foreach (var parameter in exported.target.parameters) {
				graph.unknown (parameter);
				opaque_type (parameter.semantic_type);
			}
		}
		foreach (var function in program.all_definitions ()) {
			current_scope = function;
			foreach (var parameter in function.parameters) {
				graph.parameter (parameter);
			}
			foreach (var local in function.locals) {
				if (local.incoming_parameter != null) {
					graph.copy (local, local.incoming_parameter);
				}
			}
			if (function.native_declaration != null || function.name_span.file.native_interface) {
				graph.unknown (function);
				foreach (var parameter in function.parameters) {
					opaque_type (parameter.semantic_type);
				}
				opaque_type (function.return_type);
			} else {
				block (function.body, function);
			}
		}
		current_scope = null;
		uint prior = 0;
		do {
			prior = graph.revision;
			for (int i = 0; i < indirect_calls.length; i++) {
				var invoked = indirect_calls[i];
				var candidates = graph.candidates (invoked.callee);
				if (candidates == null) {
					continue;
				}
				foreach (var candidate in candidates) {
					call (candidate as CoreFunction, invoked.arguments, null);
				}
			}
		} while (prior != graph.revision);
	}

	private void opaque_type(SemanticType type) {
		if (type.kind != TypeKind.VOID && !FunctionValueType.scalar (type) && !(type is HandleType) && !(type is StringType)) {
			graph.escape_storage ();
		}
	}

	private Object? place(CorePlace storage) {
		if (storage is CoreLocalPlace) {
			return storage;
		}
		if (storage is CoreFieldPlace) {
			return ((CoreFieldPlace) storage).field;
		}
		if (storage is CoreIndirectFieldPlace) {
			value (((CoreIndirectFieldPlace) storage).pointer);
			return ((CoreIndirectFieldPlace) storage).field;
		}
		if (storage is CoreArrayElementPlace) {
			value (((CoreArrayElementPlace) storage).index);
		} else if (storage is CoreSliceElementPlace) {
			var indexed = (CoreSliceElementPlace) storage;
			value (indexed.slice);
			value (indexed.index);
		}
		return null;
	}

	private void call(CoreFunction? target, GenericArray<CoreValue> arguments, CoreValue? receiver) {
		bool protected_call = receiver != null && call_context.overlaps (receiver.semantic_type);
		foreach (var argument in arguments) {
			protected_call |= call_context.overlaps (argument.semantic_type);
		}
		if (current_scope != null && target != null) {
			effect_calls.add (new CoreEffectCall (current_scope, target, arguments, protected_call));
		}
		if (receiver != null) {
			value (receiver);
		}
		for (int i = 0; i < arguments.length; i++) {
			value (arguments[i]);
			if (target != null && i < target.parameters.length) {
				graph.copy (target.parameters[i], arguments[i]);
			}
		}
	}

	private void value(CoreValue expression) {
		if (expression is CoreOwnedArgumentValue) {
			var owned = (CoreOwnedArgumentValue) expression;
			if (owned.producer != null) {
				value (owned.producer);
			}
		} else if (expression is CoreTaskAwait) {
			var wait = (CoreTaskAwait) expression;
			if (wait.bridge_executor != null) {
				value (wait.bridge_executor);
			}
			value (wait.child);
		} else if (expression is CoreAsyncOperation) {
			var operation = (CoreAsyncOperation) expression;
			if (operation.executor != null) {
				value (operation.executor);
			}
			if (operation.task != null) {
				value (operation.task);
			}
			if (operation.argument != null) {
				value (operation.argument);
			}
		} else if (expression is CoreFunctionAddress) {
			var target = ((CoreFunctionAddress) expression).target;
			if (target == null) {
				graph.unknown (expression);
			} else {
				graph.address (expression, target);
			}
		} else if (expression is CoreParameterValue) {
			graph.copy (expression, ((CoreParameterValue) expression).parameter);
		} else if (expression is CoreLoadValue) {
			var source = place (((CoreLoadValue) expression).source);
			if (source == null) {
				graph.unknown (expression);
			} else {
				graph.copy (expression, source);
			}
		} else if (expression is CoreCallValue) {
			var invoked = (CoreCallValue) expression;
			call (invoked.target, invoked.arguments, invoked.receiver);
			if (invoked.target == null || invoked.target.dispatch_kind != ClassDispatchKind.DIRECT) {
				graph.unknown (expression);
			} else {
				graph.copy (expression, invoked.target);
			}
		} else if (expression is CoreCCallValue) {
			var invoked = (CoreCCallValue) expression;
			foreach (var argument in invoked.arguments) {
				value (argument);
				opaque_type (argument.semantic_type);
			}
			opaque_type (expression.semantic_type);
		} else if (expression is CoreFunctionValueCall) {
			var invoked = (CoreFunctionValueCall) expression;
			value (invoked.callee);
			if (!indirect_calls.find (invoked)) {
				indirect_calls.add (invoked);
			}
			foreach (var argument in invoked.arguments) {
				value (argument);
			}
			graph.unknown (expression);
		} else if (expression is CoreObjectReceiverValue) {
			value (((CoreObjectReceiverValue) expression).reference);
		} else if (expression is CoreClassUpcast) {
			value (((CoreClassUpcast) expression).reference);
		} else if (expression is CoreOwnedObjectResultConstruction) {
			var construction = (CoreOwnedObjectResultConstruction) expression;
			call (construction.constructor, construction.arguments, null);
		} else if (expression is CoreOwnedBufferAllocate) {
			var allocated = (CoreOwnedBufferAllocate) expression;
			value (allocated.count);
			var failure = allocated.failure_call as CoreCallStatement;
			if (failure != null) {
				call (failure.target, failure.arguments, failure.receiver);
			}
			var foreign = allocated.failure_call as CoreCCallStatement;
			if (foreign != null) {
				foreach (var argument in foreign.arguments) {
					value (argument);
					opaque_type (argument.semantic_type);
				}
			}
		} else if (expression is CoreSlotsValue) {
			var query = (CoreSlotsValue) expression;
			place (query.store);
			if (query.operand != null) {
				value (query.operand);
			}
		} else if (expression is CoreSlotsTake) {
			var extracted = (CoreSlotsTake) expression;
			place (extracted.store);
			value (extracted.index);
		} else if (expression is CoreBinaryValue) {
			var binary = (CoreBinaryValue) expression;
			value (binary.left);
			value (binary.right);
		} else if (expression is CoreShortCircuitValue) {
			var binary = (CoreShortCircuitValue) expression;
			value (binary.left);
			value (binary.right);
		} else if (expression is CoreComparisonChain) {
			foreach (var operand in ((CoreComparisonChain) expression).operands) {
				value (operand);
			}
		} else if (expression is CoreIntegerConversionValue) {
			value (((CoreIntegerConversionValue) expression).operand);
		} else if (expression is CoreFloatConversionValue) {
			value (((CoreFloatConversionValue) expression).operand);
		} else if (expression is CoreNumericConversionValue) {
			value (((CoreNumericConversionValue) expression).operand);
		} else if (expression is CoreIntegerShiftValue) {
			var shifted = (CoreIntegerShiftValue) expression;
			value (shifted.operand);
			value (shifted.count);
		} else if (expression is CoreTextLengthValue) {
			value (((CoreTextLengthValue) expression).receiver);
		} else if (expression is CoreSliceFromArrayValue) {
			var slice = (CoreSliceFromArrayValue) expression;
			if (slice.start != null) {
				value (slice.start);
			}
			if (slice.count != null) {
				value (slice.count);
			}
		} else if (expression is CoreSliceLengthValue) {
			value (((CoreSliceLengthValue) expression).slice);
		} else if (expression is CorePrefixValue) {
			value (((CorePrefixValue) expression).operand);
		} else if (expression is CoreStructArgument) {
			producer (((CoreStructArgument) expression).producer);
		} else if (expression.semantic_type is FunctionValueType) {
			graph.unknown (expression);
		}
	}

	private void producer(CoreStructProducer source) {
		if (source is CoreStructAwait) {
			value (((CoreStructAwait) source).operation);
		} else if (source is CoreStructInvocationResult) {
			value (((CoreStructInvocationResult) source).invocation);
		} else if (source is CoreStructProjectionProducer) {
			producer (((CoreStructProjectionProducer) source).source);
		} else if (source is CoreStructCallResult) {
			var invoked = (CoreStructCallResult) source;
			call (invoked.target, invoked.arguments, invoked.receiver);
		}
	}

	private void statements(GenericArray<CoreStatement> items, CoreFunction function) {
		foreach (var statement in items) {
			if (statement is CoreValueStatement) {
				value (((CoreValueStatement) statement).value);
			} else if (statement is CoreTaskAwaitStatement) {
				value (((CoreTaskAwaitStatement) statement).operation);
			} else if (statement is CoreAsyncOperationStatement) {
				value (((CoreAsyncOperationStatement) statement).operation);
			} else if (statement is CoreAsyncDelay) {
				value (((CoreAsyncDelay) statement).ticks);
			} else if (statement is CoreInitialize) {
				var initialized = (CoreInitialize) statement;
				value (initialized.value);
				var destination = place (initialized.target);
				if (destination != null) {
					graph.copy (destination, initialized.value);
				}
			} else if (statement is CoreStore) {
				var stored = (CoreStore) statement;
				value (stored.value);
				var destination = place (stored.target);
				if (destination != null) {
					graph.copy (destination, stored.value);
				}
			} else if (statement is CoreArrayInitialize) {
				var initialized = (CoreArrayInitialize) statement;
				foreach (var element in initialized.elements) {
					value (element);
				}
				foreach (var entry in initialized.records) {
					statements (entry.initializers, function);
					if (entry.producer != null) {
						producer (entry.producer);
					}
				}
			} else if (statement is CoreOwnershipRearm) {
				var rearmed = (CoreOwnershipRearm) statement;
				if (rearmed.producer != null) {
					value (rearmed.producer);
				}
			} else if (statement is CoreOwnedFieldTransfer) {
				var transferred = (CoreOwnedFieldTransfer) statement;
				if (transferred.producer != null) {
					value (transferred.producer);
				}
			} else if (statement is CoreStructInitialize) {
				var initialized = (CoreStructInitialize) statement;
				if (initialized.producer != null) {
					producer (initialized.producer);
				}
				statements (initialized.initializers, function);
			} else if (statement is CoreStructResultStore) {
				producer (((CoreStructResultStore) statement).producer);
			} else if (statement is CoreStructReturn) {
				producer (((CoreStructReturn) statement).producer);
			} else if (statement is CoreConstructorObjectInitialization) {
				var construction = (CoreConstructorObjectInitialization) statement;
				call (construction.constructor, construction.arguments, null);
			} else if (statement is CoreReturn) {
				var returned = ((CoreReturn) statement).value;
				if (returned != null) {
					value (returned);
					graph.copy (function, returned);
				}
			} else if (statement is CoreOwnershipReturn) {
				var returned = ((CoreOwnershipReturn) statement).producer;
				if (returned != null) {
					value (returned);
				}
			} else if (statement is CoreCallStatement) {
				var invoked = (CoreCallStatement) statement;
				call (invoked.target, invoked.arguments, invoked.receiver);
			} else if (statement is CoreCCallStatement) {
				var invoked = (CoreCCallStatement) statement;
				foreach (var argument in invoked.arguments) {
					value (argument);
					opaque_type (argument.semantic_type);
				}
			} else if (statement is CoreWithScope) {
				var scoped = (CoreWithScope) statement;
				call_context.enter (scoped.source.semantic_type);
				block (scoped.body, function);
				call_context.leave ();
			} else if (statement is CoreScope) {
				block (((CoreScope) statement).body, function);
			} else if (statement is CoreIf) {
				var branch = (CoreIf) statement;
				value (branch.condition);
				block (branch.then_block, function);
				if (branch.else_block != null) {
					block (branch.else_block, function);
				}
			} else if (statement is CoreWhile) {
				var loop = (CoreWhile) statement;
				value (loop.condition);
				block (loop.body, function);
				if (loop.step != null) {
					block (loop.step, function);
				}
			} else if (statement is CoreTry) {
				var guarded = (CoreTry) statement;
				block (guarded.body, function);
				foreach (var handler in guarded.catches) {
					block (handler.body, function);
				}
			}
		}
	}

	private void block(CoreBlock body, CoreFunction function) {
		statements (body.statements, function);
	}

	internal Astra.Code.CodeOriginFrontier? effect_frontier (Object expression, GenericArray<Object> formals) {
		if (!(expression is CoreValue)) {
			return null;
		}
		value ((CoreValue) expression);
		return graph.frontier (expression, formals);
	}
	internal void add_effect_calls(Astra.Code.CodeEffectAnalysis effects) {
		foreach (var site in effect_calls) {
			var arguments = new GenericArray<Object> ();
			bool protected_call = site.protected_call;
			foreach (var argument in site.arguments) {
				arguments.add (argument);
				var loan = argument as CoreSlotsValue;
				protected_call |= loan != null && loan.action == OwnerSlotsAction.BORROW &&
					(site.target.kind == CallableKind.METHOD || loan.iteration != null);
			}
			effects.add_call (site.scope, site.target, arguments, protected_call);
		}
	}

	internal GenericArray<CoreFunction>? targets(CoreValue expression) {
		value (expression);
		var found = graph.targets (expression);
		if (found == null) {
			return null;
		}
		var result = new GenericArray<CoreFunction> ();
		foreach (var candidate in found) {
			var function = candidate as CoreFunction;
			if (function == null) {
				return null;
			}
			result.add (function);
		}
		return result;
	}

}
}
