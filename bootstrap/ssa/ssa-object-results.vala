// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Ssa {
// Compiler-owned input, separate from lexical allocations and source parameters.
public class SsaResultObjectStorage : SsaValue {
	private WeakRef class_identity;
	public SsaClass? object_class { owned get { return (SsaClass?) class_identity.get (); } }
	internal SsaResultObjectStorage (SourceSpan span, SsaClass object_class) {
		base (span, object_class.semantic_type);
		this.class_identity = WeakRef (object_class);
	}
}

public class SsaResultStorageReceiverValue : SsaValue {
	public SsaResultObjectStorage storage { get; private set; }
	internal SsaResultStorageReceiverValue (SourceSpan span, SsaResultObjectStorage storage, ReceiverType contract) {
		base (span, contract);
		this.storage = storage;
	}
}

public class SsaResultConstructionInstruction : SsaCallInstruction {
	public SsaResultObjectStorage storage { get; private set; }
	internal SsaResultConstructionInstruction (SourceSpan span, SsaConstructor constructor, SsaResultObjectStorage storage, GenericArray<SsaValue> arguments) {
		base (span, null, -1, constructor, arguments, new SsaResultStorageReceiverValue (span, storage, constructor.receiver.contract));
		this.storage = storage;
	}
}
// Derive caller-backed return roots from this stage's actual values and calls.
internal class SsaCallerResultOrigins : Object {
	private HashTable<SsaFunction, GenericResultOrigins> results = new HashTable<SsaFunction, GenericResultOrigins> (direct_hash, direct_equal);
	private HashTable<SsaFunction, HashTable<SsaValue, GenericResultOrigins>> values = new HashTable<SsaFunction, HashTable<SsaValue, GenericResultOrigins>> (direct_hash, direct_equal);
	private HashTable<SsaValue, bool> definitions = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
	internal SsaCallerResultOrigins (SsaProgram program) {
		foreach (var function in program.functions) {
			bool complete = function.blocks.find (function.entry);
			foreach (var block in function.blocks) {
				complete &= block.is_complete;
			}
			if (complete && function.return_type is ClassType && function.owned_cleanup != null && !function.heap_result && !function.declaration_only ()) {
				results.insert (function, new GenericResultOrigins ());
			}
			foreach (var parameter in function.parameters) {
				definitions.insert (parameter, true);
			}
			foreach (var block in function.blocks) {
				foreach (var parameter in block.parameters) {
					definitions.insert (parameter, true);
				}
				foreach (var instruction in block.instructions) {
					if (instruction.result != null) {
						definitions.insert (instruction.result, true);
					}
				}
			}
		}
		bool changed = false;
		do {
			changed = false;
			foreach (var function in results.get_keys ()) {
				var equation = analyze (function);
				if (!results.lookup (function).same (equation)) {
					results.insert (function, equation);
					changed = true;
				}
			}
		} while (changed);
		values.remove_all ();
	}
	private GenericResultOrigins value(SsaValue? operand, HashTable<SsaValue, GenericResultOrigins> origins) {
		if (operand == null || operand is SsaNullPointerConstant) {
			return new GenericResultOrigins ();
		}
		if (operand is SsaResultObjectStorage) {
			return new GenericResultOrigins (GenericResultOrigins.CALLER);
		}
		return origins.lookup (operand) ?? new GenericResultOrigins (definitions.contains (operand) ? 0 : GenericResultOrigins.UNKNOWN);
	}
	private static bool merge(HashTable<SsaValue, GenericResultOrigins> origins, SsaValue result, GenericResultOrigins incoming) {
		var prior = origins.lookup (result) ?? new GenericResultOrigins ();
		var combined = prior.union (incoming);
		if (prior.same (combined)) {
			return false;
		}
		origins.insert (result, combined);
		return true;
	}
	private GenericResultOrigins call(SsaCallInstruction invoked, HashTable<SsaValue, GenericResultOrigins> origins) {
		if (invoked.target == null) {
			return new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
		}
		if (invoked.target.heap_result) {
			return new GenericResultOrigins (GenericResultOrigins.HEAP);
		}
		if (invoked.target.dispatch_kind != ClassDispatchKind.DIRECT) {
			return new GenericResultOrigins (GenericResultOrigins.CALLER);
		}
		var equation = results.lookup (invoked.target);
		if (equation == null) {
			return new GenericResultOrigins (GenericResultOrigins.CALLER);
		}
		var arguments = new GenericArray<GenericResultOrigins> ();
		foreach (var argument in invoked.arguments) {
			arguments.add (value (argument, origins));
		}
		return equation.compose (arguments);
	}
	private static GenericArray<SsaEdge> edges(SsaTerminator terminator) {
		var result = new GenericArray<SsaEdge> ();
		if (terminator is SsaBranch) {
			result.add (((SsaBranch) terminator).edge);
		} else if (terminator is SsaConditionalBranch) {
			var branch = (SsaConditionalBranch) terminator;
			result.add (branch.true_edge);
			result.add (branch.false_edge);
		} else if (terminator is SsaEnumDispatch) {
			var dispatch = (SsaEnumDispatch) terminator;
			foreach (var arm in dispatch.cases) {
				result.add (arm.edge);
			}
			result.add (dispatch.invalid_edge);
		} else if (terminator is SsaBufferAllocationBranch) {
			var allocation = (SsaBufferAllocationBranch) terminator;
			result.add (allocation.success_edge);
			result.add (allocation.failure_edge);
		}
		return result;
	}
	private GenericResultOrigins analyze(SsaFunction function) {
		var origins = new HashTable<SsaValue, GenericResultOrigins> (direct_hash, direct_equal);
		foreach (var parameter in function.parameters) {
			origins.insert (parameter, new GenericResultOrigins (0, new int[] { parameter.ordinal }));
		}
		bool changed = false;
		do {
			changed = false;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction.result == null || !(instruction.result.semantic_type is ClassType)) {
						continue;
					}
					GenericResultOrigins equation;
					if (instruction is SsaCallInstruction) {
						equation = call ((SsaCallInstruction) instruction, origins);
					} else if (instruction is SsaCallSuccess) {
						equation = call (((SsaCallSuccess) instruction).call, origins);
					} else if (instruction is SsaObjectReferenceInstruction) {
						equation = new GenericResultOrigins (((SsaObjectReferenceInstruction) instruction).storage.heap_allocated ? GenericResultOrigins.HEAP : GenericResultOrigins.CALLER);
					} else if (instruction is SsaClassUpcast) {
						equation = value (((SsaClassUpcast) instruction).reference, origins);
					} else if (instruction is SsaFallibleInputRestore) {
						equation = value (((SsaFallibleInputRestore) instruction).argument.value, origins);
					} else if (instruction is SsaFrameInputRestore) {
						equation = value (((SsaFrameInputRestore) instruction).argument.value, origins);
					} else {
						equation = new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
					}
					changed |= merge (origins, instruction.result, equation);
				}
				foreach (var edge in edges (block.terminator)) {
					if (edge.target == null) {
						continue;
					}
					for (int i = 0; i < int.min ((int) edge.arguments.length, (int) edge.target.parameters.length); i++) {
						if (edge.target.parameters[i].semantic_type is ClassType) {
							changed |= merge (origins, edge.target.parameters[i], value (edge.arguments[i], origins));
						}
					}
				}
			}
		} while (changed);
		var result = new GenericResultOrigins ();
		foreach (var block in function.blocks) {
			var returned = block.terminator as SsaOwnershipReturn;
			if (returned != null) {
				result = result.union (value (returned.value, origins));
			}
		}
		values.insert (function, origins);
		return result;
	}
	internal bool null_only(SsaFunction function, SsaValue operand) {
		var origins = values.lookup (function);
		if (origins == null) {
			analyze (function);
			origins = values.lookup (function);
		}
		var equation = value (operand, origins);
		return equation.domains == 0 && equation.input_count == 0;
	}
	internal bool incoming(SsaFunction function, SsaValue operand) {
		var origins = values.lookup (function);
		if (origins == null) {
			analyze (function);
			origins = values.lookup (function);
		}
		var equation = value (operand, origins);
		if (equation.domains != 0 || equation.input_count == 0) {
			return false;
		}
		for (int i = 0; i < equation.input_count; i++) {
			int ordinal = equation.input (i);
			if (ordinal < 0 || ordinal >= function.parameters.length) {
				return false;
			}
			var parameter = function.parameters[ordinal];
			if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || parameter.heap_object || parameter.semantic_type != operand.semantic_type) {
				return false;
			}
		}
		return true;
	}
}

}
