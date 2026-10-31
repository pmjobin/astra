// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public abstract class SyntaxNode : Object {
	public ForeignPolicySyntax? foreign_member { get; internal set; }
	private GenericArray<ForeignPolicySyntax>? selected_foreign_channels;
	public GenericArray<ForeignPolicySyntax> foreign_channels {
		get {
			if (selected_foreign_channels == null) {
				selected_foreign_channels = new GenericArray<ForeignPolicySyntax> ();
			}
			return selected_foreign_channels;
		}
	}
	// MODULE-1A top-level visibility; member privacy remains lexical.
	public bool module_internal { get; internal set; default = false; }
	public SourceSpan span { get; private set; }

	protected SyntaxNode (SourceSpan span) {
		this.span = span;
	}
}

public class CompilationUnitSyntax : SyntaxNode {
	public GenericArray<ClassDeclarationSyntax> c_classes { get; private set; default = new GenericArray<ClassDeclarationSyntax> (); }
	public GenericArray<ComImportSyntax> com_interfaces { get; private set; default = new GenericArray<ComImportSyntax> (); }
	public Token? namespace_name { get; internal set; }
	public GenericArray<Token> imports { get; private set; default = new GenericArray<Token> (); }
	public GenericArray<GenericTypeApplicationSyntax> type_applications { get; private set; default = new GenericArray<GenericTypeApplicationSyntax> (); }
	public GenericArray<AsyncRuntimeSyntax> async_runtimes { get; private set; default = new GenericArray<AsyncRuntimeSyntax> (); }
	public GenericArray<EnumDeclarationSyntax> enums { get; private set; default = new GenericArray<EnumDeclarationSyntax> (); }
	public GenericArray<ConstantDeclarationSyntax> constants { get; private set; default = new GenericArray<ConstantDeclarationSyntax> (); }
	public GenericArray<ClassDeclarationSyntax> classes { get; private set; default = new GenericArray<ClassDeclarationSyntax> (); }

	public GenericArray<NativeInstanceDeclarationSyntax> native_instances(bool include_generic = true) {
		var result = new GenericArray<NativeInstanceDeclarationSyntax> ();
		foreach (var instance in structs) {
			if (include_generic || instance.type_parameters.length == 0) {
				result.add (instance);
			}
		}
		foreach (var instance in classes) {
			if (include_generic || instance.type_parameters.length == 0) {
				result.add (instance);
			}
		}
		return result;
	}

	public GenericArray<FunctionDeclarationSyntax> functions { get; private set; }
	public GenericArray<StructDeclarationSyntax> structs { get; private set; }
	public Token end_of_file { get; private set; }

	public CompilationUnitSyntax (SourceFile source, GenericArray<FunctionDeclarationSyntax> functions, Token end_of_file, GenericArray<StructDeclarationSyntax>? structs = null) {
		base (SourceSpan (source, 0, source.length));
		this.functions = functions;
		this.structs = structs ?? new GenericArray<StructDeclarationSyntax> ();
		this.end_of_file = end_of_file;
	}
}

public abstract class NativeInstanceDeclarationSyntax : SyntaxNode {
	public ConcurrencyPolicy? concurrency_policy { get; internal set; }
	public GenericArray<CCodeEntrySyntax>? allocator { get; internal set; }
	public GenericArray<CCodeEntrySyntax>? alignment { get; internal set; }
	public GenericArray<CCodeEntrySyntax>? representation { get; internal set; }
	public GenericArray<SyntaxNode> members { get; private set; }
	public GenericArray<FunctionDeclarationSyntax> methods { get; private set; default = new GenericArray<FunctionDeclarationSyntax> (); }
	public Token keyword { get; private set; }
	public Token name { get; private set; }
	public Token open_brace { get; private set; }
	public GenericArray<StructFieldDeclarationSyntax> fields { get; private set; }
	public Token close_brace { get; private set; }

	protected NativeInstanceDeclarationSyntax (Token keyword, Token name, Token open_brace, GenericArray<StructFieldDeclarationSyntax> fields, Token close_brace, GenericArray<SyntaxNode>? members = null) {
		base (SourceSpan.cover (keyword.span, close_brace.span));
		this.keyword = keyword;
		this.name = name;
		this.open_brace = open_brace;
		this.fields = fields;
		this.members = members ?? new GenericArray<SyntaxNode> ();
		if (members == null) {
			foreach (var field in fields) {
				this.members.add (field);
			}
		}
		foreach (var member in this.members) {
			if (member is FunctionDeclarationSyntax && !(member is LifecycleDeclarationSyntax)) {
				methods.add ((FunctionDeclarationSyntax) member);
			}
		}
		this.close_brace = close_brace;
	}
}

public class StructDeclarationSyntax : NativeInstanceDeclarationSyntax {
	public GenericArray<WhereClauseSyntax> where_clauses { get; internal set; default = new GenericArray<WhereClauseSyntax> (); }
	public GenericArray<Token> type_parameters { get; internal set; default = new GenericArray<Token> (); }
	public StructDeclarationSyntax (Token keyword, Token name, Token open_brace, GenericArray<StructFieldDeclarationSyntax> fields, Token close_brace, GenericArray<SyntaxNode>? members = null) {
		base (keyword, name, open_brace, fields, close_brace, members);
	}
}

