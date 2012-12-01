package MegaHAL::Plugin::BotDB;
use feature 'switch';
use MegaHAL::Cache qw(cache_http);
use AnyEvent::HTTP;
use JSON::XS;
use YAML::Any qw(Dump LoadFile);
use Text::ParseWords;

sub new {
    my ($class, $serv) = @_;
    my $self = { 'chans' => {} };
    $secret = LoadFile('BotDB_API_secret.yml');
    my $id = time;
    $serv->reg_cb(
        'publicmsg' => sub {
            my ($this, $nick, $ircmsg) = @_;
            #print "Callback $id\n";
            #print Dumper($ircmsg)."\n";
            my ($modes, $nick, $ident) = $this->split_nick_mode($ircmsg->{'prefix'});
            my $command = $ircmsg->{'command'};
            my $chan    = $ircmsg->{'params'}->[0];
            my $message = $ircmsg->{'params'}->[1];
            my $mstr    = join '', keys %{$modes};
            return if $command ne 'PRIVMSG' or $this->is_my_nick($nick);
            #print "1 $chan $message\n";
            if ($self->{'chans'}->{$chan}) {
                #print "2 $chan $message\n";
                if ($message =~ /^#!/) {
                    my ($cmd, @args) = shellwords(substr $message, length('#!'));
                    if ($cmd eq 'bot') {
                        my ($B, $C, $U, $O, $V) = ("\cB", "\cC", "\c_", "\cO", "\cV");
                        my $query = 'name';
                        my $qval  = '';
                        if ($args[0] =~ /^#?\d+$/) {
                            $query = 'id';
                            $args[0] =~ /^#?(\d+)$/;
                            $qval = $1;
                        } elsif ($args[0] eq 'owner') {
                            $query = 'owner';
                            $qval  = $args[1];
                        } elsif ($args[0] eq 'id') {
                            $query = 'id';
                            $qval  = $args[1];
                        } elsif ($args[0] eq 'name') {
                            $query = 'name';
                            $qval  = $args[1];
                        } elsif ($args[0]) {
                            $qval = $args[0];
                        } else {
                            $serv->send_long_message('utf8', 0, 'PRIVMSG' => $chan, "${C}4${B}${p}bot${B} #[${U}id${U}]|[${U}name${U}]|id [${U}id${U}]|name [${U}name${U}]|owner [${U}owner${U}]");
                            return;
                        }
                        print "Fetching bot query ($query = $qval) for $nick in $chan...";
                        cache_http(
                            ('http://azunyan.afterlifelochie.net/botdb/api/find-bot.php?' . $secret . '&' . $query . '=' . $qval),
                            'botdb:' . ($query . '=' . $qval),
                            60 * 15,
                            sub {
                                print "Fetched bot query ($query = $qval)!";
                                return 0 if not $_[0];
                                my $dat;
                                eval { $dat = decode_json($_[0]); };
                                if ($@) {
                                    print $@;
                                    return 0;
                                }
                                if (ref $dat eq 'HASH') {    #error
                                    $serv->send_long_message('utf8', 0, 'PRIVMSG' => $chan, "$nick: ${C}4${B}ERROR:${O} \"" . $dat->{'error'} . "\" (" . $dat->{'help'} . ")");
                                    return 0;
                                }
                                if (scalar(@$dat) == 1) {
                                    my $b = $dat->[0];
                                    my $botid, $botname, $botowner, $botdesc, $botnsname, $prefix, $ownerver;
                                    $botid     = $b->{'botid'};
                                    $botname   = $b->{'botname'};
                                    $botowner  = $b->{'botowner'};
                                    $botdesc   = $b->{'botshortdesc'};
                                    $botnsname = $b->{'botnickservname'};
                                    my $temp = $b->{'commandprefix'};
                                    #$temp=~s/\"//g;
                                    $temp = substr $temp, 1, -1;
                                    my @prefixes = split /,/, $temp;
                                    $prefix   = join ",", (splice @prefixes, 1);
                                    $ownerver = $b->{'ownerverified'};
                                    $botowner = "${C}" . ($ownerver ? 3 : 4) . "$botowner${O}";
                                    #$botdesc=~s#<b>([^<]+?)</b>#${B}$1${B}#ig;
                                    #if (length($botdesc) > 300) {
                                    #    $botdesc=~s/^([^<]+)/$1/;
                                    #    if (length($botdesc) > 300) {
                                    #        $botdesc=(substr $botdesc,0,255).'[...]';
                                    #    }
                                    #}else{
                                    #    $botdesc=~s/<[^>]+?>//g;
                                    #}
                                    $serv->send_long_message('utf8', 0, 'PRIVMSG' => $chan, "$botname [#$botid] [${B}Owner:${O}$botowner" . ($botnsname ne $botname && $botnsname ne '' ? ",${B}NickServ name:${O}$botnsname" : "") . ($prefix ? ",${B}Prefix${O}:$prefix" : '') . "] $botdesc");
                                } else {
                                    $serv->send_long_message('utf8', 0, 'PRIVMSG' => $chan, "Multiple results [" . (join ",", (map { '#' . $_->{'botid'} . ':' . $_->{'botname'} } @{$dat})) . "]");
                                }
                            },
                            $query . '=' . $qval
                        );
                    }
                }
            }
        }
    );
    return bless $self, $class;
}

sub load {
    my ($self, $data) = @_;
    $self->{'chans'} = $data;
}

sub save {
    my ($self) = @_;
    return $self->{'chans'};
}
