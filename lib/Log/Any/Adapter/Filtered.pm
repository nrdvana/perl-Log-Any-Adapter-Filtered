package Log::Any::Adapter::Filtered;
use strict;
use warnings;
use parent 'Log::Any::Adapter::Base';
use Carp ();
use Scalar::Util ();
use Data::Dumper ();

our $VERSION= '0.000001';

# ABSTRACT: Logging adapter base class with support for filtering

=head1 DESCRIPTION

The most needed feature I saw lacking from Log::Any::Adapter::Stdout was
the ability to easily filter out unwanted log levels on a per-category basis.
This logging base class addresses that missing feature, providing some
structure for other adapter classes to quickly implement filtering in an
efficient way.

This package gives you:

=over

=item *

A method to convert log level names to numeric values. (you can override this
to define your own numbering)

=item *

A parser for a convenient filter notation, composed of log levels, 'all',
'none', and numeric offsets from a named level.

=item *

A cascading set of "default filter" values where you can configure the
default filtering for each category and overall for the package.
Subclasses inherit any values set in the parent class.  These are a global
configuration, and very easy to initialize from environment variables in
a subclass.

=item *

Automatic optimization where a new subclass is created for each filter level,
so the method call to a disabled log level is an empty sub, rather than the
typical log-level comparison code.

=item *

Set of default logging methods which perform stringification of all message
arguments in a sensible way consistent with the Log::Any API.  All you need
to implement in the subclass is a single C<write_msg($level, $msg_str)> method.

=back

=head1 NUMERIC LOG LEVELS

In order to filter out "this level and below" there must be a concept of
numeric log leveels.  We get these from the method _log_level_value, and a
default implementation simply assigns increasing values to each level, with
'info' having a value of 1 (which I think is easy to remember).

=head2 _log_level_value

  my $n= $class->_log_level_value('info');
  my $n= $class->_log_level_value('min');
  my $n= $class->_log_level_value('max');

Takes one argument of a log level name or alias name or the special values
'min' or 'max', and returns a numeric value for it.  Increasing numbers
indicate higher priority.

If you override this, make sure 'min' and 'max' are consistent with the
rest of the values you return.

=cut

our %level_map;              # mapping from level name to numeric level
BEGIN {
	# Initialize globals, and use %ENV vars for defaults
	%level_map= (
		min       => -1,
		trace     => -1,
		debug     =>  0,
		info      =>  1,
		notice    =>  2,
		warning   =>  3,
		error     =>  4,
		critical  =>  5,
		alert     =>  6,
		emergency =>  7,
		max       =>  7,
	);
	# Make sure we have numeric levels for all the core logging methods
	for ( Log::Any->logging_methods() ) {
		if (!defined $level_map{$_}) {
			# This is an attempt at being future-proof to the degree that a new level
			# added to Log::Any won't kill a program using this logging adapter,
			# but will emit a warning so it can be fixed properly.
			warn __PACKAGE__." encountered unknown log level '$_'";
			$level_map{$_}= 4;
		}
	}
	# Now add numeric values for all the aliases, too
	my %aliases= Log::Any->log_level_aliases;
	$level_map{$_} ||= $level_map{$aliases{$_}}
		for keys %aliases;
}

sub _log_level_value { $level_map{$_[1]} }

=head1 FILTERS

A filter can be specified for a specific logger instance, or come from a
default.  This package provides both an accessor for the filter of an instance
and a set of functions to configure the defaults.  The defaults cascade from
parent log adapters to child log adapters, so if you set defaults on this
C<Log::Any::Adapter::Filtered> class, they will affect any logging adapter
derived from it.

=head2 filter

  use Log::Any::Adapter 'Filtered', filter => 'info';
  print $log->filter;

Filter is an attribute of the generated logger.  It returns the symbolic name
of the logging level.

=cut

sub filter { $_[0]{filter} }

