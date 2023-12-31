#!/usr/bin/perl -w



# CHANGE LOG
# -----------
# 2022-12-22	njeffrey	Script created
# 2022-12-26	njeffrey	Add --disabledonly parameter
# 2023-10-16	njeffrey	Add a column to the report that shows if a service is in a period of scheduled downtime
# 2023-10-18	njeffrey	Add a column to include comments for host downtime / service downtime
# 2023-11-38	njeffrey	Regex bugfix, embedded curly braces in plugin_output line of status.dat causing unintentional matches



# NOTES
# -----
# perl script to generate HTML report suitable for displaying on a web page or sending via email
# This report is designed to be used as a high-level validation that notifications are enbled for all nagios hosts and services
#
# It is assumed that this script runs Monday-Friday on the nagios server from the nagios user crontab.  For example:
# 5 7 * * 1,2,3,4,5 /home/nagios/nagios_notification_report.pl 2>&1 #daily report to show nagios notification status


use strict; 				#enforce good coding practices
use Getopt::Long;                       #allow --long-switches to be used as parameters.  Install with: perl -MCPAN -e 'install Getopt::Long'


#declare variables
my ($verbose,$cmd,$host,$localhost);
my ($key,$config_file,$output_file,$temp_file,$bgcolor,$fontcolor);
my ($to,$from,$subject,$sendmail,$monitoring_system_url);
my ($count,$status_dat,%hosts,%services);
my ($opt_h,$opt_v,$opt_d);
my ($disabledonly);
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
my ($is_in_effect,$end_time,$service_description,$host_comment,$service_comment);
$verbose               = "no";									#yes/no flag to increase verbosity for debugging
$sendmail              = "/usr/sbin/sendmail"; 		 					#location of binary
$output_file           = "/home/nagios/nagios_notification_report.html";			#location of file
$temp_file             = "/home/nagios/nagios_notification_report.tmp";				#location of file
$config_file           = "/home/nagios/nagios_notification_report.cfg";				#location of file
$bgcolor               = "white";								#HTML background color
$localhost             = `hostname -s`;								#get the local hostname
$status_dat            = "/var/log/nagios/status.dat";						#location of status.dat file used by nagios on RHEL7
$disabledonly          = "no";									#yes|no flag to show all hosts and services (long output) or only disabled hosts and services (short output)



sub get_options {
   #
   # this gets the command line parameters provided by the users
   print "running get_options subroutine \n" if ($verbose eq "yes");
   #
   Getopt::Long::Configure('bundling');
   GetOptions(
      "h"   => \$opt_h, "help"         => \$opt_h,
      "v"   => \$opt_v, "verbose"      => \$opt_v,
      "d"   => \$opt_d, "disabledonly" => \$opt_d,

   );
   #
   # If the user supplied -h or --help switch, provide help
   if( defined( $opt_h ) ) {
      print "USAGE: \n";
      print "   $0 --help  \n";
      print "   $0 --verbose  \n";
      print "   $0 --disabledonly   (only show hosts and services with disabled notifications, skip those with enabled notifications)  \n";
      exit;
   }
   #
   # If the user supplied -v or --verbose switch, increase script output verbosity for debugging
   if( defined( $opt_v ) ) {
      $verbose = "yes";
   }
   #
   # If the user supplied -d or --disabledonly switch, only show hosts and services with disabled notifications (makes for a smaller report)
   if( defined( $opt_d ) ) {
      $disabledonly = "yes";
   }
}                       #end of subroutine




sub sanity_checks {
   #
   print "running sanity_checks subroutine \n" if ($verbose eq "yes");
   #
   # confirm the status.dat file is available
   $status_dat = "/var/log/nagios/status.dat"    if (-f "/var/log/nagios/status.dat");		#location on RHEL7
   $status_dat = "/var/spool/nagios/status.dat"  if (-f "/var/spool/nagios/status.dat");  	#location on RHEL8
   if( ! -f $status_dat ) {
      print "ERROR - Unknown - cannot locate $status_dat \n";
      exit; 											#exit script
   }                                            						#end of if block
   if( ! -r  $status_dat ) {
      print "ERROR - $status_dat is not readable by the current user \n";
      exit; 											#exit script
   }                                            						#end of if block
   #
   # if $temp_file already exists, delete old copy
   if ( -f $temp_file ) {
      unlink "$temp_file";
   }
   if ( -f $temp_file ) {
      print "ERROR - cannot delete old copy of temporary file $temp_file \n";
   }
   #
   # if $output_file already exists, delete old copy
   if ( -f $output_file ) {
      unlink "$output_file";
   }
   if ( -f $output_file ) {
      print "ERROR - cannot delete old copy of HTML report file $output_file \n";
   }
} 												#end of subroutine




