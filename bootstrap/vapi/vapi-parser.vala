// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Vapi {
public class VapiParseResult : Object {
	public VapiFileSyntax? file { get; private set; }
	public Diagnostic? diagnostic { get; private set; }

	internal VapiParseResult (VapiFileSyntax? file, Diagnostic? diagnostic) {
		assert ((file == null) != (diagnostic == null));
		this.file = file;
		this.diagnostic = diagnostic;
	}

}

public class VapiParser : Object {
	private SourceFile source;
	private VapiLexer lexer;
	private VapiToken? current;
	private Diagnostic? diagnostic;

	private VapiParser (SourceFile source) {
		this.source = source;
		lexer = new VapiLexer (source);
	}

	public static VapiParseResult parse(SourceFile source) {
		var parser = new VapiParser (source);
		var file = parser.advance () ? parser.parse_file () : null;
		return new VapiParseResult (file, parser.diagnostic);
	}

	private bool advance() {
		current = lexer.next_token ();
		if (current == null) {
			diagnostic = lexer.diagnostic;
			return false;
		}
		return true;
	}

	private VapiToken? expect(VapiTokenKind kind, string message) {
		if (current.kind != kind) {
			diagnostic = new Diagnostic (current.span, message);
			return null;
		}
		var token = current;
		return advance () ? token : null;
	}

	private VapiFileSyntax? parse_file() {
		var functions = new GenericArray<VapiFunctionDeclarationSyntax> ();
		var handles = new GenericArray<VapiHandleDeclarationSyntax> ();
		while (current.kind != VapiTokenKind.EOF) {
			VapiCCodeAttributeSyntax? metadata = null;
			if (current.kind == VapiTokenKind.OPEN_BRACKET) {
				metadata = parse_metadata ();
				if (metadata == null) {
					return null;
				}
			}
			if (current.kind == VapiTokenKind.HANDLE) {
				var handle = parse_handle (metadata);
				if (handle == null) {
					return null;
				}
				handles.add (handle);
				continue;
			}
			var function = parse_function (metadata);
			if (function == null) {
				return null;
			}
			functions.add (function);
		}
		return new VapiFileSyntax (source, functions, current, handles);
	}

	private VapiHandleDeclarationSyntax? parse_handle(VapiCCodeAttributeSyntax? metadata) {
		var keyword = current;
		if (metadata != null && metadata.kind != DeclarationPolicyId.C_CODE) {
			diagnostic = new Diagnostic (metadata.span, "GObjectImport annotates typed callables; handles retain explicit CCode cleanup");
			return null;
		}
		bool has_cleanup = false;
		if (metadata != null) {
			foreach (var entry in metadata.entries) {
				if (entry.key.spelling () == "context" && !AllocationPolicy.valid_context_mode (entry.value.string_value)) {
					diagnostic = new Diagnostic (entry.value.span, "invalid allocator context contract");
					return null;
				}
				if (entry.key.spelling () != "destroy_function" && entry.key.spelling () != "cheader_filename" && entry.key.spelling () != "context") {
					diagnostic = new Diagnostic (entry.key.span, "VAPI handle declarations do not support %s".printf (entry.key.spelling ()));
					return null;
				}
				has_cleanup |= entry.key.spelling () == "destroy_function";
			}
		}
		if (!has_cleanup) {
			diagnostic = new Diagnostic (keyword.span, "VAPI handle declaration requires CCode destroy_function");
			return null;
		}
		if (!advance ()) {
			return null;
		}
		var name = expect (VapiTokenKind.IDENTIFIER, "expected VAPI handle name");
		if (name == null) {
			return null;
		}
		var semicolon = expect (VapiTokenKind.SEMICOLON, "expected ';' after VAPI handle declaration");
		return semicolon == null ? null : new VapiHandleDeclarationSyntax (metadata, keyword, name, semicolon);
	}

