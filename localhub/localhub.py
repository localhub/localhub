#!/usr/bin/env python3
import socket, os, sys, json, inspect, formatter

class LocalhubClient(object):
	def __init__(self):
		sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
		sock.connect('/tmp/localhub.{uid}.sock'.format(uid=os.getuid()))
		self.connection = sock.makefile('rw')
		self.recv = self.__recv()

	def __recv(self):
		for msg in self.connection:
			yield json.loads(msg)

	def __send(self, msg):
		self.connection.write(json.dumps(msg))
		self.connection.write('\n')
		self.connection.flush()

	@classmethod
	def commands(cls):
		for name in cls.__dict__:
			if name[:4] == 'cmd_':
				fn = getattr(cls, name)
				yield (name[4:], fn.__doc__, inspect.getargspec(fn).args[1:])

	def cmd_list(self):
		"List jobs"
		self.__send({ 'command': 'list' })
		yield next(self.recv)

	def cmd_restart(self, job):
		"Restart a job"
		self.__send({
			'command': 'restart',
			'job': job
		})
		yield next(self.recv)

	def cmd_stop(self, job):
		"Stop a job"
		self.__send({
			'command': 'stop',
			'job': job
		})
		yield next(self.recv)

	def cmd_start(self, job):
		"Start a job"
		self.__send({
			'command': 'start',
			'job': job
		})
		yield next(self.recv)

def usage():
	return (
		"usage: localhub \033[4mcommand\033[0m [\033[4marguments\033[0m...]\n"
		"\n"
		"  https://github.com/localhub/localhub\n"
		"\n"
		"commands:\n" + "\n".join(
			"  localhub {}{} - {}".format(
				command[0],
				(
					(" " + " ".join("\033[4m" + arg + "\033[0m" for arg in command[2]))
					if command[2] else ""
				),
				command[1]
			) for command in LocalhubClient.commands()
		)
	)

if __name__ == "__main__":
	command_line = sys.argv[1:]

	if not command_line:
		print(usage(), file=sys.stderr)
		sys.exit(1)

	command, *args = sys.argv[1:]

	try:
		client = LocalhubClient()
	except socket.error as e:
		print("Couldn’t connect. Is localhubd running?", file=sys.stderr)
		sys.exit(2)
	
	method = getattr(client, 'cmd_' + command, None)
	if method is None:
		print(usage(), file=sys.stderr)
		sys.exit(1)
	for message in method(*args):
		for line in formatter.format(message):
			print(line)
