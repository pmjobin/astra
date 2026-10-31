// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;
using Astra.Syntax;

namespace Astra.Semantic {
// A separate compiler-owned namespace; ordinary type/value/member lookup is irrelevant.
public class GenericCapabilitySymbol : Object {
	public GenericCapabilityIdentity identity { get; private set; }
	public string name { owned get { return identity.spelling (); } }
	internal GenericCapabilitySymbol (GenericCapabilityIdentity identity) {
		this.identity = identity;
	}
}

public class GenericCapabilityNamespace : Object {
	private HashTable<string, GenericCapabilitySymbol> names = new HashTable<string, GenericCapabilitySymbol> (str_hash, str_equal);
	public GenericCapabilityNamespace () {
		for (int i = 0; i <= GenericCapabilityIdentity.OWNABLE; i++) {
			var symbol = new GenericCapabilitySymbol ((GenericCapabilityIdentity) i);
			names.insert (symbol.name, symbol);
		}
	}
	public GenericCapabilitySymbol? resolve(string name) {
		return names.lookup (name);
	}
}

public class GenericCapabilityRequirement : Object {
	private WeakRef parameter;
	public TypeParameterSymbol? type_parameter { owned get { return (TypeParameterSymbol?) parameter.get (); } }
	public GenericCapabilitySymbol capability { get; private set; }
	public SourceSpan span { get; private set; }
	internal GenericCapabilityRequirement (TypeParameterSymbol parameter, GenericCapabilitySymbol capability, SourceSpan span) {
		this.parameter = WeakRef (parameter);
		this.capability = capability;
		this.span = span;
	}
}

public class CheckedGenericCapabilityOperation : CheckedExpression {
	public GenericOperationKind operator_kind { get; private set; }
	public TypeParameterType type_parameter { get; private set; }
	public GenericCapabilitySymbol capability { get; private set; }
	public CheckedExpression left { get; private set; }
	public CheckedExpression? right { get; private set; }
	internal CheckedGenericCapabilityOperation (SourceSpan span, SemanticType result, GenericOperationKind kind, TypeParameterType parameter, GenericCapabilitySymbol capability, CheckedExpression left, CheckedExpression? right = null) {
		base (span, result);
		this.operator_kind = kind;
		this.type_parameter = parameter;
		this.capability = capability;
		this.left = left;
		this.right = right;
	}
}

public class TypeParameterSymbol : Symbol {
	public GenericTransportMode transport_mode { get { return semantic_type.transport_mode; } }
	public GenericArray<GenericCapabilityRequirement> capability_requirements { get; private set; default = new GenericArray<GenericCapabilityRequirement> (); }
	public TypeParameterType semantic_type { get; private set; }
	public int ordinal { get; private set; }
	internal TypeParameterSymbol (SourceSpan span, int ordinal, GenericCapabilitySet? capabilities = null) {
		base (span, span);
		this.ordinal = ordinal;
		this.semantic_type = new TypeParameterType (name, capabilities);
	}
}

public class GenericFunctionSymbol : FunctionSymbol {
	public GenericResultOrigins result_origins { get; internal set; default = new GenericResultOrigins (); }
	public int heap_consumer_parameter { get; internal set; default = -1; }
	public GenericSliceObligations element_obligations { get; private set; default = new GenericSliceObligations (); }
	public GenericArray<GenericCapabilityRequirement> capability_requirements { get; private set; default = new GenericArray<GenericCapabilityRequirement> (); }
	public GenericArray<TypeParameterSymbol> type_parameters { get; private set; }
	internal GenericFunctionSymbol (SourceSpan span, SourceSpan name_span, SemanticType result, GenericArray<ParameterSymbol> parameters, GenericArray<TypeParameterSymbol> type_parameters, ResultOwnershipContract contract = ResultOwnershipContract.UNMANAGED, CForeignCleanupContract? cleanup = null, string? name = null) {
		base (span, name_span, result, parameters, contract, cleanup, CallableDomain.NATIVE, name);
		this.type_parameters = type_parameters;
	}
}

internal delegate FunctionSymbol? GenericOriginTarget(CallExpressionSyntax call, HashTable<string, SemanticType> locals, TypeSubstitution? substitution);
internal delegate GenericResultOrigins GenericOriginEquation(FunctionSymbol function, CallExpressionSyntax call, HashTable<string, SemanticType> locals);
internal delegate SemanticType? GenericOriginType(TypeNameSyntax syntax);

internal class SourceResultOriginRequest : Object {
	internal FunctionSymbol function;
	internal TypeArgumentVector arguments;
	internal TypeSubstitution substitution;
	internal GenericResultOrigins equation = new GenericResultOrigins ();
	internal bool solved;
	internal SourceResultOriginRequest (FunctionSymbol function, TypeArgumentVector arguments, TypeSubstitution substitution) {
		this.function = function;
		this.arguments = arguments;
		this.substitution = substitution;
	}
}

// Source derives a symbolic equation before any concrete caller is checked.
// Core reconstructs its own equation from Core nodes, without this visitor.
internal class GenericSourceResultOrigins : Object {
	private HashTable<string, GenericResultOrigins> values = new HashTable<string, GenericResultOrigins> (str_hash, str_equal);
	private HashTable<string, SemanticType> types = new HashTable<string, SemanticType> (str_hash, str_equal);
	private GenericOriginTarget target;
	private GenericOriginType type;
	private GenericOriginEquation? project;
	private TypeSubstitution? substitution;
	private HashTable<FunctionSymbol, GenericResultOrigins> equations;
	private GenericResultOrigins result = new GenericResultOrigins ();
	internal static int literal_condition(ExpressionSyntax? syntax) {
		while (syntax is ParenthesizedExpressionSyntax) {
			syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
		}
		var literal = syntax as BooleanLiteralExpressionSyntax;
		return literal == null ? -1 : literal.literal.spelling () == "true" ? 1 : 0;
	}