public class ClassDeclarationSyntax : NativeInstanceDeclarationSyntax {
	public GenericArray<WhereClauseSyntax> where_clauses { get; internal set; default = new GenericArray<WhereClauseSyntax> (); }
	public ForeignPolicySyntax? foreign_import { get; internal set; }
	public ForeignPolicySyntax? foreign_export { get; internal set; }
	public ForeignPolicySyntax? com_export { get; internal set; }
	public ForeignPolicySyntax? gobject_export { get; internal set; }
	public bool is_interface { get; internal set; default = false; }
	public GenericArray<Token> type_parameters { get; internal set; default = new GenericArray<Token> (); }
	public bool exact_heap_class { get; internal set; default = false; }
	public TypeNameSyntax? parent_class { get; internal set; }
	public Token? exception_root { get; internal set; }
	public ClassDeclarationSyntax (Token keyword, Token name, Token open_brace, GenericArray<StructFieldDeclarationSyntax> fields, Token close_brace, GenericArray<SyntaxNode>? members = null) {
		base (keyword, name, open_brace, fields, close_brace, members);
	}
}

public class StructFieldDeclarationSyntax : SyntaxNode {
	public Token? private_keyword { get; internal set; }
	public Token? readonly_keyword { get; internal set; }
	public Token? owned_keyword { get; private set; }
	public TypeNameSyntax type_name { get; private set; }
	public Token name { get; private set; }
	public Token semicolon { get; private set; }

	public StructFieldDeclarationSyntax (TypeNameSyntax type_name, Token name, Token semicolon, Token? owned_keyword = null) {
		base (SourceSpan.cover (owned_keyword == null ? type_name.span : owned_keyword.span, semicolon.span));
		this.owned_keyword = owned_keyword ?? ((type_name is SharedTypeSyntax) ? ((SharedTypeSyntax) type_name).keyword : null);
		this.type_name = type_name;
		this.name = name;
		this.semicolon = semicolon;
	}
}

public class WhereClauseSyntax : SyntaxNode {
	public Token keyword { get; private set; }
	public Token type_parameter { get; private set; }
	public Token colon { get; private set; }
	public GenericArray<Token> capabilities { get; private set; }
	public GenericArray<Token> commas { get; private set; }
	internal WhereClauseSyntax (Token keyword, Token parameter, Token colon, GenericArray<Token> capabilities, GenericArray<Token> commas) {
		base (SourceSpan.cover (keyword.span, capabilities[capabilities.length - 1].span));
		this.keyword = keyword;
		this.type_parameter = parameter;
		this.colon = colon;
		this.capabilities = capabilities;
		this.commas = commas;
	}
}

public class FunctionDeclarationSyntax : SyntaxNode {
	public bool is_signal { get; internal set; }
	public ForeignPolicySyntax? foreign_policy { get; private set; }
	public bool is_c_import { get { return extern_keyword != null || (foreign_policy != null && (foreign_policy.kind == DeclarationPolicyId.C_IMPORT || foreign_policy.kind == DeclarationPolicyId.GOBJECT_IMPORT)); } }
	public bool is_c_export { get { return export_keyword != null || (foreign_policy != null && foreign_policy.kind == DeclarationPolicyId.C_EXPORT); } }
	public bool utf8_factory { get; internal set; default = false; }
	public Token? async_keyword { get; private set; }
	public bool is_async { get { return async_keyword != null; } }
	public MemberDispatchSyntax dispatch { get; internal set; default = MemberDispatchSyntax.DIRECT; }
	public TypeNameSyntax? throws_class { get; internal set; }
	public GenericArray<CCodeEntrySyntax>? ccode { get; internal set; }
	public GenericArray<CCodeEntrySyntax>? floating_point { get; internal set; }
	public GenericArray<WhereClauseSyntax> where_clauses { get; internal set; default = new GenericArray<WhereClauseSyntax> (); }
	public GenericArray<Token> type_parameters { get; internal set; default = new GenericArray<Token> (); }
	public Token? owned_keyword { get; private set; }
	public TypeNameSyntax? return_type { get; private set; }
	public Token name { get; private set; }
	public Token open_paren { get; private set; }
	public GenericArray<ParameterSyntax> parameters { get; private set; }
	public GenericArray<Token> commas { get; private set; }
	public Token close_paren { get; private set; }
	public BlockStatementSyntax? body { get; private set; }
	public Token? extern_keyword { get; private set; }
	public Token? export_keyword { get; private set; }
	public Token? abi_identifier { get; private set; }
	public Token? semicolon { get; private set; }

	public FunctionDeclarationSyntax (TypeNameSyntax? return_type, Token name, Token open_paren, GenericArray<ParameterSyntax> parameters, GenericArray<Token> commas, Token close_paren, BlockStatementSyntax body, Token? export_keyword = null, Token? abi_identifier = null, Token? owned_keyword = null, Token? async_keyword = null, Token? factory_end = null, ForeignPolicySyntax? foreign_policy = null) {
		base (SourceSpan.cover (foreign_policy != null ? foreign_policy.span : async_keyword != null ? async_keyword.span : export_keyword == null ? (owned_keyword == null ? (return_type == null ? name.span : return_type.span) : owned_keyword.span) : export_keyword.span, factory_end == null ? body.span : factory_end.span));
		this.async_keyword = async_keyword;
		this.foreign_policy = foreign_policy;
		this.owned_keyword = owned_keyword ?? ((return_type is SharedTypeSyntax) ? ((SharedTypeSyntax) return_type).keyword : null);
		this.export_keyword = export_keyword;
		this.abi_identifier = abi_identifier;
		this.return_type = return_type;
		this.name = name;
		this.open_paren = open_paren;
		this.parameters = parameters;
		this.commas = commas;
		this.close_paren = close_paren;
		this.body = body;
	}

