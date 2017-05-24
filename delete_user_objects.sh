#!/bin/bash


#    This script is incomplete due to the fact that not all features within our JSS
#    are being utilized and therefore some associations will not be encoutered in
#    our specific environment. 

#    This script was written to delete users form the JSS. To do so, various 
#    assocaiations may need to be stripped by the script before the user object can 
#    be deleted. Currently only "computer", "peripherals" and "vpp assignments" 
#    assocaiations are being stripped. 

#    This script relies on the 3rd party command "xmlstarlet" for easy editing of
#    XML data. 

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


#	check for xmlstarlet
if ! /usr/bin/which xmlstarlet &> /dev/null; then
	(>&2 /bin/echo "ERROR: Unable to locate required command: xmlstarlet.")
	exit $LINENO
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
		/bin/echo "USER ID:	$USER_ID"	
		/bin/echo "COMPUTERS:       ${#COMPUTERS[@]}"
		/bin/echo "PERIPHERALS:     ${#PERIPHERALS[@]}"
		/bin/echo "MOBILE DEVICES:  ${#MOBILE_DEVICES[@]}"
		/bin/echo "VPP ASSIGNMENTS: ${#VPP_ASSIGNMENTS[@]}"
	fi


	for COMPUTER in ${COMPUTERS[@]}; do
		XML=`/usr/bin/curl -X GET -H "Content-Type: application/xml" -s -u "${JSS_USER}:${JSS_PASSWORD}" "${JSS_URL%/}/JSSResource/computers/id/$COMPUTER" | xmlstarlet ed -d computer/location`
		XML=`/bin/echo $XML | xmlstarlet ed -s computer -t elem -n location`
		XML=`/bin/echo $XML | xmlstarlet ed -s computer/location -t elem -n username`
		XML=`/bin/echo $XML | xmlstarlet ed -s computer/location -t elem -n realname`
		XML=`/bin/echo $XML | xmlstarlet ed -s computer/location -t elem -n real_name`
		XML=`/bin/echo $XML | xmlstarlet ed -s computer/location -t elem -n email_address`
		XML=`/bin/echo $XML | xmlstarlet ed -s computer/location -t elem -n position`
		XML=`/bin/echo $XML | xmlstarlet ed -s computer/location -t elem -n phone`
		XML=`/bin/echo $XML | xmlstarlet ed -s computer/location -t elem -n phone_number`
		XML=`/bin/echo $XML | xmlstarlet ed -s computer/location -t elem -n department`
		XML=`/bin/echo $XML | xmlstarlet ed -s computer/location -t elem -n building`
		XML=`/bin/echo $XML | xmlstarlet ed -s computer/location -t elem -n room`
		DID_UPDATE_COMPUTER=`/usr/bin/curl -X PUT -H "Content-Type: application/xml" -w "%{http_code}" -s -u "${JSS_USER}:${JSS_PASSWORD}" -o /dev/null -d "$XML" "${JSS_URL%/}/JSSResource/computers/id/$COMPUTER"`
		if [ $DID_UPDATE_COMPUTER -eq 201 ]; then 
			/bin/echo " UPDATED COMPUTER ID: $COMPUTER"
		else
			(>&2 /bin/echo " FAILED COMPUTER ID: $COMPUTER")
		fi
	done

	for PERIPHERAL in ${PERIPHERALS[@]}; do
		XML=`/usr/bin/curl -X GET -H "Content-Type: application/xml" -s -u "${JSS_USER}:${JSS_PASSWORD}" "${JSS_URL%/}/JSSResource/computers/id/$PERIPHERAL" | xmlstarlet ed -d peripheral/location`
		XML=`/bin/echo $XML | xmlstarlet ed -s peripheral -t elem -n location`
		XML=`/bin/echo $XML | xmlstarlet ed -s peripheral/location -t elem -n username`
		XML=`/bin/echo $XML | xmlstarlet ed -s peripheral/location -t elem -n realname`
		XML=`/bin/echo $XML | xmlstarlet ed -s peripheral/location -t elem -n real_name`
		XML=`/bin/echo $XML | xmlstarlet ed -s peripheral/location -t elem -n email_address`
		XML=`/bin/echo $XML | xmlstarlet ed -s peripheral/location -t elem -n position`
		XML=`/bin/echo $XML | xmlstarlet ed -s peripheral/location -t elem -n phone`
		XML=`/bin/echo $XML | xmlstarlet ed -s peripheral/location -t elem -n phone_number`
		XML=`/bin/echo $XML | xmlstarlet ed -s peripheral/location -t elem -n department`
		XML=`/bin/echo $XML | xmlstarlet ed -s peripheral/location -t elem -n building`
		XML=`/bin/echo $XML | xmlstarlet ed -s peripheral/location -t elem -n room`
		/usr/bin/curl -X PUT -H "Content-Type: application/xml" -w "%{http_code}" -s -u "${JSS_USER}:${JSS_PASSWORD}" -d "$XML" "${JSS_URL%/}/JSSResource/peripherals/id/$PERIPHERAL -o /dev/null"
	done

	for VPP_ASSIGNMENT in ${VPP_ASSIGNMENTS[@]}; do
		XML=`/usr/bin/curl -X GET -H "Content-Type: application/xml" -s -u "${JSS_USER}:${JSS_PASSWORD}" "${JSS_URL%/}/JSSResource/vppassignments/id/$VPP_ASSIGNMENT" | xmlstarlet ed -d vpp_assignment/scope/jss_users/user[id=$USER_ID]`
		/usr/bin/curl -X PUT -H "Content-Type: application/xml" -w "%{http_code}" -s -u "${JSS_USER}:${JSS_PASSWORD}" -d "$XML" "${JSS_URL%/}/JSSResource/vppassignments/id/$VPP_ASSIGNMENT  -o /dev/null"
	done

	if [ -n "$USER_ID" ]; then DID_DELETE=`/usr/bin/curl -X DELETE -H "Content-Type: application/xml" -w "%{http_code}" -o /dev/null -s -u "${JSS_USER}:${JSS_PASSWORD}" "${JSS_URL%/}/JSSResource/users/id/$USER_ID"`
		if [ $DID_DELETE -eq 200 ]; then 
			/bin/echo "DELETED USER ID: $USER_ID"
		else
			(>&2 /bin/echo "FAILED USER ID: $USER_ID")
		fi
	fi
done



