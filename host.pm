#!/usr/bin/perl
# This is the UNIX LDAP command toolchain by Adam Beeman, 2011, eBay Inc.

# This module contains all the host related functions

# interesting host related functions that could be incorporated into this
# module are:

# ssh key installation logic - see magic-update-keys script 
# this logic requires ssh-askpath and access to the password list

# ldap client setup - provide the most direct method for all supported OSes

# ldap client access management 

# file distribution - update essential config files, etc, on hosts of all types
# includes support for both different platforms and different profiles


use Socket;



$usage_host = "


Host commands:
ldapadmtool.pl host [-v][-A][-p][-i] [-e <env>] -h <hostname> [-n <netgroup>]

Basic login check:
ldapadmtool.pl host [-V] -B -h <hostname>

Update Password file for Netgroup inclusions on a host:
ldapadmtool.pl host [-V] -P|-A -h <hostname> [-e <env>]

-P : push updates to host
-A : append updates to host
-i : install/reinstall ldap client files on host (not yet implemented)
";


#List/Search commands:
#ldapadmtool.pl host [-v] -e <env> -L -u <username> [-F '<attribute-list>']
#ldapadmtool.pl host [-v] -e <env> -L -g <gidgroup> [-F '<attribute-list>']
#ldapadmtool.pl host [-v] -e <env> -L -n <netgroup> [-F '<attribute-list>']
#ldapadmtool.pl host [-v] -e <env> -L -h <hostname>   # we don't really use host records much



sub ldapadmtoolHostMain {
	if ($argv =~ /host help/) {
		print $usage_host;
		exit 0;
	}
	if ($default_env && ! $opt_e) {
		$opt_e = $default_env;
	}
	# this is a basic validation of being able to login and run "uname" using our ssh keys, etc.
	if ($opt_B && $opt_h) {
		my $output;
		eval {
			local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
			alarm $timeout;
			# do stuff
			my $fqdn = $opt_h . "." . $domains{$opt_e};
			print "testing login to $fqdn\n";
			$output = `ssh -l root -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $fqdn	 uname`;
			alarm 0;
		};
		if ($@) {
			print "login to $opt_h timed out\n";
			die unless $@ eq "alarm\n";   # propagate unexpected errors
			# timed out
		} else {
			print "check of $opt_h completed sucessfully\n";
			print $output;
		}
		
	}
	
	if ($opt_P && $opt_h && $opt_e) {
		my ($hostname, $domainname) = split("\\.", $opt_h, 2);
		print "hostname : $hostname domainname : $domainname\n" if ($DEBUG);
		return updateHostPasswd($ldap, $hostname);
		#my $ip_addr = lookupHostDNS($opt_h);
		#if ($ip_addr) {
		#	print updateHostPasswd($ldap, $ip_addr);
		#} else {
		#	print "Couldn't lookup up an address for $opt_h\n";
		#	exit 21;
		#}
	}

	if ($opt_A && $opt_h && $opt_e) {
		my ($hostname, $domainname) = split("\\.", $opt_h, 2);
		print "hostname : $hostname domainname : $domainname\n" if ($DEBUG);
		return appendHostPasswd($ldap, $hostname);
	}	
	print "Couldn't match what you asked for with an action!\n$usage_host\n";
	exit 1;	
}

# takes a hostname, optional domain name, and gets an an IP, or fails.
sub lookupHostDNS {
	my $hostname = shift;
	my $domain = shift;
	# does the hostname contain dots? Maybe it's an FQDN already
	if ($hostname =~ /\./) {
		my ($host, $spdomain) = split('\.', $hostname, 2);
		$hostname = $1;
		$domain = "$spdomain";
		print "lookupHostDNS: got $domain from $hostname\n" if ($DEBUG);
	} elsif (! $domain && $opt_e) {
		$domain = $domains{$opt_e};	
		print "lookupHostDNS: got $domain from -e $opt_e\n" if ($DEBUG);
	} else {
		print "$lookupHostDNS: using $domain before lookup\n" if ($DEBUG);
	}
	my $packed_ip = gethostbyname($hostname . "." . $domain);
	if (defined $packed_ip) {
        $ip_address = inet_ntoa($packed_ip);
		print "lookupHostDNS: found $ip_address\n" if ($DEBUG);
		return $ip_address;
	} else { 
		warn "no matching A record for $hostname\n";
		return 0;
	}

}

# run a command with a timeout on a host. 
# Takes: hostname, remote-command, optional timeout in seconds (defaults to 30)
# Returns: output of remote command.
# Will not 
sub remoteCommand {
	my $hostname = shift;
	my $rcmd = shift;
	my $timeout = shift;
	if (! $timeout) { $timeout = 30; }
	$output; # we'll need this if the command works
	eval {
        local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
        alarm $timeout;
		print "remoteCommand trying: $hostname : $rcmd\n" if ($DEBUG);
		#-o BatchMode=yes
		$output = `ssh -tx -o BatchMode=yes  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -l root $hostname "$rcmd"`;
		alarm 0;
	};
	
	if ($@) {
        warn " $hostname connection timed out";
        die unless $@ eq "alarm\n";   # propagate unexpected errors
        # timed out
	} else {
		print "remoteCommand got: $output\n" if ($DEBUG);
        return $output;
	}
	

}

