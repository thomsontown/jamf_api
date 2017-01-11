#!/bin/bash

#	This script determines the closest distribution point to the client 
#	(based on response times) and then updates the default setting for the 
#	computer within the JSS. The script does NOT evaluate distribution 
#	servers (JDS), only file share distribution points listed in the JSS. 

#	This script should be added to the JSS with a policy trigger set to
#	"Network State Change" and the frequency set to "Ongoing".

#	Author:		Andrew Thomson 
#	Date:		10-12-2016


JSS_USER=""			#	add jss api user name
JSS_PASSWORD=""		#	add jss api user password∫
DEFAULT_AVG="1000"
DEBUG=true
COMPUTER_UUID=`/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }'` 


function onExit() {
	echo  "Exited with code #$? after $SECONDS second(s)."
}


#	make sure to cleanup on exit
trap onExit EXIT


#	exit if credentials are missing
if [ -z "$JSS_USER" -o -z "$JSS_PASSWORD" ]; then
	echo "ERROR: Missing credentials."
	exit $LINENO
fi


#	get jss url
if ! JSS_URL=`/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url`; then
	echo "ERROR: Unable to read JSS url."
	exit $LINENO
fi


#	make sure jss is available
JSS_CONNECTION=`/usr/bin/curl --connect-timeout 10 -sw "%{http_code}" ${JSS_URL%/}/JSSCheckConnection -o /dev/null`
if [ $JSS_CONNECTION -ne 200 ]; then
	echo "ERROR: Unable to connect to JSS."
	exit $LINENO
fi


#	get computer id
COMPUTER_ID=`/usr/bin/curl -X GET -H "Accept: application/xml" -su ${JSS_USER}:${JSS_PASSWORD} "${JSS_URL%/}/JSSResource/computers/udid/${COMPUTER_UUID}" | /usr/bin/xpath "/computer[1]/general[1]/id[1]/node()[1]" 2> /dev/null`


#	error if no computer object found 
if [ -z $COMPUTER_ID ]; then
	echo "ERROR: No corresponding computer object found."
	exit $LINENO
fi


#	get xml list of distribution points
ARRAY_IDS=(`/usr/bin/curl --connect-timeout 10 -su ${JSS_USER}:${JSS_PASSWORD} -H 'Content-Type: application/xml' -X 'GET' ${JSS_URL%/}/JSSResource/distributionpoints | /usr/bin/xpath "//id" 2> /dev/null | /usr/bin/awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`)


#	enumerate the array of distribution point ids and get ping response times
for ARRAY_ID in ${ARRAY_IDS[@]}; do

	#	get xml list of attributes for specified distribution point
	DP_XML=`/usr/bin/curl --connect-timeout 10 -su ${JSS_USER}:${JSS_PASSWORD} -H 'Content-Type: application/xml' -X 'GET' ${JSS_URL%/}/JSSResource/distributionpoints/id/$ARRAY_ID`
	
	#	check if distribution point is master
	IS_MASTER=$(/usr/bin/xpath "//is_master/text()" <<< ${DP_XML} 2> /dev/null)
	if [[ $IS_MASTER == true ]]; then DEFAULT_MASTER="$ARRAY_ID"; fi
	
	#	get ip address for the specified distribution point
	IP_ADDRESS=$(/usr/bin/xpath "//ip_address/text()" <<< ${DP_XML} 2> /dev/null)
	
	#	ping address to retrieve average roundtrip time
	PACKET_AVG=`/sbin/ping -W 5 -c 1 -q ${IP_ADDRESS} 2> /dev/null | /usr/bin/awk -F '/' '/round\-trip/{ print $5 }'`
		
	#	only work with servers that respond
	if [[ -n $PACKET_AVG ]]; then
		
		#	display current id and address
		if $DEBUG; then /usr/bin/printf "ID: $ARRAY_ID \t SERVER: ${IP_ADDRESS} \t AVG: $PACKET_AVG \n"; fi
		
		#	compare values
		IS_LESS=`echo "$PACKET_AVG < $DEFAULT_AVG" | /usr/bin/bc -l 2> /dev/null`
		
		#	if new ave is less than previous, update default
		if [[ "$IS_LESS" == "1" ]]; then
			DEFAULT_ID="$ARRAY_ID"
			DEFAULT_SERVER="$IP_ADDRESS"
			DEFAULT_AVG="$PACKET_AVG"
		fi	
	fi
done


 #	check if master found
if [ -z $DEFAULT_MASTER ]; then
	echo "ERROR: Unable to find master server."
	exit $LINENO
fi


#	display master server
if $DEBUG; then echo "MASTER: $DEFAULT_MASTER"; fi
	

#	exit if no servers found
if [ -z $DEFAULT_SERVER ] &&  [ -z $DEFAULT_MASTER ]; then
	echo "ERROR: No servers could be found."
	exit $LINENO
fi


#	if master is found but no distribution points are found, set default to master
if [ -z $DEFAULT_SERVER ] &&  [ -n $DEFAULT_MASTER ]; then
	DEFAULT_ID="$DEFAULT_MASTER"
fi


#	get name of server associated with the id
DEFAULT_NAME=`/usr/bin/curl -X GET -H "Accept: application/xml" -su ${JSS_USER}:${JSS_PASSWORD} "${JSS_URL%/}/JSSResource/distributionpoints/id/$DEFAULT_ID" | /usr/bin/xpath "/distribution_point[1]/name[1]/node()[1]" 2> /dev/null`
if $DEBUG; then /usr/bin/printf "DEFAULT: \n ID: $DEFAULT_ID \n NAME: $DEFAULT_NAME \n SERVER: $DEFAULT_SERVER \n AVG: $DEFAULT_AVG \n MASTER: $DEFAULT_MASTER \n"; fi


#	format xml data to update computer's default distribution point
XML_TEMPLATE="
	<computer>
		<general>
			<distribution_point>
				$DEFAULT_NAME
			</distribution_point>
		</general>
	</computer>"

	
#	update the default distribution point assocaited with this computer
HTTP_CODE=`/usr/bin/curl -w "%{http_code}" -f -s -k -u "${JSS_USER}:${JSS_PASSWORD}" -d "${XML_TEMPLATE}" -o /dev/null -H "Content-Type: application/xml" -X 'PUT' "${JSS_URL%/}/JSSResource/computers/id/${COMPUTER_ID}"`
if [ "$HTTP_CODE" != "201" ]; then 
	echo "ERROR: Unable to update default distribution point. [$HTTP_CODE]"
	exit $LINENO
fi