#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Slash 2.003;
use Slash::Constants qw(:web :messages);
use Slash::Display;
use Slash::Utility;
use Slash::XML;

use vars qw($VERSION);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

sub main {
	my $slashdb   = getCurrentDB();
	my $reader    = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $user      = getCurrentUser();
	my $form      = getCurrentForm();

	my $post_ok   = $user->{state}{post};
	my $user_ok   = !$user->{is_anon};

	# possible value of "op" parameter in form
	my %ops = (
		userlogin	=> [ 1,				\&loginForm		],
		userclose	=> [ $user_ok,			\&loginForm		],
		newuserform	=> [ 1,				\&newUserForm		],
		newuser		=> [ $post_ok,			\&newUser		],
		mailpasswdform	=> [ 1,				\&mailPasswdForm	],
		mailpasswd	=> [ $post_ok,			\&mailPasswd		],
		changeprefs	=> [ $user_ok,			\&changePrefs		],
		saveprefs	=> [ $post_ok && $user_ok,	\&savePrefs		],
	);

	my $op = $form->{op};
	if (!$op || !exists $ops{$op} || !$ops{$op}[ALLOWED]) {
		$form->{op} = $op = 'userlogin';
	}

	# you are logged in, just go to your prefs (you were authenticated
	# in Slash::Apache::User, before you got here)
	if ($op eq 'userlogin' && $user_ok) {
		redirect(cleanRedirectUrl($form->{returnto}));
		return;
	}

	$ops{$op}[FUNCTION]->($slashdb, $reader, $constants, $user, $form);
	writeLog($user->{nickname});
}

#################################################################
sub newUserForm {
	my($slashdb, $reader, $constants, $user, $form, $note) = @_;

	_validFormkey('generate_formkey') or return;

	header(getData('newuserformhead')) or return;
	slashDisplay('newUserForm', { note => $note, form => $form });
	footer();
}

