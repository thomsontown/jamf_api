#!/usr/bin/python

'''
This script was written to list all the jss policies that contain scripts.
Policies are not limited to those displayed within the jss interface but
also includes those that are created via Casper Remote.

Author:		Andrew Thomson
Date:		2017-09-08
GitHub:		https://github.com/thomsontown 
'''


import base64, getpass, os, plistlib, subprocess, sys, urllib2, urlparse
import xml.etree.ElementTree as etree


#	import standard variables from config.py
if os.path.exists(os.path.join(os.path.expanduser("~"), 'config.py')):
	#	add profile root to path
	sys.path.append(os.path.expanduser("~"))
	#	import all variables
	from  config import *


def main():
	
	#	get login and password 
	#	if not already set
	jssUser, jssPass = getLogin()

	#	get jss url from jamf
	#	plist or prompt if no
	#	plist found
	jssURL = getURL()

	#	get all policies from jss
	policiesXML = queryJSS(joinURL(jssURL, '/JSSResource/policies'))
	

	#	enumerate policies to extract ids 
	for policy in policiesXML.findall('policy'):

		#	query policy by id to extract script info
		scriptsXML = queryJSS(joinURL(jssURL, 'JSSResource/policies/id',  policy.find('id').text, 'subset/scripts'))

		#	if policy contains scripts then get names of scripts
		if not scriptsXML.find('scripts/size').text == '0': 
			for script in scriptsXML.findall('scripts/script'):
				print '{0:<60} {1:<30} '.format(policy.find('name').text, script.find('name').text)

		

def getLogin():

	#	prompt for username if not found
	if 'jssUser' not in globals():
		global jssUser
		jssUser = raw_input('Enter JSS Username: ')

	#	prompt for password if not found
	if 'jssPass' not in globals():
		global jssPass
		jssPass = getpass.getpass('Enter JSS Password: ') 

	return (jssUser, jssPass)  


def getURL():

	#	verify plist exists
	if os.path.exists('/Library/Preferences/com.jamfsoftware.jamf.plist'):
		
		#	convert plist into xml string
		plist_string = subprocess.Popen(['/usr/bin/plutil', '-convert', 'xml1', '/Library/Preferences/com.jamfsoftware.jamf.plist','-o', '-'], stdout=subprocess.PIPE).stdout.read()

		#	assign xml string to plistlib object 
		plist_data = plistlib.readPlistFromString(plist_string)
		
		#	return jss_URL  
		return plist_data['jss_url']

	else:

		#	prompt for URL
		jssURL = raw_input('Enter JSS URL: ')

		#	return jss_URL
		return jssURL


def queryJSS(requestURL):
	
	if not requestURL:
		sys.stderr.write('ERROR: Missing required URL component.') 
		exit(1)

	#	build api request`
	request = urllib2.Request(requestURL) 
	request.add_header('Authorization', 'Basic ' + base64.b64encode(jssUser + ':' + jssPass))

	#	send request to get response
	response = urllib2.urlopen(request)

	#	parse xml from string into an element
	return etree.fromstring(response.read())


def joinURL(host, path, *additional_path):
    return urlparse.urljoin(host, os.path.join(path, *additional_path))


#	initiate main if run directly
if __name__ == '__main__':
    main()