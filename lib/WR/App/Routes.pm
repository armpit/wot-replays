package WR::App::Routes;
use strict;
use warnings;

sub install {
    my $dummy = shift;
    my $self  = shift;
    my $rts   = shift;

    $rts->route('/postaction')->to('postaction#nginx_post_action');

    my $r = $rts->bridge('/')->to(cb => sub {
        my $self = shift;
    
        $self->app->log->debug('bridge cb top');
        my $r = $self->init_auth();
        $self->app->log->debug('bridge cb bottom');
        return $r;
    });

    my $rb = $r->under('/replay/:replay_id');
        $rb->route('/battleviewer')->to('replays-view#battleviewer', pageid => 'battleviewer', page => { title => 'replay.battleviewer.page.title' });
        $rb->route('/download')->to('replays-export#download', pageid => undef);
        $rb->route('/packets')->to('replays-view#packets', pageid => undef);
        $rb->route('/comment')->to('replays-view#addcomment');
        $rb->route('/delcomment/:comment_id')->to('replays-view#delcomment');
        $rb->route('/heatmap')->to('replays-view#heatmap', pageid => 'battleheatmap', page => { title => 'replay.heatmap.page.title' });
        $rb->route('/desc')->to('replays#desc', pageid => undef);
        $rb->route('/up')->to('replays-rate#rate_up', pageid => undef);
        $rb->route('/')->to('replays-view#view', pageid => 'replay')->name('viewreplay');

    $r->route('/')->to('replays#browse', 
        filter_opts => {},
        pageid      => 'home', 
        filter_root => 'browse',
        page        => { 
            title       => 'index.page.title' 
        }, 
        browse => { 
            heading     => 'index.page.header' 
        },
        browse_filter_raw   =>  {
            p   =>  1,
            v   =>  '*',
            tmi =>  1,
            tma =>  10,
            m   =>  '*',
            mt  =>  '*',
            mm  =>  '*',
            sr  =>  'upload',
            s   =>  '*',
            vp  =>  1,
            vi  =>  0
        },
        initialize_with => [ '_fp_competitions', '_fp_notifications' ],
    );

    $r->route('/browse/*filter')->to('replays#browse', filter_opts => {}, pageid => 'browse', page => { title => 'browse.page.title' }, filter_root => 'browse');
    $r->route('/browse')->to(cb => sub {
        my $self = shift;
        $self->stash('browse_filter_raw' => {
            p   => 1,
            vp  => 1,
            vi  => 0,
            tmi => 1,
            tma => 10,
            v   => '*',
            m   => '*',
            s   => '*',
            mm  => '*',
            mt  => '*',
            sr  => 'upload',
        }, pageid => 'browse');
        $self->redirect_to(sprintf('/browse/%s', $self->browse_page(1)));
    });

    my $upload = $r->under('/upload');
        $upload->route('/')->to('replays-upload#upload', pageid => 'upload', upload_type => 'single');
        $upload->route('/process')->to('replays-upload#process_upload');
        $upload->route('/:upload_type')->to('replays-upload#upload', pageid => 'upload');

    my $xhr = $r->under('/xhr');
        $xhr->route('/qs')->to('ui#xhr_qs');
        $xhr->route('/ds')->to('ui#xhr_ds');
        $xhr->route('/du')->to('ui#xhr_du');
        $xhr->route('/dn_d')->to(cb => sub {
            my $self = shift;
            
            $self->render_later;
            if($self->req->is_xhr) {
                $self->dismiss_notification($self->req->param('id') => sub {
                    $self->render(json => { ok => 1 });
                });
            } else {
                $self->render(text => 'No.', status => 403);
            }
        });
    
    my $lang = $r->under('/lang');
        $lang->route('/:lang')->to('ui#xhr_po');

    my $bv = $r->under('/battleviewer/:replay_id');
        $bv->route('/')->to('replays-view#battleviewer', pageid => 'battleviewer', page => { title => 'replay.battleviewer.page.title' });

    my $bhm = $r->under('/battleheatmap/:replay_id');
        $bhm->route('/')->to('replays-view#heatmap', pageid => 'battleheatmap', page => { title => 'replay.heatmap.page.title' });

    $r->route('/clans')->to('clan#index', pageid => 'clan', page => { title => 'clans.page.title' });
    my $clan = $r->under('/clan');
        $clan->route('/:server/:clanticker')->to(cb => sub {
            my $self = shift;
            $self->stash('browse_filter_raw' => {
                p   => 1,
                vp  => 1,
                m   => '*',
                s   => '*',
                mm  => '*',
                mt  => '*',
                sr  => 'upload',
                pp  => 1, 
                pi  => 0,
            });
            $self->redirect_to(sprintf('/clan/%s/%s/%s', $self->stash('server'), $self->stash('clanticker'), $self->browse_page(1)));
        }, pageid => 'clan');

        $clan->route('/:server/:clanticker/*filter')->to('replays#browse', next => 'browse',
            page => {
                title => 'clan.page.title',
                title_args => [ 'clanticker' ],
            },
            pageid => 'clan',
            filter_opts => {
                base_query => sub {
                    my $self = shift;
                    return { 'c' => $self->stash('clanticker'), 's' => $self->stash('server') };
                },
                filter_root => sub {
                    my $self = shift;
                    return sprintf('clan/%s/%s', $self->stash('server'), $self->stash('clanticker'));
                }
            }
        );

    $r->route('/players')->to('player#index', pageid => 'player', page => { title => 'players.page.title' });
    my $player = $r->under('/player');
        $player->route('/:server/:player_name')->to(cb => sub {
            my $self = shift;
            $self->stash('browse_filter_raw' => {
                p   => 1,
                vp  => 1,
                m   => '*',
                s   => '*',
                mm  => '*',
                mt  => '*',
                sr  => 'upload',
                pp  => 1, 
                pi  => 0,
            });
            $self->redirect_to(sprintf('/player/%s/%s/%s', $self->stash('server'), $self->stash('player_name'), $self->browse_page(1)));
        }, pageid => 'player');
        $player->route('/:server/:player_name/latest')->to('player#latest', pageid => 'player');
        $player->route('/:server/:player_name/*filter')->to('replays#browse', next => 'browse',
            page => {
                title => 'player.page.title',
                title_args => [ 'player_name' ],
            },
            pageid => 'player',
            filter_opts => {
                base_query => sub {
                    my $self = shift;
                    return { 'pl' => $self->stash('player_name'), 's' => $self->stash('server') };
                },
                filter_root => sub {
                    my $self = shift;
                    return sprintf('player/%s/%s', $self->stash('server'), $self->stash('player_name'));
                }
            }
        );


    my $vehicles = $r->under('/vehicles');
        $vehicles->route('/')->to('vehicle#select', 
            pageid  => 'vehicle', 
            page    => { 
                title   => 'vehicles.page.title', 
                title_args => [ 't:Select Nation' ],
            }
        );
        $vehicles->route('/:country')->to('vehicle#index', 
            pageid  => 'vehicle', 
            page    => { 
                title   => 'vehicles.page.title', 
                title_args => [ 'l:nations:country' ],
            }
        );

    my $vehicle = $r->under('/vehicle');
        $vehicle->route('/:country/:vehicle')->to(cb => sub {
            my $self = shift;
            $self->stash('browse_filter_raw' => {
                p   => 1,
                vp  => 1,
                m   => '*',
                s   => '*',
                mm  => '*',
                mt  => '*',
                sr  => 'upload',
            });
            $self->redirect_to(sprintf('/vehicle/%s/%s/%s', $self->stash('country'), $self->stash('vehicle'), $self->browse_page(1)));
        }, pageid => 'vehicle');
        $vehicle->route('/:country/:vehicle/*filter')->to('replays#browse', 
            page => {
                title       => 'vehicle.page.title',
                title_args  => [ 'd:data.vehicles:name:vehicle:i18n' ],
            },
            pageid => 'vehicle',
            filter_opts => {
                base_query => sub {
                    my $self = shift;
                    return { 'v' => sprintf('%s:%s', $self->stash('country'), $self->stash('vehicle')) };
                },
                filter_root => sub {
                    my $self = shift;
                    return sprintf('vehicle/%s/%s', $self->stash('country'), $self->stash('vehicle'));
                }
            }
        );


    $r->route('/maps')->to('map#index', pageid => 'map');

=pod
    my $heatmaps = $r->under('/heatmaps');
        $heatmaps->route('/:map_ident')->to('heatmap#view', next => 'view', page => { title => 'heatmaps.page.title', title_args => [ 'map_name' ] });
=cut

    my $map = $r->under('/map');
        $map->route('/:map_id')->to(cb => sub {
            my $self = shift;
            $self->stash('browse_filter_raw' => {
                p   => 1,
                vp  => 1,
                tmi => 1,
                tma => 10,
                v   => '*',
                s   => '*',
                mm  => '*',
                mt  => '*',
                sr  => 'upload',
            });
            $self->redirect_to(sprintf('/map/%s/%s', $self->stash('map_id'), $self->browse_page(1)));
        }, pageid => 'map');
        $map->route('/:map_id/*filter')->to('replays#browse', 
            page => {
                title => 'map.page.title',
                title_args => [ 'map_name' ],
            },
            pageid => 'map',
            filter_opts => {
                async      => 1,
                base_query => sub {
                    my $self = shift;
                    my $cb   = shift;
                    my $slug = $self->stash('map_id');

                    $self->model('wot-replays.data.maps')->find_one({ slug => $slug } => sub {
                        my ($coll, $err, $doc) = (@_);
                        $self->stash('map_name' => $self->loc($doc->{i18n}));
                        $cb->({ m => $doc->{numerical_id }});
                    });
                },
                filter_root => sub {
                    my $self = shift;
                    return sprintf('map/%s', $self->stash('map_id'));
                }
            }
        );
   
    $r->route('/competitions')->to('competition#list', pageid => 'competition', page => { title => 'competitions.page.title' });
    my $competition = $r->under('/competition');
        my $cbridge = $competition->bridge('/:competition_id')->to('competition#bridge'); # loads the competition
            $cbridge->route('/')->to('competition#view', pageid => 'competition', page => { title => 'competition.page.title', title_args => [ 'competition_title' ] });
            $cbridge->route('/:server/:identifier')->to('replays#browse',
                pageid      => 'competition', 
                filter_opts => {
                    async      => 1,
                    # never should've named it that but hey... 
                    base_query => sub {
                        my $self     = shift;
                        my $cb       = shift;
                        my $id       = $self->stash('identifier');
                        my $server   = $self->stash('server');
                        my $config   = $self->stash('competition')->{config};
                        my $event    = WR::Event->new(log => $self->app->log, db => $self->get_database, %$config);

                        # get the merge args
                        my $base = $event->get_leaderboard_entries({ pi => 0, pp => 1, pl => $id, s => $server, _inc => [qw/pi pp pl s/] });
                        $cb->($base);
                    },
                    filter_root => sub {
                        my $self = shift;
                        return sprintf('competition/%s/%s/%s', $self->stash('competition_id'), $self->stash('server'), $self->stash('identifier'));
                    }
                },
                page        => { 
                    title       => 'competition.page.entries.title',
                    title_args  => [ 'competition_name', 'identifier' ],
                }, 
            );
            $cbridge->route('/:server/:identifier/*filter')->to('replays#browse', 
                pageid      => 'competition', 
                filter_opts => {
                    async      => 1,
                    # never should've named it that but hey... 
                    base_query => sub {
                        my $self = shift;
                        my $cb   = shift;
                        my $server = $self->stash('server');
                        my $id   = $self->stash('identifier');
                        my $config = $self->stash('competition')->{config};
                        my $event = WR::Event->new(log => $self->app->log, db => $self->get_database, %$config);

                        # get the merge args
                        my $base = $event->get_leaderboard_entries({ pi => 0, pp => 1, pl => $id, s => $server, _inc => [qw/pi pp pl s/] });
                        $cb->($base);
                    },
                    filter_root => sub {
                        my $self = shift;
                        return sprintf('competition/%s/%s/%s', $self->stash('competition_id'), $self->stash('server'), $self->stash('identifier'));
                    }
                },
                page        => { 
                    title       => 'competition.page.entries.title',
                    title_args  => [ 'competition_name', 'identifier' ],
                }, 
            );


    my $login = $r->under('/login');
        $login->route('/')->to('auth#do_login', pageid => 'login');
        $login->route('/:s')->to('auth#do_login', pageid => 'login');

    $r->route('/logout')->to('auth#do_logout');

    my $openid = $r->under('/openid');
        $openid->any('/return/:type')->to('auth#openid_return', type => 'default');


    my $doc = $r->under('/doc');
        for(qw/about credits missions replayprivacy/) {
            warn 'doc route returns: ', $doc->route(sprintf('/%s', $_))->to('ui#doc', docfile => $_, pageid => $_), "\n";
        }

        $doc->route('/donate')->to(cb => sub {
            my $self = shift;
            $self->redirect_to('http://www.patreon.com/scrambled');
        });


    my $pb = $r->bridge('/profile')->to('profile#bridge');
        $pb->route('/replays/type/:type/page/:page')->to('profile#replays', mustauth => 1, pageid => 'profile', page => { title => 'profile.replays.page.title' });
        $pb->route('/uploads/page/:page')->to('profile#uploads', pageid => 'profile', page => { title => 'profile.uploads.page.title' });
        $pb->route('/settings')->to('profile#settings', pageid => 'profile', page => { title => 'profile.settings.page.title' });
        $pb->route('/sl/:lang')->to('profile#sl', pageid => 'profile');
        $pb->route('/link')->to('auth#do_link', pageid => 'profile');
        $pb->route('/link/:s')->to('auth#do_link', pageid => 'profile');
        $pb->route('/linked/:status')->to('profile#linked', pageid => 'profile');

        my $pbj = $pb->under('/j');
            $pbj->route('/sr')->to('profile#sr', pageid => 'profile');
            $pbj->route('/hr')->to('profile#hr', pageid => 'profile');
            $pbj->route('/pr')->to('profile#pr', pageid => 'profile');
            $pbj->route('/cr')->to('profile#cr', pageid => 'profile');
            $pbj->route('/plr')->to('profile#plr', pageid => 'profile');
            $pbj->route('/tr')->to('profile#tr', pageid => 'profile');
            $pbj->route('/setting')->to('profile#setting', pageid => 'profile');

    my $statistics = $r->under('/statistics');
        my $mastery = $statistics->under('/mastery');
            $mastery->route('/')->to('statistics-mastery#index', pageid => 'statistics/mastery');
            $mastery->route('/csv/:filedate')->to('statistics-mastery#as_csv', pageid => 'statistics/mastery');

    my $admin = $r->bridge('/admin')->to('admin#bridge');
        $admin->route('/')->to('admin#index', pageid => 'admin/home');
        $admin->route('/usersonline')->to('admin#get_online_users');
        $admin->route('/uploadslist')->to('admin#get_upload_queue');
        $admin->route('/todaycount')->to('admin#get_today_count');
        $admin->route('/replaycount')->to('admin#get_replay_count');

        $admin->route('/events')->to('admin-events#index', pageid => 'admin/events');

        my $language = $admin->bridge('/language');
            $language->route('/')->to('admin-language#redir', pageid => 'admin/language');
            my $langroot = $language->bridge('/:lang')->to('admin-language#language_bridge');
                $langroot->route('/')->to('admin-language#index', pageid => 'admin/language', section => '--');
                $langroot->route('/publish')->to('admin-language#publish', pageid => 'admin/language');
                my $section = $langroot->under('/:section');
                    $section->route('/')->to('admin-language#section', pageid => 'admin/language');
                    $section->route('/single')->via(qw/POST/)->to('admin-language#save_single');
                    $section->route('/all')->via(qw/POST/)->to('admin-language#save_all');

        my $site = $admin->under('/site');
            my $replays = $site->under('/replays');
                $replays->route('/page/:page')->to('admin-site#replays', pageid => 'admin/site');
            my $uploads = $site->under('/uploads');
                $uploads->route('/page/:page')->to('admin-site#uploads', pageid => 'admin/site');
            my $notifications = $site->under('/notifications');
                $notifications->route('/')->to('admin-site#notifications', pageid => 'admin/notifications');

        my $modtools = $admin->under('/moderator');
            my $chatreader = $modtools->under('/chatreader');
                $chatreader->route('/')->to('admin-moderator-chatreader#index', pageid => 'admin/moderator');
                $chatreader->route('/process')->to('admin-moderator-chatreader#process');
            my $bothunter = $modtools->under('/bothunter');
                $bothunter->route('/')->to('admin-moderator-bothunter#index', pageid => 'admin/moderator');
                $bothunter->route('/process')->to('admin-moderator-bothunter#process');
}

1;
