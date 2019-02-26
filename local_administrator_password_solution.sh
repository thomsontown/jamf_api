#!/bin/bash


#    This script was written to mimic Microsoft's Local Administrator Password Solution (LAPS)
#    but for Macs. The script is intended to run as a script within the JAMF PRO server and 
#    deployed via a policy. The specified RECORD_NAME indicates the local account whose password
#    will be randomized and written to the JAMF PRO database as a pre-defined extention attribute
#    (string). With the proper policy scheduling (check-in, on-going) the frequency of the 
#    password randomization can be configured with the UPDATE_AFTER_DAYS variable setting. One
#    feature of this script comapred with Microsoft's implementation is the use of a pre-determined
#    PASSWORD_SUFFIX common to all randomized passwords to ensure if the database is ever 
#    compromised the required suffix would still be unknown.


#    Author:          Andrew Thomson
#    Date:            10-10-2018
#    GitHub:          https://github.com/thomsontown


JSS_URL=""                              # specify the url to your jss
JSS_USER=""                             # specify jss username with write access to computer objects 
JSS_PASSWORD=""                         # provide jss username password 
RECORD_NAME="macadmin"                  # specify the full user name of an account to verify/create
FORCE="$4"                              # specify any string as the 4th variable to force a random password update
PASSWORD_SUFFIX="tuv"                   # specify a suffix added to the randomized password that will not stored in the jss database
PASSWORD_EXTENSION_ATTRIBUTE_ID=""      # specify the extension attribute id number to store the randomized password
UPDATE_AFTER_DAYS="60"                  # specify after how many days to update a new randomized the pasword


function isRoot () {

	#	verify script run as root
	if [[ $EUID -ne 0 ]]; then

		echo "ERROR: Script must run with root privileges." >&2
		echo -e "\\tUSAGE: sudo \"$0\"" >&2
		return $LINENO
	else
		return 0
	fi
}


function randomizePassword () {

	if ! local PASSWORD=`/usr/bin/openssl rand -base64 100 | /usr/bin/tr -cd '[1-9A-NP-Za-np-z]'`; then
		echo "ERROR: Unable to generate randomized password."
		return $LINENO
	else
		echo ${PASSWORD:3:11}$PASSWORD_SUFFIX
		return 0
	fi
}


function jssCheckConnection () {

	local JSS_CONNECTION=`/usr/bin/curl -s -k --connect-timeout 10 -sw "%{http_code}" "${JSS_URL%/}/JSSCheckConnection" -o /dev/null`
	if [ "$JSS_CONNECTION" -eq 200 ] || [ "$JSS_CONNECTION" -eq 403 ]; then 
		return 0
	else
		return "$JSS_CONNECTION"
	fi
}


function encodeUrl () {

	/usr/bin/python -c "import urllib, sys; print urllib.quote(sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()[0:-1])" "$@"
}


