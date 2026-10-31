// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public class ParseResult : Object {
	public CompilationUnitSyntax? unit { get; private set; }
	public Diagnostic? diagnostic { get; private set; }

	internal ParseResult (CompilationUnitSyntax? unit, Diagnostic? diagnostic) {
		assert ((unit == null) != (diagnostic == null));
		this.unit = unit;
		this.diagnostic = diagnostic;
	}
}

public class Parser : Object {
	// Bound recursion, dumping, and recursive destruction of malformed trees.
	internal const int MAX_EXPRESSION_DEPTH = 256;
	internal const int MAX_BLOCK_DEPTH = 256;
	private string namespace_prefix = "";
	private int block_depth = 0;
	private int type_depth = 0;
	private bool allocation_element = false;
	private SourceFile source;
	private Lexer lexer;
	private Token? current;
	private Token? lookahead;
	private Token? second_lookahead;
	private Diagnostic? diagnostic;
	// Cursor probes own separate inventories; only committed syntax is retained.
	private GenericArray<GenericTypeApplicationSyntax> type_applications = new GenericArray<GenericTypeApplicationSyntax> ();

	private Parser (SourceFile source) {
		this.source = source;
		lexer = new Lexer (source);
	}

	private Parser.from_cursor (Parser original) {
		this.source = original.source;
		this.namespace_prefix = original.namespace_prefix;
		this.lexer = original.lexer.fork ();
		this.current = original.current;
		this.lookahead = original.lookahead;
		this.second_lookahead = original.second_lookahead;
	}

	public static ParseResult parse(SourceFile source) {
		var parser = new Parser (source);
		CompilationUnitSyntax? unit = null;
		if (parser.advance ()) {
			unit = parser.parse_unit ();
		}
		if (unit != null) {
			foreach (var application in parser.type_applications) {
				unit.type_applications.add (application);
			}
		}
		return new ParseResult (unit, parser.diagnostic);
	}

	private bool advance() {
		current = lookahead ?? lexer.next_token ();
		lookahead = second_lookahead;
		second_lookahead = null;
		if (current == null) {
			diagnostic = lexer.diagnostic;
			return false;
		}
		return true;
	}

	// Split only while consuming a type close. Expression shifts keep their token.
	private Token? type_close(string message) {
		if (current.kind != TokenKind.SHIFT_RIGHT) {
			return expect (TokenKind.GREATER, message);
		}
		var span = current.span;
		var first = new Token (TokenKind.GREATER, SourceSpan (source, span.start, span.start + 1));
		current = new Token (TokenKind.GREATER, SourceSpan (source, span.start + 1, span.end));
		return first;
	}

	private GenericArray<Token>? parse_type_parameters() {
		if (!advance ()) {
			return null;
		}
		var parameters = new GenericArray<Token> ();
		while (true) {
			var parameter = expect (TokenKind.IDENTIFIER, "expected type parameter name; empty lists and trailing commas are unsupported");
			if (parameter == null) {
				return null;
			}
			parameters.add (parameter);
			if (current.kind != TokenKind.COMMA) {
				break;
			}
			if (!advance ()) {
				return null;
			}
		}
		return type_close ("expected '>' after type parameters") == null ? null : parameters;
	}

	private GenericArray<TypeNameSyntax>? parse_type_arguments(int channel_start = -1) {
		if (expect (TokenKind.LESS, "expected '<' before type arguments") == null) {
			return null;
		}
		var arguments = new GenericArray<TypeNameSyntax> ();
		while (true) {
			Token? channel = null;
			if (channel_start >= 0 && arguments.length >= channel_start && (current.kind == TokenKind.OWNED || current.kind == TokenKind.BORROWED)) {
				channel = current;
				if (!advance ()) {
					return null;
				}
				if (current.kind == TokenKind.OWNED || current.kind == TokenKind.BORROWED) {
					fail (current.span, "callable channel requires at most one ownership qualifier");
					return null;
				}
			}
			var type = parse_type ("expected explicit type argument; empty lists and trailing commas are unsupported");
			if (type == null) {
				return null;
			}
			arguments.add (channel == null ? type : new CallableChannelTypeSyntax (channel, type));
			if (current.kind != TokenKind.COMMA) {
				break;
			}
			if (!advance ()) {
				return null;
			}
		}
		return type_close ("expected '>' after type arguments") == null ? null : arguments;
	}

	private bool begins_generic_call() {
		if (current.kind != TokenKind.LESS) {
			return false;
		}
		var probe = new Parser.from_cursor (this);
		return probe.parse_type_arguments () != null && probe.current.kind == TokenKind.OPEN_PAREN;
	}

	private bool begins_enum_application() {
		if (current.kind != TokenKind.LESS) {
			return false;
		}
		var probe = new Parser.from_cursor (this);
		return probe.parse_type_arguments () != null && probe.current.kind == TokenKind.DOT;
	}

	private CallExpressionSyntax? parse_applied_enum_call(Token qualifier, int recursion_depth) {
		var arguments = parse_type_arguments ();
		var dot = arguments == null ? null : expect (TokenKind.DOT, "expected '.' after applied enum type");
		var member = dot == null ? null : expect (TokenKind.IDENTIFIER, "expected enum variant");
		var call = member == null ? null : parse_call (member, recursion_depth, qualifier, dot);
		if (call != null) {
			call.qualifier_arguments = arguments;
		}
		return call;
	}

	private bool next_is(TokenKind kind) {
		if (lookahead == null) {
			lookahead = lexer.next_token ();
		}
		if (lookahead == null) {
			diagnostic = lexer.diagnostic;
			return false;
		}
		return lookahead.kind == kind;
	}

	private bool following_is(TokenKind kind) {
		if (lookahead == null) {
			lookahead = lexer.next_token ();
		}
		if (lookahead == null) {
			diagnostic = lexer.diagnostic;
			return false;
		}
		if (second_lookahead == null) {
			second_lookahead = lexer.next_token ();
		}
		if (second_lookahead == null) {
			diagnostic = lexer.diagnostic;
			return false;
		}
		return second_lookahead.kind == kind;
	}

	private bool next_begins_expression() {
		if (lookahead == null) {
			lookahead = lexer.next_token ();
		}
		if (lookahead == null) {
			diagnostic = lexer.diagnostic;
			return false;
		}
		switch (lookahead.kind) {
		case TokenKind.THIS: case TokenKind.SLICE: case TokenKind.LEN:
		case TokenKind.IDENTIFIER: case TokenKind.INTEGER: case TokenKind.FLOAT:
		case TokenKind.TRUE: case TokenKind.FALSE: case TokenKind.NULL:
		case TokenKind.OPEN_PAREN: case TokenKind.PLUS: case TokenKind.MINUS:
		case TokenKind.BANG: case TokenKind.AMPERSAND: case TokenKind.ALL:
		case TokenKind.ANY:
		case TokenKind.SPLAT:
		case TokenKind.INSERT:
		case TokenKind.SHUFFLE:
		case TokenKind.SELECT:
			return true;
		default:
			return false;
		}
	}

	private void fail(SourceSpan span, string message) {
		if (diagnostic == null) {
			diagnostic = new Diagnostic (span, message);
		}
	}

	private Token? expect(TokenKind kind, string message) {
		if (current.kind != kind) {
			// Colon is only admitted by the where-clause grammar. Preserve the
			// established diagnostic for unsupported labels and other uses.
			fail (current.span, current.kind == TokenKind.CONST ? "'const' is a reserved keyword for compile-time constants" : current.kind == TokenKind.VAR ? "'var' is a reserved keyword for inferred local declarations" : current.kind == TokenKind.COLON ? "unexpected character ':'" : message);
			return null;
		}
		var token = current;
		return advance () ? token : null;
	}

	private CompilationUnitSyntax? parse_unit() {
		Token? namespace_name = null;
		var imports = new GenericArray<Token> ();
		var runtimes = new GenericArray<AsyncRuntimeSyntax> ();
		var enums = new GenericArray<EnumDeclarationSyntax> ();
		var constants = new GenericArray<ConstantDeclarationSyntax> ();
		var functions = new GenericArray<FunctionDeclarationSyntax> ();
		var structs = new GenericArray<StructDeclarationSyntax> ();
		var classes = new GenericArray<ClassDeclarationSyntax> ();
		var com_interfaces = new GenericArray<ComImportSyntax> ();
		var c_classes = new GenericArray<ClassDeclarationSyntax> ();
		while (current.kind != TokenKind.EOF) {
			if (current.kind == TokenKind.IDENTIFIER && (current.spelling () == "namespace" || current.spelling () == "using") && next_is (TokenKind.IDENTIFIER) && following_is (TokenKind.SEMICOLON)) {
				var directive = current;
				if (com_interfaces.length != 0 || functions.length != 0 || structs.length != 0 || classes.length != 0 || enums.length != 0 || constants.length != 0 || runtimes.length != 0) {
					fail (directive.span, "namespace and using directives must precede declarations");
					return null;
				}
				if (!advance ()) {
					return null;
				}
				var name = current;
				if (!advance () || expect (TokenKind.SEMICOLON, "expected ';' after namespace directive") == null) {
					return null;
				}
				if (directive.spelling () == "namespace") {
					if (namespace_name != null || imports.length != 0) {
						fail (directive.span, "one namespace directive must precede using directives");
						return null;
					}
					namespace_name = name;
					namespace_prefix = name.spelling () + ".";
				} else {
					foreach (var prior in imports) {
						if (prior.spelling () == name.spelling ()) {
							fail (name.span, "duplicate using namespace");
							return null;
						}
					}
					imports.add (name);
				}
				continue;
			}
			bool module_internal = false;
			if (namespace_name != null && current.kind == TokenKind.IDENTIFIER && (current.spelling () == "public" || current.spelling () == "internal") && !next_is (TokenKind.OPEN_PAREN) && (next_is (TokenKind.EXPORT) || next_is (TokenKind.EXTERN) || !following_is (TokenKind.OPEN_PAREN))) {
				module_internal = current.spelling () == "internal";
				if (!advance ()) {
					return null;
				}
			}
			if (current.kind == TokenKind.ASYNC && next_is (TokenKind.IDENTIFIER) && lookahead.spelling () == "runtime") {
				var keyword = current;
				if (!advance () || !advance ()) {
					return null;
				}
				var name = expect (TokenKind.IDENTIFIER, "expected nominated virtual executor identity");
				if (name == null || expect (TokenKind.THROWS, "expected runtime exception nomination") == null) {
					return null;
				}
				var error = parse_type ("expected ordinary runtime exception class");
				if (error == null || current.kind != TokenKind.IDENTIFIER || current.spelling () != "returns") {
					fail (current.span, "expected 'returns' and ordinary root status enum");
					return null;
				}
				if (!advance ()) {
					return null;
				}
				var status = parse_type ("expected root status enum");
				if (status == null) {
					return null;
				}
				Token? provider = null;
				if (current.kind == TokenKind.IDENTIFIER && current.spelling () == "provider") {
					if (!advance ()) {
						return null;
					}
					provider = expect (TokenKind.TEXT, "expected explicit async provider string");
					if (provider == null) {
						return null;
					}
				}
				var end = expect (TokenKind.SEMICOLON, "expected ';' after runtime nomination");
				if (end == null) {
					return null;
				}
				runtimes.add (new AsyncRuntimeSyntax (keyword, name, error, status, end, provider));
				continue;
			}
			if (current.kind == TokenKind.OPEN_BRACKET && next_is (TokenKind.IDENTIFIER) && (DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.C_IMPORT || DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.GOBJECT_IMPORT) && foreign_class_ahead ()) {
				var attribute = lookahead;
				var entries = parse_ccode (DeclarationPolicyRegistry.lookup (attribute.spelling ()), true);
				if (entries == null || current.kind != TokenKind.CLASS || namespace_name != null || module_internal) {
					fail (attribute.span, "declaration-driven CImport requires a global Class declaration");
					return null;
				}
				var imported = parse_native_instance (false, true) as ClassDeclarationSyntax;
				if (imported == null) {
					return null;
				}
				imported.foreign_import = new ForeignPolicySyntax (attribute, entries);
				c_classes.add (imported);
				continue;
			}
			Token? exception_root = null;
			if (current.kind == TokenKind.OPEN_BRACKET && next_is (TokenKind.IDENTIFIER) && DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.COM_IMPORT) {
				if (namespace_name != null || module_internal) {
					fail (current.span, "selected COMImport requires an explicit global interface declaration");
					return null;
				}
				var attribute = lookahead;
				var entries = parse_ccode (DeclarationPolicyId.COM_IMPORT, true);
				if (entries == null) {
					return null;
				}
				bool declared = false;
				foreach (var entry in entries) {
					declared |= entry.key.spelling () == "profile" && entry.decoded_value == "declarations-v1";
				}
				if (declared) {
					if (current.kind != TokenKind.IDENTIFIER || current.spelling () != "interface") {
						fail (current.span, "declarations-v1 COMImport requires a typed interface declaration");
						return null;
					}
					var declaration = parse_native_instance (false, true, true) as ClassDeclarationSyntax;
					if (declaration == null) {
						return null;
					}
					var policy = new ForeignPolicySyntax (attribute, entries);
					declaration.foreign_import = policy;
					com_interfaces.add (new ComImportSyntax (policy, declaration.name, declaration.close_brace, declaration));
					continue;
				}
				var keyword = expect (TokenKind.IDENTIFIER, "COMImport requires interface Name;");
				if (keyword == null || keyword.spelling () != "interface") {
					fail (attribute.span, "COMImport requires interface Name;");
					return null;
				}
				var name = expect (TokenKind.IDENTIFIER, "COMImport requires a nominal interface name");
				var end = name == null ? null : expect (TokenKind.SEMICOLON, "selected COMImport interface excludes arbitrary members/inheritance");
				if (end == null) {
					return null;
				}
				com_interfaces.add (new ComImportSyntax (new ForeignPolicySyntax (attribute, entries), name, end));
				continue;
			}
			ConcurrencyKind concurrency = ConcurrencyKind.NONE;
			GenericArray<CCodeEntrySyntax>? allocator = null;
			GenericArray<CCodeEntrySyntax>? alignment = null;
			GenericArray<CCodeEntrySyntax>? representation = null;
			ForeignPolicySyntax? foreign_export = null;
			ForeignPolicySyntax? com_export = null;
			ForeignPolicySyntax? gobject_export = null;
			while (current.kind == TokenKind.OPEN_BRACKET && next_is (TokenKind.IDENTIFIER) && (DeclarationPolicyRegistry.storage (DeclarationPolicyRegistry.lookup (lookahead.spelling ())) || ConcurrencyKind.parse (lookahead.spelling ()) != ConcurrencyKind.NONE || ((DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.C_EXPORT || DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.COM_EXPORT || DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.GOBJECT_EXPORT) && foreign_class_ahead ()))) {
				string attribute = lookahead.spelling ();
				if (DeclarationPolicyRegistry.lookup (attribute) == DeclarationPolicyId.GOBJECT_EXPORT) {
					if (gobject_export != null) {
						fail (current.span, "duplicate Class GObjectExport policy");
						return null;
					}
					var name = lookahead;
					var entries = parse_ccode (DeclarationPolicyId.GOBJECT_EXPORT, true);
					if (entries == null) {
						return null;
					}
					gobject_export = new ForeignPolicySyntax (name, entries);
					continue;
				}
				if (DeclarationPolicyRegistry.lookup (attribute) == DeclarationPolicyId.COM_EXPORT) {
					if (com_export != null) {
						fail (current.span, "duplicate Class COMExport policy");
						return null;
					}
					var name = lookahead;
					var entries = parse_ccode (DeclarationPolicyId.COM_EXPORT, true);
					if (entries == null) {
						return null;
					}
					com_export = new ForeignPolicySyntax (name, entries);
					continue;
				}
				if (DeclarationPolicyRegistry.lookup (attribute) == DeclarationPolicyId.C_EXPORT) {
					if (foreign_export != null) {
						fail (current.span, "duplicate Class CExport policy");
						return null;
					}
					var name = lookahead;
					var entries = parse_ccode (DeclarationPolicyId.C_EXPORT, true);
					if (entries == null) {
						return null;
					}
					foreign_export = new ForeignPolicySyntax (name, entries);
					continue;
				}
				if (ConcurrencyKind.parse (attribute) != ConcurrencyKind.NONE) {
					if (!advance ()) {
						return null;
					}
					while (true) {
						var name = expect (TokenKind.IDENTIFIER, "expected a concurrency declaration policy");
						if (name == null) {
							return null;
						}
						var kind = ConcurrencyKind.parse (name.spelling ());
						if (kind == ConcurrencyKind.NONE || (concurrency & kind) != 0) {
							fail (name.span, "unknown or duplicate concurrency declaration policy");
							return null;
						}
						concurrency |= kind;
						if (current.kind != TokenKind.COMMA) {
							break;
						}
						if (!advance ()) {
							return null;
						}
					}
					if (expect (TokenKind.CLOSE_BRACKET, "concurrency declaration policies take no arguments") == null) {
						return null;
					}
					continue;
				}
				if (attribute == "Allocator" && allocator != null || attribute == "Align" && alignment != null || attribute == "Repr" && representation != null) {
					fail (current.span, "duplicate storage declaration policy");
					return null;
				}
				var entries = parse_ccode (DeclarationPolicyRegistry.lookup (attribute));
				if (entries == null) {
					return null;
				}
				if (attribute == "Allocator") {
					allocator = entries;
				} else if (attribute == "Align") {
					alignment = entries;
				} else {
					representation = entries;
				}
			}
			if ((allocator != null || alignment != null || representation != null) && current.kind != TokenKind.CLASS && current.kind != TokenKind.STRUCT) {
				fail (current.span, "storage policies require a Class or record declaration");
				return null;
			}
			if (foreign_export != null && current.kind != TokenKind.CLASS) {
				fail (current.span, "Class CExport requires one native Class declaration");
				return null;
			}
			if (com_export != null && (foreign_export == null || current.kind != TokenKind.CLASS)) {
				fail (com_export.span, "selected COMExport requires an explicit Class CExport bridge");
				return null;
			}
			if (gobject_export != null && (foreign_export == null || current.kind != TokenKind.CLASS)) {
				fail (gobject_export.span, "selected GObjectExport requires an explicit Class CExport bridge");
				return null;
			}
			if (gobject_export != null && com_export != null) {
				bool modern_c = false, modern_com = false, modern_go = false;
				foreach (var entry in foreign_export.entries) {
					modern_c |= entry.key.spelling () == "profile" && entry.decoded_value == "declarations-v1";
				}
				foreach (var entry in com_export.entries) {
					modern_com |= entry.key.spelling () == "profile" && entry.decoded_value == "declarations-v1";
				}
				foreach (var entry in gobject_export.entries) {
					modern_go |= entry.key.spelling () == "profile" && entry.decoded_value == "declarations-v1";
				}
				if (!modern_c || !modern_com || !modern_go) {
					fail (gobject_export.span, "COMExport and GObjectExport are incompatible selected foreign personalities");
					return null;
				}
			}
			if (concurrency != ConcurrencyKind.NONE && current.kind != TokenKind.CLASS && !(current.kind == TokenKind.IDENTIFIER && current.spelling () == "interface" && (concurrency == ConcurrencyKind.SHARED || concurrency == (ConcurrencyKind.SHARED | ConcurrencyKind.MONITOR)))) {
				fail (current.span, "concurrency policies require a native Class or Shared interface declaration");
				return null;
			}
			if (current.kind == TokenKind.OPEN_BRACKET && next_is (TokenKind.IDENTIFIER) && DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.EXCEPTION_ROOT) {
				if (!advance ()) {
					return null;
				}
				exception_root = current;
				if (!advance () || expect (TokenKind.CLOSE_BRACKET, "ExceptionRoot takes no arguments") == null) {
					return null;
				}
				if (current.kind != TokenKind.CLASS) {
					fail (current.span, "ExceptionRoot must nominate a class declaration");
					return null;
				}
			}
			if (current.kind == TokenKind.ENUM) {
				var declaration = parse_enum ();
				if (declaration == null) {
					return null;
				}
				declaration.module_internal = module_internal;
				enums.add (declaration);
				continue;
			}
			if (current.kind == TokenKind.CONST) {
				var declaration = parse_constant ();
				if (declaration == null) {
					return null;
				}
				declaration.module_internal = module_internal;
				constants.add (declaration);
				continue;
			}
			bool interface_contract = current.kind == TokenKind.IDENTIFIER && current.spelling () == "interface" && next_is (TokenKind.IDENTIFIER) && following_is (TokenKind.OPEN_BRACE);
			if (current.kind == TokenKind.STRUCT || current.kind == TokenKind.CLASS || interface_contract) {
				var declaration = parse_native_instance (interface_contract);
				if (declaration == null) {
					return null;
				}
				declaration.module_internal = module_internal;
				declaration.allocator = allocator;
				declaration.alignment = alignment;
				declaration.representation = representation;
				if (foreign_export != null) {
					((ClassDeclarationSyntax) declaration).foreign_export = foreign_export;
				}
				if (com_export != null) {
					((ClassDeclarationSyntax) declaration).com_export = com_export;
				}
				if (gobject_export != null) {
					((ClassDeclarationSyntax) declaration).gobject_export = gobject_export;
				}
				if (concurrency != ConcurrencyKind.NONE) {
					declaration.concurrency_policy = new ConcurrencyPolicy (concurrency);
				}
				if (declaration.keyword.kind == TokenKind.CLASS) {
					((ClassDeclarationSyntax) declaration).exception_root = exception_root;
					classes.add ((ClassDeclarationSyntax) declaration);
				} else {
					structs.add ((StructDeclarationSyntax) declaration);
				}
				continue;
			}
			var function = parse_function ();
			if (function == null) {
				return null;
			}
			function.module_internal = module_internal;
			functions.add (function);
		}
		var unit = new CompilationUnitSyntax (source, functions, current, structs);
		unit.namespace_name = namespace_name;
		foreach (var imported in imports) {
			unit.imports.add (imported);
		}
		foreach (var imported in c_classes) {
			unit.c_classes.add (imported);
		}
		foreach (var runtime in runtimes) {
			unit.async_runtimes.add (runtime);
		}
		foreach (var declaration in enums) {
			unit.enums.add (declaration);
		}
		foreach (var declaration in constants) {
			unit.constants.add (declaration);
		}
		foreach (var declaration in classes) {
			unit.classes.add (declaration);
		}
		foreach (var contract in com_interfaces) {
			unit.com_interfaces.add (contract);
		}
		return unit;
	}

