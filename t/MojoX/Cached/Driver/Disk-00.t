use Test::More;

use strict;
use warnings;

use Mojo::File;

note 'Test for no callbacks';

use_ok('MojoX::Cached::Driver::Disk');

ok(
    my $driver = MojoX::Cached::Driver::Disk->new(
        dir        => Mojo::File::tempdir( CLEANUP => 1 ),
        files_mode => 0600,
    ),
    'create driver'
);

subtest 'get/set' => sub {
    ok( $driver->set( key => { data => 'data' } ), 'set' );
    my @data = $driver->get('key');
    is( ~~ @data, 1, 'get' );
    is_deeply( $data[0], { value => { data => 'data' }, expire_at => undef },
        '...data' );
};

subtest 'get/set with expire_in' => sub {
    my $time = time;
    ok(
        $driver->set(
            key => { data => 'data with expiration' },
            {
                t         => $time,
                expire_in => 1,
            }
        ),
        'set'
    );
    my @data = $driver->get('key');
    is( ~~ @data, 1, 'get' );
    is_deeply(
        $data[0],
        {
            value     => { data => 'data with expiration' },
            expire_at => $time + 1,
        },
        '...data'
    );

    @data = $driver->get( 'key', {t => $time + 2 });
    is( ~~ @data, 0, 'expired' );
};

subtest 'expire' => sub {
    ok( $driver->set( key => { data => 'data' } ), 'set' );
    my @data = $driver->get('key');
    is( ~~ @data, 1, 'get' );
    is_deeply( $data[0], { value => { data => 'data' }, expire_at => undef },
        '...data' );

    is( $driver->expire('key'), 1, 'expire success' );

    @data = $driver->get('key');
    is( ~~ @data, 0, 'expired' );

    isnt( $driver->expire('key'), 1, 'expire not success' );
};

subtest 'driver opts and flush' => sub {
    for ( 1 .. 5 ) {
        my $key = "key$_";
        subtest $key => sub {
            ok( $driver->set( $key => { data => 'data' } ), 'set' );
            my @data = $driver->get($key);
            is( ~~ @data, 1, 'get' );
            is_deeply( $data[0],
                { value => { data => 'data' }, expire_at => undef },
                '...data' );
            }
    }

    for my $is ( 1, 0 ) {
        subtest $is ? 'not flushed' : 'flushed' => sub {
            for ( 1 .. 5 ) {
                my $key  = "key$_";
                my @data = $driver->get($key);
                is( ~~ @data, $is,
                    "get $key. Found: " . ( $is ? 'yes' : 'no' ) );
            }
        };
        note 'flush';
        $driver->flush;
    }
};

done_testing();
