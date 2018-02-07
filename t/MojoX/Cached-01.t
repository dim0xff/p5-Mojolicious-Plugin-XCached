use Test::More;

use strict;
use warnings;

use lib 't/lib';

use TestDriver;

note 'Test for callbacks';

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

my $key1 = { data => [ 1, 2, 3 ] };
subtest set => sub {
    is(
        $cached->set(
            key1 => $key1,
            $default_expire * 2,
            sub {
                is( shift, $cached, 'instance' );

                is_deeply( $_[0], $key1, 'set with default_expire * 2' );

                ok( exists $driver->cache->{key1}, 'set key' );
                is_deeply( $driver->cache->{key1}{value}, $key1,
                    'cached data' );

                is(
                    $driver->cache->{key1}{expire_at},
                    time + $default_expire * 2,
                    'default expire * 2'
                );

                is(
                    $cached->set(
                        key1 => $key1,
                        sub {
                            shift;

                            is_deeply( $_[0], $key1, 'default set' );

                            is(
                                $driver->cache->{key1}{expire_at},
                                time + $default_expire,
                                'default expire'
                            );

                            return 'OK 1';
                        }
                    ),
                    'OK 1',
                    '->set OK'
                );

                return 'OK 2';
            }
        ),
        'OK 2',
        '->set OK'
    );
};

subtest get => sub {
    is(
        $cached->get(
            'key1',
            sub {
                is( shift, $cached, 'instance' );
                my ($data) = @_;
                is_deeply( $data, $key1, 'retrieved data is equal to cached' );

                sleep( $default_expire + 1 );
                is(
                    $cached->get(
                        'key1',
                        sub {
                            shift;
                            my ($data) = @_;
                            is( $data, undef, 'data is expired' );

                            return 'OK 1';
                        }
                    ),
                    'OK 1',
                    '->get OK'
                );

                return 'OK 2';
            }
        ),
        'OK 2',
        '->get OK'
    );
};

subtest expire => sub {
    is(
        $cached->set(
            key1 => $key1,
            sub {
                shift;

                is_deeply( $_[0], $key1, 'data in cache' );

                is(
                    $cached->expire(
                        'key1',
                        sub {
                            is( shift, $cached, 'instance' );
                            my $status = shift;
                            is( $status, 1, 'expire' );
                            is(
                                $cached->get(
                                    'key1',
                                    sub {
                                        shift;
                                        my ($data) = @_;
                                        is( $data, undef, 'data is expired' );

                                        return 'OK 1';
                                    }
                                ),
                                'OK 1',
                                '->get OK'
                            );

                            return 'OK 2';
                        }
                    ),
                    'OK 2',
                    '->expire OK'
                );

                is(
                    $cached->expire(
                        'key1',
                        sub {
                            is( shift, $cached, 'instance' );
                            my $status = shift;
                            isnt( $status, 1, 'already expired' );

                            return 'OK 3';
                        }
                    ),
                    'OK 3',
                    '->set OK'
                );

                return 'OK';
            }
        ),
        'OK',
        '->set OK'
    );
};

subtest cached_sub => sub {
    for ( 1 .. 5 ) {
        my ( @value, $value );
        $cached->cached_sub(
            key => \&subroutine,
            [1],
            sub {
                is( shift, $cached, 'instance' );
                my @value = @_;
                is_deeply(
                    \@value,
                    [ 2, 'true' ],
                    "cached (cb/list): 1 / call: $_"
                );
            }
        );

        @value = $cached->cached_sub( key => \&subroutine, [1] );
        is_deeply( \@value, [ 2, 'true' ], "cached (list): 1 / call: $_" );

        $value = $cached->cached_sub( key => \&subroutine, [1] );
        is( $value, 2, "cached (scalar): 1 / call: $_" );

        $cached->cached_sub(
            key => \&subroutine,
            [2],
            sub {
                shift;
                my @value = @_;
                is_deeply(
                    \@value,
                    [ 4, 'true' ],
                    "cached (cb/list): 2 / call: $_"
                );
            }
        );

        @value = $cached->cached_sub( key => \&subroutine, [2] );
        is_deeply( \@value, [ 4, 'true' ], "cached (list): 2 / call: $_" );

        $value = $cached->cached_sub( key => \&subroutine, [2] );
        is( $value, 4, "cached (scalar): 2 / call: $_" );
    }

    is( subroutine_calls(), 4, 'only 4 cals for 30 caches' );
    is( scalar( keys %{ $driver->cache } ),
        4,
        '4 keys in cache for one key name, 2 diff context, 2 diff arguments' );
};

