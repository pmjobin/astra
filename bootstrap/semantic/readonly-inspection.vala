// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Code;

namespace Astra.Semantic {
// Transitive receiver/element protection for scoped inspection loans. Calls
// may observe copied values but cannot transport an alias to mutable storage.
internal class ReadonlyInspection : Object {
	private GenericArray<FunctionSymbol> requests = new GenericArray<FunctionSymbol> ();
	private HashTable<FunctionSymbol, CheckedFunction> definitions = new HashTable<FunctionSymbol, CheckedFunction> (direct_hash, direct_equal);
	private HashTable<FunctionSymbol, bool> visited = new HashTable<FunctionSymbol, bool> (direct_hash, direct_equal);
	private Diagnostic? diagnostic;
	private CopyabilityFields? fields;
	private ReadonlyCodeOrigins? code_origins;
	private CodeEffectAnalysis? inference;
	private FunctionSymbol? inference_scope;
	private CodeEffectSummary? inference_result;
	internal static CodeEffectAnalysis infer_effects(CheckedProgram program, CopyabilityFields fields) {
		var origins = new ReadonlyCodeOrigins (program);
		var effects = create_effect_analysis (origins);
		var definitions = new GenericArray<CheckedFunction> ();
		foreach (var function in program.all_definitions ()) {
			definitions.add (function);
		}
		foreach (var property in program.properties) {
			if (!definitions.find (property.getter)) {
				definitions.add (property.getter);
			}
			if (property.setter != null && !definitions.find (property.setter)) {
				definitions.add (property.setter);
			}
		}
		foreach (var function in definitions) {
			var parameters = new GenericArray<Object> ();
			var formals = new GenericArray<Object> ();
			foreach (var parameter in function.symbol.parameters) {
				parameters.add (parameter);
				var signature = parameter.semantic_type as FunctionValueType;
				if (signature == null) {
					continue;
				}
				bool first_order = true;
				foreach (var type in signature.parameter_types) {
					first_order &= !(type is FunctionValueType);
				}
				if (first_order) {
					formals.add (parameter);
				}
			}
			var positions = new GenericArray<int> ();
			for (int p = 0; p < function.symbol.parameters.length; p++) {
				if (!(function.symbol.parameters[p].semantic_type is FunctionValueType)) {
					continue;
				}
				bool record_leaf = false;
				if (!record_leaf) {
					positions.add (p);
				}
			}
			var declaration = function.native_declaration;
			effects.add_function (function.symbol, parameters, formals,
				declaration == null ? null : Astra.Code.CodeInputSet.decode (declaration.identity.scoped_readonly,
					declaration.identity.readonly_inputs, (int) parameters.length, positions),
				declaration == null ? null : Astra.Code.CodeInputSet.decode (true,
					declaration.identity.callback_inputs, (int) parameters.length, positions));
		}
		origins.add_effect_calls (effects);
		effects.infer_readonly ((function, result) => {
				var checker = new ReadonlyInspection ();
				checker.fields = (type) => fields (type);
				foreach (var definition in definitions) {
					checker.definitions.insert (definition.symbol, definition);
				}
				checker.inference = effects;
				checker.inference_scope = (FunctionSymbol) function;
				checker.inference_result = result;
				checker.inspect ((FunctionSymbol) function, ((FunctionSymbol) function).span);
				checker.fields = null;
				return checker.diagnostic == null;
			});
		effects.infer_requirements ();
		return effects;
	}

	// Vala shares closure storage within one method. Keep this long-lived
	// frontier separate from probes that capture the analysis or its owner.
	private static CodeEffectAnalysis create_effect_analysis(ReadonlyCodeOrigins origins) {
		return new CodeEffectAnalysis ((value, formals) => origins.effect_frontier (value, formals));
	}

	private static GenericArray<Object> objects(GenericArray<CheckedExpression> values) {
		var result = new GenericArray<Object> ();
		foreach (var value in values) {
			result.add (value);
		}
		return result;
	}

