// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Source {
public errordomain RuntimeLifetimeError {
	INVALID_GRAPH, UNGROUNDED, LOCAL_ESCAPE
}

public enum RuntimeScopeOriginKind {
	LOCAL_CONTEXT, CONTEXT_PARAMETER, OWNER_PARAMETER
}

// Primitive references only. A graph parameter is a complete owning value,
// whereas a context parameter supplies one allocator lifetime anchor.
public class RuntimeScopeOrigin : Object {
	public RuntimeScopeOriginKind kind { get; private set; }
	public int ordinal { get; private set; }
	public int region { get; private set; default = -1; }
	private string owner_path = "";
	public string path { get { return owner_path; } }
	public bool descendants { get; private set; }
	private GenericArray<string> excluded = new GenericArray<string> ();
	public uint exclusion_count { get { return excluded.length; } }
	public string exclusion(uint index) {
		return excluded[index];
	}

	public RuntimeScopeOrigin.local (int context, int region) {
		kind = RuntimeScopeOriginKind.LOCAL_CONTEXT;
		ordinal = context;
		this.region = region;
	}
	public RuntimeScopeOrigin.context_input (int parameter) {
		kind = RuntimeScopeOriginKind.CONTEXT_PARAMETER;
		ordinal = parameter;
	}
	internal RuntimeScopeOrigin.owner_input (int parameter, string path, bool descendants, GenericArray<string> excluded) {
		kind = RuntimeScopeOriginKind.OWNER_PARAMETER;
		ordinal = parameter;
		this.owner_path = path;
		this.descendants = descendants;
		foreach (var key in excluded) {
			this.excluded.add (key);
		}
		RuntimeLifetimeEquations.sort_edges (this.excluded);
	}
	public bool valid() {
		if (kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
			return ordinal >= 0 && region >= 0 && path == "" && !descendants && excluded.length == 0;
		}
		if (kind == RuntimeScopeOriginKind.CONTEXT_PARAMETER) {
			return ordinal >= 0 && region == -1 && path == "" && !descendants && excluded.length == 0;
		}
		if (kind != RuntimeScopeOriginKind.OWNER_PARAMETER || ordinal < -1 || region != -1 || !RuntimeLifetimeEquations.valid_path (path) || !descendants && excluded.length != 0) {
			return false;
		}
		string prior = "";
		foreach (var key in excluded) {
			if (!RuntimeLifetimeEquations.valid_edge (key) || prior != "" && strcmp (prior, key) >= 0) {
				return false;
			}
			prior = key;
		}
		return true;
	}

	public string identity() {
		var text = new StringBuilder ("runtime-lifetime/1:%d;%d;%d;%s;%d".printf ((int) kind, ordinal, region, path, descendants ? 1 : 0));
		foreach (var key in excluded) {
			text.append (";except=" + key);
		}
		return text.str;
	}

}

private enum RuntimeLifetimeNodeKind {
	ABSENT, PRODUCT, INPUT, JOIN, PROJECT, REPLACE
}

private class RuntimeLifetimeNode : Object {
	internal RuntimeLifetimeNodeKind kind;
	internal int parameter = -1;
	internal int source = -1;
	internal int replacement = -1;
	internal string path = "";
	internal GenericArray<RuntimeScopeOrigin> roots = new GenericArray<RuntimeScopeOrigin> ();
	internal GenericArray<int> root_sources = new GenericArray<int> ();
	internal HashTable<string, int> fields = new HashTable<string, int> (str_hash, str_equal);
	internal GenericArray<int> alternatives = new GenericArray<int> ();
	internal RuntimeLifetimeNode (RuntimeLifetimeNodeKind kind) {
		this.kind = kind;
	}

}
private class RuntimeLifetimeQuery : Object {
	internal int node;
	internal int ordinal;
	internal string path;
	internal bool descendants;
	internal GenericArray<string> excluded = new GenericArray<string> ();
	internal GenericArray<int> parents = new GenericArray<int> ();
	internal bool grounded;
	internal bool cached_empty;
	internal RuntimeLifetimeQuery (int node, string path, bool descendants, GenericArray<string>? exclusions) {
		this.node = node;
		this.path = path;
		this.descendants = descendants;
		if (exclusions != null) {
			foreach (var key in exclusions) {
				if (!RuntimeLifetimeEquations.has_edge (excluded, key)) {
					excluded.add (key);
				}
			}
		}
		RuntimeLifetimeEquations.sort_edges (excluded);
	}

	internal string identity() {
		var text = new StringBuilder ("%d:%s:%d".printf (node, path, descendants ? 1 : 0));
		foreach (var key in excluded) {
			text.append (":" + key);
		}
		return text.str;
	}

}

