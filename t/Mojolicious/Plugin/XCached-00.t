use Mojo::Base -strict;

use lib 't/lib';

use Data::Dumper;

use Test::More;
use Test::Mojo;


my $t = Test::Mojo->new('TestApp');

subtest 'xcache key' => sub {
    my $c  = $t->app->build_controller;
    my $ts = time;

    # Get `key`
    my $data = $c->xcache('key');
    ok( !defined($data), '... no `key` data yet' );

    my $data_to_set = { a => [ 'data', 1, { a => 1, b => 2 } ] };

    # Set `key` at t
    $c->xcache( key => $data_to_set, { t => $ts } );
    $data = $c->xcache('key');
    is_deeply( $data, $data_to_set, '... equal at t' );

    # Get `key` at t+2
    $data = $c->xcache( 'key', undef, { t => $ts + 2 } );
    is_deeply( $data, $data_to_set, '... equal at t+2' );

    # Get `key` at t+4
    $data = $c->xcache( 'key', undef, { t => $ts + 4 } );
    is( defined $data, defined undef, '... empty at t+4' );


    # Set `key` with expiration time: t+2 sec
    $c->xcache( key => $data_to_set, { t => $ts, expire_in => 2 } );
    $data = $c->xcache( 'key', undef, { t => $ts } );
    is_deeply( $data, $data_to_set, '... re-set at t witn expiration' );

    # Get `key` at t+2
    $data = $c->xcache( 'key', undef, { t => $ts + 2 } );
    is_deeply( $data, $data_to_set, '... equal with expiration at t+2' );

    # Get `key` at t+3
    $data = $c->xcache( 'key', undef, { t => $ts + 3 } );
    ok( !defined($data), '... expired at t+3' );

    subtest expire => sub {

        # Set `key` with expiration time: t+2 sec
        $c->xcache( key => $data_to_set, { t => $ts, expire_in => 2 } );
        $data = $c->xcache( 'key', undef, { t => $ts } );
        is_deeply( $data, $data_to_set, 'set at t witn expiration' );


        # Expire `key`
        my $expire_status
            = $c->xcache( key => {}, { t => $ts, expire_in => -1 } );
        is_deeply( $expire_status, 1, 'expire status' );

        # Get `key`
        $data = $c->xcache( 'key', undef, { t => $ts } );
        is( $data, undef, 'no data' );
    };
};

subtest 'xcache sub' => sub {
    my $x3 = sub {
        my $num = shift;

        return wantarray ? ( $num * 3, 'okay' ) : ( $num * 3 );
    };

    my $ts = time;
    my $c  = $t->app->build_controller;


    # Scalar
    subtest 'Scalar' => sub {
        my $data = $c->xcache('key');
        is( defined $data, defined undef, 'no `key` data yet' );

        $data = $c->xcache(
            key => $x3 => [3],
            (
                driver => { t => $ts },
                fn_key => 0,
            )
        );
        is( $data, 9, 'named scalar okay (ret)' );

        $data = $c->xcache('key');
        is( $data, 9, 'named scalar okay' );

        $data = $c->xcache( 'key', undef, { t => $ts + 2 } );
        is( $data, 9, 'named scalar okay t+2' );

        $data = $c->xcache(
            key => $x3 => [5],
            (
                driver => { t => $ts },
                fn_key => 0,
            )
        );
        is( $data, 9, 'named scalar still okay' );

        $data = $c->xcache(
            key => $x3 => [5],
            (
                driver => { t => $ts + 2 },
                fn_key => 0,
            )
        );
        is( $data, 9, 'named scalar still okay t+2' );


        my $expire_result = $c->xcache( 'key', undef, { expire_in => 0 } );
        is( $expire_result, 1, 'expire result' );

        $expire_result = $c->xcache( 'key', undef, { expire_in => 0 } );
        is( $expire_result, !!0, 'expire again result' );

        $data = $c->xcache( 'key', undef, { t => $ts } );
        ok( !defined($data), 'expired' );

        $data = $c->xcache(
            key => $x3 => [3],
            (
                driver => { t => $ts },
                fn_key => 0,
            )
        );
        is( $data, 9,
            'named scalar cache result okay before level expiration' );

        $data = $c->xcache('key');
        is( $data, 9, 'named scalar okay before level expiration' );

        $data = $c->xcache(
            key => $x3 => [5],
            (
                driver => { t => $ts + 4 },
                fn_key => 0,
            )
        );
        is( $data, 15, 'named scalar cache result after level expiration' );
        $data = $c->xcache('key');
        is( $data, 15, 'named scalar okay after level expiration' );

        $data = $c->xcache( 'key', undef, { t => $ts + 4 * 2 } );
        ok( !defined($data), 'expired' );
    };


    # List
    subtest 'List' => sub {
        my @data = $c->xcache(
            key => $x3 => [3],
            (
                driver => { t => $ts },
                fn_key => 0,
            )
        );
        is_deeply( \@data, [ 9, 'okay' ], 'named list okay (ret)' );

        my $data = $c->xcache('key');
        is_deeply( $data, [ 9, 'okay' ], 'named list okay' );

        $data = $c->xcache( 'key', undef, { t => $ts + 2 } );
        is_deeply( $data, [ 9, 'okay' ], 'named list (get scalar) okay t+2' );

        @data = $c->xcache(
            key => $x3 => [5],
            (
                driver => { t => $ts },
                fn_key => 0,
            )
        );
        is_deeply( \@data, [ 9, 'okay' ], 'named list still okay' );

        @data = $c->xcache(
            key => $x3 => [5],
            (
                driver => { t => $ts + 2 },
                fn_key => 0,
            )
        );
        is_deeply( \@data, [ 9, 'okay' ], 'named list still okay t+2' );

        my $expire_result = $c->xcache( 'key', undef, { expire_in => 0 } );
        is( $expire_result, 1, 'expire result' );

        $data = $c->xcache( 'key', undef, { t => $ts } );
        ok( !defined($data), 'expired' );

        @data = $c->xcache(
            key => $x3 => [3],
            (
                driver => { t => $ts + 2 },
                fn_key => 0,
            )
        );
        is_deeply(
            \@data,
            [ 9, 'okay' ],
            'named list cach result before level expiration'
        );

        $data = $c->xcache('key');
        is_deeply(
            $data,
            [ 9, 'okay' ],
            '... named list okay before level expiration'
        );

        @data = $c->xcache(
            key => $x3 => [5],
            (
                driver => { t => $ts + 6 },
                fn_key => 0,
            )
        );
        is_deeply(
            \@data,
            [ 15, 'okay' ],
            '... named list okay after level expiration'
        );

        $data = $c->xcache( 'key', undef, { t => $ts + 6 + 4 } );
        ok( !defined($data), 'expired' );
    };
};