sub get_date {
   #
   print "running get_date subroutine \n" if ($verbose eq "yes");
   #
   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
   $year = $year + 1900;                                                #$year is actually years since 1900
   $mon  = $mon + 1;                                                    #months are numbered from 0 to 11
   $mon  = "0$mon"  if ($mon  < 10);                                    #add leading zero if required
   $mday = "0$mday" if ($mday < 10);                                    #add leading zero if required
   $hour = "0$hour" if ($hour < 10);                                    #add leading zero if required
   $min  = "0$min"  if ($min  < 10);                                    #add leading zero if required
   #
   print "   current time is $year-$mon-$mday $hour:$min \n" if ($verbose eq "yes");
}                                                                       #end of subroutine




sub read_config_file {
   #
   print "running read_config_file subroutine \n" if ($verbose eq "yes");
   #
   if ( ! -f "$config_file" ) {									#confirm the config file exists
      print "ERROR: cannot find config file $config_file - exiting script \n";
      exit;
   } 												#end of if block
   if ( -z "$config_file" ) {									#confirm the config file is larger than zero bytes
      print "ERROR: config file $config_file is zero size - exiting script \n";
      exit;
   } 												#end of if block
   print "   opening config file $config_file for reading \n" if ($verbose eq "yes");
   open(IN,"$config_file") or die "Cannot read config file $config_file $! \n"; 		#open file for reading
   while (<IN>) {                                                                            	#read a line from the command output
      #
      # email address details 
      #
      $to                    = $1              if (/^to=([a-zA-Z0-9,_\-\@\.]+)/);		#find line in config file
      $from                  = $1              if (/^from=([a-zA-Z0-9_\-\@\.]+)/);		#find line in config file
      $subject               = $1              if (/^subject=([a-zA-Z0-9 _\-\@]+)/);		#find line in config file
      $monitoring_system_url = $1              if (/^monitoring_system_url=(.*)/);		#find line in config file
   }                                                                                         	#end of while loop
   close IN;                                                                                 	#close filehandle
   #
   # check to see if to/from/subject are populated
   #
   unless(defined($to)) {
      print "ERROR: Could not find line similar to to=helpdesk\@example.com in config file $config_file \n";
      exit;
   }												#end of unless block
   unless(defined($from)) {
      print "ERROR: Could not find line similar to from=alerts\@example.com in config file $config_file \n";
      exit;
   }												#end of unless block
   unless(defined($subject)) {
      print "ERROR: Could not find line similar to subject=BigCorp daily nagios notification report in config file $config_file \n";
      exit;
   }												#end of unless block
   unless(defined($monitoring_system_url)) {
      print "ERROR: Could not find line similar to monitoring_system_url=http://MyNagiosHost.example.com in config file $config_file \n";
      exit;
   }												#end of unless block
   print "   to:$to  from:$from  subject:$subject monitoring_system_url=$monitoring_system_url \n" if ($verbose eq "yes");
} 												#end of subroutine




