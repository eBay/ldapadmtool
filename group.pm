#!/usr/bin/perl



$usage_group = "

Group commands:
Create a group:
ldapadmtool.pl group [-V] -C -e <env> -g <groupname> [-i <gidnumber>] [-d \"<description>\"]

Add/remove group members:
ldapadmtool.pl group [-V][-f] -m <add|delete> -e <env> -g <groupname> -u <username>

Delete an entire group:
ldapadmtool.pl group [-V]-D -e <env> -g <groupname>


List/Display all of the groups:
ldapadmtool.pl group [-V] -L -e <env> 

Display members of a group (raw):
ldapadmtool.pl group [-V] -L -e <env> -g <gidgroup>


List/Display user members of a group neatly:
ldapadmtool.pl group [-V] -L -e <env> -g <gidgroup> -U


";


sub ldapadmtoolGroupMain {
	if ($argv =~ /group help/) {
		print $usage_group;
		exit 0;
	}
	if (! $opt_e && $default_env) {
		$opt_e = $default_env;
	}
	unless ($opt_e) {
		print "You must specify an environment with the -e option or set a default environment!\n";
		exit 3;
	}
	if ($opt_m eq "add") {
		print "adding a member to a gidgroup\n" if ($DEBUG);
		if (! $opt_g) {
			print "You must specify a gidgroup when using -m add\n";
			exit 3;
		}
		if ($opt_u) {
			my $ret = addUserToGidgroup($opt_u, $opt_g, $opt_e, $ldap);
		 	exit($ret) if $ret;
		} elsif ($opt_h) {
			my $ret = addHostToGidgroup($opt_h, $opt_g, $opt_e, $ldap);
		 	exit($ret) if $ret;
		} elsif ($opt_c) {
			my $ret = addGidgroupToGidgroup($opt_c, $opt_g, $opt_e, $ldap);
		 	exit($ret) if $ret;
		} else {
			print "You must specify a user, host, or gidgroup to add!\n";
			exit 5;
		}
		
	} elsif ($opt_m eq "delete") {
		print "removing a member from a gidgroup\n" if ($DEBUG);
		if (! $opt_g) {
			print "You must specify a gidgroup when using -m delete\n";
			exit 3;
		}
		if ($opt_u) {
			my $ret = deleteUserFromGidgroup($opt_u, $opt_g, $opt_e, $ldap);
		 	exit($ret) if $ret;
	
		} else {
			print "You must specify a user, host, or gidgroup to delete!\n";
			exit 4;
		}
	}
	
	# listing options
	if ($opt_L && $opt_g) {
		if ($opt_U) {
			if ($DEBUG) { print "opt_U selected. Listing Users\n"; }
			displayGidgroup($opt_g, $opt_e, $ldap, "users");
		} else {
			displayGidgroup($opt_g, $opt_e, $ldap);
		}
	}
	# if you don't choose what gidgroups to display, it will list them all.
	if ($opt_L && ! $opt_g) {
		my @gidgroups = listGidgroups($ldap, "cn=*");
		print join("\n", @gidgroups), "\n";
	}
	
	
	# remove gidgroup
	# currently this only removes the gidgroup, it doesn't clean up references to
	# it which exist in other gidgroups, it doesn't touch any hosts 
	# or do any other housekeeping.
	if ($opt_g &&  $opt_D) {
		if (! $opt_F) {
			print "Do you really want to delete the gidgroup, $opt_g, from domain $opt_e? [y/n]: ";
			my $ans = <>;
			unless ($ans =~ /^y/ || $ans =~ /^Y/) {
				print "OK, action cancelled. Goodbye.\n";
				exit 4;
			}
		}
		print "Removing gidgroup $opt_g from $opt_e\n";
		my $ret = ldapDelete($ldap, "cn=" . $opt_g . "," . $base_group);
		exit($ret) if $ret;
	}
	
	if ($opt_C) {
		if ($opt_d) {
			createGidgroup($opt_g, $ldap, $opt_d);
		} else {
			createGidgroup($opt_g, $ldap);
		}
	}

}



# Search function for finding gidgroup members
# takes: ldapconnection, query
sub listGidgroups {
	my $ldap = shift;
	my $query = shift;
	
	print "searching for $query in $base_group\n" if ($DEBUG);
	my $groupattrs = [ 'cn', 'memberUid' ];
	my $result = $ldap->search ( base    => "$base_group",
	scope   => "sub",
	filter  => "$query",
	attrs   =>  $groupattrs );
	my $href = $result->as_struct;
	my @arrayOfDNs  = keys %$href;        # use DN hashes
	my @groups;
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
					push(@groups, $_);
				}
			}
		}
		# End of that DN
	}
	return @groups;
}