	internal GenericSourceResultOrigins (FunctionSymbol function, HashTable<FunctionSymbol, GenericResultOrigins> equations, owned GenericOriginTarget target, owned GenericOriginType type, TypeSubstitution? substitution = null, owned GenericOriginEquation? project = null) {
		this.substitution = substitution;
		this.project = (owned) project;
		this.equations = equations;
		this.target = (owned) target;
		this.type = (owned) type;
		if (function.implicit_receiver != null) {
			types.insert ("this", function.implicit_receiver.semantic_type.instance_type);
		}
		foreach (var parameter in function.parameters) {
			types.insert (parameter.name, substitution == null ? parameter.semantic_type : substitution.apply (parameter.semantic_type));
			if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				values.insert (parameter.name, new GenericResultOrigins (0, new int[] { parameter.ordinal }));
			}
		}
	}
	private GenericResultOrigins expression(ExpressionSyntax? syntax) {
		if (syntax == null || syntax is NullPointerExpressionSyntax) {
			return new GenericResultOrigins ();
		}
		if (syntax is ParenthesizedExpressionSyntax) {
			return expression (((ParenthesizedExpressionSyntax) syntax).expression);
		}
		if (syntax is MoveExpressionSyntax) {
			var moved = (MoveExpressionSyntax) syntax;
			if (moved.fields.length != 0) {
				return new GenericResultOrigins (GenericResultOrigins.HEAP);
			}
			return values.lookup (moved.source.spelling ()) ?? new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
		}
		if (syntax is HeapObjectConstructionSyntax) {
			return new GenericResultOrigins (GenericResultOrigins.HEAP);
		}
		var call = syntax as CallExpressionSyntax;
		if (call == null) {
			return new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
		}
		CallableSignature? signature = null;
		if (call.receiver == null && call.receiver_place == null) {
			if (call.identifier.spelling () == "closure_invoke" && call.arguments.length != 0) {
				var callee = call.arguments[0] as NameExpressionSyntax;
				if (callee != null) {
					signature = types.lookup (callee.identifier.spelling ()) as CallableSignature;
				}
			} else {
				signature = types.lookup (call.identifier.spelling ()) as CallableSignature;
			}
		}
		if (signature != null && signature.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
			return new GenericResultOrigins (GenericResultOrigins.HEAP);
		}
		var callee = target (call, types, substitution);
		if (callee is ConstructorSymbol) {
			return new GenericResultOrigins (GenericResultOrigins.CALLER);
		}
		var equation = callee == null ? null : equations.lookup (callee);
		if (project != null && callee != null && callee.result_contract == ResultOwnershipContract.OWNED_TRANSFER && (callee.return_type is TypeParameterType || callee.return_type is ClassType)) {
			equation = project (callee, call, types);
		}
		if (equation != null) {
			var arguments = new GenericArray<GenericResultOrigins> ();
			foreach (var argument in call.arguments) {
				arguments.add (expression (argument));
			}
			return equation.compose (arguments);
		}
		if (callee != null && callee.result_contract == ResultOwnershipContract.OWNED_TRANSFER && callee.return_type is ClassType) {
			return new GenericResultOrigins (callee.heap_result ? GenericResultOrigins.HEAP : GenericResultOrigins.CALLER);
		}
		return new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
	}
	private void statement(StatementSyntax syntax) {
		if (syntax is BlockStatementSyntax) {
			var declared_names = new GenericArray<string> ();
			var saved_values = new HashTable<string, GenericResultOrigins> (str_hash, str_equal);
			var saved_types = new HashTable<string, SemanticType> (str_hash, str_equal);
			foreach (var child in ((BlockStatementSyntax) syntax).statements) {
				string? name = null;
				if (child is LocalDeclarationSyntax) {
					name = ((LocalDeclarationSyntax) child).name.spelling ();
				} else if (child is InferredLocalDeclarationSyntax) {
					name = ((InferredLocalDeclarationSyntax) child).name.spelling ();
				}
				if (name != null && !declared_names.find (name)) {
					declared_names.add (name);
					if (values.contains (name)) {
						saved_values.insert (name, values.lookup (name));
					}
					if (types.contains (name)) {
						saved_types.insert (name, types.lookup (name));
					}
				}
				statement (child);
			}
			foreach (var name in declared_names) {
				if (saved_values.contains (name)) {
					values.insert (name, saved_values.lookup (name));
				} else {
					values.remove (name);
				}
				if (saved_types.contains (name)) {
					types.insert (name, saved_types.lookup (name));
				} else {
					types.remove (name);
				}
			}
		} else if (syntax is ReturnStatementSyntax) {
			result = result.union (expression (((ReturnStatementSyntax) syntax).expression));
		} else if (syntax is LocalDeclarationSyntax) {
			var local = (LocalDeclarationSyntax) syntax;
			var equation = expression (local.initializer);
			ExpressionSyntax initializer = local.initializer;
			while (initializer is ParenthesizedExpressionSyntax) {
				initializer = ((ParenthesizedExpressionSyntax) initializer).expression;
			}
			values.insert (local.name.spelling (), (initializer is CallExpressionSyntax) ? equation.captured () : equation);
			var declared = type (local.type_name);
			if (declared != null) {
				types.insert (local.name.spelling (), declared);
			}
		} else if (syntax is InferredLocalDeclarationSyntax) {
			var local = (InferredLocalDeclarationSyntax) syntax;
			var equation = expression (local.initializer);
			ExpressionSyntax initializer = local.initializer;
			while (initializer is ParenthesizedExpressionSyntax) {
				initializer = ((ParenthesizedExpressionSyntax) initializer).expression;
			}
			values.insert (local.name.spelling (), (initializer is CallExpressionSyntax) ? equation.captured () : equation);
			var reference = local.initializer as NameExpressionSyntax;
			if (reference != null && types.contains (reference.identifier.spelling ())) {
				types.insert (local.name.spelling (), types.lookup (reference.identifier.spelling ()));
			}
		} else if (syntax is AssignmentStatementSyntax) {
			var assignment = (AssignmentStatementSyntax) syntax;
			var previous = values.lookup (assignment.name.spelling ()) ?? new GenericResultOrigins ();
			values.insert (assignment.name.spelling (), previous.union (expression (assignment.expression)));
		} else if (syntax is IfStatementSyntax) {
			var branch = (IfStatementSyntax) syntax;
			int constant = literal_condition (branch.condition);
			if (constant != 0) {
				statement (branch.then_body);
			}
			if (constant != 1 && branch.else_body != null) {
				statement (branch.else_body);
			}
		} else if (syntax is WhileStatementSyntax) {
			var loop = (WhileStatementSyntax) syntax;
			if (literal_condition (loop.condition) != 0) {
				statement (loop.body);
			}
		} else if (syntax is ForeachStatementSyntax) {
			statement (((ForeachStatementSyntax) syntax).body);
		} else if (syntax is ForStatementSyntax) {
			var loop = (ForStatementSyntax) syntax;
			if (loop.initializer != null) {
				statement (loop.initializer);
			}
			if (literal_condition (loop.condition) != 0) {
				statement (loop.body);
				if (loop.step != null) {
					statement (loop.step);
				}
			}
		} else if (syntax is WithStatementSyntax) {
			var scoped = (WithStatementSyntax) syntax;
			if (scoped.initializer != null) {
				statement (scoped.initializer);
			}
			statement (scoped.body);
		} else if (syntax is TryStatementSyntax) {
			var guarded = (TryStatementSyntax) syntax;
			statement (guarded.body);
			foreach (var caught in guarded.catches) {
				statement (caught.body);
			}
		} else if (syntax is MatchStatementSyntax) {
			foreach (var arm in ((MatchStatementSyntax) syntax).arms) {
				statement (arm.body);
			}
		}
	}
	internal GenericResultOrigins derive(BlockStatementSyntax body) {
		statement (body);
		return result;
	}
}

