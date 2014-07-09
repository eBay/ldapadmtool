#!/bin/perl

#use Net::LDAP;
#use Getopt::Std;


$usage_user ="ldapadmtool.pl User administration commands

User commands:

Create a user:
ldapadmtool.pl user [-V] -C [-e <env>] -u <username> \\ 
	[-r \"<full name>\"] [-g <gidNumber>][-n <netgroup>][-p <password>]

Delete a user:
ldapadmtool.pl user [-V] -D [-e <env>] -u <username>

Password reset:
ldapadmtool.pl user [-V] [-e <env>] -u <username> -p <newpassword>

List all users:
ldapadmtool.pl user -L [-e <env>]

List a particular user in detail:
ldapadmtool.pl user -L [-e <env>] -u <user>

List all users in a netgroup:
ldapadmtool.pl user -L [-e <env>] -n <netgroup>

Options:
-V : print verbose/debugging output
-C : create user
-D : delete user
-L : list user(s)
-e <env>: choices are defined in config file 
-g <gidNumber>: set user's default group to gidNumber
-r <full name>: create account with full name - use quotes, ex, -r \"Joe Sixpack\" 
-n <netgroup>: add user as a member of named netgroup
-u <username>: username to work with
-p <password>: set a password on the account
";


# this is the main entry point for this module
sub ldapadmtoolUserMain {	
	if ($argv =~ /user help/) {
		print $usage_user;
		exit 0;
	}
	if (! $opt_e && $default_env) {
		$opt_e = $default_env;
	}
	unless ($opt_e) {
		print "You must specify an environment with the -e option or set a default environment!\n";
		exit 3;
	}
	if ($opt_L) {
		if (@extras) {
			print "Unexpected arguements found: ", join(" ", @extras), "\n";
			print $usage_user;
			exit 1;
		}
		if ($opt_u) {
			my $entry = loadUser($opt_u, $ldap);
			if (! $entry) {
				print "$opt_u not found in $base_users\n";
				exit 1;
			}
			if ($entry && $entry->dump()) { print "OK\n" if ($DEBUG); }
		} elsif ($opt_n && ! $opt_u) {
			displayNetgroup($opt_n, $opt_e, $ldap, "users");
		} else {
			my @users = findObjects($ldap, $base_users, "uid=*");
			foreach my $user (@users) {
				print $user->get_value("uid"), "\n";
			}
		}
		exit 0;
	}
	# account creations/verifies
	if ($opt_C) {
		print "New user creation requested: $opt_u\n" if ($DEBUG);
		# check if this user account already exists!
		my $exists = &findObject($ldap, $base_users, "uid=" . $opt_u);
		if ($exists) {
			# if the user already exists, we print a message, but don't
			# bail out completely, as there may be other actions required
			print "$opt_u already exists in $base_users\n";
		} else {
			my $dn = "uid=" . $opt_u . "," . $base_users;
			print "constructed DN: $dn\n" if ($DEBUG);
			
			my $entry = Net::LDAP::Entry->new( $dn , objectClass => [qw( top account shadowAccount posixAccount ) ] );
			# are we creating a role account?
			if ($opt_r) {
				print "Role account creation requested: $opt_r\n" if ($DEBUG);
				my $uidnum = nextuid($ldap, $base_users);
				$entry->add("uidNumber" => $uidnum);
				$entry->add("gecos" => $opt_r);

			} else {
				# if we're creating a new user that is associated with a CORP account, we need
				# to retrieve some information from CORP as well as verify that it's a valid
				# username
				print "Connect to AD and lookup Corp user credentials...\n" if ($DEBUG);
				$cldap = ADConnect();
				if (! $cldap) {
					print "Unable to connect to Active Directory from this host in $domain,\nIf this isn't working or configured, use the -r option to provide the user's name.\n";
					exit 42;
				}
				my $corpentry = &findObject($cldap, "OU=Accounts_User," . $ad_base, "sAMAccountName=" . $opt_u);
				# if we can't find a matching CORP account, we bail here.
				if (!$corpentry) {
					print "No valid CORP account found for $opt_u!\n";
					print "Please provide a valid CORP username, or use -r to create a role account.\n";
					exit 10;
				}
				my $gecos = $corpentry->get_value("gecos");
			
				# in theory everyone in AD has a uidNumber!
				# BUT we have found that some Linux flavors don't like the high numbers from AD.
				# So this portion of code is changed to use nextuid() for everyone.
				#my $uidnum = $corpentry->get_value("uidNumber");
				#if (! $uidnum) {
				#	print STDERR "Couldn't get a uid number from AD, using internal nextuid()";
				#	$uidnum = nextuid($ldap, $base_users);
				#}
				my $uidnum = nextuid($ldap, $base_users);
				
				$entry->add("uidNumber" => $uidnum);
				$entry->add("gecos" => $corpentry->get_value("gecos"));
			}
			
			$entry->add("gidNumber" => $opt_g ? $opt_g : $default_gid);
			$entry->add("loginShell" => "/bin/bash");
			$entry->add("homeDirectory" => "/home/" . $opt_u);
			$entry->add("cn" => $opt_u);
			
			# dump a listing of the entry we're creating before we try to save it
			if ($DEBUG) { print $entry->dump(); }
			my $result = $entry->update($ldap);
			
			if ($result->code) {
				print STDERR "error: ", $result->error;
			} else {
				print "Created user $opt_u in $base_users\n";
			}
		}
		# is this a combo action (create a user and add to a netgroup?)
		# exit with a nonzero status if there were problems.
		if ($opt_n) {
			my $ret = addUserToNetgroup($opt_u, $opt_n, $opt_e, $ldap);
			# were multiple netgroups specified?
			if (@extras) {
				print "Processing additional netgroups: ", join(" ", @extras), "\n";
				foreach my $extra (@extras) {
					chomp $extra;
					addUserToNetgroup($opt_u, $extra, $opt_e, $ldap);
				}
			}
			exit($ret);
		}
		exit 7;
	}
	
	
	# user password reset
	if ($opt_u &&  $opt_p) {
		print "User password reset requested for $opt_u in $base\n";
		my $entry = loadUser($opt_u, $ldap);
		if (! $entry) {
			print "No account for $opt_u could be found in $opt_e\n";
			exit 100;
		}
		my $ret = userUpdatePassword($ldap, "uid=" . $opt_u . "," . $base_users, $opt_p);
		if ($ret) {
			print "Password could not be updated.\n";
		} else {
			print "Password updated successfully.\n";	
		}
		exit $ret;
	}
	
	
	# remove user account
	# currently this only removes the LDAP account, it doesn't clean up netgroups, 
	# gidgroups, or do any other housekeeping.
	if ($opt_u &&  $opt_D) {
		if (! $opt_F) {
			print "Do you really want to delete the account, $opt_u, from domain $opt_e? [y/n]: ";
			my $ans = <>;
			unless ($ans =~ /^y/ || $ans =~ /^Y/) {
				print "OK, action cancelled. Goodbye.\n";
				exit 4;
			}
			&ldapDelete($ldap, "uid=" . $opt_u . "," . $base_users);
			exit 0;
		}
	}
	print "Couldn't match what you asked for with an action!\n$usage_user\n";
	exit 1;
}

# this code to do a quick search/dump of a user
	#	if ($CHANGEME) {
	#	$cldap = ADConnect();
	#	$entry = &findObject($cldap, "OU=Accounts_User," . $ad_base, "sAMAccountName=" . $opt_u);
	#	if ($entry) { 
	#		foreach my $attr (@user_attrs) {
	#			print $attr, ": ", $entry->get_value($attr), "\n";
	#		}
	#		#$ent->dump; 
	#	} else { print "$opt_u not found in $opt_e LDAP users\n"; }	
	#}






# update a user's password
# takes args: ldapconnection, dn, newpw
sub userUpdatePassword {
	my $ldap = shift;
	my $dn = shift;
	my $newpw = shift;
	my $mesg = $ldap->modify($dn,
		changes => [
		replace    => [ userPassword => "$newpw" ] ]);

	$mesg->code && print STDERR "error: ", $mesg->error;
	if ($mesg->code) {
		print "Sorry, I couldn't update $opt_u 's password in $opt_e\n";
		return 1;
	}
}

# checks if a user exists or not
# takes args: username, ldapconnection 
sub loadUser {
	my $user = shift;
	my $ldap = shift;
	print "checking LDAP for: $user \n" if ($DEBUG);
	return if ($checked_users{$user});
	#my $groupattrs = [ 'cn','objectclass', 'uid' ];
	my $query = "uid=$user";
	my $result = $ldap->search ( base    => "$base_users",
		scope   => "sub",
		filter  => "$query",
		#attrs   =>  $groupattrs
	);
	
	# assume only one record will match the query
	my $entry = $result->entry(0);
	if (!$entry) {
		return 0;
	} else {
		return $entry;
	}
}




# printPassdLine will dump out a user's core attributes in a familiar UNIX passwd file format
# Takes an LDAP entry object as arg
sub printPasswdLine {
	if ($ent = shift) { 
		my $uid = lc($ent->get_value("uid"));
		my $uidNum = $ent->get_value("uidNumber"); 
		my $gidNum = $ent->get_value("gidNumber"); 
		my $gecos = $ent->get_value("gecos"); 
		my $home = $ent->get_value("homeDirectory"); 
		my $shell = $ent->get_value("loginShell"); 
		print $uid, ":x:", $uidNum, ":", $gidNum, ":", $gecos, ":", $home, ":", $shell, "\n";
	} else {
		print "No entry found.\n";
	}
}

# get the next available UID number
# takes an LDAP connection and base as argument
sub nextuid {
	my $ldap = shift;
	my $base = shift;
	if ($DEBUG) { print "nextuid: base: $base \n"; }
	# large sites may need to choose uid numbers within a specific range
	# the commented out example tries to place all new accounts with uid numbers
	# between 3000 and 30000
	#my $ldfilter = '(&(objectClass=posixAccount)(uidNumber>=3000)(uidNumber<=30000))';
	my $ldfilter = '(objectClass=posixAccount)';
	my $ldsrch = $ldap->search(base => $base, filter => $ldfilter,
		attrs => [ 'uidNumber' ] );
	die $ldsrch->error if $ldsrch->code;
	$ect = $ldsrch->count();
	print "Got: $ect records\n" if ($DEBUG);
	# problem with this is that it uses a lexical sort, not a numeric one
	@esrt = $ldsrch->sorted('uidNumber');
	$u1 = $esrt[0]->get_value('uidNumber');
	for($i = 0 ; $i < $ect ; $i++) {
		$u2 = $esrt[$i]->get_value('uidNumber');
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
