use lib 't', 'lib';
use strict;
use warnings;
use Test::More tests => 5;
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

my $VAR1;
my $a = do 't/dump1';
my $b = eval join('',<DATA>);
is_deeply($a,$b);

ok($io->unlink);

package IO::Dumper;
use IO::All '-base';
use Data::Dumper;

sub dump {
    my $self = shift;
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
