package IO::All::Link;
use strict;
use warnings;
use IO::All::File '-Base';

const type => 'link';

sub link {
    bless $self, __PACKAGE__;
    $self->name(shift);
    $self->_init;
}

sub readlink {
    $self->new(CORE::readlink($self->name));
}

sub symlink {
    my $target = shift;
    $self->assert_filepath if $self->_assert;
    CORE::symlink($target, $self->pathname);
}

1;

__DATA__

=head1 NAME 

IO::All::Link - Symbolic Link Support for IO::All

=head1 SYNOPSIS

See L<IO::All>.

=head1 DESCRIPTION

=head1 AUTHOR

Brian Ingerson <INGY@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2004. Brian Ingerson. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
