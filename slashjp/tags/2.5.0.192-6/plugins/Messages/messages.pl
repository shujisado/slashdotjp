#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

# this program does some really cool stuff.
# so i document it here.  yay for me!

use strict;
use Slash 2.003;	# require Slash 2.3.x
use Slash::Constants qw(:web :messages);
use Slash::Display;
use Slash::Utility;
use Slash::XML;
use Time::HiRes;
use vars qw($VERSION);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

sub main {
my $start_time = Time::HiRes::time;
	my $messages  = getObject('Slash::Messages');
	my $constants = getCurrentStatic();
	my $user      = getCurrentUser();
	my $form      = getCurrentForm();

	# require POST and logged-in user for these ops
	my $user_ok   = $user->{state}{post} && !$user->{is_anon};

	# possible value of "op" parameter in form
	my %ops = (
		display_prefs	=> [ !$user->{is_anon},	\&display_prefs		],
		save_prefs	=> [ $user_ok,		\&save_prefs		],
		list_messages	=> [ !$user->{is_anon},	\&list_messages		],
		list		=> [ !$user->{is_anon},	\&list_messages		],
		display_message	=> [ !$user->{is_anon},	\&display_message	],
		display		=> [ !$user->{is_anon},	\&display_message	],
		delete_message	=> [ $user_ok,		\&delete_message	],
		deletemsgs	=> [ $user_ok,		\&delete_messages	],

		list_rss	=> [ !$user->{is_anon},	\&list_messages_rss	],

# 		send_message	=> [ $user_ok,		\&send_message		],
# 		edit_message	=> [ !$user->{is_anon},	\&edit_message		],

		# ????
		default		=> [ 1,			\&list_messages		]
	);

	# prepare op to proper value if bad value given
	my $op = $form->{op};
	if (!$op || !exists $ops{$op} || !$ops{$op}[ALLOWED]) {
		$op = 'default';
	}

	# dispatch of op
#printf STDERR scalar(localtime) . " messages.pl before $$ op $op uid $user->{uid} elapsed %5.3f\n", (Time::HiRes::time - $start_time);
	$ops{$op}[FUNCTION]->($messages, $constants, $user, $form);
#printf STDERR scalar(localtime) . " messages.pl after  $$ op $op uid $user->{uid} elapsed %5.3f\n", (Time::HiRes::time - $start_time);

	# writeLog('SOME DATA');	# if appropriate
}

sub edit_message {
	my($messages, $constants, $user, $form, $error_message) = @_;

	header(getData('header')) or return;
	slashDisplay('edit', { error_message => $error_message });
	footer();
}

sub send_message {
	my($messages, $constants, $user, $form) = @_;
	my $slashdb = getCurrentDB();


	# edit_message if errors
	if ($form->{which} eq 'Preview') {
		edit_message(@_);
	}

	# check for user
	my $to_uid = $slashdb->getUserUID($form->{to_user});
	if (!$to_uid) {
		edit_message(@_, "UID for $form->{to_user} not found");
	}
	my $to_user = $slashdb->getUser($to_uid);
	if (!$to_user) {  # should never happen
		edit_message(@_, "$form->{to_user} ($to_uid) not found");
	}

	# check for user availability
	my $users = $messages->checkMessageCodes(MSG_CODE_INTERUSER, [$to_uid]);
	my $ium = $user->{messages_interuser_receive};
	if ($users->[0] != $to_uid || !$ium) {
		edit_message(@_, "$form->{to_user} ($to_uid) is not accepting interuser messages");
	}

	if ($ium != MSG_IUM_ANYONE) {
		my $zoo = getObject('Slash::Zoo');
		if ($ium == MSG_IUM_FRIENDS && !$zoo->isFriend($user->{uid}, $to_uid)) {
			edit_message(@_, "$form->{to_user} ($to_uid) only accepts messages from friends");
		} elsif ($ium == MSG_IUM_NOFOES && $zoo->isFoe($user->{uid}, $to_uid)) {
			edit_message(@_, "$form->{to_user} ($to_uid) does not accept messages from foes");
		}
	}

	$messages->create($to_uid, MSG_CODE_INTERUSER, {
		template_name	=> 'interuser',
		subject		=> {
			template_name	=> 'interuser_subj',
			subject		=> $form->{postersubj},
		},
		comment		=> {
			subject		=> $form->{postersubj},
			comment		=> $form->{postercomment},
		},
	}, $user->{uid});


	header() or return;
	footer();	

	# print success screen
}



