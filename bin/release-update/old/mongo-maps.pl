#!/usr/bin/perl
use strict;
use FindBin;
use lib ("$FindBin::Bin/lib","$FindBin::Bin/../lib","$FindBin::Bin/../../lib");
use WR;
use WR::XMLReader;
use Data::Localize;
use Data::Localize::Gettext;
use Mango;
use Mango::BSON;
use JSON::XS;
use File::Slurp qw/read_file/;
use Data::Dumper;

die 'Usage: mongo-maps.pl <path to arena defs> <path to arenas.po>', "\n" unless($ARGV[1]);
my $arena_defs = shift(@ARGV);
my $arena_po   = shift(@ARGV);
my @maps       = (@ARGV);

my $text = Data::Localize::Gettext->new(path => $arena_po);

my $mango  = Mango->new($ENV{'MONGO'} || 'mongodb://localhost');
my $db     = $mango->db('wot-replays');
my $coll   = $db->collection('data.maps');

# first find the list of arenas
my $arena_list = sprintf('%s/_list_.xml', $arena_defs);

my $list_reader = WR::XMLReader->new(filename => $arena_list);
my $list        = $list_reader->parse;

sub get_position {
    my $pos = shift;
    my $r;
    if(ref($pos) eq 'ARRAY') {
        $r = [];
        foreach my $tpos (@$pos) {
            push(@$r, [ map { $_ + 0 } (split(/\s/, $tpos, 2)) ]);
        }
    } elsif(ref($pos) eq 'HASH') {
        return undef; # maybe empty array?
    } else {
        $r = [ [ map { $_ + 0 } (split(/\s/, $pos, 2)) ] ];
    }
    return $r;
}

print Dumper($list);

foreach my $raw (@{$list->{map}}) {
    my $map = make_map_base($raw);
    my $map_reader = WR::XMLReader->new(filename => sprintf('%s/%s.xml', $arena_defs, $map->{_id}));
    my $map_data   = $map_reader->parse;

    $map->{attributes}->{camouflage} = $map_data->{vehicleCamouflageKind};
    $map->{attributes}->{positions} = {};

    foreach my $type (keys(%{$map_data->{gameplayTypes}})) {
        # bases can come in multiple positions
        my $gt = $map_data->{gameplayTypes}->{$type};
        my $pos = {};

        if($type eq 'assault') {
            my $basepos = [];
            if(defined($gt->{teamBasePositions}->{team2})) {
                my $t = $gt->{teamBasePositions}->{team2};
                if(scalar(keys(%$t)) > 0) {
                    $basepos->[1] = get_position($t->{position1});
                } else {
                    $basepos->[1] = undef;
                }
            }
            if(defined($gt->{teamBasePositions}->{team1})) {
                my $t = $gt->{teamBasePositions}->{team1};
                if(scalar(keys(%$t)) > 0) {
                    $basepos->[0] = get_position($t->{position1});
                } else {
                    $basepos->[0] = undef;
                }
            }

            $pos->{base} = $basepos;

            if(defined($gt->{teamSpawnPoints})) {
                if(defined($gt->{teamSpawnPoints}->{team1}->{position})) {
                    $pos->{team}->[0] = get_position($gt->{teamSpawnPoints}->{team1}->{position});
                }
                if(defined($gt->{teamSpawnPoints}->{team2}->{position})) {
                    $pos->{team}->[1] = get_position($gt->{teamSpawnPoints}->{team2}->{position});
                }
            } else {
                $pos->{team} = [ [ [ 0, 0 ] ], [ [ 0, 0 ] ] ];
            }
        } elsif($type eq 'ctf') {
            # ctf has 2 bases
            if(defined($gt->{teamBasePositions}->{team1}->{position1})) {
                $pos->{base}->[0] = get_position($gt->{teamBasePositions}->{team1}->{position1});
            }
            if(defined($gt->{teamBasePositions}->{team2}->{position1})) {
                $pos->{base}->[1] = get_position($gt->{teamBasePositions}->{team2}->{position1});
            }
            # but it may also have additional team points
            if(defined($gt->{teamSpawnPoints})) {
                if(defined($gt->{teamSpawnPoints}->{team1}->{position})) {
                    $pos->{team}->[0] = get_position($gt->{teamSpawnPoints}->{team1}->{position});
                }
                if(defined($gt->{teamSpawnPoints}->{team2}->{position})) {
                    $pos->{team}->[1] = get_position($gt->{teamSpawnPoints}->{team2}->{position});
                }
            } else {
                $pos->{team} = [ undef, undef ];
            }
        } else {
            # encounter mode, has a control point, and 2 team spawns
            $pos->{control} = get_position($gt->{controlPoint});
            if(defined($gt->{teamSpawnPoints})) {
                if(defined($gt->{teamSpawnPoints}->{team1}->{position})) {
                    $pos->{team}->[0] = get_position($gt->{teamSpawnPoints}->{team1}->{position});
                }
                if(defined($gt->{teamSpawnPoints}->{team2}->{position})) {
                    $pos->{team}->[1] = get_position($gt->{teamSpawnPoints}->{team2}->{position});
                }
            } else {
                $pos->{team} = [ [ [ 0, 0 ] ], [ [ 0, 0 ] ] ];
            }
        }
        $map->{attributes}->{positions}->{$type} = $pos;
    }

    print '-' x 80, "\n", $map->{label}, "\n", '-' x 80, "\n", Dumper($map_data->{gameplayTypes}), "\n\n", Dumper($map->{attributes}->{positions}), "\n\n\n";

    # get the bounding box, and the length/width of the map
    my $bb = $map_data->{boundingBox};
    my $ur = [ map { $_ + 0 } (split(/\s/, $bb->{upperRight}, 2)) ];
    my $bl = [ map { $_ + 0 } (split(/\s/, $bb->{bottomLeft}, 2)) ];
    my $width = $ur->[0] - $bl->[0];
    my $height = $ur->[1] - $bl->[1];

    $map->{attributes}->{geometry} = {
        upper_right => $ur,
        bottom_left => $bl,
        width_height => [ $width, $height ],
    };

    $coll->save($map);
}

sub make_map_base {
    my $map = shift;
    my ($dummy, $id) = split(/_/, $map->{name}, 2);

    my $name = $text->localize_for(lang => 'arenas', id => sprintf('%s/name', $map->{name}));

    die 'no name for map, arenas.po path is set to ', $arena_po, "\n" unless(defined($name));

    my $slug = lc($name);
    $slug =~ s/\s+//g;
    $slug =~ s/'//g;

    my $data = {
        _id             => $map->{name},
        name_id         => $id,
        numerical_id    => $map->{id} + 0,
        label           => $name,
        slug            => $slug,
        icon            => lc(sprintf('%s.png', $map->{name})),
        i18n            => sprintf('#arenas:%s/name', $map->{name}),
        attributes      => {},
    };
    return $data;
}
