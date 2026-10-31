// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Source;
using Astra.Code;

namespace Astra.Ssa {
// Conservative body analysis. No annotation, imported prototype, raw pointer,
// callback, suspension or unknown instruction supplies an optimizer promise.
public class SsaEffectAnalysis : Object {
	private static bool scalar(SemanticType type) {
		return type.kind == TypeKind.BOOL || type is IntegerType || type is FloatingType || type is VectorType;
	}
	private static bool receiver_domain(SsaProgram program, SsaFunction function) {
		if (function.implicit_receiver == null) {
			return true;
		}
		var type = function.implicit_receiver.contract.instance_type;
		foreach (var owner in program.native_instances ()) {
			if (owner.semantic_type != type) {
				continue;
			}
			var object_class = owner as SsaClass;
			// Guards, affinity checks and lifetime policies add observable runtime
			// effects after SSA. A copied getter body cannot erase those effects
			// or grant its callers memory(none)/readonly promises.
			if (object_class != null && object_class.concurrency_policy != null) {
				return false;
			}
			// Ordinary methods have no implicit field cleanup. Their explicit
			// instructions below must independently prove every access/call.
			if (!(function is SsaLifecycle)) {
				return true;
			}
			for (var parent = object_class == null ? null : object_class.parent_class; parent != null; parent = parent.parent_class) {
				foreach (var field in parent.fields) {
					if (!scalar (field.semantic_type) || field.owned_cleanup != null || field.slots_cleanup != null) {
						return false;
					}
				}
				foreach (var property in parent.properties) {
					if (property.is_owned_lazy || !scalar (property.semantic_type)) {
						return false;
					}
				}
			}
			foreach (var field in owner.fields) {
				if (!scalar (field.semantic_type) || field.owned_cleanup != null || field.slots_cleanup != null) {
					return false;
				}
			}
			foreach (var property in owner.properties) {
				if (property.is_owned_lazy || !scalar (property.semantic_type)) {
					return false;
				}
			}
			return true;
		}
		return false;
	}