	private EnumDeclarationSyntax? parse_enum() {
		var keyword = expect (TokenKind.ENUM, "expected 'enum'");
		var name = keyword == null ? null : expect (TokenKind.IDENTIFIER, "expected enum name");
		if (name == null) {
			return null;
		}
		var parameters = current.kind == TokenKind.LESS ? parse_type_parameters () : new GenericArray<Token> ();
		if (parameters == null) {
			return null;
		}
		if (expect (TokenKind.OPEN_BRACE, "expected '{' after enum name") == null) {
			return null;
		}
		var variants = new GenericArray<EnumVariantSyntax> ();
		while (current.kind != TokenKind.CLOSE_BRACE) {
			var variant = expect (TokenKind.IDENTIFIER, "expected enum variant name");
			if (variant == null) {
				return null;
			}
			var fields = new GenericArray<EnumPayloadSyntax> ();
			var end = variant.span;
			if (current.kind == TokenKind.OPEN_PAREN) {
				if (!advance ()) {
					return null;
				}
				if (current.kind != TokenKind.CLOSE_PAREN) {
					while (true) {
						Token? owned_keyword = null;
						if (current.kind == TokenKind.BORROWED) {
							fail (current.span, "borrowed enum payloads remain unsupported");
							return null;
						}
						if (current.kind == TokenKind.OWNED) {
							owned_keyword = current;
							if (!advance ()) {
								return null;
							}
						}
						var type = parse_type ("expected enum payload type");
						var field = type == null ? null : expect (TokenKind.IDENTIFIER, "expected enum payload field name");
						if (field == null) {
							return null;
						}
						var payload = new EnumPayloadSyntax (type, field);
						payload.owned_keyword = owned_keyword;
						fields.add (payload);
						if (current.kind != TokenKind.COMMA) {
							break;
						}
						if (!advance ()) {
							return null;
						}
					}
				}
				var close = expect (TokenKind.CLOSE_PAREN, "expected ')' after enum payload fields");
				if (close == null) {
					return null;
				}
				end = close.span;
			}
			variants.add (new EnumVariantSyntax (variant, fields, end));
			if (current.kind != TokenKind.COMMA) {
				break;
			}
			if (!advance ()) {
				return null;
			}
		}
		var close = expect (TokenKind.CLOSE_BRACE, "expected ',' or '}' after enum variant");
		if (close == null) {
			return null;
		}
		if (current.kind == TokenKind.SEMICOLON) {
			fail (current.span, "enum declarations have no trailing semicolon");
			return null;
		}
		var declaration = new EnumDeclarationSyntax (keyword, name, variants, close);
		declaration.type_parameters = parameters;
		return declaration;
	}

	private MatchStatementSyntax? parse_match() {
		var keyword = expect (TokenKind.MATCH, "expected 'match'");
		if (keyword == null || expect (TokenKind.OPEN_PAREN, "expected '(' after 'match'") == null) {
			return null;
		}
		var scrutinee = current.kind == TokenKind.MOVE ? parse_owned_initializer (true) : parse_expression (0, 0);
		if (scrutinee == null || expect (TokenKind.CLOSE_PAREN, "expected ')' after match scrutinee") == null || expect (TokenKind.OPEN_BRACE, "expected '{' before match arms") == null) {
			return null;
		}
		var arms = new GenericArray<EnumArmSyntax> ();
		while (current.kind != TokenKind.CLOSE_BRACE) {
			var arm_keyword = current;
			Token? qualifier = null;
			Token? variant = null;
			var type_arguments = new GenericArray<TypeNameSyntax> ();
			var bindings = new GenericArray<EnumBindingSyntax> ();
			if (current.kind == TokenKind.ELSE) {
				if (!advance ()) {
					return null;
				}
			} else {
				if (expect (TokenKind.CASE, "expected 'case', 'else' or '}' in match") == null) {
					return null;
				}
				qualifier = expect (TokenKind.IDENTIFIER, "expected exact enum type qualifier");
				if (qualifier == null) {
					return null;
				}
				if (current.kind == TokenKind.LESS) {
					type_arguments = parse_type_arguments ();
					if (type_arguments == null) {
						return null;
					}
				}
				if (expect (TokenKind.DOT, "expected '.' after enum pattern qualifier") == null) {
					return null;
				}
				variant = expect (TokenKind.IDENTIFIER, "expected enum pattern variant");
				if (variant == null || expect (TokenKind.OPEN_PAREN, "enum patterns require parentheses") == null) {
					return null;
				}
				if (current.kind != TokenKind.CLOSE_PAREN) {
					while (true) {
						var first = expect (TokenKind.IDENTIFIER, "expected payload binding or '_'");
						if (first == null) {
							return null;
						}
						Token? field = null;
						var binding = first;
						if (current.kind == TokenKind.EQUAL) {
							field = first;
							if (!advance ()) {
								return null;
							}
							binding = expect (TokenKind.IDENTIFIER, "expected payload binding or '_' after '='");
							if (binding == null) {
								return null;
							}
						}
						bindings.add (new EnumBindingSyntax (binding, field));
						if (current.kind != TokenKind.COMMA) {
							break;
						}
						if (!advance ()) {
							return null;
						}
					}
				}
				if (expect (TokenKind.CLOSE_PAREN, "expected ')' after enum pattern bindings") == null) {
					return null;
				}
			}
			if (expect (TokenKind.COLON, "expected ':' after match pattern") == null) {
				return null;
			}
			var body = parse_block ("match arm");
			if (body == null) {
				return null;
			}
			var arm = new EnumArmSyntax (arm_keyword, qualifier, variant, bindings, body);
			arm.type_arguments = type_arguments;
			arms.add (arm);
		}
		var close = expect (TokenKind.CLOSE_BRACE, "expected '}' after match arms");
		return close == null ? null : new MatchStatementSyntax (keyword, scrutinee, arms, close);
	}

	private GenericArray<WhereClauseSyntax>? parse_where_clauses(bool permitted) {
		var clauses = new GenericArray<WhereClauseSyntax> ();
		while (current.kind == TokenKind.IDENTIFIER && current.spelling () == "where") {
			var keyword = current;
			if (!permitted) {
				fail (keyword.span, "where clauses require a top-level generic function");
				return null;
			}
			if (!advance ()) {
				return null;
			}
			var parameter = expect (TokenKind.IDENTIFIER, "expected type parameter name after 'where'");
			if (parameter == null) {
				return null;
			}
			var colon = expect (TokenKind.COLON, "expected ':' after where type parameter");
			if (colon == null) {
				return null;
			}
			foreach (var prior in clauses) {
				if (prior.type_parameter.spelling () == parameter.spelling ()) {
					fail (parameter.span, "duplicate where clause for type parameter '%s'; combine capabilities in one clause".printf (parameter.spelling ()));
					return null;
				}
			}
			var capabilities = new GenericArray<Token> ();
			var capability_commas = new GenericArray<Token> ();
			while (true) {
				var capability = expect (TokenKind.IDENTIFIER, "expected capability name; empty lists and trailing commas are unsupported");
				if (capability == null) {
					return null;
				}
				foreach (var prior in capabilities) {
					if (prior.spelling () == capability.spelling ()) {
						fail (capability.span, "duplicate capability '%s' for type parameter '%s'".printf (capability.spelling (), parameter.spelling ()));
						return null;
					}
				}
				capabilities.add (capability);
				if (current.kind != TokenKind.COMMA) {
					break;
				}
				capability_commas.add (current);
				if (!advance ()) {
					return null;
				}
			}
			clauses.add (new WhereClauseSyntax (keyword, parameter, colon, capabilities, capability_commas));
		}
		return clauses;
	}

