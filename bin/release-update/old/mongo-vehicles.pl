#!/usr/bin/perl
use strict;
use lib qw(lib ../lib ../../lib);
use Data::Localize;
use JSON::XS;
use File::Slurp qw/read_file/;
use Data::Localize::Gettext;
use Mango;

use constant NATION_NAMES => [(qw/ussr germany usa china france uk japan/)];
use constant NATION_INDICES => {
    ussr => 0,
    germany => 1,
    usa => 2,
    china => 3,
    france => 4,
    uk => 5,
    japan => 6
};

die 'Usage: mongo-vehicles.pl <version>', "\n" unless($ARGV[0]);
my $version = $ARGV[0];

my $text = Data::Localize::Gettext->new(path => sprintf('../../etc/res/raw/%s/lang/*_vehicles.po', $version));

my $mango  = Mango->new('mongodb://localhost:27017/');
my $db     = $mango->db('wot-replays');
my $coll   = $db->collection('data.vehicles');

$| = 1;

my $j = JSON::XS->new;


my $b = read_file(sprintf('../../etc/res/raw/%s/vehicles/fix.json', $version));
my $langfix = $j->decode($b);

sub fixed_ident {
    my $id = shift;

    return ($langfix->{$id}) 
        ? $langfix->{$id}
        : $id
} 

for my $country (qw/japan china france germany usa ussr uk/) {
    my $f = sprintf('../../etc/res/raw/%s/vehicles/%s.json', $version, $country);
    print 'processing: ', $f, "\n";
    my $b = read_file($f);
    my $x = $j->decode($b);

    foreach my $vid (keys(%$x)) {
        print "\t", 'ID: ', $vid, "\n";

        my $data = {};
        my $v = $x->{$vid}->{'level'};
        $v =~ s/^\s+//g;
        $v =~ s/\s+$//g;
        $data->{level} = int($v + 0);

        my $us = $x->{$vid}->{'userString'};
        my ($cat, $ident) = split(/:/, $us);
        $cat =~ s/^#//g;

        print "\t\t", 'userString: ', $us, "\n";

        my $tags = { map { $_ => 1 } (split(/\s+/, $x->{$vid}->{tags})) };
        my $type = 'U';

        # find out what type of tank we're dealing with here
        if(defined($tags->{lightTank})) {
            $type = 'L';
        } elsif(defined($tags->{mediumTank})) {
            $type = 'M';
        } elsif(defined($tags->{heavyTank})) {
            $type = 'H';
        } elsif(defined($tags->{SPG})) {
            $type = 'S';
        } elsif(defined($tags->{'AT-SPG'})) {
            $type = 'T';
        }

        $data->{i18n} = $x->{$vid}->{userString};

        warn 'userString: ', $data->{i18n}, "\n";
        warn 'cat: ', $cat, "\n";

        $data->{label} = $text->localize_for(lang => $cat, id => fixed_ident($ident));
        $data->{label_short} = $text->localize_for(lang => $cat, id => fixed_ident(sprintf('%s_short', $ident))) || $data->{label};
        $data->{_id} = sprintf('%s:%s', $country, $vid);
        $data->{country} = $country;
        $data->{name} = $vid;
        $data->{name_lc} = lc($vid);
        $data->{description} = $text->localize_for(lang => $cat, id => fixed_ident(sprintf('%s_descr', $vid)));
        $data->{type} = $type;
        $data->{wot_id} = $x->{$vid}->{id} + 0;

        # generate a typecomp from it
        my $header = 1 + (NATION_INDICES->{$country} << 4);
        my $typecomp = ($data->{wot_id} << 8) + $header;

        $data->{typecomp} = $typecomp;

        $coll->save($data);
    }
    print "\n";
}
