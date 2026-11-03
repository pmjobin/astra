// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
internal class ReadonlyEffectCall : Object {
	internal FunctionSymbol scope;
	internal FunctionSymbol target;
	internal GenericArray<CheckedExpression> arguments;
	internal bool protected_call;
	internal ReadonlyEffectCall (FunctionSymbol scope, FunctionSymbol target, GenericArray<CheckedExpression> arguments, bool protected_call) {
		this.scope = scope;
		this.target = target;
		this.arguments = arguments;
		this.protected_call = protected_call;
	}

}
// Reconstruct code-value flow from checked definitions. The analysis is
// temporary and does not substitute a function name for an effect proof.
internal class ReadonlyCodeOrigins : Object {
	private Astra.Code.CodeOrigins graph = new Astra.Code.CodeOrigins ();
	private ReadonlyCallContext call_context = new ReadonlyCallContext ();
	private GenericArray<CheckedFunctionValueCall> indirect_calls = new GenericArray<CheckedFunctionValueCall> ();
	private GenericArray<ReadonlyEffectCall> effect_calls = new GenericArray<ReadonlyEffectCall> ();
	private FunctionSymbol? current_scope;
	internal ReadonlyCodeOrigins (CheckedProgram program) {
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
			definition (function);
		}
		foreach (var property in program.properties) {
			definition (property.getter);
			if (property.setter != null) {
				definition (property.setter);
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
					call (candidate as FunctionSymbol, invoked.arguments, null);
				}
			}
		} while (prior != graph.revision);
	}

	private void definition(CheckedFunction function) {
		current_scope = function.symbol;
		foreach (var parameter in function.symbol.parameters) {
			graph.parameter (parameter);
		}
		foreach (var local in function.locals) {
			if (local.incoming_parameter != null) {
				graph.copy (local, local.incoming_parameter);
			}
		}
		if (function.body == null || function.symbol.name_span.file.native_interface) {
			graph.unknown (function.symbol);
			foreach (var parameter in function.symbol.parameters) {
				opaque_type (parameter.semantic_type);
			}
			opaque_type (function.symbol.return_type);
			return;
		}
		block (function.body, function.symbol);
	}

	private void opaque_type(SemanticType type) {
		if (type.kind != TypeKind.VOID && !FunctionValueType.scalar (type) && !(type is HandleType) && !(type is StringType)) {
			graph.escape_storage ();
		}
	}

	private Object? place(CheckedPlace storage) {
		if (storage is CheckedLocalPlace) {
			return ((CheckedLocalPlace) storage).local;
		}
		if (storage is CheckedFieldPlace) {
			return ((CheckedFieldPlace) storage).field;
		}
		if (storage is CheckedReceiverFieldPlace) {
			return ((CheckedReceiverFieldPlace) storage).field;
		}
		if (storage is CheckedObjectFieldPlace) {
			value (((CheckedObjectFieldPlace) storage).reference);
			return ((CheckedObjectFieldPlace) storage).field;
		}
		if (storage is CheckedArrayElementPlace) {
			value (((CheckedArrayElementPlace) storage).index);
		} else if (storage is CheckedSliceElementPlace) {
			var indexed = (CheckedSliceElementPlace) storage;
			value (indexed.slice);
			value (indexed.index);
		}
		return null;
	}

	private void call(DirectCallableSymbol? target, GenericArray<CheckedExpression> arguments, CheckedExpression? receiver) {
		bool protected_call = receiver != null && call_context.overlaps (receiver.semantic_type);
		foreach (var argument in arguments) {
			protected_call |= call_context.overlaps (argument.semantic_type);
		}
		if (current_scope != null && target is FunctionSymbol) {
			effect_calls.add (new ReadonlyEffectCall (current_scope, (FunctionSymbol) target, arguments, protected_call));
		}
		if (target is CFunctionSymbol || target is FunctionSymbol && ((FunctionSymbol) target).name_span.file.native_interface) {
			foreach (var argument in arguments) {
				opaque_type (argument.semantic_type);
			}
			if (target != null) {
				opaque_type (target.return_type);
			}
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

	private void value(CheckedExpression expression) {
		if (expression is CheckedOwnedArgument) {
			var owned = (CheckedOwnedArgument) expression;
			if (owned.producer != null) {
				value (owned.producer);
			}
		} else if (expression is CheckedTaskAwait) {
			value (((CheckedTaskAwait) expression).child);
		} else if (expression is CheckedAsyncOperation) {
			var operation = (CheckedAsyncOperation) expression;
			if (operation.executor != null) {
				value (operation.executor);
			}
			if (operation.task != null) {
				value (operation.task);
			}
			if (operation.argument != null) {
				value (operation.argument);
			}
		} else if (expression is CheckedTaskCreate) {
			var created = (CheckedTaskCreate) expression;
			call (created.target, created.arguments, null);
		} else if (expression is CheckedFunctionAddress) {
			var target = ((CheckedFunctionAddress) expression).target;
			if (target == null) {
				graph.unknown (expression);
			} else {
				graph.address (expression, target);
			}
		} else if (expression is CheckedParameterReferenceExpression) {
			graph.copy (expression, ((CheckedParameterReferenceExpression) expression).parameter);
		} else if (expression is CheckedLocalReferenceExpression) {
			graph.copy (expression, ((CheckedLocalReferenceExpression) expression).local);
		} else if (expression is CheckedFieldReferenceExpression) {
			graph.copy (expression, ((CheckedFieldReferenceExpression) expression).field);
		} else if (expression is CheckedLoadExpression) {
			var source = place (((CheckedLoadExpression) expression).source);
			if (source != null) {
				graph.copy (expression, source);
			} else {
				graph.unknown (expression);
			}
		} else if (expression is CheckedCallExpression) {
			var invoked = (CheckedCallExpression) expression;
			call (invoked.target, invoked.arguments, invoked.receiver);
			var target = invoked.target as FunctionSymbol;
			if (target == null || target.dispatch_kind != ClassDispatchKind.DIRECT) {
				graph.unknown (expression);
			} else {
				graph.copy (expression, target);
			}
		} else if (expression is CheckedObjectReceiverExpression) {
			value (((CheckedObjectReceiverExpression) expression).reference);
		} else if (expression is CheckedClassUpcast) {
			value (((CheckedClassUpcast) expression).reference);
		} else if (expression is CheckedOwnedObjectResultConstruction) {
			var construction = (CheckedOwnedObjectResultConstruction) expression;
			call (construction.constructor, construction.arguments, null);
		} else if (expression is CheckedFunctionValueCall) {
			var invoked = (CheckedFunctionValueCall) expression;
			if (!indirect_calls.find (invoked)) {
				indirect_calls.add (invoked);
			}
			value (invoked.callee);
			foreach (var argument in invoked.arguments) {
				value (argument);
			}
			graph.unknown (expression);
		} else if (expression is CheckedOwnedBufferAllocate) {
			var allocated = (CheckedOwnedBufferAllocate) expression;
			value (allocated.count);
			if (allocated.failure_call != null) {
				call (allocated.failure_call.target, allocated.failure_call.arguments, allocated.failure_call.receiver);
			}
		} else if (expression is CheckedSlotsValue) {
			var query = (CheckedSlotsValue) expression;
			place (query.store);
			if (query.operand != null) {
				value (query.operand);
			}
		} else if (expression is CheckedSlotsTake) {
			var extracted = (CheckedSlotsTake) expression;
			place (extracted.store);
			value (extracted.index);
		} else if (expression is CheckedBinaryExpression) {
			var binary = (CheckedBinaryExpression) expression;
			value (binary.left);
			value (binary.right);
		} else if (expression is CheckedShortCircuitExpression) {
			var binary = (CheckedShortCircuitExpression) expression;
			value (binary.left);
			value (binary.right);
		} else if (expression is CheckedComparisonChain) {
			foreach (var operand in ((CheckedComparisonChain) expression).operands) {
				value (operand);
			}
		} else if (expression is CheckedIntegerConversionExpression) {
			value (((CheckedIntegerConversionExpression) expression).operand);
		} else if (expression is CheckedFloatConversionExpression) {
			value (((CheckedFloatConversionExpression) expression).operand);
		} else if (expression is CheckedNumericConversionExpression) {
			value (((CheckedNumericConversionExpression) expression).operand);
		} else if (expression is CheckedIntegerShiftExpression) {
			var shifted = (CheckedIntegerShiftExpression) expression;
			value (shifted.operand);
			value (shifted.count);
		} else if (expression is CheckedTextLengthExpression) {
			value (((CheckedTextLengthExpression) expression).receiver);
		} else if (expression is CheckedSliceFromArrayExpression) {
			var slice = (CheckedSliceFromArrayExpression) expression;
			if (slice.start != null) {
				value (slice.start);
			}
			if (slice.count != null) {
				value (slice.count);
			}
		} else if (expression is CheckedLengthExpression) {
			var length = (CheckedLengthExpression) expression;
			if (length.slice != null) {
				value (length.slice);
			}
		} else if (expression is CheckedPrefixExpression) {
			value (((CheckedPrefixExpression) expression).operand);
		} else if (expression is CheckedStructArgument) {
			producer (((CheckedStructArgument) expression).producer);
		} else if (expression.semantic_type is FunctionValueType) {
			graph.unknown (expression);
		}
	}

	private void producer(CheckedStructProducer source) {
		if (source is CheckedStructAwait) {
			value (((CheckedStructAwait) source).operation);
		} else if (source is CheckedStructInvocationResult) {
			value (((CheckedStructInvocationResult) source).invocation);
		} else if (source is CheckedStructProjectionProducer) {
			producer (((CheckedStructProjectionProducer) source).source);
		} else if (source is CheckedStructCallResult) {
			var invoked = (CheckedStructCallResult) source;
			call (invoked.target, invoked.arguments, invoked.receiver);
		}
	}

	private void initializers(GenericArray<CheckedFieldInitializer> fields) {
		foreach (var field in fields) {
			if (field.initializer != null) {
				initializers (field.initializer.fields);
			} else if (field.producer != null) {
				producer (field.producer);
			} else {
				value (field.expression);
				graph.copy (field.field, field.expression);
			}
		}
	}

	private void block(CheckedBlockStatement body, FunctionSymbol function) {
		foreach (var statement in body.statements) {
			if (statement is CheckedValueStatement) {
				value (((CheckedValueStatement) statement).value);
			} else if (statement is CheckedTaskAwaitStatement) {
				value (((CheckedTaskAwaitStatement) statement).operation);
			} else if (statement is CheckedAsyncOperationStatement) {
				value (((CheckedAsyncOperationStatement) statement).operation);
			} else if (statement is CheckedAsyncDelay) {
				value (((CheckedAsyncDelay) statement).ticks);
			} else if (statement is CheckedConstructorObjectInitialization) {
				var construction = (CheckedConstructorObjectInitialization) statement;
				call (construction.constructor, construction.arguments, null);
			} else if (statement is CheckedObjectConstruction) {
				initializers (((CheckedObjectConstruction) statement).initializers);
			} else if (statement is CheckedFieldInitialize) {
				var stored = (CheckedFieldInitialize) statement;
				value (stored.value);
				graph.copy (stored.target.field, stored.value);
			} else if (statement is CheckedLocalDeclaration) {
				var local = (CheckedLocalDeclaration) statement;
				value (local.initializer);
				graph.copy (local.local, local.initializer);
			} else if (statement is CheckedAssignment) {
				var assigned = (CheckedAssignment) statement;
				value (assigned.expression);
				graph.copy (assigned.target, assigned.expression);
			} else if (statement is CheckedStore) {
				var stored = (CheckedStore) statement;
				value (stored.value);
				var destination = place (stored.target);
				if (destination != null) {
					graph.copy (destination, stored.value);
				}
			} else if (statement is CheckedArrayLocalDeclaration) {
				var initialized = (CheckedArrayLocalDeclaration) statement;
				foreach (var element in initialized.elements) {
					value (element);
				}
				foreach (var entry in initialized.records) {
					if (entry.initializer != null) {
						initializers (entry.initializer.fields);
					}
					if (entry.producer != null) {
						producer (entry.producer);
					}
				}
			} else if (statement is CheckedOwnedBufferReplace) {
				value (((CheckedOwnedBufferReplace) statement).incoming);
			} else if (statement is CheckedStructLocalDeclaration) {
				initializers (((CheckedStructLocalDeclaration) statement).initializers);
			} else if (statement is CheckedFieldAssignment) {
				var assigned = (CheckedFieldAssignment) statement;
				value (assigned.expression);
				graph.copy (assigned.field, assigned.expression);
			} else if (statement is CheckedReturnStatement) {
				var returned = ((CheckedReturnStatement) statement).expression;
				if (returned != null) {
					value (returned);
					graph.copy (function, returned);
				}
			} else if (statement is CheckedStructReturn) {
				producer (((CheckedStructReturn) statement).producer);
			} else if (statement is CheckedStructResultStore) {
				producer (((CheckedStructResultStore) statement).producer);
			} else if (statement is CheckedCallStatement) {
				var invoked = (CheckedCallStatement) statement;
				call (invoked.target, invoked.arguments, invoked.receiver);
			} else if (statement is CheckedWithScope) {
				var scoped = (CheckedWithScope) statement;
				call_context.enter (scoped.source.semantic_type);
				block (scoped, function);
				call_context.leave ();
			} else if (statement is CheckedBlockStatement) {
				block ((CheckedBlockStatement) statement, function);
			} else if (statement is CheckedIf) {
				var branch = (CheckedIf) statement;
				value (branch.condition);
				block (branch.then_body, function);
				if (branch.else_body != null) {
					block (branch.else_body, function);
				}
			} else if (statement is CheckedTry) {
				var attempt = (CheckedTry) statement;
				block (attempt.body, function);
				foreach (var handler in attempt.catches) {
					block (handler.body, function);
				}
			} else if (statement is CheckedWhile) {
				var loop = (CheckedWhile) statement;
				value (loop.condition);
				block (loop.body, function);
				if (loop.step != null) {
					block (loop.step, function);
				}
			}
		}
	}

	internal Astra.Code.CodeOriginFrontier? effect_frontier (Object expression, GenericArray<Object> formals) {
		if (!(expression is CheckedExpression)) {
			return null;
		}
		value ((CheckedExpression) expression);
		return graph.frontier (expression, formals);
	}
	internal void add_effect_calls(Astra.Code.CodeEffectAnalysis effects) {
		foreach (var site in effect_calls) {
			var arguments = new GenericArray<Object> ();
			bool protected_call = site.protected_call;
			foreach (var argument in site.arguments) {
				arguments.add (argument);
				var loan = argument as CheckedSlotsValue;
				protected_call |= loan != null && loan.action == OwnerSlotsAction.BORROW &&
					(site.target.kind == CallableKind.METHOD || loan.iteration != null);
			}
			effects.add_call (site.scope, site.target, arguments, protected_call);
		}
	}

	internal GenericArray<FunctionSymbol>? targets(CheckedExpression expression) {
		value (expression);
		var found = graph.targets (expression);
		if (found == null) {
			return null;
		}
		var result = new GenericArray<FunctionSymbol> ();
		foreach (var candidate in found) {
			var function = candidate as FunctionSymbol;
			if (function == null) {
				return null;
			}
			result.add (function);
		}
		return result;
	}

}
}
