use Test::More;

use strict;
use warnings;

use lib 't/lib';

use TestDriverDeffer;

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

my $default_expire = 2;

my $driver = TestDriverDeffer->new( speed => 1 );
ok(
    my $cached = MojoX::Cached->new(
        driver         => $driver,
        default_expire => $default_expire,
    ),
    'Cached created'
);

is( $cached->driver, $driver, 'driver ref' );

my $key1 = { data => [ 1, 2, 3 ] };
subtest set => sub {
    my $p      = Mojo::Promise->new;
    my $test_i = 0;
    Mojo::IOLoop->timer(
        0 => sub {
            $test_i++;
            my $t = time;
            is(
                $cached->set(
                    key1 => $key1,
                    {
                        expire_in => $default_expire * 2
                    },
                    sub {
                        $test_i++;
                        is( shift, $cached, 'instance' );

                        is_deeply( $_[0], $key1,
                            'set with default_expire * 2' );

                        ok( exists $driver->cache->{key1}, 'set key' );
                        is_deeply( $driver->cache->{key1}{value},
                            $key1, 'cached data' );

                        is(
                            $driver->cache->{key1}{expire_at},
                            $t + $default_expire * 2,
                            'default expire * 2'
                        );

                        is(
                            $cached->set(
                                key1 => $key1,
                                { t => $t },
                                sub {
                                    shift;

                                    is_deeply( $_[0], $key1, 'default set' );

                                    is(
                                        $driver->cache->{key1}{expire_at},
                                        $t + $default_expire,
                                        'default expire'
                                    );

                                    $p->resolve;
                                    return 'OK 1';
                                }
                            ),
                            1,
                            '->set OK'
                        );

                        return 'OK 2';
                    }
                ),
                1,
                '->set OK'
            );
            is( $test_i, 1, 'Test progress' );
        }
    );
    is( $test_i, 0, 'Test started' );
    $p->wait;
    is( $test_i, 2, 'Test done' );
};

done_testing();
