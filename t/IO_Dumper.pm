package IO_Dumper;
use strict;
use IO::All '-Base';

package IO::All::Filesys;
use Data::Dumper;
sub dump {
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Sortkeys = 1;
    $self->print(Data::Dumper::Dumper(@_));
    return $self;
} 
