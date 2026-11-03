// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Backend.LLVM {
internal class LlvmNativeModuleSymbol : Object {
	internal string symbol;
	internal string shape;
	internal bool imported;
	internal LlvmNativeModuleSymbol (string symbol, string shape, bool imported) {
		this.symbol = symbol;
		this.shape = shape;
		this.imported = imported;
	}

}

internal class LlvmNativeModuleBinding : Object {
	private CApi.ValueRef function;
	private CApi.TypeRef type;
	private string symbol;
	private bool imported;
	private uint convention;
	internal LlvmNativeModuleBinding (CApi.ValueRef function, CApi.TypeRef type, string symbol, bool imported, uint convention = LlvmLowering.CALL_CONVENTION) {
		this.convention = convention;
		this.function = function;
		this.type = type;
		this.symbol = symbol;
		this.imported = imported;
	}

	internal void verify() throws LlvmError {
		size_t length;
		if (CApi.value_name (function, out length) != symbol || length != symbol.length || (void*) CApi.global_value_type (function) != (void*) type || CApi.get_linkage (function) != CApi.Linkage.EXTERNAL || CApi.function_call_conv (function) != convention || (CApi.count_basic_blocks (function) == 0) != imported) {
			throw new LlvmError.VERIFICATION ("native module function lost exact symbol/signature/linkage/body authority");
		}
	}

}

// Construction-local typed correspondence, independent of serialized text.
// Only copied symbol/type witnesses survive into the LLVM artifact.
public class LlvmNativeModulePlan : Object {
	private HashTable<SsaFunction, LlvmNativeModuleSymbol> bindings = new HashTable<SsaFunction, LlvmNativeModuleSymbol> (direct_hash, direct_equal);
	private HashTable<SsaClass, LlvmNativeModuleSymbol> descriptors = new HashTable<SsaClass, LlvmNativeModuleSymbol> (direct_hash, direct_equal);
	private HashTable<string, bool> symbols = new HashTable<string, bool> (str_hash, str_equal);

	public static string function_key(SsaFunction function) {
		string member = function.name_span.text ();
		if (function is SsaConstructor) {
			member = "init";
		} else if (function is SsaDestructor) {
			member = "deinit";
		} else if (function is SsaPropertyGetter) {
			member = "get:" + ((SsaPropertyGetter) function).property_member.name;
		} else if (function is SsaPropertySetter) {
			member = "set:" + ((SsaPropertySetter) function).property_member.name;
		}
		var method = function as SsaMethod;
		if (method != null && method.generic_method_instance != null) {
			member += method.generic_method_instance.arguments.display_suffix (true);
		}
		return function.implicit_receiver == null ? "F:" + function.name : "C:" + function.implicit_receiver.contract.instance_type.display_name () + "::" + member;
	}

	public static string class_shape(NativeClassPlan owner, NativeAbiProgram program) {
		var text = new StringBuilder ("class=" + owner.name + ";");
		text.append_printf ("polymorphic=%d;exception-root=%d;parent=%s;", owner.polymorphic ? 1 : 0,
			owner.exception_root ? 1 : 0, owner.parent_ordinal < 0 ? "none" : program.classes[owner.parent_ordinal].name);
		text.append_printf ("interface=%d;", owner.is_interface ? 1 : 0);
		var key = owner.generic_instance;
		if (key == null) {
			return text.str;
		}
		if (key.declared_structure != null) {
			var declared = key.declared_structure;
			text.append ("declared-generic=" + declared.definition.name + ";");
			for (int a = 0; a < declared.argument_count; a++) {
				var argument = declared.argument (a);
				text.append_printf ("argument=%d:%s;", a, argument.nominal_name);
				if (argument.record != null) {
					text.append (record_shape (argument.record, program));
				}
				if (argument.resource != null) {
					text.append ("cleanup=" + argument.resource.cleanup_symbol + ";");
				}
			}
			return text.str;
		}
		text.append ("generic=" + key.definition.name + ";field=" + key.definition.field_name + ";");
		text.append_printf ("properties=%d;generic-methods=%d;", key.definition.property_count, key.definition.generic_method_count);
		if (key.record_argument != null) {
			text.append (record_shape (key.record_argument, program));
		} else if (key.resource_argument != null) {
			text.append ("resource=" + key.resource_argument.type_name + ":" + key.resource_argument.cleanup_symbol + ";");
		} else {
			text.append ("argument=" + program.classes[key.argument_ordinal].name + ";");
		}
		for (int m = 0; m < key.definition.member_count; m++) {
			var signature = key.definition.signature (m);
			text.append_printf ("member=%s:%d;", key.definition.member_name (m), (int) key.definition.operation (m));
			if (signature == null) {
				continue;
			}
			text.append_printf ("result=%d:%d;", (int) signature.result, signature.owned_result ? 1 : 0);
			for (int p = 0; p < signature.parameter_count; p++) {
				text.append_printf ("parameter=%d:%d;", (int) signature.parameter (p), signature.owns_parameter (p) ? 1 : 0);
			}
		}
		return text.str;
	}

