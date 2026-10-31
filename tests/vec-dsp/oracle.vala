// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Tests.DspValues;

namespace Astra.Tests.DspOracle {
private class BoolLane : Object {
	internal bool value;
	internal BoolLane (bool value) {
		this.value = value;
	}
}

// Test-only ordered scalar objects. Integer math/conversion delegates to
// the compiler authorities; structural operations retain exact lane objects.
private class VectorValue : Object {
	internal GenericArray<Object> lanes = new GenericArray<Object> ();
	internal int count { get { return (int) lanes.length; } }
	internal VectorValue sat_add(VectorValue other) {
		return saturate (other, true);
	}
	internal VectorValue sat_sub(VectorValue other) {
		return saturate (other, false);
	}
	private VectorValue saturate(VectorValue other, bool add) {
		assert (count == other.count);
		var result = new VectorValue ();
		for (int i = 0; i < count; i++) {
			var a = (AstraIntegerValue) lanes[i];
			var b = (AstraIntegerValue) other.lanes[i];
			result.lanes.add (add ? a.saturating_add (b) : a.saturating_sub (b));
		}
		return result;
	}
	internal VectorValue widen_low(IntegerType destination) {
		return widen (destination, 0);
	}
	internal VectorValue widen_high(IntegerType destination) {
		return widen (destination, count / 2);
	}
	private VectorValue widen(IntegerType destination, int start) {
		var result = new VectorValue ();
		for (int i = 0; i < count / 2; i++) {
			result.lanes.add (((AstraIntegerValue) lanes[start + i]).convert_to (destination));
		}
		return result;
	}
	internal VectorValue pack_wrap(VectorValue other, IntegerType destination) {
		return pack (other, destination, false);
	}
	internal VectorValue pack_sat(VectorValue other, IntegerType destination) {
		return pack (other, destination, true);
	}
	private VectorValue pack(VectorValue other, IntegerType destination, bool saturate) {
		assert (count == other.count);
		var result = new VectorValue ();
		foreach (var source in new VectorValue[] {this, other}) {
			foreach (var lane in source.lanes) {
				result.lanes.add (saturate ? ((AstraIntegerValue) lane).saturating_convert_to (destination) : ((AstraIntegerValue) lane).convert_to (destination));
			}
		}
		return result;
	}
	internal VectorValue interleave_low(VectorValue other) {
		return interleave (other, 0);
	}
	internal VectorValue interleave_high(VectorValue other) {
		return interleave (other, count / 2);
	}
	private VectorValue interleave(VectorValue other, int start) {
		assert (count == other.count);
		var result = new VectorValue ();
		for (int i = 0; i < count / 2; i++) {
			result.lanes.add (lanes[start + i]);
			result.lanes.add (other.lanes[start + i]);
		}
		return result;
	}
}

private HashTable<Object, string> spellings;
private int definitions;
private int lane_checks;
private int vector_cases;
private int roundtrips;
private int identity_checks;
private int scalar_checks;

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
		text.append (literal (value.lanes[i]));
	}
	text.append ("}");
	return text.str;
}

private void check_vector(string type, string expression, VectorValue expected) {
	string name = "v%d".printf (definitions++);
	stdout.printf ("\t%s %s=%s;\n", type, name, expression);
	if (!(expected.lanes[0] is AstraF32Value)) {
		stdout.printf ("\t%s e%s=%s;\n\tif(!all(%s==e%s)){return false;}\n", type, name, initializer (expected), name, name);
	} else {
		for (int i = 0; i < expected.count; i++) {
			var value = (AstraF32Value) expected.lanes[i];
			string lane = "%s[%d]".printf (name, i);
			string failure = (value.bits & 0x7fffffffU) > 0x7f800000U ? lane + "==" + lane : (value.bits & 0x7fffffffU) == 0 ? "1.0/" + lane + "!=" + (value.bits == 0 ? "" : "-") + "1e100" : lane + "!=" + literal (value);
			stdout.printf ("\tif(%s){return false;}\n", failure);
		}
	}
	lane_checks += expected.count;
	vector_cases++;
}

