#! /usr/bin/perl

use strict;
use warnings;
use Test::More;

use_ok('Log::Any::Adapter::Filtered') or BAIL_OUT;

my $LF= 'Log::Any::Adapter::Filtered';

is( $LF->default_filter_for(''), 'debug', 'global default starts at debug' );
is( $LF->default_filter_for('Foo'), 'debug', 'package default matches global' );

# Now define a new subclass
eval '
	package Log::Any::Adapter::Bar;
	$INC{"Log/Any/Adapter/Bar.pm"}= 1;
	use parent "Log::Any::Adapter::Filtered";
	1;
' == 1 or die $@;
my $LB= 'Log::Any::Adapter::Bar';

is( $LB->default_filter_for(''), 'debug', 'subclass starts at same default' );

$LF->set_default_filter_for('', 'info');
is( $LB->default_filter_for(''), 'info', 'subclass sees changed default in parent' );

is( $LB->default_filter, 'info', 'alias works' );

$LF->set_default_filter_for('Foo', 'trace');
is( $LB->default_filter_for('Foo'), 'trace', 'subclass sees changed default for category Foo' );
is( $LF->default_filter_for('Foo'), 'trace', 'changed default for category Foo' );

$LB->set_default_filter_for('Foo', 'error');
is( $LB->default_filter_for('Foo'), 'error', 'subclass setting takes priority' );
is( $LF->default_filter_for(''), 'info', 'base class is still info' );
is( $LB->default_filter_for(''), 'info', 'subclass is still info' );

$LF->set_default_filter_for('', 'notice');
is( $LF->default_filter_for('Foo'), 'trace', 'category Foo unaffected' );
is( $LB->default_filter_for('Foo'), 'error', 'subclass category Foo unaffected' );

$LB->set_default_filter_for('Foo', undef);
is( $LB->default_filter_for('Foo'), 'trace', 'default for category reverts to global default' );
$LF->set_default_filter_for('Foo', undef);
is( $LB->default_filter_for('Foo'), 'notice', 'default for category reverts to global default' );

# Now, set the subclass as our logger, and verify we can change the defaults
# by calling the methods on the logger.

1 == eval "use Log::Any::Adapter 'Bar'; 1;" or die $@;
require Log::Any;
my $log= Log::Any->get_logger(category => 'Foo');

is( $log->filter, 'notice' );
$log->default_filter_for('X', 'debug');
is( $LB->default_filter_for('X'), 'debug', 'default set via instance' );

done_testing;