=head2 _coerce_filter_level

  my $log_level= $class->_coerce_filter_level( 'info' );
  my $log_level= $class->_coerce_filter_level( 'info+2' );
  my $log_level= $class->_coerce_filter_level( 'info-1' );
  my $log_level= $class->_coerce_filter_level( 'all' );
  my $log_level= $class->_coerce_filter_level( 'none' );

Take a symbolic specification for a log level and return its log_level number.

=cut

sub _coerce_filter_level {
	my ($class, $val)= @_;
	my $n;
	return (!defined $val || $val eq 'none')? $class->_log_level_value('min') - 1
		: ($val eq 'all')? $class->_log_level_value('max')
		: defined ($n= $class->_log_level_value($val))? $n
		: ($val =~ /^([A-Za-z]+)([-+][0-9]+)$/) && defined ($n= $class->_log_level_value(lc $1))? $n + $2
		: Carp::croak "unknown log level '$val'";
}

=head2 _default_filter_stack

  my @hashes= $class->_default_filter_stack

Returns a list of hashrefs, where each is a map of category name to default
log level.  The category name '' represents the global default.  These are the
actual global hashrefs, and you should not modify them directly.  Especially
since they are lazily built and you can't know which hashref is for which
class.  They are returned in order from subclass to parent class.

=head2 default_filter_for

  my $filter_spec= $class->default_filter_for($category);
  $class->default_filter_for($category, $new_value); 

Get (or set) the effective filter spec for a given category.
If category is omitted or '' this will return (or set) the global default.
The two-argument version is really just a front-end to L<set_default_filter_for>.

Example:

  package Foo;
  use parent 'Log::Any::Adapter::Filtered';
  package Bar;
  use parent 'Log::Any::Adapter::Filtered';
  
  Foo->default_filter_for('', 'notice');
  Foo->default_filter_for('Acme::Baz', 'trace');
  Bar->default_filter_for('Acme::Baz') # returns 'trace'
  Bar->default_filter_for('Acme::Blah') # returns 'notice'

=head2 set_default_filter_for

  $class->set_default_filter($category, 'trace');

Changes the default filter for the named category.  See L<default_filter_for>.

=head2 default_filter

  $class->default_filter('notice');
  $class->default_filter # returns 'notice'

Class accessor for the global filter value.  (each Log::Any::Adapter::Filtered
subclass gets its own global, and they cascade from parent as well)

This is actually just a front-end for C<default_filter_for('', @_)>.

=cut

our %_default_filter;
BEGIN {
	%_default_filter= ( '' => 'debug' );
}

sub _default_filter_stack {
	return ( \%_default_filter );
}

sub _init_default_filter_var {
	my $class= shift;
	1 == eval '
		package '.$class.';
		our %_default_filter;
		sub _default_filter_stack { 
			return ( \%_default_filter, $_[0]->SUPER::_default_filter_stack );
		}
		1;'
		or die $@;
}

sub default_filter_for {
	my ($class, $category)= @_;
	goto $class->can('set_default_filter_for') if @_ > 2;
	my @filter_stack= $class->_default_filter_stack;
	if (defined $category && length $category) {
		defined $_->{$category} && return $_->{$category}
			for @filter_stack;
	}
	defined $_->{''} && return $_->{''}
		for @filter_stack;
}

sub set_default_filter_for {
	my ($class, $category, $value)= @_;
	$class= ref $class if Scalar::Util::blessed($class);
	$class->_coerce_filter_level($value); # just testing for validity
	$category= '' unless defined $category;
	no strict 'refs';
	$class =~ s/::Filter\d+$//; # Don't create a hash for the per-filter-level subclasses
	defined *{ $class . '::_default_filter' } or $class->_init_default_filter_var;
	${ $class . '::_default_filter' }{ $category }= $value;
	return $class->default_filter_for($category);
}

sub default_filter {
	(shift)->default_filter_for('', @_);
}

=head1 LOGGING METHODS

