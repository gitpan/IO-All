package IO::All;
use strict;
use warnings;
use 5.006_001;
our $VERSION = '0.21';
use Spiffy 0.16 qw(-Base !field);
use Fcntl qw(:DEFAULT :flock);
use Symbol();
use File::Spec();
our @EXPORT = qw(io);

spiffy_constructor 'io';

#===============================================================================
# Private Accessors
#===============================================================================
sub field;
const _domain_default => 'localhost';
field _binary => undef;
field _dbm_list => [];
field _handle => undef;
field _listen => undef;
field _mldbm => 0;
field _separator => $/;
field _serializer => 'Data::Dumper';
field _tied_file => undef;

#===============================================================================
# Public Accessors
#===============================================================================
sub chain;
chain block_size => 1024;
chain domain => undef;
chain errors => undef;
chain filter => undef;
field io_handle => undef;
field is_open => 0;
field is_stdio => 0;
chain mode => undef;
chain name => undef;
chain perms => undef;
chain port => undef;
field type => '';

#===============================================================================
# Chainable option methods (write only)
#===============================================================================
sub option;
option 'assert';
option 'autoclose' => 1;
option 'backwards';
option 'chomp';
option 'confess';
option 'deep';
option 'fork';
option 'lock';
option 'rdonly';
option 'rdwr';
option 'sort';

#===============================================================================
# IO::Handle proxy methods
#===============================================================================
sub proxy; 
proxy 'autoflush';
proxy 'eof';
proxy 'fileno';
proxy 'stat';
proxy 'string_ref';
proxy 'tell';
proxy 'truncate';

#===============================================================================
# IO::Handle proxy methods that open the handle if needed
#===============================================================================
sub proxy_open; 
proxy_open print => '>';
proxy_open printf => '>';
proxy_open sysread => O_RDONLY;
proxy_open syswrite => O_CREAT | O_WRONLY;
proxy_open seek => '+<';
proxy_open 'getc';
proxy_open 'recv';
proxy_open 'send';

#===============================================================================
# Configuration Option Methods
#===============================================================================
sub dbm {
    $self->_dbm_list([@_]);
    return $self;
}

sub mldbm {
    $self->_mldbm(1);
    my ($serializer) = grep { /^(Storable|Data::Dumper|FreezeThaw)$/ } @_;
    $self->_serializer($serializer) if defined $serializer;
    my @dbm_list = grep { not /^(Storable|Data::Dumper|FreezeThaw)$/ } @_;
    $self->_dbm_list([@dbm_list]);
    return $self;
}

sub separator {
    $self->_separator(@_ ? shift(@_) : "\n");
    return $self;
}

#===============================================================================
# Object creation and setup methods
#===============================================================================
sub new {
    my $new = bless Symbol::gensym(), ref($self) || $self;
    $new->_copy_from($self) if ref($self);
    my $name = shift;
    return $new->_init unless defined $name;
    return $new->handle($name)
      if ref $name or ref(\ $name) eq 'GLOB';
    return $new->stdio if $name eq '-';
    return $new->stderr if $name eq '=';
    return $new->temp if $name eq '?';
    return $new->string if $name eq '$';
    return $new->socket($name) if $name =~ /^[\w\-\.]*:\d{1,5}$/;
    return $new->pipe($name) 
      if $name =~ s/^\s*\|\s*// or $name =~ s/\s*\|\s*$//;
    return $new->file($name) if -f $name;
    return $new->dir($name) if -d $name;
    return $new->link($name) if -l $name ;
    $new->name($name);
    $new->_init;
}

sub _copy_from {
    my $other = shift;
    for (keys(%{*$other})) {
        # XXX Need to audit exclusions here
        next if /^(handle|io_handle)$/;
        *$self->{$_} = *$other->{$_};
    }
}

sub stdio {
    $self->is_stdio(1);
    return $self->_init;
}

sub stdin {
    $self->open_stdio('<');
    $self->is_stdio(1);
    $self->is_open(1);
    return $self;
}

sub stdout {
    $self->open_stdio('>');
    $self->is_stdio(1);
    $self->is_open(1);
    return $self;
}

sub stderr {
    $self->open_stderr;
    $self->is_stdio(1);
    $self->is_open(1);
    return $self;
}

sub string {
    $self->type('string');
    return $self->_init;
}

sub temp {
    require IO::File;
    my $temp_file = IO::File::new_tmpfile()
      or $self->throw("Can't create temporary file");
    $self->io_handle($temp_file);
    $self->error_check;
    $self->autoclose(0);
    $self->is_open(1);
    return $self;
}

sub handle {
    $self->_handle(shift) if @_;
    return $self->_init;
}

sub file {
    require IO::File;
    $self->name(shift) if @_;
    $self->type('file');
    return $self->_init;
}

sub dir {
    require IO::Dir;
    $self->name(shift) if @_;
    $self->type('dir');
    return $self->_init;
}

sub socket {
    $self->name(shift) if @_;
    $self->type('socket');
    return $self->_init;
}

sub link {
    $self->name(shift) if @_;
    $self->type('link');
    return $self->_init;
}

sub pipe {
    $self->name(shift) if @_;
    $self->type('pipe');
    return $self->_init;
}

sub file_handle {
    $self->_handle(shift) if @_;
    $self->type('file');
    return $self->_init;
}

sub dir_handle {
    $self->_handle(shift) if @_;
    $self->type('dir');
    return $self->_init;
}

sub socket_handle {
    $self->_handle(shift) if @_;
    $self->type('socket');
    return $self->_init;
}

sub _init {
    $self->io_handle(undef);
    $self->is_open(0);
    return $self;
}

#===============================================================================
# Tie Interface
#===============================================================================
sub tie { 
    tie *$self, $self; 
    return $self;
}

sub TIEHANDLE() {
    return $_[0] if ref $_[0];
    my $class = shift;
    my $self = bless Symbol::gensym(), $class;
    $self->init(@_);
}

sub READLINE() {
    goto &getlines if wantarray;
    goto &getline;
}

sub DESTROY {
    no warnings;
    unless ( $^V and $^V lt v5.8.0 ) {
        untie *$self if tied *$self;
    }
}

sub BINMODE { 
    binmode *$self->io_handle;
}

{
    no warnings;
    *GETC   = \&getc;
    *PRINT  = \&print;
    *PRINTF = \&printf;
    *READ   = \&read;
    *WRITE  = \&write;
    *SEEK   = \&seek;
    *TELL   = \&getpos;
    *EOF    = \&eof;
    *CLOSE  = \&close;
    *FILENO = \&fileno;
}

#===============================================================================
# Stat Methods
#===============================================================================
sub device    { my $x = (stat($self->io_handle || $self->name))[0] }
sub inode     { my $x = (stat($self->io_handle || $self->name))[1] }
sub modes     { my $x = (stat($self->io_handle || $self->name))[2] }
sub nlink     { my $x = (stat($self->io_handle || $self->name))[3] }
sub uid       { my $x = (stat($self->io_handle || $self->name))[4] }
sub gid       { my $x = (stat($self->io_handle || $self->name))[5] }
sub device_id { my $x = (stat($self->io_handle || $self->name))[6] }
sub size      { my $x = (stat($self->io_handle || $self->name))[7] }
sub atime     { my $x = (stat($self->io_handle || $self->name))[8] }
sub mtime     { my $x = (stat($self->io_handle || $self->name))[9] }
sub ctime     { my $x = (stat($self->io_handle || $self->name))[10] }
sub blksize   { my $x = (stat($self->io_handle || $self->name))[11] }
sub blocks    { my $x = (stat($self->io_handle || $self->name))[12] }

#===============================================================================
# File::Spec Interface
#===============================================================================
sub canonpath {
    File::Spec->canonpath($self->name);
}

sub catdir {
    $self->new->dir(File::Spec->catdir(@_));
}

sub catfile {
    $self->new->file(File::Spec->catfile(@_));
}

sub join {
    $self->catfile(@_);
}

sub curdir {
    $self->new->dir(File::Spec->curdir);
}

sub devnull {
    $self->new->file(File::Spec->devnull);
}

sub rootdir {
    $self->new->dir(File::Spec->rootdir);
}

sub tmpdir {
    $self->new->dir(File::Spec->tmpdir);
}

sub updir {
    $self->new->dir(File::Spec->updir);
}

sub case_tolerant {
    File::Spec->case_tolerant;
}

sub is_absolute {
    File::Spec->file_name_is_absolute($self->name);
}

sub path {
    map {
        $self->new->dir($_);
    } File::Spec->path;
}

sub splitpath {
    File::Spec->splitpath($self->name);
}

