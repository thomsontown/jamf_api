#!/bin/sh

#    This script finds all groups (static and smart) that are NOT scoped
#    to policies or configuration profiles and display them in a list.
#    The user is then prompted if the non-scoped groups should be deleted.
#    If confirmed, each non-scoped group will be backed up into an xml file
#    and delted from the JAMF PRO server. 

#    Depending on how you use groups in your environment, this script can
#    help maintaining only necessary groups. 

#    Author:            Andrew Thomson
#    Date:              12-06-2016
#    GitHub:            https://github.com/thomsontown


#JSS_USER=""		#	Un-comment this line and add your login name if different from your os x login account.
#JSS_PASSWORD=""	#	Un-comment this line and add your password to prevent being prompted each time.
PROMPT_TO_DELETE=true
DISPLAY_GROUP_NAMES=true
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


	#################
	#    GROUPS     #
	#################


#	get computer groups xml
COMPUTER_GROUPS=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/computergroups`

#	get count of computer groups
COMPUTER_GROUPS_COUNT=`echo $COMPUTER_GROUPS | /usr/bin/xpath "/computer_groups/size/text()" 2> /dev/null`
if $DEBUG; then echo "GROUP ID COUNT: $COMPUTER_GROUPS_COUNT"; fi

#	enumerate computer groups for ids
for (( INDEX=1; INDEX<=$COMPUTER_GROUPS_COUNT; INDEX++ )); do
	COMPUTER_GROUP_IDS+=(`echo $COMPUTER_GROUPS | /usr/bin/xpath "/computer_groups/computer_group[$INDEX]/id/text()" 2> /dev/null`)
done

#	sort ids because it looks better
COMPUTER_GROUP_IDS=( `for i in ${COMPUTER_GROUP_IDS[@]}; do echo $i; done | sort` )



	#################
	#   POLICIES    #
	#################


#	get policies xml
POLICIES=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/policies`


#	get count of policies
POLICIES_COUNT=`echo $POLICIES | /usr/bin/xpath "/policies/size/text()" 2> /dev/null`
if $DEBUG; then echo "POLICY ID COUNT: $POLICIES_COUNT"; fi


#	enumerate policies for ids
for (( INDEX=1; INDEX<=$POLICIES_COUNT; INDEX++ )); do
	POLICY_IDS+=(`echo $POLICIES | /usr/bin/xpath "/policies/policy[$INDEX]/id/text()" 2> /dev/null`)
done


for POLICY_ID in ${POLICY_IDS[@]}; do 

	#	get xml for individual policy based on id
	POLICY_GROUPS=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/policies/id/$POLICY_ID/subset/scope`
	
	#	get count of computer groups the individual policy is scoped
	POLICY_GROUPS_COUNT=`echo $POLICY_GROUPS | /usr/bin/xpath "count(/policy/scope/computer_groups/computer_group)" 2> /dev/null`
	if $DEBUG; then echo " GROUPS FOUND: $POLICY_GROUPS_COUNT"; fi
	
	#	enumerate computers groups within policy
	if [ $POLICY_GROUPS_COUNT -ne 0 ]; then
		for (( INDEX=1; INDEX<=$POLICY_GROUPS_COUNT; INDEX++ )); do
			
			SCOPED_GROUP_IDS+=(`echo $POLICY_GROUPS | /usr/bin/xpath "/policy/scope/computer_groups/computer_group[$INDEX]/id/text()" 2> /dev/null`)
		done
	fi
done


	#################
	# OS X PROFILES #
	#################


#	get profiles xml
PROFILES=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/osxconfigurationprofiles`


#	get count of profiles
PROFILES_COUNT=`echo $PROFILES | /usr/bin/xpath "/os_x_configuration_profiles/size/text()" 2> /dev/null`
if $DEBUG; then echo "PROFILE ID COUNT: $PROFILES_COUNT"; fi

#	enumerate profiles for ids
for (( INDEX=1; INDEX<=$PROFILES_COUNT; INDEX++ )); do
	PROFILE_IDS+=(`echo $PROFILES | /usr/bin/xpath "/os_x_configuration_profiles/os_x_configuration_profile[$INDEX]/id/text()" 2> /dev/null`)
