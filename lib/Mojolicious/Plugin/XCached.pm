package Mojolicious::Plugin::XCached;

# ABSTRACT: Cache layers plugin

use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Loader qw(load_class);
use Scalar::Util qw(blessed);
use Storable qw(dclone);

use MojoX::Cached;

sub register {
    my ( $plugin, $app, $config ) = @_;

    $app->attr( xcached => sub { [] } );

    my $cache_index = 0;
    for my $cfg ( @{ $config // [] } ) {

        # Get cache driver module name using rules:
        #   SomeDriver      => MojoX::Cached::Driver::SomeDriver
        #   +SomeUserDriver => SomeUserDriver
        my $module = $cfg->{driver};
        if ( $module !~ s/^\+// ) {
            $module = "MojoX::Cached::Driver::$module";
        }

        # Load cache driver module
        if ( my $error = load_class($module) ) {
            $app->log->error( "XCached driver loading for '$module' failed"
                    . ( ref $error ? ": $error" : "" ) );
            next;
        }

        # Create XCached object
        my $idx    = $cache_index;
        my %config = %{ dclone $cfg};

        $config{driver} = $module->new( delete $config{driver_options} // () );
        $config{name} //= "Cache:L$idx";

        my $xcached = MojoX::Cached->new(%config);

        $app->xcached->[$idx] = $xcached;
        $app->helper( "xcached.l$idx" => sub { shift->app->xcached->[$idx] } );

        $app->log->debug("XCached layer $idx loaded ($module)");

        $cache_index++;
    }

    $app->helper( xcache    => sub { _xcache(@_) } );
    $app->helper( xcaches   => sub { return $cache_index } );
    $app->helper( xcinclude => sub { _xcinclude(@_) } );

    $app->log->debug("XCached loaded. Total layers: $cache_index");
}

# Layered cache
sub _xcache {
    my ( $c, $key ) = ( shift, shift );

    my ( $sub, $obj, $method );
    if ( ref $_[0] eq 'CODE' ) {
        $sub = shift @_;
    }
    elsif ( @_ > 1 && blessed( $_[0] ) && $_[0]->can( $_[1] ) ) {
        $obj    = shift @_;
        $method = shift;
    }

    my ( @arguments, $cb, @rest );
    @arguments = shift @_ if @_ && ref $_[0] eq 'ARRAY';
    $cb        = pop @_   if ref $_[-1] eq 'CODE';
    @rest      = @_;

    # No XCached
    if ( $c->stash('NO_XCACHED') || !$c->xcaches ) {

        # Return nothing if it is "get" for general data
        return unless @arguments;

        # It is "set", return data needed to be cached
        if ($sub) {
            return $cb
                ? $cb->( undef, $sub->( @{ $arguments[0] || [] } ) )
                : $sub->( @{ $arguments[0] || [] } );
        }
        elsif ( $obj && $method ) {
            return $cb
                ? $cb->( undef, $obj->$method( @{ $arguments[0] || [] } ) )
                : $obj->$method( @{ $arguments[0] || [] } );
        }
        else {
            return $cb
                ? $cb->( undef, $arguments[0] )
                : $arguments[0];
        }
    }

    my $in_scalar;

    $key = $c->app->xcached->[0]->get_cache_key(
        $key, wantarray,
        ( $sub    // () ),
        ( $obj    // () ),
        ( $method // () ),
        @arguments, @rest, ( $cb // () )
    );

    # Cache for regular data: change it to subroutine call
    if ( !$sub && !$method ) {
        $in_scalar = 1;
        $sub       = sub { shift @_ };
        @rest      = ( expire_in => shift @rest ) if @rest;
        @arguments = ( [@arguments] );
    }

    # Expire?
    my $to_expire = ( {@rest}->{expire_in} // 1 ) <= 0;

    # Layers of caches (direction: bottom-top)
    my @layers;
    for my $idx ( reverse 0 .. ( $c->xcaches - 1 ) ) {
        my ( $l_idx, @params, @cb ) = ($#layers);

        if (@layers) {
            @params = ( $layers[$l_idx], [], );
        }
        else {
            @params = (
                ( $sub    // () ),
                ( $obj    // () ),
                ( $method // () ), @arguments,
            );
        }

        if ($cb) {
            if ($idx) {
                push @cb,
                    $to_expire
                    ? sub { shift; $layers[ $l_idx + 2 ]->(); @_; }
                    : sub { shift; @_; };
            }
            else {
                push @cb, $cb;
            }
        }

        push @layers, sub {
            if ($in_scalar) {
                return scalar $c->app->xcached->[$idx]->cached(
                    $key => @params,
                    ( @rest, fn_key => 0 ),
                    @cb
                );
            }
            else {
                return $c->app->xcached->[$idx]->cached(
                    $key => @params,
                    ( @rest, fn_key => 0 ),
                    @cb
                );
            }
        };
    }

    if ($to_expire) {
        if ($cb) {
            return $layers[0]->();
        }
        else {
            $_->() for @layers;
        }
    }
    else {
        return $layers[-1]->();
    }
}


# Cached include
sub _xcinclude {
    my $c = shift;

    # No XCached
    return $c->helpers->include(@_) if $c->stash('NO_XCACHED') || !$c->xcaches;

    my ( $template, %args ) = ( @_ % 2 ? shift : undef, @_ );

    my $xcache_key    = delete $args{xcache_key};
    my $cache_options = delete $args{xcached};
    $cache_options = [] unless ref $cache_options eq 'ARRAY';

    return $c->xcache(
        ( $xcache_key // '$c->helpers' ) => $c->helpers => include =>
            [ $template, %args ],
        @{$cache_options}
    );
}

1;

__END__

=head1 SYNOPSIS

    # In your app
    $app->plugin(XCached => [ ... caches config ... ] );


    # In your controller
    sub action {
        my $c = shift;

        my $user = $c->xcache('user');
        if (!$user) {
            $user = $user_model->load_user( id => $c->param('user_id') );
            $c->xcache( user => $user, 3600 );
        }

        $c->render( user => $user );
    }

    # ... or like this
    sub action {
        my $c = shift;

        my $user = $c->xcache(
            user => $user_model => load_user =>
            [ id => $c->param('user_id') ],
            3600
        );

        $c->render( user => $user );
    }

    # ... or even like this, if driver is non-blocking
    sub action {
        my $c = shift;

        $c->render_later;

        $c->xcache(
            user => $user_model => load_user =>
            [ id => $c->param('user_id') ],
            3600,
            sub {
                my ( $xcache, $user ) = @_;

                $c->render( user => $user );
            }
        );
    }


    # In your template
    %= xcinclude( 'common/user/info', user => $current_user, xcache => [ fn_key => 0 ],  xcache_key => 'current_user' );

    # @common/user/info.html.ep
    % for $object ( $user->related_objects ) {
        %= include( 'common/user/related_object' => $object );
    % }

=head1 DESCRIPTION

L<Mojolicious::Plugin::XCached> allows to add layers of caches to your app.

Caches are implemented via L<MojoX::Cached>.

Plugin adds two helpers:

=over

=item L</xcache>

To use caches inside application and/or templates

=item L</xcaches>

Returns count of cache layers

=item L</xcinclude>

To cache rendered templates includes

=back


=head1 CACHES CONFIG

Caches config has to be provided on plugin loading. Config is ARRAY of HASHes.
First element represents top level cache layer, last - bottom,
so try to place the fastest cache to the top.

    [
        {
            driver         => 'MODULE',
            driver_options => {},
            ...
        },
        ...
    ]

Each hash requires C<driver> key and optional C<driver_options> key.
Other keys will be passed to C<MojoX::CachedE<gt>new(...)> as is.

B<driver> has to be a module name inside C<MojoX::Cached::Driver> namespace
or started with C<+> sign, to refer full module name.

    Mojo        -> MojoX::Cached::Driver::Mojo
    Disk        -> MojoX::Cached::Driver::Disk
    SomeModule  -> MojoX::Cached::Driver::SomeModule
    +UserDriver -> UserDriver

B<driver_options> will be passed to driver constructor (C<new>)

    # these options
    driver         => 'Mojo',
    driver_options => { expire_in => 3600, driver => { max_keys => 50 } },

    # will be used as
    MojoX::Cached::Driver::Mojo->new( {
        expire_in => 3600,
        driver    => { max_keys => 50 }
    } );


=head1 HELPERS

Cache could be disabled via C<NO_XCACHED> stash key.
B<1> means I<disable xcache>, B<0> means I<enable xcache>.

=head2 xcache

Layered cache, accepts the same arguments as L<MojoX::Cached/cached>.

Will cache data at all layers, and get from top available layer.

=head1 xcinclude

Cache rendered template, render if needed. In addition to C<xcached>
and C<xcache_key> arguments, it accepts the same arguments
as L<Mojolicious::Plugin::DefaultHelpers/include>.

C<xcached> parameter must be C<ARRAY>. It will be dereferenced
and passed to L</xcache>.
C<xcache_key> will be used as cache C<key> (instead of default C<$c-E<gt>helpers>).
