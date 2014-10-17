'use strict'
fs = require 'fs'
util = require 'util'
net = require 'net'
readline = require 'readline'
events = require 'events'
path = require 'path'
child_process = require 'child_process'
http = require 'http'
httpProxy = require 'http-proxy'
proxy = httpProxy.createProxyServer()

# Colors!
red   = '\u001b[31m'
reset = '\u001b[0m'

timeout = (timeout, cb) ->
	fired = false
	setTimeout () ->
		fired = true
		cb true
	return () ->
		return if fired
		fired = true
		cb.apply undefined, [false].concat arguments

class Homed
	@Job: class Job
		constructor: (@id, @dir, runfile) ->
			@started = true
			@runningSince = new Date
			@child = child_process.spawn(
				runfile, [], {
					detached: true,
					stdio: ['ignore', null, null, 'pipe']
				}
			)
			@child.on 'exit', @onExit.bind(this)

			controlSock = @child.stdio[3]
			@control = readline.createInterface controlSock, controlSock
			@control.on 'line', (line) =>
				try
					line = JSON.parse line
				catch
					return
				@recv line

		stop: (cb) ->
			# Fairly undocumented/unsupported: Kill the child's whole
			# process group, we gave it one
			console.log "Killing " + @id + " (pid " + @child.pid + ")"
			@started = false
			@runningSince = null
			process.kill(-@child.pid)
			@child.on 'exit', (code, signal) ->
				clearTimeout killTimeout
				console.log "Child exited with code " + code + ", signal " + signal
				cb()
			await killTimeout = setTimeout defer(), 10000
			console.log('hard-killing', @child.pid)
			process.kill(-@child.pid, 'SIGKILL')

		toJSON: () -> { id: this.id }

		recv: (message) ->
			for k, v of message then switch k
				when "proxy"
					@proxy = v


		onExit: (code, signal) ->
			console.log "Hey, just FYI my job exited with " + code + " " + signal

	constructor: (@jobsDir) ->
		events.EventEmitter.call this
	
	util.inherits Homed, events.EventEmitter

	start: () ->
		hostRe = /^[^.]+/

		findJob = (req) =>
			job = null
			match = req.headers.host.match hostRe
			if match
				job = @jobs[match[0]]

			if not job or not job.proxy
				return null
			return job

		@proxyServer = http.createServer (req, res) =>
			if job = findJob req
				proxy.web req, res, { target: { port: job.proxy } }
			else
				res.writeHead 404
				res.end 'Service not found'
				return

		@proxyServer.on 'upgrade', (req, socket, head) =>
			if job = findJob req
				proxy.ws req, socket, head, {
					target: { port: job.proxy }
				}
			else
				socket.close()


		@proxyServer.listen 4000

		@jobs = {}

		@syncJobs()
		@watcher = fs.watch @jobsDir, (event, filename) => @syncJobs()

		@controlPath = '/tmp/homed.' + process.getuid() + '.sock'
		@controlServer = new net.Server

		fs.unlinkSync @controlPath if fs.existsSync @controlPath
		process.umask 0o77
		@controlServer.listen @controlPath
		@controlServer.on 'connection', @onConnection.bind this

	shutDown: (cb) ->
		if @controlServer
			@controlServer.close()
			@controlServer = null
		if @watcher
			@watcher.close()
			@watcher = null
		await
			for job of @jobs
				@jobs[job].stop defer()
		@jobs = {}
		if cb then cb()
		null

	loadJobDirectory: (id, dir) ->
		if id of @jobs
			throw new Exception "Shit, already had a job named " + id
		runfile = path.join dir, 'run'
		await fs.exists runfile, defer(exists)
		if not exists
			@emit 'warning', "Job at " + dir + " doesn’t have a run file, ignoring"
			return
		@jobs[id] = job = new Job(id, dir, runfile)
		console.log "Started " + id + " (pid " + job.child.pid + ")"

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
			stats = fs.statSync (path.join @jobsDir, job)
			if not stats.isDirectory() then continue
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
			type: "job_list",
			"jobs": @homed.jobs
		}
	cmd_shutdown: (msg) ->
		@send {
			"type": "info",
			"message": "Shutting down…"
		}
		await @homed.shutDown(defer())
		@send { type: "bye" }

# - - -

process.title = 'homed'
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
