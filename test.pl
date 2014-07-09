#!/usr/bin/perl -I ..
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

$usage = "test.pl - doing just one thing, well. 
";

if ($#ARGV < 0) {
	print $usage;
	exit 0;
}

$argv = "test.pl " . join(" ", @ARGV);

$subcmd = shift;

# help command
if ($subcmd =~ /help/) {
	print $usage;
	exit 0;
}

$DEBUG = 1;
$cldap = ADConnect();
if (! $cldap) {
	print "Unable to connect to AD from this host in $domain, please try from somewhere else.\n";
	exit 42;
}



# new syntax guideline is to use lower
# case letters for options with args and upper case for
# standalone options


getopts('a:c:d:e:g:h:k:i:m:n:p:r:s:u:ABCDEFGHLNPRUV');

# are there extra words after the last items getopts found?
while (my $extra = shift) {
	push(@extras, $extra);
}



if ($opt_n) {
	print "netgroup 1: $opt_n \n";
	if (@extras) {
		print "Extra args detected: ", join(" ", @extras), "\n";
	}

}

