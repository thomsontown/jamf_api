#!/bin/sh

#	This script will display a list of computer names that do are not assigned to a Casper site.
#	Be patient, this script may take some time to complete.

#	Author:		Andrew Thomson
#	Date:		08-10-2016


#JSS_USER=""		#	Un-comment this line and add your login name if different from your os x login account.
#JSS_PASSWORD=""	#	Un-comment this line and add your password to prevent being prompted each time.

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


#	get computers ids
COMPUTERS=(`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL}JSSResource/computers | /usr/bin/xpath "//id" 2> /dev/null | awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`)


#	enumerate computers for last check-in time
for COMPUTER in ${COMPUTERS[@]}; do
	SITE_NAME=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/computers/id/$COMPUTER/subset/general | /usr/bin/xpath "/computer/general/site/name/text()" 2> /dev/null`
	if [ "$SITE_NAME" == "None" ]; then 
		/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/computers/id/$COMPUTER/subset/general | /usr/bin/xpath "/computer/general/name/text()" 2> /dev/null
		echo $'\r'
	fi
done


#	audible completion sound
/usr/bin/afplay /System/Library/Sounds/Glass.aiff