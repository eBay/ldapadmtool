#!/usr/bin/perl


$usage_automount = "

Automount commands:
Create an automount map:
ldapadmtool.pl automount [-V] -C -e <env> -a <automount-map> 

Delete an entire map:
ldapadmtool.pl automount [-V] -D -e <env> -a <automount-map>

Add/remove automount map entry:
ldapadmtool.pl automount [-V][-f] -m <add> -e <env>  -a <automount-map> -k <key> [-i \"<info>\"]
ldapadmtool.pl automount [-V][-f] -m <delete> -e <env> -a <automount-map> -k <key> 


List/Display all of the automount maps:
ldapadmtool.pl automount [-V] -L -e <env> 

List/Display entries in an automount map:
ldapadmtool.pl automount [-V] -L -e <env> -a <automount-map>

List/Display a single entry from an automount map  (raw):
ldapadmtool.pl automount [-V] -L -e <env> -a <automount-map> -k <key>

List/Display a single entry from an automount neatly:
ldapadmtool.pl automount [-V] -L -e <env> -a <automount-map> -k <key> -N

";


sub ldapadmtoolAutomountMain {
	if ($argv =~ /automount help/) {
		print $usage_automount;
		exit 0;
	}
	if ($opt_C) {
		print "creating a new automount entry\n" if ($DEBUG);
		my $ret = newAutomountEntry($opt_a, $opt_e, $ldap);
		if ($ret) {
			print "Created automount map $ret->dn \n";
		}
	}
	
	# Any modifications or creations need to include all the options
	if (($opt_m) && ! ($opt_a && $opt_e && $opt_k)) {
		print $usage_automount;
		exit 0;
		
	}
	if ($opt_m eq "add") {
		print "adding an entry to an automount map\n" if ($DEBUG);
		my $ret = addEntryToAutomountMap($opt_a, $opt_k, $opt_i, $ldap);
		exit($ret) if $ret;
		
	} elsif ($opt_m eq "delete") {
		print "removing a command from an automount map\n" if ($DEBUG);
		my $ret = deleteEntryFromAutomountMap($opt_a, $opt_k, $ldap);
		exit ($ret) if $ret;
		
	}

	
	# listing options
	if ($opt_L) {
		if ($opt_a) {
			# we're looking at a particular map
			if ($opt_k) {
				# individual entry
				displayAutomountMapEntry($opt_a, $opt_k, $ldap);
			} else {
				# all entries in that map
				displayAutomountMap($opt_a, $ldap);
			}
		} else {
			# show a list of all the maps
			my @ammaps = listAutomountMaps("automountKey=*", $ldap);
			print join("\n", @ammaps), "\n";
		}
		exit 0;
	}
	
	
	# remove automount map - removes entire tree (if empty - may fail otherwise)
	if ($opt_a &&  $opt_D) {
		if (! $opt_F) {
			print "Do you really want to delete the automount map, $opt_a, from domain $opt_e? [y/n]: ";
			my $ans = <>;
			unless ($ans =~ /^y/ || $ans =~ /^Y/) {
				print "OK, action cancelled. Goodbye.\n";
				exit 4;
			}
		}
		print "Removing automount map $opt_a from $opt_e\n";
		my $ret = ldapDelete($ldap, "automountMapName=" . $opt_a . "," . $base);
		exit($ret) if $ret;
	}
	print "Couldn't match what you asked for with an action!\n$usage_automount\n";
	exit 1;	
}






# create a new automount map folder object like this:
#dn: automountMapName=auto_direct,dc=example,dc=com
#objectClass: automountMap
#objectClass: top
#automountMapName: auto_direct

# takes name, user-spec, host-spec, command, ldapconnection
# returns the created entry
# newAutomountEntry($opt_a, $opt_e, $ldap)
sub newAutomountEntry {
	my $name = shift;
	my $env = shift;
	my $ldap = shift;
	
	my $dn = "automountMapName=$name,$base";
	print "adding: $dn\n" if ($DEBUG);
	my $entry = new Net::LDAP::Entry;
	$entry->dn($dn);
	$entry->add("objectClass" => [qw( top automountMap )] );
	print "about to save automount map $name :\n", $entry->dump, "\n" if ($DEBUG);
	$result = $entry->update($ldap);
	$result->code && warn "error: ", $result->error;
	if (! $result->code) {
		print "Created automount map at $dn\n";
		return $entry;
	}
}




# autmount map entry
#dn: automountkey=/home,automountMapName=auto_direct,dc=example,dc=com
#objectClass: automount
#objectClass: top
#automountInformation: -rw,bg,largefiles home.example.com:/export/home
#automountKey: /home

# addEntryToAutomountMap($opt_a, $opt_k, $opt_i, $ldap);
# takes map, key, info, ldapconnection args
sub addEntryToAutomountMap {
	my $name = shift;
	my $mapkey = shift;
	my $info = shift;
	my $ldap = shift;
	my $dn = "automountkey=$mapkey,automountMapName=$name,$base";
	print "adding: $dn\n" if ($DEBUG);
	my $entry = new Net::LDAP::Entry;
	$entry->dn($dn);
	$entry->add("objectClass" => [qw( top automount )] );
	$entry->add("automountInformation", $info);
	print "about to save automount map entry $name :\n", $entry->dump, "\n" if ($DEBUG);
	$result = $entry->update($ldap);
	$result->code && warn "error: ", $result->error;
	if (! $result->code) {
		print "Created automount map entry at $dn\n";
		return $entry;
	}
}

# deleteEntryFromAutomountMap($opt_a, $opt_k, $ldap)
sub deleteEntryFromAutomountMap {
	my $name = shift;
	my $mapkey = shift;
	my $ldap = shift;
	
	my $ret = ldapDelete($ldap, "automountkey=$mapkey,automountMapName=$name,$base");
	exit($ret) if $ret;
}



#displayAutomountMapEntry($opt_a, $opt_k, $ldap);
# takes map, mapkey, ldapconnection
sub displayAutomountMapEntry {
	my $name = shift;
	my $mapkey = shift;
	my $ldap = shift;
	my $query = "automountKey=$mapkey";
	my $result = $ldap->search ( base    => "automountMapName=$name,$base",
		scope   => "sub",
		filter  => "$query");
	
	# assume only one record will match the query
	my $entry = $result->entry(0);
	if (!$entry) {
		warn "couldn't find automount map key: $mapkey in automountMapName=$name,$base";
		return;
	} else {
		if ($opt_N) {
			my $info = $entry->get_value("automountInformation");
			print "$mapkey\t$info\n";
			# We're done
			return;
		} else {
			# otherwise, dump neatly 
			$entry->dump();
		}
	}
}

# displayAutomountMap($mapname, $ldap)
sub displayAutomountMap {
	my $name = shift;
	my $ldap = shift;
	
	my $query = "objectclass=automount";
	print "searching for $query in automountMapName=$name,$base\n" if ($DEBUG);
	my $mapattrs = [ 'automountkey', 'automountinformation' ];
	my $result = $ldap->search ( base    => "automountMapName=$name,$base",
	scope   => "sub",
	filter  => "$query",
	attrs   =>  $mapattrs );
	my $href = $result->as_struct;
	my @arrayOfDNs  = keys %$href;        # use DN hashes
	my @maps;
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
			if ($attrName eq "automountkey") {
				foreach ( @$attrVal ) {
					print "$_\n";
					push(@maps, $_);
				}
			}
		}
		# End of that DN
	}
	return @maps;

}

