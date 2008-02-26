#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;

use Slash;
use Slash::Display;
use Slash::Utility;

sub main {
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	# lc just in case
	my $op = lc($form->{op});

	my($tbtitle);

	my $ops = {
		default		=> {
			function	=> \&edit,
			seclev		=> 1,
		},
		save		=> {
			function	=> \&save,
			seclev		=> 1,
		},
		paypal		=> {	# deprecated, left in for historical reasons
			function	=> \&makepayment,
			seclev		=> 1,
		},
		makepayment	=> {
			function	=> \&makepayment,
			seclev		=> 1,
		},
		pause		=> {
			function	=> \&pause,
			seclev		=> 1,
		},
		grant		=> {
			function	=> \&grant,
			seclev		=> 100
		},
		confirm 	=> {
			function	=> \&confirm,
			seclev		=> 1
		},
	};

	if ($user->{is_anon} && $op !~ /^(paypal|makepayment)$/) {
		my $rootdir = getCurrentSkin('rootdir');
		redirect("$rootdir/users.pl");
		return;
	}

	$op = 'default' unless $ops->{$op};

	if ($op ne 'pause') {
		# "pause" is special, it does a 302 redirect so we need
		# to not output any HTML.  Everything else gets this,
		# header and menu.
		header("subscribe") or return;
		print createMenu('users', {
			style =>	'tabbed',
			justify =>	'right',
			color =>	'colored',
			tab_selected =>	'preferences',
		});
	}

	my $retval = $ops->{$op}{function}->($form, $slashdb, $user, $constants);

	footer();
	writeLog($user->{uid}, $op);
}

##################################################################
# Edit options
sub edit {
	my($form, $slashdb, $user, $constants) = @_;
	my $user_edit;
	if ($form->{uid}
		&& $user->{seclev} >= 100
		&& $form->{uid} =~ /^\d+$/
		&& !isAnon($form->{uid})) {
		$user_edit = $slashdb->getUser($form->{uid});
	}
	$user_edit ||= $user;

	my $subscribe = getObject('Slash::Subscribe');
	my @defpages = sort keys %{$subscribe->{defpage}};
	my $edited_buypage_defaults_yet = exists $user->{buypage_index};
	my $user_newvalues = { };
	if (!$edited_buypage_defaults_yet) {
		for my $page (@defpages) {
			$user_newvalues->{"buypage_$page"} = $subscribe->{defpage}{$page};
		}
	}
	$user_newvalues->{hits_bought_today_max} =
		defined($user->{hits_bought_today_max})
		? $user->{hits_bought_today_max}
		: "";

	titlebar("100%", "Configuring Subscription", {
		template =>		'prefs_titlebar',
		tab_selected =>		'subscription',
	});
	slashDisplay("edit", {
		user_edit => $user_edit,
		user_newvalues => $user_newvalues,
	});
	1;
}

##################################################################
# Edit options
sub save {
	my($form, $slashdb, $user, $constants) = @_;
	my $user_edit;
	if ($form->{uid}
		&& $user->{seclev} >= 100
		&& $form->{uid} =~ /^\d+$/
		&& !isAnon($form->{uid})) {
		$user_edit = $slashdb->getUser($form->{uid});
	}
	$user_edit ||= $user;

	my $has_buying_permission = 0;
	$has_buying_permission = 1
		if $form->{secretword} eq $constants->{subscribe_secretword}
			or $user->{seclev} >= 100;

	my $subscribe = getObject('Slash::Subscribe');
	my @defpages = sort keys %{$subscribe->{defpage}};
	my $edited_buypage_defaults_yet = exists $user->{buypage_index};

	my $user_update = { };
	my $user_newvalues = { };
	if ($has_buying_permission) {
		my($buymore) = $form->{buymore} =~ /(\d+)/;
		if ($buymore) {
			$user_update->{"-hits_paidfor"} =
				"hits_paidfor + $buymore";
			$user_newvalues->{hits_paidfor} =
				$user_edit->{hits_paidfor} + $buymore;
		}
	}
	if (!$edited_buypage_defaults_yet) {
		# Set default values in case some of the form fields
		# somehow aren't sent to us.
		for my $page (@defpages) {
			$user_newvalues->{"buypage_$page"} = $subscribe->{defpage}{$page};
		}
	}
	for my $key (grep /^buypage_\w+$/, keys %$form) {
		# False value (probably empty string) means set the row to 0
		# in users_param.
		$user_newvalues->{$key} =
			$user_update->{$key} = $form->{$key} ? 1 : 0;
	}
	my $hbtm = $form->{hbtm};
	$hbtm = "" if $hbtm < 0;
	$hbtm = 65535 if $hbtm > 65535;
	$user_newvalues->{hits_bought_today_max} =
		$user_update->{hits_bought_today_max} =
		$hbtm;
	$slashdb->setUser($user_edit->{uid}, $user_update);

	titlebar("100%", "Configuring Subscription", {
		template =>		'prefs_titlebar',
		tab_selected =>		'subscription',
	});
	print "<p>Subscription options saved.\n<p>";
	slashDisplay("edit", {
		user_edit => $user_edit,
		user_newvalues => $user_newvalues,
	});
	1;
}

