package MegaHAL::Filehandle;
use IO::Handle;
sub TIEHANDLE {
    my ($class,$orig,$rl,$hook)=@_;
    $self=[$rl,IO::Handle->new(),$hook];
    $$self[1]->fdopen(fileno($orig),'r');
    return bless $self,shift;
}

sub WRITE {
    my ($self,@args)=@_;
    my $str=substr(${$args[0]},$args[2],$args[1]);
    chomp $str;
    $$self[0]->print("$str\n");
    $self->[2]->($str) if $self->[2];
    return length($str);
}

sub PRINT {
    my ($self,@args)=@_;
    my $str=join($,,@args);
    chomp $str;
    $self->[2]->($str) if $self->[2];
    return $self->[0]->print("$str\n");
}

sub PRINTF {
    shift;
    my $fmt=shift;
    print sprintf($fmt,@_);
}

sub UNTIE {
    $$self[1]->close();
}
1;