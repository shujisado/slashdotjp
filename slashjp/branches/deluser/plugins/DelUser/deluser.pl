#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id: $

use strict;
use utf8;
use Slash;
#use Slash::Apache ();
use Slash::Constants qw(:web :messages);
use Slash::Display;
use Slash::Utility;
use Slash::XML;
use Data::Dumper;

sub main {
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $post_ok = $user->{state}{post};
	my $user_ok = !$user->{is_anon};
	my $delete_ok = $form->{delete_ok};


	my %ops = (
	    deleteform => [$user_ok, \&deleteUserForm],
	    deleteok => [$post_ok && $user_ok && $delete_ok, \&deleteUser],
	    );

	# set default op
	my $op = $form->{op};
	if (!$op || !exists $ops{$op} || !$ops{$op}[ALLOWED]) {
	    $form->{op} = $op = 'deleteform';
	}

	# if not logged in or you are admin
	if (!$user_ok || $user->{seclev} > 2) {
	    my $rootdir = getCurrentStatic('rootdir');
	    redirect("$rootdir/");
	}

	$ops{$op}[FUNCTION]->($slashdb, $reader, $constants, $user, $form);
	writeLog($user->{nickname});
}


##################################################################
sub deleteUserForm {
    my($slashdb, $reader, $constants, $user, $form, $note) = @_;
    my $error;
    my $err = formkeyHandler('generate_formkey', 'deluser', 0, \$error, {});
    header();
    slashDisplay('deleteUser');
    footer();
}

sub deleteUser {
    my($slashdb, $reader, $constants, $user, $form) = @_;
    my $uid = $user->{uid};

    my @checks = qw(valid_check formkey_check regen_formkey);
    my $error;
    for (@checks) {
   	 my $err = formkeyHandler($_, 'deluser', 0, \$error, {});
	 last if $err || $error;
    }

    if ($error || !$form->{delete_ok}) {
	my $note = '';
	deleteUserForm(@_, $note);
    } else {
#	my $rows = $slashdb->deleteUser($uid);
#	if ($rows) {
#	    $slashdb->deleteLogToken($uid);
#	    $uid = $constants->{anonymous_coward_uid};
	    #delete $cookies->{user};
#	    setCookie('user', '');

	    header();
	    slashDisplay('deleteUserFinished');
	    footer();
#	}
    }
}

createEnvironment();
main();
1;