	public static string record_shape(NativeStructValuePlan record, NativeAbiProgram program) {
		var text = new StringBuilder ();
		string nominal = record.struct_name;
		foreach (var application in program.record_applications) {
			if (application.record == record) {
				nominal = application.nominal_name;
			}
		}
		text.append_printf ("record(%s,%d,%d;", nominal, (int) record.mode, (int) record.result_carrier);
		foreach (var leaf in record.leaves) {
			text.append_printf ("leaf=%s/%s/%d:%s;", leaf.field_path, leaf.storage_path, leaf.buffer_component, callable_shape (leaf.abi_type, program));
		}
		foreach (var owner in record.ownership) {
			text.append_printf ("owner=%s:%s:", owner.field_path, owner.type_name);
			if (owner.cleanup_class_ordinal >= 0) {
				text.append ("class=" + program.classes[owner.cleanup_class_ordinal].name);
			} else if (owner.buffer_cleanup != null) {
				text.append ("buffer=" + owner.buffer_cleanup.element_spelling () + ":" + owner.buffer_cleanup.base_type.spelling () + ":" + owner.buffer_cleanup.length_type.spelling ());
			} else {
				text.append ("resource=" + owner.cleanup_symbol);
			}
			text.append (";");
		}
		text.append (")");
		return text.str;
	}