sub splitdir {
    File::Spec->splitdir($self->name);
}

sub catpath {
    $self->new(File::Spec->catpath(@_));
}

sub abs2rel {
    File::Spec->abs2rel($self->name, @_);
}

sub rel2abs {
    File::Spec->rel2abs($self->name, @_);
}

#===============================================================================
# Public IO Action Methods
#===============================================================================
sub accept {
    use POSIX ":sys_wait_h";
    sub REAPER {
        while (waitpid(-1, WNOHANG) > 0) {}
        $SIG{CHLD} = \&REAPER;
    }
    local $SIG{CHLD};
    $self->_listen(1);
    $self->assert_open_socket;
    my $server = $self->io_handle;
    my $socket; 
    while (1) {
        $socket = $server->accept;
        last unless $self->_fork;
        next unless defined $socket;
        $SIG{CHLD} = \&REAPER;
        my $pid = CORE::fork;
        $self->throw("Unable to fork for IO::All::accept")
          unless defined $pid;
        last unless $pid;
        close $socket;
        undef $socket;
    }
    close $server;
    my $io = ref($self)->new->socket_handle($socket);
    $io->io_handle($socket);
    $io->is_open(1);
    return $io;
}

sub All {
    $self->all(0);
}

sub all {
    my $depth = @_ ? shift(@_) : $self->_deep ? 0 : 1;
    my @all;
    my $last = 1;
    while (my $io = $self->next) {
        push @all, $io;
        push(@all, $io->all($depth - 1)), $last = 0
          if $depth != 1 and $io->is_dir;
    }
    @all = grep {&{$self->filter}} @all
      if $self->filter;
    return @all unless $last and $self->_sort;
    return sort {$a->name cmp $b->name} @all;
}

sub All_Dirs {
    $self->all_dirs(0);
}

sub all_dirs {
    grep {$_->is_dir} $self->all(@_);
}

sub All_Files {
    $self->all_files(0);
}

sub all_files {
    grep {$_->is_file} $self->all(@_);
}

sub All_Links {
    $self->all_links(0);
}

sub all_links {
    grep {$_->is_link} $self->all(@_);
}

sub append {
    $self->assert_open('>>');
    $self->print(@_);
}

sub appendln {
    $self->assert_open('>>');
    $self->println(@_);
}

sub binary {
    return binmode($self->io_handle)
      if $self->is_open;
    $self->_binary(1);
    return $self;
}

sub buffer {
    if (not @_) {
        *$self->{buffer} = do {my $x = ''; \ $x}
          unless exists *$self->{buffer};
        return *$self->{buffer};
    }
    my $buffer_ref = ref($_[0]) ? $_[0] : \ $_[0];
    $$buffer_ref = '' unless defined $$buffer_ref;
    *$self->{buffer} = $buffer_ref;
    return $self;
}

sub clear {
    my $buffer = *$self->{buffer};
    $$buffer = '';
    return $self;
}

sub close {
    return unless $self->is_open;
    $self->is_open(0);
    $self->shutdown
      if $self->is_socket;
    my $io_handle = $self->io_handle;
    $self->unlock;
    $self->io_handle(undef);
    $self->mode(undef);
    if (my $tied_file = $self->_tied_file) {
        if (ref($tied_file) eq 'ARRAY') {
            untie @$tied_file;
        }
        else {
            untie %$tied_file;
        }
        $self->_tied_file(undef);
        return 1;
    }
    $io_handle->close(@_);
}

sub filename {
    my $filename;
    (undef, undef, $filename) = $self->splitpath;
    return $filename;
}

sub filepath {
    my ($volume, $path) = $self->splitpath;
    return File::Spec->catpath($volume, $path);
}

sub getline {
    return $self->getline_backwards
      if $self->_backwards;
    $self->assert_open('<');
    my $line;
    {
        local $/ = @_ ? shift(@_) : $self->_separator;
        $line = $self->io_handle->getline;
        chomp($line) if $self->_chomp;
    }
    $self->error_check;
    return defined $line
    ? $line
    : $self->_autoclose && $self->close && undef || 
      undef;
}

sub getlines {
    return $self->getlines_backwards
      if $self->_backwards;
    $self->assert_open('<');
    my @lines;
    {
        local $/ = @_ ? shift(@_) : $self->_separator;
        @lines = $self->io_handle->getlines;
        if ($self->_chomp) {
            chomp for @lines;
        }
    }
    $self->error_check;
    return (@lines) or
           $self->_autoclose && $self->close && () or
           ();
}

sub is_dir {
    ($self->type || '') eq 'dir';
}

sub is_file {
    ($self->type || '') eq 'file';
}

sub is_link {
    ($self->type || '') eq 'link';
}

sub is_socket {
    ($self->type || '') eq 'socket';
}

sub is_string {
    ($self->type || '') eq 'string';
}

sub length {
    length(${$self->buffer});
}

sub mkdir {
    my @options = $self->perms ? ($self->perms) : ();
    mkdir($self->name, @options);
}

sub mkpath {
    require File::Path;
    File::Path::mkpath($self->name, @_);
}

sub next {
    $self->assert_open_dir;
    my $name = '.'; 
    while ($name =~ /^\.{1,2}$/) {
        $name = $self->io_handle->read;
        unless (defined $name) {
            $self->close;
            return;
        }
    }
    return IO::All->new(File::Spec->catfile($self->name, $name));
}

sub open {
    return $self if $self->is_open;
    $self->is_open(1);
    return $self->open_string(@_) if $self->is_string;
    return $self->open_stdio(@_) if $self->is_stdio;
    my ($mode, $perms) = @_;
    $self->mode($mode) if defined $mode;
    $self->mode('<') unless defined $self->mode;
    $self->perms($perms) if defined $perms;
    my @args;
    unless ($self->is_dir) {
        push @args, $self->mode;
        push @args, $self->perms if defined $self->perms;
    }
    if (defined $self->name) {
        $self->open_name($self->name, @args);
    }
    elsif (defined $self->_handle and
           not $self->io_handle->opened
          ) {
        # XXX Not tested
        $self->io_handle->fdopen($self->_handle, @args);
    }
    binmode($self->io_handle) 
      if $self->_binary;
    return $self;
}

sub println {
    $self->print(map {/\n\z/ ? ($_) : ($_, "\n")} @_);
}

sub read {
    $self->assert_open('<');
    my $length = (@_ or $self->type eq 'dir')
    ? $self->io_handle->read(@_)
    : $self->io_handle->read(
        ${$self->buffer}, 
        $self->block_size, 
        $self->length,
    );
    $self->error_check;
    return $length || $self->_autoclose && $self->close && 0;
}

{
    no warnings;
    *readline = \&getline;
}

sub readlink {
    $self->new(readlink($self->name));
}

sub rename {
    my $new = shift;
    rename($self->name, "$new")
      ? UNIVERSAL::isa($new, 'IO::All')
        ? $new
        : $self->new($new)
      : undef;
}

sub rmdir {
    rmdir $self->name;
}

sub rmtree {
    require File::Path;
    File::Path::rmtree($self->name, @_);
}

sub scalar {
    $self->assert_open('<');
    local $/;
    my $scalar = $self->io_handle->getline;
    $self->error_check;
    $self->_autoclose && $self->close;
    return $scalar;
}

sub shutdown {
    my $how = @_ ? shift : 2;
    $self->io_handle->shutdown(2);
}

sub slurp {
    my $slurp = $self->scalar;
    return $slurp unless wantarray;
    my $separator = $self->_separator;
    if ($self->_chomp) {
        local $/ = $separator;
        map {chomp; $_} split /(?<=\Q$separator\E)/, $slurp;
    }   
    else {
        split /(?<=\Q$separator\E)/, $slurp;
    }
}

sub unlink {
    unlink $self->name;
}

sub unlock {
    flock $self->io_handle, LOCK_UN
      if $self->_lock;
}

sub write {
    $self->assert_open('>');
    my $length = @_
    ? $self->io_handle->write(@_)
    : $self->io_handle->write(${$self->buffer}, $self->length);
    $self->error_check;
    $self->clear unless @_;
    return $length;
}

#===============================================================================
# Implementation methods. Subclassable.
#===============================================================================
sub throw {
    require Carp;
    ;
    return &{$self->errors}(@_)
      if $self->errors;
    return Carp::confess(@_)
      if $self->_confess;
    return Carp::croak(@_);
}

#===============================================================================
# Private instance methods
#===============================================================================
sub assert_dirpath {
    my $dir_name = shift;
    return $dir_name if -d $dir_name or
      CORE::mkdir($self->name, $self->perms || 0755) or
      do {
          require File::Path;
          File::Path::mkpath($dir_name);
      } or
      $self->throw("Can't make $dir_name"); 
}

