#!/bin/bash


#    This script was written to delete users form the JSS. To do so, this script
#    enumerates user associations and tries to remove them before deleting the 
#    user object. Not ALL user associations are covered within this script because
#    they are not present in our environment. 


#    Author:        Andrew Thomson
#    Date:          05-16-2017
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


#	check for arguments and display usage
if [ $# -eq 0 ]; then 
	/bin/echo "USAGE: ${0##*/} [user_id user_id user_id] or [user_name user_name user_name]"
	exit $LINENO
else 
	ARGUMENTS=("$@")
fi


#	enumerate users to delete
for JUSER in ${ARGUMENTS[@]}; do
	if isInteger "$JUSER"; then
		#	get user data from id
		XML_USER=`/usr/bin/curl -X GET -H "Content-Type: application/xml" -s -u "${JSS_USER}:${JSS_PASSWORD}" "${JSS_URL%/}/JSSResource/users/id/$JUSER" 2> /dev/null`
	else
		#	get user data from name
		XML_USER=`/usr/bin/curl -X GET -H "Content-Type: application/xml" -s -u "${JSS_USER}:${JSS_PASSWORD}" "${JSS_URL%/}/JSSResource/users/name/$JUSER" 2> /dev/null`
	fi

	#	get user id
	USER_ID=`/bin/echo $XML_USER | /usr/bin/xpath "/user/id/text()" 2> /dev/null`

	#	get array of associated computer ids
	COMPUTERS=(`/bin/echo $XML_USER | /usr/bin/xpath  "/user/links/computers//computer/id" 2> /dev/null | /usr/bin/awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`)
	
	#	get array of associated peripheral ids
	PERIPHERALS=(`/bin/echo $XML_USER | /usr/bin/xpath  "/user/links/peripherals//peripheral/id" 2> /dev/null | /usr/bin/awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`)

	#	get array of associated mobile device ids
	MOBILE_DEVICES=(`/bin/echo $XML_USER | /usr/bin/xpath  "/user/links/mobile_devices//mobile_device/id" 2> /dev/null | /usr/bin/awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`)

	#	get array of assocaiated vpp assignments
	VPP_ASSIGNMENTS=(`/bin/echo $XML_USER | /usr/bin/xpath  "/user/links/vpp_assignments//vpp_assignment/id" 2> /dev/null | /usr/bin/awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`)

	#	display debug info
	if $DEBUG; then 
		/bin/echo
		/bin/echo "USER ID:	 $USER_ID"	
		/bin/echo "COMPUTERS:       ${#COMPUTERS[@]}"
		/bin/echo "PERIPHERALS:     ${#PERIPHERALS[@]}"
		/bin/echo "MOBILE DEVICES:  ${#MOBILE_DEVICES[@]}"
		/bin/echo "VPP ASSIGNMENTS: ${#VPP_ASSIGNMENTS[@]}"
	fi

	#	remove user association from computers
	for COMPUTER in ${COMPUTERS[@]}; do
		XML="<computer><general><id>$COMPUTER</id></general><location><username/><realname/><real_name/><email_address/><position/><phone/><phone_number/><department/><building/><room/></location></computer>"
		RETURN_CODE=`/usr/bin/curl -X PUT -H "Content-Type: application/xml" -w "%{http_code}" -s -u "${JSS_USER}:${JSS_PASSWORD}" -o /dev/null -d "$XML" "${JSS_URL%/}/JSSResource/computers/id/$COMPUTER"`
		if [ "$RETURN_CODE" -eq 201 ]; then 
			/bin/echo " UPDATED COMPUTER ID: $COMPUTER"
		else
			(>&2 /bin/echo " FAILED COMPUTER ID: $COMPUTER")
		fi
	done

	#	remove user association from peripherals
	for PERIPHERAL in ${PERIPHERALS[@]}; do
		XML="<peripheral><general><id>$PERIPHERAL</id></general><location><username/><realname/><real_name/><email_address/><position/><phone/><phone_number/><department/><building/><room/></location></peripheral>"
		RETURN_CODE=`/usr/bin/curl -X PUT -H "Content-Type: application/xml" -w "%{http_code}" -o /dev/null -s -u "${JSS_USER}:${JSS_PASSWORD}" -d "$XML" "${JSS_URL%/}/JSSResource/peripherals/id/$PERIPHERAL"`
		if [ "$RETURN_CODE" -eq 201 ]; then 
			/bin/echo " UPDATED PERIPHERAL ID: $PERIPHERAL"
		else
			(>&2 /bin/echo " FAILED PERIPHERAL ID: $PERIPHERAL")
		fi
	done

	#	remove user association from mobile devices
	for MOBILE_DEVICE in ${MOBILE_DEVICES[@]}; do
		XML="<mobile_device><general><id>$MOBILE_DEVICE</id></general><location><username/><realname/><real_name/><email_address/><position/><phone/><phone_number/><department/><building/><room/></location></mobile_device>"
		RETURN_CODE=`/usr/bin/curl -X PUT -H "Content-Type: application/xml" -w "%{http_code}" -o /dev/null -s -u "${JSS_USER}:${JSS_PASSWORD}" -d "$XML" "${JSS_URL%/}/JSSResource/mobiledevices/id/$MOBILE_DEVICE"`
		if [ "$RETURN_CODE" -eq 201 ]; then 
			/bin/echo " UPDATED MOBILE_DEVICE ID: $MOBILE_DEVICE"
		else
			(>&2 /bin/echo " FAILED MOBILE_DEVICE ID: $MOBILE_DEVICE")
		fi
	done

	#	remove user association from vpp assignments
	if [ ${#VPP_ASSIGNMENTS[@]} -ne 0 ]; then VPP_ASSIGNMENTS=(`/usr/bin/curl -X GET -H "Content-Type: application/xml" -s -u "${JSS_USER}:${JSS_PASSWORD}" "${JSS_URL%/}/JSSResource/vppassignments" 2> /dev/null | /usr/bin/xpath  "/vpp_assignments//vpp_assignment/id" 2> /dev/null | /usr/bin/awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`); fi
	for VPP_ASSIGNMENT in ${VPP_ASSIGNMENTS[@]}; do
		XML=`/usr/bin/curl -X GET -H "Content-Type: application/xml" -s -u "${JSS_USER}:${JSS_PASSWORD}" "${JSS_URL%/}/JSSResource/vppassignments/id/$VPP_ASSIGNMENT"`
		USER_NODE=`/bin/echo $XML | /usr/bin/xpath "/vpp_assignment/scope/jss_users/user[id=$USER_ID]" 2> /dev/null`

		#	if user found in scope then remove
		if [ -n "$USER_NODE" ]; then
			RETURN_CODE=`/usr/bin/curl -X PUT -H "Content-Type: application/xml" -w "%{http_code}" -o /dev/null -s -u "${JSS_USER}:${JSS_PASSWORD}" -d "${XML/$USER_NODE/}" "${JSS_URL%/}/JSSResource/vppassignments/id/$VPP_ASSIGNMENT"`
			if [ "$RETURN_CODE" -eq 201 ]; then 
				/bin/echo " UPDATED VPP_ASSIGNMENT ID: $VPP_ASSIGNMENT"

				#	allow time for scope to recalculate
				/bin/sleep 5 
			fi
		fi
	done

	#	delete user
	if [ -n "$USER_ID" ]; then RETURN_CODE=`/usr/bin/curl -X DELETE -H "Content-Type: application/xml" -w "%{http_code}" -o /dev/null -s -u "${JSS_USER}:${JSS_PASSWORD}" "${JSS_URL%/}/JSSResource/users/id/$USER_ID"`
		if [ $RETURN_CODE -eq 200 ]; then 
			/bin/echo "DELETED USER ID: $USER_ID"
		else
			(>&2 /bin/echo "FAILED USER ID: $USER_ID")
		fi
	fi
done