subtest 'xcache method' => sub {
    my $c = $t->app->build_controller;

    my $ts = time;

    # Scalar
    subtest 'Scalar' => sub {
        my $data = $c->xcache('key');
        is( defined $data, defined undef, '... no `key` data yet' );

        $c->xcache(
            key => $t->app => 'x3' => [3],
            (
                driver => { t => $ts },
                fn_key => 0,
            )
        );
        $data = $c->xcache('key');
        is( $data, 9, '... named scalar okay' );

        $data = $c->xcache( 'key', undef, { t => $ts + 2 } );
        is( $data, 9, '... named scalar okay t+2' );

        $data = $c->xcache(
            key => $t->app => 'x3' => [5],
            (
                driver => { t => $ts },
                fn_key => 0,
            )
        );
        is( $data, 9, '... named scalar still okay' );

        $c->xcache( 'key', undef, { expire_in => 0 } );
        $data = $c->xcache( 'key', undef, { t => $ts } );
        ok( !defined($data), 'expired' );

        $c->xcache(
            key => $t->app => 'x3' => [3],
            (
                driver => { t => $ts },
                fn_key => 0,
            )
        );
        $data = $c->xcache('key');
        is( $data, 9, '... named scalar okay before level expiration' );
        $data = $c->xcache(
            key => $t->app => 'x3' => [5],
            (
                driver => { t => $ts + 4 },
                fn_key => 0,
            )
        );
        is( $data, 15, '... named scalar okay after level expiration' );

        $data = $c->xcache( 'key', undef, { t => $ts + 4 + 4 } );
        ok( !defined($data), 'expired' );
    };


    # List
    subtest 'List' => sub {
        () = $c->xcache(
            key => $t->app => 'x3' => [3],
            (
                driver => { t => $ts },
                fn_key => 0,
            )
        );
        my $data = $c->xcache('key');
        is_deeply( $data, [ 9, 'okay' ], '... named list okay' );

        $data = $c->xcache( 'key', undef, { t => $ts + 2 } );
        is_deeply( $data, [ 9, 'okay' ], '... named list okay t+2' );

        my @data = $c->xcache(
            key => $t->app => 'x3' => [5],
            (
                driver => { t => $ts },
                fn_key => 0,
            )
        );
        is_deeply( \@data, [ 9, 'okay' ], '... named list still okay' );

        $c->xcache( 'key', undef, { expire_in => 0 } );
        $data = $c->xcache( 'key', undef, { t => $ts } );
        ok( !defined($data), 'expired' );

        () = $c->xcache(
            key => $t->app => 'x3' => [3],
            (
                driver => { t => $ts },
                fn_key => 0,
            )
        );
        $data = $c->xcache('key');
        is_deeply(
            $data,
            [ 9, 'okay' ],
            '... named list okay before level expiration'
        );
        @data = $c->xcache(
            key => $t->app => 'x3' => [5],
            (
                driver => { t => $ts + 4 },
                fn_key => 0,
            )
        );
        is_deeply(
            \@data,
            [ 15, 'okay' ],
            '... named list okay after level expiration'
        );

        $data = $c->xcache( 'key', undef, { t => $ts + 4 + 4 } );
        ok( !defined($data), 'expired' );
    };
};

done_testing();