	public static string callable_shape(NativeAbiType type, NativeAbiProgram program) {
		var closure = type as NativeClosureHandleType;
		if (closure != null) {
			var result = new StringBuilder ("native-closure<environment=" + closure.environment +
				";error=" + (closure.checked_error ?? "none") + ";threaded=" + (closure.threaded ? "1" : "0") +
				";actor=" + (closure.actor ? "1" : "0") + ";");
			foreach (var owner in program.classes) {
				if (owner.name == closure.environment) {
					result.append (class_shape (owner, program));
					result.append ("allocation=" + (owner.allocation_policy == null ? "heap" : owner.allocation_policy.identity) + ";");
				}
			}
			result.append (callable_shape (closure.signature, program));
			return result.str + ">";
		}
		var signature = type as NativeFunctionPointerType;
		if (signature == null) {
			return type.spelling ();
		}
		var result = new StringBuilder ("native-code<" + (signature.void_result ? "void" : signature.record_result == null ? signature.result_scalar ().spelling () : "record=" + signature.record_result.record_name));
		if (signature.owned_result != null) {
			var channel = signature.owned_result;
			result.append (";owned-result=" + (channel.is_class ? "Class:" : "Resource:") + channel.type_name);
			if (channel.is_class) {
				foreach (var owner in program.classes) {
					if (owner.name == channel.type_name) {
						result.append (":" + class_shape (owner, program) + ":allocation=" + (owner.allocation_policy == null ? "heap" : owner.allocation_policy.identity));
					}
				}
			} else {
				foreach (var resource in program.callable_resources) {
					if (resource.type_name == channel.type_name) {
						result.append (":" + resource.cleanup_symbol);
					}
				}
			}
		}
		if (signature.record_result != null) {
			foreach (var record in program.struct_values) {
				if (record.struct_name == signature.record_result.record_name) {
					result.append (";result=" + record_shape (record, program));
				}
			}
		}
		foreach (var parameter in signature.parameter_types) {
			result.append ("," + callable_shape (parameter, program));
		}
		foreach (var channel in signature.borrowed_parameters) {
			result.append (";borrowed%d=%s:%s".printf (channel.ordinal, channel.is_class ? "Class" : "Resource", channel.type_name));
			if (!channel.is_class) {
				foreach (var resource in program.callable_resources) {
					if (resource.type_name == channel.type_name) {
						result.append (":" + resource.cleanup_symbol);
					}
				}
			}
		}
		foreach (var channel in signature.owned_parameters) {
			result.append (";owned%d=%s:%s".printf (channel.ordinal, channel.is_class ? "Class" : "Resource", channel.type_name));
			if (channel.is_class) {
				foreach (var owner in program.classes) {
					if (owner.name == channel.type_name) {
						result.append (":" + class_shape (owner, program) + ":allocation=" + (owner.allocation_policy == null ? "heap" : owner.allocation_policy.identity));
					}
				}
			} else {
				foreach (var resource in program.callable_resources) {
					if (resource.type_name == channel.type_name) {
						result.append (":" + resource.cleanup_symbol);
					}
				}
			}
		}
		foreach (var group in signature.record_parameters) {
			result.append (";record%d@%d:%s=".printf (group.source_ordinal, group.first_leaf, group.mode == NativeStructValueMode.BORROW_VALUE ? "BORROW_VALUE" : group.mode == NativeStructValueMode.MOVE_VALUE ? "MOVE_VALUE" : "COPY_VALUE"));
			foreach (var record in program.struct_values) {
				if (record.struct_name == group.record_name) {
					result.append (record_shape (record, program));
				}
			}
		}
		return result.str + ">";
	}

