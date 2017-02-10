#!/bin/bash


#    While static groups within JAMF PRO are typically thought of as 
#    less-uesful than their more dynamic counterparts known as smart 
#    groups, I have found they still serve a critical role. This is 
#    especially so for those who extract the most from JAMF PRO via a
#    series of API scripts. Those API script often return a list of 
#    computer IDs or names. But those lists usually need to be acted 
#    upon in some way. Being able to easily create a static group within
#    JAMF PRO can make that happen. 

#    That is why I wrote this script. It allows for the quick creation
#    and/or re-population of a static group based on a string of computer 
#    IDs or names

#    To run the script, you may opt to uncomment and fill-in some of 
#    the override variables. If not, the script will prompt you along
#    the way. Be sure to include a delimited string of computer IDs or
#    computer names as an argument to this script. 

#    Author:        Andrew Thomson
#    Date:          02-10-2017
#    GitHub:        https://github.com/thomsontown


#    uncomment to override variables
# JSS_USER=""
# JSS_PASSWORD=""
# JSS_URL=""
# GROUP_NAME=""


#	used to determine if input are ids or computer names
function isInteger() { return `[ "$@" -eq "$@" ] 2> /dev/null`; }


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
	echo "Please enter JSS password for account: $USER."
	read -s JSS_PASSWORD
fi


#	exit if credentials are missing
if [ -z "$JSS_USER" ] || [ -z "$JSS_PASSWORD" ]; then
	(>&2 echo "ERROR: Missing credentials.")
	exit $LINENO
fi


#	get jss url
if ! JSS_URL=`/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url`; then
	(>&2 echo "ERROR: Unable to read JSS url.")
	exit $LINENO
fi


#	make sure jss is available
JSS_CONNECTION=`/usr/bin/curl --connect-timeout 10 -sw "%{http_code}" ${JSS_URL%/}/JSSCheckConnection -o /dev/null`
if [ $JSS_CONNECTION -ne 200 ]; then
	(>&2 echo "ERROR: Unable to connect to JSS.")
	exit $LINENO
fi


#	check for arguments and display usage
if [ $# -eq 0 ]; then 
	echo -e "\033[1mUSAGE:\033[0m ${0##*/} [\033[2mcomputer_id computer_id computer_id ...\033[0m] or [\033[2mcomputer_name computer_name computer_name ...\033[0m]"
	exit $LINENO
else 
	ARGUMENTS=("$@")
fi


#	prompt for group name if not provided
if [ -z "$GROUP_NAME" ]; then
	read -p "What is the name of the static group you would like to create or re-populate? " GROUP_NAME
	if [ -z "$GROUP_NAME" ]; then 
		(>&2 echo "ERROR: No group name specified.")
		exit $LINENO
	fi
fi


#	query jss for existing group name
GROUP_ID=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} "${JSS_URL%/}/JSSResource/computergroups/name/$GROUP_NAME" | /usr/bin/xpath "//computer_group/id/text()" 2> /dev/null`


#	create new group if no existing one can be found
if [ -z "$GROUP_ID" ]; then

	#	minimal xml required to create static group
	XML_GROUP_TEMPLATE="<computer_group><id>0</id><name>$GROUP_NAME</name><is_smart>false</is_smart></computer_group>"

	 #	upload xml to create static group
	GROUP_ID=`/usr/bin/curl -X POST -H "Content-Type: application/xml" -s -u "${JSS_USER}:${JSS_PASSWORD}" -d "${XML_GROUP_TEMPLATE}" "${JSS_URL%/}/JSSResource/computergroups/id/0" | /usr/bin/xpath "//computer_group/id/text()" 2> /dev/null`

	#	display error if no group id is returned
	if [ -z "$GROUP_ID" ]; then 
		(>&2 echo "ERROR: Unable to create JSS computer group.")
		exit $LINENO
	fi
fi


#	create opening xml for replacing members of the static group
XML_COMPUTER_TEMPLATE="<computer_group><id>$GROUP_ID</id><name>$GROUP_NAME</name><computers>"


#	enumerate computers to re-populate static group
for COMPUTER in ${ARGUMENTS[@]}; do

	#	leave breadcrumbs for pseudo progress
	echo -e -n "."

	#	derermine if computer id (integer) or name (alpha) was provided
	if isInteger "$COMPUTER"; then
		XML_COMPUTER=`/usr/bin/curl -X GET -H "Content-Type: application/xml" -s -u "${JSS_USER}:${JSS_PASSWORD}" "${JSS_URL%/}/JSSResource/computers/id/$COMPUTER/subset/general" 2> /dev/null`

		COMPUTER_NAME=`echo $XML_COMPUTER | /usr/bin/xpath "/computer/general/name/text()" 2> /dev/null`
		COMPUTER_SN=`echo $XML_COMPUTER | /usr/bin/xpath "/computer/general/serial_number/text()" 2> /dev/null`
		COMPUTER_ID="$COMPUTER"
	else
		XML_COMPUTER=`/usr/bin/curl -X GET -H "Content-Type: application/xml" -s -u "${JSS_USER}:${JSS_PASSWORD}" "${JSS_URL%/}/JSSResource/computers/name/$COMPUTER/subset/general" 2> /dev/null`

		COMPUTER_ID=`echo $XML_COMPUTER | /usr/bin/xpath "/computer/general/id/text()" 2> /dev/null`
		COMPUTER_SN=`echo $XML_COMPUTER | /usr/bin/xpath "/computer/general/serial_number/text()" 2> /dev/null`
		COMPUTER_NAME="$COMPUTER"
	fi
	
	#	verify computer details were found		
	if [ -z "$COMPUTER_SN" ] || [ -z "$COMPUTER_ID" ] || [ -z "$COMPUTER_NAME" ]; then (>&2 echo -e "\nERROR: Unable to retrieve info for computer [$COMPUTER]."); continue; fi 

	#	insert xml requied for each computer be a member of the static group
	XML_COMPUTER_TEMPLATE+="<computer><id>$COMPUTER_ID</id><name>$COMPUTER_NAME</name><serial_number>$COMPUTER_SN</serial_number></computer>"
done


#	close out the xml for re-populating members of the static group
XML_COMPUTER_TEMPLATE+="</computers></computer_group>"


#	verify xml formatting before submitting
if ! XML_COMPUTER_TEMPLATE=`echo $XML_COMPUTER_TEMPLATE | /usr/bin/xmllint --format -`; then 
	(>&2 echo -e "\nERROR: Imporperly formatted data structure found.")
	exit $LINENO
fi


#	upload xml to re-populate the computers in the static group
HTTP_CODE=`/usr/bin/curl -X PUT -H "Content-Type: application/xml" -w "%{http_code}" -s -u "${JSS_USER}:${JSS_PASSWORD}" -d "$XML_COMPUTER_TEMPLATE" -o /dev/null "${JSS_URL%/}/JSSResource/computergroups/id/$GROUP_ID" 2> /dev/null`
if [ "$HTTP_CODE" -ne "201" ]; then
	(>&2 echo -e "\nERROR: Unable to replace computers in static group.")
	exit $LINENO
fi


#	return cursor
echo -e "\nDURATION: $SECONDS second(s)"


#	play audible completion sound
if [ -f /System/Library/Sounds/Glass.aiff ]; then /usr/bin/afplay /System/Library/Sounds/Glass.aiff; fi
