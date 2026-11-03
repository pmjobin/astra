// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.VectorLaneOracle {
private class BoolLane : Object {
	internal bool value;
	internal BoolLane (bool value) {
		this.value = value;
	}

}

// Test-only ordered scalar values. These operations never compute scalar
// arithmetic: in particular, exact AstraF32Value objects pass through intact.
private class VectorValue : Object {
	private GenericArray<Object> lanes = new GenericArray<Object> ();
	internal int count { get { return (int) lanes.length; } }
	internal VectorValue (GenericArray<Object> input) {
		foreach (var lane in input) {
			lanes.add (lane);
		}
	}

	internal Object extract(int index) {
		assert (index >= 0 && index < count);
		return lanes[index];
	}

	internal static VectorValue splat(Object value, int count) {
		var lanes = new GenericArray<Object> ();
		for (int i = 0; i < count; i++) {
			lanes.add (value);
		}
		return new VectorValue (lanes);
	}

	internal VectorValue insert(int index, Object replacement) {
		assert (index >= 0 && index < count);
		var lanes = new GenericArray<Object> ();
		for (int i = 0; i < count; i++) {
			lanes.add (i == index ? replacement : this.lanes[i]);
		}
		return new VectorValue (lanes);
	}

	internal VectorValue shuffle(int[] selectors) {
		assert (selectors.length == count);
		var lanes = new GenericArray<Object> ();
		foreach (int index in selectors) {
			lanes.add (extract (index));
		}
		return new VectorValue (lanes);
	}

	internal static VectorValue select(VectorValue mask, VectorValue a, VectorValue b) {
		assert (mask.count == a.count && a.count == b.count);
		var lanes = new GenericArray<Object> ();
		for (int i = 0; i < a.count; i++) {
			lanes.add (((BoolLane) mask.extract (i)).value ? a.extract (i) : b.extract (i));
		}
		return new VectorValue (lanes);
	}

}

private HashTable<Object, string> spellings;
private int lane_checks;
private int definitions;
private int identity_checks;

private string literal(Object value) {
	if (value is AstraIntegerValue) {
		return ((AstraIntegerValue) value).to_string ();
	}
	if (value is BoolLane) {
		return ((BoolLane) value).value ? "true" : "false";
	}
	return spellings.lookup (value);
}

private string initializer(VectorValue value) {
	var text = new StringBuilder ("{");
	for (int i = 0; i < value.count; i++) {
		if (i > 0) {
			text.append (",");
		}
		text.append (literal (value.extract (i)));
	}
	text.append ("}");
	return text.str;
}

private void check_scalar(string expression, Object expected) {
	var f32 = expected as AstraF32Value;
	string failure;
	if (f32 != null && (f32.bits & 0x7fffffffU) > 0x7f800000U) {
		failure = "%s==%s".printf (expression, expression);
	} else if (f32 != null && (f32.bits & 0x7fffffffU) == 0) {
		failure = "1.0/%s!=%s1e100".printf (expression, f32.bits == 0 ? "" : "-");
	} else {
		failure = "%s!=%s".printf (expression, literal (expected));
	}
	stdout.printf ("\tif(%s){return false;}\n", failure);
	lane_checks++;
}

private void check_vector(string type, string expression, VectorValue expected) {
	string name = "r%d".printf (definitions++);
	stdout.printf ("\t%s %s=%s;\n", type, name, expression);
	if (!(expected.extract (0) is AstraF32Value)) {
		// Accepted VEC-1 equality/all checks every integer/bool lane at
		// once. Avoid a large unrelated scalar CFG in the test harness.
		stdout.printf ("\t%s e%s=%s;\n\tif(!all(%s==e%s)){return false;}\n", type, name, initializer (expected), name, name);
		lane_checks += expected.count;
		return;
	}
	for (int i = 0; i < expected.count; i++) {
		check_scalar ("%s[%d]".printf (name, i), expected.extract (i));
	}
}

private void same_objects(VectorValue a, VectorValue b) {
	assert (a.count == b.count);
	for (int i = 0; i < a.count; i++) {
		assert (a.extract (i) == b.extract (i));
		identity_checks++;
	}
}