// Finite equations preserve allocation roots separately from owned fields,
// container elements, closure payloads and task captures. Backedges refer to
// integer nodes, so recursive ownership shapes never form GObject cycles.
// Stage adapters must supply the actual complete typed ownership operations.
public class RuntimeLifetimeEquations : Object {
	private GenericArray<RuntimeLifetimeNode> nodes = new GenericArray<RuntimeLifetimeNode> ();
	private bool sealed;
	// Sealed equations never change. Cache only fully validated empty queries,
	// including their exact path, descendant flag and exclusions. No mutable
	// result array or failed/partially grounded query enters this cache.
	private HashTable<string, bool> empty_queries = new HashTable<string, bool> (str_hash, str_equal);
	private int projection_depth;
	public bool is_sealed { get { return sealed; } }
	public bool has_scope_roots {
		get {
			foreach (var node in nodes) {
				if (node.roots.length != 0) {
					return true;
				}
			}
			return false;
		}
	}
	public uint count { get { return nodes.length; } }
	internal bool contains(int value) {
		return value >= 0 && value < nodes.length;
	}

	public RuntimeLifetimeEquations () {
		nodes.add (new RuntimeLifetimeNode (RuntimeLifetimeNodeKind.ABSENT));
	}

	internal static bool has_edge(GenericArray<string> edges, string key) {
		foreach (var edge in edges) {
			if (edge == key) {
				return true;
			}
		}
		return false;
	}

	internal static void sort_edges(GenericArray<string> edges) {
		// Iterative merge sort keeps comparison work O(n log n), including on
		// GLib versions predating sort_values. Avoid Vala's sort adapter, whose
		// generated closure fails the strict C warning profile in Vala 0.56.
		var work = new GenericArray<string> (edges.length);
		foreach (var edge in edges) {
			work.add (edge);
		}
		for (int width = 1; width < edges.length; width *= 2) {
			for (int start = 0; start < edges.length; start += 2 * width) {
				int middle = int.min (start + width, (int) edges.length);
				int end = int.min (start + 2 * width, (int) edges.length);
				int left = start;
				int right = middle;
				for (int output = start; output < end; output++) {
					if (left < middle && (right == end || strcmp (edges[left], edges[right]) <= 0)) {
						work[output] = edges[left++];
					} else {
						work[output] = edges[right++];
					}
				}
			}
			for (int i = 0; i < edges.length; i++) {
				edges[i] = work[i];
			}
			if (width > edges.length / 2) {
				break;
			}
		}
	}

	public static bool valid_edge(string key) {
		if (key == "e" || key == "c" || key == "r" || key == "x" || key == "p" || key == "w") {
			return true;
		}
		if (key.length < 2 || key[0] != 'f' && key[0] != 't' || key.length > 2 && key[1] == '0') {
			return false;
		}
		uint64 value = 0;
		for (int i = 1; i < key.length; i++) {
			if (key[i] < '0' || key[i] > '9') {
				return false;
			}
			value = value * 10 + (key[i] - '0');
			if (value > int.MAX) {
				return false;
			}
		}
		return true;
	}

	public static bool valid_path(string path) {
		if (path == "") {
			return true;
		}
		foreach (var key in path.split (".")) {
			if (!valid_edge (key)) {
				return false;
			}
		}
		return true;
	}

