package Mojolicious::Plugin::XCached;

# ABSTRACT: Cache plugin

use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Loader qw(load_class);
use Scalar::Util qw(blessed);

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
        my %config = %{$cfg};

        $config{driver} = $module->new( delete $config{driver_options} // () );
        $config{name} //= "Cache:L$idx";

        my $xcached = MojoX::Cached->new(%config);

        $app->xcached->[$idx] = $xcached;
        $app->helper( "xcached.l$idx" => sub { shift->app->xcached->[$idx] } );

        $app->log->debug("X::Cached loaded ($module), layer $idx");

        $cache_index++;
    }

    $app->helper( xcache    => sub { _xcache(@_) } );
    $app->helper( xcaches   => sub { return $cache_index } );
    $app->helper( xcinclude => sub { _xcinclude(@_) } );
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

    # Data to be cached
    my @arguments = shift @_ if @_;

    # No XCached
    if ( $c->stash('NO_XCACHED') ) {

        # Return nothing if it is "get" for general data
        return unless @arguments;

        # It is "set", return data needed to be cached
        if ($sub) {
            return $sub->( @{ $arguments[0] || [] } );
        }
        elsif ( $obj && $method ) {
            return $obj->$method( @{ $arguments[0] || [] } );
        }
        else {
            return $arguments[0];
        }
    }

    my @rest = @_;

    # Create chain of caches (from lower to top)
    my @chain;

    # Cache method/sub call
    if ( $sub || $method ) {
        for my $idx ( reverse 0 .. ( $c->xcaches - 1 ) ) {
            if (@chain) {
                my $chain_idx = $#chain;
                push @chain, sub {
                    return $c->app->xcached->[$idx]->cached(
                        "L$idx" => $chain[$chain_idx],
                        [
                            $key,
                            ( $method // () ),
                            (
                                  $sub || $method
                                ? $arguments[0]
                                : ()
                            )
                        ],
                        @rest
                    );
                };
            }
            else {
                push @chain, sub {
                    return $c->app->xcached->[$idx]->cached(
                        $key,
                        ( $sub    // () ),
                        ( $obj    // () ),
                        ( $method // () ),
                        @arguments, @rest
                    );
                };
            }
        }
    }
    elsif ( $c->xcaches ) {

        # Cache regular data: use only first level cache
        @chain = (
            sub {
                return $c->app->xcached->[0]->cached( $key, @arguments, @rest );
            }
        );
    }

    return unless @chain;
    return $chain[-1]->();
}

# Cached include
sub _xcinclude {
    my $c = shift;

    # No XCached
    return $c->helpers->include(@_) if $c->stash('NO_XCACHED');

    my ( $template, %args ) = ( @_ % 2 ? shift : undef, @_ );

    my $cache_options = delete $args{xcached};
    $cache_options = [] unless ref $cache_options eq 'ARRAY';

    return $c->xcache(
        '$c->helpers' => $c->helpers => include => [ $template, %args ],
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

        my $user = $c->xcached('user');
        if (!$user) {
            $user = $user_model->load_user( id => $c->param('user_id') );
            $c->xcached( user => $user, 3600 );
        }

        $c->render( user => $user );
    }

    # ... or even like this
    sub action {
        my $c = shift;

        my $user = $c->xcached(
            user => $user_model => load_user =>
            [ id => $c->param('user_id') ],
            3600
        );

        $c->render( user => $user );
    }


    # In your template
    %= xcinclude( 'common/user/info', $user );

    # @common/user/info.html.ep
    % for $object ( $user->related_objects ) {
        %= include( 'common/user/related_object' => $object );
    % }

=head1 DESCRIPTION

L<Mojolicious::Plugin::XCached> allows to add layers of caches to your app.

Caches are implemented via L<MojoX::Cached>.

Plugin adds two helpers:

=over

=item L</xcached>

To use caches inside application and/or templates

=item L</xcinclude>

To cache rendered templates includes

=back


=head1 CACHES CONFIG

Caches config has to be provided on plugin loading. Config is ARRAY of HASHes.
First element represents top level cache layer, last - bottom.
   
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
    driver_options => { max_keys => 50 },

    # will be used as
    MojoX::Cached::Driver::Mojo->new( { max_keys => 50 } )


=head1 HELPERS

Cache could be disabled via C<NO_XCACHED> stash key.
B<1> means I<disable xcache>, B<0> means I<enable xcache>.

=head2 xcache

Layered cache, accepts the same arguments as L<MojoX::Cached/cached>.

Subroutine/method calls will be cached on all layers,
but regular value will be cached only on first cache level.

=head1 xcinclude

Cache rendered template, render if needed. Accepts the same arguments
as L<Mojolicious::Plugin::DefaultHelpers/include>.