#################################################################
sub newUser {
	my($slashdb, $reader, $constants, $user, $form) = @_;

	#if (my $error =	_validFormkey(qw(max_post_check valid_check formkey_check), 1)) {
	#	return newUserForm(@_, $error);
	#}

	my $plugins = $slashdb->getDescriptions('plugins');

	my @note;
	my $error = 0;
	my $nc = $constants->{nick_chars} || join('', 'a' .. 'z');
	my $nr = $constants->{nick_regex} || '^[a-z]$';
	my $ns = $constants->{nick_regex_start} || '[a-zA-Z_]';

	# check if new nick is OK and if user exists
	my $newnick = nickFix($form->{newusernick});
	my $matchname = nick2matchname($newnick);

	if ($form->{newusernick} !~ /^$ns/) {
		push @note, getData('nick_starts_unavailable_chars');
		$error = 1;
	}

	if ($form->{newusernick} =~ /\s{2,}/) {
		push @note, getData('nick_has_continuous_whitespace');
		$error = 1;
	}

	if ($form->{newusernick} !~ /^[$nc]+$/) {
		push @note, getData('nick_has_unavailable_chars');
		$error = 1;
	}

	if (length($form->{newusernick}) > $constants->{nick_maxlen}) {
		push @note, getData('nick_is_too_long');
		$error = 1;
	}

	if (!$newnick) {
		push @note, getData('nick_invalid');
		$error = 1;
	} elsif ($constants->{use_privacy_agreement} && !$form->{agree_priv_cont}) {
		push @note, getData('not_agree_priv_cont');
		$error = 1;
	} elsif (!$form->{email} || !emailValid($form->{email})) {
		push @note, getData('email_invalid');
		$error = 1;
	} elsif ($form->{email} ne $form->{email2}) {
		push @note, getData('email_do_not_match');
		$error = 1;
	} elsif ($slashdb->existsEmail($form->{email})) {
		push @note, getData('email_exists');
		$error = 1;
	} elsif ($matchname ne '' && $newnick ne '') {
		if ($constants->{newuser_portscan}) {
			my $is_trusted = $slashdb->checkAL2($user->{srcids}, 'trusted');
			if (!$is_trusted) {
				my $is_proxy = $slashdb->checkForOpenProxy($user->{hostip});
				if ($is_proxy) {
					push @note, getData('new_user_open_proxy', {
						unencoded_ip	=> $ENV{REMOTE_ADDR},
						port		=> $is_proxy,
					});
					$error = 1;
				}
			}
		}
	} else {
		push @note, getData('duplicate_user', { 
			nick => $newnick,
		});
		$error = 1;
	}

	if (!$error) {
		my $uid = $slashdb->createUser(
			$matchname, $form->{email}, $newnick
		);
		if ($uid) {
			my $data = {};
			getOtherUserParams($data);

			for (qw(tzcode)) {
				$data->{$_} = $form->{$_} if defined $form->{$_};
			}
			$data->{creation_ipid} = $user->{ipid};

			$slashdb->setUser($uid, $data) if keys %$data;

			$form->{pubkey} = $plugins->{'Pubkey'}
				? strip_nohtml($form->{pubkey}, 1)
				: '';

			if (1) {
				my $messages  = getObject('Slash::Messages');
				my %params;
				$params{MSG_CODE_COMMENT_REPLY()} = MSG_MODE_EMAIL()
					if $form->{comment_reply};
				$params{MSG_CODE_NEWSLETTER()}  = MSG_MODE_EMAIL()
					if $form->{newsletter};
				$params{MSG_CODE_HEADLINES()}   = MSG_MODE_EMAIL()
					if $form->{headlines};
				$params{MSG_CODE_ZOO_CHANGE()}   = MSG_MODE_EMAIL()
					if $form->{zoo_change};
				$params{MSG_CODE_M2()}   = MSG_MODE_EMAIL()
					if $form->{m2};
				$params{MSG_CODE_COMMENT_MODERATE()}   = MSG_MODE_EMAIL()
					if $form->{comment_moderate};
				$params{MSG_CODE_JOURNAL_FRIEND()}   = MSG_MODE_EMAIL()
					if $form->{journal_friend};
				$params{MSG_CODE_JOURNAL_REPLY()}   = MSG_MODE_EMAIL()
					if $form->{journal_reply};
				$messages->setPrefs($uid, \%params);
			}

			my $user_send = $slashdb->getUser($uid);
			_sendMailPasswd(@_, $user_send);
			header(getData('newuserhead')) or return;
			print getData('newuser_msg', { uid => $uid });
			footer();
			return;
		} else {
#			$slashdb->resetFormkey($form->{formkey});	
			push @note, getData('duplicate_user', { 
				nick => $newnick,
			});
			$error = 1;
		}
	}

	if ($error) {
		my $note = join ' ', @note;
#		$slashdb->resetFormkey($form->{formkey});
		return newUserForm(@_, $note);
	}
}

#################################################################
sub loginForm {
	my($slashdb, $reader, $constants, $user, $form) = @_;

	header(getData('loginhead')) or return;
	slashDisplay('loginForm');
	footer();
}

#################################################################
sub mailPasswdForm {
	my($slashdb, $reader, $constants, $user, $form, $note) = @_;

	_validFormkey('generate_formkey') or return;

	header(getData('mailpasswdhead')) or return;
	slashDisplay('sendPasswdForm', { note => $note });
	footer();
}