	private static void require(bool condition, string message) throws RuntimeLifetimeError {
		if (!condition) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("runtime lifetime graph: %s", message);
		}
	}

	private void open() throws RuntimeLifetimeError {
		require (!sealed, "sealed equations cannot change");
	}

	private void member(int node) throws RuntimeLifetimeError {
		require (node >= 0 && node < nodes.length, "operand belongs to another equation inventory");
	}

	private int append(RuntimeLifetimeNode node) throws RuntimeLifetimeError {
		open ();
		nodes.add (node);
		return (int) nodes.length - 1;
	}

	public void seal() {
		sealed = true;
	}

	public int absent() {
		return 0;
	}

	public int product(GenericArray<RuntimeScopeOrigin> roots, HashTable<string, int> fields, GenericArray<int>? root_sources = null) throws RuntimeLifetimeError {
		var node = new RuntimeLifetimeNode (RuntimeLifetimeNodeKind.PRODUCT);
		foreach (var origin in roots) {
			require (origin.valid () && origin.kind != RuntimeScopeOriginKind.OWNER_PARAMETER, "allocation root requires an exact local or context-input anchor");
			node.roots.add (origin);
		}
		if (root_sources != null) {
			for (int i = 0; i < root_sources.length; i++) {
				member (root_sources[i]);
				node.root_sources.add (root_sources[i]);
			}
		}
		foreach (var key in fields.get_keys ()) {
			require (valid_edge (key), "invalid ownership edge");
			member (fields.lookup (key));
			node.fields.insert (key, fields.lookup (key));
		}
		return append (node);
	}

	public int input(int parameter) throws RuntimeLifetimeError {
		require (parameter >= -1, "invalid owning input ordinal");
		var node = new RuntimeLifetimeNode (RuntimeLifetimeNodeKind.INPUT);
		node.parameter = parameter;
		return append (node);
	}

	public int join() throws RuntimeLifetimeError {
		return append (new RuntimeLifetimeNode (RuntimeLifetimeNodeKind.JOIN));
	}

	public void alternative(int join, int value) throws RuntimeLifetimeError {
		open ();
		member (join);
		member (value);
		require (nodes[join].kind == RuntimeLifetimeNodeKind.JOIN, "backedge requires its exact join node");
		if (!nodes[join].alternatives.find (value)) {
			nodes[join].alternatives.add (value);
		}
	}

	public int project(int value, string path) throws RuntimeLifetimeError {
		member (value);
		require (path != "" && valid_path (path), "projection requires an exact nonempty ownership path");
		var node = new RuntimeLifetimeNode (RuntimeLifetimeNodeKind.PROJECT);
		node.source = value;
		node.path = path;
		projection_depth = int.max (projection_depth, path.split (".").length);
		return append (node);
	}

	public int replace(int value, string edge, int incoming) throws RuntimeLifetimeError {
		member (value);
		member (incoming);
		require (valid_edge (edge), "replacement requires one exact ownership edge");
		var node = new RuntimeLifetimeNode (RuntimeLifetimeNodeKind.REPLACE);
		node.source = value;
		node.path = edge;
		node.replacement = incoming;
		return append (node);
	}

	private RuntimeLifetimeQuery enqueue(HashTable<string, RuntimeLifetimeQuery> seen, GenericArray<RuntimeLifetimeQuery> pending, int node, string path, bool descendants, GenericArray<string>? excluded, RuntimeLifetimeQuery? parent = null) {
		// A growing projection cycle denotes arbitrarily deep descendants.
		// Widen to all descendants, preserving safety and finite convergence.
		if (path.split (".").length > nodes.length + projection_depth) {
			path = "";
			descendants = true;
			excluded = null;
		}
		var query = new RuntimeLifetimeQuery (node, path, descendants, excluded);
		string key = query.identity ();
		var existing = seen.lookup (key);
		if (existing != null) {
			query = existing;
		} else {
			query.cached_empty = empty_queries.contains (key);
			query.grounded = query.cached_empty;
			query.ordinal = (int) pending.length;
			seen.insert (key, query);
			pending.add (query);
		} if (parent != null && !query.parents.find (parent.ordinal)) {
			query.parents.add (parent.ordinal);
		}
		return query;
	}

	public GenericArray<RuntimeScopeOrigin> requirements(int value, string path = "", bool descendants = true, GenericArray<string>? excluded = null) throws RuntimeLifetimeError {
		member (value);
		require (sealed && valid_path (path), "query requires sealed equations and a valid ownership path");
		if (excluded != null) {
			require (descendants, "only descendant queries can exclude child edges");
			foreach (var edge in excluded) {
				require (valid_edge (edge), "invalid excluded ownership edge");
			}
		}
		var seen = new HashTable<string, RuntimeLifetimeQuery> (str_hash, str_equal);
		var pending = new GenericArray<RuntimeLifetimeQuery> ();
		enqueue (seen, pending, value, path, descendants, excluded);
		var origins = new HashTable<string, RuntimeScopeOrigin> (str_hash, str_equal);
		for (int p = 0; p < pending.length; p++) {
			var query = pending[p];
			if (query.cached_empty) {
				continue;
			}
			var node = nodes[query.node];
			if (node.kind == RuntimeLifetimeNodeKind.ABSENT) {
				query.grounded = true;
				continue;
			}
			if (node.kind == RuntimeLifetimeNodeKind.INPUT) {
				var origin = new RuntimeScopeOrigin.owner_input (node.parameter, query.path, query.descendants, query.excluded);
				origins.insert (origin.identity (), origin);
				query.grounded = true;
				continue;
			}
			if (node.kind == RuntimeLifetimeNodeKind.JOIN) {
				for (int a = 0; a < node.alternatives.length; a++) {
					enqueue (seen, pending, node.alternatives[a], query.path, query.descendants, query.excluded, query);
				}
				continue;
			}
			if (node.kind == RuntimeLifetimeNodeKind.PROJECT) {
				enqueue (seen, pending, node.source, node.path + (query.path == "" ? "" : "." + query.path), query.descendants, query.excluded, query);
				continue;
			}
			int dot = query.path.index_of_char ('.');
			string head = dot < 0 ? query.path : query.path.substring (0, dot);
			string tail = dot < 0 ? "" : query.path.substring (dot + 1);
			if (node.kind == RuntimeLifetimeNodeKind.REPLACE) {
				if (query.path != "") {
					enqueue (seen, pending, head == node.path ? node.replacement : node.source, head == node.path ? tail : query.path, query.descendants, query.excluded, query);
				} else {
					var omitted = new GenericArray<string> ();
					foreach (var edge in query.excluded) {
						omitted.add (edge);
					}
					if (!has_edge (omitted, node.path)) {
						omitted.add (node.path);
					}
					enqueue (seen, pending, node.source, "", query.descendants, query.descendants ? omitted : null, query);
					if (query.descendants && !has_edge (query.excluded, node.path)) {
						enqueue (seen, pending, node.replacement, "", true, null, query);
					}
				} continue;
			}
			require (node.kind == RuntimeLifetimeNodeKind.PRODUCT, "unknown ownership equation");
			if (query.path != "") {
				require (node.fields.contains (head), "projection is absent from the complete ownership product");
				enqueue (seen, pending, node.fields.lookup (head), tail, query.descendants, query.excluded, query);
				continue;
			}
			query.grounded = node.root_sources.length == 0;
			foreach (var origin in node.roots) {
				origins.insert (origin.identity (), origin);
			}
			for (int i = 0; i < node.root_sources.length; i++) {
				enqueue (seen, pending, node.root_sources[i], "", false, null, query);
			}
			if (query.descendants) {
				foreach (var edge in node.fields.get_keys ()) {
					if (!has_edge (query.excluded, edge)) {
						enqueue (seen, pending, node.fields.lookup (edge), "", true, null, query);
					}
				}
			}
		}
		var ready = new GenericArray<RuntimeLifetimeQuery> ();
		foreach (var query in pending) {
			if (query.grounded) {
				ready.add (query);
			}
		}
		for (int p = 0; p < ready.length; p++) {
			for (int a = 0; a < ready[p].parents.length; a++) {
				var parent = pending[ready[p].parents[a]];
				if (!parent.grounded) {
					parent.grounded = true;
					ready.add (parent);
				}
			}
		}
		if (ready.length != pending.length) {
			throw new RuntimeLifetimeError.UNGROUNDED ("runtime lifetime graph: an ownership equation cycle has no input or allocation grounding");
		}
		if (origins.size () == 0) {
			foreach (var key in seen.get_keys ()) {
				if (empty_queries.size () >= 65536) {
					break;
				}
				empty_queries.insert (key, true);
			}
		}
		var result = new GenericArray<RuntimeScopeOrigin> ();
		foreach (var origin in origins.get_values ()) {
			result.add (origin);
		}
		for (int i = 1; i < result.length; i++) {
			var origin = result[i];
			int position = i;
			while (position > 0 && strcmp (result[position - 1].identity (), origin.identity ()) > 0) {
				result[position] = result[position - 1];
				position--;
			}
			result[position] = origin;
		}
		return result;
	}

	// Instantiate an opaque function summary into the caller's own equations.
	// Only reachable result/effect nodes are copied. Local producer anchors
	// cannot cross this boundary; formal references bind to exact caller inputs.
	public int instantiate(int result, RuntimeLifetimeEquations caller, HashTable<int, int> inputs, HashTable<int, RuntimeScopeOrigin> contexts) throws RuntimeLifetimeError {
		require (sealed, "function summary must be sealed before instantiation");
		caller.open ();
		member (result);
		foreach (var origin in requirements (result)) {
			if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
				throw new RuntimeLifetimeError.LOCAL_ESCAPE ("runtime lifetime graph: callee-local scoped allocation cannot escape through an opaque result or stored effect");
			}
		}
		var copied = new HashTable<int, int> (direct_hash, direct_equal);
		return instantiate_node (result, caller, inputs, contexts, copied);
	}

	private int instantiate_node(int value, RuntimeLifetimeEquations caller, HashTable<int, int> inputs, HashTable<int, RuntimeScopeOrigin> contexts, HashTable<int, int> copied) throws RuntimeLifetimeError {
		if (copied.contains (value)) {
			return copied.lookup (value);
		}
		var node = nodes[value];
		if (node.kind == RuntimeLifetimeNodeKind.ABSENT) {
			return caller.absent ();
		}
		if (node.kind == RuntimeLifetimeNodeKind.INPUT) {
			require (inputs.contains (node.parameter), "summary lost its exact original owning input");
			int actual = inputs.lookup (node.parameter);
			caller.member (actual);
			copied.insert (value, actual);
			return actual;
		}
		int result = caller.join ();
		copied.insert (value, result);
		if (node.kind == RuntimeLifetimeNodeKind.JOIN) {
			for (int a = 0; a < node.alternatives.length; a++) {
				caller.alternative (result, instantiate_node (node.alternatives[a], caller, inputs, contexts, copied));
			}
			return result;
		}
		int materialized;
		if (node.kind == RuntimeLifetimeNodeKind.PROJECT) {
			materialized = caller.project (instantiate_node (node.source, caller, inputs, contexts, copied), node.path);
		} else if (node.kind == RuntimeLifetimeNodeKind.REPLACE) {
			materialized = caller.replace (instantiate_node (node.source, caller, inputs, contexts, copied), node.path, instantiate_node (node.replacement, caller, inputs, contexts, copied));
		} else {
			var roots = new GenericArray<RuntimeScopeOrigin> ();
			foreach (var origin in node.roots) {
				if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
					continue;
				}
				require (contexts.contains (origin.ordinal), "summary lost its exact borrowed allocator input");
				var actual = contexts.lookup (origin.ordinal);
				require (actual.valid () && actual.kind != RuntimeScopeOriginKind.OWNER_PARAMETER, "allocator input lost its exact caller lifetime anchor");
				roots.add (actual);
			}
			var fields = new HashTable<string, int> (str_hash, str_equal);
			foreach (var edge in node.fields.get_keys ()) {
				fields.insert (edge, instantiate_node (node.fields.lookup (edge), caller, inputs, contexts, copied));
			}
			var sources = new GenericArray<int> ();
			for (int i = 0; i < node.root_sources.length; i++) {
				sources.add (instantiate_node (node.root_sources[i], caller, inputs, contexts, copied));
			}
			materialized = caller.product (roots, fields, sources);
		}
		caller.alternative (result, materialized);
		return result;
	}

	// Wire snapshots contain only integer equations and formal context roots.
	// Compact traversal starts at the published outputs. Dead local roots may
	// remain under a replaced/projected edge, but no observable one may escape.
	private GenericArray<string> archive_fields(RuntimeLifetimeNode node) {
		var result = new GenericArray<string> ();
		foreach (var key in node.fields.get_keys ()) {
			result.add (key);
		}
		sort_edges (result);
		return result;
	}

	private static void archive_add(int value, HashTable<int, int> mapping, GenericArray<int> order) {
		if (!mapping.contains (value)) {
			mapping.insert (value, (int) order.length);
			order.add (value);
		}
	}

	private static void archive_references(StringBuilder text, GenericArray<int> values, HashTable<int, int> mapping) {
		for (int i = 0; i < values.length; i++) {
			if (i != 0) {
				text.append_c (',');
			}
			text.append_printf ("%d", mapping.lookup (values[i]));
		}
	}

	public string encode_outputs(GenericArray<int> outputs, out GenericArray<int> rewritten) throws RuntimeLifetimeError {
		require (sealed && outputs.length != 0, "archive requires sealed equations and exact outputs");
		var mapping = new HashTable<int, int> (direct_hash, direct_equal);
		var order = new GenericArray<int> ();
		rewritten = new GenericArray<int> ();
		archive_add (0, mapping, order);
		for (int i = 0; i < outputs.length; i++) {
			member (outputs[i]);
			foreach (var origin in requirements (outputs[i])) {
				if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
					throw new RuntimeLifetimeError.LOCAL_ESCAPE ("runtime lifetime archive cannot export a callee-local scope root");
				}
			}
			archive_add (outputs[i], mapping, order);
			rewritten.add (mapping.lookup (outputs[i]));
		}
		for (int i = 0; i < order.length; i++) {
			var node = nodes[order[i]];
			if (node.kind == RuntimeLifetimeNodeKind.PRODUCT) {
				foreach (var key in archive_fields (node)) {
					archive_add (node.fields.lookup (key), mapping, order);
				}
				for (int r = 0; r < node.root_sources.length; r++) {
					archive_add (node.root_sources[r], mapping, order);
				}
			} else if (node.kind == RuntimeLifetimeNodeKind.JOIN) {
				for (int a = 0; a < node.alternatives.length; a++) {
					archive_add (node.alternatives[a], mapping, order);
				}
			} else if (node.kind == RuntimeLifetimeNodeKind.PROJECT || node.kind == RuntimeLifetimeNodeKind.REPLACE) {
				archive_add (node.source, mapping, order);
				if (node.kind == RuntimeLifetimeNodeKind.REPLACE) {
					archive_add (node.replacement, mapping, order);
				}
			}
		}
		require (order.length <= 65536, "archive exceeds 65536 equations");
		var text = new StringBuilder ("runtime-lifetime-equations/1\n");
		for (int i = 0; i < order.length; i++) {
			var node = nodes[order[i]];
			switch (node.kind) {
			case RuntimeLifetimeNodeKind.ABSENT: text.append ("a");
				break;
			case RuntimeLifetimeNodeKind.INPUT: text.append_printf ("i|%d", node.parameter);
				break;
			case RuntimeLifetimeNodeKind.JOIN: text.append ("j|");
				archive_references (text, node.alternatives, mapping);
				break;
			case RuntimeLifetimeNodeKind.PROJECT: text.append_printf ("q|%d|%s", mapping.lookup (node.source), node.path);
				break;
			case RuntimeLifetimeNodeKind.REPLACE:
				text.append_printf ("r|%d|%s|%d", mapping.lookup (node.source), node.path, mapping.lookup (node.replacement));
				break;
			case RuntimeLifetimeNodeKind.PRODUCT:
				text.append ("p|");
				var roots = new GenericArray<string> ();
				var unique_roots = new HashTable<string, bool> (str_hash, str_equal);
				foreach (var origin in node.roots) {
					if (origin.kind != RuntimeScopeOriginKind.CONTEXT_PARAMETER) {
						continue;
					}
					string key = origin.ordinal.to_string ();
					if (!unique_roots.contains (key)) {
						unique_roots.insert (key, true);
						roots.add (key);
					}
				}
				sort_edges (roots);
				for (int r = 0; r < roots.length; r++) {
					if (r != 0) {
						text.append_c (',');
					}
					text.append (roots[r]);
				}
				text.append_c ('|');
				int field_count = 0;
				foreach (var key in archive_fields (node)) {
					if (field_count++ != 0) {
						text.append_c (',');
					}
					text.append_printf ("%s=%d", key, mapping.lookup (node.fields.lookup (key)));
				}
				text.append_c ('|');
				archive_references (text, node.root_sources, mapping);
				break;
			}
			text.append_c ('\n');
		}
		require (text.len <= 8 * 1024 * 1024, "archive exceeds 8 MiB");
		return text.str;
	}

	internal static int archive_integer(string text, int minimum = 0, int maximum = int.MAX) throws RuntimeLifetimeError {
		int64 value;
		require (int64.try_parse (text, out value) && value >= minimum && value <= maximum && text == value.to_string (), "archive requires canonical bounded integers");
		return (int) value;
	}

	public void validate_formals(bool receiver, bool[] owners, bool[] contexts) throws RuntimeLifetimeError {
		require (sealed && owners.length == contexts.length, "formal authority requires sealed equations and exact signature roles");
		foreach (var node in nodes) {
			if (node.kind == RuntimeLifetimeNodeKind.INPUT) {
				int p = node.parameter;
				require (p == -1 ? receiver : p >= 0 && p < owners.length && owners[p] && !contexts[p], "equation input differs from its declared owner or receiver role");
			}
			foreach (var root in node.roots) {
				require (root.kind == RuntimeScopeOriginKind.CONTEXT_PARAMETER && root.ordinal >= 0 && root.ordinal < contexts.length && contexts[root.ordinal] && !owners[root.ordinal], "equation context differs from its borrowed allocator signature role");
			}
		}
	}

	private static GenericArray<int> archive_list(string text, int maximum) throws RuntimeLifetimeError {
		var values = new GenericArray<int> ();
		if (text != "") {
			foreach (var item in text.split (",")) {
				values.add (archive_integer (item, 0, maximum));
			}
		}
		return values;
	}

	public static RuntimeLifetimeEquations decode(string text) throws RuntimeLifetimeError {
		require (text.length <= 8 * 1024 * 1024, "archive exceeds 8 MiB");
		var lines = text.split ("\n");
		require (lines.length >= 3 && lines[0] == "runtime-lifetime-equations/1" && lines[lines.length - 1] == "", "unsupported or truncated equation archive");
		int count = lines.length - 2;
		require (count <= 65536 && lines[1] == "a", "archive requires bounded equations and absent node zero");
		var result = new RuntimeLifetimeEquations ();
		for (int i = 1; i < count; i++) {
			var tokens = lines[i + 1].split ("|");
			RuntimeLifetimeNode node;
			if (tokens[0] == "i" && tokens.length == 2) {
				node = new RuntimeLifetimeNode (RuntimeLifetimeNodeKind.INPUT);
				node.parameter = archive_integer (tokens[1], -1);
			} else if (tokens[0] == "j" && tokens.length == 2) {
				node = new RuntimeLifetimeNode (RuntimeLifetimeNodeKind.JOIN);
				node.alternatives = archive_list (tokens[1], count - 1);
			} else if (tokens[0] == "q" && tokens.length == 3) {
				node = new RuntimeLifetimeNode (RuntimeLifetimeNodeKind.PROJECT);
				node.source = archive_integer (tokens[1], 0, count - 1);
				require (tokens[2] != "" && valid_path (tokens[2]), "archive projection lost its typed ownership path");
				node.path = tokens[2];
				result.projection_depth = int.max (result.projection_depth, node.path.split (".").length);
			} else if (tokens[0] == "r" && tokens.length == 4) {
				node = new RuntimeLifetimeNode (RuntimeLifetimeNodeKind.REPLACE);
				node.source = archive_integer (tokens[1], 0, count - 1);
				require (valid_edge (tokens[2]), "archive replacement lost its immediate ownership edge");
				node.path = tokens[2];
				node.replacement = archive_integer (tokens[3], 0, count - 1);
			} else if (tokens[0] == "p" && tokens.length == 4) {
				node = new RuntimeLifetimeNode (RuntimeLifetimeNodeKind.PRODUCT);
				var roots = archive_list (tokens[1], int.MAX);
				for (int r = 0; r < roots.length; r++) {
					node.roots.add (new RuntimeScopeOrigin.context_input (roots[r]));
				}
				if (tokens[2] != "") {
					foreach (var field in tokens[2].split (",")) {
						var pair = field.split ("=");
						require (pair.length == 2 && valid_edge (pair[0]) && !node.fields.contains (pair[0]), "archive field requires one unique typed edge");
						node.fields.insert (pair[0], archive_integer (pair[1], 0, count - 1));
					}
				}
				node.root_sources = archive_list (tokens[3], count - 1);
			} else {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("unsupported or malformed lifetime equation");
			}
			result.nodes.add (node);
		}
		result.seal ();
		return result;
	}

}

