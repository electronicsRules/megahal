package MegaHAL::Plugin::TimedMbox;
use Text::ParseWords;

sub new {
    my ($class, $serv) = @_;
    my $self;
    $self = {
        'chans' => {},
        'msgs'  => {}
    };
    $serv->reg_cb(
        tick => sub {
            foreach (keys %{ $self->{'msgs'} }) {
                if ($_ <= AnyEvent->now) {
                    my $msg = $self->{'msgs'}->{$_};
                    delete $self->{'msgs'}->{$_};
                    $serv->msg($msg->{chan}, sprintf("%s -> %s: %s", $msg->{source}, $msg->{target}, $msg->{msg}));
                }
            }
        }
    );
    $serv->reg_cb(
        publicmsg => sub {
            my ($this,  $nick, $ircmsg) = @_;
            my ($modes, $nick, $ident)  = $this->split_nick_mode($ircmsg->{'prefix'});
            my $command = $ircmsg->{'command'};
            my $chan    = $ircmsg->{'params'}->[0];
            my $message = $ircmsg->{'params'}->[1];
            my $mstr    = join '', keys %{$modes};
            return if $command ne 'PRIVMSG' or $this->is_my_nick($nick);
            if ($self->{'chans'}->{$chan}) {
                my $prefix = $self->{'chans'}->{$chan} || '#!';
                if (substr($message, 0, length($prefix)) eq $prefix) {
                    my $rest = substr($message, length($prefix));
                    my ($cmd, @args) = shellwords($rest);
                    if ($cmd eq 'notify') {
                        if (scalar(@args) < 2) {
                            $self->msg($chan, "ERR: ${prefix}notify <after> <target> [message]");
                        } else {
                            my $after;
                            if ($args[0] =~ /^(?:(?:(\d+):)?(\d+):)?(\d+)$/) {
                                $after = $3 + $2 * 60 + $1 * 60 * 60;
                            } elsif ($args[0] =~ /[0-9]+ ?(?:(?:days?)|(?:weeks?)|(?:months?)|(?:years?)|(?:hours?)|(?:minutes?)|(?:seconds?))/) {
                                my %suf = qw(second 1 minute 60 hour 3600 day 86400 week 604800 month 2592000 year 31579200);
                                foreach (keys %suf) {
                                    $args[0] =~ s/([0-9.]+) ?($_)s?/$after+=$1*$suf{$2};''/eg;
                                }
                            } else {
                                $serv->msg($chan, "Unknown time format!");
                                return;
                            }
                            $serv->msg($chan, "I'll remind them after $after seconds.");
                            $self->{'msgs'}->{ AnyEvent->now + $after } = {
                                chan   => $chan,
                                target => $args[1] || $nick,
                                source => $nick,
                                msg    => $args[2] || "I was looking for you some time ago."
                            };
                        }
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
