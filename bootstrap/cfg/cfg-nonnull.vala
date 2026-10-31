// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
// Stage-owned forward must analysis. It consumes CFG definitions/edges rather
// than semantic/Core facts; ordinary ownership validation remains separate.
internal class CfgNonNull : Object {
	private HashTable<CfgEvaluatedValue, CfgValue> definitions = new HashTable<CfgEvaluatedValue, CfgValue> (direct_hash, direct_equal);
	private GenericArray<Object> universe = new GenericArray<Object> ();
	private HashTable<CfgBlock, NonNullFacts> outputs = new HashTable<CfgBlock, NonNullFacts> (direct_hash, direct_equal);
	private CfgFunction function;
	private CfgReachabilityResult reachable;
	private NonNullFacts state = new NonNullFacts ();
	private NonNullProjections projections = new NonNullProjections ();
	private bool validating;
	private void fail(SourceSpan span, string reason) throws CfgError {
		throw new CfgError.INVALID_CFG ("%s", new Diagnostic (span, "CFG nonnull " + reason).format ());
	}
	private void require(bool proven, SourceSpan span) throws CfgError {
		if (validating && state.reachable && !proven) {
			fail (span, "contract requires a current non-null proof");
		}
	}
	private void remember(Object? key) {
		if (key != null && !universe.find (key)) {
			universe.add (key);
		}
	}
	private bool required(CfgPlace slot) {
		var local = slot as CfgLocalPlace;
		return (local != null && (local.requires_nonnull || (local.incoming_parameter != null && local.incoming_parameter.requires_nonnull))) || (slot is CfgIndirectFieldPlace && ((CfgIndirectFieldPlace) slot).field.requires_nonnull);
	}
	public static void verify(CfgProgram program) throws CfgError {
		foreach (var instance in program.native_instances ()) {
			foreach (var field in instance.fields) {
				if (field.requires_nonnull && (!(instance is CfgClass) || field.owned_cleanup == null || !NonNullReferenceTypes.supports (field.semantic_type) || instance.semantic_type is ExactGenericClassType || instance.semantic_type.is_parameterized ())) {
					throw new CfgError.INVALID_CFG ("nonnull field lost exact owned native Class field contract");
				}
			}
		}
		foreach (var imported in program.c_functions) {
			foreach (var parameter in imported.parameters) {
				if (parameter.requires_nonnull) {
					throw new CfgError.INVALID_CFG ("foreign nonnull contracts cannot be assumed");
				}
			}
		}
		foreach (var function in program.functions) {
			bool needed = function.nonnull_result;
			bool boundary = needed;
			foreach (var parameter in function.parameters) {
				needed = needed || parameter.requires_nonnull;
				boundary = boundary || parameter.requires_nonnull;
			}
			foreach (var local in function.locals) {
				needed = needed || local.requires_nonnull;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var initial = instruction as CfgInitialize;
					var store = instruction as CfgStore;
					var target = initial != null ? initial.target : store != null ? store.target : null;
					needed = needed || (target is CfgIndirectFieldPlace && ((CfgIndirectFieldPlace) target).field.requires_nonnull);
					var call = instruction as CfgCallInstruction;
					if (call != null && call.target != null) {
						foreach (var parameter in call.target.parameters) {
							needed = needed || parameter.requires_nonnull;
						}
					}
				}
			}
			if (!needed) {
				continue;
			}
			if (function.dispatch_kind != ClassDispatchKind.DIRECT) {
				throw new CfgError.INVALID_CFG ("nonnull contracts require direct native definitions");
			}
			if (function.nonnull_result && (!NonNullReferenceTypes.supports (function.return_type) || (function.result_contract != ResultOwnershipContract.OWNED_TRANSFER && function.result_contract != ResultOwnershipContract.RECEIVER_BORROW && !(function.return_type is FunctionValueType)))) {
				throw new CfgError.INVALID_CFG ("nonnull result lost exact owned/receiver-borrow Class or Resource contract");
			}
			foreach (var parameter in function.parameters) {
				if (parameter.requires_nonnull && !NonNullReferenceTypes.supports (parameter.semantic_type)) {
					throw new CfgError.INVALID_CFG ("nonnull parameter requires exact Class or Resource");
				}
			}
			foreach (var local in function.locals) {
				if (local.requires_nonnull && !NonNullReferenceTypes.supports (local.semantic_type)) {
					throw new CfgError.INVALID_CFG ("nonnull local requires exact Class or Resource");
				}
			}
			foreach (var exported in program.c_exports) {
				if (boundary && exported.target == function) {
					throw new CfgError.INVALID_CFG ("nonnull signature cannot cross exported C boundary");
				}
			}
			var proof = new CfgNonNull ();
			proof.function = function;
			proof.run ();
		}
	}
	private Object? backing(CfgValue value) {
		if (value is CfgReceiverValue) {
			return ((CfgReceiverValue) value).receiver;
		}
		if (value is CfgObjectReferenceValue) {
			return ((CfgObjectReferenceValue) value).storage;
		}
		if (value is CfgObjectValidateValue) {
			return backing (((CfgObjectValidateValue) value).reference);
		}
		if (value is CfgLoadValue) {
			var place = ((CfgLoadValue) value).source;
			return (place is CfgLocalPlace) ? place : null;
		}
		if (value is CfgParameterValue) {
			return ((CfgParameterValue) value).parameter;
		}
		if (value is CfgOwnedBorrowValue) {
			return ((CfgOwnedBorrowValue) value).source;
		}
		if (value is CfgClassUpcast) {
			return backing (((CfgClassUpcast) value).reference);
		}
		return state.backing (value);
	}
	private Object? property_key(CfgCallInstruction call) {
		var getter = call.target as CfgPropertyGetter;
		if (getter == null || call.receiver == null || !getter.property_member.is_borrowed || getter.property_member.is_lazy) {
			return null;
		}
		return projections.key (backing (call.receiver), getter.property_member);
	}
	private bool known(CfgValue value) {
		if (value is CfgNullPointerValue) {
			return false;
		}
		if (value is CfgObjectReferenceValue) {
			return !((CfgObjectReferenceValue) value).storage.fallible;
		}
		if (value is CfgStorageReceiverValue) {
			return !((CfgStorageReceiverValue) value).storage.fallible;
		}
		if (value is CfgFunctionAddress || value is CfgResultStorageReceiverValue || value is CfgReceiverValue || value is CfgObjectValidateValue || value is CfgCatchBorrow) {
			return true;
		}
		if (value is CfgClassUpcast) {
			return known (((CfgClassUpcast) value).reference);
		}
		if (value is CfgLoadValue) {
			var place = ((CfgLoadValue) value).source;
			return state.knows (place) || (place is CfgIndirectFieldPlace && ((CfgIndirectFieldPlace) place).field.requires_nonnull);
		}
		if (value is CfgParameterValue) {
			return state.knows (((CfgParameterValue) value).parameter);
		}
		if (value is CfgOwnedBorrowValue) {
			return state.knows (((CfgOwnedBorrowValue) value).source);
		}
		return state.knows (value);
	}
	private CfgValue expanded(CfgValue value) {
		var seen = new HashTable<CfgValue, bool> (direct_hash, direct_equal);
		while (value is CfgEvaluatedValue && definitions.contains ((CfgEvaluatedValue) value) && !seen.contains (value)) {
			seen.insert (value, true);
			value = definitions.lookup ((CfgEvaluatedValue) value);
		}
		return value;
	}
	private void refine(CfgValue input, bool truth) {
		state.assume (input, truth);
		var condition = expanded (input);
		if (condition is CfgLoadValue) {
			state.assume (((CfgLoadValue) condition).source, truth);
		}
		if (condition is CfgBooleanValue) {
			if ((((CfgBooleanValue) condition).literal == BooleanLiteral.TRUE) != truth) {
				state.reachable = false;
			}
			return;
		}
		if (condition is CfgPrefixValue && ((CfgPrefixValue) condition).operator_kind == PrefixOperator.NOT) {
			refine (((CfgPrefixValue) condition).operand, !truth);
			return;
		}
		var binary = condition as CfgBinaryValue;
		if (binary == null || (binary.operator_kind != BinaryOperator.EQUAL && binary.operator_kind != BinaryOperator.NOT_EQUAL) || (binary.operator_kind == BinaryOperator.NOT_EQUAL) != truth) {
			return;
		}
		CfgValue? pointer = (expanded (binary.left) is CfgNullPointerValue) ? binary.right : (expanded (binary.right) is CfgNullPointerValue) ? binary.left : null;
		if (pointer != null) {
			var key = backing (pointer);
			state.refine (pointer);
			if (key != null) {
				state.refine (key);
			}
		}
	}
	private NonNullFacts edge(CfgBlock source, CfgBlock target) {
		state = outputs.lookup (source).copy ();
		var branch = source.terminator as CfgConditionalBranch;
		if (branch != null && branch.true_target != branch.false_target) {
			refine (branch.condition, branch.true_target == target);
		}
		return state;
	}
	private NonNullFacts incoming(CfgBlock target) {
		if (!reachable.is_reachable (target)) {
			var dead = new NonNullFacts ();
			dead.reachable = false;
			return dead;
		}
		if (target == function.entry) {
			var initial = new NonNullFacts ();
			foreach (var parameter in function.parameters) {
				initial.assign (parameter, parameter.requires_nonnull);
			}
			return initial;
		}
		var merged = new NonNullFacts ();
		merged.reachable = false;
		foreach (var source in function.blocks) {
			foreach (var successor in source.terminator.successors ()) {
				if (successor == target) {
					merged = NonNullFacts.join (merged, edge (source, target));
				}
			}
		}
		return merged;
	}
	private void bind_boolean(Object target, CfgValue value, NonNullFacts before) {
		var after = state;
		state = before.copy ();
		refine (value, true);
		var yes = state;
		state = before.copy ();
		refine (value, false);
		var no = state;
		state = after;
		state.boolean (target, yes, no);
	}
	private void store(CfgPlace target, CfgValue value, SourceSpan span) throws CfgError {
		bool proven = known (value);
		if (required (target)) {
			require (proven, span);
		}
		projections.invalidate (state);
		var before = state.copy ();
		state.assign (target, proven);
		if (target.semantic_type.kind == TypeKind.BOOL) {
			bind_boolean (target, value, before);
		}
	}
	private void instruction(CfgInstruction node) throws CfgError {
		if (!state.reachable) {
			return;
		}
		if (node is CfgActorSend) {
			projections.invalidate (state);
			state.capture (((CfgActorSend) node).result, false);
			return;
		}
		if (node is CfgAsyncDelay || node is CfgOwnershipTransferInstruction || node is CfgOwnershipRearmInstruction || node is CfgOwnershipReleaseInstruction || node is CfgOwnedArgumentCapture || node is CfgResourceCapture || node is CfgOwnershipReturnInstruction || node is CfgCleanupInstruction || node is CfgSlotsAppend || node is CfgSlotsReplace) {
			projections.invalidate (state);
		}
		if (node is CfgCallSuccess) {
			var success = (CfgCallSuccess) node;
			bool proven = success.call != null && success.call.target.nonnull_result;
			state.capture (success.result, proven);
			if (success.call.result != null) {
				state.capture (success.call.result, proven);
			}
			return;
		}
		if (node is CfgEvaluateInstruction) {
			var evaluation = (CfgEvaluateInstruction) node;
			if (evaluation.value is CfgFunctionValueCall || evaluation.value is CfgClosureBind || evaluation.value is CfgClosureCall || evaluation.value is CfgRetainedOperation || evaluation.value is CfgSharedOperation) {
				projections.invalidate (state);
			}
			var source = backing (evaluation.value);
			bool proven = known (evaluation.value);
			var before = state.copy ();
			state.capture (evaluation.result, proven, source);
			if (evaluation.value.semantic_type.kind == TypeKind.BOOL) {
				bind_boolean (evaluation.result, evaluation.value, before);
			}
			if (node is CfgResourceCapture && ((CfgResourceCapture) node).source != null) {
				state.assign (((CfgResourceCapture) node).source, false);
			}
			if (node is CfgExceptionTake) {
				state.assign (((CfgExceptionTake) node).owner, false);
			}
			return;
		}
		if (node is CfgOwnedBorrowInstruction) {
			var borrow = ((CfgOwnedBorrowInstruction) node).result;
			state.capture (borrow, state.knows (borrow.source), borrow.source);
			return;
		}
		if (node is CfgInitialize) {
			var initial = (CfgInitialize) node;
			store (initial.target, initial.value, initial.span);
			return;
		}
		if (node is CfgStore) {
			var write = (CfgStore) node;
			store (write.target, write.value, write.span);
			return;
		}
		if (node is CfgOwnershipTransferInstruction) {
			var move = (CfgOwnershipTransferInstruction) node;
			bool proven = state.knows (move.source);
			if (required (move.destination)) {
				require (proven, move.span);
			}
			state.assign (move.source, false);
			state.assign (move.destination, proven);
			return;
		}
		if (node is CfgOwnershipRearmInstruction) {
			var rearm = (CfgOwnershipRearmInstruction) node;
			bool proven = rearm.source != null ? state.knows(rearm.source) : rearm.value != null && known (rearm.value);
			if (required (rearm.owner)) {
				require (proven, rearm.span);
			}
			if (rearm.source != null) {
				state.assign (rearm.source, false);
			}
			state.assign (rearm.owner, proven);
			return;
		}
		if (node is CfgOwnershipReleaseInstruction) {
			state.assign (((CfgOwnershipReleaseInstruction) node).owner, false);
			return;
		}
		if (node is CfgOwnedArgumentCapture) {
			var argument = ((CfgOwnedArgumentCapture) node).transfer;
			state.capture (argument, argument.source != null && state.knows (argument.source));
			if (argument.source != null) {
				state.assign (argument.source, false);
			}
			return;
		}
		if (node is CfgOwnedArgumentAbort) {
			var argument = ((CfgOwnedArgumentAbort) node).transfer;
			if (argument.source != null) {
				state.assign (argument.source, state.knows (argument));
			}
			return;
		}
		if (node is CfgOwnershipReturnInstruction) {
			var result = ((CfgOwnershipReturnInstruction) node).result;
			state.capture (result, result.source != null ? state.knows (result.source) : result.producer != null && known (result.producer));
			if (result.source != null) {
				state.assign (result.source, false);
			}
			return;
		}
		if (node is CfgCallInstruction) {
			var call = (CfgCallInstruction) node;
			var projection = property_key (call);
			bool observed = projection != null && state.knows (projection);
			for (int i = 0; i < call.arguments.length; i++) {
				if (call.target.parameters[i].requires_nonnull) {
					require (known (call.arguments[i]), call.arguments[i].span);
				}
			}
			if (projection == null) {
				projections.invalidate (state);
			}
			if (call.result != null) {
				state.capture (call.result, call.exception_result == null && (call.target.nonnull_result || observed), projection);
			}
			if (call.success_result != null) {
				state.capture (call.success_result, false);
			}
			return;
		}
		if (node is CfgCCallInstruction) {
			projections.invalidate (state);
			var call = (CfgCCallInstruction) node;
			if (call.result != null) {
				state.capture (call.result, false);
			}
			return;
		}
		if (node is CfgCleanupInstruction) {
			var slot = backing (((CfgCleanupInstruction) node).value);
			if (slot != null) {
				state.assign (slot, false);
			}
			return;
		}
		if (node is CfgStructResultConsume && ((CfgStructResultConsume) node).results.shape.mode == StructValueMode.COPY_VALUE) {
			return;
		}
		if (node is CfgAsyncDelay || node is CfgOwnedCallTransferCommit || node is CfgValidatePlace || node is CfgSlotsBorrow || node is CfgSlotsInitialize || node is CfgExceptionStamp || node is CfgGroupCallSuccess) {
			return;
		}
		if (node is CfgSlotsAppend) {
			state.assign (((CfgSlotsAppend) node).incoming, false);
			return;
		}
		if (node is CfgSlotsReplace) {
			state.assign (((CfgSlotsReplace) node).incoming, false);
			return;
		}
		if (validating) {
			fail (node.span, "proof excludes an unsupported effect shape in this definition (%s)".printf (node.get_type ().name ()));
		}
	}
	private void transfer(CfgBlock block) throws CfgError {
		foreach (var node in block.instructions) {
			instruction (node);
		}
		var returned = block.terminator as CfgReturn;
		if (returned != null && !(returned is CfgExceptionReturn) && function.nonnull_result) {
			require (returned.value != null && known (returned.value), returned.span);
		}
	}
	private void run() throws CfgError {
		reachable = CfgReachability.analyze (function);
		foreach (var parameter in function.parameters) {
			remember (parameter);
		}
		foreach (var local in function.locals) {
			remember (local);
		}
		foreach (var block in function.blocks) {
			foreach (var node in block.instructions) {
				var evaluation = node as CfgEvaluateInstruction;
				if (evaluation != null) {
					definitions.insert (evaluation.result, evaluation.value);
					remember (evaluation.result);
				}
				var call = node as CfgCallInstruction;
				if (call != null) {
					remember (call.result);
					remember (call.success_result);
				}
				if (node is CfgOwnedBorrowInstruction) {
					remember (((CfgOwnedBorrowInstruction) node).result);
				}
				if (node is CfgOwnedArgumentCapture) {
					remember (((CfgOwnedArgumentCapture) node).transfer);
				}
				if (node is CfgOwnershipReturnInstruction) {
					remember (((CfgOwnershipReturnInstruction) node).result);
				}
			}
		}
		foreach (var block in function.blocks) {
			var top = new NonNullFacts ();
			foreach (var key in universe) {
				top.capture (key, true);
			}
			outputs.insert (block, top);
		}
		bool converged = false;
		for (int round = 0; round < 4096 && !converged; round++) {
			converged = true;
			foreach (var block in function.blocks) {
				state = incoming (block);
				transfer (block);
				if (!state.same (outputs.lookup (block))) {
					outputs.insert (block, state.copy ());
					converged = false;
				}
			}
		}
		if (!converged) {
			fail (function.span, "proof did not converge within its bounded fact domain");
		}
		validating = true;
		foreach (var block in function.blocks) {
			state = incoming (block);
			transfer (block);
		}
	}
}
}