// Function-local lexical storage authority. Stage adapters reconstruct this
// tree and these inventories from their own declarations. An allocator's
// region and the actual destination owner's cleanup extent are distinct.
public class RuntimeLifetimeRegions : Object {
	private GenericArray<int> parents = new GenericArray<int> ();
	private HashTable<int, int> contexts = new HashTable<int, int> (direct_hash, direct_equal);
	private HashTable<int, int> storage = new HashTable<int, int> (direct_hash, direct_equal);
	private HashTable<int, bool> context_inputs = new HashTable<int, bool> (direct_hash, direct_equal);
	private HashTable<int, bool> owner_inputs = new HashTable<int, bool> (direct_hash, direct_equal);
	private bool sealed;
	private static void require(bool condition, string message) throws RuntimeLifetimeError {
		if (!condition) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("runtime lifetime regions: %s", message);
		}
	}

	public int add_region(int parent) throws RuntimeLifetimeError {
		require (!sealed && (parents.length == 0 ? parent == -1 : parent >= 0 && parent < parents.length), "regions require one root and exact prior parents");
		parents.add (parent);
		return (int) parents.length - 1;
	}

	public void context(int local, int region) throws RuntimeLifetimeError {
		require (!sealed && local >= 0 && region >= 0 && region < parents.length && !contexts.contains (local), "context requires its unique exact lexical declaration");
		contexts.insert (local, region);
	}

	public void owner(int local, int region) throws RuntimeLifetimeError {
		require (!sealed && local >= 0 && region >= 0 && region < parents.length && !storage.contains (local), "owner requires its unique actual storage cleanup extent");
		storage.insert (local, region);
	}

	public void input(int ordinal, bool allocator = false) throws RuntimeLifetimeError {
		require (!sealed && ordinal >= (allocator ? 0 : -1) && !context_inputs.contains (ordinal) && !owner_inputs.contains (ordinal), "input requires one exact context or owner signature role");
		if (allocator) {
			require (!context_inputs.contains (ordinal), "duplicate allocator input");
			context_inputs.insert (ordinal, true);
		} else {
			require (!owner_inputs.contains (ordinal), "duplicate owner input");
			owner_inputs.insert (ordinal, true);
		}
	}

	public void seal() {
		sealed = true;
	}

	private bool outlives(int source, int destination) {
		for (int region = destination; region >= 0; region = parents[region]) {
			if (source == region) {
				return true;
			}
		}
		return false;
	}

	public void validate(RuntimeLifetimeEquations equations, int value, int destination) throws RuntimeLifetimeError {
		require (sealed && storage.contains (destination), "lifetime check requires sealed authority and exact destination storage");
		foreach (var origin in equations.requirements (value)) {
			require (origin.valid (), "value carries an invalid context origin");
			if (origin.kind == RuntimeScopeOriginKind.CONTEXT_PARAMETER) {
				require (context_inputs.contains (origin.ordinal), "value refers to an unbound allocator input");
				continue;
			}
			if (origin.kind == RuntimeScopeOriginKind.OWNER_PARAMETER) {
				require (owner_inputs.contains (origin.ordinal), "value refers to an unbound owner or receiver input");
				continue;
			}
			require (contexts.contains (origin.ordinal) && contexts.lookup (origin.ordinal) == origin.region, "value refers to a different context declaration or region");
			int region = storage.lookup (destination);
			if (!outlives (origin.region, region) || origin.region == region && origin.ordinal >= destination) {
				throw new RuntimeLifetimeError.LOCAL_ESCAPE ("runtime lifetime regions: scoped allocation cannot outlive context #%d through owner #%d".printf (origin.ordinal, destination));
			}
		}
	}

}

