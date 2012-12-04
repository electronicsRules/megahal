package MegaHAL::Shell;
use Text::ParseWords;
use MegaHAL::Shellquote;
use Getopt::Long;
use Carp;
use feature 'switch';

sub parse {
    my ($iface, $str, $tree) = @_;
    croak "Specify interface as the first argument!\n" unless UNIVERSAL::isa($iface, MegaHAL::Interface);
    croak "Specify command tree as the third argument!\n" unless ref $tree eq 'ARRAY';
    my $sq = new MegaHAL::Shellquote(sub { &parse($iface, $_[0], $tree) });
    my @args = $sq->parse($str);
    Getopt::Long::Configure(qw(default require_order pass_through));
    match($iface, $tree, [], {}, [], @args);
}

sub match {
    my ($iface, $tree, $_stk, $_pd, $_targs, @args) = @_;
    my @stk   = @$_stk;
    my %pd    = %$_pd;
    my %opts  = $pd{opts};
    my @targs = @$_targs;
    my $name  = shift @args;
    OUTER: foreach my $i (@$tree) {
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
        local @args  = @args;
        local @targs = @targs;
        my %opts;
        if ($i->{'opts'}) {
            $iface->cerr();
            my $ret = GetOptionsFromArray(\@args, \%opts, @{ $i->{'opts'} });
            $iface->ecerr();
            next unless $ret;
        }
        foreach (@{ $i->{'args'} }) {
            given ($_) {
                when ('string') {
                    push @targs, shift @args;
                }
                when ('string+') {    #XXX: Does *not* solve the quoting problem completely. Shellquote.pm will need hackery.
                    push @targs, join ' ', @args;
                    @args = ();
                    last;
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
                    } else {
                        error($iface, [ @stk, $cname ], "No such server!");
                    }
                }
            }
        }
        if ($i->{'sopts'}) {
            $iface->cerr();
            my $ret = GetOptionsFromArray(\@args, \%opts, @{ $i->{'sopts'} });
            $iface->ecerr();
            next unless $ret;
        }
        if ($i->{'sub'} and $args[0]) {
            return if match($iface, $i->{'sub'}, [ @stk, $cname ], \%pd, \@targs, @args);
        }
        if ($i->{'cb'}) {
            $i->{'cb'}->($iface, \%pd, \%opts, @targs);
            return 1;
        }
    }
    return 0;
}

sub error {
    my ($iface, $stk, $text) = @_;
    $iface->write("\cC5" . (join " ", @$stk) . " " . $text);
}

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