	public static string signature_shape(SsaFunction source, NativeSignature signature, NativeAbiProgram program) {
		var result = new StringBuilder ();
		result.append_printf ("result-contract=%d;", (int) source.result_contract);
		result.append_printf ("readonly=%d;", program.functions[source.ordinal].scoped_readonly ? 1 : 0);
		var effects = program.functions[source.ordinal];
		result.append_printf ("readonly-inputs=%s;callback-inputs=%s;callback-input-count=%d;callback-contract-supported=%d;",
			effects.readonly_inputs, effects.callback_inputs, effects.callback_input_count, effects.callback_contract_supported ? 1 : 0);
		var async_plan = program.functions[source.ordinal].async_callable;
		if (async_plan != null) {
			result.append ("async=" + async_plan.contract ());
		}
		if (signature.exception_plan != null) {
			result.append_printf ("checked-bound=%s;checked-root=%s;", signature.exception_plan.bound_name, signature.exception_plan.root_name);
		}
		if (source.floating_policy != 0) {
			result.append_printf ("floating-policy=%u;", source.floating_policy);
		}
		result.append_printf ("kind=%d;return=%s;nonnull=%d;heap=%d;receiver=%s;storage=%d;physical=%d;", (int) source.kind, source.return_type.nominal_name (), source.nonnull_result ? 1 : 0, source.heap_result ? 1 : 0, source.implicit_receiver == null ? "none" : source.implicit_receiver.contract.instance_type.nominal_name (), signature.object_result == null ? 0 : 1, signature.physical_parameter_count);
		var callable = program.functions[source.ordinal];
		if (callable.record_observation != null) {
			var observation = callable.record_observation;
			result.append ("receiver-record-field=" + program.classes[observation.class_ordinal].fields[observation.field_ordinal].name + ";");
		}
		if (callable.declaring_type_is_class && callable.declaring_type_ordinal >= 0 && program.classes[callable.declaring_type_ordinal].generic_instance != null) {
			result.append (class_shape (program.classes[callable.declaring_type_ordinal], program));
		}
		foreach (var parameter in source.parameters) {
			result.append_printf ("source(%s,%d,%d,%d);", parameter.semantic_type.nominal_name (), (int) parameter.pointer_contract, parameter.heap_object ? 1 : 0, parameter.requires_nonnull ? 1 : 0);
		}
		foreach (var group in source.struct_parameters) {
			result.append_printf ("nominal-record(%d,%s);", group.source_ordinal, group.shape.semantic_type.nominal_name ());
		}
		foreach (var parameter in signature.parameters) {
			result.append_printf ("channel(%s,%s,%s);", callable_shape (parameter.abi_type, program), parameter.object_origin == null ? "none" : parameter.object_origin.class_name + (parameter.object_origin.heap ? ":heap" : ":lexical"), parameter.borrowed_class_ordinal < 0 ? "none" : program.classes[parameter.borrowed_class_ordinal].name);
			if (parameter.scalar_pointee != null) {
				result.append_printf ("scalar-pointee(%d,%s);", parameter.ordinal, parameter.scalar_pointee.spelling ());
			}
			if (parameter.resource != null) {
				result.append_printf ("resource-parameter(%d,%s,%s,%d);", parameter.ordinal, parameter.resource.type_name, parameter.resource.cleanup_symbol, parameter.owns_resource ? 1 : 0);
			}
			int owner = parameter.object_origin != null ? parameter.object_origin.class_ordinal : parameter.borrowed_class_ordinal;
			if (owner >= 0 && program.classes[owner].generic_instance != null) {
				result.append (class_shape (program.classes[owner], program));
			}
		}
		foreach (var group in signature.struct_parameters) {
			result.append_printf ("record-parameters(%d,%d", group.source_ordinal, group.first_leaf);
			foreach (var leaf in group.value_plan.leaves) {
				result.append ("," + leaf.abi_type.spelling ());
			}
			result.append (");");
			result.append (record_shape (group.value_plan, program));
		}
		foreach (var group in signature.buffer_parameters) {
			result.append_printf ("buffer-parameter(%d,%d,%s,%d,%s,%s);", group.source_ordinal, group.first_leaf,
				group.value_plan.element_spelling (), group.value_plan.transfers_ownership ? 1 : 0,
				group.value_plan.base_type.spelling (), group.value_plan.length_type.spelling ());
		}
		if (signature.struct_result != null) {
			result.append_printf ("result-record(%d", (int) signature.struct_result.result_carrier);
			foreach (var leaf in signature.struct_result.leaves) {
				result.append ("," + leaf.abi_type.spelling ());
			}
			result.append (");");
			result.append (record_shape (signature.struct_result, program));
		} else {
			result.append ("result=" + (signature.result == null ? "void" : callable_shape (signature.result.abi_type, program)) + ";");
		}
		if (signature.buffer_result != null) {
			var buffer = signature.buffer_result;
			result.append_printf ("buffer-result(%s,%d,%s,%s);", buffer.element_spelling (), buffer.transfers_ownership ? 1 : 0, buffer.base_type.spelling (), buffer.length_type.spelling ());
		}
		result.append ("heap-result=" + (signature.heap_result == null ? "none" : signature.heap_result.class_name + (signature.heap_result.heap ? ":heap" : ":lexical")) + ";");
		if (signature.resource_result != null) {
			result.append ("resource-result=" + signature.resource_result.type_name + ":" + signature.resource_result.cleanup_symbol + ";");
		}
		if (signature.heap_result != null && program.classes[signature.heap_result.class_ordinal].generic_instance != null) {
			result.append (class_shape (program.classes[signature.heap_result.class_ordinal], program));
		}
		return result.str;
	}

