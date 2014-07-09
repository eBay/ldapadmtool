#!/usr/bin/perl
# This is the UNIX LDAP command toolchain by Adam Beeman, 2011, eBay Inc.
use Net::LDAP;

use Net::Syslog;
use Net::Domain qw(hostname hostfqdn hostdomain domainname);

use ldapadmtool::config;





# takes: message
sub logActivity {
	my $username;
	my $msg = shift;
	my $username = getlogin();
	if (! $username) { 
		$username = "unknown";
	}
	my $hostname = hostfqdn();
	chomp $hostname;
	if($DEBUG) {
		print "Sending syslog message to $log_server : $msg\n";
	}
# seems like my Net::Syslog is broken on OSX
#	my $s=new Net::Syslog(Facility=>'local4',Priority=>'debug',SyslogHost=> $log_server);
#	$s->send('ldapadmtool cmd: ' . $username . "\@" . $hostname . ' executed: ' . $msg , Priority=>'info');

}

# allows the user to override default login credentials by
# setting environment variables
sub loadCreds {
	
	# the user can override defaults by setting the following values in
	# their environment (shell):
	# ldap_binddn
	# ldap_bindpw
	# ad_binddn
	# ad_bindpw
	# if it exists, read the credentials from there instead of using the
	# defaults
	print "entering loadCreds\n" if ($DEBUG);
	
	# figure out where we're running the command from
	if (!$domain) { $domain = lc(hostdomain()); } # if domain isn't set in config, get it from local
	print "detected local domain is $domain\n" if ($DEBUG);
	
	# setup our global connection info based on where we are
	# using globals is bad, but I'm doing it (sorry)
	$ldap_bindpw_file = $admincredfiles{$domain};
	$ldap_server = $ldap_servers{$domain};
	$ad_server = $ad_servers{$domain};
	$log_server = $log_servers{$domain};
	print "ldap_server = $ldap_server\nad_server = $ad_server\nlog_server = $log_server\n" if ($DEBUG);
	
	
	if ($ENV{"LDAPUSER"}) {
		print "loading ldap_binddn_file from environment\n" if ($DEBUG);
		$ldap_binddn_file = $ENV{"LDAPUSER"};
	}
	if ($ENV{"LDAPPASS"}) {
		print "loading ldap_bindpw_file from environment\n" if ($DEBUG);
		$ldap_bindpw_file = $ENV{"LDAPPASS"};
	}
	if ($ENV{"ADUSER"}) {
		print "loading ad_binddn from environment\n" if ($DEBUG);
		$ad_binddn_file = $ENV{"ADUSER"};
	}
	if ($ENV{"ADPASS"}) {
		print "loading ad_bindpw from environment\n" if ($DEBUG);
		$ad_bindpw_file = $ENV{"ADPASS"};
	}

	if ($ENV{"SSHPUB"}) {
		print "loading ssh_pub_key from environment\n" if ($DEBUG);
		$ssh_pub_key = $ENV{"SSHPUB"};
	}
	if ($ENV{"SSHPRIV"}) {
		print "loading ssh_priv_key from environment\n" if ($DEBUG);
		$ssh_priv_key = $ENV{"SSHPRIV"};
	}	
	
	# At this point we should be ready to read in our credentials
	# from the files or defaults selected.
	if ($DEBUG) {
		print "ENV dump:\n", %ENV, "\n";
		print "ldap_binddn_file = $ldap_binddn_file\n",
			"ldap_bindpw_file = $ldap_bindpw_file\n",
			"ad_binddn_file = $ad_binddn_file\n",
			"ad_bindpw_file = $ad_bindpw_file\n";
	}
	
	
	# the first two options can also be specified in config.ph as
	# site deployment variables.
	if ($ldap_binddn_file && -r $ldap_binddn_file) {
		print "reading in ldap_binddn from $ldap_binddn_file\n" if ($DEBUG);
		$ldap_binddn = `cat $ldap_binddn_file`;
		chomp $ldap_binddn;
	}
	if ($ad_binddn_file && -r $ad_binddn_file) {
		print "reading in ldap_binddn from $ldap_binddn_file\n" if ($DEBUG);
		$ad_binddn = `cat $ad_binddn_file`;
		chomp $ad_binddn;
	}
	
	
	
	# Passwords are only read in from secure files or entered interactively.
	if (-r $ldap_bindpw_file) {
		print "reading in ldap_bindpw from $ldap_bindpw_file\n" if ($DEBUG);
		$ldap_bindpw = `cat $ldap_bindpw_file`;
		chomp $ldap_bindpw;
	# Cutting out the logic to interactively read in passwords
	#} else {
	#	print "debug: $ldap_bindpw_file\n";
	#	$ldap_bindpw = read_password('Enter Directory Manager password: ');
	#	chomp $ldap_bindpw;
	}
	
	if (-r $ad_bindpw_file) {
		print "reading in ad_bindpw from $ad_bindpw_file\n" if ($DEBUG);
		$ad_bindpw = `cat $ad_bindpw_file`;
		chomp $ad_bindpw;
	# Cutting out the logic to interactively read in passwords
	#} else {
	#	$ad_bindpw = read_password('Enter Corp role acct password: ');
	#	chomp $ad_bindpw;
	}
	if ($ENV["ad_binddn"]) {
		$ldap_binddn = $ENV["ad_binddn"];
	}
}