# for gift subscriptions pass puid (the uid of the purchaser)
# in addition to uid
sub makepayment {
	my($form, $slashdb, $user, $constants) = @_;

	if (!$form->{secretword}
		|| $form->{secretword} ne $constants->{subscribe_secretword}) {
		sleep 5; # easy way to help defeat brute-force attacks
		print "<p>makepayment: Payment rejected, wrong secretword\n";
	}

	my @keys = qw( uid email payment_gross payment_net
		method transaction_id data memo puid);
	my $payment = { };
	for my $key (@keys) {
		$payment->{$key} = $form->{$key} || '';
	}
	if (!defined($payment->{payment_net})) {
		$payment->{payment_net} = $payment->{payment_gross};
	}
	$payment->{puid} ||= $payment->{uid};
	$payment->{payment_type} = ($payment->{puid} == $payment->{uid})
		? "user" : "gift";

	my $subscribe = getObject('Slash::Subscribe');
	my $num_pages = $subscribe->convertDollarsToPages($payment->{payment_gross});
	$payment->{pages} = $num_pages;

	my $rows = $subscribe->insertPayment($payment);
	if ($rows == 1) {
		$slashdb->setUser($payment->{uid}, {
			"-hits_paidfor" => "hits_paidfor + $num_pages"
		});
		print "<p>makepayment: Payment confirmed\n";
		send_gift_msg($payment->{uid}, $payment->{puid}, $payment->{pages}, $form->{from})
			if $payment->{payment_type} eq "gift";
	} else {
		use Data::Dumper;
		my $warning = "DEBUG: Payment accepted but record "
			. "not added to database! rows='$rows'\n"
			. Dumper($payment);
		print STDERR $warning;
		print "<p>makepayment: Payment transaction ID already recorded or other error, "
			. "not added to database! rows='$rows'\n";
	}
}

# Wait a moment for an instant payment notification to take place
# "behind the scenes," then redirect the user to the main subscribe.pl
# page where they will see their new subscription options.
sub pause {
	my($form, $slashdb, $user, $constants) = @_;
	my $gSkin = getCurrentSkin();
	sleep 5;
	redirect("$gSkin->{rootdir}/subscribe.pl");
}

sub grant {
	my($form, $slashdb, $user, $constants) = @_;
	titlebar("100%", "Granting pages to user");
	if (!$user->{is_admin}){
		print "<p>Insufficient permission -- you aren't an admin\n";
		return;
	}
	
	my $subscribe = getObject('Slash::Subscribe');
	my $uid = $form->{uid};
	my $pages = $form->{pages};
	my $grant_recipient = $slashdb->getUser($uid);
	my $grant_success;

	if ($pages and $grant_recipient){
		$grant_success = $subscribe->grantPagesToUID($pages,$grant_recipient->{uid});

	}
	slashDisplay("grant", {
		uid		=> $uid,
		pages		=> $pages,
		grant_recipient	=> $grant_recipient,
		grant_success 	=> $grant_success
	});
	
}

sub confirm {
	my($form, $slashdb, $user, $constants) = @_;
	titlebar("100%", "Confirm subscription and choose payment type");
	my $type = $form->{subscription_type};
	my $uid = $form->{uid};
	my $sub_user = $slashdb->getUser($uid);
	slashDisplay("confirm", {
		type     => $type,
		uid      => $uid,
		sub_user => $sub_user,
		from 	 => $form->{from}
	});
}

sub send_gift_msg {
	my ($uid, $puid, $pages, $from) = @_;
	
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $receiving_user  = $slashdb->getUser($uid);
	my $purchasing_user = $slashdb->getUser($puid);

	my $message = slashDisplay('gift_msg', {
			receiving_user  => $receiving_user,
			purchasing_user => $purchasing_user,
			pages 		=> $pages,
			from		=> $from	
		}, { Return => 1, Nocomm => 1 } );
	my $title = "Gift subscription to $constants->{sitename}\n";
	doEmail($uid, $title, $message);
}


createEnvironment();
main();
1;

