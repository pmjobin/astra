#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Characterize real original UTF8/builder/formatter/shared source under C0."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def corpus():
	rows = {}
	for name, data, text in [('empty', [], '""'), ('ASCII', [65, 90], '"AZ"'), ('multibyte', [226, 130, 172, 240, 159, 152, 128], '"€😀"'), ('NUL', [65, 0, 66], '"A\\0B"')]:
		body = 'var bytes = new u8['+str(len(data))+']; '+''.join('bytes['+str(i)+'] = '+str(value)+'; ' for i, value in enumerate(data))
		rows['UTF8-'+name] = (False, 'int main() { try { '+body+'var result = utf8_message(bytes); if (result.text == '+text+') return 42; return 3; } catch (InvalidUtf8 caught) { return 4; } }\n')
	for name, data in [('truncated', [194]), ('continuation', [128]), ('overlong-two', [192, 128]), ('overlong-three', [224, 128, 128]), ('surrogate', [237, 160, 128]), ('out-of-range', [244, 144, 128, 128]), ('invalid-leader', [245, 128, 128, 128]), ('truncated-four', [240, 159, 152])]:
		body = 'var bytes = new u8['+str(len(data))+']; '+''.join('bytes['+str(i)+'] = '+str(value)+'; ' for i, value in enumerate(data))
		rows['UTF8-'+name] = (True, 'int main() { try { '+body+'var result = utf8_message(bytes); return 3; } catch (InvalidUtf8 caught) { if (caught.message == "invalid UTF-8") return 42; return 4; } }\n')
	rows['builder-growth'] = (False, 'int main() { try { var output = new Utf8ByteBuilder(); if (output.capacity() != 0) return 3; if (output.reserve(0 - 1)) return 4; if (!output.reserve(1)) return 5; var bytes = new u8[1]; bytes[0] = 65; if (!output.append_bytes(bytes)) return 6; var first = output.snapshot(); bytes[0] = 66; if (!output.append_bytes(bytes)) return 7; if (!output.reserve(33)) return 8; if (!output.append_bytes(bytes)) return 9; var last = output.snapshot(); if (first.text != "A") return 10; if (last.text != "ABB") return 11; if (output.byte_count() != 3) return 12; return 42; } catch (Error caught) { return 13; } }\n')
	rows['formatter-extremes'] = (False, 'int main() { try { var output = new Utf8ByteBuilder(); append_int(output, 0 - 2147483647 - 1); append_int(output, 2147483647); append_int(output, 0); append_int(output, 0 - 42); var result = output.snapshot(); if (result.text == "-214748364821474836470-42") return 42; return 3; } catch (Error caught) { return 4; } }\n')
	rows['original-flow-number'] = (False, 'int main() { try { var output = new Utf8ByteBuilder(); flow_number(output, 42); var result = output.snapshot(); if (result.text == " 42") return 42; return 3; } catch (Error caught) { return 4; } }\n')
	rows['shared-SourceSpan'] = (False, 'int main() { try { var bytes = new u8[3]; bytes[0] = 65; bytes[1] = 66; bytes[2] = 67; var source = source_buffer("./path", move bytes, false); var shared = shared_acquire(move source); var retained = shared_clone(shared); var first = new SourceSpan(move retained, 0, 1); var last_handle = shared_clone(shared); var last = new SourceSpan(move last_handle, 1, 3); var cover = first.cover(last); var content = cover.bytes(); var path = cover.path(); var location = cover.location(); if (len(content) != 3) return 3; if (content[2] != 67) return 4; if (path.text != "path") return 5; if (location.line != 1) return 6; return 42; } catch (Error caught) { return 7; } }\n')
	return rows


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r5_original_oracles_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('original-oracles-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	original = read(paths.RUNTIME/('original-before-'+a.mode)/'result.json'); dependencies = [Path(row['path']) for row in original['inputs'][2:]]; assert all(sha(row['path']) == row['sha256'] for row in original['inputs'])
	providers = [paths.BUILD.parent/('effects25-r4/full-final16-'+a.mode)/(name+'.o') for name in ('args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap')]
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stderr[-2500:]); return r
	for name, (error, text) in corpus().items():
		source = leaf/(name+'.astra'); source.write_text(text); inputs = [source, *dependencies]
		if name == 'original-flow-number': inputs.insert(1, Path(original['inputs'][0]['path']))
		exe = build/name; run([C0, '-'+a.mode, *inputs, *[word for path in providers for word in ('--link-object', path)], '-o', exe], name+'-build'); run([exe], name+'-execute', (42,)); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
		rows.append(dict(name=name, actual_InvalidUtf8=error, source_sha256=sha(source), inputs=[dict(path=str(p), sha256=sha(p)) for p in inputs], ELF_sha256=sha(exe), actual_exit=42)); (leaf/'result.json').write_text(json.dumps(dict(status='ORIGINAL_C0_ORACLES', profile=a.mode, programs=rows, Astra_native_credit=0, limitation='Real unchanged complete original dependencies. C0 execution and unsuppressed returning Valgrind establish independent policy and observations only; no Astra-native credit.'), indent=2)+'\n'); print(a.mode, name, 'original C0 execution and memory pass', flush=True)


if __name__ == '__main__':
	main()