	private static FunctionEffectFacts empty(SsaFunction function) {
		return new FunctionEffectFacts (0, new uint[function.parameters.length]);
	}
	private static FunctionEffectFacts derive(SsaProgram program, SsaFunction function, HashTable<SsaFunction, FunctionEffectFacts> known) {
		if (function.span.file.native_interface || function.module_import_symbol != null) {
			return function.checked_native_effects () ?? empty (function);
		}
		if (function.async_body != null || function.throws_type != null || function.utf8_factory || function.owned_cleanup != null || function.object_storage.length != 0 || function.heap_owners.length != 0 || function.buffer_storage.length != 0 || function.enum_slots.length != 0 || function.struct_parameters.length != 0 || function.buffer_parameters.length != 0 || (function.return_type.kind != TypeKind.VOID && !scalar (function.return_type)) || !receiver_domain (program, function)) {
			return empty (function);
		}
		var aliases = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
		var parameters = new uint[function.parameters.length];
		if (function.implicit_receiver != null) {
			aliases.insert (function.implicit_receiver, true);
		}
		for (int p = 0; p < function.parameters.length; p++) {
			var parameter = function.parameters[p];
			if (scalar (parameter.semantic_type)) {
				continue;
			}
			if (!(parameter.semantic_type is ClassType) || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
				return empty (function);
			}
			foreach (var owner in program.classes) {
				if (owner.semantic_type == parameter.semantic_type && (owner.concurrency_policy != null || owner.allocation_policy != null)) {
					return empty (function);
				}
			}
			aliases.insert (parameter, true);
			parameters[p] = 1;
		}
		for (int pass = 0; pass <= function.blocks.length; pass++) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var upcast = instruction as SsaClassUpcast;
					if (upcast != null && aliases.contains (upcast.reference)) {
						aliases.insert (upcast.result, true);
					}
					var validation = instruction as SsaObjectValidateInstruction;
					if (validation != null && aliases.contains (validation.reference)) {
						aliases.insert (validation.result, true);
					}
				}
			}
		}
		bool reads = false;
		bool writes = function is SsaLifecycle;
		bool unknown_memory = false;
		// Ordinary borrowed formals may alias. Any possible write/unknown call
		// withholds readonly for every formal, without inventing disjointness.
		bool may_trap = (function.floating_policy & 6U) != 0;
		foreach (var block in function.blocks) {
			foreach (var parameter in block.parameters) {
				if (!scalar (parameter.semantic_type)) {
					return empty (function);
				}
			}
			if (!(block.terminator is SsaBranch || block.terminator is SsaConditionalBranch || block.terminator is SsaReturn || block.terminator is SsaFunctionEnd)) {
				return empty (function);
			}
			var returned = block.terminator as SsaReturn;
			if (returned != null && returned.value != null && !scalar (returned.value.semantic_type)) {
				return empty (function);
			}
			foreach (var instruction in block.instructions) {
				var validation = instruction as SsaObjectValidateInstruction;
				if (validation != null) {
					if (!aliases.contains (validation.reference)) {
						return empty (function);
					}
					may_trap = true;
					continue;
				}
				if (instruction is SsaClassUpcast) {
					if (!aliases.contains (instruction.result)) {
						return empty (function);
					}
					continue;
				}
				var load = instruction as SsaLoadInstruction;
				if (load != null) {
					if (load.volatile_enabled || !scalar (load.result.semantic_type)) {
						return empty (function);
					}
					var field = load.source as SsaIndirectFieldPlace;
					if (field != null && aliases.contains (field.pointer)) {
						reads = true;
						continue;
					}
					if (load.source is SsaLocalMemoryPlace && scalar (load.source.semantic_type)) {
						continue;
					}
					return empty (function);
				}
				var store = instruction as SsaStoreInstruction;
				if (store != null) {
					if (store.volatile_enabled || !scalar (store.value.semantic_type)) {
						return empty (function);
					}
					var field = store.target as SsaIndirectFieldPlace;
					if (field != null && aliases.contains (field.pointer)) {
						writes = true;
						continue;
					}
					if (store.target is SsaLocalMemoryPlace && scalar (store.target.semantic_type)) {
						continue;
					}
					return empty (function);
				}
				var foreign = instruction as SsaCCallInstruction;
				if (foreign != null) {
					foreach (var argument in foreign.arguments) {
						if (!scalar (argument.semantic_type)) {
							return empty (function);
						}
					}
					if (foreign.result != null && !scalar (foreign.result.semantic_type)) {
						return empty (function);
					}
					unknown_memory = true;
					continue;
				}
				var call = instruction as SsaCallInstruction;
				if (call != null) {
					if (call.target == null || call.target.async_body != null || call.target.throws_type != null || call.target.dispatch_kind != ClassDispatchKind.DIRECT || call.result != null && !scalar (call.result.semantic_type)) {
						return empty (function);
					}
					var effects = known.lookup (call.target);
					for (int p = 0; p < call.arguments.length; p++) {
						var argument = call.arguments[p];
						if (scalar (argument.semantic_type)) {
							continue;
						}
						if (!aliases.contains (argument) || effects == null || (effects.parameter (p) & 1) == 0) {
							return empty (function);
						}
						reads = true;
						if ((effects.parameter (p) & 2) == 0) {
							writes = true;
						}
					}
					if (call.receiver != null) {
						if (!aliases.contains (call.receiver) || effects == null || (effects.flags & FunctionEffectFacts.RECEIVER_NO_CAPTURE) == 0) {
							return empty (function);
						}
						reads = true;
						if ((effects.flags & FunctionEffectFacts.RECEIVER_READONLY) == 0) {
							writes = true;
						}
					} else if (effects == null || (effects.flags & FunctionEffectFacts.NO_EXTERNAL_MEMORY) == 0) {
						unknown_memory = true;
					}
					continue;
				}
				var binary = instruction as SsaBinaryInstruction;
				if (binary != null && (!scalar (binary.left.semantic_type) || !scalar (binary.right.semantic_type))) {
					return empty (function);
				}
				if ((binary != null && (binary.left.semantic_type is IntegerType || (binary.left.semantic_type is VectorType && ((VectorType) binary.left.semantic_type).element_type is IntegerType))) || instruction is SsaPrefixInstruction || instruction is SsaIntegerShiftInstruction || instruction is SsaNumericGuard || instruction is SsaNumericConversionInstruction || instruction is SsaFloatConversionInstruction || instruction is SsaIntegerConversionInstruction || instruction is SsaVectorExtractInstruction || instruction is SsaVectorInsertInstruction || instruction is SsaDspInstruction || instruction is SsaVectorDotInstruction || instruction is SsaVectorReductionInstruction) {
					may_trap = true;
				}
				if (instruction is SsaInitializeInstruction) {
					if (!scalar (((SsaInitializeInstruction) instruction).target.semantic_type)) {
						return empty (function);
					}
					continue;
				}
				if (!(instruction is SsaPrefixInstruction || instruction is SsaBinaryInstruction || instruction is SsaIntegerShiftInstruction || instruction is SsaNumericGuard || instruction is SsaNumericConversionInstruction || instruction is SsaFloatConversionInstruction || instruction is SsaIntegerConversionInstruction || instruction is SsaDspInstruction || instruction is SsaVectorDotInstruction || instruction is SsaVectorSplatInstruction || instruction is SsaVectorExtractInstruction || instruction is SsaVectorInsertInstruction || instruction is SsaVectorShuffleInstruction || instruction is SsaVectorSelectInstruction || instruction is SsaVectorConstructInstruction || instruction is SsaVectorReductionInstruction)) {
					return empty (function);
				}
				if (instruction.result != null && !scalar (instruction.result.semantic_type)) {
					return empty (function);
				}
			}
		}
		bool receiver = function.implicit_receiver != null;
		uint flags = receiver ? FunctionEffectFacts.RECEIVER_NO_CAPTURE : 0;
		if (!writes && !unknown_memory) {
			if (receiver) {
				flags |= FunctionEffectFacts.RECEIVER_READONLY;
			}
			for (int p = 0; p < parameters.length; p++) {
				if (parameters[p] != 0) {
					parameters[p] |= 2;
				}
			}
		}
		if (!reads && !writes && !unknown_memory && !may_trap) {
			flags |= FunctionEffectFacts.NO_EXTERNAL_MEMORY;
		}
		var getter = function as SsaPropertyGetter;
		if (getter != null && getter.property_member.is_lazy) {
			flags = FunctionEffectFacts.RECEIVER_NO_CAPTURE;
			if (!writes && !unknown_memory) {
				flags |= FunctionEffectFacts.LAZY_READONLY_FACTORY;
			}
		}
		return new FunctionEffectFacts (flags, parameters);
	}

	private static HashTable<SsaFunction, FunctionEffectFacts> infer(SsaProgram program) {
		var known = new HashTable<SsaFunction, FunctionEffectFacts> (direct_hash, direct_equal);
		for (uint pass = 0; pass <= program.functions.length; pass++) {
			bool changed = false;
			foreach (var function in program.functions) {
				var facts = derive (program, function, known);
				var previous = known.lookup (function);
				if (previous == null || !facts.same (previous)) {
					known.insert (function, facts);
					changed = true;
				}
			}
			if (!changed) {
				break;
			}
		}
		return known;
	}
	public static void annotate(SsaProgram program) {
		var known = infer (program);
		foreach (var function in program.functions) {
			function.effect_facts = known.lookup (function).copy ();
		}
	}
	public static void verify(SsaProgram program) throws SsaError {
		var known = infer (program);
		foreach (var function in program.functions) {
			if (function.effect_facts != null && (!function.effect_facts.valid () || !function.effect_facts.same (known.lookup (function)))) {
				throw new SsaError.INVALID_SSA ("derived effects no longer match the verified body or native-interface boundary");
			}
		}
	}

}
}

