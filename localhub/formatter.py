def format_jobs(message):
	return "\n".join("{} ({})".format(name, job) for name, job in message.items())

def format_info(message):
	return "\033[36m" + message + "\033[0m"

def format_error(message):
	return "\033[31m" + message + "\033[0m"


def format_ok(_):
	return None

def format(message):
	for k in message:
		s = globals().get("format_" + k)(message[k])
		if s is not None:
			yield s
