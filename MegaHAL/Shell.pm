package MegaHAL::Shell;
use Text::ParseWords;
use MegaHAL::Shellquote;
use Getopt::Long;
use Carp;
use feature 'switch';

sub parse {
    my ($iface, $str, $tree, $pd) = @_;
    croak "Specify interface as the first argument!\n" unless UNIVERSAL::isa($iface, MegaHAL::Interface);
    croak "Specify command tree as the third argument!\n" unless ref $tree eq 'ARRAY';
    my $sq = new MegaHAL::Shellquote(sub { &parse($iface, $_[0], $tree) });
    my @args = $sq->split($str);
    Getopt::Long::Configure(qw(default require_order pass_through));
    my @matches;
    eval {
        if (ref $tree->[0] eq 'ARRAY') {
            push @matches, match($iface, $_, [], $pd || {}, [], [], @args) foreach @{$tree};
        } else {
            @matches = match($iface, $tree, [], $pd || {}, [], [], @args);
        }
    };
    return if $@;
    if (scalar(@matches) > 1) {    #Multiple suitable commands.
        $iface->write("\cC5Multiple commands matched.");
        return 2;
    } elsif (scalar(@matches) == 0) {    #No commands.
        $iface->write("\cC5No such command.");
        return 1;
    } else {
        $iface->acan(
            $matches[0]->[1],
            sub {
                if ($_[0]) {
                    $matches[0]->[2]->($iface, splice(@{ $matches[0] }, 3));
                } else {
                    $iface->write("\cC5Access denied.");
                }
            }
        );
        return 0;
    }
}