sub assert_open {
    return if $self->is_open;
    return $self->open_string(@_) if $self->is_string;
    return $self->open_stdio(@_) if $self->is_stdio;
    my $type = $self->type || 'file';
    my $method = "assert_open_$type";
    return $self->$method(@_);
}

sub assert_open_backwards {
    return if $self->is_open;
    require File::ReadBackwards;
    my $file_name = $self->name;
    my $io_handle = File::ReadBackwards->new($file_name)
      or $self->throw("Can't open $file_name for backwards:\n$!");
    $self->io_handle($io_handle);
    $self->is_open(1);
}

field '_dbm_class';
field _dbm_extra => [];
sub assert_open_dbm {
    $self->is_open(1);
    my $tied_file = $self->_tied_file;
    return $tied_file if $tied_file;
    my $dbm_list = $self->_dbm_list;
    my @dbm_list = @$dbm_list ? @$dbm_list :
      (qw(DB_File GDBM_File NDBM_File ODBM_File SDBM_File));
    my $dbm_class;
    for my $module (@dbm_list) {
        if (defined $INC{"$module.pm"} or eval "use $module; 1") {
            $self->_dbm_class($module);
            last;
        }
    }
    $self->throw("No module available for IO::All DBM operation")
      unless defined $self->_dbm_class;
    my $mode = $self->_rdonly ? O_RDONLY : O_RDWR;
    if ($self->_dbm_class eq 'DB_File::Lock') {
        my $flag = $self->_rdwr ? 'write' : 'read';
        $mode = $self->_rdwr ? O_RDWR : O_RDONLY;
        $self->_dbm_extra([$flag]);
    }
    $mode |= O_CREAT if $mode & O_RDWR;
    $self->mode($mode);
    $self->perms(0666) unless defined $self->perms;
    return $self->_mldbm ? $self->_tie_mldbm : $self->_tie_dbm;
}

sub _tie_dbm {
    my $hash;
    my $filename = $self->name;
    tie %$hash, $self->_dbm_class, $filename, $self->mode, $self->perms, 
        eval('$DB_HASH'), @{$self->_dbm_extra}
      or $self->throw("Can't open '$filename' as DBM file:\n$!");
    $self->_tied_file($hash);
}

sub _tie_mldbm {
    my $filename = $self->name;
    my $dbm_class = $self->_dbm_class;
    my $serializer = $self->_serializer;
    eval "use MLDBM qw($dbm_class $serializer)";
    $self->throw("Can't open '$filename' as MLDBM:\n$@") if $@;
    my $hash;
    tie %$hash, 'MLDBM', $filename, $self->mode, $self->perms, 
        eval('$DB_HASH'), @{$self->_dbm_extra}
      or $self->throw("Can't open '$filename' as MLDBM file:\n$!");
    $self->_tied_file($hash);
}

sub assert_open_dir {
    return if $self->is_open;
    require IO::Dir;
    $self->type('dir');
    $self->io_handle(IO::Dir->new)
      unless defined $self->io_handle;
    $self->open;
}

sub assert_open_file {
    return if $self->is_open;
    $self->type('file');
    require IO::File;
    $self->io_handle(IO::File->new)
      unless defined $self->io_handle;
    $self->mode(shift) unless $self->mode;
    $self->open;
}

sub assert_open_pipe {
    return if $self->is_open;
    require IO::Handle;
    $self->io_handle(IO::Handle->new)
      unless defined $self->io_handle;
    my $command = $self->name;
    $command =~ s/(^\||\|$)//;
    my $mode = shift;
    my $pipe_mode = 
      $mode eq '>' ? '|-' :
      $mode eq '<' ? '-|' :
      $self->throw("Invalid usage mode '$mode' for pipe");
    CORE::open($self->io_handle, $pipe_mode, $command);
}

sub assert_open_socket {
    return if $self->is_open;
    $self->type('socket');
    $self->is_open(1);
    require IO::Socket;
    $self->get_socket_domain_port;
    my @args = $self->_listen
    ? (
        LocalAddr => $self->domain,
        LocalPort => $self->port,
        Proto => 'tcp',
        Listen => 1,
        Reuse => 1,
    )
    : (
        PeerAddr => $self->domain,
        PeerPort => $self->port,
        Proto => 'tcp',
    );
    my $socket = IO::Socket::INET->new(@args)
      or $self->throw("Can't open socket");
    $self->io_handle($socket);
}

sub assert_tied_file {
    return $self->_tied_file || do {
        eval {require Tie::File};
        $self->throw("Tie::File required for file array operations:\n$@") 
          if $@;
        my $array_ref = do { my @array; \@array };
        my $name = $self->name;
        my @options = $self->_rdonly ? (mode => O_RDONLY) : ();
        tie @$array_ref, 'Tie::File', $name, @options;
        $self->throw("Can't tie 'Tie::File' to '$name':\n$!")
          unless tied @$array_ref;
        $self->_tied_file($array_ref);
    };
}

sub error_check {
    return unless $self->io_handle->can('error');
    return unless $self->io_handle->error;
    $self->throw($!);
}

sub copy {
    my $copy;
    for (keys %{*$self}) {
        $copy->{$_} = *$self->{$_};
    }
    $copy->{io_handle} = 'defined'
      if defined $copy->{io_handle};
    return $copy;
}

sub get_socket_domain_port {
    my ($domain, $port);
    ($domain, $port) = split /:/, $self->name
      if defined $self->name;
    $self->domain($domain) unless defined $self->domain;
    $self->domain($self->_domain_default) unless $self->domain;
    $self->port($port) unless defined $self->port;
    return $self;
}

sub getline_backwards {
    $self->assert_open_backwards;
    return $self->io_handle->readline;
}

sub getlines_backwards {
    my @lines;
    while (defined (my $line = $self->getline_backwards)) {
        push @lines, $line;
    }
    return @lines;
}

sub set_lock {
    return unless $self->_lock;
    my $io_handle = $self->io_handle;
    my $flag = $self->mode =~ /^>>?$/
    ? LOCK_EX
    : LOCK_SH;
    flock $io_handle, $flag;
}

sub open_file {
    require IO::File;
    if ($self->name and $self->_assert) {
        my $directory;
        (undef, $directory) = File::Spec->splitpath($self->name);
        $self->assert_dirpath($directory);
    } 
    my $handle = IO::File->new;
    $self->io_handle($handle);
    $handle->open(@_) 
      or $self->throw($self->open_file_msg);
    $self->set_lock;
    return $self;
}

