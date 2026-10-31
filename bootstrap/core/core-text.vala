// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Text;

namespace Astra.Core {
public class CoreUtf8FactoryValue : CoreValue {
	public CoreParameter input { get; private set; }
	public bool validates { get; private set; }
	internal CoreUtf8FactoryValue (SourceSpan span, SemanticType type, CoreParameter input, bool validates) {
		base (span, type);
		this.input = input;
		this.validates = validates;
	}
}
internal class CoreUtf8FactoryAuthority : Object {
	private static void require(bool valid) throws CoreError {
		if (!valid) {
			throw new CoreError.INVALID_IR ("UTF-8 factory lost exact validation/copy/owner/error authority");
		}
	}
	private static void snapshot_constructor(CoreClass owner) throws CoreError {
		var ctor = owner.constructor;
		require (ctor != null && ctor.parameters.length == 1 && ctor.parameters[0].semantic_type is StringType && ctor.body.statements.length == 1 && ctor.locals.length == 0);
		var init = ctor.body.statements[0] as CoreFieldInitialize;
		var place = init == null ? null : init.target as CoreIndirectFieldPlace;
		var input = init == null ? null : init.value as CoreParameterValue;
		var receiver = place == null ? null : place.pointer as CoreReceiverValue;
		require (place != null && place.field == owner.fields[0] && input != null && input.parameter == ctor.parameters[0] && receiver != null && receiver.receiver == ctor.receiver);
	}
	internal static HashTable<CoreUtf8FactoryValue, CoreFunction> authorize(CoreProgram program) throws CoreError {
		var allowed = new HashTable<CoreUtf8FactoryValue, CoreFunction> (direct_hash, direct_equal);
		int count = 0;
		foreach (var function in program.functions) {
			if (!function.utf8_factory) {
				continue;
			}
			require (++count == 1 && function.kind == CallableKind.FUNCTION && function.async_body == null && function.generic_instance == null && function.heap_result && function.return_type is ClassType && function.throws_type != null && function.owned_cleanup != null && function.owned_cleanup.is_heap_object && function.parameters.length == 1);
			var parameter = function.parameters[0];
			var slice = parameter.semantic_type as SliceType;
			require (slice != null && slice.element_type.kind == TypeKind.U8 && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
			CoreClass? message = null;
			CoreClass? error = null;
			foreach (var owner in program.classes) {
				if (owner.semantic_type == function.return_type) {
					message = owner;
				}
				if (owner.semantic_type == function.throws_type) {
					error = owner;
				}
			}
			require (message != null && error != null && message.parent_class == null && !message.polymorphic && message.fields.length == 1 && message.fields[0].text_snapshot && message.methods.length == 0 && message.properties.length == 1 && message.properties[0].setter == null && error.fields.length == 0 && error.methods.length == 0 && error.properties.length == 0 && error.parent_class != null && error.parent_class.exception_root);
			require (message.destructor != null && message.destructor.body.statements.length == 0 && error.destructor != null && error.destructor.body.statements.length == 0);
			snapshot_constructor (message);
			require (error.parent_class.fields.length == 1 && error.parent_class.fields[0].text_snapshot);
			snapshot_constructor (error.parent_class);
			var root = error.parent_class;
			require (root.properties.length == 1);
			var root_return = root.properties[0].getter.body.statements.length == 1 ? root.properties[0].getter.body.statements[0] as CoreReturn : null;
			var root_load = root_return == null ? null : root_return.value as CoreLoadValue;
			var root_field = root_load == null ? null : root_load.source as CoreIndirectFieldPlace;
			require (root_field != null && root_field.field == root.fields[0]);
			var getter_return = message.properties[0].getter.body.statements.length == 1 ? message.properties[0].getter.body.statements[0] as CoreReturn : null;
			var getter_load = getter_return == null ? null : getter_return.value as CoreLoadValue;
			var getter_place = getter_load == null ? null : getter_load.source as CoreIndirectFieldPlace;
			require (getter_place != null && getter_place.field == message.fields[0]);
			var error_ctor = error.constructor;
			require (error_ctor != null && error_ctor.parameters.length == 0 && error_ctor.body.statements.length == 1);
			var base_call = error_ctor.body.statements[0] as CoreBaseLifecycleCall;
			var diagnostic = base_call == null || base_call.arguments.length != 1 ? null : base_call.arguments[0] as CoreTextValue;
			require (base_call != null && base_call.target == error.parent_class.constructor && diagnostic != null && diagnostic.payload.hex () == "696e76616c6964205554462d38");
			require (function.body.statements.length == 3);
			var branch = function.body.statements[0] as CoreIf;
			var test = branch == null ? null : branch.condition as CoreUtf8FactoryValue;
			require (test != null && test.validates && test.input == parameter && test.semantic_type.kind == TypeKind.BOOL && branch.else_block == null && branch.then_block.statements.length == 2);
			var construction = branch.then_block.statements[0] as CoreConstructorObjectInitialization;
			var returned = branch.then_block.statements[1] as CoreOwnershipReturn;
			var text = construction == null || construction.arguments.length != 1 ? null : construction.arguments[0] as CoreUtf8FactoryValue;
			require (text != null && !text.validates && text.input == parameter && text.semantic_type is StringType && construction.constructor == message.constructor && construction.storage.heap_allocated && construction.acquisition != null && returned != null && returned.source == construction.acquisition && returned.producer == null);
			var error_construction = function.body.statements[1] as CoreConstructorObjectInitialization;
			var thrown = function.body.statements[2] as CoreThrow;
			require (error_construction != null && error_construction.constructor == error.constructor && error_construction.arguments.length == 0 && error_construction.storage.heap_allocated && thrown != null && thrown.source == error_construction.target && thrown.owner == error_construction.acquisition);
			allowed.insert (test, function);
			allowed.insert (text, function);
		}
		return allowed;
	}
}

public class CoreTextValue : CoreValue {
	public TextBytes payload { get; private set; }
	internal CoreTextValue (SourceSpan span, SemanticType type, TextBytes payload) {
		base (span, type);
		this.payload = payload;
	}
}
public class CoreTextLengthValue : CoreValue {
	public CoreValue receiver { get; private set; }
	internal CoreTextLengthValue (SourceSpan span, SemanticType type, CoreValue receiver) {
		base (span, type);
		this.receiver = receiver;
	}
}

private class CoreStoredText : Object {
	internal CoreValue value;
	internal CoreLocalPlace destination;
	internal CoreStoredText (CoreValue value, CoreLocalPlace destination) {
		this.value = value;
		this.destination = destination;
	}
}
private class CoreTextInvalidation : Object {
	internal Object owner;
	internal GenericArray<Object> values = new GenericArray<Object> ();
	internal CoreTextInvalidation (Object owner) {
		this.owner = owner;
	}
}
internal class CoreTextOrigins : Object {
	private TextOriginFlow flow = new TextOriginFlow ();
	private GenericArray<CoreValue> views = new GenericArray<CoreValue> ();
	private bool receiver_result;
	private GenericArray<CoreStoredText> stored = new GenericArray<CoreStoredText> ();
	private GenericArray<CoreTextInvalidation> invalidations = new GenericArray<CoreTextInvalidation> ();
	private GenericArray<CoreValue> returns = new GenericArray<CoreValue> ();
	private Object? receiver_owner(CoreValue? receiver) {
		if (receiver is CoreWithReference) {
			return ((CoreWithReference) receiver).contract.source;
		}
		if (receiver is CoreClassUpcast) {
			return receiver_owner (((CoreClassUpcast) receiver).reference);
		}
		if (receiver is CoreObjectReceiverValue) {
			return receiver_owner (((CoreObjectReceiverValue) receiver).reference);
		}
		if (receiver is CoreLoadValue) {
			return ((CoreLoadValue) receiver).source;
		}
		if (receiver is CoreParameterValue) {
			return ((CoreParameterValue) receiver).parameter;
		}
		if (receiver is CoreReceiverValue) {
			return ((CoreReceiverValue) receiver).receiver;
		}
		return null;
	}
	private void invalidate(Object owner) {
		if (!flow.state.reachable) {
			return;
		}
		var event = new CoreTextInvalidation (owner);
		foreach (var key in flow.state.bindings.get_keys ()) {
			event.values.add (flow.state.bindings.lookup (key));
		}
		invalidations.add (event);
	}
	private void protected_group(CoreTry guarded) throws CoreError {
		var entry = flow.state.snapshot ();
		flow.begin_try ();
		block (guarded.body);
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
			block (caught.body);
			flow.merge (entry, merged, flow.state);
			merged = flow.state;
		}
		foreach (var event in exceptional) {
			flow.exception (event.effect, flow.project (entry, event.state));
		}
		flow.state = merged;
	}
	private void value(CoreValue expression) {
		if (expression is CoreSlotsValue && ((CoreSlotsValue) expression).operand != null) {
			value (((CoreSlotsValue) expression).operand);
		}
		if (expression is CoreOwnedArgumentValue && ((CoreOwnedArgumentValue) expression).source != null) {
			invalidate (((CoreOwnedArgumentValue) expression).source.place);
		}
		if (expression is CoreCallValue) {
			var call = (CoreCallValue) expression;
			if (call.receiver != null) {
				value (call.receiver);
			}
			foreach (var argument in call.arguments) {
				value (argument);
			}
			if (call.target.throws_type != null) {
				flow.exception (call.target.throws_type);
			}
		}
		if (expression is CoreCCallValue) {
			foreach (var argument in ((CoreCCallValue) expression).arguments) {
				value (argument);
			}
		}
		if (expression is CoreComparisonChain) {
			foreach (var operand in ((CoreComparisonChain) expression).operands) {
				value (operand);
			}
		}
		if (expression is CoreBinaryValue) {
			value (((CoreBinaryValue) expression).left);
			value (((CoreBinaryValue) expression).right);
		}
		if (expression is CoreShortCircuitValue) {
			value (((CoreShortCircuitValue) expression).left);
			value (((CoreShortCircuitValue) expression).right);
		}
		if (expression is CorePrefixValue) {
			value (((CorePrefixValue) expression).operand);
		}
		if (expression is CoreNumericConversionValue) {
			value (((CoreNumericConversionValue) expression).operand);
		}
		if (expression is CoreFloatConversionValue) {
			value (((CoreFloatConversionValue) expression).operand);
		}
		if (expression is CoreIntegerConversionValue) {
			value (((CoreIntegerConversionValue) expression).operand);
		}
		if (expression is CoreTextLengthValue) {
			value (((CoreTextLengthValue) expression).receiver);
		}

		if (expression.semantic_type.is_text_slice ()) {
			views.add (expression);
		}
		if (expression is CoreParameterValue) {
			var parameter = ((CoreParameterValue) expression).parameter;
			flow.origins.borrowed (parameter);
			flow.origins.copy (expression, parameter);
			return;
		}
		if (expression is CoreLoadValue && ((CoreLoadValue) expression).source is CoreSliceElementPlace) {
			var slice = ((CoreSliceElementPlace) ((CoreLoadValue) expression).source).slice;
			value (slice);
			flow.origins.copy (expression, slice);
			return;
		}
		if (expression is CoreLoadValue && ((CoreLoadValue) expression).source is CoreIndirectFieldPlace && ((CoreIndirectFieldPlace) ((CoreLoadValue) expression).source).field.text_snapshot) {
			flow.origins.receiver_borrow (expression, receiver_owner (((CoreIndirectFieldPlace) ((CoreLoadValue) expression).source).pointer));
			return;
		}
		if (expression is CoreUtf8FactoryValue) {
			flow.origins.borrowed (expression);
			return;
		}
		if (expression is CoreTextValue) {
			flow.origins.literal (expression);
		} else if (expression is CoreCallValue) {
			var target = ((CoreCallValue) expression).target;
			if (target != null && target.result_contract == ResultOwnershipContract.STATIC_TEXT) {
				flow.origins.literal (expression);
			} else if (target != null && target.result_contract == ResultOwnershipContract.RECEIVER_TEXT) {
				flow.origins.receiver_borrow (expression, receiver_owner (((CoreCallValue) expression).receiver));
			}
		} else if (expression is CoreLoadValue) {
			flow.read (((CoreLoadValue) expression).source, expression);
		}
	}
	private void block(CoreBlock body) throws CoreError {
		var declared = new GenericArray<CorePlace> ();
		foreach (var source in body.statements) {
			if (source is CoreTry) {
				protected_group ((CoreTry) source);
			} else if (source is CoreThrow) {
				var thrown = (CoreThrow) source;
				if (!thrown.rethrows) {
					invalidate (thrown.source);
				}
				flow.exception (thrown.source.semantic_type);
				flow.state.reachable = false;
			} else if (source is CoreScope) {
				block (((CoreScope) source).body);
			} else if (source is CoreEnumMatch) {
				var match = (CoreEnumMatch) source;
				var entry = flow.state.snapshot ();
				Astra.Text.TextOriginState? merged = null;
				foreach (var arm in match.arms) {
					flow.state = entry.snapshot ();
					block (arm.body);
					if (merged == null) {
						merged = flow.state;
					} else {
						flow.merge (entry, merged, flow.state);
						merged = flow.state;
					}
				}
				flow.state = merged;
			} else if (source is CoreEnumReturn) {
				flow.state.reachable = false;
			} else if (source is CoreIf) {
				var branch = (CoreIf) source;
				value (branch.condition);
				var entry = flow.state.snapshot ();
				block (branch.then_block);
				var left = flow.state;
				flow.state = entry.snapshot ();
				if (branch.else_block != null) {
					block (branch.else_block);
				}
				flow.merge (entry, left, flow.state);
			} else if (source is CoreWhile) {
				flow.begin_loop ();
				value (((CoreWhile) source).condition);
				block (((CoreWhile) source).body);
				flow.begin_step ();
				if (((CoreWhile) source).step != null) {
					block (((CoreWhile) source).step);
				}
				flow.end_loop ();
			} else if (source is CoreBreak || source is CoreContinue) {
				flow.jump (source is CoreBreak);
			} else if (source is CoreInitialize) {
				var init = (CoreInitialize) source;
				if (init.target is CoreLocalPlace && ((CoreLocalPlace) init.target).text_loan && ((CoreLocalPlace) init.target).text_extent != body.text_extent) {
					throw new CoreError.INVALID_IR ("stored text declaration changed its exact lexical block extent");
				}
				value (init.value);
				declared.add (init.target);
				if (init.value.semantic_type.is_text_view ()) {
					flow.write (init.target, init.value);
					if (init.target is CoreLocalPlace) {
						stored.add (new CoreStoredText (init.value, (CoreLocalPlace) init.target));
					}
				}
			} else if (source is CoreStore) {
				var store = (CoreStore) source;
				value (store.value);
				if (store.value.semantic_type.is_text_view ()) {
					flow.write (store.target, store.value);
					if (store.target is CoreLocalPlace) {
						stored.add (new CoreStoredText (store.value, (CoreLocalPlace) store.target));
					}
				}
			} else if (source is CoreOwnershipRelease) {
				invalidate (((CoreOwnershipRelease) source).owner.place);
			} else if (source is CoreStructAcquire) {
				var record = (CoreStructAcquire) source;
				if (record.producer != null) {
					value (record.producer);
				}
			} else if (source is CoreSlotsAppend) {
				invalidate (((CoreSlotsAppend) source).incoming.place);
			} else if (source is CoreOwnedFieldTransfer) {
				var transfer = (CoreOwnedFieldTransfer) source;
				if (transfer.producer != null) {
					value (transfer.producer);
				}
				if (transfer.source != null) {
					invalidate (transfer.source.place);
				}
			} else if (source is CoreOwnershipTransfer) {
				invalidate (((CoreOwnershipTransfer) source).source.place);
			} else if (source is CoreOwnershipRearm) {
				var rearm = (CoreOwnershipRearm) source;
				if (rearm.producer != null) {
					value (rearm.producer);
				}
				invalidate (rearm.owner.place);
				if (rearm.source != null) {
					invalidate (rearm.source.place);
				}
			} else if (source is CoreCallStatement) {
				var call = (CoreCallStatement) source;
				if (call.receiver != null) {
					value (call.receiver);
				}
				foreach (var argument in call.arguments) {
					value (argument);
				}
				if (call.target.throws_type != null) {
					flow.exception (call.target.throws_type);
				}
			} else if (source is CoreOwnershipReturn) {
				var returned = (CoreOwnershipReturn) source;
				if (returned.producer != null) {
					value (returned.producer);
				}
				if (returned.source != null) {
					invalidate (returned.source.place);
				}
				flow.state.reachable = false;
			} else if (source is CoreReturn) {
				var returned = ((CoreReturn) source).value;
				if (returned != null) {
					value (returned);
					if (returned.semantic_type is StringType && !receiver_result) {
						returns.add (returned);
					}
				}
				flow.state.reachable = false;
			}
		}
		foreach (var local in declared) {
			flow.state.bindings.remove (local);
		}
	}
	internal static void verify(CoreProgram program) throws CoreError {
		var proof = new CoreTextOrigins ();
		foreach (var function in program.all_definitions ()) {
			proof.receiver_result = function.result_contract == ResultOwnershipContract.RECEIVER_TEXT;
			proof.flow.state = new TextOriginState ();
			proof.block (function.body);
		}
		foreach (var loan in proof.stored) {
			var owners = proof.flow.origins.receiver_owners (loan.value);
			if (owners.length != 0 && (loan.value.text_loan_intent == null || !loan.value.text_loan_intent.matches (owners))) {
				throw new CoreError.INVALID_IR ("stored text loan lost its exact predecessor receiver association");
			}
			if (loan.value.text_loan_intent != null && !loan.value.text_loan_intent.matches (owners)) {
				throw new CoreError.INVALID_IR ("text loan changed its retained backing association");
			}
			foreach (var owner in owners) {
				if (!loan.destination.text_loan || loan.destination.text_extent == null) {
					throw new CoreError.INVALID_IR ("stored receiver text requires its exact retained loan extent");
				}
				if (owner is CoreLocalPlace) {
					var backing = (CoreLocalPlace) owner;
					if (backing.text_extent == null || !backing.text_extent.outlives (loan.destination.text_extent)) {
						throw new CoreError.INVALID_IR ("receiver text backing does not outlive its destination");
					}
				} else if (!(owner is CoreReceiver || owner is CoreParameter)) {
					throw new CoreError.INVALID_IR ("receiver text lacks an exact stable backing identity");
				}
			}
		}
		foreach (var event in proof.invalidations) {
			foreach (var value in event.values) {
				foreach (var owner in proof.flow.origins.receiver_owners (value)) {
					if (owner == event.owner) {
						throw new CoreError.INVALID_IR ("receiver invalidation overlaps a surviving stored text loan");
					}
				}
			}
		}
		foreach (var view in proof.views) {
			if (!proof.flow.origins.is_bounded (view)) {
				throw new CoreError.INVALID_IR ("text slice requires stable deep backing origins");
			}
		}
		foreach (var returned in proof.returns) {
			if (!proof.flow.origins.is_static (returned)) {
				throw new CoreError.INVALID_IR ("text return: borrowed text cannot escape through a STATIC_TEXT result");
			}
		}
	}
}
}