# verify/install ssh key
# Takes: hostname, keyfile
# returns: message or 0 if unsuccessful.
sub verifyKeys {
	my $hostname = shift;
	my $keyfile = shift;
	my $key = `cat $keyfile`;
	chomp $key;
	if (!$key) {
		warn "can't open keyfile $keyfile!";
		return 0;
	}
	my @keyparts = split(" ", $key);
	my $keyname = $keyparts[-1];
	print "using key named $keyname\n" if ($DEBUG);
	print "backing up authorized_keys2 on remote host\n" if ($DEBUG);
	my $output = remoteCommand($hostname, "pwd ; mkdir -p .ssh ; cp -p .ssh/authorized_keys2 .ssh/authorized_keys2.bak ;id ;  ls -la .ssh ;egrep -v \"" . $keyname . "\" .ssh/authorized_keys2.bak > .ssh/authorized_keys2");
	print $output if ($DEBUG);
	print "pushing authorized_keys2 from local host\n" if ($DEBUG);
	my $output = `cat $keyfile | ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -l root "$hostname" "cat >> .ssh/authorized_keys2"`;
	print $output if ($DEBUG);
	if ($output =~ /Permission denied/) {
		warn "Couldn't update keys on $hostname";
		return 0;
	}
	print "ssh keys installed on $hostname sucessfully\n" if ($DEBUG);
	return "success";
}


# todo: verify. this was brought over from earlier versions of code
# current issues: reliance on local filesystem, how to find DNS subdomain 
# takes: ldapconnection, hostname, domainname
sub updateHostPasswd {
	my $ldap = shift;
	my $hostname = shift;
	
	# this section will need updating when we add domains to the netgroup triplets
	my $query = 'nisNetgroupTriple=\(' . $hostname . ',,\)';
	my @netgroups = listNetgroups($ldap, $query);
	print "Found netgroups for $hostname: \n" . join(" ", @netgroups) . "\n" if ($DEBUG);
     
	my $appendstr =  "+\@" . $admin_netgroup{$opt_e};
	my $ng;
	foreach $ng (@netgroups) {
		next if ($ng eq "ldapclients"); # skip "default" netgroup
		# include user netgroups and not host netgroups
		$ng =~ s/host-/user-/;
		$appendstr = $appendstr . "\n+\@" . $ng;
		print "gen: $ng went onto $appendstr" if ($DEBUG);
	}
	#chomp $appendstr; # trailing newlines will get added back by echo below.
	print "generated passwd.append contents:\n$appendstr" if ($DEBUG);
	my $fqdn;
	if ($opt_h =~ /\./) {
		$fqdn = $opt_h;
		print "$fqdn had dots in it, assume FQDN\n" if ($DEBUG);
	} else {
		$fqdn = $hostname . "." . $domains{$opt_e};
		print "added domain to hostname to get $fqdn\n";
		
	}
	print "updating files on $fqdn\n" if ($DEBUG);
	print "echo \"$appendstr\" | ssh -tx root\@$fqdn 'cat > /etc/passwd.append'\n" if ($DEBUG);
	print `echo \"$appendstr\" | ssh -tx root\@$fqdn 'cat > /etc/passwd.append'`; 
	print "ssh -tx root\@$fqdn 'cd /etc; grep -v \"^+@\" passwd > passwd.base ; cat passwd.base passwd.append > passwd ; chmod 644 passwd; pwconv'\n" if ($DEBUG);
	print `ssh -tx root\@$fqdn 'cd /etc; grep -v \"^+@\" passwd > passwd.base ; cat passwd.base passwd.append > passwd ; chmod 644 passwd; pwconv'`;

}

sub appendHostPasswd {
	my $ldap = shift;
	my $hostname = shift;
	
	# this section will need updating when we add domains to the netgroup triplets
	my $query = 'nisNetgroupTriple=\(' . $hostname . ',,\)';
	my @netgroups = listNetgroups($ldap, $query);
	print "Found netgroups for $hostname: \n" . join(" ", @netgroups) . "\n" if ($DEBUG);
     
	my $appendstr =  "+\@" . $admin_netgroup{$opt_e};
	my $ng;
	foreach $ng (@netgroups) {
		next if ($ng eq "ldapclients"); # skip "default" netgroup
		# include user netgroups and not host netgroups
		$ng =~ s/host-/user-/;
		$appendstr = $appendstr . "\n+\@" . $ng;
		print "gen: $ng went onto $appendstr" if ($DEBUG);
	}
	#chomp $appendstr; # trailing newlines will get added back by echo below.
	print "generated passwd.append contents:\n$appendstr" if ($DEBUG);
	my $fqdn;
	if ($opt_h =~ /\./) {
		$fqdn = $opt_h;
		print "$fqdn had dots in it, assume FQDN\n" if ($DEBUG);
	} else {
		$fqdn = $hostname . "." . $domains{$opt_e};
		print "added domain to hostname to get $fqdn\n";
		
	}
	print "updating files on $fqdn\n" if ($DEBUG);
	print "echo \"$appendstr\" | ssh -tx root\@$fqdn 'cat > /etc/passwd.append'\n" if ($DEBUG);
	print `echo \"$appendstr\" | ssh -tx root\@$fqdn 'cat > /etc/passwd.append'`; 
	print "ssh -tx root\@$fqdn 'cd /etc; grep -v \"^+@\" passwd > passwd.base ; grep \"^+@\" passwd >> passwd.append; cat passwd.base > passwd ; cat passwd.append| sort -u >> passwd; chmod 644 passwd; pwconv'\n" if ($DEBUG);
	print `ssh -tx root\@$fqdn 'cd /etc; grep -v \"^+@\" passwd > passwd.base ; grep \"^+@\" passwd >> passwd.append; cat passwd.base > passwd ; cat passwd.append| sort -u >> passwd; chmod 644 passwd; pwconv'`;

}

1;
