use feature 'switch';
use utf8;
use EV;
use AnyEvent;
use AnyEvent::IRC::Client;
use AnyEvent::HTTP;
use YAML::Any qw(LoadFile DumpFile Dump);
use AnyEvent::ReadLine::Gnu;
use Text::ParseWords;
use Getopt::Long qw(GetOptionsFromArray);
use MegaHAL::Filehandle;
use MegaHAL::Server;
use MegaHAL::Interface::Console;
use MegaHAL::ACL;
use MegaHAL::Shell;
use Term::ANSIColor qw(colorstrip);
use MegaHAL::Telnet;
our $VERSION = '1.5';
our @cmdt;
my $old_stdout;
open($old_stdout, '>&STDOUT') or die "Can't dup STDOUT!\n";
my $c = AnyEvent->condvar;
our %srv;
our $cif = MegaHAL::Interface::Console->new();
if (1 || !defined(&DB::DB)) {
    our $rl = AnyEvent::ReadLine::Gnu->new(
        prompt  => '> ',
        on_line => sub {
            console($_[0], $cif);
        },
        out => $old_stdout
    );
    tie(*STDOUT, 'MegaHAL::Filehandle', *STDOUT, $rl, \&outh);
    tie(*STDERR, 'MegaHAL::Filehandle', *STDERR, $rl, \&errh);
} else {
    my $t;
    $t = AnyEvent->timer(after => 1, interval => 1, cb => sub { $t; &dbghook });
}

sub dbghook {
    print '';
}
our %outh;
our $inouth = 0;
sub hout { $outh{ $outhn++ } = $_[0]; return $outhn - 1 }

sub outh {
    my ($str) = @_;
    return if $inouth;
    local $inouth = 1;
    MegaHAL::Telnet::outh($str);
    foreach (values %srv) {
        eval { $_->call_hook('stdout', $str); };
    }
    $_->($str) foreach values %outh;
}
our @errh;
our $inerrh = 0;
sub herr { $errh{ $errhn++ } = $_[0]; return $errhn - 1 }

sub errh {
    my ($str) = @_;
    return if $inerrh;
    local $inerrh = 1;
    MegaHAL::Telnet::errh($str);
    foreach (values %srv) {
        eval { $_->call_hook('stderr', $str); };
    }
    $_->($str) foreach values %errh;
}

our $cfg = {};
our $extip;

sub init {
    load();
    MegaHAL::ACL::init();    #Connect to ACL database
    MegaHAL::Telnet::init();
    $c->recv;
}

sub load {
    if (-e 'megahal.yml') {
        $cfg   = LoadFile('megahal.yml');
        $extip = $cfg->{'extip'};
        foreach (keys %{ $cfg->{'servers'} }) {
            $srv{$_} = new MegaHAL::Server() if not $srv{$_};
            $srv{$_}->load($cfg->{'servers'}->{$_});
            $srv{$_}->{'name'} = $_;
        }
    }
    if (!$extip) {
        http_get 'http://automation.whatismyip.com/n09230945.asp', sub {
            $extip = $_[0];
          }
    }
}

sub save {
    $cfg->{'servers'} = { map { ($_, $srv{$_}->save()) } keys %srv };
    DumpFile('megahal.yml', $cfg);
}

sub a2h {
    my %h;
    foreach (@_) { $h{$_}++; }
    return %h;
}

END {
    $rl->hide if $rl;
}

