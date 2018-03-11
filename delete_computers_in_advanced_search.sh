#!/bin/bash


#    This script targets the computers of an Advanced Search within the JSS 
#    and deletes them. The ID number of the advanced search can be provided
#    below as ADVANCED_COMPUTER_SEARCH_ID or as an argument using the -i 
#    option from the command line. By default, the script identifies the name
#    asscoiated with the search ID and the number of computers found within it.
#    It also prompts [y/n] to delete them all. If the user continues, he or she
#    will be prompted to type in a code number that is displayed in a prompt.
#    If the code enterted matches the code privided by the prompt, the script
#    will attempt to delete all compouters within the Advanced Search. 
#    If the script is to be run from a launch agent or from a cron job the  
#    -a option must be specified to prevent any prompting. 

#    The script outputs to stdout and a log file in $HOME/Library/Logs folder. 
#    USE AT YOUR OWN RISK. 

#    Author:        Andrew Thomson
#    Date:          2018-03-18
#    GitHub:        https://github.com/thomsontown


#JSS_USER=""                        #	Un-comment this line and add your login name if different from your os x login account.
#JSS_PASSWORD=""                    #	Un-comment this line and add your password to prevent being prompted each time.		
#ADVANCED_COMPUTER_SEARCH_ID=""     #   Un-comment this line and add the ID of the Advanced Search to target.
LAUNCH_AGENT=false


 #	load common source variables
if [ -f ~/.bash_source ]; then
	source ~/.bash_source
fi


function log () {
  /bin/echo "`/bin/date +"%b %d %H:%M:%S"` $1" >> "$HOME/Library/Logs/${0##*/}.log"
}


#	parse option arguments
while getopts ":ai:" OPT; do
	  case $OPT in
    a)
      LAUNCH_AGENT=true
      ;;
    i)
	  ADVANCED_COMPUTER_SEARCH_ID="$OPTARG"
	  ;;
    \?)
      echo "USAGE: ${0##*/} [-a (run script via LaunchAgent no prompting)] [-i X (provide advanced search ID number as X)]" 
      exit $LINENO
      ;;
    :)
      echo "Option -$OPTARG requires an advanced search ID number as an argument." >&2
      exit $LINENO
      ;;
  esac
done


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


#	make sure and ID has been specified
if [ -z $ADVANCED_COMPUTER_SEARCH_ID ]; then
	echo "USAGE: ${0##*/} [-a (run script via LaunchAgent no prompting)] [-i X (provide advanced search ID number as X)]" 
	exit $LINENO
fi


#	get advanced search data by id
ADVANCED_SEARCH_XML=`/usr/bin/curl -X GET -H"Accept: application/xml" -s -u ${JSS_USER}:${JSS_PASSWORD} ${JSS_URL%/}/JSSResource/advancedcomputersearches/id/${ADVANCED_COMPUTER_SEARCH_ID}` 


#	get computers by id
COMPUTERS=(`echo $ADVANCED_SEARCH_XML | /usr/bin/xpath "//computers//id"  2> /dev/null | awk -F'</?id>' '{for(i=2;i<=NF;i++) print $i}'`)


#	if no computers found, exit script
if [ ${#COMPUTERS[@]} -eq 0 ]; then
	echo "No computers found."
	log "No computers found."
	exit 0
fi


#	get advanced search name
NAME=`echo $ADVANCED_SEARCH_XML | /usr/bin/xpath "/advanced_computer_search/name/text()" 2> /dev/null`


#	if -a option not specified, prompt user to continue
if ! $LAUNCH_AGENT; then

	read -s -n 1 -p "The report [$NAME] contains ${#COMPUTERS[@]} computers. Delete them all? [y/n]" DELETE; echo -e "\r"
	if [[ $DELETE != y ]]; then exit $LINENO; fi

	CODE=$RANDOM
	read -s -n ${#CODE} -p "To be ABSOLUTELY sure, type the CODE: $CODE to continue." VERIFY; echo -e "\r"
	if [ $VERIFY != $CODE ]; then exit $LINENO; fi
else 
	echo "Please wait . . ."
fi


#	enumerate computers for last check-in time
for ID in ${COMPUTERS[@]}; do

	#	get computer name by id
	COMPUTER_NAME=`echo $ADVANCED_SEARCH_XML | /usr/bin/xpath "/advanced_computer_search/computers/computer[id=$ID]/Computer_Name/text()" 2> /dev/null`

	#	delete computer by id
	RC=`/usr/bin/curl --connect-timeout 60 -skw "%{http_code}\n" -u $JSS_USER:$JSS_PASSWORD -o /dev/null ${JSS_URL%/}/JSSResource/computers/id/$ID -X DELETE`

	#	display output based on success or error
	if [ $RC -eq 200 ]; then
		log "DELETED: ID: $ID NAME: $COMPUTER_NAME"
		echo "DELETED: ID: $ID NAME: $COMPUTER_NAME"
	else
		log "ERROR:   ID: $ID NAME: $COMPUTER_NAME"
		echo "ERROR:   ID: $ID NAME: $COMPUTER_NAME"
	fi
done


#	audible completion sound
echo "Done."
/usr/bin/afplay /System/Library/Sounds/Glass.aiff


