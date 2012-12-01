use File::Find;
use File::Copy;
use Perl::Tidy;
use threads;
use Thread::Queue;
$|=1;
my $iq=Thread::Queue->new();
my @wrk;
our $len=42;
foreach (1..8) {
    push @wrk,threads->create('worker',$iq);
}
find({wanted => sub {
    if (-f and -r and /\.(?:(?:p[lm]x?)|t)$/) {
        $_=~s/^\.\///;
        return if $_ eq $0;
        $iq->enqueue($_);
    }
}, no_chdir => 1},'.');
$iq->enqueue(undef) foreach @wrk;
$_->join foreach @wrk;
sub worker {
    my ($iq)=@_;
    while (defined(my $i=$iq->dequeue())) {
        my $name=$i;
        $name=~s/\//::/g if $name=~s/\.pm$//;
        #printf "[%-${len}s] Running perltidy...\n",$name;
        my $err=Perl::Tidy::perltidy(
            source => $i,
            destination => "$i.tdy",
            argv => '-pro=.../.perltidyrc'
        );
        threads::yield();
        if ($err) {
            printf "[%-${len}s] Error.\n",$name;
        }else{
            #printf "[%-${len}s] Comparing to original...\n",$name;
            if (`diff -q $i $i.tdy`) {
                printf "[%-${len}s] Changed\n",$name;
                copy($i.'.tdy',$i);
            }else{
                printf "[%-${len}s] Same\n",$name
            }
            unlink($i.".tdy");
        }
    }
}