function getUdid () {

	local COMPUTER_UDID=`/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }'` 
	if [ ${#COMPUTER_UDID} -gt 30 ]; then 
		echo $COMPUTER_UDID
		return 0
	else
		echo "ERROR: Unable to determine this systems Unique Device ID (UDID)."
		return $LINENO
	fi
}


function getDateDiff () {

	local FIRST_DATE="$1"
	local SECOND_DATE="$2"

	#	first date is required
	if [ -z "$FIRST_DATE" ]; then 
		echo "ERROR: Missing date parameter." >&2
		return $LINENO
	fi

	# 	second date is optional with current date as the default
	if [ -z "$SECOND_DATE" ]; then 
		local SECOND_DATE=`/bin/date +"%Y-%m-%d %H:%M:%S %z"`
	fi
	
	#	convert first date to epoch
	if ! local FIRST_DATE_EPOCH=`/bin/date -j -f "%Y-%m-%d %H:%M:%S %z" "$FIRST_DATE" +"%s" 2> /dev/null`; then
		echo "ERROR: Unable to convert first date."
		return $LINENO
	fi

	#	convert second date to epoch
	if ! local SECOND_DATE_EPOCH=`/bin/date -j -f "%Y-%m-%d %H:%M:%S %z" "$SECOND_DATE" +"%s" 2> /dev/null`; then
		echo "ERROR: Unable to convert second date."
		return $LINENO
	fi

	#	calculate number of days between the dates
	DATE_DIFF=`/bin/expr \( $SECOND_DATE_EPOCH - $FIRST_DATE_EPOCH \) / 86400 2> /dev/null`
	if [[ $DATE_DIFF =~ ^[-+]?[0-9]+$ ]]; then
		echo $DATE_DIFF
		return 0

	else
		echo "ERROR: Unable to calculate date differential." >&2
		return $LINENO
	fi
}


function jssGetComputerId () {

	local COMPUTER_UDID=`getUdid`
	local COMPUTER_ID=`/usr/bin/curl -X GET -H "Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} "${JSS_URL%/}/JSSResource/computers/udid/$COMPUTER_UDID" | /usr/bin/xpath "//general/id/text()" 2> /dev/null`
	if [ -z $COMPUTER_ID ]; then
		echo "ERROR: Unable to determine computer id." >&2
		return $LINENO
	else 
		echo $COMPUTER_ID
		return 0
	fi
}


function createLocalUser () {

	local REAL_NAME="$1"
	local UNIQUE_ID="$2"
	local ADMIN=$3
	local RECORD_NAME=`echo $REAL_NAME | /usr/bin/tr  '[:upper:]' '[:lower:]' | /usr/bin/tr -d '[:space:]'`
	local MAX_ID=$(($UNIQUE_ID + 10))

	#	verify local user account
	if ! /usr/bin/dscl . -read /Users/"$RECORD_NAME" &>/dev/null; then 

		#	find next available UniqueID
		while [[ $UNIQUE_ID -le $MAX_ID ]]; do
		    USER=`/usr/bin/dscl /Local/Default -search /Users UniqueID "$UNIQUE_ID"| /usr/bin/awk '/UniqueID/ {print $1}' 2> /dev/null`
		    
	    	#	found available UniqueID
		    if [[ -z $USER ]]; then break; fi
			
			#	increment unique id
		    ((UNIQUE_ID++))
		done

		#	error if max id is reached
		if [[ $UNIQUE_ID -eq $MAX_ID ]]; then 
			echo "ERROR: Unable to find a UniqueID within specified range." >&2
			return $LINENO
		fi

		#	error if missing paramters
		if [[ -z $RECORD_NAME ]] || [[ -z $REAL_NAME ]] || [[ -z $UNIQUE_ID ]] || [[ -z $ADMIN ]] || [[ -z PASSWORD ]]; then 
			echo "ERROR: Missing required parameter for user account creation." >&2
			return $LINENO
		fi

		if ! /usr/bin/dscl . create /Users/$RECORD_NAME 2> /dev/null; then 
			echo "ERROR: Unable to create user account [$RECORD_NAME]." >&2
			return $LINENO
		fi

		if ! /usr/bin/dscl . create /Users/$RECORD_NAME RealName "$REAL_NAME" 2> /dev/null; then 
			echo "ERROR: Unable to specify real name [$REAL_NAME] for [$RECORD_NAME]." >&2
			return $LINENO
		fi

		if ! /usr/bin/dscl . create /Users/$RECORD_NAME UserShell /bin/bash 2> /dev/null; then 
			echo "ERROR: Unable to specify shell [/bin/bash] for [$RECORD_NAME]." >&2
			return $LINENO
		fi

		if ! /usr/bin/dscl . create /Users/$RECORD_NAME RecordName $RECORD_NAME 2> /dev/null; then 
			echo "ERROR: Unable to create record name for [$RECORD_NAME]." >&2
			return $LINENO
		fi

		if ! /usr/bin/dscl . create /Users/$RECORD_NAME UniqueID "$UNIQUE_ID" 2> /dev/null; then 
			echo "ERROR: Unable to specify a unique id [$UNIQUE_ID] for [$RECORD_NAME]." >&2
			return $LINENO
		fi

		if ! /usr/bin/dscl . create /Users/$RECORD_NAME PrimaryGroupID 20 2> /dev/null; then 
			echo "ERROR: Unable to assign user [$RECORD_NAME] to primary group [staff]." >&2
			return $LINENO
		fi

		if [[ $UNIQUE_ID -lt 500 ]]; then

			if ! /usr/bin/dscl . create /Users/$RECORD_NAME NFSHomeDirectory /private/var/$RECORD_NAME 2> /dev/null; then
				echo "ERROR: Unable to create home directory [/priave/var/$RECORD_NAME] for [$RECORD_NAME]." >&2
				return $LINENO
			fi
		else
			if ! /usr/bin/dscl . create /Users/$RECORD_NAME NFSHomeDirectory /Users/$RECORD_NAME 2> /dev/null; then
				echo "ERROR: Unable to create home directory [/Users/$RECORD_NAME] for [$RECORD_NAME]."
				return $LINENO
			fi
		fi

		if [[ $UNIQUE_ID -lt 500 ]]; then

			if ! /usr/bin/dscl . create /Users/$RECORD_NAME IsHidden 1 2> /dev/null; then 
				echo "ERROR: Unable to specify account as hidden for [$RECORD_NAME]." >&2
				return $LINENO
			fi
		fi

		if ! /usr/bin/dscl . passwd /Users/$RECORD_NAME ${PASSWORD} 2> /dev/null; then 
			echo "ERROR: Unable to set password for [$RECORD_NAME]." >&2
			return $LINENO
		fi

		if ! /usr/bin/dscl . read /Groups/admin GroupMembership | /usr/bin/grep "$RECORD_NAME" && $ADMIN; then 
			if ! /usr/bin/dscl . append /Groups/admin GroupMembership $RECORD_NAME; then 
				echo "ERROR: Unable to add [$RECORD_NAME] to admin group."
				return $LINENO
			fi
		fi

		if ! /usr/sbin/createhomedir -c -u $RECORD_NAME &> /dev/null; then
			echo "ERROR: Unable to create home directory for spcified user [$RECORD_NAME]."
			return $LINENO
		fi

		return 0 

	else

		echo  "User \"$RECORD_NAME\" already exist."
		return 0
	fi
}


function changePassword () {

	if ! /usr/bin/dscl . passwd /Users/$RECORD_NAME ${PASSWORD} 2> /dev/null; then 
		echo "ERROR: Unable to set password for [$RECORD_NAME]." >&2
		return $LINENO
	fi
}


function jssUpdateExtenstionAttribute () {

	local ATTRIBUTE="<computer>
		<extension_attributes>
			<extension_attribute>
				<id>$PASSWORD_EXTENSION_ATTRIBUTE_ID</id>
				<name>Unique ID</name>
				<type>String</type>
				<value>${PASSWORD:0:11}</value>
			</extension_attribute>
		</extension_attributes>
	</computer>"


	HTTP_CODE=`/usr/bin/curl -X PUT -H "Content-Type: application/xml" -w "%{http_code}" -o /dev/null -s -u "${JSS_USER}:${JSS_PASSWORD}" -d "$ATTRIBUTE" "${JSS_URL%/}/JSSResource/computers/id/${COMPUTER_ID}"`
	if [ "$HTTP_CODE" -ne 201 ]; then
		echo "ERROR: Unable to modify setting [$HTTP_CODE]." >&2
		return $LINENO
	else
		return 0
	fi
}


function main () {

	#	verify root
	if ! isRoot; then 
		exit $LINENO
	fi

	#	generate random password
	PASSWORD=`randomizePassword`

	#	verify jss connectivity
	if ! jssCheckConnection; then
		exit $LINENO
	else

		#	get jss computer id
		if ! COMPUTER_ID=`jssGetComputerId`; then
			exit $LINENO
		fi
	fi

	#	verify account
	if ! /usr/bin/dscl . -read /Users/"$RECORD_NAME" &>/dev/null; then 

		#	create account if missing
		if ! createLocalUser "GAN Super" "501" true; then
			exit $LINENO
		fi

		#	write last update check	
		if ! /usr/bin/defaults write  /Library/Preferences/com.gannett.RandomAdminPassword.plist LastUpdated -string "`/bin/date +"%Y-%m-%d %H:%M:%S %z"`" 2> /dev/null; then
			exit $LINENO
		fi

		#	write updated password to jss
		if ! jssUpdateExtenstionAttribute; then 
			exit $LINENO
		fi

	else

		#	get last update date
		if ! LAST_UPDATED=`/usr/bin/defaults read  /Library/Preferences/com.gannett.RandomAdminPassword.plist LastUpdated 2> /dev/null`; then
			LAST_UPDATED="2017-01-01 00:00:00 -0400"
		fi

		#	get date diff from last updated
		if ! DATE_DIFF=`getDateDiff "$LAST_UPDATED"`; then
			exit $LINENO
		fi

		#	only update password if > 60 days or forced
		if [[ $DATE_DIFF -ge $UPDATE_AFTER_DAYS ]] || [[ -n $FORCE ]]; then

			#	change password if account found
			if ! changePassword "macadmin"; then
				exit $LINENO
			fi

			#	write last update check	
			if ! /usr/bin/defaults write  /Library/Preferences/com.gannett.RandomAdminPassword.plist LastUpdated -string "`/bin/date +"%Y-%m-%d %H:%M:%S %z"`" 2> /dev/null; then
				exit $LINENO
			fi

			#	write updated password to jss
			if ! jssUpdateExtenstionAttribute; then 
				exit $LINENO
			fi
		fi
	fi
}


if [[ "$BASH_SOURCE" == "$0" ]]; then
    main
fi
