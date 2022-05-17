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


=method get ($key, \%options?, \&cb?)

Get cached value by C<$key>.
Optional driver C<\%options> could be passed.
Optional callback C<\&cb> could be added for non-blocking C<get>.

Driver B<MUST> support key C<t> in C<\%options> which represents current time.
If there are no C<t> key, then current time (via C<time()> will be used).

I<Success> means I<data is cached and not expired yet>.

On B<success returns> C<\%result>:

    {
        value     => ..., # cached data
        expire_at => ..., # expiration unixtime

        # Also could contain driver specified data
        ...
    }

On B<fail returns> nothing.

If callback is provided, then returns data from callback call.
Callback will be called as:

    # On success
    $cb->( $driver, \%result )

    # On fail
    $cb->( $driver )

I<Note about expiration.>
If data is cached but expired, then C<-E<gt>expire> will be called
for provided key.

=method set ($key, $data, \%options?, \&cb?)

Cache C<$data> by C<$key>.
Optional driver C<\%options> could be passed.
Optional callback C<\&cb> could be added as last argument for
non-blocking C<set>.

Driver B<MUST> support key C<t> in C<\%options> which represents current time.
If there are no C<t> key, then current time (via C<time()> will be used).

Driver B<MUST> support key C<expire_in> in C<\%options> which represents
expiration time in seconds (default L</expire_in>).

I<Success> means I<data is successfuly cached>.

On B<success returns> like-L</get> HASH

On B<fail returns> nothing.

If callback is provided, then returns data from callback call.
Callback will be called as:

    # On success
    $cb->( $driver, \%result )

    # On fail
    $cb->( $driver )

=method expire ($key, \%options?, \&cb?)

Expire cached data by C<$key>. B<Returns> expire status:
success(true value) or fail(false value).

Optional driver C<\%options> could be passed.
Optional callback C<\&cb> could be added as last argument for
non-blocking C<expire>.

I<Success> means I<data was found and removed from cache>.

If callback is provided, then returns data from callback call.
Expire status will be passed as second argument:

    # On success
    $cb->( $driver, 1 )

    # On fail
    $cb->( $driver, !!0 )

=method flush(\%options?, \&cb?)

Clears cache. B<Returns> nothing.

Optional driver C<\%options> could be passed.
Optional callback C<\&cb> could be added as last argument for
non-blocking C<flush>. Callback will be fired once cache is flushed.

Data returned from callback will be returned to caller. Callback will be called as:

    $cb->( $driver )