sub read_status_dat {
   #
   print "running read_status_dat subroutine \n" if ($verbose eq "yes");
   #
   # This subroutine will read the status.dat file, and collapse each stanza that look similar to the following into a single line for easier parsing:
   #
   # hoststatus {
   #     host_name=host1.example.com
   #     notification_period=14x7
   #     notifications_enabled=1		<--- this is the line we are interested in for host notifications
   #     problem_has_been_acknowledged=0
   #     active_checks_enabled=1
   #     passive_checks_enabled=1
   #     }
   # 
   # hostdowntime {
   #     host_name=host1.example.com
   #     start_time=1697489130
   #     end_time=1697496330
   #     is_in_effect=1
   #     comment=testing host downtime
   #     }
   #
   # servicedowntime {                    	<--- this stanza will only exist if the service is in a period of scheduled downtime
   #     host_name=host1.example.com
   #     service_description=vmtoolsd
   #     entry_time=1697473540
   #     start_time=1697473535
   #     flex_downtime_start=0
   #     end_time=1697480735    		<--- epoch seconds for when downtime will end
   #     is_in_effect=1
   #     comment=in downtime for testing
   #     }
   #
   #
   # After this subroutine is finished, the multi-line stanzas will be collapsed into one lie per host that will look similar to the following:
   #    hoststatus {  host_name=host1.example.com  notification_period=24x7  notifications_enabled=1  }
   #    hoststatus {  host_name=host2.example.com  notification_period=14x7  notifications_enabled=1  }
   #    hoststatus {  host_name=host3.example.com  notification_period=14x7  notifications_enabled=0  }
   #
   # read the nagios status.dat file and generate a temporary file containing the information we are interested in
   #
   print "   opening $status_dat file for reading \n" if ($verbose eq "yes");
   open(OUT,">>$temp_file") or die "Cannot open $temp_file for appending $! \n";
   open(IN,"$status_dat") or die "Cannot open $status_dat file for reading $! \n"; 		#open filehandle
   while (<IN>) {                                                      		 		#read a line from the command output
      next if (/plugin_output=/);								#this line sometimes contains reserved characters such as "{} and is not needed
      next if (/long_plugin_output=/);								#this line sometimes contains reserved characters such as "{} and is not needed
      if (/\{$/){										#find lines that end with the { character
         chomp;											#remove newline 
         print     "\n"    if ($verbose eq "yes");						#write out to screen
         print     "$_"    if ($verbose eq "yes");						#write out to screen
         print OUT "\n";									#write out to temporary file
         print OUT $_;										#write out to temporary file
      } 
      if (/\}$/){										#find lines that end with the } character
         chomp;											#remove newline 
         s/\t//g;										#get rid of leading tab character
         print     ",$_" if ($verbose eq "yes"); 						#write out to screen
         print     "\n"  if ($verbose eq "yes");						#write out to screen
         print OUT ",$_";									#write out to temporary file
         print OUT "\n";									#write out to temporary file
      } 
      if (/^\t/) {										#if line begins with tab character
         chomp;											#remove newline 
         s/\t//g;										#get rid of leading tab character
         s/\"//g;										#get rid of " characters
         s/\{//g;										#get rid of { characters
         s/\}//g;										#get rid of } characters
         if (/host_name=/) {
            print     ",$_" if ($verbose eq "yes");						#write out to screen
            print OUT ",$_";									#write out to temporary file
         }
         if (/notification_period=/) {								#0=disabled 1=enabled
            print     ",$_" if ($verbose eq "yes");						#write out to screen
            print OUT ",$_";									#write out to temporary file
         }
         if (/notifications_enabled=/) {							#0=disabled 1=enabled
            print     ",$_" if ($verbose eq "yes");						#write out to screen
            print OUT ",$_";									#write out to temporary file
         }
         if (/service_description=/) {
            print     ",$_" if ($verbose eq "yes");						#write out to screen
            print OUT ",$_";									#write out to temporary file
         }
         if (/is_in_effect=/) {
            print     ",$_" if ($verbose eq "yes");						#write out to screen
            print OUT ",$_";									#write out to temporary file
         }
         if (/end_time=/) {
            print     ",$_" if ($verbose eq "yes");						#write out to screen
            print OUT ",$_";									#write out to temporary file
         }
         if (/comment=/) {
            print     ",$_" if ($verbose eq "yes");						#write out to screen
            print OUT ",$_";									#write out to temporary file
         }
      }
   }                                                                    			#end of while loop
   close IN;                                                          		  		#close filehandle
   close OUT;											#close filehandle
} 												#end of subroutine




