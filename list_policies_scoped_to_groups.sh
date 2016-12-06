#!/bin/sh

#JSS_USER=""		#	Un-comment this line and add your login name if different from your os x login account.
#JSS_PASSWORD=""	#	Un-comment this line and add your password to prevent being prompted each time.
IFS=$'\r'
DEBUG=false


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


#	get xml formatted data
XML_POLICIES=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL}JSSResource/policies | /usr/bin/xmllint --format -`


#	get count of policies
POLICIES_COUNT=`echo $XML_POLICIES | /usr/bin/xpath "/policies/size/text()" 2> /dev/null`
if $DEBUG; then echo "COUNT: $POLICIES_COUNT"; fi
	
	
#	eunmerate policy by id
for (( INDEX=1; INDEX<=$POLICIES_COUNT; INDEX++ )); do
		if $DEBUG; then echo "INDEX: $INDEX"; fi
	
		#	get id of current policy 
		CURRENT_POLICY_ID=`echo $XML_POLICIES | /usr/bin/xpath "/policies/policy[$INDEX]/id/text()" 2> /dev/null`
		if $DEBUG; then echo "ID: $CURRENT_POLICY_ID"; fi
			
		#	get xml formatted data for current policy 	
		XML_CURRENT_POLICY_ID=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL}JSSResource/policies/id/${CURRENT_POLICY_ID} | /usr/bin/xmllint --format -`
		
		#	get name of current policy
		CURRENT_POLICY_NAME=`echo $XML_CURRENT_POLICY_ID | /usr/bin/xpath "/policy/general/name/text()" 2> /dev/null`
		if $DEBUG; then echo "POLICY NAME: $CURRENT_POLICY_NAME"; fi
		
		#	get count of computer groups scoped to current policy
		COMPUTER_GROUP_COUNT=`echo $XML_CURRENT_POLICY_ID | /usr/bin/xpath "count(/policy/scope/computer_groups/computer_group)" 2> /dev/null`
		if $DEBUG; then echo "GROUPS: $COMPUTER_GROUP_COUNT"; fi
			
		#	determine if any computers groups are scoped 
		if [ $COMPUTER_GROUP_COUNT -gt 0 ] ;then
			
			#	enumerate computers groups scoped to current policy
			for (( JNDEX=1; JNDEX<=$COMPUTER_GROUP_COUNT; JNDEX++ )); do
				if $DEBUG; then echo "JNDEX:  $JNDEX"; fi
				
				#	get name of computer group scoped to current policy	
				CURRENT_GROUP_NAME=`echo $XML_CURRENT_POLICY_ID | /usr/bin/xpath "/policy/scope/computer_groups/computer_group[$JNDEX]/name/text()" 2> /dev/null`
				
				#	get id of competer group scoped to current policy
				CURRENT_GROUP_ID=`echo $XML_CURRENT_POLICY_ID | /usr/bin/xpath "/policy/scope/computer_groups/computer_group[$JNDEX]/id/text()" 2> /dev/null` 
				
				#	display policy id, group id and group name
				echo "POLICY_ID: \t $CURRENT_POLICY_ID \t GROUP_ID: $CURRENT_GROUP_ID \t GROUP_NAME: $CURRENT_GROUP_NAME"
			done
		fi
		if $DEBUG; then echo $'\n'; fi
done