# create a new gidgroup object
# takes name, connection, optional description
# returns the created entry
sub createGidgroup {
	my $name = shift;
	my $ldap = shift;
	my $desc = shift;
	
	my $dn = "cn=$name,$base_group";
	print "adding: $dn\n" if ($DEBUG);
	my $entry = new Net::LDAP::Entry;
	$entry->dn($dn);
	$entry->add("objectClass" => [qw( top posixGroup )] );
	$entry->add("description", $desc) if ($desc);
	$entry->add("gidNumber", $opt_i ? $opt_i : nextgid($ldap, $base_group));
	print "about to save group $name :\n", $entry->dump, "\n" if ($DEBUG);
	$result = $entry->update($ldap);
	$result->code && print STDERR "error: ", $result->error, "\n";
	return $entry;
}

# takes name, domain, connection
# returns the entry
sub loadGidgroup {
	my $name = shift;
	my $domain = shift;
	my $ldap = shift;
	# 
	my $query = "cn=$name";
	my $result = $ldap->search ( base    => "$base_group",
	scope   => "sub",
	filter  => "$query");
	
	# assume only one record will match the query
	my $entry = $result->entry(0);
	if (!$entry) {
		print STDERR "couldn't find gidgroup: $name in $domain uder $base_group\n";
		return;
	} else {
		return $entry;
	}
}

# takes name, domain, connection, optional option
sub displayGidgroup {
	my $name = shift;
	my $domain = shift;
	my $ldap = shift;
	my $option = shift;
	my $entry = loadGidgroup($name, $domain, $ldap);
	if (! $entry) {
		print "No such gidgroup $name in $domain\n";
		return;
	}
	
	if ($option eq "users") {
		my @users = $entry->get_value("memberuid");
		foreach my $user (@users) {
			print "$user\n";
		}
		# We're done
		return;
	} else {
		# otherwise, dump neatly 
		$entry->dump();
	}
}


# takes user, gidgroup, domain, ldapconnection args
sub addUserToGidgroup {
	my $username = shift;
	my $gidgroup = shift;
	my $domain = shift;
	my $ldap = shift;
	my $entry = &loadGidgroup($gidgroup, $domain, $ldap);
	if (! $entry) {
		print STDERR "Gidgroup $gidgroup not found in $domain\n";
		return 22;
	} else {
		my @members = $entry->get_value("memberuid");
		if (grep {$_ eq $username} @members) {
			# The user is already in the gidgroup! But this isn't a bad error so return 0.
			print "$username is already in $gidgroup\n";
			return 0;
		}
		print "add: memberud : $username\n" if ($DEBUG>1);
		$entry->add("memberuid" => $username);
		$result = $entry->update($ldap);
		if ($result->code) {
			print STDERR "error: ", $result->error, "\n";
			return $result->code;
		}
		print "$username added to $gidgroup\n";
		return 0;
	}
}

# takes user, gidgroup, domain, ldapconnection args
sub deleteUserFromGidgroup {
	my $username = shift;
	my $gidgroup = shift;
	my $domain = shift;
	my $ldap = shift;
	my $entry = &loadGidgroup($gidgroup, $domain, $ldap);
	if (! $entry) {
		print STDERR "Gidgroup $gidgroup not found in $domain\n";
	} else {
		my @members = $entry->get_value("memberuid");
		if (! grep {$_ eq $username} @members) {
			# The user is not in the gidgroup! But this isn't a bad error so return 0.
			print "$username is not in $gidgroup\n";
			return 0;
		}
		print "delete: memberuid : $username\n" if ($DEBUG>1);
		$entry->delete("memberuid" => $username);
		$result = $entry->update($ldap);
		if ($result->code) {
			print STDERR "error: ", $result->error, "\n";
			return $result->code;
		}
		print "$username removed from $gidgroup\n";
		return 0;
	}
}

# get the next available UID number
# takes an LDAP connection and base as argument
sub nextgid {
	my $ldap = shift;
	my $base = shift;
	if ($DEBUG) { print "nextgid: base: $base \n"; }
	my $ldfilter = '(&(objectClass=posixGroup)(gidNumber>=1000)(gidNumber<=30000))';
	my $ldsrch = $ldap->search(base => $base, filter => $ldfilter,
	attrs => [ 'gidNumber' ] );
	die $ldsrch->error if $ldsrch->code;
	$ect = $ldsrch->count();
	print "Got: $ect records\n";
	# problem with this is that it uses a lexical sort, not a numeric one
	@esrt = $ldsrch->sorted('gidNumber');
	$u1 = $esrt[0]->get_value('gidNumber');
	for($i = 0 ; $i < $ect ; $i++) {
		$u2 = $esrt[$i]->get_value('gidNumber');
		#print "u1: $u1 , u2: $u2 \n";
		if ( ( $u2 - $u1 ) > 1 ) {
			$nuid = $u1 + 1;
			return $nuid;
			last;
		}
		$u1 = $u2;
	}
	# fall through to incrementing from the last found uid
	$nuid = $u1 + 1;
	return $nuid;
}



1;