#################################################################
sub mailPasswd {
	my($slashdb, $reader, $constants, $user, $form) = @_;

	if (my $error =	_validFormkey(qw(max_post_check valid_check interval_check formkey_check), 1)) {
		return mailPasswdForm(@_, $error);
	}

	my $error = 0;
	my @note;
	my $uid = $user->{uid};

	if ($form->{unickname}) {
		if ($form->{unickname} =~ /\@/) {
			$uid = $reader->getUserEmail($form->{unickname});

		} elsif ($form->{unickname} =~ /^\d+$/) {
			my $tmpuser = $reader->getUser($form->{unickname}, ['nickname', 'uid']);
			$uid = $tmpuser->{uid};

		} else {
			$uid = $reader->getUserUID($form->{unickname});
		}
	}

	if (!$uid || isAnon($uid)) {
		push @note, getData('mail_nonickname');
		$error = 1;
	}

	my $user_send = $reader->getUser($uid);

	if (!$error) {
		# A user coming from a srcid that's been marked as not
		# acceptable for posting from also does not get to
		# mail a password to anyone.

		## XXX: we added uid to srcids, so now this is broken;
		## anywhere else we need to address this?
		my %srcids;
		@srcids{keys %{$user->{srcids}}} = values %{$user->{srcids}};
		delete $srcids{uid};

		if ($reader->checkAL2(\%srcids, [qw( nopost nopostanon spammer )])) {
			push @note, getData('mail_readonly');
			$error = 1;

		} elsif ($reader->checkMaxMailPasswords($user_send)) {
			push @note, getData('mail_toooften');
			$error = 1;
		}
	}

	if ($error) {
		my $note = join ' ', @note;
#		$slashdb->resetFormkey($form->{formkey});
		return mailPasswdForm(@_, $note);
	}

	_sendMailPasswd(@_, $user_send);
	mailPasswdForm(@_, getData('mail_mailed_note', { name => $user_send->{nickname} }));
}

#################################################################
sub _sendMailPasswd {
	my($slashdb, $reader, $constants, $user, $form, $user_send) = @_;

	my $uid       = $user_send->{uid};
	my $newpasswd = $slashdb->getNewPasswd($uid);
	my $tempnick  = $user_send->{nickname};
	my $subject   = getData('mail_subject', { nickname => $user_send->{nickname} });
	my $mail_template = $form->{op} eq "newuser" ? "mail_msg_newuser" : "mail_msg";

	# Pull out some data passed in with the request.  Only the IP
	# number is actually trustworthy, the others could be forged.
	# Note that we strip the forgeable ones to make sure there
	# aren't any "<>" chars which could fool a stupid mail client
	# into parsing a plaintext email as HTML.
	my $r = Apache->request;
	my $remote_ip = $r->connection->remote_ip;

	my $xff = $r->header_in('X-Forwarded-For') || '';
	$xff =~ s/\s+/ /g;
	$xff = substr(strip_notags($xff), 0, 20);

	my $ua = $r->header_in('User-Agent') || '';
	$ua =~ s/\s+/ /g;
	$ua = substr(strip_attribute($ua), 0, 60);

	my $msg = getData($mail_template, {
		newpasswd	=> $newpasswd,
		tempnick	=> $tempnick,
		remote_ip	=> $remote_ip,
		x_forwarded_for	=> $xff,
		user_agent	=> $ua,
	});

	doEmail($uid, $subject, $msg);
	$slashdb->setUserMailPasswd($user_send);
}

#################################################################
sub changePrefs {
	my($slashdb, $reader, $constants, $user, $form, $note) = @_;

	# I am not going to add admin-modification right now,
	# because they way it is currently done sucks.  we should
	# handle that in one place only, not duplicate the same
	# damned code everywhere, and i will not be a party to
	# such madness. -- pudge

	_validFormkey('generate_formkey') or return;

	header(getData('prefshead')) or return;
	slashDisplay('changePasswd', { note => $note });
	footer();
}

