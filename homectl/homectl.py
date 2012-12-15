#!/usr/bin/env python3
import socket, os, sys, json

class HomedClient(object):
	def __init__(self):
		sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
		sock.connect('/tmp/homed.{uid}.sock'.format(uid=os.getuid()))
		self.connection = sock.makefile('rw')

	def __sendCommand(self, command):
		self.connection.write(json.dumps(command))
		self.connection.write('\n')
		self.connection.flush()
		return json.loads(self.connection.readline())
	def listJobs(self):
		return self.__sendCommand({ 'command': 'list' })["jobs"]

if __name__ == "__main__":
	import argparse

	commands = {
		'list': HomedClient.listJobs
	}


	parser = argparse.ArgumentParser(
		formatter_class=argparse.RawDescriptionHelpFormatter,
		description="Interface to control homed (https://github.com/Sidnicious/homed)",
		epilog="""
commands:
  list: list jobs
""",
	)
	parser.add_argument('command', metavar='command', choices=commands.keys())
	args = parser.parse_args()

	try:
		client = HomedClient()
	except socket.error as e:
		print("Couldn’t connect. Is homed running?", file=sys.stderr)
		sys.exit(1)
	print(commands[args.command](client))
