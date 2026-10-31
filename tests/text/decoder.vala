// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Text;

namespace Astra.Tests.TextDecoder {
[CCode (cname = "g_unichar_to_utf8", cheader_filename = "glib.h")]
private static extern int oracle_encode(unichar scalar, char* output);
private void scalars() {
	// GLib's independent scalar encoder is the byte oracle. Production
	// decoding/validation uses explicit scalar arithmetic, including NUL.
	uint checked = 0;
	for (uint32 scalar = 0; scalar <= 0x10ffff; scalar++) {
		if (scalar >= 0xd800 && scalar <= 0xdfff) {
			continue;
		}
		string spelling = "\"\\U%08x\"".printf (scalar);
		var file = new SourceFile.from_text ("scalar.astra", spelling);
		int offset = 1;
		var decoder = new TextLiteralDecoder ();
		var payload = decoder.decode (file, 0, ref offset);
		assert (payload != null && decoder.diagnostic == null && payload.valid () && offset == file.length);
		char[] expected = new char[6];
		int length = oracle_encode ((unichar) scalar, expected);
		assert (payload.byte_length == length);
		for (int i = 0; i < length; i++) {
			assert (payload.byte_at (i) == (uint8) expected[i]);
		}
		checked++;
	}
	assert (checked == 1112064);
}
private void immutable() {
	uint8[] input = {
		'a', 0, 'b'
	};
	var payload = new TextBytes (input);
	input[2] = 'c';
	assert (payload.valid () && payload.byte_length == 3 && payload.hex () == "610062");
	assert (payload.equal_content (new TextBytes ({'a', 0, 'b'})) && !payload.equal_content (new TextBytes (input)));
	assert (!new TextBytes ({1}, 2147483648L).valid ());
	assert (!new TextBytes ({1}, -2).valid ());
	assert (!new TextBytes ({1}, 0).valid ());
	assert (!new TextBytes ({0xed, 0xa0, 0x80}).valid ());
	assert (!new TextBytes ({0xc0, 0x80}).valid ());
	assert (!new TextBytes ({0xf4, 0x90, 0x80, 0x80}).valid ());
	assert (!new TextBytes ({0x80}).valid ());
	assert (!new TextBytes ({0xe0, 0xa0}).valid ());
	assert (new TextBytes ({0xef, 0xbb, 0xbf, 0xef, 0xbf, 0xbf}).valid ());
}
private void origins() {
	var graph = new TextOrigins ();
	var literal = new Object ();
	var cycle = new Object ();
	var join = new Object ();
	graph.literal (literal);
	graph.copy (cycle, cycle);
	graph.copy (join, literal);
	graph.copy (join, cycle);
	assert (!graph.is_static (join));
	graph.copy (cycle, literal);
	assert (graph.is_static (join));
	graph.copy (join, new Object ());
	assert (!graph.is_static (join));
}
private void spans_and_escapes() {
	string spelling = "\"é\\\"\\\\\\n\\r\\t\\0after\"";
	var file = new SourceFile.from_text ("escapes.astra", " \r\n" + spelling + " next");
	var lexer = new Lexer (file);
	var token = lexer.next_token ();
	assert (token.kind == TokenKind.TEXT && token.span.file == file && token.span.start == 3 && token.span.end == 3 + spelling.length);
	assert (token.spelling () == spelling && token.text_payload.hex () == "c3a9225c0a0d09006166746572" && token.text_payload.byte_length == 13);
	var name = lexer.next_token ();
	assert (name.kind == TokenKind.IDENTIFIER && name.spelling () == "next" && name.span.start == 4 + spelling.length);
	assert (lexer.next_token ().kind == TokenKind.EOF && lexer.diagnostic == null);
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text/decoder/all-unicode-scalars", scalars);
	Test.add_func ("/text/decoder/immutable-malformed-bounded-payload", immutable);
	Test.add_func ("/text/provenance/grounded-fixpoint", origins);
	Test.add_func ("/text/decoder/spans-and-short-escapes", spans_and_escapes);
	return Test.run ();
}
}
