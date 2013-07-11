package MegaHAL::Interface::PM;
use base qw(MegaHAL::Interface);

sub new {
    my ($class, $server, $nick) = @_;
    my $self = $class->SUPER::new($nick . '@' . $$server{'name'});
    $self->{'server'} = $server;
    $self->{'nick'}   = $nick;
    return bless $self, $class;
}

sub _write {
    my ($self, $str) = @_;
    foreach (split "\n", $str) {
        $main::srv{ $self->{'server'} }->msg($self->{'nick'}, $str);
    }
}
sub colour { }

sub _auth {
    my ($self) = @_;
    return $main::srv{ $self->{'server'} }->auth($self->{'nick'}, undef)->transform(done => sub { return $self->{'nick'} if $_[0] });
}
sub type   {"PM"}
sub atype  {'irc'}
sub source { $_[0]->{'nick'} . '@' . $_[0]->{'server'} }
1;
