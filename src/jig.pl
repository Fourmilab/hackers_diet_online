#! /usr/bin/perl

    
    
    require 5;
    use strict;
    use warnings;
    use utf8;


    use Time::Local;
    use Encode qw(decode_utf8);
    use GD;
    use Digest::SHA1  qw(sha1_hex);
    use XML::LibXML;
    use XML::LibXML::Common qw(:w3c);       # XML/DOM node type mnemonics
    use HDiet::Julian qw(MONTH_ABBREVIATIONS :DEFAULT);
    use Socket qw(inet_aton);
    use Sys::Syslog;


    use lib "/server/bin/httpd/cgi-bin/HDiet/Cgi";
    use CGI;

    use HDiet::Aggregator;
    use HDiet::Cluster;
    use HDiet::monthlog;
    use HDiet::user;
    use HDiet::history;
    use HDiet::pubname;
    use HDiet::session;
    use HDiet::cookie;
    use HDiet::hdCSV;
    use HDiet::html;
    use HDiet::xml;

    use HDiet::Util::IDNA::Punycode;
    use HDiet::Text::CSV;

    



    
    #   Processing arguments and options

    my $verbose = 0;            # Verbose output for debugging

    my $testmode = 0;           # Test mode: don't update real database

    #   Handy constants

    my %mnames = split(/,/, "Jan,1,Feb,2,Mar,3,Apr,4,May,5,Jun,6,Jul,7,Aug,8,Sep,9,Oct,10,Nov,11,Dec,12");

    our @monthNames = (   "Zeroary",
                           "January", "February", "March",
                           "April", "May", "June",
                           "July", "August", "September",
                           "October", "November", "December"
                     );

    my @chartSizes = ( '320x240', '480x360', '512x384', '640x480', '800x600', '1024x768', '1200x900', '1600x1200' );

    my @feedback_categories = ( 
    '(Not specified)',
    'Problem report',
    'Recommendation for change',
    'Suggestion for new feature',
    'How do I...?',
    'Documentation or usage question',
    'General comment'
 );





    binmode(STDOUT, ":utf8");
    binmode(STDIN, ":utf8");

