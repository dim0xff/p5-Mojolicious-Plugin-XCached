package MojoX::Cached;

# ABSTRACT: Simple cache which supports data caching, sub/method call results caching

use Mojo::Base -base;

use Digest::MD5 qw(md5_hex);
use Encode qw(encode_utf8);
use Scalar::Util qw(blessed);

use MojoX::Cached::Driver::Mojo;

use constant DEBUG => $ENV{MOJOX_CACHED_DEBUG};

#<<< no tidy
has 'default_expire';
has 'driver'       => sub { MojoX::Cached::Driver::Mojo->new };
has 'flatten_args' => sub { sub { shift->default_flatten_args(@_) } };
has 'name'         => 'XCached';
has 'use_fn_key'   => 1;
#>>>


sub get {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';

    my ( $self, $key, $driver_opts ) = @_;

    warn "-- @{[$self->name]} ->get '$key'\n\n" if DEBUG;

    # Callback
    if ($cb) {
        return $self->driver->get(
            $key,
            $driver_opts,
            sub {
                my @data = @_;

                return $cb->(
                    $self,
                    ( @data > 1 ? ( $data[1]{value}, 1 ) : ( undef, !!0 ) ),
                    @data,
                );
            }
        );
    }

    # Default behaviour
    my $cached_data = $self->driver->get( $key, $driver_opts ) or return;
    return $cached_data->{value};
}

