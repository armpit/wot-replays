package WR::App::Controller::Replays::View;
use Mojo::Base 'WR::App::Controller';
use boolean;
use WR::Query;
use WR::Efficiency;
use WR::Res::Achievements;
use Time::HiRes qw/gettimeofday tv_interval/;
use JSON::XS;
use Text::CSV_XS;

sub stats {
    my $self = shift;

    $self->render(json => {
        views => $self->stash('req_replay')->{site}->{views} + 0,
        downloads => $self->stash('req_replay')->{site}->{downloads} + 0,
        likes => $self->stash('req_replay')->{site}->{like} + 0,
    });
}

sub incview {
    my $self = shift;
    $self->db('wot-replays')->get_collection('replays')->update({ _id => $self->stash('req_replay')->{_id} }, { '$inc' => { 'site.views' => 1 } });
    $self->render(json => { ok => 1 });
}

sub get_vehicle_tier {
    my $self = shift;

    if(my $v = $self->model('wot-replays.data.vehicles')->find_one({ _id => $self->stash('req_replay')->{player}->{vehicle}->{full} })) {
        return $v->{level};
    } else {
        return undef;
    }
}

sub get_comparison {
    my $self = shift;
    my $p    = shift;
    my $pp   = 10;
    my $offset = (($p-1) * $pp);

    my $query = {
        _id => { '$nin' => [ $self->stash('req_replay')->{_id} ] },
        'player.vehicle.full' => $self->stash('req_replay')->{player}->{vehicle}->{full},
        'map.id' => $self->stash('req_replay')->{map}->{id},
        'complete' => true,
    };

    my $cursor = $self->model('wot-replays.replays')->find($query);
    my $total = $cursor->count();
    my $maxp  = int($total/$pp);
    $maxp++ if($maxp * $pp < $total);

    $cursor->sort({ 'site.uploaded_at' => -1 });
    $cursor->skip($offset);
    $cursor->limit($pp);

    my $result = [];
    my $replay = $self->stash('req_replay');

    while(my $r = $cursor->next()) {
        my $d = {
            url     => sprintf('/replay/%s.html', $r->{_id}->to_string()),
            player  => $r->{player}->{name},
            mode    => $r->{game}->{type},
        };
        for(qw/kills damaged spotted damageDealt credits xp/) {
            $d->{$_} = {
                this => $replay->{statistics}->{$_} + 0,
                that => $r->{statistics}->{$_} + 0,
                flag => ($replay->{statistics}->{$_} + 0 > $r->{statistics}->{$_} + 0) 
                    ? '>'
                    : ($replay->{statistics}->{$_} + 0 < $r->{statistics}->{$_} + 0)
                        ? '<'
                        : '='
            }
        }

        my $this_acc = ($replay->{statistics}->{shots} > 0 && $replay->{statistics}->{hits} > 0) 
            ? sprintf('%.0f', (100/($replay->{statistics}->{shots}/$replay->{statistics}->{hits})))
            : 0;
        my $that_acc = ($r->{statistics}->{shots} > 0 && $r->{statistics}->{hits} > 0) 
            ? sprintf('%.0f', (100/($r->{statistics}->{shots}/$r->{statistics}->{hits})))
            : 0;

        $d->{accuracy} = {
            this => $this_acc,
            that => $that_acc,
            flag => ($this_acc > $that_acc)
                ? '>'
                : ($this_acc < $that_acc) 
                    ? '<'
                    : '='
        };

        my $hc = 0;
        foreach my $v (values(%$d)) {
            next unless(ref($v) eq 'HASH');
            $hc += 1 if($v->{flag} eq '>');
            $hc += 0 if($v->{flag} eq '=');
            $hc -= 1 if($v->{flag} eq '=');
        }
        $d->{rating} = $hc;
        push(@$result, $d);
    }

    return {
        p => $p,
        maxp => $maxp,
        results => $result,
        total => $total,
    };
}

sub comparison {
    my $self = shift;
    my $p    = $self->req->param('p') || 1;

    my $r = $self->get_comparison($p);

    $self->stash(%$r);
    $self->respond(template => 'replay/view/comparison');
}

sub fuck_jsonxs {
    my $self = shift;
    my $obj = shift;

    return $obj unless(ref($obj));

    if(ref($obj) eq 'ARRAY') {
        return [ map { $self->fuck_jsonxs($_) } @$obj ];
    } elsif(ref($obj) eq 'HASH') {
        foreach my $field (keys(%$obj)) {
            next unless(ref($obj->{$field}));
            if(ref($obj->{$field}) eq 'HASH') {
                $obj->{$field} = $self->fuck_jsonxs($obj->{$field});
            } elsif(ref($obj->{$field}) eq 'ARRAY') {
                my $t = [];
                push(@$t, $self->fuck_jsonxs($_)) for(@{$obj->{$field}});
                $obj->{$field} = $t;
            } elsif(boolean::isBoolean($obj->{$field})) {
                $obj->{$field} = ($obj->{$field}) ? JSON::XS->true : JSON::XS->false;
            }
        }
        return $obj;
    }
}

sub view_as_json {
    my $self = shift;

    my $j = JSON::XS->new()->pretty->allow_blessed(1)->convert_blessed(1);
    $self->render(text => $j->encode($self->fuck_jsonxs($self->stash('req_replay'))));
}

