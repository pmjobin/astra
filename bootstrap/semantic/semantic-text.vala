// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Text;

namespace Astra.Semantic {
public class CheckedUtf8FactoryExpression : CheckedExpression {
	public ParameterSymbol input { get; private set; }
	public bool validates { get; private set; }
	internal CheckedUtf8FactoryExpression (SourceSpan span, SemanticType type, ParameterSymbol input, bool validates) {
		base (span, type);
		this.input = input;
		this.validates = validates;
	}
}
public class Utf8FactoryContracts : Object {
	private static CheckedFunction? definition(CheckedProgram program, FunctionSymbol? symbol) {
		foreach (var function in program.functions) {
			if (function.symbol == symbol) {
				return function;
			}
		}
		return null;
	}
	private static bool snapshot_constructor(CheckedProgram program, ClassSymbol owner) {
		var constructor = definition (program, owner.constructor);
		if (constructor == null || constructor.symbol.parameters.length != 1 || !(constructor.symbol.parameters[0].semantic_type is StringType) || constructor.locals.length != 0 || constructor.body.statements.length != 1) {
			return false;
		}
		var init = constructor.body.statements[0] as CheckedFieldInitialize;
		var value = init == null ? null : init.value as CheckedParameterReferenceExpression;
		var receiver = init == null ? null : init.target.receiver as CheckedThisExpression;
		return init != null && value != null && value.parameter == constructor.symbol.parameters[0] && init.target.field == owner.fields[0] && receiver != null && receiver.receiver == owner.constructor.receiver;
	}
	public static Diagnostic? validate_program(CheckedProgram program) {
		int count = 0;
		foreach (var function in program.functions) {
			if (!function.symbol.utf8_factory) {
				continue;
			}
			var symbol = function.symbol;
			ClassSymbol? message = null;
			ClassSymbol? error = null;
			foreach (var owner in program.classes) {
				if (owner.semantic_type == symbol.return_type) {
					message = owner;
				}
				if (owner.semantic_type == symbol.throws_type) {
					error = owner;
				}
			}
			bool valid = ++count == 1 && symbol.name_span.text () == "utf8_message" && symbol.kind == CallableKind.FUNCTION && symbol.async_body == null && symbol.heap_result && symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER && symbol.parameters.length == 1 && symbol.parameters[0].semantic_type is SliceType && ((SliceType) symbol.parameters[0].semantic_type).element_type == program.types.u8_type && symbol.parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE;
			valid = valid && message != null && error != null && message.name_span.text () == "Utf8Message" && error.name_span.text () == "InvalidUtf8" && message.parent_class == null && !message.polymorphic && message.fields.length == 1 && message.fields[0].name == "snapshot" && message.fields[0].text_snapshot && message.methods.length == 0 && message.properties.length == 1 && message.properties[0].name == "text" && message.destructor == null && error.fields.length == 0 && error.methods.length == 0 && error.properties.length == 0 && error.destructor == null && error.parent_class != null && error.parent_class.exception_root;
			if (valid) {
				var root = error.parent_class;
				valid = root.fields.length == 1 && root.fields[0].text_snapshot && root.properties.length == 1 && root.properties[0].name == "message" && snapshot_constructor (program, message) && snapshot_constructor (program, root);
				var ctor = definition (program, error.constructor);
				var call = ctor == null || ctor.body.statements.length != 1 ? null : ctor.body.statements[0] as CheckedBaseLifecycleCall;
				var text = call == null || call.arguments.length != 1 ? null : call.arguments[0] as CheckedTextExpression;
				valid = valid && ctor != null && ctor.symbol.parameters.length == 0 && ctor.locals.length == 0 && call != null && call.target == root.constructor && text != null && text.payload.hex () == "696e76616c6964205554462d38";
				var getter = definition (program, message.properties[0].getter);
				var returned = getter == null || getter.body.statements.length != 1 ? null : getter.body.statements[0] as CheckedReturnStatement;
				var load = returned == null ? null : returned.expression as CheckedLoadExpression;
				var field = load == null ? null : load.source as CheckedReceiverFieldPlace;
				valid = valid && field != null && field.field == message.fields[0];
				var error_getter = root.properties.length == 1 ? definition (program, root.properties[0].getter) : null;
				var error_return = error_getter == null || error_getter.body.statements.length != 1 ? null : error_getter.body.statements[0] as CheckedReturnStatement;
				var error_load = error_return == null ? null : error_return.expression as CheckedLoadExpression;
				var error_field = error_load == null ? null : error_load.source as CheckedReceiverFieldPlace;
				valid = valid && error_field != null && error_field.field == root.fields[0];
				var branch = function.body.statements.length == 2 ? function.body.statements[0] as CheckedIf : null;
				var test = branch == null ? null : branch.condition as CheckedUtf8FactoryExpression;
				var construction = branch == null || branch.then_body.statements.length != 2 ? null : branch.then_body.statements[0] as CheckedConstructorObjectInitialization;
				var returned_owner = construction == null ? null : branch.then_body.statements[1] as CheckedOwnershipReturn;
				var certified = construction == null || construction.arguments.length != 1 ? null : construction.arguments[0] as CheckedUtf8FactoryExpression;
				var thrown = function.body.statements.length == 2 ? function.body.statements[1] as CheckedThrow : null;
				valid = valid && test != null && test.validates && test.semantic_type == program.types.bool_type && test.input == symbol.parameters[0] && branch.else_body == null && certified != null && !certified.validates && certified.semantic_type == program.types.string_type && certified.input == test.input && construction.constructor == message.constructor && construction.storage.heap_allocated && returned_owner != null && returned_owner.transfer != null && returned_owner.transfer.source == construction.local && returned_owner.producer == null && thrown != null && thrown.construction != null && thrown.construction.constructor == error.constructor && thrown.construction.arguments.length == 0 && thrown.construction.storage.heap_allocated;
			}
			if (!valid) {
				return new Diagnostic (symbol.span, "Utf8MessageFactory requires the canonical unique snapshot Class, static InvalidUtf8 constructor and nominated snapshot Error root");
			}
		}
		return null;
	}
}
public class CheckedTextExpression : CheckedExpression {
	public TextBytes payload { get; private set; }
	internal CheckedTextExpression (SourceSpan span, SemanticType type, TextBytes payload) {
		base (span, type);
		this.payload = payload;
	}
}
public class CheckedTextLengthExpression : CheckedExpression {
	public CheckedExpression receiver { get; private set; }
	internal CheckedTextLengthExpression (SourceSpan span, SemanticType type, CheckedExpression receiver) {
		base (span, type);
		this.receiver = receiver;
	}
}

// Check every definition before the checked program is published. Calls
// carry an obligation on their definition, including mutually recursive
// definitions; visible call sites never supply backing-lifetime evidence.
private class SemanticStoredText : Object {
	internal CheckedExpression value;
	internal LocalSymbol destination;
	internal SemanticStoredText (CheckedExpression value, LocalSymbol destination) {
		this.value = value;
		this.destination = destination;
	}
}
private class SemanticTextInvalidation : Object {
	internal Object owner;
	internal SourceSpan span;
	internal GenericArray<Object> values = new GenericArray<Object> ();
	internal SemanticTextInvalidation (Object owner, SourceSpan span) {
		this.owner = owner;
		this.span = span;
	}
}
internal class SemanticTextOrigins : Object {
	private TextOriginFlow flow = new TextOriginFlow ();
	private GenericArray<CheckedExpression> views = new GenericArray<CheckedExpression> ();
	private bool receiver_result;
	private GenericArray<SemanticStoredText> stored = new GenericArray<SemanticStoredText> ();
	private GenericArray<SemanticTextInvalidation> invalidations = new GenericArray<SemanticTextInvalidation> ();
	private GenericArray<CheckedExpression> returns = new GenericArray<CheckedExpression> ();
	private Object? receiver_owner(CheckedExpression? receiver) {
		if (receiver is CheckedWithReference) {
			return ((CheckedWithReference) receiver).contract.source;
		}
		if (receiver is CheckedClassUpcast) {
			return receiver_owner (((CheckedClassUpcast) receiver).reference);
		}
		if (receiver is CheckedObjectReceiverExpression) {
			return receiver_owner (((CheckedObjectReceiverExpression) receiver).reference);
		}
		if (receiver is CheckedLocalReferenceExpression) {
			return ((CheckedLocalReferenceExpression) receiver).local;
		}
		if (receiver is CheckedParameterReferenceExpression) {
			return ((CheckedParameterReferenceExpression) receiver).parameter;
		}
		if (receiver is CheckedThisExpression) {
			return ((CheckedThisExpression) receiver).receiver;
		}
		if (receiver is CheckedObjectReferenceExpression) {
			return ((CheckedObjectReferenceExpression) receiver).storage;
		}
		return null;
	}
	private void invalidate(Object owner, SourceSpan span) {
		if (!flow.state.reachable) {
			return;
		}
		var event = new SemanticTextInvalidation (owner, span);
		foreach (var key in flow.state.bindings.get_keys ()) {
			event.values.add (flow.state.bindings.lookup (key));
		}
		invalidations.add (event);
	}
	private void protected_group(CheckedTry guarded) {
		var entry = flow.state.snapshot ();
		flow.begin_try ();
		statement (guarded.body);
		var exceptional = flow.end_try ();
		var merged = flow.state;
		foreach (var caught in guarded.catches) {
			var incoming = entry.snapshot ();
			incoming.reachable = false;
			var remaining = new GenericArray<TextOriginException> ();
			var bound = (ClassType) caught.binding.semantic_type;
			foreach (var event in exceptional) {
				var effect = (ClassType) event.effect;
				if (effect.derives_from (bound) || bound.derives_from (effect)) {
					flow.merge (entry, incoming, flow.project (entry, event.state));
					incoming = flow.state;
				}
				if (!effect.derives_from (bound)) {
					remaining.add (event);
				}
			}
			exceptional = remaining;
			flow.state = incoming;
			statement (caught.body);
			flow.merge (entry, merged, flow.state);
			merged = flow.state;
		}
		foreach (var event in exceptional) {
			flow.exception (event.effect, flow.project (entry, event.state));
		}
		flow.state = merged;
	}
	private void value(CheckedExpression expression) {
		if (expression is CheckedSlotsValue && ((CheckedSlotsValue) expression).operand != null) {
			value (((CheckedSlotsValue) expression).operand);
		}
		if (expression is CheckedOwnershipMove) {
			invalidate (((CheckedOwnershipMove) expression).source, expression.span);
		}
		if (expression is CheckedOwnedArgument && ((CheckedOwnedArgument) expression).transfer != null) {
			value (((CheckedOwnedArgument) expression).transfer);
		}
		if (expression is CheckedCallExpression) {
			var call = (CheckedCallExpression) expression;
			if (call.receiver != null) {
				value (call.receiver);
			}
			foreach (var argument in call.arguments) {
				value (argument);
			}
			var target = call.target as FunctionSymbol;
			if (target != null && target.throws_type != null) {
				flow.exception (target.throws_type);
			}
		}
		if (expression is CheckedComparisonChain) {
			foreach (var operand in ((CheckedComparisonChain) expression).operands) {
				value (operand);
			}
		}
		if (expression is CheckedBinaryExpression) {
			value (((CheckedBinaryExpression) expression).left);
			value (((CheckedBinaryExpression) expression).right);
		}
		if (expression is CheckedShortCircuitExpression) {
			value (((CheckedShortCircuitExpression) expression).left);
			value (((CheckedShortCircuitExpression) expression).right);
		}
		if (expression is CheckedPrefixExpression) {
			value (((CheckedPrefixExpression) expression).operand);
		}
		// Conversion operands retain calls and ownership transfers.
		if (expression is CheckedNumericConversionExpression) {
			value (((CheckedNumericConversionExpression) expression).operand);
		}
		if (expression is CheckedFloatConversionExpression) {
			value (((CheckedFloatConversionExpression) expression).operand);
		}
		if (expression is CheckedIntegerConversionExpression) {
			value (((CheckedIntegerConversionExpression) expression).operand);
		}
		if (expression is CheckedTextLengthExpression) {
			value (((CheckedTextLengthExpression) expression).receiver);
		}

		if (expression.semantic_type.is_text_slice ()) {
			views.add (expression);
		}
		if (expression is CheckedParameterReferenceExpression) {
			var parameter = ((CheckedParameterReferenceExpression) expression).parameter;
			flow.origins.borrowed (parameter);
			flow.origins.copy (expression, parameter);
			return;
		}
		if (expression is CheckedLoadExpression && ((CheckedLoadExpression) expression).source is CheckedSliceElementPlace) {
			var slice = ((CheckedSliceElementPlace) ((CheckedLoadExpression) expression).source).slice;
			value (slice);
			flow.origins.copy (expression, slice);
			return;
		}
		if (expression is CheckedLoadExpression && ((CheckedLoadExpression) expression).source is CheckedReceiverFieldPlace && ((CheckedReceiverFieldPlace) ((CheckedLoadExpression) expression).source).field.text_snapshot) {
			flow.origins.receiver_borrow (expression, receiver_owner (((CheckedReceiverFieldPlace) ((CheckedLoadExpression) expression).source).receiver));
			return;
		}
		if (expression is CheckedLoadExpression && ((CheckedLoadExpression) expression).source is CheckedObjectFieldPlace && ((CheckedObjectFieldPlace) ((CheckedLoadExpression) expression).source).field.text_snapshot) {
			flow.origins.receiver_borrow (expression, receiver_owner (((CheckedObjectFieldPlace) ((CheckedLoadExpression) expression).source).reference));
			return;
		}
		if (expression is CheckedUtf8FactoryExpression) {
			flow.origins.borrowed (expression);
			return;
		}
		if (expression is CheckedTextExpression || expression is CheckedConstantReference) {
			flow.origins.literal (expression);
			return;
		}
		if (expression is CheckedCallExpression) {
			var target = ((CheckedCallExpression) expression).target as FunctionSymbol;
			if (target != null && target.result_contract == ResultOwnershipContract.STATIC_TEXT) {
				flow.origins.literal (expression);
			} else if (target != null && target.result_contract == ResultOwnershipContract.RECEIVER_TEXT) {
				flow.origins.receiver_borrow (expression, receiver_owner (((CheckedCallExpression) expression).receiver));
			}
			return;
		}
		if (expression is CheckedLocalReferenceExpression) {
			flow.read (((CheckedLocalReferenceExpression) expression).local, expression);
		}
	}
	private void statement(CheckedStatement source) {
		if (source is CheckedTry) {
			protected_group ((CheckedTry) source);
		} else if (source is CheckedThrow) {
			var thrown = (CheckedThrow) source;
			if (!thrown.rethrows) {
				invalidate (thrown.owner, thrown.span);
			}
			flow.exception (thrown.owner.semantic_type);
			flow.state.reachable = false;
		} else if (source is CheckedBlockStatement) {
			var body = (CheckedBlockStatement) source;
			foreach (var child in body.statements) {
				statement (child);
			}
			foreach (var key in flow.state.bindings.get_keys ()) {
				if (key is LocalSymbol && ((LocalSymbol) key).lexical_region == body.region) {
					flow.state.bindings.remove (key);
				}
			}
		} else if (source is CheckedEnumMatch) {
			var match = (CheckedEnumMatch) source;
			var entry = flow.state.snapshot ();
			Astra.Text.TextOriginState? merged = null;
			foreach (var arm in match.arms) {
				flow.state = entry.snapshot ();
				statement (arm.body);
				if (merged == null) {
					merged = flow.state;
				} else {
					flow.merge (entry, merged, flow.state);
					merged = flow.state;
				}
			}
			flow.state = merged;
		} else if (source is CheckedEnumReturn) {
			flow.state.reachable = false;
		} else if (source is CheckedIf) {
			var branch = (CheckedIf) source;
			value (branch.condition);
			var entry = flow.state.snapshot ();
			statement (branch.then_body);
			var left = flow.state;
			flow.state = entry.snapshot ();
			if (branch.else_body != null) {
				statement (branch.else_body);
			}
			flow.merge (entry, left, flow.state);
		} else if (source is CheckedWhile) {
			flow.begin_loop ();
			value (((CheckedWhile) source).condition);
			statement (((CheckedWhile) source).body);
			flow.begin_step ();
			if (((CheckedWhile) source).step != null) {
				statement (((CheckedWhile) source).step);
			}
			flow.end_loop ();
		} else if (source is CheckedBreak || source is CheckedContinue) {
			flow.jump (source is CheckedBreak);
		} else if (source is CheckedLocalDeclaration) {
			var local = (CheckedLocalDeclaration) source;
			value (local.initializer);
			if (local.local.semantic_type.is_text_view ()) {
				flow.write (local.local, local.initializer);
				stored.add (new SemanticStoredText (local.initializer, local.local));
			}
		} else if (source is CheckedAssignment) {
			var assignment = (CheckedAssignment) source;
			value (assignment.expression);
			if (assignment.target.semantic_type.is_text_view ()) {
				flow.write (assignment.target, assignment.expression);
				stored.add (new SemanticStoredText (assignment.expression, assignment.target));
			}
		} else if (source is CheckedStore) {
			value (((CheckedStore) source).value);
		} else if (source is CheckedStructLocalDeclaration) {
			foreach (var initial in ((CheckedStructLocalDeclaration) source).initializers) {
				if (initial.expression != null) {
					value (initial.expression);
				}
			}
		} else if (source is CheckedSlotsAppend) {
			value (((CheckedSlotsAppend) source).incoming);
		} else if (source is CheckedOwnedFieldTransfer) {
			value (((CheckedOwnedFieldTransfer) source).incoming);
		} else if (source is CheckedFieldAssignment) {
			value (((CheckedFieldAssignment) source).expression);
		} else if (source is CheckedOwnershipRearmAssignment) {
			var rearm = (CheckedOwnershipRearmAssignment) source;
			value (rearm.incoming);
			invalidate (rearm.owner, source.span);
		} else if (source is CheckedOwnershipRelease) {
			invalidate (((CheckedOwnershipRelease) source).owner, source.span);
		} else if (source is CheckedCallStatement) {
			var call = (CheckedCallStatement) source;
			if (call.receiver != null) {
				value (call.receiver);
			}
			foreach (var argument in call.arguments) {
				value (argument);
			}
			var target = call.target as FunctionSymbol;
			if (target != null && target.throws_type != null) {
				flow.exception (target.throws_type);
			}
		} else if (source is CheckedConstructorObjectInitialization) {
			foreach (var argument in ((CheckedConstructorObjectInitialization) source).arguments) {
				value (argument);
			}
		} else if (source is CheckedOwnershipReturn) {
			var returned = (CheckedOwnershipReturn) source;
			if (returned.producer != null) {
				value (returned.producer);
			}
			if (returned.transfer != null) {
				value (returned.transfer);
			}
			flow.state.reachable = false;
		} else if (source is CheckedReturnStatement) {
			var returned = ((CheckedReturnStatement) source).expression;
			if (returned != null) {
				value (returned);
				if (returned.semantic_type is StringType && !receiver_result) {
					returns.add (returned);
				}
			}
			flow.state.reachable = false;
		}
	}
	internal static Diagnostic? check(CheckedProgram program) {
		var proof = new SemanticTextOrigins ();
		foreach (var function in program.all_definitions ()) {
			proof.receiver_result = function.symbol.result_contract == ResultOwnershipContract.RECEIVER_TEXT;
			proof.flow.state = new TextOriginState ();
			proof.statement (function.body);
		}
		foreach (var loan in proof.stored) {
			var owners = proof.flow.origins.receiver_owners (loan.value);
			loan.value.text_loan_intent = new TextLoanIntent (owners);
			if (owners.length != 0) {
				loan.destination.text_loan = true;
			}
			foreach (var owner in owners) {
				LexicalRegion? region = (owner is LocalSymbol) ? ((LocalSymbol) owner).lexical_region : (owner is ParameterSymbol) ? ((ParameterSymbol) owner).lexical_region : (owner is LexicalObjectStorageSymbol) ? ((LexicalObjectStorageSymbol) owner).lexical_region : null;
				if (!(owner is ReceiverSymbol) && (region == null || !region.outlives (loan.destination.lexical_region))) {
					return new Diagnostic (loan.value.span, "receiver text loan requires its exact backing owner to outlive the destination local");
				}
			}
		}
		foreach (var event in proof.invalidations) {
			foreach (var value in event.values) {
				foreach (var owner in proof.flow.origins.receiver_owners (value)) {
					if (owner == event.owner) {
						return new Diagnostic (event.span, "cannot invalidate a receiver while a stored text loan remains in its lexical extent");
					}
				}
			}
		}
		foreach (var view in proof.views) {
			if (!proof.flow.origins.is_bounded (view)) {
				return new Diagnostic (view.span, "text slice requires a stable table and payload borrow rooted in native parameters");
			}
		}
		foreach (var returned in proof.returns) {
			if (!proof.flow.origins.is_static (returned)) {
				return new Diagnostic (returned.span, "borrowed text cannot escape through a STATIC_TEXT result; returning a local requires exclusively static backing origins");
			}
		}
		return null;
	}
}
}
