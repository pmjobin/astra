// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
namespace Astra.Semantic {
internal class GenericClassMethodRequest : Object {
	internal MethodSymbol header;
	internal GenericFunctionSymbol? caller;
	internal GenericClassMethodRequest (MethodSymbol header, GenericFunctionSymbol? caller) {
		this.header = header;
		this.caller = caller;
	}

}
// Source demand edges close declaration dependencies before the checked
// graph is detached. No executable source body crosses into Core.
internal class GenericClassFunctionRequest : Object {
	internal GenericFunctionSymbol target;
	internal GenericFunctionSymbol? caller;
	internal TypeArgumentVector arguments;
	internal GenericClassFunctionRequest (GenericFunctionSymbol target, GenericFunctionSymbol? caller, TypeArgumentVector arguments) {
		this.target = target;
		this.caller = caller;
		this.arguments = arguments;
	}

}

internal delegate string GenericNominalName(SourceSpan span, string name);
// A finite source template, not a native instance or an ownership domain.
internal class ExactClassTemplate : Object {
	internal ClassDeclarationSyntax syntax;
	internal ExactClassDefinitionIdentity identity;
	internal string parameter;
	internal string[] parameters;
	internal GenericArray<ClassSymbol> instances = new GenericArray<ClassSymbol> ();
	private GenericArray<ExactGenericClassType> open_applications = new GenericArray<ExactGenericClassType> ();
	internal ExactGenericClassType open_application(TypeArgumentVector arguments) {
		foreach (var prior in open_applications) {
			if (prior.arguments.matches (arguments)) {
				return prior;
			}
		}
		var result = new ExactGenericClassType.application (identity, arguments);
		open_applications.add (result);
		return result;
	}

	internal ExactClassTemplate (ClassDeclarationSyntax syntax, ExactClassDefinitionIdentity identity) {
		this.syntax = syntax;
		this.identity = identity;
		parameters = new string[syntax.type_parameters.length];
		for (int p = 0; p < parameters.length; p++) {
			parameters[p] = syntax.type_parameters[p].spelling ();
		}
		parameter = parameters[0];
	}

	internal ClassSymbol? find_arguments(TypeArgumentVector arguments) {
		foreach (var instance in instances) {
			if (instance.generic_instance.arguments.matches (arguments)) {
				return instance;
			}
		}
		return null;
	}

	internal static GenericTypePattern pattern(TypeNameSyntax type, string[] parameters, string[] method_parameters, GenericNominalName nominal) {
		var channel = type as CallableChannelTypeSyntax;
		if (channel != null) {
			return new GenericTypePattern.channel (pattern (channel.underlying, parameters, method_parameters, nominal), channel.keyword.kind == TokenKind.OWNED ? GenericValueMode.OWNED : GenericValueMode.BORROWED);
		}
		var nonnull = type as NonNullTypeSyntax;
		if (nonnull != null) {
			return new GenericTypePattern.shaped (GenericTypePatternKind.NONNULL, new GenericTypePattern[] { pattern (nonnull.underlying, parameters, method_parameters, nominal) });
		}
		var pointer = type as PointerTypeSyntax;
		if (pointer != null) {
			return new GenericTypePattern.shaped (GenericTypePatternKind.POINTER, new GenericTypePattern[] { pattern (pointer.pointee, parameters, method_parameters, nominal) });
		}
		var slots = type as OwnerSlotsTypeSyntax;
		if (slots != null) {
			return new GenericTypePattern.shaped (GenericTypePatternKind.OWNER_SLOTS, new GenericTypePattern[] { pattern (slots.element, parameters, method_parameters, nominal) });
		}
		var slice = type as SliceTypeSyntax;
		if (slice != null) {
			return new GenericTypePattern.shaped (GenericTypePatternKind.SLICE, new GenericTypePattern[] { pattern (slice.element_type, parameters, method_parameters, nominal) });
		}
		var application = type as GenericTypeApplicationSyntax;
		if (application != null) {
			var arguments = new GenericTypePattern[application.type_arguments.length];
			for (int a = 0; a < arguments.length; a++) {
				arguments[a] = pattern (application.type_arguments[a], parameters, method_parameters, nominal);
			}
			return new GenericTypePattern.shaped (GenericTypePatternKind.APPLICATION, arguments, nominal (type.span, type.lookup_name ()));
		}
		string name = type.lookup_name ();
		GenericTypePattern? result = null;
		for (int p = 0; p < parameters.length; p++) {
			if (name == parameters[p]) {
				result = new GenericTypePattern.bound (p);
			}
		}
		for (int p = 0; p < method_parameters.length; p++) {
			if (name == method_parameters[p]) {
				result = new GenericTypePattern.bound (p, true);
			}
		}
		if (result == null) {
			result = new GenericTypePattern.named (nominal (type.span, name));
		}
		foreach (var star in type.stars) {
			result = new GenericTypePattern.shaped (GenericTypePatternKind.POINTER, new GenericTypePattern[] { result });
		}
		return result;
	}

