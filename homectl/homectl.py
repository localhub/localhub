#!/usr/bin/env python3
import socket, os, sys, json, inspect, formatter

class HomedClient(object):
	def __init__(self):
		sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
		sock.connect('/tmp/homed.{uid}.sock'.format(uid=os.getuid()))
		self.connection = sock.makefile('rw')
		self.recv = self.__recv()

	def __recv(self):
		for msg in self.connection:
			yield json.loads(msg)

	def __send(self, msg):
		self.connection.write(json.dumps(msg))
		self.connection.write('\n')
		self.connection.flush()

	def __until(self, message_type):
		for message in self.recv:
			yield message
			if message["type"] == message_type: break

	@classmethod
	def commands(cls):
		for name in cls.__dict__:
			if name[:4] == 'cmd_':
				fn = getattr(cls, name)
				yield (name[4:], fn.__doc__, inspect.getargspec(fn).args[1:])

	def cmd_list(self):
		"List jobs"
		self.__send({ 'command': 'list' })
		return self.__until("job_list")

	def cmd_shutdown(self):
		"Shut down homed"
		self.__send({ 'command': 'shutdown' })
		return self.__until("bye")

	def cmd_restart(self, job):
		"Restart a job"
		pass

def usage():
	return (
		"usage: homectl \033[4mcommand\033[0m [\033[4marguments\033[0m...]\n"
		"\n"
		"  Interface to control homed (https://github.com/Sidnicious/homed)\n"
		"\n"
		"commands:\n" + "\n".join(
			"  homectl {}{} - {}".format(
				command[0],
				(
					(" " + " ".join("\033[4m" + arg + "\033[0m" for arg in command[2]))
					if command[2] else ""
				),
				command[1]
			) for command in HomedClient.commands()
		)
	)

if __name__ == "__main__":
	command_line = sys.argv[1:]

	if not command_line:
		print(usage(), file=sys.stderr)
		sys.exit(1)

	command, *args = sys.argv[1:]

	try:
		client = HomedClient()
	except socket.error as e:
		print("Couldn’t connect. Is homed running?", file=sys.stderr)
		sys.exit(2)
	
	method = getattr(client, 'cmd_' + command, None)
	if method is None:
		print(usage(), file=sys.stderr)
		sys.exit(1)
	for line in method(*args): print(formatter.format(line))
