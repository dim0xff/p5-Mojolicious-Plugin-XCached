use Mojo::Base -strict;

use lib 't/lib';

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('TestApp');

subtest 'xcache key' => sub {
    my $c    = $t->app->build_controller;
    my $data = $c->xcache('key');
    ok( !defined($data), '... no `key` data yet' );

    my $ts = time;
    my $data_to_set = { a => [ 'data', 1, { a => 1, b => 2 } ] };
    $c->xcache( key => $data_to_set, { t => $ts } );
    $data = $c->xcache('key');
    is_deeply( $data, $data_to_set, '... equal in t' );

    $data = $c->xcache( 'key', undef, { t => $ts + 2 } );
    is_deeply( $data, $data_to_set, '... equal in t+2' );

    $data = $c->xcache( 'key', undef, { t => $ts + 4 } );
    is( defined $data, defined undef, '... empty in t+4' );


    $c->xcache( key => $data_to_set, { t => $ts, expire_in => 2 } );
    $data = $c->xcache( 'key', undef, { t => $ts } );
    is_deeply( $data, $data_to_set, '... re-set in t witn expiration' );

    $data = $c->xcache( 'key', undef, { t => $ts + 2 } );
    is_deeply( $data, $data_to_set, '... equal with expiration in t+2' );

    $data = $c->xcache( 'key', undef, { t => $ts + 3 } );
    ok( !defined($data), '... expired in t+3' );
};

subtest 'xcache sub' => sub {
    my $x3 = sub {
        my $num = shift;

        return wantarray ? ( $num * 3, 'okay' ) : ( $num * 3 );
    };

    my $c = $t->app->build_controller;


    # Scalar
    my $data = $c->xcache('key');
    is( defined $data, defined undef, '... no `key` data yet' );

    my $ts = time;
    $c->xcache(
        key => $x3 => [3],
        (
            cache  => { t => $ts },
            fn_key => 0,
        )
    );
    $data = $c->xcache('key');
    is( $data, 9, '... named scalar okay' );

    $data = $c->xcache( 'key', undef, { t => $ts + 2 } );
    is( $data, 9, '... named scalar okay t+2' );

    $data = $c->xcache(
        key => $x3 => [5],
        (
            cache  => { t => $ts },
            fn_key => 0,
        )
    );
    is( $data, 9, '... named scalar still okay' );

    $c->xcache( 'key', undef, { expire_in => 0 } );
    $data = $c->xcache( 'key', undef, { t => $ts } );
    ok( !defined($data), 'expired' );

    $c->xcache(
        key => $x3 => [3],
        (
            cache  => { t => $ts },
            fn_key => 0,
        )
    );
    $data = $c->xcache('key');
    is( $data, 9, '... named scalar okay before level expiration' );
    $data = $c->xcache(
        key => $x3 => [5],
        (
            cache  => { t => $ts + 4 },
            fn_key => 0,
        )
    );
    is( $data, 15, '... named scalar okay after level expiration' );

    $data = $c->xcache( 'key', undef, { t => $ts + 4 + 4 } );
    ok( !defined($data), 'expired' );


    # List
    () = $c->xcache(
        key => $x3 => [3],
        (
            cache  => { t => $ts },
            fn_key => 0,
        )
    );
    $data = $c->xcache('key');
    is_deeply( $data, [ 9, 'okay' ], '... named list okay' );

    $data = $c->xcache( 'key', undef, { t => $ts + 2 } );
    is_deeply( $data, [ 9, 'okay' ], '... named list okay t+2' );

    my @data = $c->xcache(
        key => $x3 => [5],
        (
            cache  => { t => $ts },
            fn_key => 0,
        )
    );
    is_deeply( \@data, [ 9, 'okay' ], '... named list still okay' );

    $c->xcache( 'key', undef, { expire_in => 0 } );
    $data = $c->xcache( 'key', undef, { t => $ts } );
    ok( !defined($data), 'expired' );

    () = $c->xcache(
        key => $x3 => [3],
        (
            cache  => { t => $ts },
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
        key => $x3 => [5],
        (
            cache  => { t => $ts + 4 },
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

subtest 'xcache method' => sub {
    my $c = $t->app->build_controller;


    # Scalar
    my $data = $c->xcache('key');
    is( defined $data, defined undef, '... no `key` data yet' );

    my $ts = time;
    $c->xcache(
        key => $t->app => 'x3' => [3],
        (
            cache  => { t => $ts },
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
            cache  => { t => $ts },
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
            cache  => { t => $ts },
            fn_key => 0,
        )
    );
    $data = $c->xcache('key');
    is( $data, 9, '... named scalar okay before level expiration' );
    $data = $c->xcache(
        key => $t->app => 'x3' => [5],
        (
            cache  => { t => $ts + 4 },
            fn_key => 0,
        )
    );
    is( $data, 15, '... named scalar okay after level expiration' );

    $data = $c->xcache( 'key', undef, { t => $ts + 4 + 4 } );
    ok( !defined($data), 'expired' );


    # List
    () = $c->xcache(
        key => $t->app => 'x3' => [3],
        (
            cache  => { t => $ts },
            fn_key => 0,
        )
    );
    $data = $c->xcache('key');
    is_deeply( $data, [ 9, 'okay' ], '... named list okay' );

    $data = $c->xcache( 'key', undef, { t => $ts + 2 } );
    is_deeply( $data, [ 9, 'okay' ], '... named list okay t+2' );

    my @data = $c->xcache(
        key => $t->app => 'x3' => [5],
        (
            cache  => { t => $ts },
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
            cache  => { t => $ts },
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
            cache  => { t => $ts + 4 },
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

done_testing();