// Temporary stage-local state. Bindings name compiler slots using primitive
// IDs; reads capture their current graph version, never the mutable slot.
public class RuntimeLifetimeState : Object {
	public bool reachable = true;
	internal HashTable<int, int> bindings = new HashTable<int, int> (direct_hash, direct_equal);
	public RuntimeLifetimeState snapshot() {
		var result = new RuntimeLifetimeState ();
		result.reachable = reachable;
		foreach (int key in bindings.get_keys ()) {
			result.bindings.insert (key, bindings.lookup (key));
		}
		return result;
	}

}
public class RuntimeLifetimeException : Object {
	public RuntimeLifetimeState state { get; private set; }
	public int value { get; private set; }
	public int site { get; private set; }
	internal RuntimeLifetimeException (RuntimeLifetimeState state, int value, int site) {
		this.state = state.snapshot ();
		this.value = value;
		this.site = site;
	}

}
private class RuntimeLifetimeLoop : Object {
	internal RuntimeLifetimeState header;
	internal GenericArray<RuntimeLifetimeState> continues = new GenericArray<RuntimeLifetimeState> ();
	internal GenericArray<RuntimeLifetimeState> exits = new GenericArray<RuntimeLifetimeState> ();
	internal RuntimeLifetimeLoop (RuntimeLifetimeState header) {
		this.header = header;
	}

}
public class RuntimeLifetimeFlow : Object {
	public RuntimeLifetimeEquations equations { get; private set; default = new RuntimeLifetimeEquations (); }
	public RuntimeLifetimeState state { get; set; default = new RuntimeLifetimeState (); }
	private GenericArray<RuntimeLifetimeLoop> loops = new GenericArray<RuntimeLifetimeLoop> ();
	private GenericArray<GenericArray<RuntimeLifetimeException>> protected_states = new GenericArray<GenericArray<RuntimeLifetimeException>> ();
	private static void require(bool condition, string message) throws RuntimeLifetimeError {
		if (!condition) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("runtime lifetime flow: %s", message);
		}
	}

	public int read(int binding) throws RuntimeLifetimeError {
		require (state.bindings.contains (binding), "read requires its declared graph binding");
		return state.bindings.lookup (binding);
	}

	public void declare(int binding, int value) throws RuntimeLifetimeError {
		require (!state.bindings.contains (binding) && equations.contains (value), "declaration requires a fresh slot and exact graph value");
		state.bindings.insert (binding, value);
	}

	public void write(int binding, int value) throws RuntimeLifetimeError {
		require (state.bindings.contains (binding) && equations.contains (value), "write requires its current declared slot and exact graph value");
		state.bindings.insert (binding, value);
	}

	public RuntimeLifetimeState project(RuntimeLifetimeState scope, RuntimeLifetimeState incoming) throws RuntimeLifetimeError {
		var result = scope.snapshot ();
		result.reachable = incoming.reachable;
		foreach (int key in scope.bindings.get_keys ()) {
			require (incoming.bindings.contains (key), "scope exit lost a surviving binding");
			result.bindings.insert (key, incoming.bindings.lookup (key));
		}
		return result;
	}

	public void merge(RuntimeLifetimeState scope, RuntimeLifetimeState left, RuntimeLifetimeState right) throws RuntimeLifetimeError {
		if (!left.reachable) {
			state = project (scope, right);
			return;
		}
		if (!right.reachable) {
			state = project (scope, left);
			return;
		}
		var merged = scope.snapshot ();
		foreach (int key in scope.bindings.get_keys ()) {
			require (left.bindings.contains (key) && right.bindings.contains (key), "control join lost an incoming graph binding");
			int a = left.bindings.lookup (key), b = right.bindings.lookup (key);
			if (a == b) {
				merged.bindings.insert (key, a);
			} else {
				int joined = equations.join ();
				equations.alternative (joined, a);
				equations.alternative (joined, b);
				merged.bindings.insert (key, joined);
			}
		}
		state = merged;
	}

	public void begin_loop() throws RuntimeLifetimeError {
		var header = state.snapshot ();
		foreach (int key in state.bindings.get_keys ()) {
			int phi = equations.join ();
			equations.alternative (phi, state.bindings.lookup (key));
			header.bindings.insert (key, phi);
		}
		loops.add (new RuntimeLifetimeLoop (header));
		state = header.snapshot ();
	}

	public void jump(bool exiting) throws RuntimeLifetimeError {
		require (loops.length != 0, "loop jump requires an active exact target");
		if (state.reachable) {
			var loop = loops[loops.length - 1];
			var incoming = project (loop.header, state);
			if (exiting) {
				loop.exits.add (incoming);
			} else {
				loop.continues.add (incoming);
			}
		}
		state.reachable = false;
	}

	public void begin_step() throws RuntimeLifetimeError {
		require (loops.length != 0, "loop step requires an active exact target");
		var loop = loops[loops.length - 1];
		foreach (var incoming in loop.continues) {
			merge (loop.header, state, incoming);
		}
		loop.continues = new GenericArray<RuntimeLifetimeState> ();
	}

	public void end_loop() throws RuntimeLifetimeError {
		begin_step ();
		var loop = loops[loops.length - 1];
		if (state.reachable) {
			foreach (int key in loop.header.bindings.get_keys ()) {
				require (state.bindings.contains (key), "backedge lost a loop-carried binding");
				equations.alternative (loop.header.bindings.lookup (key), state.bindings.lookup (key));
			}
		}
		loops.remove_index (loops.length - 1);
		state = loop.header.snapshot ();
		foreach (var incoming in loop.exits) {
			merge (loop.header, state, incoming);
		}
	}

	public void begin_try() {
		protected_states.add (new GenericArray<RuntimeLifetimeException> ());
	}

	public void exception(int value, int site) throws RuntimeLifetimeError {
		require (equations.contains (value) && site >= 0, "exception requires its exact graph value and call/throw site");
		if (state.reachable && protected_states.length != 0) {
			protected_states[protected_states.length - 1].add (new RuntimeLifetimeException (state, value, site));
		}
	}

	public GenericArray<RuntimeLifetimeException> end_try() throws RuntimeLifetimeError {
		require (protected_states.length != 0, "exception region is absent");
		var result = protected_states[protected_states.length - 1];
		protected_states.remove_index (protected_states.length - 1);
		return result;
	}

}
}