sub view {
    my $self = shift;
    my $desc;
    my $format = $self->stash('format');
    my $start = [ gettimeofday ];

    $self->redirect_to(sprintf('%s.html', $self->req->url)) unless(defined($format));

    $self->view_as_json and return if($format eq 'json');

    $self->stash('cachereplay' => 1);

    my $replay = $self->stash('req_replay');
    my $r = { %$replay };

    my $comp = $self->get_comparison(1);

    $self->stash(%$comp);

    my $title = sprintf('%s - %s - %s (%s), %s',
        $r->{player}->{name},
        $self->vehicle_name($r->{player}->{vehicle}->{full}),
        $self->map_name($r->{map}->{id}),
        $self->app->wr_res->gametype->i18n($r->{game}->{type}),
        ($r->{game}->{isWin} > 0) 
            ? 'Victory'
            : ($r->{game}->{isDraw} > 0)
                ? 'Draw'
                : 'Defeat');
    if($r->{complete}) {
        $title .= sprintf(', earned %d xp%s, %d credits',
            $r->{statistics}->{xp},
            ($r->{statistics}->{dailyXPFactor10} > 10) 
                ? sprintf(' (x%d)', $r->{statistics}->{dailyXPFactor10}/10)
                : '',
            $r->{statistics}->{credits});
    }

    my $description = sprintf('This is a replay of a %s match fought by %s, using the %s vehicle, on map %s', 
        $self->app->wr_res->gametype->i18n($r->{game}->{type}), 
        $r->{player}->{name}, 
        $self->vehicle_name($r->{player}->{vehicle}->{full}),
        $self->map_name($r->{map}->{id})
    );

    # need to bugger up the teams and sort them by the number of frags which we can obtain from the vehicle hash
    my $xp_sorted_teams = [];
    my $team_xp = [];

    foreach my $tid (0..1) {
        my $list = {};
        foreach my $player (@{$r->{teams}->[$tid]}) {
            my $xp = $r->{vehicles}->{$player}->{xp} || 0;
            $list->{$player} = $xp;
            $team_xp->[$tid] += $r->{vehicles}->{$player}->{xp};
        }

        foreach my $id (sort { $list->{$b} <=> $list->{$a} } (keys(%$list))) {
            push(@{$xp_sorted_teams->[$tid]}, $id);
        }
    }

    my $team_total_xp = [ $team_xp->[0], $team_xp->[1] ];

    $team_xp->[0] = ($team_xp->[0] > 0 && scalar(@{$r->{teams}->[0]}) > 0) ? int($team_xp->[0] / scalar(@{$r->{teams}->[0]})) : 0;
    $team_xp->[1] = ($team_xp->[1] > 0 && scalar(@{$r->{teams}->[1]}) > 0) ? int($team_xp->[1] / scalar(@{$r->{teams}->[1]})) : 0;
    $team_xp->[2] = ($team_xp->[0] + $team_xp->[1] > 0) ? int(($team_xp->[0] + $team_xp->[1]) / 2) : 0;

    my $playerteam = $r->{player}->{team} - 1;

    if($playerteam == 0) {
        $r->{teams} = [ $xp_sorted_teams->[0], $xp_sorted_teams->[1] ];
        $r->{teamxp} = [ $team_xp->[0], $team_xp->[1], $team_xp->[2] ];
        $r->{teamtotalxp} = [ $team_total_xp->[0], $team_total_xp->[1] ];
    } else {
        $r->{teams} = [ $xp_sorted_teams->[1], $xp_sorted_teams->[0] ];
        $r->{teamxp} = [ $team_xp->[1], $team_xp->[0], $team_xp->[2] ];
        $r->{teamtotalxp} = [ $team_total_xp->[1], $team_total_xp->[0] ];
    }

    my $dossier_popups = {};
    my $other_awards = [];
    my $achievements = WR::Res::Achievements->new();

    my $ah = { map { $_ => 1 } @{$r->{statistics}->{achievements}} };

    foreach my $e (@{$r->{statistics}->{dossierPopUps}}) {
        $dossier_popups->{$e->[0]} = $e->[1]; # id, count
        next if($achievements->is_battle($e->[0])); # don't want the battle awards to be in other awards
        next if(defined($ah->{$e->[0]})); # if they were given in battle, keep them there

        if($achievements->is_class($e->[0])) {
            # class achievements get the whole medalKay1..4 etc. bit so add a class suffix, and no count
            push(@$other_awards, {
                class_suffix => $e->[1],
                count => undef,
                type => $e->[0],
            });
        } elsif($achievements->is_single($e->[0])) {
            # non-repeatables, no suffix, no count
            push(@$other_awards, {
                class_suffix => undef,
                count => undef,
                type => $e->[0],
            });
        } elsif($achievements->is_repeatable($e->[0])) {
            # repeatables, have a count
            push(@$other_awards, {
                class_suffix => undef,
                count => $e->[1],
                type => $e->[0],
            });
        }
    }

    $self->stash('dossier_popups' => $dossier_popups);
    $self->stash('other_awards' => $other_awards);

    # get any related replays
    if(my $related = $self->model('wot-replays.replays.related')->find_one({ 'value.count' => { '$gt' => 1 }, _id => $r->{game}->{arena_id} . '' })) {
        my $in = [];
        foreach my $id (@{$related->{value}->{ids}}) {
            next if($id->to_string eq $r->{_id}->to_string);
            push(@$in, $id);
        }

        $self->stash('related' => {
            count   => $related->{value}->{count},
            replays => [ $self->model('wot-replays.replays')->find({ _id => { '$in' => $in }})->all() ],
        });
    } else {
        $self->stash(related => { count => 0, replays => [] });
    }

    $self->model('wot-replays.replays')->update({ _id => $r->{_id} }, {
        '$inc' => { 'site.views' => 1 },
    });

    $r->{site}->{views} += 1; 

    $self->respond(
        stash => {
            replay => $r,
            page   => {
                title => $title,
                description => $description,
            },
            timing_view => tv_interval($start, [ gettimeofday ]),
        }, 
        template => 'replay/view/index',
    );
}

1;