subtest cached_method => sub {
    my $obj = ThePackage->new;

    $cached->driver->flush;

    for ( 1 .. 5 ) {
        $cached->cached_method(
            o_3_2 => $obj => method => [ 3, 2 ],
            sub {
                is( shift, $cached, 'instance' );
                my @value = @_;
                is_deeply( \@value, [6], "cached (cb/list): 3*2 / call $_" );
            }
        );


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

    $cached->cached_method(
        o_3_2 => $obj => method => [ 3, 2 ],
        ( expire_in => 0 ),
        sub {
            is( shift, $cached, 'instance' );

            is( scalar( keys %{ $driver->cache } ),
                0, '... key expired (list)' );
        }
    );
};

subtest cached => sub {
    $driver->clear_status;
    $cached->cached(
        default => 'value',
        sub {
            is( my $cached = shift, $cached, 'instance' );
            my ($value) = @_;
            is( $value, 'value', 'cached->set' );

            $cached->cached(
                default => 'value',
                sub {
                    is( my $cached = shift, $cached, 'instance' );
                    my ($value) = @_;
                    is( $value, 'value', 'cached->set' );
                    is_deeply( $driver->status, [ 'get', 'set', 'get' ],
                        'set status' );
                }
            );
        }
    );

    $driver->clear_status;
    $cached->cached(
        'default',
        sub {
            is( my $cached = shift, $cached, 'instance' );
            my ($value) = @_;

            is( $value, 'value', 'cached->set' );
            is_deeply( $driver->status, ['get'], 'get status' );
        }
    );


    $driver->clear_status;
    $cached->cached(
        'default',
        undef, 0,
        sub {
            is( my $cached = shift, $cached, 'instance' );
            my ($status) = @_;

            is( $status, !!1, 'cached->expire 1' );

            $cached->cached(
                'default',
                undef, 0,
                sub {
                    is( my $cached = shift, $cached, 'instance' );
                    my ($status) = @_;

                    is( $status, !!0, 'cached->expire 0' );
                    is_deeply( $driver->status, [ 'expire', 'expire' ],
                        'get status' );
                }
            );
        }
    );


    subroutine_calls(0);
    $driver->clear_status;
    for my $n ( 1 .. 5 ) {
        $cached->cached(
            subroutine => \&subroutine => [5],
            sub {
                is( my $cached = shift, $cached, 'instance' );
                my (@value) = @_;
                is_deeply(
                    \@value,
                    [ 10, 'true' ],
                    "cb/list cached->subroutine / call $n"
                );
            }
        );
    }
    is_deeply(
        $driver->status,
        [ 'get', 'set', ('get') x 4 ],
        'cache call status'
    );


    my $obj = ThePackage->new;
    $driver->clear_status;
    for my $n ( 1 .. 5 ) {
        $cached->cached_method(
            o_3_2 => $obj => method => [ 3, 2 ],
            sub {
                is( my $cached = shift, $cached, 'instance' );
                my (@value) = @_;
                is_deeply( \@value, [6], "cached (cb/list): 3*2 / call $n" );
            }
        );
    }
    is( $obj->{calls}, 1, 'only one method call' );

    for my $expire ( !!1, !!0 ) {
        $cached->cached_method(
            o_3_2 => $obj => method => [ 3, 2 ],
            ( expire_in => 0 ),
            sub {
                is( my $cached = shift, $cached, 'instance' );
                is_deeply( \@_, [$expire], "expire" );
            }
        );
    }

    is_deeply(
        $driver->status,
        [ 'get', 'set', ('get') x 4, ('expire') x 2 ],
        'cache call status'
    );
};

subtest fn_key => sub {
    $driver->clear_status;

    my $obj = ThePackage->new;

    for my $t (
        [
            'use_fn_key => 1',
            1,
            [
                'get', 'set', 'get', 'get', 'set',    # scalar sub
                'get', 'get', 'get',            # list sub
                'get', 'set', 'get', 'get',     # scalar obj
                'get', 'get', 'get',            # list obj
            ]
        ],

        [
            'use_fn_key => 0',
            0,
            [
                'get', 'set', 'get', 'set', 'get',    # scalar sub
                'get', 'get', 'get',            # list sub
                'get', 'get', 'set', 'get',     # scalar obj
                'get', 'get', 'get',            # list obj
            ],
        ],
        )
    {
        subtest $t->[0] => sub {
            $cached->use_fn_key( $t->[1] );
            $driver->flush;
            $driver->clear_status;

            #<<< no tidy
            $cached->cached_sub( key => \&subroutine, [1], sub {} );
            $cached->cached_sub( key => \&subroutine, [1], fn_key => 1, sub {} );
            $cached->cached_sub( key => \&subroutine, [1], fn_key => 0, sub {} );

            () = $cached->cached_sub( key => \&subroutine, [1], sub {} );
            () = $cached->cached_sub( key => \&subroutine, [1], fn_key => 1, sub {} );
            () = $cached->cached_sub( key => \&subroutine, [1], fn_key => 0, sub {} );

            $cached->cached_method( key => $obj => method => [3, 2], sub {} );
            $cached->cached_method( key => $obj => method => [3, 2], fn_key => 1, sub {} );
            $cached->cached_method( key => $obj => method => [3, 2], fn_key => 0, sub {} );

            () = $cached->cached_method( key => $obj => method => [3, 2], sub {} );
            () = $cached->cached_method( key => $obj => method => [3, 2], fn_key => 1, sub {} );
            () = $cached->cached_method( key => $obj => method => [3, 2], fn_key => 0, sub {} );
            #>>>

            my $sub_list_key = $cached->fn_key( 'LIST:key', [1] );
            my $obj_list_key = $cached->fn_key( 'LIST:key->method', [ 3, 2 ] );

            is_deeply( [ sort keys %{ $driver->cache } ],
                [ sort 'key', $sub_list_key, $obj_list_key ] );

            is_deeply( $driver->status, $t->[2], 'cache call status' );
        };
    }
};

done_testing();
