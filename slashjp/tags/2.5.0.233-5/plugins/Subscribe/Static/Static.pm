# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.

package Slash::Subscribe::Static;

use strict;
use Slash;
use Slash::Utility;
use Slash::DB::Utility;

use base 'Exporter';
use base 'Slash::DB::Utility';
use base 'Slash::DB::MySQL';

our $VERSION = $Slash::Constants::VERSION;

sub new {
	my($class, $vuser) = @_;
	my $self = { };

	my $slashdb = getCurrentDB();
	my $plugins = $slashdb->getDescriptions('plugins');
	return unless $plugins->{Subscribe};

	bless($self, $class);

	my $constants = getCurrentStatic();
	$self->{virtual_user} = $vuser;
	$self->sqlConnect();

	return $self;
}

sub countTotalSubs {
	my($self) = @_;
	return $self->sqlCount('users_hits',
		'hits_paidfor > 0');
}

sub countCurrentSubs {
	my($self) = @_;
	return $self->sqlCount('users_hits',
		'hits_paidfor > 0 AND hits_paidfor > hits_bought');
}

sub countTotalRenewingSubs {
        my($self) = @_;
	return scalar( @{
                $self->sqlSelectColArrayref(
                        'users_hits.uid, COUNT(*) AS c',
                        'users_hits LEFT JOIN subscribe_payments ON users_hits.uid = subscribe_payments.uid',
                        'hits_paidfor > 0',
                        'GROUP BY users_hits.uid HAVING c > 1'
                )
        } );
}

sub countCurrentRenewingSubs {
        my($self) = @_;
        return scalar( @{
                $self->sqlSelectColArrayref(
                        'users_hits.uid, COUNT(*) AS c',
                        'users_hits LEFT JOIN subscribe_payments ON users_hits.uid = subscribe_payments.uid',
                        'hits_paidfor > 0 AND hits_paidfor > hits_bought',
                        'GROUP BY users_hits.uid HAVING c > 1'
                )
        } );
}

sub countTotalGiftSubs {
	my($self) = @_;
	my @gift_uids = $self->_getUidsForPaymentType("gift");
	return 0 unless @gift_uids;
	return $self->sqlSelect("count(DISTINCT uid)","subscribe_payments","payment_type='gift' and uid in(".join(',',@gift_uids).")");
}

sub countCurrentGiftSubs {
	my($self) = @_;
	my @gift_uids = $self->_getUidsForPaymentType("gift");
	return 0 unless @gift_uids;
	return $self->sqlCount('users_hits',
		'hits_paidfor > 0 AND hits_paidfor > hits_bought AND uid in('.join(',',@gift_uids).')');
}

sub countTotalRenewingGiftSubs {
        my($self) = @_;
	my @gift_uids = $self->_getUidsForPaymentType("gift");
	return 0 unless @gift_uids;
	return scalar( @{
                $self->sqlSelectColArrayref(
                        'users_hits.uid, COUNT(*) AS c',
                        'users_hits LEFT JOIN subscribe_payments ON users_hits.uid = subscribe_payments.uid AND users_hits.uid in('.join(',',@gift_uids).')',
                        'hits_paidfor > 0',
                        'GROUP BY users_hits.uid HAVING c > 1'
                )
        } );
}

sub countCurrentRenewingGiftSubs {
        my($self) = @_;
	my @gift_uids = $self->_getUidsForPaymentType("gift");
	return 0 unless @gift_uids;
        return scalar( @{
                $self->sqlSelectColArrayref(
                        'users_hits.uid, COUNT(*) AS c',
                        'users_hits LEFT JOIN subscribe_payments ON users_hits.uid = subscribe_payments.uid',
                        'hits_paidfor > 0 AND hits_paidfor > hits_bought AND users_hits.uid in('.join(',',@gift_uids).')',
                        'GROUP BY users_hits.uid HAVING c > 1'
                )
        } );
}

sub getLowRunningSubs {
	my ($self) = @_;
	my $low_val = int ((getCurrentStatic('paypal_num_pages') || 1000) / 20);
	print STDERR "low_val: $low_val\n";
	return $self->sqlSelectColArrayref(
		'users_hits.uid',
		'users_hits',
		"hits_paidfor > 0 and (hits_paidfor - hits_bought) BETWEEN 1 AND $low_val"
	);
}

sub getExpiredSubs {
	my ($self) = @_;
	return $self->sqlSelectColArrayref(
		'users_hits.uid',
		'users_hits',
		'hits_paidfor > 0 and (hits_paidfor - hits_bought) = 0'
	);
}
																		

sub _getUidsForPaymentType {
	my ($self, $type) = @_;
	my $ar = $self->sqlSelectColArrayref("DISTINCT uid", "subscribe_payments","payment_type = ".$self->sqlQuote($type));
	return @$ar;
}

########################################################
# Pass in start and end dates in TIMESTAMP format, i.e.,
# YYYYMMDDhhmmss.  The hhmmss is optional.  The end date is
# optional.  Thus pass the single argument "20010101" to get
# only subscribers who signed up on Jan. 1, 2001.  The start
# date is optional too;  no arguments means start and end
# dates are the beginning and end of yesterday (in MySQL's
# timezone, which means GMT).

sub getSubscriberList {
	my($self, $start, $end) = @_;
	my $slashdb = getCurrentDB();
	$start = $slashdb->sqlSelect(
		'DATE_FORMAT(DATE_SUB(NOW(), INTERVAL 1 DAY), "%Y%m%d")'
	) if !$start;
	$start .= '0' while length($start) < 14;
	$end = substr($start, 0, 8) . "235959" if !$end;
	$end   .= '0' while length($end)   < 14;
	# Just return all the columns that might be useful;  probably not all
	# of them will actually be used, oh well.
	return $slashdb->sqlSelectAllHashref(
		"spid",
		"spid,
		 subscribe_payments.uid as uid,
		 email, ts, payment_gross, payment_net, pages,
		 method, transaction_id, data, memo,
		 nickname, realemail, seclev, author,
		 karma, m2fair, m2unfair, upmods, downmods, created_at,
		 users_hits.hits as hits, hits_bought, hits_paidfor, payment_type, puid",
		"subscribe_payments, users, users_info, users_hits",
		"ts BETWEEN '$start' AND '$end'
		 AND subscribe_payments.uid = users.uid
		 AND subscribe_payments.uid = users_info.uid
		 AND subscribe_payments.uid = users_hits.uid"
	);
}

1;

