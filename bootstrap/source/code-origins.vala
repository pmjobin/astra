// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Code {
// Canonical ordinals of direct Fn inputs, independent of record/buffer
// expansion in a later representation. Empty means no required input.
public class CodeInputSet : Object {
	public static bool valid(string text, int count) {
		if (text == "") {
			return true;
		}
		int previous = -1;
		foreach (string word in text.split (",")) {
			int value;
			if (!int.try_parse (word, out value) || value <= previous || value >= count || value.to_string () != word) {
				return false;
			}
			previous = value;
		}
		return true;
	}

	public static bool contains(string text, int ordinal) {
		foreach (string word in text.split (",")) {
			if (word == ordinal.to_string ()) {
				return true;
			}
		}
		return false;
	}

	public static string encode(CodeEffectSummary summary, GenericArray<int> positions) {
		var result = new StringBuilder ();
		for (int p = 0; p < positions.length; p++) {
			if (!summary.requires_input (positions[p])) {
				continue;
			}
			if (result.len != 0) {
				result.append_c (',');
			}
			result.append (p.to_string ());
		}
		return result.str;
	}

	public static CodeEffectSummary decode(bool eligible, string text, int parameter_count, GenericArray<int> positions) {
		var result = new CodeEffectSummary (parameter_count);
		result.eligible = eligible;
		if (!valid (text, (int) positions.length)) {
			result.eligible = false;
			return result;
		}
		for (int p = 0; p < positions.length; p++) {
			if (contains (text, p)) {
				result.require_input (positions[p]);
			}
		}
		return result;
	}

}

public class CodeEffectSummary : Object {
	public bool eligible { get; internal set; default = true; }
	private bool[] inputs;
	public CodeEffectSummary (int count) {
		inputs = new bool[count];
	}

	public bool requires_input(int ordinal) {
		return ordinal >= 0 && ordinal < inputs.length && inputs[ordinal];
	}

	internal void require_input(int ordinal) {
		assert (ordinal >= 0 && ordinal < inputs.length);
		inputs[ordinal] = true;
	}

	private bool same(CodeEffectSummary other) {
		if (eligible != other.eligible || inputs.length != other.inputs.length) {
			return false;
		}
		for (int p = 0; p < inputs.length; p++) {
			if (inputs[p] != other.inputs[p]) {
				return false;
			}
		}
		return true;
	}

	internal bool matches(CodeEffectSummary other) {
		return same (other);
	}

}

public delegate CodeOriginFrontier? CodeEffectFrontier(Object value, GenericArray<Object> formals);
public delegate bool CodeEffectProbe(Object function, CodeEffectSummary result);

private class CodeEffectFunction : Object {
	internal Object identity;
	internal GenericArray<Object> parameters;
	internal GenericArray<Object> formals;
	internal CodeEffectSummary? imported_readonly;
	internal CodeEffectSummary? imported_requirements;
	internal CodeEffectFunction (Object identity, GenericArray<Object> parameters, GenericArray<Object> formals,
	                             CodeEffectSummary? imported_readonly, CodeEffectSummary? imported_requirements) {
		this.identity = identity;
		this.parameters = parameters;
		this.formals = formals;
		this.imported_readonly = imported_readonly;
		this.imported_requirements = imported_requirements;
	}

}

private class CodeEffectCall : Object {
	internal Object scope;
	internal Object target;
	internal GenericArray<Object> arguments;
	internal bool protected_call;
	internal CodeEffectCall (Object scope, Object target, GenericArray<Object> arguments, bool protected_call) {
		this.scope = scope;
		this.target = target;
		this.arguments = arguments;
		this.protected_call = protected_call;
	}

}

// Each IR independently supplies its own identities, effects and value flow.
// Only the fixed-point rules are shared; this graph never crosses a phase.
public class CodeEffectAnalysis : Object {
	private GenericArray<CodeEffectFunction> functions = new GenericArray<CodeEffectFunction> ();
	private HashTable<Object, CodeEffectFunction> definitions = new HashTable<Object, CodeEffectFunction> (direct_hash, direct_equal);
	private HashTable<Object, CodeEffectSummary> readonly_facts = new HashTable<Object, CodeEffectSummary> (direct_hash, direct_equal);
	private HashTable<Object, CodeEffectSummary> required_facts = new HashTable<Object, CodeEffectSummary> (direct_hash, direct_equal);
	private HashTable<Object, GenericArray<CodeEffectCall>> calls = new HashTable<Object, GenericArray<CodeEffectCall>> (direct_hash, direct_equal);
	private CodeEffectFrontier frontier;
	public CodeEffectAnalysis (owned CodeEffectFrontier frontier) {
		this.frontier = (owned) frontier;
	}