	private NativeInstanceDeclarationSyntax? parse_native_instance(bool interface_contract = false, bool foreign_declaration = false, bool foreign_interface = false) {
		var keyword = expect (current.kind, "expected native type declaration");
		if ((interface_contract || foreign_interface) && keyword != null) {
			keyword = new Token (TokenKind.CLASS, keyword.span);
		}
		string category = keyword.kind == TokenKind.CLASS ? "class" : "struct";
		if (keyword == null) {
			return null;
		}
		var name = expect (TokenKind.IDENTIFIER, "expected %s name".printf (category));
		if (name == null) {
			return null;
		}
		var type_parameters = new GenericArray<Token> ();
		if (current.kind == TokenKind.LESS) {
			if (interface_contract) {
				fail (current.span, "native interfaces are nongeneric fieldless contracts");
				return null;
			}
			type_parameters = parse_type_parameters ();
			if (type_parameters == null) {
				return null;
			}
		}
		bool exact_heap_class = false;
		var class_clauses = new GenericArray<WhereClauseSyntax> ();
		if (type_parameters.length != 0 && keyword.kind == TokenKind.CLASS) {
			class_clauses = parse_where_clauses (true);
			if (class_clauses == null) {
				return null;
			}
			foreach (var clause in class_clauses) {
				foreach (var bound in clause.capabilities) {
					if (bound.spelling () != "ExactHeapClass") {
						continue;
					}
					exact_heap_class = true;
				}
			}
		} else if (type_parameters.length != 0 && current.kind == TokenKind.IDENTIFIER && current.spelling () == "where") {
			class_clauses = parse_where_clauses (true);
			if (class_clauses == null) {
				return null;
			}
			foreach (var clause in class_clauses) {
				foreach (var bound in clause.capabilities) {
					if (bound.spelling () != "Ownable") {
						fail (bound.span, "where clauses on generic structs are unsupported");
						return null;
					}
				}
			}
		}

		TypeNameSyntax? parent_class = null;
		if (current.kind == TokenKind.COLON && keyword.kind == TokenKind.CLASS) {
			if (interface_contract) {
				fail (current.span, "native interface inheritance is outside this finite contract");
				return null;
			}
			if (!advance ()) {
				return null;
			}
			parent_class = parse_type ("expected one base class after ':'");
			if (parent_class == null) {
				return null;
			}
		}
		var open = expect (TokenKind.OPEN_BRACE, "expected '{' after %s name".printf (category));
		if (open == null) {
			return null;
		}
		var fields = new GenericArray<StructFieldDeclarationSyntax> ();
		var members = new GenericArray<SyntaxNode> ();
		while (current.kind != TokenKind.CLOSE_BRACE) {
			ForeignPolicySyntax? foreign_member = null;
			var foreign_channels = new GenericArray<ForeignPolicySyntax> ();
			while (current.kind == TokenKind.OPEN_BRACKET && next_is (TokenKind.IDENTIFIER) && (lookahead.spelling () == "Foreign" || lookahead.spelling () == "ForeignChannel")) {
				var attribute = lookahead;
				var kind = DeclarationPolicyRegistry.lookup (attribute.spelling ());
				var entries = parse_ccode (kind);
				if (entries == null) {
					return null;
				}
				var policy = new ForeignPolicySyntax (attribute, entries);
				if (kind == DeclarationPolicyId.FOREIGN) {
					if (foreign_member != null) {
						fail (attribute.span, "duplicate Foreign member selection");
						return null;
					}
					foreign_member = policy;
				} else {
					foreign_channels.add (policy);
				}
			}
			if (interface_contract) {
				var result = parse_type ("expected interface operation result type");
				var operation = result == null ? null : expect (TokenKind.IDENTIFIER, "expected interface operation name");
				var requirement = operation == null ? null : parse_function_tail (result, operation, null, null, null, null, null, false, true);
				if (requirement == null) {
					return null;
				}
				requirement.dispatch = MemberDispatchSyntax.VIRTUAL;
				requirement.foreign_member = foreign_member;
				foreach (var channel in foreign_channels) {
					requirement.foreign_channels.add (channel);
				}
				members.add (requirement);
				continue;
			}
			if (current.kind == TokenKind.IDENTIFIER && current.spelling () == "signal" && next_is (TokenKind.IDENTIFIER) && lookahead.spelling () == "void") {
				if (keyword.kind != TokenKind.CLASS || foreign_member == null || type_parameters.length != 0) {
					fail (current.span, "signal requires a selected nongeneric native Class member");
					return null;
				}
				if (!advance ()) {
					return null;
				}
				var result = parse_type ("signal requires void result");
				var signal_name = result == null ? null : expect (TokenKind.IDENTIFIER, "expected signal name");
				var signal = signal_name == null ? null : parse_function_tail (result, signal_name, null, null, null, null, null, false, false, null, true);
				if (signal == null) {
					return null;
				}
				signal.is_signal = true;
				signal.foreign_member = foreign_member;
				foreach (var channel in foreign_channels) {
					signal.foreign_channels.add (channel);
				}
				members.add (signal);
				continue;
			}
			if (current.kind == TokenKind.ASYNC) {
				fail (current.span, "async methods and virtual async slots are excluded; use a native free async function");
				return null;
			}
			if (current.kind == TokenKind.IDENTIFIER && (current.spelling () == "virtual" || current.spelling () == "override") && next_is (TokenKind.ASYNC)) {
				fail (lookahead.span, "async methods and virtual async slots are excluded; use a native free async function");
				return null;
			}
			Token? private_keyword = null;
			if (current.kind == TokenKind.IDENTIFIER && current.spelling () == "private" && (next_is (TokenKind.OWNED) || (next_is (TokenKind.IDENTIFIER) && !following_is (TokenKind.SEMICOLON) && !following_is (TokenKind.OPEN_PAREN)))) {
				if (keyword.kind != TokenKind.CLASS) {
					fail (current.span, "private fields require a native Class declaration");
					return null;
				}
				private_keyword = current;
				if (!advance ()) {
					return null;
				}
			}
			var dispatch = MemberDispatchSyntax.DIRECT;
			if (current.kind == TokenKind.IDENTIFIER && (current.spelling () == "virtual" || current.spelling () == "override") && next_is (TokenKind.IDENTIFIER)) {
				if (keyword.kind != TokenKind.CLASS) {
					fail (current.span, "virtual and override require a class member");
					return null;
				}
				dispatch = current.spelling () == "virtual" ? MemberDispatchSyntax.VIRTUAL : MemberDispatchSyntax.OVERRIDE;
				if (!advance ()) {
					return null;
				}
			}
			Token? readonly_keyword = null;
			if (current.kind == TokenKind.IDENTIFIER && current.spelling () == "readonly" && next_is (TokenKind.IDENTIFIER)) {
				readonly_keyword = current;
				if (!advance ()) {
					return null;
				}
			}
			Token? lazy_keyword = null;
			if (current.kind == TokenKind.IDENTIFIER && current.spelling () == "lazy" && next_is (TokenKind.IDENTIFIER) && lookahead.spelling () == "property" && !following_is (TokenKind.SEMICOLON) && !following_is (TokenKind.OPEN_PAREN)) {
				lazy_keyword = current;
				if (!advance ()) {
					return null;
				}
			}
			if (current.kind == TokenKind.IDENTIFIER && current.spelling () == "property") {
				if (private_keyword != null) {
					fail (private_keyword.span, "private applies only to Class fields");
					return null;
				}
				if (type_parameters.length != 0 && keyword.kind != TokenKind.CLASS) {
					fail (current.span, "generic structs permit fields only; properties are unsupported");
					return null;
				}
				var property = parse_property (foreign_declaration);
				if (property == null) {
					return null;
				}
				if (readonly_keyword != null) {
					fail (readonly_keyword.span, "readonly applies only to class string snapshot fields");
					return null;
				}
				property.dispatch = dispatch;
				property.lazy_keyword = lazy_keyword;
				property.foreign_member = foreign_member;
				foreach (var channel in foreign_channels) {
					property.foreign_channels.add (channel);
				}
				members.add (property);
				continue;
			}
			if (current.kind == TokenKind.IDENTIFIER && (current.spelling () == "init" || current.spelling () == "deinit")) {
				if (private_keyword != null) {
					fail (private_keyword.span, "private applies only to Class fields");
					return null;
				}
				if (keyword.kind != TokenKind.CLASS) {
					fail (current.span, "struct lifecycle members are unsupported");
					return null;
				}
				if (dispatch != MemberDispatchSyntax.DIRECT || readonly_keyword != null) {
					fail (current.span, "lifecycle members cannot be virtual, override or readonly");
					return null;
				}
				var lifecycle_name = current;
				if (!advance ()) {
					return null;
				}
				var lifecycle = parse_function_tail (null, lifecycle_name, null, null, null, null, null, false, false, null, foreign_declaration);
				if (lifecycle == null) {
					return null;
				}
				lifecycle.foreign_member = foreign_member;
				foreach (var channel in foreign_channels) {
					lifecycle.foreign_channels.add (channel);
				}
				members.add (lifecycle);
				continue;
			}
			var owned_keyword = current.kind == TokenKind.OWNED ? current : null;
			if (owned_keyword != null && !advance ()) {
				return null;
			}
			var field_type = parse_type ("expected field type or '}' after %s fields".printf (category));
			if (field_type == null) {
				return null;
			}
			var field_name = expect (TokenKind.IDENTIFIER, "expected field name");
			if (field_name == null) {
				return null;
			}
			if (current.kind == TokenKind.LESS && (keyword.kind != TokenKind.CLASS || type_parameters.length == 0)) {
				fail (current.span, "generic members require a general native Class template");
				return null;
			}
			if (current.kind == TokenKind.OPEN_PAREN || current.kind == TokenKind.LESS) {
				if (private_keyword != null) {
					fail (private_keyword.span, "private applies only to Class fields");
					return null;
				}
				if (type_parameters.length != 0 && keyword.kind != TokenKind.CLASS) {
					fail (current.span, "generic structs permit fields only; methods are unsupported");
					return null;
				}
				var method = parse_function_tail (field_type, field_name, owned_keyword, null, null, null, null, false, false, null, foreign_declaration);
				if (method == null) {
					return null;
				}
				if (readonly_keyword != null) {
					fail (readonly_keyword.span, "readonly applies only to class string snapshot fields");
					return null;
				}
				method.dispatch = dispatch;
				method.foreign_member = foreign_member;
				foreach (var channel in foreign_channels) {
					method.foreign_channels.add (channel);
				}
				members.add (method);
				continue;
			}
			if (foreign_member != null || foreign_channels.length != 0) {
				fail (field_name.span, "Foreign selects constructors, methods, properties or signals; storage fields remain private");
				return null;
			}
			if (owned_keyword != null && keyword.kind != TokenKind.CLASS && type_parameters.length != 0 && class_clauses.length == 0) {
				fail (owned_keyword.span, "owned %s fields are unsupported".printf (category));
				return null;
			}
			if (dispatch != MemberDispatchSyntax.DIRECT) {
				fail (field_name.span, "virtual and override apply only to methods and properties");
				return null;
			}
			var semicolon = expect (TokenKind.SEMICOLON, "expected ';' after field declaration");
			if (semicolon == null) {
				return null;
			}
			var field = new StructFieldDeclarationSyntax (field_type, field_name, semicolon, owned_keyword);
			field.private_keyword = private_keyword;
			field.readonly_keyword = readonly_keyword;
			fields.add (field);
			members.add (field);
		}
		var close = expect (TokenKind.CLOSE_BRACE, "expected '}' after %s fields".printf (category));
		if (close == null) {
			return null;
		}
		if (interface_contract) {
			if (members.length == 0) {
				fail (name.span, "native interface requires at least one typed operation");
				return null;
			}
			// The empty base initializer only installs the existing hierarchy
			// header during concrete construction. Source cannot construct it.
			members.add (interface_prerequisites (name.span.file.native_interface).members[0]);
		}
		if (keyword.kind == TokenKind.CLASS) {
			var declaration = new ClassDeclarationSyntax (keyword, name, open, fields, close, members);
			declaration.is_interface = interface_contract;
			declaration.parent_class = parent_class;
			declaration.type_parameters = type_parameters;
			declaration.exact_heap_class = exact_heap_class;
			declaration.where_clauses = class_clauses;
			return declaration;
		}
		var structure = new StructDeclarationSyntax (keyword, name, open, fields, close, members);
		structure.type_parameters = type_parameters;
		structure.where_clauses = class_clauses;
		return structure;
	}

	private static ClassDeclarationSyntax interface_prerequisites(bool native_interface = false) {
		// As with the intrinsic UTF-8 factory body, generated syntax is never
		// treated as source authority. Nonconstructibility and complete concrete
		// slot implementation make the requirement body unreachable.
		var parsed = Parser.parse (new SourceFile.from_text ("<native-interface>", "class __Contract { init() {} int requirement() { return 0; } }", native_interface));
		assert (parsed.unit != null);
		return parsed.unit.classes[0];
	}

	private PropertyDeclarationSyntax? parse_property(bool foreign_declaration = false) {
		var keyword = current;
		if (!advance ()) {
			return null;
		}
		bool borrowed = current.kind == TokenKind.BORROWED;
		if (borrowed && !advance ()) {
			return null;
		}
		Token? owned_keyword = null;
		if (current.kind == TokenKind.OWNED) {
			owned_keyword = current;
			if (!advance ()) {
				return null;
			}
		}
		var type = parse_type ("expected property value type");
		var name = type == null ? null : expect (TokenKind.IDENTIFIER, "expected property name");
		TypeNameSyntax? throws_class = null;
		if (name != null && current.kind == TokenKind.THROWS) {
			if (!advance ()) {
				return null;
			}
			throws_class = parse_type ("expected exception class bound after 'throws'");
			if (throws_class == null) {
				return null;
			}
		}
		if (name == null || expect (TokenKind.OPEN_BRACE, "computed property requires '{' and accessor bodies; initializers and indexed properties are unsupported") == null) {
			return null;
		}
		PropertyAccessorSyntax? getter = null;
		PropertyAccessorSyntax? setter = null;
		while (current.kind != TokenKind.CLOSE_BRACE) {
			var accessor = current;
			bool get = accessor.kind == TokenKind.IDENTIFIER && accessor.spelling () == "get";
			bool set = accessor.kind == TokenKind.IDENTIFIER && accessor.spelling () == "set";
			if (!get && !set) {
				fail (accessor.span, "expected 'get' or 'set' accessor in computed property");
				return null;
			}
			if (get ? getter != null : setter != null) {
				fail (accessor.span, "duplicate %s accessor for property '%s'".printf (get ? "getter" : "setter", name.spelling ()));
				return null;
			}
			if (get && setter != null) {
				fail (accessor.span, "getter must precede setter in a computed property");
				return null;
			}
			if (!advance ()) {
				return null;
			}
			ParameterSyntax? parameter = null;
			if (set) {
				if (expect (TokenKind.OPEN_PAREN, "setter requires exactly one explicit parameter: set(T name)") == null) {
					return null;
				}
				Token? owned_parameter = null;
				Token? borrowed_parameter = null;
				if ((borrowed || foreign_declaration) && current.kind == TokenKind.OWNED) {
					owned_parameter = current;
					if (!advance ()) {
						return null;
					}
				}
				if (foreign_declaration && current.kind == TokenKind.BORROWED) {
					borrowed_parameter = current;
					if (!advance ()) {
						return null;
					}
				}
				if (current.kind == TokenKind.OWNED || current.kind == TokenKind.BORROWED) {
					fail (current.span, "setter parameter must be a plain property value; ownership qualifiers are unsupported");
					return null;
				}
				if (borrowed && owned_parameter == null) {
					fail (current.span, "borrowed owner property replacement requires an explicit owned setter parameter");
					return null;
				}
				var parameter_type = parse_type ("setter requires exactly one explicit parameter type");
				var parameter_name = parameter_type == null ? null : expect (TokenKind.IDENTIFIER, "setter requires an explicit parameter name; no implicit value binding exists");
				if (parameter_name == null || expect (TokenKind.CLOSE_PAREN, "setter requires exactly one explicit parameter") == null) {
					return null;
				}
				parameter = new ParameterSyntax (parameter_type, parameter_name, borrowed_parameter, owned_parameter);
			}
			BlockStatementSyntax? body;
			if (foreign_declaration) {
				var end = expect (TokenKind.SEMICOLON, "imported property accessors require bodyless declarations ending in ';'");
				body = end == null ? null : new BlockStatementSyntax (end, new GenericArray<StatementSyntax> (), end);
			} else {
				body = parse_block (get ? "getter body (no explicit parameters)" : "setter body");
			}
			if (body == null) {
				return null;
			}
			var declaration = new PropertyAccessorSyntax (accessor, parameter, body);
			if (get) {
				getter = declaration;
			} else {
				setter = declaration;
			}
		}
		var close = current;
		if (getter == null) {
			fail (name.span, "property '%s' requires one getter; empty and setter-only properties are unsupported".printf (name.spelling ()));
			return null;
		}
		if (borrowed && !(getter.span.file.native_interface && getter.body.statements.length == 0)) {
			var returned = getter.body.statements.length == 1 ? getter.body.statements[0] as ReturnStatementSyntax : null;
			var projection = returned == null ? null : returned.expression as FieldAccessExpressionSyntax;
			if (projection == null || projection.aggregate != null || projection.identifier.kind != TokenKind.THIS || projection.indirect) {
				fail (getter.span, "borrowed property getter requires exactly return this.owned_field; effects and escaped results are excluded");
				return null;
			}
		}
		if (!advance ()) {
			return null;
		}
		var property = new PropertyDeclarationSyntax (keyword, type, name, getter, setter, close);
		property.owned_keyword = owned_keyword;
		property.is_borrowed = borrowed;
		property.throws_class = throws_class;
		return property;
	}