	public FunctionDeclarationSyntax.foreign (Token introducer, Token? abi_identifier, TypeNameSyntax return_type, Token name, Token open_paren, GenericArray<ParameterSyntax> parameters, GenericArray<Token> commas, Token close_paren, Token semicolon, Token? owned_keyword = null, ForeignPolicySyntax? foreign_policy = null) {
		base (SourceSpan.cover (introducer.span, semicolon.span));
		this.foreign_policy = foreign_policy;
		this.owned_keyword = owned_keyword ?? ((return_type is SharedTypeSyntax) ? ((SharedTypeSyntax) return_type).keyword : null);
		this.return_type = return_type;
		this.name = name;
		this.open_paren = open_paren;
		this.parameters = parameters;
		this.commas = commas;
		this.close_paren = close_paren;
		this.extern_keyword = foreign_policy == null ? introducer : null;
		this.abi_identifier = abi_identifier;
		this.semicolon = semicolon;
	}
}

// No source result type; only the native parameter/body syntax is shared.
public class LifecycleDeclarationSyntax : FunctionDeclarationSyntax {
	public GenericArray<ExpressionSyntax>? base_arguments { get; internal set; }
	public bool is_constructor { get { return name.spelling () == "init"; } }
	public LifecycleDeclarationSyntax (Token name, Token open, GenericArray<ParameterSyntax> parameters, GenericArray<Token> commas, Token close, BlockStatementSyntax body) {
		base (null, name, open, parameters, commas, close, body);
	}
}

public class TypeNameSyntax : SyntaxNode {
	public Token? namespace_qualifier { get; internal set; }
	public string lookup_name() {
		return (namespace_qualifier == null ? "" : namespace_qualifier.spelling () + ".") + identifier.spelling ();
	}
	public Token identifier { get; private set; }
	public GenericArray<Token> stars { get; private set; }

	public TypeNameSyntax (Token identifier, GenericArray<Token>? stars = null, Token? qualifier = null) {
		base (SourceSpan.cover (qualifier == null ? identifier.span : qualifier.span, stars == null || stars.length == 0 ? identifier.span : stars[stars.length - 1].span));
		this.namespace_qualifier = qualifier;
		this.identifier = identifier;
		this.stars = stars ?? new GenericArray<Token> ();
	}

	protected TypeNameSyntax.shaped (SourceSpan span, Token identifier) {
		base (span);
		this.identifier = identifier;
		this.stars = new GenericArray<Token> ();
	}

	public virtual string spelling() {
		return lookup_name () + string.nfill (stars.length, '*');
	}
}

// Compose a pointer suffix with an already parsed shaped type. Scalar
// declarations retain TypeNameSyntax's existing star tokens and dump format.
public class PointerTypeSyntax : TypeNameSyntax {
	public TypeNameSyntax pointee { get; private set; }
	public Token star { get; private set; }

	public PointerTypeSyntax (TypeNameSyntax pointee, Token star) {
		base.shaped (SourceSpan.cover (pointee.span, star.span), pointee.identifier);
		this.pointee = pointee;
		this.star = star;
	}

	public override string spelling() {
		return pointee.spelling () + "*";
	}
}

public class NonNullTypeSyntax : TypeNameSyntax {
	public Token keyword { get; private set; }
	public TypeNameSyntax underlying { get; private set; }
	public NonNullTypeSyntax (Token keyword, TypeNameSyntax underlying) {
		base.shaped (SourceSpan.cover (keyword.span, underlying.span), underlying.identifier);
		this.keyword = keyword;
		this.underlying = underlying;
		this.namespace_qualifier = underlying.namespace_qualifier;
	}
	public override string spelling() {
		return "nonnull " + underlying.spelling ();
	}
}
// Ownership belongs to a callable channel rather than the represented type.
// The parser creates this wrapper only within Fn/Closure signatures.
public class CallableChannelTypeSyntax : TypeNameSyntax {
	public Token keyword { get; private set; }
	public TypeNameSyntax underlying { get; private set; }
	public CallableChannelTypeSyntax (Token keyword, TypeNameSyntax underlying) {
		base.shaped (SourceSpan.cover (keyword.span, underlying.span), underlying.identifier);
		this.keyword = keyword;
		this.underlying = underlying;
		this.namespace_qualifier = underlying.namespace_qualifier;
	}
	public override string spelling() {
		return keyword.spelling () + " " + underlying.spelling ();
	}
}

public class SharedTypeSyntax : TypeNameSyntax {
	public Token keyword { get; private set; }
	public TypeNameSyntax payload { get; private set; }
	public SharedTypeSyntax (Token keyword, TypeNameSyntax payload) {
		base.shaped (SourceSpan.cover (keyword.span, payload.span), keyword);
		this.keyword = keyword;
		this.payload = payload;
	}
	public override string spelling() {
		return "shared " + payload.spelling ();
	}
}

public class VectorTypeSyntax : TypeNameSyntax {
	public TypeNameSyntax element_type { get; private set; }
	public Token open_angle { get; private set; }
	public Token lane_count { get; private set; }
	public Token close_angle { get; private set; }

	public VectorTypeSyntax (TypeNameSyntax element_type, Token open_angle, Token lane_count, Token close_angle) {
		base.shaped (SourceSpan.cover (element_type.span, close_angle.span), element_type.identifier);
		this.element_type = element_type;
		this.open_angle = open_angle;
		this.lane_count = lane_count;
		this.close_angle = close_angle;
	}