#################################################################
sub savePrefs {
	my($slashdb, $reader, $constants, $user, $form) = @_;

	_validFormkey(qw(max_post_check valid_check formkey_check regen_formkey))
		or return;

	my $error = 0;
	my @note;
	my $uid = $user->{uid};

	my $changepass = 0;
	if ($form->{pass1} || $form->{pass2} || length($form->{pass1}) || length($form->{pass2})) {
		$changepass = 1;
	}

	if ($changepass) {
		if ($form->{pass1} ne $form->{pass2}) {
			push @note, getData('passnomatch');
			$error = 1;
		}

		if (!$form->{pass1} || length $form->{pass1} < 6) {
			push @note, getData('passtooshort');
			$error = 1;
		}

		if ($form->{pass1} && length $form->{pass1} > 20) {
			push @note, getData('passtoolong');
			$error = 1;
		}

		my $return_uid = $slashdb->getUserAuthenticate($uid, $form->{oldpass}, 1);
		if (!$return_uid || $return_uid != $uid) {
			push @note, getData('oldpassbad');
			$error = 1;
		}
	}

	my $note;
	if ($error) {
		push @note, getData('notchanged');
		$note = join ' ', @note;
#		$slashdb->resetFormkey($form->{formkey});
	} else {
		my $user_save = {};
		$user_save->{passwd} = $form->{pass1} if $changepass;
		$user_save->{session_login} = $form->{session_login};
		$user_save->{cookie_location} = $form->{cookie_location};

		# changed pass, so delete all logtokens
		$slashdb->deleteLogToken($user->{uid}, 1);

		if ($user->{admin_clearpass}
			&& !$user->{state}{admin_clearpass_thisclick}) {
			# User is an admin who sent their password in the clear
			# some time ago; now that it's been changed, we'll forget
			# about that incident, unless this click was sent in the
			# clear as well.
			$user_save->{admin_clearpass} = '';
		}

		$slashdb->setUser($user->{uid}, $user_save);
		$note = getData('passchanged');

		my $cookie = bakeUserCookie($uid, $slashdb->getLogToken($uid, 1));
		setCookie('user', $cookie, $user_save->{session_login});
	}
	changePrefs(@_, $note);
}

#################################################################
sub _validFormkey {
	my(@checks, $return) = @_;
	my $constants = getCurrentStatic();
	my $form = getCurrentForm();
	my $op = $form->{op};

	$return = pop @checks if $checks[-1] eq '1';

	# eventually change s/users/login/g
	my $formname = $op =~ /^mailpasswd(?:form)?$/ ? 'login/mp'
		     : $op =~ /^newuser(?:form)?$/ ? 'login/nu'
		     : 'login'; 

	my $options = {};
	if (   !$constants->{plugin}{HumanConf}
	    || !$constants->{hc}
	    || (!$constants->{hc_sw_mailpasswd} && $op eq 'mailpasswdform')
	    || (!$constants->{hc_sw_newuser}    && $op eq 'newuserform')
	) {
		$options->{no_hc} = 1;
	}

	Slash::Utility::Anchor::getSkinColors();

	my $error;
	for (@checks) {
		my $err = formkeyHandler($_, $formname, 0, \$error, $options);
		last if $err || $error;
	}

	if ($error) {
		if ($return) {
			return $error;
		} else {
			header() or return;
			print $error;
			footer();
			return;
		}
	} else {
		if (!$options->{no_hc}) {
			my $hc = getObject("Slash::HumanConf");
			$hc->reloadFormkeyHC($formname) if $hc;
		}
		if ($return) {
			return;
		} else {
			getCurrentDB()->updateFormkey(0, length($ENV{QUERY_STRING}));
			return 1;
		}
	}
}

#################################################################
### this should maybe be somewhere else ... Slash::DB?
# this is to allow alternate parameters to be specified.  pass in
# your hash reference to be passed to setUser(), and this will
# add in those extra parameters.  add the parameters to string_param,
# type = otherusersparam, code = name of the param.  they will
# be checked for the main user prefs editing screens, and on
# user creation -- pudge
sub getOtherUserParams {
	my($data) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });

	my $user    = getCurrentUser();
	my $form    = getCurrentForm();
	my $params  = $reader->getDescriptions('otherusersparam');

	for my $param (keys %$params) {
		# set user too for output in this request
		$data->{$param} = $user->{$param} = defined($form->{$param})
			? $form->{$param}
			: $params->{$param};
	}
}

createEnvironment();
main();
1;

#generate_formkey changeprefs (?) mailpasswdform
#max_post_check saveprefs mailpasswd newuser
#valid_check saveprefs mailpasswd newuser
#formkey_check saveprefs mailpasswd newuser
#interval_check mailpasswd
#regen_formkey saveprefs

#formname newuser users/nu
#formname mailpasswd users/mp
