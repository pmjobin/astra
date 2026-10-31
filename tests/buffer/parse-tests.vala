// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.BufferParser {
private void positive() {
	foreach (string source in new string[] {
			"owned f64[] make(int n){return new f64[n];}",
			"void f(owned f64[] a){a=new f64[3];}",
			"void f(){owned f64[] a=new f64[3];owned f64[] b=move a;a=move b;}",
			"class C{owned f64[] a;init(int n){this.a=new f64[n];this.a[0]=1.0;}}",
			"void f(){owned void*[] a=new void*[3];owned f32<4>[] b=new f32<4>[3];}",
			"void f(){owned bool<16>[] a=new bool<16>[0];}",
			"int new(){return 3;} int f(){return new();}"
		}) {
		var result = Parser.parse(new SourceFile.from_text("buffer", source));
		if (result.diagnostic != null) {
			GLib.error("%s", result.diagnostic.format());
		}
		assert(result.unit != null);
	}
}
private void negative() {
	foreach (string source in new string[] {
			"void f(){f64 owned[] a=new f64[3];}",
			"void f(){owned[] f64 a=new f64[3];}",
			"void f(){owned f64[] a=new f64[];}",
			"void f(){owned f64[] a=new f64[1,2];}",
			"void f(){owned f64[] a=new owned f64[3];}",
			"void f(){owned f64[] a=new f64[3;}",
			"class C{owned f64[] a;init(){owned f64[] b=move this.a;}}"
		}) {
		assert(Parser.parse(new SourceFile.from_text("buffer-invalid", source)).diagnostic != null);
	}
}
int main(string[] args) {
	Test.init(ref args);
	Test.add_func("/buffer/parser/owned-bindings-parameters-results-fields-and-new", positive);
	Test.add_func("/buffer/parser/malformed-placement-and-allocation", negative);
	return Test.run();
}
}
