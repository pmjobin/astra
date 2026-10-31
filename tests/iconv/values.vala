// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.IntegerConversionOracle {
private uint scalar_checks;
private uint vector_checks;
private uint vector_cases;

private IntegerType[] integers(BuiltinTypes types) {
	return {
			   types.i8_type, types.u8_type, types.i16_type, types.u16_type, types.i32_type, types.u32_type
	};
}

private uint64[] patterns(IntegerType type) {
	var numbers = new uint64[15 + 10 * (type.bit_width - 1)];
	int index = 0;
	foreach (uint64 bits in new uint64[] {0, 1, 2, 3, 0x55, 0xaa, 0x5555, 0xaaaa, 0x55555555, 0xaaaaaaaa, type.mask, type.mask - 1, type.modulus / 2, type.modulus / 2 - 1, type.modulus / 2 + 1}) {
		numbers[index++] = bits & type.mask;
	}
	for (int power = 1; power < type.bit_width; power++) {
		uint64 boundary = ((uint64) 1) << power;
		for (int delta = -2; delta <= 2; delta++) {
			uint64 bits = (uint64) ((int64) boundary + delta) & type.mask;
			numbers[index++] = bits;
			numbers[index++] = type.mask ^ bits;
		}
	}
	assert (index == numbers.length);
	return numbers;
}

private void qualify(IntegerType source, IntegerType destination, uint64 bits) {
	var value = AstraIntegerValue.from_bits (source, bits);
	var converted = value.convert_to (destination);
	// Independent bit derivation, checked against the mathematical oracle:
	// retain low bits, then fill the extension region only for a negative source.
	uint64 expected = bits & destination.mask;
	if (destination.bit_width > source.bit_width && source.is_signed && bits >= source.modulus / 2) {
		expected |= destination.mask ^ source.mask;
	}
	int64 mathematical = destination.is_signed && expected >= destination.modulus / 2 ? (int64) expected - (int64) destination.modulus : (int64) expected;
	assert (converted.integer_type == destination && converted.bits == expected && converted.mathematical_value == mathematical);
	assert (converted.bits < destination.modulus);
	if (destination.bit_width <= source.bit_width) {
		assert (converted.bits == (bits & destination.mask));
	}
	if (destination.bit_width >= source.bit_width) {
		assert (converted.convert_to (source).equal_value (value));
	}
	if (source == destination) {
		assert (converted.equal_value (value));
	}
	scalar_checks++;
}

private void exhaustive() {
	var types = new BuiltinTypes ();
	uint before = scalar_checks;
	foreach (var source in new IntegerType[] {types.i8_type, types.u8_type}) {
		foreach (var destination in integers (types)) {
			for (uint64 bits = 0; bits < 256; bits++) {
				qualify (source, destination, bits);
			}
		}
	}
	assert (scalar_checks - before == 3072);
}

private void wider() {
	var types = new BuiltinTypes ();
	foreach (var source in new IntegerType[] {types.i16_type, types.u16_type, types.i32_type, types.u32_type}) {
		foreach (var destination in integers (types)) {
			foreach (uint64 bits in patterns (source)) {
				qualify (source, destination, bits);
			}
		}
	}
}

private void authority() {
	var types = new BuiltinTypes ();
	foreach (var source in integers (types)) {
		foreach (var destination in integers (types)) {
			assert (IntegerConversion.accepts (source, destination));
		}
		foreach (var unsupported in new SemanticType[] {types.bool_type, types.f32_type, types.raw_pointer_type, types.void_type, new StructType ("S"), new HandleType ("Resource")}) {
			assert (!IntegerConversion.accepts (source, unsupported) && !IntegerConversion.accepts (unsupported, source));
		}
	}
}

