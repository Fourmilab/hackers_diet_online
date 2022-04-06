#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    package HDiet::cookie;

    use Encode qw(encode_utf8);
    use Digest::SHA1  qw(sha1_hex);

    use HDiet::Cluster;
    use HDiet::Julian;
    use HDiet::Digest::Crc32;

    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT = qw( checkCookieSignature storeCookie testCookiePresent );
    1;

    use constant FILE_VERSION => 1;


    sub new {
        my $self = {};
        my ($invocant, $login_name, $login_time, $expiry_time) = @_;
        my $class = ref($invocant) || $invocant;

        $login_name = '' if !defined($login_name);
        $login_time = time() if !defined($login_time);
        $expiry_time = $login_time + (90 * 24 * 60 * 60) if !defined($expiry_time);

        bless($self, $class);

        $self->{version} = FILE_VERSION;

        #   Initialise instance variables
        $self->{login_name} = $login_name;
        if ($login_name ne '') {
            $self->{cookie_id} = generateCookieID($login_name);
        } else {
            $self->{cookie_id} = '';
        }
        $self->{login_time} = $login_time;
        $self->{expiry_time} = $expiry_time;

        return $self;
    }

    sub describe {
        my $self = shift;
        my ($outfile) = @_;

        if (!(defined $outfile)) {
            $outfile = \*STDOUT;
        }

        print($outfile "COOKIE Version: $self->{version}\n");
        print($outfile "  User name:      '$self->{login_name}'\n");
        print($outfile "  Cookie  ID:     '$self->{cookie_id}'\n");
        print($outfile "  Creation time:   " . localtime($self->{login_time}) . "\n");
        print($outfile "  Expiration time: " . localtime($self->{expiry_time}) . "\n");

    }

    sub save {
        my $self = shift;
        my ($outfile) = @_;

        #   File format version number
        print($outfile "$self->{version}\n");
        #   Login name
        print($outfile "$self->{login_name}\n");
        #   Cookie ID
        print($outfile "$self->{cookie_id}\n");
        #   Creation time
        print($outfile "$self->{login_time}\n");
        #   Expiration time
        print($outfile "$self->{expiry_time}\n");
    }

    sub load {
        my $self = shift;
        my ($infile) = @_;

        my $s = in($infile);

        if ($s != FILE_VERSION) {
            die("cookie::load: Incompatible file version $s");
        }

        $self->{login_name} = in($infile);
        $self->{cookie_id} = in($infile);
        $self->{login_time} = in($infile);
        $self->{expiry_time} = in($infile);
    }

    
    sub in {
        my ($fh, $default) = @_;
        my $s;
        if ($s = <$fh>) {
            $s =~ s/\s+$//;
        } else {
            if (defined($default)) {
                $s = $default;
            } else {
                die("cookie::in: Unexpected end of file");
            }
        }
        return $s;
    }


    sub signCookie {
        my $self = shift;

        my $crc = new HDiet::Digest::Crc32();
        my $cookSig = sprintf("%08x", $crc->strcrc32("Sodium Chloride" .
            $self->{cookie_id}));
        $cookSig =~ tr/a-f/FGJKQW/;

        return substr($self->{cookie_id}, 0, 23) . $cookSig . substr($self->{cookie_id}, 23);
    }

    sub generateCookie {
        my $self = shift;
        my ($name) = @_;

        return "$name=" . $self->signCookie() . "; " .
               "Domain=.fourmilab.ch; " .
               "Path=/cgi-bin/HackDiet; " .
               "Expires=" .
                jd_to_old_cookie_date(unix_time_to_jd($self->{expiry_time}));
    }

    sub expireCookie {
        my $self = shift;
        my ($name) = @_;

        return "$name=EXPIRED; " .
               "Domain=.fourmilab.ch; " .
               "Path=/cgi-bin/HackDiet; " .
               "Expires=" .
                jd_to_old_cookie_date(gregorian_to_jd(1990, 1, 1));
    }

    sub storeCookie {
        my ($ui) = @_;

        my $cook = HDiet::cookie->new($ui->{login_name}, time());
         open(CO, ">:utf8", "/server/pub/hackdiet/RememberMe/$cook->{cookie_id}.hdr") ||
            die("Cannot create persistent login file /server/pub/hackdiet/RememberMe/$cook->{cookie_id}.hdr");
        $cook->save(\*CO);
        close(CO);
        clusterCopy("/server/pub/hackdiet/RememberMe/$cook->{cookie_id}.hdr");

        return $cook->generateCookie('HDiet');
    }

    sub testCookiePresent {
        my ($name) = @_;

        my $cuser;

        if (defined($ENV{HTTP_COOKIE}) &&
            ($ENV{HTTP_COOKIE} =~ m/$name=([0-9FGJKQW]{48})/)) {
            my $csig = $1;
            my $cid = checkCookieSignature($csig);
            if (defined($cid)) {
                if (-f "/server/pub/hackdiet/RememberMe/$cid.hdr") {
                    if (open(CI, "<:utf8", "/server/pub/hackdiet/RememberMe/$cid.hdr")) {
                        my $cook = HDiet::cookie->new();
                        $cook->load(\*CI);
                        close(CI);
                        if (($cook->{cookie_id} eq $cid) &&
                            ($cook->{expiry_time} >= time())) {
                            $cuser = $cook->{login_name};
                        }
                    }
                    unlink("/server/pub/hackdiet/RememberMe/$cid.hdr");
                    clusterDelete("/server/pub/hackdiet/RememberMe/$cid.hdr");
                }
            }
        }
        return $cuser;
    }

    sub checkCookieSignature {
        my ($signedCookie) = @_;

        if ($signedCookie !~ m/^[0-9FGJKQW]{48}$/) {
#print("Cookie syntax bad signedCookie ($signedCookie)\n");
            return undef;
        }

        my $crc = new HDiet::Digest::Crc32();

        my $cookieSig = substr($signedCookie, 23, 8, "");
        $cookieSig =~ tr/FGJKQW/a-f/;
        my $cookSig = sprintf("%08x", $crc->strcrc32("Sodium Chloride" .
            $signedCookie));
#print("cookSig ($cookSig)  cookieSig ($cookieSig)  signedCookie ($signedCookie)\n");
        if ($cookSig eq $cookieSig) {
            return $signedCookie;
        }
        return undef;
    }

    sub generateCookieID {
        my ($login) = @_;

        $login = encode_utf8($login);
        for (my $i = 0; $i < 16; $i++) {
            $login .= chr(int(rand(256)));
        }
        my $si = sha1_hex($login);
        $si =~ tr/a-f/FGJKQW/;
        return $si;
    }