private void scalar_runtime(BuiltinTypes types, GenericArray<string> calls) {
	foreach (var type in integers (types)) {
		string name = type.display_name ();
		stdout.printf ("%s %s_add(%s a,%s b){return sat_add(a,b);}\n%s %s_sub(%s a,%s b){return sat_sub(a,b);}\n", name, name, name, name, name, name, name, name);
		if (type.bit_width == 8) {
			// Native exhaustive oracle uses int math: all intermediates fit.
			stdout.printf ("bool scalar_%s(){int a=%s;while(a<=%s){int b=%s;while(b<=%s){int s=a+b;int d=a-b;if(s<%s){s=%s;}if(s>%s){s=%s;}if(d<%s){d=%s;}if(d>%s){d=%s;}if((%s_add(a as %s,b as %s) as int)!=s || (%s_sub(a as %s,b as %s) as int)!=d){return false;}b=b+1;}a=a+1;}return true;}\n", name, type.minimum.to_string (), type.maximum.to_string (), type.minimum.to_string (), type.maximum.to_string (), type.minimum.to_string (), type.minimum.to_string (), type.maximum.to_string (), type.maximum.to_string (), type.minimum.to_string (), type.minimum.to_string (), type.maximum.to_string (), type.maximum.to_string (), name, name, name, name, name, name);
			scalar_checks += 131072;
			calls.add ("scalar_" + name + "()");
		} else {
			var values = boundaries (type);
			for (int row = 0; row < values.length; row++) {
				string function = "%s_matrix%d".printf (name, row);
				stdout.printf ("bool %s(){\n", function);
				var a = AstraIntegerValue.from_int64 (type, values[row]);
				foreach (int64 number in values) {
					var b = AstraIntegerValue.from_int64 (type, number);
					stdout.printf ("\tif(%s_add(%s,%s)!=%s || %s_sub(%s,%s)!=%s){return false;}\n", name, a.to_string (), b.to_string (), a.saturating_add (b).to_string (), name, a.to_string (), b.to_string (), a.saturating_sub (b).to_string ());
					scalar_checks += 2;
				}
				stdout.printf ("\treturn true;\n}\n");
				calls.add (function + "()");
			}
		}
	}
}

