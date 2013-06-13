package MegaHAL::Plugin::WZLobby;
use Text::Glob qw(glob_to_regex);
use AnyEvent::Socket;
use AnyEvent::Handle;
use EV;
use Safe;
use utf8;
use feature 'switch';

sub new {
    my ($class, $serv) = @_;
    my $self = { 'chans' => {}, 'bl' => [], 'timers' => [], 'socket' => undef, 'socket_busy' => 0 };
    $serv->reg_cb(
        'publicmsg' => sub {
            my ($this,  $nick, $ircmsg) = @_;
            my ($modes, $nick, $ident)  = $this->split_nick_mode($ircmsg->{'prefix'});
            my $command = $ircmsg->{'command'};
            my $chan    = lc($ircmsg->{'params'}->[0]);
            my $message = $ircmsg->{'params'}->[1];
            my $mstr    = join '', keys %{$modes};
            return if $command ne 'PRIVMSG' or $this->is_my_nick($nick);
            if ($self->{'chans'}->{ lc($chan) }) {
                if (!(hmatch($self->{'bl'}, $nick, $ident)) && $message=~/#!wz/) {
                    my ($B, $C, $U, $O, $V) = ("\cB", "\cC", "\c_", "\cO", "\cV");
                    my $cv=$self->getData();
                    $cv->cb(sub {
                        my $dat=$_[0]->recv;
                        my $str;
                        if (ref($dat) eq 'ARRAY') {
                            $str="Games in lobby: ";
                            if (scalar(@dat) == 0) {
                                $str.="${C}5none";
                            }else{
                                $str.=join " | ", map {sprintf "[%s] %s by %s (wz %s) at %s", $_->{name}, $_->{mapname}, $_->{hostname}, $_->{versionstring}, $_->{host}} @$dat;
                            }
                        }else{
                            $str="${C}5Error: $dat";
                        }
                        $serv->msg($chan,$str);
                    });
                    return;
                }
            }
        }
    );
    return bless $self, $class;
}

sub getData {
    my ($self)=@_;
    my $cv=AnyEvent->condvar;
    if ($self->{socket_busy}) {
        $self->{socket_busy}->cb(sub {
            $self->getData()->cb(sub {
                $cv->send($_[0]->recv);
            });
        });
        return $cv;
    }
    if (!$self->{socket}) {
        $self->reconnect->cb(sub {
            $self->getData()->cb(sub {
                $cv->send($_[0]->recv());
            });
        });
    }else{
        $self->{socket}->push_write("LIST\n\r");
        my $preflen=3+4*2+4;
        my $gamelen=60+4*2+40+4*6+40*2+159+40*2+64+255+4*7+1;
        my $gamestr='L>L>a64l>l>a40l>l>(l>)4(a40)2a159a40a40a64a255(LLLLLLLc)>a*';
        my @games;
        my $ng;
        $ng=sub {
            my ($hdl,$dat)=@_;
            if (substr($dat,-5,1) eq "\0") { #welcome msg
                $self->{socket}->unshift_read(chunk => 256, sub {
                    my $welcome=(unpack('xZ*',$_[1]))[-1];
                    if ($welcome!~/Welcome/) {
                        print "WZLobby: Reconnecting ('$welcome')!\n";
                        $self->reconnect->cb(sub {
                            $cv->send("Had to reconnect. Try again, please.");
                        });
                    }else {
                        $cv->send(\@games);
                    }
                    undef $ng;
                });
            }else{
                $self->{socket}->unshift_read(chunk => $gamelen, sub {
                    my (
                        $GAMESTRUCT_VERSION,
                        $rubbish_01,
                        $name,
                        $dwSize,$dwFlags,
                        $host,
                        $maxPlayers,$currentPlayers,
                        $uFlag1,$uFlag2,$uFlag3,$uFlag4,
                        $secondaryHost1,$secondaryHost2,
                        $extra,
                        $mapname,
                        $hostname,
                        $versionstring,
                        $modlist,
                        $version_major,
                        $version_minor,
                        $privateGame,
                        $pureGame,
                        $Mods,
                        $gameId,
                        $limits,
                        $future3,#$future4,
                        $buf_2
                    )=unpack($gamestr,$_[1]);
                    push @games, {
                        name => trimnul($name),
                        dwSize => $dwSize,
                        dwFlags => $dwFlags,
                        host => trimnul($host),
                        maxPlayers => $maxPlayers,
                        players => $currentPlayers,
                        uFlags => [$uFlag1,$uFlag2,$uFlag3,$uFlag4],
                        secondaryHosts => [$secondaryHost1,$secondaryHost2],
                        extra => trimnul($extra),
                        mapname => trimnul($mapname),
                        hostname => trimnul($hostname),
                        version => trimnul($versionstring),
                        mods => trimnul($modlist),
                        private => $privateGame,
                        pure => $pureGame,
                        limits => $limits
                    };
                    $self->{socket}->push_read(chunk => $preflen, $ng);
                });
            }
        };
        $self->{socket}->push_read(chunk => $preflen, $ng);
    }
    return $cv;
}

sub trimnul {
	my ($str)=@_;
	$str=~s/\0+$//;
	return $str;
}

sub reconnect {
    my ($self)=@_;
    my $cv=AnyEvent->condvar;
    if ($self->{socket}) {
        my $cv2=AnyEvent->condvar;
        $self->{socket}->on_drain(sub {
            shutdown $_[0]{fh}, 1;
            $cv2->send;
        });
        $self->{socket}->low_water_mark(0);
        $cv2->cb(sub {
            $self->reconnect()->cb(sub{
                $cv->send($_[0]->recv);
            });
        });
    }else{
        tcp_connect("lobby.wz2100.net",9990,sub {
            $cv->send();
        });
    }
    return $cv;
}

sub hmatch {
    my ($ref, $nick, $mask) = @_;
    my $mstr = $nick . '!' . $mask;
    foreach (@$ref) {
        $_ = MegaHAL::Plugin::WZLobby::CGlobPat->new($_) if not ref $_;
        return 1 if $mstr =~ $_;
    }
    return 0;
}

sub load {
    my ($self, $data) = @_;
    if (ref $data eq 'ARRAY') {
        $self->{'chans'} = $data->[0];
        $self->{'bl'}    = $data->[1]->{'bl'};
    } else {
        $self->{'chans'} = $data;
    }
}

sub save {
    my ($self) = @_;
    return [ $self->{'chans'}, { 'bl' => [ map { ref $_ ? $_->str : $_ } @{ $self->{'bl'} } ] } ];
}

1;

package MegaHAL::Plugin::WZLobby::CGlobPat;
use Text::Glob qw(glob_to_regex);

use overload
  '""'     => sub { $_[0]->[0] },
  'qr'     => sub { $_[0]->[1] },
  '0+'     => sub { 0 + $_[0]->[0] },
  'bool'   => sub { $_[0]->[0] },
  fallback => 1;

sub new {
    my ($class, $str, $re) = @_;
    return bless [ $str, $re || glob_to_regex($str) ], $class;
}

sub str { $_[0]->[0] }
sub re  { $_[0]->[1] }

1;
