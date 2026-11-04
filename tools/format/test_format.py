"""Positive, mutation and publication controls for the source formatter."""
import sys
sys.dont_write_bytecode = True
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest

from lanes import python_format, python_guard, meson_format, meson_guard, stable_format, run, guard, enum_indentation
from lexical import compare, attach_clauses, expand_accessors
from preprocess import compare_preprocessed
from source import read_source, publish, safe_parent, ROOT, qualified_tools, receipt_path


class Guards(unittest.TestCase):
	def test_enum_continuation_tabs(self):
		before = b'enum Role { FIRST,\n            SECOND = 2,\n            THIRD };\nvoid work() {\n\tenum Inner { ONE,\n                 TWO };\n}\nconst char *text = "enum Fake { SAME, OTHER }";\n'
		after = enum_indentation(before)
		self.assertIn(b'\n\t        SECOND', after)
		self.assertIn(b'\n\t\t         TWO', after)
		self.assertEqual(before.expandtabs(4), after.expandtabs(4))
		self.assertEqual(after, enum_indentation(after))
		compare(before, after)
		self.assertIn(b'"enum Fake { SAME, OTHER }"', after)

	def test_vala_whitespace_and_clauses(self):
		before = b'void f() { try { g(); }\ncatch (Error e) { g(); }\nfinally { g(); } }\n'
		after = attach_clauses(before)
		self.assertIn(b'} catch', after)
		self.assertIn(b'} finally', after)
		compare(before, after)
		self.assertEqual(after, attach_clauses(after))

	def test_real_astra_scopes_and_mutations(self):
		tools, unused = qualified_tools({'astra'})
		before = b'struct A { int x; }\n// next\nstruct B { int y; }\nint f(int x) { if (x > 0) { return x; } return 0; }\n'
		after = stable_format('astra', before, 'unit.astra', ROOT, tools)
		self.assertIn(b'}\n\n// next\nstruct B', after)
		self.assertIn(b'if (x > 0) return x;', after)
		for mutant in (after.replace(b'return 0;', b'return 1;'), after.replace(b'// next', b'// wrong')):
			with self.assertRaises(ValueError):
				guard('astra', before, mutant, 'unit.astra', tools)

	def test_clause_comments_and_literals(self):
		before = b'void f() { try {} // remain\ncatch (Error e) { string s = "} finally"; } /* stay */\nfinally {} }'
		self.assertEqual(attach_clauses(before), before)

	def test_vala_mutations(self):
		before = b'#if A \\\n+ && B\nowned X? f() { /* exact */ return @"x $(a >> 2)"; }\n#endif\n'
		for a, b in [(b'owned', b'unowned'), (b'X?', b'X'), (b'>>', b'<<'), (b'2', b'3'), (b'exact', b'other'), (b'A', b'C')]:
			with self.subTest(a=a), self.assertRaises(ValueError):
				compare(before, before.replace(a, b))

	def test_accessors(self):
		before = b'class X { int a { get { work(); return n; } set { n = value; } } }'
		after = expand_accessors(before)
		compare(before, after)
		self.assertIn(b'work();\n', after)
		self.assertIn(b'set { n = value; }', after)

	def test_python_indentation(self):
		before = b'#!/usr/bin/python3\n# coding: utf-8\n@decorator\ndef f():\n    x = r"raw\\n"\n    s = """payload\n    exact\n"""\n    if x:\n        return (x,\n                s) # type: ignore\n'
		after = python_format(before)
		python_guard(before, after)
		self.assertIn(b'\n\tif x:\n\t\treturn', after)
		self.assertIn(b'payload\n    exact\n', after)
		self.assertEqual(after, python_format(after))
		for mutant in (after.replace(b'raw', b'RAW'), after.replace(b'\t\treturn', b'\treturn'), after.replace(b'type: ignore', b'changed')):
			with self.assertRaises((ValueError, SyntaxError)):
				python_guard(before, mutant)

	def test_meson(self):
		before = b"if a\n    f(\n        'exact', # comment\n        '''raw\n    payload''')\nendif\n"
		after = meson_format(before)
		meson_guard(before, after)
		self.assertIn(b'\n\tf(', after)
		self.assertIn(b'raw\n    payload', after)
		self.assertEqual(after, meson_format(after))
		with self.assertRaises(ValueError):
			meson_guard(before, after.replace(b'comment', b'changed'))

	def test_atomic_modes_unchanged_and_concurrency(self):
		with tempfile.TemporaryDirectory() as tmp:
			root = Path(tmp)
			path = root/'unit.py'
			path.write_bytes(b'x = 1\n')
			path.chmod(0o751)
			before, metadata = read_source(root, 'unit.py')
			self.assertEqual(metadata, path.stat())
			publish(root, 'unit.py', before, metadata, b'x =  1\n')
			self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o751)
			before, metadata = read_source(root, 'unit.py')
			path.write_bytes(b'concurrent\n')
			with self.assertRaises(ValueError):
				publish(root, 'unit.py', before, metadata, b'wrong\n')
			self.assertEqual(path.read_bytes(), b'concurrent\n')
			self.assertEqual(sorted(p.name for p in root.iterdir()), ['unit.py'])
			(root/'link').symlink_to(path)
			with self.assertRaises(OSError):
				read_source(root, 'link')
			(root/'parent').symlink_to(root, target_is_directory=True)
			with self.assertRaises(OSError):
				read_source(root, 'parent/unit.py')
			for name in ('../outside', '/etc/passwd', './unit.py'):
				with self.assertRaises(ValueError):
					safe_parent(root, name)

	def test_tool_failures(self):
		with self.assertRaises(FileNotFoundError):
			run(['/nonexistent/astra-formatter'])
		with self.assertRaises(ValueError):
			run([sys.executable, '-c', 'import sys;sys.stderr.write("unknown option");sys.exit(0)'])
		with self.assertRaises(Exception):
			run([sys.executable, '-c', 'import time;time.sleep(5)'], timeout=0.01)

	def test_real_vala(self):
		tools, unused = qualified_tools({'vala'})
		before = b'class Example : Object { public int x { get { work(); return 1; } } void work() { try { work(); }\ncatch (Error e) { work(); }\nfinally { work(); } } }\n'
		after = stable_format('vala', before, 'unit.vala', ROOT, tools)
		self.assertIn(b'} catch', after)
		self.assertIn(b'} finally', after)

	def test_zero_exit_literal_mutation(self):
		with tempfile.TemporaryDirectory() as tmp:
			tool = Path(tmp)/'mutant'
			tool.write_text('#!/usr/bin/env python3\nimport sys\nsys.stdout.buffer.write(sys.stdin.buffer.read().replace(b"exact",b"wrong"))\n')
			tool.chmod(0o700)
			with self.assertRaises(ValueError):
				stable_format('c', b'int f() { return "exact"[0]; }\n', 'unit.c', ROOT, {'clang-format': str(tool)})

	def test_assert_mapping_is_narrow(self):
		x = b'assert(x);\n'
		y = b'\nassert(x);\n'
		before = b'__assert_fail("x", "old.c", 1, __PRETTY_FUNCTION__); int value = 7;'
		after = b'__assert_fail("x", "new.c", 2, __PRETTY_FUNCTION__); int value = 7;'
		self.assertEqual(len(compare_preprocessed(before, after, x, y, 'old.c', 'new.c')), 1)
		for mutant in (after.replace(b'value = 7', b'value = 8'), after.replace(b'"x"', b'"y"'), after.replace(b', 2,', b', 3,')):
			with self.assertRaises(ValueError):
				compare_preprocessed(before, mutant, x, y, 'old.c', 'new.c')

	def test_check_output_and_malformed_input(self):
		with self.assertRaises(ValueError):
			receipt_path(ROOT/'format/scope.json')
		with tempfile.TemporaryDirectory() as tmp:
			path = Path(tmp)/'receipt.json'
			self.assertEqual(receipt_path(path), path)
			path.symlink_to(ROOT/'format/scope.json')
			with self.assertRaises(ValueError):
				receipt_path(path)
		for bad in (b'/* unterminated', b'"unterminated', b'"""unterminated'):
			with self.assertRaises(ValueError):
				compare(bad, bad)


if __name__ == '__main__':
	unittest.main()
