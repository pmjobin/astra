// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Text;

namespace Astra.Cfg {
public class CfgUtf8FactoryValue : CfgValue {
	public CfgParameter input { get; private set; }
	public bool validates { get; private set; }
	internal CfgUtf8FactoryValue (SourceSpan span, SemanticType type, CfgParameter input, bool validates) {
		base (span, type);
		this.input = input;
		this.validates = validates;
	}
}
internal class CfgUtf8FactoryAuthority : Object {
	private static void require(bool valid) throws CfgError {
		if (!valid) {
			throw new CfgError.INVALID_CFG ("UTF-8 factory lost exact guarded byte group, canonical copy or checked-error edge");
		}
	}
	private static void snapshot_constructor(CfgClass owner) throws CfgError {
		var ctor = owner.constructor;
		require (ctor != null && ctor.parameters.length == 1 && ctor.parameters[0].semantic_type is StringType && ctor.blocks.length == 1 && ctor.entry.instructions.length == 1);
		var init = ctor.entry.instructions[0] as CfgInitialize;
		var place = init == null ? null : init.target as CfgIndirectFieldPlace;
		var input = init == null ? null : init.value as CfgParameterValue;
		var receiver = place == null ? null : place.pointer as CfgReceiverValue;
		require (place != null && place.field == owner.fields[0] && input != null && input.parameter == ctor.parameters[0] && receiver != null && receiver.receiver == ctor.receiver);
	}
	private static void snapshot_getter(CfgClass owner) throws CfgError {
		require (owner.properties.length == 1);
		var getter = owner.properties[0].getter;
		require (getter.blocks.length == 1 && getter.entry.instructions.length == 1);
		var read = getter.entry.instructions[0] as CfgEvaluateInstruction;
		var load = read == null ? null : read.value as CfgLoadValue;
		var place = load == null ? null : load.source as CfgIndirectFieldPlace;
		var returned = getter.entry.terminator as CfgReturn;
		require (place != null && place.field == owner.fields[0] && returned != null && returned.value == read.result);
	}
	internal static HashTable<CfgUtf8FactoryValue, CfgFunction> authorize(CfgProgram program) throws CfgError {
		var allowed = new HashTable<CfgUtf8FactoryValue, CfgFunction> (direct_hash, direct_equal);
		int count = 0;
		foreach (var function in program.functions) {
			if (!function.utf8_factory) {
				continue;
			}
			require (++count == 1 && function.kind == CallableKind.FUNCTION && function.async_body == null && function.heap_result && function.owned_cleanup != null && function.owned_cleanup.is_heap_object && function.parameters.length == 1 && function.blocks.length == 3 && function.entry.instructions.length == 0);
			var input = function.parameters[0];
			var slice = input.semantic_type as SliceType;
			require (slice != null && slice.element_type.kind == TypeKind.U8 && input.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
			var branch = function.entry.terminator as CfgConditionalBranch;
			var test = branch == null ? null : branch.condition as CfgUtf8FactoryValue;
			require (test != null && test.validates && test.input == input && test.semantic_type.kind == TypeKind.BOOL && branch.true_target != null && branch.false_target != null && function.blocks.find (branch.true_target) && function.blocks.find (branch.false_target) && branch.true_target != branch.false_target && branch.true_target != function.entry && branch.false_target != function.entry);
			require (branch.true_target.terminator is CfgReturn && branch.false_target.terminator is CfgExceptionReturn);
			require (branch.true_target.instructions.length == 5 && branch.false_target.instructions.length == 7);
			CfgLifecycleCallInstruction? success = null;
			CfgLifecycleCallInstruction? failure = null;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					require (instruction is CfgLifecycleCallInstruction || instruction is CfgEvaluateInstruction || instruction is CfgInitialize || instruction is CfgOwnershipReturnInstruction || instruction is CfgCleanupInstruction || instruction is CfgExceptionStamp);
					var evaluation = instruction as CfgEvaluateInstruction;
					if (evaluation != null) {
						require (evaluation.value is CfgObjectReferenceValue || evaluation.value is CfgLoadValue || evaluation.value is CfgClassUpcast);
					}
					if (instruction is CfgCallInstruction) {
						var call = instruction as CfgLifecycleCallInstruction;
						require (call != null && call.constructs);
						if (block == branch.true_target) {
							require (success == null);
							success = call;
						} else {
							require (block == branch.false_target && failure == null);
							failure = call;
						}
					}
				}
			}
			require (success != null && failure != null && success.storage.heap_allocated && failure.storage.heap_allocated && success.storage.semantic_type == function.return_type && failure.storage.semantic_type == function.throws_type && success.arguments.length == 1 && failure.arguments.length == 0);
			var text = success.arguments[0] as CfgUtf8FactoryValue;
			require (text != null && !text.validates && text.input == input && text.semantic_type is StringType);
			var message = ((CfgConstructor) success.target).declaring_class;
			var error = ((CfgConstructor) failure.target).declaring_class;
			require (message != null && error != null && message.parent_class == null && message.fields.length == 1 && message.fields[0].text_snapshot && message.methods.length == 0 && message.properties.length == 1 && error.fields.length == 0 && error.parent_class != null && error.parent_class.exception_root && error.parent_class.fields.length == 1 && error.parent_class.fields[0].text_snapshot);
			snapshot_constructor (message);
			snapshot_constructor (error.parent_class);
			snapshot_getter (message);
			snapshot_getter (error.parent_class);
			var ctor = error.constructor;
			require (ctor.parameters.length == 0 && ctor.blocks.length == 1 && ctor.entry.instructions.length == 2);
			var call = ctor.entry.instructions[1] as CfgBaseLifecycleCall;
			var diagnostic = call == null || call.arguments.length != 1 ? null : call.arguments[0] as CfgTextValue;
			require (call != null && call.target == error.parent_class.constructor && diagnostic != null && diagnostic.payload.hex () == "696e76616c6964205554462d38");
			allowed.insert (test, function);
			allowed.insert (text, function);
		}
		return allowed;
	}
}