int main() {
	var types = new BuiltinTypes ();
	spellings = new HashTable<Object, string> (direct_hash, direct_equal);
	var float_values = new GenericArray<Object> ();
	foreach (string text in new string[] {"0.0", "-0.0", "1.401298464324817070923729583289916131280e-45", "-1.401298464324817070923729583289916131280e-45", "1.1754942106924411e-38", "1.1754943508222875e-38", "1.00000011920928955078125", "-123.4567", "3.4028234663852886e38", "1e100", "-1e100"}) {
		var value = AstraF32Value.from_decimal (text.has_prefix ("-") ? text.substring (1) : text);
		assert (value != null);
		if (text.has_prefix ("-")) {
			value = value.negated ();
		}
		float_values.add (value);
		spellings.insert (value, text);
	}
	var nan = new AstraF32Value.from_bits (0x7fc01234U);
	float_values.add (nan);
	spellings.insert (nan, "nan(0.0)");
	stdout.printf ("f32 nan(f32 x){return x/x;}\n");
	var calls = new GenericArray<string> ();
	int shapes = 0;
	uint64 state = 0xA57A1A;
	foreach (string element in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		foreach (int count in new int[] {2, 4, 8, 16}) {
			var vector_type = types.vector_of (types.resolve (element), count);
			if (vector_type == null) {
				continue;
			}
			string type = vector_type.display_name ();
			string id = "v%d".printf (shapes++);
			stdout.printf ("%s %s_splat(%s x){return splat(x,%d);}\n", type, id, element, count);
			stdout.printf ("%s %s_select(bool<%d> m,%s a,%s b){return select(m,a,b);}\n", type, id, count, type, type);
			for (int i = 0; i < count; i++) {
				stdout.printf ("%s %s_extract%d(%s v){return v[%d];}\n", element, id, i, type, i);
				stdout.printf ("%s %s_insert%d(%s v,%s x){return insert(v,%d,x);}\n", type, id, i, type, element, i);
			}
			int[,] permutations = new int[4, count];
			for (int i = 0; i < count; i++) {
				permutations[0, i] = count - i - 1;
				permutations[1, i] = i;
				permutations[2, i] = 0;
				permutations[3, i] = (i + 1) % count;
			}
			for (int p = 0; p < 4; p++) {
				stdout.printf ("%s %s_shuffle%d(%s v){return shuffle(v", type, id, p, type);
				for (int i = 0; i < count; i++) {
					stdout.printf (",%d", permutations[p, i]);
				}
				stdout.printf (");}\n");
			}
			for (int trial = 0; trial < 12; trial++) {
				var a_lanes = new GenericArray<Object> ();
				var b_lanes = new GenericArray<Object> ();
				var mask_lanes = new GenericArray<Object> ();
				for (int i = 0; i < count; i++) {
					var integer = vector_type.element_type as IntegerType;
					if (integer != null) {
						state = (state * 1664525 + 1013904223) % 4294967296UL;
						a_lanes.add (AstraIntegerValue.from_bits (integer, trial == 0 ? integer.mask : trial == 1 ? integer.modulus / 2 : state & integer.mask));
						state = (state * 1664525 + 1013904223) % 4294967296UL;
						b_lanes.add (AstraIntegerValue.from_bits (integer, state & integer.mask));
					} else if (element == "f32") {
						a_lanes.add (float_values[(trial + i) % float_values.length]);
						b_lanes.add (float_values[(trial + i + 5) % float_values.length]);
					} else {
						a_lanes.add (new BoolLane ((trial + i) % 2 == 0));
						b_lanes.add (new BoolLane ((trial + i) % 3 == 0));
					}
					mask_lanes.add (new BoolLane (trial % 3 == 0 || (trial % 3 == 2 && i % 2 == 0)));
				}
				var a = new VectorValue (a_lanes);
				var b = new VectorValue (b_lanes);
				var mask = new VectorValue (mask_lanes);
				string name = "%s_check%d".printf (id, trial);
				calls.add (name);
				stdout.printf ("bool %s(){\n\t%s a=%s;\n\t%s b=%s;\n\tbool<%d> m=%s;\n", name, type, initializer (a), type, initializer (b), count, initializer (mask));
				check_vector (type, "%s_splat(a[0])".printf (id), VectorValue.splat (a.extract (0), count));
				check_vector (type, initializer (VectorValue.splat (a.extract (0), count)), VectorValue.splat (a.extract (0), count));
				for (int k = 0; k < count; k++) {
					check_scalar ("%s_extract%d(a)".printf (id, k), a.extract (k));
					var inserted = a.insert (k, b.extract (k));
					for (int i = 0; i < count; i++) {
						assert (inserted.extract (i) == (i == k ? b.extract (k) : a.extract (i)));
						identity_checks++;
					}
					check_vector (type, "%s_insert%d(a,b[%d])".printf (id, k, k), inserted);
					check_vector (type, "%s_insert%d(a,a[%d])".printf (id, k, k), a);
					same_objects (a.insert (k, a.extract (k)), a);
				}
				for (int p = 0; p < 4; p++) {
					int[] selectors = new int[count];
					for (int i = 0; i < count; i++) {
						selectors[i] = permutations[p, i];
					}
					check_vector (type, "%s_shuffle%d(a)".printf (id, p), a.shuffle (selectors));
				}
				same_objects (a.shuffle (new int[count]), VectorValue.splat (a.extract (0), count));
				check_vector (type, "%s_select(m,a,b)".printf (id), VectorValue.select (mask, a, b));
				check_vector (type, "%s_select(m,a,a)".printf (id), a);
				check_vector (type, "%s_select(splat(true,%d),a,b)".printf (id, count), a);
				check_vector (type, "%s_select(splat(false,%d),a,b)".printf (id, count), b);
				same_objects (VectorValue.select (VectorValue.splat (new BoolLane (true), count), a, b), a);
				same_objects (VectorValue.select (VectorValue.splat (new BoolLane (false), count), a, b), b);
				same_objects (VectorValue.select (mask, a, a), a);
				stdout.printf ("\treturn true;\n}\n");
			}
		}
	}
	stdout.printf ("int main(){\n");
	foreach (var name in calls) {
		stdout.printf ("\tif(!%s()){return 1;}\n", name);
	}
	stdout.printf ("\treturn 0;\n}\n// oracle shapes=%d cases=%u lane_checks=%d identity_checks=%d\n", shapes, calls.length, lane_checks, identity_checks);
	return 0;
}

}