	private VectorInitializerSyntax? parse_vector_initializer(Token open, bool array = false) {
		var lanes = new GenericArray<ExpressionSyntax> ();
		var commas = new GenericArray<Token> ();
		while (true) {
			if (current.kind == TokenKind.CLOSE_BRACE) {
				fail (current.span, array ? "array initializer requires elements; empty initializers and trailing commas are unsupported" : "vector initializer requires lane expressions; empty initializers and trailing commas are unsupported");
				return null;
			}
			ExpressionSyntax? lane;
			if (array && current.kind == TokenKind.OPEN_BRACE) {
				var entry_open = current;
				if (!advance ()) {
					return null;
				}
				var entry = parse_struct_initializer (entry_open);
				lane = entry == null ? null : new ArrayStructInitializerSyntax (entry);
			} else {
				lane = parse_expression (0, 1);
			}
			if (lane == null) {
				return null;
			}
			lanes.add (lane);
			if (current.kind != TokenKind.COMMA) {
				break;
			}
			commas.add (current);
			if (!advance ()) {
				return null;
			}
		}
		var close = expect (TokenKind.CLOSE_BRACE, "expected '}' after vector lanes");
		return close == null ? null : bounded (new VectorInitializerSyntax (open, lanes, commas, close), open.span) as VectorInitializerSyntax;
	}

	private StructInitializerSyntax? parse_struct_initializer(Token open) {
		if (open == null) {
			return null;
		}
		var fields = new GenericArray<FieldInitializerSyntax> ();
		var commas = new GenericArray<Token> ();
		if (current.kind == TokenKind.CLOSE_BRACE) {
			var close = current;
			return advance () ? new StructInitializerSyntax (open, fields, commas, close) : null;
		}
		while (true) {
			var name = expect (TokenKind.IDENTIFIER, "expected initializer field name; empty initializers and trailing commas are unsupported");
			if (name == null) {
				return null;
			}
			var equals_token = expect (TokenKind.EQUAL, "expected '=' after initializer field name");
			if (equals_token == null) {
				return null;
			}
			if (current.kind == TokenKind.OPEN_BRACE) {
				var nested_open = current;
				if (!advance ()) {
					return null;
				}
				var initializer = parse_struct_initializer (nested_open);
				if (initializer == null) {
					return null;
				}
				fields.add (new FieldInitializerSyntax.nested (name, equals_token, initializer));
			} else {
				var expression = current.kind == TokenKind.MOVE ? parse_owned_initializer (false, true) : parse_expression (0, 0);
				if (expression == null) {
					return null;
				}
				fields.add (new FieldInitializerSyntax (name, equals_token, expression));
			}
			if (current.kind != TokenKind.COMMA) {
				break;
			}
			commas.add (current);
			if (!advance ()) {
				return null;
			}
		}
		var close = expect (TokenKind.CLOSE_BRACE, "expected '}' after struct initializer");
		return close == null ? null : new StructInitializerSyntax (open, fields, commas, close);
	}

	private ExpressionSyntax? parse_field_access(Token identifier, int recursion_depth = 0) {
		var dot = expect (current.kind, "expected field access operator");
		if (dot == null) {
			return null;
		}
		var name = expect (TokenKind.IDENTIFIER, "expected field name after '%s'".printf (dot.spelling ()));
		if (name == null) {
			return null;
		}
		if (current.kind == TokenKind.OPEN_PAREN || begins_generic_call ()) {
			if (dot.kind == TokenKind.ARROW) {
				fail (dot.span, "pointer receiver calls are unsupported; use a direct struct local or 'this'");
				return null;
			}
			return parse_call (name, recursion_depth, identifier, dot);
		}
		var field = new FieldAccessExpressionSyntax (identifier, dot, name);
		while (current.kind == TokenKind.DOT) {
			var next_dot = current;
			if (!advance ()) {
				return null;
			}
			var next_name = expect (TokenKind.IDENTIFIER, "expected nested field name");
			if (next_name == null) {
				return null;
			}
			if (current.kind == TokenKind.OPEN_PAREN || begins_generic_call ()) {
				return parse_call (next_name, recursion_depth, null, next_dot, false, field);
			}
			field = new FieldAccessExpressionSyntax.projection (field, next_dot, next_name);
		}
		return field;
	}

	private bool begins_qualified_local(Token first) {
		if (current.kind != TokenKind.DOT) {
			return false;
		}
		var probe = new Parser.from_cursor (this);
		return probe.parse_type_suffix (first) != null && probe.current.kind == TokenKind.IDENTIFIER;
	}

	private TypeNameSyntax? parse_type(string message, bool conversion = false) {
		if (current.kind == TokenKind.NONNULL) {
			var keyword = current;
			if (!advance ()) {
				return null;
			}
			if (current.kind == TokenKind.NONNULL) {
				fail (current.span, "duplicate nonnull qualifier");
				return null;
			}
			var underlying = parse_type ("expected exact reference type after 'nonnull'", conversion);
			return underlying == null ? null : new NonNullTypeSyntax (keyword, underlying);
		}
		if (current.kind == TokenKind.BORROWED) {
			fail (current.span, "'borrowed' is supported only on void* parameters; borrowed locals, results, and fields are unsupported");
			return null;
		}
		if (current.kind == TokenKind.OWNED) {
			fail (current.span, "'owned' is supported only on local void* declarations in OWN-1; owned parameters, results, and fields are unsupported");
			return null;
		}
		var identifier = expect (TokenKind.IDENTIFIER, message);
		if (identifier == null) {
			return null;
		}
		if (type_depth >= MAX_EXPRESSION_DEPTH) {
			fail (identifier.span, "type application nesting limit exceeded");
			return null;
		}
		type_depth++;
		var type = parse_type_suffix (identifier, conversion);
		type_depth--;
		return type;
	}

	private TypeNameSyntax? parse_type_suffix(Token initial_identifier, bool conversion = false) {
		if (initial_identifier.spelling () == "shared" && current.kind == TokenKind.IDENTIFIER) {
			var payload = parse_type ("expected a payload type after shared", conversion);
			return payload == null ? null : new SharedTypeSyntax (initial_identifier, payload);
		}
		// The qualified suffix may outlive current after advance, including in probes.
		Token identifier = initial_identifier;
		Token? qualifier = null;
		if (current.kind == TokenKind.DOT && next_is (TokenKind.IDENTIFIER)) {
			qualifier = identifier;
			if (!advance ()) {
				return null;
			}
			identifier = current;
			if (!advance ()) {
				return null;
			}
		}
		var stars = new GenericArray<Token> ();
		// Retain extra stars only to diagnose unsupported depth semantically.
		while (current.kind == TokenKind.STAR && (!conversion || !next_begins_expression ())) {
			stars.add (current);
			if (!advance ()) {
				return null;
			}
		}
		var element = new TypeNameSyntax (identifier, stars, qualifier);

		// In an expression, complete <decimal> syntax wins over comparison.
		// A star followed by an operand belongs to multiplication, not the type.
		if (current.kind != TokenKind.LESS || (conversion && !(next_is (TokenKind.INTEGER) && following_is (TokenKind.GREATER)))) {
			return allocation_element ? element : parse_array_suffix (element, conversion);
		}
		// Builtin vector spellings retain their literal-lane grammar, including
		// malformed lanes. Nominal applications cannot follow a pointer suffix.
		bool builtin_vector = false;
		switch (identifier.spelling ()) {
		case "bool": case "i8": case "u8": case "i16": case "u16": case "int": case "i32": case "u32": case "i64": case "u64": case "isize": case "usize": case "f32": case "f64": case "void": builtin_vector = true;
			break;
			default: break;
		}
		if (stars.length == 0 && !builtin_vector && !next_is (TokenKind.INTEGER)) {
			int channel_start = -1;
			if (qualifier == null) {
				if (identifier.spelling () == "Fn") {
					channel_start = 0;
				} else if (identifier.spelling () == "Closure") {
					channel_start = 1;
				} else if (identifier.spelling () == "CheckedClosure") {
					channel_start = 2;
				}
			}
			var arguments = parse_type_arguments (channel_start);
			if (arguments == null) {
				return null;
			}
			var nominal_application = new GenericTypeApplicationSyntax (identifier, arguments, SourceSpan (source, qualifier == null ? identifier.span.start : qualifier.span.start, current.span.start));
			nominal_application.namespace_qualifier = qualifier;
			type_applications.add (nominal_application);
			TypeNameSyntax application = nominal_application;
			while (current.kind == TokenKind.STAR) {
				application = new PointerTypeSyntax (application, current);
				if (!advance ()) {
					return null;
				}
			}
			return allocation_element ? application : parse_array_suffix (application, conversion);
		}
		var open = current;
		if (!advance ()) {
			return null;
		}
		var lanes = expect (TokenKind.INTEGER, "vector lane count must be a positive decimal integer literal");
		var close = lanes == null ? null : type_close ("expected '>' after vector lane count; lane expressions are unsupported");
		if (close == null) {
			return null;
		}
		if (!conversion && current.kind == TokenKind.LESS) {
			fail (current.span, "nested vectors are unsupported");
			return null;
		}
		TypeNameSyntax type = new VectorTypeSyntax (element, open, lanes, close);
		while (current.kind == TokenKind.STAR && (!conversion || !next_begins_expression ())) {
			type = new PointerTypeSyntax (type, current);
			if (!advance ()) {
				return null;
			}
		}
		return allocation_element ? type : parse_array_suffix (type, conversion);
	}

	private bool foreign_class_ahead() {
		var probe = new Parser.from_cursor (this);
		while (probe.current.kind == TokenKind.OPEN_BRACKET) {
			if (!probe.advance ()) {
				return false;
			}
			while (probe.current.kind != TokenKind.CLOSE_BRACKET) {
				if (probe.current.kind == TokenKind.EOF || !probe.advance ()) {
					return false;
				}
			}
			if (!probe.advance ()) {
				return false;
			}
		}
		return probe.current.kind == TokenKind.CLASS;
	}

	private GenericArray<CCodeEntrySyntax>? parse_ccode(DeclarationPolicyId policy = DeclarationPolicyId.C_CODE, bool object_policy = false) {
		if (expect (TokenKind.OPEN_BRACKET, "expected '[' before CCode") == null) {
			return null;
		}
		var attribute = expect (TokenKind.IDENTIFIER, "expected CCode attribute");
		if (attribute == null) {
			return null;
		}
		if (DeclarationPolicyRegistry.lookup (attribute.spelling ()) != policy) {
			fail (attribute.span, "unsupported declaration attribute; expected CCode");
			return null;
		}
		var entries = new GenericArray<CCodeEntrySyntax> ();
		bool member_policy = policy == DeclarationPolicyId.FOREIGN || policy == DeclarationPolicyId.FOREIGN_CHANNEL;
		bool foreign_policy = member_policy || policy == DeclarationPolicyId.C_IMPORT || policy == DeclarationPolicyId.C_EXPORT || policy == DeclarationPolicyId.COM_EXPORT || policy == DeclarationPolicyId.COM_IMPORT || policy == DeclarationPolicyId.GOBJECT_EXPORT || policy == DeclarationPolicyId.GOBJECT_IMPORT;
		if (foreign_policy && current.kind == TokenKind.CLOSE_BRACKET) {
			return advance () ? entries : null;
		}
		if (expect (TokenKind.OPEN_PAREN, foreign_policy ? "expected '(' after declaration attribute" : "expected '(' after CCode") == null) {
			return null;
		}
		if (foreign_policy && current.kind == TokenKind.CLOSE_PAREN) {
			if (!advance () || expect (TokenKind.CLOSE_BRACKET, "expected ']' after foreign policy") == null) {
				return null;
			}
			return entries;
		}
		var keys = new HashTable<string, bool> (str_hash, str_equal);
		while (true) {
			Token? key;
			if (policy == DeclarationPolicyId.ALLOCATOR && current.kind == TokenKind.RELEASE) {
				key = current;
				if (!advance ()) {
					return null;
				}
			} else {
				key = expect (TokenKind.IDENTIFIER, "expected CCode metadata key");
			}
			if (key == null) {
				return null;
			}
			string name = key.spelling ();
			bool member_key = policy == DeclarationPolicyId.FOREIGN ? name == "name" || name == "personalities" || name == "native" || name == "error_domain" || name == "errors" || name == "error_factory" || name == "null_status" : name == "parameter" || name == "direction" || name == "transfer" || name == "nullable" || name == "encoding" || name == "length" || name == "capacity" || name == "produced" || name == "scope" || name == "closure" || name == "destroy";
			if (member_policy ? !member_key : object_policy ? (name != "profile" && (policy == DeclarationPolicyId.GOBJECT_IMPORT ? name != "name" && name != "type" && name != "namespace" && name != "version" && name != "symbol_prefix" && name != "header" && name != "records" && name != "threading" : policy == DeclarationPolicyId.GOBJECT_EXPORT ? name != "type" && name != "namespace" && name != "version" : policy == DeclarationPolicyId.COM_IMPORT ? name != "name" && name != "iid" && name != "view" && name != "threading" : policy == DeclarationPolicyId.COM_EXPORT ? name != "value_iid" && name != "scale_iid" && name != "interfaces" && name != "threading" : policy == DeclarationPolicyId.C_IMPORT ? name != "name" && name != "lifetime" && name != "threading" && name != "bool_abi" : name != "name" && name != "property" && name != "bool_abi")) : (foreign_policy && name != "name" && name != "record_abi" && !((policy == DeclarationPolicyId.C_IMPORT || policy == DeclarationPolicyId.C_EXPORT) && name == "bool_abi") && !((policy == DeclarationPolicyId.C_IMPORT || policy == DeclarationPolicyId.GOBJECT_IMPORT) && (name == "header" || name == "pointer_abi" || name == "text_abi" || name == "buffer_abi" || name == "callback" || name == "callback_abi")))) {
				fail (key.span, "unsupported %s argument '%s'".printf (attribute.spelling (), name));
				return null;
			}
			if (policy == DeclarationPolicyId.C_CODE && name != "text_abi" && name != "buffer_abi" && name != "record_abi" && name != "callback" && name != "callback_abi" && name != "cname" && name != "cheader_filename" && name != "device") {
				fail (key.span, "unknown CCode metadata key '%s'".printf (name));
				return null;
			}
			if (keys.contains (name)) {
				fail (key.span, "duplicate CCode metadata key '%s'".printf (name));
				return null;
			}
			keys.insert (name, true);
			if (expect (TokenKind.EQUAL, "expected '=' after CCode metadata key") == null) {
				return null;
			}
			var value = expect (TokenKind.TEXT, "expected CCode metadata string literal");
			if (value == null) {
				return null;
			}
			// Metadata keeps VAPI's small escape vocabulary, independent of text.
			string raw = value.spelling ();
			var decoded = new StringBuilder ();
			for (int i = 1; i < raw.length - 1; i++) {
				char c = raw[i];
				if (c == '\\') {
					switch (raw[++i]) {
					case '"': c = '"';
						break;
					case '\\': c = '\\';
						break;
					case 'n': c = '\n';
						break;
					case 'r': c = '\r';
						break;
					case 't': c = '\t';
						break;
						default: fail (value.span, "invalid CCode metadata string escape");
						return null;
					}
				}
				decoded.append_c (c);
			}
			if (decoded.len == 0) {
				fail (value.span, "CCode metadata must be nonempty");
				return null;
			}
			entries.add (new CCodeEntrySyntax (key, value, decoded.str));
			if (current.kind != TokenKind.COMMA) {
				break;
			}
			if (!advance ()) {
				return null;
			}
		}
		if (expect (TokenKind.CLOSE_PAREN, "expected ')' after CCode metadata") == null || expect (TokenKind.CLOSE_BRACKET, "expected ']' after CCode") == null) {
			return null;
		}
		return entries;
	}

