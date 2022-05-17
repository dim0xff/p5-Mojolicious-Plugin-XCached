use Mojo::Base -strict;

use lib 't/lib';

use Data::Dumper;

use Test::More;
use Test::Mojo;


my $t = Test::Mojo->new('TestApp');

subtest 'xcache key cb' => sub {
    my $c  = $t->app->build_controller;
    my $ts = time;

    # Get `key`
    subtest 'get not cached' => sub {
        for ( 0 .. $c->xcaches_num - 1 ) {
            $c->app->xcached->[$_]->driver->clear_status;
        }

        my $result = $c->xcache(
            'key', undef,
            sub {
                my ( $xc, $data, $ok ) = @_;
                ok( !defined($data), 'no `key` data yet' );
                is( $ok, !!0, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is( $result, 42, 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply( $c->app->xcached->[$_]->driver->status,
                ['get'], "driver log: $_" );
        }
    };

    my $data_to_set = { a => [ 'data', 1, { a => 1, b => 2 } ] };

    # Set `key` at t
    subtest 'set at t' => sub {
        for ( 0 .. $c->xcaches_num - 1 ) {
            $c->app->xcached->[$_]->driver->clear_status;
        }

        my ($result) = $c->xcache(
            key => $data_to_set,
            { t => $ts },
            sub {
                my ( $xc, $data, $ok ) = @_;

                is( $ok, 1, 'data set' );
                is_deeply( $data, [$data_to_set], 'data value' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'set' ],
                "driver log: $_"
            );
        }


        $result = $c->xcache(
            'key', undef,
            sub {
                my ( $xc, $data, $ok ) = @_;
                is_deeply( $data, [$data_to_set],
                    'data value equal at t(l0:ok l1:not used l2:not used)' );
                is( $ok, 1, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is( $result, 42, 'cb result' );

        is_deeply(
            $c->app->xcached->[0]->driver->status,
            [ 'get', 'set', 'get' ],
            "driver log: 0"
        );
        for ( 1 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'set' ],
                "driver log: $_"
            );
        }


        ($result) = $c->xcache(
            'key', undef,
            { t => $ts + 3 },
            sub {
                my ( $xc, $data, $ok ) = @_;
                is_deeply( $data, [$data_to_set],
                    'data value equal at t+3 (l0:expired l1:expired l3:ok)' );
                is( $ok, 1, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb result' );

        is_deeply(
            $c->app->xcached->[0]->driver->status,
            [ 'get', 'set', 'get', 'get', 'expire', 'set' ],
            "driver log: 0"
        );
        is_deeply(
            $c->app->xcached->[1]->driver->status,
            [ 'get', 'set', 'get', 'expire', 'set' ],
            "driver log: 1"
        );
        is_deeply(
            $c->app->xcached->[2]->driver->status,
            [ 'get', 'set', 'get' ],
            "driver log: 2"
        );


        my ($data) = $c->xcache( 'key', undef, { t => $ts + 5 } );
        is_deeply( $data, $data_to_set,
            '... equal at t+5 (l0:expired, l1:ok $l2:not used)' );

        is_deeply(
            $c->app->xcached->[0]->driver->status,
            [
                'get', 'set',    'get', 'get', 'expire', 'set',
                'get', 'expire', 'set'
            ],
            "driver log: 0"
        );
        is_deeply(
            $c->app->xcached->[1]->driver->status,
            [ 'get', 'set', 'get', 'expire', 'set', 'get' ],
            "driver log: 1"
        );
        is_deeply(
            $c->app->xcached->[2]->driver->status,
            [ 'get', 'set', 'get' ],
            "driver log: 2"
        );


        ($data) = $c->xcache( 'key', undef, { t => $ts + 7 } );
        is( $data, undef,
            '... equal at t+7 (l0:expired l1:expired l2:expired)' );

        is_deeply(
            $c->app->xcached->[0]->driver->status,
            [
                'get', 'set',    'get', 'get', 'expire', 'set',
                'get', 'expire', 'set', 'get', 'expire'
            ],
            "driver log: 0"
        );
        is_deeply(
            $c->app->xcached->[1]->driver->status,
            [ 'get', 'set', 'get', 'expire', 'set', 'get', 'get', 'expire' ],
            "driver log: 1"
        );
        is_deeply(
            $c->app->xcached->[2]->driver->status,
            [ 'get', 'set', 'get', 'get', 'expire' ],
            "driver log: 2"
        );
    };


    subtest 'set at now-10 with expiration time: 2 sec' => sub {
        for ( 0 .. $c->xcaches_num - 1 ) {
            $c->app->xcached->[$_]->driver->clear_status;
        }

        my ($result) = $c->xcache(
            key => $data_to_set,
            { t => $ts - 10, expire_in => 2, },
            sub {
                my ( $xc, $data, $ok ) = @_;

                is( $ok, 1, 'data set' );
                is_deeply( $data, [$data_to_set], 'data value' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'set' ],
                "driver log: $_"
            );
        }


        $result = $c->xcache(
            'key', undef,
            { t => $ts - 10 + 2 },
            sub {
                my ( $xc, $data, $ok ) = @_;
                is_deeply( $data, [$data_to_set],
                    'data value equal at t+2 (l0:ok l1:not used l2:not used)' );
                is( $ok, 1, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is( $result, 42, 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'set', ( $_ ? () : 'get' ) ],
                "driver log: $_"
            );
        }


        ($result) = $c->xcache(
            'key', undef,
            { t => $ts + 3 },
            sub {
                my ( $xc, $data, $ok ) = @_;
                is( $data, undef,
                    'data value equal at t+3 (l0:expired l1:expired l3:expired)'
                );
                is( $ok, !!0, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'set', ( $_ ? () : 'get' ), 'get', 'expire' ],
                "driver log: $_"
            );
        }
    };

    subtest expire => sub {

        # Set `key` with expiration time: t+2 sec
        for ( 0 .. $c->xcaches_num - 1 ) {
            $c->app->xcached->[$_]->driver->clear_status;
        }

        my ($result) = $c->xcache(
            key => $data_to_set,
            { t => $ts - 10, expire_in => 2, },
            sub {
                my ( $xc, $data, $ok ) = @_;

                is( $ok, 1, 'data set' );
                is_deeply( $data, [$data_to_set], 'data value' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'set' ],
                "driver log: $_"
            );
        }


        # Expire `key`
        $result = $c->xcache(
            'key', undef,
            { t => $ts - 10, expire_in => -1 },
            sub {
                my ( $xc, $data, $ok ) = @_;
                is( $data, undef, 'data value is undefined when `->expire`' );
                is( $ok,   1,     'expire status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is( $result, 42, 'cb expire result' );
        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'set', 'expire' ],
                "driver log: $_"
            );
        }

        # expire again
        ($result) = $c->xcache(
            'key', undef,
            { t => $ts - 10, expire_in => -1 },
            sub {
                my ( $xc, $data, $ok ) = @_;
                is( $data, undef,
                    'data value is undefined when `->expire` again' );
                is( $ok, !!0, 'expire again status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb expire again result' );
        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'set', 'expire', 'expire' ],
                "driver log (again): $_"
            );
        }

        # Get `key`
        ($result) = $c->xcache(
            key => undef,
            { t => $ts - 10 },
            sub {
                my ( $xc, $data, $ok ) = @_;

                is( $ok,   !!0,   'data get failed' );
                is( $data, undef, 'no data' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb get result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'set', 'expire', 'expire', 'get' ],
                "driver log (get after expire): $_"
            );
        }
    };
};

subtest 'xcache sub' => sub {
    my $x3 = sub {
        my $num = shift;

        return wantarray ? ( $num * 3, 'okay' ) : ( $num * 3 );
    };

    my $ts = time;
    my $c  = $t->app->build_controller;

    # always LIST context with provided cb
    subtest cache => sub {
        for ( 0 .. $c->xcaches_num - 1 ) {
            $c->app->xcached->[$_]->driver->clear_status;
        }

        my $result = $c->xcache(
            'key', undef,
            (
                driver => { t => $ts },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                ok( !defined($data), 'no `key` data yet' );
                is( $ok, !!0, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is( $result, 42, 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply( $c->app->xcached->[$_]->driver->status,
                ['get'], "driver log: $_" );
        }

        $result = $c->xcache(
            'key' => $x3 => [3],
            (
                driver => { t => $ts },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                is_deeply( $data, [ 9, 'okay' ], 'named data okay' );
                is( $ok, !!1, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is( $result, 42, 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'get', 'set' ],
                "driver log: $_"
            );
        }

        ($result) = $c->xcache(
            'key' => $x3 => [5],
            (
                driver => { t => $ts },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                is_deeply( $data, [ 9, 'okay' ], 'already cached data got' );
                is( $ok, !!1, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb result' );

        is_deeply(
            $c->app->xcached->[0]->driver->status,
            [ 'get', 'get', 'set', 'get' ],
            "driver log: 0"
        );
        for ( 1 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'get', 'set' ],
                "driver log: $_"
            );
        }


        ($result) = $c->xcache(
            'key' => $x3 => [5],
            (
                driver => { t => $ts + 2 },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                is_deeply( $data, [ 9, 'okay' ], 'named data got t+2' );
                is( $ok, !!1, 'result status t+2' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb result t+2' );

        is_deeply(
            $c->app->xcached->[0]->driver->status,
            [ 'get', 'get', 'set', 'get', 'get', 'expire', 'set' ],
            "driver log t+2: 0"
        );
        is_deeply(
            $c->app->xcached->[1]->driver->status,
            [ 'get', 'get', 'set', 'get' ],
            "driver log t+2: 1"
        );
        is_deeply(
            $c->app->xcached->[2]->driver->status,
            [ 'get', 'get', 'set' ],
            "driver log t+2: 2"
        );


        $result = $c->xcache(
            'key' => $x3 => [5],
            (
                driver => { t => $ts + 2 },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                is_deeply( $data, [ 9, 'okay' ], 'named data still okay' );
                is( $ok, !!1, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );

        is( $result, 42, 'cb result' );

        is_deeply(
            $c->app->xcached->[0]->driver->status,
            [ 'get', 'get', 'set', 'get', 'get', 'expire', 'set', 'get' ],
            "driver log still okay: 0"
        );
        is_deeply(
            $c->app->xcached->[1]->driver->status,
            [ 'get', 'get', 'set', 'get' ],
            "driver log still okay: 1"
        );
        is_deeply(
            $c->app->xcached->[2]->driver->status,
            [ 'get', 'get', 'set' ],
            "driver log still okay: 2"
        );
    };


    subtest expire => sub {
        for ( 0 .. $c->xcaches_num - 1 ) {
            $c->app->xcached->[$_]->driver->clear_status;
        }

        my $result = $c->xcache(
            'key', undef,
            (
                driver => { t => $ts, expire_in => 0 },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                ok( !defined($data), 'data expired' );
                is( $ok, !!1, 'expire result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is( $result, 42, 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply( $c->app->xcached->[$_]->driver->status,
                ['expire'], "driver log: $_" );
        }


        ($result) = $c->xcache(
            'key', undef,
            (
                driver => { t => $ts, expire_in => 0 },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                ok( !defined($data), 'data expired (already)' );
                is( $ok, !!0, 'expire again result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'expire', 'expire' ],
                "driver log: $_"
            );
        }


        ($result) = $c->xcache(
            'key', undef,
            (
                driver => { t => $ts },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                ok( !defined($data), 'no data (expired)' );
                is( $ok, !!0, 'status failed' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'expire', 'expire', 'get' ],
                "driver log: $_"
            );
        }


        $result = $c->xcache(
            'key' => $x3 => [3],
            (
                driver => { t => $ts },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                is_deeply( $data, [ 9, 'okay' ], 'named data cached' );
                is( $ok, !!1, 'cache status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is( $result, 42, 'cb result' );
        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'expire', 'expire', 'get', 'get', 'set' ],
                "driver log: $_"
            );
        }

        $result = $c->xcache(
            'key' => undef,
            (
                driver => { t => $ts + 4 },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                is( $data, undef, 'data expired' );
                is( $ok,   !!0,   'cache get status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is( $result, 42, 'cb result' );
        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'expire', 'expire', 'get', 'get', 'set', 'get', 'expire' ],
                "driver log: $_"
            );
        }
    };
};

subtest 'xcache method' => sub {
    my $ts = time;
    my $c  = $t->app->build_controller;


    # Cache
    subtest cache => sub {
        for ( 0 .. $c->xcaches_num - 1 ) {
            $c->app->xcached->[$_]->driver->clear_status;
        }

        my $result = $c->xcache(
            'key', undef,
            (
                driver => { t => $ts },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                ok( !defined($data), 'no `key` data yet' );
                is( $ok, !!0, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is( $result, 42, 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply( $c->app->xcached->[$_]->driver->status,
                ['get'], "driver log: $_" );
        }


        $result = $c->xcache(
            'key' => $t->app => 'x3' => [3],
            (
                driver => { t => $ts },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                is_deeply( $data, [ 9, 'okay' ], 'cache new data okay' );
                is( $ok, !!1, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is( $result, 42, 'cb result' );

        for ( 0 .. $c->xcaches_num - 1 ) {
            is_deeply(
                $c->app->xcached->[$_]->driver->status,
                [ 'get', 'get', 'set' ],
                "driver log: $_"
            );
        }


        ($result) = $c->xcache(
            'key' => $t->app => 'x3' => [5],
            (
                driver => { t => $ts },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                is_deeply( $data, [ 9, 'okay' ], 'already cached data got' );
                is( $ok, !!1, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );
        is_deeply( $result, [ 4, 2 ], 'cb result' );

        is_deeply(
            $c->app->xcached->[0]->driver->status,
            [ 'get', 'get', 'set', 'get' ],
            "driver log: 0"
        );
        is_deeply(
            $c->app->xcached->[1]->driver->status,
            [ 'get', 'get', 'set' ],
            "driver log: 1"
        );
        is_deeply(
            $c->app->xcached->[2]->driver->status,
            [ 'get', 'get', 'set' ],
            "driver log: 2"
        );


        $result = $c->xcache(
            'key' => $t->app => 'x3' => [5],
            (
                driver => { t => $ts + 2 },
                fn_key => 0,
            ),
            sub {
                my ( $xc, $data, $ok ) = @_;
                is_deeply( $data, [ 9, 'okay' ], 'named data still okay' );
                is( $ok, !!1, 'result status' );

                wantarray ? [ 4, 2 ] : 42;
            }
        );

        is( $result, 42, 'cb result' );

        is_deeply(
            $c->app->xcached->[0]->driver->status,
            [ 'get', 'get', 'set', 'get', 'get', 'expire', 'set' ],
            "driver log still okay: 0"
        );
        is_deeply(
            $c->app->xcached->[1]->driver->status,
            [ 'get', 'get', 'set', 'get' ],
            "driver log still okay: 1"
        );
        is_deeply(
            $c->app->xcached->[2]->driver->status,
            [ 'get', 'get', 'set' ],
            "driver log still okay: 2"
        );
    };
};

done_testing();
