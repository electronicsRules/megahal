package MegaHAL::Plugin::Test;
sub new {
    my ($class)=@_;
    $serv->send_srv('PRIVMSG' => '#bots',"\001ACTION has loaded Test.pm!\001");
    $serv->reg_cb(publicmsg => sub {
        my ($self,$nick,$ircmsg)=@_;
        #print Dumper($ircmsg)."\n";
        my ($modes,$nick,$ident)=$self->split_nick_mode($ircmsg->{'prefix'});
        my $command=$ircmsg->{'command'};
        my $chan=$ircmsg->{'params'}->[0];
        my $message=$ircmsg->{'params'}->[1];
        my $mstr=join '',keys %{$modes};
        #print("$chan $mstr$nick $command $message\n");
        return unless $command eq 'PRIVMSG';
        if ($message eq '#!testauth') {
            print "Testing NS auth...\n";
            $serv->auth($nick,$chan,sub {
                print "Auth for $nick in $chan OK!\n";
                $serv->send_srv('PRIVMSG' => '#bots', "it works!");
            });
        }
    });
    return bless [],$class;
}

sub DESTROY {
    $serv->send_srv('PRIVMSG' => '#bots','Test.pm unloaded!');
}