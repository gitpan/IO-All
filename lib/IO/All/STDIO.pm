package IO::All::STDIO;
use IO::All -Base;
use IO::File;

const type => 'stdio';

sub stdio {
    bless $self, __PACKAGE__;
    return $self->_init;
}

sub stdin {
    $self->open('<');
    return $self;
}

sub stdout {
    $self->open('>');
    return $self;
}

sub stderr {
    $self->open_stderr;
    return $self;
}

sub open {
    $self->is_open(1);
    my $mode = shift || $self->mode || '<';
    my $fileno = $mode eq '>'
    ? fileno(STDOUT)
    : fileno(STDIN);
    $self->io_handle(IO::File->new);
    $self->io_handle->fdopen($fileno, $mode);
    $self->set_binmode;
}

sub open_stderr {
    $self->is_open(1);
    $self->io_handle(IO::File->new);
    $self->io_handle->fdopen(fileno(STDERR), '>') ? $self : 0;
}

# XXX Add overload support

__DATA__

=head1 NAME 

IO::All::STDIO - STDIO Support for IO::All

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