namespace Astra.Ssa {
public class SsaReadonlyInference : Object {
	private CodeEffectAnalysis effects;
	private SsaProgram program;
	public SsaReadonlyInference (SsaProgram program) {
		this.program = program;
		var origins = new SsaCodeOrigins (program);
		effects = create_effect_analysis (origins);
		foreach (var function in program.functions) {
			var parameters = new GenericArray<Object> ();
			var formals = new GenericArray<Object> ();
			for (int p = 0; p < function.parameters.length; p++) {
				var parameter = function.parameters[p];
				parameters.add (parameter);
				var signature = parameter.semantic_type as FunctionValueType;
				if (signature == null || !first_order (signature)) {
					continue;
				}
				bool record_leaf = false;
				foreach (var group in function.struct_parameters) {
					record_leaf |= p >= group.first_leaf && p < group.first_leaf + group.shape.leaves.length;
				}
				if (!record_leaf) {
					formals.add (parameter);
				}
			}
			var declaration = function.native_declaration;
			var positions = code_inputs (function);
			effects.add_function (function, parameters, formals,
				declaration == null ? null : CodeInputSet.decode (declaration.identity.scoped_readonly && new SsaScopedInspection (program, false).is_readonly (function),
					declaration.identity.readonly_inputs, (int) parameters.length, positions),
				declaration == null ? null : CodeInputSet.decode (true,
					declaration.identity.callback_inputs, (int) parameters.length, positions));
		}
		foreach (var function in program.functions) {
			var loans = new HashTable<SsaValue, SsaSlotsValueInstruction> (direct_hash, direct_equal);
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var loan = instruction as SsaSlotsValueInstruction;
					if (loan != null && loan.action == OwnerSlotsAction.BORROW) {
						loans.insert (loan.result, loan);
					}
				}
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					if (call == null || call.target == null) {
						continue;
					}
					bool protected_call = call.readonly_required;
					foreach (var argument in call.arguments) {
						protected_call |= loans.contains (argument) && (call.target.kind == CallableKind.METHOD || loans.lookup (argument).readonly_required);
					}
					effects.add_call (function, call.target, objects (call.arguments), protected_call);
				}
			}
		}
		effects.infer_readonly (probe_readonly);
	}
	private bool probe_readonly(Object function, CodeEffectSummary result) {
		return new SsaScopedInspection (program, false).infer ((SsaFunction) function, this, result);
	}
	// Vala shares closure storage within one method. Keep this long-lived
	// frontier separate from probes that capture the analysis or its owner.
	private static CodeEffectAnalysis create_effect_analysis(SsaCodeOrigins origins) {
		return new CodeEffectAnalysis ((value, formals) => origins.effect_frontier ((SsaValue) value, formals));
	}

	private static GenericArray<Object> objects(GenericArray<SsaValue> values) {
		var result = new GenericArray<Object> ();
		foreach (var value in values) {
			result.add (value);
		}
		return result;
	}
	public static GenericArray<int> code_inputs(SsaFunction function) {
		var result = new GenericArray<int> ();
		for (int p = 0; p < function.parameters.length; p++) {
			if (!(function.parameters[p].semantic_type is FunctionValueType)) {
				continue;
			}
			bool record_leaf = false;
			foreach (var group in function.struct_parameters) {
				record_leaf |= p >= group.first_leaf && p < group.first_leaf + group.shape.leaves.length;
			}
			if (!record_leaf) {
				result.add (p);
			}
		}
		return result;
	}
	private static bool first_order(FunctionValueType signature) {
		foreach (var type in signature.physical_parameters ()) {
			if (type is FunctionValueType) {
				return false;
			}
		}
		return true;
	}
	public CodeEffectSummary? summary(SsaFunction function) {
		return effects.readonly_summary (function);
	}
	internal bool code(SsaValue value, SsaFunction scope, CodeEffectSummary result, GenericArray<SsaValue>? arguments = null) {
		return effects.code (value, scope, result, arguments == null ? null : objects (arguments));
	}
	internal bool call(SsaFunction? target, GenericArray<SsaValue> arguments, SsaFunction scope, CodeEffectSummary result) {
		return target != null && effects.call (target, objects (arguments), scope, result);
	}
	internal void infer_requirements() {
		effects.infer_requirements ();
	}
	internal CodeEffectSummary? requirements(SsaFunction function) {
		return effects.required_summary (function);
	}
	internal static void verify_imported(SsaProgram program) throws SsaError {
		bool needed = false;
		foreach (var function in program.functions) {
			var declaration = function.native_declaration;
			needed |= declaration != null && (declaration.identity.readonly_inputs != "" || declaration.identity.callback_inputs != "");
		}
		if (!needed) {
			return;
		}
		var facts = new SsaReadonlyInference (program);
		var requirements = new SsaCallbackPreconditions (program, facts);
		foreach (var function in program.functions) {
			var required = requirements.summary (function);
			if (required == null || !required.eligible) {
				throw new SsaError.INVALID_SSA ("native callback inputs require independently proved readonly code");
			}
		}
	}
}

