#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    package HDiet::Julian;

    require Exporter;

    our @ISA = qw(Exporter);
    our @EXPORT = qw(gregorian_to_jd jd_to_gregorian jd_to_weekday
        civil_time_to_jd jd_to_civil_time
        unix_time_to_jd jd_to_unix_time unix_time_to_civil_date_time
        jd_to_RFC_822_date jd_to_RFC_3339_date jd_to_old_cookie_date);
    our @EXPORT_OK = qw(leap_gregorian GREGORIAN_EPOCH WEEKDAY_NAMES
        MONTH_ABBREVIATIONS);
    1;

    
    use constant GREGORIAN_EPOCH => 1721425.5;
    use constant WEEKDAY_NAMES => [ "Sunday", "Monday", "Tuesday", "Wednesday",
                                    "Thursday", "Friday", "Saturday" ];
    use constant MONTH_ABBREVIATIONS => [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ];

    use constant J1970 => 2440587.5;    # Julian date at Unix epoch: 1970-01-01

    
    #   MOD  --  Modulus function which works for non-integers.

    sub mod {
        my ($a, $b) = @_;

        return $a - ($b * floor($a / $b));
    }

    #   FLOOR  -- Round number to the nearest integer less than
    #             the argument.  Note that, unlike int(), floor(-1.5) = -2.

    sub floor {
        my $x  = shift;
        my $ix = int($x);
        return (($x >= 0) || ($x == $ix)) ? $ix : ($ix - 1);
    }


    
    sub leap_gregorian {
        my $year = shift;

        return (($year % 4) == 0) &&
                (!((($year % 100) == 0) && (($year % 400) != 0)));
    }

    
    sub gregorian_to_jd {
        my ($year, $month, $day) = @_;

        return (GREGORIAN_EPOCH - 1) +
               (365 * ($year - 1)) +
               floor(($year - 1) / 4.0) +
               (-floor(($year - 1) / 100.0)) +
               floor(($year - 1) / 400.0) +
               floor((((367 * $month) - 362) / 12) +
               (($month <= 2) ? 0 :
                                   (leap_gregorian($year) ? -1 : -2)
               ) +
               $day);
    }


    
    sub jd_to_gregorian {
        my $jd = shift;

        my ($wjd, $depoch, $quadricent, $dqc, $cent, $dcent, $quad, $dquad,
            $yindex, $yearday, $leapadj, $year, $month, $day);

        $wjd = floor($jd - 0.5) + 0.5;
        $depoch = $wjd - GREGORIAN_EPOCH;
        $quadricent = floor($depoch / 146097);
        $dqc = mod($depoch, 146097);
        $cent = floor($dqc / 36524);
        $dcent = mod($dqc, 36524);
        $quad = floor($dcent / 1461);
        $dquad = mod($dcent, 1461);
        $yindex = floor($dquad / 365);
        $year = ($quadricent * 400) + ($cent * 100) + ($quad * 4) + $yindex;
        if (!(($cent == 4) || ($yindex == 4))) {
            $year++;
        }
        $yearday = $wjd - gregorian_to_jd($year, 1, 1);
        $leapadj = (($wjd < gregorian_to_jd($year, 3, 1)) ? 0
                                                      :
                      (leap_gregorian($year) ? 1 : 2)
                  );
        $month = int(((($yearday + $leapadj) * 12) + 373) / 367);
        $day = ($wjd - gregorian_to_jd($year, $month, 1)) + 1;

        return ($year, $month, $day);
    }

    
    sub jd_to_weekday {
        my $j = shift;
        my $ij = int($j + 1.5);

        $ij %= 7;

        return ($ij < 0) ? (7 + $ij) : $ij;
    }


    
    sub civil_time_to_jd {
        my ($hour, $min, $sec) = @_;

        my $s = $sec + (60 * ($min + (60 * $hour)));
        return ($s / (24 * 60 * 60));
    }

    
    sub jd_to_civil_time {
        my $j = shift;
        my ($ij, $hh, $mm, $ss);

        $j += 0.5;                    # Astronomical to civil
        $ij = int(($j - floor($j)) * 86400.5);
        $hh = int($ij / 3600);
        $mm = int(($ij / 60) % 60);
        $ss = int(($ij % 60) + 0.5);
        return ($hh, $mm, $ss);
    }


    
    sub unix_time_to_jd {
        my $ut = shift;

        return J1970 + ($ut / (24 * 60 * 60));
    }

    
    sub jd_to_unix_time {
        my $j = shift;

        return int((($j - J1970) * (24 * 60 * 60)) + 0.5);
    }

    
    sub unix_time_to_civil_date_time {
        my $j = unix_time_to_jd(shift);

        my @dt = jd_to_gregorian($j);
        push(@dt, jd_to_civil_time($j));
        return @dt;
    }


    
    sub jd_to_RFC_822_date {
        my $j = shift;

        my ($uy, $um, $ud) = jd_to_gregorian($j);
        my ($uhh, $umm, $uss) = jd_to_civil_time($j);

       return sprintf("%02d/%s/%04d:%02d:%02d:%02d +0000",
            $ud, MONTH_ABBREVIATIONS->[$um], $uy, $uhh, $umm, $uss);
    }

    
    sub jd_to_RFC_3339_date {
        my $j = shift;

        my ($uy, $um, $ud) = jd_to_gregorian($j);
        my ($uhh, $umm, $uss) = jd_to_civil_time($j);

        return sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ",
            $uy, $um, $ud, $uhh, $umm, $uss);
    }

    
    sub jd_to_old_cookie_date {
        my $j = shift;

        my ($uy, $um, $ud) = jd_to_gregorian($j);
        my ($uhh, $umm, $uss) = jd_to_civil_time($j);
        my $wdn = substr(WEEKDAY_NAMES->[jd_to_weekday($j)], 0, 3);
        my $mabb = MONTH_ABBREVIATIONS->[$um - 1];

        return sprintf("$wdn, %02d-$mabb-%04d %02d:%02d:%02d GMT",
            $ud, $uy, $uhh, $umm, $uss);
    }