sub get_host_notification_details {
   #
   print "running get_host_notification_details subroutine \n" if ($verbose eq "yes");
   #
   # At this point, the details of each host have been parsed into a temporary file that looks similar to the following:
   # hoststatus {  host_name=host1.example.com  notification_period=24x7  notifications_enabled=1  }
   # hoststatus {  host_name=host2.example.com  notification_period=14x7  notifications_enabled=1  }
   # hoststatus {  host_name=host3.example.com  notification_period=14x7  notifications_enabled=0  }
   #
   open(IN,"$temp_file") or die "Cannot open $temp_file file for reading $! \n"; 		#open filehandle
   while (<IN>) {                                                      		 		#read a line from the command output
      if (/^hoststatus/){									#find lines that end with the { character
         $host = $1                    if (/,host_name=([a-zA-Z0-9_\-\.]+),/);			#get current hostname
         $hosts{$host}{host_name} = $host;							#save to hash
         $hosts{$host}{notifications_enabled} = "unknown";					#initialize hash element to avoid undef errors
         $hosts{$host}{notification_period}   = "unknown";					#initialize hash element to avoid undef errors
         $hosts{$host}{is_in_effect}          = "no";						#initialize hash element to avoid undef errors (used for hostdowntime)
         $hosts{$host}{end_time}              = 0;						#initialize hash element to avoid undef errors (used for hostdowntime)
         $hosts{$host}{notifications_enabled} = "no"  if (/,notifications_enabled=0/);		#save to hash 0=disabled 1=enabled
         $hosts{$host}{notifications_enabled} = "yes" if (/,notifications_enabled=1/);		#save to hash 0=disabled 1=enabled
         $hosts{$host}{notification_period}   = $1    if (/,notification_period=([a-zA-Z0-9_\.\-]+)/);	#save to hash  
      }                                                                    			#end of if block
   }                                                                    			#end of while loop
   close IN;                                                          		  		#close filehandle
   #
   # verbose output for debugging
   if ($verbose eq "yes") {
      foreach $key (sort keys %hosts) {
         print "   hostname=$hosts{$key}{host_name} ";
         print "   notification_period=$hosts{$key}{notification_period} ";
         print "   notifications_enabled=$hosts{$key}{notifications_enabled} ";
         print "   \n";
      } 											#end of foreach loop
   } 												#end of if block
} 												#end of subroutine



sub get_host_downtime_details {
   #
   print "running get_host_downtime_details subroutine \n" if ($verbose eq "yes");
   #
   # At this point, the details of each service have  been parsed into a temporary file that looks similar to the following:
   # hostdowntime { host_name=host1.example.com   is_in_effect=1        end_time=1697480735  comment=blah blah blah, }
   # hostdowntime { host_name=host2.example.com   is_in_effect=1        end_time=1697480735  comment=foo! bar! baz!, }
   # hostdowntime { host_name=host3.example.com   is_in_effect=1        end_time=1697480735  comment=blah blah blah, }
   #
   #
   open(IN,"$temp_file") or die "Cannot open $temp_file file for reading $! \n"; 		#open filehandle
   while (<IN>) {                                                      		 		#read a line from the command output
      if (/^hostdowntime/){									#find lines that end with the { character
         $host = $1                    if (/,host_name=([a-zA-Z0-9_\-\.]+),/);			#get current hostname
         $is_in_effect         = "no";								#default value is no because the stanza in status.dat will not exist
         $is_in_effect         = "no"  if (/,is_in_effect=0/);					#save to hash 0=disabled 1=enabled
         $is_in_effect         = "yes" if (/,is_in_effect=1/);					#save to hash 0=disabled 1=enabled
         $end_time             = 0; 								#default to 0 because the stanza in status.dat will not exist
         $end_time             = $1    if (/,end_time=([0-9]+)/);				#save to hash 
         $host_comment         = "";   								#initialize hash element to avoid undef errors
         $host_comment         = $1    if (/,comment=(.*)/);					#parse out any comment provided by the nagios sysadmin 
         $host_comment         =~ s/,//g;							#remove any embedded commas in the free-form comment field to make later regex easier
         $host_comment         =~ s/{//g;							#remove any embedded {      in the free-form comment field to make later regex easier
         $host_comment         =~ s/}//g;							#remove any embedded }      in the free-form comment field to make later regex easier
         #
         # convert $end_time from seconds since epoch to human readable time
         if ($end_time > 0) {
            $end_time = localtime($end_time);
         }
         #
         # At this point we know the $host $is_in_effect $end_time 
         # There is already a single-level hash with all the host details, so loop through the hash keys to add the hostdowntime details to the existing hash 
         #
         foreach $key (sort keys %hosts) {
            if ( "$host" eq "$hosts{$key}{host_name}" ) {					#confirm the host_name matches
               $hosts{$key}{is_in_effect} = $is_in_effect;
               $hosts{$key}{end_time}     = $end_time;
               $hosts{$key}{host_comment} = $host_comment;
               if ($verbose eq "yes") {
                  print "   hostname=$hosts{$key}{host_name} ";
                  print "   is_in_effect=$hosts{$key}{is_in_effect} ";
                  print "   end_time=$hosts{$key}{end_time} ";
                  print "   host_comment=$hosts{$key}{host_comment} ";
                  print "   \n";
               }
            }
         } 											#end of foreach loop
      }                                                                    			#end of if block
   }                                                                    			#end of while loop
   close IN;                                                          		  		#close filehandle
} 												#end of subroutine


