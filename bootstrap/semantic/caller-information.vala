// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Text;

namespace Astra.Semantic {
public enum CallerInformationKind {
	FILE_PATH,
	LINE_NUMBER,
	ARGUMENT_EXPRESSION
}

// Declaration-only evidence. An ordinal is resolved once, without retaining
// syntax or a target symbol. Nothing here is part of a semantic value type.
public class CallerInformationContract : Object {
	public CallerInformationKind kind { get; private set; }
	public int target_ordinal { get; private set; }
	public SourceSpan span { get; private set; }
	public CallerInformationContract (CallerInformationKind kind, SourceSpan span, int target_ordinal = -1) {
		this.kind = kind;
		this.span = span;
		this.target_ordinal = target_ordinal;
	}

	public string dump_suffix() {
		switch (kind) {
		case CallerInformationKind.FILE_PATH:
			return " (caller-file-path)";
		case CallerInformationKind.LINE_NUMBER:
			return " (caller-line-number)";
		case CallerInformationKind.ARGUMENT_EXPRESSION:
			return " (caller-argument-expression #%d)".printf (target_ordinal);
		default:
			return " (invalid-caller-information)";
		}
	}

}

public class CallerInformation : Object {
	// Check the full C-string size before Vala's byte-array length narrows it.
	[CCode (cname = "strlen", cheader_filename = "string.h")]
	private static extern size_t source_name_byte_length(string name);
	private static bool available(SourceSpan span) {
		return span.file != null && span.start >= 0 && span.end > span.start && span.end <= span.file.length;
	}

	private static bool contains(SourceSpan outer, SourceSpan inner) {
		return available (outer) && available (inner) && outer.file == inner.file && outer.start <= inner.start && outer.end >= inner.end;
	}

	// Also used at the independently checked semantic-to-Core boundary.
	public static Diagnostic? validate(DirectCallableSymbol callable, BuiltinTypes types, bool exported = false) {
		bool suffix = false;
		for (int i = 0; i < callable.parameters.length; i++) {
			var parameter = callable.parameters[i];
			var contract = parameter.caller_information;
			if (contract == null) {
				if (suffix) {
					return new Diagnostic (parameter.span, "required parameter cannot follow a caller-information parameter");
				}
				continue;
			}
			suffix = true;
			if (!(callable is FunctionSymbol) || exported || (callable.domain != CallableDomain.NATIVE && callable.domain != CallableDomain.METHOD && callable.domain != CallableDomain.CONSTRUCTOR)) {
				return new Diagnostic (parameter.span, "caller information is permitted only on explicit native function, method and constructor parameters; foreign and exported signatures are unsupported");
			}
			if (parameter.ordinal != i || !contains (callable.span, parameter.span) || !contains (parameter.span, contract.span) || contract.span.end > parameter.name_span.start) {
				return new Diagnostic (parameter.span, "caller-information contract requires exact parameter identity and declaration source provenance");
			}
			switch (contract.kind) {
			case CallerInformationKind.FILE_PATH: case CallerInformationKind.ARGUMENT_EXPRESSION:
				if (parameter.semantic_type != types.string_type || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
					return new Diagnostic (parameter.span, "caller file/expression parameter requires exact borrowed string");
				}
				break;
			case CallerInformationKind.LINE_NUMBER:
				if (parameter.semantic_type != types.int_type || parameter.pointer_contract != PointerParameterContract.UNMANAGED) {
					return new Diagnostic (parameter.span, "caller line parameter requires exact int/i32");
				}
				break;
			default:
				return new Diagnostic (parameter.span, "invalid caller-information kind");
			}
			int target = contract.target_ordinal;
			if (contract.kind == CallerInformationKind.ARGUMENT_EXPRESSION) {
				if (target < 0 || target >= i || callable.parameters[target].ordinal != target || callable.parameters[target].caller_information != null) {
					return new Diagnostic (parameter.span, "CallerArgumentExpression requires an exact earlier required non-annotated parameter ordinal");
				}
			} else if (target != -1) {
				return new Diagnostic (parameter.span, "file/line caller information cannot have a capture target");
			}
		}
		return null;
	}

	public static Diagnostic? validate_program(CheckedProgram program) {
		foreach (var function in program.c_functions) {
			var error = validate (function, program.types);
			if (error != null) {
				return error;
			}
		}
		foreach (var function in program.all_definitions ()) {
			bool exported = false;
			foreach (var export in program.c_exports) {
				if (export.target == function.symbol) {
					exported = true;
				}
			}
			var error = validate (function.symbol, program.types, exported);
			if (error != null) {
				return error;
			}
		}
		return null;
	}

	public static uint minimum_arguments(DirectCallableSymbol callable) {
		for (uint i = 0; i < callable.parameters.length; i++) {
			if (callable.parameters[i].caller_information != null) {
				return i;
			}
		}
		return callable.parameters.length;
	}

	// Called only after declaration and arity validation. Preparing immutable
	// leaves does not check/evaluate written arguments or commit owner effects.
	public static GenericArray<CheckedExpression>? complete(CallExpressionSyntax call, DirectCallableSymbol callable, BuiltinTypes types, out Diagnostic? diagnostic) {
		diagnostic = validate (callable, types);
		if (diagnostic != null) {
			return null;
		}
		var result = new GenericArray<CheckedExpression> ();
		if (call.arguments.length < minimum_arguments (callable) || call.arguments.length > callable.parameters.length) {
			diagnostic = new Diagnostic (call.span, "caller-information completion requires a valid written argument count");
			return null;
		}
		for (uint i = call.arguments.length; i < callable.parameters.length; i++) {
			var contract = callable.parameters[i].caller_information;
			var site = call.identifier.span;
			if (!contains (call.span, site)) {
				diagnostic = new Diagnostic (call.span, "caller-information synthesis requires an available call-name source range");
				return null;
			}
			if (contract.kind == CallerInformationKind.LINE_NUMBER) {
				int line;
				int column;
				site.file.locate (site.start, out line, out column);
				var value = AstraIntegerValue.from_int64 ((IntegerType) types.int_type, line);
				if (line <= 0 || value == null) {
					diagnostic = new Diagnostic (site, "caller line is not representable as a one-based signed I32");
					return null;
				}
				result.add (new CheckedIntegerExpression.typed (site, types.int_type, value));
				continue;
			}
			TextBytes payload;
			if (contract.kind == CallerInformationKind.FILE_PATH) {
				if (source_name_byte_length (site.file.path) > int32.MAX) {
					diagnostic = new Diagnostic (site, "caller source name exceeds the signed I32 byte-length limit");
					return null;
				}
				payload = new TextBytes (site.file.path.data);
			} else {
				var written = call.arguments[contract.target_ordinal].span;
				if (!contains (call.span, written) || call.open_paren.span.file != written.file || call.close_paren.span.file != written.file || written.start < call.open_paren.span.end || written.end > call.close_paren.span.start) {
					diagnostic = new Diagnostic (site, "CallerArgumentExpression synthesis requires an available written-argument source range");
					return null;
				}
				var bytes = new uint8[written.end - written.start];
				for (int n = 0; n < bytes.length; n++) {
					bytes[n] = written.file.byte_at (written.start + n);
				}
				payload = new TextBytes (bytes);
			}
			if (!payload.valid ()) {
				diagnostic = new Diagnostic (site, "caller-information source bytes are not representable as immutable UTF-8 string with an I32 byte length");
				return null;
			}
			result.add (new CheckedTextExpression (site, types.string_type, payload));
		}
		return result;
	}

}
}
