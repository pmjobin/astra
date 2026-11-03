// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Source;

namespace Astra.Ssa {
internal class SsaFormalEffectObligation : Object {
	internal SsaFunction function;
	internal int ordinal;
	internal uint required;
	internal bool factory;
	internal SsaFormalEffectObligation (SsaFunction function, int ordinal, uint required, bool factory = false) {
		this.function = function;
		this.ordinal = ordinal;
		this.required = required;
		this.factory = factory;
	}

}

// This consumer does not call effect inference or rebuild its fixed point.
// Each consumed promise creates a use obligation. Reverse definitions identify
// the actual formal; a worklist checks transitive callees and every body path.
public class SsaFormalEffectVerifier : Object {
	private SsaProgram program;
	private GenericArray<SsaFormalEffectObligation> pending = new GenericArray<SsaFormalEffectObligation> ();
	private HashTable<string, bool> visited = new HashTable<string, bool> (str_hash, str_equal);
	private SsaFormalEffectVerifier (SsaProgram program) {
		this.program = program;
	}

	private static void require(bool condition, string message) throws SsaError {
		if (!condition) {
			throw new SsaError.INVALID_SSA ("formal effect consumer: " + message);
		}
	}

	private static bool scalar(SemanticType type) {
		return type.kind == TypeKind.BOOL || type is IntegerType || type is FloatingType || type is VectorType;
	}

	private void enqueue(SsaFunction function, int ordinal, uint required, bool factory = false) throws SsaError {
		require (function.ordinal >= 0 && function.ordinal < program.functions.length && program.functions[function.ordinal] == function,
			"callee has no exact current program identity");
		var facts = function.effect_facts;
		require (facts != null && facts.valid () && facts.parameter_count == function.parameters.length, "missing or malformed exact formal inventory");
		var getter = function as SsaPropertyGetter;
		if (factory) {
			require (ordinal == -1 && getter != null && getter.property_member.is_lazy, "factory promise has no lazy initializer body");
		} else if (getter != null && getter.property_member.is_lazy) {
			require ((required & 6U) == 0, "ordinary lazy gate writes cache state");
		}
		uint supplied;
		if (ordinal == -2) {
			supplied = facts.flags & FunctionEffectFacts.NO_EXTERNAL_MEMORY;
		} else if (ordinal == -1) {
			require (function.implicit_receiver != null, "receiver promise has no receiver");
			supplied = facts.flags & 3;
			if (factory && (facts.flags & FunctionEffectFacts.LAZY_READONLY_FACTORY) != 0) {
				supplied |= 2;
			}
		} else {
			require (ordinal >= 0 && ordinal < function.parameters.length, "formal ordinal is outside the typed signature");
			var parameter = function.parameters[ordinal];
			require (parameter.semantic_type is ClassType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE,
				"capture/read promise requires its exact borrowed Class formal");
			supplied = facts.parameter (ordinal);
		}
		require ((supplied & required) == required, "callee supplies no required formal or memory promise");
		string key = "%d/%d/%u/%d".printf (function.ordinal, ordinal, required, factory ? 1 : 0);
		if (visited.contains (key)) {
			return;
		}
		visited.insert (key, true);
		pending.add (new SsaFormalEffectObligation (function, ordinal, required, factory));
	}

	private void domain(SsaFunction function) throws SsaError {
		require (function.async_body == null && function.throws_type == null && !function.utf8_factory && function.owned_cleanup == null &&
			function.object_storage.length == 0 && function.heap_owners.length == 0 && function.buffer_storage.length == 0 && function.enum_slots.length == 0 &&
			function.struct_parameters.length == 0 && function.buffer_parameters.length == 0 &&
			(function.return_type.kind == TypeKind.VOID || scalar (function.return_type)), "unproved body or hidden cleanup domain");
		foreach (var parameter in function.parameters) {
			if (scalar (parameter.semantic_type)) {
				continue;
			}
			require (parameter.semantic_type is ClassType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE,
				"unproved non-scalar formal");
			foreach (var owner in program.classes) {
				if (owner.semantic_type != parameter.semantic_type) {
					continue;
				}
				require (owner.concurrency_policy == null && owner.allocation_policy == null, "formal has runtime policy effects");
			}
		}
		if (function.implicit_receiver == null) {
			return;
		}
		SsaNativeInstance? receiver = null;
		foreach (var owner in program.native_instances ()) {
			if (owner.semantic_type == function.implicit_receiver.contract.instance_type) {
				receiver = owner;
			}
		}
		require (receiver != null, "receiver has no exact nominal layout");
		var object_class = receiver as SsaClass;
		require (object_class == null || object_class.concurrency_policy == null, "receiver has hidden concurrency effects");
		if (!(function is SsaLifecycle)) {
			return;
		}
		var owners = new GenericArray<SsaNativeInstance> ();
		owners.add (receiver);
		for (var parent = object_class == null ? null : object_class.parent_class; parent != null; parent = parent.parent_class) {
			owners.add (parent);
		}
		foreach (var owner in owners) {
			foreach (var field in owner.fields) {
				require (scalar (field.semantic_type) && field.owned_cleanup == null && field.slots_cleanup == null, "implicit lifecycle cleanup is unproved");
			}
			foreach (var property in owner.properties) {
				require (!property.is_owned_lazy && scalar (property.semantic_type), "implicit property lifecycle is unproved");
			}
		}
	}

