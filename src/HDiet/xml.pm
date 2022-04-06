#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    package HDiet::xml;

    require Exporter;

    our @ISA = qw(Exporter);
    our @EXPORT = qw(
                       generateXMLprologue
                       generateXMLepilogue
                       textXML
                       quoteXML
                       timeXML
                     );
    our @EXPORT_OK = qw( );
    1;



    sub generateXMLprologue {
        my ($fh) = @_;

        print $fh <<"EOD";
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/css" href="http://www.fourmilab.ch/hackdiet/online/hackdiet_db.css"?>
<!DOCTYPE hackersdiet SYSTEM
          "http://www.fourmilab.ch/hackdiet/online/hackersdiet.dtd">
<hackersdiet version="1.0">
EOD
    }

    sub generateXMLepilogue {
        my ($fh) = @_;

        print $fh <<"EOD";
</hackersdiet>
EOD
    }

    sub quoteXML {
        my ($s, $safe) = @_;

        $s =~ s/&/&amp;/g;
        $s =~ s/</&lt;/g;
        $s =~ s/>/&gt;/g;
        if ($safe) {
            $s =~ s/([\x{80}-\x{FFFF}])/sprintf("&#x%x;", ord($1))/eg;
        }
        return $s;
    }

    sub textXML {
        my ($tagname, $s, $safe) = @_;

        $s = quoteXML($s, $safe);
        my $etagname = $tagname;
        $etagname =~ s/\s+.*$//;
        return "<$tagname>$s</$etagname>";
    }

    sub timeXML {
        my ($utime) = @_;

        my @lmod = gmtime($utime);
        my $lm = sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ",
            $lmod[5] + 1900, $lmod[4] + 1, $lmod[3], $lmod[2], $lmod[1], $lmod[0]);

        return $lm;
    }
