use strict;
use Test::More tests => 5;
use lib 't';
use IO_All_Test;

IO::Dumper->import;

my $hash = {
    red => 'square',
    yellow => 'circle',
    pink => 'triangle',
};

my $io = io('t/dump1')->dump($hash);
ok(-f 't/dump1');
ok($io->close);
ok(-s 't/dump1');
test_file_contents2('t/dump1', join '', <DATA>);
ok($io->unlink);

package IO::Dumper;
use IO::All '-base';
use Data::Dumper;

sub dump {
    my $self = shift;
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Sortkeys = 1;
    $self->print(Data::Dumper::Dumper(@_));
    return $self;
} 

package main;
__END__
$VAR1 = {
  'pink' => 'triangle',
  'red' => 'square',
  'yellow' => 'circle'
};
