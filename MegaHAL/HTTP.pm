package MegaHAL::HTTP;
use IO::Async::Loop;
use Net::Async::HTTP;
use URI;
use EV;

sub new {
    my ($class, $_loop) = @_;
    my $loop = $_loop || IO::Async::Loop->new();
    my $http = Net::Async::HTTP->new();
    $loop->add($http);
    my $self = {
        loop    => $loop,
        http    => $http,
        watcher => EV::prepare(sub { $loop->loop_once(0) })
    };
    return bless $self, $class;
}

sub request {
    my ($self, $uri) = @_;
    $uri = URI->new($uri) unless ref $uri;
    my $fut=$self->{http}->do_request(
        request => ($uri->isa('HTTP::Request') ? $uri : undef),
        uri     => ($uri->isa('URI')           ? $uri : undef),
        timeout => 15
    );
    return $fut->on_fail(sub {
		warn "Error in MegaHAL::HTTP: '$_[0]'\n";
	})->transform(done => sub {
		return($_[0]->decoded_content,$_[0]);
	});
}

sub DESTROY {
    $_[0]->{loop}->remove($_[0]->{http});
}

1;
