package MegaHAL::Plugin::Hailo;
use Hailo;
use Scalar::Util qw(weaken);

sub new {
    my ($class, $serv) = @_;
    my $self = {
        'bots'  => {},
        'chans' => {},
        'hobj'  => {}
    };
    bless $self, $class;
    $serv->reg_cb(
        publicmsg => sub {
            my ($this,  $nick, $ircmsg) = @_;
            my ($modes, $nick, $ident)  = $this->split_nick_mode($ircmsg->{'prefix'});
            my $command = $ircmsg->{'command'};
            my $chan    = lc($ircmsg->{'params'}->[0]);
            my $message = $ircmsg->{'params'}->[1];
            my $mstr    = join '', keys %{$modes};
            return if $command ne 'PRIVMSG' or $this->is_my_nick($nick);
            $self->input($chan, $nick, $message);
        }
    );
    $serv->reg_cb(
        ctcp => sub {
            my ($this, $src, $target, $tag, $msg, $type) = @_;
            if ($tag eq 'ACTION' && $type eq 'PRIVMSG' and $serv->is_channel_name($target) and not $this->is_my_nick($src)) {
                $self->input($chan, $src, $msg, 'ACTION');
            }
        }
    );
    $self->{'serv'} = $serv;
    weaken($self->{'serv'});
    return $self;
}

sub input {
    my ($self, $chan, $nick, $msg, $type) = @_;
    return unless $self->{'chans'}->{$chan};
    my $sn       = $self->{'serv'}->name();
    my $has_sent = 0;
    OUTER: foreach (ref $self->{'chans'}->{$chan} eq 'ARRAY' ? @{ $self->{'chans'}->{$chan} } : $self->{'chans'}->{$chan}) {
        my $obj   = $_;
        my $bn    = $obj->{'bot'};
        my $hailo = $self->{'hobj'}->{$bn};
        next if not $hailo;
        if ($obj->{'reply_ping'}) {
            my $own_nick = $self->{'serv'}->nick();
            if ($msg =~ /^$own_nick[: ,]/) {
                $msg =~ /^$own_nick[: ,](.*)$/;
                $msg = $1;
                my $repl = '';
                if ($obj->{'learn_reply'}) {
                    $repl = $hailo->learn_reply($msg);
                } else {
                    $repl = $hailo->reply($msg);
                }
                $repl = "[Hailo] $repl" if $obj->{'tag'};
                print "[$sn] {Hailo:$bn} $msg -> $repl";
                $self->{'serv'}->msg($chan, $repl);
                next;
            }
        }
        if ($obj->{'learn'}) {
            foreach (@{ $obj->{'ignore_nicks'} || [] }) {
                next OUTER if $nick eq $_;
            }
            $nick =~ tr/|_//d;
            my $is_action = 0;
            $is_action = 1 if $msg =~ s/^\cAACTION/$nick /;
            $msg = $nick . ' ' . $msg if $type eq 'ACTION' or $is_action;
            next if $msg =~ /https?:\/\// or $msg =~ /^\// or $msg =~ /^[ \cB\cC0-9]*>/;
            $msg =~ s/^[^ :]+\K: /, /;
            $msg =~ s/[-._?^;-;]{4,}//g;
            $msg =~ tr/()[]{}<>""//d;
            next if $obj->{'min_length'} && length($msg) < $obj->{'min_length'};
            $hailo->learn($msg);
        }
    }
}

sub upd_hobjs {
    my ($self) = @_;
    my $sn = $self->{'serv'}->name();
    if (!-d 'pldata') {
        mkdir 'pldata';
    }
    if (!-d 'pldata/Hailo') {
        mkdir 'pldata/Hailo';
    }
    foreach (keys %{ $self->{'hobj'} }) {
        if (!$self->{'bots'}->{$_}) {
            print "[$sn] {Hailo:$_} Saving data and removing Hailo instance\n";
            $self->{'hobj'}->{$_}->save();
            delete $self->{'hobj'}->{$_};
        }
    }
    foreach (keys %{ $self->{'bots'} }) {
        if (!$self->{'hobj'}->{$_}) {
            print "[$sn] {Hailo:$_} Creating Hailo instance...\n";
            my %opts = %{ $self->{'bots'}->{$_} } if ref $self->{'bots'}->{$_} eq 'HASH';
            $self->{'hobj'}->{$_} = Hailo->new(
                brain           => 'pldata/Hailo/' . $sn . '-' . $_ . '.db',
                order           => $opts{order} || 2,
                engine_class    => $opts{engine} || 'Default',
                storage_class   => 'SQLite',
                tokenizer_class => $opts{tokenizer} || $opts{tokeniser} || 'Words',
                engine_args => $opts{engine_args} || {},
                tokenizer_args => $opts{tokenizer_args} || $opts{tokeniser_args} || {}
            );
            print "[$sn] {Hailo:$_} Done!\n";
        }
    }
}

sub load {
    my ($self, $data) = @_;
    $self->{'chans'} = $data->{'chans'};
    $self->{'bots'}  = $data->{'bots'};
    $self->upd_hobjs();
}

sub save {
    my ($self) = @_;
    $_->save() foreach values %{ $self->{'hobj'} };
    return { 'chans' => $self->{'chans'}, 'bots' => $self->{'bots'} };
}
1;
