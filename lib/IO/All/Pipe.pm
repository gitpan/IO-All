package IO::All::Pipe;
use strict;
use warnings;
use IO::All '-Base';
use IO::File;

const type => 'pipe';

sub pipe {
    bless $self, __PACKAGE__;
    $self->name(shift) if @_;
    return $self->_init;
}

sub assert_open {
    return if $self->is_open;
    $self->mode(shift) unless $self->mode;
    $self->open;
}

sub open {
    $self->is_open(1);
    require IO::Handle;
    $self->io_handle(IO::Handle->new)
      unless defined $self->io_handle;
    my $command = $self->name;
    $command =~ s/(^\||\|$)//;
    my $mode = shift || $self->mode || '<';
    my $pipe_mode = 
      $mode eq '>' ? '|-' :
      $mode eq '<' ? '-|' :
      $self->throw("Invalid usage mode '$mode' for pipe");
    CORE::open($self->io_handle, $pipe_mode, $command);
    $self->set_binmode;
}

my %mode_msg = (
    '>' => 'output',
    '<' => 'input',
    '>>' => 'append',
);
sub open_msg {
    my $name = defined $self->name
      ? " '" . $self->name . "'"
      : '';
    my $direction = defined $mode_msg{$self->mode}
      ? ' for ' . $mode_msg{$self->mode}
      : '';
    return qq{Can't open pipe$name$direction:\n$!};
}

1;

__DATA__

=head1 NAME 

IO::All::Pipe - Pipe Support for IO::All

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