	public override string spelling() {
		return element_type.spelling () + "<" + lane_count.spelling () + ">";
	}
}

public class GenericTypeApplicationSyntax : TypeNameSyntax {
	public GenericArray<TypeNameSyntax> type_arguments { get; private set; }
	public GenericTypeApplicationSyntax (Token identifier, GenericArray<TypeNameSyntax> arguments, SourceSpan end) {
		base.shaped (end, identifier);
		this.type_arguments = arguments;
	}
	public override string spelling() {
		var text = new StringBuilder (lookup_name () + "<");
		for (int i = 0; i < type_arguments.length; i++) {
			if (i != 0) {
				text.append (",");
			}
			text.append (type_arguments[i].spelling ());
		}
		text.append (">");
		return text.str;
	}
}

public class ParameterSyntax : SyntaxNode {
	public CallerInformationSyntax? caller_information { get; private set; }
	public TypeNameSyntax type_name { get; private set; }
	public Token name { get; private set; }
	public Token? borrowed_keyword { get; private set; }
	public Token? owned_keyword { get; private set; }

	public ParameterSyntax (TypeNameSyntax type_name, Token name, Token? borrowed_keyword = null, Token? owned_keyword = null, CallerInformationSyntax? caller_information = null) {
		base (SourceSpan.cover (caller_information != null ? caller_information.span : borrowed_keyword == null ? (owned_keyword == null ? type_name.span : owned_keyword.span) : borrowed_keyword.span, name.span));
		this.caller_information = caller_information;
		this.owned_keyword = owned_keyword ?? (borrowed_keyword == null && (type_name is SharedTypeSyntax) ? ((SharedTypeSyntax) type_name).keyword : null);
		this.borrowed_keyword = borrowed_keyword;
		this.type_name = type_name;
		this.name = name;
	}
}

public abstract class StatementSyntax : SyntaxNode {
	protected StatementSyntax (SourceSpan span) {
		base (span);
	}
}

public class BlockStatementSyntax : StatementSyntax {
	public Token open_brace { get; private set; }
	public GenericArray<StatementSyntax> statements { get; private set; }
	public Token close_brace { get; private set; }

	public BlockStatementSyntax (Token open_brace, GenericArray<StatementSyntax> statements, Token close_brace) {
		base (SourceSpan.cover (open_brace.span, close_brace.span));
		this.open_brace = open_brace;
		this.statements = statements;
		this.close_brace = close_brace;
	}
}

public class IfStatementSyntax : StatementSyntax {
	public Token keyword { get; private set; }
	public Token open_paren { get; private set; }
	public ExpressionSyntax condition { get; private set; }
	public Token close_paren { get; private set; }
	public BlockStatementSyntax then_body { get; private set; }
	public Token? else_keyword { get; private set; }
	public BlockStatementSyntax? else_body { get; private set; }

	public IfStatementSyntax (Token keyword, Token open_paren, ExpressionSyntax condition, Token close_paren, BlockStatementSyntax then_body, Token? else_keyword, BlockStatementSyntax? else_body) {
		base (SourceSpan.cover (keyword.span, else_body == null ? then_body.span : else_body.span));
		this.keyword = keyword;
		this.open_paren = open_paren;
		this.condition = condition;
		this.close_paren = close_paren;
		this.then_body = then_body;
		this.else_keyword = else_keyword;
		this.else_body = else_body;
	}
}

public class WithStatementSyntax : StatementSyntax {
	public Token keyword { get; private set; }
	public Token receiver { get; private set; }
	public InferredLocalDeclarationSyntax? initializer { get; private set; }
	public BlockStatementSyntax body { get; private set; }
	public WithStatementSyntax (Token keyword, Token receiver, InferredLocalDeclarationSyntax? initializer, BlockStatementSyntax body) {
		base (SourceSpan.cover (keyword.span, body.span));
		this.keyword = keyword;
		this.receiver = receiver;
		this.initializer = initializer;
		this.body = body;
	}
}

public class ForeachStatementSyntax : StatementSyntax {
	public Token keyword { get; private set; }
	public Token binding { get; private set; }
	public ExpressionSyntax collection { get; private set; }
	public BlockStatementSyntax body { get; private set; }
	public ForeachStatementSyntax (Token keyword, Token binding, ExpressionSyntax collection, BlockStatementSyntax body) {
		base (SourceSpan.cover (keyword.span, body.span));
		this.keyword = keyword;
		this.binding = binding;
		this.collection = collection;
		this.body = body;
	}
}

public class ForStatementSyntax : StatementSyntax {
	public Token keyword { get; private set; }
	public StatementSyntax? initializer { get; private set; }
	public ExpressionSyntax? condition { get; private set; }
	public StatementSyntax? step { get; private set; }
	public BlockStatementSyntax body { get; private set; }

	public ForStatementSyntax (Token keyword, StatementSyntax? initializer, ExpressionSyntax? condition, StatementSyntax? step, BlockStatementSyntax body) {
		base (SourceSpan.cover (keyword.span, body.span));
		this.keyword = keyword;
		this.initializer = initializer;
		this.condition = condition;
		this.step = step;
		this.body = body;
	}
}

public class WhileStatementSyntax : StatementSyntax {
	public Token keyword { get; private set; }
	public Token open_paren { get; private set; }
	public ExpressionSyntax condition { get; private set; }
	public Token close_paren { get; private set; }
	public BlockStatementSyntax body { get; private set; }