	public void add_function(Object identity, GenericArray<Object> parameters, GenericArray<Object> formals,
		CodeEffectSummary? imported_readonly = null, CodeEffectSummary? imported_requirements = null) {
		assert (!definitions.contains (identity));
		var definition = new CodeEffectFunction (identity, parameters, formals, imported_readonly, imported_requirements);
		functions.add (definition);
		definitions.insert (identity, definition);
		readonly_facts.insert (identity, imported_readonly ?? new CodeEffectSummary ((int) parameters.length));
		required_facts.insert (identity, imported_requirements ?? new CodeEffectSummary ((int) parameters.length));
	}

	public void add_call(Object scope, Object target, GenericArray<Object> arguments, bool protected_call = false) {
		var sites = calls.lookup (scope);
		if (sites == null) {
			sites = new GenericArray<CodeEffectCall> ();
			calls.insert (scope, sites);
		}
		sites.add (new CodeEffectCall (scope, target, arguments, protected_call));
	}

	public CodeEffectSummary? readonly_summary(Object function) {
		return readonly_facts.lookup (function);
	}

	public CodeEffectSummary? required_summary(Object function) {
		return required_facts.lookup (function);
	}

	public bool code(Object value, Object scope, CodeEffectSummary result, GenericArray<Object>? arguments = null) {
		var owner = definitions.lookup (scope);
		if (owner == null) {
			return false;
		}
		var origin = frontier (value, owner.formals);
		if (origin == null) {
			return false;
		}
		foreach (var formal in origin.parameters) {
			int position = -1;
			for (int p = 0; p < owner.parameters.length; p++) {
				if (owner.parameters[p] == formal) {
					position = p;
				}
			}
			if (position < 0) {
				return false;
			}
			result.require_input (position);
		}
		foreach (var address in origin.targets) {
			var target = definitions.lookup (address);
			var known = readonly_facts.lookup (address);
			if (target == null || known == null || !known.eligible) {
				return false;
			}
			if (arguments != null) {
				if (!call (address, arguments, scope, result)) {
					return false;
				}
			} else {
				for (int p = 0; p < target.parameters.length; p++) {
					if (known.requires_input (p)) {
						return false;
					}
				}
			}
		}
		return true;
	}

	public bool call(Object target, GenericArray<Object> arguments, Object scope, CodeEffectSummary result) {
		var definition = definitions.lookup (target);
		var known = readonly_facts.lookup (target);
		if (definition == null || known == null || !known.eligible || definition.parameters.length != arguments.length) {
			return false;
		}
		for (int p = 0; p < arguments.length; p++) {
			if (known.requires_input (p) && !code (arguments[p], scope, result)) {
				return false;
			}
		}
		return true;
	}

	public void infer_readonly(CodeEffectProbe probe) {
		bool changed = false;
		do {
			changed = false;
			foreach (var function in functions) {
				if (function.imported_readonly != null) {
					continue;
				}
				var result = new CodeEffectSummary ((int) function.parameters.length);
				result.eligible = probe (function.identity, result);
				if (!result.matches (readonly_facts.lookup (function.identity))) {
					readonly_facts.insert (function.identity, result);
					changed = true;
				}
			}
		} while (changed);
	}

	public void infer_requirements() {
		bool changed = false;
		do {
			changed = false;
			foreach (var function in functions) {
				if (function.imported_requirements != null) {
					continue;
				}
				var result = new CodeEffectSummary ((int) function.parameters.length);
				var sites = calls.lookup (function.identity);
				if (sites != null) {
					foreach (var site in sites) {
						if (site.scope != function.identity) {
							continue;
						}
						var target = definitions.lookup (site.target);
						var known = required_facts.lookup (site.target);
						if (target == null || known == null || !known.eligible || site.arguments.length != target.parameters.length) {
							result.eligible = false;
							continue;
						}
						for (int p = 0; p < site.arguments.length; p++) {
							if (known.requires_input (p) && !code (site.arguments[p], function.identity, result)) {
								result.eligible = false;
							}
						}
						if (site.protected_call && !call (site.target, site.arguments, function.identity, result)) {
							result.eligible = false;
						}
					}
				}
				if (!result.matches (required_facts.lookup (function.identity))) {
					required_facts.insert (function.identity, result);
					changed = true;
				}
			}
		} while (changed);
	}

}

public class CodeOriginFrontier : Object {
	public GenericArray<Object> targets { get; private set; default = new GenericArray<Object> (); }
	public GenericArray<Object> parameters { get; private set; default = new GenericArray<Object> (); }
}

