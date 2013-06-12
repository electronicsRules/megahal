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
use Term::ANSIColor qw(colorstrip);
use MegaHAL::Telnet;
our $VERSION = '1.5';
our @cmdt;
my $old_stdout;
open($old_stdout, '>&STDOUT') or die "Can't dup STDOUT!\n";
my $c = AnyEvent->condvar;
our %srv;
our $cif = MegaHAL::Interface::Console->new();
our $rl;
if (1 || !defined(&DB::DB)) {
    $rl = AnyEvent::ReadLine::Gnu->new(
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
#open(CONOUT, '>&', $old_stdout) or die "Can't dup STDOUT for CONOUT!\n";
tie(*CONOUT, 'MegaHAL::Filehandle', $old_stdout, $rl, sub { });

sub dbghook {
    print '';
}

sub outh {
    my ($str) = @_;
    MegaHAL::Telnet::outh($str);
    foreach (values %srv) {
        eval { $_->call_hook('stdout', $str); };
    }
}

sub errh {
    my ($str) = @_;
    MegaHAL::Telnet::errh($str);
    foreach (values %srv) {
        eval { $_->call_hook('stderr', $str); };
    }
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
our $default = \('_default');
@cmdt = (
    qr/^q(?:uit)?$/ => [
        '', 's',
        sub {
            if ($_[1] eq '-f') {
                exit();
            } else {
                my $cv = AnyEvent->condvar;
                $cv->begin(sub { $c->send; });
                foreach (values %srv) {
                    $cv->begin();
                    $_->disconnect(
                        $_[1] || 'Quit',
                        0,
                        sub {
                            $cv->end();
                        }
                    );
                }
                $cv->end();
            }
          }
    ],
    qr/^(?:re)?(?:(?:load)|(?:hash))$/ => [
        '', '',
        sub {
            load();
            $_[0]->write("Loaded!\n");
          }
    ],
    'save' => [
        '', '',
        sub {
            save();
            $_[0]->write("Saved!\n");
          }
    ],
    qr/^con(?:nect)?$/ => [
        '_server',
        '',
        sub {
            my ($i, $s) = @_;
            if ($srv{$s} && $srv{$s}->is_connecting()) {
                $i->write("\cC4Already connected to $s!\n");
            } else {
                $i->write("[$s] Connecting...\n");
                my $r = $srv{$s}->connect();
                if ($r == 0) {
                    $i->write("[$s] Plugins loaded OK\n");
                } else {
                    $i->write("\cC4Error connecting to $s: " . $r->[0]);
                }
            }
          }
    ],
    qr/^dis(?:con(?:nect)?)?$/ => [
        '_server',
        's',
        sub {
            my ($i, $s, $msg) = @_;
            if ($srv{$s} && $srv{$s}->is_connecting()) {
                $srv{$s}->disconnect($msg);
            } else {
                $i->write("\cC4$s is not connected!\n");
            }
          }
    ],
    qr/^mod(?:ule)?$/ => [
        'server', '',
        [
            qr/^l(?:oad)?$/ => [
                '_plugin',
                '',
                sub {
                    my ($i, $s, $p) = @_;
                    if ($srv{$s}->is_loaded($p)) {
                        $i->write("\cC4$p is already loaded on $s!\n");
                        return;
                    }
                    $i->write("[$s] Loading $p...\n");
                    my $r = $srv{$s}->load_plugin($p);
                    if ($r == 0) {
                        $i->write("[$s] Loaded $p successfully\n");
                    } else {
                        $i->write("[$s] \cC4Error while loading $p: " . ($r->[0]));
                    }
                  }
            ],
            qr/^u(?:nload)?$/ => [
                '_plugin',
                '',
                sub {
                    my ($i, $s, $p) = @_;
                    if (!$srv{$s}->is_loaded($p)) {
                        $i->write("\cC4$p is not loaded on $s!\n");
                        return;
                    }
                    $i->write("[$s] Unloading $p...\n");
                    my $r = $srv{$s}->unload_plugin($p);
                    if ($r == 0) {
                        $i->write("[$s] Unloaded $p successfully\n");
                    } else {
                        $i->write("[$s] \cC4Error while unloading $p: " . ($r->[0]));
                    }
                  }
            ],
            qr/^r(?:eload)?$/ => [
                '_plugin',
                '',
                sub {
                    my ($i, $s, $p) = @_;
                    if (!$srv{$s}->is_loaded($p)) {
                        $i->write("\cC4$p is not loaded on $s!\n");
                        return;
                    }
                    $i->write("[$s] Unloading $p...\n");
                    my $r = $srv{$s}->unload_plugin($p);
                    if ($r == 0) {
                        $i->write("[$s] Unloaded $p successfully\n");
                    } else {
                        $i->write("[$s] \cC4Error while unloading $p: " . ($r->[0]));
                    }
                    if ($srv{$s}->is_loaded($p)) {
                        $i->write("\cC4$p is already loaded on $s!\n");
                        return;
                    }
                    $i->write("[$s] Loading $p...\n");
                    my $r = $srv{$s}->load_plugin($p);
                    if ($r == 0) {
                        $i->write("[$s] Loaded $p successfully\n");
                    } else {
                        $i->write("[$s] \cC4Error while loading $p: " . ($r->[0]));
                    }
                  }
            ],
            qr/^l(?:ist)?$/ => [
                '', '',
                sub {
                    my ($i, $s) = @_;
                    $i->write("Plugins: " . (join ", ", ($srv{$s}->list_plugins())) . "\n");
                  }
            ],
            $default => [
                '', '',
                sub {
                    my ($i, $s) = @_;
                    $i->write("Plugins: " . (join ", ", ($srv{$s}->list_plugins())) . "\n");
                  }
            ]
        ]
    ],
    qr/^se?rv(?:er)?$/ => [
        '',
        '',
        [
            qr/^a(?:dd)?$/ => [
                '', undef,
                sub {
                    my $i = shift @_;
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
                    $o{'name'} = shift @_;
                    if ($srv{ $o{'name'} }) {
                        $i->write("\cC4Server ${o{name}} already exists!\n");
                        return;
                    }
                    GetOptionsFromArray(\@_, \%o, 'port=s', 'ssl!', 'nick|nickname=s', 'pass|password=s', 'auth=s', 'authpw|nspw=s', 'ip|server|addr|address=s');
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
                            $i->write("\cC4Failed to add server - no address provided!\n");
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
            ],
            qr/^d(?:el)?$/ => [
                '_server',
                '',
                sub {
                    my ($i, $s) = @_;
                    $i->write("[$s] Disconnecting...") if $srv{$s}->is_connecting();
                    $srv{$s}->disconnect();
                    delete $srv{$s};
                    $i->write("[$s] Deleted!");
                  }
            ],
            qr/^s(?:et)?$/ => [
                '_server',
                '',
                sub {
                    $i = shift @_;
                    my %o = a2h(qw(port ssl nick pass auth authpw ip oper reconnect ping extip));
                    if ($o{ $_[1] }) {
                        $i->write("[$_[0]] Set $_[1] to $_[2]\n");
                        $srv{ $_[0] }->{ $_[1] } = $_[2];
                    } else {
                        $i->write("\cC4No such option ${$_[1]}!\n");
                    }
                  }
            ],
            qr/^l(?:ist)?$/ => [
                '', '',
                sub {
                    $_[0]->write(join " ", map { $srv{$_}->is_connecting() ? "\cC3$_ [UP]\cO" : "\cC5$_\cO" } keys %srv);
                  }
            ],
            $default => [
                '', '',
                sub {
                    $_[0]->write(join " ", map { $srv{$_}->is_connecting() ? "\cC3$_ [UP]\cO" : "\cC5$_\cO" } keys %srv);
                  }
            ]
        ]
    ],
    qr/^a(?:cl)?$/ => [
        '',
        '',
        [
            qr/^c(?:reate)?$/ => [
                '', 'SS',
                sub {
                    my ($i, $u, $p) = @_;
                    my $rv = MegaHAL::ACL::new_user($u, $p);
                    if ($rv) {
                        $i->write('User ' . $u . ' created');
                    } else {
                        $i->write("\cC4Error! User " . $u . ' probably already exists.');
                    }
                  }
            ],
            qr/^d(?:(?:elete)|(?:estroy))?/ => [
                'user', '',
                sub {
                    my ($i, $u) = @_;
                    my $rv = MegaHAL::ACL::del_user($u);
                    if ($rv) {
                        $i->write("User $u deleted!");
                    } else {
                        $i->write("\cC4Error deleting user $u!");
                    }
                  }
            ],
            qr/^l(?:ist)?$/ => [
                '', '',
                sub {
                    # XXX TODO!
                  }
            ],
            qr/^a(?:llow)?$/ => [
                '', undef,
                sub {
                    my $i = shift @_;
                    my $rv;
                    my ($plugin, $node) = split /\./, $_[-1];
                    if (not $node) {
                        $plugin = 'core';
                        $node   = $_[-1];
                    }
                    if ($_[2]) {    #irc
                        if ($srv{ $_[0] }) {
                            my ($_nick, $_chan) = split /\@/, $_[1];
                            $_nick = $_[1] if not $_nick;
                            $rv = MegaHAL::ACL::add_ircacl($_[0], $_nick, $plugin, $node, $_chan);
                        } else {
                            $i->write("\cC4No such server!");
                            return;
                        }
                    } else {        #acl
                        if (MegaHAL::ACL::exists_user($_[0])) {
                            $rv = MegaHAL::ACL::add_acl($_[0], $plugin, $node);
                        } else {
                            $i->write("\cC4User not found!");
                        }
                    }
                    if ($rv) {
                        $i->write('OK');
                    } else {
                        $i->write("\cC4Error!");
                    }
                  }
            ],
            qr/^(?:(?:d(?:eny)?)|(?:f(?:orbid)?))$/ => [
                '', undef,
                sub {
                    my $i = shift @_;
                    my $rv;
                    my ($plugin, $node) = split /\./, $_[-1];
                    if (not $node) {
                        $plugin = undef;
                        $node   = $_[-1];
                    }
                    if ($_[2]) {    #irc
                        if ($srv{ $_[0] }) {
                            my ($_nick, $_chan) = split /\@/, $args[1];
                            $_nick = $_[1] if not $_nick;
                            if (defined $_chan) {
                                $rv = MegaHAL::ACL::del_chanircacl($_[0], $_nick, $plugin, $node, $_chan);
                            } else {
                                $rv = MegaHAL::ACL::del_ircacl($_[0], $_nick, $plugin, $node);
                            }
                        } else {
                            $i->write("\cC4No such server!");
                            return;
                        }
                    } else {    #acl
                        if (MegaHAL::ACL::user_exists($_[0])) {
                            $rv = MegaHAL::ACL::del_acl($_[0], $plugin, $node);
                        } else {
                            $i->write("\cC4User not found!");
                        }
                    }
                    if ($rv) {
                        $i->write('OK');
                    } else {
                        $i->write("\cC4Error!");
                    }
                  }
            ],
            #TODO
            #qr/^l(?:ist)?$/ => ['',undef,[
            #
            #]]
        ]
    ],
    qr/^r(?:aw)?$/ => [
        'server',
        undef,
        sub {
            my ($i, @args) = @_;
            $srv{ $args[0] }->send_srv($args[1] => (splice @args, 2));
          }
    ],
    'c' => [
        'server', undef,
        sub {
            my ($i, @args) = @_;
            my $s = shift @args;
            $srv{$s}->call_hook('consoleCommand', @args);
            $srv{$s}->call_hook('iConsoleCommand', $i, @args);
          }
    ],
    'e' => [
        '', undef,
        sub {
            my ($i, @args) = @_;
            $i->write(eval(join ' ', @args));
          }
    ]
);

sub console {
    my ($line, $iface) = @_;
    return if $line eq '';
    die "Legacy console usage!\n" unless $iface;
    my ($cmd, @args) = shellwords($line);
    $iface->auth(
        sub {
            command($iface, $cmd, \@args, [], \@cmdt, [], 0, 'core') or $iface->write("\cC4No such command!\n");
        }
    );
}

sub command {
    # Put arguments into $scmd, they are moved to $args as necessary by tags/type
    my ($iface, $cmd, $scmd, $args, $tree, $parents, $blanket, $plugin) = @_;
    if (scalar(@$tree) % 2 != 0) {
        die "Odd number of arguments in command tree (@$parents $cmd)!\n";
    }
    foreach (0 .. (scalar(@$tree) - 1) / 2) {
        my $match = $tree->[ $_ * 2 ];
        if (ref $match eq 'Regexp') {
            next unless lc($cmd) =~ $match;
        } elsif ($match eq $default) {
            next unless $cmd eq '';
        } elsif (ref $match) {
            die "Command tree keys should be strings or regexes (@$parents $cmd)!\n";
        } else {
            next unless lc($cmd) eq $match;
        }
        my $subt  = $tree->[ ($_ * 2) + 1 ];
        my $type  = $subt->[0];
        my $argn  = scalar(@$parents) + 1;
        my $nargm = 0;
        given ($type) {
            when ('server') {
                unless ($srv{ $scmd->[0] } && $srv{ $scmd->[0] }->is_connected()) {
                    $iface->write("\cC4Invalid arguments for @$parents $cmd, argument $argn should be a connected server.\n");
                    return -1;
                }
                $nargm++;
            }
            when ('_server') {
                unless ($srv{ $scmd->[0] }) {
                    $iface->write("\cC4Invalid arguments for @$parents $cmd, argument $argn should be a server.\n");
                    return -1;
                }
                $nargm++;
            }
            when ('splugin') {
                unless ($srv{ $scmd->[0] } && $srv{ $scmd->[0] }->is_connected()) {
                    $iface->write("\cC4Invalid arguments for @$parents $cmd, argument $argn should be a connected server.\n");
                    return -1;
                }
                unless ($srv{ $scmd->[0] }->is_loaded($scmd->[1])) {
                    $iface->write("\cC4Invalid arguments for @$parents $cmd, argument " . ($argn + 1) . " should be a loaded plugin.\n");
                    return -1;
                }
                $nargm += 2;
            }
            when ('plugin') {
                unless ($srv{ $scmd->[0] }->is_loaded($scmd->[0])) {
                    $iface->write("\cC4Invalid arguments for @$parents $cmd, argument " . ($argn + 1) . " should be a loaded plugin.\n");
                    return -1;
                }
                $nargm++;
            }
            when ('user') {
                unless (MegaHAL::ACL::exists_user($scmd->[0])) {
                    $iface->write("\cC4Invalid arguments for @$parents $cmd, argument " . ($argn + 1) . " should be an ACL user.\n");
                    return -1;
                }
                $nargm++;
            }
        }
        #Blanket permissions
        if (!$blanket) {
            if ($iface->acan('*', '*')) {
                $blanket = 1;
            }
            if (($type eq 'server' || $type eq '_server' || $type eq 'splugin') and $iface->acan('*', 'soper@' . $scmd->[0])) {    #soper or above
                $blanket = 1;
            }
            if ($type eq 'plugin' and $iface->acan($scmd->[0], '*')) {
                $blanket = 1;
            }
            if ($type eq 'splugin' and $iface->acan($scmd->[1], '*')) {
                $blanket = 1;
            }
        }
        my $nscmd = [@$scmd];
        my $nargs = [@$args];
        foreach (1 .. $nargm) {
            push @$nargs, (shift @$nscmd);
        }
        if (ref $subt->[2] eq 'CODE') {    #Command
            unless ($blanket || $iface->acan($plugin, (join '.', (@$parents, $cmd)))) {
                $iface->write("\cC4I'm sorry, but I can't let you do that.\n");
                return -1;
            }
            $subt->[2]->($iface, @$nargs, @$nscmd);
            return 1;
        } elsif (ref $subt->[2] eq 'ARRAY') {    #Subtree
            return command($iface, $nscmd->[0], [ splice @$nscmd, 1 ], $nargs, $subt->[2], [ @$parents, $cmd ], $blanket, $plugin);
        } else {
            die "Invalid action (should be CODE or ARRAY reference) at @$parents $cmd!\n";
        }
    }
    return 0;
}

init();
