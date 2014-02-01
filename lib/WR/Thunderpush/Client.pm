package WR::Thunderpush::Client;
use Mojo::Base 'Mojo::EventEmitter';
use Mojo::UserAgent;
use String::Unquotemeta ();
use Mojo::JSON;

has 'ua'                => sub { Mojo::UserAgent->new };
has 'host'              => undef;
has 'key'               => undef;
has 'user'              => undef;
has 'channels'          => sub { [] };

has '_socket'    => undef;
has '_server' => sub { int(rand(1000)) };
has '_conn_id' => sub {
    my $self = shift;
    my $str  = '';
    my $a = ['a'..'z','A'..'Z'];

    while(length($str) < 8) {
        $str .= $a->[int(rand(scalar(@$a)))];
    }
    return $str;
};
has 'j'                 => sub { Mojo::JSON->new };

sub connect {
    my $self = shift;
    my $url  = sprintf('ws://%s/connect/%d/%s/websocket', $self->host, $self->_server, $self->_conn_id);

    $self->ua->inactivity_timeout(3600);

    warn 'connecting using: ', $url, "\n";

    $self->ua->websocket($url => sub {
        my ($ua, $tx) = (@_);

        $self->emit('connect' => { status => 0, error => 'no tx' }) and return unless(defined($tx));

        if($tx->is_websocket) {
            warn 'tx is websocket', "\n";
            $self->_socket($tx);
            $self->_socket->send({json => sprintf('CONNECT %s:%s', $self->user, $self->key)});
            $self->subscribe($_) for(@{$self->channels});
            $self->_socket->on(finish => sub {
                my ($socket, $code, $reason) = (@_);
                $self->emit('finished' => { code => $code, reason => $reason });
            });
            $self->_socket->on(message => sub {
                my ($s, $d) = (@_);
                my $type = substr($d, 0, 1);

                if($type eq 'o') {
                    $self->emit('open');
                } elsif($type eq 'a') {
                    my $array = $self->j->decode(substr($d, 1));
                    $self->emit(message => $self->j->decode($_)) for(@$array);
                } elsif($type eq 'm') {
                    $self->emit(message => $self->j->decode(substr($d, 1)));
                } elsif($type eq 'h') {
                    $self->emit('heartbeat');
                } elsif($type eq 'c') { 
                    my $r = $self->j->decode(substr($d, 1));
                    $self->emit(finished => { code => $r->[0], reason => $r->[1] });
                }
            });
            $self->emit('connect' => { status => 1 });
        } else {
            if($tx->success) {
                warn 'tx is not websocket', "\n";
                $self->emit('connect' => { status => 0, error => 'not a websocket' });
            } else {
                warn 'connection failed', "\n";
                $self->emit('connect' => { status => 0, error => 'connection refused' });
            }
        }
    });
}

sub finish {
    my $self = shift;
    $self->_socket->finish;
}

sub subscribe {
    my $self    = shift;
    my $channel = shift;

    $self->_socket->send({ json => sprintf('SUBSCRIBE %s', $channel)});
}

1;
