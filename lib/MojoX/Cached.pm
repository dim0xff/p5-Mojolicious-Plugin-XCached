package MojoX::Cached;

# ABSTRACT: Simple cache which supports data caching, sub/method call results caching.

use Mojo::Base -base;

use Mojo::Util qw(md5_sum);
use Scalar::Util qw(blessed);

use MojoX::Cached::Driver::Mojo;

use constant DEBUG => $ENV{MOJOX_CACHED_DEBUG};

#<<< no tidy
has 'default_expire';
has 'driver'       => sub { MojoX::Cached::Driver::Mojo->new };
has 'flatten_args' => sub { sub { shift->default_flatten_args(@_) } };
has 'name'         => 'XCached';
#>>>


sub get {
    my ( $self, $key ) = @_;

    warn "-- @{[$self->name]} get $key\n\n" if DEBUG;

    my $cdata = $self->driver->get($key) or return;

    return $cdata->{value};
}

sub set {
    my ( $self, $key, $data, $expire_in ) = @_;

    warn "-- @{[$self->name]} set $key\n\n" if DEBUG;

    $expire_in //= $self->default_expire;
    my $cdata = $self->driver->set( $key, $data, $expire_in ) or return;

    return $cdata->{value};
}

sub expire {
    my ( $self, $key ) = @_;

    warn "-- @{[$self->name]} expire $key\n\n" if DEBUG;

    return $self->driver->expire($key);
}

sub cached {
    my ( $self, $key ) = ( shift, shift );

    # Get/Set
    if (@_) {
        if ( ref $_[0] eq 'CODE' ) {

            # Cached sub
            return $self->cached_sub( $key, @_ );
        }
        elsif ( @_ > 1 && blessed( $_[0] ) && $_[0]->can( $_[1] ) ) {

            # Cached method
            return $self->cached_method( $key, @_ );
        }
        else {
            # Try to get key
            my @data = $self->get($key);

            # Already cached. Return
            return $data[0] if @data;

            # Default Set
            return $self->set( $key, @_ );
        }
    }

    # Get
    else {
        return $self->get($key);
    }
}

