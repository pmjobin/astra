// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
// Forward field/numeric context can inspect an inferred call's checked
// result. Replay its effects only when ordinary checking reaches
// that call; the destination never supplies generic argument information.
internal class GenericCallContext : Object {
	internal CheckedNode result;
	internal SemanticType semantic_type {
		get {
			if (result is CheckedStructProducer) {
				return ((CheckedStructProducer) result).semantic_type;
			}
			if (result is CheckedEnumProducer) {
				return ((CheckedEnumProducer) result).semantic_type;
			}
			return ((CheckedExpression) result).semantic_type;
		}
	}
	internal SemanticOwnershipFlow? flow;
	internal GenericCallContext (CheckedNode result, SemanticOwnershipFlow? flow) {
		assert (result is CheckedExpression || result is CheckedStructProducer || result is CheckedEnumProducer);
		this.result = result;
		this.flow = flow;
	}

}

// Argument/call transactions exist only in semantic checking. The inherited
// structured ownership authority is also used independently by Core.
internal class SemanticOwnershipFlow : GenericOwnershipFlow {
	internal SemanticOwnershipFlow (SourceSpan span, string context = "generic definition checking") {
		base (span, context);
	}

	// Compose a completed temporary proof without sharing mutable event IDs.
	// Discarding a fragment has no effect on the receiving flow or its owners.
	internal void append(SemanticOwnershipFlow fragment) {
		assert (fragment != this && fragment.parents.length == 0);
		int[] mapping = new int[fragment.owners.size ()];
		var iterator = HashTableIter<Object, int> (fragment.owners);
		Object owner;
		int ordinal;
		while (iterator.next (out owner, out ordinal)) {
			if (!owners.contains (owner)) {
				owners.insert (owner, (int) owners.size ());
			}
			mapping[ordinal] = owners.lookup (owner);
		}
		current.children.add (copy_event (fragment.root, mapping));
	}

	private static GenericOwnershipEvent copy_event(GenericOwnershipEvent source, int[] mapping) {
		var event = new GenericOwnershipEvent (source.kind, source.span);
		event.owner = source.owner == -1 ? -1 : mapping[source.owner];
		event.name = source.name;
		event.truth = source.truth;
		event.target = source.target;
		event.parameter = source.parameter;
		event.returned = source.returned;
		event.effect = source.effect;
		foreach (var bound in source.bounds) {
			event.bounds.add (bound);
		}
		foreach (var child in source.children) {
			event.children.add (copy_event (child, mapping));
		}
		return event;
	}

}

// Temporary checking evidence, never attached to a Checked call or type.
internal class GenericInferenceObservation : Object {
	internal TypeParameterSymbol parameter;
	internal SemanticType candidate;
	internal int argument_index;
	internal SourceSpan span;
	internal GenericInferenceObservation (TypeParameterSymbol parameter, SemanticType candidate, int argument_index, SourceSpan span) {
		this.parameter = parameter;
		this.candidate = candidate;
		this.argument_index = argument_index;
		this.span = span;
	}

}

internal class GenericCallInference : Object {
	private GenericFunctionSymbol definition;
	private HashTable<TypeParameterSymbol, GenericInferenceObservation> first = new HashTable<TypeParameterSymbol, GenericInferenceObservation> (direct_hash, direct_equal);
	internal GenericArray<GenericInferenceObservation> observations = new GenericArray<GenericInferenceObservation> ();
	internal Diagnostic? diagnostic { get; private set; }
	internal GenericCallInference (GenericFunctionSymbol definition) {
		this.definition = definition;
	}

	internal TypeParameterSymbol? parameter_for(SemanticType type) {
		foreach (var parameter in definition.type_parameters) {
			if (parameter.semantic_type == type) {
				return parameter;
			}
		}
		return null;
	}