sub get_service_notification_details {
   #
   print "running get_service_notification_details subroutine \n" if ($verbose eq "yes");
   #
   # At this point, the details of each service have  been parsed into a temporary file that looks similar to the following:
   # servicestatus { host_name=host1.example.com   service_description=ping        notification_period=14x7        notifications_enabled=1 }
   # servicestatus { host_name=host2.example.com   service_description=CPU util    notification_period=14x7        notifications_enabled=1 }
   # servicestatus { host_name=host3.example.com   service_description=SNMP        notification_period=14x7        notifications_enabled=1 }
   #
   # servicedowntime { host_name=host1.example.com   service_description=ping        is_in_effect=1        end_time=1697480735 }
   # servicedowntime { host_name=host2.example.com   service_description=CPU util    is_in_effect=1        end_time=1697480735 }
   # servicedowntime { host_name=host3.example.com   service_description=SNMP        is_in_effect=1        end_time=1697480735 }
   #
   $count = 0;												#initialize counter variable
   open(IN,"$temp_file") or die "Cannot open $temp_file file for reading $! \n"; 			#open filehandle
   while (<IN>) {                                                      		 			#read a line from the command output
      if (/^servicestatus/){										#find lines that begin with servicestatus
         #
         # parse out the hostname
         #
         $host = $1                    if (/,host_name=([a-zA-Z0-9_\-\.]+),/);				#get current hostname
         $services{$host}{$count}{host_name} = "$host";							#initialize hash element to avoid undef errors
         #
         # initialize hash elements to avoid undef errors
         #
         $services{$host}{$count}{notifications_enabled} = "unknown" unless $services{$host}{$count}{notifications_enabled};	#initialize hash element to avoid undef errors
         $services{$host}{$count}{notification_period}   = "unknown" unless $services{$host}{$count}{notification_period};	#initialize hash element to avoid undef errors
         $services{$host}{$count}{service_description}   = "unknown" unless $services{$host}{$count}{service_description};	#initialize hash element to avoid undef errors
         $services{$host}{$count}{is_in_effect}          = "no"      unless $services{$host}{$count}{is_in_effect};		#initialize hash element to avoid undef errors (used for servicedowntime)
         $services{$host}{$count}{end_time}              = 0         unless $services{$host}{$count}{end_time} ;		#initialize hash element to avoid undef errors (used for servicedowntime)
         #
         # this section comes from the servicedescription stanza
         #
         $services{$host}{$count}{notifications_enabled} = "no"  if (/,notifications_enabled=0/);	#save to hash 0=disabled 1=enabled
         $services{$host}{$count}{notifications_enabled} = "yes" if (/,notifications_enabled=1/);	#save to hash 0=disabled 1=enabled
         $services{$host}{$count}{notification_period}   = $1    if (/,notification_period=([a-zA-Z0-9_\.\-]+)/);	#save to hash  
         $services{$host}{$count}{service_description}   = $1    if (/,service_description=([a-zA-Z0-9_\.\-\/\\ ]+),/);	#save to hash  
#         #
#         # this section comes from the servicedowntime stanza
#         #
#         $services{$host}{$count}{is_in_effect}          = "no"  if (/,is_in_effect=0/);		#save to hash 0=disabled 1=enabled
#         $services{$host}{$count}{is_in_effect}          = "yes" if (/,is_in_effect=1/);		#save to hash 0=disabled 1=enabled
#         $services{$host}{$count}{end_time}              = $1    if (/,end_time=([0-9]+)/);		#save to hash 
         #
         # increment counter variable being used as second-level hash key
         #
         $count++;											#increment counter 
      }                                                                    				#end of if block
   }                                                                    				#end of while loop
   close IN;                                                          		  			#close filehandle
   #
   # verbose output for debugging
   if ($verbose eq "yes") {
      foreach $key (sort keys %services) {
         foreach my $key2 ( sort keys %{$services{$key}} ) {
            print "   hostname=$services{$key}{$key2}{host_name} ";
            print "   notification_period=$services{$key}{$key2}{notification_period} ";
            print "   notifications_enabled=$services{$key}{$key2}{notifications_enabled} ";
            print "   service_description=$services{$key}{$key2}{service_description} ";
            print "   is_in_effect=$services{$key}{$key2}{is_in_effect} ";
            print "   end_time=$services{$key}{$key2}{end_time} ";
            print "   \n";
         } 												#end of foreach loop
      } 												#end of foreach loop
   } 													#end of if block
} 													#end of subroutine




