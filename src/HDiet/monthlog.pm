#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    use HDiet::trendfit;

    package HDiet::monthlog;

    use HDiet::hdCSV;
    use HDiet::Julian qw(WEEKDAY_NAMES :DEFAULT);
    use HDiet::html;
    use HDiet::xml;
    use GD;

    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(
                      WEIGHT_KILOGRAM WEIGHT_POUND WEIGHT_STONE
                      ENERGY_CALORIE ENERGY_KILOJOULE
                      WEIGHT_CONVERSION ENERGY_CONVERSION
                      CALORIES_PER_WEIGHT_UNIT
                      );
    our %EXPORT_TAGS = (
                            units => [ qw(WEIGHT_KILOGRAM WEIGHT_POUND WEIGHT_STONE
                                          ENERGY_CALORIE ENERGY_KILOJOULE) ]
                       );
    1;

    
    use constant FILE_VERSION => 1;
    use constant WEIGHT_KILOGRAM => 0;
    use constant WEIGHT_POUND => 1;
    use constant WEIGHT_STONE => 2;
    use constant WEIGHT_UNITS => [ "kilogram", "pound", "stone" ];
    use constant DELTA_WEIGHT_UNITS => [ "kilogram", "pound", "pound" ];
    use constant DELTA_WEIGHT_ABBREVIATIONS => [ "kg", "lb", "lb" ];
    use constant WEIGHT_ABBREVIATIONS => [ "kg", "lb", "st" ];
    use constant CALORIES_PER_WEIGHT_UNIT => [ 7716, 3500, 3500 ];

    use constant WEIGHT_CONVERSION => [
    #   Entries for pounds and stones are identical because
    #   even if stones are selected, entries in log items are
    #   always kept in pounds.
    #
    #  To:         kg               lb             st
    #                                                             From
              [ 1.0,            2.2046226,     2.2046226    ],  #   kg
              [ 0.45359237,     1.0,           1.0          ],  #   lb
              [ 0.45359237,     1.0,           1.0          ]   #   st
    ];


    use constant ENERGY_CALORIE => 0;
    use constant ENERGY_KILOJOULE => 1;
    use constant ENERGY_UNITS => [ "calorie", "kilojoule" ];
    use constant ENERGY_ABBREVIATIONS => [ "cal", "kJ" ];
    use constant CALORIES_PER_ENERGY_UNIT => [ 1, 0.239045 ];
    use constant ENERGY_CONVERSION => [
    #
    #   To:         cal         kJ                 From
                [   1.0,        4.18331  ],     #   cal
                [   0.239045,   1.0      ]      #   kJ
    ];

    use constant RUNG_MAX => 48;



    
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



    sub new {
        my $self = {};
        my ($invocant, $login_name, $year, $month, $log_unit,
            $trend_carry_forward, $last_modification_time) = @_;
        my $class = ref($invocant) || $invocant;

        $login_name = '' if !defined($login_name);
        $year = 0 if !defined($year);
        $month = 0 if !defined($month);
        $log_unit = WEIGHT_KILOGRAM if !defined($log_unit);
        $trend_carry_forward = 0 if !defined($trend_carry_forward);
        $last_modification_time = 0 if !defined($last_modification_time);

        bless($self, $class);

        $self->{version} = FILE_VERSION;

        #   Initialise instance variables from constructor arguments
        $self->{login_name} = $login_name;
        $self->{year} = $year;
        $self->{month} = $month;
        $self->{log_unit} = $log_unit;
        $self->{trend_carry_forward} = $trend_carry_forward;
        $self->{last_modification_time} = $last_modification_time;

        $self->{weight} = [];                   # Create empty weight array
        $self->{rung} = [];                     # Create empty exercise rung array
        $self->{flag} = [];                     # Create empty flag array
        $self->{comment} = [];                  # Create empty comment array
        $self->{trend} = [];                    # Create empty trend array
        $self->{verbose} = 0;                   # Default to non-verbose mode

        return $self;
    }

    sub DESTROY {
        my $self = shift;

        if ($self->{verbose}) {
            print("monthlog: Destructor invoked\n");
        }
        undef($self->{weight});
        undef($self->{rung});
        undef($self->{flag});
        undef($self->{comment});
        undef($self->{trend});

    }

    sub describe {
        my $self = shift;
        my ($outfile) = @_;

        if (!(defined $outfile)) {
            $outfile = \*STDOUT;
        }

        print($outfile "MONTHLOG Version: $self->{version}\n");
        print($outfile "  Login: '$self->{login_name}'  Year: $self->{year}  " .
            "Month: $self->{month}  " .
            "Log unit: " . WEIGHT_UNITS->[$self->{log_unit}] ."\n");
        print($outfile "  Trend carry-forward: $self->{trend_carry_forward}\n" .
            "  Last modification time: " . localtime($self->{last_modification_time}) .
            "\n");
        print($outfile "  Days in month: " . $self->monthdays() . "\n");

        for (my $i = 1; $i <= $self->monthdays(); $i++) {
            my $dw = defined($self->{weight}[$i]) ? sprintf("%6.2f", $self->{weight}[$i]) : "      ";
            my $dt = defined($self->{trend}[$i]) ? sprintf("%6.2f", $self->{trend}[$i]) : "      ";
            my $dr = defined($self->{rung}[$i]) ? sprintf("%2d", $self->{rung}[$i]) : "  ";
            my $df = defined($self->{flag}[$i]) ? sprintf("%1d", $self->{flag}[$i]) : " ";
            my $dc = defined($self->{comment}[$i]) ? "  $self->{comment}[$i]" : "";

            printf($outfile "   %2d  $dw  $dt  $dr  $df$dc\n", $i);
        }
    }

    sub computeTrend {
        my $self = shift;

        my $t = $self->{trend_carry_forward};
        my $n = $self->monthdays();

        if ($t == 0) {
            for (my $i = 1; $i <= $n; $i++) {
                if (defined($self->{weight}[$i]) && ($self->{weight}[$i] > 0)) {
                    $t = $self->{weight}[$i];
                    last;
                }
            }
        }

        if ($t > 0) {
            for (my $i = 1; $i <= $n; $i++) {
                if (defined($self->{weight}[$i]) && ($self->{weight}[$i] > 0)) {
                    $t = $t + (($self->{weight}[$i] - $t) / 10);
                }
                $self->{trend}[$i] = $t;
            }
        }

        my $nd = $n;

        while (($nd >= 0) && (!defined($self->{weight}[$nd]))) {
            $nd--;
        }

        if ($nd <= 1) {
            return 0;
        }

        my $fitter = HDiet::trendfit->new();
        for (my $i = 1; $i <= $nd; $i++) {
            $fitter->addPoint($self->{trend}[$i]);
        }
        return $fitter->fitSlope();
    }

    sub bodyMassIndex {
        my $self = shift;

        my ($height, $day) = @_;

        $day = 0 if !defined($day);
        return 0 if $height == 0;

        my $n = $self->monthdays();
        my $weight = 0;

        if ($day <= 0) {
            my $nd = 0;
            for (my $i = 1; $i <= $n; $i++) {
                if (defined($self->{weight}[$i]) && ($self->{weight}[$i])) {
                    if ($day < 0) {
                        $weight = $self->{trend}[$i];
                        $nd = 1;
                   } else {
                        $weight += $self->{trend}[$i];
                        $nd++;
                    }
                }
            }
            $weight /= $nd if $nd > 0;
        } else {
            $weight = $self->{weight}[$day] if defined($self->{weight}[$day]);
        }

        $weight *= WEIGHT_CONVERSION->[$self->{log_unit}][WEIGHT_KILOGRAM];
        return sprintf("%.1f", $weight / ($height / 100) ** 2);
    }

    sub fractionFlagged {
        my $self = shift;

        my $n = $self->monthdays();
        my $nf = 0;

        for (my $i = 1; $i <= $n; $i++) {
            if ($self->{flag}[$i]) {
                $nf++;
            }
        }

        return $nf / $n;
    }

    sub save {
        my $self = shift;
        my ($outfile) = @_;

        #   File format version number
        print($outfile "$self->{version}\n");
        #   Year, Month, Log unit
        print($outfile "$self->{year},$self->{month},$self->{log_unit}\n");
        #   Trend carry-forward, Last modification time
        print($outfile "$self->{trend_carry_forward},$self->{last_modification_time}\n");
        my $md = $self->monthdays();
        #   Weight array
        for (my $i = 1; $i <= $md; $i++) {
            print($outfile (dnz($self->{weight}[$i]) ? $self->{weight}[$i] : ''));
            print($outfile (($i < $md) ? ',' : "\n"));
        }
        #   Rung array
        for (my $i = 1; $i <= $md; $i++) {
            print($outfile (dnz($self->{rung}[$i]) ? $self->{rung}[$i] : ''));
            print($outfile (($i < $md) ? ',' : "\n"));
        }
        #   Flag array
        for (my $i = 1; $i <= $md; $i++) {
            print($outfile (dnz($self->{flag}[$i]) ? $self->{flag}[$i] : ''));
            print($outfile (($i < $md) ? ',' : "\n"));
        }

        #   Comments
        print($outfile $self->encodeComments() . "\n");
    }

    sub load {
        my $self = shift;
        my ($infile) = @_;

        my $s = in($infile);

        if ($s != FILE_VERSION) {
            die("monthlog::load: Incompatible file version $s");
        }

        $s = in($infile);
        $s =~ m/^(\d+),(\d+),(\d+)$/ || die("monthlog::load: Error parsing year, month, log unit");
        $self->{year} = $1;
        $self->{month} = $2;
        $self->{log_unit} = $3;

        $s = in($infile);
        $s =~ m/^([\d\.]+),(\d+)$/ || die("monthlog::load: Error parsing trend carry forward, last modification time");
        $self->{trend_carry_forward} = $1;
        $self->{last_modification_time} = $2;

        my $md = $self->monthdays();

        $s = in($infile);
        for (my $i = 1; $i <= $md; $i++) {
            $s =~ s/^([\d\.]*),?// || die("monthlog::load: Error parsing weight for day $i");
            if ($1 ne '') {
                $self->{weight}[$i] = $1;
            }
        }
        if ($s ne '') {
            die("monthlog::load: Residual characters ($s) after parsing weights");
        }

        $self->computeTrend();      # Fill in daily trend now that weights are known

        $s = in($infile);
        $s =~ s/\s//g;
        for (my $i = 1; $i <= $md; $i++) {
            $s =~ s/^(\d*),?// || die("monthlog::load: Error parsing rung for day $i");
            if ($1 ne '') {
                $self->{rung}[$i] = $1;
            }
        }
        if ($s ne '') {
            die("monthlog::load: Residual characters ($s) after parsing rungs");
        }

        $s = in($infile);
        for (my $i = 1; $i <= $md; $i++) {
            $s =~ s/^(\d*),?// || die("monthlog::load: Error parsing flag for day $i");
            if ($1 ne '') {
                $self->{flag}[$i] = $1;
            }
        }
        if ($s ne '') {
            die("monthlog::load: Residual characters ($s) after parsing flags");
        }

        $s = in($infile);
        $self->decodeComments($s);
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
                die("monthlog::in: Unexpected end of file");
            }
        }
        return $s;
    }


    sub toHTML {
        my $self = shift;

        my ($fh, $efirst, $elast, $display_unit,
            $decimal_character, $browse_public,
            $printFriendly, $monochrome) = @_;

        $efirst = 0 if !defined($efirst) || $printFriendly;
        $elast = 0 if !defined($elast) || $printFriendly;

        my $printfix = ($printFriendly ? 'pr_' : '') . ($monochrome ? 'mo_' : '');

        my $n = $self->monthdays();

        my $logToDisplayUnit = WEIGHT_CONVERSION->[$self->{log_unit}][$display_unit];

        
    print $fh <<"EOD";
<table border="border" class="${printfix}mlog">
<tr>
<th colspan="2">Date</th>
<th>Weight</th>
<th>Trend</th>
<th>Var.</th>
<th>Rung</th>
<th>Flag</th>
EOD

    if (!$browse_public) {
        print $fh <<"EOD";
<th>Comments</th>
EOD
    }

    print $fh <<"EOD";
</tr>
EOD


        my $lastweight;
        for ($lastweight = $n; $lastweight >= 1; $lastweight--) {
            if (znd($self->{weight}[$lastweight])) {
                last;
            }
        }

        my $wday = jd_to_weekday(gregorian_to_jd($self->{year}, $self->{month}, 1));
        for (my $i = 1; $i <= $n; $i++) {
            my $edit = (!$browse_public) && ($i >= $efirst) && ($i <= $elast);

            print($fh "<tr>\n");

            
    print($fh "<th>$i</th>\n");     # Day
    print($fh "<td>" . substr(WEEKDAY_NAMES->[$wday], 0, 3) . "</td>\n"); # Weekday
    $wday = ($wday + 1) % 7;

            
    # Weight
    print($fh "<td>");
    if ($edit) {
        print($fh "<input type=\"text\" name=\"w$i\"  id=\"w$i\" size=\"6\" value=\"" .
            wgt(znd($self->{weight}[$i]) * $logToDisplayUnit,
                $display_unit, $decimal_character) .
            "\" onchange=\"changeWeight($i);\" />" .
        "<input type=\"hidden\" id=\"W$i\" value=\"" .
        (znd($self->{weight}[$i]) ? fixo(znd($self->{weight}[$i]) * $logToDisplayUnit, 4)
                                  : '') . "\" />");
    } else {
        print($fh wgt(znd($self->{weight}[$i]) * $logToDisplayUnit,
            $display_unit, $decimal_character));
    }
    print($fh "</td>\n");

    # Trend
    print($fh "<td id=\"t$i\">" .
        wgt(($i > $lastweight) ? undef :
            (znd($self->{trend}[$i]) * $logToDisplayUnit), $display_unit, $decimal_character, 1) .
            "<input type=\"hidden\" id=\"T$i\" value=\"" . fixo(znd($self->{trend}[$i]) *
            $logToDisplayUnit, 4) . "\" />" .
        "</td>\n");

     # Variance
    my $var = (defined($self->{weight}[$i]) && defined($self->{trend}[$i]) &&
                ($self->{weight}[$i] > 0) && ($self->{trend}[$i] > 0)) ?
                    (($self->{weight}[$i] - $self->{trend}[$i]) * $logToDisplayUnit) : undef;
    print($fh "<td class=\"r\"><span id=\"v$i\" class=\"" . $printfix .
                 ((defined($var) && (sprintf("%.1f", $var) !~ m/^\-?0\.0$/)) ?
                    (($var < 0) ? "g" : "r") : "bk") . "\">" .
                    var($var, $decimal_character) . "</span></td>\n");

            
    print($fh "<td>");
    if ($edit) {
        print($fh "<input type=\"text\" name=\"r$i\" id=\"r$i\" size=\"3\" value=\"" .
            bnd($self->{rung}[$i]) . "\" onchange=\"changeRung($i);\" />");
    } else {
        print($fh bnd($self->{rung}[$i]));
    }
    print($fh "</td>\n");

            
    print($fh "<td>");
    if ($edit) {
        print($fh "<input type=\"checkbox\" name=\"f$i\" id=\"f$i\" onclick=\"updateFlag($i);\"" .
            ($self->{flag}[$i] ? " checked=\"checked\"" : "") . " />");
    } else {
        if ($self->{flag}[$i]) {
            print($fh "<input type=\"hidden\" name=\"f$i\" id=\"f$i\" value=\"checked\" />");
        }
        print($fh $self->{flag}[$i] ? "&#10004;" : "");
    }
    print($fh "</td>\n");

            if (!$browse_public) {
                
    print($fh "<td>");
    my $cmt = quoteHTML(defined($self->{comment}[$i]) ? $self->{comment}[$i] : "");
    if ($edit) {
        print($fh "<input type=\"text\" name=\"c$i\" id=\"c$i\" size=\"60\" " .
                  "maxlength=\"4096\" " .
                  "value=\"$cmt\" onchange=\"changeComment($i);\" />");
    } else {
        print($fh $cmt);
    }
    print($fh "</td>\n");

            }

            print($fh "</tr>\n");
        }

        
    print $fh <<"EOD";
</table>
EOD


    }

    sub editWeight {
        my ($weight, $unit, $dchar) = @_;

        $dchar = '.' if !defined($dchar);
        my $sgn = ($weight < 0) ? "-" : "";
        my $w = abs($weight);
        my $sw;
        if ($unit == WEIGHT_STONE) {
            $sw = sprintf("%s%d %2.1f", $sgn, int($w / 14), $w - (int($w / 14) * 14));
        } else {
            $sw = sprintf("%s%.1f", $sgn, $w);
        }
        $sw =~ s/\./$dchar/;
        return $sw;
    }

    sub convertWeight {
        my ($weight, $from, $to) = @_;

        $weight = canonicalWeight($weight * WEIGHT_CONVERSION->[$from][$to]);

        return $weight;
    }

    sub canonicalWeight {
        my ($weight) = @_;

        $weight = sprintf("%.2f", $weight);

        $weight =~ s/(\.[^0]*)0+$/$1/;
        $weight =~ s/\.$//;

        return $weight;
    }

    sub dnz {
        my ($s) = @_;

        return defined($s) && ($s > 0);
    }

    sub bnd {
        my ($s) = @_;

        return (defined($s) && ($s > 0)) ? $s : '';
    }

    sub znd {
        my ($s) = @_;

        return (defined($s) && ($s > 0)) ? $s : 0;
    }

    sub fixo {
        my ($v, $places) = @_;
        my $s = sprintf("%.${places}f", $v);
        $s =~ s/0+$//;
        $s =~ s/\.$//;
        return $s;
    }

    sub wgt {
        my ($s, $dunit, $dchar, $nbsp) = @_;

        return (defined($s) && ($s > 0)) ? editWeight($s, $dunit, $dchar) :
            ($nbsp ? '&nbsp;' : '');
    }

    sub var {
        my ($s, $dchar) = @_;

        my $v;
        if (defined($s)) {
            $v =  (($s < 0) ? "&minus;" : "+") . sprintf("%.1f", abs($s));
            $v = '0.0' if $v =~ m/\D0\.0$/;
            $v =~ s/\./$dchar/;
        } else {
            $v = '&nbsp;';
        }
        return $v;
    }

    sub computeChartScale {
        my $self = shift;
        my ($width, $height, $display_unit, $dietcalc) = @_;

        $width = 640 if !defined($width);
        $height = 480 if !defined($height);

        my $logToDisplayUnit = WEIGHT_CONVERSION->[$self->{log_unit}][$display_unit];

        
    my ($fontLineHeight, $fontCharHeight) = (20, 10);
    my ($leftMargin, $rightMargin, $topMargin, $bottomMargin) =
        ($fontCharHeight * (($display_unit == WEIGHT_STONE) ? 6 : 5),
        $fontCharHeight * 3, 10, $fontCharHeight * 3);
    my ($axisOffset, $tickSize, $sinkerSize) = (3, 5, 4);

    my ($topLeftX, $topLeftY) = (0, 0);
    my ($extentX, $extentY) = ($width, $height);

    my $pixelsPerDay = ($extentX - ($leftMargin + $rightMargin)) / ($self->monthdays() - 1);

    my ($bX, $bY) = ($topLeftX + $leftMargin, (($topLeftY + $extentY) - $bottomMargin));


        
    my ($weightMin, $weightMax) = (1e308, 0);
    my ($trendMin, $trendMax) = (1e308, 0);

    for (my $i = 1; $i <= $self->monthdays(); $i++) {
         if (dnz($self->{weight}[$i])) {
            $weightMax = max($weightMax, $self->{weight}[$i] * $logToDisplayUnit);
            $weightMin = min($weightMin, $self->{weight}[$i] * $logToDisplayUnit);
            $trendMax = max($trendMax, $self->{trend}[$i] * $logToDisplayUnit);
            $trendMin = min($trendMin, $self->{trend}[$i] * $logToDisplayUnit);
         }
    }

    $weightMin = min($weightMin, $trendMin);
    $weightMax = max($weightMax, $trendMax);

    if ($self->{trend_carry_forward} > 0) {
        $weightMin = min($weightMin, $self->{trend_carry_forward} * $logToDisplayUnit);
        $weightMax = max($weightMax, $self->{trend_carry_forward} * $logToDisplayUnit);
    }

    
    #   Julian day of start and end of month
    my ($mjdstart, $mjdend) = (gregorian_to_jd($self->{year}, $self->{month}, 1),
        gregorian_to_jd($self->{year}, $self->{month}, $self->monthdays()));
    my ($pjdstart, $pjdend) = (max($mjdstart, $$dietcalc[0]), min($mjdend, $$dietcalc[2]));
    my ($plan_start_day, $plan_start_weight,
        $plan_end_day, $plan_end_weight) = (-1) x 4;
    if (defined($$dietcalc[0])) {
        #   If plan starts before the end of the month, we shall plot it
        if ($pjdstart <= $mjdend) {
            if ($$dietcalc[2] <= $mjdstart) {
                #   Plan ends before start of month; plot flat line at end weight
                $plan_start_day = 1;
                $plan_end_day = $self->monthdays();
                $plan_start_weight = $plan_end_weight = $$dietcalc[3] *
                    WEIGHT_CONVERSION->[WEIGHT_KILOGRAM][$display_unit];
            } else {
                (undef, undef, $plan_start_day) = jd_to_gregorian($pjdstart);
                (undef, undef, $plan_end_day) = jd_to_gregorian($pjdend);
                $plan_start_weight = $$dietcalc[1] + (($$dietcalc[3] - $$dietcalc[1]) *
                    (($pjdstart - $$dietcalc[0]) / ($$dietcalc[2] - $$dietcalc[0])));
                $plan_end_weight = $$dietcalc[1] + (($$dietcalc[3] - $$dietcalc[1]) *
                    (($pjdend - $$dietcalc[0]) / ($$dietcalc[2] - $$dietcalc[0])));
                $plan_start_weight *= WEIGHT_CONVERSION->[WEIGHT_KILOGRAM][$display_unit];
                $plan_end_weight *= WEIGHT_CONVERSION->[WEIGHT_KILOGRAM][$display_unit];

            }
        }
    }

    if ($plan_start_day > 0) {
        $weightMin = min($weightMin, min($plan_start_weight, $plan_end_weight));
        $weightMax = max($weightMax, max($plan_start_weight, $plan_end_weight));
    }

    #   If no weights at all have been specified, scale the chart to encompass
    #   the union of the 5% to 95% percentile points of adult males and females
    #   as published at:    http://www.halls.md/chart/height-weight.htm
    if ($weightMin > $weightMax) {
        if ($display_unit == WEIGHT_KILOGRAM) {
            $weightMin = 40;
            $weightMax = 120;
        } else {
            $weightMin = 100;
            $weightMax = 265;
        }
    } else {
        #   Provide a buffer zone around extrema for new entries
        $weightMax += (($display_unit == WEIGHT_KILOGRAM) ?
            1 :
            (1 * 2)) / 2;
        $weightMin -= (($display_unit == WEIGHT_KILOGRAM) ?
            1 :
            (1 * 2)) / 2;
    }

    my $maxLabelRows = int(($extentY - ($topMargin + $bottomMargin)) / $fontLineHeight);

    my $factor = 0;
    my $vunit = 1;
    my $power = 1;
    my @factors = (1, 2, 5);

    $weightMin *= 10;
    $weightMax *= 10;
    $weightMin = int($weightMin);
    $weightMax = int($weightMax);

    while (int(($weightMax - ($weightMin - ($weightMin % $vunit))) / ($factors[$factor] * $power)) > $maxLabelRows) {
        $factor++;
        if ($factor > 2) {
            $factor = 0;
            $power *= 10;
        }
        $vunit = $factors[$factor] * $power;
    }

    #   There's no point using a finer-grained unit than we
    #   plot decimal places for weight.

    if (($vunit < 10) && ($self->{log_unit} == WEIGHT_STONE)) {
        $vunit = 10;
    }
    if (($vunit < 100) && ($self->{log_unit} == WEIGHT_STONE)) {
        $vunit = 100;
    }

    #   Round weight unit minimum to even unit multiple

    $weightMin -= $weightMin % $vunit;

    #   Offset by one unit at top and bottom to avoid collision
    #   with axes.

    $weightMin -= $vunit;
    $weightMax += $vunit;
    $weightMin /= 10;
    $weightMax /= 10;
    $vunit /= 10;


        return $bX . ',' .
               sprintf("%.4f", $pixelsPerDay) . ',' .
               $bY . ',' .
               $weightMin . ',' .
               ($extentY - ($bottomMargin + $topMargin)) . ',' .
               sprintf("%.4f", $weightMax - $weightMin) . ',' .
               RUNG_MAX;

    }

    sub plotChart {
        my $self = shift;
        my ($outfile, $width, $height, $display_unit, $dchar,
            $dietcalc, $printFriendly, $monochrome) = @_;

        if (!(defined $outfile)) {
            $outfile = \*STDOUT;
        }

        $width = 640 if !defined($width);
        $height = 480 if !defined($height);

        my $logToDisplayUnit = WEIGHT_CONVERSION->[$self->{log_unit}][$display_unit];

        
    my ($fontLineHeight, $fontCharHeight) = (20, 10);
    my ($leftMargin, $rightMargin, $topMargin, $bottomMargin) =
        ($fontCharHeight * (($display_unit == WEIGHT_STONE) ? 6 : 5),
        $fontCharHeight * 3, 10, $fontCharHeight * 3);
    my ($axisOffset, $tickSize, $sinkerSize) = (3, 5, 4);

    my ($topLeftX, $topLeftY) = (0, 0);
    my ($extentX, $extentY) = ($width, $height);

    my $pixelsPerDay = ($extentX - ($leftMargin + $rightMargin)) / ($self->monthdays() - 1);

    my ($bX, $bY) = ($topLeftX + $leftMargin, (($topLeftY + $extentY) - $bottomMargin));


        my $img = new GD::Image($width, $height);

        $img->interlaced('true');

        
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


        $img->filledRectangle($leftMargin + (-$axisOffset) + 1, $topMargin,
                        $leftMargin + ($pixelsPerDay * ($self->monthdays() - 1)),
                            $topMargin + ($extentY - ($topMargin + $bottomMargin)) + ($axisOffset + 1), $grey);

        my $lday = 0;
        for (my $i = $self->monthdays(); $i >= 1; $i--) {
            if (dnz($self->{weight}[$i])) {
                $lday = $i;
                last;
            }
        }

        
    #   X axis
    $img->line($bX - $axisOffset, $bY + $axisOffset + 1,
               $bX + ($pixelsPerDay * ($self->monthdays() - 1)), $bY + $axisOffset + 1, $black);
    #   Y axis
    $img->line($bX - $axisOffset, $bY + $axisOffset + 1,
               $bX - $axisOffset, $bY - ($extentY - (($topMargin + $bottomMargin))), $black);

    #   Date axis labels
    for (my $i = 0; $i < $self->monthdays(); $i += 3) {
        main::drawText($img, $i + 1, 'Times', 12, 0,
            $topLeftX + $leftMargin + ($pixelsPerDay * $i),
            (($topLeftY + $extentY) - ($bottomMargin - $topMargin)), 'c', 't', $black);
    }

    #   Ticks on date axis
    for (my $i = 1; $i < $self->monthdays(); $i++) {
        $img->line($bX + ($pixelsPerDay * $i), $bY + $axisOffset,
                   $bX + ($pixelsPerDay * $i), ($bY + $axisOffset) - $tickSize, $black);
    }

        
    my $lrung;
    my ($lx, $ly) = (-1, -1);

    for (my $i = 1; $i <= $self->monthdays(); $i++) {
        if (dnz($self->{rung}[$i])) {
            my $rt = $self->{rung}[$i];
            $lrung = $rt;

            my ($cx, $cy) = ($bX + ($pixelsPerDay * ($i - 1)),
                ($bY - int((($rt - 1) * ($extentY - ($bottomMargin + $topMargin))) / RUNG_MAX)));

            if ($ly >= 0) {
                 $img->line($lx, $ly, $cx, $cy, $blue);
                 ($lx, $ly) = ($cx, $cy);
            } else {
                if ($i == $self->monthdays()) {
                    $lx = $bX + ($pixelsPerDay * ($i - 2));
                    $img->line($lx, $cy, $cx, $cy, $blue);
                } else {
                    ($lx, $ly) = ($cx, $cy);
                }
            }
        } else {
            if ($ly >= 0) {
                my $cx = $bX + ($pixelsPerDay * ($i - 1));
                $img->line($lx, $ly, $cx, $ly, $blue);
                ($lx, $ly) = (-1, -1);
            }
        }
    }

    #   Draw labels for exercise rung scale

    if ($lrung) {
        $img->line($bX + ($pixelsPerDay * ($self->monthdays() - 1)),
                   $bY + $axisOffset + 1,
                   $bX + ($pixelsPerDay * ($self->monthdays() - 1)),
                   $bY - ($extentY - (($topMargin + $bottomMargin))), $black);

        for (my $i = 1; $i <= RUNG_MAX; $i = (int($i / 6) * 6) + 6) {
            main::drawText($img, $i, 'Times', 12, 0,
                $bX + ($pixelsPerDay * ($self->monthdays() - 1)) + 8,
                $bY - (int((($i - 1) * ($extentY - ($bottomMargin + $topMargin))) / RUNG_MAX)), 'l', 'c', $black);
            if ($i > 1) {
                $img->line($bX + ($pixelsPerDay * ($self->monthdays() - 1)) - $tickSize,
                           $bY - int((($i - 1) * ($extentY - ($bottomMargin + $topMargin))) / RUNG_MAX),
                           $bX + ($pixelsPerDay * ($self->monthdays() - 1)),
                           $bY - int((($i - 1) * ($extentY - ($bottomMargin + $topMargin))) / RUNG_MAX), $black);
            }
        }
    }


        
    my ($weightMin, $weightMax) = (1e308, 0);
    my ($trendMin, $trendMax) = (1e308, 0);

    for (my $i = 1; $i <= $self->monthdays(); $i++) {
         if (dnz($self->{weight}[$i])) {
            $weightMax = max($weightMax, $self->{weight}[$i] * $logToDisplayUnit);
            $weightMin = min($weightMin, $self->{weight}[$i] * $logToDisplayUnit);
            $trendMax = max($trendMax, $self->{trend}[$i] * $logToDisplayUnit);
            $trendMin = min($trendMin, $self->{trend}[$i] * $logToDisplayUnit);
         }
    }

    $weightMin = min($weightMin, $trendMin);
    $weightMax = max($weightMax, $trendMax);

    if ($self->{trend_carry_forward} > 0) {
        $weightMin = min($weightMin, $self->{trend_carry_forward} * $logToDisplayUnit);
        $weightMax = max($weightMax, $self->{trend_carry_forward} * $logToDisplayUnit);
    }

    
    #   Julian day of start and end of month
    my ($mjdstart, $mjdend) = (gregorian_to_jd($self->{year}, $self->{month}, 1),
        gregorian_to_jd($self->{year}, $self->{month}, $self->monthdays()));
    my ($pjdstart, $pjdend) = (max($mjdstart, $$dietcalc[0]), min($mjdend, $$dietcalc[2]));
    my ($plan_start_day, $plan_start_weight,
        $plan_end_day, $plan_end_weight) = (-1) x 4;
    if (defined($$dietcalc[0])) {
        #   If plan starts before the end of the month, we shall plot it
        if ($pjdstart <= $mjdend) {
            if ($$dietcalc[2] <= $mjdstart) {
                #   Plan ends before start of month; plot flat line at end weight
                $plan_start_day = 1;
                $plan_end_day = $self->monthdays();
                $plan_start_weight = $plan_end_weight = $$dietcalc[3] *
                    WEIGHT_CONVERSION->[WEIGHT_KILOGRAM][$display_unit];
            } else {
                (undef, undef, $plan_start_day) = jd_to_gregorian($pjdstart);
                (undef, undef, $plan_end_day) = jd_to_gregorian($pjdend);
                $plan_start_weight = $$dietcalc[1] + (($$dietcalc[3] - $$dietcalc[1]) *
                    (($pjdstart - $$dietcalc[0]) / ($$dietcalc[2] - $$dietcalc[0])));
                $plan_end_weight = $$dietcalc[1] + (($$dietcalc[3] - $$dietcalc[1]) *
                    (($pjdend - $$dietcalc[0]) / ($$dietcalc[2] - $$dietcalc[0])));
                $plan_start_weight *= WEIGHT_CONVERSION->[WEIGHT_KILOGRAM][$display_unit];
                $plan_end_weight *= WEIGHT_CONVERSION->[WEIGHT_KILOGRAM][$display_unit];

            }
        }
    }

    if ($plan_start_day > 0) {
        $weightMin = min($weightMin, min($plan_start_weight, $plan_end_weight));
        $weightMax = max($weightMax, max($plan_start_weight, $plan_end_weight));
    }

    #   If no weights at all have been specified, scale the chart to encompass
    #   the union of the 5% to 95% percentile points of adult males and females
    #   as published at:    http://www.halls.md/chart/height-weight.htm
    if ($weightMin > $weightMax) {
        if ($display_unit == WEIGHT_KILOGRAM) {
            $weightMin = 40;
            $weightMax = 120;
        } else {
            $weightMin = 100;
            $weightMax = 265;
        }
    } else {
        #   Provide a buffer zone around extrema for new entries
        $weightMax += (($display_unit == WEIGHT_KILOGRAM) ?
            1 :
            (1 * 2)) / 2;
        $weightMin -= (($display_unit == WEIGHT_KILOGRAM) ?
            1 :
            (1 * 2)) / 2;
    }

    my $maxLabelRows = int(($extentY - ($topMargin + $bottomMargin)) / $fontLineHeight);

    my $factor = 0;
    my $vunit = 1;
    my $power = 1;
    my @factors = (1, 2, 5);

    $weightMin *= 10;
    $weightMax *= 10;
    $weightMin = int($weightMin);
    $weightMax = int($weightMax);

    while (int(($weightMax - ($weightMin - ($weightMin % $vunit))) / ($factors[$factor] * $power)) > $maxLabelRows) {
        $factor++;
        if ($factor > 2) {
            $factor = 0;
            $power *= 10;
        }
        $vunit = $factors[$factor] * $power;
    }

    #   There's no point using a finer-grained unit than we
    #   plot decimal places for weight.

    if (($vunit < 10) && ($self->{log_unit} == WEIGHT_STONE)) {
        $vunit = 10;
    }
    if (($vunit < 100) && ($self->{log_unit} == WEIGHT_STONE)) {
        $vunit = 100;
    }

    #   Round weight unit minimum to even unit multiple

    $weightMin -= $weightMin % $vunit;

    #   Offset by one unit at top and bottom to avoid collision
    #   with axes.

    $weightMin -= $vunit;
    $weightMax += $vunit;
    $weightMin /= 10;
    $weightMax /= 10;
    $vunit /= 10;

        
    if ($plan_start_day > 0) {
        my $sy = int((($plan_start_weight - $weightMin) *
            ($extentY - ($bottomMargin + $topMargin))) / ($weightMax - $weightMin));
        my $ey = int((($plan_end_weight - $weightMin) *
            ($extentY - ($bottomMargin + $topMargin))) / ($weightMax - $weightMin));

        $img->setStyle($yellow, $yellow, $yellow, $yellow,
                       gdTransparent, gdTransparent, gdTransparent, gdTransparent);
        $img->line($bX + ($pixelsPerDay * ($plan_start_day - 1)), $bY - $sy,
                   $bX + ($pixelsPerDay * ($plan_end_day - 1)), $bY - $ey, gdStyled);
        if ($plan_end_day < $self->monthdays()) {
            $img->line($bX + ($pixelsPerDay * ($plan_end_day - 1)), $bY - $ey,
                       $bX + ($pixelsPerDay * ($self->monthdays() - 1)), $bY - $ey, gdStyled);
        }
    }

        if ($lday > 0) {
            
    for (my $i = 1; $i < $lday; $i++) {
        my $oy = int(((($self->{trend}[$i] * $logToDisplayUnit) - $weightMin) *
            ($extentY - ($bottomMargin + $topMargin))) / ($weightMax - $weightMin));
        my $ny = int(((($self->{trend}[$i + 1] * $logToDisplayUnit) - $weightMin) *
            ($extentY - ($bottomMargin + $topMargin))) / ($weightMax - $weightMin));

        $img->line($bX + ($pixelsPerDay * ($i - 1)), $bY - $oy,
                   $bX + ($pixelsPerDay * $i), $bY - $ny, $red);
    }

            
    for (my $i = 1; $i <= $self->monthdays(); $i++) {
         if (dnz($self->{weight}[$i])) {
            my $px = $pixelsPerDay * ($i - 1);
            my $ty = int(((($self->{trend}[$i] * $logToDisplayUnit) - $weightMin) *
                        ($extentY - ($bottomMargin + $topMargin))) / ($weightMax - $weightMin));
            my $wy = int(((($self->{weight}[$i] * $logToDisplayUnit) - $weightMin) *
                        ($extentY - ($bottomMargin + $topMargin))) / ($weightMax - $weightMin));
            my $offset = $wy - $ty;

            if (($offset < -$sinkerSize) || ($offset > $sinkerSize)) {
                 my $dy = sgn($offset);

                $img->line($bX + $px, $bY - ($ty + $dy),
                           $bX + $px, $bY - ($wy + (($offset > 0) ? -$sinkerSize : $sinkerSize)), $green);
            }

            #   Fill float/sinker with white or yellow, if it's flagged.

            for (my $j = -$sinkerSize; $j <= $sinkerSize; $j++) {
                my $dx = abs($j) - $sinkerSize;

                $img->line($bX + $px - $dx, $bY - ($wy + $j),
                           $bX + $px + $dx, $bY - ($wy + $j),
                           $self->{flag}[$i] ? $yellow : $white);
            }

            #   Trace the outline of the float/sinker in blue

            $img->line($bX + $px - $sinkerSize, $bY - $wy,
                       $bX + $px, $bY - ($wy - $sinkerSize), $blue);
            $img->line($bX + $px, $bY - ($wy - $sinkerSize),
                       $bX + $px + $sinkerSize, $bY - $wy, $blue);
            $img->line($bX + $px + $sinkerSize, $bY - $wy,
                       $bX + $px, $bY - ($wy + $sinkerSize), $blue);
            $img->line($bX + $px, $bY - ($wy + $sinkerSize),
                       $bX + $px - $sinkerSize, $bY - $wy, $blue);
        }
    }

        }
        
    for (my $plotw = $weightMin; int($plotw * 10 + 0.5) <= int($weightMax * 10 + 0.5); $plotw += $vunit) {
        my $wy = int((($plotw - $weightMin) *
                    ($extentY - ($bottomMargin + $topMargin))) / ($weightMax - $weightMin));
        main::drawText($img, editWeight($plotw, $display_unit, $dchar), 'Times', 12, 0,
            $leftMargin - 8, $bY - $wy, 'r', 'c', $black);
        if ($plotw > $weightMin) {
            $img->line($bX - $axisOffset, $bY - $wy,
                       $bX + (-$axisOffset + $tickSize), $bY - $wy, $black);
        }
#print("$plotw $wy\n");
    }


        print($outfile $img->png());

    }

    sub updateFromCGI {
        my $self = shift;
        my ($h) = @_;

        my ($change_weight, $change_rung, $change_flag, $change_comment) = (0, 0, 0, 0);
        my $days = $self->monthdays();

        for (my $d = 1; $d <= $days; $d++) {
            my $k;

            
    $k = "w$d";
    if (defined($$h{$k})) {
        my $w = $$h{$k};

        $w =~ s/,/./g;

        
    my $wa = $w;
    $wa =~ s/^\s+//;
    $wa =~ s/\s+$//;

    if (($$h{du} == WEIGHT_STONE) && ($wa !~ m/\d*\.\d*/)) {
        $wa = '';
    }

    if (($wa eq '.') || ($wa =~ m/^\.\d+$/) ||
            ($wa =~ m/^\d(\.\d*)?$/) ||
            (($$h{du} == WEIGHT_STONE) && ($wa =~ m/^\d\d\.\d*$/))) {
        my $p = 0;
        my $lw;
        for (my $j = $d - 1; $j >= 1; $j--) {
            if (defined($$h{"w$j"}) && ($$h{"w$j"} =~ m/^\d/)) {
                $lw = $$h{"w$j"};
                $lw =~ s/,/./g;
                $p = 1;
                last;
            }
        }

        if ($p) {
            if ($wa eq '.') {
                $w = $lw;
            } else {
                if ($$h{du} == WEIGHT_STONE) {
                    
    $lw =~ m/^(\d+)\s+(\d*\.?\d*)$/;
    my ($stones, $pounds) = ($1, $2);

    if ($pounds >= 10) {
        if ($wa < 4) {
            if ($wa =~ m/^\.\d+$/) {
                $pounds = int($pounds) + $wa;
            } else {
                $pounds = ((int($pounds  / 10)) * 10) + $wa;
            }
        } else {
            $pounds = $wa;
        }
    } else {
        if ($wa =~ m/^\.\d+$/) {
            $pounds = int($pounds) + $wa;
        } else {
            $pounds = $wa;
        }
    }
    $w = "$stones $pounds";
    $$h{$k} = $w;

                } else {
                    if ($wa =~ m/^\.\d+$/) {
                        $w = int($lw) + $wa;
                    } elsif ($wa =~ m/^\d(\.\d*)?$/) {
                        $w = (int($lw / 10) * 10) + $wa;
                    }
                    $$h{$k} = $w;
                }
            }
        }
    }


        $w =~ s/[^\d\s\.]//g;
        $w =~ s/^\s+//;
        $w =~ s/\s+$//;
        #   If specification is stones and pounds, convert to pounds
        if (($w ne '') && ($$h{du} == WEIGHT_STONE)) {
            if ($w =~ m/\s*(\d+)\s+([\d\.]+)/) {
                $w = ($1 * 14) + $2;
            }
        }

        if ($w ne '') {
            $w = convertWeight($w, $$h{du}, $self->{log_unit});
        }

        if (($w eq '') && (znd($self->{weight}[$d]) != 0)) {
            undef($self->{weight}[$d]);
            $change_weight++;
        } elsif (($w ne '') && ($w ne znd($self->{weight}[$d]))) {
            $self->{weight}[$d] = $w;
            $change_weight++;
        }
    }

            
    $k = $$h{"r$d"};

    if (defined($k) && ($k =~ m/^\s*([\.,\+\-])\s*$/)) {
        my $cop = $1;
        for (my $j = $d - 1; $j >= 1; $j--) {
            if (defined($$h{"r$j"}) && ($$h{"r$j"} ne '')) {
                $k = $$h{"r$j"};
                $k++ if $cop eq '+';
                $k-- if $cop eq '-';
                last;
            }
        }
    }

    if (defined($k)) {
        $k =~ s/\D//g;          #   Delete non-digit characters
        if ($k =~ m/^\d/) {
            $k = 1 if $k < 1;
            $k = RUNG_MAX if $k > RUNG_MAX;
        }
        $$h{"r$d"} = $k;

        if (($k eq '') && (znd($self->{rung}[$d]) != 0)) {
            undef($self->{rung}[$d]);
            $change_rung++;
        } elsif (($k ne '') && ($k ne znd($self->{rung}[$d]))) {
            $self->{rung}[$d] = $k;
            $change_rung++;
        }
    }

            
    if (defined($$h{"f$d"})) {
        $k = $$h{"f$d"};

        if (($k eq '') && (znd($self->{flag}[$d]) != 0)) {
            undef($self->{flag}[$d]);
            $change_flag++;
        } elsif (($k ne '') && (znd($self->{flag}[$d]) == 0)) {
            $self->{flag}[$d] = 1;
            $change_flag++;
        }
    } else {
        if (znd($self->{flag}[$d]) != 0) {
            undef($self->{flag}[$d]);
            $change_flag++;
        }
    }

            
    if (defined($$h{"c$d"})) {
        $k = $$h{"c$d"};
        if (($k eq '.') || ($k eq ',')) {
            for (my $j = $d - 1; $j >= 1; $j--) {
                if (defined($$h{"c$j"}) && ($$h{"c$j"} ne '')) {
                    $k = $$h{"c$j"};
                    $$h{"c$d"} = $k;
                    last;
                }
            }
        }
        if ($k =~ m/^\.\s+$/) {
            $k = '. ';
        } else {
            $k =~ s/\s+$//;
        }
        if (($k eq '') && defined($self->{comment}[$d])) {
            undef($self->{comment}[$d]);
            $change_comment++;
        } elsif (($k ne '') &&
            ((!defined($self->{comment}[$d])) || ($k ne $self->{comment}[$d]))) {
            $self->{comment}[$d] = $k;
            $change_comment++;
        }
    }

        }

        my $changes = $change_weight + $change_rung + $change_flag + $change_comment;

        return ($changes, $change_weight, $change_rung, $change_flag, $change_comment);
    }

    sub importCSV {
        my $self = shift;

        my $s = shift;
        my ($date, $weight, $rung, $flag, $comment) = parseCSV($s);

        #   Ignore any line without a strictly compliant date

        if ($date =~ m/^(\d\d\d\d)\-(\d\d)\-(\d\d)$/) {
            my ($yy, $mm, $dd) = ($1, $2, $3);
            if (($yy != $self->{year}) ||
                ($mm != $self->{month}) ||
                ($dd < 1) || ($dd > $self->monthdays())) {
                die("Bogus CSV import date for $self->{year}-$self->{month}: $date");
            }
            $weight =~ s/\s//g;
            $self->{weight}[$dd] = $weight if ($weight ne '');
            $rung =~ s/\s//g;
            $self->{rung}[$dd] = $rung if ($rung ne '');
            $flag =~ s/\s//g;
            $self->{flag}[$dd] = $flag if ($flag ne '');
            $self->{comment}[$dd] = $comment if ($comment ne '');
            return 1;
        }
        return 0;
    }

    sub exportCSV {
        my $self = shift;

        my ($fh) = @_;

        print $fh <<"EOD";
Date,Weight,Rung,Flag,Comment\r
StartTrend,$self->{trend_carry_forward},$self->{log_unit},$self->{last_modification_time},$self->{last_modification_time},1.0\r
EOD

        for (my $i = 1; $i <= $self->monthdays(); $i++) {
            my $csv = encodeCSV(sprintf("%04d-%02d-%02d", $self->{year}, $self->{month}, $i),
                                bnd($self->{weight}[$i]),
                                bnd($self->{rung}[$i]),
                                znd($self->{flag}[$i]),
                                (defined($self->{comment}[$i]) ? $self->{comment}[$i] : ''));
            print($fh "$csv\r\n");
        }
    }

    sub exportHDReadCSV {
        my $self = shift;

        my ($fh) = @_;

        my $tcf = sprintf("%.4f", znd($self->{trend_carry_forward}));
        my $wu = ucfirst(WEIGHT_UNITS->[$self->{log_unit}]) . 's';
        my $mon = $::monthNames[$self->{month}];
        print $fh <<"EOD";
Date,Weight,Rung,Flag,Comment
StartTrend,$tcf,$self->{log_unit},$self->{last_modification_time},$self->{last_modification_time}
EOD
        for (my $i = 1; $i <= $self->monthdays(); $i++) {
            my $cmt = '';
            if (defined($self->{comment}[$i])) {
                $cmt = $self->{comment}[$i];
                $cmt =~  s/([\x{00}-\x{1F}-\x{80}-\x{9F}\x{100}-\x{FFFF}])/sprintf("&#x%x;", ord($1))/eg;
                $cmt =~ s/"/""/g;
                if ($cmt =~ m/[\s",]/) {
                    $cmt = '"' . $cmt . '"';
                }
            }
            print($fh sprintf("%04d-%02d-%02d", $self->{year}, $self->{month}, $i) . ',' .
                      bnd($self->{weight}[$i]) . ',' .
                      bnd($self->{rung}[$i]) . ',' .
                      znd($self->{flag}[$i]) . ',' .
                      $cmt . "\n");
        }
    }

    sub exportExcelCSV {
        my $self = shift;

        my ($fh) = @_;

        
    my $tcf = $self->{trend_carry_forward};
    if ($tcf == 0) {
        for (my $i = 1; $i <= $self->monthdays(); $i++) {
            if (znd($self->{weight}[$i])) {
                $tcf = $self->{weight}[$i];
                last;
            }
        }
    }
    $tcf = sprintf("%.2f", $tcf);


        my $wu = ucfirst(WEIGHT_UNITS->[$self->{log_unit}]) . 's';
        my $mon = $::monthNames[$self->{month}];
        print $fh <<"EOD";
Date,,Weight,Trend,Variance,,Rung,Flag\r
,,,,,,,\r
,,$wu,,$mon $self->{year},,,\r
Trend carry forward:,,,$tcf,,,,\r
EOD

        my $wd = jd_to_weekday(gregorian_to_jd($self->{year}, $self->{month}, 1));

        for (my $i = 1; $i <= $self->monthdays(); $i++) {
            my $cmt = '';
            if (defined($self->{comment}[$i])) {
                $cmt = $self->{comment}[$i];
                $cmt =~  s/([\x{00}-\x{1F}-\x{80}-\x{9F}\x{100}-\x{FFFF}])/sprintf("&#x%x;", ord($1))/eg;
                $cmt =~ s/"/""/g;
                $cmt = '"' . $cmt . '"';
            }

            print($fh sprintf("%d/%d/%02d", $self->{month}, $i, $self->{year} % 100) . ',' .
                WEEKDAY_NAMES->[$wd] . ',' .
                ((bnd($self->{weight}[$i]) eq '') ? (($cmt eq '') ? '---' : $cmt) : sprintf("%.1f", $self->{weight}[$i])) . ',' .
                ((bnd($self->{trend}[$i]) eq '') ? '' : sprintf("%.1f", $self->{trend}[$i])) . ',' .
                sprintf("%.2f", znd($self->{weight}[$i]) - znd($self->{trend}[$i])) . ',' .
                sprintf("%.1f", $tcf) . ',' .
                bnd($self->{rung}[$i]) . ',' .
                (znd($self->{flag}[$i]) ? '1' : ''). "\r\n");

            $wd = ($wd + 1) % 7;
            if (znd($self->{trend}[$i])) {
                $tcf = $self->{trend}[$i];
            }
        }
    }

    sub exportXML {
        my $self = shift;

        my ($fh, $safe) = @_;

        my $wu = WEIGHT_UNITS->[$self->{log_unit}];
        my $lm = timeXML($self->{last_modification_time});
        my $nd = $self->monthdays();

        print $fh <<"EOD";
    <monthlog version="1.0">
        <properties>
            <year>$self->{year}</year>
            <month>$self->{month}</month>
            <weight-unit>$wu</weight-unit>
            <trend-carry-forward>$self->{trend_carry_forward}</trend-carry-forward>
            <last-modified>$lm</last-modified>
        </properties>
        <days ndays="$nd">
EOD

        for (my $i = 1; $i <= $self->monthdays(); $i++) {
            my $sweight = textXML('weight', bnd($self->{weight}[$i]), $safe);
            my $srung = textXML('rung', bnd($self->{rung}[$i]), $safe);
            my $sflag = textXML('flag', bnd($self->{flag}[$i]), $safe);
            my $scomment = textXML('comment', (defined($self->{comment}[$i]) ? $self->{comment}[$i] : ''), $safe);

            print $fh <<"EOD";
            <day>
                <date>$i</date>
                $sweight
                $srung
                $sflag
                $scomment
            </day>
EOD
        }
        print $fh <<"EOD";
        </days>
    </monthlog>
EOD
    }

    sub monthdays {
        my ($year, $month);

        if ($#_ == 0) {
            my $self = shift;
            ($year, $month) = ($self->{year}, $self->{month});
        } else {
            ($year, $month) = @_;
        }

        if ($year == 0) {
            return 0;
        }

        #   Thirty days hath September, ...
        my @monthdays = ( 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );

        if ($month == 2) {
            if ((($year % 4) != 0) ||
                ((($year % 100) == 0) && ($year % 400) != 0)) {
                return 28;
            }
            return 29;
        } else {
            return $monthdays[$month];
        }
    }

    sub previousMonth {
        my ($year, $month);

        if ($#_ == 0) {
            my $self = shift;
            ($year, $month) = ($self->{year}, $self->{month});
        } else {
            ($year, $month) = @_;
        }

        $month--;
        if ($month < 1) {
            $year--;
            $month = 12;
        }

        return ($year, $month);
    }

    sub nextMonth {
        my ($year, $month);

        if ($#_ == 0) {
            my $self = shift;
            ($year, $month) = ($self->{year}, $self->{month});
        } else {
            ($year, $month) = @_;
        }

        $month++;
        if ($month > 12) {
            $year++;
            $month = 1;
        }

        return ($year, $month);
    }

    sub verbose {
        my $self = shift;

        my $v;
        if ($v = shift) {
            $self->{verbose} = $v;
        }
        if ($self->{verbose}) {
            print("monthlog: Verbose = $self->{verbose}\n");
        }
        return $self->{verbose};
    }

    sub encodeComments {
        my $self = shift;

        my $mdays = $self->monthdays();
        my $enc = '';
        my @cmt = @{$self->{comment}};

        for (my $i = 1; $i <= $mdays; $i++) {
            if (defined($cmt[$i]) &&
                ($cmt[$i] ne '')) {
                $enc .= $i;                 # Comment appears on this day first
                for (my $j = $i + 1; $j <= $mdays; $j++) {
                    if (defined($cmt[$j]) &&
                        ($cmt[$i] eq $cmt[$j])) {
                        $enc .= ",$j";      # Comment also appears on this day
                        $cmt[$j] = '';      # Wipe it out since it's been handled as a duplicate
                    }
                }
                my $ct = $cmt[$i];
                $ct =~ s/"/""/g;
                $enc .= "\"$ct\"";
            }
        }
        return $enc;
    }

    sub decodeComments {
        my $self = shift;

        my $ecom = shift;

        while ($ecom =~ s/^([\d,]+)"((?:[^"]|"")+)"//) {
#print("Days: $1  Comment: ($2)\n");
            my ($days, $comment) = ($1, $2);

            $comment =~ s/""/"/g;
            while ($days =~ s/(\d+),?//) {
                $self->{comment}[$1] = $comment;
            }

        }
    }
