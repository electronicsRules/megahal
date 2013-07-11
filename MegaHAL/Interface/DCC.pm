package MegaHAL::Interface::DCC;
use base qw(MegaHAL::Interface);

sub new {
    my ($class, $server, $nick, $id) = @_;
    my $self = $class->SUPER::new($nick . '[' . $id . ']@' . $$server{'name'});
    $self->{'server'} = $server;
    $self->{'id'}     = $id;
    $self->{'nick'}   = $nick;
    $self->{'auth'}   = 0;
    return bless $self, $class;
}

sub _write {
    my ($self, $str) = @_;
    foreach (split "\n", $str) {
        $main::srv{ $self->{'server'} }->send_dcc_chat($self->{'id'}, $_);
    }
}
sub colour { }

sub _auth {
    my ($self) = @_;
    return $self->{'nick'} if $self->{'auth'};
    return $main::srv{ $self->{'server'} }->auth(
        $self->{'nick'},
        undef
    );
    return $main::srv{ $self->{'server'} }->auth(
        $self->{'nick'},
        undef
    )->transform(done => sub {
        $self->{'auth'}=1;
        return $self->{'nick'} if $_[0]
    });
}
sub type   {"DCC"}
sub atype  {'irc'}
sub source { $_[0]->{'nick'} . '#' . $_[0]->{'id'} . '@' . $_[0]->{'server'} }
1;
