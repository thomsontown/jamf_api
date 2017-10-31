#!/usr/bin/env python


'''
This script was written to download the scripts for any
Mac-based extension attributes from wtihin the JSS and 
save them to a folder on the desktop. 

Partly, I worte this becuase my JAMF Technical Engineer 
requested I send a copy of all the extension attribute 
scripts from my JSS for review. But I also wanted to take 
the time to work with the python-jss module rather than 
coding my own JSS connections and queries and parsing the 
results. 

Author:        Andrew Thomson
Date:          2017-10-31
GitHub:        https://github.com/thomsontown

'''


import os
import plistlib
import subprocess
import sys


#	import non-standard python-jss module
try:
    import jss                    
except ImportError:
    sys.stderr.write("This script requires the python-jss module. The module can be installed by using the following command.\npip install python-jss")
    exit(1)


#	import standard variables from config.py
if os.path.exists(os.path.join(os.path.expanduser("~"), 'config.py')):
	#	add profile root to path
	sys.path.append(os.path.expanduser("~"))
	#	import all variables
	from  config import *


def main():

	#	create folder to save scripts
	path_to_save = '~/Desktop/ext_att_scripts'
	makeNewFolder(path_to_save)

	#	get login and password if not already set
	jssUser, jssPass = getLogin()

	#	get jss url from jamf plist or prompt if no plist found
	jssUrl = getURL()

	#	create instance of jss object
	j = jss.JSS(url=jssUrl, user=jssUser, password=jssPass, ssl_verify=True)

	#	get all extension attributes
	print "Querying the JSS . . ."
	sys.stdout.flush()
	extension_attributes = j.ComputerExtensionAttribute().retrieve_all()

	#	enumerate extension attributes
	for extension_attribute in extension_attributes:
	
		#	get input_type elements for each extension_attribute
		input_types = extension_attribute.findall('input_type')

		#	enumerate input_types
		for input_type in input_types:

			#	set identifying flags to false
			isScript = False
			isMac    = False

			#	enumerate elements within input_type
			for element in input_type:
				#	if type is script then set flag to true
				if element.tag == 'type' and  element.text == 'script':	isScript = True
				#	if platform is mac then set flag to true
				if element.tag == 'platform' and element.text == 'Mac': isMac = True
				#	set text of script to script variable
				if element.tag == 'script': script = element.text

			#	if type is script and platform is mac then save script to attribute name
			if isScript and isMac: 
				try:
					f = open(os.path.join(os.path.expanduser(path_to_save), extension_attribute.name + ".txt"), "w")
					f.write(script)
					f.close()
				except IOError as e:
					sys.stderr.write("Unable to write to file: '%s'.\n" % os.path.join(os.path.expanduser(path_to_save), extension_attribute.name + ".txt"))

	#	play sound to notify completion
	print '\a'


def makeNewFolder(newFolderPath):
	
	if not os.path.isdir(os.path.expanduser(newFolderPath)):
		try:
			os.makedirs(os.path.expanduser(newFolderPath))
		except OSError as e:
			sys.stderr.write("Unable to create folder: '%s'.\n" % os.path.expanduser(newFolderPath))
			exit(1)


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


#	initiate main if run directly
if __name__ == '__main__':
    main()