sub match {
    my ($iface, $tree, $_stk, $_pd, $_targs, $_perms, @args) = @_;
    my @stk  = @$_stk;
    my $name = shift @args;
    my @matches;
    OUTER: foreach my $i (@$tree) {
        my @targs = @$_targs;
        my @perms = @$_perms;
        my %opts  = $pd{opts};
        my %pd    = %$_pd;
        next unless $i->{'name'};
        my $match = 0;
        foreach (ref $i->{'name'} ? @{ $i->{'name'} } : $i->{'name'}) {
            if (lc $name eq lc $_) {
                $match = 1;
                last;
            }
        }
        next if not $match;
        my $cname = ref $i->{'name'} ? $i->{'name'}->[0] : $i->{'name'};
        my %opts;
        if ($i->{'opts'}) {
            $iface->cerr();
            my $ret = GetOptionsFromArray(\@args, \%pd, 'server=s', 'target=s', 'channel=s', 'plugin=s');
            my $ret2 = GetOptionsFromArray(\@args, \%opts, @{ $i->{'opts'} });
            $iface->ecerr();
            next unless $ret and $ret2;
        }
        if (ref $i->{'source'} eq 'HASH') {
            if ($pd{server} and $i->{'source'}->{'server'} and $i->{'source'}->{'server'} ne $pd{server}) {
                next;
            }
            if ($pd{plugin} and $i->{'source'}->{'plugin'} and $i->{'source'}->{'plugin'} ne $pd{plugin}) {
                next;
            }
        }
        push @perms, [ '*', join(".", @stk, $cname) ];
        push @perms, [ '*', join(".", @stk, '*') ];
        push @perms, [ $pd{plugin} || 'core', join(".", @stk, $cname) ];
        push @perms, [ $pd{plugin} || 'core', join(".", @stk, '*') ];
        if ($pd{server}) {
            push @perms, [ '*@' . $pd{server}->name(), join(".", @stk, $cname) ];
            push @perms, [ '*@' . $pd{server}->name(), join(".", @stk, '*') ];
            push @perms, [ $pd{plugin} || 'core@' . $pd{server}->name(), join(".", @stk, $cname) ];
            push @perms, [ $pd{plugin} || 'core@' . $pd{server}->name(), join(".", @stk, '*') ];
        }
        foreach (@{ $i->{'args'} }) {
            my $nea;
            $nea = 1 if not defined $args[0];
            given ($_) {
                when ('string') {
                    push @targs, shift @args;
                }
                when ('string+') {    #XXX: Does *not* solve the quoting problem completely. Shellquote.pm will need hackery.
                    push @targs, join ' ', @args;
                    @args = ();
                    last;
                }
                when ('string?') {
                    push @targs, shift @args;
                    $nea = 0;
                }
                when ('target') {
                    if ($args[0] =~ /^[#&]?[a-zA-Z_0-9-]+$/) {
                        push @targs, shift @args;
                    } else {
                        error($iface, [ @stk, $cname ], "Invalid target!");
                    }
                }
                when ('channel') {
                    if ($pd{server}) {
                        if ($pd{server}->is_channel_name($args[0])) {
                            push @targs, shift @args;
                        } else {
                            error($iface, [ @stk, $cname ], "Not a channel name!");
                        }
                    } else {
                        error($iface, [ @stk, $cname ], "No server specified prior to an argument of type 'channel'!");
                    }
                }
                when ('cserver') {
                    if ($::srv{ $args[0] }) {
                        if ($::srv{ $args[0] }->is_connected()) {
                            $pd{server} = $::srv{ $args[0] };
                            push @targs, shift @args;
                        } else {
                            error($iface, [ @stk, $cname ], "The specified server is not connected.");
                        }
                    } else {
                        error($iface, [ @stk, $cname ], "No such server!");
                    }
                }
                when ('server') {
                    if ($::srv{ $args[0] }) {
                        $pd{server} = $::srv{ $args[0] };
                        push @targs, shift @args;
                    } else {
                        error($iface, [ @stk, $cname ], "No such server!");
                    }
                }
                when ('*') {
                    push @targs, shift @args while @args;
                }
            }
            error($iface, [ @stk, $cname ], "Not enough arguments!");
        }
        if ($i->{'sopts'}) {
            $iface->cerr();
            my $ret = GetOptionsFromArray(\@args, \%opts, @{ $i->{'sopts'} });
            $iface->ecerr();
            next unless $ret;
        }
        if ($i->{'sub'} and $args[0]) {
            push @matches, match($iface, $i->{'sub'}, [ @stk, $cname ], \%pd, \@targs, \@perms, @args);
        }
        if ($i->{'cb'}) {
            if (scalar(@args) > 0) {
                error($iface, [ @stk, $cname ], "Too many arguments!");
            } else {
                push @matches, [ [ @stk, $cname ], \@perms, $i->{'cb'}, \%pd, \%opts, @targs ];
            }
        }
    }
    return @matches;
}

sub help {
    my ($tree, @args) = @_;
    my $subtree = $tree;
    my @help;
    foreach (@{$tree}) {
        push @help, sprintf "%-20s " . ('%-12s ' x scalar(@{ $_->{'args'} })) . " %s", $_->{'name'}->[0], @{ $_->{'args'} }, $_->{'desc'};
        push @help, help($_->{'sub'}, splice(@args, 1)) if $_->{'sub'};
    }
    return join "\n", @help;
}

sub error {
    my ($iface, $stk, $text) = @_;
    $iface->write("\cC5" . $text);
    die $text;
}
1;

=pod

msg --server=highway-all --plugin=PMSyndicate #channel message does not require quotes

commands as hash structures:
#pseudostruct, DO NOT COPY!

    {# Permissions: *.*, *@highway-all.*, PMSyndicate@highway-all.*, _plugin@highway-all.*, PMSyndicate@highway-all.msg, PMSyndicate@*.*, _plugin@*.*, PMSyndicate@*.msg
        name: ['msg'],
        args: ['cserver','target','string+'],
        source: {'server': 'highway-all', 'plugin': 'PMSyndicate'},
    }
    {
        name: ['server','srv'],
        args: ['server'],
        sub: [
            {# Permissions: *.*, core@*.server.*, core@*.server.set, core@highway-all.*, core@*.*, *@highway-all.*, *@highway-all.server.*, *@highway-all.server.set
                name: ['set'],
                args: ['string','string'],
            },
            {# Permissions: *.*, core@*.server.delete, core@*.*
                name: ['delete','del'],
                confirm: 1     #Maybe.
                explicitacl: 1 #Requires explicit permission in the ACL - core@*.server.* is not good enough!
                noserveracl: 1 #All-server permissions required to do stuff - core@highway-all.delete is not good enough!
            }
        ]
    }
    {
        name: ['server','srv'], #also allows for plugins to extend existing top-level commands. not sure how to output help from this.
        sub: [
            {# Permissions: *.*, core@*.server.*, core@*.server.add - since 'server' is not in typed-args, @<server> permissions are not an option.
                name: ['add','new'],
                args: ['string']
                sopts: [
                    'address|ip=s',
                    'port=s',
                    'nick|nickname=s',
                    'user|username=s',
                    'real|gecos|realname=s'
                ]
            }
        ]
    }

=cut