#$iface, $pd, $opts, @args
our $core_cmds = [
    {},
    {   name => [ 'quit', 'q' ],
        cb   => sub       { exit; },
    },
    {   name => [ 'connect', 'con' ],
        args => ['server'],
        cb   => sub {
            my ($i, $pd, $opts, @args) = @_;
            $::srv{ $pd->{server} }->connect();
          }
    },
    {   name => [ 'disconnect', 'dis' ],
        args => [ 'cserver',    'string?' ],
        cb   => sub {
            my ($i, $pd, $opts, @args) = @_;
            $::srv{ $pd->{server} }->disconnect($args[0]);
          }
    },
    {   name => [ 'server', 'srv' ],
        args => [],
        cb   => sub {
            my ($i, $pd, $opts, @args) = @_;
            $i->write(join " ", keys %srv);
        },
        kids => [ {
                name => [ 'create', 'new', 'add' ],
                args => [ 'string', 'string?' ],
                sopts => [ 'ip|server|addr|address=s', 'port=s', 'nick|nickname=s', 'user|username=s', 'pass|password=s', 'auth=s', 'authpw|nspw=s', 'real|gecos|realname=s', 'ssl!' ],
                cb    => sub {
                    my ($i, $pd, $opts, @args) = @_;
                    my %o = (
                        'port'   => '6667',
                        'ssl'    => '0',
                        'nick'   => 'MegaHAL',
                        'user'   => 'megahal',
                        'real'   => 'MegaHAL',
                        'pass'   => '',
                        'auth'   => 'nickserv',
                        'authpw' => ''
                    );
                    $o{'name'} = shift @args;
                    if ($srv{ $o{'name'} }) {
                        die "Server ${o{name}} already exists!\n";
                    }
                    $o{$_} = $opts->{$_} foreach keys %$opts;
                    if (!$o{'ip'}) {
                        if ($args[0] =~ /^(?:(?<nick>[^@]+)@)?(?<addr>[0-9:a-zA-Z.]+?)(?::(?<port>\+?\d+))?$/) {
                            $o{'ip'}   = $+{'addr'};
                            $o{'port'} = $+{'port'} if $+{'port'};
                            $o{'nick'} = $+{'nick'} if $+{'nick'};
                            if ($args[1]) {
                                $o{'port'} = $_[1];
                            }
                            if ($args[2]) {
                                $o{'pass'} = $_[2];
                            }
                        } else {
                            die "Failed to add server - no address provided!\n";
                            return;
                        }
                    }
                    if ($o{'port'} =~ /^\+/) {
                        $o{'port'} = substr $o{'port'}, 1;
                        $o{'ssl'} = 1;
                    }
                    $srv{ $o{'name'} } = new MegaHAL::Server(\%o);
                    $i->write("Server ${o{name}} added successfully\n");
                  }
            }
        ]
    },
    {   name => [ 'server', 'srv' ],
        args => ['string'],
        kids => [ {
                name => [ 'set',    'edit' ],
                args => [ 'string', 'string' ],
                cb   => sub {
                    my ($i, $pd, $opts, @args) = @_;
                    my %keys = map { $_, 1 } qw(port ssl nick user real pass auth authpw reconnect ping ip oper extip);
                    die "No such option: $args[1]!\n" unless $keys{ $args[1] };
                    $srv{ $args[0] }->{ $args[1] } = $args[2];
                    $i->write("[$args[0]] Set $args[1] to '$args[2]'");
                  }
            },
            {   name => [ 'delete', 'del' ],
                cb   => sub {
                    my ($i, $pd, $opts, @args) = @_;
                    delete $srv{ $args[0] };
                  }
            }
        ]
    },
    {   name => [ 'eval', 'e' ],
        args => ['string+'],
        cb   => sub {
            my ($i, $pd, $opts, @args) = @_;
            $i->write(eval $args[0]);
          }
    },
    {   name => [ 'print', 'p' ],
        args => ['string+'],
        cb   => sub {
            my ($i, $pd, $opts, @args) = @_;
            $i->write(Dump @args);
          }
    },
    {   name => [ 'help', 'h' ],
        args => ['*'],
        cb   => sub {
            my ($iface, $pd, $opts, @args) = @_;
            $iface->write(MegaHAL::Shell::help(cmdtree(), @args));
          }
    },
    {    #XXX legacy plugin command hook
        name => [ 'c',      'command' ],
        args => [ 'server', '*' ],
        cb   => sub {
            my ($i, $pd, $opts, @args) = @_;
            $srv{ $args[0] }->call_hook('consoleCommand', @args);
            $srv{ $args[0] }->call_hook('iConsoleCommand', $i, @args);
          }
    }
];

sub cmdtree {
    [ $core_cmds, map { $_->commands() } grep { ref $_ eq 'MegaHAL::Server' } values %srv ];
}

sub console {
    my ($line, $iface) = @_;
    print Dump cmdtree;
    MegaHAL::Shell::parse($iface, $line, cmdtree(), {});
}
init();
