#!/bin/bash


#JSS_USER=""		#	Un-comment this line and add your login name if different from your os x login account.
#JSS_PASSWORD=""	#	Un-comment this line and add your password to prevent being prompted each time.
DEBUG=true


function jssCheck {

	#	test host connection
	JSS_CHECK=`/usr/bin/curl -s -k --connect-timeout 10 -sw "%{http_code}" ${JSS_URL%/}/JSSCheckConnection -o /dev/null`

	#	alert on connection failure
	if [ $JSS_CHECK -ne 200 ]; then

		#	error out if jss non responsive 
		(>&2 echo -e   "\nERROR: Unable to reach server. Service may be unavailable.")
		exit $LINENO

	fi
}


 #	load coomon source variables
if [ -f ~/.bash_source ]; then
	source ~/.bash_source
fi


if ! JSS_URL=`/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url`; then
	echo "ERROR: Unable to read default url."
	exit $LINENO
fi


if [ -z $JSS_USER ]; then
	JSS_USER=$USER
fi 


if [ -z $JSS_PASSWORD ]; then 
	echo "Please enter JSS password for account: $USER."
	read -s JSS_PASSWORD
fi


#	verify jss connection
jssCheck


#	get computers ids
COMPUTERS=(`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/computers | /usr/bin/xpath "//id"  2> /dev/null | awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`)


#	display headers
echo -e "COUNT\tTOTAL\tTIME"


#	enumerate computers for last check-in time
for COMPUTER in ${COMPUTERS[@]}; do

	#	verify jss connection
	jssCheck

	#	test host connection
	JSS_COMPUTER_RESULT=`/usr/bin/curl -s -k --connect-timeout 3 --max-time 3 -u ${JSS_USER}:${JSS_PASSWORD} -sw "%{http_code}" ${JSS_URL%/}/JSSResource/computers/id/$COMPUTER -o /dev/null`

	#	display progress
	echo -en "\r$((COUNT++))\t${#COMPUTERS[@]}\t$SECONDS" 

	#	display and log query failures
	if [ $JSS_COMPUTER_RESULT != 200 ]; then
		#	output connection info
		echo -e "$COMPUTER" >> "~/Desktop/`/usr/bin/basename ${0} ${0##*.}`log"
		
		#	audible sound when problem id found
		/usr/bin/afplay /System/Library/Sounds/Pop.aiff
	fi

done


#	display completion notice
echo -e "\nCompleted in $SECONDS with return code: $?."


#	audible completion sound
/usr/bin/afplay /System/Library/Sounds/Glass.aiff