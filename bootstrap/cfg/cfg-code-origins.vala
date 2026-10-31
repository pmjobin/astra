// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Cfg {
internal class CfgCodeOrigins : Object {
	private Astra.Code.CodeOrigins graph = new Astra.Code.CodeOrigins ();
	private GenericArray<CfgFunctionValueCall> indirect_calls = new GenericArray<CfgFunctionValueCall> ();
	internal CfgCodeOrigins (CfgProgram program) {
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
			foreach (var local in function.locals) {
				if (local.incoming_parameter != null) {
					graph.copy (local, local.incoming_parameter);
				}
			}
			if (function.native_declaration != null || function.name_span.file.native_interface) {
				graph.unknown (function);
				foreach (var parameter in function.parameters) {
					opaque_type (parameter.semantic_type);
				}
				opaque_type (function.return_type);
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is CfgEvaluateInstruction) {
						var evaluated = (CfgEvaluateInstruction) instruction;
						value (evaluated.value);
						graph.copy (evaluated.result, evaluated.value);
					} else if (instruction is CfgInitialize) {
						var initialized = (CfgInitialize) instruction;
						value (initialized.value);
						var destination = place (initialized.target);
						if (destination != null) {
							graph.copy (destination, initialized.value);
						}
					} else if (instruction is CfgStore) {
						var stored = (CfgStore) instruction;
						value (stored.value);
						var destination = place (stored.target);
						if (destination != null) {
							graph.copy (destination, stored.value);
						}
					} else if (instruction is CfgCCallInstruction) {
						var invoked = (CfgCCallInstruction) instruction;
						foreach (var argument in invoked.arguments) {
							value (argument);
							opaque_type (argument.semantic_type);
						}
						opaque_type (invoked.target.return_type);
					} else if (instruction is CfgCallInstruction) {
						var invoked = (CfgCallInstruction) instruction;
						call (invoked.target, invoked.arguments, invoked.receiver);
						if (invoked.result != null) {
							if (invoked.target == null || invoked.target.dispatch_kind != ClassDispatchKind.DIRECT) {
								graph.unknown (invoked.result);
							} else {
								graph.copy (invoked.result, invoked.target);
							}
						}
					} else if (instruction is CfgStructInvoke) {
						value (((CfgStructInvoke) instruction).call);
					}
				}
				if (!block.is_complete) {
					graph.unknown (function);
					continue;
				}
				var returned = block.terminator as CfgReturn;
				if (returned != null && returned.value != null) {
					value (returned.value);
					graph.copy (function, returned.value);
				}
			}
		}
		uint prior = 0;
		do {
			prior = graph.revision;
			for (int i = 0; i < indirect_calls.length; i++) {
				var invoked = indirect_calls[i];
				var candidates = graph.candidates (invoked.callee);
				if (candidates == null) {
					continue;
				}
				foreach (var candidate in candidates) {
					call (candidate as CfgFunction, invoked.arguments, null);
				}
			}
		} while (prior != graph.revision);
	}
	private void opaque_type(SemanticType type) {
		if (type.kind != TypeKind.VOID && !FunctionValueType.scalar (type) && !(type is HandleType) && !(type is StringType)) {
			graph.escape_storage ();
		}
	}
	private Object? place(CfgPlace storage) {
		if (storage is CfgLocalPlace || storage is CfgTemporaryPlace) {
			return storage;
		}
		if (storage is CfgFieldPlace) {
			return ((CfgFieldPlace) storage).field;
		}
		if (storage is CfgIndirectFieldPlace) {
			value (((CfgIndirectFieldPlace) storage).pointer);
			return ((CfgIndirectFieldPlace) storage).field;
		}
		if (storage is CfgObjectFieldPlace) {
			return ((CfgObjectFieldPlace) storage).field;
		}
		return null;
	}
	private void call(CfgFunction? target, GenericArray<CfgValue> arguments, CfgValue? receiver) {
		if (receiver != null) {
			value (receiver);
		}
		for (int i = 0; i < arguments.length; i++) {
			value (arguments[i]);
			if (target != null && i < target.parameters.length) {
				graph.copy (target.parameters[i], arguments[i]);
			}
		}
	}
	private void value(CfgValue expression) {
		if (expression is CfgFunctionAddress) {
			var target = ((CfgFunctionAddress) expression).target;
			if (target == null) {
				graph.unknown (expression);
			} else {
				graph.address (expression, target);
			}
		} else if (expression is CfgParameterValue) {
			graph.copy (expression, ((CfgParameterValue) expression).parameter);
		} else if (expression is CfgLoadValue) {
			var source = place (((CfgLoadValue) expression).source);
			if (source == null) {
				graph.unknown (expression);
			} else {
				graph.copy (expression, source);
			}
		} else if (expression is CfgFunctionValueCall) {
			var invoked = (CfgFunctionValueCall) expression;
			value (invoked.callee);
			if (!indirect_calls.find (invoked)) {
				indirect_calls.add (invoked);
			}
			foreach (var argument in invoked.arguments) {
				value (argument);
			}
			graph.unknown (expression);
		} else if (expression is CfgBinaryValue) {
			var binary = (CfgBinaryValue) expression;
			value (binary.left);
			value (binary.right);
		} else if (expression is CfgPrefixValue) {
			value (((CfgPrefixValue) expression).operand);
		} else if (expression is CfgEvaluatedValue || expression is CfgCallResultValue) {
			return;
		} else if (expression.semantic_type is FunctionValueType) {
			graph.unknown (expression);
		}
	}
	internal Astra.Code.CodeOriginFrontier? effect_frontier (Object expression, GenericArray<Object> formals) {
		if (!(expression is CfgValue)) {
			return null;
		}
		value ((CfgValue) expression);
		return graph.frontier (expression, formals);
	}

	internal GenericArray<CfgFunction>? targets(CfgValue expression) {
		value (expression);
		var found = graph.targets (expression);
		if (found == null) {
			return null;
		}
		var result = new GenericArray<CfgFunction> ();
		foreach (var candidate in found) {
			var function = candidate as CfgFunction;
			if (function == null) {
				return null;
			}
			result.add (function);
		}
		return result;
	}
}
}
