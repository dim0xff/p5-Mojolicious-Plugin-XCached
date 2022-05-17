use Test::More;

use strict;
use warnings;

use lib 't/lib';

note 'Test for no callbacks';

use TestDriver;
use Encode qw(encode_utf8);

use_ok('MojoX::Cached');

# TODO:
#   * test flatten_args XCache attribute and cached option

#
# HELPERS
#

BEGIN {
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
}

#
# TESTS
#

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

my $t = time;
my $key1 = { data => [ 1, 2, 3 ] };
subtest set => sub {
    ok(
        $cached->set(
            key1 => $key1,
            { t => $t, expire_in => $default_expire * 2 }
        ),
        'set with default_expire * 2'
    );
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

        $value = $cached->cached_sub( key => \&subroutine, [2] );
        is( $value, 4, "cached (scalar): 1 / call: $_" );

        @value = $cached->cached_sub( key => \&subroutine, [3] );
        is_deeply( \@value, [ 6, 'true' ], "cached (list): 2 / call: $_" );

        $value = $cached->cached_sub( key => \&subroutine, [4] );
        is( $value, 8, "cached (scalar): 2 / call: $_" );
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
        o_3_2  => $obj        => method => [ 3, 2 ],
        driver => { expire_in => 0 }
    );
    is( scalar( keys %{ $driver->cache } ), 1, '... key expired (scalar)' );

    () = $cached->cached_method(
        o_3_2  => $obj        => method => [ 3, 2 ],
        driver => { expire_in => 0 }
    );
    is( scalar( keys %{ $driver->cache } ), 0, '... key expired (list)' );
};

subtest cached => sub {
    $driver->clear_status;

    is( $cached->cached( default => 'value' ), 'value', 'cached->set' );
    is( $cached->cached( default => 'value' ), 'value', 'cached->set' );
    is( $cached->cached('default'), 'value', 'cached->get' );
    is( $cached->cached( 'default', undef, { expire_in => 1 } ),
        'value', 'cached->get with opts' );
    is( $cached->cached( default => 'value', { expire_in => 0 } ),
        1, 'cached->set (expire)' );
    is( $cached->cached( default => 'value', { expire_in => 0 } ),
        !!0, 'cached->set (expire)' );
    is_deeply( $driver->status,
        [ 'get', 'set', 'get', 'get', 'get', 'expire', 'expire' ],
        'set status' );

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
    $cached->cached(
        subroutine => \&subroutine => [5],
        driver     => { expire_in  => 0 }
    );
    is_deeply(
        $driver->status,
        [ ( 'get', 'set', ('get') x 4 ) x 2, 'expire' ],
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
        o_3_2  => $obj        => method => [ 3, 2 ],
        driver => { expire_in => 0 }
    );

    is_deeply(
        $driver->status,
        [ ( 'get', 'set' ) x 2, ('get') x 8, 'expire' ],
        'cache call status'
    );
};

subtest fn_key => sub {
    $driver->clear_status;

    my $obj = ThePackage->new;

    # key-ключ
    my $key = "key-\x{43a}\x{43b}\x{44e}\x{447}";

    subtest 'encode_utf8' => sub {
        $cached->use_fn_key(1);
        $driver->flush;
        $driver->clear_status;

        $cached->cached_sub( $key => \&subroutine, [4] );
        is( scalar $cached->cached_sub( $key => \&subroutine, [4] ),
            8, 'fn_key with encode_utf8' );

        eval {
            $cached->cached_sub(
                $key => \&subroutine,
                [5], fn_key_no_encode_utf8 => 1
            );
        };
        like(
            $@,
            qr/Wide character/,
            'fn_key with encode_utf8 failed: Wide character...'
        );
        undef $@;

        $cached->cached_sub(
            encode_utf8($key) => \&subroutine,
            [5], fn_key_no_encode_utf8 => 1
        );
        is(
            scalar $cached->cached_sub(
                encode_utf8($key) => \&subroutine,
                [5], fn_key_no_encode_utf8 => 1
            ),
            10,
            'fn_key without encode_utf8 success (manual encoded)'
        );
    };


    for my $t (
        [
            'use_fn_key => 1',
            1,
            [
                'get', 'set', 'get', 'get', 'set',    # scalar sub
                'get', 'set', 'get', 'get',     # list sub
                'get', 'set', 'get', 'get',     # scalar obj
                'get', 'set', 'get', 'get',     # list obj
            ]
        ],
        [
            'use_fn_key => 0',
            0,
            [
                'get', 'set', 'get', 'set', 'get',    # scalar sub
                'get', 'get', 'set', 'get',     # list sub
                'get', 'get', 'set', 'get',     # scalar obj
                'get', 'get', 'set', 'get',     # list obj
            ],
        ],
        )
    {
        subtest $t->[0] => sub {
            $cached->use_fn_key( $t->[1] );
            $driver->flush;
            $driver->clear_status;

            #<<< no tidy
            $cached->cached_sub( $key => \&subroutine, [1] );
            $cached->cached_sub( $key => \&subroutine, [1], fn_key => 1 );
            $cached->cached_sub( $key => \&subroutine, [1], fn_key => 0 );

            () = $cached->cached_sub( $key => \&subroutine, [1] );
            () = $cached->cached_sub( $key => \&subroutine, [1], fn_key => 1 );
            () = $cached->cached_sub( $key => \&subroutine, [1], fn_key => 0 );

            $cached->cached_method( $key => $obj => method => [3, 2] );
            $cached->cached_method( $key => $obj => method => [3, 2], fn_key => 1 );
            $cached->cached_method( $key => $obj => method => [3, 2], fn_key => 0 );

            () = $cached->cached_method( $key => $obj => method => [3, 2] );
            () = $cached->cached_method( $key => $obj => method => [3, 2], fn_key => 1 );
            () = $cached->cached_method( $key => $obj => method => [3, 2], fn_key => 0 );
            #>>>

            my $sub_scalar_key = $cached->fn_key( "SCALAR:$key", [1] );
            my $sub_list_key   = $cached->fn_key( "LIST:$key",   [1] );
            my $obj_scalar_key
                = $cached->fn_key( "SCALAR:$key->method", [ 3, 2 ] );
            my $obj_list_key = $cached->fn_key( "LIST:$key->method", [ 3, 2 ] );

            is_deeply(
                [ sort keys %{ $driver->cache } ],
                [
                    sort $key,     $sub_list_key, $sub_scalar_key,
                    $obj_list_key, $obj_scalar_key
                ]
            );

            is_deeply( $driver->status, $t->[2], 'cache call status' );
        };
    }
};

done_testing();
