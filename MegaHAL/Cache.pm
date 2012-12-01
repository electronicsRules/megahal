package MegaHAL::Cache;
use AnyEvent;
use AnyEvent::HTTP;
use EV;
#use AnyEvent::Memcached;
#use Cache::Memcached;
use CHI;
use base Exporter;
our @EXPORT_OK=qw(cache_http);
#our $cache=new Cache::Memcached(
#    'servers' => [ '/tmp/memcached.sock' ],
#    'namespace' => 'megahal:'
#);
our %ds;
our $cache=CHI->new(
    driver => 'Memcached',
    servers => ['/tmp/memcached.sock'],
    l1_cache => {
        driver => 'Memory',
        datastore => \%ds,
        max_size => 1024*1024*2
        },
    namespace => 'megahal:'
);
#$cache->connect();
our @delayedreq;
our $dreqi=1;
our $lreq=0;
our $delreqt=AnyEvent->timer(after => 0, interval => $dreqi, cb => sub {
    if (scalar(@delayedreq) > 0 && (AnyEvent->now() - $lreq) >= $dreqi) {
        cache_http(@{shift @delayedreq});
    }
});
sub cache_http {
    my ($url,$key,$expire,$sub)=@_;
    if (!$key) {
        $key=$url;
        $key=~s#^https?://##;
        $key=~s#^www\.##;
    }
=begin comment
    $cache->get('http:'.$key, cb => sub {
        my ($value,$err)=@_;
        if (defined $value) {
            $sub->($value);
        }else{
            if ((AnyEvent->now() - $lreq) >= $dreqi) {
                AnyEvent::HTTP::http_get $url, sub {
                    $cache->set('http:'.$key, $_[0], expire => $expire || 60 * 15, cb => sub {});
                    $sub->($_[0]);
                }
            }else{
                push @delayedreq, [$url,$key,$expire,$sub];
            }
        }
    });
=cut

#=begin comment
    my $val=$cache->get('http:'.$key);
    EV::run EV::RUN_NOWAIT;
    if (defined $val) {
        print "Cache hit $key!\n";
        $sub->($val);
    }else{
        if ((AnyEvent->now() - $lreq) >= $dreqi) {
            AnyEvent::HTTP::http_get $url, sub {
                if ($sub->($_[0])) {
                    EV::run EV::RUN_NOWAIT;
                    $cache->set('http:'.$key, $_[0], $expire || 60 * 60 * 15);
                }
            };
            $lreq=time;
        }else{
            push @delayedreq, [$url,$key,$expire,$sub];
        }
    }
#=cut

}
