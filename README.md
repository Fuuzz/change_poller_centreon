# change_poller

A shell script to automatically and massively move hosts from one poller to another, or from a list of hosts to a poller, for the monitoring platform Centreon.
The script needs a source type and a destination poller.
The script can be launched from command line both as a command with arguments and as an interactive utility.

## Command mode

Launching the script with the options and arguments execute all the steps automatically until the end of the script; useful for automation tasks, i.e. in case of a poller not reachable.

## Interactive mode

Launching the script without any option starts the interactive prompt, user will be asked to select the host source (a starting poller or a host list file) and the destination poller.

## In development

- Whitelist handling
- Option to automatically deploy pollers at the end of the process