	private static SsaValue? origin(SsaFunction function, SsaValue value, HashTable<SsaValue, SsaInstruction> definitions) throws SsaError {
		var path = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
		while (true) {
			if (value == function.implicit_receiver || value is SsaFunctionParameter && function.parameters.find ((SsaFunctionParameter) value)) {
				return value;
			}
			require (!path.contains (value), "cyclic pointer definition");
			path.insert (value, true);
			var definition = definitions.lookup (value);
			if (definition is SsaObjectValidateInstruction) {
				value = ((SsaObjectValidateInstruction) definition).reference;
			} else if (definition is SsaClassUpcast) {
				value = ((SsaClassUpcast) definition).reference;
			} else {
				return null;
			}
		}
	}

	private static bool pure_scalar(SsaInstruction instruction, bool memory_none) {
		if (instruction.result != null && !scalar (instruction.result.semantic_type)) {
			return false;
		}
		var binary = instruction as SsaBinaryInstruction;
		if (binary != null && (!scalar (binary.left.semantic_type) || !scalar (binary.right.semantic_type))) {
			return false;
		}
		var prefix = instruction as SsaPrefixInstruction;
		if (prefix != null && !scalar (prefix.operand.semantic_type)) {
			return false;
		}
		if (memory_none) {
			if (binary != null && (binary.left.semantic_type is IntegerType || binary.left.semantic_type is VectorType && ((VectorType) binary.left.semantic_type).element_type is IntegerType)) {
				return false;
			}
			if (instruction is SsaPrefixInstruction || instruction is SsaIntegerShiftInstruction || instruction is SsaNumericGuard ||
			    instruction is SsaNumericConversionInstruction || instruction is SsaFloatConversionInstruction || instruction is SsaIntegerConversionInstruction ||
			    instruction is SsaVectorExtractInstruction || instruction is SsaVectorInsertInstruction || instruction is SsaDspInstruction ||
			    instruction is SsaVectorDotInstruction || instruction is SsaVectorReductionInstruction) {
				return false;
			}
		}
		return instruction is SsaPrefixInstruction || instruction is SsaBinaryInstruction || instruction is SsaIntegerShiftInstruction ||
		       instruction is SsaNumericGuard || instruction is SsaNumericConversionInstruction || instruction is SsaFloatConversionInstruction ||
		       instruction is SsaIntegerConversionInstruction || instruction is SsaDspInstruction || instruction is SsaVectorDotInstruction ||
		       instruction is SsaVectorSplatInstruction || instruction is SsaVectorExtractInstruction || instruction is SsaVectorInsertInstruction ||
		       instruction is SsaVectorShuffleInstruction || instruction is SsaVectorSelectInstruction || instruction is SsaVectorConstructInstruction || instruction is SsaVectorReductionInstruction;
	}