	private FunctionDeclarationSyntax? parse_function() {
		GenericArray<CCodeEntrySyntax>? ccode = null;
		GenericArray<CCodeEntrySyntax>? floating_point = null;
		ForeignPolicySyntax? foreign_policy = null;
		bool utf8_factory = false;
		if (current.kind == TokenKind.OPEN_BRACKET && next_is (TokenKind.IDENTIFIER) && (DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.C_IMPORT || DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.C_EXPORT || DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.GOBJECT_IMPORT)) {
			var attribute = lookahead;
			var entries = parse_ccode (DeclarationPolicyRegistry.lookup (attribute.spelling ()));
			if (entries == null) {
				return null;
			}
			foreign_policy = new ForeignPolicySyntax (attribute, entries);
			if (current.kind == TokenKind.OPEN_BRACKET || current.kind == TokenKind.EXTERN || current.kind == TokenKind.EXPORT) {
				fail (current.span, "CImport/CExport cannot combine with another callable policy or legacy extern/export");
				return null;
			}
		} else if (current.kind == TokenKind.OPEN_BRACKET && next_is (TokenKind.IDENTIFIER) && DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.UTF8_MESSAGE_FACTORY) {
			if (!advance () || !advance () || expect (TokenKind.CLOSE_BRACKET, "Utf8MessageFactory takes no arguments") == null) {
				return null;
			}
			utf8_factory = true;
		} else if (current.kind == TokenKind.OPEN_BRACKET && next_is (TokenKind.IDENTIFIER) && DeclarationPolicyRegistry.lookup (lookahead.spelling ()) == DeclarationPolicyId.FLOATING_POINT) {
			floating_point = parse_ccode (DeclarationPolicyId.FLOATING_POINT);
			if (floating_point == null) {
				return null;
			}
		} else if (current.kind == TokenKind.OPEN_BRACKET) {
			ccode = parse_ccode ();
			if (ccode == null) {
				return null;
			}
		}

		Token? extern_keyword = null;
		Token? export_keyword = null;
		Token? abi_identifier = null;
		if (current.kind == TokenKind.EXTERN || current.kind == TokenKind.EXPORT) {
			var keyword = current;
			if (keyword.kind == TokenKind.EXTERN) {
				extern_keyword = keyword;
			} else {
				export_keyword = keyword;
			}
			if (!advance () || expect (TokenKind.OPEN_PAREN, "expected '(' after '%s'".printf (keyword.spelling ())) == null) {
				return null;
			}
			abi_identifier = expect (TokenKind.IDENTIFIER, "expected foreign ABI identifier");
			if (abi_identifier == null || expect (TokenKind.CLOSE_PAREN, "expected ')' after foreign ABI identifier") == null) {
				return null;
			}
			if (current.kind == TokenKind.EXTERN || current.kind == TokenKind.EXPORT) {
				fail (current.span, "extern and export cannot be combined or repeated");
				return null;
			}
		}
		var async_keyword = current.kind == TokenKind.ASYNC ? current : null;
		if (async_keyword != null) {
			if (extern_keyword != null || export_keyword != null || foreign_policy != null) {
				fail (async_keyword.span, "async foreign declarations are unsupported");
				return null;
			}
			if (!advance ()) {
				return null;
			}
			if (current.kind == TokenKind.EXTERN || current.kind == TokenKind.EXPORT) {
				fail (async_keyword.span, "async foreign declarations are unsupported");
				return null;
			}
		}
		var owned_keyword = current.kind == TokenKind.OWNED ? current : null;
		if (owned_keyword != null && !advance ()) {
			return null;
		}
		var return_type = parse_type ("expected function return type name");
		if (return_type == null) {
			return null;
		}
		var name = expect (TokenKind.IDENTIFIER, "expected function name");
		if (name == null) {
			return null;
		}
		if (utf8_factory && (extern_keyword != null || export_keyword != null || async_keyword != null)) {
			fail (name.span, "Utf8MessageFactory requires a synchronous native definition");
			return null;
		}
		var function = parse_function_tail (return_type, name, owned_keyword, extern_keyword, export_keyword, abi_identifier, async_keyword, utf8_factory, false, foreign_policy);
		if (function != null) {
			function.ccode = ccode;
			function.floating_point = floating_point;
		}
		return function;
	}

	private CallerInformationSyntax? parse_caller_information() {
		var open = expect (TokenKind.OPEN_BRACKET, "expected '[' before caller information");
		var name = open == null ? null : expect (TokenKind.IDENTIFIER, "expected caller-information annotation name");
		if (name == null) {
			return null;
		}
		Token? target = null;
		switch (DeclarationPolicyRegistry.lookup (name.spelling ())) {
		case DeclarationPolicyId.CALLER_FILE: case DeclarationPolicyId.CALLER_LINE: break;
		case DeclarationPolicyId.CALLER_ARGUMENT:
			if (expect (TokenKind.OPEN_PAREN, "CallerArgumentExpression requires one string literal naming an earlier required parameter") == null) {
				return null;
			}
			target = expect (TokenKind.TEXT, "CallerArgumentExpression requires one string literal naming an earlier required parameter");
			if (target == null || expect (TokenKind.CLOSE_PAREN, "CallerArgumentExpression accepts exactly one string literal") == null) {
				return null;
			}
			break;
			default: fail (name.span, "unknown native parameter annotation '%s'; expected CallerFilePath, CallerLineNumber or CallerArgumentExpression".printf (name.spelling ()));
			return null;
		}
		var close = expect (TokenKind.CLOSE_BRACKET, "expected ']' after caller-information annotation; file and line annotations take no payload");
		if (close == null) {
			return null;
		}
		if (current.kind == TokenKind.OPEN_BRACKET) {
			fail (current.span, "a parameter accepts exactly one caller-information annotation");
			return null;
		}
		return new CallerInformationSyntax (SourceSpan.cover (open.span, close.span), name, target);
	}

	private FunctionDeclarationSyntax? parse_function_tail(TypeNameSyntax? return_type, Token name, Token? owned_keyword = null, Token? extern_keyword = null, Token? export_keyword = null, Token? abi_identifier = null, Token? async_keyword = null, bool utf8_factory = false, bool interface_requirement = false, ForeignPolicySyntax? foreign_policy = null, bool foreign_declaration = false) {
		bool imports_c = extern_keyword != null || (foreign_policy != null && (foreign_policy.kind == DeclarationPolicyId.C_IMPORT || foreign_policy.kind == DeclarationPolicyId.GOBJECT_IMPORT));
		bool exports_c = export_keyword != null || (foreign_policy != null && foreign_policy.kind == DeclarationPolicyId.C_EXPORT);
		var type_parameters = new GenericArray<Token> ();
		if (current.kind == TokenKind.LESS) {
			if (async_keyword != null) {
				fail (current.span, "generic async declarations are unsupported");
				return null;
			}
			if (return_type == null) {
				fail (current.span, "generic constructors and destructors are unsupported");
				return null;
			}
			type_parameters = parse_type_parameters ();
			if (type_parameters == null) {
				return null;
			}
			if (imports_c || exports_c) {
				fail (name.span, "generic extern(C) and export(C) functions are unsupported");
				return null;
			}
		}
		var open = expect (TokenKind.OPEN_PAREN, "expected '(' after function name");
		if (open == null) {
			return null;
		}
		var parameters = new GenericArray<ParameterSyntax> ();
		var commas = new GenericArray<Token> ();
		if (current.kind != TokenKind.CLOSE_PAREN) {
			while (true) {
				CallerInformationSyntax? caller_information = null;
				if (current.kind == TokenKind.OPEN_BRACKET) {
					caller_information = parse_caller_information ();
					if (caller_information == null) {
						return null;
					}
				}
				var parameter_owned_keyword = current.kind == TokenKind.OWNED ? current : null;
				if (parameter_owned_keyword != null && !advance ()) {
					return null;
				}
				if (parameter_owned_keyword != null && current.kind == TokenKind.BORROWED) {
					fail (current.span, "parameter accepts only one ownership qualifier");
					return null;
				}
				var borrowed_keyword = current.kind == TokenKind.BORROWED ? current : null;
				if (borrowed_keyword != null && !advance ()) {
					return null;
				}
				var parameter_type = parse_type ("expected parameter type name");
				if (parameter_type == null) {
					return null;
				}
				var parameter_name = expect (TokenKind.IDENTIFIER, "expected parameter name");
				if (parameter_name == null) {
					return null;
				}
				if (caller_information != null && current.kind == TokenKind.EQUAL) {
					fail (current.span, "caller-information parameters do not admit explicit default initializers");
					return null;
				}
				parameters.add (new ParameterSyntax (parameter_type, parameter_name, borrowed_keyword, parameter_owned_keyword, caller_information));
				if (current.kind != TokenKind.COMMA) {
					break;
				}
				commas.add (current);
				if (!advance ()) {
					return null;
				}
			}
		}
		var close = expect (TokenKind.CLOSE_PAREN, "expected ')' after parameters");
		if (close == null) {
			return null;
		}
		TypeNameSyntax? throws_class = null;
		if (current.kind == TokenKind.THROWS) {
			if (!advance ()) {
				return null;
			}
			throws_class = parse_type ("expected exception class bound after 'throws'");
			if (throws_class == null) {
				return null;
			}
			if (return_type == null && name.spelling () != "init") {
				fail (throws_class.span, "destructors cannot declare escaping throws");
				return null;
			}
			if (imports_c || exports_c) {
				fail (throws_class.span, "C boundaries cannot declare native throws; use a nonthrowing source adapter");
				return null;
			}
		}
		GenericArray<ExpressionSyntax>? base_arguments = null;
		if (current.kind == TokenKind.COLON && return_type == null) {
			if (name.spelling () != "init") {
				fail (current.span, "only init accepts a base initializer");
				return null;
			}
			if (!advance ()) {
				return null;
			}
			var base_name = expect (TokenKind.IDENTIFIER, "expected base initializer");
			if (base_name == null) {
				return null;
			}
			if (base_name.spelling () != "base") {
				fail (base_name.span, "constructor initializer must call base(args)");
				return null;
			}
			var call = parse_call (base_name, 0);
			if (call == null) {
				return null;
			}
			base_arguments = call.arguments;
		}
		if (imports_c) {
			var semicolon = expect (TokenKind.SEMICOLON, "expected ';' after foreign function declaration; foreign declarations have no body");
			return semicolon == null ? null : new FunctionDeclarationSyntax.foreign (extern_keyword ?? foreign_policy.name, abi_identifier, return_type, name, open, parameters, commas, close, semicolon, owned_keyword, foreign_policy);
		}
		if (interface_requirement) {
			if (type_parameters.length != 0 || throws_class != null || owned_keyword != null) {
				fail (name.span, "interface operations require nonthrowing nongeneric copied int signatures");
				return null;
			}
			var end = expect (TokenKind.SEMICOLON, "interface operation requires a bodyless ';' declaration");
			if (end == null) {
				return null;
			}
			return new FunctionDeclarationSyntax (return_type, name, open, parameters, commas, close, interface_prerequisites ().methods[0].body, null, null, null, null, end);
		}
		var clauses = parse_where_clauses (type_parameters.length != 0);
		if (clauses == null) {
			return null;
		}
		if (exports_c && current.kind != TokenKind.OPEN_BRACE) {
			fail (current.span, "export(C) requires a definition with a function body");
			return null;
		}
		BlockStatementSyntax? body;
		Token? factory_end = null;
		if (utf8_factory) {
			var end = expect (TokenKind.SEMICOLON, "Utf8MessageFactory requires a bodyless ';' definition");
			if (end == null) {
				return null;
			}
			if (type_parameters.length != 0 || clauses.length != 0 || name.spelling () != "utf8_message" || return_type.spelling () != "Utf8Message" || owned_keyword == null || throws_class == null || throws_class.spelling () != "InvalidUtf8" || parameters.length != 1 || parameters[0].name.spelling () != "bytes" || parameters[0].type_name.spelling () != "u8[]" || parameters[0].owned_keyword != null || parameters[0].caller_information != null) {
				fail (name.span, "Utf8MessageFactory requires exactly owned Utf8Message utf8_message(u8[] bytes) throws InvalidUtf8");
				return null;
			}
			factory_end = end;
			body = Utf8FactorySyntax.body (namespace_prefix);
		} else if (foreign_declaration) {
			var end = expect (TokenKind.SEMICOLON, "CImport Class members require bodyless declarations");
			if (end == null) {
				return null;
			}
			body = new BlockStatementSyntax (end, new GenericArray<StatementSyntax> (), end);
		} else {
			body = parse_block ();
		}
		if (body == null) {
			return null;
		}
		if (return_type == null) {
			if (name.spelling () == "deinit" && parameters.length != 0) {
				fail (name.span, "destructor deinit takes no explicit parameters");
				return null;
			}
			var lifecycle = new LifecycleDeclarationSyntax (name, open, parameters, commas, close, body);
			lifecycle.throws_class = throws_class;
			lifecycle.base_arguments = base_arguments;
			return lifecycle;
		}
		var function = new FunctionDeclarationSyntax (return_type, name, open, parameters, commas, close, body, export_keyword, abi_identifier, owned_keyword, async_keyword, factory_end, foreign_policy);
		function.throws_class = throws_class;
		function.utf8_factory = utf8_factory;
		function.type_parameters = type_parameters;
		function.where_clauses = clauses;
		return function;
	}

	private BlockStatementSyntax? parse_block(string context = "function body") {
		if (block_depth >= MAX_BLOCK_DEPTH) {
			fail (current.span, "block nesting limit of 256 exceeded");
			return null;
		}
		var open = expect (TokenKind.OPEN_BRACE, "expected '{' before " + context);
		if (open == null) {
			return null;
		}
		var statements = new GenericArray<StatementSyntax> ();
		block_depth++;
		while (current.kind != TokenKind.CLOSE_BRACE) {
			if (current.kind == TokenKind.EOF) {
				fail (current.span, "expected '}' after " + context);
				return null;
			}
			var statement = parse_statement ();
			if (statement == null) {
				return null;
			}
			statements.add (statement);
		}
		var close = expect (TokenKind.CLOSE_BRACE, "expected '}' after " + context);
		block_depth--;
		return close == null ? null : new BlockStatementSyntax (open, statements, close);
	}

	private StatementSyntax? parse_indexed_member_statement(owned ExpressionSyntax receiver) {
		while (current.kind == TokenKind.DOT) {
			var dot = current;
			if (!advance ()) {
				return null;
			}
			var member = expect (TokenKind.IDENTIFIER, "expected member name after indexed Place");
			if (member == null) {
				return null;
			}
			if (current.kind == TokenKind.OPEN_PAREN || begins_generic_call ()) {
				var call = parse_call (member, 0, null, dot, false, receiver);
				var end = call == null ? null : expect (TokenKind.SEMICOLON, "expected ';' after member call");
				return end == null ? null : new CallStatementSyntax (call, end);
			}
			receiver = new FieldAccessExpressionSyntax.projection (receiver, dot, member);
		}
		var equals_token = expect (TokenKind.EQUAL, "expected '=' after indexed field target");
		if (equals_token == null) {
			return null;
		}
		var value = parse_expression (0, 0);
		var end = value == null ? null : expect (TokenKind.SEMICOLON, "expected ';' after assignment");
		return end == null ? null : new FieldAssignmentStatementSyntax ((FieldAccessExpressionSyntax) receiver, equals_token, value, end);
	}

	private TryStatementSyntax? parse_try() {
		var keyword = current;
		if (!advance ()) {
			return null;
		}
		var body = parse_block ("try body");
		if (body == null) {
			return null;
		}
		var catches = new GenericArray<CatchClauseSyntax> ();
		while (current.kind == TokenKind.CATCH) {
			var catch_keyword = current;
			if (!advance () || expect (TokenKind.OPEN_PAREN, "expected '(' after catch") == null) {
				return null;
			}
			var type = parse_type ("expected exception class in catch");
			var binding = type == null ? null : expect (TokenKind.IDENTIFIER, "expected borrowed catch binding");
			if (binding == null || expect (TokenKind.CLOSE_PAREN, "expected ')' after catch binding") == null) {
				return null;
			}
			var handler = parse_block ("catch body");
			if (handler == null) {
				return null;
			}
			catches.add (new CatchClauseSyntax (catch_keyword, type, binding, handler));
		}
		if (catches.length == 0) {
			fail (current.span, "try requires at least one typed catch");
			return null;
		}
		return new TryStatementSyntax (keyword, body, catches);
	}

