#!/usr/bin/env perl
use 5.018;
use warnings;

use Cwd;
use MAB2::Parser::Disk;
use HKS3::MARC21Web qw/
                       get_marc_via_id
                       get_empty_auth_record
                       marc_record_from_xml
                       add_field
                       get_marc_file
                    /;
use Text::CSV qw/ csv /;

die "CACHE_DIR not defined" unless $ENV{CACHE_DIR};
my $cwd = getcwd();

my $filename = $ARGV[0];
my $file = $cwd . '/' . $filename;
die "Not a file. ($file)" unless -f $file;

my $mappingfilename = $ARGV[1];
my $mappingfile = $cwd . '/' . $mappingfilename;
die "Not a file. ($mappingfile)" unless -f $mappingfile;

my $parser = MAB2::Parser::Disk->new( $file );

my $count = 0;
my $count_isbn = 0;
my $cache_dir = $ENV{CACHE_DIR};

my $mapping_mab2_marc = get_mapping();

my $marc_file = get_marc_file( 'hdn_marc.xml' );

while ( my $mab_record_hash = $parser->next() ) {
    my $mab_record = $mab_record_hash->{record};
    my $isbn = get_isbn($mab_record);
    $count++;
    my $xml = '';
    my $marc_record;
    if ($isbn) {
        $count_isbn++;
        $xml = get_marc_via_id($isbn, 'ISBN', $cache_dir, ['dnb']);
    }

    if ($xml) {
        $marc_record = marc_record_from_xml($xml);
    }
    else {
        $xml = get_empty_auth_record();
        $marc_record = marc_record_from_xml($xml);
        for my $field ($mab_record->@*) {
            if (exists $mapping_mab2_marc->{ $field->[0] }) {
                my $m = $mapping_mab2_marc->{ $field->[0] };
                #say $m->{name} . ': ' . $field->[3];
                add_field(
                    $marc_record,
                    $m->{'marc-field'},
                    $m->{'marc-ind1'},
                    $m->{'marc-ind2'},
                    $m->{'marc-subfield'},
                    $field->[3],
                );
            }
            else {
                #die "unknown mab2 field: " . $field->[0];
            }
        }
    }

    $marc_file->write($marc_record);
}

say "$count/$count_isbn";

sub get_isbn {
    my ($record) = @_;
    my $isbn = '';
    for my $field ($record->@*) {
        if ( $field->[0] eq '540' && $field->[1] eq 'a' ) {
            $isbn = $field->[3];
            $isbn = strip_isbn_prefix($isbn);
        }
    }
    return $isbn;
}
sub strip_isbn_prefix {
    my $isbn = shift;
    my $prefix = 'ISBN';
    if ( substr($isbn, 0, length $prefix) eq $prefix ) {
        $isbn = substr($isbn, 1 + length $prefix);
    }
    return $isbn;
}

sub get_mapping {

    my $csv = csv(
        in         => $mappingfile,
        sep_char   => ";",
        quote_char => '"',
        headers    => "auto",
        encoding   => "UTF-8",
    );
    # name, mab2-field, mab2-subfield, marc21-field, marc21-subfield, ind1, ind2
    my $mapping_data = [
        #[ 'Titel', '331', ' ', '245', 'a', ' ', ' ' ],
        #[ 'ISBN', '540', ' ', '020', 'a', ' ', ' ' ],
    ];
    for my $mapping (@$csv) {
        my $re_MAB2 = qr/
                     ^
                     (\d\d\d)
                     ([a-z])?
                     $
        /xms;
        my ($field_MAB, $subfield_MAB) = $mapping->{MAB2} =~ $re_MAB2;

        my $re_MARC21 = qr/
                     ^
                     (\d\d\d)
                     ([a-z])
                     (?:
                         \ 
                         ([\w\#])
                         ([\w\#])
                     )?
                     $
        /xms;
        my ($field_MARC, $subfield_MARC, $ind1_MARC, $ind2_MARC) = $mapping->{MARC21} =~ $re_MARC21;

        if ($field_MAB && $field_MARC) {
            say "map " . $mapping->{MAB2} . " to " . $mapping->{MARC21};
            push $mapping_data->@*,
                 [
                     $mapping->{Bezeichnung},
                     $field_MAB,
                     $subfield_MAB,
                     $field_MARC,
                     $subfield_MARC,
                     $ind1_MARC,
                     $ind2_MARC,
                 ];
        }
        else {
          print "invalid mapping: " . $mapping->{MAB2} . " to " . $mapping->{MARC21};
          say " (MAB2 ERROR)" unless $field_MAB;
          say " (MARC21 ERROR)" unless $field_MARC;
        }
    }

    my $mapping_mab2_marc = {};
    for my $m ($mapping_data->@*) {
        $mapping_mab2_marc->{ $m->[1] } = {
                                            name            => $m->[0],
                                            'mab2-subfield' => $m->[2],
                                            'marc-field'    => $m->[3],
                                            'marc-subfield' => $m->[4],
                                            'marc-ind1'     => $m->[5],
                                            'marc-ind2'     => $m->[6],
                                          }
    }

    return $mapping_mab2_marc;
}