	private static GenericValueMode mode(ParameterSyntax parameter) {
		return parameter.owned_keyword != null ? GenericValueMode.OWNED : parameter.borrowed_keyword != null ? GenericValueMode.BORROWED : GenericValueMode.VALUE;
	}

	private static GenericTypeConstraint[]? constraints(GenericArray<WhereClauseSyntax> clauses,
		string[] parameters, string[] method_parameters, out Diagnostic? diagnostic) {
		diagnostic = null;
		GenericTypeConstraint[] result = {};
		foreach (var clause in clauses) {
			int ordinal = -1;
			bool method = false;
			for (int p = 0; p < parameters.length; p++) {
				if (parameters[p] == clause.type_parameter.spelling ()) {
					ordinal = p;
				}
			}
			for (int p = 0; p < method_parameters.length; p++) {
				if (method_parameters[p] == clause.type_parameter.spelling ()) {
					ordinal = p;
					method = true;
				}
			}
			if (ordinal < 0) {
				diagnostic = new Diagnostic (clause.type_parameter.span, "unknown type parameter in generic constraint");
				return null;
			}
			GenericCapabilityIdentity[] identities = null;
			bool exact_heap_class = false;
			foreach (var token in clause.capabilities) {
				if (token.spelling () == "ExactHeapClass") {
					if (exact_heap_class) {
						diagnostic = new Diagnostic (token.span, "duplicate ExactHeapClass bound");
						return null;
					}
					exact_heap_class = true;
					continue;
				}
				bool found = false;
				for (int c = (int) GenericCapabilityIdentity.EQ; c <= (int) GenericCapabilityIdentity.OWNABLE; c++) {
					var identity = (GenericCapabilityIdentity) c;
					if (identity.spelling () == token.spelling ()) {
						identities += identity;
						found = true;
					}
				}
				if (!found) {
					diagnostic = new Diagnostic (token.span, "unknown generic capability '" + token.spelling () + "'");
					return null;
				}
			}
			var constraint = new GenericTypeConstraint (ordinal, method, new GenericCapabilitySet (identities), exact_heap_class);
			if (!constraint.valid (parameters.length, method_parameters.length)) {
				diagnostic = new Diagnostic (clause.span, "generic constraint requires unique capabilities; ExactHeapClass and Ownable cannot combine with value capabilities");
				return null;
			}
			result += constraint;
		}
		return result;
	}

