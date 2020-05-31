package MojoX::Cached::Driver;

# ABSTRACT: XCached driver superclass/interface

use Mojo::Base -base;

has 'expire_in';

sub get    {...}
sub set    {...}
sub expire {...}
sub flush  {...}

1;

__END__

=head1 DESCRIPTION

Use this module as base to create your own XCached drivers

Driver must support non-blocking interface, but non-blocking features
are not required. All callbacks will get driver instance as first argument.

Next methods have to be implemented:

=attr expire_in

Default expiration time in seconds for driver.

Default is C<undef> (cache forever).


=method get ($key, \%opts?, $cb?)

Get cached value by C<$key>.
Optional driver options C<\%opts> could be passed.
Optional callback C<$cb> could be added for non-blocking C<get>.

Driver MUST support key C<t> in C<\%opts> which represents current time.
If there are no C<t> key, then current time (via C<time()> will be used).

On success returns C<\%result>:

    {
        value     => ..., # cached data
        expire_at => ..., # expiration unixtime

        # Also could contain driver specified data
        ...
    }

On fail returns nothing.

If callback is provided, then returns data from callback call.
Callback will be called as:

    # On success
    $cb->( $driver, \%result )

    # On fail
    $cb->( $driver )


=method set ($key, $data, \%opts?, $cb?)

Cache C<$data> by C<$key>.
Optional driver options C<\%opts> could be passed.
Optional callback C<$cb> could be added as last argument for
non-blocking C<set>.

Driver MUST support key C<t> in C<\%opts> which represents current time.
If there are no C<t> key, then current time (via C<time()> will be used).

Driver MUST support key C<expire_in> in C<\%opts> which represents
expiration time in seconds (default L</expire_in>).

On success returns like-L</get> HASH, otherwise returns nothing.

If callback is provided, then returns data from callback call.
On success HASH will be passed as second argument to callback.

=method expire ($key, $cb?)

Expire cached data by C<$key>. Returns expire status.

Optional callback C<$cb> could be added as last argument for
non-blocking C<expire>.
Expire status will be passed as second argument.
If callback is provided, then returns data from callback call.

=method flush($cb?)

Clear cache. Returns nothing.

Optional callback C<$cb> could be added as last argument for
non-blocking C<flush>. Will be fired once cache is flushed.
Data returned from callback will be returned to caller.
