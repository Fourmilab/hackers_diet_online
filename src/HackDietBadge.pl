#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    use Crypt::OpenSSL::AES;
    use Crypt::CBC;
    use HDiet::Digest::Crc32;

    print <<"EOD";
Content-type: image/png\r
Pragma: no-cache\r
EOD

    if (defined($ENV{QUERY_STRING}) && ($ENV{QUERY_STRING} =~ m/b=([0-9FGJKQW]+)/)) {
        my $cuserid = $1;

        my $btype;
        if ($ENV{QUERY_STRING} =~ m/t=(\d+)/) {
            $btype = $1;
        } else {
            $btype = 0;
        }

        my $user_file_name;

        eval {
            $user_file_name = decodeEncryptedUserID($cuserid);
        };

        if ((!$@) && defined($user_file_name) &&
            open(BI, "</server/pub/hackdiet/Users/$user_file_name/BadgeImage.png")) {
        } else {
            open(BI, "</server/bin/httpd/cgi-bin/HDiet/Images/steenkin_badge.png") ||
                die("Cannot open /server/bin/httpd/cgi-bin/HDiet/Images/steenkin_badge.png");
            print(STDERR "HackDietBadge: Bogus or corrupted user specification\n");
        }
    } else {
        open(BI, "</server/bin/httpd/cgi-bin/HDiet/Images/steenkin_badge.png") ||
            die("Cannot open /server/bin/httpd/cgi-bin/HDiet/Images/steenkin_badge.png");
        print(STDERR "HackDietBadge: Invalid or missing query string\n");
    }

    print("Content-Length: ", -s BI, "\r\n\r\n");

    my $iobuf;
    while (read(BI, $iobuf, 65536)) {
        print($iobuf);
    }
    close(BI);

    
    sub decodeEncryptedUserID {
        my ($crypt) = @_;

        $crypt =~ tr/FGJKQW/a-f/;
        my $cryptoSig = substr($crypt, 17, 8, "");
        $crypt = pack("H*", $crypt);

        my $crc = new HDiet::Digest::Crc32();
        my $outerSig = sprintf("%08x", $crc->strcrc32($crypt));

        if ($cryptoSig ne $outerSig) {
print(STDERR "user::decodeEncryptedUserID: Outer CRC bad: $cryptoSig $outerSig\n");
            return undef;
        }

        my $crypto = Crypt::CBC->new(
                -key => "Super duper top secret!",
                -cipher => "Crypt::OpenSSL::AES"
                                    );

        my $decrypted = $crypto->decrypt($crypt);

        my $rcrc = substr($decrypted, -8, 8, "");
        my $icrc = sprintf("%08x", $crc->strcrc32($decrypted));

        if ($rcrc ne $icrc) {
print(STDERR "user::decodeEncryptedUserID: Inner CRC bad:  RCRC = $rcrc  ICRC = $icrc\n");
            return undef;
        }

        return substr($decrypted, 13, -11);
     }

