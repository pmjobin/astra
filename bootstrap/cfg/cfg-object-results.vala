// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
// Compiler-owned input, separate from lexical allocations and source parameters.
public class CfgResultObjectStorage : CfgValue {
	private WeakRef class_identity;
	public CfgClass? object_class { owned get { return (CfgClass?) class_identity.get (); } }
	internal CfgResultObjectStorage (SourceSpan span, CfgClass object_class) {
		base (span, object_class.semantic_type);
		this.class_identity = WeakRef (object_class);
	}
}

public class CfgResultStorageReceiverValue : CfgValue {
	public CfgResultObjectStorage storage { get; private set; }
	internal CfgResultStorageReceiverValue (SourceSpan span, CfgResultObjectStorage storage, ReceiverType contract) {
		base (span, contract);
		this.storage = storage;
	}
}

public class CfgResultConstructionInstruction : CfgCallInstruction {
	public CfgResultObjectStorage storage { get; private set; }
	internal CfgResultConstructionInstruction (SourceSpan span, CfgConstructor constructor, CfgResultObjectStorage storage, GenericArray<CfgValue> arguments) {
		base (span, constructor, arguments, null, new CfgResultStorageReceiverValue (span, storage, constructor.receiver.contract));
		this.storage = storage;
	}
}
// Caller roots are reconstructed from CFG calls, acquisitions and transfers.
// No Core summary or source ownership marker participates in this proof.
internal class CfgCallerResultOrigins : Object {
	private HashTable<CfgFunction, GenericResultOrigins> results = new HashTable<CfgFunction, GenericResultOrigins> (direct_hash, direct_equal);
	private HashTable<CfgCallResultValue, CfgCallInstruction> calls = new HashTable<CfgCallResultValue, CfgCallInstruction> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, CfgValue> evaluations = new HashTable<CfgEvaluatedValue, CfgValue> (direct_hash, direct_equal);
	private HashTable<CfgFunction, HashTable<CfgLocalPlace, GenericResultOrigins>> locals = new HashTable<CfgFunction, HashTable<CfgLocalPlace, GenericResultOrigins>> (direct_hash, direct_equal);

	internal CfgCallerResultOrigins (CfgProgram program) {
		foreach (var function in program.functions) {
			bool complete = function.blocks.find (function.entry);
			foreach (var block in function.blocks) {
				complete &= block.is_complete;
			}
			if (complete && function.return_type is ClassType && function.owned_cleanup != null && !function.heap_result && !function.declaration_only ()) {
				results.insert (function, new GenericResultOrigins ());
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as CfgCallInstruction;
					if (call != null && call.result != null) {
						calls.insert (call.result, call);
					}
					var evaluation = instruction as CfgEvaluateInstruction;
					if (evaluation != null) {
						evaluations.insert (evaluation.result, evaluation.value);
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
		locals.remove_all ();
	}
	private GenericResultOrigins local(CfgLocalPlace place, HashTable<CfgLocalPlace, GenericResultOrigins> values) {
		return values.lookup (place) ?? new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
	}
	private GenericResultOrigins value(CfgValue? operand, HashTable<CfgLocalPlace, GenericResultOrigins> values) {
		if (operand == null || operand is CfgNullPointerValue) {
			return new GenericResultOrigins ();
		}
		var parameter = operand as CfgParameterValue;
		if (parameter != null) {
			return new GenericResultOrigins (0, new int[] { parameter.parameter.ordinal });
		}
		var load = operand as CfgLoadValue;
		if (load != null && load.source is CfgLocalPlace) {
			return local ((CfgLocalPlace) load.source, values);
		}
		var pending = operand as CfgPendingOwnedArgument;
		if (pending != null && pending.source != null) {
			return local (pending.source, values);
		}
		var evaluated = operand as CfgEvaluatedValue;
		var expression = evaluated == null ? null : evaluations.lookup (evaluated);
		if (expression != null) {
			return value (expression, values);
		}
		var call_result = operand as CfgCallResultValue;
		var call = call_result == null ? null : calls.lookup (call_result);
		if (call != null) {
			if (call.target.heap_result) {
				return new GenericResultOrigins (GenericResultOrigins.HEAP);
			}
			if (call.target.dispatch_kind != ClassDispatchKind.DIRECT) {
				return new GenericResultOrigins (GenericResultOrigins.CALLER);
			}
			var equation = results.lookup (call.target);
			if (equation == null) {
				return new GenericResultOrigins (GenericResultOrigins.CALLER);
			}
			var arguments = new GenericArray<GenericResultOrigins> ();
			foreach (var argument in call.arguments) {
				arguments.add (value (argument, values));
			}
			return equation.compose (arguments);
		}
		if (operand is CfgResultObjectStorage) {
			return new GenericResultOrigins (GenericResultOrigins.CALLER);
		}
		var reference = operand as CfgObjectReferenceValue;
		if (reference != null) {
			return new GenericResultOrigins (reference.storage.heap_allocated ? GenericResultOrigins.HEAP : GenericResultOrigins.CALLER);
		}
		return new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
	}
	private static bool merge(HashTable<CfgLocalPlace, GenericResultOrigins> values, CfgLocalPlace place, GenericResultOrigins incoming) {
		var prior = values.lookup (place) ?? new GenericResultOrigins ();
		var combined = prior.union (incoming);
		if (prior.same (combined)) {
			return false;
		}
		values.insert (place, combined);
		return true;
	}
	private GenericResultOrigins analyze(CfgFunction function) {
		var values = new HashTable<CfgLocalPlace, GenericResultOrigins> (direct_hash, direct_equal);
		foreach (var place in function.locals) {
			GenericResultOrigins equation;
			if (place.incoming_parameter != null) {
				equation = new GenericResultOrigins (0, new int[] { place.incoming_parameter.ordinal });
			} else if (place.cleanup != null && place.cleanup.is_heap_object) {
				equation = new GenericResultOrigins (GenericResultOrigins.HEAP);
			} else if (place.object_storage != null) {
				equation = new GenericResultOrigins (GenericResultOrigins.CALLER);
			} else {
				equation = new GenericResultOrigins ();
			}
			values.insert (place, equation);
		}
		bool changed = false;
		do {
			changed = false;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var initialization = instruction as CfgInitialize;
					if (initialization != null && initialization.acquisition != null) {
						changed |= merge (values, initialization.acquisition, value (initialization.value, values));
					}
					var transfer = instruction as CfgOwnershipTransferInstruction;
					if (transfer != null) {
						changed |= merge (values, transfer.destination, local (transfer.source, values));
					}
				}
			}
		} while (changed);
		var result = new GenericResultOrigins ();
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var returned = instruction as CfgOwnershipReturnInstruction;
				if (returned == null) {
					continue;
				}
				result = result.union (returned.result.source == null ? value (returned.result.producer, values) : local (returned.result.source, values));
			}
		}
		locals.insert (function, values);
		return result;
	}
	internal GenericResultOrigins inputs(CfgFunction function, CfgLocalPlace owner) {
		var values = locals.lookup (function);
		if (values == null) {
			analyze (function);
			values = locals.lookup (function);
		}
		return local (owner, values);
	}
}

}