use Data::Dumper;


    my $user_file_name = quoteUserName('John Walker');
    if (!(-f "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu")
        || (!open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu"))) {
        die("Cannot open /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    }

    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

#    $ui->describe();

    my $uec = $ui->generateEncryptedUserID();
    my $duec = decodeEncryptedUserID($uec);
#    print(Dumper($uec, $duec));
    print("Encoded ID: ($uec)\n");
    print("User ID: ($duec)\n");

    my $hist = HDiet::history->new($ui, $user_file_name);
    open(BF, ">/tmp/steenk.png") || die("Cannot create /tmp/steenk.png");
    $hist->drawBadgeImage(\*BF, 14);
    close(BF);

    exit(0);

    
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


    
    
    sub propagate_trend {
        my ($user, $first, $canon) = @_;

        $first = '0000-00' if !defined($first) || ($first eq '');
        $canon = 0 if !defined($canon);

        my @logs = $user->enumerateMonths();
        my $user_file_name = quoteUserName($user->{login_name});
        
    my $ifirst;

    for ($ifirst = 0; $ifirst <= $#logs; $ifirst++) {
        if ($logs[$ifirst] ge $first) {
            last;
        }
    }

        
    my $mlog = HDiet::monthlog->new();

    my $i = $ifirst;
    open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb") ||
        die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb");
    $mlog->load(\*FL);
    close(FL);

    if ($canon) {
        
    if ($canon) {
        my $ncanon = 0;

        for (my $j = 1; $j <= $mlog->monthdays(); $j++) {
            if (defined($mlog->{weight}[$j]) && ($mlog->{weight}[$j] ne '')) {
                my $cw = canonicalWeight($mlog->{weight}[$j]);
                if ($cw ne $mlog->{weight}[$j]) {
#print("Log: $logs[$i]  Day $j:  $mlog->{weight}[$j] ==> $cw<br>\n");
                    $mlog->{weight}[$j] = $cw;
                    $ncanon++;
                }
            }
        }

        if ($ncanon > 0) {
#print("Log: $logs[$i]  $ncanon weight entries canonicalised.<br>\n");
        }
    }

        
    $mlog->{last_modification_time} = time();
    open(FL, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb") ||
        die("Cannot create monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb");
    $mlog->save(\*FL);
    close(FL);
    clusterCopy("/server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb");

    }

    my $ltrend = $mlog->{trend}[$mlog->monthdays()];
    my $lunit = $mlog->{log_unit};
    undef($mlog);

#print("First log: $logs[$ifirst]  Trend = $ltrend<br>\n");


        for ($i = $ifirst + 1; $i <= $#logs; $i++) {
            
    $mlog = HDiet::monthlog->new();

    open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb") ||
        die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb");
    $mlog->load(\*FL);
    close(FL);

    
    if ($lunit != $mlog->{log_unit}) {
        $ltrend *= WEIGHT_CONVERSION->[$lunit][$mlog->{log_unit}];
#print("Log: $logs[$i]  Converted trend unit from $lunit to $mlog->{log_unit}<br>\n");
        $lunit = $mlog->{log_unit};
    }


    $ltrend = 0 if !defined($ltrend);
    $ltrend = sprintf("%.4f", $ltrend);
    $ltrend =~ s/(\.[^0]*)0+$/$1/;
    $ltrend =~ s/\.$//;

    
    if ($canon) {
        my $ncanon = 0;

        for (my $j = 1; $j <= $mlog->monthdays(); $j++) {
            if (defined($mlog->{weight}[$j]) && ($mlog->{weight}[$j] ne '')) {
                my $cw = canonicalWeight($mlog->{weight}[$j]);
                if ($cw ne $mlog->{weight}[$j]) {
#print("Log: $logs[$i]  Day $j:  $mlog->{weight}[$j] ==> $cw<br>\n");
                    $mlog->{weight}[$j] = $cw;
                    $ncanon++;
                }
            }
        }

        if ($ncanon > 0) {
#print("Log: $logs[$i]  $ncanon weight entries canonicalised.<br>\n");
        }
    }


#print("Log: $logs[$i]  Trend = $ltrend, was $mlog->{trend_carry_forward}<br>\n");
    $mlog->{trend_carry_forward} = $ltrend;
    $mlog->computeTrend();

    
    $mlog->{last_modification_time} = time();
    open(FL, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb") ||
        die("Cannot create monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb");
    $mlog->save(\*FL);
    close(FL);
    clusterCopy("/server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb");


    $ltrend = $mlog->{trend}[$mlog->monthdays()];
    undef($mlog);

        }

        if ($user->{badge_trend} != 0) {
            open(FB, ">/server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png") ||
                die("Cannot update monthly log file /server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png");
            my $hist = HDiet::history->new($user, $user_file_name);
            $hist->drawBadgeImage(\*FB, $user->{badge_trend});
            close(FB);
            do_command("mv /server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png /server/pub/hackdiet/Users/$user_file_name/BadgeImage.png");
            clusterCopy("/server/pub/hackdiet/Users/$user_file_name/BadgeImage.png");
        }
   }

    
    sub append_history {
        my ($user_file, $type, $extra) = @_;

        $extra = '' if !defined($extra);
        if ($extra ne '') {
            $extra = ',' . $extra;
        }
        open(FH, ">>:utf8", "/server/pub/hackdiet/Users/$user_file/History.hdh") ||
           die("Cannot append to history file /server/pub/hackdiet/Users/$user_file/History.hdh");
        print(FH "$type," . time() . ",$ENV{REMOTE_ADDR}$extra\n");
        close(FH);
        clusterCopy("/server/pub/hackdiet/Users/$user_file/History.hdh");
    }

    
    sub update_last_transaction {
        my ($user_file) = @_;

        #   Update the date and time of the last transaction by this user
        my $now = time();
        open(FL, ">:utf8", "/server/pub/hackdiet/Users/$user_file/LastTransaction.hdl") ||
            die("Cannot update last transaction file /server/pub/hackdiet/Users/$user_file/LastTransaction.hdl");
        print FL <<"EOD";
1
$now
EOD
        close(FL);
        clusterCopy("/server/pub/hackdiet/Users/$user_file/LastTransaction.hdl");
   }

    
    sub last_transaction_time {
        my ($user_file) = @_;

        if (open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file/LastTransaction.hdl")) {
            my $lt = 0;
            my $s = in(\*FL);
            if ($s == 1) {          # Only proceed if version correct
                $s = in(\*FL);
                if ($s =~ m/^\d+$/) {
                    $lt = $s;
                }
            }
            close(FL);
            return $lt;
        } else {
            return 0;
        }
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
                die("main::in: Unexpected end of file");
            }
        }
        return $s;
    }


    
    sub is_user_session_open {
        my ($user_name) = @_;

        my $user_file_name = quoteUserName($user_name);
        if ((-f "/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda")
            && open(FS, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda")) {
            my $asn = load_active_session(\*FS);
            close(FS);
            if (-f "/server/pub/hackdiet/Sessions/$asn.hds") {
                return 1;
            } else {
                unlink("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
                clusterDelete("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
#print(STDERR "is_user_session_open abstergifying orphaned session /server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda\n");
            }
        }
        return 0;
   }


    
    sub parseWeight {
        my ($w, $unit) = @_;

        $w =~ s/,/./g;
        my $n;
        if ($unit == WEIGHT_STONE) {
            if ($w =~ m/^\s*(\d+)\s+(\d*\.?\d*)\s*$/) {
                $n = ($1 * 14) + $2;
            } elsif ($w =~ m/^\s*(\d*\.?\d*)\s*$/) {
                $n = $1 * 14;
            }
        } else {
            if ($w =~ m/^\s*(\d*\.?\d*)\s*$/) {
                $n = $1;
            }
        }
        return $n;
    }

    
    sub parseSignedWeight {
        my ($w, $unit) = @_;
        my $sgn = 1;

        if ($w =~ s/\s*([\+\-])//) {
            if ($1 eq '-') {
                $sgn = -1;
            }
        }
        my $v = parseWeight($w, $unit);
        if (defined($v)) {
            return $sgn * $v;
        }
        return undef;
    }


    
    sub wrapText {
        my ($t, $columns) = @_;

        my ($ip, $xp) = ('', '');
        my $break = '\s';
        my $separator = "\n";

        my $r = "";
        my $tail = $t;
        my $lead = $ip;
        my $ll = $columns - length($ip) - 1;
        my $nll = $columns - length($xp) - 1;
        my $nl = "";
        my $remainder = "";

        pos($t) = 0;
        while ($t !~ /\G\s*\Z/gc) {
            if ($t =~ /\G([^\n]{0,$ll})($break|\z)/xmgc) {
                $r .= $nl . $lead . $1;
                $remainder = $2;
            } elsif ($t =~ /\G([^\n]*?)($break|\z)/xmgc) {
                $r .= $nl . $lead . $1;
                $remainder = $2;
            }

            $lead = $xp;
            $ll = $nll;
            $nl = $separator;
        }
        $r .= $remainder;

        $r .= $lead . substr($t, pos($t), length($t)-pos($t))
                if pos($t) ne length($t);

        return $r;
    }



    
    sub print_command_line_help {
        print << "EOD";
Usage: HackDiet.pl [ options ]
       Options:
             --copyright     Print copyright information
             --help          Print this message
             --test          Test mode: do not actually block hosts
             --verbose       Print verbose debugging information
             --version       Print version number
Version 1.0, August 2007
EOD
   }

    
    #   Return least of arguments
    sub min {
        my $v = 1e308;

        my $a;
        while (defined($a = shift())) {
            $v = $a if $a < $v;
        }
        return $v;
    }

    #   Return greatest of arguments
    sub max {
        my $v = -1e308;

        my $a;
        while (defined($a = shift())) {
            $v = $a if $a > $v;
        }
        return $v;
    }

    #   Return sign of argument
    sub sgn {
        my $a = shift();

        return ($a == 0) ? 0 : (($a > 0) ? 1 : -1);
    }

    #   Round number to nearest integer
    sub round {
        return sprintf("%.0f", shift());
    }

    
    sub do_command {
        my ($cmd, $annotation) = @_;

        if ($verbose) {
            if (!defined($annotation)) {
                $annotation = '';
            } else {
                $annotation .= ": ";
            }
            print(STDERR "$annotation$cmd\n");
        }

        if (!$testmode) {
            system($cmd);
        }
    }

    
#    sub etime {
#        my ($sec, $min, $hour, $mday, $mon, $year) = localtime($_[0]);
#        return sprintf("%d-%02d-%02d %02d:%02d",
#            $year + 1900, $mon + 1, $mday, $hour, $min);
#    }

    
    sub toHex {
        my ($s) = @_;

        my $h = '';
        while ($s =~ s/^(.)//s) {
            $h .= sprintf("%02X ", ord($1));
        }
        $h =~ s/\s$//;
        return $h;
    }

    
    sub isCurrentMonth {
        my ($lyear, $lmonth) = @_;

        #   Julian day at the server
        my $server_jd = unix_time_to_jd(time());

        #   JD at start of specified month
        my $this_month_jd = gregorian_to_jd($lyear, $lmonth, 1);

        #   JD at start of next month
        my ($nyear, $nmonth) = ($lyear, $lmonth + 1);
        if ($lmonth >= 12) {
            $lyear++;
            $lmonth = 1;
        }
        my $next_month_jd = gregorian_to_jd($nyear, $nmonth, 1);

        return ($server_jd >= ($this_month_jd + 1)) &&
               ($server_jd <= ($next_month_jd - 1));
    }

    
    sub encodeDomainName {
        my ($idn) = @_;

        my $dn = '';
        my $w;

        foreach $w (split(/\./, $idn)) {
            $dn .= encode_punycode($w) . '.';
        }

        $dn =~ s/\.$//;
        return $dn;
    }

    
    sub validMailDomain {
        my ($dn) = @_;

        my $nmx = `dig +short $dn MX | egrep -v ' 127\.0\.0.' | wc -l`;
        $nmx =~ s/\s//g;

        if ($nmx == 0) {
            $nmx = `dig +short $dn A | egrep -v ' 127\.0\.0.' | wc -l`;
            $nmx =~ s/\s//g;
        }

        return $nmx > 0;
    }

    
    sub drawText {
        my ($img, $text, $font, $size, $angle, $x, $y, $alignh, $alignv, $colour) = @_;

        my $fontFile = "/server/bin/httpd/cgi-bin/HDiet/Fonts/$font.ttf";

        if (($alignh ne 'o') || ($alignv ne 'o')) {
            my @ext =  GD::Image->stringFT($colour, $fontFile, $size, $angle, $x, $y, $text);

            if ($alignh eq 'l') {
                $x -= ($ext[0] - $x);
            } elsif ($alignh eq 'c') {
                $x -= int(($ext[2] - $ext[0]) / 2);
            } elsif ($alignh eq 'r') {
                $x -= $ext[2] - $x;
            } else {
                die("drawText: invalid horizontal alignment '$alignh'") if $alignh ne 'o';
            }

            if ($alignv eq 'b') {
                $y -= ($ext[1] - $y);
            } elsif ($alignv eq 'c') {
                $y += int(($y - $ext[7]) / 2);
            } elsif ($alignv eq 't') {
                $y -= $ext[7] - $y;
            } else {
                die("drawText: invalid vertical alignment '$alignv'") if $alignv ne 'o';
            }
        }
        $img->stringFT($colour, $fontFile, $size, $angle, $x, $y, $text);
    }


    
    sub parse_cgi_arguments {
        my $data;
#   NOTE: On Perl 5.8.5 we needed to read the CGI POST arguments
#   in UTF-8 mode.  On Perl 5.8.8 the decode_utf8() function
#   appears to double-decode POST (but not GET arguments) unless
#   we read the POST arguments in :raw mode.  I am not sure
#   I understand this (and there is much conflicting information
#   on this topic on the Web), but simply always reading STDIN
#   in :raw appears to work, at least at the moment.
#        if ($ENV{QUERY_STRING} =~ m/enc=raw/) {
#            binmode(STDIN, ":raw");
#        }
        binmode(STDIN, ":raw");

        my $query = new CGI;
#print("Content-type: text/plain\r\n\r\nQuery:\n");
#use Data::Dumper;
#print(Dumper($query));

        my %CGIfields = $query->Vars();
        my $uploaded = 0;
        if ($CGIfields{uploaded_file}) {
#print(STDERR "Uploading file...\n");
            my $uploaded_content = '';

            my $uf = $query->upload('uploaded_file');
            while (<$uf>) {
                $uploaded_content .= $_;
            }
            close($uf);
            $CGIfields{file} = $uploaded_content;
            $uploaded = 1;
#print(STDERR "Uploaded file of " . length($CGIfields{file}) . " bytes.\n");
        }
#   DECODE CGI ARGUMENTS FROM UTF-8.  THIS MAY BREAK POST AND
#   NEEDS MORE RESEARCH.  SEE COMMENTS FOR 2007-03-21.
for my $k (keys %CGIfields) {
    if ($k eq 'file') {
        #   IF ARGUMENT IS FILE, DO NOT DECODE FROM UTF-8.  THIS NEEDS
        #   TO BE THOUGHT OUT.  WE MAY TRY DECODING AND USE THE DECODE
        #   IF IT WORKS.
#print(STDERR "Uploaded " . length($CGIfields{file}) . "\n");
    } else {
        $CGIfields{$k} = decode_utf8($CGIfields{$k});
    }
#print(STDERR "Argument $k " . length($CGIfields{$k}) . " bytes.\n");
}
        return %CGIfields;
    }

    
    sub ndz {
        return defined($_[0]) ? $_[0] : 0;
    }

    sub ndb {
        return defined($_[0]) ? $_[0] : '';
    }