int main() {
	var types = new BuiltinTypes ();
	var calls = new GenericArray<string> ();
	spellings = new HashTable<Object, string> (direct_hash, direct_equal);
	var floats = new GenericArray<Object> ();
	foreach (string text in new string[] {"0.0", "-0.0", "1.401298464324817070923729583289916131280e-45", "-1.401298464324817070923729583289916131280e-45", "1e100", "-1e100", "1.00000011920928955078125", "3.4028234663852886e38"}) {
		var value = AstraF32Value.from_decimal (text.has_prefix ("-") ? text.substring (1) : text);
		if (text.has_prefix ("-")) {
			value = value.negated ();
		}
		floats.add (value);
		spellings.insert (value, text);
	}
	var nan = new AstraF32Value.from_bits (0x7fc01234U);
	floats.add (nan);
	spellings.insert (nan, "nan(0.0)");
	stdout.printf ("f32 nan(f32 x){return x/x;}\n");
	scalar_runtime (types, calls);
	int shapes = 0;
	int widen_pairs = 0;
	int pack_pairs = 0;
	uint64 state = 0xA57AD5;
	foreach (string category in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		var element = types.resolve (category);
		var integer = element as IntegerType;
		foreach (int count in new int[] {2, 4, 8, 16}) {
			var type = types.vector_of (element, count);
			if (type == null) {
				continue;
			}
			string name = type.display_name ();
			string id = "shape%d".printf (shapes++);
			foreach (string op in new string[] {"sat_add", "sat_sub", "interleave_low", "interleave_high"}) {
				if (op.has_prefix ("sat") && integer == null) {
					continue;
				}
				stdout.printf ("%s %s_%s(%s a,%s b){return %s(a,b);}\n", name, id, op, name, name, op);
			}
			if (integer != null) {
				foreach (var destination in integers (types)) {
					bool widen = destination.bit_width > integer.bit_width;
					if (destination.bit_width == integer.bit_width) {
						continue;
					}
					var output = types.vector_of (destination, widen ? count / 2 : count * 2);
					if (output == null) {
						continue;
					}
					if (widen) {
						widen_pairs++;
					} else {
						pack_pairs++;
					}
					foreach (string op in widen ? new string[] {"widen_low", "widen_high"} : new string[] {"pack_wrap", "pack_sat"}) {
						stdout.printf ("%s %s_%s_%s(%s a%s){return %s(a,%s%s);}\n", output.display_name (), id, op, destination.display_name (), name, widen ? "" : "," + name + " b", op, widen ? "" : "b,", destination.display_name ());
					}
				}
			}
			for (int trial = 0; trial < 12; trial++) {
				var a = new VectorValue ();
				var b = new VectorValue ();
				for (int lane = 0; lane < count; lane++) {
					if (integer != null) {
						var bounds = boundaries (integer);
						state = (state * 1664525 + 1013904223) % 4294967296UL;
						a.lanes.add (trial < 8 ? AstraIntegerValue.from_int64 (integer, bounds[(trial * count + lane) % bounds.length]) : AstraIntegerValue.from_bits (integer, state & integer.mask));
						state = (state * 1664525 + 1013904223) % 4294967296UL;
						b.lanes.add (trial < 8 ? AstraIntegerValue.from_int64 (integer, bounds[(trial * count + lane + bounds.length / 2) % bounds.length]) : AstraIntegerValue.from_bits (integer, state & integer.mask));
					} else if (category == "f32") {
						a.lanes.add (floats[(trial + lane) % floats.length]);
						b.lanes.add (floats[(trial + lane + 4) % floats.length]);
					} else {
						a.lanes.add (new BoolLane ((trial + lane) % 2 == 0));
						b.lanes.add (new BoolLane ((trial + lane) % 3 == 0));
					}
				}
				string function = "%s_case%d".printf (id, trial);
				stdout.printf ("bool %s(){\n\t%s a=%s;\n\t%s b=%s;\n", function, name, initializer (a), name, initializer (b));
				var low = a.interleave_low (b);
				var high = a.interleave_high (b);
				for (int lane = 0; lane < count; lane++) {
					assert (low.lanes[lane] == (lane % 2 == 0 ? a : b).lanes[lane / 2]);
					assert (high.lanes[lane] == (lane % 2 == 0 ? a : b).lanes[count / 2 + lane / 2]);
					identity_checks += 2;
				}
				check_vector (name, id + "_interleave_low(a,b)", low);
				check_vector (name, id + "_interleave_high(a,b)", high);
				if (integer != null) {
					check_vector (name, id + "_sat_add(a,b)", a.sat_add (b));
					check_vector (name, id + "_sat_sub(a,b)", a.sat_sub (b));
					foreach (var destination in integers (types)) {
						bool widen = destination.bit_width > integer.bit_width;
						if (destination.bit_width == integer.bit_width) {
							continue;
						}
						var output = types.vector_of (destination, widen ? count / 2 : count * 2);
						if (output == null) {
							continue;
						}
						string d = destination.display_name ();
						if (widen) {
							check_vector (output.display_name (), id + "_widen_low_" + d + "(a)", a.widen_low (destination));
							check_vector (output.display_name (), id + "_widen_high_" + d + "(a)", a.widen_high (destination));
							var round = a.widen_low (destination).pack_wrap (a.widen_high (destination), integer);
							for (int lane = 0; lane < count; lane++) {
								assert (((AstraIntegerValue) round.lanes[lane]).equal_value ((AstraIntegerValue) a.lanes[lane]));
							}
							check_vector (name, "pack_wrap(" + id + "_widen_low_" + d + "(a)," + id + "_widen_high_" + d + "(a)," + category + ")", a);
							roundtrips++;
						} else {
							check_vector (output.display_name (), id + "_pack_wrap_" + d + "(a,b)", a.pack_wrap (b, destination));
							check_vector (output.display_name (), id + "_pack_sat_" + d + "(a,b)", a.pack_sat (b, destination));
						}
					}
				}
				stdout.printf ("\treturn true;\n}\n");
				calls.add (function + "()");
			}
		}
	}
	stdout.printf ("int main(){\n");
	foreach (string call in calls) {
		stdout.printf ("\tif(!%s){return 1;}\n", call);
	}
	stdout.printf ("\treturn 0;\n}\n// oracle scalar_checks=%d vector_shapes=%d widen_pairs=%d pack_pairs=%d vector_cases=%d lane_checks=%d roundtrips=%d identity_checks=%d\n", scalar_checks, shapes, widen_pairs, pack_pairs, vector_cases, lane_checks, roundtrips, identity_checks);
	return 0;
}
}