	public WhileStatementSyntax (Token keyword, Token open_paren, ExpressionSyntax condition, Token close_paren, BlockStatementSyntax body) {
		base (SourceSpan.cover (keyword.span, body.span));
		this.keyword = keyword;
		this.open_paren = open_paren;
		this.condition = condition;
		this.close_paren = close_paren;
		this.body = body;
	}
}

public class BreakStatementSyntax : StatementSyntax {
	public Token keyword { get; private set; }
	public Token semicolon { get; private set; }

	public BreakStatementSyntax (Token keyword, Token semicolon) {
		base (SourceSpan.cover (keyword.span, semicolon.span));
		this.keyword = keyword;
		this.semicolon = semicolon;
	}
}

public class ContinueStatementSyntax : StatementSyntax {
	public Token keyword { get; private set; }
	public Token semicolon { get; private set; }

	public ContinueStatementSyntax (Token keyword, Token semicolon) {
		base (SourceSpan.cover (keyword.span, semicolon.span));
		this.keyword = keyword;
		this.semicolon = semicolon;
	}
}

public class ReleaseStatementSyntax : StatementSyntax {
	public Token keyword { get; private set; }
	public Token owner { get; private set; }
	public Token semicolon { get; private set; }

	public ReleaseStatementSyntax (Token keyword, Token owner, Token semicolon) {
		base (SourceSpan.cover (keyword.span, semicolon.span));
		this.keyword = keyword;
		this.owner = owner;
		this.semicolon = semicolon;
	}
}

public class ReturnStatementSyntax : StatementSyntax {
	public Token keyword { get; private set; }
	public ExpressionSyntax? expression { get; private set; }
	public Token semicolon { get; private set; }

	public ReturnStatementSyntax (Token keyword, ExpressionSyntax? expression, Token semicolon) {
		base (SourceSpan.cover (keyword.span, semicolon.span));
		this.keyword = keyword;
		this.expression = expression;
		this.semicolon = semicolon;
	}
}

// Contextual local initializer, deliberately not an ExpressionSyntax.
public class StructInitializerSyntax : SyntaxNode {
	public Token open_brace { get; private set; }
	public GenericArray<FieldInitializerSyntax> fields { get; private set; }
	public GenericArray<Token> commas { get; private set; }
	public Token close_brace { get; private set; }

	public StructInitializerSyntax (Token open_brace, GenericArray<FieldInitializerSyntax> fields, GenericArray<Token> commas, Token close_brace) {
		base (SourceSpan.cover (open_brace.span, close_brace.span));
		this.open_brace = open_brace;
		this.fields = fields;
		this.commas = commas;
		this.close_brace = close_brace;
	}
}

public class FieldInitializerSyntax : SyntaxNode {
	public Token name { get; private set; }
	public Token equals_token { get; private set; }
	public ExpressionSyntax expression { get; private set; }

	public StructInitializerSyntax? initializer { get; private set; }

	public FieldInitializerSyntax.nested (Token name, Token equals_token, StructInitializerSyntax initializer) {
		base (SourceSpan.cover (name.span, initializer.span));
		this.name = name;
		this.equals_token = equals_token;
		this.initializer = initializer;
	}

	public FieldInitializerSyntax (Token name, Token equals_token, ExpressionSyntax expression) {
		base (SourceSpan.cover (name.span, expression.span));
		this.name = name;
		this.equals_token = equals_token;
		this.expression = expression;
	}
}

public class StructLocalDeclarationSyntax : StatementSyntax {
	public Token? owned_keyword { get; private set; }
	public TypeNameSyntax type_name { get; private set; }
	public Token name { get; private set; }
	public Token equals_token { get; private set; }
	public StructInitializerSyntax initializer { get; private set; }
	public Token semicolon { get; private set; }

	public StructLocalDeclarationSyntax (TypeNameSyntax type_name, Token name, Token equals_token, StructInitializerSyntax initializer, Token semicolon, Token? owned_keyword = null) {
		base (SourceSpan.cover (owned_keyword == null ? type_name.span : owned_keyword.span, semicolon.span));
		this.owned_keyword = owned_keyword;
		this.type_name = type_name;
		this.name = name;
		this.equals_token = equals_token;
		this.initializer = initializer;
		this.semicolon = semicolon;
	}
}

public class FieldAssignmentStatementSyntax : StatementSyntax {
	public FieldAccessExpressionSyntax target { get; private set; }
	public Token equals_token { get; private set; }
	public ExpressionSyntax expression { get; private set; }
	public Token? semicolon { get; private set; }

	public FieldAssignmentStatementSyntax (FieldAccessExpressionSyntax target, Token equals_token, ExpressionSyntax expression, Token? semicolon) {
		base (SourceSpan.cover (target.span, (semicolon == null ? expression.span : semicolon.span)));
		this.target = target;
		this.equals_token = equals_token;
		this.expression = expression;
		this.semicolon = semicolon;
	}
}

public class MoveExpressionSyntax : ExpressionSyntax {
	public Token keyword { get; private set; }
	public Token source { get; private set; }
	public GenericArray<Token> fields { get; private set; }

	public MoveExpressionSyntax (Token keyword, Token source, GenericArray<Token>? fields = null) {
		base (SourceSpan.cover (keyword.span, fields == null || fields.length == 0 ? source.span : fields[fields.length - 1].span), 1);
		this.keyword = keyword;
		this.source = source;
		this.fields = fields ?? new GenericArray<Token> ();
	}
}

