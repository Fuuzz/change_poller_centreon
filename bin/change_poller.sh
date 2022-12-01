#!/bin/bash
#
#aaa This script asks for a source poller or hosts list and a destination poller to massively change the poller for all the hosts
# The script can be executed as interactive command or as a command with arguments from command line
#
# Authors:
#     "Matteo D'ALFONSO <mdalfonso@centreon.com>"
#     "Elia RAMPI <erampi@centreon.com>"
# Version: 1.1
#
# 1.1 - 23/09/2022: Refined log file naming; added exception handling for hosts with whitespace
# 1.2 - 23/11/2022: Improved log file naming and handling

set -e

# Check for bash 4
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
	echo "You need at least bash version 4"
	exit
fi

# Check centreon executable existence
if [[ -z $(command centreon) ]]; then
	printf "Centreon executables not found"
	exit 1
fi

#Initializing variables
TODAY=$(date +%Y%m%d-%H%M)
TMPFILE=$(mktemp)
WDIR=$(dirname $0)

# Creating the log folder if not present
if [[ ! -d ${WDIR}/../log/ ]]; then
	mkdir ${WDIR}/../log/
fi

# Checking for the conf file
if [[ -r ${WDIR}/../conf/login.conf ]]; then
	source ${WDIR}/../conf/login.conf
else
	printf "Login conf file not present or readable\n"
	exit 1
fi
declare -A POLLERS_DICT
declare -a HOSTS_ARRAY
unset POLLER
unset NEW_POLLER
unset INPUT_FILE
unset DEPLOY
POLLER_OK=

# Function to show script usage
function help {
	printf "\nThis script can be launched in interactive or command mode.\nTo launch as command, provide a source and destination argument; with no arguments, the script will start in interactive mode.\n"
	printf "$0 [-h] [-s source_poller | -f source_file] [-d destination poller]\n\n"
}

# Function to select and check the source and destination poller
function poller_select {

	for i in "${!POLLERS_DICT[@]}"; do
		printf "%s) %s\n" "$i" "${POLLERS_DICT[$i]}"
	done
	read -p "Poller number: " IDPOLLER

	POL=$1
	if [[ ${POLLERS_DICT[$IDPOLLER]+_} ]]; then
		if [[ $POL == "POLLER" ]] || [[ $POL == "NEW_POLLER" ]]; then
			eval ${POL}="${POLLERS_DICT[${IDPOLLER}]}"
			printf "Choosen poller: %s\n" "${!POL}"
		fi
	else
		printf "Poller ${IDPOLLER} not found, exiting...\n"
		help
		exit 1
	fi
}

# Function to check that the selected poller exists
function poller_check {
	POL="$1"
	for poller in ${POLLERS_DICT[@]}; do
		if [[ $poller == ${!POL} ]]; then
			POLLER_OK=true
		break
		fi
	done
	if ! $POLLER_OK; then
		printf "Poller '%s' not found\n" ${!POL}
		exit 1
	fi
}

# Function to check and parse the host list from a file
function file_check_parse {

	# Checking if file exist and is readable
	if [[ -r $1 ]] ; then
		echo "$1 is valid"
	else
		printf "File %s not present or readable\n" "$1"
		exit 1
	fi		
	# Read the file and populate array
	while read line; do
		HOSTS_ARRAY+=("${line}")
	done < $1
}

# Saving Poller list to temporary file
centreon -u $USERNAME -p $PASSWORD -o INSTANCE -a SHOW | awk -F';' 'NR > 1 && $5 == 1 {print $1, $2}' > $TMPFILE

# Parsing file to populate POLLERS_DICT, then deletes temp file
while read -r id poller; do
	POLLERS_DICT[${id}]=${poller}
done < $TMPFILE
rm $TMPFILE

# Verify it there are no option set to enter interactive mode
if [ "$#" -eq 0  ]; then

# Prompt for parameters
printf "
Welcome to the poller change utility for Centreon.

Enter the type of source for the task, or ask for help.
Valid options: 

\ts) Source poller 
\tf) Hosts list taken by file
\th) Help
\tx) Exit 
"

read -p "Enter option: " CRITERIA

