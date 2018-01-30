use Test::More;

use strict;
use warnings;

use lib 't/lib';

use TestDriver;
use MojoX::Cached;

my $default_expire = 1;

my $driver = TestDriver->new;
ok(
    my $cached = MojoX::Cached->new(
        driver         => $driver,
        default_expire => $default_expire
    ),
    'Cached created'
);

is( $cached->driver, $driver, 'driver ref' );

my $key1 = { data => [ 1, 2, 3 ] };
subtest set => sub {
    ok( $cached->set( key1 => $key1, $default_expire * 2 ),
        'set with default_expire * 2' );
    ok( exists $driver->cache->{key1}, 'set key' );
    is_deeply( $driver->cache->{key1}{value}, $key1, 'cached data' );
    is(
        $driver->cache->{key1}{expire_at},
        time + $default_expire * 2,
        'default expire * 2'
    );

    ok( $cached->set( key1 => $key1 ), 'default set' );
    is(
        $driver->cache->{key1}{expire_at},
        time + $default_expire,
        'default expire'
    );
};

subtest get => sub {
    my $data = $cached->get('key1');
    is_deeply( $data, $key1, 'retrieved data is equal to cached' );

    sleep( $default_expire + 1 );

    $data = $cached->get('key1');
    is( $data, undef, 'data is expired' );
};

subtest expire => sub {
    $cached->set( key1 => $key1 );
    isnt( $cached->get('key1'), undef, 'data in cache' );

    $cached->expire('key1');
    is( $cached->get('key1'), undef, 'data is expired' );
};

subtest cached_sub => sub {
    for ( 1 .. 5 ) {
        my ( @value, $value );

        @value = $cached->cached_sub( key => \&subroutine, [1] );
        is_deeply( \@value, [ 2, 'true' ], "cached (list): 1 / call: $_" );

        $value = $cached->cached_sub( key => \&subroutine, [1] );
        is( $value, 2, "cached (scalar): 1 / call: $_" );

        @value = $cached->cached_sub( key => \&subroutine, [2] );
        is_deeply( \@value, [ 4, 'true' ], "cached (list): 2 / call: $_" );

        $value = $cached->cached_sub( key => \&subroutine, [2] );
        is( $value, 4, "cached (scalar): 2 / call: $_" );
    }

    is( subroutine_calls(), 4, 'only 4 cals for 20 caches' );
    is( scalar( keys %{ $driver->cache } ),
        4,
        '4 keys in cache for one key name, 2 diff context, 2 diff arguments' );
};

subtest cached_method => sub {
    my $obj = ThePackage->new;

    $cached->driver->flush;

    for ( 1 .. 5 ) {
        my @value
            = $cached->cached_method( o_3_2 => $obj => method => [ 3, 2 ] );
        is_deeply( \@value, [6], "cached (list): 3*2 / call $_" );


        my $value
            = $cached->cached_method( o_3_2 => $obj => method => [ 3, 2 ] );
        is( $value, 6, "cached (scalar): 3*2 / call $_" );
    }
    is( $obj->{calls}, 2, 'only two method call' );

    is( scalar( keys %{ $driver->cache } ),
        2, '2 keys in cache for one key name, 2 diff context' );

    $cached->cached_method(
        o_3_2 => $obj => method => [ 3, 2 ],
        ( expire_in => 0 )
    );
    is( scalar( keys %{ $driver->cache } ), 1, '... key expired (scalar)' );

    () = $cached->cached_method(
        o_3_2 => $obj => method => [ 3, 2 ],
        ( expire_in => 0 )
    );
    is( scalar( keys %{ $driver->cache } ), 0, '... key expired (list)' );
};

subtest cached => sub {
    $driver->clear_status;
    is( $cached->cached( default => 'value' ), 'value', 'cached->set' );
    is( $cached->cached( default => 'value' ), 'value', 'cached->set' );
    is_deeply( $driver->status, [ 'get', 'set', 'get' ], 'set status' );

    $driver->clear_status;
    is( $cached->cached('default'), 'value', 'cached->get' );
    is_deeply( $driver->status, ['get'], 'get status' );


    subroutine_calls(0);
    $driver->clear_status;
    is( scalar $cached->cached( subroutine => \&subroutine => [5] ),
        10, "scalar cached->subroutine / call $_" )
        for ( 1 .. 5 );
    is_deeply(
        [ $cached->cached( subroutine => \&subroutine => [5] ) ],
        [ 10, 'true' ],
        "list cached->subroutine / call $_"
    ) for ( 1 .. 5 );
    is_deeply(
        $driver->status,
        [ ( 'get', 'set', ('get') x 4 ) x 2 ],
        'cache call status'
    );


    my $obj = ThePackage->new;
    $driver->clear_status;
    for ( 1 .. 5 ) {
        my @value
            = $cached->cached_method( o_3_2 => $obj => method => [ 3, 2 ] );
        is_deeply( \@value, [6], "cached (list): 3*2 / call $_" );


        my $value
            = $cached->cached_method( o_3_2 => $obj => method => [ 3, 2 ] );
        is( $value, 6, "cached (scalar): 3*2 / call $_" );
    }
    is( $obj->{calls}, 2, 'only two method call' );

    $cached->cached_method(
        o_3_2 => $obj => method => [ 3, 2 ],
        ( expire_in => 0 )
    );

    is_deeply(
        $driver->status,
        [ ( 'get', 'set' ) x 2, ('get') x 8, 'expire' ],
        'cache call status'
    );
};

# TODO:
#   * test flatten_args XCache attribute and cached option

#
# HELPERS
#

my $calls = 0;

sub subroutine {
    $calls++;
    return wantarray ? ( $_[0] * 2, 'true' ) : ( $_[0] * 2 );
}

sub subroutine_calls {
    ($calls) = @_ if @_;
    $calls;
}

package ThePackage {

    sub new {
        bless { calls => 0 }, shift;
    }

    sub method {
        shift->{calls}++;

        return $_[0] * $_[1];
    }

    1;
};

done_testing();