// No runtime retention: an explicit exit discharges one local's lexical loan.
public class CfgTextLoanEnd : CfgInstruction {
	public TextLoanIntent exit_authority { get; private set; }
	public CfgLocalPlace local { get; private set; }
	internal CfgTextLoanEnd (SourceSpan span, CfgLocalPlace local, TextLoanIntent exit_authority) {
		base (span);
		this.local = local;
		this.exit_authority = exit_authority;
	}
}

public class CfgTextSnapshotDestroy : CfgInstruction {
	public CfgIndirectFieldPlace field { get; private set; }
	internal CfgTextSnapshotDestroy (SourceSpan span, CfgIndirectFieldPlace field) {
		base (span);
		this.field = field;
	}
}

public class CfgTextValue : CfgValue {
	public TextBytes payload { get; private set; }
	internal CfgTextValue (SourceSpan span, SemanticType type, TextBytes payload) {
		base (span, type);
		this.payload = payload;
	}
}
public class CfgTextLengthValue : CfgValue {
	public CfgValue receiver { get; private set; }
	internal CfgTextLengthValue (SourceSpan span, SemanticType type, CfgValue receiver) {
		base (span, type);
		this.receiver = receiver;
	}
}

private class CfgStoredText : Object {
	internal CfgValue value;
	internal CfgLocalPlace destination;
	internal CfgStoredText (CfgValue value, CfgLocalPlace destination) {
		this.value = value;
		this.destination = destination;
	}
}
private class CfgTextInvalidation : Object {
	internal Object owner;
	internal GenericArray<Object> values = new GenericArray<Object> ();
	internal CfgTextInvalidation (Object owner) {
		this.owner = owner;
	}
}
internal class CfgTextOrigins : Object {
	private GenericArray<CfgStoredText> stored = new GenericArray<CfgStoredText> ();
	private HashTable<CfgEvaluatedValue, CfgValue> evaluations = new HashTable<CfgEvaluatedValue, CfgValue> (direct_hash, direct_equal);
	private HashTable<CfgTemporaryPlace, GenericArray<CfgLocalPlace>> catch_bindings = new HashTable<CfgTemporaryPlace, GenericArray<CfgLocalPlace>> (direct_hash, direct_equal);
	private GenericArray<CfgTextInvalidation> invalidations = new GenericArray<CfgTextInvalidation> ();
	private GenericArray<Object> exits = new GenericArray<Object> ();
	private TextOrigins origins = new TextOrigins ();
	private GenericArray<CfgValue> views = new GenericArray<CfgValue> ();
	private GenericArray<CfgValue> returns = new GenericArray<CfgValue> ();
	private Object? receiver_owner(CfgValue? receiver) {
		if (receiver is CfgEvaluatedValue) {
			return receiver_owner (evaluations.lookup ((CfgEvaluatedValue) receiver));
		}
		if (receiver is CfgClassUpcast) {
			return receiver_owner (((CfgClassUpcast) receiver).reference);
		}
		if (receiver is CfgObjectValidateValue) {
			return receiver_owner (((CfgObjectValidateValue) receiver).reference);
		}
		if (receiver is CfgLoadValue) {
			return ((CfgLoadValue) receiver).source;
		}
		if (receiver is CfgParameterValue) {
			return ((CfgParameterValue) receiver).parameter;
		}
		if (receiver is CfgReceiverValue) {
			return ((CfgReceiverValue) receiver).receiver;
		}
		return null;
	}
	private void invalidate(Object owner, TextOriginState state) {
		var event = new CfgTextInvalidation (owner);
		foreach (var key in state.bindings.get_keys ()) {
			event.values.add (state.bindings.lookup (key));
		}
		invalidations.add (event);
	}
	private void value(CfgValue expression, TextOriginState state) {
		if (expression is CfgSlotsValue && ((CfgSlotsValue) expression).operand != null) {
			value (((CfgSlotsValue) expression).operand, state);
		}
		if (expression.semantic_type.is_text_slice ()) {
			views.add (expression);
		}
		if (expression is CfgParameterValue) {
			var parameter = ((CfgParameterValue) expression).parameter;
			origins.borrowed (parameter);
			origins.copy (expression, parameter);
			return;
		}
		if (expression is CfgLoadValue && ((CfgLoadValue) expression).source is CfgSliceElementPlace) {
			var slice = ((CfgSliceElementPlace) ((CfgLoadValue) expression).source).slice;
			value (slice, state);
			origins.copy (expression, slice);
			return;
		}
		if (expression is CfgLoadValue && ((CfgLoadValue) expression).source is CfgIndirectFieldPlace && ((CfgIndirectFieldPlace) ((CfgLoadValue) expression).source).field.text_snapshot) {
			origins.receiver_borrow (expression, receiver_owner (((CfgIndirectFieldPlace) ((CfgLoadValue) expression).source).pointer));
			return;
		}
		if (expression is CfgUtf8FactoryValue) {
			origins.borrowed (expression);
			return;
		}
		if (expression is CfgTextValue) {
			origins.literal (expression);
		} else if (expression is CfgLoadValue) {
			origins.copy (expression, state.bindings.lookup (((CfgLoadValue) expression).source) ?? new Object ());
		}
	}
	private void function(CfgFunction function) {
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction is CfgEvaluateInstruction) {
					var evaluation = (CfgEvaluateInstruction) instruction;
					evaluations.insert (evaluation.result, evaluation.value);
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var init = instruction as CfgInitialize;
				if (init != null && init.value is CfgCatchBorrow) {
					var slot = receiver_owner (((CfgCatchBorrow) init.value).exception) as CfgTemporaryPlace;
					if (slot != null) {
						var bindings = catch_bindings.lookup (slot);
						if (bindings == null) {
							bindings = new GenericArray<CfgLocalPlace> ();
							catch_bindings.insert (slot, bindings);
						}
						bindings.add ((CfgLocalPlace) init.target);
					}
				}
			}
		}
		var entries = new HashTable<CfgBlock, TextOriginState> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			var state = new TextOriginState ();
			foreach (var local in function.locals) {
				if (local.semantic_type.is_text_view ()) {
					state.bindings.insert (local, new Object ());
				}
			}
			foreach (var temporary in function.temporaries) {
				if (temporary.semantic_type.is_text_view ()) {
					state.bindings.insert (temporary, new Object ());
				}
			}
			entries.insert (block, state);
		}
		foreach (var block in function.blocks) {
			var state = entries.lookup (block).snapshot ();
			foreach (var instruction in block.instructions) {
				if (instruction is CfgTextLoanEnd) {
					state.bindings.insert (((CfgTextLoanEnd) instruction).local, new Object ());
				}
				Object? invalidated = null;
				if (instruction is CfgOwnedArgumentCapture) {
					invalidated = ((CfgOwnedArgumentCapture) instruction).transfer.source;
				} else if (instruction is CfgSlotsAppend) {
					invalidated = ((CfgSlotsAppend) instruction).incoming;
				} else if (instruction is CfgResourceCapture) {
					invalidated = ((CfgResourceCapture) instruction).source;
				} else if (instruction is CfgOwnershipReleaseInstruction) {
					invalidated = ((CfgOwnershipReleaseInstruction) instruction).owner;
				} else if (instruction is CfgOwnershipTransferInstruction) {
					invalidated = ((CfgOwnershipTransferInstruction) instruction).source;
				} else if (instruction is CfgOwnershipRearmInstruction) {
					invalidated = ((CfgOwnershipRearmInstruction) instruction).owner;
				} else if (instruction is CfgExceptionTake) {
					invalidated = ((CfgExceptionTake) instruction).owner;
				} else if (instruction is CfgCleanupInstruction) {
					invalidated = receiver_owner (((CfgCleanupInstruction) instruction).value);
				}
				if (invalidated != null) {
					invalidate (invalidated, state);
					var bindings = (invalidated is CfgTemporaryPlace) ? catch_bindings.lookup ((CfgTemporaryPlace) invalidated) : null;
					if (bindings != null) {
						foreach (var binding in bindings) {
							invalidate (binding, state);
						}
					}
				}

				if (instruction is CfgInitialize) {
					var init = (CfgInitialize) instruction;
					if (init.value.semantic_type.is_text_view ()) {
						value (init.value, state);
						state.bindings.insert (init.target, init.value);
						if (init.target is CfgLocalPlace && !(init.target is CfgTemporaryPlace)) {
							stored.add (new CfgStoredText (init.value, (CfgLocalPlace) init.target));
						}
					}
				} else if (instruction is CfgStore) {
					var store = (CfgStore) instruction;
					if (store.value.semantic_type.is_text_view ()) {
						value (store.value, state);
						state.bindings.insert (store.target, store.value);
						if (store.target is CfgLocalPlace && !(store.target is CfgTemporaryPlace)) {
							stored.add (new CfgStoredText (store.value, (CfgLocalPlace) store.target));
						}
					}
				} else if (instruction is CfgEvaluateInstruction) {
					var eval = (CfgEvaluateInstruction) instruction;
					if (eval.result.semantic_type.is_text_view ()) {
						value (eval.value, state);
						origins.copy (eval.result, eval.value);
					}
				} else if (instruction is CfgCallInstruction) {
					var call = (CfgCallInstruction) instruction;
					var target = call.target;
					if (call.result != null && call.result.semantic_type is StringType && target != null && target.result_contract == ResultOwnershipContract.STATIC_TEXT) {
						origins.literal (call.result);
					} else if (call.result != null && call.result.semantic_type is StringType && target != null && target.result_contract == ResultOwnershipContract.RECEIVER_TEXT) {
						origins.receiver_borrow (call.result, receiver_owner (call.receiver));
					}
				}
			}
			if (block.terminator is CfgReturn) {
				var returned = ((CfgReturn) block.terminator).value;
				if (returned != null && returned.semantic_type is StringType) {
					value (returned, state);
					if (function.result_contract != ResultOwnershipContract.RECEIVER_TEXT) {
						returns.add (returned);
					}
				}
			}
			if (block.terminator is CfgReturn || block.terminator is CfgFunctionEnd || block.terminator is CfgExceptionReturn) {
				foreach (var key in state.bindings.get_keys ()) {
					exits.add (state.bindings.lookup (key));
				}
			}
			foreach (var successor in block.terminator.successors ()) {
				var bindings = entries.lookup (successor).bindings;
				foreach (var key in bindings.get_keys ()) {
					origins.copy (bindings.lookup (key), state.bindings.lookup (key) ?? new Object ());
				}
			}
		}
	}
	internal static void verify(CfgProgram program) throws CfgError {
		var proof = new CfgTextOrigins ();
		foreach (var function in program.functions) {
			proof.function (function);
		}
		foreach (var loan in proof.stored) {
			var owners = proof.origins.receiver_owners (loan.value);
			if (owners.length != 0 && (loan.value.text_loan_intent == null || !loan.value.text_loan_intent.matches (owners))) {
				throw new CfgError.INVALID_CFG ("stored text loan lost its exact predecessor receiver association");
			}
			if (loan.value.text_loan_intent != null && !loan.value.text_loan_intent.matches (owners)) {
				throw new CfgError.INVALID_CFG ("text loan changed its retained backing association");
			}
			foreach (var owner in owners) {
				if (!loan.destination.text_loan || loan.destination.text_extent == null) {
					throw new CfgError.INVALID_CFG ("stored receiver text requires its exact retained loan extent");
				}
				if (owner is CfgLocalPlace) {
					var backing = (CfgLocalPlace) owner;
					if (backing.text_extent == null || !backing.text_extent.outlives (loan.destination.text_extent)) {
						throw new CfgError.INVALID_CFG ("receiver text backing does not outlive its destination");
					}
				} else if (!(owner is CfgReceiver || owner is CfgParameter)) {
					throw new CfgError.INVALID_CFG ("receiver text lacks an exact stable backing identity");
				}
			}
		}
		foreach (var event in proof.invalidations) {
			foreach (var value in event.values) {
				foreach (var owner in proof.origins.receiver_owners (value)) {
					if (owner == event.owner) {
						throw new CfgError.INVALID_CFG ("receiver invalidation overlaps a surviving stored text loan");
					}
				}
			}
		}
		foreach (var value in proof.exits) {
			if (proof.origins.has_receiver_borrow (value)) {
				throw new CfgError.INVALID_CFG ("function exit leaves a stored receiver text loan active");
			}
		}
		foreach (var view in proof.views) {
			if (!proof.origins.is_bounded (view)) {
				throw new CfgError.INVALID_CFG ("text slice requires stable deep backing origins");
			}
		}
		foreach (var returned in proof.returns) {
			if (!proof.origins.is_static (returned)) {
				throw new CfgError.INVALID_CFG ("text return: borrowed text cannot escape through a STATIC_TEXT result");
			}
		}
	}
}
}
