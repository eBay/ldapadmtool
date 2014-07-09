#!/usr/bin/perl -I /Users/abeeman/projects
# This is the UNIX LDAP command toolchain by Adam Beeman, 2011, eBay Inc.

#use strict;
#use warnings;
use Net::LDAP;
use Getopt::Std;
#use Term::ReadPassword;

# Import all the settings and functions from the related files

# todo: change to "use"
use ldapadmtool::config;
use ldapadmtool::host;
use ldapadmtool::netgroup;
use ldapadmtool::ldapconnection;
use ldapadmtool::user;
use ldapadmtool::group;
use ldapadmtool::search;
use ldapadmtool::sudoer;
use ldapadmtool::automount;



# each of the sub-commands have their own $usage_<subcommand> in its
# own file. This is just the top-level help message.

$usage = "ldapadmtool.pl - your one-stop shop for account management 

The ldapadmtool.pl command has several subcommands. For help on each subcommand,
try running \"ldapadmtool.pl help <subcommand>\". Available subcommands are:

ldapadmtool.pl user 
ldapadmtool.pl netgroup 
ldapadmtool.pl group 
ldapadmtool.pl host 
ldapadmtool.pl search
ldapadmtool.pl sudoer
ldapadmtool.pl automount
ldapadmtool.pl help <subcommand>

";

if ($#ARGV < 0) {
	print $usage;
	exit 0;
}

$argv = "ldapadmtool.pl " . join(" ", @ARGV);

$subcmd = shift;

# help command
if ($subcmd =~ /help/) {
	$helpcmd = shift;
	if ($helpcmd =~ /user/) {
		print $usage_user;
		exit 0;
	} elsif ($helpcmd =~ /netgroup/) {
		print $usage_netgroup;
		exit 0;
	} elsif ($helpcmd =~ /group/) {
		print $usage_group;
		exit 0;
	} elsif ($helpcmd =~ /search/) {
		print $usage_search;
		exit 0;
	} elsif ($helpcmd =~ /host/) {
		print $usage_host;
		exit 0;
	} elsif ($helpcmd =~ /sudoer/) {
		print $usage_sudoer;
		exit 0;
	} elsif ($helpcmd =~ /automount/) {
		print $usage_automount;
		exit 0;
	}
	else {
		print $usage;
		exit 0;
	}
}


# new syntax guideline is to use lower
# case letters for options with args and upper case for
# standalone options


getopts('a:c:d:e:g:h:k:i:m:n:p:r:s:u:ABCDEFGHLNPRUV');

# are there extra words after the last items getopts found?
while (my $extra = shift) {
	push(@extras, $extra);
}

if ($opt_V) {
	$DEBUG = 1;
	print "Verbose output/debugging statements enabled.\n";
}
# certain parameters should always be lowercased when presented:
# usernames, hostnames, netgroup names
if ($subcmd != "sudoer") {
	$opt_e = lc($opt_e) if ($opt_e);
	$opt_u = lc($opt_u) if ($opt_u);
	$opt_h = lc($opt_h) if ($opt_h);
	$opt_n = lc($opt_n) if ($opt_n);
}
# Check for valid domain/environment to get LDAP base 
if ($opt_e) {
	$base = $bases{"$opt_e"};
	print "Selected base $base based on -e option $opt_e\n" if ($DEBUG);
	if (! $base) {
		print "You asked for environment $opt_e, but that doesn't exist. Valid choices are:\n";
		print join(keys(%bases), " "), "\n";
		exit 5;
	}
} elsif ($default_env) {
	$base = $bases{$default_env};
	print "Selected base $base based on default_env setting of $default_env\n" if ($DEBUG);
}

# Setup locations of specific OU's for users, netgroups, groups, and sudoers. 
# Note this might need some customization at some sites.
if ($base) {
	# setup some oft-used shortcuts
	$base_users="ou=people," . $base;	
	$base_netgroup="ou=netgroup," . $base;	
	$base_group="ou=group," . $base;
	$base_sudoer="ou=SUDOers," . $base;
}	

# load our credentials to access LDAP and AD
&loadCreds();

# Log everything via syslog to Splunk
&logActivity("$argv");

# No matter what, we're going to need to create at least one connection to LDAP
$ldap = ldapConnect();

# Spend as little time figuring out what to do in this file as possible
# user commands
if ($subcmd eq "user") {
	# go to the user.pm's entry point to decide what to do.
	&ldapadmtoolUserMain();
} elsif ($subcmd eq "host") {
	# go to the host.pm's entry point to decide what to do.
	&ldapadmtoolHostMain();
} elsif ($subcmd eq "group") {
	# go to the group.pm's entry point to decide what to do.
	&ldapadmtoolGroupMain();
} elsif ($subcmd eq "netgroup") {
	# go to the netgroup.pm's entry point to decide what to do.
	&ldapadmtoolNetgroupMain();
} elsif ($subcmd eq "search") {
	# go to the search.pm's entry point to decide what to do.
	&ldapadmtoolSearchMain(); 
} elsif ($subcmd eq "sudoer") {
	# go to the sudoer.pm's entry point to decide what to do.
	&ldapadmtoolSudoerMain();
} elsif ($subcmd eq "automount") {
	# go to the automount.pm's entry point to decide what to do.
	&ldapadmtoolAutomountMain();
} else {
	# no recognizable subcommand has been provided.
	print $usage;
	exit 0;
}

# close open sockets. It's the nice thing to do.
$ldap->unbind();
if ($cldap) { $cldap->unbind(); }

# if we made it this far, there's nothing left to do but exit gracefully
exit 0;