private class CodeOriginNode : Object {
	internal Object? address;
	internal bool unknown;
	internal bool parameter;
	internal GenericArray<Object> inputs = new GenericArray<Object> ();
}

// A temporary analysis graph. Each IR populates it with its own identities;
// no source symbol or earlier representation is carried between stages.
public class CodeOrigins : Object {
	private HashTable<Object, CodeOriginNode> nodes = new HashTable<Object, CodeOriginNode> (direct_hash, direct_equal);
	private HashTable<Object, bool> storage_nodes = new HashTable<Object, bool> (direct_hash, direct_equal);
	private bool opaque_storage;
	public uint revision { get; private set; }
	private CodeOriginNode node(Object value) {
		var found = nodes.lookup (value);
		if (found == null) {
			found = new CodeOriginNode ();
			nodes.insert (value, found);
			revision++;
		}
		return found;
	}

	public void address(Object value, Object target) {
		var origin = node (value);
		if (origin.address != target) {
			origin.address = target;
			revision++;
		}
	}

	public void unknown(Object value) {
		var origin = node (value);
		if (!origin.unknown) {
			origin.unknown = true;
			revision++;
		}
	}

	public void copy(Object value, Object input) {
		var destination = node (value);
		if (!destination.inputs.find (input)) {
			destination.inputs.add (input);
			revision++;
		}
	}

	// A definition with no callers contributes no actual code value. Opaque
	// entry points are separately marked unknown by the containing IR.
	public void parameter(Object value) {
		node (value).parameter = true;
	}

	public void storage(Object value) {
		storage_nodes.insert (value, true);
		if (opaque_storage) {
			unknown (value);
		}
	}

	public void escape_storage() {
		opaque_storage = true;
		foreach (var value in storage_nodes.get_keys ()) {
			unknown (value);
		}
	}

	private GenericArray<Object>? collect(Object value, bool require_complete) {
		var result = new GenericArray<Object> ();
		var pending = new GenericArray<Object> ();
		var seen = new HashTable<Object, bool> (direct_hash, direct_equal);
		pending.add (value);
		for (int i = 0; i < pending.length; i++) {
			var current = pending[i];
			if (seen.contains (current)) {
				continue;
			}
			seen.insert (current, true);
			var origin = nodes.lookup (current);
			if (origin == null) {
				if (require_complete) {
					return null;
				}
				continue;
			}
			if (require_complete && (origin.unknown || origin.address == null && origin.inputs.length == 0 && !origin.parameter)) {
				return null;
			}
			if (origin.address != null && !result.find (origin.address)) {
				result.add (origin.address);
			}
			foreach (var input in origin.inputs) {
				pending.add (input);
			}
		}
		// A cycle without a grounded address does not prove a code target.
		return result.length == 0 ? null : result;
	}

	public GenericArray<Object>? targets(Object value) {
		return collect (value, true);
	}

	// Incomplete candidates only build conservative flow equations. They are
	// never authority for accepting a call or proving effects.
	public GenericArray<Object>? candidates(Object value) {
		return collect (value, false);
	}

	public GenericArray<Object> addressed_targets() {
		var result = new GenericArray<Object> ();
		foreach (var origin in nodes.get_values ()) {
			if (origin.address != null && !result.find (origin.address)) {
				result.add (origin.address);
			}
		}
		return result;
	}

	// Derive a declaration's obligations without specializing it to its
	// currently observed callers. Only explicitly nominated formal inputs
	// terminate a path; opaque storage and ungrounded cycles still fail.
	public CodeOriginFrontier? frontier(Object value, GenericArray<Object> parameters) {
		var result = new CodeOriginFrontier ();
		var pending = new GenericArray<Object> ();
		var seen = new HashTable<Object, bool> (direct_hash, direct_equal);
		pending.add (value);
		for (int i = 0; i < pending.length; i++) {
			var current = pending[i];
			if (seen.contains (current)) {
				continue;
			}
			seen.insert (current, true);
			var origin = nodes.lookup (current);
			if (origin == null || origin.unknown) {
				return null;
			}
			if (storage_nodes.contains (current)) {
				return null;
			}
			if (parameters.find (current)) {
				if (!origin.parameter) {
					return null;
				}
				result.parameters.add (current);
				continue;
			}
			if (origin.parameter) {
				return null;
			}
			if (origin.address != null && !result.targets.find (origin.address)) {
				result.targets.add (origin.address);
			}
			if (origin.address == null && origin.inputs.length == 0) {
				return null;
			}
			foreach (var input in origin.inputs) {
				pending.add (input);
			}
		}
		return result.targets.length == 0 && result.parameters.length == 0 ? null : result;
	}

}
}