	internal bool observe_type(SemanticType pattern, SemanticType candidate, int index, SourceSpan span, int depth = 0) {
		if (depth > 256) {
			diagnostic = new Diagnostic (span, "generic argument inference exceeds the type-application depth limit of 256");
			return false;
		}
		var parameter = parameter_for (pattern);
		if (parameter != null) {
			return observe (parameter, candidate, index, span);
		}
		if (pattern is CallableSignature && candidate is CallableSignature && pattern.get_type () == candidate.get_type ()) {
			var expected_code = (CallableSignature) pattern;
			var actual_code = (CallableSignature) candidate;
			bool exact_channels = expected_code.result_contract == actual_code.result_contract && expected_code.parameter_types.length == actual_code.parameter_types.length;
			for (int p = 0; exact_channels && p < expected_code.parameter_types.length; p++) {
				exact_channels &= expected_code.parameter_contract (p) == actual_code.parameter_contract (p);
			}
			var expected_closure = pattern as ClosureHandleType;
			var actual_closure = candidate as ClosureHandleType;
			if (expected_closure != null) {
				exact_channels &= expected_closure.throws_type == actual_closure.throws_type && expected_closure.threaded == actual_closure.threaded && expected_closure.actor == actual_closure.actor;
			}
			if (exact_channels) {
				if (expected_closure != null && !observe_type (expected_closure.environment_type, actual_closure.environment_type, index, span, depth + 1)) {
					return false;
				}
				if (!observe_type (CallableTypes.result_type (pattern), CallableTypes.result_type (candidate), index, span, depth + 1)) {
					return false;
				}
				for (int p = 0; p < expected_code.parameter_types.length; p++) {
					if (!observe_type (expected_code.parameter_types[p], actual_code.parameter_types[p], index, span, depth + 1)) {
						return false;
					}
				}
				return true;
			}
		}
		if (pattern is ExactGenericClassType && candidate is ExactGenericClassType) {
			var expected_class = (ExactGenericClassType) pattern;
			var actual_class = (ExactGenericClassType) candidate;
			if (expected_class.definition == actual_class.definition && expected_class.arguments.length == actual_class.arguments.length) {
				for (int p = 0; p < expected_class.arguments.length; p++) {
					if (!observe_type (expected_class.arguments.at (p), actual_class.arguments.at (p), index, span, depth + 1)) {
						return false;
					}
				}
				return true;
			}
		}
		var expected = pattern as GenericStructApplicationType;
		var actual = candidate as GenericStructApplicationType;
		if (expected != null && actual != null && expected.definition == actual.definition && expected.type_arguments.length == actual.type_arguments.length) {
			for (int i = 0; i < expected.type_arguments.length; i++) {
				if (!observe_type (expected.type_arguments[i], actual.type_arguments[i], index, span, depth + 1)) {
					return false;
				}
			}
			return true;
		}
		if (pattern == candidate) {
			return true;
		}
		diagnostic = new Diagnostic (span, "generic argument requires exact nominal type pattern '%s', found '%s'".printf (pattern.display_name (), candidate.display_name ()));
		return false;
	}

	internal bool observe(TypeParameterSymbol parameter, SemanticType candidate, int index, SourceSpan span) {
		assert (parameter_for (parameter.semantic_type) == parameter);
		// Expression checking and symbol resolution already use the program's
		// canonical BuiltinTypes/nominal/lexical identities. Never re-intern a
		// nominal or outer parameter by its spelling or representation.
		var observation = new GenericInferenceObservation (parameter, candidate, index, span);
		observations.add (observation);
		var previous = first.lookup (parameter);
		if (previous == null) {
			first.insert (parameter, observation);
			return true;
		}
		if (previous.candidate == candidate) {
			return true;
		}
		int line;
		int column;
		previous.span.file.locate (previous.span.start, out line, out column);
		diagnostic = new Diagnostic (span, "conflicting inferred types for generic parameter '%s': '%s' and '%s' (arguments %d and %d; first at %s:%d:%d)".printf (parameter.name, previous.candidate.display_name (), candidate.display_name (), previous.argument_index + 1, index + 1, previous.span.file.path, line, column));
		return false;
	}

	internal SourceSpan argument_span(TypeParameterSymbol parameter) {
		return first.lookup (parameter).span;
	}

	internal GenericArray<SemanticType>? complete(SourceSpan span) {
		var arguments = new GenericArray<SemanticType> ();
		foreach (var parameter in definition.type_parameters) {
			var observation = first.lookup (parameter);
			if (observation == null) {
				diagnostic = new Diagnostic (span, "cannot infer generic type argument '%s' for '%s'; write an explicit type argument".printf (parameter.name, definition.name));
				return null;
			}
			arguments.add (observation.candidate);
		}
		return arguments;
	}

}
}
