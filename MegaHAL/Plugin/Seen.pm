package MegaHAL::Plugin::Seen;
use feature 'switch';
sub new {
    my ($class,$serv)=@_;
    my $self={
        'chans' => {},
        'nicks' => {}
    };
    
}

sub load {
    my ($self,$data)=@_;
    $self->{'chans'}=$data;
}

sub save {
    my ($self)=@_;
    return $self->{'chans'};
}