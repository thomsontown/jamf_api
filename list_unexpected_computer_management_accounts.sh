#!/bin/bash


#JSS_USER=""		#	Un-comment this line and add your login name if different from your os x login account.
#JSS_PASSWORD=""	#	Un-comment this line and add your password to prevent being prompted each time.
EXPECTED_MANAGEMENT_USERNAME="casper"


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


#	enumerate computers for management username
for COMPUTER in ${COMPUTERS[@]}; do

	#	get general node of specified computer
	GENERAL=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/computers/id/$COMPUTER/subset/general 2> /dev/null`

	#	get management username 
	MANAGEMENT=`echo $GENERAL | /usr/bin/xpath "/computer/general/remote_management/management_username/text()" 2> /dev/null`

	#	if management username not 'jamf' then display id, compuer name and management username
	if [ "$MANAGEMENT" != "$EXPECTED_MANAGEMENT_USERNAME" ]; then 
		echo $GENERAL | /usr/bin/xpath "concat(/computer/general/id/text(), ', ',/computer/general/name/text(), ', ',/computer/general/remote_management/management_username/text())" 2> /dev/null
	fi
done


#	audible completion sound
/usr/bin/afplay /System/Library/Sounds/Glass.aiff