// Mandatory validity requirements remain distinct from readonly eligibility.
public class SsaCallbackPreconditions : Object {
	private SsaReadonlyInference facts;
	public SsaCallbackPreconditions (SsaProgram program, SsaReadonlyInference readonly_facts) {
		facts = readonly_facts;
		facts.infer_requirements ();
	}
	public CodeEffectSummary? summary(SsaFunction function) {
		return facts.requirements (function);
	}
}

// A loan protection proof, separate from optimizer memory attributes. Scalar
// foreign/code calls may have external effects without access to this owner.
public class SsaScopedInspection : Object {
	private SsaProgram program;
	private bool allow_code_targets;
	private SsaReadonlyInference? inference;
	private SsaFunction? inference_scope;
	private CodeEffectSummary? inference_result;
	private SsaCodeOrigins? code_origins;
	private HashTable<SsaFunction, bool> visited = new HashTable<SsaFunction, bool> (direct_hash, direct_equal);
	public SsaScopedInspection (SsaProgram program, bool allow_code_targets = true) {
		this.program = program;
		this.allow_code_targets = allow_code_targets;
	}
	private void reject(string reason) throws SsaError {
		throw new SsaError.INVALID_SSA ("readonly scoped inspector " + reason);
	}
	private GenericArray<SemanticType>? fields(SemanticType type) {
		foreach (var record in program.structs) {
			if (record.semantic_type != type) {
				continue;
			}
			var result = new GenericArray<SemanticType> ();
			foreach (var field in record.fields) {
				if (field.owned_cleanup != null) {
					return null;
				}
				result.add (field.semantic_type);
			}
			return result;
		}
		return null;
	}
	private bool copied(SemanticType type) {
		if (FunctionValueType.scalar (type) || type is FunctionValueType || type is StringType) {
			return true;
		}
		if (!(type is StructType)) {
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
	public bool copied_result(SemanticType type) {
		return type.kind == TypeKind.VOID || FunctionValueType.scalar (type) || type.is_struct_storage () && copied (type);
	}
	private bool local(SsaMemoryPlace place) {
		while (place is SsaFieldPlace && ((SsaFieldPlace) place).aggregate != null) {
			place = ((SsaFieldPlace) place).aggregate;
		}
		return place is SsaLocalMemoryPlace || place is SsaDirectFieldPlace;
	}
	internal bool infer(SsaFunction target, SsaReadonlyInference inference, CodeEffectSummary result) {
		this.inference = inference;
		inference_scope = target;
		inference_result = result;
		return is_readonly (target);
	}
	public bool is_readonly(SsaFunction target) {
		try {
			verify (target);
			return true;
		} catch (SsaError error) {
			// Failed recursive checks must never remain cached as proofs.
			visited.remove_all ();
			return false;
		}
	}

	public void verify(SsaFunction target) throws SsaError {
		if (!program.functions.find (target) || target.async_body != null || target.throws_type != null || target.dispatch_kind != ClassDispatchKind.DIRECT || target.result_contract == ResultOwnershipContract.OWNED_TRANSFER || target.buffer_parameters.length != 0 || target is SsaLifecycle) {
			reject ("requires a direct synchronous nonconsuming definition");
		}
		var getter = target as SsaPropertyGetter;
		if (getter != null && getter.property_member.is_lazy) {
			reject ("lazy access may mutate receiver storage");
		}
		foreach (var parameter in target.parameters) {
			if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				reject ("cannot consume an owner");
			}
		}
		if (target.struct_result != null && target.struct_result.mode == StructValueMode.MOVE_VALUE) {
			reject ("cannot consume owning record channels");
		}
		foreach (var group in target.struct_parameters) {
			if (group.shape.mode == StructValueMode.MOVE_VALUE) {
				reject ("cannot consume owning record channels");
			}
		}
		if (target.span.file.native_interface) {
			if (!target.declaration_only () || !target.native_declaration.identity.scoped_readonly) {
				reject ("requires its original native readonly effect contract");
			}
			return;
		}
		if (visited.contains (target)) {
			return;
		}
		visited.insert (target, true);
		foreach (var block in target.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction is SsaStoreInstruction) {
					var store = (SsaStoreInstruction) instruction;
					if (!local (store.target) || !copied (store.target.semantic_type)) {
						reject ("cannot write object fields or indirect storage");
					}
				} else if (instruction is SsaInitializeInstruction) {
					var initial = (SsaInitializeInstruction) instruction;
					if (!local (initial.target) || !copied (initial.target.semantic_type)) {
						reject ("initialization cannot change observed storage");
					}
				} else if (instruction is SsaCallInstruction) {
					var call = (SsaCallInstruction) instruction;
					if (inference == null) {
						verify (call.target);
					} else if (!inference.call (call.target, call.arguments, inference_scope, inference_result)) {
						reject ("unproved conditional direct call effect");
					}
				} else if (instruction is SsaCCallInstruction) {
					var call = (SsaCCallInstruction) instruction;
					foreach (var argument in call.arguments) {
						if (!copied (argument.semantic_type) || argument.semantic_type is FunctionValueType) {
							reject ("foreign arguments cannot expose mutable aliases");
						}
					}
					if (call.target.return_type.kind != TypeKind.VOID && !copied (call.target.return_type)) {
						reject ("foreign result cannot acquire a pointer or owner");
					}
				} else if (instruction is SsaFunctionValueCall) {
					var call = (SsaFunctionValueCall) instruction;
					var signature = (FunctionValueType) call.callee.semantic_type;
					bool aliases = false;
					foreach (var parameter in signature.physical_parameters ()) {
						aliases |= !FunctionValueType.scalar (parameter);
					}
					if (aliases) {
						if (inference != null) {
							if (!inference.code (call.callee, inference_scope, inference_result, call.arguments)) {
								reject ("unproved declarative callback origin or invocation context");
							}
							continue;
						}
						if (!allow_code_targets) {
							reject ("native export requires a declarative callback effect contract");
						}
						if (code_origins == null) {
							code_origins = new SsaCodeOrigins (program);
						}
						var targets = code_origins.targets (call.callee);
						if (targets == null) {
							reject ("indirect arguments require proved code targets");
						}
						foreach (var candidate in targets) {
							verify (candidate);
						}
					}
				} else if (instruction is SsaStructResultConsume) {
					var consumption = (SsaStructResultConsume) instruction;
					if (consumption.results.shape.mode != StructValueMode.COPY_VALUE && !(consumption.results.shape.mode == StructValueMode.BORROW_VALUE && consumption.use_kind == StructResultUseKind.OBSERVE)) {
						reject ("cannot consume owning record results");
					}
				} else if (instruction is SsaStructParameterBorrow) {
					if (((SsaStructParameterBorrow) instruction).parameter.shape.mode != StructValueMode.BORROW_VALUE) {
						reject ("record parameter observation cannot acquire cleanup");
					}
				} else if (instruction is SsaStructBoundaryAcquire) {
					var acquire = (SsaStructBoundaryAcquire) instruction;
					if (acquire.shape.mode != StructValueMode.COPY_VALUE || acquire.owners.length != 0 || acquire.projection != null) {
						reject ("record acquisition cannot change observed ownership");
					}
				} else if (instruction is SsaSlotsValueInstruction) {
					var query = (SsaSlotsValueInstruction) instruction;
					if (query.action != OwnerSlotsAction.LENGTH && query.action != OwnerSlotsAction.CAPACITY && query.action != OwnerSlotsAction.BORROW) {
						reject ("cannot mutate collection storage");
					}
				} else if (instruction is SsaHeapOwnerEvent) {
					if (((SsaHeapOwnerEvent) instruction).action != SsaHeapOwnerAction.READ) {
						reject ("cannot change ownership while inspecting");
					}
				} else if (!(instruction is SsaLoadInstruction || instruction is SsaBufferReadInstruction || instruction is SsaBufferBorrowInstruction || instruction is SsaSliceLengthInstruction || instruction is SsaSliceBoundsCheck || instruction is SsaValidatePlaceInstruction || instruction is SsaObjectValidateInstruction || instruction is SsaClassUpcast || instruction is SsaPrefixInstruction || instruction is SsaBinaryInstruction || instruction is SsaIntegerShiftInstruction || instruction is SsaNumericGuard || instruction is SsaIntegerConversionInstruction || instruction is SsaFloatConversionInstruction || instruction is SsaNumericConversionInstruction)) {
					reject ("unproved instruction effect: " + instruction.get_type ().name ());
				}
			}
			if (block.terminator is SsaStructReturn) {
				var returned = (SsaStructReturn) block.terminator;
				if (returned.shape.mode != StructValueMode.COPY_VALUE && !(returned.shape.mode == StructValueMode.BORROW_VALUE && target.result_contract == ResultOwnershipContract.RECEIVER_BORROW)) {
					reject ("cannot transfer an owning record result");
				}
			} else if (!(block.terminator is SsaReturn || block.terminator is SsaBranch || block.terminator is SsaConditionalBranch || block.terminator is SsaFunctionEnd)) {
				reject ("cannot suspend or expose a checked failure");
			}
		}
	}
}
}