public class CheckedGenericFunction : CheckedFunction {
	public GenericArray<GenericCapabilityRequirement> capability_requirements { get { return definition.capability_requirements; } }
	public GenericFunctionSymbol definition { get { return (GenericFunctionSymbol) symbol; } }
	internal CheckedGenericFunction (GenericFunctionSymbol symbol, GenericArray<LocalSymbol> locals, CheckedBlockStatement body) {
		base (symbol, locals, body);
	}
}

public class CheckedGenericCall : CheckedCallExpression {
	public GenericArray<GenericCapabilityRequirement> target_requirements { get; private set; }
	public GenericArray<SemanticType> type_arguments { get; private set; }
	internal CheckedGenericCall (SourceSpan span, GenericFunctionSymbol target, GenericArray<SemanticType> type_arguments, GenericArray<CheckedExpression> arguments, SemanticType result) {
		base (span, target, arguments, null, result);
		this.type_arguments = type_arguments;
		this.target_requirements = new GenericArray<GenericCapabilityRequirement> ();
		foreach (var requirement in target.capability_requirements) {
			this.target_requirements.add (requirement);
		}
	}
}

public class CheckedGenericCallStatement : CheckedCallStatement {
	public GenericArray<GenericCapabilityRequirement> target_requirements { get; private set; }
	public GenericArray<SemanticType> type_arguments { get; private set; }
	internal CheckedGenericCallStatement (SourceSpan span, GenericFunctionSymbol target, GenericArray<SemanticType> type_arguments, GenericArray<CheckedExpression> arguments) {
		base (span, target, arguments);
		this.type_arguments = type_arguments;
		this.target_requirements = new GenericArray<GenericCapabilityRequirement> ();
		foreach (var requirement in target.capability_requirements) {
			this.target_requirements.add (requirement);
		}
	}
}
}
