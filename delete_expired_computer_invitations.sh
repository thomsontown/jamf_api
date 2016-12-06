#!/bin/sh


#	This script can be used to delete expired computer invitations. There seems to be no reason to keep
#	expired invitations within the jss and I find it helpful de-clutter the list of computer invitations.
#	Use at your own risk. 

#	Author:		Andrew Thomson
#	Date:		11-14-2016


#JSS_USER=""			#	Un-comment this line and add your login name if different from your os x login account.
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


#	get invitations 
INVITATIONS_XML=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/computerinvitations`


#	get count of invitations
COUNT=`echo $INVITATIONS_XML | /usr/bin/xpath "/computer_invitations/size/text()" 2> /dev/null`


#	enumerate invitations 
for (( INDEX=1; INDEX<=$COUNT; INDEX++ )); do

	#	get computer invitation id
	INVITATION_ID=`echo $INVITATIONS_XML | /usr/bin/xpath "/computer_invitations/computer_invitation[$INDEX]/id/text()" 2> /dev/null`

	#	get expiration date of current computer invitation
	EXPIRATION_DATE=`echo $INVITATIONS_XML | /usr/bin/xpath "/computer_invitations/computer_invitation[$INDEX]/expiration_date/text()" 2> /dev/null`

	#	show details while in debug mode
	if $DEBUG; then echo "ID: $INVITATION_ID   EXPIRATION: $EXPIRATION_DATE"; fi

	#	if expiration date is valid . . .
	if echo $EXPIRATION_DATE | /usr/bin/grep -o '[0-9]\{1,4\}\-[0-9]\{1,2\}\-[0-9]\{1,2\}' &> /dev/null; then

		#	test if expiration date has passed
		if [[ "$EXPIRATION_DATE" < "`/bin/date +"%Y-%m-%d %H:%M:%S"`" ]]; then
			echo "Deleting: ID: $INVITATION_ID EXPIRED: $EXPIRATION_DATE"

			#	delete expired computer invitation
			RESPONSE_CODE=`/usr/bin/curl -X DELETE --connect-timeout 5 -sw "%{http_code}" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/computerinvitations/id/$INVITATION_ID -o /dev/null 2> /dev/null`

			#	display if error occurs 
			if [[ $RESPONSE_CODE -ne 200 ]]; then
				echo "ERROR: Unable to delete computer invitation [ID:$INVITATION_ID]"
			fi
		fi
	fi
done


#	audible completion sound
/usr/bin/afplay /System/Library/Sounds/Glass.aiff

