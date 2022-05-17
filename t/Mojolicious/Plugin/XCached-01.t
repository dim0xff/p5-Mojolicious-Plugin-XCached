use Mojo::Base -strict;

use lib 't/lib';

use Test::More;
use Test::Mojo;

subtest 'index' => sub {
    my $t = Test::Mojo->new('TestApp');

    my $r;
    my $now = time;

    $r = $t->get_ok( '/?t=123&now=' . $now )->status_is(200);
    $r->content_like(
        qr|
        test/index\s123/123
        \s+
        test/include\s123
        \s+
        content_for\stest/index\s123
        \s+
        content_for\stest/include\s123
        \s+
        content_with\stest/include\s123
    |x
    );

    $now += 2;
    $r = $t->get_ok( '/?t=456&now=' . $now )->status_is(200);
    $r->content_like(
        qr|
        test/index\s123/456
        \s+
        test/include\s123
        \s+
        content_for\stest/index\s456
        \s+
        content_for\stest/include\s123
        \s+
        content_with\stest/include\s123
    |x
    );

    $now += 2;
    $r = $t->get_ok( '/?t=789&now=' . $now )->status_is(200);
    $r->content_like(
        qr|
        test/index\s789/789
        \s+
        test/include\s123
        \s+
        content_for\stest/index\s789
        \s+
        content_for\stest/include\s123
        \s+
        content_with\stest/include\s123
    |x
    );
};


done_testing();
