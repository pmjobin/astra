// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Semantic {
// Opt-in editor observations of resolved symbols. No lexical name guessing,
// executable IR, retained global state or generated-program metadata.
public class ToolingIndex : Object {
	private GenericArray<string> references = new GenericArray<string> ();
	private GenericArray<string> symbols = new GenericArray<string> ();
	private HashTable<string, bool> declared = new HashTable<string, bool> (str_hash, str_equal);
	private HashTable<string, bool> observed = new HashTable<string, bool> (str_hash, str_equal);

	public static string quote(string text) {
		var result = new StringBuilder ("\"");
		for (int i = 0; i < text.length; i++) {
			uint8 b = text.data[i];
			if (b == '"' || b == '\\') {
				result.append_c ('\\');
				result.append_c ((char) b);
			} else if (b < 32) {
				result.append ("\\u%04x".printf (b));
			} else {
				result.append_c ((char) b);
			}
		}
		result.append_c ('"');
		return result.str;
	}

	private static string identity(Symbol symbol) {
		var span = symbol.name_span;
		return "%s#%d:%d".printf (span.file.path, span.start, span.end);
	}

	private static string location(SourceSpan span) {
		return "\"file\":%s,\"start\":%d,\"end\":%d".printf (quote (span.file.path), span.start, span.end);
	}

	public void reference(SourceSpan span, Symbol? symbol) {
		if (symbol == null) {
			return;
		}
		string row = "{%s,\"id\":%s}".printf (location (span), quote (identity (symbol)));
		if (!observed.contains (row)) {
			observed.insert (row, true);
			references.add (row);
		}
	}

	public void expression(ExpressionSyntax syntax, CheckedExpression value) {
		if (syntax is ParenthesizedExpressionSyntax) {
			return;
		}
		if (value is CheckedLocalReferenceExpression) {
			reference (syntax.span, ((CheckedLocalReferenceExpression) value).local);
		} else if (value is CheckedParameterReferenceExpression) {
			reference (syntax.span, ((CheckedParameterReferenceExpression) value).parameter);
		} else if (value is CheckedConstantReference) {
			reference (syntax.span, ((CheckedConstantReference) value).constant);
		} else if (value is CheckedFunctionAddress) {
			reference (syntax.span, ((CheckedFunctionAddress) value).target);
		}
		if (syntax is FieldAccessExpressionSyntax) {
			var field = (FieldAccessExpressionSyntax) syntax;
			if (value is CheckedPropertyGetExpression) {
				reference (field.field_name.span, ((CheckedPropertyGetExpression) value).property_symbol);
			} else if (value is CheckedFieldReferenceExpression) {
				reference (field.field_name.span, ((CheckedFieldReferenceExpression) value).field);
			} else if (value is CheckedIndirectFieldReference) {
				reference (field.field_name.span, ((CheckedIndirectFieldReference) value).field);
			} else if (value is CheckedLoadExpression) {
				var place = ((CheckedLoadExpression) value).source;
				if (place is CheckedFieldPlace) {
					reference (field.field_name.span, ((CheckedFieldPlace) place).field);
				} else if (place is CheckedObjectFieldPlace) {
					reference (field.field_name.span, ((CheckedObjectFieldPlace) place).field);
				}
			}
		}
	}

	private static string array_text(GenericArray<string> values) {
		var result = new StringBuilder ("[");
		foreach (string value in values) {
			if (result.len != 1) {
				result.append_c (',');
			}
			result.append (value);
		}
		result.append_c (']');
		return result.str;
	}

	public static string diagnostic_json(Diagnostic diagnostic) {
		return "{\"format\":\"astra-tooling/1\",\"symbols\":[],\"references\":[],\"diagnostics\":[{%s,\"message\":%s}]}\n".printf (location (diagnostic.span), quote (diagnostic.message));
	}

	private void declaration(Symbol symbol, string kind, string detail, SourceSpan? scope = null) {
		string key = identity (symbol);
		if (declared.contains (key)) {
			return;
		}
		declared.insert (key, true);
		string extent = scope == null ? "" : ",\"scope_start\":%d,\"scope_end\":%d".printf (scope.start, scope.end);
		symbols.add ("{%s,\"id\":%s,\"name\":%s,\"kind\":%s,\"detail\":%s%s}".printf (
			location (symbol.name_span), quote (key), quote (symbol.name), quote (kind), quote (detail), extent));
	}

	private static string class_policy(ClassSymbol owner) {
		var result = new StringBuilder ("class " + owner.name + "; ");
		var policy = owner.concurrency_policy;
		if (policy != null && policy.shared) {
			result.append ("intrusive shared owner; clone acquires; assignment moves; atomic strong/weak lifetime; ");
		} else {
			result.append ("unique owner; deterministic cleanup; no mandatory reference count; ");
		}
		if (policy != null) {
			if (policy.monitor) {
				result.append ("monitor: nonrecursive protected method lock; no suspension under lock; ");
			}
			if (policy.singleton) {
				result.append ("process singleton: lazy owning anchor; explicit quiescent shutdown; ");
			}
			if (policy.thread_bound) {
				result.append ("thread-bound: constructing-thread token, no worker transfer; ");
			}
			if (policy.actor) {
				result.append ("actor: explicit bounded mailbox/executor binding; ");
			}
		}
		if (owner.allocation_policy != null) {
			result.append (owner.allocation_policy.dump ());
		} else {
			result.append ("allocation selected by checked construction");
		}
		result.append ("; native layout; foreign adapters are separate; runtime descriptors opt-in");
		if (owner.foreign_export != null) {
			var foreign = owner.foreign_export;
			result.append ("; CExport opaque " + foreign.prefix + ": selected property " + foreign.property_name + ", separate cached wrapper, native strong/weak authority, explicit acquire/release, constructing-thread data calls");
		}
		if (owner.foreign_export != null && owner.foreign_export.com != null) {
			result.append ("; COMExport " + owner.foreign_export.com.identity () + ": cached SDK interface views, QI acquires one native strong, last native strong retires views");
		}
		if (owner.foreign_export != null && owner.foreign_export.gobject != null) {
			result.append ("; " + owner.foreign_export.gobject.identity () + ": one native owner per GObject lifetime, atomic weak cache, property/signal affinity, synchronous callback quiescence");
		}
		return result.str;
	}

