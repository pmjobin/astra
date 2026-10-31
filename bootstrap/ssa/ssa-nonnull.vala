// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Source;

namespace Astra.Ssa {
// Reconstruct reference proofs from SSA definitions and edge arguments. No
// source/Core/CFG facts or ABI attributes authorize a nonnull use here.
internal class SsaNonNull : Object {
	private SsaFunction function;
	private HashTable<SsaValue, SsaInstruction> definitions = new HashTable<SsaValue, SsaInstruction> (direct_hash, direct_equal);
	private HashTable<SsaBlock, NonNullFacts> outputs = new HashTable<SsaBlock, NonNullFacts> (direct_hash, direct_equal);
	private HashTable<SsaBlock, bool> reachable = new HashTable<SsaBlock, bool> (direct_hash, direct_equal);
	private GenericArray<Object> universe = new GenericArray<Object> ();
	private NonNullFacts state = new NonNullFacts ();
	private NonNullProjections projections = new NonNullProjections ();
	private bool validating;
	private void require(bool proven, SourceSpan span) throws SsaError {
		if (validating && state.reachable && !proven) {
			throw new SsaError.INVALID_SSA ("%s: SSA nonnull contract requires a current non-null proof", span.file.path);
		}
	}
	public static void verify(SsaProgram program) throws SsaError {
		foreach (var instance in program.native_instances ()) {
			foreach (var field in instance.fields) {
				if (field.requires_nonnull && (!(instance is SsaClass) || field.owned_cleanup == null || !NonNullReferenceTypes.supports (field.semantic_type) || instance.semantic_type is ExactGenericClassType || instance.semantic_type.is_parameterized ())) {
					throw new SsaError.INVALID_SSA ("nonnull field lost exact owned native Class field contract");
				}
			}
		}
		foreach (var imported in program.c_functions) {
			foreach (var parameter in imported.parameters) {
				if (parameter.requires_nonnull) {
					throw new SsaError.INVALID_SSA ("foreign nonnull contracts cannot be assumed");
				}
			}
		}
		foreach (var function in program.functions) {
			function.verify_nonnull_uses ();
			bool boundary = function.nonnull_result;
			bool needed = function.has_nonnull_uses || boundary;
			foreach (var parameter in function.parameters) {
				boundary = boundary || parameter.requires_nonnull;
				needed = needed || parameter.requires_nonnull;
				if (parameter.requires_nonnull && !NonNullReferenceTypes.supports (parameter.semantic_type)) {
					throw new SsaError.INVALID_SSA ("nonnull parameter requires exact Class or Resource");
				}
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					needed = needed || instruction is SsaNonNullUse;
					var initial = instruction as SsaInitializeInstruction;
					var store = instruction as SsaStoreInstruction;
					var target = initial != null ? initial.target : store != null ? store.target : null;
					needed = needed || (target is SsaFieldPlace && ((SsaFieldPlace) target).field.requires_nonnull);
					var call = instruction as SsaCallInstruction;
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
				throw new SsaError.INVALID_SSA ("nonnull contracts require direct native definitions");
			}
			if (function.nonnull_result && (!NonNullReferenceTypes.supports (function.return_type) || (function.result_contract != ResultOwnershipContract.OWNED_TRANSFER && function.result_contract != ResultOwnershipContract.RECEIVER_BORROW && !(function.return_type is FunctionValueType)))) {
				throw new SsaError.INVALID_SSA ("nonnull result lost exact owned/receiver-borrow Class or Resource contract");
			}
			foreach (var exported in program.c_exports) {
				if (boundary && exported.target == function) {
					throw new SsaError.INVALID_SSA ("nonnull signature cannot cross exported C boundary");
				}
			}
			var proof = new SsaNonNull ();
			proof.function = function;
			proof.run ();
		}
	}
	private Object receiver_key(SsaValue value) {
		var definition = definitions.lookup (value);
		if (definition is SsaObjectReferenceInstruction) {
			return ((SsaObjectReferenceInstruction) definition).storage;
		}
		if (definition is SsaObjectValidateInstruction) {
			return receiver_key (((SsaObjectValidateInstruction) definition).reference);
		}
		if (definition is SsaClassUpcast) {
			return receiver_key (((SsaClassUpcast) definition).reference);
		}
		return value;
	}
	private Object? property_key(SsaCallInstruction call) {
		var getter = call.target as SsaPropertyGetter;
		if (getter == null || call.receiver == null || !getter.property_member.is_borrowed || getter.property_member.is_lazy) {
			return null;
		}
		return projections.key (receiver_key (call.receiver), getter.property_member);
	}
	private bool known(SsaValue value) {
		return !(value is SsaNullPointerConstant) && (value is SsaFunctionAddress || value is SsaReceiver || state.knows (value));
	}
	private void refine(SsaValue value, bool truth) {
		state.assume (value, truth);
		if (value is SsaBooleanConstant) {
			if ((((SsaBooleanConstant) value).literal == BooleanLiteral.TRUE) != truth) {
				state.reachable = false;
			}
			return;
		}
		var instruction = definitions.lookup (value);
		if (instruction is SsaPrefixInstruction && ((SsaPrefixInstruction) instruction).operator_kind == PrefixOperator.NOT) {
			refine (((SsaPrefixInstruction) instruction).operand, !truth);
			return;
		}
		var binary = instruction as SsaBinaryInstruction;
		if (binary == null || (binary.operator_kind != BinaryOperator.EQUAL && binary.operator_kind != BinaryOperator.NOT_EQUAL) || (binary.operator_kind == BinaryOperator.NOT_EQUAL) != truth) {
			return;
		}
		SsaValue? pointer = (binary.left is SsaNullPointerConstant) ? binary.right : (binary.right is SsaNullPointerConstant) ? binary.left : null;
		if (pointer != null) {
			state.refine (pointer);
		}
	}
	private NonNullFacts assuming(NonNullFacts before, SsaValue value, bool truth) {
		var saved = state;
		state = before.copy ();
		refine (value, truth);
		var result = state;
		state = saved;
		return result;
	}
	private void kill_definitions(NonNullFacts facts, SsaBlock target) {
		// A loop executes the same static definitions again. Facts about the
		// previous iteration cannot authorize this iteration's phi/result.
		foreach (var parameter in target.parameters) {
			facts.assign (parameter, false);
		}
		foreach (var instruction in target.instructions) {
			if (instruction.result != null) {
				facts.assign (instruction.result, false);
			}
		}
	}
	private NonNullFacts edge(SsaBlock source, SsaEdge edge, bool? truth = null) {
		var prior = outputs.lookup (source).copy ();
		var branch = source.terminator as SsaConditionalBranch;
		if (branch != null && truth != null) {
			prior = assuming (prior, branch.condition, truth);
		}
		var result = prior.copy ();
		kill_definitions (result, edge.target);
		for (int i = 0; i < edge.arguments.length; i++) {
			var saved = state;
			state = prior;
			bool proven = known (edge.arguments[i]);
			state = saved;
			result.capture (edge.target.parameters[i], proven);
		}
		for (int i = 0; i < edge.arguments.length; i++) {
			var parameter = edge.target.parameters[i];
			if (parameter.semantic_type.kind == TypeKind.BOOL) {
				var yes = assuming (prior, edge.arguments[i], true);
				var no = assuming (prior, edge.arguments[i], false);
				kill_definitions (yes, edge.target);
				kill_definitions (no, edge.target);
				for (int p = 0; p < edge.arguments.length; p++) {
					var target = edge.target.parameters[p];
					if (!NonNullReferenceTypes.supports (target.semantic_type)) {
						continue;
					}
					var y = assuming (prior, edge.arguments[i], true);
					var n = assuming (prior, edge.arguments[i], false);
					if (y.knows (edge.arguments[p])) {
						yes.refine (target);
					}
					if (n.knows (edge.arguments[p])) {
						no.refine (target);
					}
				}
				result.boolean (parameter, yes, no);
			}
		}
		return result;
	}
	private NonNullFacts incoming(SsaBlock target) {
		if (target == function.entry) {
			var entry = new NonNullFacts ();
			foreach (var parameter in function.parameters) {
				entry.capture (parameter, parameter.requires_nonnull);
			}
			return entry;
		}
		var result = new NonNullFacts ();
		result.reachable = false;
		if (!reachable.contains (target)) {
			return result;
		}
		foreach (var source in function.blocks) {
			var branch = source.terminator as SsaBranch;
			var conditional = source.terminator as SsaConditionalBranch;
			if (branch != null && branch.edge.target == target) {
				result = NonNullFacts.join (result, edge (source, branch.edge));
			}
			if (conditional != null) {
				if (conditional.true_edge.target == target) {
					result = NonNullFacts.join (result, edge (source, conditional.true_edge, true));
				}
				if (conditional.false_edge.target == target) {
					result = NonNullFacts.join (result, edge (source, conditional.false_edge, false));
				}
			}
			var allocation = source.terminator as SsaBufferAllocationBranch;
			if (allocation != null) {
				if (allocation.success_edge.target == target) {
					result = NonNullFacts.join (result, edge (source, allocation.success_edge));
				}
				if (allocation.failure_edge.target == target) {
					result = NonNullFacts.join (result, edge (source, allocation.failure_edge));
				}
			}
			var dispatch = source.terminator as SsaEnumDispatch;
			if (dispatch != null) {
				foreach (var choice in dispatch.cases) {
					if (choice.edge.target == target) {
						result = NonNullFacts.join (result, edge (source, choice.edge));
					}
				}
				if (dispatch.invalid_edge.target == target) {
					result = NonNullFacts.join (result, edge (source, dispatch.invalid_edge));
				}
			}
		}
		return result;
	}
	private bool invalidates_projection(SsaInstruction node) {
		if (node is SsaCallInstruction) {
			return property_key ((SsaCallInstruction) node) == null;
		}
		if (node is SsaHeapOwnerEvent) {
			return ((SsaHeapOwnerEvent) node).action != SsaHeapOwnerAction.READ;
		}
		return node is SsaActorSend || node is SsaClosureBind || node is SsaClosureCall || node is SsaRetainedOperation || node is SsaSharedOperation || node is SsaCCallInstruction || node is SsaFunctionValueCall ||
		       node is SsaStoreInstruction || node is SsaInitializeInstruction || node is SsaAsyncDelay;
	}
	private void instruction(SsaInstruction node) throws SsaError {
		if (!state.reachable) {
			return;
		}
		var initial = node as SsaInitializeInstruction;
		var store = node as SsaStoreInstruction;
		var target = initial != null ? initial.target : store != null ? store.target : null;
		if (target is SsaFieldPlace && ((SsaFieldPlace) target).field.requires_nonnull) {
			require (known (initial != null ? initial.value : store.value), node.span);
		}
		if (node is SsaNonNullUse) {
			require (known (((SsaNonNullUse) node).value), node.span);
		}
		if (node is SsaCallInstruction) {
			var call = (SsaCallInstruction) node;
			for (int i = 0; i < call.arguments.length; i++) {
				if (call.target.parameters[i].requires_nonnull) {
					require (known (call.arguments[i]), call.arguments[i].span);
				}
			}
		}
		if (invalidates_projection (node)) {
			projections.invalidate (state);
		}
		if (node.result == null) {
			return;
		}
		bool proven = node is SsaObjectReferenceInstruction && !((SsaObjectReferenceInstruction) node).storage.fallible || node is SsaObjectValidateInstruction || node is SsaAddressOfInstruction;
		if (node is SsaLoadInstruction && ((SsaLoadInstruction) node).source is SsaFieldPlace) {
			proven = ((SsaFieldPlace) ((SsaLoadInstruction) node).source).field.requires_nonnull;
		}
		if (node is SsaClassUpcast) {
			proven = known (((SsaClassUpcast) node).reference);
		}
		if (node is SsaCallInstruction) {
			var call = (SsaCallInstruction) node;
			var projection = property_key (call);
			proven = call.exception_result == null && (call.target.nonnull_result || projection != null && state.knows (projection));
		}
		if (node is SsaCallSuccess) {
			proven = ((SsaCallSuccess) node).call.target.nonnull_result;
		}
		var before = state.copy ();
		state.capture (node.result, proven, (node is SsaCallInstruction) ? property_key ((SsaCallInstruction) node) : null);
		if (node.result.semantic_type.kind == TypeKind.BOOL) {
			state.boolean (node.result, assuming (before, node.result, true), assuming (before, node.result, false));
		}
	}
	private void transfer(SsaBlock block) throws SsaError {
		foreach (var node in block.instructions) {
			instruction (node);
		}
		var returned = block.terminator as SsaReturn;
		if (returned != null && !(returned is SsaExceptionReturn) && function.nonnull_result) {
			require (returned.value != null && known (returned.value), returned.span);
		}
	}
	private void run() throws SsaError {
		var pending = new GenericArray<SsaBlock> ();
		pending.add (function.entry);
		reachable.insert (function.entry, true);
		for (int i = 0; i < pending.length; i++) {
			foreach (var next in pending[i].terminator.successors ()) {
				if (!reachable.contains (next)) {
					reachable.insert (next, true);
					pending.add (next);
				}
			}
		}
		foreach (var parameter in function.parameters) {
			universe.add (parameter);
		}
		foreach (var block in function.blocks) {
			foreach (var parameter in block.parameters) {
				universe.add (parameter);
			}
			foreach (var node in block.instructions) {
				if (node.result != null) {
					universe.add (node.result);
					definitions.insert (node.result, node);
				}
			}
		}
		foreach (var block in function.blocks) {
			var top = new NonNullFacts ();
			top.reachable = reachable.contains (block);
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
			throw new SsaError.INVALID_SSA ("nonnull proof did not converge within its bounded fact domain");
		}
		validating = true;
		foreach (var block in function.blocks) {
			state = incoming (block);
			transfer (block);
		}
	}
}
}
