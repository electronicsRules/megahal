package MegaHAL::Plugin::Welcome;
use feature 'switch';
use AnyEvent::HTTP;
use JSON::XS;
use YAML::Any qw(Dump);
use Text::ParseWords;

sub new {
    my ($class, $serv) = @_;
    my $self = { 'chans' => {} };
    my $id = time;
    $serv->reg_cb(
        'join' => sub {
            my ($this, $nick, $chan, $is_myself) = @_;
            #print "$nick joined $chan!\n";
            return if $is_myself;
            if ($self->{'chans'}->{$chan}) {
                $serv->send_long_message('utf8', 0, 'PRIVMSG' => $chan, $self->{'chans'}->{$chan});
            }
        }
    );
    $serv->{'plugins'}->reg_cb(
        'consoleCommand' => sub {
            my ($this, $cmd, @args) = @_;
            if ($cmd eq 'welcome') {
                given ($args[0]) {
                    when ('add') {
                        return if not $_[0];
                        $self->{'chans'}->{ $args[1] } = $args[2];
                    }
                    when ('del') {
                        return if not $_[0];
                        delete $self->{'chans'}->{ $args[1] };
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