sub ldapConnect {
	# returns an LDAP connection
	# uses global variables setup in loadCreds() 
	# to determine credentials and servers
	
	if ($DEBUG) { print "connecting to $ldap_server ...\n"; }	
	my $ldap = Net::LDAP->new($ldap_server) or  die "$@";
	if ($DEBUG) { print "binding as $ldap_binddn \n"; }
	my $mesg = $ldap->bind($ldap_binddn, password => $ldap_bindpw);
	if ($DEBUG && ! $mesg->code) { print "LDAP bind successfully\n"; }
	if ($mesg->code) { print STDERR "error: ", $mesg->error; }
	return $ldap;
}

sub ADConnect {
	# returns an LDAP connection to AD
	if (! $ad_server) {
		# There's no AD connection available for this environment
		print "No Active Directory connection is available from $domain\n";
		return;
	}
	if ($DEBUG) { print "connecting to $ad_server ...\n"; }
	my $ldap = Net::LDAP->new($ad_server) or  die "$@";
	if ($DEBUG) { print "binding as $ad_binddn \n"; }
	my $mesg = $ldap->bind($ad_binddn,
		password => $ad_bindpw);
	$mesg->code && die "error: ", $mesg->error;
	return $ldap;
}

# takes: ldapconnection, base dn, query 
sub findObject {
	my $ldap = shift;
	my $base = shift;
	my $query = shift;
	if ($DEBUG) { print "findObject: base: " . $base . " query: " . $query . "\n"; }
	my $msg = $ldap->search(base => $base, filter => $query);
	if ($msg->code)	{
		$ec = $msg->code;
        	if ($ec == LDAP_NO_SUCH_OBJECT ) {
			print "\nCouldn't find $query .\n";
			exit(5);
	        }
        	print "LDAP Error code: $ec\n";
	        print STDERR $msg->error, "\n";
	}
	$ent=$msg->entry(0);
	return $ent;
}


# takes: ldapconnection, base dn, query 
sub findObjects {
	my $ldap = shift;
	my $base = shift;
	my $query = shift;
	if ($DEBUG) { print "findObjects: base: " . $base . " query: " . $query . "\n"; }
	my $msg = $ldap->search(base => $base, filter => $query);
	if ($msg->code)	{
		$ec = $msg->code;
        if ($ec == LDAP_NO_SUCH_OBJECT ) {
		print "\nCouldn't find $query .\n";
		exit(5);
        }
        print "LDAP Error code: $ec\n";
        die $msg->error;
	}
	my @entries=$msg->entries();
	return @entries;
}

# delete an object from the directory
# note that this doesn't do any cleanup of related objects (groups, netgroups)
# takes args: ldapconnection, dn
sub ldapDelete {
	my $ldap = shift;
	my $dn = shift;
	# Remove entry
	$msg = $ldap->delete($dn);
	if ($msg->code) {
		$ec = $msg->code;
        	if ($ec == LDAP_NO_SUCH_OBJECT ) {
			print "\nCouldn't find object $dn for delete operation.\n";
			exit(1);
	        }
        	print "LDAP Error code: $ec\n";
        	die $msg->error;
	}
	print "Deleted $dn\n";
	return 0;
}

1;
