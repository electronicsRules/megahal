package MegaHAL::HTTP;
use IO::Async::Loop;
use Net::Async::HTTP;
use URI;
use EV;

sub new {
	my ($class,$_loop)=@_;
	my $loop = $_loop || IO::Async::Loop->new();
	my $http = Net::Async::HTTP->new();
	$loop->add( $http );
	my $self={
		loop => $loop,
		http => $http,
		timeout => 30,
		watcher => EV::prepare(sub {$loop->loop_once(0)})
	};
	return bless $self, $class;
}

sub request {
	my ($self,$uri)=@_;
	$uri=URI->new($uri) unless ref $uri;
	my $cv=AnyEvent->condvar;
	$self->{http}->do_request(
		request => ($uri->isa('HTTP::Request') ? $uri : undef),
		uri => ($uri->isa('URI') ? $uri : undef),
		timeout => $self->{timeout},
		on_response => sub {
			$cv->send($_[0]->decoded_content(),$_[0]);
		},
		on_error => sub {
			warn "Error in MegaHAL::HTTP: '$_[0]'\n";
			$cv->send(\$_[0],\$_[1]);
		}
	);
	return $cv;
}

sub DESTROY {
	$_[0]->{loop}->remove($_[0]->{http});
}

1;
