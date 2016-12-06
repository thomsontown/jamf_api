#!/bin/sh

#JSS_USER=""		#	Un-comment this line and add your login name if different from your os x login account.
#JSS_PASSWORD=""	#	Un-comment this line and add your password to prevent being prompted each time.
DEBUG=true


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


#	get computer groups xml
COMPUTER_GROUPS=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/computergroups`

#	get count of computer groups
COMPUTER_GROUPS_COUNT=`echo $COMPUTER_GROUPS | /usr/bin/xpath "/computer_groups/size/text()" 2> /dev/null`

#	enumerate computer groups for ids
for (( INDEX=1; INDEX<=$COMPUTER_GROUPS_COUNT; INDEX++ )); do
	COMPUTER_GROUP_IDS+=(`echo $COMPUTER_GROUPS | /usr/bin/xpath "/computer_groups/computer_group[$INDEX]/id/text()" 2> /dev/null`)
done

echo ${COMPUTER_GROUP_IDS[@]}
	