public class InferredLocalDeclarationSyntax : StatementSyntax {
	public Token keyword { get; private set; }
	public Token name { get; private set; }
	public Token equals_token { get; private set; }
	public ExpressionSyntax initializer { get; private set; }
	public Token? semicolon { get; private set; }

	public InferredLocalDeclarationSyntax (Token keyword, Token name, Token equals_token, ExpressionSyntax initializer, Token? semicolon) {
		base (SourceSpan.cover (keyword.span, semicolon == null ? initializer.span : semicolon.span));
		this.keyword = keyword;
		this.name = name;
		this.equals_token = equals_token;
		this.initializer = initializer;
		this.semicolon = semicolon;
	}
}

public class LocalDeclarationSyntax : StatementSyntax {
	public Token? owned_keyword { get; private set; }
	public TypeNameSyntax type_name { get; private set; }
	public Token name { get; private set; }
	public Token equals_token { get; private set; }
	public ExpressionSyntax initializer { get; private set; }
	public Token semicolon { get; private set; }

	public LocalDeclarationSyntax (TypeNameSyntax type_name, Token name, Token equals_token, ExpressionSyntax initializer, Token semicolon, Token? owned_keyword = null) {
		base (SourceSpan.cover (owned_keyword == null ? type_name.span : owned_keyword.span, semicolon.span));
		this.owned_keyword = owned_keyword ?? ((type_name is SharedTypeSyntax) ? ((SharedTypeSyntax) type_name).keyword : null);
		this.type_name = type_name;
		this.name = name;
		this.equals_token = equals_token;
		this.initializer = initializer;
		this.semicolon = semicolon;
	}
}

public class CallStatementSyntax : StatementSyntax {
	public CallExpressionSyntax call { get; private set; }
	public Token? semicolon { get; private set; }

	public CallStatementSyntax (CallExpressionSyntax call, Token? semicolon) {
		base (SourceSpan.cover (call.span, (semicolon == null ? call.span : semicolon.span)));
		this.call = call;
		this.semicolon = semicolon;
	}
}

public class AssignmentStatementSyntax : StatementSyntax {
	public Token name { get; private set; }
	public Token equals_token { get; private set; }
	public ExpressionSyntax expression { get; private set; }
	public Token? semicolon { get; private set; }

	public AssignmentStatementSyntax (Token name, Token equals_token, ExpressionSyntax expression, Token? semicolon) {
		base (SourceSpan.cover (name.span, (semicolon == null ? expression.span : semicolon.span)));
		this.name = name;
		this.equals_token = equals_token;
		this.expression = expression;
		this.semicolon = semicolon;
	}
}

public abstract class ExpressionSyntax : SyntaxNode {
	// Host stack safety metadata, with no language/semantic interpretation.
	internal int tree_depth;

	protected ExpressionSyntax (SourceSpan span, int tree_depth) {
		base (span);
		this.tree_depth = tree_depth;
	}
}

// Parsed only at the direct local initializer site, never as a general literal.
public class VectorInitializerSyntax : ExpressionSyntax {
	public Token open_brace { get; private set; }
	public GenericArray<ExpressionSyntax> lanes { get; private set; }
	public GenericArray<Token> commas { get; private set; }
	public Token close_brace { get; private set; }

	public VectorInitializerSyntax (Token open_brace, GenericArray<ExpressionSyntax> lanes, GenericArray<Token> commas, Token close_brace) {
		base (SourceSpan.cover (open_brace.span, close_brace.span), 1);
		this.open_brace = open_brace;
		this.lanes = lanes;
		this.commas = commas;
		this.close_brace = close_brace;
		foreach (var lane in lanes) {
			tree_depth = int.max (tree_depth, lane.tree_depth + 1);
		}
	}
}

// Ordinals remain tokens, never ordinary expression operands.
public class VectorPrimitiveExpressionSyntax : ExpressionSyntax {
	public Token keyword { get; private set; }
	public Token open_paren { get; private set; }
	public GenericArray<ExpressionSyntax> operands { get; private set; }
	public GenericArray<Token> indices { get; private set; }
	public GenericArray<Token> commas { get; private set; }
	public Token close_paren { get; private set; }

	public VectorPrimitiveExpressionSyntax (Token keyword, Token open_paren, GenericArray<ExpressionSyntax> operands, GenericArray<Token> indices, GenericArray<Token> commas, Token close_paren) {
		base (SourceSpan.cover (keyword.span, close_paren.span), 1);
		this.keyword = keyword;
		this.open_paren = open_paren;
		this.operands = operands;
		this.indices = indices;
		this.commas = commas;
		this.close_paren = close_paren;
		foreach (var operand in operands) {
			tree_depth = int.max (tree_depth, operand.tree_depth + 1);
		}
	}
}

public class VectorDotExpressionSyntax : ExpressionSyntax {
	public Token keyword { get; private set; }
	public Token open_paren { get; private set; }
	public GenericArray<ExpressionSyntax> operands { get; private set; }
	public TypeNameSyntax? destination { get; private set; }
	public GenericArray<Token> commas { get; private set; }
	public Token close_paren { get; private set; }

	public VectorDotExpressionSyntax (Token keyword, Token open_paren, GenericArray<ExpressionSyntax> operands, TypeNameSyntax? destination, GenericArray<Token> commas, Token close_paren) {
		base (SourceSpan.cover (keyword.span, close_paren.span), 1);
		this.keyword = keyword;
		this.open_paren = open_paren;
		this.operands = operands;
		this.destination = destination;
		this.commas = commas;
		this.close_paren = close_paren;
		foreach (var operand in operands) {
			tree_depth = int.max (tree_depth, operand.tree_depth + 1);
		}
	}
}

