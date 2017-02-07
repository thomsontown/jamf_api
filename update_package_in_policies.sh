#!/bin/bash

#    This script was written to provide a consistent way to updated
#    JAMF PRO policies that reference outdated package files. The 
#    idea is to search for a unique string that will identify all policies 
#    that deploy a common package. For example, your JAMF PRO server 
#    may have multiple policies deploying the latest Firefox to various 
#    sites, while others may target updates or Self-Service options. 

#    Once an updated package has been uploaded to the JAMF PRO server,
#    you can run this script and optionally include a case-sensitive
#    search string as a parameter. If no search string is provided, the 
#    script will prompt for one during runtime. The partial string should
#    target package names that contain different versions of the same 
#    installer package.

#    The script will then enumerate all package names that match the 
#    provided search string and then find all the policies that reference
#    those packages. The latest matching package (highest id) will be the
#    package used to update outdated packages (lesser matching package ids)
#    contained within existing policies.

#    So if your JAMF PRO server just received the latest installer package 
#    for Firefox, but the server has 3 references to an outdated Firefox 
#    package, the script will provide 3 separate prompts asking you if
#    you want it to update each policy with the latest Firefox package. 

#    This script works in a similar fashion found within Casper Admin, 
#    where you can right-click on a package and select "Replace in all 
#    Configurations with..." and then you get to select which package to
#    replace. The only difference is this script works against packages
#    within policies instead of configurations.

#    The script only updates the package ID and NAME within a policy. 
#    If a polcy has multiple packages, only the package that matches the
#    search string will be affect. Similarly, if a package was set to 
#    "Cache" or "Install Cached", those actions will remain unchange.   

#    The script contains variables where you can add a JSS_USER name and 
#    JSS_PASSWORD to avoid prompting during runtime. The credentials you
#    provide will need to have access to the APIs and to update policy records. 

#    Author:        Andrew Thomson
#    Date:          12-04-2016
#    GitHub:        https://github.com/thomsontown


#JSS_USER=""		#	Un-comment this line and add your login name if different from your os x login account.
#JSS_PASSWORD=""	#	Un-comment this line and add your password to prevent being prompted each time.
DEBUG=false
VERSION="1.02"


#	load common source variables
if [ -f ~/.bash_source ]; then
	source ~/.bash_source
fi


#	if no jss url path specified
#	then read from preference file
if [ -z $JSS_URL ]; then 

	#	if no jss url found in preference file
	#	then display error
	if ! JSS_URL=`/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url`; then
		echo "ERROR: Unable to read default url."
		exit $LINENO
	fi
fi


#	if no jss user name specified
#	then use current user name
if [ -z $JSS_USER ]; then
	JSS_USER=$USER
fi 


#	if no jss password specified
#	then prompt user to enter
if [ -z $JSS_PASSWORD ]; then 
	echo "Please enter JSS password for account: $USER."
	read -s JSS_PASSWORD
fi


#	prompt for partial word search to match 
#	with package names
if [ -z $1 ]; then 
	echo "Please enter a partial package name to search:"
	read "SEARCH"
else
	SEARCH=$1
fi


#	get ids of packages that match the partial word search
MATCHING_PACKAGES=(`/usr/bin/curl -X GET -H "Accept: application/xml" -su ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/packages | /usr/bin/xpath "/packages/package//./name[contains(.,'$SEARCH')]/../id" 2> /dev/null | /usr/bin/awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`)


#	sort array from oldest id to newest
MATCHING_PACKAGES=(`/usr/bin/printf "%s\n" "${MATCHING_PACKAGES[@]}" | /usr/bin/sort -n`)
if $DEBUG; then echo "MATCHING PACKAGE IDS: ${MATCHING_PACKAGES[@]}"; fi


