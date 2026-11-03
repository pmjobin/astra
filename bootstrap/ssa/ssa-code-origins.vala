// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Ssa {
// Rebuild code-value flow from SSA definitions, storage and physical edges.
// Earlier representations do not supply target or effect authority.
internal class SsaCodeOrigins : Object {
	private Astra.Code.CodeOrigins graph = new Astra.Code.CodeOrigins ();
	private GenericArray<SsaFunctionValueCall> indirect_calls = new GenericArray<SsaFunctionValueCall> ();
	private SsaProgram program;
	internal SsaCodeOrigins (SsaProgram program) {
		this.program = program;
		foreach (var owner in program.native_instances ()) {
			foreach (var field in owner.fields) {
				if (field.semantic_type is FunctionValueType) {
					graph.storage (field);
				}
			}
		}
		foreach (var exported in program.c_exports) {
			if (exported.target == null) {
				continue;
			}
			foreach (var parameter in exported.target.parameters) {
				graph.unknown (parameter);
				opaque_type (parameter.semantic_type);
			}
		}
		foreach (var function in program.functions) {
			foreach (var parameter in function.parameters) {
				graph.parameter (parameter);
			}
			if (function.entry.terminator is SsaForeignReturn || function.entry.terminator is SsaForeignSignalReturn || function.native_declaration != null || function.name_span.file.native_interface) {
				graph.unknown (function);
				foreach (var parameter in function.parameters) {
					opaque_type (parameter.semantic_type);
				}
				opaque_type (function.return_type);
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is SsaStructBoundaryAcquire) {
						var acquired = (SsaStructBoundaryAcquire) instruction;
						record (acquired.shape, acquired.leaves);
					} else if (instruction is SsaRecordFieldCommit) {
						var committed = (SsaRecordFieldCommit) instruction;
						record (committed.shape, committed.leaves);
					} else if (instruction is SsaInitializeInstruction) {
						var initialized = (SsaInitializeInstruction) instruction;
						store (initialized.target, initialized.value);
					} else if (instruction is SsaStoreInstruction) {
						var stored = (SsaStoreInstruction) instruction;
						store (stored.target, stored.value);
					} else if (instruction is SsaLoadInstruction) {
						var loaded = (SsaLoadInstruction) instruction;
						var source = place (loaded.source);
						if (source == null) {
							graph.unknown (loaded.result);
						} else {
							graph.copy (loaded.result, source);
						}
					} else if (instruction is SsaCCallInstruction) {
						var invoked = (SsaCCallInstruction) instruction;
						foreach (var argument in invoked.arguments) {
							value (argument);
							opaque_type (argument.semantic_type);
						}
						opaque_type (invoked.target.return_type);
					} else if (instruction is SsaCallInstruction) {
						var invoked = (SsaCallInstruction) instruction;
						call (invoked.target, invoked.arguments);
						if (invoked.result != null) {
							if (invoked.target == null || invoked.target.dispatch_kind != ClassDispatchKind.DIRECT) {
								graph.unknown (invoked.result);
							} else {
								graph.copy (invoked.result, invoked.target);
							}
						}
					} else if (instruction is SsaFunctionValueCall) {
						var invoked = (SsaFunctionValueCall) instruction;
						indirect_calls.add (invoked);
						value (invoked.callee);
						foreach (var argument in invoked.arguments) {
							value (argument);
						}
						if (invoked.result != null) {
							graph.unknown (invoked.result);
						}
					} else if (instruction.result != null && instruction.result.semantic_type is FunctionValueType) {
						graph.unknown (instruction.result);
					}
				}
				if (!block.is_complete) {
					graph.unknown (function);
					continue;
				}
				var returned = block.terminator as SsaReturn;
				if (returned is SsaStructReturn) {
					var aggregate = (SsaStructReturn) returned;
					record (aggregate.shape, aggregate.leaves);
				}
				if (returned != null && returned.value != null) {
					value (returned.value);
					graph.copy (function, returned.value);
				}
				foreach (var edge in edges (block.terminator)) {
					if (edge.target == null) {
						continue;
					}
					for (int i = 0; i < int.min ((int) edge.arguments.length, (int) edge.target.parameters.length); i++) {
						value (edge.arguments[i]);
						graph.copy (edge.target.parameters[i], edge.arguments[i]);
					}
				}
			}
		}
		uint prior = 0;
		do {
			prior = graph.revision;
			foreach (var invoked in indirect_calls) {
				var candidates = graph.candidates (invoked.callee);
				if (candidates == null) {
					continue;
				}
				foreach (var candidate in candidates) {
					call (candidate as SsaFunction, invoked.arguments);
				}
			}
		} while (prior != graph.revision);
	}

	private void opaque_type(SemanticType type) {
		if (type.kind != TypeKind.VOID && !FunctionValueType.scalar (type) && !(type is HandleType) && !(type is StringType)) {
			graph.escape_storage ();
		}
	}

	private void record(StructValueShape shape, GenericArray<SsaValue> leaves) {
		for (int i = 0; i < int.min ((int) shape.leaves.length, (int) leaves.length); i++) {
			if (!(leaves[i].semantic_type is FunctionValueType)) {
				continue;
			}
			value (leaves[i]);
			SemanticType type = shape.semantic_type;
			SsaStructField? field = null;
			for (int depth = 0; depth < shape.leaves[i].depth; depth++) {
				SsaStruct? owner = null;
				foreach (var candidate in program.structs) {
					if (candidate.semantic_type == type) {
						owner = candidate;
						break;
					}
				}
				int ordinal = shape.leaves[i].field_ordinal (depth);
				if (owner == null || ordinal < 0 || ordinal >= owner.fields.length) {
					field = null;
					break;
				}
				field = owner.fields[ordinal];
				type = field.semantic_type;
			}
			if (field != null) {
				graph.copy (field, leaves[i]);
			}
		}
	}

	private Object? place(SsaMemoryPlace storage) {
		if (storage is SsaLocalMemoryPlace) {
			return ((SsaLocalMemoryPlace) storage).storage;
		}
		if (storage is SsaFieldPlace) {
			return ((SsaFieldPlace) storage).field;
		}
		return null;
	}

	private void value(SsaValue operand) {
		var address = operand as SsaFunctionAddress;
		if (address != null) {
			if (address.target == null) {
				graph.unknown (operand);
			} else {
				graph.address (operand, address.target);
			}
		}
	}

	private void store(SsaMemoryPlace destination, SsaValue operand) {
		value (operand);
		var target = place (destination);
		if (target != null) {
			graph.copy (target, operand);
		}
	}

	private void call(SsaFunction? target, GenericArray<SsaValue> arguments) {
		for (int i = 0; i < arguments.length; i++) {
			value (arguments[i]);
			if (target != null && i < target.parameters.length) {
				graph.copy (target.parameters[i], arguments[i]);
			}
		}
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

	internal Astra.Code.CodeOriginFrontier? effect_frontier (SsaValue operand, GenericArray<Object> formals) {
		value (operand);
		return graph.frontier (operand, formals);
	}
	internal GenericArray<SsaFunction> addressed_functions() {
		var result = new GenericArray<SsaFunction> ();
		foreach (var target in graph.addressed_targets ()) {
			if (target is SsaFunction) {
				result.add ((SsaFunction) target);
			}
		}
		return result;
	}

	internal GenericArray<SsaFunction>? targets(SsaValue operand) {
		value (operand);
		var found = graph.targets (operand);
		if (found == null) {
			return null;
		}
		var result = new GenericArray<SsaFunction> ();
		foreach (var candidate in found) {
			var function = candidate as SsaFunction;
			if (function == null) {
				return null;
			}
			result.add (function);
		}
		return result;
	}

}
}
