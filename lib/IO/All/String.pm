package IO::All::String;
use IO::All -Base;
use IO::String;

const type => 'string';
proxy 'string_ref';

sub string {
    bless $self, __PACKAGE__;
    $self->_init;
}

sub open {
    $self->io_handle(IO::String->new);
    $self->set_binmode;
}

__DATA__

=head1 NAME 

IO::All::String - String IO Support for IO::All

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
