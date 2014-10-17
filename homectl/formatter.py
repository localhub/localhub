

def format_job_list(message):
	return "\n".join("{} ({})".format(name, job) for name, job in message["jobs"].items())

def format_info(message):
	return "\033[36m" + message["message"] + "\033[0m"

def format_bye(message):
	return "Bye!"

def format(message):
	formatter = globals().get("format_" + message["type"], None)
	if formatter is not None:
		return formatter(message)
	else:
		return message
