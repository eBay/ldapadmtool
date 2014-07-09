#!/usr/bin/perl
# This is part of the UNIX LDAP command toolchain by Adam Beeman, 2011, eBay Inc.

use Net::LDAP::Entry;

$usage_netgroup = "ldapadmtool.pl Netgroup administration commands

Create a netgroup:
ldapadmtool.pl netgroup [-][-F] -C -e <env> -n <netgroup> [-d \"<description>\"]

Delete an entire netgroup:
ldapadmtool.pl [-v][-F] -D -e <env> -n <netgroup>

Add/remove netgroup members:
ldapadmtool.pl netgroup [-V][-f] -m <add|delete> -e <env> -n <netgroup> -u <username>
ldapadmtool.pl netgroup [-V][-f] -m <add|delete> -e <env> -n <netgroup> -h <hostname>
ldapadmtool.pl netgroup [-V][-f] -m <add|delete> -e <env> -n <netgroup> -c <child-netgroup>

When using -m add, if the options to -u or -h are comma separated lists, 
you can add multiple items at once.

List/Display all of the netgroups:
ldapadmtool.pl netgroup [-V] -L -e <env> 

List/Display members of a netgroup (raw):
ldapadmtool.pl netgroup [-V] [-R] -L -e <env> -n <netgroup>

List/Display user members of a netgroup neatly:
ldapadmtool.pl netgroup [-V] [-R] -L -e <env> -n <netgroup> -U

List/Display host members of a netgroup neatly:
ldapadmtool.pl netgroup [-V] [-R] -L -e <env> -n <netgroup> -H

Display child netgroup members of a netgroup neatly:
ldapadmtool.pl netgroup [-V] -L -e <env> -n <netgroup> -N

Options: 
-R : recursive list - descend into child netgroups and get their values, too.
-V : verbose - print extra debugging info.
";

# Hidden option (not needed often):
# Repair broken host entries in a netgroup: changes (hostname,-,-) to (hostname,,) :
# ldapadmtool.pl netgroup [-V] -R -e <env> -n <netgroup>


sub ldapadmtoolNetgroupMain {
	if ($argv =~ /netgroup help/) {
		print $usage_netgroup;
		exit 0;
	}
	if (! $opt_e && $default_env) {
		$opt_e = $default_env;
	}
	unless ($opt_e) {
		print "You must specify an environment with the -e option or set a default environment!\n";
		exit 3;
	}
	# if unexpected args are provided, remind users of the syntax
	if (@extras) {
		print "Unexpected argument(s) provided: ", join(" ", @extras), "\n";
		print $usage_netgroup;
		exit 1;
	}
	if ($opt_m eq "add") {
		print "adding a member to a netgroup\n" if ($DEBUG);
		if (! $opt_n) {
			print "You must specify a netgroup when using -m add\n";
			exit 3;
		}
		if ($opt_u) {
			my @items = split(",", $opt_u);
			my $ret;
			foreach my $item (@items) {
				$ret = addUserToNetgroup($item, $opt_n, $opt_e, $ldap);
			}
		 	exit($ret);
		} elsif ($opt_h) {
			my @items = split(",", $opt_h);
			my $ret;
			foreach my $item (@items) {
				$ret = addHostToNetgroup($item, $opt_n, $opt_e, $ldap);
			}
		 	exit($ret);
		} elsif ($opt_c) {
			my $ret = addNetgroupToNetgroup($opt_c, $opt_n, $opt_e, $ldap);
		 	exit($ret);
		} else {
			print "You must specify a user, host, or netgroup to add!\n";
			exit 5;
		}
	} elsif ($opt_m eq "delete") {
		print "removing a member from a netgroup\n" if ($DEBUG);
		if (! $opt_n) {
			print "You must specify a netgroup when using -m delete\n";
			exit 3;
		}
		if ($opt_u) {
			my $ret = deleteUserFromNetgroup($opt_u, $opt_n, $opt_e, $ldap);
		 	exit($ret);
		} elsif ($opt_h) {
			my $ret = deleteHostFromNetgroup($opt_h, $opt_n, $opt_e, $ldap);
		 	exit($ret);
		} elsif ($opt_c) {
			my $ret = deleteNetgroupFromNetgroup($opt_c, $opt_n, $opt_e, $ldap);
		 	exit($ret);
		} else {
			print "You must specify a user, host, or netgroup to delete!\n";
			exit 4;
		}
	}
	if ($opt_L && $opt_n) {
		if ($opt_U) {
			if ($DEBUG) { print "opt_U selected. Listing Users\n"; }
			displayNetgroup($opt_n, $opt_e, $ldap, "users");
		} elsif ($opt_H) {
			if ($DEBUG) { print "opt_H selected. Listing Hosts\n"; }
			displayNetgroup($opt_n, $opt_e, $ldap, "hosts");
		} elsif ($opt_N) {
			if ($DEBUG) { print "opt_N selected. Listing child Netgroups\n"; }
			displayNetgroup($opt_n, $opt_e, $ldap, "children");
		} else {
			displayNetgroup($opt_n, $opt_e, $ldap);
		}
		exit 0;
	}
	# if you don't choose what netgroups to display, it will list them all.
	if ($opt_L && ! $opt_n) {
		my @netgroups = listNetgroups($ldap, "cn=*");
		print join("\n", @netgroups), "\n";
		exit 0;
	}
		
		
	# remove netgroup
	# currently this only removes the netgroup, it doesn't clean up references to
	# it which exist in other netgroups, it doesn't touch any hosts 
	# or do any other housekeeping.
	if ($opt_n &&  $opt_D) {
		if (! $opt_F) {
			print "Do you really want to delete the netgroup, $opt_n, from domain $opt_e? [y/n]: ";
			my $ans = <>;
			unless ($ans =~ /^y/ || $ans =~ /^Y/) {
				print "OK, action cancelled. Goodbye.\n";
				exit 4;
			}
		}
		print "Removing netgroup $opt_n from $opt_e\n";
		my $ret = ldapDelete($ldap, "cn=" . $opt_n . "," . $base_netgroup);
		exit($ret);
	}
	
	if ($opt_C) {
		if ($opt_d) {
			createNetgroup($opt_n, $ldap, $opt_d);
		} else {
			createNetgroup($opt_n, $ldap);
		}
		exit 0;
	}
	if ($opt_R) {
		repairNetgroup($opt_n, $opt_e, $ldap);
		exit 0;
	}
	print "No action selected!\n", $usage_netgroup;
	exit 60;
	
}



# Search function for finding netgroup members
# takes: ldapconnection, query
# This function uses a global hash to keep track of what's already been looked up,
# to prevent repeat queries when doing recursion.
# the recursion-proofing logic has been commented out, since the recursion is also
# disabled at the moment
# returns a list of netgroups.
#%listNetgroupsQueries; 
sub listNetgroups {
	my $ldap = shift;
	my $query = shift;
	
	# don't re-run previous queries.
	if ($listNetgroupsQueries{$query}) {
		print "duplicate query: $query\n" if ($DEBUG);
		return;
	}
	$listNetgroupsQueries{$query} = 1;
	print "searching for $query in $base_netgroup\n" if ($DEBUG);
	my $groupattrs = [ 'cn', 'nisNetgroupTriple', 'memberNisNetgroup' ];
	my $result = $ldap->search ( base    => "$base_netgroup",
		scope   => "sub",
		filter  => "$query",
		attrs   =>  $groupattrs );
	my $href = $result->as_struct;
	my @arrayOfDNs  = keys %$href;        # use DN hashes
	my @netgroups;
	# process each DN using it as a key
	foreach ( @arrayOfDNs ) {
		#print "check1: ", $_, "\n";
		my $valref = $$href{$_};
		# get an array of the attribute names
		# passed for this one DN.
		my @arrayOfAttrs = sort keys %$valref; #use Attr hashes
		my $attrName;        
		foreach $attrName (@arrayOfAttrs) {
			# skip any binary data: yuck!
			next if ( $attrName =~ /;binary$/ );
			# get the attribute value (pointer) using the
			# attribute name as the hash
			my $attrVal =  @$valref{$attrName};
			#print "\t $attrName: @$attrVal \n";
			if ($attrName eq "cn") {
				foreach ( @$attrVal ) {
					#print "$_\n";
					push(@netgroups, $_);
					# if we wanted to do recursion and find what netgroups the
					# found objects are also members of, enable this.
					if ($opt_R) {
						#print "checking: $_\n";
						my @result = listNetgroups($ldap, "membernisnetgroup=$_");
						if (@result) { @netgroups = (@netgroups, @result); }
					}
				}
			}
		}
		# End of that DN
	}
	return @netgroups;
}






# create a new netgroup object
# takes name, connection, optional description
# returns the created entry
sub createNetgroup {
	my $name = shift;
	my $ldap = shift;
	my $desc = shift;
	my $dn = "cn=$name,$base_netgroup";
	print "adding: $dn\n" if ($DEBUG);
	my $entry = new Net::LDAP::Entry;
	$entry->dn($dn);
	$entry->add("objectClass" => [qw( top nisNetgroup )] );
	$entry->add("description", $desc) if ($desc);
	if ($DRYRUN) {
		print "DRYRUN: $netgroup not updated\n";
	} else {
		print "about to save\n" if ($DEBUG);
		$result = $entry->update($ldap);
	}
	if ($result->code) {
		print STDERR "error: ", $result->error;
	} else {
		print "Created netgroup $name in $base_netgroup\n";
	}
	return $entry;
}

# takes name, domain, connection
# returns the entry
sub loadNetgroup {
	my $name = shift;
	my $domain = shift;
	my $ldap = shift;
	# 
	my $query = "cn=$name";
	my $result = $ldap->search ( base    => "$base_netgroup",
		scope   => "sub",
		filter  => "$query");
	
	# assume only one record will match the query
	my $entry = $result->entry(0);
	if (!$entry) {
		print STDERR "couldn't find netgroup: $name in $domain under $base_netgroup";
		return;
	} else {
		return $entry;
	}
}

# takes name, domain, connection, optional option
sub displayNetgroup {
	my $name = shift;
	my $domain = shift;
	my $ldap = shift;
	my $option = shift;
	my $entry = loadNetgroup($name, $domain, $ldap);
	if (! $entry) {
		print "No such netgroup $name in $domain\n";
		return;
	}
	
	if ($option eq "users") {
		my @users = $entry->get_value("nisnetgrouptriple");
		foreach $ng (@users) {
			# (,abeeman,)
			# OR
			# (-,abeeman,-)
			if ($ng =~ m/^\((.*)\)/) {
                #print "$1 ";
                my $triple = $1;
                my ($host, $user, $domain) = split(',', $triple);
                if ($user) { 
					print "$user\n" unless ($user eq "-");
                }
			}
		}
		if ($opt_R) {
			my @kids = $entry->get_value("memberNisNetgroup");
			foreach my $ng (@kids) {
				displayNetgroup($ng, $domain, $ldap, $option);
			}
		}
		# We're done
		return;
	} elsif ($option eq "hosts") {
		my @hosts = $entry->get_value("nisnetgrouptriple");
		foreach $ng (@hosts) {
			if ($ng =~ m/^\((.*)\)/) {
                #print "$1 ";
                my $triple = $1;
                my ($host, $user, $domain) = split(',', $triple);
                if ($host) { 
					print "$host\n" unless ($host eq "-");
                }
			}
		}
		if ($opt_R) {
			my @kids = $entry->get_value("memberNisNetgroup");
			foreach my $ng (@kids) {
				displayNetgroup($ng, $domain, $ldap, $option);
			}
		}
		# We're done
		return;
	}  elsif ($option eq "children") {
		my @kids = $entry->get_value("memberNisNetgroup");
		foreach my $ng (@kids) {
			print "$ng\n";
		}
		# We're done
		return;
	}
	
	
	else {
		# otherwise, dump neatly 
		$entry->dump();
		if ($opt_R) {
			my @kids = $entry->get_value("memberNisNetgroup");
			foreach my $ng (@kids) {
				print "======= $ng =======\n";
				displayNetgroup($ng, $domain, $ldap, $option);
			}
		}
	}
}


# takes user, netgroup, domain, ldapconnection args
sub addUserToNetgroup {
	my $username = shift;
	my $netgroup = shift;
	my $domain = shift;
	my $ldap = shift;
	my $entry = &loadNetgroup($netgroup, $domain, $ldap);
	if (! $entry) {
		print STDERR "Netgroup $netgroup not found in $domain";
		return 22;
	} else {
		#my $val = "(-," . $username . ",-)";
		my $val = "(," . $username . ",)";
		my @members = $entry->get_value("nisnetgrouptriple");
		if (grep {$_ eq $val} @members) {
			# The user is already in the netgroup! 
			print "$username is already in $netgroup\n";
			return 1;
		}
		print "add: nisnetgrouptriple : $val\n" if ($DEBUG>1);
		$entry->add("nisnetgrouptriple" => $val);
		$result = $entry->update($ldap);
		if ($result->code) {
			print STDERR "error: ", $result->error;
			return $result->code;
		}
		print "$username added to $netgroup\n";
		return 0;
	}
}

# takes user, netgroup, domain, ldapconnection args
sub deleteUserFromNetgroup {
	my $username = shift;
	my $netgroup = shift;
	my $domain = shift;
	my $ldap = shift;
	my $entry = &loadNetgroup($netgroup, $domain, $ldap);
	if (! $entry) {
		print STDERR "Netgroup $netgroup not found in $domain";
	} else {
		#my $val = "(-," . $username . ",-)";
		my $val = "(," . $username . ",)";
		my @members = $entry->get_value("nisnetgrouptriple");
		if (! grep {$_ eq $val} @members) {
			# The user is not in the netgroup! But this isn't a bad error so return 0.
			print "$username is not in $netgroup\n";
			return 0;
		}
		print "delete: nisnetgrouptriple : $val\n" if ($DEBUG>1);
		$entry->delete("nisnetgrouptriple" => $val);
		$result = $entry->update($ldap);
		if ($result->code) {
			print STDERR "error: ", $result->error;
			return $result->code;
		}
		print "$username removed from $netgroup\n";
		return 0;
	}
}

# takes host, netgroup, domain, ldapconnection args
sub addHostToNetgroup {
	my $host = shift;
	my $netgroup = shift;
	my $domain = shift;
	my $ldap = shift;
	my $entry = &loadNetgroup($netgroup, $domain, $ldap);
	if (! $entry) {
		print STDERR "Netgroup $netgroup not found in $domain";
		return;
	} else {
		my ($hostname, $domainname) = split("\\.", $host, 2);
		print "hostname : $hostname domainname : $domainname\n" if ($DEBUG);
		my $val = "(" . $hostname . ",,)";
		my @members = $entry->get_value("nisnetgrouptriple");
		if (grep {$_ eq $val} @members) {
			# The host is already in the netgroup! 
			print "$hostname is already in $netgroup\n";
			return 1;
		}
		print "add: nisnetgrouptriple : $val\n" if ($DEBUG>1);
		$entry->add("nisnetgrouptriple" => $val);
		$result = $entry->update($ldap);
		if ($result->code) {
			print STDERR "error: ", $result->error;
			return $result->code;
		}
		print "$hostname added to $netgroup\n";
		return 0;
	}
}

# takes host, netgroup, domain, ldapconnection args
sub deleteHostFromNetgroup {
	my $host = shift;
	my $netgroup = shift;
	my $domain = shift;
	my $ldap = shift;
	my $entry = &loadNetgroup($netgroup, $domain, $ldap);
	if (! $entry) {
		print STDERR "Netgroup $netgroup not found in $domain";
	} else {
		my ($hostname, $domainname) = split("\\.", $host, 2);
		print "hostname : $hostname domainname : $domainname\n" if ($DEBUG);
		my $val = "(" . $hostname . ",,)";
		my @members = $entry->get_value("nisnetgrouptriple");
		if (! grep {$_ eq $val} @members) {
			# The host is not in the netgroup! But this isn't a bad error so return 0.
			print "$hostname is not in $netgroup\n";
			return 0;
		}
		print "delete: nisnetgrouptriple : $val\n" if ($DEBUG>1);
		$entry->delete("nisnetgrouptriple" => $val);
		$result = $entry->update($ldap);
		if ($result->code) {
			print STDERR "error: ", $result->error;
			return $result->code;
		}
		print "$hostname removed from $netgroup\n";
		return 0;
	}
}

# takes child netgroup, parent netgroup, domain, ldapconnection args
sub addNetgroupToNetgroup {
	my $child = shift;
	my $netgroup = shift;
	my $domain = shift;
	my $ldap = shift;
	my $entry = &loadNetgroup($netgroup, $domain, $ldap);
	if (! $entry) {
		print STDERR "Netgroup $netgroup not found in $domain";
	} else {
		my @members = $entry->get_value("membernisnetgroup");
		if (grep {$_ eq $child} @members) {
			# The child netgroup is already in the netgroup! But this isn't a bad error so return 0.
			print "$child is already in $netgroup\n";
			return 0;
		}
		print "add: memberNisNetgroup : $child\n" if ($DEBUG>1);
		$entry->add("memberNisNetgroup" => $child);
		$result = $entry->update($ldap);
		if ($result->code) {
			print STDERR "error: ", $result->error;
			return $result->code;
		}
		print "$child added to $netgroup\n";
		return 0;
	}
}

# takes child netgroup, parent netgroup, domain, ldapconnection args
sub deleteNetgroupFromNetgroup {
	my $child = shift;
	my $netgroup = shift;
	my $domain = shift;
	my $ldap = shift;
	my $entry = &loadNetgroup($netgroup, $domain, $ldap);
	if (! $entry) {
		print STDERR "Netgroup $netgroup not found in $domain";
	} else {
		my @members = $entry->get_value("membernisnetgroup");
		if (! grep {$_ eq $child} @members) {
			# The child netgroup is not in the netgroup! But this isn't a bad error so return 0.
			print "$child is not in $netgroup\n";
			return 0;
		}
		print "delete: memberNisNetgroup : $child\n" if ($DEBUG>1);
		$entry->delete("memberNisNetgroup" => $child);
		$result = $entry->update($ldap);
		if ($result->code) {
			print STDERR "error: ", $result->error;
			return $result->code;
		}
		print "$child removed from $netgroup\n";
		return 0;
	}
}


###### More esoteric functions

# repair function: changes (,username,) to (-,username,-)
# takes netgroup, domain, ldapconnection args
sub repairNetgroup {
	my $netgroup = shift;
	my $domain = shift;
	my $ldap = shift;
	my $changes = 0;
	my $entry = &loadNetgroup($netgroup, $domain, $ldap);
	if (! $entry) {
		print STDERR "Netgroup $netgroup not found in $domain";
	} else {
		my @members = $entry->get_value("nisnetgrouptriple");
		foreach my $member (@members) {
			if ($member =~ /\((.*),-,-\)/) {
				my $hostname = $1;
				my $val = "(" . $hostname . ",,)";
				print "delete: nisnetgrouptriple : $member\n" if ($DEBUG>1);
				$entry->delete("nisnetgrouptriple" => $member);
				print "add: nisnetgrouptriple : $val\n" if ($DEBUG>1);
				$entry->add("nisnetgrouptriple" => $val);
				$changes++;
			}
		}
		return unless $changes;
		$result = $entry->update($ldap);
		if ($result->code) {
			print STDERR "error: ", $result->error;
			return $result->code;
		}
		print "$changes changes applied to $netgroup\n";
		return 0;
	}
}







# This one does recursive expansion and can be used to determine what
# groups a person or host is a member of due to inclusion in multiple groups.
# takes query, ldapconnection
# uses a global hash of previously run queries to stop runaways

#example query for a host 
# $query = 'nisNetgroupTriple=\(' . $query . ',,\)';
#print "constructed query: $query \n";

# the code was brought over from some prior work
# not sure if this is tested/used anywhere yet
my %queries;
sub expandGroup {
	my $query = shift;
	# don't re-run previous queries.
	if ($queries{$query}) {
		print "duplicate query: $query\n" if ($DEBUG);
		return;
	}
	$queries{$query} = 1;
	my $ldap = shift;     
	my $groupattrs = [ 'cn', 'nisNetgroupTriple', 'memberNisNetgroup' ];
	my $result = $ldap->search ( base    => "$base_netgroup",
		scope   => "sub",
		filter  => "$query",
		attrs   =>  $groupattrs);
		
	my $href = $result->as_struct;
	my @arrayOfDNs  = keys %$href;        # use DN hashes
	# process each DN using it as a key	
	foreach ( @arrayOfDNs ) {
        #       print $_, "\n";
		my $valref = $$href{$_};
		# get an array of the attribute names
		# passed for this one DN.
		my @arrayOfAttrs = sort keys %$valref; #use Attr hashes
		my $attrName;        
		foreach $attrName (@arrayOfAttrs) {
			# skip any binary data: yuck!
			next if ( $attrName =~ /;binary$/ );
			# get the attribute value (pointer) using the
			# attribute name as the hash
			my $attrVal =  @$valref{$attrName};
			#print "\t $attrName: @$attrVal \n";
			if ($attrName eq "cn") {
				foreach ( @$attrVal ) {
					print "$_\n";
					#               print "expandGroup for membernisnetgroup: $_ \n";
					&expandGroup("membernisnetgroup=$_");
				}
			}
		}
	}
}


# not yet implemented
# takes DL name, corp ldapconnection, netgroup, domain, ldapconnection args
#sub syncNetgroupToDL {
#	my $dlname = shift;
#	my $corpldap = shift;
#	my $netgroup = shift;
#	my $domain = shift;
#	my $ldap = shift;
#}

1;
