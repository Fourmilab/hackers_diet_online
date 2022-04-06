#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    package HDiet::hdCSV;

    require Exporter;

    our @ISA = qw(Exporter);
    our @EXPORT = qw(parseCSV encodeCSV);
    1;

    sub parseCSV {
        my ($s) = @_;

        my @fields;
        my $f;

        $s =~ s/\s+$//;
        $s =~ s/,$/,""/;

        while ($s ne '') {
            if ($s =~ s/^\s*"((?:""|[^"])*)"\s*,?//) {

                $f = $1;
                $f =~ s/""/"/g;
                my $uf = '';
                while ($f =~ s/^(.)//) {
                    my $c = $1;
                    if ($c eq "\\") {
                        if ($f =~ s/\\//) {
                            $uf .= "\\";
                        } elsif ($f =~ s/x\{([0-7a-fA-F]+)\}//) {
                            $uf .= chr(hex($1));
                        } else {
                            print(STDERR "Undefined backslash escape \\$f in CSV record.\n");
                        }
                    } else {
                        $uf .= $1;
                    }
                }
                $f = $uf;
            } else {
                $s =~ s/^\s*([^,]*),?//;
                $f = $1;
                $f =~ s/\s+$//
            }

            push(@fields, $f);
        }

        return @fields;
    }

    sub encodeCSV {
        my $f;
        my $s = '';

        while (defined($f = shift)) {

            #   Encode any non-ISO-8859-1 graphic characters
            #   (including wide characters) as hexadecimal escape
            #   sequences and force any backslashes in the
            #   string.

            my $ef = '';
            my $forced = 0;
            while ($f =~ s/^(.)//) {
                my $o = ord($1);
                if (($o < 32) ||
                    (($o >= 127) && ($o < 161)) ||
                    ($o > 255)) {
                    $ef .= sprintf("\\x{%lx}", $o);
                    $forced = 1;
                } elsif ($1 eq "\\") {
                    $ef .= "\\\\";
                    $forced = 1;
                } else {
                    $ef .= $1;
                }
            }

            #   If the field contains leading or trailing white
            #   space, an embedded comma, quote, or an escaped character,
            #   force quotes within it and enclose in quotes.

            if (($ef =~ m/^\s/) || ($ef =~ m/\s$/) ||
                ($ef =~ m/,/) || ($ef =~ m/"/) || $forced) {
                $ef =~ s/"/""/g;
                $ef = '"' . $ef . '"';
            }

            $s .= $ef . ',';
        }

        $s =~ s/,$//;
        return $s;
    }
