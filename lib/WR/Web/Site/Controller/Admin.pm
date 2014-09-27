package WR::App::Controller::Admin;
use Mojo::Base 'WR::App::Controller';
use Mango::BSON;
use DateTime;

sub bridge {
    my $self = shift;
    return 1 if($self->has_admin_access);
    $self->redirect_to('/') and return 0;
}

sub get_replay_count {
    my $self = shift;
    my $end  = shift;

    $self->render_later;
    $self->model('wot-replays.replays')->find()->count(sub {
        my ($cursor, $err, $count) = (@_);
        $self->render(json => { count => $count});
    });
}

sub get_today_count {
    my $self = shift;
    my $end  = shift;
    my $now  = (DateTime->now(time_zone => 'UTC')->truncate(to => 'day')->epoch * 1000);

    $self->render_later;
    $self->model('wot-replays.replays')->find({ 'site.uploaded_at' => { '$gte' => Mango::BSON::bson_time($now) } })->count(sub {
        my ($cursor, $err, $count) = (@_);

        $self->render(json => { count => $count});
    });
}

sub get_upload_queue {
    my $self = shift;
    my $end  = shift;

    $self->render_later;
    $self->model('wot-replays.jobs')->find({ complete => Mango::BSON::bson_false, ready => Mango::BSON::bson_true })->sort({ ctime => 1, priority => 1 })->all(sub {
        my ($c, $err, $docs) = (@_);
        $self->stash('uploads' => $docs);
        $self->render(template => 'admin/uploads_list');
    });
}

sub get_online_users {
    my $self = shift;
    my $end  = shift;

    $self->render_later;
    $self->app->thunderpush->ua->inactivity_timeout(60);
    $self->app->thunderpush->channel_list('site' => sub {
        my ($p, $res) = (@_);
        my $o = [];
        my $g = 0;

        use Data::Dumper;
        warn Dumper($res);

        foreach my $user (@{$res->{response}->{users}}) {
            if($user =~ /^(anon-|undefined)/) {
                $g++;
            } else {
                push(@$o, $user);
            }
        }

        $self->render(json => { guest_count => $g, users => $o });
    });
}

sub index {
    my $self = shift;

    $self->render_later;

    $self->respond(template => 'admin/index', stash => {
        page => { title => 'Dashboard' },
        server_time => DateTime->now(time_zone => 'UTC')->strftime('%d/%m/%Y %H:%M:%S UTC'),
    });
}

1;