	private VapiCCodeAttributeSyntax? parse_metadata() {
		var open = current;
		if (!advance ()) {
			return null;
		}
		var attribute = expect (VapiTokenKind.IDENTIFIER, "expected VAPI attribute name");
		if (attribute == null) {
			return null;
		}
		var policy = DeclarationPolicyRegistry.lookup (attribute.spelling ());
		if (policy != DeclarationPolicyId.C_CODE && policy != DeclarationPolicyId.GOBJECT_IMPORT) {
			diagnostic = new Diagnostic (attribute.span, "unknown VAPI attribute '%s'".printf (attribute.spelling ()));
			return null;
		}
		if (expect (VapiTokenKind.OPEN_PAREN, "expected '(' after CCode") == null) {
			return null;
		}
		var entries = new GenericArray<VapiMetadataEntrySyntax> ();
		var keys = new HashTable<string, string> (str_hash, str_equal);
		while (true) {
			var key = expect (VapiTokenKind.IDENTIFIER, "expected VAPI metadata key");
			if (key == null) {
				return null;
			}
			string name = key.spelling ();
			if (policy == DeclarationPolicyId.GOBJECT_IMPORT ? name != "name" && name != "header" && name != "text_abi" && name != "carrier" : name != "cname" && name != "cheader_filename" && name != "destroy_function" && name != "text_abi" && name != "context") {
				diagnostic = new Diagnostic (key.span, "unknown VAPI metadata key '%s'".printf (name));
				return null;
			}
			if (keys.contains (name)) {
				diagnostic = new Diagnostic (key.span, "duplicate VAPI metadata key '%s'".printf (name));
				return null;
			}
			keys.insert (name, name);
			if (expect (VapiTokenKind.EQUAL, "expected '=' after VAPI metadata key") == null) {
				return null;
			}
			var value = expect (VapiTokenKind.STRING, "expected VAPI metadata string literal");
			if (value == null) {
				return null;
			}
			if (value.string_value == "") {
				diagnostic = new Diagnostic (value.span, "VAPI metadata '%s' must be nonempty".printf (name));
				return null;
			}
			entries.add (new VapiMetadataEntrySyntax (key, value));
			if (current.kind != VapiTokenKind.COMMA) {
				break;
			}
			if (!advance ()) {
				return null;
			}
		}
		if (expect (VapiTokenKind.CLOSE_PAREN, "expected ')' after VAPI metadata") == null) {
			return null;
		}
		var close = expect (VapiTokenKind.CLOSE_BRACKET, "expected ']' after CCode attribute");
		return close == null ? null : new VapiCCodeAttributeSyntax (SourceSpan.cover (open.span, close.span), entries, policy);
	}

	private VapiTypeNameSyntax? parse_type(string message) {
		if (current.kind == VapiTokenKind.BORROWED) {
			diagnostic = new Diagnostic (current.span, "'borrowed' is supported only on void* parameters; borrowed locals, results, and fields are unsupported");
			return null;
		}
		var identifier = expect (VapiTokenKind.IDENTIFIER, message);
		return identifier == null ? null : parse_type_suffix (identifier);
	}

	private VapiTypeNameSyntax? parse_type_suffix(VapiToken identifier) {
		var stars = new GenericArray<VapiToken> ();
		// Retain extra stars only to diagnose unsupported depth semantically.
		while (current.kind == VapiTokenKind.STAR) {
			stars.add (current);
			if (!advance ()) {
				return null;
			}
		}
		return new VapiTypeNameSyntax (identifier, stars);
	}

	private VapiFunctionDeclarationSyntax? parse_function(VapiCCodeAttributeSyntax? metadata) {
		if (current.spelling () == "extern" || current.spelling () == "export") {
			diagnostic = new Diagnostic (current.span, "VAPI declarations are implicit C imports; extern/export syntax is not supported");
			return null;
		}
		var owned_keyword = current.kind == VapiTokenKind.OWNED ? current : null;
		if (owned_keyword != null && !advance ()) {
			return null;
		}
		var result = parse_type ("expected VAPI function return type name");
		if (result == null) {
			return null;
		}
		if (metadata != null) {
			foreach (var entry in metadata.entries) {
				if (entry.key.spelling () == "context") {
					diagnostic = new Diagnostic (entry.key.span, "context metadata annotates a nominal handle declaration");
					return null;
				}
				if (entry.key.spelling () == "destroy_function" && result.spelling () != "void*") {
					diagnostic = new Diagnostic (result.span, "VAPI destroy_function requires exactly a 'void*' result");
					return null;
				}
			}
		}
		var name = expect (VapiTokenKind.IDENTIFIER, "expected VAPI function name");
		if (name == null || expect (VapiTokenKind.OPEN_PAREN, "expected '(' after VAPI function name") == null) {
			return null;
		}
		var parameters = new GenericArray<VapiParameterSyntax> ();
		if (current.kind != VapiTokenKind.CLOSE_PAREN) {
			while (true) {
				var borrowed_keyword = current.kind == VapiTokenKind.BORROWED ? current : null;
				if (borrowed_keyword != null && !advance ()) {
					return null;
				}
				var parameter_type = parse_type ("expected VAPI parameter type name");
				if (parameter_type == null) {
					return null;
				}
				var parameter_name = expect (VapiTokenKind.IDENTIFIER, "expected VAPI parameter name");
				if (parameter_name == null) {
					return null;
				}
				parameters.add (new VapiParameterSyntax (parameter_type, parameter_name, borrowed_keyword));
				if (current.kind != VapiTokenKind.COMMA) {
					break;
				}
				if (!advance ()) {
					return null;
				}
			}
		}
		if (expect (VapiTokenKind.CLOSE_PAREN, "expected ')' after VAPI parameters") == null) {
			return null;
		}
		var semicolon = expect (VapiTokenKind.SEMICOLON, "expected ';' after VAPI function declaration");
		return semicolon == null ? null : new VapiFunctionDeclarationSyntax (result, name, parameters, semicolon, metadata, owned_keyword);
	}

}
}
