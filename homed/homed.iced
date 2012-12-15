fs = require 'fs'
util = require 'util'
net = require 'net'
readline = require 'readline'
events = require 'events'
path = require 'path'
child_process = require 'child_process'

class Homed
	constructor: (@jobsDir) ->
		events.EventEmitter.call this
	
	util.inherits Homed, events.EventEmitter

	start: () ->
		@jobs = {}

		@syncJobs()
		fs.watch @jobsDir, (event, filename) => @syncJobs()

		@controlPath = '/tmp/homed.' + process.getuid() + '.sock'
		@controlServer = new net.Server

		fs.unlinkSync @controlPath if fs.existsSync @controlPath
		process.umask 0o77
		@controlServer.listen @controlPath
		@controlServer.on 'connection', @onConnection.bind this

	shutDown: () ->
		@controlServer.close()

	loadJobDirectory: (id, dir) ->
		if id of @jobs
			throw new Exception "Shit, already had a job named " + id
		runfile = path.join dir, 'run'
		await fs.exists runfile, defer(exists)
		if not exists
			@emit 'warning', "Job at " + dir + " doesn’t have a run file, ignoring"
			return
		@jobs[id] =
			dir: dir
			child: child = child_process.spawn(
				runfile,
				[],
				{ stdio: ['ignore', 1, 2] }
			)
		console.log "Started " + id + " (pid " + child.pid + ")"



	unloadJobDirectory: (jobDir) ->
		console.log "TODO: unload the job in " + jobDir
		delete @jobs[jobDir]

	syncJobs: () ->
		goneJobs = {}
		goneJobs[job] = null for job in Object.keys @jobs
		try
			jobDirectories = fs.readdirSync @jobsDir
		catch e
			@emit "error", e
			return false

		for job in jobDirectories
			if !(job of @jobs)
				@loadJobDirectory job, path.join @jobsDir, job
			delete goneJobs[job]

		@unloadJobDirectory path.join @jobsDir, job for job in Object.keys goneJobs

		return true


	onConnection: (sock) ->
		new HomedClient @, sock

class HomedClient
	constructor: (@homed, @sock) ->
		sock.setEncoding 'utf-8'
		i = readline.createInterface sock, sock
		i.on 'line', (line) =>
			try
				obj = JSON.parse line
			catch e
				console.log "Couldn’t parse message, closing connection with this client"
				sock.destroy()
			@recv obj

	send: (msg) ->
		@sock.write JSON.stringify(msg)
		@sock.write '\n'

	recv: (msg) ->
		method = 'cmd_' + (msg.command || '')
		if not method of @ then method = 'cmd_unknown'
		@[method] msg
	
	cmd_list: (msg) ->
		@send {
			command: "list",
			"jobs": @homed.jobs
		}
# - - -

args = process.argv[2..]
if not args.length
	process.stderr.write "usage: homed job_directory\n"
	process.exit -1

homed = new Homed args[0]

homed.on "error", (error) ->
	util.error error
	process.exit 1

homed.on "warning", (error) ->
	util.error error

homed.start()

process.on 'SIGINT', () ->
	process.exit()

process.on 'exit', () ->
	homed.shutDown()