	private void body(SsaFormalEffectObligation proof) throws SsaError {
		var function = proof.function;
		if (function.native_declaration != null || function.span.file.native_interface || function.module_import_symbol != null) {
			var evidence = function.checked_native_effects ();
			require (!proof.factory && evidence != null && evidence.same (function.effect_facts), "import lacks exact checked native object evidence");
			return;
		}
		domain (function);
		bool memory_none = proof.ordinal == -2, readonly = memory_none || (proof.required & 2) != 0;
		if (memory_none) {
			require ((function.floating_policy & 6U) == 0, "checked FP traps are external effects");
		}
		SsaValue? root = proof.ordinal == -1 ? (SsaValue?) function.implicit_receiver : proof.ordinal >= 0 ? (SsaValue?) function.parameters[proof.ordinal] : null;
		var definitions = new HashTable<SsaValue, SsaInstruction> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction.result != null) {
					definitions.insert (instruction.result, instruction);
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var parameter in block.parameters) {
				require (scalar (parameter.semantic_type), "unproved pointer block argument");
			}
			require (block.terminator is SsaBranch || block.terminator is SsaConditionalBranch || block.terminator is SsaReturn || block.terminator is SsaFunctionEnd, "unproved control transfer");
			var returned = block.terminator as SsaReturn;
			require (returned == null || returned.value == null || scalar (returned.value.semantic_type), "result can expose an address");
			foreach (var instruction in block.instructions) {
				var validation = instruction as SsaObjectValidateInstruction;
				if (validation != null) {
					require (!memory_none && origin (function, validation.reference, definitions) != null, "unproved null refusal");
					continue;
				}
				var upcast = instruction as SsaClassUpcast;
				if (upcast != null) {
					require (origin (function, upcast.reference, definitions) != null, "unproved pointer cast");
					continue;
				}
				var load = instruction as SsaLoadInstruction;
				if (load != null) {
					require (!load.volatile_enabled && scalar (load.result.semantic_type), "observable or pointer-valued load");
					var field = load.source as SsaIndirectFieldPlace;
					require (load.source is SsaLocalMemoryPlace || !memory_none && field != null && origin (function, field.pointer, definitions) != null, "unproved memory read");
					continue;
				}
				var store = instruction as SsaStoreInstruction;
				var initialize = instruction as SsaInitializeInstruction;
				if (store != null || initialize != null) {
					var place = store == null ? initialize.target : store.target;
					var value = store == null ? initialize.value : store.value;
					require ((store == null || !store.volatile_enabled) && scalar (value.semantic_type) && scalar (place.semantic_type), "store can expose an address or volatile effect");
					var field = place as SsaIndirectFieldPlace;
					require (place is SsaLocalMemoryPlace || !readonly && field != null && origin (function, field.pointer, definitions) != null, "write can modify an aliased formal");
					continue;
				}
				var foreign = instruction as SsaCCallInstruction;
				if (foreign != null) {
					require (!readonly, "unknown foreign memory effects");
					foreach (var argument in foreign.arguments) {
						require (scalar (argument.semantic_type), "unknown foreign capture");
					}
					require (foreign.result == null || scalar (foreign.result.semantic_type), "unknown foreign pointer result");
					continue;
				}
				var call = instruction as SsaCallInstruction;
				if (call != null) {
					require (call.target != null && call.target.dispatch_kind == ClassDispatchKind.DIRECT && call.target.async_body == null && call.target.throws_type == null &&
						(call.result == null || scalar (call.result.semantic_type)), "unproved call target, suspension, error or address result");
					bool pointers = call.receiver != null;
					if (call.receiver != null) {
						var actual = origin (function, call.receiver, definitions);
						require (actual != null && !memory_none, "unproved receiver use");
						uint required = (actual == root && (proof.required & 1) != 0 ? 1U : 0U) | (readonly ? 2U : 0U);
						if (required != 0) {
							enqueue (call.target, -1, required);
						}
					}
					for (int p = 0; p < call.arguments.length; p++) {
						if (scalar (call.arguments[p].semantic_type)) {
							continue;
						}
						var actual = origin (function, call.arguments[p], definitions);
						require (actual != null && !memory_none, "unproved pointer argument");
						pointers = true;
						uint required = (actual == root && (proof.required & 1) != 0 ? 1U : 0U) | (readonly ? 2U : 0U);
						if (required != 0) {
							enqueue (call.target, p, required);
						}
					}
					if (readonly && !pointers) {
						enqueue (call.target, -2, FunctionEffectFacts.NO_EXTERNAL_MEMORY);
					}
					continue;
				}
				require (pure_scalar (instruction, memory_none), "unknown instruction or trap effect");
			}
		}
	}

	public static void verify(SsaProgram program) throws SsaError {
		var consumer = new SsaFormalEffectVerifier (program);
		foreach (var function in program.functions) {
			var facts = function.effect_facts;
			if (facts == null) {
				continue;
			}
			require (facts.valid () && facts.parameter_count == function.parameters.length, "malformed original facts");
			if ((facts.flags & 3) != 0) {
				consumer.enqueue (function, -1, facts.flags & 3);
			}
			if ((facts.flags & FunctionEffectFacts.LAZY_READONLY_FACTORY) != 0) {
				consumer.enqueue (function, -1, 2, true);
			}
			if ((facts.flags & FunctionEffectFacts.NO_EXTERNAL_MEMORY) != 0) {
				consumer.enqueue (function, -2, FunctionEffectFacts.NO_EXTERNAL_MEMORY);
			}
			for (int p = 0; p < facts.parameter_count; p++) {
				if (facts.parameter (p) != 0) {
					consumer.enqueue (function, p, facts.parameter (p));
				}
			}
		}
		for (int p = 0; p < consumer.pending.length; p++) {
			consumer.body (consumer.pending[p]);
		}
	}

}
}
