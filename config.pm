#!/usr/bin/perl
#This is the UNIX LDAP command toolchain by Adam Beeman, 2011, eBay Inc.

# Uncomment this to turn on verbose debugging
#$DEBUG = 1;

# This module contains all the app configuration related functions

use vars qw( $domain $default_env $ad_binddn $ldap_binddn $ldap_server $ad_server $ad_base $log_server $ad_bindpw_file $ldap_bindpw_file @user_attrs $default_gid %admin_netgroup %domains %bases %ldap_servers %admincredfiles %log_servers %ad_servers);

$ad_base = "DC=lurkingsystems,DC=com"; 
$domain = "lurkingsystems.com";
$ldap_binddn = "cn=admin,dc=lurkingsystems,dc=com";

# unless you specify a default environment for all operations, LDAPAdmin will refuse
# to continue with some operations without the -e flag to specify an environment to use
$default_env = "dev";

#$ad_bindpw_file = "/Users/abeeman/projects/ldapadmtool-secret/ad_auth_pass.txt";
$ldap_bindpw_file  = "/Users/abeeman/projects/ldapadmtool-secret/ldap-admin.txt";


@user_attrs = ( "uidNumber", "gidNumber", "gecos", "unixHomeDirectory", 
"loginShell", "telephoneNumber", "physicalDeliveryOfficeName" );

# default gid for new users
$default_gid = "500";


# the following hashes contain guidance for selecting items that differ from one domain to another

# what netgroup to include in /etc/passwd depending on the host's environment
%admin_netgroup = ( "dev" => "admin", "qa" => "qaadmins", "prod", "prodadmins" );

# what is the default domain name for a host in one of these environments?
%domains = ( "dev" => "lurkingsystems.com", );

# map environments to specifig LDAP OU's
%bases = ( "dev" => "dc=lurkingsystems,dc=com", );

# which LDAP server should we connect to when running this program?
%ldap_servers = ( "lurkingsystems.com" => "192.168.192.118", );

# which file should we check for the Directory Manager password?
%admincredfiles = ( "lurkingsystems.com" => "/Users/abeeman/projects/ldapadmtool-secret/ldap-admin.txt", );

# where is the nearest syslog server or splunk forwarder?
%log_servers = ( "lurkingsystems.com" => "192.168.192.118", );

# which domains are unable to connect to CORP AD?
# simple, if there's no matching entry in %adservers for current domain...
# we won't allow connecting to AD.
%ad_servers = ( "corp.lurkingsystems.com" => "ldap.corp.lurkingsystems.com", );


1;




=head1 NAME
 
 ldapadmtool::config - Basic app/site config defaults
 
 
 =head1 SYNOPSIS
 
 use ldapadmtool::Config;
 print $Config{installbin};  # or whatever
 
 
 =head1 DESCRIPTION
 
 B<FOR INTERNAL USE ONLY>
 
 A place to store site-wide settings, etc.
 
=cut





