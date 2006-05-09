use inc::Module::Install;

name        'IO-All';
all_from    'lib/IO/All.pm';

requires    perl => '5.6.1';

clean_files 't/output/';

WriteAll;
