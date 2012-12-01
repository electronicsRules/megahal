package MegaHAL::Interface::Telnet;
#use MegaHAL::Telnet;
use Term::ANSIColor;
use base qw(MegaHAL::Interface::Console);
sub new {
    my ($class,$hdl)=@_;
    my $self=$class->SUPER::new();
    $self->{'user'}='';
    $self->{'hdl'}=$hdl;
    $self->{'auth'}=0;
    return bless $self,$class;
}
sub _write {
    my ($self,$str)=@_;
    chomp $str;
    $self->{'hdl'}->push_write($str.color('reset')."\n");
}
sub type {"telnet"}
sub atype {'user'}
sub source {$_[0]->{'user'}.'@telnet' || 'UNKNOWN'}
sub _auth {
    my ($self)=@_;
    $self->{'auth'} ? $self->{'user'} : 0;
}
1;
