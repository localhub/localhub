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
USER = (require 'pwuid')()
PREFIX = path.join USER.dir, '.localhub'

proxy.on 'error', (e) ->
	console.log 'Proxy error:', e

timeout = (timeout, cb) ->
	fired = false
	setTimeout () ->
		fired = true
		cb true
	return () ->
		return if fired
		fired = true
		cb.apply undefined, [false].concat arguments

class Localhubd
	@Job: class Job
		constructor: (@id, @dir) ->

		start: (cb) ->
			if @runningSince
				cb()
				return
			@runningSince = new Date
			@child = child_process.spawn(
				path.join(@dir, 'run'), [], {
					detached: true,
					stdio: [0, 1, 2, 'pipe']
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

			console.log "Started " + @id + " (pid " + @child.pid + ")"
			cb()

		stop: (cb) ->
			if not @child
				cb()
				return
			pid = @child.pid
			console.log "Stopping " + @id + " (pid " + pid + ")"
			@child.on 'exit', (code, signal) =>
				clearTimeout killTimeout
				cb()
			# Kill the child's whole process group, we gave it one with detached: true
			process.kill(-pid)
			await killTimeout = setTimeout defer(), 10000
			console.log('hard-killing', pid)
			process.kill(-pid, 'SIGKILL')

		toJSON: () -> { runningSince: @runningSince }

		recv: (message) ->
			for k, v of message then switch k
				when "proxy"
					@proxy = v

		onExit: (code, signal) ->
			delete @runningSince
			delete @control
			delete @child
			console.log "Hey, just FYI my job exited with " + code + " " + signal

	constructor: ->
		events.EventEmitter.call this
	
	util.inherits Localhubd, events.EventEmitter

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

		try
			fs.mkdirSync PREFIX

		@jobs = {}

		@syncJobs()
		@watcher = fs.watch PREFIX, (event, filename) => @syncJobs()

		@controlPath = '/tmp/localhub.' + process.getuid() + '.sock'
		@controlServer = new net.Server

		fs.unlinkSync @controlPath if fs.existsSync @controlPath
		process.umask 0o77
		@controlServer.listen @controlPath
		@controlServer.on 'connection', @onConnection.bind this

		await
			for id, job of @jobs
				job.start defer()

	shutDown: (cb) ->
		if @controlServer
			@controlServer.close()
			@controlServer = null
		if @watcher
			@watcher.close()
			@watcher = null
		if @proxyServer
			@proxyServer.close()
			@proxyServer = null
		await
			for job of @jobs
				@jobs[job].stop defer()
		@jobs = {}
		if cb then cb()
		null

	loadJobDirectory: (id, dir) ->
		if id of @jobs
			throw new Exception "Shit, already had a job named " + id
		@jobs[id] = job = new Job id, dir

	unloadJobDirectory: (jobDir) ->
		console.log "TODO: unload the job in " + jobDir
		delete @jobs[jobDir]

	syncJobs: () ->
		goneJobs = {}
		goneJobs[job] = null for job in Object.keys @jobs
		try
			jobDirectories = fs.readdirSync PREFIX
		catch e
			@emit "error", e
			return false

		for job in jobDirectories
			stats = fs.statSync (path.join PREFIX, job)
			if not stats.isDirectory() then continue
			if !(job of @jobs)
				@loadJobDirectory job, path.join PREFIX, job
			delete goneJobs[job]

		@unloadJobDirectory path.join PREFIX, job for job in Object.keys goneJobs

		return true

	onConnection: (sock) ->
		new LocalhubdClient @, sock

class LocalhubdClient
	constructor: (@localhubd, @sock) ->
		sock.setEncoding 'utf-8'
		i = readline.createInterface sock, sock
		i.on 'line', (line) =>
			try
				obj = JSON.parse line
			catch e
				console.log "Couldn’t parse message, closing connection"
				sock.end()
				return
			@recv obj

	send: (msg) ->
		@sock.write JSON.stringify(msg)
		@sock.write '\n'

	recv: (msg) ->
		method = 'cmd_' + (msg.command || '')
		if not (method of @)
			console.log "Unknown command, closing connection"
			@sock.end()
			return
		@[method] msg
	
	cmd_list: (msg) ->
		@send { "jobs": @localhubd.jobs }
	cmd_stop: (msg) ->
		job = @localhubd.jobs[msg.job]
		if not job
			@send { error: "No such job" }
			return
		await job.stop defer()
		@send { ok: true }
	cmd_start: (msg) ->
		job = @localhubd.jobs[msg.job]
		if not job
			@send { error: "No such job" }
			return
		await job.start defer()
		@send { ok: true }
	cmd_restart: (msg) ->
		job = @localhubd.jobs[msg.job]
		if not job
			@send { error: "No such job" }
			return
		await job.stop defer()
		await job.start defer()
		@send { ok: true }

# - - -

process.title = 'localhubd'

localhubd = new Localhubd

localhubd.on "error", (error) ->
	util.error error
	process.exit 1

localhubd.on "warning", (error) ->
	util.error error

localhubd.start()

process.on 'SIGINT', () ->
	process.exit()

process.on 'exit', () ->
	localhubd.shutDown()
