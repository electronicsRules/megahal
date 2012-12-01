package MegaHAL::Plugin::Syndicate;
use feature 'switch';
use AnyEvent::HTTP;
use JSON::XS;
use YAML::Any qw(Dump);
use Text::ParseWords;
sub new {
    my ($class,$serv)=@_;
    my $self={
        'chans' => {}
        };
    my $id=time;
    $serv->reg_cb('publicmsg' => sub {
        my ($this,$nick,$ircmsg)=@_;
        #print "Callback $id\n";
        #print Dumper($ircmsg)."\n";
        my ($modes,$nick,$ident)=$this->split_nick_mode($ircmsg->{'prefix'});
        my $command=$ircmsg->{'command'};
        my $chan=$ircmsg->{'params'}->[0];
        my $message=$ircmsg->{'params'}->[1];
        my $mstr=join '',keys %{$modes};
        return if $command ne 'PRIVMSG' or $this->is_my_nick($nick);
        #print "1 $chan $message\n";
        if ($self->{'chans'}->{$chan} && $self->{'chans'}->{$chan}->{$nick}) {
            $serv->msg($chan,sprintf("<\cC04%s%s\cO> %s", $mstr, $nick, $message));
        }
    });
    $serv->reg_cb('ctcp' => sub {
        my ($test,$src,$target,$tag,$msg,$type)=@_;
        #print "$src $target $tag $msg $type\n";
        if ($tag eq 'ACTION' && $type eq 'PRIVMSG' && $self->{'chans'}->{$target} && $self->{'chans'}->{$target}->{$src}) {
            $serv->msg($target,sprintf(" * \cC04%s\cO %s", $src, $msg));
        }
    });
    $serv->{'plugins'}->reg_cb('consoleCommand' => sub {
        my ($this,$cmd,@args)=@_;
        if ($cmd eq 'syndicate') {
            given($args[0]) {
                when('add') {
                    $self->{'chans'}->{$args[1]}->{$args[2]}=1;
                }
                when('del') {
                    delete $self->{'chans'}->{$args[1]}->{$args[2]} if $args[2];
                    delete $self->{'chans'}->{$args[1]} unless $args[2];
                }
            }
        }
    });
    return bless $self,$class;
}

sub load {
    my ($self,$data)=@_;
    $self->{'chans'}=$data;
}

sub save {
    my ($self)=@_;
    return $self->{'chans'};
}