# Case loop for the criteria for interactive mode
case $CRITERIA in
	# Source poller option
	s)
		printf "\nEnter the starting poller:\n"
		poller_select "POLLER"	
		HOSTS_ARRAY=($(centreon -u $USERNAME -p $PASSWORD -o INSTANCE -a GETHOSTS -v "$POLLER"| awk -F ';' 'NR > 1 {print $2}'))
	;;

	# Source file option
	f)
		printf "\nEnter the source file path, or enter [x] to Exit:\n"
		printf "Use absolute path or relative path from this folder: '%s'\n" "$WDIR"
		read -p "File path: " INPUT_FILE
		if [[ "$INPUT_FILE" == "x" ]]; then
			printf "Exiting...\n"
			exit 0
		fi
		file_check_parse "${INPUT_FILE}"
	;;

	x)
		printf "Exiting...\n"
		exit 0
	;;

	h)
		help
		exit 0
	;;

	*)
		printf "\nWrong options, exiting...\n"
		exit 1
	;;
esac

# Prompt for the destination poller
printf "\nEnter the destination poller:\n"
poller_select "NEW_POLLER"

# If there are more than 0 parameters enter getopts selection and check if they are valid
else

# Redirecting output
exec > >(tee -a ${WDIR}/../log/${TODAY}-execution.log) 2>&1

while getopts "hs:f:d:" Option
do
	case $Option in
	h) 
		help
		exit
	;;
	
	s)
		POLLER=$OPTARG
		POLLER_OK=false
		poller_check "POLLER"
		HOSTS_ARRAY=($(centreon -u $USERNAME -p $PASSWORD -o INSTANCE -a GETHOSTS -v "$POLLER"| awk -F ';' 'NR > 1 {print $2}'))
	;;
	
	f)
		INPUT_FILE=$OPTARG
		file_check_parse "${INPUT_FILE}"
	;;

	d)
		NEW_POLLER=$OPTARG
		POLLER_OK=false
		poller_check "NEW_POLLER"
	;;

	*) 
		printf "Invalid option\n"
		help
	;;

	esac

done

shift $(($OPTIND - 1))

	# Verify if option destination is present
	if [[ -z "$NEW_POLLER" ]] ; then
		printf "Missing -d option\n"
		exit 1
	# Verify that only one source option is present
	elif [[ -n "$POLLER" ]] && [[ -n "$INPUT_FILE" ]]; then
		printf "Only one source option required: -s or -f\n"
		exit 1
	# Verify that at least one source option is present
	elif [[ -z "$POLLER" ]] && [[ -z "$INPUT_FILE" ]]; then
		printf "At least one source option required: -s or -f\n"
		exit 1
	fi
fi

# Assign proper name to log file
if [[ -n "$POLLER" ]]; then
	OUTPUT_LIST="${WDIR}/../log/${TODAY}-poller-change-from-${POLLER}-to-${NEW_POLLER}"
	EXCEPTION_LIST="${WDIR}/../log/${TODAY}-change-exceptions-from-${POLLER}-to-${NEW_POLLER}"
elif [[ -n "$INPUT_FILE" ]]; then
	FILENAME=$(basename ${INPUT_FILE})
	OUTPUT_LIST="${WDIR}/../log/${TODAY}-poller-change-from-${FILENAME}-to-${NEW_POLLER}"
	EXCEPTION_LIST="${WDIR}/../log/${TODAY}-change-exceptions-from-${FILENAME}-to-${NEW_POLLER}"
fi

# Printing all the hosts involved to the log file, then setting the new poller as specified for all the hosts; excluding hosts with whitespace in name
cat /dev/null > $OUTPUT_LIST
cat /dev/null > $EXCEPTION_LIST
for i in ${HOSTS_ARRAY[@]}; do
	if [[ $i = *" "*  ]]; then
		printf "%s\n" "$i" >> "$EXCEPTION_LIST"
		
	else
		printf "%s\n" "$i" >> "$OUTPUT_LIST"
		centreon -u $USERNAME -p $PASSWORD -o HOST -a SETINSTANCE -v "${i};${NEW_POLLER}"
	fi
done

# Application of the changes and reload of the pollers if option is set
if [[ -n "$DEPLOY" ]]; then
	for poller in ${POLLERS_DICT[@]}; do
		centreon -u $USERNAME -p $PASSWORD -a APPLYCFG -v "${poller}"
	done
fi

# Handling the log files
if [[ -s "$OUTPUT_LIST" ]]; then
	printf "The processed hosts log has been saved as $OUTPUT_LIST\n"
else
	printf "WARNING - The list $OUTPUT_LIST is empty\n"
fi

if [[ -s "$EXCEPTION_LIST" ]]; then
	printf "The exception hosts log has been saved as $EXCEPTION_LIST\n"
else
	rm $EXCEPTION_LIST
fi