This package provides default logging methods which all call back to a
'write_msg' method which must be defined in the subclass.

The methods convert all arguments into a single string according to the
Log::Any spec, so that subclasses don't have to deal with that.
This involves a 'dumper' to convert objects to strings for the printf style
functions.  We define a 'dumper' attribute for log instances, and a
C<default_dumper> class method which returns a coderef to use as the default
value.

Feel free to override default_dumper in subclasses.  You should also allow it
to be overridden at runtime by code like C<*{$class.'::default_dumper'}= sub { ... }>
without breaking your class.

The only contract for the default dumper is that it should "do something
sensible to show the data to the user in logged-text form."  But, end-users
might override the dumper to give very precise output.

=head2 dumper

  use Log::Any::Adapter 'Filtered', dumper => sub { my $val=shift; ... };
  $log->dumper( sub { ... } );

Use a custom dumper function for converting perl data to strings.

Defaults to L</default_dumper>.  Setting this to C<undef> will cause it
to revert to the default.

=head2 default_dumper

Returns a sensible default for dumping perl data in human-readable form.
Override this method as needed.  Even feel free to override it from your
main script like

  *Log::Any::Adapter::Filtered::default_dumper= sub { ... };

=cut

sub dumper {
	$_[0]{dumper}= $_[1] if @_ > 1;
	$_[0]{dumper} ||= $_[0]->default_dumper
}

sub default_dumper {
	return \&_default_dumper;
}

sub _default_dumper {
	my $val= shift;
	my $s= Data::Dumper->new([$val])->Indent(0)->Terse(1)->Useqq(1)->Quotekeys(0)
		->Maxdepth(Scalar::Util::blessed($val)? 2 : 4)->Sortkeys(1)->Dump;
	substr($s, 2000-3)= '...' if length $s > 2000;
	$s;
}

=head2 write_msg

  $self->write_msg( $level_name, $message_string )

This is an internal method which all the other logging methods call.
Subclasses should modify this as needed.

=cut

sub write_msg {
	my ($self, $level_name, $str)= @_;
	print STDERR "$level_name: $str\n";
}

=head1 CONSTRUCTOR

=head2 init

This module provides an adapter init() function that assigns the default filter
and dumper, and applies the filter optimization by re-blessing this class
to one of the filtered subclasses based on the numeric value of the filter level.

If you define your own C<init> for a subclass, make sure to call
C<$self-E<gt>SUPER::init(@_)> if you want these features.

=cut

sub category { $_[0]{category} }

sub init {
	my $self= shift;
	# Apply default dumper if not set
	$self->{dumper} ||= $self->default_dumper;
	# Apply default filter if not set
	defined $self->{filter}
		or $self->{filter}= $self->default_filter_for($self->{category});
	
	# Rebless to a "level filter" package, which is a subclass of this one
	# but with some methods replaced by empty subs.
	# If log level is less than the minimum value, we show all messages, so no need to rebless.
	(ref($self).'::Filter0')->can('info') or $self->_build_filtered_subclasses;
	my $filter_value= $self->_coerce_filter_level($self->filter);
	my $min_value= $self->_log_level_value('min');
	if ($filter_value >= $min_value) {
		my $max_value= $self->_log_level_value('max');
		$filter_value= $max_value if $filter_value > $max_value;
		my $pkg_suffix= $filter_value - $min_value;
		bless $self, ref($self)."::Filter$pkg_suffix"
	}
	
	return $self;
}

=head2 _build_logging_methods

This method builds all the standard logging methods from L<Log::Any/LOG LEVELS>.
This method is called on this package at compile time, and probably doesn't
need to be called for subclasses.

For regular logging functions (i.e. C<warn>, C<info>) the arguments are
stringified and concatenated.  Errors during stringify or printing are not
caught.

For printf-like logging functions (i.e. C<warnf>, C<infof>) reference
arguments are passed to C<$self-E<gt>dumper> before passing them to
sprintf.  Errors are not caught here either.