#	two or more packages are required for the possibility
#	of updating to the most recent package
if [ ${#MATCHING_PACKAGES[@]} -eq 1 ]; then
	echo "ERROR: Only 1 package was found containing the string \"$SEARCH\"."
	exit $LINENO
elif [ ${#MATCHING_PACKAGES[@]} -eq 0 ]; then
	echo "ERROR: No packages were found containing the string \"$SEARCH\"."
	exit $LINENO
fi


#	display the count of packages that match
#	the search string
echo "MATCHING PACKAGES: ${#MATCHING_PACKAGES[@]}"


#	get newest matching package	(last id in array)
NEWEST_PACKAGE_ID="${MATCHING_PACKAGES[${#MATCHING_PACKAGES[@]}-1]}"
if $DEBUG; then echo "NEWEST ID: $NEWEST_PACKAGE_ID"; fi


#	get name of newest matching package
NEWEST_PACKAGE_NAME=`/usr/bin/curl -X GET -H "Accept: application/xml" -su ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/packages/id/$NEWEST_PACKAGE_ID | /usr/bin/xpath "/package/name/text()" 2> /dev/null`	
if [ -z "$NEWEST_PACKAGE_NAME" ]; then
	echo "ERROR: Unable to retrieve package name."
	exit $LINENO
fi
if $DEBUG; then echo "NEWEST NAME: $NEWEST_PACKAGE_NAME"; fi


#	remove the newest package from array
#	no need to search for updated policies
unset MATCHING_PACKAGES[${#MATCHING_PACKAGES[@]}-1]


#	get ids of all policies to enumerate 
ALL_POLICIES=(`/usr/bin/curl -X GET -H"Accept: application/xml" -su ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/policies/createdBy/jss | /usr/bin/xpath "//id" 2> /dev/null | /usr/bin/awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`)
echo "TOTAL POLICIES: ${#ALL_POLICIES[@]}"


#	set static count of policies to enumerate
POLICIES_COUNT=${#ALL_POLICIES[@]}


#	enumerate policies 
for INDEX in ${!ALL_POLICIES[@]}; do

	#	get ids of all packages found within current policy
	POLICY_PACKAGES=(`/usr/bin/curl -X GET -H"Accept: application/xml" -su ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/policies/id/${ALL_POLICIES[$INDEX]}/subset/packages | /usr/bin/xpath "//id" 2> /dev/null | /usr/bin/awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`)

	#	enumerate each package id internal to the current policy
	for POLICY_PACKAGE in ${POLICY_PACKAGES[@]}; do

		#	enumerate each mactching pacakge id 
		for MATCHING_PACKAGE in ${MATCHING_PACKAGES[@]}; do

			#	if the current package id matches up against 
			#	one of the package ids found in the original 
			#	string query then set the FOUND flag to true
			if [[ "$POLICY_PACKAGE" == "$MATCHING_PACKAGE" ]]; then
				OUTDATED_POLICY_PACKAGE+=(${ALL_POLICIES[$INDEX]}:$MATCHING_PACKAGE)
			fi
		done
	done

	#	display current policy number compared 
	#	to the total count of policies
	echo -ne "\b\b\b\b\b\b\b\b\b$(($INDEX+1))/$POLICIES_COUNT"
done


#	display the count of policies that contain an outdated package id
echo -e "\b\b\b\b\b\b\b\b\bOUTDATED POLICIES: ${#OUTDATED_POLICY_PACKAGE[@]}"


#	display debug info - policy id contraining outdated package : id of outdated pacakge in the policy
if $DEBUG; then echo "OUTDATED POLICY & PACKAGE: ${OUTDATED_POLICY_PACKAGE[@]}"; fi


#	enumerate policies that may need updating
for POLICY_PACKAGE in ${OUTDATED_POLICY_PACKAGE[@]}; do

	#	display debug info - current policy id
	if $DEBUG; then echo "CURRENT POLICY ID: ${POLICY_PACKAGE%:*}"; fi

	#	display debug info - current package id
	if $DEBUG; then echo "CURRENT PACKAGE ID: ${POLICY_PACKAGE##*}"; fi

	#	get the name of the current policy
	POLICY_NAME=`/usr/bin/curl -X GET -H "Accept: application/xml" -su ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/policies/id/${POLICY_PACKAGE%:*} | /usr/bin/xpath "/policy/general/name/text()" 2> /dev/null`	
	if $DEBUG; then echo "CURRENT POLICY NAME: $POLICY_NAME"; fi

	#	get the name of the current package
	CURRENT_PACKAGE_NAME=`/usr/bin/curl -X GET -H "Accept: application/xml" -su ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/packages/id/${POLICY_PACKAGE##*:} | /usr/bin/xpath "/package/name/text()" 2> /dev/null`	
	if $DEBUG; then echo "CURRENT PACKAGE NAME: $CURRENT_PACKAGE_NAME"; fi

	#	prompt to update policy with new package
	echo "Updated the policy \"$POLICY_NAME\" and replace \"$CURRENT_PACKAGE_NAME\" with \"$NEWEST_PACKAGE_NAME\"? [y/n]"
	read UPDATE

	#	begin update process
	if [ "$UPDATE" == "y" ]; then

		#	get xml for the current policy
		POLICY_XML=`/usr/bin/curl -X GET -H "Accept: application/xml" -su ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/policies/id/${POLICY_PACKAGE%:*}/subset/packages 2> /dev/null | /usr/bin/xmllint --format -`
		
		#	search and replace original pacakge id with the newest package id
		POLICY_XML="${POLICY_XML/${POLICY_PACKAGE##*:}/$NEWEST_PACKAGE_ID}"

		#	search and replace original package name with the newest package name
		POLICY_XML="${POLICY_XML/$CURRENT_PACKAGE_NAME/$NEWEST_PACKAGE_NAME}"

		#	update the policy now pointing to the new package
		HTTP_CODE=`/usr/bin/curl -w "%{http_code}" -f -s -k -u "${JSS_USER}:${JSS_PASSWORD}" -d "${POLICY_XML}" -o /dev/null -H "Content-Type: application/xml" -X 'PUT' "${JSS_URL%/}/JSSResource/policies/id/${POLICY_PACKAGE%:*}"`
		
		#	display error message and return code on error
		if [ "$HTTP_CODE" != "201" ]; then 
			echo "ERROR: Unable to update policy. [$HTTP_CODE]"
			exit $LINENO
		fi
	else 
		echo "Not updating \"$POLICY_NAME\"."
	fi
done