public class DspExpressionSyntax : ExpressionSyntax {
	public Token keyword { get; private set; }
	public Token open_paren { get; private set; }
	public ExpressionSyntax first { get; private set; }
	public ExpressionSyntax? second { get; private set; }
	public TypeNameSyntax? destination { get; private set; }
	public GenericArray<Token> commas { get; private set; }
	public Token close_paren { get; private set; }

	public DspExpressionSyntax (Token keyword, Token open_paren, ExpressionSyntax first, ExpressionSyntax? second, TypeNameSyntax? destination, GenericArray<Token> commas, Token close_paren) {
		base (SourceSpan.cover (keyword.span, close_paren.span), int.max (first.tree_depth, second == null ? 0 : second.tree_depth) + 1);
		this.keyword = keyword;
		this.open_paren = open_paren;
		this.first = first;
		this.second = second;
		this.destination = destination;
		this.commas = commas;
		this.close_paren = close_paren;
	}
}

public class ConversionExpressionSyntax : ExpressionSyntax {
	public ExpressionSyntax operand { get; private set; }
	public Token keyword { get; private set; }
	public TypeNameSyntax destination { get; private set; }

	public ConversionExpressionSyntax (ExpressionSyntax operand, Token keyword, TypeNameSyntax destination) {
		base (SourceSpan.cover (operand.span, destination.span), operand.tree_depth + 1);
		this.operand = operand;
		this.keyword = keyword;
		this.destination = destination;
	}
}

public class VectorExtractExpressionSyntax : IndexExpressionSyntax {
	public ExpressionSyntax vector { get; private set; }
	public Token open_bracket { get; private set; }
	public Token index { get; private set; }
	public Token close_bracket { get; private set; }

	public VectorExtractExpressionSyntax (ExpressionSyntax vector, Token open_bracket, Token index, Token close_bracket) {
		base (vector, new IntegerLiteralExpressionSyntax (index), close_bracket);
		this.vector = vector;
		this.open_bracket = open_bracket;
		this.index = index;
		this.close_bracket = close_bracket;
	}
}

public class VectorReductionExpressionSyntax : ExpressionSyntax {
	public Token keyword { get; private set; }
	public Token open_paren { get; private set; }
	public ExpressionSyntax operand { get; private set; }
	public Token close_paren { get; private set; }

	public VectorReductionExpressionSyntax (Token keyword, Token open_paren, ExpressionSyntax operand, Token close_paren) {
		base (SourceSpan.cover (keyword.span, close_paren.span), operand.tree_depth + 1);
		this.keyword = keyword;
		this.open_paren = open_paren;
		this.operand = operand;
		this.close_paren = close_paren;
	}
}

// Reuses ordered argument syntax, but is produced only at a fresh local
// construction site; ordinary expression parsing never produces this node.
public class ConstructorInitializerSyntax : CallExpressionSyntax {
	public ConstructorInitializerSyntax (Token name, Token open, GenericArray<ExpressionSyntax> arguments, GenericArray<Token> commas, Token close, Token type_name, Token dot) {
		base (name, open, arguments, commas, close, type_name, dot);
	}
}

public class CallExpressionSyntax : ExpressionSyntax {
	public bool signal_emission { get; internal set; }
	public GenericArray<TypeNameSyntax> qualifier_arguments { get; internal set; default = new GenericArray<TypeNameSyntax> (); }
	public GenericArray<TypeNameSyntax> type_arguments { get; internal set; default = new GenericArray<TypeNameSyntax> (); }
	public ExpressionSyntax? receiver_place { get; private set; }
	public Token? receiver { get; private set; }
	public Token? member_operator { get; private set; }
	public Token identifier { get; private set; }
	public Token open_paren { get; private set; }
	public GenericArray<ExpressionSyntax> arguments { get; private set; }
	public GenericArray<Token> commas { get; private set; }
	public Token close_paren { get; private set; }

	public CallExpressionSyntax (Token identifier, Token open_paren, GenericArray<ExpressionSyntax> arguments, GenericArray<Token> commas, Token close_paren, Token? receiver = null, Token? member_operator = null, ExpressionSyntax? receiver_place = null) {
		base (SourceSpan.cover (receiver_place != null ? receiver_place.span : receiver == null ? identifier.span : receiver.span, close_paren.span), receiver_place == null ? 1 : receiver_place.tree_depth + 1);
		this.receiver_place = receiver_place;
		this.receiver = receiver;
		this.member_operator = member_operator;
		this.identifier = identifier;
		this.open_paren = open_paren;
		this.arguments = arguments;
		this.commas = commas;
		this.close_paren = close_paren;
		for (int i = 0; i < arguments.length; i++) {
			tree_depth = int.max (tree_depth, arguments[i].tree_depth + 1);
		}
	}
}

public class FieldAccessExpressionSyntax : ExpressionSyntax {
	public Token identifier { get; private set; }
	public Token dot { get; private set; }
	public bool indirect { get { return dot.kind == TokenKind.ARROW; } }
	public Token field_name { get; private set; }

	public ExpressionSyntax? aggregate { get; private set; }

	public FieldAccessExpressionSyntax.projection (ExpressionSyntax aggregate, Token dot, Token field_name) {
		base (SourceSpan.cover (aggregate.span, field_name.span), aggregate.tree_depth + 1);
		this.aggregate = aggregate;
		this.identifier = (aggregate is FieldAccessExpressionSyntax) ? ((FieldAccessExpressionSyntax) aggregate).identifier : field_name;
		this.dot = dot;
		this.field_name = field_name;
	}

