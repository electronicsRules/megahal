package MegaHAL::Interface;
use Term::ANSIColor qw(colorstrip);
use MegaHAL::ACL;

sub new {
    my ($class, $source, $target) = @_;
    my $self = {
        'source' => $source,
        'fh'     => undef,
        'code'   => undef
    };
    if (ref $target eq 'CODE') {
        $self->{'code'} = $target;
    } elsif (ref $target eq 'GLOB' or UNIVERSAL::isa($target, 'IO::Handle')) {
        $self->{'fh'} = $target;
    }
    bless $self, $class;
    $self->{'source'} = $self->source() if not $self->{'source'};
    return $self;
}

sub write {
    my $self = shift;
    my $str = join ' ', @_;
    $str = colorstrip($str) unless $self->ansicolorok();    #Get rid of existing Term::ANSIColor codes, because Shit Happens(tm)
    my %map = $self->colour();
    foreach (grep { $_ ne "\cC" } keys %map) {
        $str =~ s/($_)/ref $map{$_} eq 'CODE' ? $map{$_}->($1) : $map{$_}/eg;
    }
    $str =~ s/(\cC\d?\d?(?:,\d\d?)?)/ref $map{"\cC"} eq 'CODE' ? $map{"\cC"}->($1) : $map{"\cC"}/eg if defined $map{"\cC"};
    return $self->_write($str)                                                                      if $self->can('_write');
    return $self->{'code'}->($str)                                                                  if $self->{'code'};
    return print $self->{'fh'}, $str if $self->{'fh'};
    return print "[$$self{source}] $str\n";
}

sub ansicolorok {0}
sub type        {"UNKNOWN"}
sub source      { $_[0]->{'source'} || "UNKNOWN" }
sub atype       {'user'}

sub acan {
    my ($self, $plugin, $node, $channel, $cb) = @_;
    my $f;
    if ($self->atype() eq 'irc' && defined($self->{'server'})) {
        $f = Future->needs_any($self->auth())->transform(
            done => sub {
                return 0 if not $_[0];
                return MegaHAL::ACL::has_ircnode($self->{'server'}, $_[0], $plugin, $node, $channel);
            }
        );
    } elsif ($self->atype() eq 'user') {
        $f = Future->needs_any($self->auth())->transform(
            done => sub {
                return 0 if not $_[0];
                return MegaHAL::ACL::has_node($_[0], $plugin, $node);
            }
        );
    } elsif ($self->atype() eq 'always') {
        $f->done(1);
    } else {
        $fut->fail("No authentication methods available!");
    }
    $f->on_ready($cb) if $cb;
    return $f;
}

sub colour {
    (   "\cB" => "",
        "\cC" => "",
        "\cU" => "",
        "\cR" => "",
        "\c_" => "",
        "\c]" => "",
        "\cO" => ""
    );
}

sub auth {
    my ($self, $cb) = @_;
    my $ret = $self->_auth();
    if (!ref $ret) {
        return $cb->($ret) if $cb;
    }
    return $ret;
}

sub _auth {
    return 0;
}
1;