	public void require(FunctionSymbol function) {
		if (!requests.find (function)) {
			requests.add (function);
		}
	}

	public Diagnostic? validate(CheckedProgram program, owned CopyabilityFields fields) {
		this.fields = (owned) fields;
		if (requests.length != 0) {
			code_origins = new ReadonlyCodeOrigins (program);
		}
		foreach (var function in program.all_definitions ()) {
			definitions.insert (function.symbol, function);
		}
		foreach (var property in program.properties) {
			definitions.insert (property.getter.symbol, property.getter);
			if (property.setter != null) {
				definitions.insert (property.setter.symbol, property.setter);
			}
		}
		foreach (var function in requests) {
			inspect (function, function.span);
		}
		bool native_callbacks = false;
		foreach (var function in definitions.get_values ()) {
			var declaration = function.native_declaration;
			native_callbacks |= declaration != null && (declaration.identity.readonly_inputs != "" || declaration.identity.callback_inputs != "");
		}
		if (diagnostic == null && native_callbacks && this.fields != null) {
			var effects = infer_effects (program, this.fields);
			foreach (var function in definitions.get_values ()) {
				var required = effects.required_summary (function.symbol);
				if (required == null || !required.eligible) {
					diagnostic = new Diagnostic (function.span, "native callback inputs require independently proved readonly code");
					break;
				}
			}
		}
		// The field resolver may capture the analyzer that owns this checker.
		// Keep it only while validation is active, including on rejection.
		this.fields = null;
		code_origins = null;
		return diagnostic;
	}

	private void reject(SourceSpan span, string reason) {
		if (diagnostic == null) {
			diagnostic = new Diagnostic (span, "readonly scoped inspector " + reason);
		}
	}

	internal static bool copied_result(SemanticType type, CopyabilityFields fields) {
		if (type.kind == TypeKind.VOID || FunctionValueType.scalar (type)) {
			return true;
		}
		if (!type.is_struct_storage ()) {
			return false;
		}
		try {
			foreach (var leaf in StructLeafOrder.enumerate (type, fields)) {
				if (!FunctionValueType.scalar (leaf.semantic_type)) {
					return false;
				}
			}
		} catch (StructLeafError error) {
			return false;
		}
		return true;
	}

	private bool copied(SemanticType type) {
		if (type is FunctionValueType || FunctionValueType.scalar (type) || type is StringType) {
			return true;
		}
		if (!type.is_struct_storage () || fields == null) {
			return false;
		}
		try {
			foreach (var leaf in StructLeafOrder.enumerate (type, fields)) {
				if (!FunctionValueType.scalar (leaf.semantic_type)) {
					return false;
				}
			}
		} catch (StructLeafError error) {
			return false;
		}
		return true;
	}

	private void inspect(FunctionSymbol function, SourceSpan span) {
		if (inference != null && function is LifecycleSymbol) {
			reject (span, "cannot perform lifecycle work while inspecting");
			return;
		}
		var definition = definitions.lookup (function);
		var getter = function as PropertyGetterSymbol;
		if (definition == null || function.dispatch_kind != ClassDispatchKind.DIRECT || function.async_body != null || function.throws_type != null || function is GenericFunctionSymbol || (getter != null && (getter.property_symbol.is_lazy || getter.property_symbol.is_owned_lazy))) {
			reject (span, "requires an exact synchronous nonthrowing direct definition without lazy mutation");
			return;
		}
		if (function.result_contract == ResultOwnershipContract.OWNED_TRANSFER || function.struct_result_contract != null && function.struct_result_contract.mode == StructValueMode.MOVE_VALUE) {
			reject (span, "cannot acquire an owning result");
			return;
		}
		foreach (var parameter in function.parameters) {
			if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || parameter.struct_value_contract != null && parameter.struct_value_contract.mode == StructValueMode.MOVE_VALUE) {
				reject (span, "cannot consume an owner while inspecting");
				return;
			}
		}
		if (function.name_span.file.native_interface) {
			if (definition.native_declaration == null || !definition.native_declaration.identity.scoped_readonly) {
				reject (span, "requires the imported declaration's original readonly effect contract");
			}
			return;
		}
		if (visited.contains (function)) {
			return;
		}
		visited.insert (function, true);
		block (definition.body);
	}