	private StatementSyntax? parse_statement() {
		if (current.kind == TokenKind.IDENTIFIER && current.spelling () == "emit" && next_is (TokenKind.IDENTIFIER) && following_is (TokenKind.OPEN_PAREN)) {
			var keyword = current;
			if (!advance ()) {
				return null;
			}
			var name = current;
			if (!advance ()) {
				return null;
			}
			var call = parse_call (name, 0, new Token.generated (TokenKind.THIS, keyword.span, "this"), new Token.generated (TokenKind.DOT, keyword.span, "."));
			if (call == null) {
				return null;
			}
			call.signal_emission = true;
			var end = expect (TokenKind.SEMICOLON, "expected ';' after signal emission");
			return end == null ? null : new CallStatementSyntax (call, end);
		}
		if (current.kind == TokenKind.NONNULL) {
			var type = parse_type ("expected nonnull local type");
			return type == null ? null : parse_local_declaration (type);
		}
		if (current.kind == TokenKind.WITH) {
			return parse_with ();
		}
		if (current.kind == TokenKind.FOREACH) {
			return parse_foreach ();
		}
		if (current.kind == TokenKind.FOR) {
			return parse_for ();
		}
		if (current.kind == TokenKind.AWAIT) {
			var expression = parse_primary_or_prefix (0) as AwaitExpressionSyntax;
			if (expression == null) {
				return null;
			}
			var end = expect (TokenKind.SEMICOLON, "expected ';' after await statement");
			return end == null ? null : new AwaitStatementSyntax (expression, end);
		}
		if (current.kind == TokenKind.TRY) {
			return parse_try ();
		}
		if (current.kind == TokenKind.THROW) {
			var keyword = current;
			if (!advance ()) {
				return null;
			}
			ExpressionSyntax? expression = null;
			if (current.kind != TokenKind.SEMICOLON) {
				expression = current.kind == TokenKind.MOVE ? parse_owned_initializer () : parse_expression (0, 0);
				if (expression == null) {
					return null;
				}
			}
			var end = expect (TokenKind.SEMICOLON, "expected ';' after throw");
			return end == null ? null : new ThrowStatementSyntax (keyword, expression, end);
		}
		if (current.kind == TokenKind.MATCH) {
			return parse_match ();
		}
		if (current.kind == TokenKind.SWAP) {
			var keyword = current;
			if (!advance () || expect (TokenKind.OPEN_PAREN, "expected '(' after 'swap'") == null) {
				return null;
			}
			var left = parse_expression (0, 0);
			if (left == null || expect (TokenKind.COMMA, "swap requires exactly two owner operands separated by ','") == null) {
				return null;
			}
			var right = parse_expression (0, 0);
			if (right == null || expect (TokenKind.CLOSE_PAREN, "swap requires exactly two owner operands and ')'") == null) {
				return null;
			}
			var end = expect (TokenKind.SEMICOLON, "expected ';' after swap statement");
			return end == null ? null : new SwapStatementSyntax (keyword, left, right, end);
		}
		if (current.kind == TokenKind.CONST) {
			return parse_constant ();
		}
		if (current.kind == TokenKind.VAR) {
			return parse_inferred_local ();
		}
		if (current.kind == TokenKind.OPEN_BRACE) {
			return parse_block ("lexical block");
		}
		if (current.kind == TokenKind.RELEASE) {
			var keyword = current;
			if (!advance ()) {
				return null;
			}
			if (current.kind == TokenKind.THIS && next_is (TokenKind.DOT)) {
				fail (current.span, "explicit release of an owned field is unsupported; the slot must remain initialized");
				return null;
			}
			var owner = expect (TokenKind.IDENTIFIER, "expected owned local identifier after 'release'");
			if (current.kind == TokenKind.DOT) {
				fail (current.span, "explicit release of an owned field is unsupported; the slot must remain initialized");
				return null;
			}
			var semicolon = owner == null ? null : expect (TokenKind.SEMICOLON, "release statement requires exactly 'release identifier;'");
			return semicolon == null ? null : new ReleaseStatementSyntax (keyword, owner, semicolon);
		}
		if (current.kind == TokenKind.BORROWED) {
			fail (current.span, "'borrowed' is supported only on void* parameters; borrowed locals, results, and fields are unsupported");
			return null;
		}
		if (current.kind == TokenKind.MOVE) {
			fail (current.span, "'move' is supported only as the direct initializer of a fresh 'owned void*' local");
			return null;
		}
		if (current.kind == TokenKind.OWNED) {
			var keyword = current;
			if (!advance ()) {
				return null;
			}
			var local_type = parse_type ("expected type after 'owned'");
			return local_type == null ? null : parse_local_declaration (local_type, keyword);
		}
		if (current.kind == TokenKind.BREAK || current.kind == TokenKind.CONTINUE) {
			var keyword = current;
			if (!advance ()) {
				return null;
			}
			var semicolon = expect (TokenKind.SEMICOLON, "expected ';' after '%s'".printf (keyword.spelling ()));
			if (semicolon == null) {
				return null;
			}
			return keyword.kind == TokenKind.BREAK ? (StatementSyntax) new BreakStatementSyntax (keyword, semicolon) : new ContinueStatementSyntax (keyword, semicolon);
		}
		if (current.kind == TokenKind.WHILE) {
			return parse_while ();
		}
		if (current.kind == TokenKind.IF) {
			return parse_if ();
		}
		if (current.kind == TokenKind.RETURN) {
			return parse_return ();
		}
		if (current.kind == TokenKind.STAR) {
			var target = parse_primary_or_prefix (0) as DereferenceExpressionSyntax;
			if (target == null || expect (TokenKind.EQUAL, "expected '=' after dereference assignment target") == null) {
				return null;
			}
			var expression = parse_expression (0, 0);
			var semicolon = expression == null ? null : expect (TokenKind.SEMICOLON, "expected ';' after assignment statement");
			return semicolon == null ? null : new DereferenceAssignmentSyntax (target, expression, semicolon);
		}
		if (current.kind == TokenKind.SLICE || current.kind == TokenKind.OPEN_PAREN) {
			var target = parse_expression (0, 0) as IndexExpressionSyntax;
			if (target == null) {
				fail (current.span, "expected indexed assignment target");
				return null;
			}
			return parse_indexed_assignment (target);
		}
		var first = expect (current.kind == TokenKind.THIS ? TokenKind.THIS : TokenKind.IDENTIFIER, "expected return, if, while, break, continue, local declaration, assignment, or call statement");
		if (first == null) {
			return null;
		}
		if (current.kind == TokenKind.OPEN_PAREN || begins_generic_call ()) {
			var call = parse_call (first, 0);
			if (call == null) {
				return null;
			}
			var semicolon = expect (TokenKind.SEMICOLON, "expected ';' after call statement");
			return semicolon == null ? null : new CallStatementSyntax (call, semicolon);
		}
		if (current.kind == TokenKind.IDENTIFIER || current.kind == TokenKind.STAR || current.kind == TokenKind.LESS || begins_qualified_local (first)) {
			var local_type = parse_type_suffix (first);
			if (local_type == null) {
				return null;
			}
			return parse_local_declaration (local_type);
		}
		if (current.kind == TokenKind.OPEN_BRACKET) {
			if (next_is (TokenKind.CLOSE_BRACKET)) {
				var type = parse_array_suffix (new TypeNameSyntax (first), false);
				return type == null ? null : parse_local_declaration (type);
			}
			var target = parse_index (new NameExpressionSyntax (first), 0);
			if (target == null) {
				return null;
			}
			if (current.kind == TokenKind.IDENTIFIER) {
				return parse_local_declaration (new ArrayTypeSyntax.expression (new TypeNameSyntax (first), target.subscript, target.close));
			}
			if (current.kind == TokenKind.DOT) {
				return parse_indexed_member_statement (target);
			}
			if (current.kind == TokenKind.OPEN_BRACKET) {
				fail (current.span, "nested arrays and vector lane assignment targets are unsupported; use insert()");
				return null;
			}
			if (expect (TokenKind.EQUAL, "expected '=' after indexed assignment target; array pointers are unsupported") == null) {
				return null;
			}
			var expression = parse_expression (0, 0);
			var semicolon = expression == null ? null : expect (TokenKind.SEMICOLON, "expected ';' after indexed assignment");
			return semicolon == null ? null : new IndexedAssignmentSyntax (target, expression, semicolon);
		}
		FieldAccessExpressionSyntax? field_target = null;
		if (current.kind == TokenKind.DOT || current.kind == TokenKind.ARROW) {
			var member = parse_field_access (first);
			if (member is CallExpressionSyntax) {
				var semicolon = expect (TokenKind.SEMICOLON, "expected ';' after method call statement");
				return semicolon == null ? null : new CallStatementSyntax ((CallExpressionSyntax) member, semicolon);
			}
			field_target = member as FieldAccessExpressionSyntax;
			if (field_target == null) {
				return null;
			}
			if (current.kind == TokenKind.OPEN_BRACKET) {
				var indexed = parse_index (field_target, 0);
				return indexed == null ? null : parse_indexed_assignment (indexed);
			}
		}
		var equals_token = expect (TokenKind.EQUAL, "expected '=' after assignment target");
		if (equals_token == null) {
			return null;
		}
		var expression = current.kind == TokenKind.MOVE ? parse_owned_initializer () : parse_expression (0, 0);
		if (expression == null) {
			return null;
		}
		var semicolon = expect (TokenKind.SEMICOLON, "expected ';' after assignment statement");
		if (semicolon == null) {
			return null;
		}
		return field_target == null ? (StatementSyntax) new AssignmentStatementSyntax (first, equals_token, expression, semicolon) : new FieldAssignmentStatementSyntax (field_target, equals_token, expression, semicolon);
	}

	private StatementSyntax? parse_indexed_assignment(IndexExpressionSyntax target) {
		if (current.kind == TokenKind.DOT) {
			return parse_indexed_member_statement (target);
		}
		if (expect (TokenKind.EQUAL, "expected '=' after indexed assignment target") == null) {
			return null;
		}
		var expression = parse_expression (0, 0);
		var semicolon = expression == null ? null : expect (TokenKind.SEMICOLON, "expected ';' after indexed assignment");
		return semicolon == null ? null : new IndexedAssignmentSyntax (target, expression, semicolon);
	}

	private TypeNameSyntax? parse_array_suffix(TypeNameSyntax element, bool conversion) {
		if (conversion || current.kind != TokenKind.OPEN_BRACKET) {
			return element;
		}
		if (!advance ()) {
			return null;
		}
		if (current.kind == TokenKind.CLOSE_BRACKET) {
			var close = current;
			if (!advance ()) {
				return null;
			}
			if (current.kind == TokenKind.OPEN_BRACKET || current.kind == TokenKind.STAR) {
				fail (current.span, "nested slices, arrays of slices and slice pointers are unsupported");
				return null;
			}
			return new SliceTypeSyntax (element, close);
		}
		if (current.kind == TokenKind.IDENTIFIER && current.spelling () == "slots" && next_is (TokenKind.CLOSE_BRACKET)) {
			var marker = current;
			if (!advance ()) {
				return null;
			}
			var close = expect (TokenKind.CLOSE_BRACKET, "expected ']' after owner slots marker");
			if (close == null) {
				return null;
			}
			return new OwnerSlotsTypeSyntax (element, marker, close);
		}
		var length = parse_expression (0, 0);
		var close = length == null ? null : expect (TokenKind.CLOSE_BRACKET, "expected ']' after constant array extent");
		if (close == null) {
			return null;
		}
		if (current.kind == TokenKind.OPEN_BRACKET || current.kind == TokenKind.STAR) {
			fail (current.span, "nested arrays and array pointers are unsupported");
			return null;
		}
		return new ArrayTypeSyntax.expression (element, length, close);
	}

	private IndexExpressionSyntax? parse_index(ExpressionSyntax container, int depth) {
		var open = current;
		if (!advance ()) {
			return null;
		}
		var index = parse_expression (0, depth + 1);
		var close = index == null ? null : expect (TokenKind.CLOSE_BRACKET, "expected ']' after index expression");
		if (close == null) {
			return null;
		}
		var literal = index as IntegerLiteralExpressionSyntax;
		return bounded (literal == null ? new IndexExpressionSyntax (container, index, close) : new VectorExtractExpressionSyntax (container, open, literal.literal, close), open.span) as IndexExpressionSyntax;
	}

	private ConstantDeclarationSyntax? parse_constant() {
		var keyword = current;
		if (!advance ()) {
			return null;
		}
		if (current.kind == TokenKind.VAR || current.kind == TokenKind.OWNED || current.kind == TokenKind.BORROWED) {
			fail (current.span, "const declarations cannot use var or ownership qualifiers");
			return null;
		}
		TypeNameSyntax? type = null;
		Token? name;
		if (current.kind == TokenKind.IDENTIFIER && (next_is (TokenKind.EQUAL) || next_is (TokenKind.SEMICOLON))) {
			name = current;
			if (!advance ()) {
				return null;
			}
		} else {
			type = parse_type ("expected constant name or type");
			name = type == null ? null : expect (TokenKind.IDENTIFIER, "expected constant name");
		}
		if (name == null || expect (TokenKind.EQUAL, "constant declaration requires an initializer") == null) {
			return null;
		}
		if (current.kind == TokenKind.SEMICOLON || current.kind == TokenKind.EOF) {
			fail (current.span, "constant declaration requires an initializer");
			return null;
		}
		var initializer = current.kind == TokenKind.MOVE ? parse_owned_initializer () : parse_expression (0, 0);
		var semicolon = initializer == null ? null : expect (TokenKind.SEMICOLON, "constant declaration requires one name and a terminating ';'");
		return semicolon == null ? null : new ConstantDeclarationSyntax (keyword, type, name, initializer, semicolon);
	}

	private StatementSyntax? parse_inferred_local(bool with_header = false) {
		var keyword = current;
		if (!advance ()) {
			return null;
		}
		var name = expect (TokenKind.IDENTIFIER, "'var' is a reserved keyword for inferred local declarations; expected local name");
		if (name == null) {
			return null;
		}
		if (current.kind == TokenKind.IDENTIFIER || current.kind == TokenKind.COLON) {
			fail (current.span, "inferred local declaration cannot include an explicit type");
			return null;
		}
		var equals_token = expect (TokenKind.EQUAL, "inferred local declaration requires an initializer");
		if (equals_token == null) {
			return null;
		}
		if (current.kind == TokenKind.SEMICOLON || current.kind == TokenKind.CLOSE_BRACE || current.kind == TokenKind.EOF) {
			fail (current.span, "inferred local declaration requires an initializer");
			return null;
		}
		if (current.kind == TokenKind.OPEN_BRACE) {
			fail (current.span, "cannot infer local type from this initializer; write an explicit type");
			return null;
		}
		var initializer = current.kind == TokenKind.MOVE ? parse_owned_initializer () : parse_expression (0, 0);
		if (with_header) {
			return initializer == null ? null : new InferredLocalDeclarationSyntax (keyword, name, equals_token, initializer, null);
		}
		var semicolon = initializer == null ? null : expect (TokenKind.SEMICOLON, "expected ';' after inferred local declaration");
		return semicolon == null ? null : new InferredLocalDeclarationSyntax (keyword, name, equals_token, initializer, semicolon);
	}

