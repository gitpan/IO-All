use inc::Module::Install;

name('IO-All');
author('Brian Ingerson <ingy@cpan.org>');
abstract('IO::All of it to Graham and Damian');
license('perl');
version_from('lib/IO/All.pm');

requires(qw(
    perl 5.6.1
    Spiffy 0.16
    Filter::Util::Call 0
    Tie::File 0.96
));
clean_files('t/output/*');

check_nmake();

&WriteAll();
