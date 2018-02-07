use Test::More;

use strict;
use warnings;

use Mojo::File;

note 'Test for callbacks';

use_ok('MojoX::Cached::Driver::Disk');

ok(
    my $driver = MojoX::Cached::Driver::Disk->new(
        dir        => Mojo::File::tempdir( CLEANUP => 1 ),
        files_mode => 0600,
    ),
    'create driver'
);


subtest 'get/set' => sub {
    $driver->set(
        key => { data => 'data' },
        sub {
            ok( @_, 'set' );

            is( shift(@_), $driver, 'driver' );
            is_deeply( $_[0],
                { value => { data => 'data' }, expire_at => undef },
                'set data' );


            is(
                $driver->get(
                    'key',
                    sub {
                        is( shift(@_), $driver, 'driver' );

                        my @data = @_;
                        is( ~~ @data, 1, 'get' );
                        is_deeply(
                            $data[0],
                            { value => { data => 'data' }, expire_at => undef },
                            '...data'
                        );

                        return "OK";
                    }
                ),
                'OK',
                '->get OK'
            );
        }
    );
};

subtest 'get/set with expire_in' => sub {
    my $time = time;

    $driver->set(
        key => { data => 'data with expiration' },
        1,
        sub {
            ok( @_, 'set' );

            is($driver->get(
                'key',
                sub {
                    my $driver = shift;
                    my @data   = @_;
                    is( ~~ @data, 1, 'get' );
                    is_deeply(
                        $data[0],
                        {
                            value     => { data => 'data with expiration' },
                            expire_at => $time + 1,
                        },
                        '...data'
                    );

                    note 'sleep...';
                    sleep(2);

                    is($driver->get(
                        'key',
                        sub {
                            shift;
                            my @data = @_;
                            is( ~~ @data, 0, 'expired' );

                            return 'OK';
                        }
                    ), 'OK', '->get OK');

                    return 'OK';
                }
            ), 'OK', '->get OK');
        }
    );
};

subtest 'expire' => sub {
    $driver->set(
        key => { data => 'data' },
        sub {
            ok( @_, 'set' );
            $driver->get(
                'key',
                sub {
                    shift;
                    my @data = @_;
                    is( ~~ @data, 1, 'get' );
                    is_deeply( $data[0],
                        { value => { data => 'data' }, expire_at => undef },
                        '...data' );

                    $driver->expire(
                        'key',
                        sub {
                            is( shift(@_), $driver, 'driver' );
                            is( $_[0],     1,       'expire success' );

                            $driver->get(
                                'key',
                                sub {
                                    shift;
                                    my @data = @_;
                                    is( ~~ @data, 0, 'expired' );
                                }
                            );

                            $driver->expire(
                                'key',
                                sub {
                                    shift;
                                    isnt( $_[0], 1, 'expire not success' );
                                }
                            );
                        }
                    );
                }
            );
        }
    );
};

subtest 'driver opts and flush' => sub {
    for ( 1 .. 5 ) {
        my $key = "key$_";
        subtest $key => sub {
            $driver->set(
                $key => { data => 'data', for => $key },
                sub {
                    ok( @_, 'set' );
                    $driver->get(
                        $key,
                        sub {
                            shift;
                            my @data = @_;
                            is( ~~ @data, 1, 'get' );
                            is_deeply(
                                $data[0],
                                {
                                    value => { data => 'data', for => $key },
                                    expire_at => undef
                                },
                                '...data'
                            );
                        }
                    );
                }
            );
        };
    }

    for my $is ( 1, 0 ) {
        subtest $is ? 'not flushed' : 'flushed' => sub {
            for ( 1 .. 5 ) {
                my $key = "key$_";
                $driver->get(
                    $key,
                    sub {
                        shift;
                        my @data = @_;
                        is( ~~ @data, $is,
                            "get $key. Found: " . ( $is ? 'yes' : 'no' ) );
                    }
                );
            }
        };
        $driver->flush(
            sub {
                ok( 1, 'flush' );
            }
        );
    }
};

done_testing();
