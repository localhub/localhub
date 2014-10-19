def format_jobs(message):
	return "\n".join("{} ({})".format(name, job) for name, job in message.items())

def format_info(message):
	return "\033[36m" + message + "\033[0m"

def format_stopped(job):
	return "{} stopped".format(job)

def format_started(job):
	return "{} started".format(job)

def format_restarted(job):
	return "{} restarted".format(job)

def format(message):
	for k in message:
		yield globals().get("format_" + k)(message[k])