sub set {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';

    my ( $self, $key, $data, $driver_opts ) = @_;

    warn "-- @{[$self->name]} ->set '$key'\n\n" if DEBUG;

    my %merged_opts = (
        expire_in => $self->default_expire,

        %{ $driver_opts // {} }
    );

    # Callback
    if ($cb) {
        return $self->driver->set(
            $key => $data,
            \%merged_opts,
            sub {
                my @data = @_;

                return $cb->(
                    $self,
                    ( @data > 1 ? ( $data[1]{value}, 1 ) : ( undef, !!0 ) ),
                    @data,
                );
            }
        );
    }

    # Default behaviour
    my $cached_data = $self->driver->set( $key, $data, \%merged_opts )
        or return;
    return $cached_data->{value};
}

sub expire {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';

    my ( $self, $key, $driver_opts ) = @_;

    warn "-- @{[$self->name]} ->expire '$key'\n\n" if DEBUG;

    return $self->driver->expire(
        $key,
        $driver_opts,
        (
            $cb
            ? sub {
                my @data = @_;

                return $cb->( $self, ( undef, $data[1] ? 1 : !!0 ), @data );
                }
            : ()
        )
    );
}

sub cached {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';

    my ( $self, $key ) = ( shift, shift );

    # Get/Set/Expire:
    # $_[0] contains data to be cached
    if ( @_ && defined $_[0] ) {

        # Cached sub
        if ( ref $_[0] eq 'CODE' ) {
            warn "-- @{[$self->name]} ->cached_sub via cached...\n"
                if DEBUG;

            return $self->cached_sub( $key, @_, ( $cb // () ) );
        }

        # Cached method
        elsif (@_ > 1
            && blessed( $_[0] )
            && defined $_[1]
            && !ref( $_[1] )
            && $_[0]->can( $_[1] ) )
        {
            warn "-- @{[$self->name]} ->cached_method via cached...\n"
                if DEBUG;

            return $self->cached_method( $key, @_, ( $cb // () ) );
        }

        # Regular data
        else {
            my ( $data, $opts ) = @_;

            $opts //= {};

            if ( ( $opts->{expire_in} // 1 ) <= 0 ) {
                warn "-- @{[$self->name]} ->expire regular data via cached...\n"
                    if DEBUG;

                return $self->expire( $key, $opts, ( $cb // () ) );
            }

            my $next = sub {
                my ( $self, $value, $success, @rest ) = @_;

                # Data found in cache
                if ($success) {
                    warn
                        "-- @{[$self->name]} ... ->get regular data FOUND via cached...\n\n"
                        if DEBUG;

                    return $cb
                        ? $cb->( $self, $value, $success, @rest )
                        : $value;
                }

                warn
                    "-- @{[$self->name]} ... ->get regular data NOT found via cached...\n"
                    if DEBUG;
                warn
                    "-- @{[$self->name]} ... ->set regular data found via cached...\n"
                    if DEBUG;

                # Cache data
                return $self->set( $key, $data, $opts, ( $cb // () ) );
            };

            if ($cb) {
                warn
                    "-- @{[$self->name]} ->get regular data with cb via cached...\n"
                    if DEBUG;

                return $self->get( $key, $next );
            }
            else {
                warn "-- @{[$self->name]} ->get regular data via cached...\n"
                    if DEBUG;

                return $self->get( $key, $next );
                return $next->( $self, $self->get( $key, $opts ) );
            }
        }
    }

    # Get/Expire
    else {
        shift if @_; # get/expire: remove undefined data from @_

        # Now $_[0] could contains %driver_options
        # If driver options contains 'expire_in' <= 0, then expire data
        if (   @_
            && ref $_[0] eq 'HASH'
            && ( $_[0]->{expire_in} // 1 ) <= 0 )
        {
            warn "-- @{[$self->name]} ->expire via cached...\n"
                if DEBUG;

            return $self->expire( $key, @_, ( $cb // () ) );
        }
        else {
            warn "-- @{[$self->name]} ->get via cached...\n"
                if DEBUG;

            return $self->get( $key, @_, ( $cb // () ) );
        }
    }
}

sub cached_sub {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';

    my ( $self, $key ) = ( shift, shift );

    warn "-- @{[$self->name]} ->cached_sub '$key'\n\n" if DEBUG;

    my ( $sub, $arguments, %rest ) = @_;
    $arguments = [] unless ref $arguments eq 'ARRAY';

    # Respect context
    my $is_list_context = $cb ? 1 : !!wantarray;

    $key = $self->get_cache_key( $key, !!wantarray, $sub, $arguments, %rest,
        ( $cb // () ) );

    my $driver_opts = $rest{driver} || {};

    # Expiration
    return $self->expire( $key, $driver_opts, ( $cb // () ) )
        if ( $driver_opts->{expire_in} // 1 ) <= 0;


    my $next = sub {
        my ( $self, $value, $success, @rest ) = @_;
        # @rest contains "raw" data returned from driver

        # Found, return cached data
        if ($success) {
            warn "-- @{[$self->name]} ->cached_sub data found for '$key'\n\n"
                if DEBUG;

            return
                  $cb                                       ? $cb->(@_)
                : $is_list_context && ref $value eq 'ARRAY' ? @{$value}
                :                                             $value;
        }

        warn "-- @{[$self->name]} ->cached_sub data NOT found for '$key'\n\n"
                if DEBUG;

        # Not found. Cache it!
        if ($is_list_context) {
            my @data = $sub->( @{$arguments} );

            if ( @data > 1 || defined $data[0] ) {
                return $self->set(
                    $key => \@data,
                    $driver_opts,
                    ( $cb // sub { return @data } )
                );
            }

            return $cb->($self, undef, !!0) if $cb;
            return;
        }
        else {
            my $data = $sub->( @{$arguments} );
            if ( defined $data ) {
                return $self->set(
                    $key => $data,
                    $driver_opts,
                    ( $cb // sub { return $data } )
                );
            }

            return scalar $cb->($self, undef, !!0) if $cb;
            return;
        }
    };

    if ($cb) {
        return $self->get( $key, $driver_opts, $next );
    }
    else {
        # Get data for key and provided driver options
        # @data has no values when no cached data found
        my @data = $self->get( $key, $driver_opts );

        return $next->( $self, ( @data ? ( $data[0], 1 ) : ( undef, 0 ) ) );
    }
}

sub cached_method {
    my ( $self, $key ) = ( shift, shift );

    warn "-- @{[$self->name]} ->cached_method '$key'\n\n" if DEBUG;

    $key = $self->get_cache_key( $key, !!wantarray, @_ );

    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';
    my ( $obj, $method, $arguments, @opts ) = @_;

    return $self->cached_sub(
        $key => sub { $obj->$method(@_) } => $arguments,
        ( @opts, fn_key => 0 ),
        ( $cb // () )
    );
}

sub get_cache_key {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';

    my ( $self, $key, $wantarray ) = ( shift, shift, shift );

    # Determine caller type
    my ( $sub, $obj, $method );
    if ( @_ && ref $_[0] eq 'CODE' ) {
        $sub = shift;
    }
    elsif ( @_ > 1 && blessed( $_[0] ) && $_[0]->can( $_[1] ) ) {
        $obj    = shift;
        $method = shift;
    }
    else {
        return $key;
    }

    my ( $arguments, %opts ) = @_;

    # fn_key using is disabled, return original $key
    return $key unless $opts{fn_key} // $self->use_fn_key;

    warn "-- @{[$self->name]} ->get_cache_key for '$key'...\n\n" if DEBUG;

    # Modify $key for method call
    if ( $obj && $method ) {
        $key = "$key->$method";
        warn
            "-- @{[$self->name]} ->get_cache_key upgrade key to method cache key: '$key'\n\n"
            if DEBUG;
    }

    # Respect call context
    $key = ( $cb || $wantarray ? 'LIST' : 'SCALAR' ) . ":$key";
    warn
        "-- @{[$self->name]} ->get_cache_key repsect context cache key '$key'\n\n"
        if DEBUG;

    return $self->fn_key(
        $key => $arguments,
        {
            flatten_args   => $opts{fn_key_flatten_args},
            no_encode_utf8 => $opts{fn_key_no_encode_utf8},
        }
    );
}

sub fn_key {
    my ( $self, $key, $arguments, $opts ) = @_;

    $opts //= {};

    local $self->{flatten_args} = $opts->{flatten_args}
        if ref $opts->{flatten_args} eq 'CODE';

    $key = $key . '(' . $self->_flatten_args($arguments) . ')';
    $key = encode_utf8($key) unless $opts->{no_encode_utf8};

    warn "-- @{[$self->name]} ->fn_key '@{[md5_hex($key)]}' / '$key'\n\n"
        if DEBUG;

    return md5_hex($key);
}

sub default_flatten_args {
    my ( $self, $arguments, $pre, $key ) = @_;

    $pre //= '';

    return $pre unless defined $arguments;

    my $local_pre = '';
    if ( ref $arguments eq 'HASH' ) {
        for my $key ( sort keys %{$arguments} ) {
            $local_pre
                = $self->_flatten_args( $arguments->{$key}, $local_pre, $key );
        }
        $local_pre = "{$local_pre}";
    }
    elsif ( ref $arguments eq 'ARRAY' ) {
        for my $element ( @{$arguments} ) {
            $local_pre = $self->_flatten_args( $element, $local_pre );
        }
        $local_pre = "[$local_pre]";
    }
    elsif ( blessed $arguments && $arguments->can('to_string') ) {
        $local_pre = $arguments->to_string;
    }
    else {
        $local_pre = "$arguments";
    }

    $key //= '';
    $key = "$key=>" if $key;

    return ( length($pre) ? "$pre," : "" ) . "$key$local_pre";
}

sub _flatten_args {
    my $self = shift;

    return $self->flatten_args->( $self, @_ );
}


1;

__END__

=head1 SYNOPSIS

    use MojoX::Cached;
    use MojoX::Cached::Driver::SomeDriver;

    # Initialize
    my $driver = MojoX::Cached::Driver::SomeDriver->new( ... driver options ... );
    my $cacher = MojoX::Cached->new( driver => $driver );

    # Simple using
    #
    # Set
    $cacher->set( user => { name => 'Dmitry', email => 'dim0xff@gmail.com', ... } );

    # Get
    my $user = $cacher->get('user');


    # Cache method results for 1 hour (3600 seconds)
    #
    # Perform (in scalar context):
    #   $template->render( ... some template data ... )
    #   and cache result
    my $rendered = $cacher->cached(
        'heavy_template' => $temlate => 'render' =>
        [ ... some template data ... ],
        driver => { expire_in => 3600 }
    );

    # The same, but in list context
    # Results will be stored separately (means, that method will be called again
    # in list context)
    ($rendered) = $cacher->cached(
        'heavy_template' => $temlate => 'render' =>
        [ ... some template data ... ],
        driver => { expire_in => 3600 }
    );

    # Later when on call method with same arguments, result will be fetched from
    # cache (if not expired) respecting call context

=head1 DESCRIPTION

Simple cache, which supports data caching, sub/method call results caching.
You have treat this like L<Memoize> with expiration and different backends.

It supports non-blocking interface, but non-blocking feature depends on driver
implementation. Optional callback C<\&cb> could be passed as last argument for
most of methods.

If callback is provided, then methods return data from callback call.
Callback will be called as:

    # On success
    $cb->( $xcache, $result_value, 1, @driver_return )

    # On fail
    $cb->( $xcache, undef, !!0, @driver_return )

Available backends:

=over

=item L<MojoX::Cached::Driver::Disk>

Slow cache driver with filesystem storage.

=item L<MojoX::Cached::Driver::Mojo>

Cache driver built on top of L<Mojo::Cache>

=back

Debug warning messages could be turn on via C<MOJOX_CACHED_DEBUG=1>
environment variable.


=attr default_expire

Default expiration time in seconds.

Default is C<undef> (cache forever).


=attr driver

Cache L<driver|MojoX::Cached::Driver>.
Default is L<MojoX::Cached::Driver::Mojo>.


=attr flatten_args

Subroutine to make string from sub/method arguments.
Default is L</default_flatten_args>.


=attr name

Debug name for cache. Default is C<XCached>.


=attr use_fn_key

Boolean value, which indicates if L</fn_key> should be used
to generate cache key for subroutine/method call.
Default is C<1> (true).


=method get ($key, \%driver_options?, \&cb?)

Get cached data by C<$key>

If C<\%driver_options> is provided it will be passed to driver method call.


=method set ($key, $data, \%driver_options?, \&cb?)

Cache C<$data> by C<$key>.

If C<\%driver_options> is provided it will be merged with default values and passed
to driver call.

Default C<\%driver_options> values are

    expire_in - default to L</default_expire>

=method expire ($key, \%driver_options, \&cb?)

Expire cached data by C<$key>.

If C<\%driver_options> is provided it will be passed to driver method call.


=method cached_sub ($key, \&subroutine, \@arguments, %options?, \&cb?)

Cache data (by C<$key> or L<functional key|/fn_key>) returned from
C<&subroutine(@arguments)> call with respecting call context (LIST or SCALAR).

I<Note about context>: when C<\&cb> is passed context will be forced to B<LIST>.

Available C<options>:

=over

=item driver

Type: hashref

Optional driver options. If it has key C<expire_in> with zero or negative value
it means L<expiration|/expire> instead of caching.

=back


Cache key will be generated via L</get_cache_key>,
(where C<%options> will be passed as is, look L</get_cache_key> for other
useful options).

    my $sub = sub {...};

    # SCALAR context
    # Perform equals to:
    #   my $value = $sub->( ... arguments ... );
    my $value = $cached->cached_sub( key => $sub, [ ... arguments ... ] );

    # LIST context
    # Perform equals to:
    #   my @values = $sub->( ... arguments ... );
    my @values = $cached->cached_sub( key => $sub, [ ... arguments ... ] );

    # With callback
    # Will be expired in 3600 seconds
    $cached->cached_method(
        key => $sub => [ ... arguments ... ],
        ( driver => { expire_in => 3600 } ),
        sub {
            my ( $cached, $result, $ok ) = @_;
            # $result = [ $sub->( ... arguments ... ) ];
        }
    );

    # With callback and with provided hash key 'some_key'
    # Will be expired in 3000 seconds from now (or in 3600 seconds from time-600)
    $cached->cached_method(
        some_key => $sub => [ ... arguments ... ],
        (
            driver => { expire_in => 3600, t => time - 600, },
            fn_key => 0,
        ),
        sub {
            my ( $cached, $result, $ok ) = @_;
            # $result = [ $sub->( ... arguments ... ) ];
        }
    );


=method cached_method ($key, $object, $method, \@arguments, %options?, \&cb?)

Cache data (by C<$key>) returned from C<$object-E<gt>$method(@arguments)> call
with respecting call context (LIST OR SCALAR).

It is wrapper over L</cached_sub>, so for C<%options> refer to L</cached_sub>.

    # Scalar context
    # Perform equals to:
    #   my $value = $object->some_method( ... arguments ... );
    my $value = $cached->cached_method(
            key => $object => some_method => [ ... arguments ...]
        );

    # List context
    # Perform equals to:
    #   my @values = $object->some_method( ... arguments ... );
    my @values = $cached->cached_method(
            key => $object => some_method => [ ... arguments ...]
        );

    # With callback
    $cached->cached_method(
        key => $object => $some_method => [ ... arguments ... ],
        driver => { expire_in => 3600 },
        sub {
            my ( $cached, $result, $ok ) = @_;
            # $result = [ $object->$some_method( ... arguments ... ) ];
        }
    );


=method cached ($key, ($data?, \%driver_opts?) | ( \&subroutine|($object, $method), \@arguments, %options? ), \&cb?)

Shorthand for for L</get>, L</set>, L</expire>, L</cached_sub> and L</cached_method>
and its expiration.

    # ->get
    $cached->cached($key, \&cb?);                        # without driver options
    $cached->cached($key, undef, \%driver_opts?, \&cb?); # with driver options

    # ->get if cached, or ->set (or even ->expire)
    $cached->cached($key, $data, \&cb?);                   # get/set without driver options
    $cached->cached($key, $data, \%driver_opts?, \&cb?);   # get/set with driver options
    $cached->cached($key, $data, {expire_in => 0}, \&cb?); # expire ($data is ignored)
    $cached->cached($key, undef, {expire_in => 0}, \&cb?); # expire


    # cached_sub
    $cached->cached($key, \&subroutine, \@arguments, %options?, \&cb?);

    # cached_method
    $cached->cached($key, $object, $method, \@arguments, %options?, \&cb?);


=method get_cache_key ($key, $wantarray, \&subroutine|($object, $method), \@arguments, \%options?, \&cb?)

Returns cache key for provided arguments.

Available options:

=over

=item fn_key

Type: B<bool>

Indicate if data has to be cached not by C<$key> but by L<functional key|/fn_key>
(default L</use_fn_key>).

=item fn_key_flatten_args

Type: B<coderef>

Subroutine to make string from sub/method arguments for current caching
(default L</default_flatten_args>) when C<fn_key> is C<true>.

=item fn_key_no_encode_utf8

Type: B<bool>

Indicate if Encode::encode_utf8 should be done on key generation when  C<fn_key> is C<true>.

=back


=method fn_key ($key, \@arguments, \%options?)

Generate cache key for C<$key> and @arguments.

Addition C<\%options> could be provided.

Available C<options>:

=over

=item flatten_args

Type: B<coderef>

Default: L</default_flatten_args>

Generate cache key for C<$key> and @arguments via C<flatten_args>

=item no_encode_utf8

Type: B<bool>

Default: false

Since L</fn_key> generation is based on MD5 hash,
indicate that data (C<$key> and C<\@arguments>) passed to MD5 should be UTF8 encoded
(via L<Encode/encode_utf8>).

=back


=method default_flatten_args ($arguments?, $prepend?, $key?)

C<$arguments> could be HASH, ARRAY, blessed value with C<to_string> method,
other types will be supposed to be SCALAR
(which will be stringified like C<'' . $arguments>).
If it is blessed and can C<to_string>, then C<to_string> will be used to
stringify C<$arguments>.

Make string from C<$arguments>

    # Say User implements "to_string" method
    my $user = User->load( id => 42 );

    # ... and Object doesn't
    my $obj = Object->new;

    # Then
    say $user->to_string; # User(id=42)
    say "$obj";           # Object=HASH(0xfc75d8)

    # And finally
    #
    # [1,[a,b],{c=>[3,2,1],d=>e},User(id=42),Object=HASH(0xfc75d8)]
    say $cached->flatten_args(
            [
                1,
                [
                    'a',
                    'b',
                ],
                {
                    d => 'e',
                    c => [
                        3,
                        2,
                        1,
                    ]
                },
                $user,
                $obj
            ]
        );
