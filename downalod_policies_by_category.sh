#!/bin/sh

#JSS_USER=""		#	Un-comment this line and add your login name if different from your os x login account.
#JSS_PASSWORD=""	#	Un-comment this line and add your password to prevent being prompted each time.
IFS=$'\r'
DESTINATION="$HOME/Desktop/JSS_POLICY_XML"


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


if [ ! -d "$DESTINATION" ]; then 
	if ! /bin/mkdir -p -m 755 "$DESTINATION"; then
		echo "ERROR: Unable to create destination folder [$DESTINATION]." >&2
		exit $LINENO
	fi
fi


#	get categories
XML_CATEGORIES=(`/usr/bin/curl -X GET -H "Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL}JSSResource/categories 2> /dev/null`)


#	get count of categories
CATEGORIES_COUNT=`echo $XML_CATEGORIES | /usr/bin/xpath "count(//category)" 2> /dev/null`


#	enumerate category names
for ((INDEX=1;INDEX<=$CATEGORIES_COUNT;INDEX++)); do 
	# echo $XML_CATEGORIES | /usr/bin/xpath "/categories/category[$INDEX]/name/text()" 2> /dev/null
	CATEGORIES+=(`echo $XML_CATEGORIES | /usr/bin/xpath "/categories/category[$INDEX]/name/text()" 2> /dev/null`)
done


#	display selection prompt
echo "Enter the number that corrosponds to the category of policies to export [1-$CATEGORIES_COUNT]."
select CATEGORY in "${CATEGORIES[@]}"; do
	if [ "$REPLY" -gt "$CATEGORIES_COUNT" -o "$REPLY" -lt 1 ]; then 
		echo "User canceled."
		exit
	fi
	break
done


#	url encode name
CATEGORY=`/usr/bin/python -c "import urllib, sys; print urllib.quote(sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()[0:-1])" "$CATEGORY"`


#	get xml formatted data
XML_POLICIES=`/usr/bin/curl -X GET -H "Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL}JSSResource/policies/category/$CATEGORY`

 
#	get count of policies
POLICIES_COUNT=`echo $XML_POLICIES | /usr/bin/xpath "/policies/size/text()" 2> /dev/null`
	
	
#	eunmerate policy by id
for (( INDEX=1; INDEX<=$POLICIES_COUNT; INDEX++ )); do
	
		#	get id of current policy 
		CURRENT_POLICY_ID=`echo $XML_POLICIES | /usr/bin/xpath "/policies/policy[$INDEX]/id/text()" 2> /dev/null`
			
		#	get xml formatted data for current policy 	
		XML_CURRENT_POLICY_ID=`/usr/bin/curl -X GET -H "Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL}JSSResource/policies/id/${CURRENT_POLICY_ID} | /usr/bin/xmllint --format -`
		
		#	get name of current policy
		CURRENT_POLICY_NAME=`echo $XML_CURRENT_POLICY_ID | /usr/bin/xpath "/policy/general/name/text()" 2> /dev/null`
		echo "Downloading: $CURRENT_POLICY_NAME"


		if ! echo "$XML_CURRENT_POLICY_ID" > "${DESTINATION%/}/${CURRENT_POLICY_NAME}.xml" 2> /dev/null; then 
			echo "ERROR: Unable to write policy to xml." >&2
		fi
done


#	play sound upon completion
if [ -f /System/Library/Sounds/Glass.aiff ]; then
	/usr/bin/afplay /System/Library/Sounds/Glass.aiff
fi