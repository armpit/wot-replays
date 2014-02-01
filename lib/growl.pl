#!/usr/bin/perl
use strict;
use warnings;
use WR::Thunderpush;
use Data::Dumper;
use Mojo::IOLoop;

my $p = WR::Thunderpush->new(
    host => 'bacon.wotreplays.org:20000',
    key     => '52ecedef9c81a515f6010000',
    secret  => '52ecee0f9c81a5163c010000',
    );

$p->send_to_channel('site' => { evt => 'growl', data => { type => 'info', allow_dismiss => Mojo::JSON->true, delay => 10000, text => join(' ', @ARGV) }  } => sub {
    my ($p, $res) = (@_);

    print Dumper($res);
    exit(0);
});

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
