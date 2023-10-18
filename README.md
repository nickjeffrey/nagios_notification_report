# nagios_notification_report
daily email report of nagios hosts and services notification status

This perl script to generate HTML report suitable for displaying on a web page or sending via email

This report is designed to be used as a high-level validation that notifications are enbled for all nagios hosts and services


# Assumptions
It is assumed you already have a working nagios environment in place.  This script runs via cron from the nagios user on the nagios server.

# Installation 

Copy the .pl and .cfg files to the nagios user home directory

Edit the .cfg to match your local environment to/from email addresses, hostnames

It is assumed that this script runs Monday-Friday on the nagios server from the nagios user crontab.  Create a cron job similar to the following:
 ```    
     5 7 * * 1,2,3,4,5 /home/nagios/nagios_notification_report.pl 2>&1 #daily report to show nagios notification status
```

# Sample Output

Refer to the nagios_notification_report.html file


