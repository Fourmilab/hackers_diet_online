#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    use HDiet::monthlog;

    package HDiet::Aggregator;

    use HDiet::Julian;

    require Exporter;

    our @ISA = qw(Exporter);
    our @EXPORT = ( );

    1;

    sub new {
        my $self = {};
        my ($invocant, $receiver, $weight_unit) = @_;
        my $class = ref($invocant) || $invocant;

        bless($self, $class);

        #   Initialise instance variables from constructor arguments
        $self->{receiver} = $receiver;
        $self->{weight_unit} = $weight_unit;

        return $self;
    }

    sub retrieve {
        my $self = shift;
        my ($start_jd, $end_jd, $public_only, $user_list) = @_;

        my $receive = $self->{receiver};
        my ($from_y, $from_m, $from_d) = jd_to_gregorian($start_jd);
        my ($to_y, $to_m, $to_d) = jd_to_gregorian($end_jd);
        my $sdate = sprintf("%04d-%02d-%02d", $from_y, $from_m, $from_d);
        my $edate = sprintf("%04d-%02d-%02d", $to_y, $to_m, $to_d);
        my ($naccts, $npaccts) = (0, 0);

        if (defined($user_list)) {
            my @users = @$user_list;
            for my $u (@users) {
                my $user_file_name = HDiet::user::quoteUserName($u);
                
#my $recret = 0;
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account directory /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);
    $naccts++;
    $npaccts++ if $ui->{public};
    if ((!$public_only) || $ui->{public}) {
        my ($cur_y, $cur_m, $cur_d) = ($from_y, $from_m, $from_d);
        for (my $j = $start_jd; $j <= $end_jd; ) {
            my $monkey = sprintf("%04d-%02d", $cur_y, $cur_m);
            if (-f "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") {
                open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") ||
                    die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$monkey.hdb");
                my $mlog = HDiet::monthlog->new();
                $mlog->load(\*FL);
                close(FL);
                for (my $dd = $cur_d; $dd <= $mlog->monthdays(); $dd++) {
                    my ($rw, $rt) = ($mlog->{weight}[$dd], $mlog->{trend}[$dd]);
                    $rw *= HDiet::monthlog::WEIGHT_CONVERSION->[$mlog->{log_unit}][$self->{weight_unit}]
                        if defined($rw);
                    $rt *= HDiet::monthlog::WEIGHT_CONVERSION->[$mlog->{log_unit}][$self->{weight_unit}]
                        if defined($rt);
                    &$receive($ui, $j,
                         $rw,
                         $rt,
                         $mlog->{rung}[$dd],
                         $mlog->{flag}[$dd],
                         $mlog->{comment}[$dd]);
                    $j++;
                    if ($j > $end_jd) {
                        last;
                    }
                }
            }
            $cur_m++;
            $cur_d = 1;
            if ($cur_m > 12) {
                $cur_y++;
                $cur_m = 1;
                $j = gregorian_to_jd($cur_y, $cur_m, $cur_d);
            }
        }
    }

            }
        } else {
            opendir(CD, "/server/pub/hackdiet/Users") ||
                die("Cannot open directory /server/pub/hackdiet/Users");
            for my $user_file_name (grep(!/\.\.?\z/, readdir(CD))) {
                
#my $recret = 0;
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account directory /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);
    $naccts++;
    $npaccts++ if $ui->{public};
    if ((!$public_only) || $ui->{public}) {
        my ($cur_y, $cur_m, $cur_d) = ($from_y, $from_m, $from_d);
        for (my $j = $start_jd; $j <= $end_jd; ) {
            my $monkey = sprintf("%04d-%02d", $cur_y, $cur_m);
            if (-f "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") {
                open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") ||
                    die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$monkey.hdb");
                my $mlog = HDiet::monthlog->new();
                $mlog->load(\*FL);
                close(FL);
                for (my $dd = $cur_d; $dd <= $mlog->monthdays(); $dd++) {
                    my ($rw, $rt) = ($mlog->{weight}[$dd], $mlog->{trend}[$dd]);
                    $rw *= HDiet::monthlog::WEIGHT_CONVERSION->[$mlog->{log_unit}][$self->{weight_unit}]
                        if defined($rw);
                    $rt *= HDiet::monthlog::WEIGHT_CONVERSION->[$mlog->{log_unit}][$self->{weight_unit}]
                        if defined($rt);
                    &$receive($ui, $j,
                         $rw,
                         $rt,
                         $mlog->{rung}[$dd],
                         $mlog->{flag}[$dd],
                         $mlog->{comment}[$dd]);
                    $j++;
                    if ($j > $end_jd) {
                        last;
                    }
                }
            }
            $cur_m++;
            $cur_d = 1;
            if ($cur_m > 12) {
                $cur_y++;
                $cur_m = 1;
                $j = gregorian_to_jd($cur_y, $cur_m, $cur_d);
            }
        }
    }

            }
            closedir(CD);
        }

        return ($naccts, $npaccts);
    }
