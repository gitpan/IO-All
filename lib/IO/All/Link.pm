package IO::All::Link;
use IO::All::File -Base;

const type => 'link';

sub link {
    bless $self, __PACKAGE__;
    $self->name(shift) if @_;
    $self->_init;
}

sub readlink {
    IO::All->new(CORE::readlink($self->name));
}

sub symlink {
    my $target = shift;
    $self->assert_filepath if $self->_assert;
    CORE::symlink($target, $self->pathname);
}

sub AUTOLOAD {
    our $AUTOLOAD;
    (my $method = $AUTOLOAD) =~ s/.*:://;
    my $target = $self->target;
    unless ($target) {
        $self->throw("Can't call $method on symlink");
        return;
    }
    $target->$method(@_);
}

sub target {
    return *$self->{target} if *$self->{target};
    my %seen;
    my $link = $self;
    my $new;
    while ($new = $link->readlink) {
        my $type = $new->type or return;
        last if $type eq 'file';
        last if $type eq 'dir';
        return unless $type eq 'link';
        return if $seen{$new->name}++;
        $link = $new;
    }
    *$self->{target} = $new;
}

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