	private void call(DirectCallableSymbol? target, CheckedExpression? receiver, GenericArray<CheckedExpression> arguments, SourceSpan span) {
		if (receiver != null) {
			value (receiver);
		}
		foreach (var argument in arguments) {
			value (argument);
		}
		if (target is FunctionSymbol) {
			if (inference == null) {
				inspect ((FunctionSymbol) target, span);
			} else if (!inference.call (target, objects (arguments), inference_scope, inference_result)) {
				reject (span, "unproved conditional direct call effect");
			}
		} else if (target is CFunctionSymbol) {
			if (target.return_type.kind != TypeKind.VOID && !copied (target.return_type)) {
				reject (span, "cannot acquire foreign pointer or handle results");
			}
			foreach (var argument in arguments) {
				if (!copied (argument.semantic_type)) {
					reject (argument.span, "cannot expose mutable C pointers, handles or buffers");
				}
			}
		} else {
			reject (span, "requires an exact native or scalar/text foreign call");
		}
	}

	private void place(CheckedPlace storage) {
		if (storage is CheckedLocalPlace) {
			return;
		}
		if (storage is CheckedSliceElementPlace) {
			var element = (CheckedSliceElementPlace) storage;
			value (element.slice);
			value (element.index);
			return;
		}
		if (storage is CheckedFieldPlace) {
			place (((CheckedFieldPlace) storage).aggregate);
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
		reject (storage.span, "requires direct object or local reads");
	}

	private void value(CheckedExpression expression) {
		if (diagnostic != null) {
			return;
		}
		if (inference != null && expression is CheckedFunctionAddress) {
			return;
		}
		if (expression is CheckedLengthExpression) {
			var length = (CheckedLengthExpression) expression;
			if (length.slice != null) {
				value (length.slice);
			}
			return;
		}
		if (expression is CheckedStructProjectionValue) {
			producer (((CheckedStructProjectionValue) expression).source);
			return;
		}
		if (expression is CheckedIntegerExpression || expression is CheckedFloatExpression || expression is CheckedBooleanExpression || expression is CheckedNullPointerExpression || expression is CheckedTextExpression || expression is CheckedParameterReferenceExpression || expression is CheckedLocalReferenceExpression || expression is CheckedThisExpression || expression is CheckedConstantReference) {
			return;
		}
		if (expression is CheckedLoadExpression) {
			place (((CheckedLoadExpression) expression).source);
			return;
		}
		if (expression is CheckedOwnedFieldBorrow) {
			place (((CheckedOwnedFieldBorrow) expression).source);
			return;
		}
		if (expression is CheckedObjectReceiverExpression) {
			value (((CheckedObjectReceiverExpression) expression).reference);
			return;
		}
		if (expression is CheckedClassUpcast) {
			value (((CheckedClassUpcast) expression).reference);
			return;
		}
		if (expression is CheckedSlotsValue) {
			var query = (CheckedSlotsValue) expression;
			if (inference != null && query.action == OwnerSlotsAction.BORROW) {
				place (query.store);
				if (query.operand != null) {
					value (query.operand);
				}
				return;
			}
			if (query.action != OwnerSlotsAction.LENGTH && query.action != OwnerSlotsAction.CAPACITY || query.operand != null) {
				reject (expression.span, "cannot mutate or expose collection element storage");
				return;
			}
			place (query.store);
			return;
		}
		if (expression is CheckedTextLengthExpression) {
			value (((CheckedTextLengthExpression) expression).receiver);
			return;
		}
		if (expression is CheckedPrefixExpression) {
			value (((CheckedPrefixExpression) expression).operand);
			return;
		}
		if (expression is CheckedBinaryExpression) {
			value (((CheckedBinaryExpression) expression).left);
			value (((CheckedBinaryExpression) expression).right);
			return;
		}
		if (expression is CheckedShortCircuitExpression) {
			value (((CheckedShortCircuitExpression) expression).left);
			value (((CheckedShortCircuitExpression) expression).right);
			return;
		}
		if (expression is CheckedComparisonChain) {
			foreach (var operand in ((CheckedComparisonChain) expression).operands) {
				value (operand);
			}
			return;
		}
		if (expression is CheckedIntegerConversionExpression) {
			value (((CheckedIntegerConversionExpression) expression).operand);
			return;
		}
		if (expression is CheckedFloatConversionExpression) {
			value (((CheckedFloatConversionExpression) expression).operand);
			return;
		}
		if (expression is CheckedNumericConversionExpression) {
			value (((CheckedNumericConversionExpression) expression).operand);
			return;
		}
		if (expression is CheckedStructArgument) {
			producer (((CheckedStructArgument) expression).producer);
			return;
		}
		if (expression is CheckedFunctionValueCall) {
			var invoked = (CheckedFunctionValueCall) expression;
			var signature = (FunctionValueType) invoked.callee.semantic_type;
			bool requires_target = false;
			foreach (var parameter in signature.parameter_types) {
				requires_target |= !copied (parameter) || parameter is FunctionValueType || parameter is StringType;
			}
			if (requires_target) {
				if (inference != null) {
					if (!inference.code (invoked.callee, inference_scope, inference_result, objects (invoked.arguments))) {
						reject (expression.span, "unproved declarative callback origin or invocation context");
					}
					value (invoked.callee);
					foreach (var argument in invoked.arguments) {
						value (argument);
					}
					return;
				}
				var targets = code_origins == null ? null : code_origins.targets (invoked.callee);
				if (targets == null) {
					reject (expression.span, "cannot prove the actual targets of a borrowed observation callback");
					return;
				}
				foreach (var target in targets) {
					inspect (target, expression.span);
				}
			}
			value (invoked.callee);
			foreach (var argument in invoked.arguments) {
				value (argument);
			}
			return;
		}
		if (expression is CheckedCallExpression) {
			var invoked = (CheckedCallExpression) expression;
			call (invoked.target, invoked.receiver, invoked.arguments, invoked.span);
			return;
		}
		reject (expression.span, "requires scalar/text observations and bounded native calls");
	}

	private void producer(CheckedStructProducer source) {
		if (source is CheckedStructInvocationResult) {
			value (((CheckedStructInvocationResult) source).invocation);
			return;
		}
		if (source.contract.mode == StructValueMode.BORROW_VALUE) {
			if (source is CheckedStructBorrowSnapshot) {
				place (((CheckedStructBorrowSnapshot) source).source);
				return;
			}
			var invoked = source as CheckedStructCallResult;
			if (invoked != null && invoked.target is PropertyGetterSymbol && invoked.target.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
				call (invoked.target, invoked.receiver, invoked.arguments, source.span);
				return;
			}
			reject (source.span, "borrowed record observation requires its exact pure receiver getter");
			return;
		}
		if (source.contract.mode != StructValueMode.COPY_VALUE || !copied (source.semantic_type)) {
			reject (source.span, "record observations require copied fields without mutable aliases");
			return;
		}
		if (source is CheckedStructProjectionProducer) {
			producer (((CheckedStructProjectionProducer) source).source);
			return;
		}
		if (source is CheckedStructSnapshot) {
			place (((CheckedStructSnapshot) source).source);
			return;
		}
		if (source is CheckedStructCallResult) {
			var invoked = (CheckedStructCallResult) source;
			call (invoked.target, invoked.receiver, invoked.arguments, source.span);
			return;
		}
		reject (source.span, "record observation requires a bounded snapshot or native call");
	}

	private bool writable(CheckedPlace place) {
		while (place is CheckedFieldPlace) {
			place = ((CheckedFieldPlace) place).aggregate;
		}
		var local = place as CheckedLocalPlace;
		if (local == null || !copied (local.semantic_type)) {
			return false;
		}
		var parameter = local.local.incoming_parameter;
		return parameter == null || parameter.struct_value_contract == null || parameter.struct_value_contract.mode != StructValueMode.BORROW_VALUE;
	}

	private void initializers(GenericArray<CheckedFieldInitializer> fields) {
		foreach (var field in fields) {
			if (field.initializer != null) {
				initializers (field.initializer.fields);
			} else if (field.producer != null) {
				producer (field.producer);
			} else {
				value (field.expression);
			}
		}
	}

	private void block(CheckedBlockStatement body) {
		foreach (var statement in body.statements) {
			if (diagnostic != null) {
				return;
			}
			if (statement is CheckedLocalDeclaration) {
				var local = (CheckedLocalDeclaration) statement;
				if (!copied (local.local.semantic_type) || local is CheckedOwnedLocalDeclaration) {
					reject (local.span, "permits only copied scalar/text locals");
				}
				value (local.initializer);
			} else if (statement is CheckedAssignment) {
				var assignment = (CheckedAssignment) statement;
				if (!copied (assignment.target.semantic_type)) {
					reject (assignment.span, "cannot mutate ownership or object storage");
				}
				value (assignment.expression);
			} else if (statement is CheckedStore) {
				var store = (CheckedStore) statement;
				if (!writable (store.target)) {
					reject (store.span, "cannot write object fields or indirect storage");
				}
				value (store.value);
			} else if (statement is CheckedStructLocalDeclaration) {
				var local = (CheckedStructLocalDeclaration) statement;
				if (!copied (local.local.semantic_type) || local.local.is_record_owner) {
					reject (local.span, "cannot acquire an owning record local");
					return;
				}
				initializers (local.initializers);
			} else if (statement is CheckedStructCopy) {
				var copy = (CheckedStructCopy) statement;
				if (!writable (copy.destination) || !copied (copy.semantic_type)) {
					reject (copy.span, "cannot change observed record storage");
					return;
				}
				place (copy.source);
			} else if (statement is CheckedReturnStatement) {
				var returned = ((CheckedReturnStatement) statement).expression;
				if (returned != null) {
					value (returned);
				}
			} else if (statement is CheckedStructReturn) {
				producer (((CheckedStructReturn) statement).producer);
			} else if (statement is CheckedStructResultStore) {
				var stored = (CheckedStructResultStore) statement;
				if (!(stored.destination is CheckedLocalPlace)) {
					reject (stored.span, "cannot write an observed record field");
				}
				producer (stored.producer);
			} else if (statement is CheckedBlockStatement) {
				block ((CheckedBlockStatement) statement);
			} else if (statement is CheckedIf) {
				var branch = (CheckedIf) statement;
				value (branch.condition);
				block (branch.then_body);
				if (branch.else_body != null) {
					block (branch.else_body);
				}
			} else if (statement is CheckedWhile) {
				var loop = (CheckedWhile) statement;
				value (loop.condition);
				block (loop.body);
				if (loop.step != null) {
					block (loop.step);
				}
			} else if (statement is CheckedCallStatement) {
				var invoked = (CheckedCallStatement) statement;
				call (invoked.target, invoked.receiver, invoked.arguments, invoked.span);
			} else if (!(statement is CheckedBreak || statement is CheckedContinue)) {
				reject (statement.span, "cannot mutate ownership or object storage");
			}
		}
	}

}
}
