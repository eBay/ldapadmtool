#!/usr/bin/perl


$usage_sudoer = "

Sudoer commands:
In general each sudoer object has a sudoer role name (specified with -s), 
a host-spec, a user-spec, and one or more command-specs.
A host-spec will either be a hostname or a host-netgroup with a + in front of it.
A user-spec will either be a username or a user-netgroup with a + in front of it.


Create a sudoer:
ldapadmtool.pl sudoer [-V] -C [-P] -e <env> -s <sudoername> -h <host-spec> -u <user-spec> -c \"<command-spec>\"

Add/remove sudoer commands:
ldapadmtool.pl sudoer [-V] [-P] -m <add|delete> -e <env> -s <sudoername> -u <user-spec> -h <host-spec> -c \"<command-spec>\"

Delete an entire sudoer record:
ldapadmtool.pl sudoer [-V]-D -e <env> -s <sudoername>


List/Display all of the sudoer entries:
ldapadmtool.pl sudoer [-V] -L -e <env> 

Display members of a sudoer entry (raw):
ldapadmtool.pl sudoer [-V] -L -e <env> -s <sudoername>


List/Display user members of a sudoer neatly:
ldapadmtool.pl sudoer [-V] -L -e <env> -s <sudoername> -N

Options:
-P	: use NOPASSWD option (don't prompt users for password)
-N  : print an entry neatly (sudoers file format)

Ex: to grant ALL perm to members of user-imd netgroup on host-imd machines:
ldapadmtool.pl sudoer -C -e arch -h +host-imd -u +user-imd -c ALL -P -s imd_all
";


sub ldapadmtoolSudoerMain {
	if ($argv =~ /sudoer help/) {
		print $usage_sudoer;
		exit 0;
	}
	# Any modifications or creations need to include all the options
	if (($opt_m || $opt_C) && ! ($opt_s && $opt_h && $opt_e && $opt_h && $opt_c)) {
		print $usage_sudoer;
		exit 0;
		
	}
	if ($opt_s && $opt_m eq "add") {
		print "adding a command to a sudoer entry\n" if ($DEBUG);
		my $ret = addCommandToSudoer($opt_s, $opt_u, $opt_h, $opt_c, $ldap);
		exit($ret);
		
	} elsif ($opt_s && $opt_m eq "delete") {
		print "removing a command from a sudoer entry\n" if ($DEBUG);
		my $ret = deleteCommandFromSudoer($opt_s, $opt_u, $opt_h, $opt_c, $ldap);
		exit($ret);
			
	}
	if ($opt_C) {
		print "creating a new sudoer entry\n" if ($DEBUG);
		my $ret = newSudoerEntry($opt_s, $opt_u, $opt_h, $opt_c, $ldap);
		exit($ret);

	}
	
	# listing options
	if ($opt_L && $opt_s) {
		exit (displaySudoer($opt_s, $opt_e, $ldap));
	}
	# if you don't choose what sudoers to display, it will list them all.
	if ($opt_L && ! $opt_s) {
		my @sudoers = listSudoers($ldap, "cn=*");
		print join("\n", @sudoers), "\n";
		exit 0;
	}
	
	
	# remove sudoer - removes entire entry
	if ($opt_s &&  $opt_D) {
		if (! $opt_F) {
			print "Do you really want to delete the sudoer record, $opt_s, from domain $opt_e? [y/n]: ";
			my $ans = <>;
			unless ($ans =~ /^y/ || $ans =~ /^Y/) {
				print "OK, action cancelled. Goodbye.\n";
				exit 4;
			}
		}
		print "Removing sudoer $opt_s from $opt_e\n";
		my $ret = ldapDelete($ldap, "cn=" . $opt_s . "," . $base_sudoer);
		exit($ret) if $ret;
	}
	print "Couldn't match what you asked for with an action!\n$usage_sudoer\n";
	exit 1;	
}



# Search function for finding sudoer members
# takes: ldapconnection, query
sub listSudoers {
	my $ldap = shift;
	my $query = shift;
	
	print "searching for $query in $base_sudoer\n" if ($DEBUG);
	my $sudoerattrs = [ 'cn', 'sudoCommand', 'sudoHost', 'sudoUser' ];
	my $result = $ldap->search ( base    => "$base_sudoer",
	scope   => "sub",
	filter  => "$query",
	attrs   =>  $sudoerattrs );
	my $href = $result->as_struct;
	my @arrayOfDNs  = keys %$href;        # use DN hashes
	my @sudoers;
	# process each DN using it as a key
	foreach ( @arrayOfDNs ) {
		my $valref = $$href{$_};
		# get an array of the attribute names passed for this one DN.
		my @arrayOfAttrs = sort keys %$valref; #use Attr hashes
		my $attrName;        
		foreach $attrName (@arrayOfAttrs) {
			# skip any binary data: yuck!
			next if ( $attrName =~ /;binary$/ );
			my $attrVal =  @$valref{$attrName};
			if ($attrName eq "cn") {
				foreach ( @$attrVal ) {
					#print "$_\n";
					push(@sudoers, $_);
				}
			}
		}
		# End of that DN
	}
	return @sudoers;
}

# create a new sudoer object like this:
#dn: cn=qadba_mysql,ou=SUDOers,dc=example,dc=com
#objectClass: sudoRole
#objectClass: top
#cn: qadba_mysql
#sudoCommand: /usr/bin/su - mysql
#sudoHost: ALL
#sudoUser: +qadba
# takes name, user-spec, host-spec, command, ldapconnection
# returns the created entry
#newSudoerEntry($opt_s, $opt_u, $opt_h, $opt_c, $ldap);
sub newSudoerEntry {
	my $name = shift;
	my $userspec = shift;
	my $hostspec = shift;
	my $command = shift;
	my $ldap = shift;
	
	my $dn = "cn=$name,$base_sudoer";
	print "adding: $dn\n" if ($DEBUG);
	my $entry = new Net::LDAP::Entry;
	$entry->dn($dn);
	$entry->add("objectClass" => [qw( top sudoRole )] );
	$entry->add("sudoUser", $userspec);
	$entry->add("sudoHost", $hostspec);
	$entry->add("sudoCommand", $command);
	$entry->add("sudoOption", "!authenticate") if ($opt_P);
	print "about to save sudoer $name :\n", $entry->dump, "\n" if ($DEBUG);
	$result = $entry->update($ldap);
	$result->code && print STDERR "error: ", $result->error, "\n";
	return $entry;
}

# takes name, domain, connection
# returns the entry
sub loadSudoer {
	my $name = shift;
	my $domain = shift;
	my $ldap = shift;
	# 
	my $query = "cn=$name";
	my $result = $ldap->search ( base    => "$base_sudoer",
	scope   => "sub",
	filter  => "$query");
	
	# assume only one record will match the query
	my $entry = $result->entry(0);
	if (!$entry) {
		print STDERR "couldn't find sudoer: $name in $domain uder $base_sudoer\n";
		return;
	} else {
		return $entry;
	}
}

# takes name, domain, connection, optional option
sub displaySudoer {
	my $name = shift;
	my $domain = shift;
	my $ldap = shift;
	my $option = shift;
	my $entry = loadSudoer($name, $domain, $ldap);
	if (! $entry) {
		print "No such sudoer record $name in $domain\n";
		return;
	}
	
	if ($opt_N) {
		my $userspec = $entry->get_value("sudoUser");
		my $hostspec = $entry->get_value("sudoHost");
		my $options  = $entry->get_value("sudoOption"); 
		my @commands = $entry->get_value("sudoCommand");
		print "$userspec\t$hostspec = ", (($options =~ /\!authenticate/) ? "NOPASSWD: " : ""), join(", ", @commands), "\n";
		# We're done
		return;
	} else {
		# otherwise, dump neatly 
		$entry->dump();
	}
}

# addCommandToSudoer($opt_s, $opt_u, $opt_h, $opt_c, $ldap);
# takes user, sudoer, domain, ldapconnection args
sub addCommandToSudoer {
	my $name = shift;
	my $userspec = shift;
	my $hostspec = shift;
	my $command = shift;
	my $ldap = shift;
	my $entry = &loadSudoer($name, $domain, $ldap);
	if (! $entry) {
		print STDERR "Sudoer entry $name not found in $domain\n";
		return 27;
	} else {
		my @commands = $entry->get_value("sudoCommand");
		if (grep {$_ eq $command} @commands) {
			# The command is already in the sudoer record! But this isn't a bad error so return 0.
			print "$command is already in $name\n";
			return 0;
		}
		print "add: $name : $command\n" if ($DEBUG>1);
		$entry->add("sudoCommand", $command);
		$entry->add("sudoOption", "!authenticate") if ($opt_P);
		$result = $entry->update($ldap);
		if ($result->code) {
			print STDERR "error: ", $result->error, "\n";
			return $result->code;
		}
		print "$command added to $name\n";
		return 0;
	}
}

# takes user, sudoer, domain, ldapconnection args
sub deleteCommandFromSudoer {
	my $name = shift;
	my $userspec = shift;
	my $hostspec = shift;
	my $command = shift;
	my $ldap = shift;
	my $entry = &loadSudoer($name, $domain, $ldap);	if (! $entry) {
		print STDERR "Sudoer entry $name not found in $domain\n";
	} else {
		my @commands = $entry->get_value("sudoCommand");
		if (! grep {$_ eq $command} @commands) {
			# The command isn't already in the sudoer record! But this isn't a bad error so return 0.
			print "$command isn't already in $name\n";
			return 0;
		}
		print "delete: $name : $command\n" if ($DEBUG>1);
		$entry->delete("sudoCommand", $command);

		$result = $entry->update($ldap);
		if ($result->code) {
			print STDERR "error: ", $result->error, "\n";
			return $result->code;
		}
		print "$command removed from $name\n";
		return 0;
	}
}



1;