sub display_prefs {
	my($messages, $constants, $user, $form, $note) = @_;
	my $slashdb = getCurrentDB();

	my $deliverymodes   = $messages->getDescriptions('deliverymodes');
	my $messagecodes    = $messages->getDescriptions('messagecodes');
	my $bvdeliverymodes = $messages->getDescriptions('bvdeliverymodes');
	my $bvmessagecodes  = $messages->getDescriptions('bvmessagecodes');
	
	foreach my $bvmessagecode (keys %$bvmessagecodes) {
		$bvmessagecodes->{$bvmessagecode}->{'valid_bvdeliverymodes'} = [];
		foreach my $bvdeliverymode (keys %$bvdeliverymodes) {
			# skip if we have no valid delivery modes (i.e. off)
			if (!$bvmessagecodes->{$bvmessagecode}->{'delivery_bvalue'}) {
				delete $bvmessagecodes->{$bvmessagecode};
				last;
			}
			# build our list of valid delivery modes
			if (($bvdeliverymodes->{$bvdeliverymode}->{'bitvalue'} & $bvmessagecodes->{$bvmessagecode}->{'delivery_bvalue'}) ||
			    ($bvdeliverymodes->{$bvdeliverymode}->{'bitvalue'} == 0)) {
				push(@{$bvmessagecodes->{$bvmessagecode}->{'valid_bvdeliverymodes'}}, $bvdeliverymodes->{$bvdeliverymode}->{'code'});
			}
		}
	}

	my $uid = $user->{uid};
	if ($user->{seclev} >= 1000 && $form->{uid}) {
		$uid = $form->{uid};
	}

	my $prefs = $messages->getPrefs($uid);
	my $userm = $slashdb->getUser($uid); # so we can modify a different user other than ourself

	header(getData('header')) or return;
	print createMenu('users', {
		style		=> 'tabbed',
		justify 	=> 'right',
		color		=> 'colored',
		tab_selected	=> 'preferences',
	});
	slashDisplay('journuserboxes');
	my $prefs_titlebar = slashDisplay('prefs_titlebar', {
		nickname	=> $user->{nickname},
		uid		=> $user->{uid},
		tab_selected	=> 'messages',
		title => getData( 'prefshead' )
	}, { Return => 1 });
	my $messages_menu =  createMenu('messages');
	slashDisplay('display_prefs', {
		userm		=> $userm,
		prefs		=> $prefs,
		note		=> $note,
		messagecodes	=> $messagecodes,
		deliverymodes	=> $deliverymodes,
		prefs_titlebar	=> $prefs_titlebar,
		messages_menu	=> $messages_menu,
		bvmessagecodes  => $bvmessagecodes,
		bvdeliverymodes => $bvdeliverymodes
	});
	footer();
}

sub save_prefs {
	my($messages, $constants, $user, $form) = @_;
	my $slashdb = getCurrentDB();

	my(%params, %prefs);
	my $uid = $user->{uid};
	if ($user->{seclev} >= 1000 && $form->{uid}) {
		$uid = $form->{uid};
	}

	my $messagecodes = $messages->getDescriptions('messagecodes');
	for my $code (keys %$messagecodes) {
		my $coderef = $messages->getMessageCode($code);
		if (!exists($form->{"deliverymodes_$code"})
			||
		    !$messages->checkMessageUser($code, $slashdb->getUser($uid))
		) {
			$params{$code} = MSG_MODE_NONE;
		} else {
			$params{$code} = fixint($form->{"deliverymodes_$code"});
		}
	}
	$messages->setPrefs($uid, \%params);

	for (qw(message_threshold messages_interuser_receive)) {
		$prefs{$_} = $form->{$_};
	}
	$slashdb->setUser($uid, \%prefs);

	display_prefs(@_, getData('prefs saved'));
}

sub list_messages {
	my($messages, $constants, $user, $form, $note) = @_;

	my $messagecodes = $messages->getDescriptions('messagecodes');
	my $message_list = $messages->getWebByUID();

	header(getData('header')) or return;
# Spank me, this won't be here for long (aka Pater's cleanup will remove it) -Brian
	print createMenu('users', {
		style		=> 'tabbed',
		justify		=> 'right',
		color		=> 'colored',
		tab_selected	=> 'me',
	});
	slashDisplay('journuserboxes');
	my $user_titlebar = slashDisplay('user_titlebar', {
		nickname	=> $user->{nickname},
		uid		=> $user->{uid},
		tab_selected	=> 'messages'
	}, { Return => 1} );
	my $messages_menu = createMenu('messages'); # [ Message Preferences | Inbox ]
	slashDisplay('list_messages', {
		note		=> $note,
		messagecodes	=> $messagecodes,
		message_list	=> $message_list,
		messages_menu 	=> $messages_menu,
		user_titlebar	=> $user_titlebar,
	});
	footer();
}

sub list_messages_rss {
	my($messages, $constants, $user, $form) = @_;

	my @items;
	my $message_list = $messages->getWebByUID();
	for my $message (@$message_list) {
		my $title = "Message #$message->{id}";
		$title .= ": $message->{subject}" if $message->{subject};

		push @items, {
			story	=> {
				'time'	=> $message->{date}
			},
			title		=> $title,
			description	=> $message->{message} || '',
			'link'		=> root2abs() . "/messages.pl?op=display&id=$message->{id}",
		};
	}

	xmlDisplay($form->{content_type} => {
		channel => {
			title		=> "$constants->{sitename} Messages",
			description	=> "$constants->{sitename} Messages",
			'link'		=> root2abs() . '/my/inbox/',
		},
		image	=> 1,
		items	=> \@items,
		rdfitemdesc		=> 1,
		rdfitemdesc_html	=> 1,
	});
}

sub display_message {
	my($messages, $constants, $user, $form) = @_;

	my $message = $messages->getWeb($form->{id});

	if ($message) {
		if ($message->{message} =~ /^<URL:(\S+)>$/) {
			redirect($1);
		} else {
			header(getData('header')) or return;
			slashDisplay('display', {
				message		=> $message,
			});
			footer();
		}
	} else {
		header(getData('header')) or return;
		print getData('message not found', {
			id		=> $form->{id},
		});
		footer();
	}
}

sub delete_message {
	my($messages, $constants, $user, $form) = @_;
	my $note;

	if ($messages->_delete_web($form->{id})) {
		$note = getData('delete good', { id => $form->{id} });
	} else {
		$note = getData('delete bad',  { id => $form->{id} });
	}

	list_messages(@_, $note);
}

sub delete_messages {
	my($messages, $constants, $user, $form) = @_;
	my($note, @success, @fail);

	for my $id (grep { $_ = /^del_(\d+)$/ ? $1 : 0 } keys %$form) {
		if ($messages->_delete_web($id)) {
			push @success, $id;
		} else {
			push @fail, $id;
		}
	}

	$note = getData('deletes', { success => \@success, fail => \@fail });

	list_messages(@_, $note);
}

# etc.

createEnvironment();
main();

1;
