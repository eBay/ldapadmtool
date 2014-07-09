#!/usr/bin/perl


$usage_search = "
What netgroups is a user or host a member of?
ldapadmtool.pl search [-V][-R] -e <env> -N -u <username>
ldapadmtool.pl search [-V][-R] -e <env> -N -h <hostname>

What netgroups is a netgroup a child of?
ldapadmtool.pl search [-V] -e <env> -N -c <netgroup>

What gidgroups is a user a member of?
ldapadmtool.pl search [-V] -e <env> -G -u <username>

Options:
-N : find what netgroups a user or host is a member of
-G : find what gidgroups a user is a member of
-R : recursive list - descend into child netgroups and get their values, too.
-V : verbose - print extra debugging info.

";

# Not yet implemented!
#Lookup informatiom from CORP Active Directory
#ldapadmtool.pl search [-v] -E -u <username> [-f '<attribute-list>']
#ldapadmtool.pl search [-v] -E -u <username> -W
#-E : look up information from the CORP domain controllers, not LDAP
#-f : print only values for the listed attributes (use , to separate multiples)
#-W : print user's Whole/Full name (can only used with -E)



sub ldapadmtoolSearchMain {
	if ($argv =~ /search help/) {
		print $usage_search;
		exit 0;
	}
	
	unless ($opt_e || $opt_E) {
		print "You must specify arch, qa, or corp with the -e option!\n";
		exit 3;
	}
	
	
	
	# informational/search commands
	#ldapadmtool.pl search [-d] -e <env> -L -u <username> 
	#ldapadmtool.pl search [-d] -e <env> -L -g <gidgroup>
	#ldapadmtool.pl search [-d] -e <env> -L -n <netgroup>
	if ($opt_L) {
		if ($opt_u) {
			$entry = &findObject($ldap, $base_users, "uid=" . $opt_u);
			if ($entry) { $ent->dump; } else { print "$opt_u not found in $opt_e LDAP users\n"; }
		} elsif ($opt_n) {
			$entry = &findObject($ldap, $base_netgroup, "cn=" . $opt_n);
			if ($entry) { $ent->dump; } else { print "$opt_n not found in $opt_e LDAP netgroups\n"; }
		} elsif ($opt_g) {
			$entry = &findObject($ldap, $base_group, "cn=" . $opt_g);
			if ($entry) { $ent->dump; } else { print "$opt_g not found in $opt_e LDAP groups\n"; }
		} else {
			print $usage_search;
			exit 1;
		}
		exit 0;
	}
	
	# Find what netgroups a user or host is a member of
	#ldapadmtool.pl [-d] -e <env> -N -u <username>
	#ldapadmtool.pl [-d] -e <env> -N -h <hostname>
	if ($opt_N) {
		if ($opt_u) {
			my $query = 'nisNetgroupTriple=\(,' . $opt_u . ',\)';
			my @netgroups = listNetgroups($ldap, $query);
			print join("\n", @netgroups), "\n";
			
			
		} elsif ($opt_h) {
			my $query = 'nisNetgroupTriple=\(' . $opt_h . ',,\)';
			my @netgroups = listNetgroups($ldap, $query);
			print join("\n", @netgroups), "\n";

		} elsif ($opt_c) {
			my $query = 'memberNisNetgroup=' . $opt_c;
			my @netgroups = listNetgroups($ldap, $query);
			print join("\n", @netgroups), "\n";
			
		} else {
			print $usage_search;
			exit 1;
		}
	}
	
	
	# find what gidgroups a user is a member of
	#ldapadmtool.pl [-d] -e <env> -G -u <username>
	if ($opt_G) {
		if ($opt_u) {
			my $query = 'memberUid=' . $opt_u;
			my @groups = listGidgroups($ldap, $query);
			print join("\n", @groups), "\n";
		}
	}

}



1;