sub cached_sub {
    my ( $self, $key, $sub, $arguments, %opts ) = @_;

    # Respect context
    my $is_list_context = !!wantarray;
    $key = ( $is_list_context ? 'LIST' : 'SCALAR' ) . ":$key";

    warn "-- @{[$self->name]} sub $key\n\n" if DEBUG;

    $key = $self->fn_key( $key => $arguments, $opts{flatten_args} );

    # Expiration
    return $self->expire($key) if ( $opts{expire_in} // 1 ) <= 0;

    # Try to get from cache
    my @data = $self->get($key);
    if (@data) {
        warn "-- @{[$self->name]} sub data found for $key\n\n" if DEBUG;
        return $is_list_context ? @{ $data[0] } : $data[0];
    }

    # Not found. Cache it!
    if ($is_list_context) {
        @data = $sub->( @{ $arguments || [] } );
        $self->set( $key => \@data, $opts{expire_in} );
        return @data;
    }
    else {
        my $data = $sub->( @{ $arguments || [] } );
        $self->set( $key => $data, $opts{expire_in} );
        return $data;
    }
}

sub cached_method {
    my ( $self, $key, $obj, $method, $arguments, @opts ) = @_;

    warn "-- @{[$self->name]} method $key\n\n" if DEBUG;

    return $self->cached_sub( "$key->$method", sub { $obj->$method(@_) },
        $arguments, @opts );
}

sub fn_key {
    my ( $self, $key, $arguments, $flatten_args ) = @_;

    local $self->{flatten_args} = $flatten_args if ref $flatten_args eq 'CODE';

    $key = $key . '(' . $self->_flatten_args($arguments) . ')';

    warn "-- @{[$self->name]} key @{[md5_sum($key)]} / $key\n\n" if DEBUG;

    return md5_sum($key);
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
    my $rendered = $cacher->cacher(
        'heavy_template' => $temlate => 'render' =>
        [ ... some template data ... ],
        3600
    );

    # The same, but in list context
    # Results will be stored separately (means, that method will be called again
    # in list context)
    ($rendered) = $cacher->cacher(
        'heavy_template' => $temlate => 'render' =>
        [ ... some template data ... ],
        3600
    );

    # Later when on call method with same arguments, result will be fetched from
    # cache (if not expired) respect call context

=head1 DESCRIPTION

Simple cache, which supports data caching, sub/method call results caching.
You have treat this like L<Memoize> with expiration and different backends.

Available backends:

=over 4

=item L<MojoX::Cached::Driver::Disk>

Slow cache driver with filesystem storage.

=item L<MojoX::Cached::Driver::Mojo>

Cache driver built on top of L</Mojo::Cache>

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


=method get ($key)

Get cached data by C<$key>


=method set ($key, $data, $expire_in?)

Cache C<$data> by C<$key>.
In addition expiration could be set via C<$expire_in> (default L</default_expire>).


=method expire ($key)

Expire cached data by C<$key>.


=method cached_sub ($key, \&subroutine, \@arguments, %options?)

Cache data (by C<$key>) returned from C<&subroutine(@arguments)> call
with respecting call context (LIST or SCALAR).

Available C<options> keys:

=over 4

=item expire_in

Type: B<number>

Key expiration could be set via option C<expire_in> (default L</default_expire>).
Negative means "expire key".

=item flatten_args

Type: B<coderef>

Subroutine to make string from sub/method arguments for current caching
(default L</default_flatten_args>).

=back

    my $sub = sub {...};

    # Scalar context
    # Perform equal to:
    #   my $value = $sub->( ... arguments ... );
    my $value = $cached->cached_sub( key => $sub, [ ... arguments ... ] );

    # List context
    # Perform equal to:
    #   my @values = $sub->( ... arguments ... );
    my @values = $cached->cached_sub( key => $sub, [ ... arguments ... ], ( expire_in => 3600 ) );


=method cached_method ($key, $object, $method, \@arguments, %options?)

Cache data (by C<$key>) returned from C<$object-E<gt>$method(@arguments)> call
with respecting call context (LIST OR SCALAR).
For C<%options> look L</cached_sub>.

    # Scalar context
    # Perform equal to:
    #   my $value = $object->some_method( ... arguments ... );
    my $value = $cached->cached_method(
            key => $object => some_method => [ ... arguments ...]
        );

    # List context
    # Perform equal to:
    #   my @values = $object->some_method( ... arguments ... );
    my @values = $cached->cached_method(
            key => $object => some_method => [ ... arguments ...]
        );


=method cached

Alias for C<get>, C<set>, C<cached_sub> and C<cached_method>.

    # Get
    cached($key)

    # Set
    cached($key, $data, $expire_in?)

    # cached_sub
    cached($key, \&subroutine, \@arguments, %options)

    # cached_method
    cached($key, $object, $method, \@arguments, %options)


=method fn_key ($key, \@arguments, \&flatten_args?)

Generate cache key for C<$key> and @arguments via C<flatten_args>
(default L</default_flatten_args>).


=method flatten_args ($arguments?, $prepend?, $key?)

C<$arguments> could be HASH, ARRAY, blessed value with C<to_string> method,
other types will be supposed to be SCALAR.
If it is blessed and can C<to_string>, then C<to_string> will be used to
stringify C<$arguments>.

Make string from C<$arguments>

    # Say User implements "to_string" method
    my $user = User->load( id => 42 );

    # ... and Object doesn't
    my $obj = Object->new;

    # User(id=42)
    say $user->to_string;

    # Object=HASH(0xfc75d8)
    say "$obj";

    # [1,[a,b],{c=>[3,2,1],d=>e},User(id=42),Object=HASH(0xfc75d8)]
    say flatten_args(
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