	public void bind(SsaFunction source, NativeSignature signature, NativeAbiProgram program, string symbol, bool imported) throws LlvmError {
		if (bindings.contains (source) || symbols.contains (symbol) || !symbol.has_prefix ("astra_mod_")) {
			throw new LlvmError.INVALID_INPUT ("duplicate or invalid native module symbol authority");
		}
		string shape = signature_shape (source, signature, program);
		var declaration = source.native_declaration;
		if (declaration != null && (!imported || declaration.identity.symbol != symbol || declaration.identity.signature_shape != shape)) {
			throw new LlvmError.INVALID_INPUT ("native declaration requires its original exact symbol and ABI signature");
		}
		bindings.insert (source, new LlvmNativeModuleSymbol (symbol, shape, imported));
		symbols.insert (symbol, true);
		if (imported) {
			try {
				source.bind_module_import (symbol);
			} catch (SsaError error) {
				throw new LlvmError.INVALID_INPUT ("%s", error.message);
			}
		}
	}

	internal string? symbol_for(SsaFunction source) {
		var binding = bindings.lookup (source);
		return binding == null ? null : binding.symbol;
	}

	public void bind_descriptor(SsaClass source, NativeAbiProgram program, string symbol, bool imported) throws LlvmError {
		if (descriptors.contains (source) || symbols.contains (symbol) || !symbol.has_prefix ("astra_mod_") ||
		    source.ordinal < 0 || source.ordinal >= program.classes.length || !source.polymorphic ||
		    !program.classes[source.ordinal].polymorphic || program.classes[source.ordinal].name != source.name) {
			throw new LlvmError.INVALID_INPUT ("native descriptor requires one exact polymorphic nominal Class binding");
		}
		descriptors.insert (source, new LlvmNativeModuleSymbol (symbol, class_shape (program.classes[source.ordinal], program), imported));
		symbols.insert (symbol, true);
	}

	internal string? descriptor_symbol(SsaClass source) {
		var binding = descriptors.lookup (source);
		return binding == null ? null : binding.symbol;
	}

	internal bool descriptor_imported(SsaClass source) {
		var binding = descriptors.lookup (source);
		return binding != null && binding.imported;
	}

	internal bool is_import(SsaFunction source) {
		var binding = bindings.lookup (source);
		return binding != null && binding.imported;
	}

	internal void validate(SsaProgram source, NativeAbiProgram program) throws LlvmError {
		if (source.functions.length != program.functions.length) {
			throw new LlvmError.INVALID_INPUT ("native module SSA/NABI inventory mismatch");
		}
		foreach (var function in source.functions) {
			if (!function.native_declaration_valid ()) {
				throw new LlvmError.INVALID_INPUT ("native module lost original declaration facts");
			}
		}
		foreach (var function in source.functions) {
			if (function.native_declaration != null && !is_import (function)) {
				throw new LlvmError.INVALID_INPUT ("native declaration requires its exact imported symbol binding");
			}
		}
		foreach (var function in source.functions) {
			if (function.module_import_symbol != null && (!is_import (function) || symbol_for (function) != function.module_import_symbol)) {
				throw new LlvmError.INVALID_INPUT ("native import lost its registered external module plan");
			}
		}
		foreach (var function in bindings.get_keys ()) {
			if (function.ordinal < 0 || function.ordinal >= source.functions.length || source.functions[function.ordinal] != function || bindings.lookup (function).shape != signature_shape (function, program.functions[function.ordinal].signature, program)) {
				throw new LlvmError.INVALID_INPUT ("native module correspondence lost its exact typed signature");
			}
		}
		foreach (var owner in descriptors.get_keys ()) {
			if (owner.ordinal < 0 || owner.ordinal >= source.classes.length || source.classes[owner.ordinal] != owner ||
			    descriptors.lookup (owner).shape != class_shape (program.classes[owner.ordinal], program)) {
				throw new LlvmError.INVALID_INPUT ("native descriptor correspondence lost its exact nominal class shape");
			}
		}
	}

}
}
