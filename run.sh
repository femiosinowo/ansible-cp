#!/bin/bash

# no args - default run
if [ $# == 0 ]; then
	echo "Running ansible-playbook"
	sudo ansible-playbook -u vagrant -i hosts --private-key=certs/nxt.pem site.yml
# one argument
elif [ $# == 1 ]; then
	# list commands
	if [ "$1" == "--help" ] || [ "$1" == "help" ]; then
		echo "Available params:"
		echo "  test - test connection on all hosts"
		echo "  *    - run with --tags=\"*\" (ex: --tags=\"base,app\")"
		echo "  * *  - run with multiple arguments"
	# ping/test hosts
	elif [ "$1" == "test" ] || [ "$1" == "ping" ]; then
		echo "Running ansible ping"

		sudo ansible -u vagrant -i hosts --private-key=certs/nxt.pem -m ping all
	# tags given
	else
		echo "Running ansible-playbook with --tags=\"$1\""

		sudo ansible-playbook -u vagrant -i hosts --private-key=certs/nxt.pem --tags=\"$1\" site.yml
	fi
# multiple args
elif [ $# > 1 ]; then
	echo "Running ansible-playbook with arguments: \"$*\""

	# FIXME: escape double quotes
	sudo ansible-playbook -u vagrant -i hosts --private-key=certs/nxt.pem "$*" site.yml
fi