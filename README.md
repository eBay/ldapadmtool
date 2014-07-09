This is the UNIX LDAP command toolchain by Adam Beeman, 2011-2014, eBay Inc.

The only script in this directory you should need to run directly is
ldapadmtool.pl. The rest are supporting files which could be installed
into your Perl @INC path somewhere.

This script requires a few perl modules which can be obtained from CPAN:

Net::LDAP
Getopt::Std

Some disabled functionality can be turned back on by installing
Net::Syslog and Term::ReadPassword and then going through the code
and uncommenting sections which used it. In general that should not
be required.

Authentication credentials are loaded from files referenced in the config
file, or they can be read in from the environment. You can override what accounts
and LDAP passwords to use by setting the following environment variables
in the shell:

ldap_binddn
ldap_bindpw
ad_binddn
ad_bindpw

To configure the tool, after installing the required perl modules,
just edit config.pm to customize it, and also edit ldapadmtool.pl
to change the first line to point to the location where you have installed
the files.