For any log level below C<info>, errors ARE caught with an C<eval> and printed
as a warning.
This is to prevent sloppy debugging code from ever crashing a production system
if additional log levels are enabled on the fly.
Also, references are passed through C<$self-E<gt>dumper> even in the regular
C<debug> and C<trace> methods.

=cut

# Programmatically generate all the info, infof, is_info ... methods
sub _build_logging_methods {
	my $class= shift;
	$class= ref $class if Scalar::Util::blessed($class);
	my %seen;
	# We implement the stock methods, but also 'fatal' because in my mind, fatal is not
	# an alias for 'critical' and I want to see a prefix of "fatal" on messages.
	for my $method ( grep { !$seen{$_}++ } Log::Any->logging_methods(), 'fatal' ) {
		my ($impl, $printfn);
		if ($class->_log_level_value($method) >= $class->_log_level_value('info')) {
			# Standard logging.  Concatenate everything as a string.
			$impl= sub {
				(shift)->write_msg($method, join('', map { !defined $_? '<undef>' : $_ } @_));
			};
			# Formatted logging.  We dump data structures (because Log::Any says to)
			$printfn= sub {
				my $self= shift;
				$self->write_msg($method, sprintf((shift), map { !defined $_? '<undef>' : !ref $_? $_ : $self->dumper->($_) } @_));
			};
		} else {
			# Debug and trace logging.  For these, we trap exceptions and dump data structures
			$impl= sub {
				my $self= shift;
				eval { $self->write_msg($method, join('', map { !defined $_? '<undef>' : !ref $_? $_ : $self->dumper->($_) } @_)); 1 }
					or $self->warn("$@");
			};
			$printfn= sub {
				my $self= shift;
				eval { $self->write_msg($method, sprintf((shift), map { !defined $_? '<undef>' : !ref $_? $_ : $self->dumper->($_) } @_)); 1; }
					or $self->warn("$@");
			};
		}
			
		# Install methods in base package
		no strict 'refs';
		*{"${class}::$method"}= $impl;
		*{"${class}::${method}f"}= $printfn;
		*{"${class}::is_$method"}= sub { 1 };
	}
	# Now create any alias that isn't handled
	my %aliases= Log::Any->log_level_aliases;
	for my $method (grep { !$seen{$_}++ } keys %aliases) {
		no strict 'refs';
		*{"${class}::$method"}=    *{"${class}::$aliases{$method}"};
		*{"${class}::${method}f"}= *{"${class}::$aliases{$method}f"};
		*{"${class}::is_$method"}= *{"${class}::is_$aliases{$method}"};
	}
}

# Create per-filter-level packages
# This is an optimization for minimizing overhead when using disabled levels
sub _build_filtered_subclasses {
	my $class= shift;
	$class= ref $class if Scalar::Util::blessed($class);
	my $min_level= $class->_log_level_value('min');
	my $max_level= $class->_log_level_value('max');
	my $pkg_suffix_ofs= 0 - $min_level;
	
	# Create packages, inheriting from $class
	for ($min_level .. $max_level) {
		my $suffix= $_ - $min_level;
		no strict 'refs';
		push @{"${class}::Filter${suffix}::ISA"}, $class;
	}
	# For each method, mask it in any package of a higher filtering level
	for my $method (keys %level_map) {
		my $level= $class->_log_level_value($method);
		# Suppress methods in all higher filtering level packages
		for ($level .. $max_level) {
			my $suffix= $_ - $min_level;
			no strict 'refs';
			*{"${class}::Filter${suffix}::$method"}= sub {};
			*{"${class}::Filter${suffix}::${method}f"}= sub {};
			*{"${class}::Filter${suffix}::is_$method"}= sub { 0 }
		}
	}
}

BEGIN {
	__PACKAGE__->_build_logging_methods;
}

1;