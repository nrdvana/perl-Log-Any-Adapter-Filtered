#! /usr/bin/perl

use strict;
use warnings;
use Test::More;

use_ok('Log::Any::Adapter::Filtered') or BAIL_OUT;

my $LF= 'Log::Any::Adapter::Filtered';

subtest 'level to number' => sub {
	for (
		[ 'trace', 'debug' ],
		[ 'debug', 'info' ],
		[ 'info',  'notice' ],
		[ 'notice',  'warn' ],
		[ 'warn',  'error' ],
		[ 'error', 'fatal' ]
	) {
		my ($lev1, $lev2)= @$_;
		cmp_ok( $LF->_log_level_value($lev1), '<=', $LF->_log_level_value($lev2), "$lev1 <= $lev2" );
	}
};

subtest 'coerce filter to number' => sub {
	for (
		[ 'trace-1', 'trace' ],
		[ 'trace', 'trace+1' ],
		[ 'none', 'trace' ],
		[ 'error', 'all' ],
	) {
		my ($f1, $f2)= @$_;
		cmp_ok( $LF->_coerce_filter_level($f1), '<=', $LF->_coerce_filter_level($f2), "$f1 <= $f2" );
	}
};

done_testing;
