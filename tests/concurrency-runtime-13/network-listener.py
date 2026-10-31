# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Astra listening/accepting/framing with concurrent independently compiled C peers."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def program(template, clients, seed):
	lines = [template, 'async void serve(owned TcpSocket listener) throws Error{',
		'int port=listener.local_port();bool busy=false;',
		'{var duplicate=new TcpSocket();duplicate.open();try{duplicate.listen(port,2);}catch(SocketError error){if(error.code!=-98){throw;}busy=true;}}',
		'if(!busy){throw new Error("missing busy endpoint");}',
		f'listener_oracle_start(port,{clients},{seed});int started=astra_net_milliseconds();']
	for i in range(clients):
		lines += [f'var s{i}=new TcpSocket();while(!listener.accept_into(s{i})){{network_deadline(started,10000);await delay_ticks(1);}}',
			f'var t{i}=serve_connection(move s{i},{seed});start(t{i});']
		if i < clients - 1:
			lines += ['try{']
	for i in reversed(range(clients)):
		lines += [f'int r{i}=await move t{i};if(r{i}<1 || r{i}>{clients}){{throw new Error("client result");}}']
		if i > 0:
			lines += [f'}}catch(Error error){{await cancel_and_join(move t{i-1});throw;}}']
	lines += ['await refused_connection();}', 'export(C) int run_listener(){try{',
		'var listener=new TcpSocket();listener.open();listener.listen(0,16);var executor=ThreadedExecutor.open(4);var status=executor.run(serve(move listener));',
		'match(status){case ThreadedStatus.Completed():{}else:{return 81;}}',
		f'}}catch(Error error){{return 82;}}return listener_oracle_finish({clients});}}', 'int main(){return run_listener();}']
	return '\n'.join(lines) + '\n'


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-network-listener')
	here = Path(__file__).parent
	common = [ROOT / 'lib/astra/hosted/network.astra', ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra', ROOT / 'lib/astra/text/utf8-message.astra']
	providers = [ROOT / 'lib/runtime/async/threaded.c', ROOT / 'lib/runtime/platform/text-posix.c', ROOT / 'lib/runtime/platform/network-posix.c', here / 'network-oracle.c', here / 'network-listener-oracle.c']
	flags = ['-Wl,--wrap=' + name for name in ['socket', 'accept4', 'close', 'send', 'recv']]
	entry = e.output / 'entry.c'
	entry.write_text('extern int run_listener(void);int main(void){return run_listener();}\n')
	for clients in [2, 4, 8]:
		for seed in [1, 17]:
			source = e.output / f'listener-{clients}-{seed}.astra'
			source.write_text(program((here / 'network-listener.astra').read_text(), clients, seed))
			expected = f'Astra TCP listener: {clients} concurrent peers, exact binary frames, refused connect, busy bind, bounded buffers, all sockets closed\n'
			for level in ['O0', 'O1', 'O2']:
				obj = source.with_suffix('.' + level + '.o'); product = source.with_suffix('.' + level)
				e.run([e.compiler, '-' + level, '-c', source, *common, '-o', obj])
				e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, entry, *flags, '-o', product])
				e.run([product], stdout=expected, timeout=30)
				e.files(obj, product)
			e.files(source)
	source = e.output / 'listener-4-17.astra'
	expected = 'Astra TCP listener: 4 concurrent peers, exact binary frames, refused connect, busy bind, bounded buffers, all sockets closed\n'
	for sanitizer in ['address', 'thread']:
		instrument(e, 'listener', [source, *common], providers, expected, sanitizer, flags)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'listener-8-17.O2'],
		stdout='Astra TCP listener: 8 concurrent peers, exact binary frames, refused connect, busy bind, bounded buffers, all sockets closed\n', contains='ERROR SUMMARY: 0 errors', timeout=60)
	trace = e.output / 'listener.strace'
	e.run(['strace', '-f', '-o', trace, '-e', 'trace=socket,bind,listen,connect,getsockopt,accept4,sendto,recvfrom,shutdown,close,poll', e.output / 'listener-4-17.O2'], stdout=expected, timeout=30)
	for token in ['listen(', 'accept4(', 'connect(', 'EADDRINUSE', 'ECONNREFUSED', 'sendto(', 'recvfrom(']:
		assert token in trace.read_text(), token
	e.files(*providers, *common, here / 'network-listener.astra', Path(__file__), entry, trace)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