sub get_service_downtime_details {
   #
   print "running get_service_downtime_details subroutine \n" if ($verbose eq "yes");
   #
   # At this point, the details of each service have  been parsed into a temporary file that looks similar to the following:
   # servicedowntime { host_name=host1.example.com   service_description=ping        is_in_effect=1        end_time=1697480735   comment=blah blah blah }
   # servicedowntime { host_name=host2.example.com   service_description=CPU util    is_in_effect=1        end_time=1697480735   comment=foo! bar@ baz% }
   # servicedowntime { host_name=host3.example.com   service_description=SNMP        is_in_effect=1        end_time=1697480735   comment=blah blah blah }
   #
   #
   open(IN,"$temp_file") or die "Cannot open $temp_file file for reading $! \n"; 		#open filehandle
   while (<IN>) {                                                      		 		#read a line from the command output
      if (/^servicedowntime/){									#find lines that end with the { character
         $host = $1                    if (/,host_name=([a-zA-Z0-9_\-\.]+),/);			#get current hostname
         $is_in_effect         = "no";								#default value is no because the stanza in status.dat will not exist
         $is_in_effect         = "no"  if (/,is_in_effect=0/);					#save to hash 0=disabled 1=enabled
         $is_in_effect         = "yes" if (/,is_in_effect=1/);					#save to hash 0=disabled 1=enabled
         $end_time             = 0; 								#default to 0 because the stanza in status.dat will not exist
         $end_time             = $1    if (/,end_time=([0-9]+)/);					#save to hash 
         $service_description  = $1    if (/,service_description=([a-zA-Z0-9_\.\-\/\\ ]+),/);					#save to hash 
         $service_comment      = "";                                                            #initialize hash element to avoid undef errors
         $service_comment      = $1    if (/,comment=(.*)/);                                    #parse out any comment provided by the nagios sysadmin
         $service_comment      =~ s/,//g;                                                       #remove any embedded commas in the free-form comment field to make later regex easier
         $service_comment      =~ s/{//g;                                                       #remove any embedded {      in the free-form comment field to make later regex easier
         $service_comment      =~ s/}//g;                                                       #remove any embedded }      in the free-form comment field to make later regex easier

         #
         # convert $end_time from seconds since epoch to human readable time
         if ($end_time > 0) {
            $end_time = localtime($end_time);
         }
         #
         # At this point we know the $host $is_in_effect $end_time 
         # There is already a multi-level hash with all the service descriptions, so loop through the hash keys to add the servicedowntime details to the existing hash 
         #
         foreach $key (sort keys %services) {
            foreach my $key2 ( sort keys %{$services{$key}} ) {
               if ( "$host" eq "$services{$key}{$key2}{host_name}" ) {					#confirm the host_name and service_description match
                  if ( "$service_description" eq "$services{$key}{$key2}{service_description}" ) {		#confirm the host_name and service_description match
                     $services{$key}{$key2}{is_in_effect}    = $is_in_effect;
                     $services{$key}{$key2}{end_time}        = $end_time;
                     $services{$key}{$key2}{service_comment} = $service_comment;
                     if ($verbose eq "yes") {
                        print "   hostname=$services{$key}{$key2}{host_name} ";
                        print "   service_description=$services{$key}{$key2}{service_description} ";
                        print "   is_in_effect=$services{$key}{$key2}{is_in_effect} ";
                        print "   end_time=$services{$key}{$key2}{end_time} ";
                        print "   service_comment=$services{$key}{$key2}{service_comment} ";
                        print "   \n";
                     }
                  }
               }
            } 											#end of foreach loop
         } 											#end of foreach loop
      }                                                                    			#end of if block
   }                                                                    			#end of while loop
   close IN;                                                          		  		#close filehandle
} 												#end of subroutine