my %mode_msg = (
    '>' => 'output',
    '<' => 'input',
    '>>' => 'append',
);
sub open_file_msg {
    my $name = defined $self->name
      ? " '" . $self->name . "'"
      : '';
    my $direction = defined $mode_msg{$self->mode}
      ? ' for ' . $mode_msg{$self->mode}
      : '';
    return qq{Can't open file$name$direction:\n$!};
}

sub open_dir {
    require IO::Dir;
    $self->assert_dirpath($self->name)
      if $self->name and $self->_assert;
    my $handle = IO::Dir->new;
    $self->io_handle($handle);
    $handle->open(@_)
      or $self->throw($self->open_dir_msg);
    return $self;
}

sub open_dir_msg {
    my $name = defined $self->name
      ? " '" . $self->name . "'"
      : '';
    return qq{Can't open directory$name:\n$!};
}

sub open_name {
    return $self->open_file(@_) unless $self->type;
    return $self->open_file(@_) if $self->type eq 'file';
    return $self->open_dir(@_) if $self->type eq 'dir';
    return if $self->type eq 'socket';
    return $self->open_file(@_);
}

sub open_stdio {
    require IO::File;
    my $mode = shift || $self->mode || '<';
    my $fileno = $mode eq '>'
    ? fileno(STDOUT)
    : fileno(STDIN);
    $self->io_handle(IO::File->new);
    $self->io_handle->fdopen($fileno, $mode) ? $self : 0;
}

sub open_stderr {
    $self->io_handle(IO::File->new);
    $self->io_handle->fdopen(fileno(STDERR), '>') ? $self : 0;
}

sub open_string {
    require IO::String;
    $self->io_handle(IO::String->new);
    return $self;
}

#===============================================================================
# Closure generating functions
#===============================================================================
sub option() {
    my $package = caller;
    my ($field, $default) = @_;
    $default ||= 0;
    field("_$field", $default);
    no strict 'refs';
    *{"${package}::$field"} =
      sub {
          my $self = shift;
          *$self->{"_$field"} = @_ ? shift(@_) : 1;
          return $self;
      };
}

sub chain() {
    my $package = caller;
    my ($field, $default) = @_;
    no strict 'refs';
    *{"${package}::$field"} =
      sub {
          my $self = shift;
          if (@_) {
              *$self->{$field} = shift;
              return $self;
          }
          return $default unless exists *$self->{$field};
          return *$self->{$field};
      };
}

sub field() {
    my $package = caller;
    my ($field, $default) = @_;
    no strict 'refs';
    return if defined &{"${package}::$field"};
    *{"${package}::$field"} =
      sub {
          my $self = shift;
          unless (exists *$self->{$field}) {
              *$self->{$field} = 
                ref($default) eq 'ARRAY' ? [] :
                ref($default) eq 'HASH' ? {} : 
                $default;
          }
          return *$self->{$field} unless @_;
          *$self->{$field} = shift;
      };
}

sub proxy() {
    my $package = caller;
    my ($proxy) = @_;
    no strict 'refs';
    return if defined &{"${package}::$proxy"};
    *{"${package}::$proxy"} =
      sub {
          my $self = shift;
          my @return = $self->io_handle->$proxy(@_);
          $self->error_check;
          wantarray ? @return : $return[0];
      };
}

sub proxy_open() {
    my $package = caller;
    my ($proxy, @args) = @_;
    no strict 'refs';
    return if defined &{"${package}::$proxy"};
    *{"${package}::$proxy"} =
      sub {
          my $self = shift;
          $self->assert_open(@args);
          my @return = $self->io_handle->$proxy(@_);
          $self->error_check;
          wantarray ? @return : $return[0];
      };
}

#===============================================================================
# Overloading support
#===============================================================================
my $old_warn_handler = $SIG{__WARN__}; 
$SIG{__WARN__} = sub { 
    if ($_[0] !~ /^Useless use of .+ \(.+\) in void context/) {
        goto &$old_warn_handler if $old_warn_handler;
        warn(@_);
    }
};
    
use overload '""' => 'overload_stringify';
use overload '|' => 'overload_bitwise_or';
use overload '<<' => 'overload_left_bitshift';
use overload '>>' => 'overload_right_bitshift';
use overload '<' => 'overload_less_than';
use overload '>' => 'overload_greater_than';
use overload '${}' => 'overload_string_deref';
use overload '@{}' => 'overload_array_deref';
use overload '%{}' => 'overload_hash_deref';
use overload '&{}' => 'overload_code_deref';

sub overload_bitwise_or { $self->overload_handler(@_, '|') }
sub overload_left_bitshift { $self->overload_handler(@_, '<<') }
sub overload_right_bitshift { $self->overload_handler(@_, '>>') }
sub overload_less_than { $self->overload_handler(@_, '<') }
sub overload_greater_than { $self->overload_handler(@_, '>') }
sub overload_string_deref { $self->overload_handler(@_, '${}') }
sub overload_array_deref { $self->overload_handler(@_, '@{}') }
sub overload_hash_deref { $self->overload_handler(@_, '%{}') }
sub overload_code_deref { $self->overload_handler(@_, '&{}') }

sub overload_table {
    *$self->{overload_table} ||= {
        'file < scalar' => 'overload_scalar_to_file',
        'file > scalar' => 'overload_file_to_scalar',

        'file << scalar' => 'overload_scalar_addto_file',
        'file >> scalar' => 'overload_file_addto_scalar',

        'file > file' => 'overload_file_to_file',
        'file < file' => 'overload_file_from_file',
        'file >> file' => 'overload_file_addto_file',
        'file << file' => 'overload_file_addfrom_file',

        '${} file' => 'overload_file_as_scalar',
        '@{} file' => 'overload_file_as_array',
        '@{} dir' => 'overload_dir_as_array',
        '%{} file' => 'overload_file_as_dbm',
        '%{} dir' => 'overload_dir_as_hash',
        
        'socket < file' => 'overload_file_to_socket',
        'file > socket' => 'overload_file_to_socket',
        '&{} socket' => 'overload_socket_as_code',
    };
}

sub overload_handler() {
    my ($self) = @_;
    my $method = $self->get_overload_method(@_);
    $self->$method(@_);
}

my $op_swap = {
    '>' => '<', '>>' => '<<',
    '<' => '>', '<<' => '>>',
};
sub get_overload_method() {
    my ($self, $arg1, $arg2, $swap, $operator) = @_;
    if ($swap) {
        $operator = $op_swap->{$operator} || $operator;
    }
    my $arg1_type = $self->get_argument_type($arg1);
    my $key = ($operator =~ /\{\}$/)
    ? "$operator $arg1_type"
    : do {
        my $arg2_type = $self->get_argument_type($arg2);
        "$arg1_type $operator $arg2_type";
    };
    my $table = $self->overload_table;
    return defined $table->{$key} 
      ? $table->{$key}
      : $self->overload_undefined($key);
}

sub get_argument_type {
    my $argument = shift;
    my $ref = ref($argument);
    return 'scalar' unless $ref;
    return 'code' if $ref eq 'CODE';
    return 'array' if $ref eq 'ARRAY';
    return 'hash' if $ref eq 'HASH';
    return 'ref' unless $argument->isa('IO::All');
    my $type = $argument->type;
    return defined $argument->name ? 'file' : 'unknown' 
      unless $type;
    return 'file' if $type eq 'pipe';
    return $type;
}

sub overload_stringify {
    my $name = $self->name;
    return defined($name) ? $name : overload::StrVal($self);
}

sub overload_undefined {
    require Carp;
    my $key = shift;
    Carp::carp "Undefined behavior for overloaded IO::All operation: '$key'"
      if $^W;
    return 'overload_noop';
}

sub overload_noop {
    return;
}

sub overload_scalar_addto_file() {
    $_[1]->append($_[2]);
    $_[1];
}

sub overload_file_addto_file() {
    $_[2]->append($_[1]->scalar);
    $_[2];
}

sub overload_file_addfrom_file() {
    $_[1]->append($_[2]->scalar);
    $_[1];
}

sub overload_file_to_file() {
    require File::Copy;
    File::Copy::copy($_[1]->name, $_[2]->name);
    $_[2];
}

sub overload_file_from_file() {
    require File::Copy;
    File::Copy::copy($_[2]->name, $_[1]->name);
    $_[1];
}

sub overload_dir_as_array() {
    [ $_[1]->all ];
}

sub overload_dir_as_hash() {
    +{ 
        map {
            (my $name = $_->name) =~ s/.*[\/\\]//;
            ($name, $_);
        } $_[1]->all 
    };
}

sub overload_file_as_array() {
    $_[1]->assert_tied_file;
}

sub overload_file_as_dbm() {
    $_[1]->assert_open_dbm;
}

sub overload_scalar_to_file() {
    local $\;
    $_[1]->print($_[2]);
    $_[1];
}

sub overload_file_as_scalar() {
    my $scalar = $_[1]->scalar;
    return \$scalar;
}

sub overload_file_to_scalar() {
    $_[2] = $_[1]->scalar;
}

sub overload_file_addto_scalar() {
    $_[2] .= $_[1]->scalar;
    $_[2];
}

sub overload_socket_as_code {
    sub {
        my $coderef = shift;
        while ($self->is_open) {
            $_ = $self->getline;
            &$coderef($self);
        }
    }
}

sub overload_file_to_socket() {
    local $\;
    $_[1]->print($_[2]->scalar);
    $_[1]->close;
}

1;

__END__

=head1 NAME

IO::All - IO::All of it to Graham and Damian!

=head1 IMPORTANT NOTES!!!

(14 May 2004) Version 0.20 breaks backwards compatibility (I said I
would :-) slightly to make the module even cleaner than before. All
flags like '-fork', '-tie', etc have been replaced by methods like 
->fork and ->tie etc. Also the syntax for creating a temporary file has
changed. Please read the docs and adjust accordingly. Also the docs have
been completely revised; another good reason to read on.

(15 Mar 2004) If you've just read the perl.com article at
L<http://www.perl.com/pub/a/2004/03/12/ioall.html>, there have already
been major additions thanks to the great feedback I've gotten from the
Perl community. Be sure and read the latest doc. Things are changing
fast. Many of the changes have to do with operator overloading for
IO::All objects, which results in some fabulous new idioms.

=head1 SYNOPSIS

    use IO::All;                                # Let the madness begin...

    # Some of the many ways to read a whole file into a scalar
    io('file.txt') > $contents;                 # Overloaded "arrow"
    $contents < io 'file.txt';                  # Flipped but same operation
    $io = io 'file.txt';                        # Create a new IO::All object
    $contents = $$io;                           # Overloaded scalar dereference
    $contents = $io->slurp;                     # A method to read everything
    $contents = $io->scalar;                    # Another method for that
    $contents = join '', $io->getlines;         # Join the separate lines
    $contents = join '', map "$_\n", @$io;      # Same. Overloaded array deref
    $io->tie;                                   # Tie the object as a handle
    $contents = join '', <$io>;                 # And use it in builtins
    # and the list goes on ...

    # Other file operations:
    @lines = io('file.txt')->slurp;             # List context slurp
    $content > io('file.txt');                  # Print to a file
    io('file.txt')->print($content, $more);     # (ditto)
    $content >> io('file.txt');                 # Append to a file
    io('file.txt')->append($content);           # (ditto)
    $content << $io;                            # Append to a string
    io('copy.txt') < io('file.txt');            $ Copy a file
    io('file.txt') > io('copy.txt');            # Invokes File::Copy
    io('more.txt') >> io('all.txt');            # Add on to a file

    # Print the path name of a file:
    print $io->name;                            # The direct method
    print "$io";                                # Object stringifies to name
    print $io;                                  # Quotes not needed here
    print $io->filename;                        # The file portion only

    # Read all the files/directories in a directory:
    $io = io('my/directory/');                  # Create new directory object
    @contents = $io->all;                       # Get all contents of dir
    @contents = @$io;                           # Directory as an array
    @contents = values %$io;                    # Directory as a hash
    push @contents, $subdir                     # One at a time
      while $subdir = $io->next;

    # Print the name and file type for all the contents above:
    print "$_ is a " . $_->type . "\n"          # Each element of @contents
      for @contents;                            # is an IO::All object!!

    # Print first line of each file:
    print $_->getline                           # getline gets one line
      for io('dir')->all_files;                 # Files only

    # Print names of all files/dirs three directories deep:
    print "$_\n" for $io->all(3);               # Pass in the depth. Default=1

    # Print names of all files/dirs recursively:
    print "$_\n" for $io->all(0);               # Zero means all the way down
    print "$_\n" for $io->All;                  # Capitalized shortcut
    print "$_\n" for $io->deep->all;            # Another way

    # There are some special file names:
    print io('-');                              # Print STDIN to STDOUT
    io('-') > io('-');                          # Do it again
    io('-') < io('-');                          # Same. Context sensitive.
    "Bad puppy" > io('=');                      # Message to STDERR
    $string_file = io('$');                     # Create IO::String Object
    $temp_file = io('?');                       # Create a temporary file

    # Socket operations:
    $server = io('localhost:5555')->fork;       # Create a daemon socket
    $connection = $server->accept;              # Get a connection socket
    $input < $connection;                       # Get some data from it
    "Thank you!" > $connection;                 # Thank the caller
    $connection->close;                         # Hang up
    io(':6666')->accept->slurp > io->devnull;   # Take a complaint and file it
    
    # DBM database operations:
    $dbm = io 'my/database';                    # Create a database object
    print $dbm->{grocery_list};                 # Hash context makes it a DBM
    $dbm->{todo} = $new_list;                   # Write to database
    $dbm->dbm('GDBM_file');                     # Demand specific DBM
    io('mydb')->mldbm->{env} = \%ENV;           # MLDBM support

    # Tie::File support:
    $io = io 'file.txt';
    $io->[42] = 'Line Forty Three';             # Change a line
    print $io->[@$io / 2];                      # Print middle line
    @$io = reverse @$io;                        # Reverse lines in a file

    # Stat functions:
    printf "%s %s %s\n",                        # Print name, uid and size of 
      $_->name, $_->uid, $_->size               # contents of current directory
        for io('.')->all;
    print "$_\n" for sort                       # Use mtime method to sort all
      {$b->mtime <=> $a->mtime}                 # files under current directory
        io('.')->All_Files;                     # by recent modification time.

    # File::Spec support:
    $contents < io->catfile(qw(dir file.txt));  # Portable IO operation
    
    # Miscellaneous:
    @lines = io('file.txt')->chomp->slurp;      # Chomp as you slurp
    @chunks = 
      io('file.txt')->separator('xxx')->slurp;  # Use alternnate record sep
    $binary = io('file.bin')->binary->scalar;   # Read a binary file
    io('a-symlink')->readlink->slurp;           # Readlink returns an object

    # This is just the beginning, read on...

=head1 DESCRIPTION

"Graham Barr for doing it all. Damian Conway for doing it all different."

IO::All combines all of the best Perl IO modules into a single Spiffy
object oriented interface to greatly simplify your everyday Perl IO
idioms. It exports a single function called C<io>, which returns a new
IO::All object. And that object can do it all!

The IO::All object is a proxy for IO::File, IO::Dir, IO::Socket,
IO::String, Tie::File, File::Spec, File::Path and File::ReadBackwards;
as well as all the DBM and MLDBM modules. You can use most of the
methods found in these classes and in IO::Handle (which they inherit
from). IO::All adds dozens of other helpful idiomatic methods including
file stat and manipulation functions.

Optionally, every IO::All object can be tied to itself. This means that
you can use most perl IO builtins on it: readline, <>, getc, print,
printf, syswrite, sysread, close.

If you need even more power, IO::All is easily subclassable. You can
override any methods and also add new methods of your own.

The distinguishing magic of IO::All is that it will automatically open
(and close) files, directories, sockets and other IO things for you. You
never need to specify the mode ('<', '>>', etc), since it is determined
by the usage context. That means you can replace this:

    open STUFF, '<', './mystuff'
      or die "Can't open './mystuff' for input:\n$!";
    local $/;
    my $stuff = <STUFF>;
    close STUFF;

with this:

    my $stuff < io'./mystuff';

And that is a B<good thing>!

=head1 METHOD ROLE CALL

Here is an alphabetical list of all the public methods that you can call
on an IO::All object.

C<All>, C<All_Files>, C<All_Links>, C<All_Dirs>, C<abs2rel>, C<accept>,
C<all>, C<all_dirs>, C<all_files>, C<all_links>, C<append>, C<appendf>,
C<appendln>, C<assert>, C<atime>, C<autoclose>, C<autoflush>,
C<backwards>, C<binary>, C<blksize>, C<blocks>, C<block_size>, C<buffer>,
C<canonpath>, C<case_tolerant>, C<catdir>, C<catfile>, C<catpath>,
C<chomp>, C<clear>, C<close>, C<confess>, C<ctime>, C<curdir>, C<dbm>,
C<deep>, C<device>, C<device_id>, C<devnull>, C<dir>, C<domain>, C<eof>,
C<errors>, C<file>, C<filename>, C<fileno>, C<filepath>, C<filter>,
C<fork>, C<getc>, C<getline>, C<getlines>, C<gid>, C<handle>, C<inode>,
C<io_handle>, C<is_absolute>, C<is_dir>, C<is_file>, C<is_open>,
C<is_pipe>, C<is_socket>, C<is_stdio>, C<is_string>, C<join>, C<length>,
C<link>, C<lock>, C<mkdir>, C<mkpath>, C<mldbm>, C<mode>, C<modes>,
C<mtime>, C<name>, C<new>, C<next>, C<nlink>, C<open>, C<path>,
C<perms>, C<pipe>, C<port>, C<print>, C<printf>, C<println>, C<rdonly>,
C<rdwr>, C<read>, C<readlink>, C<recv>, C<rel2abs>, C<rename>, C<rmdir>,
C<rmtree>, C<rootdir>, C<scalar>, C<seek>, C<send>, C<separator>,
C<shutdown>, C<size>, C<slurp>, C<socket>, C<sort>, C<splitdir>,
C<splitpath>, C<stat>, C<stdio>, C<stderr>, C<stdin>, C<stdout>,
C<string>, C<string_ref>, C<sysread>, C<syswrite>, C<tell>, C<temp>,
C<tie>, C<tmpdir>, C<truncate>, C<type>, C<uid>, C<unlink>, C<unlock>,
C<updir> and C<write>.

Each method is documented further below.

=head1 OPERATOR OVERLOADING

IO::All objects overload a small set of Perl operators to great effect.
The overloads are limited to <, <<, >, >>, dereferencing operations, and
stringification.

Even though relatively few operations are overloaded, there is actually
a huge matrix of possibilities for magic. That's because the overloading
is sensitive to the types, position and context of the arguments, and an
IO::All object can be one of many types.

The most important overload to grok is stringification. IO::All objects
stringify to their file or directory name. Here we print the contents of
the current directory:

    perl -MIO::All -le 'print for io(".")->all'

is the same as:

    perl -MIO::All -le 'print $_->name for io(".")->all'

Stringification is important because it allows IO::All operations to return
objects when they might otherwise return file names. Then the recipient can
use the result either as an object or a string.

'>' and '<' move data between objects in the direction pointed to by the
operator.

    $content1 < io('file1');
    $content1 > io('file2');
    io('file2') > $content3;
    io('file3') < $content3;
    io('file3') > io('file4');
    io('file5') < io('file4');

'>>' and '<<' do the same thing except the recipent string or file is
appended to.

An IO::All file used as an array reference becomes tied using Tie::File:

    $file = io"file";
    # Print last line of file
    print $file->[-1];
    # Insert new line in middle of file
    $file->[$#$file / 2] = 'New line';

An IO::All file used as a hash reference becomes tied to a DBM class:

    io('mydbm')->{ingy} = 'YAML';

An IO::All directory used as an array reference, will expose each file or
subdirectory as an element of the array.

    print "$_\n" for @{io 'dir'};

IO::All directories used as hash references have file names as keys, and
IO::All objects as values:

    print io('dir')->{'foo.txt'}->slurp;

Files used as scalar references get slurped:

    print ${io('dir')->{'foo.txt'}};

Not all combinations of operations and object types are supported. Some
just haven't been added yet, and some just don't make sense. If you use
an invalid combination, an error will be thrown.

=head1 COOKBOOK

This section describes some various things that you can easily cook up
with IO::All.

=head2 File Locking

IO::All makes it very easy to lock files. Just use the C<lock> method. Here's a
standalone program that demonstrates locking for both write and read:

    use IO::All;
    my $io1 = io('myfile')->lock;
    $io1->println('line 1');

    fork or do {
        my $io2 = io('myfile')->lock;
        print $io2->slurp;
        exit;
    };

    sleep 1;
    $io1->println('line 2');
    $io1->println('line 3');
    $io1->unlock;

There are a lot of subtle things going on here. An exclusive lock is
issued for C<$io1> on the first C<println>. That's because the file
isn't actually opened until the first IO operation.

When the child process tries to read the file using C<$io2>, there is
a shared lock put on it. Since C<$io1> has the exclusive lock, the
slurp blocks.

The parent process sleeps just to make sure the child process gets a
chance. The parent needs to call C<unlock> or C<close> to release the
lock. If all goes well the child will print 3 lines.

=head2 Round Robin

This simple example will read lines from a file forever. When the last
line is read, it will reopen the file and read the first one again.

    my $io = io'file1.txt';
    $io->autoclose(1);
    while (my $line = $io->getline || $io->getline) {
        print $line;
    }

=head2 Reading Backwards

If you call the C<backwards> method on an IO::All object, the
C<getline> and C<getlines> will work in reverse. They will read the
lines in the file from the end to the beginning.

    my @reversed;
    my $io = io('file1.txt');
    $io->backwards;
    while (my $line = $io->getline) {
        push @reversed, $line;
    }

or more simply:

    my @reversed = io('file1.txt')->backwards->getlines;

The C<backwards> method returns the IO::All object so that you can
chain the calls.

NOTE: This operation requires that you have the File::ReadBackwards 
module installed.
    
=head2 Client/Server Sockets

IO::All makes it really easy to write a forking socket server and a
client to talk to it.

In this example, a server will return 3 lines of text, to every client
that calls it. Here is the server code:

    use IO::All;

    my $socket = io(':12345')->fork->accept;
    $socket->print($_) while <DATA>;
    $socket->close;

    __DATA__
    On your mark,
    Get set,
    Go!

Here is the client code:

    use IO::All;

    my $io = io('localhost:12345');
    print while $_ = $io->getline;

You can run the server once, and then run the client repeatedly (in
another terminal window). It should print the 3 data lines each time.

Note that it is important to close the socket if the server is forking,
or else the socket won't go out of scope and close.

=head2 A Tiny Web Server

Here is how you could write a simplistic web server that works with static and
dynamic pages:

    perl -MIO::All -e 'io(":8080")->fork->accept->(sub { $_[0] < io(-x $1 ? "./$1 |" : $1) if /^GET \/(.*) / })'

There is are a lot of subtle things going on here. First we accept a socket
and fork the server. Then we overload the new socket as a code ref. This code
ref takes one argument, another code ref, which is used as a callback. 

The callback is called once for every line read on the socket. The line
is put into C<$_> and the socket itself is passed in to the callback.

Our callback is scanning the line in C<$_> for an HTTP GET request. If one is
found it parses the file name into C<$1>. Then we use C<$1> to create an new
IO::All file object... with a twist. If the file is executable (C<-x>), then
we create a piped command as our IO::All object. This somewhat approximates
CGI support.

Whatever the resulting object is, we direct the contents back at our socket
which is in C<$_[0]>. Pretty simple, eh? 

=head2 DBM Files

IO::All file objects used as a hash reference, treat the file as a DBM tied to
a hash. Here I write my DB record to STDERR:

    io("names.db")->{ingy} > io'=';

Since their are several DBM formats available in Perl, IO::All picks the first
one of these that is installed on your system:

    DB_File GDBM_File NDBM_File ODBM_File SDBM_File

You can override which DBM you want for each IO::All object:

    my @keys = keys %{io('mydbm')->dbm('SDBM_File')};

=head2 File Subclassing

Subclassing is easy with IO::All. Just create a new module and use
IO::All as the base class. Since IO::All is a Spiffy module, you do it
like this:

    package NewModule;
    use IO::All '-base';

You need to do it this way so that IO::All will export the C<io> function.
Here is a simple recipe for subclassing:

IO::Dumper inherits everything from IO::All and adds an extra method
called C<dump>, which will dump a data structure to the file we
specify in the C<io> function. Since it needs Data::Dumper to do the
dumping, we override the C<open> method to C<require Data::Dumper> and
then pass control to the real C<open>.

First the code using the module:

    use IO::Dumper;
    
    io('./mydump')->dump($hash);

And next the IO::Dumper module itself:

    package IO::Dumper;
    use IO::All '-base';
    use Data::Dumper;
    
    sub dump {
        my $self = shift;
        Dumper(@_) > $self;
    }
    
    1;

=head2 Inline Subclassing

This recipe does the same thing as the previous one, but without needing
to write a separate module. The only real difference is the first line.
Since you don't "use" IO::Dumper, you need to still call its C<import>
method manually.

    IO::Dumper->import;
    io('./mydump')->dump($hash);
    
    package IO::Dumper;
    use IO::All '-base';
    use Data::Dumper;
    
    sub dump {
        my $self = shift;
        Dumper(@_) > $self;
    }

=head1 THE IO::All METHODS

This section gives a full description of all of the methods that you can
call on IO::All objects. The methods have been grouped into subsections
based on object construction, option settings, configuration, action
methods and support for specific modules.

=head2 Object Construction and Initialization Methods

=over 4

=item * new

There are three ways to create a new IO::All object. The first is with
the special function C<io> which really just calls C<< IO::All->new >>.
The second is by calling C<new> as a class method. The third is calling
C<new> as an object instance method. In this final case, the new objects
attributes are copied from the instance object.

    io(file-descriptor);
    IO::All->new(file-descriptor);
    $io->new(file-descriptor);
            
All three forms take a single argument, a file descriptor. A file
descriptor can be any of the following:

    - A file name
    - A file handle
    - A directory name
    - A directory handle
    - A typeglob reference
    - A piped shell command. eq '| ls -al'
    - A socket domain/port.  eg 'perl.com:5678'
    - '-' means STDIN or STDOUT (depending on usage)
    - '=' means STDERR
    - '$' means an IO::String object
    - '?' means a temporary file

If no file descriptor is provided, an object will still be created, but
it must be defined by one of the following methods before it can be used
for I/O:

=item * file

    io->file(file-name);

Using the C<file> method sets the type of the object to I<file> and sets
the pathname of the file if provided.

It might be important to use this method if you had a file whose name
was C<'-'>, or if the name might otherwise be confused with a
directory or a socket. In this case, either of these statements would
work the same:

    my $file = io('-')->file;
    my $file = io->file('-');

=item * dir

    io->file(dir-name);

Make the object be of type I<directory>.

=item * socket

    io->file(domain:port);

Make the object be of type I<socket>.

=item * link

    io->file(link-name);

Make the object be of type I<link>.

=item * pipe

    io->file(link-name);

Make the object be of type I<pipe>. The following two statements are
equivalent:

    my $io = io('ls -l |');
    my $io = io('ls -l')->pipe;
    my $io = io->pipe('ls -l');

=item * string

Make the object be a IO::String object. These are equivalent:

    my $io = io('$');
    my $io = io->string;

=item * temp

Make the object represent a temporary file. It will automatically be
open for both read and write.

=item * stdio

Make the object represent either STDIN or STDOUT depending on how it is
used subsequently. These are equivalent:

    my $io = io('-');
    my $io = io->stdin;

=item * stdin

Make the object represent STDIN.

=item * stdout

Make the object represent STDOUT.

=item * stderr

Make the object represent STDERR.

=item * handle

    io->handle(io-handle);

Forces the object to be created from an pre-existing IO handle. You can
chain calls together to indicate the type of handle:

    my $file_object = io->file->handle($file_handle);
    my $dir_object = io->dir->handle($dir_handle);

=back

If you need to use the same options to create a lot of objects, and
don't want to duplicate the code, just create a dummy object with the
options you want, and use that object to spawn other objects.

    my $lt = io->lock->tie;
    ...
    my $io1 = $lt->new('file1');
    my $io2 = $lt->new('file2');

Since the new method copies attributes from the calling object, both
C<$io1> and C<$io2> will be locked and tied.

=head2 Option Setting Methods

The following methods don't do any actual I/O, but they specify options
about how the I/O should be done.

Each option can take a single argument of 0 or 1. If no argument is
given, the value 1 is assumed. Passing 0 turns the option off.

All of these options return the object reference that was used to
invoke them. This is so that the option methods can be chained
together. For example:

    my $io = io('path/file')->tie->assert->chomp->lock;

=over 4

=item * assert

This method ensures that the path for a file or directory actually exists
before the file is open. If the path does not exist, it is created.

=item * autoclose

By default, IO::All will close an object opened for input when EOF is
reached. By closing the handle early, one can immediately do other
operations on the object without first having to close it.

This option is on by default, so if you don't want this behaviour, say
so like this:

    $io->autoclose(0);

The object will then be closed when C<$io> goes out of scope, or you
manually call C<< $io->close >>.

=item * autoflush

Proxy for IO::Handle::autoflush

=item * backwards

Sets the object to 'backwards' mode. All subsequent C<getline>
operations will read backwards from the end of the file.

Requires the File::ReadBackwards CPAN module.

=item * binary

Indicates the file has binary content and should be opened with
C<binmode>.

=item * chomp

Indicates that all operations that read lines should chomp the lines. If
the C<separator> method has been called, chomp will remove that value
from the end of each record.

=item * confess

Errors should be reported with the very detailed Carp::confess function.

=item * deep

Indicates that calls to the C<all> family of methods should search
directories as deep as possible.

=item * fork

Indicates that the process should automatically be forked inside the
C<accept> socket method.

=item * lock

Indicate that operations on an object should be locked using flock.

=item * rdonly

This option indicates that certain operations like DBM and Tie::File
access should be done in read-only mode.

=item * rdwr

This option indicates that DBM and MLDBM files should be opened in read-
write mode.

=item * sort

Indicates whether objects returned from one of the C<all> methods will
be in sorted order by name. True by default.

=item * tie

Indicate that the object should be tied to itself, thus allowing it to
be used as a filehandle in any of Perl's builtin IO operations.

    my $io = io('foo')->tie;
    @lines = <$io>;

=back

=head2 Configuration Methods

The following methods don't do any actual I/O, but they set specific
values to configure the IO::All object.

If these methods are passed no argument, they will return their
current value. If arguments are passed they will be used to set the
current value, and the object reference will be returned for potential
method chaining.

=over 4

=item * block_size

The default length to be used for C<read> and C<sysread> calls.
Defaults to 1024.

=item * buffer

Returns a reference to the internal buffer, which is a scalar. You can
use this method to set the buffer to a scalar of your choice. (You can
just pass in the scalar, rather than a reference to it.)

This is the buffer that C<read> and C<write> will use by default.

You can easily have IO::All objects use the same buffer:

    my $input = io('abc');
    my $output = io('xyz');
    my $buffer;
    $output->buffer($input->buffer($buffer));
    $output->write while $input->read;

=item * dbm

This method takes the names of zero or more DBM modules. The first one
that is available is used to process the dbm file.

    io('mydbm')->dbm('NDBM_File', 'SDBM_File')->{author} = 'ingy';

If no module names are provided, the first available of the
following is used:

    DB_File GDBM_File NDBM_File ODBM_File SDBM_File

=item * domain

Set the domain name or ip address that a socket should use.

=item * errors

Use this to set a subroutine reference that gets called when an internal
error is thrown.

=item * filter

Use this to set a subroutine reference that will be used to grep
which objects get returned on a call to one of the C<all> methods.
For example:

    my @odd = io->curdir->filter(sub {$_->size % 2})->All_Files;

C<@odd> will contain all the files under the current directory whose
size is an odd number of bytes.

=item * mldbm

Similar to the C<dbm> method, except create a Multi Level DBM object
using the MLDBM module.

This method takes the names of zero or more DBM modules and an optional
serialization module. The first DBM module that is available is used to
process the MLDBM file. The serialization module can be Data::Dumper,
Storable or FreezeThaw.

    io('mymldbm')->mldbm('GDBM_File', 'Storable')->{author} = 
      {nickname => 'ingy'};

=item * domain

Set the domain name or ip address that a socket should use.

=item * mode

Set the mode for which the file should be opened. Examples:

    $io->mode('>>')->open;
    $io->mode(O_RDONLY);

=item * name

Set or get the name of the file or directory represented by the IO::All
object.

=item * perms

Sets the permissions to be used if the file/directory needs to be created.

=item * port

Set the port number that a socket should use.

=item * separator

Sets the record (line) separator to whatever value you pass it. Default
is \n. Affects the chomp setting too.

=item * string_ref

Proxy for IO::String::string_ref

Returns a reference to the internal string that is acting like a file.

=back

=head2 IO Action Methods

These are the methods that actually perform I/O operations on an IO::All
object. The stat methods and the File::Spec methods are documented in
separate sections below.

=over 4

=item * accept

For sockets. Opens a server socket (LISTEN => 1, REUSE => 1). Returns an
IO::All socket object that you are listening on.

If the C<fork> method was called on the object, the process will
automatically be forked for every connection.

=item * all

Returns a list of IO::All objects for all files and subdirectories in a
directory. 

'.' and '..' are excluded.

Takes an optional argument telling how many directories deep to search. The
default is 1. Zero (0) means search as deep as possible.

The filter method can be used to limit the results.

The items returned are sorted by name unless C<< ->sort(0) >> is used.

=item * All

Same as C<all(0)>.

=item * all_dirs

Same as C<all>, but only return directories.

=item * All_Dirs

Same as C<all_dirs(0)>.

=item * all_files

Same as C<all>, but only return files.

=item * All_Files

Same as C<all_files(0)>.

=item * all_links

Same as C<all>, but only return links.

=item * All_Links

Same as C<all_links(0)>.

=item * append

Same as print, but sets the file mode to '>>'.

=item * appendf

Same as printf, but sets the file mode to '>>'.

=item * appendln

Same as println, but sets the file mode to '>>'.

=item * clear

Clear the internal buffer. This method is called by C<write> after it
writes the buffer. Returns the object reference for chaining.

=item * close

Close will basically unopen the object, which has different meanings for
different objects. For files and directories it will close and release
the handle. For sockets it calls shutdown. For tied things it unties
them, and it unlocks locked things.

=item * eof

Proxy for IO::Handle::eof

=item * filename

Return the name portion of the file path in the object. For example:

    io('my/path/file.txt')->filename;

would return C<file.txt>.

=item * fileno

Proxy for IO::Handle::fileno

=item * filepath

Return the path portion of the file path in the object. For example:

    io('my/path/file.txt')->filename;

would return C<my/path>.

=item * getc

Proxy for IO::Handle::getc

=item * getline

Calls IO::File::getline. You can pass in an optional record separator.

=item * getlines

Calls IO::File::getlines. You can pass in an optional record separator.

=item * io_handle

Direct access to the actual IO::Handle object being used on an opened
IO::All object.

=item * is_dir

Returns boolean telling whether or not the IO::All object represents
a directory.

=item * is_file

Returns boolean telling whether or not the IO::All object
represents a file.

=item * is_link

Returns boolean telling whether or not the IO::All object represents
a symlink.

=item * is_open

Indicates whether the IO::All is currently open for input/output.

=item * is_pipe

Returns boolean telling whether or not the IO::All object represents
a pipe operation.

=item * is_socket

Returns boolean telling whether or not the IO::All object represents
a socket.

=item * is_stdio

Returns boolean telling whether or not the IO::All object represents
a STDIO file handle.

=item * is_string

Returns boolean telling whether or not the IO::All object represents
an IO::String object.

=item * length

Return the length of the internal buffer.

=item * mkdir

Create the directory represented by the object.

=item * mkpath

Create the directory represented by the object, when the path contains
more than one directory that doesn't exist. Proxy for File::Path::mkpath.

=item * next

For a directory, this will return a new IO::All object for each file
or subdirectory in the directory. Return undef on EOD.

=item * open

Open the IO::All object. Takes two optional arguments C<mode> and
C<perms>, which can also be set ahead of time using the C<mode> and
C<perms> methods.

NOTE: Normally you won't need to call open (or mode/perms), since this
happens automatically for most operations.

=item * print

Proxy for IO::Handle::print

=item * printf

Proxy for IO::Handle::printf

=item * println

Same as print, but adds newline to each argument unless it already
ends with one.

=item * read

This method varies depending on its context. Read carefully (no pun
intended).

For a file, this will proxy IO::File::read. This means you must pass
it a buffer, a length to read, and optionally a buffer offset for where
to put the data that is read. The function returns the length actually
read (which is zero at EOF).

If you don't pass any arguments for a file, IO::All will use its own
internal buffer, a default length, and the offset will always point at
the end of the buffer. The buffer can be accessed with the C<buffer>
method. The length can be set with the C<block_size> method. The default
length is 1024 bytes. The C<clear> method can be called to clear
the buffer.

For a directory, this will proxy IO::Dir::read.

=item * readline

Same as C<getline>.

=item * readlink

Calls Perl's readlink function on the link represented by the object.
Instead of returning the file path, it returns a new IO::All object
using the file path.

=item * recv

Proxy for IO::Socket::recv

=item * rename

    my $new = $io->rename('new-name');

Calls Perl's rename function and returns an IO::All object for the
renamed file. Returns false if the rename failed.

=item * rewind

Proxy for IO::Dir::rewind

=item * rmdir

Delete the directory represented by the IO::All object.

=item * rmtree

Delete the directory represented by the IO::All object and all the files
and directories beneath it. Proxy for File::Path::rmtree.

=item * scalar

Same as slurp, but ignores list context and always returns one string.
Nice to use when you, for instance, want to use as a function argument
where list context is implied:

    compare(io('file1')->scalar, io('file2')->scalar);

=item * seek

Proxy for IO::Handle::seek. If you use seek on an unopened file, it will
be opened for both read and write.

=item * send

Proxy for IO::Socket::send

=item * shutdown

Proxy for IO::Socket::shutdown

=item * slurp

Read all file content in one operation. Returns the file content
as a string. In list context returns every line in the file.

=item * stat

Proxy for IO::Handle::stat

=item * sysread

Proxy for IO::Handle::sysread

=item * syswrite

Proxy for IO::Handle::syswrite

=item * tell

Proxy for IO::Handle::tell

=item * throw

This is an internal method that gets called whenever there is an error.
It could be useful to override it in a subclass, to provide more control
in error handling.

=item * truncate

Proxy for IO::Handle::truncate

=item * type

Returns a string indicated the type of io object. Possible values are:

    file
    dir
    link
    socket
    string
    pipe

Returns undef if type is not determinable.

=item * unlink

Unlink (delete) the file represented by the IO::All object.

NOTE: You can unlink a file after it is open, and continue using it
until it is closed.

=item * unlock

Release a lock from an object that used the C<lock> method.

=item * write

Opposite of C<read> for file operations only.

NOTE: When used with the automatic internal buffer, C<write> will
clear the buffer after writing it.

=back

=head2 Stat Methods

This methods get individual values from a stat call on the file,
directory or handle represented by th IO::All object.

=over 4

=item * atime

Last access time in seconds since the epoch

=item * blksize

Preferred block size for file system I/O

=item * blocks

Actual number of blocks allocated

=item * ctime

Inode change time in seconds since the epoch

=item * device

Device number of filesystem

=item * device_id

Device identifier for special files only

=item * gid

Numeric group id of file's owner

=item * inode

Inode number

=item * modes

File mode - type and permissions

=item * mtime

Last modify time in seconds since the epoch

=item * nlink

Number of hard links to the file

=item * size

Total size of file in bytes

=item * uid

Numeric user id of file's owner

=back

=head2 File::Spec Methods

These methods are all adaptations from File::Spec. Each method
actually does call the matching File::Spec method, but the arguments
and return values differ slightly. Instead of being file and directory
B<names>, they are IO::All B<objects>. Since IO::All objects stringify
to their names, you can generally use the methods just like File::Spec.

=over 4

=item * abs2rel

Returns the relative path for the absolute path in the IO::All object.
Can take an optional argument indicating the base path.

=item * canonpath

Returns the canonical path for the IO::All object.

=item * case_tolerant

Returns 0 or 1 indicating whether the file system is case tolerant.
Since an active IO::All object is not needed for this function, you can
code it like:

    IO::All->case_tolerant;

or more simply:

    io->case_tolerant;

=item * catdir

Concatenate the directory components together, and return a new IO::All
object representing the resulting directory.

=item * catfile

Concatenate the directory and file components together, and return a new
IO::All object representing the resulting file.

    my $contents = io->catfile(qw(dir subdir file))->slurp;

This is a very portable way to read C<dir/subdir/file>.

=item * catpath

Concatenate the volume, directory and file components together, and
return a new IO::All object representing the resulting file.

=item * curdir

Returns an IO::All object representing the current directory.

=item * devnull

Returns an IO::All object representing the /dev/null file.

=item * is_absolute

Returns 0 or 1 indicating whether the C<name> field of the IO::All object is
an absolute path.

=item * join

Same as C<catfile>.

=item * path

Returns a list of IO::All directory objects for each directory in your path.

=item * rel2abs

Returns the absolute path for the relative path in the IO::All object. Can
take an optional argument indicating the base path.

=item * rootdir

Returns an IO::All object representing the root directory on your
file system.

=item * splitdir

Returns a list of the directory components of a path in an IO::All object.

=item * splitpath

Returns a volume directory and file component of a path in an IO::All object.

=item * tmpdir

Returns an IO::All object representing a temporary directory on your
file system.

=item * updir

Returns an IO::All object representing the current parent directory.

=back

=head1 OPERATIONAL NOTES

=over 4

=item *

An IO::All object will automatically be opened as soon as there is
enough contextual information to know what type of object it is, and
what mode it should be opened for. This is usually when the first read
or write operation is invoked but might be sooner.

=item *

The mode for an object to be opened with is determined heuristically
unless specified explicitly.

=item *

For input, IO::All objects will automatically be closed after EOF (or
EOD). For output, the object closes when it goes out of scope.

To keep input objects from closing at EOF, do this:

    $io->autoclose(0);

=item * 

You can always call C<open> and C<close> explicitly, if you need that
level of control. To test if an object is currently open, use the
C<is_open> method.

=item *

Overloaded operations return the target object, if one exists.

This would set C<$xxx> to the IO::All object:

    my $xxx = $contents > io('file.txt');

While this would set C<$xxx> to the content string:

    my $xxx = $contents < io('file.txt');

=back

=head1 STABILITY

The goal of the IO::All project is to continually refine the module
to be as simple and consistent to use as possible. Therefore, in the
early stages of the project, I will not hesitate to break backwards
compatibility with other versions of IO::All if I can find an easier
and clearer way to do a particular thing.

IO is tricky stuff. There is definitely more work to be done. On the
other hand, this module relies heavily on very stable existing IO
modules; so it may work fairly well.

I am sure you will find many unexpected "features". Please send all
problems, ideas and suggestions to ingy@cpan.org.

=head2 Known Bugs and Deficiencies

Not all possible combinations of objects and methods have been tested.
There are many many combinations. All of the examples have been tested.
If you find a bug with a particular combination of calls, let me know.

If you call a method that does not make sense for a particular object,
the result probably won't make sense. Little attempt is made to check
for improper usage.

=head1 SEE ALSO

IO::Handle, IO::File, IO::Dir, IO::Socket, IO::String, File::Spec,
File::Path, File::ReadBackwards, Tie::File

Also check out the Spiffy module if you are interested in extending this
module.

=head1 CREDITS

A lot of people have sent in suggestions, that have become a part of
IO::All. Thank you.

Special thanks to Ian Langworth for continued testing and patching.

Thank you Simon Cozens for tipping me off to the overloading possibilities.

Finally, thanks to Autrijus Tang, for always having one more good idea.

(It seems IO::All of it to a lot of people!)

=head1 AUTHOR

Brian Ingerson <ingy@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2004. Brian Ingerson. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
