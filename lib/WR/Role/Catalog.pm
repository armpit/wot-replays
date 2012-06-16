package WR::Role::Catalog;
use Moose::Role;
use File::Slurp;
use JSON::XS qw(decode_json);
use Try::Tiny;

has '_catalog' => (is => 'ro', isa => 'HashRef', required => 1, lazy => 1, builder => '_build_catalog');
has '_path' => (is => 'ro', isa => 'Str', required => 1, builder => '_build_path');

sub _build_path {
    my $self = shift;

    return (-e '/home/wotreplay/wot-replays/etc/res') 
        ? '/home/wotreplay/wot-replays/etc/res'
        : sprintf('%s/projects/wot-replays/etc/res', $ENV{HOME});
}

sub _build_catalog {
    my $self = shift;
    my $class = blessed($self);

    $class =~ s/.*://g;

    my $catfile = sprintf('%s/%s.json', $self->_path, lc($class));
    my $content = read_file($catfile);
    my $cat = {};

    try {
        $cat = decode_json($content);
    } catch {
        warn __PACKAGE__, ': catalog decoding error for ', $catfile, ': ', $_, "\n";
    };

    return $cat;
}

sub i18n {
    my $self = shift;
    my $key  = shift;

    return (defined($self->_catalog->{$key})) 
        ? (defined($self->_catalog->{$key}->{label}))
            ? $self->_catalog->{$key}->{label}
            : sprintf('nolabel:%s', $key)
        : sprintf('nocat:%s', $key);
}

sub get {
    my $self = shift;
    my $key  = shift;
    my $field = shift;

    return (defined($self->_catalog->{$key}))
        ? (defined($self->_catalog->{$key}->{$field}))
            ? $self->_catalog->{$key}->{$field}
            : undef
        : undef;
}

no Moose::Role;
1;