	private static ExactClassTemplate? check_declared(ClassDeclarationSyntax syntax, out Diagnostic? diagnostic, string? canonical_name, GenericNominalName nominal) {
		diagnostic = null;
		var parameters = new string[syntax.type_parameters.length];
		for (int p = 0; p < parameters.length; p++) {
			parameters[p] = syntax.type_parameters[p].spelling ();
			for (int prior = 0; prior < p; prior++) {
				if (parameters[prior] == parameters[p]) {
					diagnostic = new Diagnostic (syntax.type_parameters[p].span, "duplicate generic Class type parameter");
					return null;
				}
			}
		}
		var fields = new GenericFieldPattern[syntax.fields.length];
		for (int f = 0; f < fields.length; f++) {
			var field = syntax.fields[f];
			fields[f] = new GenericFieldPattern (field.name.spelling (), pattern (field.type_name, parameters, {}, nominal), field.owned_keyword != null, field.private_keyword != null, field.readonly_keyword != null);
		}
		GenericMemberPattern[] members = {};
		GenericPropertyPattern[] properties = {};
		foreach (var member in syntax.members) {
			var property = member as PropertyDeclarationSyntax;
			if (property != null) {
				var result = pattern (property.type_name, parameters, {}, nominal);
				var error = property.throws_class == null ? null : pattern (property.throws_class, parameters, {}, nominal);
				var getter = new GenericMemberPattern ("get", GenericMemberPatternKind.GETTER, 0, result,
					property.is_borrowed ? GenericValueMode.BORROWED : property.owned_keyword != null ? GenericValueMode.OWNED : GenericValueMode.VALUE,
					{}, null, error, false, (int) property.dispatch);
				GenericMemberPattern? setter = null;
				if (property.setter != null) {
					var parameter = property.setter.parameter;
					setter = new GenericMemberPattern ("set", GenericMemberPatternKind.SETTER, 0, new GenericTypePattern.named ("void"), GenericValueMode.VALUE,
						new GenericTypePattern[] { result }, new GenericValueMode[] { parameter == null ? GenericValueMode.VALUE : mode (parameter) }, error, false, (int) property.dispatch);
				}
				properties += new GenericPropertyPattern (property.name.spelling (), getter, setter, property.is_lazy);
				continue;
			}
			var function = member as FunctionDeclarationSyntax;
			if (function == null) {
				continue;
			}
			var local_parameters = new string[function.type_parameters.length];
			for (int p = 0; p < local_parameters.length; p++) {
				local_parameters[p] = function.type_parameters[p].spelling ();
				for (int prior = 0; prior < p; prior++) {
					if (local_parameters[prior] == local_parameters[p]) {
						diagnostic = new Diagnostic (function.type_parameters[p].span, "duplicate generic method type parameter");
						return null;
					}
				}
			}
			var arguments = new GenericTypePattern[function.parameters.length];
			var modes = new GenericValueMode[arguments.length];
			for (int p = 0; p < arguments.length; p++) {
				arguments[p] = pattern (function.parameters[p].type_name, parameters, local_parameters, nominal);
				modes[p] = mode (function.parameters[p]);
			}
			var lifecycle = function as LifecycleDeclarationSyntax;
			var kind = lifecycle == null ? GenericMemberPatternKind.METHOD : lifecycle.is_constructor ? GenericMemberPatternKind.CONSTRUCTOR : GenericMemberPatternKind.DESTRUCTOR;
			var result = function.return_type == null ? new GenericTypePattern.named ("void") : pattern (function.return_type, parameters, local_parameters, nominal);
			var error = function.throws_class == null ? null : pattern (function.throws_class, parameters, local_parameters, nominal);
			var member_constraints = constraints (function.where_clauses, parameters, local_parameters, out diagnostic);
			if (member_constraints == null) {
				return null;
			}
			members += new GenericMemberPattern (function.name.spelling (), kind, local_parameters.length, result,
				function.owned_keyword == null ? GenericValueMode.VALUE : GenericValueMode.OWNED, arguments, modes, error, function.is_async, (int) function.dispatch, member_constraints);
		}
		var class_constraints = constraints (syntax.where_clauses, parameters, {}, out diagnostic);
		if (class_constraints == null) {
			return null;
		}
		var structure = new GenericClassStructure (parameters.length, fields, members, properties, class_constraints);
		if (!structure.valid ()) {
			diagnostic = new Diagnostic (syntax.span, "generic Class requires unique declared fields/members and well-scoped type expressions");
			return null;
		}
		return new ExactClassTemplate (syntax, new ExactClassDefinitionIdentity.declared (canonical_name ?? syntax.name.spelling (), structure));
	}

	internal static ExactClassTemplate? check(ClassDeclarationSyntax syntax, out Diagnostic? diagnostic, string? canonical_name = null, GenericNominalName? nominal = null) {
		if (nominal != null) {
			return check_declared (syntax, out diagnostic, canonical_name, nominal);
		}
		GenericNominalName identity = (span, name) => name;
		return check_declared (syntax, out diagnostic, canonical_name, identity);
	}

}
}