sub generate_html_report_header {
   #
   print "running generate_html_report_header subroutine \n" if ($verbose eq "yes");
   #
   print "   opening $output_file for writing \n" if ($verbose eq "yes");
   open (OUT,">$output_file") or die "Cannot open $output_file for writing: $! \n";
   print OUT "<html><head><title>Status Report</title></head><body> \n";	
   print OUT "<br>This report is generated by the $0 script on $localhost \n";	
   print OUT "<br>Last updated $year-$mon-$mday $hour:$min \n";
   print OUT "<p>\&nbsp\;</p> \n";
   print OUT "<hr> \n";
   print OUT "<br><b>How to use this report</b> \n";
   print OUT "<br>    <li>This daily report is to remind the nagios sysadmins to re-enable any notifications that may have been accidentally turned off. \n";
   print OUT "<br>    <li>HINT: use the --disabled only parameter in the cron job to skip all the <font color=green> green </font> results, only showing <font color=red> red </font> results to cut down on the size of the report. \n";
   print OUT "<br>    <li>If you see any <font color=red>red</font> warnings, please login to nagios at $monitoring_system_url to confirm that those notifications are supposed to be disabled. \n";
   print OUT "<br>    <li>If you do not see any <font color=red>red</font> warnings, no further action is needed. \n";
   print OUT "</ul><hr> \n";
}										#end of subroutine




sub generate_html_report_hosts {
   #
   print "running generate_html_report_hosts subroutine \n" if ($verbose eq "yes");
   #
   # Create the HTML table for all the nagios hosts
   #
   print OUT "<table border=1> \n";
   print OUT "<tr bgcolor=gray><td colspan=5> Nagios hosts \n";
   print OUT "<tr bgcolor=gray><td> Hostname <td> Notification Period <td> Notifications Enabled <td> In Scheduled Downtime <td> Comment \n";
   foreach $key (sort keys %hosts) {
      next if ( ($disabledonly eq "yes") && ($hosts{$key}{notifications_enabled} eq "yes") && ($hosts{$key}{is_in_effect} eq "no") );  #skip any enabled hosts if the --disabledonly parameter was provided
      #
      # print hostname field in table row
      #
      $bgcolor = "white"; 
      print OUT "<tr><td bgcolor=$bgcolor> $hosts{$key}{host_name} \n" ;
      #
      # print notification period in table row
      #
      $bgcolor = "white";								#initialize variable
      $hosts{$key}{notification_period} = "unknown" unless ($hosts{$key}{notification_period});
      print OUT "    <td bgcolor=$bgcolor> $hosts{$key}{notification_period} \n";
      #
      # print notifications_enabled status in table row
      #
      $bgcolor = "white";								#initialize variable
      $bgcolor = "orange" if ($hosts{$key}{notifications_enabled} eq "unknown");
      $bgcolor = "red"    if ($hosts{$key}{notifications_enabled} eq "no");
      $bgcolor = "green"  if ($hosts{$key}{notifications_enabled} eq "yes");
      print OUT "    <td bgcolor=$bgcolor> $hosts{$key}{notifications_enabled} \n";
      #
      # print scheduled downtime status in table row
      #
      $bgcolor = "white";								#initialize variable
      $bgcolor = "orange" if ($hosts{$key}{is_in_effect} eq "unknown");
      $bgcolor = "green"  if ($hosts{$key}{is_in_effect} eq "no");
      $bgcolor = "red"    if ($hosts{$key}{is_in_effect} eq "yes");
      if ( $hosts{$key}{is_in_effect} eq "yes") {
         print OUT "    <td bgcolor=$bgcolor> host downtime until $hosts{$key}{end_time} \n";
      } else {
         print OUT "    <td bgcolor=$bgcolor> $hosts{$key}{is_in_effect} \n";
      } 											#end of if/else block
      #
      # print any optional comment that exists in the status.dat file
      #
      $bgcolor = "white";								#initialize variable
      $hosts{$key}{host_comment} = " "  unless ($hosts{$key}{host_comment});
      print OUT "    <td bgcolor=$bgcolor> $hosts{$key}{host_comment} \n";
   } 											#end of foreach loop
   # print HTML table footer 
   print OUT "</table><p>\&nbsp\;</p> \n";
}											#end of subroutine