	private StatementSyntax? parse_local_declaration(TypeNameSyntax local_type, Token? owned_keyword = null) {
		var name = expect (TokenKind.IDENTIFIER, "expected local name");
		if (name == null) {
			return null;
		}
		var equals_token = expect (TokenKind.EQUAL, "expected '=' and initializer after local name");
		if (equals_token == null) {
			return null;
		}
		if (current.kind == TokenKind.OPEN_BRACE) {
			var open = current;
			if (!advance ()) {
				return null;
			}
			bool named = (current.kind == TokenKind.CLOSE_BRACE && !(local_type is VectorTypeSyntax) && !(local_type is ArrayTypeSyntax)) || (current.kind == TokenKind.IDENTIFIER && next_is (TokenKind.EQUAL));
			if (diagnostic != null) {
				return null;
			}
			if (!named) {
				var positional = parse_vector_initializer (open, local_type is ArrayTypeSyntax);
				ExpressionSyntax? initializer = (positional != null && local_type is ArrayTypeSyntax) ? new ArrayInitializerSyntax (positional) : (ExpressionSyntax?) positional;
				var semicolon = initializer == null ? null : expect (TokenKind.SEMICOLON, "expected ';' after local declaration");
				return semicolon == null ? null : new LocalDeclarationSyntax (local_type, name, equals_token, initializer, semicolon, owned_keyword);
			}
			var initializer = parse_struct_initializer (open);
			if (initializer == null) {
				return null;
			}
			var semicolon = expect (TokenKind.SEMICOLON, "expected ';' after local declaration");
			return semicolon == null ? null : new StructLocalDeclarationSyntax (local_type, name, equals_token, initializer, semicolon, owned_keyword);
		}
		if (current.kind == TokenKind.IDENTIFIER && current.spelling () == local_type.spelling () && next_is (TokenKind.DOT) && following_is (TokenKind.IDENTIFIER) && second_lookahead.spelling () == "init") {
			var type_name = current;
			if (!advance ()) {
				return null;
			}
			var dot = current;
			if (!advance ()) {
				return null;
			}
			var constructor_name = current;
			if (!advance ()) {
				return null;
			}
			var initializer = parse_call (constructor_name, 0, type_name, dot, true);
			var semicolon = initializer == null ? null : expect (TokenKind.SEMICOLON, "constructor initializer must be the complete fresh local initializer");
			return semicolon == null ? null : new LocalDeclarationSyntax (local_type, name, equals_token, initializer, semicolon, owned_keyword);
		}
		var initializer = owned_keyword != null || current.kind == TokenKind.MOVE ? parse_owned_initializer () : parse_expression (0, 0);
		if (initializer == null) {
			return null;
		}
		var semicolon = expect (TokenKind.SEMICOLON, "expected ';' after local declaration");
		return semicolon == null ? null : new LocalDeclarationSyntax (local_type, name, equals_token, initializer, semicolon, owned_keyword);
	}

	private IfStatementSyntax? parse_if() {
		var keyword = expect (TokenKind.IF, "expected 'if'");
		if (keyword == null) {
			return null;
		}
		var open = expect (TokenKind.OPEN_PAREN, "expected '(' after 'if'");
		if (open == null) {
			return null;
		}
		var condition = parse_expression (0, 0);
		if (condition == null) {
			return null;
		}
		var close = expect (TokenKind.CLOSE_PAREN, "expected ')' after if condition");
		if (close == null) {
			return null;
		}
		var then_body = parse_block ("if body");
		if (then_body == null) {
			return null;
		}
		Token? else_keyword = null;
		BlockStatementSyntax? else_body = null;
		if (current.kind == TokenKind.ELSE) {
			else_keyword = current;
			if (!advance ()) {
				return null;
			}
			else_body = parse_block ("else body");
			if (else_body == null) {
				return null;
			}
		}
		return new IfStatementSyntax (keyword, open, condition, close, then_body, else_keyword, else_body);
	}

	// Assignment/call nodes also represent the unterminated for step. The
	// closing parenthesis belongs to the loop, never a fabricated semicolon.
	private StatementSyntax? parse_for_step() {
		var target = parse_expression (0, 0);
		if (target == null) {
			return null;
		}
		if (target is CallExpressionSyntax && current.kind == TokenKind.CLOSE_PAREN) {
			return new CallStatementSyntax ((CallExpressionSyntax) target, null);
		}
		var equals_token = expect (TokenKind.EQUAL, "for step requires an assignment or call");
		if (equals_token == null) {
			return null;
		}
		var value = current.kind == TokenKind.MOVE ? parse_owned_initializer () : parse_expression (0, 0);
		if (value == null) {
			return null;
		}
		if (target is NameExpressionSyntax) {
			return new AssignmentStatementSyntax (((NameExpressionSyntax) target).identifier, equals_token, value, null);
		}
		if (target is FieldAccessExpressionSyntax) {
			return new FieldAssignmentStatementSyntax ((FieldAccessExpressionSyntax) target, equals_token, value, null);
		}
		if (target is IndexExpressionSyntax) {
			return new IndexedAssignmentSyntax ((IndexExpressionSyntax) target, value, null);
		}
		if (target is DereferenceExpressionSyntax) {
			return new DereferenceAssignmentSyntax ((DereferenceExpressionSyntax) target, value, null);
		}
		fail (target.span, "for step requires an assignable target");
		return null;
	}

	private WithStatementSyntax? parse_with() {
		var keyword = current;
		if (!advance () || expect (TokenKind.OPEN_PAREN, "expected '(' after 'with'") == null) {
			return null;
		}
		InferredLocalDeclarationSyntax? initializer = null;
		Token? receiver = null;
		if (current.kind == TokenKind.VAR) {
			initializer = parse_inferred_local (true) as InferredLocalDeclarationSyntax;
			if (initializer == null) {
				return null;
			}
			receiver = initializer.name;
		} else {
			receiver = expect (TokenKind.IDENTIFIER, "with requires a named owned receiver or 'var name = owned expression'");
		}
		if (receiver == null || expect (TokenKind.CLOSE_PAREN, "expected ')' after with receiver") == null) {
			return null;
		}
		var body = parse_block ("with body");
		return body == null ? null : new WithStatementSyntax (keyword, receiver, initializer, body);
	}

	private ForeachStatementSyntax? parse_foreach() {
		var keyword = current;
		if (!advance () || expect (TokenKind.OPEN_PAREN, "expected '(' after 'foreach'") == null || expect (TokenKind.VAR, "foreach requires 'var' and a borrowed element binding") == null) {
			return null;
		}
		var binding = expect (TokenKind.IDENTIFIER, "expected foreach element name");
		var separator = binding == null ? null : expect (TokenKind.IDENTIFIER, "expected 'in' after foreach element name");
		if (separator == null) {
			return null;
		}
		if (separator.spelling () != "in") {
			fail (separator.span, "expected 'in' after foreach element name");
			return null;
		}
		var collection = parse_expression (0, 0);
		if (collection == null || expect (TokenKind.CLOSE_PAREN, "expected ')' after foreach collection") == null) {
			return null;
		}
		var body = parse_block ("foreach body");
		return body == null ? null : new ForeachStatementSyntax (keyword, binding, collection, body);
	}

	private ForStatementSyntax? parse_for() {
		var keyword = current;
		if (!advance () || expect (TokenKind.OPEN_PAREN, "expected '(' after 'for'") == null) {
			return null;
		}
		StatementSyntax? initializer = null;
		if (current.kind != TokenKind.SEMICOLON) {
			if (!(current.kind == TokenKind.VAR || current.kind == TokenKind.OWNED || current.kind == TokenKind.IDENTIFIER || current.kind == TokenKind.THIS || current.kind == TokenKind.STAR || current.kind == TokenKind.OPEN_PAREN || current.kind == TokenKind.SLICE)) {
				fail (current.span, "for initializer requires a local declaration, assignment or call");
				return null;
			}
			initializer = parse_statement ();
			if (initializer == null) {
				return null;
			}
			if (!(initializer is LocalDeclarationSyntax || initializer is InferredLocalDeclarationSyntax || initializer is StructLocalDeclarationSyntax || initializer is AssignmentStatementSyntax || initializer is FieldAssignmentStatementSyntax || initializer is IndexedAssignmentSyntax || initializer is DereferenceAssignmentSyntax || initializer is CallStatementSyntax)) {
				fail (initializer.span, "for initializer requires a local declaration, assignment or call");
				return null;
			}
		} else if (!advance ()) {
			return null;
		}
		ExpressionSyntax? condition = null;
		if (current.kind != TokenKind.SEMICOLON) {
			condition = parse_expression (0, 0);
			if (condition == null) {
				return null;
			}
		}
		if (expect (TokenKind.SEMICOLON, "expected ';' after for condition") == null) {
			return null;
		}
		StatementSyntax? step = null;
		if (current.kind != TokenKind.CLOSE_PAREN) {
			step = parse_for_step ();
			if (step == null) {
				return null;
			}
		}
		if (expect (TokenKind.CLOSE_PAREN, "expected ')' after for step") == null) {
			return null;
		}
		var body = parse_block ("for body");
		return body == null ? null : new ForStatementSyntax (keyword, initializer, condition, step, body);
	}

	private WhileStatementSyntax? parse_while() {
		var keyword = expect (TokenKind.WHILE, "expected 'while'");
		if (keyword == null) {
			return null;
		}
		var open = expect (TokenKind.OPEN_PAREN, "expected '(' after 'while'");
		if (open == null) {
			return null;
		}
		var condition = parse_expression (0, 0);
		if (condition == null) {
			return null;
		}
		var close = expect (TokenKind.CLOSE_PAREN, "expected ')' after while condition");
		if (close == null) {
			return null;
		}
		var body = parse_block ("while body");
		return body == null ? null : new WhileStatementSyntax (keyword, open, condition, close, body);
	}

	private ReturnStatementSyntax? parse_return() {
		var keyword = expect (TokenKind.RETURN, "expected 'return' statement");
		if (keyword == null) {
			return null;
		}
		ExpressionSyntax? expression = null;
		if (current.kind != TokenKind.SEMICOLON) {
			expression = current.kind == TokenKind.MOVE ? parse_owned_initializer () : parse_expression (0, 0);
			if (expression == null) {
				return null;
			}
		}
		var semicolon = expect (TokenKind.SEMICOLON, "expected ';' after return statement");
		return semicolon == null ? null : new ReturnStatementSyntax (keyword, expression, semicolon);
	}

	private static int infix_binding_power(TokenKind kind) {
		switch (kind) {
		case TokenKind.AS:
			return 25;
		case TokenKind.PIPE_PIPE:
			return 0;
		case TokenKind.AMPERSAND_AMPERSAND:
			return 1;
		case TokenKind.PIPE:
			return 2;
		case TokenKind.CARET:
			return 3;
		case TokenKind.AMPERSAND:
			return 4;
		case TokenKind.EQUAL_EQUAL:
		case TokenKind.BANG_EQUAL:
			return 5;
		case TokenKind.LESS:
		case TokenKind.LESS_EQUAL:
		case TokenKind.GREATER:
		case TokenKind.GREATER_EQUAL:
			return 6;
		case TokenKind.SHIFT_LEFT:
		case TokenKind.SHIFT_RIGHT:
			return 7;
		case TokenKind.PLUS:
		case TokenKind.MINUS:
			return 10;
		case TokenKind.STAR:
		case TokenKind.SLASH:
		case TokenKind.PERCENT:
			return 20;
			default:
			return -1;
		}
	}

	private ExpressionSyntax? bounded(ExpressionSyntax expression, SourceSpan marker) {
		if (expression.tree_depth > MAX_EXPRESSION_DEPTH) {
			fail (marker, "expression nesting limit of 256 exceeded");
			return null;
		}
		return expression;
	}

	private ExpressionSyntax? parse_expression(int minimum_power, int recursion_depth) {
		if (recursion_depth >= MAX_EXPRESSION_DEPTH) {
			fail (current.span, "expression nesting limit of 256 exceeded");
			return null;
		}
		var left = parse_primary_or_prefix (recursion_depth);
		if (left == null) {
			return null;
		}
		while (true) {
			while (current.kind == TokenKind.OPEN_BRACKET) {
				left = parse_index (left, recursion_depth);
				if (left == null) {
					return null;
				}
			}
			if (current.kind == TokenKind.DOT) {
				var dot = current;
				if (!advance ()) {
					return null;
				}
				var member = expect (TokenKind.IDENTIFIER, "expected member name after '.'");
				if (member == null) {
					return null;
				}
				if (indexed_member_root (left)) {
					left = current.kind == TokenKind.OPEN_PAREN || begins_generic_call () ? (ExpressionSyntax?) parse_call (member, recursion_depth, null, dot, false, left) : bounded (new FieldAccessExpressionSyntax.projection (left, dot, member), member.span);
					if (left == null) {
						return null;
					}
					continue;
				}
				if (member.spelling () != "byte_length" && current.kind != TokenKind.OPEN_PAREN && !begins_generic_call ()) {
					left = bounded (new FieldAccessExpressionSyntax.projection (left, dot, member), member.span);
					if (left == null) {
						return null;
					}
					continue;
				}
				if (member.spelling () != "byte_length") {
					fail (member.span, "only text byte_length supports an expression receiver");
					return null;
				}
				left = bounded (new TextMemberExpressionSyntax (left, member), member.span);
				if (left == null) {
					return null;
				}
				continue;
			}
			if (infix_binding_power (current.kind) < minimum_power) {
				break;
			}
			var operator_token = current;
			int power = infix_binding_power (operator_token.kind);
			if (!advance ()) {
				return null;
			}
			if (operator_token.kind == TokenKind.AS) {
				var destination = parse_type ("expected destination type after 'as'", true);
				if (destination == null) {
					return null;
				}
				left = bounded (new ConversionExpressionSyntax (left, operator_token, destination), operator_token.span);
				if (left == null) {
					return null;
				}
				continue;
			}
			// RHS binds more tightly, making every current infix left associative.
			var right = parse_expression (power + 1, recursion_depth + 1);
			if (right == null) {
				return null;
			}
			ExpressionSyntax combined;
			var prior = left as BinaryExpressionSyntax;
			if (power == 6 && (left is ComparisonChainSyntax || (prior != null && infix_binding_power (prior.operator_token.kind) == 6))) {
				var operands = new GenericArray<ExpressionSyntax> ();
				var operators = new GenericArray<Token> ();
				if (left is ComparisonChainSyntax) {
					foreach (var operand in ((ComparisonChainSyntax) left).operands) {
						operands.add (operand);
					}
					foreach (var operation in ((ComparisonChainSyntax) left).operators) {
						operators.add (operation);
					}
				} else {
					operands.add (prior.left);
					operands.add (prior.right);
					operators.add (prior.operator_token);
				}
				operands.add (right);
				operators.add (operator_token);
				combined = new ComparisonChainSyntax (operands, operators);
			} else {
				combined = operator_token.kind == TokenKind.AMPERSAND_AMPERSAND || operator_token.kind == TokenKind.PIPE_PIPE ? (ExpressionSyntax) new ShortCircuitExpressionSyntax (left, operator_token, right) : new BinaryExpressionSyntax (left, operator_token, right);
			}
			left = bounded (combined, operator_token.span);
			if (left == null) {
				return null;
			}
		}
		return left;
	}

	private static bool indexed_member_root(ExpressionSyntax syntax) {
		while (syntax is FieldAccessExpressionSyntax && ((FieldAccessExpressionSyntax) syntax).aggregate != null) {
			syntax = ((FieldAccessExpressionSyntax) syntax).aggregate;
		}
		return syntax is IndexExpressionSyntax;
	}

	private CallExpressionSyntax? parse_call(Token identifier, int recursion_depth, Token? receiver = null, Token? member_operator = null, bool construction = false, ExpressionSyntax? receiver_place = null) {
		if (current.kind == TokenKind.LESS && (construction || (receiver != null && identifier.spelling () == "init") || identifier.kind != TokenKind.IDENTIFIER)) {
			fail (current.span, "non-generic constructors and builtin forms do not accept type arguments");
			return null;
		}
		var type_arguments = current.kind == TokenKind.LESS ? parse_type_arguments () : new GenericArray<TypeNameSyntax> ();
		if (type_arguments == null) {
			return null;
		}
		var open = expect (TokenKind.OPEN_PAREN, "expected '(' after function name");
		if (open == null) {
			return null;
		}
		var arguments = new GenericArray<ExpressionSyntax> ();
		var commas = new GenericArray<Token> ();
		if (current.kind != TokenKind.CLOSE_PAREN) {
			while (true) {
				var argument = current.kind == TokenKind.MOVE ? parse_owned_initializer (true) : parse_expression (0, recursion_depth + 1);
				if (argument == null) {
					return null;
				}
				arguments.add (argument);
				if (current.kind != TokenKind.COMMA) {
					break;
				}
				commas.add (current);
				if (!advance ()) {
					return null;
				}
			}
		}
		var close = expect (TokenKind.CLOSE_PAREN, "expected ')' after call arguments");
		if (close == null) {
			return null;
		}
		if (construction) {
			return bounded (new ConstructorInitializerSyntax (identifier, open, arguments, commas, close, receiver, member_operator), identifier.span) as CallExpressionSyntax;
		}
		var call = new CallExpressionSyntax (identifier, open, arguments, commas, close, receiver, member_operator, receiver_place);
		call.type_arguments = type_arguments;
		return bounded (call, identifier.span) as CallExpressionSyntax;
	}