	private static string struct_policy(StructSymbol structure) {
		string result = "struct " + structure.name + "; derived value/cleanup semantics";
		if (structure.representation != null) {
			result += "; " + structure.representation.dump ();
		}
		return result;
	}

	private static string signature(DirectCallableSymbol function) {
		var result = new StringBuilder (function.return_type.display_name () + " " + function.name + "(");
		foreach (var p in function.parameters) {
			if (!result.str.has_suffix ("(")) {
				result.append (", ");
			}
			result.append (p.semantic_type.display_name () + " " + p.name + p.pointer_contract.dump_suffix ());
		}
		result.append_c (')');
		if (function is CFunctionSymbol) {
			var imported = (CFunctionSymbol) function;
			result.append ("; " + DeclarationPolicyRegistry.spelling (imported.declaration_policy) + "; C ABI symbol=" + imported.external_symbol);
			if (imported.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99) {
				result.append ("; C99 _Bool copied i1/zeroext; no bool storage");
			}
		} else if (function is FunctionSymbol) {
			var native = (FunctionSymbol) function;
			if (native.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
				result.append ("; owned result transfers");
			}
			if (native.throws_type != null) {
				result.append (" throws " + native.throws_type.display_name ());
			}
			if (native.async_body != null) {
				result.append ("; async frame/executor contract");
			}
		}
		return result.str;
	}

	public string format(CheckedProgram program, bool explanation = false) {
		foreach (var instance in program.native_instances ()) {
			declaration (instance, (instance is ClassSymbol) ? "class" : "struct", (instance is ClassSymbol) ? class_policy ((ClassSymbol) instance) : struct_policy ((StructSymbol) instance));
			foreach (var field in instance.fields) {
				declaration (field, "field", field.semantic_type.display_name () + " " + field.name, instance.span);
			}
			foreach (var property in instance.properties) {
				declaration (property, "property", property.semantic_type.display_name () + " " + property.name + (property.is_lazy ? "; first-success lazy cache" : ""), instance.span);
			}
		}
		foreach (var handle in program.handles) {
			if (handle.com_import != null) {
				declaration (handle, "interface", handle.com_import.identity () + "; separate owned COM wrapper; explicit acquire/clone; constructing-thread cleanup");
			}
		}
		foreach (var constant in program.constants) {
			declaration (constant, "constant", "const " + constant.semantic_type.display_name () + " " + constant.name);
		}
		foreach (var function in program.c_functions) {
			declaration (function, "function", signature (function));
		}
		foreach (var function in program.all_definitions ()) {
			declaration (function.symbol, "function", signature (function.symbol));
			foreach (var parameter in function.symbol.parameters) {
				declaration (parameter, "parameter", parameter.semantic_type.display_name () + " " + parameter.name + parameter.pointer_contract.dump_suffix (), function.span);
			}
			foreach (var local in function.locals) {
				declaration (local, "local", local.semantic_type.display_name () + " " + local.name + (local.is_owned ? "; owns cleanup; moves explicitly" : "; borrowed or copied value"), function.span);
			}
		}
		if (explanation) {
			var result = new StringBuilder ("Astra checked declaration policies (source profile)\n");
			foreach (var instance in program.native_instances ()) {
				if (instance is ClassSymbol) {
					result.append (class_policy ((ClassSymbol) instance) + "\n");
				} else if (((StructSymbol) instance).representation != null) {
					result.append (((StructSymbol) instance).representation.dump () + "; copied C representation; explicit active projection where selected\n");
				}
			}
			foreach (var handle in program.handles) {
				if (handle.com_import != null) {
					result.append (handle.com_import.identity () + "; one foreign reference per wrapper; QI acquires, clone AddRef, scope Release; checked thread/apartment; HRESULT/out\n");
				}
			}
			foreach (var exported in program.c_exports) {
				result.append (DeclarationPolicyRegistry.spelling (exported.declaration_policy) + " " + exported.external_symbol + "; explicit C ABI wrapper, native target retained" + (exported.bool_abi == Astra.Foreign.CBoolAbi.C99 ? "; C99 _Bool copied i1/zeroext; no bool storage" : "") + "\n");
			}
			foreach (var imported in program.c_functions) {
				result.append (signature (imported) + "; explicit link input required\n");
			}
			return result.str;
		}
		return "{\"format\":\"astra-tooling/1\",\"symbols\":%s,\"references\":%s,\"diagnostics\":[]}\n".printf (array_text (symbols), array_text (references));
	}

}
}