private void emit_runtime() {
	var types = new BuiltinTypes ();
	var functions = new StringBuilder ();
	var calls = new StringBuilder ("int main(){\n");
	int index = 0;
	// Parameter-driven conversions prevent dependence on Astra/LLVM constant folding.
	foreach (var source in integers (types)) {
		foreach (var destination in integers (types)) {
			string s = source.display_name ();
			string d = destination.display_name ();
			functions.append_printf ("%s c%d(%s x){return x as %s;}\n", d, index, s, d);
			functions.append_printf ("int t%d(){\n", index);
			var bits = patterns (source);
			// Exhaustive 8-bit runtime differential; wider runtime uses the full boundary matrix.
			int count = source.bit_width == 8 ? 256 : bits.length;
			for (int i = 0; i < count; i++) {
				var value = AstraIntegerValue.from_bits (source, source.bit_width == 8 ? (uint64) i : bits[i]);
				functions.append_printf ("\tif(c%d(%s)!=%s){return 1;}\n", index, value.to_string (), value.convert_to (destination).to_string ());
			}
			functions.append ("\treturn 0;\n}\n");
			calls.append_printf ("\tif(t%d()!=0){return 1;}\n", index++);
		}
	}
	uint shapes = 0;
	foreach (int lanes in new int[] {2, 4, 8, 16}) {
		foreach (var source in integers (types)) {
			foreach (var destination in integers (types)) {
				var from = types.vector_of (source, lanes);
				var to = types.vector_of (destination, lanes);
				if (from == null || to == null) {
					continue;
				}
				shapes++;
				assert (IntegerConversion.accepts (from, to));
				string s = from.display_name ();
				string d = to.display_name ();
				functions.append_printf ("%s c%d(%s x){return x as %s;}\n", d, index, s, d);
				functions.append_printf ("int t%d(){\n", index);
				uint64 random = 0x1badf00d;
				var bits = patterns (source);
				for (int row = 0; row < 12; row++) {
					var a = new StringBuilder ();
					var b = new StringBuilder ();
					var expected = new StringBuilder ();
					var mask = new StringBuilder ();
					var permutation = new StringBuilder ();
					for (int lane = 0; lane < lanes; lane++) {
						random = (random * 1664525 + 1013904223) & 0xffffffff;
						uint64 pattern = row < 6 ? bits[(row * lanes + lane) % bits.length] : random & source.mask;
						var value = AstraIntegerValue.from_bits (source, pattern);
						qualify (source, destination, pattern);
						if (lane > 0) {
							a.append (",");
							b.append (",");
							expected.append (",");
							mask.append (",");
						}
						a.append (value.to_string ());
						b.append (AstraIntegerValue.from_bits (source, source.mask ^ pattern).to_string ());
						expected.append (value.convert_to (destination).to_string ());
						mask.append (lane % 2 == 0 ? "true" : "false");
						permutation.append_printf (",%d", (lanes - lane + row) % lanes);
						vector_checks++;
					}
					functions.append_printf ("\t%s a%d={%s};%s b%d={%s};%s e%d={%s};bool<%d> m%d={%s};\n", s, row, a.str, s, row, b.str, d, row, expected.str, lanes, row, mask.str);
					functions.append_printf ("\t%s r%d=c%d(a%d);if(!all(r%d==e%d)){return 1;}\n", d, row, index, row, row, row);
					functions.append_printf ("\tif(r%d[0]!=e%d[0] || r%d[%d]!=e%d[%d]){return 2;}\n", row, row, row, lanes - 1, row, lanes - 1);
					functions.append_printf ("\tif(!all((shuffle(a%d%s) as %s)==shuffle(a%d as %s%s))){return 3;}\n", row, permutation.str, d, row, d, permutation.str);
					functions.append_printf ("\tif(!all((select(m%d,a%d,b%d) as %s)==select(m%d,a%d as %s,b%d as %s))){return 4;}\n", row, row, row, d, row, row, d, row, d);
					if (destination.bit_width >= source.bit_width) {
						functions.append_printf ("\tif(!all((r%d as %s)==a%d)){return 5;}\n", row, s, row);
					}
					vector_cases++;
				}
				functions.append ("\treturn 0;\n}\n");
				calls.append_printf ("\tif(t%d()!=0){return 2;}\n", index++);
			}
		}
	}
	assert (shapes == 92);
	calls.append ("\treturn 0;\n}\n");
	stdout.printf ("// oracle scalar_checks=%u vector_shapes=%u vector_cases=%u vector_lane_checks=%u\n%s%s", scalar_checks, shapes, vector_cases, vector_checks, functions.str, calls.str);
}

int main(string[] args) {
	if (args.length == 2 && args[1] == "--emit-runtime") {
		exhaustive ();
		wider ();
		authority ();
		emit_runtime ();
		return 0;
	}
	Test.init (ref args);
	Test.add_func ("/iconv/integer-value/exhaustive-i8-u8-all-destinations", exhaustive);
	Test.add_func ("/iconv/integer-value/wider-boundaries-properties", wider);
	Test.add_func ("/iconv/integer-value/exact-capability", authority);
	return Test.run ();
}
}
