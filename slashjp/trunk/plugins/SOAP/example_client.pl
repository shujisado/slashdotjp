#!/usr/bin/perl -w

# $Id$

use strict;
use Data::Dumper;
use SOAP::Lite;

my $host        = 'www.example.com';
my $uri         = "http://$host/Slash/SOAP/Test";
my $proxy       = "http://$host/soap.pl";

# add example later for showing authentication with cookies, both
# with cookie files, and with creating your own cookie

my $soap = SOAP::Lite->uri($uri)->proxy($proxy);

my $uid = 2;
my $nick = $soap->get_nickname($uid)->result;
my $nuid = $soap->get_uid($nick)->result;

print "Results for UID $uid: $nick ($nuid)\n";

__END__
