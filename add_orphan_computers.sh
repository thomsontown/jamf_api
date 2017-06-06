#!/bin/sh


#    This script was written to parse the JAMFSoftwareServer.log file to find any
#    orphan computers (computers contacting the JSS without an existing object) and
#    re-add corrosponding computer objects. This should enable invetories and check-
#    ins to occur normally. 

#    Leaving the JSS_SITE setting at -1 will add the newly created computer objects
#    to the root of the JSS. Changing the setting to a corrosponding site ID will
#    add the newly created computer object to the specified site. 


#    Author:          Andrew Thomson
#    Date:            06/06/2017
#    GitHub:          https://github.com/thomsontown


#    uncomment to override variables
# JSS_USER=""
# JSS_PASSWORD=""
# JSS_URL=""
JSS_SITE="-1"
LOG_PATH=$1


#	load common source variables
if [ -f ~/.bash_source ]; then
	source ~/.bash_source
fi


#	use current user for jss username if not provided
if [ -z $JSS_USER ]; then
	JSS_USER=$USER
fi 


#	prompt for password if not provided
if [ -z $JSS_PASSWORD ]; then 
	/bin/echo "Please enter JSS password for account: $USER."
	read -s JSS_PASSWORD
fi


#	exit if credentials are missing
if [ -z "$JSS_USER" ] || [ -z "$JSS_PASSWORD" ]; then
	(>&2 /bin/echo "ERROR: Missing credentials.")
	exit $LINENO
fi


#	get jss url
if ! JSS_URL=`/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url`; then
	(>&2 /bin/echo "ERROR: Unable to read JSS url.")
	exit $LINENO
fi


#	make sure jss is available
JSS_CONNECTION=`/usr/bin/curl --connect-timeout 10 -sw "%{http_code}" ${JSS_URL%/}/JSSCheckConnection -o /dev/null`
if [ $JSS_CONNECTION -ne 200 ]; then
	(>&2 /bin/echo "ERROR: Unable to connect to JSS.")
	exit $LINENO
fi


#	get the path to latest JAMFSoftwareServer log file
if [ -z "${LOG_PATH}" ]; then
	
	#	display log download option
	/usr/bin/open ${JSS_URL%/}/logging.html
	
	echo "Please enter or drag-n-drop the path to the most recent JAMFSoftwareServer.log. Then press the enter key."
	read LOG_PATH
	if [ ! -f "${LOG_PATH}" ]; then 
		echo "ERROR: The log file cannot be found."
		exit $LINENO
	fi
fi


#	search for orphan computers
MACHINE_ADDRESSES=(`/usr/bin/grep "Comm Device null."  "${LOG_PATH}" | /usr/bin/grep -Eo [:0-9A-F:]{2}\(\:[:0-9A-F:]{2}\){5} | /usr/bin/sort -u`)


#	exit if no orphan computers are found
if [ ${#MACHINE_ADDRESSES[@]} -eq 0 ]; then
	/bin/echo "No orphan computers found."
	exit 0
fi


#	enumerate each mac address found 
for MACHINE_ADDRESS in ${MACHINE_ADDRESSES[@]}; do

	XML="<computer><general><id>0</id><name>orphan</name><mac_address>$MACHINE_ADDRESS</mac_address><site><id>$JSS_SITE</id></site></general></computer>"

	#	check if mac address is already in the jss
	RETURN_CODE=`/usr/bin/curl -X GET -H "Content-Type: application/xml" -w "%{http_code}" -o /dev/null -s -u "${JSS_USER}:${JSS_PASSWORD}" -d "$XML" "${JSS_URL%/}/JSSResource/computers/macaddress/$MACHINE_ADDRESS"`
	
	#	add new computer object
	if [ "$RETURN_CODE" -eq "404" ]; then
		RETURN_CODE=`/usr/bin/curl -X POST -H "Content-Type: application/xml" -w "%{http_code}" -o /dev/null -s -u "${JSS_USER}:${JSS_PASSWORD}" -d "$XML" "${JSS_URL%/}/JSSResource/computers/id/0"`
		if [ "$RETURN_CODE" -ne 201 ]; then
			(>&2 /bin/echo "Unable to add MAC: $MACHINE_ADDRESS")
		fi
	fi
done


#	play completion sound
if [ -f /System/Library/Sounds/Glass.aiff ]; then /usr/bin/afplay /System/Library/Sounds/Glass.aiff; fi