sub generate_html_report_services {
   #
   print OUT "<table border=1> \n";
   print OUT "<tr bgcolor=gray><td colspan=6> Nagios services \n";
   print OUT "<tr bgcolor=gray><td> Hostname <td> Service Description <td> Notification Period <td> Notifications Enabled <td> In Scheduled Downtime <td> Comment\n";
   foreach my $key ( sort keys %services ) {
      foreach my $key2 ( sort keys %{$services{$key}} ) {
         #
         next if ( ($disabledonly eq "yes") && ($services{$key}{$key2}{notifications_enabled} eq "yes") && ($services{$key}{$key2}{is_in_effect} eq "no") );  #skip any enabled services if the --disabledonly parameter was used
         #
         # print hostname field in table row
         #
         $bgcolor = "white"; 
         print OUT "<tr><td bgcolor=$bgcolor> $services{$key}{$key2}{host_name} \n" ;
         #
         # print service description in table row
         #
         $bgcolor = "white";								#initialize variable
         $services{$key}{$key2}{service_description} = "unknown" unless ($services{$key}{$key2}{service_description});
         print OUT "    <td bgcolor=$bgcolor> $services{$key}{$key2}{service_description} \n";
         #
         # print notification period in table row
         #
         $bgcolor = "white";								#initialize variable
         $services{$key}{$key2}{notification_period} = "unknown" unless ($services{$key}{$key2}{notification_period});
         print OUT "    <td bgcolor=$bgcolor> $services{$key}{$key2}{notification_period} \n";
         #
         # print notifications_enabled status in table row
         #
         $bgcolor = "white";								#initialize variable
         $bgcolor = "orange" if ($services{$key}{$key2}{notifications_enabled} eq "unknown");
         $bgcolor = "red"    if ($services{$key}{$key2}{notifications_enabled} eq "no");
         $bgcolor = "green"  if ($services{$key}{$key2}{notifications_enabled} eq "yes");
         print OUT "    <td bgcolor=$bgcolor> $services{$key}{$key2}{notifications_enabled} \n";
         #
         # print scheduled downtime status in table row
         #
         #$services{$key}{$key2}{is_in_effect} = "Services_Workinprogress" unless $services{$key}{$key2}{is_in_effect};  #BUG xxxx:
         $bgcolor = "white";								#initialize variable
         $bgcolor = "orange" if ($services{$key}{$key2}{is_in_effect} eq "unknown");
         $bgcolor = "green"  if ($services{$key}{$key2}{is_in_effect} eq "no");
         $bgcolor = "red"    if ($services{$key}{$key2}{is_in_effect} eq "yes");
         if ( $services{$key}{$key2}{is_in_effect} eq "yes") {
            print OUT "    <td bgcolor=$bgcolor> service downtime until $services{$key}{$key2}{end_time} \n";
         } else {
            print OUT "    <td bgcolor=$bgcolor> $services{$key}{$key2}{is_in_effect} \n";
         } 											#end of if/else block
         #
         # print any optional comment that exists in the status.dat file
         #
         $bgcolor = "white";								#initialize variable
         $services{$key}{$key2}{service_comment} = " "  unless ($services{$key}{$key2}{service_comment});
         print OUT "    <td bgcolor=$bgcolor> $services{$key}{$key2}{service_comment} \n";
      } 											#end of foreach loop
   } 											#end of foreach loop
   # print HTML table footer 
   print OUT "</table><p>\&nbsp\;</p> \n";
}											#end of subroutine




sub generate_html_report_footer {
   #
   print "running generate_html_report_footer subroutine \n" if ($verbose eq "yes");
   #
   print OUT "</ul></body></html> \n";
   close OUT;										#close filehandle
} 											#end of subroutine




sub send_report_via_email {
   #
   print "running send_report_via_email subroutine \n" if ($verbose eq "yes");
   #
   open(MAIL,"|$sendmail -t");
   ## Mail Header
   print MAIL "To: $to\n";
   print MAIL "From: $from\n";
   print MAIL "Subject: $subject\n";
   ## Mail Body
   print MAIL "Content-Type: text/html; charset=ISO-8859-1\n\n";
   open (IN,"$output_file") or warn "Cannot open $output_file for reading: $! \n";
   while (<IN>) { 				#read a line from the filehandle
      print MAIL $_;				#print to email message
   } 						#end of while loop
   close IN;					#close filehandle
   close MAIL;					#close filehandle
   #
   # delete temporary files
   unlink "$temp_file"   if ( -f "$temp_file"   );
   unlink "$output_file" if ( -f "$output_file" );
} 						#end of subroutine




# ---------------- main body of script --------------
get_options;
sanity_checks;
get_date;
read_config_file;
read_status_dat;
get_host_notification_details;
get_host_downtime_details;
get_service_notification_details;
get_service_downtime_details;
generate_html_report_header;			
generate_html_report_hosts;
generate_html_report_services;
generate_html_report_footer;		
send_report_via_email;

