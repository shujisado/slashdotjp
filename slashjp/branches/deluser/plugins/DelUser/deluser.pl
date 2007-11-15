#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id: $

use strict;
#use Image::Size;
#use POSIX qw(O_RDWR O_CREAT O_EXCL tmpnam);

use utf8;

use Slash;
use Slash::Display;
use Slash::Utility;
use Data::Dumper;

sub main {
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $post_ok = $user->{state}{post};
	my $user_ok = !$user->{is_anon};
	# lc just in case
	my $op = lc($form->{op});

	my %ops = (
	    deleteform => [$user_ok, \&deleteUserForm],
	    delete => [$post_ok, \&deleteUser],
	    );

	# set default op
	my $op = $form->{op};
	if (!$op || !exists $ops{$op} || !$ops{$op}[ALLOWED]) {
	    $form->{op} = $op = 'deleteform';
	}

	# if not logged in
	if (!$user_ok) {
	    redirect("$rootdir/");
	}

	$ops{$op}[FUNCTION]->($slashdb, $reader, $constants, $user, $form);
	writeLog($user->{nickname});
}


##################################################################
sub deleteUserForm {
    my($slashdb, $reader, $constants, $user, $form) = @_;
    slashDisplay('deleteUserForm');
    footer();
}

sub deleteUser {
    my($slashdb, $reader, $constants, $user, $form) = @_;
    my $uid = $user->{uid};

#    my $rows = $slashdb->deleteUser($uid);
    slashDisplay('deleteUserFinished');
    footer();
}

createEnvironment();
main();
1;
