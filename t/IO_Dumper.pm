package IO_Dumper;
use strict;
use IO::All '-base';
use Data::Dumper;

sub dump {
    my $self = shift;
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Sortkeys = 1;
    $self->print(Data::Dumper::Dumper(@_));
    return $self;
} 

1;