	private ExpressionSyntax? parse_owned_initializer(bool argument = false, bool field_initializer = false) {
		if (current.kind != TokenKind.MOVE) {
			return parse_expression (0, 0);
		}
		var keyword = current;
		if (!advance ()) {
			return null;
		}
		if (current.kind == TokenKind.THIS && next_is (TokenKind.DOT)) {
			fail (current.span, "moving ownership out of an owned field is unsupported; 'move' requires a named owner");
			return null;
		}
		var source = expect (TokenKind.IDENTIFIER, "expected owned local identifier after 'move'");
		if (source == null) {
			return null;
		}
		var fields = new GenericArray<Token> ();
		while (current.kind == TokenKind.DOT) {
			if (!advance ()) {
				return null;
			}
			var field = expect (TokenKind.IDENTIFIER, "expected record field after '.' in ownership move");
			if (field == null) {
				return null;
			}
			fields.add (field);
		}
		if (fields.length != 0 && (argument || field_initializer)) {
			fail (keyword.span, "projected owner moves require a fresh named local destination");
			return null;
		}
		if (field_initializer ? (current.kind != TokenKind.COMMA && current.kind != TokenKind.CLOSE_BRACE) : argument ? (current.kind != TokenKind.COMMA && current.kind != TokenKind.CLOSE_PAREN) : current.kind != TokenKind.SEMICOLON) {
			fail (current.span, "move initializer requires exactly 'move identifier'");
			return null;
		}
		return new MoveExpressionSyntax (keyword, source, fields);
	}

	private ExpressionSyntax? parse_vector_dot(int recursion_depth) {
		var keyword = current;
		int count = keyword.kind == TokenKind.MAC_WRAP || keyword.kind == TokenKind.MAC_F32 ? 3 : 2;
		if (!advance ()) {
			return null;
		}
		var open = expect (TokenKind.OPEN_PAREN, "expected '(' after dot/MAC primitive");
		if (open == null) {
			return null;
		}
		var operands = new GenericArray<ExpressionSyntax> ();
		var commas = new GenericArray<Token> ();
		for (int i = 0; i < count; i++) {
			if (i > 0) {
				var comma = expect (TokenKind.COMMA, "expected ',' between dot/MAC operands");
				if (comma == null) {
					return null;
				}
				commas.add (comma);
			}
			var operand = parse_expression (0, recursion_depth + 1);
			if (operand == null) {
				return null;
			}
			operands.add (operand);
		}
		TypeNameSyntax? destination = null;
		if (keyword.kind == TokenKind.DOT_WRAP) {
			var comma = expect (TokenKind.COMMA, "expected ',' before dot_wrap accumulator type");
			if (comma == null) {
				return null;
			}
			commas.add (comma);
			destination = parse_type ("expected dot_wrap accumulator type");
			if (destination == null) {
				return null;
			}
		}
		var close = expect (TokenKind.CLOSE_PAREN, "expected ')' after dot/MAC operands");
		return close == null ? null : bounded (new VectorDotExpressionSyntax (keyword, open, operands, destination, commas, close), keyword.span);
	}

	private ExpressionSyntax? parse_dsp(int recursion_depth) {
		var keyword = current;
		bool widen = keyword.kind == TokenKind.WIDEN_LOW || keyword.kind == TokenKind.WIDEN_HIGH;
		bool pack = keyword.kind == TokenKind.PACK_WRAP || keyword.kind == TokenKind.PACK_SAT;
		if (!advance ()) {
			return null;
		}
		var open = expect (TokenKind.OPEN_PAREN, "expected '(' after DSP primitive");
		var first = open == null ? null : parse_expression (0, recursion_depth + 1);
		if (first == null) {
			return null;
		}
		var commas = new GenericArray<Token> ();
		var comma = expect (TokenKind.COMMA, "expected ',' after first DSP operand");
		if (comma == null) {
			return null;
		}
		commas.add (comma);
		ExpressionSyntax? second = null;
		if (!widen) {
			second = parse_expression (0, recursion_depth + 1);
			if (second == null) {
				return null;
			}
		}
		TypeNameSyntax? destination = null;
		if (widen || pack) {
			if (pack) {
				comma = expect (TokenKind.COMMA, "expected ',' before DSP destination element type");
				if (comma == null) {
					return null;
				}
				commas.add (comma);
			}
			destination = parse_type ("expected DSP destination element type");
			if (destination == null) {
				return null;
			}
		}
		var close = expect (TokenKind.CLOSE_PAREN, "expected ')' after DSP operands");
		return close == null ? null : bounded (new DspExpressionSyntax (keyword, open, first, second, destination, commas, close), keyword.span);
	}

	private ExpressionSyntax? parse_vector_primitive(int recursion_depth) {
		var keyword = current;
		if (!advance ()) {
			return null;
		}
		var open = expect (TokenKind.OPEN_PAREN, "expected '(' after vector primitive");
		var first = open == null ? null : parse_expression (0, recursion_depth + 1);
		if (first == null) {
			return null;
		}
		var operands = new GenericArray<ExpressionSyntax> ();
		var indices = new GenericArray<Token> ();
		var commas = new GenericArray<Token> ();
		operands.add (first);
		int position = 1;
		while (current.kind == TokenKind.COMMA) {
			commas.add (current);
			if (!advance ()) {
				return null;
			}
			if (keyword.kind == TokenKind.SELECT || (keyword.kind == TokenKind.INSERT && position == 2)) {
				var operand = parse_expression (0, recursion_depth + 1);
				if (operand == null) {
					return null;
				}
				operands.add (operand);
			} else {
				string message = keyword.kind == TokenKind.SPLAT ? "splat lane count must be one unsuffixed positive decimal integer literal" : "vector lane index must be one unsuffixed non-negative decimal integer literal";
				var index = expect (TokenKind.INTEGER, message);
				if (index == null) {
					return null;
				}
				if (current.kind != TokenKind.COMMA && current.kind != TokenKind.CLOSE_PAREN) {
					fail (current.span, message);
					return null;
				}
				indices.add (index);
			}
			position++;
		}
		var close = expect (TokenKind.CLOSE_PAREN, "expected ')' after vector primitive operands");
		if (close == null) {
			return null;
		}
		int arity = keyword.kind == TokenKind.SPLAT ? 2 : 3;
		if (keyword.kind != TokenKind.SHUFFLE && position != arity) {
			fail (keyword.span, "'%s' requires exactly %d operands".printf (keyword.spelling (), arity));
			return null;
		}
		return bounded (new VectorPrimitiveExpressionSyntax (keyword, open, operands, indices, commas, close), keyword.span);
	}

	private bool context_allocation_prefix() {
		if (!next_is (TokenKind.OPEN_PAREN)) {
			return false;
		}
		var probe = new Parser.from_cursor (this);
		if (!probe.advance ()) {
			return false;
		}
		int depth = 0;
		for (int tokens = 0; tokens < MAX_EXPRESSION_DEPTH * 4; tokens++) {
			if (probe.current.kind == TokenKind.OPEN_PAREN) {
				depth++;
			}
			if (probe.current.kind == TokenKind.CLOSE_PAREN && --depth == 0) {
				return probe.advance () && probe.current.kind == TokenKind.IDENTIFIER;
			}
			if (probe.current.kind == TokenKind.EOF || !probe.advance ()) {
				return false;
			}
		}
		return false;
	}
	private ExpressionSyntax? parse_primary_or_prefix(int recursion_depth) {
		var token = current;
		if (token.kind == TokenKind.AWAIT) {
			if (!advance ()) {
				return null;
			}
			ExpressionSyntax? operation;
			if (current.kind == TokenKind.MOVE) {
				var move = current;
				if (!advance ()) {
					return null;
				}
				var name = expect (TokenKind.IDENTIFIER, "await move requires a named task");
				operation = name == null ? null : new MoveExpressionSyntax (move, name);
			} else {
				operation = parse_expression (30, recursion_depth + 1);
			}
			return operation == null ? null : bounded (new AwaitExpressionSyntax (token, operation), token.span);
		}
		// Contextual spelling preserves existing identifiers/functions named new.
		if (token.kind == TokenKind.IDENTIFIER && (token.spelling () == "new" || token.spelling () == "try_new") && (next_is (TokenKind.IDENTIFIER) || context_allocation_prefix ())) {
			if (!advance ()) {
				return null;
			}
			ExpressionSyntax? allocation_context = null;
			if (current.kind == TokenKind.OPEN_PAREN) {
				if (!advance ()) {
					return null;
				}
				allocation_context = parse_expression (0, recursion_depth + 1);
				if (allocation_context == null || expect (TokenKind.CLOSE_PAREN, "expected ')' after allocator context") == null) {
					return null;
				}
			}
			allocation_element = true;
			var element = parse_type ("expected concrete buffer element type after 'new'");
			allocation_element = false;
			if (element == null) {
				return null;
			}
			if (current.kind == TokenKind.OPEN_PAREN) {
				var call = parse_call (element.identifier, recursion_depth);
				return call == null ? null : bounded (new HeapObjectConstructionSyntax (token, element, call.arguments, call.close_paren, allocation_context), token.span);
			}
			if (token.spelling () == "try_new") {
				fail (token.span, "try_new requires an exact Class constructor with a checked allocation policy");
				return null;
			}
			if (expect (TokenKind.OPEN_BRACKET, "expected '[' after buffer element type or '(' after class name") == null) {
				return null;
			}
			var count = parse_expression (0, recursion_depth + 1);
			var close = count == null ? null : expect (TokenKind.CLOSE_BRACKET, "expected ']' after runtime array count");
			if (close == null) {
				return null;
			}
			ExpressionSyntax? failure_call = null;
			if (current.kind == TokenKind.ELSE) {
				if (!advance ()) {
					return null;
				}
				failure_call = parse_expression (0, recursion_depth + 1);
				if (failure_call == null) {
					return null;
				}
				var direct = failure_call;
				while (direct is ParenthesizedExpressionSyntax) {
					direct = ((ParenthesizedExpressionSyntax) direct).expression;
				}
				if (!(direct is CallExpressionSyntax)) {
					fail (failure_call.span, "allocation failure action requires a direct named or supported member call");
					return null;
				}
				if (current.kind == TokenKind.ELSE) {
					fail (current.span, "duplicate allocation failure clause");
					return null;
				}
			}
			return bounded (new BufferAllocationSyntax (token, element, count, close, failure_call, allocation_context), token.span);
		}
		switch (token.kind) {
		case TokenKind.CONST:
			fail (token.span, "'const' is a reserved keyword for compile-time constants");
			return null;
		case TokenKind.VAR:
			fail (token.span, "'var' is a reserved keyword for inferred local declarations");
			return null;
		case TokenKind.SLICE:
		case TokenKind.LEN:
			return advance () ? parse_call (token, recursion_depth) : null;
		case TokenKind.DOT_WRAP:
		case TokenKind.MAC_WRAP:
		case TokenKind.DOT_F32:
		case TokenKind.MAC_F32:
			return parse_vector_dot (recursion_depth);
		case TokenKind.SAT_ADD:
		case TokenKind.SAT_SUB:
		case TokenKind.WIDEN_LOW:
		case TokenKind.WIDEN_HIGH:
		case TokenKind.PACK_WRAP:
		case TokenKind.PACK_SAT:
		case TokenKind.INTERLEAVE_LOW:
		case TokenKind.INTERLEAVE_HIGH:
			return parse_dsp (recursion_depth);
		case TokenKind.SPLAT:
		case TokenKind.INSERT:
		case TokenKind.SHUFFLE:
		case TokenKind.SELECT:
			return parse_vector_primitive (recursion_depth);
		case TokenKind.ALL:
		case TokenKind.ANY:
			if (!advance ()) {
				return null;
			}
			var reduction_open = expect (TokenKind.OPEN_PAREN, "expected '(' after vector reduction keyword");
			var mask = reduction_open == null ? null : parse_expression (0, recursion_depth + 1);
			var reduction_close = mask == null ? null : expect (TokenKind.CLOSE_PAREN, "expected ')' after vector reduction operand");
			return reduction_close == null ? null : bounded (new VectorReductionExpressionSyntax (token, reduction_open, mask, reduction_close), token.span);
		case TokenKind.RELEASE:
			fail (token.span, "'release' is supported only as a statement: 'release identifier;'");
			return null;
		case TokenKind.MOVE:
			fail (token.span, "'move' is supported only as the direct initializer of a fresh 'owned void*' local");
			return null;
		case TokenKind.THIS:
		case TokenKind.IDENTIFIER:
			if (!advance ()) {
				return null;
			}
			if (begins_enum_application ()) {
				return parse_applied_enum_call (token, recursion_depth);
			}
			if (current.kind == TokenKind.OPEN_PAREN || begins_generic_call ()) {
				return parse_call (token, recursion_depth);
			}
			if (current.kind == TokenKind.DOT || current.kind == TokenKind.ARROW) {
				return parse_field_access (token, recursion_depth);
			}
			return new NameExpressionSyntax (token);
		case TokenKind.STAR:
			if (!advance ()) {
				return null;
			}
			var pointer = parse_expression (30, recursion_depth + 1);
			return pointer == null ? null : bounded (new DereferenceExpressionSyntax (token, pointer), token.span);
		case TokenKind.AMPERSAND:
			if (!advance ()) {
				return null;
			}
			var identifier = expect (TokenKind.IDENTIFIER, "expected direct local identifier after '&'");
			if (identifier == null) {
				return null;
			}
			if (current.kind == TokenKind.OPEN_BRACKET) {
				fail (current.span, "vector lanes have no storage identity and cannot be addressed");
				return null;
			}
			if (current.kind == TokenKind.DOT || current.kind == TokenKind.ARROW || current.kind == TokenKind.OPEN_PAREN) {
				fail (current.span, "address-of supports only a direct local identifier, not fields or expressions");
				return null;
			}
			return new AddressOfExpressionSyntax (token, identifier);
		case TokenKind.NULL:
			return advance () ? new NullPointerExpressionSyntax (token) : null;
		case TokenKind.TEXT:
			return advance () ? new TextLiteralExpressionSyntax (token) : null;
		case TokenKind.FLOAT:
			return advance () ? new FloatLiteralExpressionSyntax (token) : null;
		case TokenKind.INTEGER:
			return advance () ? new IntegerLiteralExpressionSyntax (token) : null;
		case TokenKind.TRUE:
		case TokenKind.FALSE:
			return advance () ? new BooleanLiteralExpressionSyntax (token) : null;
		case TokenKind.PLUS:
		case TokenKind.MINUS:
		case TokenKind.BANG:
		case TokenKind.TILDE:
			if (!advance ()) {
				return null;
			}
			var operand = parse_expression (30, recursion_depth + 1);
			return operand == null ? null : bounded (new PrefixExpressionSyntax (token, operand), token.span);
		case TokenKind.OPEN_PAREN:
			if (!advance ()) {
				return null;
			}
			var expression = parse_expression (0, recursion_depth + 1);
			if (expression == null) {
				return null;
			}
			var close = expect (TokenKind.CLOSE_PAREN, "expected ')' after expression");
			return close == null ? null : bounded (new ParenthesizedExpressionSyntax (token, expression, close), token.span);
			default:
			fail (token.span, "expected expression");
			return null;
		}
	}
}
}