	public FieldAccessExpressionSyntax (Token identifier, Token dot, Token field_name) {
		base (SourceSpan.cover (identifier.span, field_name.span), 1);
		this.identifier = identifier;
		this.dot = dot;
		this.field_name = field_name;
	}
}

public class NameExpressionSyntax : ExpressionSyntax {
	public Token identifier { get; private set; }

	public NameExpressionSyntax (Token identifier) {
		base (identifier.span, 1);
		this.identifier = identifier;
	}
}

public class FloatLiteralExpressionSyntax : ExpressionSyntax {
	public Token literal { get; private set; }

	public FloatLiteralExpressionSyntax (Token literal) {
		base (literal.span, 1);
		this.literal = literal;
	}
}

public class IntegerLiteralExpressionSyntax : ExpressionSyntax {
	public Token literal { get; private set; }

	public IntegerLiteralExpressionSyntax (Token literal) {
		base (literal.span, 1);
		this.literal = literal;
	}
}

public class NullPointerExpressionSyntax : ExpressionSyntax {
	public Token keyword { get; private set; }

	public NullPointerExpressionSyntax (Token keyword) {
		base (keyword.span, 1);
		this.keyword = keyword;
	}
}

public class BooleanLiteralExpressionSyntax : ExpressionSyntax {
	public Token literal { get; private set; }

	public BooleanLiteralExpressionSyntax (Token literal) {
		base (literal.span, 1);
		this.literal = literal;
	}
}

public class ParenthesizedExpressionSyntax : ExpressionSyntax {
	public Token open_paren { get; private set; }
	public ExpressionSyntax expression { get; private set; }
	public Token close_paren { get; private set; }

	public ParenthesizedExpressionSyntax (Token open_paren, ExpressionSyntax expression, Token close_paren) {
		base (SourceSpan.cover (open_paren.span, close_paren.span), expression.tree_depth + 1);
		this.open_paren = open_paren;
		this.expression = expression;
		this.close_paren = close_paren;
	}
}

public class PrefixExpressionSyntax : ExpressionSyntax {
	public Token operator_token { get; private set; }
	public ExpressionSyntax operand { get; private set; }

	public PrefixExpressionSyntax (Token operator_token, ExpressionSyntax operand) {
		base (SourceSpan.cover (operator_token.span, operand.span), operand.tree_depth + 1);
		this.operator_token = operator_token;
		this.operand = operand;
	}
}

// Evaluates left first and right only on the required path.
public class ShortCircuitExpressionSyntax : ExpressionSyntax {
	public ExpressionSyntax left { get; private set; }
	public Token operator_token { get; private set; }
	public ExpressionSyntax right { get; private set; }

	public ShortCircuitExpressionSyntax (ExpressionSyntax left, Token operator_token, ExpressionSyntax right) {
		base (SourceSpan.cover (left.span, right.span), int.max (left.tree_depth, right.tree_depth) + 1);
		this.left = left;
		this.operator_token = operator_token;
		this.right = right;
	}
}

public class ComparisonChainSyntax : ExpressionSyntax {
	public GenericArray<ExpressionSyntax> operands { get; private set; }
	public GenericArray<Token> operators { get; private set; }
	public ComparisonChainSyntax (GenericArray<ExpressionSyntax> operands, GenericArray<Token> operators) {
		base (SourceSpan.cover (operands[0].span, operands[operands.length - 1].span), operands.length);
		this.operands = operands;
		this.operators = operators;
		foreach (var operand in operands) {
			tree_depth = int.max (tree_depth, operand.tree_depth + 1);
		}
	}
}

public class BinaryExpressionSyntax : ExpressionSyntax {
	public ExpressionSyntax left { get; private set; }
	public Token operator_token { get; private set; }
	public ExpressionSyntax right { get; private set; }

	public BinaryExpressionSyntax (ExpressionSyntax left, Token operator_token, ExpressionSyntax right) {
		base (SourceSpan.cover (left.span, right.span), int.max (left.tree_depth, right.tree_depth) + 1);
		this.left = left;
		this.operator_token = operator_token;
		this.right = right;
	}
}

public class DereferenceExpressionSyntax : ExpressionSyntax {
	public Token star { get; private set; }
	public ExpressionSyntax pointer { get; private set; }

	public DereferenceExpressionSyntax (Token star, ExpressionSyntax pointer) {
		base (SourceSpan.cover (star.span, pointer.span), pointer.tree_depth + 1);
		this.star = star;
		this.pointer = pointer;
	}
}

public class DereferenceAssignmentSyntax : StatementSyntax {
	public DereferenceExpressionSyntax target { get; private set; }
	public ExpressionSyntax expression { get; private set; }

	public DereferenceAssignmentSyntax (DereferenceExpressionSyntax target, ExpressionSyntax expression, Token? semicolon) {
		base (SourceSpan.cover (target.span, (semicolon == null ? expression.span : semicolon.span)));
		this.target = target;
		this.expression = expression;
	}
}

public class AddressOfExpressionSyntax : ExpressionSyntax {
	public Token ampersand { get; private set; }
	public Token identifier { get; private set; }

	public AddressOfExpressionSyntax (Token ampersand, Token identifier) {
		base (SourceSpan.cover (ampersand.span, identifier.span), 1);
		this.ampersand = ampersand;
		this.identifier = identifier;
	}
}
}
