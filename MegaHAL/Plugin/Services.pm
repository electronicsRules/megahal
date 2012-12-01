package MegaHAL::Plugin::Services;
use MegaHAL::Interface::PM;
use feature 'switch';
use AnyEvent::HTTP;
use JSON::XS;
use YAML::Any qw(Dump);
use Text::ParseWords;

sub new {
    my ($class, $serv) = @_;
    my $self = {
        'chans' => {},
        'users' => {}
    };
    my $id = time;
    $serv->reg_cb(
        'join' => sub {
            my ($this, $nick, $chan, $is_myself) = @_;
            #print "$nick joined $chan!\n";
            return if $is_myself;
            if ($self->{'chans'}->{$chan}->{$nick}->{'modes'}) {
                $serv->auth(
                    $nick, $chan,
                    sub {
                        $serv->send_srv(MODE => $chan, $_, $nick) foreach split //, $self->{'chans'}->{$chan}->{$nick}->{'modes'};
                    }
                );
            }
        }
    );
    $serv->reg_cb(
        'iConsoleCommand' => sub {
            my ($this, $iface, $cmd, @args) = @_;
            if ($cmd eq 'service') {
                given ($args[0]) {
                    when ('register') {
                        return if not $_[0];
                        if ($serv->is_channel_name($args[1])) {
                            $self->{'chans'}->{ $args[1] } = { $args[2] => { 'founder' => 1 } };
                            $iface->write("$args[1] registered with $args[2] as founder");
                        } else {
                            $iface->write("\cC4$args[1] is not a channel name!");
                        }
                    }
                    when ('drop') {
                        return if not $_[0];
                        delete $self->{'chans'}->{ $args[1] };
                        $iface->write("$args[1] dropped.");
                    }
                }
            }
        }
    );
    $serv->reg_cb(
        'privatemsg' => sub {
            my ($this,  $nick, $ircmsg) = @_;
            my ($modes, $nick, $ident)  = $serv->split_nick_mode($ircmsg->{'prefix'});
            my $command = $ircmsg->{'command'};
            my $message = $ircmsg->{'params'}->[1];
            my $mstr    = join '', keys %$modes;
            return if $command ne 'PRIVMSG';
            my ($cmd, @args) = shellwords($message);
            $self->{'users'}->{$nick} = new MegaHAL::Interface::PM($serv->name(), $nick) if not $self->{'users'}->{$nick};
            given ($cmd) {
                when ('setmode') {
                    return if not $serv->is_channel_name($args[0]);
                    $self->{'users'}->{$nick}->acan(
                        'Services',
                        'override',
                        $args[0],
                        sub {
                            return unless $_[0] or $self->{'chans'}->{ $args[0] }->{$nick}->{'founder'};
                            return if not $_[0] and $self->{'chans'}->{ $args[0] }->{ $args[1] }->{'founder'};
                            if ($args[2]) {
                                $self->{'chans'}->{ $args[0] }->{ $args[1] }->{'modes'} = $args[2];
                                $self->{'users'}->{$nick}->write("Modes $args[2] set for $args[1] in channel $args[0].");
                            } else {
                                delete $self->{'chans'}->{ $args[0] }->{ $args[1] };
                            }
                        }
                    );
                }
                when ('listmode') {
                    return if not $serv->is_channel_name($args[0]);
                    $self->{'users'}->{$nick}->acan(
                        'Services',
                        'override',
                        $args[0],
                        sub {
                            return unless $_[0] or $self->{'chans'}->{ $args[0] }->{$nick}->{'founder'};
                            my $str = join ", ", map { $_ . ' ' . $self->{'chans'}->{ $args[0] }->{$_}->{'modes'} } keys %{ $self->{'chans'}->{ $args[0] } };
                        }
                    );
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
1;