# Search function for finding automount maps
# takes: query, ldapconnection 
sub listAutomountMaps {
	my $query = shift;
	my $ldap = shift;
	my $query = "objectclass=automountMap";
	print "searching for $query in $base\n" if ($DEBUG);
	my $mapattrs = [ 'automountMapName' ];
	my $result = $ldap->search ( base    => "$base",
	scope   => "sub",
	filter  => "$query",
	attrs   =>  $mapattrs );
	my $href = $result->as_struct;
	my @arrayOfDNs  = keys %$href;        # use DN hashes
	my @maps;
	# process each DN using it as a key
	foreach ( @arrayOfDNs ) {
		#print "$_\n";
		my $valref = $$href{$_};
		# get an array of the attribute names passed for this one DN.
		my @arrayOfAttrs = sort keys %$valref; #use Attr hashes
		my $attrName;        
		foreach $attrName (@arrayOfAttrs) {
			#print $attrName, "\n";
			# skip any binary data: yuck!
			next if ( $attrName =~ /;binary$/ );
			my $attrVal =  @$valref{$attrName};
			if ($attrName eq "automountmapname") {
				foreach ( @$attrVal ) {
					#print "$_\n";
					push(@maps, $_);
				}
			}
		}
		# End of that DN
	}
	return @maps;
}

1;
