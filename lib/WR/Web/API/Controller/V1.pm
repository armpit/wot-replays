package WR::Web::API::Controller::V1;
use Mojo::Base 'Mojolicious::Controller';
use File::Path qw/make_path/;
use Mango::BSON;
use Scalar::Util qw/blessed/;
use Try::Tiny qw/try catch/;
use WR::Provider::Mapgrid;
use Digest::SHA qw/sha256_hex/;

sub validate_token {
    my $self    = shift;
    my $token   = $self->req->param('t');
    my $next    = $self->stash('next');

    # cb is only called when the token is valid 
    $self->model('api_token')->find_one({ _id => $token } => sub {
        my ($coll, $err, $doc) = (@_);

        if(defined($doc)) {
            my $oh = $self->req->headers->header('Origin') || '';
            my $ho = 0;
            
            foreach my $o (@{$doc->{origin}}) {
                if($o eq $oh) {
                    $ho = 1;
                    last;
                }
            }

            if($ho) {
                $self->res->headers->header('Access-Control-Allow-Origin' => $oh);
                $self->res->headers->header('Access-Control-Allow-Headers' => '*');
                $self->$next($doc);
            } else {
                $self->render(json => { ok => 0, error => 'token.unbound' });
            }
        }  else {
            $self->render(json => { ok => 0, error => 'token.invalid' });
        }
    });
}

sub data {
    my $self = shift;
    my $type = $self->stash('type');

    $self->render_later;

    if($type =~ /^(vehicles|equipment|components|consumables)$/) {
        my $m = sprintf('wot-replays.data.%s', $type);
        $self->model($m)->find()->all(sub {
            my ($coll, $err, $docs) = (@_);
            $self->render(json => { ok => (defined($err)) ? 0 : 1, (defined($err)) ? (error => 'data.error', 'data.error' => $err) : (data => $docs) });
        });
    } else {
        $self->render(json => { ok => 0, error => 'data.invalid.type' });
    }
}

sub process_status {
    my $self    = shift;
    my $job_id  = $self->stash('job_id');

    $self->render_later;
    $self->model('wot-replays.jobs')->find_one({ _id => $job_id } => sub {
        my ($coll, $err, $job) = (@_);

        if(defined($job)) {
            # now find it's position in the queue as well as the total size of the queue
            my $cursor = $self->model('wot-replays.jobs')->find({
                ready       => Mango::BSON::bson_true,
                complete    => Mango::BSON::bson_false,
            });
            my $pending = $cursor->count(sub {
                my ($cursor, $err, $count) = (@_);
                $cursor->sort(Mango::BSON::bson_doc({ priority => 1, ctime => 1 }));
                $cursor->all(sub {
                    my ($coll, $err, $docs) = (@_);
                    my $pos = 0;
                    foreach my $d (@$docs) {
                        $pos++;
                        last if($d->{_id} eq $job_id);
                    }
                    $self->render(json => { %$job, pending => $count, position => $pos });
                });
            });
        } else {
            $self->render(json => { status => -1, error => 'No such job ID exists' });
        }
    });
}

sub rfrag {
    my $self = shift;
    my $a    = [ 'A'..'Z', 'a'..'z', 0..9 ];
    my $s    = '';

    while(length($s) < 7) {
        $s .= $a->[int(rand(scalar(@$a)))];
    }
    return $s;
}

sub process_replay {
    my $self = shift;
    my $adoc = shift;

    $self->render(json => { ok => 0, error => 'process.not.enabled.for.token' }) and return unless($adoc->{enable_process});

    $self->render_later;

    if(my $upload = $self->req->upload('replay')) {
        $self->render(json => { ok => 0, error => 'not.a.replay.file'}) and return unless($upload->filename =~ /\.wotreplay$/);

        # generate a random fragment 
        my $filename = $upload->filename;
        $filename =~ s/.*\\//g if($filename =~ /\\/);
        $filename =~ s/[#\*\(\)\[\]\{\}\?\\\,\;\/]/_/g;
        $filename = sprintf('%s-%s', $self->rfrag, $filename);

        my $hashbucket_size = length($filename);
        $hashbucket_size = 7 if($hashbucket_size > 7);
        my $replay_filename = $filename;
        my $replay_path = sprintf('%s/%s', $self->stash('config')->{paths}->{replays}, $self->hashbucket($filename, $hashbucket_size));
        my $replay_file = sprintf('%s/%s', $replay_path, $filename);
        my $replay_file_base = sprintf('%s/%s', $self->hashbucket($filename, $hashbucket_size), $filename);

        make_path($replay_path);

        my $digest = sha256_hex($upload->asset->slurp);
        
        my $prio_map = {
            'wotreplays.org' => 20,
        };

        my $api = {
            via         =>  $adoc->{ident},
        };

        my $prio = (defined($prio_map->{$adoc->{ident}})) ? $prio_map->{$adoc->{ident}} : 1000;

        if(my $postback = $self->req->param('postback')) {
            $api->{postback} = $postback;
            $api->{flags} = {
                replay      =>  (defined($self->req->param('without-replay'))) ? 0 : 1,
                packets     =>  (defined($self->req->param('with-packets'))) ? 1 : 0,
            };
        } else {
            $api->{flags} = {
                replay      => 1, # doesn't have any effect since we don't post back
                packets     => 1, # doens't have any effect since we don't post back 
            };
        }

        # set this up as the job id
        $self->model('wot-replays.jobs')->save({
            _id         => $digest,
            api         => $api,
            uploader    => undef,
            ready       => Mango::BSON::bson_false,
            complete    => Mango::BSON::bson_false,
            status      => 0,
            error       => undef,
            replayid    => undef,
            ctime       => Mango::BSON::bson_time,
            status_text => [ ],
            data        => { },
            priority    => $prio,
        } => sub {
            my ($coll, $err, $oid) = (@_);
            if(defined($oid)) {
                $upload->asset->move_to($replay_file);
                $self->model('wot-replays.jobs')->update({ _id => $digest }, { 
                    '$set' => {
                        'data'  => {
                            file        => $replay_file,
                            file_base   => $replay_file_base,
                            desc        => '',
                            visible     => 1,
                        },
                        ready => Mango::BSON::bson_true,
                    }
                } => sub {
                    my ($coll, $err, $oid) = (@_);

                    if($err) {
                        $self->render(json => { ok => 0, error => 'process.store.fail', 'process.store.fail' => $_ });
                    } else {
                        $self->model('wot-replays.jobs')->find({ complete => Mango::BSON::bson_false, ready => Mango::BSON::bson_true })->count(sub {
                            my ($coll, $err, $count) = (@_);
                            $self->render(json => { ok => 1, process_id => $digest });
                        });
                    } 
                });
            } else {    
                $self->render(json => { ok => 0, error => 'process.job.fail' });
            }
        });
    } else {
        $self->render(json => { ok => 0, error => 'no.upload' });
    }
}

1;
