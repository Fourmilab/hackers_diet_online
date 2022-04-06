#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    use HDiet::monthlog qw(:units);
    use HDiet::trendfit;

    package HDiet::history;

    use HDiet::Julian qw(WEEKDAY_NAMES :DEFAULT);
    use HDiet::Cluster;
    use GD;

    require Exporter;

    use constant MIN_VALUE => -1E100;
    use constant MAX_VALUE => 1E100;

    
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


    our @ISA = qw(Exporter);
    our @EXPORT = ( );

    my ($width, $height, $leftMargin, $rightMargin, $topMargin, $bottomMargin,
        $xAxisLength);
    my ($start_jd, $end_jd);
    my ($wgt_min, $wgt_max);
    my ($img);
    my %logs;                   # Monthly log cache
    my @years;                 # List of years in the user database

    my $fitter;
    my $lastFitDay;
    my ($nDays, $tFlags);

    1;

    sub new {
        my $self = {};
        my ($invocant, $user, $user_file_name) = @_;
        my $class = ref($invocant) || $invocant;

        bless($self, $class);

        #   Initialise instance variables from constructor arguments
        $self->{user} = $user;
        $self->{user_file_name} = $user_file_name;

        return $self;
    }

    sub getDays {
        my ($jdstart, $ndays, $ui) = @_;

        my ($wsum, $tsum, $rsum, $flgc, $wtd, $rd) = (0, 0, 0, 0, 0, 0);

        for (my $i = 0; $i < $ndays; $i++) {
            my ($yy, $mm, $dd) = jd_to_gregorian($jdstart);
            my $m = $logs{sprintf("%04d-%02d", $yy, $mm)};

            if ($m) {
                if ($m->{weight}[$dd]) {
                    $wsum += $m->{weight}[$dd] * HDiet::monthlog::WEIGHT_CONVERSION->[$m->{log_unit}][$ui->{display_unit}];
                    my $dtrend = $m->{trend}[$dd] * HDiet::monthlog::WEIGHT_CONVERSION->[$m->{log_unit}][$ui->{display_unit}];
                    $tsum += $dtrend;
                    $wtd++;
                }

                if ($m->{trend}[$dd]) {
                    if ($jdstart > $lastFitDay) {
                        $fitter->addPoint($m->{trend}[$dd] *
                            HDiet::monthlog::WEIGHT_CONVERSION->[$m->{log_unit}][$ui->{display_unit}]);
                    }
                }

                if ($m->{rung}[$dd]) {
                    $rsum += $m->{rung}[$dd];
                    $rd++;
                }

                if ($m->{flag}[$dd]) {
                    $flgc++;
                }
                if ($jdstart > $lastFitDay) {
                    $nDays++;
                    $tFlags++ if $m->{flag}[$dd];
                    $lastFitDay = $jdstart;
                }
            }
            $jdstart++;
        }

        if ($wtd > 0) {
            $wsum /= $wtd;
            $tsum /= $wtd;
        } else {
            $wsum = undef;
            $tsum = undef;
        }
        if ($rd > 0) {
            $rsum /= $rd;
        } else {
            $rsum = undef;
        }

        return ($wsum, $tsum, $rsum, $flgc);
    }

    sub analyseTrend {
        my $self = shift;

        my (@intervals) = @_;

        my ($ui, $user_file_name) = ($self->{user}, $self->{user_file_name});

        my ($start_date, $end_date) = ('9999-99-99', '0000-00-00');

        
    my @interval;
    for (my $i = 0; $i <= $#intervals; $i += 2) {
        die("history::analyseTrend: Interval[$i] ($intervals[$i] - $intervals[$i + 1]) out of order")
            if $intervals[$i] gt $intervals[$i + 1];
        $start_date = $intervals[$i] if $intervals[$i]  lt $start_date;
        $end_date = $intervals[$i + 1] if $intervals[$i + 1] gt $end_date;
        $intervals[$i] =~ m/^(\d+)(?:\-(\d+))?(?:\-(\d+))?$/ ||
            die("history::analyseTrend: invalid intervals[$i] start date intervals[$i]");
        my $int_start_jd = gregorian_to_jd($1, $2, $3);

        $intervals[$i + 1] =~ m/^(\d+)(?:\-(\d+))?(?:\-(\d+))?$/ ||
            die("history::drawChart: history::analyseTrend: invalid intervals[$i + 1] start date intervals[$i + 1]");
        my $int_end_jd = gregorian_to_jd($1, $2, $3);
        push(@interval, [$int_start_jd, $int_end_jd]);
    }


        
    $start_date =~ m/^(\d+)(?:\-(\d+))?(?:\-(\d+))?$/ || die("history::drawChart: invalid start date $start_date");
    my ($start_y, $start_m, $start_d) = ($1, $2, $3);
    $start_m = 1 if !defined($start_m);
    $start_d = 1 if !defined($start_d);
    $start_jd = gregorian_to_jd($start_y, $start_m, $start_d);

    $end_date =~ m/^(\d+)(?:\-(\d+))?(?:\-(\d+))?$/ || die("history::drawChart: invalid end date $end_date");
    my ($end_y, $end_m, $end_d) = ($1, $2, $3);
    $end_m = 12 if !defined($end_m);
    if (!defined($end_d)) {
        $end_jd = gregorian_to_jd($end_y, $end_m + 1, 1) - 1;
        $end_d  = (jd_to_gregorian($end_jd))[2];
    }
    $end_jd = gregorian_to_jd($end_y, $end_m, $end_d);

    my $dayspan = (($end_jd + 1) - $start_jd);

#print("Inclusive interval: $start_date - $end_date  $start_jd - $end_jd  $dayspan days\n");

        
    my ($cur_y, $cur_m) = ($start_y, $start_m);

    for (my $monkey = sprintf("%04d-%02d", $start_y, $start_m); $monkey le sprintf("%04d-%02d", $end_y, $end_m); $monkey = sprintf("%04d-%02d", $cur_y, $cur_m)) {
        if (!$logs{$monkey}) {
            if (-f "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") {
                open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") ||
                    die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$monkey.hdb");
                my $mlog = HDiet::monthlog->new();
                $logs{$monkey} = $mlog;
                $mlog->load(\*FL);
                close(FL);
            }
        }
        ($cur_y, $cur_m) = HDiet::monthlog::nextMonth($cur_y, $cur_m);
    }


#use Data::Dumper;
#print(Dumper(\@interval));

        #   Instantiate a fitter for each interval we're watching
        my @fitter;
        for (my $i = 0; $i <= $#interval; $i++) {
            $fitter[$i] = HDiet::trendfit->new();
        }

        $fitter = HDiet::trendfit->new();
        $lastFitDay = 0;
        ($nDays, $tFlags) = (0, 0);

        
    my $lastTrend = 0;

    for (my $cdate = $start_jd; $cdate <= $end_jd; $cdate++) {
        my ($weight, $trend) = getDays($cdate, 1, $ui);
        $trend = $lastTrend if (!$trend) && $lastTrend;
        if ($trend) {
            for (my $i = 0; $i <= $#interval; $i++) {
                if (($cdate >= $interval[$i][0]) && ($cdate <= $interval[$i][1])) {
                    $fitter[$i]->addPoint($trend);
                }
            }
            $lastTrend = $trend;
        }
    }


#print(Dumper(\@fitter));

        my @slopes;
        for (my $i = 0; $i <= $#fitter; $i++) {
            push(@slopes, $fitter[$i]->fitSlope());
            push(@slopes, $fitter[$i]->minMaxMean());
        }

#print(Dumper(\@slopes));

        return @slopes;
    }

    sub drawChart {
        my $self = shift;

        my ($outfile, $start_date, $end_date, $ww, $hh, $dietcalc,
            $printFriendly, $monochrome) = @_;

        my ($ui, $user_file_name) = ($self->{user}, $self->{user_file_name});

        ($width, $height) = ($ww, $hh);

        if (!(defined $outfile)) {
            $outfile = \*STDOUT;
        }

        $fitter = HDiet::trendfit->new();
        $lastFitDay = 0;
        ($nDays, $tFlags) = (0, 0);

        
    $start_date =~ m/^(\d+)(?:\-(\d+))?(?:\-(\d+))?$/ || die("history::drawChart: invalid start date $start_date");
    my ($start_y, $start_m, $start_d) = ($1, $2, $3);
    $start_m = 1 if !defined($start_m);
    $start_d = 1 if !defined($start_d);
    $start_jd = gregorian_to_jd($start_y, $start_m, $start_d);

    $end_date =~ m/^(\d+)(?:\-(\d+))?(?:\-(\d+))?$/ || die("history::drawChart: invalid end date $end_date");
    my ($end_y, $end_m, $end_d) = ($1, $2, $3);
    $end_m = 12 if !defined($end_m);
    if (!defined($end_d)) {
        $end_jd = gregorian_to_jd($end_y, $end_m + 1, 1) - 1;
        $end_d  = (jd_to_gregorian($end_jd))[2];
    }
    $end_jd = gregorian_to_jd($end_y, $end_m, $end_d);

    my $dayspan = (($end_jd + 1) - $start_jd);

        
    my ($cur_y, $cur_m) = ($start_y, $start_m);
    my ($first_day, $last_day) = ($start_d, 31);
    my ($weight_min, $weight_max, $trend_min, $trend_max, $rung_min, $rung_max) =
            (MAX_VALUE, MIN_VALUE, MAX_VALUE, MIN_VALUE, MAX_VALUE, MIN_VALUE);
    my ($trend_mean, $trend_last, $trend_ndays) = (0, 0, 0);

    for (my $monkey = sprintf("%04d-%02d", $start_y, $start_m);
         $monkey le sprintf("%04d-%02d", $end_y, $end_m);
         $monkey = sprintf("%04d-%02d", $cur_y, $cur_m)) {
        if (-f "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") {
            open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") ||
                die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$monkey.hdb");
            my $mlog = HDiet::monthlog->new();
            $logs{$monkey} = $mlog;
            $mlog->load(\*FL);
            close(FL);

            if (($cur_y == $end_y) && ($cur_m == $end_m)) {
                $last_day = $end_d;
            }

            my $logToDisplayUnit = HDiet::monthlog::WEIGHT_CONVERSION->[$mlog->{log_unit}][$ui->{display_unit}];
            for (my $i = $first_day; $i <= min($mlog->monthdays(), $last_day); $i++) {
                if (defined($mlog->{weight}[$i])) {
                    $weight_min = min($mlog->{weight}[$i] * $logToDisplayUnit, $weight_min);
                    $weight_max = max($mlog->{weight}[$i] * $logToDisplayUnit, $weight_max);
                }
                if (defined($mlog->{trend}[$i])) {
                    $trend_min = min($mlog->{trend}[$i] * $logToDisplayUnit, $trend_min);
                    $trend_max = max($mlog->{trend}[$i] * $logToDisplayUnit, $trend_max);
                    $trend_last = $mlog->{trend}[$i] *
                        HDiet::monthlog::WEIGHT_CONVERSION->[$mlog->{log_unit}][HDiet::monthlog::WEIGHT_KILOGRAM];
                    $trend_mean += $trend_last;
                    $trend_ndays++;
                }
                if (defined($mlog->{rung}[$i])) {
                    $rung_min = min($mlog->{rung}[$i] * $logToDisplayUnit, $rung_min);
                    $rung_max = max($mlog->{rung}[$i] * $logToDisplayUnit, $rung_max);
                }
            }

            if ($mlog->{trend_carry_forward} > 0) {
                $trend_min = min($trend_min, $mlog->{trend_carry_forward} * $logToDisplayUnit);
                $trend_max = max($trend_max, $mlog->{trend_carry_forward} * $logToDisplayUnit);
             }
        }

        ($cur_y, $cur_m) = HDiet::monthlog::nextMonth($cur_y, $cur_m);
        $first_day = 1;
    }

    ($wgt_min, $wgt_max) = (min($weight_min, $trend_min), max($weight_max, $trend_max));

        
    my ($pjdstart, $pjdend) = (max($start_jd, $$dietcalc[0]), min($end_jd, $$dietcalc[2]));
    my ($plan_start_day, $plan_start_weight,
        $plan_end_day, $plan_end_weight) = (-1) x 4;
    if (defined($$dietcalc[0])) {
        #   If plan starts before the end of the month, we shall plot it
        if ($pjdstart <= $end_jd) {
            if ($$dietcalc[2] <= $start_jd) {
                #   Plan ends before start of chart; plot flat line at end weight
                $plan_start_day = $start_jd;
                $plan_end_day = $end_jd;
                $plan_start_weight = $plan_end_weight = $$dietcalc[3];
            } else {
                $plan_start_day = $pjdstart;
                $plan_end_day = $pjdend;
                $plan_start_weight = $$dietcalc[1] + (($$dietcalc[3] - $$dietcalc[1]) *
                    (($pjdstart - $$dietcalc[0]) / ($$dietcalc[2] - $$dietcalc[0])));
                $plan_end_weight = $$dietcalc[1] + (($$dietcalc[3] - $$dietcalc[1]) *
                    (($pjdend - $$dietcalc[0]) / ($$dietcalc[2] - $$dietcalc[0])));
            }
        }
        $plan_start_weight *= HDiet::monthlog::WEIGHT_CONVERSION->[HDiet::monthlog::WEIGHT_KILOGRAM][$ui->{display_unit}];
        $plan_end_weight *= HDiet::monthlog::WEIGHT_CONVERSION->[HDiet::monthlog::WEIGHT_KILOGRAM][$ui->{display_unit}];
        if (min($plan_start_weight, $plan_end_weight) > 0) {
            $wgt_min = min($wgt_min, min($plan_start_weight, $plan_end_weight));
        }
        if (max($plan_start_weight, $plan_end_weight) > 0) {
            $wgt_max = max($wgt_max, max($plan_start_weight, $plan_end_weight));
        }
    }

        
    $width = 640 if !defined($width);
    $height = 480 if !defined($height);

    my ($fontLineHeight, $fontCharHeight) = (20, 10);
    my $fontCharWidth = 8;
    ($leftMargin, $rightMargin, $topMargin, $bottomMargin) =
        ($fontCharHeight * (($ui->{display_unit} == HDiet::monthlog::WEIGHT_STONE) ? 6 : 5),
        $fontCharHeight * 3, $fontCharHeight * 2, int($fontCharHeight * 6));
    my ($axisOffset, $tickSize, $sinkerSize) = (3, 5, 4);

    my ($topLeftX, $topLeftY) = (0, 0);
    my ($extentX, $extentY) = ($width, $height);

    my $pixelsPerDay = int(($extentX - ($leftMargin + $rightMargin)) / ($dayspan - 1));
    my $daysPerPixel = int(($dayspan - 1) / ($extentX - ($leftMargin + $rightMargin)));

    my ($bX, $bY) = ($topLeftX + $leftMargin, (($topLeftY + $extentY) - $bottomMargin));


        $img = new GD::Image($width, $height);
        
    #   First colour allocated is background
    my $white =  $img->colorAllocate(255, 255, 255);
    my $grey = ($printFriendly || $monochrome) ?
                    $white :
                    $img->colorAllocate(160, 160, 160);
    my $black =  $img->colorAllocate(  0,   0,   0);
    my $red =    $monochrome ? $black : $img->colorAllocate(255,   0,   0);
    my $green =  $monochrome ? $black : $img->colorAllocate(  0, 255,   0);
    my $yellow = $monochrome ? $black : ($printFriendly ?
        $img->colorAllocate(192, 192,   0) : $img->colorAllocate(255, 255,   0));
    my $blue =   $monochrome ? $black : $img->colorAllocate(  0,   0, 255);
    my $dkgrey = $img->colorAllocate(128, 128, 128);

        $img->interlaced('true');

        $xAxisLength = $width - ($leftMargin + $rightMargin);
        $img->filledRectangle($leftMargin + (-$axisOffset) + 1, $topMargin,
                              $leftMargin + $xAxisLength + $axisOffset,
                              $topMargin + $height - ($topMargin + $bottomMargin) + ($axisOffset - 1), $grey);

        
    #   Y axis
    PlotLine(-$axisOffset, -$axisOffset, -$axisOffset, $height - ($topMargin + $bottomMargin), $black);

    #   X axis
    PlotLine(-$axisOffset, -$axisOffset, $xAxisLength + $axisOffset, -$axisOffset, $black);
    
    my @ext;

    my $font = 'Times';
    my $fontFile = "/server/bin/httpd/cgi-bin/HDiet/Fonts/$font.ttf";
    @ext =  GD::Image->stringFT($black, $fontFile, 12, 0, 20, 20, "Mar ");
    my $cw = $ext[2] - $ext[0];
    @ext =  GD::Image->stringFT($black, $fontFile, 12, 0, 20, 20, "M ");
    my $scw = $ext[2] - $ext[0];

    my $single = 0;
    my $flblinc = ((int(($end_jd - $start_jd) / 30) * $cw) + ($xAxisLength - 1)) / $xAxisLength;
    my $lblinc = int($flblinc);
    $lblinc = 1 if $lblinc < 1;
    if ($lblinc > 1) {
        $lblinc = int(((int(($end_jd - $start_jd) / 30) * $scw) + ($xAxisLength - 1)) / $xAxisLength);
        $lblinc = 1 if $lblinc < 1;
        $single = 1;
    }

    my ($dt_y, $dt_m, $dt_d) = ($start_y, $start_m, $start_d);

    my $cjd = gregorian_to_jd($dt_y, $dt_m, $dt_d);

    if ($flblinc < 3) {
        
   while ($cjd <= $end_jd) {
        my $yearStart = $dt_m == 1;
        my $monster;

        if ($yearStart) {
            $monster = $single ? sprintf("%02d", $dt_y % 100) : $dt_y;
        } else {
            $monster = substr($::monthNames[$dt_m], 0, $single ? 1 : 3);
        }

        my $pix = $leftMargin + int(($xAxisLength * ($cjd - $start_jd)) / ($end_jd - $start_jd));
        ::drawText($img, $monster, 'Times', 12, 0,
            $pix, ($height - $bottomMargin) + 8, 'c', 't', $black);
        $img->line($pix, ($height - $bottomMargin) - $tickSize, $pix,
                         ($height - $bottomMargin) + $axisOffset, $black);

        if (($end_jd - $start_jd) < 32) {
            my ($nt_y, $nt_m) = ($dt_y, $dt_m + 1);
            if ($nt_m > 12) {
                $nt_m = 1;
                $nt_y++;
            }
            my $eom_jd = gregorian_to_jd($nt_y, $nt_m, 1);

            my $md = (int((($dt_d) - 1) / 7) * 7) + 7;
            for (my $d = gregorian_to_jd($dt_y, $dt_m, $md);
                 $d < ::min($end_jd, $eom_jd); $d += 7, $md+= 7) {
                $pix = $leftMargin + int(($xAxisLength * ($d - $start_jd)) / ($end_jd - $start_jd));
                ::drawText($img, $md, 'Times', 12, 0,
                    $pix, ($height - $bottomMargin) + 8, 'c', 't', $black);
                $img->line($pix, ($height - $bottomMargin) - $tickSize,
                           $pix, ($height - $bottomMargin) + $axisOffset, $black);
            }
        }

        $dt_m++;
        $dt_d = 1;
        if ($dt_m > 12) {
            $dt_y++;
            $dt_m = 1;
        }
        $cjd = gregorian_to_jd($dt_y, $dt_m, $dt_d);
    }

     } else {
        
    @ext =  GD::Image->stringFT($black, $fontFile, 12, 0, 20, 20, "2999 ");
    $cw = $ext[2] - $ext[0];
    $lblinc = int(((int(($end_jd - $start_jd) / 365) * $cw) + ($xAxisLength - 1)) / $xAxisLength);
    $lblinc = 1 if $lblinc < 1;

    $single = 0;
    if ($lblinc > 1) {
        @ext =  GD::Image->stringFT($black, $fontFile, 12, 0, 20, 20, "99 ");
        $cw = $ext[2] - $ext[0];
        $lblinc = int(((int(($end_jd - $start_jd) / 365) * $cw) + ($xAxisLength - 1)) / $xAxisLength);
        $lblinc = 1 if $lblinc < 1;
        $single = 1;
    }

    my $cjd = $start_jd;

    if (($start_m != 1) || ($start_d != 1)) {
        $dt_m = $dt_d = 1;
        $dt_y++;
        $cjd = gregorian_to_jd($dt_y, $dt_m, $dt_d);
    }

    while ($cjd < $end_jd) {
        my $label_x = $leftMargin + int(($xAxisLength * ($cjd - $start_jd)) / ($end_jd - $start_jd));
        ::drawText($img, $single ? sprintf("%02d", $dt_y % 100) : $dt_y, 'Times', 12, 0,
            $label_x, ($height - $bottomMargin) + $tickSize, 'c', 't', $black);
        $img->line($label_x, ($height - $bottomMargin) - $tickSize, $label_x, ($height - $bottomMargin) + $axisOffset, $black);
        $dt_y += $lblinc;
        ($dt_m, $dt_d) = (1, 1);
        $cjd = gregorian_to_jd($dt_y, $dt_m, $dt_d);
    }

    }



        
     if ($wgt_min == $wgt_max) {
            $wgt_min -= 10;
            $wgt_max += 10;
    }

    my $maxLabelRows = ($height - ($topMargin + $bottomMargin)) / $fontLineHeight;

    $wgt_max = int($wgt_max * 100);
    $wgt_min = int($wgt_min * 100);
    my $factor = 0;
    my $vunit = 1;
    my $power = 1;
    my @factors = (1, 2, 5);

    while ((($wgt_max - ($wgt_min - ($wgt_min % $vunit))) / ($factors[$factor] * $power)) > $maxLabelRows) {
        $factor++;
        if ($factor > 2) {
            $factor = 0;
            $power *= 10;
        }
        $vunit = $factors[$factor] * $power;
    }

    if ($vunit < 100) {
        $vunit = 100;
    }
    $vunit /= 100;

    $wgt_min -= $wgt_min % $vunit;
    $wgt_max = $wgt_max / 100;
    $wgt_min = $wgt_min / 100;


        
    if ($wgt_max > 0) {
        
    for (my $plotw = $wgt_min; $plotw <= $wgt_max; $plotw += $vunit) {

        my $ws = HDiet::monthlog::editWeight($plotw, $ui->{display_unit}, $ui->{decimal_character});
        my $wy = WeightToY($plotw);
        main::drawText($img, $ws, 'Times', 12, 0,
            $leftMargin - 8, ($height - $bottomMargin) - $wy, 'r', 'c', $black);
        PlotLine(-$axisOffset, $wy, $tickSize - $axisOffset, $wy, $black);
    }

        my $lrung = 0;
        my $nFlagged = 0;
        if ($pixelsPerDay > 1) {
            
    my ($pix, $opix);
    my ($lrg, $ltrend);
    my ($ow, $owy) = (0, 0);

    for (my $cdate = $start_jd; $cdate <= $end_jd; $cdate++) {
        my $pix = int(($xAxisLength * ($cdate - $start_jd)) / ($end_jd - $start_jd));
        my ($weight, $trend, $rung, $flags) = getDays($cdate, 1, $ui);
        $nFlagged += $flags;
        $weight = 0 if !defined($weight);
        $trend = 0 if !defined($trend);

        #   Plot weight
        if ($weight > 0) {
            if ($pixelsPerDay > int($sinkerSize * 1.5)) {
                
        my $ty = WeightToY($trend);
        my $wy = WeightToY($weight);
        my $offset = $wy - $ty;

        if (($offset < -$sinkerSize) || ($offset > $sinkerSize)) {
            my $dy = sgn($offset);

            PlotLine($pix, $ty + $dy, $pix, $wy + (($offset > 0) ? -$sinkerSize : $sinkerSize), $green);
        }

        #   Fill float/sinker with white or yellow, if it's flagged.

        for (my $j = -$sinkerSize; $j <= $sinkerSize; $j++) {
            my $dx = abs($j) - $sinkerSize;

            PlotLine($pix - $dx, ($wy + $j),
                     $pix + $dx, ($wy + $j),
                     $flags ? $yellow : $white);
        }

        #   Trace the outline of the float/sinker in blue

        PlotLine($pix - $sinkerSize, $wy,
                 $pix, $wy - $sinkerSize, $blue);
        PlotLine($pix, $wy - $sinkerSize,
                 $pix + $sinkerSize, $wy, $blue);
        PlotLine($pix + $sinkerSize, $wy,
                 $pix, $wy + $sinkerSize, $blue);
        PlotLine($pix, $wy + $sinkerSize,
                 $pix - $sinkerSize, $wy, $blue);

            } else {
                my $nwy = WeightToY($weight);
                if (($ow > 0) && ($weight > 0)) {
                    PlotLine($opix, $owy, $pix, $nwy, $dkgrey);
                }
                $ow = $weight;
                $owy = $nwy;
            }
        }

        #   Plot trend
        my $ny = WeightToY($trend);
        if ($ltrend) {
            if ($trend) {
                PlotLine($opix, $ltrend, $pix, $ny, $red);
            } else {
                PlotLine($opix, $ltrend, $pix, $ltrend, $red);
            }
        }
        $ltrend = $ny if $trend;


        if ($lrg) {
            my $rt = $lrg;
            $lrung = $lrg;
            if ($rung) {
                $rt = $rung;
            }
            PlotLine($opix, RungToY($lrg), $pix, RungToY($rt), $blue);
        }
        $lrg = $rung;

        $opix = $pix;
    }

        } else {
            
    my $w;
    my $ot = 0;
    my $t;
    my $rg;
    my $oty;
    my ($ow, $owy) = (0, 0);

    for (my $i = 0; $i < $xAxisLength; $i++) {
        my $sDate = $start_jd + ((($end_jd - $start_jd) * $i) / $xAxisLength);
        my $eDate = $start_jd + ((($end_jd - $start_jd) * ($i + 1)) / $xAxisLength);
        my $nd = int($eDate - $sDate);
        $nd = 1 if ($nd == 0);
        my ($weight, $trend, $rung, $flags) = getDays($sDate, $nd, $ui);
        $nFlagged += $flags;

#####   FIXME -- OPTION TO PLOT WEIGHT AS FLOAT/SINKER BAND ABOVE/BELOW TREND
        #   Plot weight
        $weight = 0 if !defined($weight);
        my $nwy = WeightToY($weight);
        if (($ow > 0) && ($weight > 0)) {
            PlotLine($i - 1, $owy, $i, $nwy, $dkgrey);
        }
        $ow = $weight;
        $owy = $nwy;

        #   Plot trend
        $trend = 0 if !defined($trend);
        my $nty = WeightToY($trend);
        if (($ot > 0) && ($trend > 0)) {
            PlotLine($i - 1, $oty, $i, $nty, $red);
        }
        $ot = $trend;
        $oty = $nty;


        if ($rung) {
            my $ry = RungToY($rung);
            if ($lrung) {
                PlotLine($i - 1, RungToY($lrung), $i, $ry, $blue);
            }
            $lrung = $rung;
        }
    }

        }

        
    if ($lrung) {
        #   Rung axis
        PlotLine($xAxisLength + $axisOffset, -$axisOffset, $xAxisLength + $axisOffset, $height - ($topMargin + $bottomMargin), $black);

        my $RUNG_EXCLUSION_ZONE = 6;    # How many rungs to exclude around last rung in monthly log
                                        # (Should really be calculated from font metrics and window
                                        #  geometry).

        my $ry = RungToY($lrung);
        main::drawText($img, $lrung, 'Times', 12, 0,
            ($width - $rightMargin) + 8, ($height - $bottomMargin) - $ry, 'o', 'c', $black);
        PlotLine($xAxisLength + $axisOffset, $ry, ($xAxisLength + $axisOffset) - $tickSize, $ry, $black);

       for (my $i = 1; $i <= 48; $i = (int($i / 6) * 6) + 6) {
            if (abs($lrung - $i) >= $RUNG_EXCLUSION_ZONE) {
                $ry = RungToY($i);
                main::drawText($img, $i, 'Times', 12, 0,
                    ($width - $rightMargin) + 8, ($height - $bottomMargin) - $ry, 'o', 'c', $black);
                PlotLine($xAxisLength + $axisOffset, $ry, ($xAxisLength + $axisOffset) - $tickSize, $ry, $black);
            }
        }
    }


        
    my (@intervals, @slopes);
    push(@intervals, sprintf("%04d-%02d-%02d", $start_y, $start_m, $start_d),
                      sprintf("%04d-%02d-%02d", $end_y, $end_m, $end_d));
    @slopes = $self->analyseTrend(@intervals);
    my $tslope = $slopes[0];
    my $fracf = $tFlags / $nDays;
    my $sweekly = $self->{user}->localiseDecimal(sprintf("%.2f", abs($tslope) * 7));
    my $caption;
    if ($width < 480) {
#print(STDERR "Narrow $width:  N = $fitter->{n}  Tslope = $tslope  Fracf = $fracf  Sweekly = $sweekly\n");
        $caption = (($tslope > 0) ? "Gain" : "Loss") .
                " $sweekly " .
                HDiet::monthlog::DELTA_WEIGHT_ABBREVIATIONS->[$ui->{display_unit}] .
                "/wk.  " .
                (($tslope > 0) ? "Excess" : "Deficit") .
                sprintf(": %.0f ", abs($tslope) *
                    (HDiet::monthlog::CALORIES_PER_WEIGHT_UNIT->[$ui->{display_unit}] /
                     HDiet::monthlog::CALORIES_PER_ENERGY_UNIT->[$ui->{energy_unit}])) .
                HDiet::monthlog::ENERGY_ABBREVIATIONS->[$ui->{energy_unit}] . "/day" .
                "." .
                (($fracf > 0) ? sprintf("  %.0f%% flag.", $fracf * 100) : '');
    } else {
#print(STDERR "Wide $width:  N = $fitter->{n}  Tslope = $tslope  Fracf = $fracf  Sweekly = $sweekly\n");
        $caption = 'Weekly ' .
                (($tslope > 0) ? "gain" : "loss") .
                " $sweekly " .
                HDiet::monthlog::DELTA_WEIGHT_UNITS->[$ui->{display_unit}] .
                "s.  Daily " .
                (($tslope > 0) ? "excess" : "deficit") .
                sprintf(": %.0f ", abs($tslope) *
                    (HDiet::monthlog::CALORIES_PER_WEIGHT_UNIT->[$ui->{display_unit}] /
                     HDiet::monthlog::CALORIES_PER_ENERGY_UNIT->[$ui->{energy_unit}])) .
                HDiet::monthlog::ENERGY_UNITS->[$ui->{energy_unit}] . "s" .
                "." .
                (($fracf > 0) ? sprintf("  %.0f%% flagged.", $fracf * 100) : '');
    }
    main::drawText($img, $caption, 'Times', 12, 0,
        int($width / 2), $height - 20, 'c', 'b', $black);
    if (($ui->{height} > 0) && ($trend_ndays > 0) && ($trend_last > 0)) {
        $trend_mean /= $trend_ndays;
        $caption = "Body mass index: mean " .
            $self->{user}->localiseDecimal(sprintf("%.1f", $trend_mean / ($ui->{height} / 100) ** 2)) .
            ", most recent " .
            $self->{user}->localiseDecimal(sprintf("%.1f", $trend_last / ($ui->{height} / 100) ** 2)) . ".";
        main::drawText($img, $caption, 'Times', 12, 0,
            int($width / 2), $height - 4, 'c', 'b', $black);
    }

        
    my $title = sprintf("%04d-%02d-%02d &#8211; %04d-%02d-%02d",
        $start_y, $start_m, $start_d, $end_y, $end_m, $end_d);
    main::drawText($img, $title, 'Times', 12, 0,
        int($width / 2), $topMargin - 4, 'c', 'b', $black);

    } else {
        $img->string(gdMediumBoldFont, $leftMargin + 40, $topMargin + int(($height - ($topMargin + $bottomMargin)) / 2),
            "There are no weight log entries in this date range.", $red);
    }


        
    if ($plan_start_day > 0) {
        my $sx = int(($xAxisLength * ($plan_start_day - $start_jd)) / ($end_jd - $start_jd));
        my $sy = WeightToY($plan_start_weight);
        my $ex = int(($xAxisLength * ($plan_end_day - $start_jd)) / ($end_jd - $start_jd));
        my $ey = WeightToY($plan_end_weight);

        $img->setStyle($yellow, $yellow, $yellow, $yellow,
                       gdTransparent, gdTransparent, gdTransparent, gdTransparent);
        PlotLine($sx, $sy, $ex, $ey, gdStyled);
        if ($plan_end_day < $end_jd) {
            PlotLine($ex, $ey, $xAxisLength, $ey, gdStyled);
        }
    }


        
    %logs = ();
    @years = ();


        print($outfile $img->png());


    }

    sub WeightToY {             # Map weight to vertical pixel position
        my ($w) = @_;
        return int((($w - $wgt_min) * ($height - ($bottomMargin + $topMargin))) / ($wgt_max - $wgt_min));
    }

    sub RungToY {               # Map exercise rung to vertical pixel position
        my ($r) = @_;
        return int((($r - 1) * ($height - ($bottomMargin + $topMargin))) / HDiet::monthlog::RUNG_MAX);
    }
    sub PlotScaleLine {         # Transform plot area co-ordinates into absolute
        my ($x1, $y1, $x2, $y2) = @_;
        return ($leftMargin + $x1, ($height - $bottomMargin) - $y1,
                $leftMargin + $x2, ($height - $bottomMargin) - $y2);
    }

    sub PlotLine {              # Plot a line given plot area co-ordinates and colour
        my ($rx1, $ry1, $rx2, $ry2, $colour) = @_;
        die("Colour missing from call to PlotLine") if !defined($colour);
        my ($x1, $y1, $x2, $y2) = PlotScaleLine($rx1, $ry1, $rx2, $ry2);
        $img->line($x1, $y1, $x2, $y2, $colour);
    }

    sub drawBadgeImage {
        my $self = shift;

        my ($outfile, $trendDays) = @_;

        my ($ui, $user_file_name) = ($self->{user}, $self->{user_file_name});

        if (!(defined $outfile)) {
            $outfile = \*STDOUT;
        }

        ($width, $height) = (200, 78);  # Badge image size
        my ($printFriendly, $monochrome) = (0, 0);
        $img = GD::Image->newFromPng("/server/bin/httpd/cgi-bin/HDiet/Images/badgeback.png", 1);
        die("Cannot load image template /server/bin/httpd/cgi-bin/HDiet/Images/badgeback.png") if !$img;
        
    #   First colour allocated is background
    my $white =  $img->colorAllocate(255, 255, 255);
    my $grey = ($printFriendly || $monochrome) ?
                    $white :
                    $img->colorAllocate(160, 160, 160);
    my $black =  $img->colorAllocate(  0,   0,   0);
    my $red =    $monochrome ? $black : $img->colorAllocate(255,   0,   0);
    my $green =  $monochrome ? $black : $img->colorAllocate(  0, 255,   0);
    my $yellow = $monochrome ? $black : ($printFriendly ?
        $img->colorAllocate(192, 192,   0) : $img->colorAllocate(255, 255,   0));
    my $blue =   $monochrome ? $black : $img->colorAllocate(  0,   0, 255);
    my $dkgrey = $img->colorAllocate(128, 128, 128);

        my $dkgreen =  $img->colorAllocate(  0, 160,   0);
        $img->interlaced('true');

        my ($ly, $lm, $ld, $ldu, $lw, $lt) = $self->lastDay();
        my $l_jd = gregorian_to_jd($ly, $lm, $ld);
        my ($s_y, $s_m, $s_d) = $self->firstDay();
        my $s_jd = gregorian_to_jd($s_y, $s_m, $s_d);

        my ($cx, $cy) = (132, 3);

        if (defined($lw)) {

            my (@intervals, @slopes, $tslope, $deltaW, $deltaE);

            if (($l_jd - $s_jd) > 1) {
                my ($f_y, $f_m, $f_d) = $self->firstDayOfInterval($ly, $lm, $ld, $trendDays);
                my $f_jd = gregorian_to_jd($f_y, $f_m, $f_d);
                push(@intervals, sprintf("%04d-%02d-%02d", $f_y, $f_m, $f_d),
                                  sprintf("%04d-%02d-%02d", $ly, $lm, $ld));
                @slopes = $self->analyseTrend(@intervals);
                $tslope = $slopes[0];
                $deltaW = sprintf("%.2f", abs($tslope) * 7);
                $deltaW =~ s/\./$ui->{decimal_character}/;
                $deltaE = sprintf("%.0f", abs($tslope) *
                    (HDiet::monthlog::CALORIES_PER_WEIGHT_UNIT->[$ui->{display_unit}] /
                     HDiet::monthlog::CALORIES_PER_ENERGY_UNIT->[$ui->{energy_unit}]));
            }

            main::drawText($img, sprintf("%04d-%02d-%02d", $ly, $lm, $ld),
                'DejaVuLGCSans-Bold', 10, 0, $cx, $cy, 'c', 't', $black);
                $cy += 13;

            my $ws = HDiet::monthlog::editWeight($lw *
                HDiet::monthlog::WEIGHT_CONVERSION->[$ldu][$ui->{display_unit}],
                $ui->{display_unit}, $ui->{decimal_character});
            my ($wu, $eu) = (HDiet::monthlog::WEIGHT_ABBREVIATIONS->[$ui->{display_unit}],
                             HDiet::monthlog::ENERGY_ABBREVIATIONS->[$ui->{energy_unit}]);
            if ($ui->{display_unit} =~ HDiet::monthlog::WEIGHT_STONE) {
                $ws =~ s/\s/" $wu "/e;
                $wu = HDiet::monthlog::WEIGHT_ABBREVIATIONS->[HDiet::monthlog::WEIGHT_POUND];
            }
            $ws .= " $wu";
            main::drawText($img, $ws,
                'DejaVuLGCSans-Bold', 12, 0, $cx, $cy, 'c', 't', $black);
            $cy += 16;


            if (defined($deltaW)) {
                #   Trend label
                main::drawText($img,
                    abs($trendDays) . ' ' . (($trendDays > 0) ? 'Day' : 'Month') . 'Trend',
                    'DejaVuLGCSans', 10, 0, $cx, $cy, 'c', 't', $black);
                $cy += 14;

                #   Energy balance
                main::drawText($img,
                    (($tslope <= 0) ? 'Deficit' : 'Excess') . " $deltaE $eu/day",
                    'DejaVuLGCSans', 10, 0, $cx, $cy, 'c', 't',
                    (($tslope <= 0) ? $dkgreen : $red));
                $cy += 14;

                #   Weekly weight change
                main::drawText($img, (($tslope <= 0) ? 'Loss' : 'Gain') . " $deltaW $wu/week",
                    'DejaVuLGCSans', 10, 0, $cx, $cy, 'c', 't',
                    (($tslope <= 0) ? $dkgreen : $red));
            } else {
                $cy += 18;
                main::drawText($img, "Trend not defined.",
                    'DejaVuLGCSans', 10, 0, $cx, $cy, 'c', 't', $black);
            }

        } else {
            $cy += int($height / 2) - 12;
            main::drawText($img, 'No Log',
                'DejaVuLGCSans-Bold', 12, 0, $cx, $cy, 'c', 'c', $black);
                $cy += 18;
            main::drawText($img, 'Entries',
                'DejaVuLGCSans-Bold', 12, 0, $cx, $cy, 'c', 'c', $black);
        }

        print($outfile $img->png());
    }

    sub syntheticData {
        my $self = shift;

        my ($start_date,                    # Start date: YYYY-MM-DD
            $end_date,                      # End date:   YYYY-MM-DD
            $field_name,                    # Name of field to be filled
            $fill_fraction,                 # Fraction of days to fill
            $start_value,                   # Start value
            $end_value,                     # End value
            $format,                        # Format for rounding numbers
            ) = splice(@_, 0, 7);

        my ($ui, $user_file_name) = ($self->{user}, $self->{user_file_name});

        
    $start_date =~ m/^(\d+)(?:\-(\d+))?(?:\-(\d+))?$/ || die("history::drawChart: invalid start date $start_date");
    my ($start_y, $start_m, $start_d) = ($1, $2, $3);
    $start_m = 1 if !defined($start_m);
    $start_d = 1 if !defined($start_d);
    $start_jd = gregorian_to_jd($start_y, $start_m, $start_d);

    $end_date =~ m/^(\d+)(?:\-(\d+))?(?:\-(\d+))?$/ || die("history::drawChart: invalid end date $end_date");
    my ($end_y, $end_m, $end_d) = ($1, $2, $3);
    $end_m = 12 if !defined($end_m);
    if (!defined($end_d)) {
        $end_jd = gregorian_to_jd($end_y, $end_m + 1, 1) - 1;
        $end_d  = (jd_to_gregorian($end_jd))[2];
    }
    $end_jd = gregorian_to_jd($end_y, $end_m, $end_d);

    my $dayspan = (($end_jd + 1) - $start_jd);

        
    my ($cur_y, $cur_m) = ($start_y, $start_m);

    for (my $monkey = sprintf("%04d-%02d", $start_y, $start_m); $monkey le sprintf("%04d-%02d", $end_y, $end_m); $monkey = sprintf("%04d-%02d", $cur_y, $cur_m)) {
        if (!$logs{$monkey}) {
            if (-f "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") {
                open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") ||
                    die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$monkey.hdb");
                my $mlog = HDiet::monthlog->new();
                $logs{$monkey} = $mlog;
                $mlog->load(\*FL);
                close(FL);
            }
        }
        ($cur_y, $cur_m) = HDiet::monthlog::nextMonth($cur_y, $cur_m);
    }


        my ($ngen, $nskip) = (0, 0);
        for (my $j = $start_jd; $j <= $end_jd; $j++) {
            if (rand() <= $fill_fraction) {
                my ($cd_y, $cd_m, $cd_d) = jd_to_gregorian($j);
                my $v = $start_value + ($end_value - $start_value) * (($j - $start_jd) / ($end_jd - $start_jd));

                
    for (my $n = 0; $n <= $#_; $n++) {

        #   'uniform', <range>
        if ($_[$n] eq 'uniform') {
            $n++;
            $v += rand($_[$n] * 2) - $_[$n];

        #   'gaussian', <range>
        } elsif ($_[$n] eq 'gaussian') {
            $n++;
            my $g = 0;
            for (my $i = 0; $i < 8; $i++) {
                $g += rand();
            }
            $g /= 8;
            $v += ($_[$n] * 2 * $g) - $_[$n];

        #   'sine', <factor>, <period>, <phase>
        } elsif ($_[$n] eq 'sine') {
            my $factor = $_[++$n];
            my $period = $_[++$n];
            my $phase  = $_[++$n];
            $period = 31 if $period eq '';
            $phase = 0 if $phase eq '';
            my $pi = 4 * atan2(1, 1);
            $v += $factor * sin((2 * $pi) * ((($j + $phase) - $start_jd) / $period));

        } elsif ($_[$n] ne '') {
            die("history::syntheticData: Invalid perturbation function $_[$n]");
        }
    }


                $v = sprintf($format, $v);
#print("    $j  $v<br />\n");
                my $monkey = sprintf("%04d-%02d", $cd_y, $cd_m);
                if (!defined($logs{$monkey})) {
                    
    my $mlog = HDiet::monthlog->new();
    $logs{$monkey} = $mlog;
    $mlog->{login_name} = $ui->{login_name};
    $mlog->{year} = $cd_y;
    $mlog->{month} = $cd_m;
    $mlog->{log_unit} = $ui->{log_unit};
    $mlog->{last_modification_time} = 0;
    $mlog->{trend_carry_forward} = 0;

                }
                $logs{$monkey}->{$field_name}[$cd_d] = $v;
                $ngen++;
            } else {
#print("    $j<br />\n");
                $nskip++;
            }
        }

        
    for my $k (keys(%logs)) {
        my $mlog = $logs{$k};
        $mlog->{last_modification_time} = time();
        open(FL, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/$k.hdb") ||
            die("Cannot update monthly log file /server/pub/hackdiet/Users/$user_file_name/$k.hdb");
        $mlog->save(\*FL);
        close(FL);
        clusterCopy("/server/pub/hackdiet/Users/$user_file_name/$k.hdb");
    }

    if (scalar(keys(%logs)) > 0) {
        if ($self->{user}->{badge_trend} != 0) {
            open(FB, ">/server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png") ||
                die("Cannot update monthly log file /server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png");
            $self->drawBadgeImage(\*FB, $self->{user}->{badge_trend});
            close(FB);
            ::do_command("mv /server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png /server/pub/hackdiet/Users/$user_file_name/BadgeImage.png");
            clusterCopy("/server/pub/hackdiet/Users/$user_file_name/BadgeImage.png");
        }
    }


if (0) {
print("<pre>\n");
for my $l (sort(keys(%logs))) {
    $logs{$l} ->describe();
}
print("</pre>\n");
}
        print("<h3>$ngen days generated, $nskip days skipped.</h3>\n");
    }

    sub lastDay {
        my $self = shift;

        
    if ($#years < 0) {
        @years = $self->{user}->enumerateYears();
    }


        for (my $y = $#years; $y >= 0; $y--) {
            my @months = $self->{user}->enumerateMonths($years[$y]);
            for (my $m = $#months; $m >= 0; $m--) {
                
    if (!$logs{$months[$m]}) {
        open(FL, "<:utf8", "/server/pub/hackdiet/Users/$self->{user_file_name}/$months[$m].hdb") ||
            die("Cannot open monthly log file /server/pub/hackdiet/Users/$self->{user_file_name}/$months[$m].hdb");
        my $mlog = HDiet::monthlog->new();
        $logs{$months[$m]} = $mlog;
        $mlog->load(\*FL);
        close(FL);
    }

                for (my $d = $logs{$months[$m]}->monthdays(); $d >= 1;  $d--) {
                    if ($logs{$months[$m]}->{weight}[$d]) {
                        return ($logs{$months[$m]}->{year}, $logs{$months[$m]}->{month}, $d,
                                $logs{$months[$m]}->{log_unit},
                                $logs{$months[$m]}->{weight}[$d],
                                $logs{$months[$m]}->{trend}[$d]);
                    }
                }
            }
        }
        return undef;
    }

    sub firstDay {
        my $self = shift;

        
    if ($#years < 0) {
        @years = $self->{user}->enumerateYears();
    }


        for (my $y = 0; $y <= $#years; $y++) {
            my @months = $self->{user}->enumerateMonths($years[$y]);
            for (my $m = 0; $m <= $#months; $m++) {
                
    if (!$logs{$months[$m]}) {
        open(FL, "<:utf8", "/server/pub/hackdiet/Users/$self->{user_file_name}/$months[$m].hdb") ||
            die("Cannot open monthly log file /server/pub/hackdiet/Users/$self->{user_file_name}/$months[$m].hdb");
        my $mlog = HDiet::monthlog->new();
        $logs{$months[$m]} = $mlog;
        $mlog->load(\*FL);
        close(FL);
    }

                for (my $d = 1; $d <= $logs{$months[$m]}->monthdays();  $d++) {
                    if ($logs{$months[$m]}->{weight}[$d]) {
                        return ($logs{$months[$m]}->{year}, $logs{$months[$m]}->{month}, $d);
                    }
                }
            }
        }
        return undef;
    }

    sub firstDayOfInterval {
        if ($#_ > 3) {
            my $self = shift;
        }
        my ($year, $month, $day, $interval) = @_;
#print("Fdoi E($interval): $year-$month-$day\n");

        if ($interval >= 0) {
            my $jdEnd = gregorian_to_jd($year, $month, $day);
            ($year, $month, $day) = jd_to_gregorian($jdEnd - $interval);
        } else {
            while ($interval < 0) {
                ($year, $month) = HDiet::monthlog::previousMonth($year, $month);
                $interval++;
            }
            if ($day > HDiet::monthlog::monthdays($year, $month)) {
                $day = HDiet::monthlog::monthdays($year, $month);
            }
        }

#print("Fdoi X($interval): $year-$month-$day\n");
        return ($year, $month, $day);
    }