done


for PROFILE_ID in ${PROFILE_IDS[@]}; do 

	#	get xml for individual profile based on id
	PROFILE_GROUPS=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/osxconfigurationprofiles/id/$PROFILE_ID/subset/scope`
	
	#	get count of computer groups the individual profile is scoped
	PROFILE_GROUPS_COUNT=`echo $PROFILE_GROUPS | /usr/bin/xpath "count(/os_x_configuration_profile/scope/computer_groups/computer_group)" 2> /dev/null`
    if $DEBUG; then echo " GROUPS FOUND: $PROFILE_GROUPS_COUNT"; fi	
	
	#	enumerate computers groups within profile
	if [ $PROFILE_GROUPS_COUNT -ne 0 ]; then
		for (( INDEX=1; INDEX<=$PROFILE_GROUPS_COUNT; INDEX++ )); do
			
			SCOPED_GROUP_IDS+=(`echo $PROFILE_GROUPS | /usr/bin/xpath "os_x_configuration_profile/scope/computer_groups/computer_group[$INDEX]/id/text()" 2> /dev/null`)
		done
	fi
done


#	sort and remove duplicate ids
SCOPED_GROUP_IDS=( `for i in ${SCOPED_GROUP_IDS[@]}; do echo $i; done | sort -u` )


#	enumerate known scoped computer groups and remove them from total
for SCOPED_GROUP_ID in ${SCOPED_GROUP_IDS[@]}; do
	for (( INDEX=0; INDEX<=($COMPUTER_GROUPS_COUNT-1); INDEX++ )); do
		if [[ $SCOPED_GROUP_ID -eq ${COMPUTER_GROUP_IDS[$INDEX]} ]]; then
			unset COMPUTER_GROUP_IDS[$INDEX]
			break
		fi
	done	
done


#	display output as ids or names
for COMPUTER_GROUP_ID in  ${COMPUTER_GROUP_IDS[@]}; do
	if $DISPLAY_GROUP_NAMES; then
		echo $COMPUTER_GROUPS | /usr/bin/xpath "/computer_groups/computer_group[id=$COMPUTER_GROUP_ID]/name/text()" 2> /dev/null; echo $'\r'
	else
		echo $COMPUTER_GROUP_ID
	fi
done	
	

#	prompt to continue process and delete un-scoped computer groups
if $PROMPT_TO_DELETE && [[ ${#COMPUTER_GROUP_IDS[@]} -ne 0 ]]; then 

	#	audible alert
	/usr/bin/afplay /System/Library/Sounds/Glass.aiff
	
	#	prompt
	echo "Do you want to delete the computer groups that are NOT scoped to any policy or profile? [Y/N]"
	read DELETE_GROUPS
	
	#	exit if no
	case $DELETE_GROUPS in
	    [nN][oO]|[nN]) 
			exit 0
	        ;;
	esac
fi 	


#	make backup folder
BACKUP_PATH=`/usr/bin/mktemp -d ~/Desktop/Un-Scoped\ Computer\ Groups\.XXXX`


#	enumerate un-scoped computer groups and delete 
for COMPUTER_GROUP_ID in  ${COMPUTER_GROUP_IDS[@]}; do
	
	#	backup id to xml before deleting
	/usr/bin/curl -X GET -H"Accept: application/xml" -s -u $JSS_USER:$JSS_PASSWORD ${JSS_URL%/}/JSSResource/computergroups/id/$COMPUTER_GROUP_ID -o "$BACKUP_PATH/$COMPUTER_GROUP_ID.xml"
	
	#	delete un-scoped computer group
	/usr/bin/curl -sk -u $JSS_USER:$JSS_PASSWORD -o /dev/null ${JSS_URL%/}/JSSResource/computergroups/id/$COMPUTER_GROUP_ID -X DELETE	
done


#	audible completion sound
/usr/bin/afplay /System/Library/Sounds/Glass.aiff


