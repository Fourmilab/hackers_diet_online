#! /usr/bin/perl

    
=head1 NAME

HackDiet - Hacker's Diet Online Database Interface

=head1 SYNOPSIS

B<HackDiet.pl>
[I<options>]

=head1 DESCRIPTION


=head1 OPTIONS

All options may be abbreviated to their shortest
unambiguous prefix.

=over 5

=item B<--copyright>

Display copyright information.

=item B<--help>

Display how to call information.


=item B<--verbose>

Generate verbose output to indicate what's going on.


=item B<--version>

Display version number.

=back
=cut


=head1 VERSION

This is B<HackDiet> version 1.0, released August 2007.
The current version of this program is always posted at
http://www.fourmilab.ch/hackdiet/online/.

=head1 AUTHOR

John Walker
(http://www.fourmilab.ch/)

=head1 BUGS

Please report any bugs to bugs@fourmilab.ch.

=head1 SEE ALSO

B<nuweb> (http://nuweb.sourceforge.net/),
S<Literate Programming> (http://www.literateprogramming.com/).

=head1 COPYRIGHT

This program is in the public domain.

=cut


    
    
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





    
    $SIG{INT} =
        sub {
            my $i = 0;
            my ($pkg, $file, $line);
            print(STDERR "Termination by INT signal.  Stack trace:\n");
            while (($pkg, $file, $line) = caller($i)) {
                print(STDERR "    $i:  Package $pkg  File $file  Line $line\n");
                $i++;
            }
            die("INT received");
        };


    #   Override site address in otherwise relative URLs
    my $homeBase = "/hackdiet/online";

    my $dataBase = "/server/pub/hackdiet";

    
    use Getopt::Long;

    GetOptions(
                'copyright' => sub { print("This program is in the public domain.\n"); exit(0); },
                'help' => sub { &print_command_line_help; exit(0); },
                'test' => \$testmode,
                'verbose' => \$verbose,
                'version' => sub { print("Version 1.0, August 2007\n"); exit(0); }
              );


    
    {
        my $ok = 1;

        if (!$ok) {
            die("Invalid option specification(s)");
        }
    }


    if ($#ARGV != -1) {
        &print_command_line_help;
        exit(0);
    }

    binmode(STDIN, ":utf8");

    my $fh = \*STDOUT;

    my %CGIargs = &parse_cgi_arguments;

    my $inHTML = 0;
    my $readOnly = 0;
    my $cookieLogin = 0;
    my $cookieUser;
    our @HTTP_header;
    our @headerScripts;

    
    my %browsing_user_requests = (
        account => 1,
        browsepub => 1,
        calendar => 1,
        chart => 1,
        dietcalc => 1,
        do_public_browseacct => 1,
        histchart => 1,
        histreq => 1,
        log => 1,
        logout => 1,
        quitbrowse => 1,
        trendan => 1
    );

    
    if (!defined $CGIargs{q}) {
        for my $qk (keys(%CGIargs)) {
            if ($qk =~ m/^(\w+)=(.*)$/) {
                 $CGIargs{$1} = $2;
            }
        }
    }

    
    my ($timeZoneOffset, $userTime) = ('unknown', time());
    if (defined($CGIargs{HDiet_tzoffset})) {
        if ($CGIargs{HDiet_tzoffset} =~ m/^\-?\d+$/) {
            $timeZoneOffset = $CGIargs{HDiet_tzoffset};
            if (abs($timeZoneOffset) > (25 * 60)) {
                $timeZoneOffset = 'unknown';
            } else {
                $userTime -= $timeZoneOffset * 60;
            }
        }
    }
    my $tzOff = "&amp;HDiet_tzoffset=$timeZoneOffset";
    my ($userYear, $userMon, $userMday, $userHour, $userMin, $userSec) =
        unix_time_to_civil_date_time($userTime);
#if ($CGIargs{HDiet_tzoffset}) {
#print(STDERR "Local time($CGIargs{HDiet_tzoffset}:$timeZoneOffset): $userYear-$userMon-$userMday $userHour:$userMin:$userSec\n");
#}

    
    if (defined $CGIargs{q}) {
        if ($CGIargs{q} eq 'chart') {
            
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    if (!(($CGIargs{m} =~ m/^(\d\d\d\d)\-(\d\d)$/) &&
        ($1 >= 1980) && ($1 <= ((unix_time_to_civil_date_time($userTime))[0] + 1)) &&
        ($2 >= 1) && ($2 <= 12))) {
        if (!$inHTML) {
            if ($ENV{'REQUEST_METHOD'}) {
                
    print($fh "Content-type: text/html\r\n\r\n");

            }
            $inHTML = 1;
        }
        write_XHTML_prologue($fh, $homeBase, "Create New User Account", undef, $session->{handheld});
        my $qm = quoteHTML($CGIargs{m});
        print $fh <<"EOD";
<h1 class="c">Invalid Log Date Specification</h1>

<p class="justified">
Your request specified an invalid date:
</p>

<p class="centred">
<tt>$qm</tt>
</p>

<p class="justified">
for a monthly log.  Dates must be specified as &ldquo;<i>YYYY</i><tt>-</tt><i>MM</i>&rdquo;.
</p>


<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account home page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        last;
    }


    
    
    if (!(($CGIargs{m} =~ m/^(\d\d\d\d)\-(\d\d)$/) &&
        ($1 >= 1980) && ($1 <= ((unix_time_to_civil_date_time($userTime))[0] + 1)) &&
        ($2 >= 1) && ($2 <= 12))) {
        if (!$inHTML) {
            if ($ENV{'REQUEST_METHOD'}) {
                
    print($fh "Content-type: text/html\r\n\r\n");

            }
            $inHTML = 1;
        }
        write_XHTML_prologue($fh, $homeBase, "Create New User Account", undef, $session->{handheld});
        my $qm = quoteHTML($CGIargs{m});
        print $fh <<"EOD";
<h1 class="c">Invalid Log Date Specification</h1>

<p class="justified">
Your request specified an invalid date:
</p>

<p class="centred">
<tt>$qm</tt>
</p>

<p class="justified">
for a monthly log.  Dates must be specified as &ldquo;<i>YYYY</i><tt>-</tt><i>MM</i>&rdquo;.
</p>


<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account home page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        last;
    }


    my $mlog = HDiet::monthlog->new();
    if (-f "/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb") {
        open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb") ||
            die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb");
        $mlog->load(\*FL);
        close(FL);
    } else {
        $mlog->{login_name} = $user_name;
        $CGIargs{m} =~ m/(^\d+)\-(\d+)$/;
        my ($yy, $mm) = ($1, $2);
        $mlog->{year} = $yy + 0;
        $mlog->{month} = $mm + 0;
        $mlog->{log_unit} = $ui->{log_unit};
        $mlog->{last_modification_time} = 0;
        $mlog->{trend_carry_forward} = 0;
    }
    
    if ($mlog->{trend_carry_forward} == 0) {
        my $cmon = sprintf("%04d-%02d", $mlog->{year}, $mlog->{month});
        my @logs = $ui->enumerateMonths();
        for (my $m = $#logs; $m >= 0; $m--) {
            if ($logs[$m] lt $cmon) {
                my $llog = HDiet::monthlog->new();
                open(LL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$m].hdb") ||
                    die("Cannot open previous monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$m].hdb");
                $llog->load(\*LL);
                close(LL);
                for (my $d = $llog->monthdays(); $d >= 1; $d--) {
                    if ($llog->{trend}[$d]) {
                        $mlog->{trend_carry_forward} = $llog->{trend}[$d] *
                            HDiet::monthlog::WEIGHT_CONVERSION->[$llog->{log_unit}][$mlog->{log_unit}];;
                        last;
                    }
                }
                last;
            }
        }
    }



    
    print($fh "Content-type: image/png\r\n\r\n");


    $CGIargs{width} = ($session->{handheld} ? 320 : 640) if !defined $CGIargs{width};
    $CGIargs{height} = ($session->{handheld} ? 240 : 480) if !defined $CGIargs{height};

    my @dcalc;
    if ($ui->{plot_diet_plan}) {
        @dcalc = $ui->dietPlanLimits();
    }

    $mlog->plotChart($fh, $CGIargs{width}, $CGIargs{height},
        $ui->{display_unit}, $ui->{decimal_character}, \@dcalc,
        $CGIargs{print}, $CGIargs{mono});

    update_last_transaction($user_file_name) if !$readOnly;
    exit(0);

        } elsif ($CGIargs{q} eq 'histchart') {
            
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    my $hc = HDiet::history->new($ui, $user_file_name);

    
    print($fh "Content-type: image/png\r\n\r\n");


    $CGIargs{width} = 640 if !defined $CGIargs{width};
    $CGIargs{height} = 480 if !defined $CGIargs{height};

    my ($start_date, $end_date);

###### FIXME:  Sanity check arguments and default if not specified.
    $start_date = $CGIargs{start} if defined($CGIargs{start});
    $end_date = $CGIargs{end} if defined($CGIargs{end});

    my @dcalc;
    if ($ui->{plot_diet_plan}) {
        @dcalc = $ui->dietPlanLimits();
    }

    $hc->drawChart($fh, $start_date, $end_date, $CGIargs{width}, $CGIargs{height}, \@dcalc,
        $CGIargs{print}, $CGIargs{mono});

    update_last_transaction($user_file_name);
    exit(0);

        } elsif ($CGIargs{q} eq 'csvout') {
            
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    
    if (!(($CGIargs{m} =~ m/^(\d\d\d\d)\-(\d\d)$/) &&
        ($1 >= 1980) && ($1 <= ((unix_time_to_civil_date_time($userTime))[0] + 1)) &&
        ($2 >= 1) && ($2 <= 12))) {
        if (!$inHTML) {
            if ($ENV{'REQUEST_METHOD'}) {
                
    print($fh "Content-type: text/html\r\n\r\n");

            }
            $inHTML = 1;
        }
        write_XHTML_prologue($fh, $homeBase, "Create New User Account", undef, $session->{handheld});
        my $qm = quoteHTML($CGIargs{m});
        print $fh <<"EOD";
<h1 class="c">Invalid Log Date Specification</h1>

<p class="justified">
Your request specified an invalid date:
</p>

<p class="centred">
<tt>$qm</tt>
</p>

<p class="justified">
for a monthly log.  Dates must be specified as &ldquo;<i>YYYY</i><tt>-</tt><i>MM</i>&rdquo;.
</p>


<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account home page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        last;
    }


    my $mlog = HDiet::monthlog->new();
    if (-f "/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb") {
        open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb") ||
            die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb");
        $mlog->load(\*FL);
        close(FL);
    } else {
        $mlog->{login_name} = $user_name;
        $CGIargs{m} =~ m/(^\d+)\-(\d+)$/;
        my ($yy, $mm) = ($1, $2);
        $mlog->{year} = $yy + 0;
        $mlog->{month} = $mm + 0;
        $mlog->{log_unit} = $ui->{log_unit};
        $mlog->{last_modification_time} = 0;
        $mlog->{trend_carry_forward} = 0;
    }
    
    if ($mlog->{trend_carry_forward} == 0) {
        my $cmon = sprintf("%04d-%02d", $mlog->{year}, $mlog->{month});
        my @logs = $ui->enumerateMonths();
        for (my $m = $#logs; $m >= 0; $m--) {
            if ($logs[$m] lt $cmon) {
                my $llog = HDiet::monthlog->new();
                open(LL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$m].hdb") ||
                    die("Cannot open previous monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$m].hdb");
                $llog->load(\*LL);
                close(LL);
                for (my $d = $llog->monthdays(); $d >= 1; $d--) {
                    if ($llog->{trend}[$d]) {
                        $mlog->{trend_carry_forward} = $llog->{trend}[$d] *
                            HDiet::monthlog::WEIGHT_CONVERSION->[$llog->{log_unit}][$mlog->{log_unit}];;
                        last;
                    }
                }
                last;
            }
        }
    }



    print($fh "Content-type: text/csv; charset=iso-8859-1\r\n");
    print($fh "Content-disposition: attachment; filename=\"$CGIargs{m}.csv\"\r\n");
    print($fh "\r\n");

    $mlog->exportCSV($fh);

    exit(0);

        } elsif ($CGIargs{q} eq 'xmlout') {
            
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    
    if (!(($CGIargs{m} =~ m/^(\d\d\d\d)\-(\d\d)$/) &&
        ($1 >= 1980) && ($1 <= ((unix_time_to_civil_date_time($userTime))[0] + 1)) &&
        ($2 >= 1) && ($2 <= 12))) {
        if (!$inHTML) {
            if ($ENV{'REQUEST_METHOD'}) {
                
    print($fh "Content-type: text/html\r\n\r\n");

            }
            $inHTML = 1;
        }
        write_XHTML_prologue($fh, $homeBase, "Create New User Account", undef, $session->{handheld});
        my $qm = quoteHTML($CGIargs{m});
        print $fh <<"EOD";
<h1 class="c">Invalid Log Date Specification</h1>

<p class="justified">
Your request specified an invalid date:
</p>

<p class="centred">
<tt>$qm</tt>
</p>

<p class="justified">
for a monthly log.  Dates must be specified as &ldquo;<i>YYYY</i><tt>-</tt><i>MM</i>&rdquo;.
</p>


<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account home page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        last;
    }


    my $mlog = HDiet::monthlog->new();
    if (-f "/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb") {
        open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb") ||
            die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb");
        $mlog->load(\*FL);
        close(FL);
    } else {
        $mlog->{login_name} = $user_name;
        $CGIargs{m} =~ m/(^\d+)\-(\d+)$/;
        my ($yy, $mm) = ($1, $2);
        $mlog->{year} = $yy + 0;
        $mlog->{month} = $mm + 0;
        $mlog->{log_unit} = $ui->{log_unit};
        $mlog->{last_modification_time} = 0;
        $mlog->{trend_carry_forward} = 0;
    }
    
    if ($mlog->{trend_carry_forward} == 0) {
        my $cmon = sprintf("%04d-%02d", $mlog->{year}, $mlog->{month});
        my @logs = $ui->enumerateMonths();
        for (my $m = $#logs; $m >= 0; $m--) {
            if ($logs[$m] lt $cmon) {
                my $llog = HDiet::monthlog->new();
                open(LL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$m].hdb") ||
                    die("Cannot open previous monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$m].hdb");
                $llog->load(\*LL);
                close(LL);
                for (my $d = $llog->monthdays(); $d >= 1; $d--) {
                    if ($llog->{trend}[$d]) {
                        $mlog->{trend_carry_forward} = $llog->{trend}[$d] *
                            HDiet::monthlog::WEIGHT_CONVERSION->[$llog->{log_unit}][$mlog->{log_unit}];;
                        last;
                    }
                }
                last;
            }
        }
    }



    binmode($fh, ":utf8");
    print($fh "Content-type: application/xml; charset=utf-8\r\n");
    print($fh "Content-disposition: attachment; filename=\"$CGIargs{m}.xml\"\r\n");
    print($fh "\r\n");

    generateXMLprologue($fh);
    $mlog->exportXML($fh, 1);
    generateXMLepilogue($fh);

    exit(0);

        } elsif ($CGIargs{q} eq 'backup') {
            
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);


    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    my $nlogs = `ls -1 /server/pub/hackdiet/Users/$user_file_name/????-??.hdb 2>/dev/null | wc -l`;
    chomp($nlogs);

    if ($nlogs > 0) {
        my ($year, $mon, $mday, $hour, $min, $sec) =
            unix_time_to_civil_date_time($userTime);
        my $date = sprintf("%04d-%02d-%02d", $year, $mon, $mday);

        print($fh "Content-type: application/zip\r\n");
        print($fh "Content-disposition: attachment; filename=\"hackdiet_log_backup_$date.zip\"\r\n");
        print($fh "\r\n");

        system("zip -q -j - /server/pub/hackdiet/Users/$user_file_name/????-??.hdb");
        exit(0);
    }


    print($fh "Content-type: text/html\r\n\r\n");

write_XHTML_prologue($fh, $homeBase, "Download backup copy", undef, $session->{handheld});
generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);


    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


print $fh <<"EOD";
<h1 class="c">You have no logs to back up!</h1>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=log&amp;s=$session->{session_id}$tzOff">Back to monthly log</a></h4>
EOD
write_XHTML_epilogue($fh, $homeBase);

    update_last_transaction($user_file_name) if !$readOnly;
    exit(0);

        } elsif ($CGIargs{q} eq 'do_exportdb') {
            
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    my $hist = HDiet::history->new($ui, $user_file_name);
    my ($s_y, $s_m, $s_d) = $hist->firstDay();
    my $s_jd = gregorian_to_jd($s_y, $s_m, $s_d);
    my ($l_y, $l_m, $l_d) = $hist->lastDay();
    my $l_jd = gregorian_to_jd($l_y, $l_m, $l_d);


    $CGIargs{from_d} = 1;
    $CGIargs{to_d} = 31;
    
    my $custom = $CGIargs{period} && ($CGIargs{period} eq 'c');
    my ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd,
        $cust_end_y, $cust_end_m, $cust_end_d,$cust_end_jd);
    if ($custom) {
        ($cust_start_y, $cust_start_m, $cust_start_d) = ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d});
        $cust_start_jd = gregorian_to_jd($cust_start_y, $cust_start_m, $cust_start_d);
        ($cust_end_y, $cust_end_m, $cust_end_d) = ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d});
        $cust_end_jd = gregorian_to_jd($cust_end_y, $cust_end_m, $cust_end_d);

        if ($cust_end_jd != $cust_start_jd) {
            #   If start or end of interval is outside the database,
            #   constrain it to the  first or last entry.
            if (($cust_start_jd < $s_jd) || ($cust_start_jd > $l_jd)) {
                ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd) =
                    ($s_y, $s_m, $s_d, $s_jd);
               ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d}) =
                    ($cust_start_y, $cust_start_m, $cust_start_d);
            }
            if (($cust_end_jd < $s_jd) || ($cust_end_jd > $l_jd)) {
                ($cust_end_y, $cust_end_m, $cust_end_d, $cust_end_jd) =
                    ($l_y, $l_m, $l_d, $l_jd);
                ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d}) =
                    ($cust_end_y, $cust_end_m, $cust_end_d);
            }

            #   If end of interval is before start, reverse them
            if ($cust_end_jd < $cust_start_jd) {
                my @temp = ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd);
                ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd) =
                    ($cust_end_y, $cust_end_m, $cust_end_d, $cust_end_jd);
                ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d}) =
                    ($cust_start_y, $cust_start_m, $cust_start_d);
                ($cust_end_y, $cust_end_m, $cust_end_d, $cust_end_jd) = @temp;
                ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d}) =
                    ($cust_end_y, $cust_end_m, $cust_end_d);
            }
        } else {
            $custom = 0;                # Void interval disables custom display
            $CGIargs{period} = '';
        }
    }


    my ($start_ym, $end_ym) = ("0000-00", "9999-99");

    if ($custom) {
        $start_ym = sprintf("%04d-%02d", $cust_start_y, $cust_start_m);
        $end_ym = sprintf("%04d-%02d", $cust_end_y, $cust_end_m);
    }

    $CGIargs{format} = '?' if !$CGIargs{format};

    if ($CGIargs{format} eq 'xml') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    binmode($fh, ":utf8");

#my $oldfh = select $fh; $| = 1; select $oldfh;
    print($fh "Content-type: application/xml; charset=utf-8\r\n");
    print($fh "Content-disposition: attachment; filename=\"hackdiet_db.xml\"\r\n");
    print($fh "\r\n");

    generateXMLprologue($fh);

    my $ep = timeXML(time());

    print $fh <<"EOD";
    <epoch>$ep</epoch>
    <account version="1.0">
EOD
    $ui->exportUserInformationXML($fh);
    $ui->exportPreferencesXML($fh);
    $ui->exportDietPlanXML($fh);
    print $fh <<"EOD";
    </account>
EOD

    my @logs = $ui->enumerateMonths();

    print $fh <<"EOD";
    <monthlogs version="1.0">
EOD
    for (my $i = 0; $i <= $#logs; $i++) {
        if (($logs[$i] ge $start_ym) && ($logs[$i] le $end_ym)) {
            my $mlog = HDiet::monthlog->new();
            open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb") ||
                die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb");
            $mlog->load(\*FL);
            close(FL);

            $mlog->exportXML($fh, 1);

            undef($mlog);
        }
    }
    print $fh <<"EOD";
    </monthlogs>
EOD

    generateXMLepilogue($fh);
    exit(0);

    } elsif ($CGIargs{format} eq 'csv') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    print($fh "Content-type: text/csv; charset=iso-8859-1\r\n");
    print($fh "Content-disposition: attachment; filename=\"hackdiet_db.csv\"\r\n");
    print($fh "\r\n");

    print($fh encodeCSV("Epoch", timeXML(time())), "\r\n");

    print($fh encodeCSV("User", "1.0", $ui->{login_name},
        $ui->{first_name}, $ui->{middle_name}, $ui->{last_name},
        $ui->{e_mail}, timeXML($ui->{account_created})), "\r\n");

    print($fh encodeCSV("Preferences", "1.0",
        HDiet::monthlog::WEIGHT_UNITS->[$ui->{log_unit}],
        HDiet::monthlog::WEIGHT_UNITS->[$ui->{display_unit}],
        HDiet::monthlog::ENERGY_UNITS->[$ui->{energy_unit}],
        $ui->{current_rung},
        $ui->{decimal_character}), "\r\n");

    my $at = timeXML($ui->{calc_start_date});

    print($fh encodeCSV("Diet-Plan", "1.0",
        $ui->{calc_calorie_balance},
        $ui->{calc_start_weight},
        $ui->{calc_goal_weight},
        $at,
        $ui->{plot_diet_plan}), "\r\n");

    my @logs = $ui->enumerateMonths();

    for (my $i = 0; $i <= $#logs; $i++) {
        if (($logs[$i] ge $start_ym) && ($logs[$i] le $end_ym)) {
            my $mlog = HDiet::monthlog->new();
            open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb") ||
                die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb");
            $mlog->load(\*FL);
            close(FL);

            $mlog->exportCSV($fh);

            undef($mlog);
        }
    }
    exit(0);

    } elsif ($CGIargs{format} eq 'palm') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    print($fh "Content-type: text/csv; charset=iso-8859-1\r\n");
    print($fh "Content-disposition: attachment; filename=\"hackdiet_db.csv\"\r\n");
    print($fh "\r\n");

    my @logs = $ui->enumerateMonths();

    for (my $i = 0; $i <= $#logs; $i++) {
        if (($logs[$i] ge $start_ym) && ($logs[$i] le $end_ym)) {
            my $mlog = HDiet::monthlog->new();
            open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb") ||
                die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb");
            $mlog->load(\*FL);
            close(FL);

            $mlog->exportHDReadCSV($fh);

            undef($mlog);
        }
    }
    exit(0);

    } elsif ($CGIargs{format} eq 'excel') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    print($fh "Content-type: text/csv; charset=iso-8859-1\r\n");
    print($fh "Content-disposition: attachment; filename=\"hackdiet_db.csv\"\r\n");
    print($fh "\r\n");

    my @logs = $ui->enumerateMonths();

    for (my $i = 0; $i <= $#logs; $i++) {
        if (($logs[$i] ge $start_ym) && ($logs[$i] le $end_ym)) {
            my $mlog = HDiet::monthlog->new();
            open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb") ||
                die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$i].hdb");
            $mlog->load(\*FL);
            close(FL);

            $mlog->exportExcelCSV($fh);

            undef($mlog);
        }
    }
    exit(0);

    } else {
    print $fh <<"EOD";
<h1>Invalid format specified for database export.</h1>
EOD
    }

    
    print($fh "Content-type: text/html\r\n\r\n");

    write_XHTML_prologue($fh, $homeBase, "Export Log Database", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Back to account page</a></h4>
EOD
    write_XHTML_epilogue($fh, $homeBase);

        }
    }


requeue:
    binmode(STDOUT, ":utf8");

    #   Emit Content-type if we were invoked as a CGI program
    if ($ENV{'REQUEST_METHOD'}) {
        
    print($fh "Content-type: text/html\r\n\r\n");

    }

    $inHTML = 1;

    while (1) {
        
    
    if ((!defined $CGIargs{q}) ||
        ($CGIargs{q} eq 'login') ||
        ($CGIargs{q} eq 'newlogin')) {
        
    $CGIargs{HDiet_handheld} = 'y' if $CGIargs{handheld};

    if ((!defined($CGIargs{q})) || ($CGIargs{q} ne 'newlogin')) {
        $cookieUser = testCookiePresent('HDiet');
        if (defined($cookieUser)) {
#print(STDERR "A cookie was present for ($cookieUser)\n");
            $cookieLogin = 1;
            $CGIargs{q} = 'validate_user';
            next;
        }
    }

    write_XHTML_prologue($fh, $homeBase, "Please Sign In", " checkSecure();", $CGIargs{HDiet_handheld});
    print $fh <<"EOD";
<h1 class="c">Please Sign In</h1>
EOD
    $CGIargs{HDiet_username} = '' if !defined($CGIargs{HDiet_username});
    my $u = HDiet::user->new($CGIargs{HDiet_username});
    $u->login_form($fh, $tzOff, $CGIargs{HDiet_handheld}, $CGIargs{HDiet_remember});

    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'validate_user') {
        
    if (defined($CGIargs{new})) {
        
    write_XHTML_prologue($fh, $homeBase, "Create New Account", undef, $CGIargs{HDiet_handheld});

    print $fh <<"EOD";
<h1 class="c">Create New Account</h1>
<form id="Hdiet_newacct" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
EOD

    
    if ($CGIargs{HDiet_handheld}) {
        print $fh <<"EOD";
<div><input type="hidden" name="HDiet_handheld" value="y" /></div>
EOD
    }


    my $u = HDiet::user->new($CGIargs{HDiet_username});
    $u->new_account_form($fh);
    print $fh <<"EOD";
<p class="mlog_buttons">
<input type="hidden" name="q" value="new_account" />
<input type="submit" name="login" value=" Create Account " tabindex="19" />
&nbsp;
<input type="reset" value=" Clear Form " tabindex="20" />
</p>
</form>
EOD
    write_XHTML_epilogue($fh, $homeBase);

    } else {

        #   If no user name given, re-issue login form
        if ((!$cookieLogin) && ((!defined($CGIargs{HDiet_username})) ||
            ($CGIargs{HDiet_username} eq ''))) {
            $CGIargs{q} = 'login';
            next;
        }

        my ($user_file_name, $ui);

        if ($cookieLogin) {
            $user_file_name = quoteUserName($cookieUser);
            if (!(-f "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu")
                || (!open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu"))) {
                
    
    my @lt = localtime(time());
    my $ct = sprintf("%s %d %02d:%02d:%02d",
        MONTH_ABBREVIATIONS->[$lt[4]], $lt[3], $lt[2], $lt[1], $lt[0]);

    openlog("HackDiet", "pid", "LOG_AUTH");
    syslog("info",
        "$ENV{REMOTE_ADDR}: (1) $ct $ENV{SERVER_NAME} HackDiet(pam_unix)[$$]: " .
        "authentication failure; logname= uid=0 euid=0 tty=http " .
        "ruser='$user_file_name' rhost=$ENV{REMOTE_ADDR}");
    closelog();

    $CGIargs{HDiet_handheld} = 'y' if $CGIargs{handheld};
    write_XHTML_prologue($fh, $homeBase, "Please Sign In", " checkSecure();", $CGIargs{HDiet_handheld});
    print $fh <<"EOD";
<h1 class="c">Sign In Invalid: Incorrect User Name or Password</h1>
<h1 class="c">Please Sign In</h1>
EOD
    my $u = HDiet::user->new();
    $u->login_form($fh, $tzOff, $CGIargs{HDiet_handheld}, $CGIargs{HDiet_remember});
    write_XHTML_epilogue($fh, $homeBase);
    last;

            }
            $ui = HDiet::user->new();
            $ui->load(\*FU);
            close(FU);
            $CGIargs{HDiet_username} = $ui->{login_name};
            $CGIargs{HDiet_remember} = 'y';
        } else {
            
    #   Verify user account directory exists and contains
    #   valid user information file.
    $user_file_name = quoteUserName($CGIargs{HDiet_username});
    if (!(-f "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu")
        || (!open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu"))) {
        
    
    my @lt = localtime(time());
    my $ct = sprintf("%s %d %02d:%02d:%02d",
        MONTH_ABBREVIATIONS->[$lt[4]], $lt[3], $lt[2], $lt[1], $lt[0]);

    openlog("HackDiet", "pid", "LOG_AUTH");
    syslog("info",
        "$ENV{REMOTE_ADDR}: (1) $ct $ENV{SERVER_NAME} HackDiet(pam_unix)[$$]: " .
        "authentication failure; logname= uid=0 euid=0 tty=http " .
        "ruser='$user_file_name' rhost=$ENV{REMOTE_ADDR}");
    closelog();

    $CGIargs{HDiet_handheld} = 'y' if $CGIargs{handheld};
    write_XHTML_prologue($fh, $homeBase, "Please Sign In", " checkSecure();", $CGIargs{HDiet_handheld});
    print $fh <<"EOD";
<h1 class="c">Sign In Invalid: Incorrect User Name or Password</h1>
<h1 class="c">Please Sign In</h1>
EOD
    my $u = HDiet::user->new();
    $u->login_form($fh, $tzOff, $CGIargs{HDiet_handheld}, $CGIargs{HDiet_remember});
    write_XHTML_epilogue($fh, $homeBase);
    last;

    }

    #   Read user account information and check password
    $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);
    if (($CGIargs{HDiet_password} eq '') && $ui->{read_only}) {
        $readOnly = 1;
    } elsif ($CGIargs{HDiet_password} ne $ui->{password}) {
        
    
    my @lt = localtime(time());
    my $ct = sprintf("%s %d %02d:%02d:%02d",
        MONTH_ABBREVIATIONS->[$lt[4]], $lt[3], $lt[2], $lt[1], $lt[0]);

    openlog("HackDiet", "pid", "LOG_AUTH");
    syslog("info",
        "$ENV{REMOTE_ADDR}: (1) $ct $ENV{SERVER_NAME} HackDiet(pam_unix)[$$]: " .
        "authentication failure; logname= uid=1 euid=0 tty=http " .
        "ruser='$user_file_name' rhost=$ENV{REMOTE_ADDR}");
    closelog();

    $CGIargs{HDiet_handheld} = 'y' if $CGIargs{handheld};
    write_XHTML_prologue($fh, $homeBase, "Please Sign In", " checkSecure();", $CGIargs{HDiet_handheld});
    print $fh <<"EOD";
<h1 class="c">Sign In Invalid: Incorrect User Name or Password</h1>
<h1 class="c">Please Sign In</h1>
EOD
    my $u = HDiet::user->new();
    $u->login_form($fh, $tzOff, $CGIargs{HDiet_handheld}, $CGIargs{HDiet_remember});
    write_XHTML_epilogue($fh, $homeBase);
    append_history($user_file_name, 10);
    last;

    }

        }

        
    if ((!$readOnly) && (-f "/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda")
        && open(FS, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda")) {
        my $asn = load_active_session(\*FS);
        close(FS);
        unlink("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
        clusterDelete("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
        unlink("/server/pub/hackdiet/Sessions/$asn.hds");
        clusterDelete("/server/pub/hackdiet/Sessions/$asn.hds");
        append_history($user_file_name, 3);
    }


        
    #   Create new session and add file to session directory
    my $s = HDiet::session->new($CGIargs{HDiet_username});
    $s->{read_only} = $readOnly;
    $s->{handheld} = 1 if $CGIargs{HDiet_handheld};
    $s->{cookie} = $cookieLogin;
    open(FS, ">:utf8", "/server/pub/hackdiet/Sessions/$s->{session_id}.hds") ||
        die("Cannot create session file /server/pub/hackdiet/Sessions/$s->{session_id}.hds");
    $s->save(\*FS);
    close(FS);
    clusterCopy("/server/pub/hackdiet/Sessions/$s->{session_id}.hds");

    #   Add the ActiveSession.hda back-link to the user directory
    if (!$readOnly) {
        open(FS, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda") ||
            die("Cannot create active session file /server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
        $s->save_active_session(\*FS);
        close(FS);
        clusterCopy("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
    }


        
    #   Update the date and time of the last login by this user
    if ($readOnly) {
        open(FL, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/LastLogin.hdl") ||
           die("Cannot create last login file /server/pub/hackdiet/Users/$user_file_name/LastLogin.hdl");
        print FL <<"EOD";
1
$s->{login_time}
EOD
        close(FL);
        clusterCopy("/server/pub/hackdiet/Users/$user_file_name/LastLogin.hdl");

        update_last_transaction($user_file_name);
    }


        
    append_history($user_file_name, 1, "$s->{handheld},$s->{cookie}") if !$readOnly;


        
    if (!$ui->{read_only}) {
        if ($CGIargs{HDiet_remember}) {
            testCookiePresent('HDiet');
            if (1) {
                push(@headerScripts,
                    "function setCookie() {",
                    "    document.cookie = '" . storeCookie($ui) . "';",
                    "}");
            } else {
                push(@HTTP_header, "Set-Cookie: " . storeCookie($ui));
            }
        } else {
            my $cname = 'HDiet';
            if (defined(testCookiePresent($cname)) ||
                (defined($ENV{HTTP_COOKIE}) &&
                ($ENV{HTTP_COOKIE} =~ m/$cname=([0-9FGJKQW]{48})/))) {
#print(STDERR "Revoking cookie $ENV{HTTP_COOKIE}\n");
                my $excook = HDiet::cookie->new();
                if (1) {
                    push(@headerScripts,
                        "function setCookie() {\n",
                        "    document.cookie = '" . $excook->expireCookie($cname) . "';\n",
                        "}\n");
                } else {
                    push(@HTTP_header, "Set-Cookie: " . $excook->expireCookie($cname));
                }
            }
        }
    }


        #   Queue the transaction to display the current month's log for this user

        %CGIargs = (
            q => "log",
            s => $s->{session_id},
            m => "now",
            HDiet_tzoffset => $timeZoneOffset
        );
        next;
    }

    } elsif ($CGIargs{q} eq 'relogin') {
        
    $CGIargs{HDiet_handheld} = 'y' if $CGIargs{handheld};
    write_XHTML_prologue($fh, $homeBase, "Please Sign In", " checkSecure();", $CGIargs{HDiet_handheld});
    print $fh <<"EOD";
<h1 class="c">Your session has timed out or has been ended.</h1>
<h1 class="c">Please Sign In Again</h1>
EOD
    my $u = HDiet::user->new();
    $u->login_form($fh, $tzOff, $CGIargs{HDiet_handheld}, $CGIargs{HDiet_remember});
    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'logout') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);


    #   Delete active session file
    unlink("/server/pub/hackdiet/Sessions/$CGIargs{s}.hds");
    clusterDelete("/server/pub/hackdiet/Sessions/$CGIargs{s}.hds");

    if (!$readOnly) {
        unlink("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
        clusterDelete("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
        append_history($user_file_name, 2);
    }

    #   Return user to login screen
    %CGIargs = (
        q => "newlogin",
    );
    $CGIargs{HDiet_handheld} = 'y' if $session->{handheld};
    next;

    } elsif ($CGIargs{q} eq 'wipedb') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    my @months = $ui->enumerateMonths();
    my $nmonths = $#months + 1;
    my $mont = 'month' . (($nmonths != 1) ? 's' : '');

    write_XHTML_prologue($fh, $homeBase, "Delete Entire Database", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


     print $fh <<"EOD";
<h1 class="c">Delete Entire Log Database</h1>
EOD

    if ($nmonths == 0) {
        print $fh <<"EOD";
<h3>You have no logs in the database!  Either you have never entered
and saved any log items, or you have already deleted your logs.</h3>
EOD
    } else {
        print $fh <<"EOD";

<p class="justified">
This page allows you to <span class="shrill">delete your entire log database</span>
of $nmonths $mont from The Hacker's Diet <em>Online</em>.  This operation is
<span class="shrill">irrevocable</span>&mdash;unless you have previously downloaded
a backup copy of your logs, all of the information you have entered
into them will be <span class="shrill">lost forever</span>.  Consequently, before
proceeding, we <span class="shrill">implore you</span> to make a database backup
now by pressing the button below.
</p>


<form id="Hdiet_exportdb" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="hidden" name="format" value="xml" />
<input type="hidden" name="period" value="a" />

<input type="submit" name="q=do_exportdb" value=" Back Up Entire Log Database " />
</p>
</form>


<form id="Hdiet_wipedb" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>

<p class="justified">
In order to confirm your intention to
<span class="shrill">irreversibly delete</span> your entire
log database, please enter your user name and password in the fields
below, and type the one-time &ldquo;confirmation code&rdquo;
in the box.
</p>
EOD
        
    my $concode = $ui->generatePassword(10);
    my $consig = sha1_hex($concode . "Sodium Chloride");
    $consig =~ tr/a-f/FGJKQW/;

    print $fh <<"EOD";
<table border="border" class="login">
<tr><th>User Name:</th>
    <td><input type="text" name="HDiet_username" size="60"
               maxlength="4096" value="" /></td>
</tr>
<tr><th>Password:</th>
    <td><input type="password" name="HDiet_password" size="60"
               maxlength="4096" value="" /></td>
</tr>
<tr><th>Confirmation:</th>
    <td><input type="text" name="HDiet_confirmation" size="15"
               maxlength="15" value="" />
        <span onmousedown="return false;" onmouseover="return false;">&nbsp;
        Enter code <tt><b>$concode</b></tt> in the box at the left.</span></td>
</tr>
</table>
EOD

        print $fh <<"EOD";
<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="hidden" name="c" value="$consig" />
<input type="submit" class="darwin" name="q=do_wipedb" value=" Delete Entire Log Database&#xa;(Cannot be undone!)" />
&nbsp;
<input type="submit" name="q=account" value=" Cancel " />
</p>
</form>
EOD
    }
    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'do_wipedb') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    write_XHTML_prologue($fh, $homeBase, "Log Database Deletion", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    $CGIargs{c} = '' if !defined($CGIargs{c});
    $CGIargs{HDiet_confirmation} = '' if !$CGIargs{HDiet_confirmation};
    my $consig = sha1_hex($CGIargs{HDiet_confirmation} . "Sodium Chloride");
    $consig =~ tr/a-f/FGJKQW/;

    if (($CGIargs{HDiet_username} ne $ui->{login_name}) ||
        ($CGIargs{HDiet_password} ne $ui->{password})) {
        
    print $fh <<"EOD";
<h1 class="c">Log Database Deletion Rejected</h1>

<h3>The User Name and/or Password entered to confirm the log database
deletion did not match those of your user account.</h3>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=wipedb&amp;s=$session->{session_id}$tzOff">Back
    to Delete Log Database Request</a></h4>
EOD

    } elsif ($consig ne $CGIargs{c}) {
        
    print $fh <<"EOD";
<h1 class="c">Log Database Deletion Rejected</h1>

<h3>The confirmation code entered for the deletion request did not match
that given in the request form.</h3>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=wipedb&amp;s=$session->{session_id}$tzOff">Back
    to Delete Log Database Request</a></h4>
EOD

    } else {
        if (!$readOnly) {
            
    my $tfn = timeXML(time());
    $tfn =~ s/:/./g;            # Avoid idiot tar treating time as hostname
    if ("/server/pub/hackdiet/Backups" ne '') {
        do_command("( cd /server/pub/hackdiet/Backups; tar cfj ${user_file_name}_" .
            $tfn . ".bz2 -C ../Users $user_file_name )");
        clusterCopy("/server/pub/hackdiet/Backups/${user_file_name}_$tfn.bz2");
    }


            my @months = $ui->enumerateMonths();
            for my $m (@months) {
                unlink("/server/pub/hackdiet/Users/$user_file_name/$m.hdb") ||
                   die("Cannot delete log file /server/pub/hackdiet/Users/$user_file_name/$m.hdb");
                clusterDelete("/server/pub/hackdiet/Users/$user_file_name/$m.hdb");
            }

            append_history($user_file_name, 12);
        }

        print $fh <<"EOD";

<h1 class="c">All Log Databases Deleted</h1>

<p class="justified">
Pursuant to your request, all logs have been deleted from your database
on The Hacker's Diet <em>Online</em>.  You can now
<a href="/cgi-bin/HackDiet?q=closeaccount&amp;s=$session->{session_id}$tzOff">close your account</a>
if you wish, or
<a href="/cgi-bin/HackDiet?q=importcsv&amp;s=$session->{session_id}$tzOff">restore your database</a>
from a backup copy you downloaded
before deleting the database.
</p>


<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Back to account page</a></h4>
EOD
    }
    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'closeaccount') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }



    my @months = $ui->enumerateMonths();
    my $nmonths = $#months + 1;
    my $mont = 'month' . (($nmonths != 1) ? 's' : '');

    write_XHTML_prologue($fh, $homeBase, "Close User Account", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


     print $fh <<"EOD";
<h1 class="c">Close User Account</h1>
EOD

    if ($nmonths > 0) {
        
        print $fh <<"EOD";
<h3>You have $nmonths $mont of logs in the database.  Before you can
close your account, you must
<a href="/cgi-bin/HackDiet?q=wipedb&amp;s=$session->{session_id}$tzOff">delete
all of your logs</a> from the database.  Return here after the logs have been
deleted.</h3>
EOD

    } else {

        my $qun = quoteHTML($ui->{login_name});
        print $fh <<"EOD";

<p class="justified">
This page allows you to <span class="shrill">close your account</span>
on The Hacker's Diet <em>Online</em>.  This will discard all the
preferences you have specified for your account and make your
present user name &ldquo;<b>$qun</b>&rdquo; available for
creation of a new account by another person.  Note that there
is no charge for maintaining an account, and that data are kept
in your account indefinitely even if your account is inactive.
</p>


<form id="Hdiet_wipedb" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>

<p class="justified">
If you wish to proceed with closing your account, please
confirm by entering your user name and password in the fields
below, and type the one-time &ldquo;confirmation code&rdquo;
in the box.
</p>
EOD
        
    my $concode = $ui->generatePassword(10);
    my $consig = sha1_hex($concode . "Sodium Chloride");
    $consig =~ tr/a-f/FGJKQW/;

    print $fh <<"EOD";
<table border="border" class="login">
<tr><th>User Name:</th>
    <td><input type="text" name="HDiet_username" size="60"
               maxlength="4096" value="" /></td>
</tr>
<tr><th>Password:</th>
    <td><input type="password" name="HDiet_password" size="60"
               maxlength="4096" value="" /></td>
</tr>
<tr><th>Confirmation:</th>
    <td><input type="text" name="HDiet_confirmation" size="15"
               maxlength="15" value="" />
        <span onmousedown="return false;" onmouseover="return false;">&nbsp;
        Enter code <tt><b>$concode</b></tt> in the box at the left.</span></td>
</tr>
</table>
EOD


        print $fh <<"EOD";
<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="hidden" name="c" value="$consig" />
<input type="submit" class="darwin" name="q=do_closeaccount" value=" Close User Account&#xa;(Cannot be undone!) " />
&nbsp;
<input type="submit" name="q=account" value=" Cancel " />
</p>
</form>
EOD
    }
    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'do_closeaccount') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    write_XHTML_prologue($fh, $homeBase, "User Account Close", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    $CGIargs{c} = '' if !defined($CGIargs{c});
    $CGIargs{HDiet_confirmation} = '' if !$CGIargs{HDiet_confirmation};
    my $consig = sha1_hex($CGIargs{HDiet_confirmation} . "Sodium Chloride");
    $consig =~ tr/a-f/FGJKQW/;

    if (($CGIargs{HDiet_username} ne $ui->{login_name}) ||
        ($CGIargs{HDiet_password} ne $ui->{password})) {
        
    print $fh <<"EOD";
<h1 class="c">User Account Close Rejected</h1>

<h3>The User Name and/or Password entered to confirm the account
close did not match those of your user account.</h3>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=closeaccount&amp;s=$session->{session_id}$tzOff">Back
    to Close User Account Request</a></h4>
EOD

    } elsif ($consig ne $CGIargs{c}) {
        
    print $fh <<"EOD";
<h1 class="c">User Account Close Rejected</h1>

<h3>The confirmation code entered for the account close request did not match
that given in the request form.</h3>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=closeaccount&amp;s=$session->{session_id}$tzOff">Back
    to Close User Account Request</a></h4>
EOD

    } else {
        my @months = $ui->enumerateMonths();
        my $nmonths = $#months + 1;
        if ($nmonths > 0) {
            
    my $mont = 'month' . (($nmonths != 1) ? 's' : '');
    print $fh <<"EOD";
<h1 class="c">User Account Close Rejected</h1>

<h3>You have $nmonths $mont of logs in the database.  Before you can
close your account, you must
<a href="/cgi-bin/HackDiet?q=wipedb&amp;s=$session->{session_id}$tzOff">delete
all of your logs</a> from the database.  Return here after the logs have been
deleted.</h3>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=closeaccount&amp;s=$session->{session_id}$tzOff">Back
    to Close User Account Request</a></h4>
EOD

        } else {
            if (!$readOnly) {
                #   Delete active session file
                unlink("/server/pub/hackdiet/Sessions/$CGIargs{s}.hds");
                clusterDelete("/server/pub/hackdiet/Sessions/$CGIargs{s}.hds");
                unlink("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
                clusterDelete("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");

                
    my $tfn = timeXML(time());
    $tfn =~ s/:/./g;            # Avoid idiot tar treating time as hostname
    if ("/server/pub/hackdiet/Backups" ne '') {
        do_command("( cd /server/pub/hackdiet/Backups; tar cfj ${user_file_name}_" .
            $tfn . ".bz2 -C ../Users $user_file_name )");
        clusterCopy("/server/pub/hackdiet/Backups/${user_file_name}_$tfn.bz2");
    }


                #   At this point the user is logged out.  We can now delete
                #   the user directory and all its contents.
                do_command("rm -rf /server/pub/hackdiet/Users/$user_file_name");
                clusterRecursiveDelete("/server/pub/hackdiet/Users/$user_file_name");
            }

            print $fh <<"EOD";
<h1 class="c">Account Closed</h1>

<p class="justified">
Pursuant to your request, your account
on The Hacker's Diet <em>Online</em> has been closed.  You can now
<a href="/cgi-bin/HackDiet/">log into another account</a>
if you wish, or
<a href="/cgi-bin/HackDiet?q=validate_user&amp;new=new_account$tzOff">create
a new account</a>.  Otherwise, thank you for participating and farewell!
</p>
EOD
        }
    }
    write_XHTML_epilogue($fh, $homeBase);


    
    } elsif ($CGIargs{q} eq 'account') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    my $qun = quoteHTML($user_name);
    write_XHTML_prologue($fh, $homeBase, $qun, undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, "Utilities", undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    
    if ($browse_public) {
        my $qrn = quoteHTML($real_user_name);
        print $fh <<"EOD";
<h2 class="c">$qrn browsing<br /> public $qun account</h2>
EOD
    } else {
        print $fh <<"EOD";
<h1 class="c">Welcome, $qun</h1>
EOD
    }


    
    print $fh <<"EOD";
<ul>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=log&amp;m=now$tzOff">Current monthly log</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=calendar$tzOff">Historical logs</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=histreq$tzOff">Historical charts</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=trendan$tzOff">Trend analysis</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=dietcalc$tzOff">Diet calculator</a></li>
EOD


    if ($browse_public) {
        
    print $fh <<"EOD";

    <li class="skip"><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=quitbrowse$tzOff">Quit browsing <b>$qun</b> public account</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=browsepub$tzOff">Browse a different public user account</a>
        <form id="Hdiet_acctmgr" method="post" action="/cgi-bin/HackDiet">
            <div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
            <p style="margin-top: 0px;">
            Access public account name:
            <input type="text" name="pubacct" maxlength="80" size="21" />
            <input type="hidden" name="s" value="$session->{session_id}" />
            <input type="submit" name="q=do_public_browseacct" value=" View " />
            </p>
        </form>
    </li>
EOD

    } else {
        
    print $fh <<"EOD";
    <li class="skip"><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=modacct$tzOff">Edit account settings</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=configure_badge$tzOff">Configure Web page badge image</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=paper_logs$tzOff">Print paper log forms</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=update_trend&amp;m=0000-00&amp;canon=0$tzOff">Recalculate trend carry-forward</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=clearcookies$tzOff">Forget persistent logins</a></li>

    <li class="skip"><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=exportdb$tzOff">Export database as CSV or XML</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=importcsv$tzOff">Import CSV  or XML database</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=backup$tzOff">Download native database backup</a></li>

    <li class="skip"><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=wipedb$tzOff">Delete entire log database</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=closeaccount$tzOff">Close this user account</a></li>
EOD

    if (!$readOnly) {
        print $fh <<"EOD";

    <li class="skip">

        <form id="Hdiet_pubacct" method="post" action="/cgi-bin/HackDiet">
            <p style="margin-top: 0px; margin-bottom: 4px;">
            <input type="hidden" name="s" value="$session->{session_id}" />
            Browse public user accounts:
            <select name="acct_category" size="1">
                <option value="active" selected="selected">Active accounts</option>
                <option value="inactive">Inactive accounts</option>
                <option value="all">All accounts</option>
            </select>
            <input type="submit" name="q=browsepub" value=" View " />
            </p>
        </form>

        <form id="Hdiet_acctmgr" method="post" action="/cgi-bin/HackDiet">
            <p style="margin-top: 0px;">
            Access public account name:
            <input type="text" name="pubacct" maxlength="80" size="21" />
            <input type="hidden" name="s" value="$session->{session_id}" />
            <input type="submit" name="q=do_public_browseacct" value=" View " />
            </p>
        </form>
    </li>
EOD
    }



#        if (0) {
            print $fh <<"EOD";
    <li class="skip"><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=feedback$tzOff">Send feedback message</a></li>
EOD
#        }
    }

    print $fh <<"EOD";
    <li class="skip"><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=logout$tzOff">Sign out</a></li>
</ul>
EOD

    if ($ui->{administrator} || $assumed_identity) {
        
    print $fh <<"EOD";
<h2 class="c">Administrator Functions</h2>

<ul>
    <li class="skip">
        <form id="Hdiet_admacct" method="post" action="/cgi-bin/HackDiet">
            <p style="margin-top: 0px; margin-bottom: 4px;">
            <input type="hidden" name="s" value="$session->{session_id}" />
            Manage user accounts:
            <select name="acct_category" size="1">
                <option value="active" selected="selected">Active accounts</option>
                <option value="inactive">Inactive accounts</option>
                <option value="all">All accounts</option>
            </select>
            <input type="submit" name="q=acctmgr" value=" View " />
            </p>
        </form>

        <form id="Hdiet_acctadm" method="post" action="/cgi-bin/HackDiet">
            <p style="margin-top: 0px;">
            User account name:
            <input type="text" name="useracct" maxlength="80" size="21" />
            <input type="hidden" name="s" value="$session->{session_id}" />
            <input type="submit" name="q=do_admin_browseacct" value=" View " />
            &nbsp;
            <input type="submit" name="q=do_admin_delacct" value=" Delete " />
            <input type="submit" name="q=do_admin_purgeacct" value=" Purge Logs " />
            <input type="password" name="HDiet_password" size="20" maxlength="4096" value="" />
            </p>
        </form>
</li>

    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=sessmgr$tzOff">Manage sessions</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=cookiemgr$tzOff">Manage persistent logins</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=globalstats$tzOff">Display global statistics</a></li>
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=synthdata$tzOff">Generate synthetic data</a></li>
EOD

    if (0) {
        print $fh <<"EOD";
    <li><a href="/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=invite$tzOff">Create invitation codes</a></li>
EOD
    }

    print $fh <<"EOD";
</ul>
EOD

    }

    
#    if (0) {
        my $bn = <<"EOD";
5258

EOD
        $bn =~ s/\s+$/:/;
        print $fh <<"EOD";
<p class="build">
Build $bn 2022-04-05 19:18 UTC
</p>
EOD
#    }


    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'new_account') {
        
    my @goofs;

if (0) {        # Set to 1 to investigate reports of account creation problems
    open(NOF, ">/tmp/hdiet_newacct_$$.txt");
    use Data::Dumper;
    print(NOF Data::Dumper->Dump([\%CGIargs, \%ENV], ['*CGIargs', '*ENV']));
    close(NOF);

}

    
    my $user_file_name;
    $CGIargs{HDiet_username} =~ s/\s+$//;
    if ($CGIargs{HDiet_username} eq '') {
        push(@goofs, "User name is blank");
    } else {
        $user_file_name = quoteUserName($CGIargs{HDiet_username});
        if (-d "/server/pub/hackdiet/Users/$user_file_name") {
            push(@goofs, "User name is already taken: please choose another");
        }
    }


    
    my $betaInvitation = '';
    if (0) {
        if (('Beta luck next time' eq '') ||
            ($CGIargs{HDiet_invitation} ne 'Beta luck next time')) {
            if ($CGIargs{HDiet_invitation} eq '') {
                push(@goofs, "Beta test invitation is blank");
            } else {
                $betaInvitation = $CGIargs{HDiet_invitation};
                $betaInvitation =~ s/\W//g;
                if (!(-f "/server/pub/hackdiet/Invitations/$betaInvitation.hdi")) {
                    push(@goofs, "Beta test invitation is invalid or already used");
                }
            }
        }
    }


    if ($CGIargs{HDiet_password} ne $CGIargs{HDiet_rpassword}) {
        push(@goofs, "Password does not match password confirmation");
    } else {
        if (length($CGIargs{HDiet_password}) < 6) {
            push(@goofs, "Password must be at least six characters");
        }
    }
    if ($CGIargs{HDiet_email} eq '') {
        push(@goofs, "E-mail address is blank");
    } else {
        if ($CGIargs{HDiet_email} !~ m/@/) {
            push(@goofs, "E-mail address contains no '\@' sign");
        } else {
            $CGIargs{HDiet_email} =~ m/@(.*)$/;
            if (!validMailDomain(encodeDomainName($1))) {
                my $dn = quoteHTML($1);
                push(@goofs, "Domain name <tt>$dn</tt> in your E-mail address is invalid");
            }
        }
    }

    if ($#goofs >= 0) {
        
    write_XHTML_prologue($fh, $homeBase, "Create New User Account", undef, $CGIargs{HDiet_handheld});
    print $fh <<"EOD";
<h1 class="c">Errors in New Account Request</h1>
EOD
    print $fh <<"EOD";
<p>
The following errors were found in your request to create
a new account.  Please remedy them and try again.
</p>

<ol>
EOD

    for (my $i = 0; $i <= $#goofs; $i++) {
        print($fh "<li>$goofs[$i].</li>\n");
    }
    print $fh <<"EOD";
</ol>
<form id="Hdiet_newacct" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
EOD

    
    if ($CGIargs{HDiet_handheld}) {
        print $fh <<"EOD";
<div><input type="hidden" name="HDiet_handheld" value="y" /></div>
EOD
    }


    my $u = HDiet::user->new($CGIargs{HDiet_username});
    $u->{e_mail} = $CGIargs{HDiet_email};
    $u->{first_name} = $CGIargs{HDiet_namef};
    $u->{last_name} = $CGIargs{HDiet_namel};
    $u->{middle_name} = $CGIargs{HDiet_namem};
    $u->{log_unit} = $CGIargs{HDiet_wunit};
    $u->{display_unit} = $CGIargs{HDiet_dunit};
    $u->{energy_unit} = $CGIargs{HDiet_eunit};
    $CGIargs{HDiet_dchar} = '.' if ($CGIargs{HDiet_dchar} !~ m/^[\.,]$/);
    $u->{decimal_character} = $CGIargs{HDiet_dchar};

    $u->new_account_form($fh);
    print $fh <<"EOD";
<p class="mlog_buttons">
<input type="hidden" name="q" value="new_account" />
<input type="submit" name="login" value=" Create Account " tabindex="19" />
&nbsp;
<input type="reset" value=" Clear Form " tabindex="20" />
</p>
</form>
EOD

    write_XHTML_epilogue($fh, $homeBase);
    last;

    }

    
    if (mkdir("/server/pub/hackdiet/Users/$user_file_name")) {
        clusterMkdir("/server/pub/hackdiet/Users/$user_file_name");
        my $ui = HDiet::user->new($CGIargs{HDiet_username});
        
    if (defined($CGIargs{HDiet_height_cm})) {
        $CGIargs{HDiet_height_cm} =~ s/,/./g;
    }
    if (defined($CGIargs{HDiet_height_in})) {
        $CGIargs{HDiet_height_in} =~ s/,/./g;
    }

    if ($CGIargs{HDiet_height_cm} eq '') {
        $CGIargs{HDiet_height_cm} = 0;
        if (($CGIargs{HDiet_height_ft} ne '') || ($CGIargs{HDiet_height_in} ne '')) {
            $CGIargs{HDiet_height_cm} = 2.54 *
                ((($CGIargs{HDiet_height_in} ne '') ? $CGIargs{HDiet_height_in} : 0) +
                 ((($CGIargs{HDiet_height_ft} ne '') ? $CGIargs{HDiet_height_ft} * 12 : 0)));
        }
    }
    if ($CGIargs{HDiet_password} ne '') {
        $ui->{password} = $CGIargs{HDiet_password};
    }
    $CGIargs{HDiet_dchar} = '.' if ($CGIargs{HDiet_dchar} !~ m/^[\.,]$/);

    $ui->{first_name} = $CGIargs{HDiet_namef};
    $ui->{last_name} = $CGIargs{HDiet_namel};
    $ui->{middle_name} = $CGIargs{HDiet_namem};
    $ui->{e_mail} = $CGIargs{HDiet_email};
    $ui->{log_unit} = $CGIargs{HDiet_wunit};
    $ui->{display_unit} = $CGIargs{HDiet_dunit};
    $ui->{energy_unit} = $CGIargs{HDiet_eunit};
    $ui->{decimal_character} = $CGIargs{HDiet_dchar};
    $ui->{height} = $CGIargs{HDiet_height_cm};
    $ui->{account_created} = time() if $ui->{account_created} == 0;
    $ui->{last_modification_time} = time();

    if ($CGIargs{HDiet_public}) {
        if ((!$ui->{public}) || $CGIargs{HDiet_pubnew}) {
            my $pn = HDiet::pubname->new();
            $pn->assignPublicName($ui);
        }
    } else {
        if ($ui->{public}) {
            my $pn = HDiet::pubname->new();
            $pn->deletePublicName($ui);
        }
    }

        
    open(FU, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    $ui->save(\*FU);
    close(FU);
    clusterCopy("/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");

        $CGIargs{q} = 'login';
    } else {
         push(@goofs, "Sorry, somebody else just took that user name: please choose another");
         
    write_XHTML_prologue($fh, $homeBase, "Create New User Account", undef, $CGIargs{HDiet_handheld});
    print $fh <<"EOD";
<h1 class="c">Errors in New Account Request</h1>
EOD
    print $fh <<"EOD";
<p>
The following errors were found in your request to create
a new account.  Please remedy them and try again.
</p>

<ol>
EOD

    for (my $i = 0; $i <= $#goofs; $i++) {
        print($fh "<li>$goofs[$i].</li>\n");
    }
    print $fh <<"EOD";
</ol>
<form id="Hdiet_newacct" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
EOD

    
    if ($CGIargs{HDiet_handheld}) {
        print $fh <<"EOD";
<div><input type="hidden" name="HDiet_handheld" value="y" /></div>
EOD
    }


    my $u = HDiet::user->new($CGIargs{HDiet_username});
    $u->{e_mail} = $CGIargs{HDiet_email};
    $u->{first_name} = $CGIargs{HDiet_namef};
    $u->{last_name} = $CGIargs{HDiet_namel};
    $u->{middle_name} = $CGIargs{HDiet_namem};
    $u->{log_unit} = $CGIargs{HDiet_wunit};
    $u->{display_unit} = $CGIargs{HDiet_dunit};
    $u->{energy_unit} = $CGIargs{HDiet_eunit};
    $CGIargs{HDiet_dchar} = '.' if ($CGIargs{HDiet_dchar} !~ m/^[\.,]$/);
    $u->{decimal_character} = $CGIargs{HDiet_dchar};

    $u->new_account_form($fh);
    print $fh <<"EOD";
<p class="mlog_buttons">
<input type="hidden" name="q" value="new_account" />
<input type="submit" name="login" value=" Create Account " tabindex="19" />
&nbsp;
<input type="reset" value=" Clear Form " tabindex="20" />
</p>
</form>
EOD

    write_XHTML_epilogue($fh, $homeBase);
    last;

    }


    
    if (0) {
        if ($betaInvitation ne '') {
            if (!unlink("/server/pub/hackdiet/Invitations/$betaInvitation.hdi")) {
                print(STDERR "Unable to unlink /server/pub/hackdiet/Invitations/$betaInvitation.hdi\n");
            }
            clusterDelete("/server/pub/hackdiet/Invitations/$betaInvitation.hdi");
        }
    }


    next;

    } elsif ($CGIargs{q} eq 'modacct') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    if ($session->{cookie}) {
        
    write_XHTML_prologue($fh, $homeBase, "Settings Inaccessible", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, "Settings", undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Settings Inaccessible</h1>
<p class="justified">
You signed into this session with &ldquo;Remember me&rdquo;.
In the interest of security, the private information in the Settings
page cannot be displayed or changed in such a session.  To access the
Settings page, please sign out and then sign back in with your
user name and password.
</p>
EOD
    write_XHTML_epilogue($fh, $homeBase);

    update_last_transaction($user_file_name);

    } else {

        write_XHTML_prologue($fh, $homeBase, "Modify Account Settings", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, "Settings", undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Modify Account Settings</h1>
<p class="justified">
To change your password, enter the new value in the &ldquo;Password&rdquo;
and &ldquo;Retype password&rdquo; fields; if these fields are left blank,
your password will be unchanged.
</p>
<form id="Hdiet_newacct" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
EOD
        $ui->new_account_form($fh, 1);
        print $fh <<"EOD";
<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="hidden" name="decimal_character" value="$ui->{decimal_character}" />
<input type="submit" name="q=edit_account" value=" Apply " />
&nbsp;
<input type="reset" value=" Reset " />
&nbsp;
<input type="submit" name="q=account" value=" Cancel " />
</p>
</form>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        update_last_transaction($user_file_name);
    }

    } elsif ($CGIargs{q} eq 'clearcookies') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    my %cookies;

    opendir(CD, "/server/pub/hackdiet/RememberMe") ||
        die("Cannot open directory /server/pub/hackdiet/RememberMe");
    for my $f (grep(/\w+\.hdr/, readdir(CD))) {
        open(FU, "<:utf8", "/server/pub/hackdiet/RememberMe/$f") ||
#        open(FU, "<", "/server/pub/hackdiet/RememberMe/$f") ||                #### Poison cookie search
            die("Cannot open persistent login /server/pub/hackdiet/RememberMe/$f");
        my $cookie = HDiet::cookie->new();
        $cookie->load(\*FU);
#if ($cookie->{login_name} =~ m/^[ -~]*$/) { next; }                     #### Poison cookie search
        close(FU);
        $cookies{$cookie->{cookie_id}} = $cookie;
    }
    closedir(CD);


    write_XHTML_prologue($fh, $homeBase, "Forget Persistent Logins", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, "Settings", undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    my $ndel = 0;
#print($fh "<pre>\n");
    for my $f (keys(%cookies)) {
        my $cook = $cookies{$f};
        if ($cook->{login_name} eq $ui->{login_name}) {
#            $cook->describe($fh);
            $ndel += unlink("/server/pub/hackdiet/RememberMe/$f.hdr");
            clusterDelete("/server/pub/hackdiet/RememberMe/$f.hdr");
        }
    }
#print($fh "</pre>\n");


    print $fh <<"EOD";
<h1 class="c">Forget Persistent Logins</h1>
<p class="justified">
EOD

    if ($ndel > 0) {
        print $fh <<"EOD";
All persistent logins (a total of $ndel) have been forgotten.  You
will have to log in with your name and password on the next session
from all browsers.
EOD
    } else {
        print $fh <<"EOD";
You had no persistent logins.
EOD
    }

    print $fh <<"EOD";
</p>
EOD
    write_XHTML_epilogue($fh, $homeBase);

    update_last_transaction($user_file_name);
    append_history($user_file_name, 18, $ndel);

    } elsif ($CGIargs{q} eq 'edit_account') {
        
    my @goofs;

    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    if ($CGIargs{HDiet_password} ne $CGIargs{HDiet_rpassword}) {
        push(@goofs, "Password does not match password confirmation");
    } else {
        if (($CGIargs{HDiet_password} ne '') && (length($CGIargs{HDiet_password})) < 6) {
            push(@goofs, "New password must be at least six characters");
        }
    }
    if ($CGIargs{HDiet_email} eq '') {
        push(@goofs, "E-mail address is blank");
    } else {
        if ($CGIargs{HDiet_email} !~ m/@/) {
            push(@goofs, "E-mail address contains no '\@' sign");
        } else {
            $CGIargs{HDiet_email} =~ m/@(.*)$/;
            if (!validMailDomain(encodeDomainName($1))) {
                my $dn = quoteHTML($1);
                push(@goofs, "Domain name <tt>$dn</tt> in your E-mail address is invalid");
            }
        }
    }

    if ($#goofs >= 0) {
        
    write_XHTML_prologue($fh, $homeBase, "Modify Account Settings", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, "Settings", undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<h1 class="c">Errors in Account Settings</h1>
EOD
    print $fh <<"EOD";
<p>
The following errors were found in your request to change
your account settings.  Please remedy them and try again.
</p>

<ol>
EOD

    for (my $i = 0; $i <= $#goofs; $i++) {
        print($fh "<li>$goofs[$i].</li>\n");
    }
    print $fh <<"EOD";
</ol>
<form id="Hdiet_newacct" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
EOD

    $ui->new_account_form($fh, 1);
    print $fh <<"EOD";
<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="hidden" name="decimal_character" value="$ui->{decimal_character}" />
<input type="submit" name="q=edit_account" value=" Apply " />
&nbsp;
<input type="reset" value=" Reset " />
&nbsp;
<input type="submit" name="q=account" value=" Cancel " />
</p>
</form>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Back to account page</a></h4>
EOD

    write_XHTML_epilogue($fh, $homeBase);
    last;

    }

    if (!$readOnly) {
        
    my $settings_changed = '';

    $CGIargs{HDiet_height_cm} =~ s/,/./;
    $CGIargs{HDiet_height_in} =~ s/,/./;
    my $heightcm = $CGIargs{HDiet_height_cm};
    if ($heightcm eq '') {
        $heightcm = 0;
        if (($CGIargs{HDiet_height_ft} ne '') || ($CGIargs{HDiet_height_in} ne '')) {
            $heightcm = 2.54 *
                ((($CGIargs{HDiet_height_in} ne '') ? $CGIargs{HDiet_height_in} : 0) +
                 ((($CGIargs{HDiet_height_ft} ne '') ? $CGIargs{HDiet_height_ft} * 12 : 0)));
        }
    }
    if ($CGIargs{HDiet_password} ne '') {
        $settings_changed .= ',Password' if $ui->{password} ne $CGIargs{HDiet_password};
    }
    $settings_changed .= ',FirstName' if $ui->{first_name} ne $CGIargs{HDiet_namef};
    $settings_changed .= ',LastName' if $ui->{last_name} ne $CGIargs{HDiet_namel};
    $settings_changed .= ',MiddleName' if $ui->{middle_name} ne $CGIargs{HDiet_namem};
    $settings_changed .= ',E-Mail' if $ui->{e_mail} ne $CGIargs{HDiet_email};
    $settings_changed .= ',LogUnit' if $ui->{log_unit} ne $CGIargs{HDiet_wunit};
    $settings_changed .= ',DisplayUnit' if $ui->{display_unit} ne $CGIargs{HDiet_dunit};
    $settings_changed .= ',EnergyUnit' if $ui->{energy_unit} ne $CGIargs{HDiet_eunit};
    $settings_changed .= ',DecimalCharacter' if $ui->{decimal_character} ne $CGIargs{HDiet_dchar};
    $settings_changed .= ',Height' if $ui->{height} ne $heightcm;
    $settings_changed .= ',Public' if $ui->{public} != ($CGIargs{HDiet_public} ? 1 : 0);
    $settings_changed .= ',Pubname' if $CGIargs{HDiet_pubnew};

    $settings_changed =~ s/^,//;
    append_history($user_file_name, 8, $settings_changed);

        
    if (defined($CGIargs{HDiet_height_cm})) {
        $CGIargs{HDiet_height_cm} =~ s/,/./g;
    }
    if (defined($CGIargs{HDiet_height_in})) {
        $CGIargs{HDiet_height_in} =~ s/,/./g;
    }

    if ($CGIargs{HDiet_height_cm} eq '') {
        $CGIargs{HDiet_height_cm} = 0;
        if (($CGIargs{HDiet_height_ft} ne '') || ($CGIargs{HDiet_height_in} ne '')) {
            $CGIargs{HDiet_height_cm} = 2.54 *
                ((($CGIargs{HDiet_height_in} ne '') ? $CGIargs{HDiet_height_in} : 0) +
                 ((($CGIargs{HDiet_height_ft} ne '') ? $CGIargs{HDiet_height_ft} * 12 : 0)));
        }
    }
    if ($CGIargs{HDiet_password} ne '') {
        $ui->{password} = $CGIargs{HDiet_password};
    }
    $CGIargs{HDiet_dchar} = '.' if ($CGIargs{HDiet_dchar} !~ m/^[\.,]$/);

    $ui->{first_name} = $CGIargs{HDiet_namef};
    $ui->{last_name} = $CGIargs{HDiet_namel};
    $ui->{middle_name} = $CGIargs{HDiet_namem};
    $ui->{e_mail} = $CGIargs{HDiet_email};
    $ui->{log_unit} = $CGIargs{HDiet_wunit};
    $ui->{display_unit} = $CGIargs{HDiet_dunit};
    $ui->{energy_unit} = $CGIargs{HDiet_eunit};
    $ui->{decimal_character} = $CGIargs{HDiet_dchar};
    $ui->{height} = $CGIargs{HDiet_height_cm};
    $ui->{account_created} = time() if $ui->{account_created} == 0;
    $ui->{last_modification_time} = time();

    if ($CGIargs{HDiet_public}) {
        if ((!$ui->{public}) || $CGIargs{HDiet_pubnew}) {
            my $pn = HDiet::pubname->new();
            $pn->assignPublicName($ui);
        }
    } else {
        if ($ui->{public}) {
            my $pn = HDiet::pubname->new();
            $pn->deletePublicName($ui);
        }
    }

        
    open(FU, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    $ui->save(\*FU);
    close(FU);
    clusterCopy("/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");

    }

    write_XHTML_prologue($fh, $homeBase, "Account Settings Changed", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<h1 class="c">Account Settings Changed</tt></h1>

<p class="justified">
The settings for your account have been changed per your request.
Please click the link below to return to your account's home page.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account home page</a></h4>
EOD
    write_XHTML_epilogue($fh, $homeBase);

    update_last_transaction($user_file_name);

    } elsif ($CGIargs{q} eq 'pwreset') {
        
    my $qun = '';
    $qun = quoteHTML($CGIargs{HDiet_username}) if defined($CGIargs{HDiet_username});


    write_XHTML_prologue($fh, $homeBase, "Reset Password", undef, $CGIargs{HDiet_handheld});
    print $fh <<"EOD";
<h1 class="c">Reset Password</h1>
<form id="Hdiet_reset_password" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
EOD

    
    if ($CGIargs{HDiet_handheld}) {
        print $fh <<"EOD";
<div><input type="hidden" name="HDiet_handheld" value="y" /></div>
EOD
    }


    print $fh <<"EOD";
<p class="justified">
To reset your password to a new value, which will be sent via E-mail
to the registered E-mail address for your account, enter your User
Name and E-mail address in the boxes below and press the &ldquo;Reset
Password&rdquo; button.
</p>

<table border="border" class="login">
<tr><th><span class="accesskey">U</span>ser Name:</th>
    <td><input accesskey="u" type="text" name="HDiet_username" size="60"
               maxlength="4096" value="$qun" /></td>
</tr>
<tr><th><span class="accesskey">E</span>-mail address:</th>
    <td><input accesskey="e" type="text" name="HDiet_email" size="60"
               maxlength="4096" value="" /></td>
</tr>
</table>
EOD
    my $u = HDiet::user->new($CGIargs{HDiet_username});
    print $fh <<"EOD";
<p class="mlog_buttons">
<input type="hidden" name="q" value="new_password" />
<input type="submit" name="reset" value=" Reset Password " />
&nbsp;
<input type="submit" name="cancel" value=" Cancel " />
</p>
</form>
EOD
    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'new_password') {
        
    #   If no user name given or the user clicked "Cancel" re-issue login form
    if (($CGIargs{HDiet_username} eq '') || $CGIargs{cancel}) {
        $CGIargs{q} = 'login';
        next;
    }

    #   Verify user account directory exists and contains
    #   valid user information file.
    my $user_file_name = quoteUserName($CGIargs{HDiet_username});
    if (!(-f "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu")
        || (!open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu"))) {
        
    
    my @lt = localtime(time());
    my $ct = sprintf("%s %d %02d:%02d:%02d",
        MONTH_ABBREVIATIONS->[$lt[4]], $lt[3], $lt[2], $lt[1], $lt[0]);

    openlog("HackDiet", "pid", "LOG_AUTH");
    syslog("info",
        "$ENV{REMOTE_ADDR}: (1) $ct $ENV{SERVER_NAME} HackDiet(pam_unix)[$$]: " .
        "authentication failure; logname= uid=0 euid=0 tty=http " .
        "ruser='$user_file_name' rhost=$ENV{REMOTE_ADDR}");
    closelog();

    $CGIargs{HDiet_handheld} = 'y' if $CGIargs{handheld};
    write_XHTML_prologue($fh, $homeBase, "Please Sign In", " checkSecure();", $CGIargs{HDiet_handheld});
    print $fh <<"EOD";
<h1 class="c">Sign In Invalid: Incorrect User Name or Password</h1>
<h1 class="c">Please Sign In</h1>
EOD
    my $u = HDiet::user->new();
    $u->login_form($fh, $tzOff, $CGIargs{HDiet_handheld}, $CGIargs{HDiet_remember});
    write_XHTML_epilogue($fh, $homeBase);
    last;

    }

    #   Read user account information
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    
    if ($CGIargs{HDiet_email} ne $ui->{e_mail}) {
        write_XHTML_prologue($fh, $homeBase, "Incorrect E-mail Address", undef, $CGIargs{HDiet_handheld});
        my $arghandheld = $CGIargs{HDiet_handheld} ? '&amp;HDiet_handheld=y' : '';
        my $qun = quoteHTML($CGIargs{HDiet_username});

        print $fh <<"EOD";
<h1 class="c">Incorrect E-mail Address</h1>

<p class="justified">
Your password reset request specified a different E-mail
address than the one registered for your account to which
the new password will be sent.  To avoid abuse, you must specify
the registered E-mail address to confirm your identity before
the password will be reset.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=login$arghandheld$tzOff">Sign In</a></h4>
<h4 class="nav"><a href="/cgi-bin/HackDiet?q=pwreset$arghandheld&amp;HDiet_username=$qun$tzOff">Password Reset</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        append_history($user_file_name, 9);
        last;
   }


    
    if ($ui->{read_only}) {
        write_XHTML_prologue($fh, $homeBase, "Password Reset Rejected", undef, $CGIargs{HDiet_handheld});
        my $arghandheld = $CGIargs{HDiet_handheld} ? '&amp;HDiet_handheld=y' : '';
        my $qun = quoteHTML($CGIargs{HDiet_username});

        print $fh <<"EOD";
<h1 class="c">Password Reset Rejected</h1>

<p class="justified">
This is a read-only demonstration account.  You are not permitted
to request a password reset.  You can sign in to this account in
read-only mode using a blank password.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=login$arghandheld$tzOff">Sign In</a></h4>
<h4 class="nav"><a href="/cgi-bin/HackDiet?q=pwreset$arghandheld&amp;HDiet_username=$qun$tzOff">Password Reset</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        last;
   }


    
    if ((!$readOnly) && (-f "/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda")
        && open(FS, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda")) {
        my $asn = load_active_session(\*FS);
        close(FS);
        unlink("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
        clusterDelete("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
        unlink("/server/pub/hackdiet/Sessions/$asn.hds");
        clusterDelete("/server/pub/hackdiet/Sessions/$asn.hds");
        append_history($user_file_name, 3);
    }


    $ui->resetPassword(8);

    
    open(FU, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    $ui->save(\*FU);
    close(FU);
    clusterCopy("/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");


    
    $ui->sendMail("Password reset",
"Your password for The Hacker's Diet Online:

    http://www.fourmilab.ch/cgi-bin/HackDiet

has been reset at your request.  The new password is:

    $ui->{password}

You must enter the password exactly as given above; upper and
lower case letters are not the same.  After logging into your
account with this new password, you are encouraged to change
your password to something easier to remember, but difficult
for a stranger to guess.
\n");


    
    write_XHTML_prologue($fh, $homeBase, "Password Reset and Mailed", undef, $CGIargs{HDiet_handheld});
    my ($qun, $qem) = (quoteHTML($ui->{login_name}), quoteHTML($ui->{e_mail}));
    print $fh <<"EOD";
<h1 class="c">Password Reset and Mailed</h1>
<form id="Hdiet_password_reset_confirmation" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
EOD

    
    if ($CGIargs{HDiet_handheld}) {
        print $fh <<"EOD";
<div><input type="hidden" name="HDiet_handheld" value="y" /></div>
EOD
    }


    print $fh <<"EOD";
<p class="justified">
The password for your Hacker's Diet Online account:
</p>

<blockquote>
    <p><b>$qun</b></p>
</blockquote>

<p class="justified">
has been reset to a randomly-generated value which has
been sent to your E-mail address:
</p>

<blockquote>
    <p><b>$qem</b></p>
</blockquote>

<p class="justified">
Once you receive this E-mail, return to the login page
and enter the new password to access your account.
</p>

<p class="mlog_buttons">
<input type="hidden" name="q" value="login" />
<input type="hidden" name="HDiet_username" value="$ui->{login_name}" />
<input type="submit" name="reset" value=" Return to Login Page " />
</p>
</form>
EOD
    write_XHTML_epilogue($fh, $homeBase);


    append_history($user_file_name, 6);


    } elsif ($CGIargs{q} eq 'log') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    if (defined($CGIargs{new_y}) && defined($CGIargs{new_m}) &&
        (!defined($CGIargs{m}))) {
        $CGIargs{m} = sprintf("%04d-%02d", $CGIargs{new_y}, $CGIargs{new_m});
    }

    #   If the date argument is "now", fill in the current year and month
    $CGIargs{m} = "now" if !defined($CGIargs{m});
    my ($year, $mon, $mday, $hour, $min, $sec) =
        unix_time_to_civil_date_time($userTime);
    my $nowmonth = sprintf("%04d-%02d", $year, $mon);
    if ($CGIargs{m} eq "now") {
        $CGIargs{m} = $nowmonth;
    }


    
    
    if (!(($CGIargs{m} =~ m/^(\d\d\d\d)\-(\d\d)$/) &&
        ($1 >= 1980) && ($1 <= ((unix_time_to_civil_date_time($userTime))[0] + 1)) &&
        ($2 >= 1) && ($2 <= 12))) {
        if (!$inHTML) {
            if ($ENV{'REQUEST_METHOD'}) {
                
    print($fh "Content-type: text/html\r\n\r\n");

            }
            $inHTML = 1;
        }
        write_XHTML_prologue($fh, $homeBase, "Create New User Account", undef, $session->{handheld});
        my $qm = quoteHTML($CGIargs{m});
        print $fh <<"EOD";
<h1 class="c">Invalid Log Date Specification</h1>

<p class="justified">
Your request specified an invalid date:
</p>

<p class="centred">
<tt>$qm</tt>
</p>

<p class="justified">
for a monthly log.  Dates must be specified as &ldquo;<i>YYYY</i><tt>-</tt><i>MM</i>&rdquo;.
</p>


<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account home page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        last;
    }


    my $mlog = HDiet::monthlog->new();
    if (-f "/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb") {
        open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb") ||
            die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb");
        $mlog->load(\*FL);
        close(FL);
    } else {
        $mlog->{login_name} = $user_name;
        $CGIargs{m} =~ m/(^\d+)\-(\d+)$/;
        my ($yy, $mm) = ($1, $2);
        $mlog->{year} = $yy + 0;
        $mlog->{month} = $mm + 0;
        $mlog->{log_unit} = $ui->{log_unit};
        $mlog->{last_modification_time} = 0;
        $mlog->{trend_carry_forward} = 0;
    }
    
    if ($mlog->{trend_carry_forward} == 0) {
        my $cmon = sprintf("%04d-%02d", $mlog->{year}, $mlog->{month});
        my @logs = $ui->enumerateMonths();
        for (my $m = $#logs; $m >= 0; $m--) {
            if ($logs[$m] lt $cmon) {
                my $llog = HDiet::monthlog->new();
                open(LL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$m].hdb") ||
                    die("Cannot open previous monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$m].hdb");
                $llog->load(\*LL);
                close(LL);
                for (my $d = $llog->monthdays(); $d >= 1; $d--) {
                    if ($llog->{trend}[$d]) {
                        $mlog->{trend_carry_forward} = $llog->{trend}[$d] *
                            HDiet::monthlog::WEIGHT_CONVERSION->[$llog->{log_unit}][$mlog->{log_unit}];;
                        last;
                    }
                }
                last;
            }
        }
    }



    write_XHTML_prologue($fh, $homeBase,
        "Monthly log for " . $monthNames[$mlog->{month}] . " " . $mlog->{year},
        "setResizeEventHandle();", $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id},
        (($CGIargs{m} eq $nowmonth) ? "Log" : undef),
        'onclick="return leaveDocument();"', $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<form id="monthlog" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
EOD

    my $printFriendly = defined($CGIargs{print}) && $CGIargs{print};
    my $monochrome = defined($CGIargs{mono}) && $CGIargs{mono};
    my $printfix = ($printFriendly ? 'pr_' : '') . ($monochrome ? 'mo_' : '');

    
    my $monthyear = $monthNames[$mlog->{month}] . " " . $mlog->{year};

    my ($lasty, $lastm) = $mlog->previousMonth();
    my $slast = sprintf("%04d-%02d", $lasty, $lastm);
    my ($slast_link, $slast_button);
    my $modeArgs = '';
    $modeArgs .= '&amp;print=y' if $CGIargs{print};
    $modeArgs .= '&amp;mono=y' if $CGIargs{mono};
    if ($slast ne '') {
        $slast_link = "<a class=\"i\" href=\"/cgi-bin/HackDiet?q=log&amp;" .
            "HDiet_tzoffset=$timeZoneOffset&amp;" .
            "s=$session->{session_id}&amp;m=$slast$modeArgs\" onclick=\"return leaveDocument();\">";
        if ($session->{handheld}) {
            $slast_button = "$slast_link<b>&lt;</b></a>";
        } else {
            $slast_button = "$slast_link<img src=\"$homeBase/figures/prev.png\" class=\"b0\" width=\"32\" height=\"32\" alt=\"Previous month: $slast\" /></a>";
        }
    } else {
        if ($session->{handheld}) {
            $slast_button = "<b>&lt;</b>";
        } else {
            $slast_button = "<img src=\"$homeBase/figures/prev_gr.png\" class=\"b0\" width=\"32\" height=\"32\" alt=\"No previous month\" />";
        }
    }

    my ($nexty, $nextm) = $mlog->nextMonth();
    my $snext = sprintf("%04d-%02d", $nexty, $nextm);
    my ($snext_link, $snext_button);
    if ($snext ne '') {
        $snext_link = "<a class=\"i\" href=\"/cgi-bin/HackDiet?q=log&amp;" .
            "HDiet_tzoffset=$timeZoneOffset&amp;" .
            "s=$session->{session_id}&amp;m=$snext$modeArgs\" onclick=\"return leaveDocument();\">";
        if ($session->{handheld}) {
            $snext_button = "$snext_link<b>&gt;</b></a>";
        } else {
            $snext_button = "$snext_link<img src=\"$homeBase/figures/next.png\" class=\"b0\" width=\"32\" height=\"32\" alt=\"Next month: $snext\" /></a>";
        }
    } else {
        if ($session->{handheld}) {
            $snext_button = "<b>&gt;</b>";
        } else {
            $snext_button = "<img src=\"$homeBase/figures/next_gr.png\" class=\"b0\" width=\"32\" height=\"32\" alt=\"No next month\" />";
        }
    }

    print($fh "<h1 class=\"${printfix}monthyear\">" .
              $slast_button .
              ' &nbsp; <span>' .
              $monthyear .
              "</span> &nbsp; $snext_button</h1>\n");


    
    my $mdays = $mlog->monthdays();
    my $fracf = $mlog->fractionFlagged();
    my $mbmi = $mlog->bodyMassIndex($ui->{height});
    my $lbmi = $mlog->bodyMassIndex($ui->{height}, -1);
    my $qun = quoteHTML($user_name);
    my $t0 = $mlog->{trend_carry_forward} * HDiet::monthlog::WEIGHT_CONVERSION->[$mlog->{log_unit}][$ui->{display_unit}];
    my @dcalc;
    if ($ui->{plot_diet_plan}) {
        @dcalc = $ui->dietPlanLimits();
    }

    my $iscale = $mlog->computeChartScale(640, 480, $ui->{display_unit}, \@dcalc);

    
    my $cachebuster = sprintf("%x", (int(rand(65536))) & 0xFFFF);
    $cachebuster =~ tr/a-f/FGJKQW/;



    my $mlw = $session->{handheld} ? 320 : 640;
    my $mlh = $session->{handheld} ? 240 : 480;

    print $fh <<"EOD";
<div id="canvas" class="canvas"></div>
<p class="trendan">
<script type="text/javascript" src="/hackdiet/online/wz_jsgraphics.js"></script>
<img id="chart" src="/cgi-bin/HackDiet?q=chart&amp;s=$session->{session_id}&amp;m=$CGIargs{m}$modeArgs&amp;qx=$cachebuster$tzOff"
     width="$mlw" height="$mlh" alt="Chart for $monthyear" />
<br />

<input type="hidden" name="q" value="update_log" />
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="hidden" name="m" value="$CGIargs{m}" />
<input type="hidden" name="md" id="md" value="$mdays" />
<input type="hidden" name="t0" id="t0" value="$t0" />
<input type="hidden" name="du" id="du" value="$ui->{display_unit}" />
<input type="hidden" name="hgt" id="hgt" value="$ui->{height}" />
<input type="hidden" name="dc" id="dc" value="$ui->{decimal_character}" />
<input type="hidden" name="sc" id ="sc" value="$iscale" />

EOD

    
    my $tslope = 0;
    my $hist = HDiet::history->new($ui, $user_file_name);
    my ($ly, $lm, $ld, $ldu, $lw, $lt) = $hist->lastDay();

#print(STDERR "Last day: $ly-$lm-$ld  ($mlog->{year}-$mlog->{month})   Lw $lw   Lt $lt\n");
    if (defined($lw) &&
        ($mlog->{year} == $ly) &&
        ($mlog->{month} == $lm)) {
#print(STDERR "Computed trend the hard way for $ly-$lm-$ld\n");
        my $l_jd = gregorian_to_jd($ly, $lm, $ld);
        my ($s_y, $s_m, $s_d) = $hist->firstDay();
        my $s_jd = gregorian_to_jd($s_y, $s_m, $s_d);

        my (@intervals, @slopes);

        if (($l_jd - $s_jd) > 1) {
            my ($f_y, $f_m, $f_d) = $hist->firstDayOfInterval($ly, $lm, $ld, 7);
            my $f_jd = gregorian_to_jd($f_y, $f_m, $f_d);
            push(@intervals, sprintf("%04d-%02d-%02d", $f_y, $f_m, $f_d),
                              sprintf("%04d-%02d-%02d", $ly, $lm, $ld));
            @slopes = $hist->analyseTrend(@intervals);
            $tslope = $slopes[0];
        }
    } else {
#print(STDERR "Computed trend the easy way for $ly-$lm-$ld\n");
        $tslope = $mlog->computeTrend();
        $tslope *= HDiet::monthlog::WEIGHT_CONVERSION->[$mlog->{log_unit}][$ui->{display_unit}];
    }
    my $sweekly = $ui->localiseDecimal(sprintf("%.2f", abs($tslope) * 7));
    print($fh 'Weekly <span id="delta_sign">' .
            (($tslope > 0) ? "gain" : "loss") .
            "</span> <span id=\"weekly_delta\">$sweekly</span> " .
            $mlog->DELTA_WEIGHT_UNITS->[$ui->{display_unit}] .
            "s.  Daily <span id=\"calorie_sign\">" .
            (($tslope > 0) ? "excess" : "deficit") .
            sprintf("</span>: <span id=\"daily_calories\">%.0f</span> ", abs($tslope) *
                ($mlog->CALORIES_PER_WEIGHT_UNIT->[$ui->{display_unit}] /
                $mlog->CALORIES_PER_ENERGY_UNIT->[$ui->{energy_unit}])) .
            $mlog->ENERGY_UNITS->[$ui->{energy_unit}] . "s" .
            "." .
            (($fracf > 0) ? sprintf("  <span id=\"fracf\" " .
                "style=\"display: inline;\"><span id=\"percent_flagged\">" .
                "%.0f%%</span> flagged.</span>", $fracf * 100) :
                            sprintf("  <span id=\"fracf\" " .
                "style=\"display: none;\"><span id=\"percent_flagged\">" .
                "%.0f%%</span> flagged.</span>", $fracf * 100)));

    if ($mbmi > 0) {
        my ($lmbmi, $llbmi) = ($ui->localiseDecimal($mbmi), $ui->localiseDecimal($lbmi));
        print($fh "\n<span id=\"bmi\" style=\"display: inline;\">" .
            "<br />\nBody mass index: mean <span id=\"mean_bmi\">" .
            "$lmbmi</span>, most recent <span id=\"last_bmi\">$llbmi</span>.</span>\n");
    } else {
        print($fh "\n<span id=\"bmi\" style=\"display: none;\">" .
            "<br />\nBody mass index: mean <span id=\"mean_bmi\">" .
            "???</span>, most recent <span id=\"last_bmi\">???</span>.</span>\n");
    }


    print($fh "</p>\n");

    $mlog->toHTML($fh, 1, 31,
        $ui->{display_unit}, $ui->{decimal_character}, $browse_public,
        $printFriendly, $monochrome);

    
    if ($browse_public) {
        print $fh <<"EOD";
</form>
EOD
    } else {
        my $ckprint = $CGIargs{print} ? ' checked="checked"' : '';
        my $ckmono = $CGIargs{mono} ? ' checked="checked"' : '';

        print $fh <<"EOD";
<p class="mlog_buttons">
<input type="submit" value=" Update " />
&nbsp;
<input type="reset" onclick="unsavedChanges = 0;" value=" Reset " />
<br />
<label><input type="checkbox" name="print" value="y"$ckprint  />&nbsp;Printer&nbsp;friendly</label>
&nbsp;
<label><input type="checkbox" name="mono" value="y"$ckmono  />&nbsp;Monochrome</label>
EOD

        
    if ($ui->{administrator} || $assumed_identity) {
        my $ckdl = $CGIargs{dumplog} ? ' checked="checked"' : '';
        my $ckdu = $CGIargs{dumpuser} ? ' checked="checked"' : '';
        my $ckds = $CGIargs{dumpsession} ? ' checked="checked"' : '';
        my $ckde = $CGIargs{dumpenvironment} ? ' checked="checked"' : '';
        print $fh <<"EOD";
<br />
Dump: <label><input type="checkbox" name="dumplog" value="y"$ckdl  />&nbsp;Log</label>
      <label><input type="checkbox" name="dumpuser" value="y"$ckdu  />&nbsp;User</label>
      <label><input type="checkbox" name="dumpsession" value="y"$ckds  />&nbsp;Session</label>
      <label><input type="checkbox" name="dumpenvironment" value="y"$ckde  />&nbsp;Environment</label>
EOD
    }


        print $fh <<"EOD";
</p>
</form>
EOD
    }

    
    if ($ui->{administrator} || $assumed_identity) {

        sub describeHTML {
            my ($object, $fh, $title) = @_;

            print($fh "<h4>$title</h4>\n") if $title;
            print($fh "<pre style=\"unicode-bidi: bidi-override;\">\n");
            use File::Temp qw(tempfile);
            my $tfh = tempfile();
            binmode($tfh, ":utf8");
            $object->describe($tfh);
            seek($tfh, 0, 0);
            quoteHTMLFile($tfh, $fh);
            close($tfh);
            print($fh "</pre>\n");
        }

        if ($CGIargs{dumplog}) {
            describeHTML($mlog, $fh, "Log");
        }
        if ($CGIargs{dumpuser}) {
            describeHTML($ui, $fh, "User");
        }
        if ($CGIargs{dumpsession}) {
            describeHTML($session, $fh, "Session");
        }
        if ($CGIargs{dumpenvironment}) {
            use Data::Dumper;
            my $denv = Data::Dumper->Dump([\%CGIargs, \%ENV], ['*CGIargs', '*ENV']);
            $denv = quoteHTML($denv);
            print($fh "<h4>Environment</h4>\n");
            print($fh "<pre style=\"unicode-bidi: bidi-override;\">\n");
            print($fh $denv);
            print($fh "</pre>\n");
        }
    }

    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'update_log') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);


    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    
    if (!(($CGIargs{m} =~ m/^(\d\d\d\d)\-(\d\d)$/) &&
        ($1 >= 1980) && ($1 <= ((unix_time_to_civil_date_time($userTime))[0] + 1)) &&
        ($2 >= 1) && ($2 <= 12))) {
        if (!$inHTML) {
            if ($ENV{'REQUEST_METHOD'}) {
                
    print($fh "Content-type: text/html\r\n\r\n");

            }
            $inHTML = 1;
        }
        write_XHTML_prologue($fh, $homeBase, "Create New User Account", undef, $session->{handheld});
        my $qm = quoteHTML($CGIargs{m});
        print $fh <<"EOD";
<h1 class="c">Invalid Log Date Specification</h1>

<p class="justified">
Your request specified an invalid date:
</p>

<p class="centred">
<tt>$qm</tt>
</p>

<p class="justified">
for a monthly log.  Dates must be specified as &ldquo;<i>YYYY</i><tt>-</tt><i>MM</i>&rdquo;.
</p>


<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account home page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        last;
    }


    my $mlog = HDiet::monthlog->new();
    if (-f "/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb") {
        open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb") ||
            die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb");
        $mlog->load(\*FL);
        close(FL);
    } else {
        $mlog->{login_name} = $user_name;
        $CGIargs{m} =~ m/(^\d+)\-(\d+)$/;
        my ($yy, $mm) = ($1, $2);
        $mlog->{year} = $yy + 0;
        $mlog->{month} = $mm + 0;
        $mlog->{log_unit} = $ui->{log_unit};
        $mlog->{last_modification_time} = 0;
        $mlog->{trend_carry_forward} = 0;
    }
    
    if ($mlog->{trend_carry_forward} == 0) {
        my $cmon = sprintf("%04d-%02d", $mlog->{year}, $mlog->{month});
        my @logs = $ui->enumerateMonths();
        for (my $m = $#logs; $m >= 0; $m--) {
            if ($logs[$m] lt $cmon) {
                my $llog = HDiet::monthlog->new();
                open(LL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$logs[$m].hdb") ||
                    die("Cannot open previous monthly log file /server/pub/hackdiet/Users/$user_file_name/$logs[$m].hdb");
                $llog->load(\*LL);
                close(LL);
                for (my $d = $llog->monthdays(); $d >= 1; $d--) {
                    if ($llog->{trend}[$d]) {
                        $mlog->{trend_carry_forward} = $llog->{trend}[$d] *
                            HDiet::monthlog::WEIGHT_CONVERSION->[$llog->{log_unit}][$mlog->{log_unit}];;
                        last;
                    }
                }
                last;
            }
        }
    }



    my ($changes, $change_weight, $change_rung,
        $change_flag, $change_comment) = $mlog->updateFromCGI(\%CGIargs);

    
    if (($changes > 0) && (!$readOnly)) {
        $mlog->{last_modification_time} = time();
        open(FL, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb") ||
            die("Cannot update monthly log file /server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb");
        $mlog->save(\*FL);
        close(FL);
        clusterCopy("/server/pub/hackdiet/Users/$user_file_name/$CGIargs{m}.hdb");

        if ($ui->{badge_trend} != 0) {
            
    open(FB, ">/server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png") ||
        die("Cannot update monthly log file /server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png");
    my $hist = HDiet::history->new($ui, $user_file_name);
    $hist->drawBadgeImage(\*FB, $ui->{badge_trend});
    close(FB);
    do_command("mv /server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png /server/pub/hackdiet/Users/$user_file_name/BadgeImage.png");
    clusterCopy("/server/pub/hackdiet/Users/$user_file_name/BadgeImage.png");

        }

        append_history($user_file_name, 5,
            "$CGIargs{m},$changes,$change_weight,$change_rung,$change_flag,$change_comment");

        update_last_transaction($user_file_name);

        if ($change_weight > 0) {
#print("Propagating trend starting at $CGIargs{m}<br />\n");
            propagate_trend($ui, $CGIargs{m}, 0);
        }
    }


        #   Enqueue a transaction to display the updated log
        %CGIargs = (
            q => "log",
            s => $session->{session_id},
            m => $CGIargs{m},
            dumplog => $CGIargs{dumplog},
            dumpuser => $CGIargs{dumpuser},
            dumpsession => $CGIargs{dumpsession},
            dumpenvironment => $CGIargs{dumpenvironment},
            print => $CGIargs{print},
            mono => $CGIargs{mono},
        );
        next;

    } elsif ($CGIargs{q} eq 'calendar') {
        
    my $calPerLine = 4;             # Calendars per line

    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    my $qun = quoteHTML($user_name);
    write_XHTML_prologue($fh, $homeBase, "Choose Monthly Log", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, "History", undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    $calPerLine = 1 if $session->{handheld};

    print $fh <<"EOD";
<h1 class="c">Choose Monthly Log</h1>
<table class="list_of_calendars">
EOD

    my ($intr, $calsline) = (0, 0);

    my @years = $ui->enumerateYears();

    
    for (my $y = 0; $y <= $#years; $y++) {

        if (!$intr) {
            print($fh "<tr>\n");
            $intr = 1;
            $calsline = 0;
        }

        if ($calsline >= $calPerLine) {
            print($fh "</tr><tr>\n");
            $calsline = 0;
        }

        print $fh <<"EOD";
<td><table class="calendar" border="border">
<tr><th colspan="3">$years[$y]</th></tr>
EOD
        my @months = $ui->enumerateMonths($years[$y]);
        my $m = 0;
        for (my $i = 0; $i < 4; $i++) {
        print $fh <<"EOD";
    <tr>
EOD
            for (my $j = 0; $j < 3; $j++) {
                $m++;
                print($fh "        <td>");
                my $ym = sprintf("%04d-%02d", $years[$y], $m);
                my $havemonth = 0;
                for (my $k = 0; $k <= $#months; $k++) {
                    if ($months[$k] eq $ym) {
                        print($fh "<a href=\"/cgi-bin/HackDiet?s=$session->{session_id}&amp;q=log&amp;m=$ym$tzOff\">");
                        $havemonth = 1;
                        last;
                    }
                }
                print($fh substr($monthNames[$m], 0, 3));
                if ($havemonth) {
                    print($fh "</a>");
                }
                print($fh "</td>\n");
            }
        print $fh <<"EOD";
    </tr>
EOD
        }
        print $fh <<"EOD";
</table></td>
EOD
        $calsline++;
    }


    if ($intr) {
        print($fh "</tr>\n");
    }

    print $fh <<"EOD";
</table>
EOD

    if (!$browse_public) {
        
    print $fh <<"EOD";
<form id="Hdiet_create_new_monthly_log" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
<p>
<input type="hidden" name="q" value="log" />
<input type="hidden" name="s" value="$session->{session_id}" />
<b>Create/display log for:</b>
<select name="new_m" id="new_m">
EOD

    my ($year, $mon, $mday, $hour, $min, $sec) =
        unix_time_to_civil_date_time($userTime);
    for (my $i = 1; $i <= 12; $i++) {
        my $sel = ($i == $mon) ? ' selected="selected"' : '';
        print($fh "<option value=\"$i\"$sel>$monthNames[$i]</option>\n")
    }

    print $fh <<"EOD";
</select>

<select name="new_y" id="new_y">
EOD

    for (my $y = $year; $y >= 1985; $y--) {
        print($fh "<option>$y</option>\n")
    }

    print $fh <<"EOD";
</select>

<label title="Create/display log for the specified month and year"><input type="submit" value=" Create Log " /></label>
</p>
</form>
EOD

    }

    write_XHTML_epilogue($fh, $homeBase);

    update_last_transaction($user_file_name);

    } elsif ($CGIargs{q} eq 'trendan') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    my @years = $ui->enumerateYears();

    write_XHTML_prologue($fh, $homeBase, "Trend Analysis", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, "Trend", undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    if ($#years >= 0) {
        
    print $fh <<"EOD";
<h1 class="c">Trend Analysis</h1>
EOD

    
    my $hist = HDiet::history->new($ui, $user_file_name);
    my ($s_y, $s_m, $s_d) = $hist->firstDay();
    my $s_jd = gregorian_to_jd($s_y, $s_m, $s_d);
    my ($l_y, $l_m, $l_d) = $hist->lastDay();
    my $l_jd = gregorian_to_jd($l_y, $l_m, $l_d);


    
    my (@intervals, @dayspan);
    for my $interval (7, 14, -1, -3, -6, -12) {
        my ($f_y, $f_m, $f_d) = $hist->firstDayOfInterval($l_y, $l_m, $l_d, $interval);
        my $f_jd = gregorian_to_jd($f_y, $f_m, $f_d);
        if ($f_jd < $s_jd) {
            last;
        }
        push(@intervals, sprintf("%04d-%02d-%02d", $f_y, $f_m, $f_d),
                          sprintf("%04d-%02d-%02d", $l_y, $l_m, $l_d));
        push(@dayspan, ($l_jd - $f_jd) + 1);
    }


    
    my $custom = $CGIargs{period} && ($CGIargs{period} eq 'c');
    my ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd,
        $cust_end_y, $cust_end_m, $cust_end_d,$cust_end_jd);
    if ($custom) {
        ($cust_start_y, $cust_start_m, $cust_start_d) = ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d});
        $cust_start_jd = gregorian_to_jd($cust_start_y, $cust_start_m, $cust_start_d);
        ($cust_end_y, $cust_end_m, $cust_end_d) = ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d});
        $cust_end_jd = gregorian_to_jd($cust_end_y, $cust_end_m, $cust_end_d);

        if ($cust_end_jd != $cust_start_jd) {
            #   If start or end of interval is outside the database,
            #   constrain it to the  first or last entry.
            if (($cust_start_jd < $s_jd) || ($cust_start_jd > $l_jd)) {
                ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd) =
                    ($s_y, $s_m, $s_d, $s_jd);
               ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d}) =
                    ($cust_start_y, $cust_start_m, $cust_start_d);
            }
            if (($cust_end_jd < $s_jd) || ($cust_end_jd > $l_jd)) {
                ($cust_end_y, $cust_end_m, $cust_end_d, $cust_end_jd) =
                    ($l_y, $l_m, $l_d, $l_jd);
                ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d}) =
                    ($cust_end_y, $cust_end_m, $cust_end_d);
            }

            #   If end of interval is before start, reverse them
            if ($cust_end_jd < $cust_start_jd) {
                my @temp = ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd);
                ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd) =
                    ($cust_end_y, $cust_end_m, $cust_end_d, $cust_end_jd);
                ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d}) =
                    ($cust_start_y, $cust_start_m, $cust_start_d);
                ($cust_end_y, $cust_end_m, $cust_end_d, $cust_end_jd) = @temp;
                ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d}) =
                    ($cust_end_y, $cust_end_m, $cust_end_d);
            }
        } else {
            $custom = 0;                # Void interval disables custom display
            $CGIargs{period} = '';
        }
    }


    if ($custom) {
        push(@intervals, sprintf("%04d-%02d-%02d", $cust_start_y, $cust_start_m, $cust_start_d),
                          sprintf("%04d-%02d-%02d", $cust_end_y, $cust_end_m, $cust_end_d));
        push(@dayspan, ($cust_end_jd - $cust_start_jd) + 1);
    }

    
    if ($#intervals >= 0) {
        my $wu = HDiet::monthlog::DELTA_WEIGHT_UNITS->[$ui->{display_unit}];
        my $eu = HDiet::monthlog::ENERGY_UNITS->[$ui->{energy_unit}];

        print $fh <<"EOD";
<table class="trendan" border="border">
<tr>
    <th class="custitle" colspan="6">Intervals ending $intervals[1]</th>
</tr>
<tr>
    <th rowspan="2">Last&hellip;</th>
    <th rowspan="2"><span class="r">Gain</span>/<span class="g">Loss</span><br /> ${wu}s/week</th>
    <th rowspan="2"><span class="r">Excess</span>/<span class="g">Deficit</span><br />${eu}s/day</th>
    <th colspan="3" style="border-bottom: none;">Weight Trend</th>
</tr>
<tr>
    <th style="border-top: none; border-right: none;">Min.</th>
    <th style="border-top: none; border-left: none; border-right: none;">Mean</th>
    <th style="border-top: none; border-left: none;">Max.</th>
</tr>
EOD
        my @slopes = $hist->analyseTrend(@intervals);
        my @inames = ( 'Week', 'Fortnight', 'Month', 'Quarter', 'Six months', 'Year' );

        
    for (my $i = 0; $i < (($#slopes + 1) / 4); $i++) {
        my $tslope = $slopes[$i * 4];
        my $deltaW = sprintf("%.2f", $tslope * 7);
        $deltaW =~ s/\./$ui->{decimal_character}/;
        my $deltaE = sprintf("%.0f", $tslope *
            (HDiet::monthlog::CALORIES_PER_WEIGHT_UNIT->[$ui->{display_unit}] /
             HDiet::monthlog::CALORIES_PER_ENERGY_UNIT->[$ui->{energy_unit}]));
        my $colour = $tslope > 0 ? 'r' : 'g';
        my $ecolour = $colour;
        if ($deltaW =~ m/^\-?0[\.,]00$/) {
            $colour = 'bk';
            $deltaW =~ s/^\-//;
        } else {
            $deltaW =~ s/^(\d)/\+$1/;
        }
        if ($deltaE =~ m/^\-?0$/) {
            $ecolour = 'bk';
            $deltaE =~ s/^\-//;
        } else {
            $deltaE =~ s/^(\d)/\+$1/;
        }
        $deltaW =~ s/\-/&minus;/;
        $deltaE =~ s/\-/&minus;/;

        my $eMinWeight = HDiet::monthlog::editWeight($slopes[($i * 4) + 1],
            $ui->{display_unit}, $ui->{decimal_character});
        my $eMaxWeight = HDiet::monthlog::editWeight($slopes[($i * 4) + 2],
            $ui->{display_unit}, $ui->{decimal_character});
        my $eMeanWeight = HDiet::monthlog::editWeight($slopes[($i * 4) + 3],
            $ui->{display_unit}, $ui->{decimal_character});

        
#print(STDERR "Custom $custom $i $#slopes\n");
    if ($custom && ($i == (($#slopes + 1) / 4) - 1)) {
        print $fh <<"EOD";
<tr>
    <th class="custitle" colspan="6">$intervals[$i * 2] &ndash; $intervals[($i * 2) + 1]</th>
</tr>
EOD
        my ($cd_y, $cd_m, $cd_d) = (0, 0, 0);
        my $cd_lastm = $cust_end_jd;
        while (1) {
            my ($ly, $lm, $ld) = $hist->firstDayOfInterval($cust_end_y, $cust_end_m, $cust_end_d, -($cd_m + 1));
            my $mjd = gregorian_to_jd($ly, $lm, $ld);
            if ($mjd < $cust_start_jd) {
                last;
            }
            $cd_m++;
            $cd_lastm = $mjd;
        }
        $cd_d = $cd_lastm - $cust_start_jd;
        $cd_y = int($cd_m / 12);
        $cd_m %= 12;
        my $custdur = (($cd_y > 0) ? "$cd_y y " : '') .
                      (($cd_m > 0) ? "$cd_m m " : '') .
                      (($cd_d > 0) ? "$cd_d d " : '');
        $inames[$i] = $custdur;
    }


        print $fh <<"EOD";
<tr>
    <td>$inames[$i]</td>
    <td class="w"><span class="$colour">$deltaW</span></td>
    <td class="e"><span class="$ecolour">$deltaE</span></td>
    <td class="e">$eMinWeight</td>
    <td class="e">$eMeanWeight</td>
    <td class="e">$eMaxWeight</td>
</tr>
EOD
        }

        print $fh <<"EOD";
</table>
EOD
    } else {
        print $fh <<"EOD";
<h2>There are insufficient log entries to perform
trend analysis.  You need at least a week's data
to compute a trend.</h2>
EOD
    }


    

    my %percheck = ( 'm', '', 'q', '', 'h', '', 'y', '', 'c', '' );

    if (defined($CGIargs{period})) {
        $percheck{$CGIargs{period}} = ' checked="checked"';
    } else {
        $percheck{q} = ' checked="checked"';
    }

    my (@fy_selected, @ty_selected);
    for (my $i = 0; $i <= $#years; $i++) {
        if (defined($CGIargs{from_y}) && ($CGIargs{from_y} eq $years[$i])) {
            $fy_selected[$i] = ' selected="selected"';
        } else {
            $fy_selected[$i] = '';
        }
        if (defined($CGIargs{to_y}) && ($CGIargs{to_y} eq $years[$i])) {
            $ty_selected[$i] = ' selected="selected"';
        } else {
            $ty_selected[$i] = '';
        }
    }

    my (@fm_selected, @tm_selected);
    for (my $i = 1; $i <= 12; $i++) {
        if (defined($CGIargs{from_m}) && ($CGIargs{from_m} == $i)) {
            $fm_selected[$i] = ' selected="selected"';
        } else {
            $fm_selected[$i] = '';
        }
        if (defined($CGIargs{to_m}) && ($CGIargs{to_m} == $i)) {
            $tm_selected[$i] = ' selected="selected"';
        } else {
            $tm_selected[$i] = '';
        }
    }

    my (@fd_selected, @td_selected);
    for (my $i = 1; $i <= 31; $i++) {
        if (defined($CGIargs{from_d}) && ($CGIargs{from_d} == $i)) {
            $fd_selected[$i] = ' selected="selected"';
        } else {
            $fd_selected[$i] = '';
        }
        if (defined($CGIargs{to_d}) && ($CGIargs{to_d} == $i)) {
            $td_selected[$i] = ' selected="selected"';
        } else {
            $td_selected[$i] = '';
        }
    }

    my @cs_selected;
    $CGIargs{size} = '800x600' if !defined($CGIargs{size});
    $CGIargs{size} = '320x240' if $session->{handheld};
    for (my $i = 0; $i <= $#chartSizes; $i++) {
        if ($CGIargs{size} eq $chartSizes[$i]) {
            $cs_selected[$i] = ' selected="selected"';
        } else {
            $cs_selected[$i] = '';
        }
    }

    my $ckprint = $CGIargs{print} ? ' checked="checked"' : '';
    my $ckmono = $CGIargs{mono} ? ' checked="checked"' : '';


    
    print $fh <<"EOD";
<form id="Hdiet_histchart" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
<p class="mlog_buttons">
<label><input type="checkbox" name="period" value="c"$percheck{c} />&nbsp;<b>Custom</b></label>
EOD

    
    my @f_mon;
    my $fmon;
    if (!$CGIargs{from_y}) {
        $fy_selected[0] = ' selected="selected"';
        @f_mon = $ui->enumerateMonths($years[0]);
        $f_mon[0] =~ m/^\d+\-(\d+)$/;
        $fmon = $1 + 0;
        $fm_selected[$fmon] = ' selected="selected"';
        $fd_selected[$s_d] = ' selected="selected"';
    }

    print($fh "From\n");
    
    my ($ysel, $msel, $dsel) = ("") x 3;
    if ("") {
        $ysel = ' onchange="change_from_y();"';
        $msel = ' onchange="change_from_m();"';
        $dsel = ' onchange="change_from_d();"';
    }

    print $fh <<"EOD";
    <select name="from_y" id="from_y"$ysel>
EOD

    
    for (my $i = 0; $i <= $#years; $i++) {
        print $fh <<"EOD";
        <option$fy_selected[$i]>$years[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>&nbsp;<select name="from_m" id="from_m"$msel>
EOD

    my $mid = "fm_";
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


        print $fh <<"EOD";
    </select>
EOD

    if (1) {
        print $fh <<"EOD";
    <select name="from_d" id="from_d"$dsel>
EOD
    }

    my $did;

    if (1) {
        $did = "fd_";
        
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


        print $fh <<"EOD";
        </select>
EOD
    }


    print $fh <<"EOD";
<br />
EOD

    if (!$CGIargs{to_y}) {
        $ty_selected[$#years] = ' selected="selected"';
        @f_mon = $ui->enumerateMonths($years[$#years]);
        $f_mon[$#f_mon] =~ m/^\d+\-(\d+)$/;
        $fmon = $1 + 0;
        $tm_selected[$fmon] = ' selected="selected"';
        $td_selected[$l_d] = ' selected="selected"';
    }

    print($fh "To\n");
    
    ($ysel, $msel, $dsel) = ("") x 3;
    if ("") {
        $ysel = ' onchange="change_to_y();"';
        $msel = ' onchange="change_to_m();"';
        $dsel = ' onchange="change_to_d();"';
    }
    print $fh <<"EOD";
    <select name="to_y" id="to_y"$ysel>
EOD

    @fy_selected = @ty_selected;
    
    for (my $i = 0; $i <= $#years; $i++) {
        print $fh <<"EOD";
        <option$fy_selected[$i]>$years[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>&nbsp;<select name="to_m" id="to_m"$msel>
EOD

    $mid = "tm_";
    @fm_selected = @tm_selected;
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>
EOD

    if (1) {
        print $fh <<"EOD";
    <select name="to_d" id="to_d"$dsel>
EOD
    }

    if (1) {
        $did = "td_";
        @fd_selected = @td_selected;
        
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


        print $fh <<"EOD";
    </select>
EOD
    }



    print $fh <<"EOD";
<br />

<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=trendan" value=" Update " />
&nbsp;
<input type="reset" value=" Reset " />
</p>
</form>
EOD


    } else {
        print $fh <<"EOD";
        <h2>You have no log entries!  You must enter weight logs
            before you can perform trend analysis.</h2>
EOD
    }

    print $fh <<"EOD";

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Back to account page</a></h4>
EOD

    write_XHTML_epilogue($fh, $homeBase);

    update_last_transaction($user_file_name) if !$readOnly;

    } elsif (($CGIargs{q} eq 'dietcalc') || ($CGIargs{q} eq 'update_dietcalc')) {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    write_XHTML_prologue($fh, $homeBase, "Diet Calculator", "loadDietCalcFields();", $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef,
        'onclick="return leaveDocument();"', $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    
    my ($calc_calorie_balance, $calc_start_weight, $calc_goal_weight,
        $calc_weight_change, $calc_weight_week, $calc_weeks, $calc_months,, $calc_end_date,
        $calc_start_date, $plot_diet_plan, $calc_weight_unit, $calc_energy_unit) =
       (round($ui->{calc_calorie_balance} * ENERGY_CONVERSION->[ENERGY_CALORIE][$ui->{energy_unit}]),
        $ui->{calc_start_weight} * WEIGHT_CONVERSION->[WEIGHT_KILOGRAM][$ui->{display_unit}],
        $ui->{calc_goal_weight} * WEIGHT_CONVERSION->[WEIGHT_KILOGRAM][$ui->{display_unit}],
        0, 0, 0, 0, 0,
        $ui->{calc_start_date}, $ui->{plot_diet_plan},
        $ui->{display_unit}, $ui->{energy_unit}
       );

    
    if ($CGIargs{q} eq 'update_dietcalc') {
        if (defined($CGIargs{r_calc_energy_unit})) {
            $calc_energy_unit = $CGIargs{r_calc_energy_unit};
        }
        if (defined($CGIargs{r_calc_calorie_balance})) {
            $calc_calorie_balance = $CGIargs{r_calc_calorie_balance};
            $calc_calorie_balance =~ s/,/./g;
        }

        if (defined($CGIargs{r_calc_weight_unit})) {
            $calc_weight_unit = $CGIargs{r_calc_weight_unit};
        }
        if (defined($CGIargs{r_calc_start_weight})) {
            my $w = $CGIargs{r_calc_start_weight};
            $w =~ s/,/./g;
            #   If specification is stones and pounds, convert to pounds
            if (($w ne '') && ($calc_weight_unit == WEIGHT_STONE)) {
                if ($w =~ m/\s*(\d+)\s+([\d\.]+)/) {
                    $w = ($1 * 14) + $2;
                }
            }
            $calc_start_weight = $w *
                HDiet::monthlog::WEIGHT_CONVERSION->[$CGIargs{r_calc_weight_unit}][$calc_weight_unit];
        }

        if (defined($CGIargs{r_calc_goal_weight})) {
            my $w = $CGIargs{r_calc_goal_weight};
            $w =~ s/,/./g;
            #   If specification is stones and pounds, convert to pounds
            if (($w ne '') && ($calc_weight_unit == WEIGHT_STONE)) {
                if ($w =~ m/\s*(\d+)\s+([\d\.]+)/) {
                    $w = ($1 * 14) + $2;
                }
            }
            $calc_goal_weight = $w *
                HDiet::monthlog::WEIGHT_CONVERSION->[$CGIargs{r_calc_weight_unit}][$calc_weight_unit];
        }

        if (defined($CGIargs{r_calc_start_date})) {
            $calc_start_date = jd_to_unix_time($CGIargs{r_calc_start_date});
        }

        if (defined($CGIargs{r_plot_plan})) {
            $plot_diet_plan = defined($CGIargs{r_plot_plan}) ? 1 : 0;
        }
    }


    my $ckplan = $ui->{plot_diet_plan} ? ' checked="checked"' : '';
    my @eunit = ('', '');
    $eunit[$calc_energy_unit] = ' selected="selected"';
    my @wunit = ('', '', '');
    $wunit[$calc_weight_unit] = ' selected="selected"';

    if ($calc_start_date == 0) {
        $calc_start_date = time();
    }

    #   If no start weight specified, use last trend value from the
    #   most recent log or a default if no logs exist.
    if ($calc_start_weight == 0) {
        my $hist = HDiet::history->new($ui, $user_file_name);
        my ($ly, $lm, $ld, $ldu, $lw, $lt) = $hist->lastDay();
        if (defined($lt)) {
            $calc_start_weight = sprintf("%.1f", $lt * WEIGHT_CONVERSION->[$ldu][$ui->{display_unit}]);
        } else {
            $calc_start_weight = ($ui->{display_unit} == WEIGHT_KILOGRAM) ? 80 : 175;
        }
    }

    #   If no goal weight specified, assume 5 kilos or 10 pounds loss
    if ($calc_goal_weight == 0) {
        $calc_goal_weight = $calc_start_weight - (($ui->{display_unit} == WEIGHT_KILOGRAM) ? 5 : 10);
    }

    
$calc_calorie_balance = (-500 * ENERGY_CONVERSION->[ENERGY_CALORIE][$calc_energy_unit]) if $calc_calorie_balance == 0;

    $calc_weight_change = $calc_goal_weight - $calc_start_weight;
    $calc_weight_week = (($calc_calorie_balance * ENERGY_CONVERSION->[$calc_energy_unit][ENERGY_CALORIE]) * 7) / CALORIES_PER_WEIGHT_UNIT->[$calc_weight_unit];
    $calc_weeks = round($calc_weight_change / $calc_weight_week);
    $calc_months = round(((($calc_weight_change / $calc_weight_week) * 7.0) / 30.44));
    $calc_end_date = $calc_start_date + ($calc_weeks * 7.0 * 24.0 * 60.0 * 60.0);

    my @years;
    
    my $cyear = (jd_to_gregorian(unix_time_to_jd($userTime)))[0];
    @years = $ui->enumerateYears();
    if ($#years < 0) {          # If no years in database, include current year
        push(@years, $cyear);
    }
    my $lyear = max($cyear, (jd_to_gregorian(unix_time_to_jd($calc_start_date)))[0],
        (jd_to_gregorian(unix_time_to_jd($calc_end_date)))[0]);
    while ($years[$#years] < ($lyear + 1)) {
        push(@years, $years[$#years] + 1);
    }
    while ($years[0] > ($cyear - 1)) {
        unshift(@years, $years[0] - 1);
    }


    my @goofs;
    if ($CGIargs{q} eq 'update_dietcalc') {
        
    my $nschanges = 0;

    
    if ($CGIargs{calc_energy_unit} ne $CGIargs{r_calc_energy_unit}) {
        $calc_energy_unit = $CGIargs{calc_energy_unit};
        $calc_calorie_balance = round($calc_calorie_balance *
            ENERGY_CONVERSION->[$CGIargs{r_calc_energy_unit}][$calc_energy_unit]);
        @eunit = ('', '');
        $eunit[$calc_energy_unit] = ' selected="selected"';
        $nschanges++;
    }

    
    if ($CGIargs{calc_calorie_balance} ne $CGIargs{r_calc_calorie_balance}) {
        if ($CGIargs{calc_calorie_balance} =~ m/^\s*([\+\-]?\d+([\.,]\d*)?)\s*$/) {
            $calc_calorie_balance = $1;
            $calc_calorie_balance =~ s/,/./g;
            $calc_calorie_balance = round($calc_calorie_balance);
            $nschanges++;
        } else {
            push(@goofs, "Invalid daily balance");
        }
    }


    
    if ($CGIargs{calc_weight_unit} ne $CGIargs{r_calc_weight_unit}) {
        $calc_weight_unit = $CGIargs{calc_weight_unit};
        $calc_start_weight *= HDiet::monthlog::WEIGHT_CONVERSION->[$CGIargs{r_calc_weight_unit}][$CGIargs{calc_weight_unit}];
        $calc_goal_weight *= HDiet::monthlog::WEIGHT_CONVERSION->[$CGIargs{r_calc_weight_unit}][$CGIargs{calc_weight_unit}];
        @wunit = ('', '', '');
        $wunit[$calc_weight_unit] = ' selected="selected"';
        $nschanges++;
    }

    
    if ($CGIargs{calc_start_weight} ne $CGIargs{r_calc_start_weight}) {
        my $w = parseWeight($CGIargs{calc_start_weight}, $calc_weight_unit);
        if (defined($w)) {
            $calc_start_weight = $w;
        } else {
            push(@goofs, "Invalid initial weight");
        }
        $nschanges++;
    }


    
    if ($CGIargs{calc_goal_weight} ne $CGIargs{r_calc_goal_weight}) {
        my $w = parseWeight($CGIargs{calc_goal_weight}, $calc_weight_unit);
        if (defined($w)) {
            $calc_goal_weight = $w;
        } else {
            push(@goofs, "Invalid goal weight");
        }
        $nschanges++;
    }


    
    if ($CGIargs{calc_weight_change} ne $CGIargs{r_calc_weight_change}) {
        my $w = parseSignedWeight($CGIargs{calc_weight_change}, $calc_weight_unit);
        if (defined($w)) {
            $calc_goal_weight = $calc_start_weight + $w;
        } else {
            push(@goofs, "Invalid desired weight change");
        }
        $nschanges++;
    }


    
    if ($CGIargs{calc_weight_week} ne $CGIargs{r_calc_weight_week}) {
        my $w = parseSignedWeight($CGIargs{calc_weight_week}, $calc_weight_unit);
        if (defined($w)) {
            $calc_calorie_balance = round(($w * CALORIES_PER_WEIGHT_UNIT->[$calc_weight_unit]) /
                ((ENERGY_CONVERSION->[$calc_energy_unit][ENERGY_CALORIE]) * 7));
        } else {
            push(@goofs, "Invalid weight change per week");
        }
        $nschanges++;
    }


    
    if ($CGIargs{calc_weeks} ne $CGIargs{r_calc_weeks}) {
        my $ddw = -1;
        if ($CGIargs{calc_weeks} =~ m/^\s*(\d+)\s*$/) {
            if ($1 > 0) {
                $ddw = $1;
            }
        }
        if ($ddw > 0) {
            $calc_calorie_balance = round((($calc_weight_change / $ddw) *
                (CALORIES_PER_WEIGHT_UNIT->[$calc_weight_unit] / 7)));
        } else {
            push(@goofs, "Invalid diet duration in weeks");
        }
        $nschanges++;
    }

    
    if ($CGIargs{calc_months} ne $CGIargs{r_calc_months}) {
        my $ddm = -1;
        if ($CGIargs{calc_months} =~ m/^\s*(\d+)\s*$/) {
            if ($1 > 0) {
                $ddm = $1;
            }
        }
        if ($ddm > 0) {
            $calc_calorie_balance = int((($calc_weight_change / $ddm) *
                (CALORIES_PER_WEIGHT_UNIT->[$calc_weight_unit] / 30.44)));
        } else {
            push(@goofs, "Invalid diet duration in months");
        }
        $nschanges++;
    }


    
    if (gregorian_to_jd($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d}) !=
            $CGIargs{r_calc_start_date}) {
        $calc_start_date = jd_to_unix_time(gregorian_to_jd($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d}));
        $nschanges++;
    }


    
    if (gregorian_to_jd($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d}) !=
            $CGIargs{r_calc_end_date}) {
        my $ed = jd_to_unix_time(gregorian_to_jd($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d}));
        if ($ed > $calc_start_date) {
            $calc_calorie_balance = round((($calc_weight_change /
                (($ed - $calc_start_date) / (24 * 60 * 60))) *
                    CALORIES_PER_WEIGHT_UNIT->[$calc_weight_unit]) /
                    ENERGY_CONVERSION->[$calc_energy_unit][ENERGY_CALORIE]);
        } else {
            push(@goofs, "End date must be after start date");
        }
        $nschanges++;
    }


    if ($nschanges > 0) {
        
$calc_calorie_balance = (-500 * ENERGY_CONVERSION->[ENERGY_CALORIE][$calc_energy_unit]) if $calc_calorie_balance == 0;

    $calc_weight_change = $calc_goal_weight - $calc_start_weight;
    $calc_weight_week = (($calc_calorie_balance * ENERGY_CONVERSION->[$calc_energy_unit][ENERGY_CALORIE]) * 7) / CALORIES_PER_WEIGHT_UNIT->[$calc_weight_unit];
    $calc_weeks = round($calc_weight_change / $calc_weight_week);
    $calc_months = round(((($calc_weight_change / $calc_weight_week) * 7.0) / 30.44));
    $calc_end_date = $calc_start_date + ($calc_weeks * 7.0 * 24.0 * 60.0 * 60.0);

        
    my $cyear = (jd_to_gregorian(unix_time_to_jd($userTime)))[0];
    @years = $ui->enumerateYears();
    if ($#years < 0) {          # If no years in database, include current year
        push(@years, $cyear);
    }
    my $lyear = max($cyear, (jd_to_gregorian(unix_time_to_jd($calc_start_date)))[0],
        (jd_to_gregorian(unix_time_to_jd($calc_end_date)))[0]);
    while ($years[$#years] < ($lyear + 1)) {
        push(@years, $years[$#years] + 1);
    }
    while ($years[0] > ($cyear - 1)) {
        unshift(@years, $years[0] - 1);
    }

        if ($nschanges > 1) {
            push(@goofs, "Warning: you have changed more than one field in the
Diet Calculator before pressing the &ldquo;Update&rdquo; button.
This may result in unintended changes.  Please press the
&ldquo;Update&rdquo; button after each change to a field");
        }
    }

    }

    
    #   Preset start date selection fields
    my $s_jd = unix_time_to_jd($calc_start_date);
    ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d}) = jd_to_gregorian($s_jd);

    #   Preset end date selection fields
    my $e_jd = unix_time_to_jd($calc_end_date);
    ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d}) = jd_to_gregorian($e_jd);

    

    my %percheck = ( 'm', '', 'q', '', 'h', '', 'y', '', 'c', '' );

    if (defined($CGIargs{period})) {
        $percheck{$CGIargs{period}} = ' checked="checked"';
    } else {
        $percheck{q} = ' checked="checked"';
    }

    my (@fy_selected, @ty_selected);
    for (my $i = 0; $i <= $#years; $i++) {
        if (defined($CGIargs{from_y}) && ($CGIargs{from_y} eq $years[$i])) {
            $fy_selected[$i] = ' selected="selected"';
        } else {
            $fy_selected[$i] = '';
        }
        if (defined($CGIargs{to_y}) && ($CGIargs{to_y} eq $years[$i])) {
            $ty_selected[$i] = ' selected="selected"';
        } else {
            $ty_selected[$i] = '';
        }
    }

    my (@fm_selected, @tm_selected);
    for (my $i = 1; $i <= 12; $i++) {
        if (defined($CGIargs{from_m}) && ($CGIargs{from_m} == $i)) {
            $fm_selected[$i] = ' selected="selected"';
        } else {
            $fm_selected[$i] = '';
        }
        if (defined($CGIargs{to_m}) && ($CGIargs{to_m} == $i)) {
            $tm_selected[$i] = ' selected="selected"';
        } else {
            $tm_selected[$i] = '';
        }
    }

    my (@fd_selected, @td_selected);
    for (my $i = 1; $i <= 31; $i++) {
        if (defined($CGIargs{from_d}) && ($CGIargs{from_d} == $i)) {
            $fd_selected[$i] = ' selected="selected"';
        } else {
            $fd_selected[$i] = '';
        }
        if (defined($CGIargs{to_d}) && ($CGIargs{to_d} == $i)) {
            $td_selected[$i] = ' selected="selected"';
        } else {
            $td_selected[$i] = '';
        }
    }

    my @cs_selected;
    $CGIargs{size} = '800x600' if !defined($CGIargs{size});
    $CGIargs{size} = '320x240' if $session->{handheld};
    for (my $i = 0; $i <= $#chartSizes; $i++) {
        if ($CGIargs{size} eq $chartSizes[$i]) {
            $cs_selected[$i] = ' selected="selected"';
        } else {
            $cs_selected[$i] = '';
        }
    }

    my $ckprint = $CGIargs{print} ? ' checked="checked"' : '';
    my $ckmono = $CGIargs{mono} ? ' checked="checked"' : '';


    my $e_sw = HDiet::monthlog::editWeight($calc_start_weight, $calc_weight_unit, $ui->{decimal_character});
    my $e_gw = HDiet::monthlog::editWeight($calc_goal_weight, $calc_weight_unit, $ui->{decimal_character});
    my $e_dw = HDiet::monthlog::editWeight($calc_weight_change, $calc_weight_unit, $ui->{decimal_character});
    my $e_ww = HDiet::monthlog::editWeight($calc_weight_week, $calc_weight_unit, $ui->{decimal_character});

    print $fh <<"EOD";
<h1 class="c">Diet Calculator</h1>


<p class="justified" id="noJS"
   style="margin-left: auto; margin-right: auto; width: 75%; display: block; font-family: sans-serif; font-weight: bold;">
<script type="text/javascript">
/* <![CDATA[ */
    document.getElementById("noJS").style.display = "none";
/* ]]> */
</script>
Your browser does not support JavaScript (or it is disabled).  Please
click the &ldquo;Update&rdquo; button after each change to a form field
to update the rest of the form.
</p>
EOD


    if ($#goofs >= 0) {
   print $fh <<"EOD";
<h3 class="warning">Warning:  The following errors were found in
your changes to the diet calculator</h3>
<ul class="goofs">
EOD
    for (my $i = 0; $i <= $#goofs; $i++) {
        print($fh "<li>$goofs[$i].</li>\n");
    }
    print $fh <<"EOD";
</ul>
EOD
   }


    print $fh <<"EOD";
<form id="Hdiet_newacct" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>


<table border="border" class="login">

    <tr>
        <th><label for="calc_calorie_balance">Daily balance</label></th>
        <td><input type="text" name="calc_calorie_balance"  id="calc_calorie_balance"
                onchange="change_calc_calorie_balance();"
                size="5" maxlength="5"
                value="$calc_calorie_balance" />
            <input type="hidden" name="r_calc_calorie_balance"
                value="$calc_calorie_balance" />
            <select name="calc_energy_unit" id="calc_energy_unit"
                    onchange="change_calc_energy_unit();">
                <option value="0"$eunit[0]>cal</option>
                <option value="1"$eunit[1]>kJ</option>
            </select>
            <input type="hidden" name="r_calc_energy_unit"
                value="$calc_energy_unit" />
        </td>
    </tr>

    <tr>
        <th><label for="calc_start_weight">Initial weight</label></th>
        <td><input type="text" name="calc_start_weight" id="calc_start_weight"
                onchange="change_calc_start_weight();"
                size="7" maxlength="7"
                value="$e_sw" />
            <input type="hidden" name="r_calc_start_weight"
                value="$e_sw" />
            <select name="calc_weight_unit" id="calc_weight_unit"
                onchange="change_calc_weight_unit();">
                <option value="0"$wunit[0]>kilograms</option>
                <option value="1"$wunit[1]>pounds</option>
                <option value="2"$wunit[2]>stones</option>
            </select>
            <input type="hidden" name="r_calc_weight_unit"
                value="$calc_weight_unit" />
        </td>
    </tr>

    <tr>
        <th><label for="calc_goal_weight">Goal weight</label></th>
        <td><input type="text" name="calc_goal_weight" id="calc_goal_weight"
                onchange="change_calc_goal_weight();"
                size="7" maxlength="7"
                value="$e_gw" />
            <input type="hidden" name="r_calc_goal_weight"
                value="$e_gw" />
        </td>
    </tr>

    <tr>
        <th><label for="calc_weight_change">Desired weight change</label></th>
        <td><input type="text" name="calc_weight_change" id="calc_weight_change"
                onchange="change_calc_weight_change();"
                size="7" maxlength="7"
                value="$e_dw" />
            <input type="hidden" name="r_calc_weight_change"
                value="$e_dw" />
        </td>
    </tr>

    <tr>
        <th><label for="calc_weight_week">Weight change per week</label></th>
        <td><input type="text" name="calc_weight_week" id="calc_weight_week"
                onchange="change_calc_weight_week();"
                size="7" maxlength="7"
                value="$e_ww" />
            <input type="hidden" name="r_calc_weight_week"
                value="$e_ww" />
        </td>
    </tr>

    <tr>
        <th><label for="calc_weeks">Diet duration</label></th>
        <td><input type="text" name="calc_weeks" id="calc_weeks"
                onchange="change_calc_weeks();"
                size="5" maxlength="5"
                value="$calc_weeks" />&nbsp;weeks,
            <input type="hidden" name="r_calc_weeks"
                value="$calc_weeks" />
            <input type="text" name="calc_months" id="calc_months"
                onchange="change_calc_months();"
                size="5" maxlength="5"
                value="$calc_months" />&nbsp;months
            <input type="hidden" name="r_calc_months"
                value="$calc_months" />
        </td>
    </tr>

    <tr>
        <th><label for="from_y">Start date</label></th>
        <td>
EOD

    
    my ($ysel, $msel, $dsel) = ("") x 3;
    if ("1") {
        $ysel = ' onchange="change_from_y();"';
        $msel = ' onchange="change_from_m();"';
        $dsel = ' onchange="change_from_d();"';
    }

    print $fh <<"EOD";
    <select name="from_y" id="from_y"$ysel>
EOD

    
    for (my $i = 0; $i <= $#years; $i++) {
        print $fh <<"EOD";
        <option$fy_selected[$i]>$years[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>&nbsp;<select name="from_m" id="from_m"$msel>
EOD

    my $mid = "fm_";
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


        print $fh <<"EOD";
    </select>
EOD

    if (1) {
        print $fh <<"EOD";
    <select name="from_d" id="from_d"$dsel>
EOD
    }

    my $did;

    if (1) {
        $did = "fd_";
        
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


        print $fh <<"EOD";
        </select>
EOD
    }


    my $disped = ($e_jd >= $s_jd) ? 'inline' : 'none';
    print $fh <<"EOD";
            <input type="hidden" name="r_calc_start_date"
                value="$s_jd" />
        </td>
    </tr>
    <tr>
        <th><label for="to_y">End date</label></th>
        <td>
            <span id="end_date" style="display: $disped;">
EOD

    
    ($ysel, $msel, $dsel) = ("") x 3;
    if ("1") {
        $ysel = ' onchange="change_to_y();"';
        $msel = ' onchange="change_to_m();"';
        $dsel = ' onchange="change_to_d();"';
    }
    print $fh <<"EOD";
    <select name="to_y" id="to_y"$ysel>
EOD

    @fy_selected = @ty_selected;
    
    for (my $i = 0; $i <= $#years; $i++) {
        print $fh <<"EOD";
        <option$fy_selected[$i]>$years[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>&nbsp;<select name="to_m" id="to_m"$msel>
EOD

    $mid = "tm_";
    @fm_selected = @tm_selected;
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>
EOD

    if (1) {
        print $fh <<"EOD";
    <select name="to_d" id="to_d"$dsel>
EOD
    }

    if (1) {
        $did = "td_";
        @fd_selected = @td_selected;
        
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


        print $fh <<"EOD";
    </select>
EOD
    }


    $disped = ($e_jd < $s_jd) ? 'inline' : 'none';
    print $fh <<"EOD";
        </span>
            <input type="hidden" name="r_calc_end_date"
                value="$e_jd" />
            <span id="endless_date" style="display: $disped;"
                onmouseover="document.getElementById('end_date').style.display = 'inline'; document.getElementById('endless_date').style.display = 'none';">
            <i>Never</i>
            </span>
        </td>
    </tr>

</table>

EOD

    if (!$browse_public) {
        print $fh <<"EOD";

<p class="centred" id="noJS1" style="display: block;">
<script type="text/javascript">
/* <![CDATA[ */
    document.getElementById("noJS1").style.display = "none";
/* ]]> */
</script>
<input type="submit" name="q=update_dietcalc" value="     Update     " />
</p>

<p class="mlog_buttons">
<label><input type="checkbox" name="plot_plan"
    value="y"$ckplan onchange="change_calc_plot_plan();"
    />&nbsp;Plot&nbsp;plan&nbsp;in&nbsp;chart</label>
<br />
<input type="hidden" name="du" id="du" value="$ui->{display_unit}" />
<input type="hidden" name="dc" id="dc" value="$ui->{decimal_character}" />
<input type="hidden" name="eu" id="eu" value="$ui->{energy_unit}" />
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=save_dietcalc" value=" Save " />
&nbsp;
<input type="reset" onclick="unsavedChanges = 0;" value=" Reset " />
&nbsp;
<input type="submit" name="q=account" value=" Cancel " />
</p>

EOD
    }

    print $fh <<"EOD";
</form>
EOD

    write_XHTML_epilogue($fh, $homeBase);

    update_last_transaction($user_file_name) if !$readOnly;

    } elsif ($CGIargs{q} eq 'save_dietcalc') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    $CGIargs{calc_calorie_balance} =~ s/,/./g;
    $ui->{calc_calorie_balance} = $CGIargs{calc_calorie_balance} *
        ENERGY_CONVERSION->[$CGIargs{calc_energy_unit}][ENERGY_CALORIE];

    $CGIargs{calc_start_weight} =~ s/,/./g;
    my $w = $CGIargs{calc_start_weight};
    #   If specification is stones and pounds, convert to pounds
    if (($w ne '') && ($CGIargs{calc_weight_unit} == WEIGHT_STONE)) {
        if ($w =~ m/\s*(\d+)\s+([\d\.]+)/) {
            $w = ($1 * 14) + $2;
        }
    }
    $ui->{calc_start_weight} = $w *
        HDiet::monthlog::WEIGHT_CONVERSION->[$CGIargs{calc_weight_unit}][WEIGHT_KILOGRAM];

    $CGIargs{calc_goal_weight} =~ s/,/./g;
    $w = $CGIargs{calc_goal_weight};
    #   If specification is stones and pounds, convert to pounds
    if (($w ne '') && ($CGIargs{calc_weight_unit} == WEIGHT_STONE)) {
        if ($w =~ m/\s*(\d+)\s+([\d\.]+)/) {
            $w = ($1 * 14) + $2;
        }
    }
    $ui->{calc_goal_weight} = $w *
        HDiet::monthlog::WEIGHT_CONVERSION->[$CGIargs{calc_weight_unit}][WEIGHT_KILOGRAM];
    $ui->{calc_start_date} = jd_to_unix_time(gregorian_to_jd($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d}));
    $ui->{plot_diet_plan} = defined($CGIargs{plot_plan}) ? 1 : 0;

    if (!$readOnly) {
        
    open(FU, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    $ui->save(\*FU);
    close(FU);
    clusterCopy("/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");

        append_history($user_file_name, 15);
        update_last_transaction($user_file_name);
    }
    $CGIargs{q} = 'dietcalc';
    next;

    } elsif ($CGIargs{q} eq 'histreq') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    my @years = $ui->enumerateYears();

    write_XHTML_prologue($fh, $homeBase, "Chart Workshop", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, "Chart", undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    if ($#years >= 0) {
        
    print $fh <<"EOD";
<h1 class="c">Chart Workshop</h1>
EOD

    
    my $hist = HDiet::history->new($ui, $user_file_name);
    my ($s_y, $s_m, $s_d) = $hist->firstDay();
    my $s_jd = gregorian_to_jd($s_y, $s_m, $s_d);
    my ($l_y, $l_m, $l_d) = $hist->lastDay();
    my $l_jd = gregorian_to_jd($l_y, $l_m, $l_d);


    
    my $custom = $CGIargs{period} && ($CGIargs{period} eq 'c');
    my ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd,
        $cust_end_y, $cust_end_m, $cust_end_d,$cust_end_jd);
    if ($custom) {
        ($cust_start_y, $cust_start_m, $cust_start_d) = ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d});
        $cust_start_jd = gregorian_to_jd($cust_start_y, $cust_start_m, $cust_start_d);
        ($cust_end_y, $cust_end_m, $cust_end_d) = ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d});
        $cust_end_jd = gregorian_to_jd($cust_end_y, $cust_end_m, $cust_end_d);

        if ($cust_end_jd != $cust_start_jd) {
            #   If start or end of interval is outside the database,
            #   constrain it to the  first or last entry.
            if (($cust_start_jd < $s_jd) || ($cust_start_jd > $l_jd)) {
                ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd) =
                    ($s_y, $s_m, $s_d, $s_jd);
               ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d}) =
                    ($cust_start_y, $cust_start_m, $cust_start_d);
            }
            if (($cust_end_jd < $s_jd) || ($cust_end_jd > $l_jd)) {
                ($cust_end_y, $cust_end_m, $cust_end_d, $cust_end_jd) =
                    ($l_y, $l_m, $l_d, $l_jd);
                ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d}) =
                    ($cust_end_y, $cust_end_m, $cust_end_d);
            }

            #   If end of interval is before start, reverse them
            if ($cust_end_jd < $cust_start_jd) {
                my @temp = ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd);
                ($cust_start_y, $cust_start_m, $cust_start_d, $cust_start_jd) =
                    ($cust_end_y, $cust_end_m, $cust_end_d, $cust_end_jd);
                ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d}) =
                    ($cust_start_y, $cust_start_m, $cust_start_d);
                ($cust_end_y, $cust_end_m, $cust_end_d, $cust_end_jd) = @temp;
                ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d}) =
                    ($cust_end_y, $cust_end_m, $cust_end_d);
            }
        } else {
            $custom = 0;                # Void interval disables custom display
            $CGIargs{period} = '';
        }
    }


    
    my ($chart_w, $chart_h) = (800, 600);

    ($chart_w, $chart_h) = (320, 240) if $session->{handheld};

    if (defined($CGIargs{size})) {
        if ($CGIargs{size} =~ m/^(\d+)x(\d+)$/) {
            ($chart_w, $chart_h) = ($1, $2);
            $chart_w = min(1600, max($chart_w, 320));
            $chart_h = min(1600, max($chart_h, 200));
        }
    }

    my $chart_args = "width=$chart_w&amp;height=$chart_h";

    
    my ($start_y, $start_m, $start_d, $end_y, $end_m, $end_d);

    my $period = $CGIargs{period};
    $period = 'q' if !$period;

    if ($custom) {
        ($start_y, $start_m, $start_d) = ($cust_start_y, $cust_start_m, $cust_start_d);
        ($end_y, $end_m, $end_d) = ($cust_end_y, $cust_end_m, $cust_end_d);
    } else {
        my %periodIntervals = (
                                'm' => -1,
                                'q' => -3,
                                'h' => -6,
                                'y' => -12
                              );
        my $pint = $periodIntervals{$period};
        if (!$pint) {
            $period = $CGIargs{period} = 'q';
            $pint = $periodIntervals{$period};
        }

        my ($f_y, $f_m, $f_d) = $hist->firstDayOfInterval($l_y, $l_m, $l_d, $pint);
        my $f_jd = gregorian_to_jd($f_y, $f_m, $f_d);

        if ($f_jd < $s_jd) {
            ($f_y, $f_m, $f_d, $f_jd) = ($s_y, $s_m, $s_d, $s_jd);
        }

        ($start_y, $start_m, $start_d) = ($f_y, $f_m, $f_d);
        ($end_y, $end_m, $end_d) = ($l_y, $l_m, $l_d);
    }



#    my ($start_y, $start_m, $start_d) = ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d});
#    my ($end_y, $end_m, $end_d) = ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d});
    $chart_args .= "&amp;start=$start_y-$start_m-$start_d&amp;end=$end_y-$end_m-$end_d";

    my $modeArgs = '';
    $modeArgs .= '&amp;print=y' if $CGIargs{print};
    $modeArgs .= '&amp;mono=y' if $CGIargs{mono};

    
    my $cachebuster = sprintf("%x", (int(rand(65536))) & 0xFFFF);
    $cachebuster =~ tr/a-f/FGJKQW/;


    print $fh <<"EOD";
<p class="centred">
<img src="/cgi-bin/HackDiet?q=histchart&amp;s=$session->{session_id}&amp;$chart_args$modeArgs&amp;qx=$cachebuster$tzOff"
     width="$chart_w" height="$chart_h" alt="Historical chart" />
</p>
EOD


    

    my %percheck = ( 'm', '', 'q', '', 'h', '', 'y', '', 'c', '' );

    if (defined($CGIargs{period})) {
        $percheck{$CGIargs{period}} = ' checked="checked"';
    } else {
        $percheck{q} = ' checked="checked"';
    }

    my (@fy_selected, @ty_selected);
    for (my $i = 0; $i <= $#years; $i++) {
        if (defined($CGIargs{from_y}) && ($CGIargs{from_y} eq $years[$i])) {
            $fy_selected[$i] = ' selected="selected"';
        } else {
            $fy_selected[$i] = '';
        }
        if (defined($CGIargs{to_y}) && ($CGIargs{to_y} eq $years[$i])) {
            $ty_selected[$i] = ' selected="selected"';
        } else {
            $ty_selected[$i] = '';
        }
    }

    my (@fm_selected, @tm_selected);
    for (my $i = 1; $i <= 12; $i++) {
        if (defined($CGIargs{from_m}) && ($CGIargs{from_m} == $i)) {
            $fm_selected[$i] = ' selected="selected"';
        } else {
            $fm_selected[$i] = '';
        }
        if (defined($CGIargs{to_m}) && ($CGIargs{to_m} == $i)) {
            $tm_selected[$i] = ' selected="selected"';
        } else {
            $tm_selected[$i] = '';
        }
    }

    my (@fd_selected, @td_selected);
    for (my $i = 1; $i <= 31; $i++) {
        if (defined($CGIargs{from_d}) && ($CGIargs{from_d} == $i)) {
            $fd_selected[$i] = ' selected="selected"';
        } else {
            $fd_selected[$i] = '';
        }
        if (defined($CGIargs{to_d}) && ($CGIargs{to_d} == $i)) {
            $td_selected[$i] = ' selected="selected"';
        } else {
            $td_selected[$i] = '';
        }
    }

    my @cs_selected;
    $CGIargs{size} = '800x600' if !defined($CGIargs{size});
    $CGIargs{size} = '320x240' if $session->{handheld};
    for (my $i = 0; $i <= $#chartSizes; $i++) {
        if ($CGIargs{size} eq $chartSizes[$i]) {
            $cs_selected[$i] = ' selected="selected"';
        } else {
            $cs_selected[$i] = '';
        }
    }

    my $ckprint = $CGIargs{print} ? ' checked="checked"' : '';
    my $ckmono = $CGIargs{mono} ? ' checked="checked"' : '';


    print $fh <<"EOD";
<form id="Hdiet_histchart" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
<p class="mlog_buttons">
<b>Last:</b>
    <label><input type="radio" name="period" value="m"$percheck{m} />&nbsp;Month</label>
    <label><input type="radio" name="period" value="q"$percheck{q} />&nbsp;Quarter</label>
    <label><input type="radio" name="period" value="h"$percheck{h} />&nbsp;Six&nbsp;months</label>
    <label><input type="radio" name="period" value="y"$percheck{y} />&nbsp;Year</label>

    <br />
EOD

    
    print $fh <<"EOD";
<label><input type="radio" name="period" value="c"$percheck{c} />&nbsp;<b>Custom</b></label>
EOD

    
    my @f_mon;
    my $fmon;
    if (!$CGIargs{from_y}) {
        $fy_selected[0] = ' selected="selected"';
        @f_mon = $ui->enumerateMonths($years[0]);
        $f_mon[0] =~ m/^\d+\-(\d+)$/;
        $fmon = $1 + 0;
        $fm_selected[$fmon] = ' selected="selected"';
        $fd_selected[$s_d] = ' selected="selected"';
    }

    print($fh "From\n");
    
    my ($ysel, $msel, $dsel) = ("") x 3;
    if ("") {
        $ysel = ' onchange="change_from_y();"';
        $msel = ' onchange="change_from_m();"';
        $dsel = ' onchange="change_from_d();"';
    }

    print $fh <<"EOD";
    <select name="from_y" id="from_y"$ysel>
EOD

    
    for (my $i = 0; $i <= $#years; $i++) {
        print $fh <<"EOD";
        <option$fy_selected[$i]>$years[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>&nbsp;<select name="from_m" id="from_m"$msel>
EOD

    my $mid = "fm_";
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


        print $fh <<"EOD";
    </select>
EOD

    if (1) {
        print $fh <<"EOD";
    <select name="from_d" id="from_d"$dsel>
EOD
    }

    my $did;

    if (1) {
        $did = "fd_";
        
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


        print $fh <<"EOD";
        </select>
EOD
    }


    print $fh <<"EOD";
<br />
EOD

    if (!$CGIargs{to_y}) {
        $ty_selected[$#years] = ' selected="selected"';
        @f_mon = $ui->enumerateMonths($years[$#years]);
        $f_mon[$#f_mon] =~ m/^\d+\-(\d+)$/;
        $fmon = $1 + 0;
        $tm_selected[$fmon] = ' selected="selected"';
        $td_selected[$l_d] = ' selected="selected"';
    }

    print($fh "To\n");
    
    ($ysel, $msel, $dsel) = ("") x 3;
    if ("") {
        $ysel = ' onchange="change_to_y();"';
        $msel = ' onchange="change_to_m();"';
        $dsel = ' onchange="change_to_d();"';
    }
    print $fh <<"EOD";
    <select name="to_y" id="to_y"$ysel>
EOD

    @fy_selected = @ty_selected;
    
    for (my $i = 0; $i <= $#years; $i++) {
        print $fh <<"EOD";
        <option$fy_selected[$i]>$years[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>&nbsp;<select name="to_m" id="to_m"$msel>
EOD

    $mid = "tm_";
    @fm_selected = @tm_selected;
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>
EOD

    if (1) {
        print $fh <<"EOD";
    <select name="to_d" id="to_d"$dsel>
EOD
    }

    if (1) {
        $did = "td_";
        @fd_selected = @td_selected;
        
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


        print $fh <<"EOD";
    </select>
EOD
    }




    print $fh <<"EOD";
<br />

<b><label for="size">Chart size:</label></b>&nbsp;<select name="size" id="size">
EOD

    
    for (my $i = 0; $i <= $#chartSizes; $i++) {
        my $cs = $chartSizes[$i];
        $cs =~ s/x/&times;/;
        print $fh <<"EOD";
        <option id="cs$chartSizes[$i]" value="$chartSizes[$i]"$cs_selected[$i]>$cs</option>
EOD
    }


    print $fh <<"EOD";
</select>
<br />
<label><input type="checkbox" name="print" value="y"$ckprint  />&nbsp;Printer&nbsp;friendly</label>
&nbsp;
<label><input type="checkbox" name="mono" value="y"$ckmono  />&nbsp;Monochrome</label>
<br />

<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=histreq" value=" Update " />
&nbsp;
<input type="reset" value=" Reset " />
</p>
</form>
EOD

    } else {
        print $fh <<"EOD";
<h2>You have no log entries!  You must enter weight logs
    before you can request historical charts.</h2>
EOD
    }

    write_XHTML_epilogue($fh, $homeBase);
    update_last_transaction($user_file_name);

    } elsif ($CGIargs{q} eq 'importcsv') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    write_XHTML_prologue($fh, $homeBase, "Import CSV or XML Database", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<h1 class="c">Import CSV or XML Database</h1>

<p class="justified">
You can import log entries from CSV files either saved from Excel
logs or exported from a backup of a Palm database with the
<tt>hdread</tt> program.  You can also import XML database backups
from this application.  Logs in any format can either be uploaded from a
file on your computer or simply pasted into the text box below.
</p>

<p class="justified">
Normally, log entries from files you import will not overwrite
existing entries in the online database; if one or more fields in
a daily entry are nonblank, they will not be replaced by the
contents of a record for the same day in the imported file.  If you wish
to have records imported from the file override existing records,
check the &ldquo;Allow overwrite&rdquo; box in the import request.
</p>

<div>

    
<fieldset id="Hdiet_CSV_upload_fs"><legend>Import CSV or XML by File Upload</legend>
<form id="Hdiet_CSV_upload" enctype="multipart/form-data"
    method="post" action="/cgi-bin/HackDiet?enc=raw$tzOff">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
  <p>
    <label title="Choose a Local CSV or XML File to Upload and Import" for="uploaded_file">Local File:</label>
    <input type="file" id="uploaded_file" name="uploaded_file" size="30" />
    <input type="hidden" name="q" value="csv_import_data" />
    <input type="hidden" name="s" value="$session->{session_id}" />
    <label title="Upload and import CSV or XML file"><input type="submit" value=" Import " /></label>
    <br />
    <label><input type="checkbox" name="overwrite" value="y" />&nbsp;Allow&nbsp;overwrite</label>
    <label><input type="checkbox" name="listimp" value="y" />&nbsp;List&nbsp;imported&nbsp;records</label>
  </p>
</form>

<p>
Select the file you wish to upload and import.
</p>

</fieldset>


<br />

    
<fieldset class="front" id="Hdiet_CSV_submit_fs"><legend>Import Pasted CSV or XML Log Entries</legend>
<form id="Hdiet_CSV_submit" enctype="multipart/form-data"
    method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset1" value="unknown" /></div>
<p>Paste the CSV or XML you wish to import in the text area below:</p>
<p>
    <label title="Paste the CSV or XML log entries here" for="file">
    <textarea cols="75" rows="12" name="file" id="file"></textarea></label><br />
    <input type="hidden" name="q" value="csv_import_data" />
    <input type="hidden" name="s" value="$session->{session_id}" />
    <label title="Import CSV or XML log entries"><input type="submit" value=" Import " /></label>
    <label title="Clear the entry field"><input type="reset" value=" Clear " /></label>
    <label><input type="checkbox" name="overwrite" value="y" />&nbsp;Allow&nbsp;overwrite</label>
    <label><input type="checkbox" name="listimp" value="y" />&nbsp;List&nbsp;imported&nbsp;records</label>
</p>
</form>
</fieldset>

<br />
</div>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Back to account page</a></h4>
EOD

    write_XHTML_epilogue($fh, $homeBase);

    update_last_transaction($user_file_name);

    } elsif ($CGIargs{q} eq 'csv_import_data') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    write_XHTML_prologue($fh, $homeBase, "Database Imported", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<h1 class="c">Database Imported</h1>
<form id="Hdiet_CSV_import_confirmation" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>

<p class="justified">
The submitted log items have been processed as follows.
</p>

<p class="mlog_buttons">
<input type="hidden" name="q" value="account" />
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="account" value=" Return to Account Page " />
</p>
</form>

EOD

    my $listStyle;
    my ($imp, $over);

    my $csv = HDiet::Text::CSV->new();
    my ($n, $imported, $noparse, $already, $notentry) = (0, 0, 0, 0, 0);
    my (%mondb, %monchanges);

    my $overwrite = defined($CGIargs{overwrite});
    my $listCSV = defined($CGIargs{listimp});

    #   Set log format and weight unit unknown
    my ($logFormat, $csvUnit, $hdOnlineLog) = ('Unknown', -1, 0);

    if ($listCSV) {
        print $fh <<"EOD";
<pre>
EOD
    }

    if ($CGIargs{file} =~ m/\s*<\?xml\s+/) {
        
    my $parser = XML::LibXML->new();
    my $doc = $parser->parse_string($CGIargs{file});
    my $root = $doc->getDocumentElement();

    my $indent = '';

    my %logItem;
    my ($logYear, $logMonth);

    $logFormat = 'XML';
    parseDOMTree($root, '');

    #   For node name mnemonics see:
    #       /usr/lib/perl5/vendor_perl/5.8.8/i386-linux-thread-multi/XML/LibXML/Common.pm
    sub parseDOMTree {
        my ($elem, $parent) = @_;

        if ($elem->nodeType() == TEXT_NODE) {
            my $v = $elem->nodeValue();
            if ($v !~ m/^\s*$/) {
                if (($parent eq 'log-unit') || ($parent eq 'weight-unit')) {
                    $csvUnit = WEIGHT_KILOGRAM if ($elem->nodeValue() eq 'kilogram');
                    $csvUnit = WEIGHT_POUND if ($elem->nodeValue() eq 'pound');
                    $csvUnit = WEIGHT_STONE if ($elem->nodeValue() eq 'stone');
                } elsif ($parent eq 'year') {
                    $logYear = $elem->nodeValue();
                } elsif ($parent eq 'month') {
                    $logMonth = $elem->nodeValue();
                } elsif ($parent =~ m/(date|weight|rung|flag|comment)/) {
                    $logItem{$parent} = $elem->nodeValue();
                }
            }
        } elsif ($elem->nodeType() == ELEMENT_NODE) {
            if ($elem->nodeName() eq 'day') {
                %logItem = ();                  # Clear log item fields
            }
        }
        if ($elem->hasChildNodes()) {
            my @kids = $elem->getChildNodes();
            for my $kid (@kids) {
                $indent .= '  ';
                parseDOMTree($kid, $elem->nodeName());
                $indent =~ s/  //;
            }
        }

        if (($elem->nodeType() == ELEMENT_NODE) &&
            ($elem->nodeName() eq 'day')) {
            
    #   Sanity check date before proceeding
    if (($logYear >= 1980) &&  ($logYear <= ((unix_time_to_civil_date_time($userTime))[0]))) {

        my $monkey = sprintf("%04d-%02d", $logYear, $logMonth);
        my ($yy, $mm) = ($logYear, $logMonth);
        
    my $mlog;

    if (defined($mondb{$monkey})) {
        $mlog = $mondb{$monkey};
    } else {
        $mlog = HDiet::monthlog->new();
        $mondb{$monkey} = $mlog;
        $monchanges{$monkey} = 0;
        if (-f "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") {
            open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") ||
                die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$monkey.hdb");
            $mlog->load(\*FL);
            close(FL);
        } else {
            $mlog->{year} = $yy;
            $mlog->{month} = $mm;
            $mlog->{log_unit} = $ui->{log_unit};
            $mlog->{trend_carry_forward} = 0;
            $mlog->{last_modification_time} = 0;
        }
    }


        #   Test whether an entry already exists for this day

        if ((!$overwrite) && ($mlog->{weight}[$logItem{date}] || $mlog->{rung}[$logItem{date}] ||
                $mlog->{flag}[$logItem{date}] || $mlog->{comment}[$logItem{date}])) {
            $listStyle = 'conflict';
            $already++;
        } else {
            $mlog->{weight}[$logItem{date}] = ($logItem{weight} *
                    WEIGHT_CONVERSION->[$csvUnit][$mlog->{log_unit}])
                if defined($logItem{weight});
            $mlog->{rung}[$logItem{date}] = $logItem{rung}
                if defined($logItem{rung});
            $mlog->{flag}[$logItem{date}] = $logItem{flag}
                if defined($logItem{flag});
            $mlog->{comment}[$logItem{date}] = $logItem{comment};

            $monchanges{$monkey}++;
            $listStyle = 'imported';
            $imported++;
       }
    } else {
        $listStyle = 'noparse';
        $noparse++;
    }

    $n++;
    if ($listCSV) {
        my $listline =  quoteHTML(sprintf("%04d-%02d-%02d  %4.1f  %3d  %1d  %s",
            $logYear, $logMonth, $logItem{date},
            defined($logItem{weight}) ? $logItem{weight} : 0,
            defined($logItem{rung}) ? $logItem{rung} : 0,
            defined($logItem{flag}) ? $logItem{flag} : 0,
            defined($logItem{comment}) ? $logItem{comment} : ''));
        printf("<span class=\"$listStyle\">%4d.  %s</span>\n", $n, $listline);
    }

        }
    }

    } else {
        
    while ($CGIargs{file} =~ s/^([^\n]*\r?\n)//s) {
        $n++;

        my $l = $1;
        my $listline = $l;
        $listline =~ s/\s+$//;
        $listStyle = 'noparse';
        if (($listline ne '') && $csv->parse($l)) {
            $listStyle = 'notentry';
            my @f = $csv->fields();
            $imp = 0;
            $over = 0;

            
    my $excelCSVdebug = 0;
    if ($listline =~ m/^Date,,Weight,Trend,Variance,,Rung,Flag$/) {
        $logFormat = 'Excel';
#print("Set format Excel\n") if $excelCSVdebug;
    } elsif (($logFormat eq 'Excel') && ($csvUnit < 0) &&
             ($listline =~ m/^,,(\w+),,\w+\s+\d+,,,$/)) {
        my $wunit = $1;

        $csvUnit = WEIGHT_KILOGRAM if ($wunit =~ m/^Kilograms/i) || ($wunit eq 0);
        $csvUnit = WEIGHT_POUND if ($wunit =~ m/^Pounds/i) || ($wunit eq 1);
        $csvUnit = WEIGHT_STONE if ($wunit =~ m/^Stones/i) || ($wunit eq -1);
#print("Setunit $csvUnit\n") if $excelCSVdebug;
    } else {
#print("        Parsed($#f) 0($f[0])  1($f[1])   2($f[2])   3($f[3])   4($f[4])   5($f[5])   6($f[6])  7($f[7])  8($f[8])\n") if $excelCSVdebug;
        if (($#f >= 5) &&
            ($f[0] =~ m/^\d+[\/\-\.]\d+[\/\-\.]\d+$/) &&  # Date
            ($f[1] =~ m/^[a-z]+$/i) &&                  # Day of week
            ($f[2] =~ m/^[\p{IsWord}\s\.]+$/) &&        # Weight
            ($f[3] =~ m/^[\d\.]+$/) &&                  # Trend
            ($f[4] =~ m/^\-?[\d\.]*$/) &&               # Variance
            ($f[5] =~ m/^[\d\.]*$/) &&                  # Hidden carry-forward
            ($f[6] =~ m/^\s*\d*$/)) {                   # Exercise rung
#print("        Import ($f[0])  ($f[2])   ($f[6])  ($f[7])\n") if $excelCSVdebug;
            my ($date, $weight, $rung) = ($f[0], $f[2], $f[6]);
            $rung =~ s/\s//g;
            my $flag = $f[7] ? 1 : 0;
            my $comment = defined($f[8]) ? $f[8] : '';

            #   See if the first field is something we can interpret plausibly as a date
            $f[0] =~ m/^(\d+)([\/\-\.])(\d+)([\/\-\.])(\d+)$/;
            if ($2 eq $4) {
                
    my ($yy, $mm, $dd);
    if ($2 eq '-') {            # YYYY-MM-DD
        $yy = $1 + 0;
        $mm = $3 + 0;
        $dd = $5 + 0;
    } elsif ($2 eq '/') {       # MM/DD/YYYY
        $yy = $5 + 0;
        $mm = $1 + 0;
        $dd = $3 + 0;
    } elsif ($2 eq '.') {       # DD.MM.YYYY
        $yy = $5 + 0;
        $mm = $3 + 0;
        $dd = $1 + 0;
    }

    #   Kludge for two digit years
    if ($yy < 100) {
        if ($yy > 88) {
            $yy += 1900;
        } else {
            $yy += 2000;
        }
    }


                #   Sanity check date before proceeding
                if (($yy >= 1980) &&  ($yy <= ((unix_time_to_civil_date_time($userTime))[0]))) {
                    my $monkey = sprintf("%04d-%02d", $yy, $mm);

                    
    my $mlog;

    if (defined($mondb{$monkey})) {
        $mlog = $mondb{$monkey};
    } else {
        $mlog = HDiet::monthlog->new();
        $mondb{$monkey} = $mlog;
        $monchanges{$monkey} = 0;
        if (-f "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") {
            open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") ||
                die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$monkey.hdb");
            $mlog->load(\*FL);
            close(FL);
        } else {
            $mlog->{year} = $yy;
            $mlog->{month} = $mm;
            $mlog->{log_unit} = $ui->{log_unit};
            $mlog->{trend_carry_forward} = 0;
            $mlog->{last_modification_time} = 0;
        }
    }


                    #   Test whether an entry already exists for this day

                    if ((!$overwrite) && ($mlog->{weight}[$dd] || $mlog->{rung}[$dd] ||
                            $mlog->{flag}[$dd] || $mlog->{comment}[$dd])) {
                        $listStyle = 'conflict';
                        $already++;
                        $over = 1;
                    } else {
                        
    my $cmt = '';
    if ($f[2] !~ m/^[\d\.]+$/) {
        $cmt = $f[2];
        $f[2] = '';
    }
    $cmt = $f[8] if defined($f[8]) && $f[8] ne '';

    $mlog->{weight}[$dd] = ($f[2] * WEIGHT_CONVERSION->[$csvUnit][$mlog->{log_unit}]) if $f[2] ne '';
    $mlog->{rung}[$dd] = $f[6] if $f[6] ne '';
    $mlog->{flag}[$dd] = '1' if $f[7] ne '';
    $mlog->{flag}[$dd] = undef if (!$f[7]) || ($f[7] eq '0') ||
        ($f[7] eq '') || ($f[7] =~ m/^\s*$/);
    $mlog->{comment}[$dd] = $cmt if $cmt ne '';
    if ($cmt eq '') {
        undef $mlog->{comment}[$dd];
    }

    $monchanges{$monkey}++;
    $imp = 1;

                    }
                } else { print ("ExcelBarfel: $yy-$mm-$dd\n") if $excelCSVdebug; }
            } else { print ("ExcelGarfel: $1 $2 $3 $4 $5 $6\n") if $excelCSVdebug; }

         }
    }


            if (!($imp || $over)) {
                
    if ($listline =~ m/^Date,Weight,Rung,Flag,Comment$/) {
        $logFormat = 'HDRead';
    } elsif (($logFormat eq 'HDRead') &&
             ($#f >= 4) &&
             ($f[0] eq 'StartTrend') &&
             ($f[2] >= WEIGHT_KILOGRAM) && ($f[2] <= WEIGHT_STONE)) {

        $csvUnit = $f[2];
        $hdOnlineLog = 0;
        if (($#f >= 5) && ($f[5] =~ m/^[\d\.]+$/)) {
            $hdOnlineLog = 1;
        }
    } else {
        $f[0] =~ s/\s//g if defined($f[0]);
        $f[1] =~ s/\s//g if defined($f[1]);
        $f[2] =~ s/\s//g if defined($f[2]);
        $f[3] =~ s/\s//g if defined($f[3]);
        if (($#f >= 4) &&
            ($f[0] =~ m/^\d+\-\d+\-\d+$/) &&        # Date
            ($f[1] =~ m/^[\d\.]*$/) &&              # Weight
            ($f[2] =~ m/^\d*$/)) {                  # Exercise rung
            my ($date, $weight, $rung) = ($f[0], $f[1], $f[2]);
            my $flag = $f[3] ? 1 : 0;
            my $comment = defined($f[4]) ? $f[4] : '';

            #   See if the first field is an ISO 8601 date
            $f[0] =~ m/^(\d+)\-(\d+)\-(\d+)$/;
            my ($yy, $mm, $dd) = ($1, $2, $3);

            #   Sanity check date before proceeding
            if (($yy >= 1980) &&  ($yy <= ((unix_time_to_civil_date_time($userTime))[0]))) {

                my $monkey = sprintf("%04d-%02d", $yy, $mm);

                
    my $mlog;

    if (defined($mondb{$monkey})) {
        $mlog = $mondb{$monkey};
    } else {
        $mlog = HDiet::monthlog->new();
        $mondb{$monkey} = $mlog;
        $monchanges{$monkey} = 0;
        if (-f "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") {
            open(FL, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/$monkey.hdb") ||
                die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$monkey.hdb");
            $mlog->load(\*FL);
            close(FL);
        } else {
            $mlog->{year} = $yy;
            $mlog->{month} = $mm;
            $mlog->{log_unit} = $ui->{log_unit};
            $mlog->{trend_carry_forward} = 0;
            $mlog->{last_modification_time} = 0;
        }
    }


                #   Test whether an entry already exists for this day

                if ((!$overwrite) && ($mlog->{weight}[$dd] || $mlog->{rung}[$dd] ||
                        $mlog->{flag}[$dd] || $mlog->{comment}[$dd])) {
                    $listStyle = 'conflict';
                    $already++;
                } else {
                    
    if ($hdOnlineLog) {
        if ($mlog->importCSV($listline)) {
            $monchanges{$monkey}++;
            $imp = 1;
       }
    } else {
        $mlog->{weight}[$dd] = ($f[1] *
            WEIGHT_CONVERSION->[$csvUnit][$mlog->{log_unit}]) if $f[1] ne '';
        $mlog->{rung}[$dd] = $f[2] if $f[2] ne '';
        $mlog->{flag}[$dd] = $flag;
        $mlog->{comment}[$dd] = $comment;
        if ($comment eq '') {
            undef $mlog->{comment}[$dd];
        }
    }

    $monchanges{$monkey}++;
    $imp = 1;

                }
            }# else { print ("PalmBarfel: $yy-$mm-$dd\n"); }
         }# else { print ("PalmGarfel: ($f[0])  ($f[1])   ($f[2])  ($f[3]) ($f[4])\n"); }
     }

            }

            if ($imp) {
                $listStyle = 'imported';
                $imported++;
            }

            if ($listStyle eq 'notentry') {
                $notentry++;
            }
        } else {
            $listStyle = 'noparse';
            $noparse++;
        }

        if ($listCSV) {
            $listline = quoteHTML($listline);
            printf("<span class=\"$listStyle\">%4d.  %s</span>\n", $n, $listline);
        }
    }

    }

    
    my $md;
    if (!$readOnly) {
        foreach $md (sort(keys(%mondb))) {
            if ($monchanges{$md} > 0) {
                $mondb{$md}->{last_modification_time} = time();
                open(FL, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/$md.hdb") ||
                    die("Cannot open monthly log file /server/pub/hackdiet/Users/$user_file_name/$md.hdb");
                $mondb{$md}->save(\*FL);
                close(FL);
                clusterCopy("/server/pub/hackdiet/Users/$user_file_name/$md.hdb");
            }
        }
    }


    if ($listCSV) {
        print $fh <<"EOD";
</pre>
EOD
    }

    
    print($fh "<p>\n
Records submitted: $n.<br />\n
Log items imported: $imported.<br />\n");

    print($fh "<span class=\"notentry\">Records ignored as not daily log entries: $notentry.</span><br />\n")
        if $notentry > 0;
    print($fh "<span class=\"conflict\">Records skipped to avoid overwriting existing entries: $already.</span><br />\n")
        if $already > 0;
    print($fh "<span class=\"noparse\">Records discarded due to parsing errors: $noparse.</span><br />\n")
        if $noparse > 0;
    print($fh "</p>\n");

    write_XHTML_epilogue($fh, $homeBase);


    if (!$readOnly) {
        my $histrec = "$logFormat,$overwrite,$imported,$notentry,$already,$noparse";
        foreach $md (sort(keys(%mondb))) {
            if ($monchanges{$md} > 0) {
                $histrec .= ",$md,$monchanges{$md}";
            }
        }
        append_history($user_file_name, 7, "$histrec");

        update_last_transaction($user_file_name);
    }

    } elsif ($CGIargs{q} eq 'exportdb') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    my @years = $ui->enumerateYears();

    

    my %percheck = ( 'm', '', 'q', '', 'h', '', 'y', '', 'c', '' );

    if (defined($CGIargs{period})) {
        $percheck{$CGIargs{period}} = ' checked="checked"';
    } else {
        $percheck{q} = ' checked="checked"';
    }

    my (@fy_selected, @ty_selected);
    for (my $i = 0; $i <= $#years; $i++) {
        if (defined($CGIargs{from_y}) && ($CGIargs{from_y} eq $years[$i])) {
            $fy_selected[$i] = ' selected="selected"';
        } else {
            $fy_selected[$i] = '';
        }
        if (defined($CGIargs{to_y}) && ($CGIargs{to_y} eq $years[$i])) {
            $ty_selected[$i] = ' selected="selected"';
        } else {
            $ty_selected[$i] = '';
        }
    }

    my (@fm_selected, @tm_selected);
    for (my $i = 1; $i <= 12; $i++) {
        if (defined($CGIargs{from_m}) && ($CGIargs{from_m} == $i)) {
            $fm_selected[$i] = ' selected="selected"';
        } else {
            $fm_selected[$i] = '';
        }
        if (defined($CGIargs{to_m}) && ($CGIargs{to_m} == $i)) {
            $tm_selected[$i] = ' selected="selected"';
        } else {
            $tm_selected[$i] = '';
        }
    }

    my (@fd_selected, @td_selected);
    for (my $i = 1; $i <= 31; $i++) {
        if (defined($CGIargs{from_d}) && ($CGIargs{from_d} == $i)) {
            $fd_selected[$i] = ' selected="selected"';
        } else {
            $fd_selected[$i] = '';
        }
        if (defined($CGIargs{to_d}) && ($CGIargs{to_d} == $i)) {
            $td_selected[$i] = ' selected="selected"';
        } else {
            $td_selected[$i] = '';
        }
    }

    my @cs_selected;
    $CGIargs{size} = '800x600' if !defined($CGIargs{size});
    $CGIargs{size} = '320x240' if $session->{handheld};
    for (my $i = 0; $i <= $#chartSizes; $i++) {
        if ($CGIargs{size} eq $chartSizes[$i]) {
            $cs_selected[$i] = ' selected="selected"';
        } else {
            $cs_selected[$i] = '';
        }
    }

    my $ckprint = $CGIargs{print} ? ' checked="checked"' : '';
    my $ckmono = $CGIargs{mono} ? ' checked="checked"' : '';


    write_XHTML_prologue($fh, $homeBase, "Export Log Database", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<h1 class="c">Export Log Database</h1>
EOD

    print $fh <<"EOD";
<form id="Hdiet_exportdb" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>

<p class="mlog_buttons">
<b>Format:</b><br />
    <label><input type="radio" name="format" value="xml" checked="checked" />&nbsp;Hacker's Diet <em>Online</em> XML</label><br />
    <label><input type="radio" name="format" value="csv" />&nbsp;Hacker's Diet <em>Online</em> CSV</label><br />
    <label><input type="radio" name="format" value="palm" />&nbsp;Palm Eat Watch CSV</label><br />
    <label><input type="radio" name="format" value="excel" />&nbsp;Legacy Excel CSV</label><br />
</p>


<p class="mlog_buttons">
<label><input type="radio" name="period" value="a" checked="checked" />&nbsp;<b>Export all months</b></label>
<br />
<label><input type="radio" name="period" value="c" />&nbsp;<b>Export months</b></label>
EOD

    $fy_selected[0] = ' selected="selected"';
    my @f_mon = $ui->enumerateMonths($years[0]);
    $f_mon[0] =~ m/^\d+\-(\d+)$/;
    my $fmon = $1 + 0;
    $fm_selected[$fmon] = ' selected="selected"';

    print($fh "From\n");
    
    my ($ysel, $msel, $dsel) = ("") x 3;
    if ("") {
        $ysel = ' onchange="change_from_y();"';
        $msel = ' onchange="change_from_m();"';
        $dsel = ' onchange="change_from_d();"';
    }

    print $fh <<"EOD";
    <select name="from_y" id="from_y"$ysel>
EOD

    
    for (my $i = 0; $i <= $#years; $i++) {
        print $fh <<"EOD";
        <option$fy_selected[$i]>$years[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>&nbsp;<select name="from_m" id="from_m"$msel>
EOD

    my $mid = "fm_";
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


        print $fh <<"EOD";
    </select>
EOD

    if (0) {
        print $fh <<"EOD";
    <select name="from_d" id="from_d"$dsel>
EOD
    }

    my $did;

    if (0) {
        $did = "fd_";
        
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


        print $fh <<"EOD";
        </select>
EOD
    }


    print $fh <<"EOD";
<br />
EOD

    $ty_selected[$#years] = ' selected="selected"';
    @f_mon = $ui->enumerateMonths($years[$#years]);
    $f_mon[$#f_mon] =~ m/^\d+\-(\d+)$/;
    $fmon = $1 + 0;
    $tm_selected[$fmon] = ' selected="selected"';

    print($fh "To\n");
    
    ($ysel, $msel, $dsel) = ("") x 3;
    if ("") {
        $ysel = ' onchange="change_to_y();"';
        $msel = ' onchange="change_to_m();"';
        $dsel = ' onchange="change_to_d();"';
    }
    print $fh <<"EOD";
    <select name="to_y" id="to_y"$ysel>
EOD

    @fy_selected = @ty_selected;
    
    for (my $i = 0; $i <= $#years; $i++) {
        print $fh <<"EOD";
        <option$fy_selected[$i]>$years[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>&nbsp;<select name="to_m" id="to_m"$msel>
EOD

    $mid = "tm_";
    @fm_selected = @tm_selected;
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>
EOD

    if (0) {
        print $fh <<"EOD";
    <select name="to_d" id="to_d"$dsel>
EOD
    }

    if (0) {
        $did = "td_";
        @fd_selected = @td_selected;
        
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


        print $fh <<"EOD";
    </select>
EOD
    }


    print $fh <<"EOD";
<br />


<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=do_exportdb" value=" Export " />
&nbsp;
<input type="reset" value=" Reset " />
&nbsp;
<input type="submit" name="q=account" value=" Cancel " />
</p>
</form>
EOD

    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'browsepub') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    if ($readOnly) {
        my $qun = quoteUserName($real_user_name);
        die("Invalid \"$CGIargs{q}\" transaction attempted by read-only account $qun");
    }

    write_XHTML_prologue($fh, $homeBase, "Browse Public Accounts", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    my $acct_category = $CGIargs{acct_category};

    
    my %accounts;

    opendir(CD, "/server/pub/hackdiet/Pubname") ||
        die("Cannot open directory /server/pub/hackdiet/Pubname");
    for my $f (grep(/.*\.hdp$/, readdir(CD))) {
        open(FU, "<:utf8", "/server/pub/hackdiet/Pubname/$f") ||
            die("Cannot open user account directory /server/pub/hackdiet/Pubname/$f");
        my $pn = HDiet::pubname->new();
        $pn->load(\*FU);
        close(FU);
        my $sortcode = $pn->{public_name};
        $accounts{$sortcode} = $pn->{true_name};
    }
    closedir(CD);


    print $fh <<"EOD";
<h1 class="c" style="margin-bottom: 0px;">Browse Public Accounts</h1>

EOD

    my $acct_qual;
    my ($chk_all, $chk_act, $chk_inact) = ('', '', '');
    if (!defined($acct_category) || ($acct_category eq 'all')) {
        print($fh "<h3 class=\"acct_category\">All Public Accounts</h3>\n");
        $acct_qual = '';
        $chk_all = ' selected="selected"';
    } elsif ($acct_category eq 'active') {
        print($fh "<h3 class=\"acct_category\">Active Public Accounts (Updated in the last 30 days)</h3>\n");
        $acct_qual = 'active ';
        $chk_act = ' selected="selected"';
    } elsif ($acct_category eq 'inactive') {
        print($fh "<h3 class=\"acct_category\">Inactive Public Accounts (No update in the last 30 days)</h3>\n");
        $acct_qual = 'inactive ';
        $chk_inact = ' selected="selected"';
    }

    print $fh <<"EOD";
<form id="Hdiet_pubacct" method="post" action="/cgi-bin/HackDiet">
    <p class="centred" style="margin-top: 0px; margin-bottom: 4px;">
    <input type="hidden" name="s" value="$session->{session_id}" />
    <select name="acct_category" size="1">
        <option value="active"$chk_act>Active accounts</option>
        <option value="inactive"$chk_inact>Inactive accounts</option>
        <option value="all"$chk_all>All accounts</option>
    </select>
    <input type="submit" name="q=browsepub" value=" View " />
    </p>
</form>

<form id="Hdiet_acctmgr" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>

<p class="mlog_buttons">
<input type="submit" name="q=do_public_browseacct" value=" Access " />
</p>

<table border="border" class="mlog">
<tr>
    <th>Sel</th>
    <th>Public Name</th>
    <th>Member Since</th>
    <th>Public Since</th>
    <th>Weight</th>
    <th>Energy</th>
    <th>Months</th>
    <th>First Log</th>
    <th>Last Log</th>
</tr>
EOD

    my $accts_displayed = 0;

    
    if (!defined($acct_category)) {
        $acct_category = 'active';
    }

    for my $n (sort(keys(%accounts))) {
        my $qn = quoteHTML($n);
        my $qun = quoteUserName($accounts{$n});

        if ($acct_category ne 'all') {
            my $lti = time() - last_transaction_time($qun);
            my $month = 30 * 24 * 60 * 60;
            if ((($acct_category eq 'active') && ($lti > $month)) ||
                (($acct_category eq 'inactive') && ($lti < $month))) {
                next;
            }
        }

        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$qun/UserAccount.hdu") ||
            next;
        my $ui = HDiet::user->new();
        $ui->load(\*FU);
        close(FU);
        my $alink = quoteHTML($n);
        my @acreate = gmtime($ui->{account_created});
        my $acr = sprintf("%04d-%02d-%02d", $acreate[5] + 1900, $acreate[4] + 1, $acreate[3]);
        my @apsince = gmtime($ui->{public_since});
        my $aps = sprintf("%04d-%02d-%02d", $apsince[5] + 1900, $apsince[4] + 1, $apsince[3]);
        my ($wu, $eu) = (HDiet::monthlog::WEIGHT_ABBREVIATIONS->[$ui->{display_unit}],
                         HDiet::monthlog::ENERGY_ABBREVIATIONS->[$ui->{energy_unit}]);
        my @months = $ui->enumerateMonths();
        my $nmonths = $#months + 1;
        $months[0] = '' if $nmonths == 0;

        $accts_displayed++;

        print $fh <<"EOD";
<tr>
    <td><input type="radio" name="pubacct" value="$alink" /></td>
    <td>$n</td>
    <td>$acr</td>
    <td>$aps</td>
    <td>$wu</td>
    <td>$eu</td>
    <td>$nmonths</td>
    <td>$months[0]</td>
    <td>$months[$#months]</td>
</tr>
EOD
    }


    print $fh <<"EOD";
</table>

<p class="centred">
$accts_displayed ${acct_qual}public accounts displayed.<br />
</p>

<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=do_public_browseacct" value=" Access " />
</p>

</form>
EOD
    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'do_public_browseacct') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    if ($readOnly) {
        my $qun = quoteUserName($real_user_name);
        die("Invalid \"$CGIargs{q}\" transaction attempted by read-only account $qun");
    }

    if (!defined($CGIargs{pubacct})) {
        write_XHTML_prologue($fh, $homeBase, "Invalid Access Request", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Invalid Access Request</h1>

<p class="justified">
You entered a request to access a public account, but did not specify which
account you wished to access.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=browsepub&amp;s=$session->{session_id}$tzOff">Return to browse public accounts</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        exit(0);
    }

    
    my $pn = HDiet::pubname->new();
    if (!defined($pn->findPublicName($CGIargs{pubacct}))) {
        my $qn = quoteHTML($CGIargs{pubacct});
        write_XHTML_prologue($fh, $homeBase, "Invalid Access Request", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Invalid Access Request</h1>

<p class="justified">
You requested to access a public account
&ldquo;<b>$qn</b>&rdquo;, but no such public
account exists.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=browsepub&amp;s=$session->{session_id}$tzOff">Return to browse public accounts</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        exit(0);
    }


    $session->{effective_name} = '';
    $session->{browse_name} = $pn->{public_name};
    open(FS, ">:utf8", "/server/pub/hackdiet/Sessions/$session->{session_id}.hds") ||
        die("Cannot create session file /server/pub/hackdiet/Sessions/$session->{session_id}.hds");
    $session->save(\*FS);
    close(FS);
    clusterCopy("/server/pub/hackdiet/Sessions/$session->{session_id}.hds");
    $CGIargs{q} = 'account';
    next;

    } elsif ($CGIargs{q} eq 'quitbrowse') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    if ($assumed_identity || $browse_public) {
        $session->{effective_name} = $session->{browse_name} = '';
        open(FS, ">:utf8", "/server/pub/hackdiet/Sessions/$session->{session_id}.hds") ||
            die("Cannot create session file /server/pub/hackdiet/Sessions/$session->{session_id}.hds");
        $session->save(\*FS);
        close(FS);
        clusterCopy("/server/pub/hackdiet/Sessions/$session->{session_id}.hds");
    }
    $CGIargs{q} = 'account';
    next;

    } elsif ($CGIargs{q} eq 'configure_badge') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);


    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    write_XHTML_prologue($fh, $homeBase, "Configure Web Page Status Badge", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    my @cterm;
    $cterm[0] = $cterm[7] = $cterm[14] = $cterm[1] = $cterm[3] = $cterm[6] = $cterm[12] = '';
    $cterm[abs($ui->{badge_trend})] = ' selected="selected"';

    print $fh <<"EOD";
<h1 class="c">Configure Web Page Status Badge</h1>

<p class="centred">
<img src="$homeBase/figures/badge_sample.png"
    width="200" height="78"
    alt="Sample Web status badge" />
</p>

<p class="justified">
A Web badge is a small image like the example above which you can add to
your personal Web page or Web log which shows, as of the
most recent log entry, your weight, daily energy (calorie or kilojoule)
balance, and your present weekly rate of weight loss or gain based
upon fitting a linear trend to the trend values for the interval
chosen below.
</p>

<form id="Hdiet_badgeconf" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
EOD

    print $fh <<"EOD";
<p class="mlog_buttons">
<select name="badge_term" id="badge_term"
    onchange="change_badge_term();">
    <option value="0"$cterm[0]>Disable badge</option>
    <option value="7"$cterm[7]>Week</option>
    <option value="14"$cterm[14]>Fortnight</option>
    <option value="-1"$cterm[1]>Month</option>
    <option value="-3"$cterm[3]>Quarter</option>
    <option value="-6"$cterm[6]>Six months</option>
    <option value="-12"$cterm[12]>Year</option>
</select>
</p>

<p class="justified">
After choosing the interval over which you wish the trend to be
computed, press the &ldquo;Apply&rdquo; button below.  You'll
be taken to a confirmation page which includes HTML/XHTML code
you can cut and paste into your Web page to display the badge.
If you select &ldquo;Disable badge&rdquo;, badge generation will
be disabled and any existing badge image deleted; if you disable
badge generation, be sure to remove the badge image from your Web
page, as otherwise visitors will see an &ldquo;Invalid request&rdquo;
icon instead of the badge.
</p>

EOD

    print $fh <<"EOD";
<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=update_badge" value=" Apply " />
&nbsp;
<input type="reset" value=" Reset " />
&nbsp;
<input type="submit" name="q=account" value=" Cancel " />
</p>
</form>
EOD

    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'paper_logs') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    my @years;

    

    my %percheck = ( 'm', '', 'q', '', 'h', '', 'y', '', 'c', '' );

    if (defined($CGIargs{period})) {
        $percheck{$CGIargs{period}} = ' checked="checked"';
    } else {
        $percheck{q} = ' checked="checked"';
    }

    my (@fy_selected, @ty_selected);
    for (my $i = 0; $i <= $#years; $i++) {
        if (defined($CGIargs{from_y}) && ($CGIargs{from_y} eq $years[$i])) {
            $fy_selected[$i] = ' selected="selected"';
        } else {
            $fy_selected[$i] = '';
        }
        if (defined($CGIargs{to_y}) && ($CGIargs{to_y} eq $years[$i])) {
            $ty_selected[$i] = ' selected="selected"';
        } else {
            $ty_selected[$i] = '';
        }
    }

    my (@fm_selected, @tm_selected);
    for (my $i = 1; $i <= 12; $i++) {
        if (defined($CGIargs{from_m}) && ($CGIargs{from_m} == $i)) {
            $fm_selected[$i] = ' selected="selected"';
        } else {
            $fm_selected[$i] = '';
        }
        if (defined($CGIargs{to_m}) && ($CGIargs{to_m} == $i)) {
            $tm_selected[$i] = ' selected="selected"';
        } else {
            $tm_selected[$i] = '';
        }
    }

    my (@fd_selected, @td_selected);
    for (my $i = 1; $i <= 31; $i++) {
        if (defined($CGIargs{from_d}) && ($CGIargs{from_d} == $i)) {
            $fd_selected[$i] = ' selected="selected"';
        } else {
            $fd_selected[$i] = '';
        }
        if (defined($CGIargs{to_d}) && ($CGIargs{to_d} == $i)) {
            $td_selected[$i] = ' selected="selected"';
        } else {
            $td_selected[$i] = '';
        }
    }

    my @cs_selected;
    $CGIargs{size} = '800x600' if !defined($CGIargs{size});
    $CGIargs{size} = '320x240' if $session->{handheld};
    for (my $i = 0; $i <= $#chartSizes; $i++) {
        if ($CGIargs{size} eq $chartSizes[$i]) {
            $cs_selected[$i] = ' selected="selected"';
        } else {
            $cs_selected[$i] = '';
        }
    }

    my $ckprint = $CGIargs{print} ? ' checked="checked"' : '';
    my $ckmono = $CGIargs{mono} ? ' checked="checked"' : '';


    write_XHTML_prologue($fh, $homeBase, "Generate Log Forms", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<h1 class="c">Generate Paper Log Forms</h1>
EOD

    print $fh <<"EOD";
<form id="Hdiet_plog" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>


<p class="mlog_buttons">
EOD

    my $jdnow = unix_time_to_jd(time());
    my ($enowy, $enowm, $enowd) = jd_to_gregorian($jdnow);
    my @f_mon;

    for (my $y = $enowy - 1; $y <= $enowy + 1; $y++) {
        $fy_selected[$y - ($enowy - 1)] = $ty_selected[$y - ($enowy - 1)] = '';
        $years[$y - ($enowy - 1)] = $y;
        for (my $m = 1; $m <= 12; $m++) {
            $f_mon[$m] = sprintf("%4d-%02d", $y, $m);
        }
    }
    $fy_selected[1] = ' selected="selected"';
    $fm_selected[1] = ' selected="selected"';

    print($fh "From\n");
    
    my ($ysel, $msel, $dsel) = ("") x 3;
    if ("") {
        $ysel = ' onchange="change_from_y();"';
        $msel = ' onchange="change_from_m();"';
        $dsel = ' onchange="change_from_d();"';
    }

    print $fh <<"EOD";
    <select name="from_y" id="from_y"$ysel>
EOD

    
    for (my $i = 0; $i <= $#years; $i++) {
        print $fh <<"EOD";
        <option$fy_selected[$i]>$years[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>&nbsp;<select name="from_m" id="from_m"$msel>
EOD

    my $mid = "fm_";
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


        print $fh <<"EOD";
    </select>
EOD

    if (0) {
        print $fh <<"EOD";
    <select name="from_d" id="from_d"$dsel>
EOD
    }

    my $did;

    if (0) {
        $did = "fd_";
        
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


        print $fh <<"EOD";
        </select>
EOD
    }


    print $fh <<"EOD";
<br />
EOD

    $ty_selected[1] = ' selected="selected"';
    $tm_selected[12] = ' selected="selected"';

    print($fh "To\n");
    
    ($ysel, $msel, $dsel) = ("") x 3;
    if ("") {
        $ysel = ' onchange="change_to_y();"';
        $msel = ' onchange="change_to_m();"';
        $dsel = ' onchange="change_to_d();"';
    }
    print $fh <<"EOD";
    <select name="to_y" id="to_y"$ysel>
EOD

    @fy_selected = @ty_selected;
    
    for (my $i = 0; $i <= $#years; $i++) {
        print $fh <<"EOD";
        <option$fy_selected[$i]>$years[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>&nbsp;<select name="to_m" id="to_m"$msel>
EOD

    $mid = "tm_";
    @fm_selected = @tm_selected;
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>
EOD

    if (0) {
        print $fh <<"EOD";
    <select name="to_d" id="to_d"$dsel>
EOD
    }

    if (0) {
        $did = "td_";
        @fd_selected = @td_selected;
        
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


        print $fh <<"EOD";
    </select>
EOD
    }


    print $fh <<"EOD";
<br />


<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=do_paper_logs" value=" Generate " />
&nbsp;
<input type="reset" value=" Reset " />
&nbsp;
<input type="submit" name="q=account" value=" Cancel " />
</p>
</form>

<script type="text/javascript" defer="defer">
/* <![CDATA[ */
    if (document.getElementById && document.getElementById("Hdiet_plog")) {
        document.getElementById("Hdiet_plog").target = "_blank";
    }
/* ]]> */
</script>

EOD

    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'do_paper_logs') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    my @years;

    

    my %percheck = ( 'm', '', 'q', '', 'h', '', 'y', '', 'c', '' );

    if (defined($CGIargs{period})) {
        $percheck{$CGIargs{period}} = ' checked="checked"';
    } else {
        $percheck{q} = ' checked="checked"';
    }

    my (@fy_selected, @ty_selected);
    for (my $i = 0; $i <= $#years; $i++) {
        if (defined($CGIargs{from_y}) && ($CGIargs{from_y} eq $years[$i])) {
            $fy_selected[$i] = ' selected="selected"';
        } else {
            $fy_selected[$i] = '';
        }
        if (defined($CGIargs{to_y}) && ($CGIargs{to_y} eq $years[$i])) {
            $ty_selected[$i] = ' selected="selected"';
        } else {
            $ty_selected[$i] = '';
        }
    }

    my (@fm_selected, @tm_selected);
    for (my $i = 1; $i <= 12; $i++) {
        if (defined($CGIargs{from_m}) && ($CGIargs{from_m} == $i)) {
            $fm_selected[$i] = ' selected="selected"';
        } else {
            $fm_selected[$i] = '';
        }
        if (defined($CGIargs{to_m}) && ($CGIargs{to_m} == $i)) {
            $tm_selected[$i] = ' selected="selected"';
        } else {
            $tm_selected[$i] = '';
        }
    }

    my (@fd_selected, @td_selected);
    for (my $i = 1; $i <= 31; $i++) {
        if (defined($CGIargs{from_d}) && ($CGIargs{from_d} == $i)) {
            $fd_selected[$i] = ' selected="selected"';
        } else {
            $fd_selected[$i] = '';
        }
        if (defined($CGIargs{to_d}) && ($CGIargs{to_d} == $i)) {
            $td_selected[$i] = ' selected="selected"';
        } else {
            $td_selected[$i] = '';
        }
    }

    my @cs_selected;
    $CGIargs{size} = '800x600' if !defined($CGIargs{size});
    $CGIargs{size} = '320x240' if $session->{handheld};
    for (my $i = 0; $i <= $#chartSizes; $i++) {
        if ($CGIargs{size} eq $chartSizes[$i]) {
            $cs_selected[$i] = ' selected="selected"';
        } else {
            $cs_selected[$i] = '';
        }
    }

    my $ckprint = $CGIargs{print} ? ' checked="checked"' : '';
    my $ckmono = $CGIargs{mono} ? ' checked="checked"' : '';


    write_XHTML_prologue($fh, $homeBase, "Weight and Exercise Log",
        " if (window.print) { setTimeout('window.print()', 1000); }", $session->{handheld}, 1);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    #   If start and end dates are reversed, silently exchange them.
    if (gregorian_to_jd($CGIargs{from_y}, $CGIargs{from_m}, 1) >
        gregorian_to_jd($CGIargs{to_y}, $CGIargs{to_m}, 1)) {
        my ($fy, $fm) = ($CGIargs{from_y}, $CGIargs{from_m});
        ($CGIargs{from_y}, $CGIargs{from_m}) = ($CGIargs{to_y}, $CGIargs{to_m});
        ($CGIargs{to_y}, $CGIargs{to_m}) = ($fy, $fm);
    }

    my $firstpage = 1;
    for (my $y = $CGIargs{from_y}; $y <= $CGIargs{to_y}; $y++) {
        my $sm = ($y == $CGIargs{from_y}) ? $CGIargs{from_m} : 1;
        my $em = ($y == $CGIargs{to_y}) ? $CGIargs{to_m} : 12;
        for (my $m = $sm; $m <= $em; ) {
            
    my $plc = $firstpage ? 'plog_first' : 'plog_subsequent';
    $firstpage = 0;
    my $mdays = HDiet::monthlog::monthdays($y, $m);

    print $fh <<"EOD";
<div class="$plc">
<h1 class="plog">Weight and Exercise Log</h1>
<h2 class="plog">$monthNames[$m] $y</h2>
<table class="plog">
    <tr class="heading">
        <th class="h1" colspan="3">Date</th>
        <td class="s2"></td>
        <th class="h4">Weight</th>
        <td class="s4"></td>
        <th class="h5">Rung</th>
        <td class="s5"></td>
        <th class="h6">Flag</th>
        <td class="s6"></td>
        <th class="h7">Comments</th>
    </tr>
EOD

    my $wday = jd_to_weekday(gregorian_to_jd($y, $m, 1));

    for (my $d = 1; $d <= $mdays; $d++) {
        my $wdn = substr(HDiet::Julian::WEEKDAY_NAMES->[$wday], 0, 3);
        $wday = ($wday + 1) % 7;
        #   The "&nbsp;"s in this table are courtesy of crap-bag
        #   Internet Explorer, which doesn't draw a border below
        #   a table cell if it's empty.
        print $fh <<"EOD";
    <tr>
        <th class="c1">$d</th>
        <td class="s1"></td>
        <td class="c2">$wdn</td>
        <td class="s2"></td>
        <td class="c3">&nbsp;</td>
        <td class="s3"></td>
        <td class="c4">&nbsp;</td>
        <td class="s4"></td>
        <td class="c5">&nbsp;</td>
        <td class="s5"></td>
        <td class="c6">&nbsp;</td>
    </tr>
EOD
    }

    print $fh <<"EOD";
</table>
</div>
EOD

            $m++;
            if ($m > 12) {
                $m = 1;
                last;
            }
        }
    }

    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'update_badge') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);


    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    write_XHTML_prologue($fh, $homeBase, "Web Page Status Badge Configuration Changed", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    $CGIargs{badge_term} = '0' if !defined($CGIargs{badge_term});

    $ui->{badge_trend} = $CGIargs{badge_term};

    my %valid_term = ( 0, 1, 7, 1, 14, 1, -1, 1, -3, 1, -6, 1, -12, 1 );
    if (!defined($valid_term{$ui->{badge_trend}})) {
        $ui->{badge_trend} = 0;
    }

    
    open(FU, ">:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    $ui->save(\*FU);
    close(FU);
    clusterCopy("/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");


    if ($ui->{badge_trend} != 0) {
        
    open(FB, ">/server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png") ||
        die("Cannot update monthly log file /server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png");
    my $hist = HDiet::history->new($ui, $user_file_name);
    $hist->drawBadgeImage(\*FB, $ui->{badge_trend});
    close(FB);
    do_command("mv /server/pub/hackdiet/Users/$user_file_name/BadgeImageNew.png /server/pub/hackdiet/Users/$user_file_name/BadgeImage.png");
    clusterCopy("/server/pub/hackdiet/Users/$user_file_name/BadgeImage.png");

    } else {
        if (-f "/server/pub/hackdiet/Users/$user_file_name/BadgeImage.png") {
            unlink("/server/pub/hackdiet/Users/$user_file_name/BadgeImage.png");
            clusterDelete("/server/pub/hackdiet/Users/$user_file_name/BadgeImage.png");
        }
    }

    print $fh <<"EOD";
<h1 class="c">Web Page Status Badge<br />
Configuration Changed</h1>
EOD

    if ($ui->{badge_trend} == 0) {
        print $fh <<"EOD";
<p class="justified">
You have disabled generation of a Web page status badge.  Please be
sure to remove the HTML/XHTML code from your Web page which displays
the badge, otherwise you'll see an &ldquo;Invalid request&rdquo; icon
where the badge used to appear.
</p>
EOD
    } else {
        my @cterm;

        $cterm[7]  = 'week';
        $cterm[14] = 'fortnight';
        $cterm[1]  = 'month';
        $cterm[3]  = 'quarter';
        $cterm[6]  = 'six months';
        $cterm[12] = 'year';
        my $ct = $cterm[abs($ui->{badge_trend})];

        my $uec = $ui->generateEncryptedUserID();

        print $fh <<"EOD";
<p class="justified">
You have enabled Web page status badge generation with the
trend for the last
</p>

<p class="centred">
<b>$ct</b>
</p>

<p class="justified">
displayed in the badge.  To display the badge on your Web page,
copy and paste the following HTML/XHTML code into the page
where you'd like to badge to appear.  Be sure to select the
<em>entire</em> text in the box: the URL for the image is
very long and must not be truncated.
</p>

EOD

    print $fh <<"EOD";
<form id="Hdiet_badgeproto" action="#" onsubmit="return false;">
<p class="centred">
<textarea cols="80" rows="4" name="protocode" readonly="readonly"
    style="background-color: #FFFFA0; color: inherit;">
&lt;a href="http://www.fourmilab.ch/hackdiet/online/"&gt;&lt;img style="border: 0px;"
src="http://www.fourmilab.ch/cgi-bin/HackDietBadge?t=1&amp;amp;b=$uec"
alt="The Hacker's Diet Online" /&gt;&lt;/a&gt;
</textarea>
</p>
</form>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
    }

    write_XHTML_epilogue($fh, $homeBase);

    if (!$readOnly) {
        append_history($user_file_name, 19, $ui->{badge_trend});
        update_last_transaction($user_file_name);
    }

    } elsif ($CGIargs{q} eq 'update_trend') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);


    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    $CGIargs{m} = '0000-00' if !defined($CGIargs{m});
    $CGIargs{canon} = 0 if !defined($CGIargs{canon});
    if ($CGIargs{canon} ne 0) {
        $CGIargs{canon} = 1;
    }

    if ($CGIargs{m} ne '0000-00') {
        
    if (!(($CGIargs{m} =~ m/^(\d\d\d\d)\-(\d\d)$/) &&
        ($1 >= 1980) && ($1 <= ((unix_time_to_civil_date_time($userTime))[0] + 1)) &&
        ($2 >= 1) && ($2 <= 12))) {
        if (!$inHTML) {
            if ($ENV{'REQUEST_METHOD'}) {
                
    print($fh "Content-type: text/html\r\n\r\n");

            }
            $inHTML = 1;
        }
        write_XHTML_prologue($fh, $homeBase, "Create New User Account", undef, $session->{handheld});
        my $qm = quoteHTML($CGIargs{m});
        print $fh <<"EOD";
<h1 class="c">Invalid Log Date Specification</h1>

<p class="justified">
Your request specified an invalid date:
</p>

<p class="centred">
<tt>$qm</tt>
</p>

<p class="justified">
for a monthly log.  Dates must be specified as &ldquo;<i>YYYY</i><tt>-</tt><i>MM</i>&rdquo;.
</p>


<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account home page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        last;
    }

    }

write_XHTML_prologue($fh, $homeBase, "Recompute trend carry-forward", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<h1 class="c">Trend Recalculation Complete</h1>
EOD
    propagate_trend($ui, $CGIargs{m}, $CGIargs{canon}) if !$readOnly;

    print $fh <<"EOD";
<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Back to account page</a></h4>
EOD
write_XHTML_epilogue($fh, $homeBase);

    if (!$readOnly) {
        append_history($user_file_name, 4, "$CGIargs{m},$CGIargs{canon}");
        update_last_transaction($user_file_name);
    }

    } elsif ($CGIargs{q} eq 'feedback') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    write_XHTML_prologue($fh, $homeBase, "Send Feedback", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<h1 class="c">Send Feedback</h1>
EOD

    my ($subject, $category, $message, $from) = ('') x 4;
    my @feedsel;
    if (defined($CGIargs{message})) {
        
    ($subject, $category, $message, $from) =
            ($CGIargs{subject},
             $feedback_categories[$CGIargs{category}],
             $CGIargs{message},
             $ui->{e_mail});

    $subject =~ s/[\r\n]/ /g;
    $category =~ s/[\r\n]/ /g;
    $message =~ s/\r\n/\n/g;
    $message =~ s/\n\.\n/\n\. \n/g;

    
    my $pt = $CGIargs{message};
    $pt =~ s/\r\n/\n/g;
    my $t = $pt;
    $pt = '';
    if (!($t =~ m/\n$/)) {
        $t .= "\n";
    }
    while ($t =~ s/^(.*\n)//) {
        my $l = $1;
        if (length($l) > 64) {
            $l = wrapText($l, 64);
        }
        $pt .= $l;
    }
    $pt =~ s/\n\n+$/\n/;
    $pt = quoteHTML($pt);

    my ($qli, $qem, $qcat, $qsub) = (quoteHTML($ui->{login_name}), quoteHTML($ui->{e_mail}),
        quoteHTML($category), quoteHTML($subject));
    print $fh <<"EOD";

<pre class="preview"><b>From:</b>     $qli &lt;$qem&gt;
<b>Category:</b> $qcat
<b>Subject:</b>  $qsub

$pt</pre>
EOD


    $feedsel[$CGIargs{category}] = 1;

    
    my $spell = 1;          # We may make this optional some day
    my $spellCmd = 'aspell list --encoding=utf-8 --mode=none | sort -u';
    if ($spell && ($spellCmd ne '')) {
        my $sfn = "/server/pub/hackdiet/Users/$user_file_name/spell$$.tmp";
        if (open(SP, "|-:utf8", "$spellCmd >$sfn")) {
            print(SP $subject . "\n");
            print(SP $message . "\n");
            close(SP);
            open(SF, "<:utf8", $sfn) ||
                die("Cannot reopen spelling file $sfn");
            my $pt = '';
            while (<SF>) {
                $pt .= $_;
            }
            close(SF);
            unlink($sfn);
            $pt =~ s/^\s+//;
            $pt =~ s/\s+$//;
            $pt =~ s/\s+/ /g;
            if ($pt eq '') {
                print $fh <<"EOD";
<div class="spell_ok">
<h4>No Misspelled Words</h4>
</div>
EOD
            } else {
                $pt = quoteHTML(wrapText($pt, 64));
                print $fh <<"EOD";
<div class="spell_dubieties">
<h4>Possibly Misspelled Words</h4>
<pre>$pt
</pre>
</div>
EOD
            }
        }
    }


    }

    
    $feedsel[$CGIargs{category}] = 1 if defined($CGIargs{category});
    my $ckcopy = defined($CGIargs{copy_sender}) ? ' checked="checked"' : '';
    my $qun = quoteHTML($user_name);
    my $em = $ui->{e_mail};
    if ("$ui->{first_name}$ui->{middle_name}$ui->{last_name}" ne "") {
        my $fname = "$ui->{first_name} $ui->{middle_name} $ui->{last_name}";
        $fname =~ s/\s+/ /g;
        $fname =~ s/^\s+//;
        $fname =~ s/\s+$//;
        $em = "$fname <$em>";
    }
    my $qem = quoteHTML($em);
    print $fh <<"EOD";
<form id="Hdiet_feedback" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
<table border="border" class="feedback">
<tr>
<th>Name:<br />E-mail:</th> <td>$qun<br />$qem</td>
</tr>
EOD

    
    print $fh <<"EOD";
<tr>
<th>Category:</th>
<td>
    <select name="category" id="category">
EOD

    for (my $i = 0; $i <= $#feedback_categories; $i++) {
        my $sel = $feedsel[$i] ? ' selected="selected"' : '';
        print($fh "        <option value=\"$i\"$sel>$feedback_categories[$i]</option>\n");
    }
    print $fh <<"EOD";
    </select>
</td>
</tr>
EOD


    my $qms = quoteHTML($message);
    print $fh <<"EOD";
<tr>
<th>Subject:</th>
<td>
    <input type="text" name="subject" value="$subject" size="64" maxlength="80" />
</td>
</tr>
<tr>
<th class="t">Message:</th>
<td>
    <textarea cols="64" rows="16" name="message">$qms</textarea>
</td>
</tr>
</table>

<p class="mlog_buttons">
<input type="checkbox" name="copy_sender" id="copy_sender"$ckcopy />&nbsp;<label
    for="copy_sender">Send me a copy of the feedback message</label><br />
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=feedback" value=" Preview " onclick="return validateFeedback();" />
&nbsp;
<input type="submit" name="q=send_feedback" value=" Send Feedback " onclick="return validateFeedback();" />
&nbsp;
<input type="submit" name="q=account" value=" Cancel " />
</p>
</form>
EOD


    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'send_feedback') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    write_XHTML_prologue($fh, $homeBase, "Feedback Sent", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    my ($subject, $category, $message, $from) =
            ($CGIargs{subject},
             $feedback_categories[$CGIargs{category}],
             $CGIargs{message},
             $ui->{e_mail});

    $subject =~ s/[\r\n]/ /g;
    $category =~ s/[\r\n]/ /g;
    $message =~ s/\r\n/\n/g;
    $message =~ s/^\.\n/\. \n/;
    $message =~ s/\n\.\n/\n\. \n/g;

    if (!$readOnly) {
        
    $from = "noreply\@fourmilab.ch" if !defined($from);

    my $zto = 'bitbucket@fourmilab.ch';
    my $bn = <<"EOD";
5258

EOD
    $bn =~ s/\s+$//;
    my $bt = <<"EOD";
2022-04-05 19:18 UTC

EOD
    $bt =~ s/\s+$//;
    my $browser = defined($ENV{HTTP_USER_AGENT}) ? "\r\nBrowser:  $ENV{HTTP_USER_AGENT}" : '';
    my $fullName;
    if ("$ui->{first_name}$ui->{middle_name}$ui->{last_name}" ne "") {
        $fullName = "$ui->{first_name} $ui->{middle_name} $ui->{last_name}";
        $fullName =~ s/\s+/ /g;
        $fullName =~ s/^\s+//;
        $fullName =~ s/\s+$//;
        $fullName = "\r\nUser:     $fullName";
    }

    open(MAIL, "|-:utf8", "/usr/lib/sendmail",
            "-f$from",
            $zto) ||
        die("Cannot create pipe to /usr/lib/sendmail");
    print MAIL <<"EOD";
From $from\r
To: $zto\r
Subject: [HackDiet Feedback] $category\r
Content-type: text/plain; charset=utf-8\r
\r
From:     $ui->{login_name} <$from>$fullName\r
Category: $category\r
Subject:  $subject$browser\r
Build:    $bn: $bt\r
\r
$message
.\r
EOD
    close(MAIL);


        if ($CGIargs{copy_sender}) {
            
    open(MAIL, "|-:utf8", "/usr/lib/sendmail",
            "-fnoreply\@fourmilab.ch",
            $from) ||
        die("Cannot create pipe to /usr/lib/sendmail");
    print MAIL <<"EOD";
From $from\r
To: $from\r
Subject: [Hacker's Diet Online Feedback] $category\r
Content-type: text/plain; charset=utf-8\r
\r
From:     $ui->{login_name} <$from>\r
Category: $category\r
Subject:  $subject\r
\r
$message
.\r
EOD
    close(MAIL);

        }
    }

    print $fh <<"EOD";
<h1 class="c">Feedback Sent</h1>

<p class="justified">
<b>The following feedback message has been sent.  Thank you
for contributing to the improvement of The Hacker's Diet
<em>Online</em>.</b>
</p>
EOD

    
    my $pt = $CGIargs{message};
    $pt =~ s/\r\n/\n/g;
    my $t = $pt;
    $pt = '';
    if (!($t =~ m/\n$/)) {
        $t .= "\n";
    }
    while ($t =~ s/^(.*\n)//) {
        my $l = $1;
        if (length($l) > 64) {
            $l = wrapText($l, 64);
        }
        $pt .= $l;
    }
    $pt =~ s/\n\n+$/\n/;
    $pt = quoteHTML($pt);

    my ($qli, $qem, $qcat, $qsub) = (quoteHTML($ui->{login_name}), quoteHTML($ui->{e_mail}),
        quoteHTML($category), quoteHTML($subject));
    print $fh <<"EOD";

<pre class="preview"><b>From:</b>     $qli &lt;$qem&gt;
<b>Category:</b> $qcat
<b>Subject:</b>  $qsub

$pt</pre>
EOD


    print $fh <<"EOD";
<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Back
    to account page</a></h4>
EOD

    write_XHTML_epilogue($fh, $homeBase);

    append_history($user_file_name, 16, $category) if !$readOnly;

    } elsif ($CGIargs{q} eq 'test') {
        


    
    } elsif ($CGIargs{q} eq 'acctmgr') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    write_XHTML_prologue($fh, $homeBase, "Account Manager", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<h1 class="c" style="margin-bottom: 0px;">Account Manager</h1>
EOD

    my $acct_qual;
    my ($chk_all, $chk_act, $chk_inact) = ('', '', '');

    my $acct_category = $CGIargs{acct_category};
    if (!defined($acct_category) || ($acct_category eq 'all')) {
        print($fh "<h3 class=\"acct_category\">All Accounts</h3>\n");
        $acct_qual = '';
        $chk_all = ' selected="selected"';
    } elsif ($acct_category eq 'active') {
        print($fh "<h3 class=\"acct_category\">Active Accounts (Updated in the last 30 days)</h3>\n");
        $acct_qual = 'active ';
        $chk_act = ' selected="selected"';
    } elsif ($acct_category eq 'inactive') {
        print($fh "<h3 class=\"acct_category\">Inactive Accounts (No update in the last 30 days)</h3>\n");
        $acct_qual = 'inactive ';
        $chk_inact = ' selected="selected"';
    }

    print $fh <<"EOD";
<form id="Hdiet_pubacct" method="post" action="/cgi-bin/HackDiet">
    <p class="centred" style="margin-top: 0px; margin-bottom: 4px;">
    <input type="hidden" name="s" value="$session->{session_id}" />
    <select name="acct_category" size="1">
        <option value="active"$chk_act>Active accounts</option>
        <option value="inactive"$chk_inact>Inactive accounts</option>
        <option value="all"$chk_all>All accounts</option>
    </select>
    <input type="submit" name="q=acctmgr" value=" View " />
    </p>
</form>


<form id="Hdiet_acctmgr" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>

<table border="border" class="mlog">
<tr>
    <th>Sel</th>
    <th>Login</th>
    <th>First</th>
    <th>Mid</th>
    <th>Last</th>
    <th>E-mail</th>
    <th>Created</th>
    <th>Weight</th>
    <th>Energy</th>
    <th>Adm</th>
    <th>Pub</th>
    <th>R/O</th>
    <th>Pubname</th>
    <th>Months</th>
    <th>Start</th>
    <th>Latest</th>
</tr>
EOD


    
    my %accounts;

    if (!defined($acct_category)) {
        $acct_category = 'active';
    }

    opendir(CD, "/server/pub/hackdiet/Users") ||
        die("Cannot open directory /server/pub/hackdiet/Users");
    for my $f (grep(!/\.\.?\z/, readdir(CD))) {

        if ($acct_category ne 'all') {
            my $lti = time() - last_transaction_time($f);
            my $month = 30 * 24 * 60 * 60;
            if ((($acct_category eq 'active') && ($lti > $month)) ||
                (($acct_category eq 'inactive') && ($lti < $month))) {
                next;
            }
        }

        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$f/UserAccount.hdu") ||
            die("Cannot open user account directory /server/pub/hackdiet/Users/$f/UserAccount.hdu");
        my $ui = HDiet::user->new();
        $ui->load(\*FU);
        close(FU);
        my $sortcode = $ui->{login_name};
        $accounts{$sortcode} = $f;
    }
    closedir(CD);


    my ($naccts, $npub) = (0, 0);
    for my $n (sort({ lc($a) cmp lc($b)} keys(%accounts))) {
        my $qn = quoteHTML($n);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$accounts{$n}/UserAccount.hdu") ||
            die("Cannot open user account directory /server/pub/hackdiet/Users/$accounts{$n}/UserAccount.hdu");
        my $ui = HDiet::user->new();
        $ui->load(\*FU);
        close(FU);
        my $alink = quoteHTML($n);
        my @acreate = gmtime($ui->{account_created});
        my $acr = sprintf("%04d-%02d-%02d", $acreate[5] + 1900, $acreate[4] + 1, $acreate[3]);
        my $qem = quoteHTML($ui->{e_mail});
        my $adm = $ui->{administrator} ? '&#10004;' : '';
        my $pub = $ui->{public} ? '&#10004;' : '';
        my $ronly = $ui->{read_only} ? '&#10004;' : '';
        my @name = (quoteHTML($ui->{first_name}), quoteHTML($ui->{middle_name}),
                     quoteHTML($ui->{last_name}), quoteHTML($ui->{public_name}));
#if ($ui->{log_unit} eq '' || $ui->{display_unit} eq '' || $ui->{energy_unit} eq '') { print(STDERR "Gronk!  $n  ($ui->{log_unit}) ($ui->{display_unit}) ($ui->{energy_unit})\n"); }
        my ($wu, $eu) = ((HDiet::monthlog::WEIGHT_ABBREVIATIONS->[$ui->{log_unit}] .
                        "/" . HDiet::monthlog::WEIGHT_ABBREVIATIONS->[$ui->{display_unit}]),
                         HDiet::monthlog::ENERGY_ABBREVIATIONS->[$ui->{energy_unit}]);
        my @months = $ui->enumerateMonths();
        my $nmonths = $#months + 1;
        $months[0] = '' if $nmonths == 0;

        $naccts++;
        $npub++ if $ui->{public};

        print $fh <<"EOD";
<tr>
    <td><input type="radio" name="useracct" value="$alink" /></td>
    <td>$n</td>
    <td>$name[0]</td>
    <td>$name[1]</td>
    <td>$name[2]</td>
    <td>$qem</td>
    <td>$acr</td>
    <td>$wu</td>
    <td>$eu</td>
    <td>$adm</td>
    <td>$pub</td>
    <td>$ronly</td>
    <td>$name[3]</td>
    <td>$nmonths</td>
    <td>$months[0]</td>
    <td>$months[$#months]</td>
</tr>
EOD
    }

    my $percentPub = int(($npub * 100) / $naccts);

    print $fh <<"EOD";
</table>

<p class="acct_summary">
$naccts accounts, $npub of which ($percentPub%) grant public access.
</p>

<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=do_admin_browseacct" value=" Access " />
&nbsp;
<input type="submit" name="q=do_admin_delacct" value=" Delete " />
&nbsp;
<input type="submit" name="q=do_admin_purgeacct" value=" Purge Logs " />
</p>

<p class="mlog_buttons">
Administrator password:
    <input type="password" name="HDiet_password" size="20"
               maxlength="4096" value="" />
</p>

</form>
EOD
    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'do_admin_browseacct') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    if (!defined($CGIargs{useracct})) {
        write_XHTML_prologue($fh, $homeBase, "Invalid Access Request", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Invalid Access Request</h1>

<p class="justified">
You entered a request to access a user account, but did not specify which
account you wished to access.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=acctmgr&amp;s=$session->{session_id}$tzOff">Return to account manager</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        exit(0);
    }

    $user_file_name = quoteUserName($CGIargs{useracct});

    if (!(-d "/server/pub/hackdiet/Users/$user_file_name")) {
        write_XHTML_prologue($fh, $homeBase, "Invalid Access Request", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        my $qun = quoteHTML($CGIargs{useracct});

        print $fh <<"EOD";
<h1 class="c">Invalid Access Request</h1>

<p class="justified">
You requested access to account <b>$qun</b>, but no such account exists.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=acctmgr&amp;s=$session->{session_id}$tzOff">Return to account manager</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        exit(0);
    }

    $session->{effective_name} = $CGIargs{useracct};
    $session->{browse_name} = '';
    open(FS, ">:utf8", "/server/pub/hackdiet/Sessions/$session->{session_id}.hds") ||
        die("Cannot create session file /server/pub/hackdiet/Sessions/$session->{session_id}.hds");
    $session->save(\*FS);
    close(FS);
    clusterCopy("/server/pub/hackdiet/Sessions/$session->{session_id}.hds");
    $CGIargs{q} = 'account';
    next;

    } elsif ($CGIargs{q} eq 'do_admin_purgeacct') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    if (!defined($CGIargs{useracct})) {
        write_XHTML_prologue($fh, $homeBase, "Invalid Access Request", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Invalid Access Request</h1>

<p class="justified">
You entered a request to purge a user account's logs, but did not
specify which account you wished to purge.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=acctmgr&amp;s=$session->{session_id}$tzOff">Return to account manager</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        exit(0);
    }

    
    if ($CGIargs{HDiet_password} ne $ui->{password}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Password Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Password Required</h1>

<p class="justified">
This operation requires confirmation by entering your password.  You
either failed to enter a password, or the password you entered is
incorrect.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    write_XHTML_prologue($fh, $homeBase, "Delete User Account", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    my $qun = quoteHTML($CGIargs{useracct});
    my $aufn = $user_file_name;     # Save administrator's user file name
    $user_file_name = quoteUserName($CGIargs{useracct});

    if (!(-d "/server/pub/hackdiet/Users/$user_file_name")) {
        print $fh <<"EOD";
<h3>There is no user account named <b>$qun</b>.</h3>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=acctmgr&amp;s=$session->{session_id}$tzOff">Return to account manager</a></h4>
EOD
    } elsif (is_user_session_open($CGIargs{useracct})) {
       print $fh <<"EOD";
<h3>User <b>$qun</b> has an active session.  You must terminate
it before the database can be purged.</h3>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=sessmgr&amp;s=$session->{session_id}$tzOff">Go to session manager</a></h4>
<h4 class="nav"><a href="/cgi-bin/HackDiet?q=acctmgr&amp;s=$session->{session_id}$tzOff">Return to account manager</a></h4>
EOD
    } else {
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Administrator purge logs: cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        my $di = HDiet::user->new();
        $di->load(\*FU);
        close(FU);

        my @months = $di->enumerateMonths();
        my $nmonths = $#months + 1;
        my $mont = 'month' . (($nmonths != 1) ? 's' : '');

        
    my $tfn = timeXML(time());
    $tfn =~ s/:/./g;            # Avoid idiot tar treating time as hostname
    if ("/server/pub/hackdiet/Backups" ne '') {
        do_command("( cd /server/pub/hackdiet/Backups; tar cfj ${user_file_name}_" .
            $tfn . ".bz2 -C ../Users $user_file_name )");
        clusterCopy("/server/pub/hackdiet/Backups/${user_file_name}_$tfn.bz2");
    }


        for my $m (@months) {
            unlink("/server/pub/hackdiet/Users/$user_file_name/$m.hdb") ||
               die("Cannot delete log file /server/pub/hackdiet/Users/$user_file_name/$m.hdb");
            clusterDelete("/server/pub/hackdiet/Users/$user_file_name/$m.hdb");
#print($fh "<pre>unlink /server/pub/hackdiet/Users/$user_file_name/$m.hdb</pre>\n");
        }

        append_history($user_file_name, 14, $nmonths);

        print $fh <<"EOD";
<h1 class="c">Logs Purged</h1>

<p class="justified">
Purged all $nmonths $mont of logs from user account <b>$qun</b>.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=acctmgr&amp;s=$session->{session_id}$tzOff">Return to account manager</a></h4>
EOD
    }
    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'do_admin_delacct') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    if (!defined($CGIargs{useracct})) {
        write_XHTML_prologue($fh, $homeBase, "Invalid Access Request", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Invalid Access Request</h1>

<p class="justified">
You entered a request to delete a user account, but did not specify which
account you wished to delete.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=acctmgr&amp;s=$session->{session_id}$tzOff">Return to account manager</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        exit(0);
    }

    
    if ($CGIargs{HDiet_password} ne $ui->{password}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Password Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Password Required</h1>

<p class="justified">
This operation requires confirmation by entering your password.  You
either failed to enter a password, or the password you entered is
incorrect.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    write_XHTML_prologue($fh, $homeBase, "Delete User Account", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    my $qun = quoteHTML($CGIargs{useracct});
    my $aufn = $user_file_name;     # Save administrator's user file name
    $user_file_name = quoteUserName($CGIargs{useracct});

    if (!(-d "/server/pub/hackdiet/Users/$user_file_name")) {
        print $fh <<"EOD";
<h3>There is no user account named <b>$qun</b>.</h3>
EOD
    } elsif (is_user_session_open($CGIargs{useracct})) {
        print $fh <<"EOD";
<h3>User <b>$qun</b> has an active session.  You must terminate
it before the account can be deleted.</h3>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=sessmgr&amp;s=$session->{session_id}$tzOff">Go to session manager</a></h4>
<h4 class="nav"><a href="/cgi-bin/HackDiet?q=acctmgr&amp;s=$session->{session_id}$tzOff">Return to account manager</a></h4>
EOD
    } else {
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Administrator delete account: cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        my $di = HDiet::user->new();
        $di->load(\*FU);
        close(FU);
        my @months = $di->enumerateMonths();
        my $nmonths = $#months + 1;
        my $mont = 'month' . (($nmonths != 1) ? 's' : '');

        if ($nmonths > 0) {
            print $fh <<"EOD";
<h3>User <b>$qun</b> has $nmonths $mont of logs in the database.
Before you can delete this account, you must first purge the logs from
the database.  Return here after the logs have been purged.</h3>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=acctmgr&amp;s=$session->{session_id}$tzOff">Return to account manager</a></h4>
EOD
        } else {
            
    my $tfn = timeXML(time());
    $tfn =~ s/:/./g;            # Avoid idiot tar treating time as hostname
    if ("/server/pub/hackdiet/Backups" ne '') {
        do_command("( cd /server/pub/hackdiet/Backups; tar cfj ${user_file_name}_" .
            $tfn . ".bz2 -C ../Users $user_file_name )");
        clusterCopy("/server/pub/hackdiet/Backups/${user_file_name}_$tfn.bz2");
    }

            do_command("rm -rf /server/pub/hackdiet/Users/$user_file_name");
            clusterRecursiveDelete("/server/pub/hackdiet/Users/$user_file_name");

            print $fh <<"EOD";
<h1 class="c">Account Deleted</h1>

<p class="justified">
User account <b>$qun</b> has been deleted.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=acctmgr&amp;s=$session->{session_id}$tzOff">Return to account manager</a></h4>
EOD
        }
    }
    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'sessmgr') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    write_XHTML_prologue($fh, $homeBase, "Session Manager", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    
    my %sessions;

    opendir(CD, "/server/pub/hackdiet/Sessions") ||
        die("Cannot open directory /server/pub/hackdiet/Sessions");
    for my $f (grep(/\w+\.hds/, readdir(CD))) {
        open(FU, "<:utf8", "/server/pub/hackdiet/Sessions/$f") ||
            die("Cannot open session /server/pub/hackdiet/Sessions/$f");
        my $session = HDiet::session->new();
        $session->load(\*FU);
        close(FU);
        $sessions{$session->{login_name}} = $session->{session_id};
    }
    closedir(CD);


    print $fh <<"EOD";
<h1 class="c">Session Manager</h1>

<form id="Hdiet_sessmgr" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>

<table border="border" class="mlog">
<tr>
    <th>Sel</th>
    <th>User</th>
    <th>Session Start</th>
    <th>Administering</th>
    <th>Browsing</th>
    <th>R/O</th>
    <th>Handheld</th>
    <th>Cookie</th>
</tr>
EOD

    
    for my $f (sort({ lc($a) cmp lc($b)} keys(%sessions))) {
        open(FU, "<:utf8", "/server/pub/hackdiet/Sessions/$sessions{$f}.hds") ||
            die("Cannot open session /server/pub/hackdiet/Sessions/$sessions{$f}.hds");
        my $session = HDiet::session->new();
        $session->load(\*FU);
        close(FU);
        my $qun = quoteHTML($f);
        my $alink = quoteHTML($sessions{$f});
        my @sopen = gmtime($session->{login_time});
        my $acr = sprintf("%04d-%02d-%02d %02d:%02d", $sopen[5] + 1900, $sopen[4] + 1, $sopen[3], $sopen[2], $sopen[1]);
        my $qef = quoteHTML($session->{effective_name});
        my $qbr = quoteHTML($session->{browse_name});
        my $rocheck = $session->{read_only} ? '&#10004;' : '';
        my $hhcheck = $session->{handheld} ? '&#10004;' : '';
        my $cookiecheck = $session->{cookie} ? '&#10004;' : '';

        print $fh <<"EOD";
<tr>
    <td><input type="radio" name="sessionid" value="$alink" /></td>
    <td>$qun</td>
    <td>$acr</td>
    <td>$qef</td>
    <td>$qbr</td>
    <td class="centred">$rocheck</td>
    <td class="centred">$hhcheck</td>
    <td class="centred">$cookiecheck</td>
</tr>
EOD
    }


    print $fh <<"EOD";
</table>

<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=do_admin_forceclose" value=" Terminate " />
</p>

<p class="mlog_buttons">
Administrator password:
    <input type="password" name="HDiet_password" size="20"
               maxlength="4096" value="" />
</p>

</form>
EOD
    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'cookiemgr') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    write_XHTML_prologue($fh, $homeBase, "Persistent Login Manager", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    
    my %cookies;

    opendir(CD, "/server/pub/hackdiet/RememberMe") ||
        die("Cannot open directory /server/pub/hackdiet/RememberMe");
    for my $f (grep(/\w+\.hdr/, readdir(CD))) {
        open(FU, "<:utf8", "/server/pub/hackdiet/RememberMe/$f") ||
#        open(FU, "<", "/server/pub/hackdiet/RememberMe/$f") ||                #### Poison cookie search
            die("Cannot open persistent login /server/pub/hackdiet/RememberMe/$f");
        my $cookie = HDiet::cookie->new();
        $cookie->load(\*FU);
#if ($cookie->{login_name} =~ m/^[ -~]*$/) { next; }                     #### Poison cookie search
        close(FU);
        $cookies{$cookie->{cookie_id}} = $cookie;
    }
    closedir(CD);


    print $fh <<"EOD";
<h1 class="c">Persistent Login Manager</h1>

<form id="Hdiet_cookiemgr" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>

<table border="border" class="mlog">
<tr>
    <th>Sel</th>
    <th>User</th>
    <th>Token</th>
    <th>Created</th>
    <th>Expiration</th>
</tr>
EOD

    

    for my $f (sort({ lc($cookies{$a}->{login_name}) cmp lc($cookies{$b}->{login_name})} keys(%cookies))) {
        my $cook = $cookies{$f};
        my $qtok = quoteHTML($f);
        my $qun = quoteHTML($cook->{login_name});
        my @sopen = gmtime($cook->{login_time});
        my $acr = sprintf("%04d-%02d-%02d %02d:%02d", $sopen[5] + 1900, $sopen[4] + 1, $sopen[3], $sopen[2], $sopen[1]);
        @sopen = gmtime($cook->{expiry_time});
        my $aex = sprintf("%04d-%02d-%02d %02d:%02d", $sopen[5] + 1900, $sopen[4] + 1, $sopen[3], $sopen[2], $sopen[1]);

        print $fh <<"EOD";
<tr>
    <td><input type="radio" name="cookieid" value="$qtok" /></td>
    <td>$qun</td>
    <td class="monospace">$qtok</td>
    <td>$acr</td>
    <td>$aex</td>
</tr>
EOD
    }


    print $fh <<"EOD";
</table>

<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=do_admin_delcookie" value=" Delete " />
&nbsp;
<input type="submit" name="q=cookiemgr" value=" Update " />
</p>

<p class="mlog_buttons">
Administrator password:
    <input type="password" name="HDiet_password" size="20"
               maxlength="4096" value="" />
</p>

</form>
EOD
    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'do_admin_delcookie') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    
    if (!defined($CGIargs{cookieid})) {
        write_XHTML_prologue($fh, $homeBase, "No Persistent Login Selected", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">No Persistent Login Selected</h1>

<p class="justified">
You requested to delete a persistent login, but failed to specify which
login you wish to terminate.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        exit(0);
    }


    
    my %cookies;

    opendir(CD, "/server/pub/hackdiet/RememberMe") ||
        die("Cannot open directory /server/pub/hackdiet/RememberMe");
    for my $f (grep(/\w+\.hdr/, readdir(CD))) {
        open(FU, "<:utf8", "/server/pub/hackdiet/RememberMe/$f") ||
#        open(FU, "<", "/server/pub/hackdiet/RememberMe/$f") ||                #### Poison cookie search
            die("Cannot open persistent login /server/pub/hackdiet/RememberMe/$f");
        my $cookie = HDiet::cookie->new();
        $cookie->load(\*FU);
#if ($cookie->{login_name} =~ m/^[ -~]*$/) { next; }                     #### Poison cookie search
        close(FU);
        $cookies{$cookie->{cookie_id}} = $cookie;
    }
    closedir(CD);


    if (defined($cookies{$CGIargs{cookieid}})) {
        my $cook = $cookies{$CGIargs{cookieid}};

        
    if ($CGIargs{HDiet_password} ne $ui->{password}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Password Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Password Required</h1>

<p class="justified">
This operation requires confirmation by entering your password.  You
either failed to enter a password, or the password you entered is
incorrect.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


        my $qun = quoteUserName($cook->{login_name});

        if (-f "/server/pub/hackdiet/RememberMe/$CGIargs{cookieid}.hdr") {
            unlink("/server/pub/hackdiet/RememberMe/$CGIargs{cookieid}.hdr");
            clusterDelete("/server/pub/hackdiet/RememberMe/$CGIargs{cookieid}.hdr");
        }

        append_history($user_file_name, 17, "$qun,$cook->{cookie_id}");
    } else {
print(STDERR "Bogus delete cookie request for $CGIargs{cookieid}\n");
    }

    $CGIargs{q} = 'cookiemgr';
    undef($CGIargs{cookieid});
    undef($CGIargs{password});
    next;

    } elsif ($CGIargs{q} eq 'globalstats') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    write_XHTML_prologue($fh, $homeBase, "Global Statistics", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<h1 class="c">Global Statistics</h1>

<form id="Hdiet_globalstats" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>

EOD

    my $hndays = 30;            # Number of days to analyse
    my $mincov = 80;            # Minimum coverage in percent to rank gain/loss

    
    my (@acchist, @pacchist);
    my ($acctotal, $pacctotal, $badgetotal) = (0, 0, 0);
    my (@ttrend, @pttrend);
    my (@ntrend, @nptrend);
    my ($minslope, $maxslope) = (1E100, -1E100);
    my ($pminslope, $pmaxslope) = (1E100, -1E100);
    my ($minslopeuser, $maxslopeuser, $pminslopeuser, $pmaxslopeuser);
    my ($minslopecov, $maxslopecov, $pminslopecov, $pmaxslopecov);
    my $jdnow = unix_time_to_jd(time());
    my ($enowy, $enowm, $enowd) = jd_to_gregorian($jdnow);
    $jdnow = gregorian_to_jd($enowy, $enowm, $enowd);
    my $jdthen = $jdnow - ($hndays + 1);
    my ($lastuser, $lastpubname) = ('', '');
    my $lastacc = -1;
    my $totuser = 0;
    my $agg = HDiet::Aggregator->new(\&receive_aggregated_statistics_records, $ui->{display_unit});
    my ($naccts, $npaccts) = $agg->retrieve($jdthen, $jdnow, 0);
    my %lu = ( "login_name", $lastuser . "xxx" );
    receive_aggregated_statistics_records(\%lu, $jdnow, undef);


    
    my ($cumaccts, $pcumaccts) = (0, 0);
    for (my $i = 0; $i <= $hndays; $i++) {
        $acchist[$i] = 0 if !defined($acchist[$i]);
        $pacchist[$i] = 0 if !defined($pacchist[$i]);
        $cumaccts += $acchist[$i];
        $pcumaccts += $pacchist[$i];
    }
    my ($inacccts, $pinaccts) = ($naccts - $cumaccts, $npaccts - $pcumaccts);

    print $fh <<"EOD";
<h2>Open Accounts</h2>

<table class="global_stats">
    <tr>
        <th class="v"></th>
        <th>All</th>
        <th>Public</th>
    </tr>

    <tr>
        <th class="l">Active</th>
        <td>$cumaccts</td>
        <td>$pcumaccts</td>
    </tr>

    <tr>
        <th class="l">Inactive</th>
        <td>$inacccts</td>
        <td>$pinaccts</td>
    </tr>

    <tr>
        <th class="l">Total</th>
        <td>$naccts</td>
        <td>$npaccts</td>
    </tr>
</table>

<p>
&ldquo;Active&rdquo; accounts are those with a weight log
entry in the last $hndays days.  A total of $badgetotal accounts
have badge generation enabled.
</p>
EOD


    
    my $balunits = HDiet::monthlog::ENERGY_ABBREVIATIONS->[$ui->{energy_unit}] . "/day";
    my $wunits = HDiet::monthlog::DELTA_WEIGHT_ABBREVIATIONS->[$ui->{display_unit}] . "/week";

    my $fitter = HDiet::trendfit->new();
    my $pfitter = HDiet::trendfit->new();
    for (my $i = 1; $i <= $hndays; $i++) {
        $fitter->addPoint($ttrend[$i] / $ntrend[$i]);
        $pfitter->addPoint($pttrend[$i] / $nptrend[$i]);
    }
    my $ttslope = $fitter->fitSlope();
    my $pttslope = $pfitter->fitSlope();

    my $meanslopeweek = gs_snum(sprintf("%.2f", $ttslope * 7));
    my $meanslopebal = gs_snum(sprintf("%.0f ", $ttslope *
                (HDiet::monthlog::CALORIES_PER_WEIGHT_UNIT->[$ui->{display_unit}] /
                 HDiet::monthlog::CALORIES_PER_ENERGY_UNIT->[$ui->{energy_unit}])));
    my $pmeanslopeweek = gs_snum(sprintf("%.2f", $pttslope * 7));
    my $pmeanslopebal = gs_snum(sprintf("%.0f ", $pttslope *
                (HDiet::monthlog::CALORIES_PER_WEIGHT_UNIT->[$ui->{display_unit}] /
                 HDiet::monthlog::CALORIES_PER_ENERGY_UNIT->[$ui->{energy_unit}])));

    print $fh <<"EOD";
<h2>Mean Gain/Loss</h2>

<table class="global_stats">
    <tr>
        <th colspan="2" class="blr">All Accounts</th>
        <th colspan="2" class="blr">Public Accounts</th>
    </tr>

    <tr>
        <th>$balunits</th>
        <th>$wunits</th>
        <th class="bl">$balunits</th>
        <th>$wunits</th>
    </tr>

    <tr>
        <td>$meanslopebal</td>
        <td>$meanslopeweek</td>
        <td>$pmeanslopebal</td>
        <td>$pmeanslopeweek</td>
    </tr>
</table>

<p>
Only accounts with weight entries in each month in the last
$hndays days are included.
</p>
EOD


    
    my $minslopeweek = gs_snum(sprintf("%.2f", $minslope * 7));
    my $minslopebal = gs_snum(sprintf("%.0f ", $minslope *
                (HDiet::monthlog::CALORIES_PER_WEIGHT_UNIT->[$ui->{display_unit}] /
                 HDiet::monthlog::CALORIES_PER_ENERGY_UNIT->[$ui->{energy_unit}])));
    my $qminslopeuser = quoteHTML($minslopeuser);

    my $pminslopeweek = gs_snum(sprintf("%.2f", $pminslope * 7));
    my $pminslopebal = gs_snum(sprintf("%.0f ", $pminslope *
                (HDiet::monthlog::CALORIES_PER_WEIGHT_UNIT->[$ui->{display_unit}] /
                 HDiet::monthlog::CALORIES_PER_ENERGY_UNIT->[$ui->{energy_unit}])));
    my $qpminslopeuser = quoteHTML($pminslopeuser);

    my $maxslopeweek = gs_snum(sprintf("%.2f", $maxslope * 7));
    my $maxslopebal = gs_snum(sprintf("%.0f ", $maxslope *
                (HDiet::monthlog::CALORIES_PER_WEIGHT_UNIT->[$ui->{display_unit}] /
                 HDiet::monthlog::CALORIES_PER_ENERGY_UNIT->[$ui->{energy_unit}])));
    my $qmaxslopeuser = quoteHTML($maxslopeuser);

    my $pmaxslopeweek = gs_snum(sprintf("%.2f", $pmaxslope * 7));
    my $pmaxslopebal = gs_snum(sprintf("%.0f ", $pmaxslope *
                (HDiet::monthlog::CALORIES_PER_WEIGHT_UNIT->[$ui->{display_unit}] /
                 HDiet::monthlog::CALORIES_PER_ENERGY_UNIT->[$ui->{energy_unit}])));
    my $qpmaxslopeuser = quoteHTML($pmaxslopeuser);

    sub gs_snum {
        my ($v) = @_;
        $v =~ s/\-/&minus;/;
        $v =~ s/^(\d)/\+$1/;
        return $v;
    }

    
    print $fh <<"EOD";
<h2>Gain and Loss Extrema</h2>

<table class="global_stats">
    <tr>
        <th class="v"></th>
        <th colspan="3" class="blr">All Accounts</th>
        <th colspan="3" class="blr">Public Accounts</th>
    </tr>

    <tr>
        <th class="v"></th>
        <th class="bl">Name</th>
        <th>$balunits</th>
        <th>$wunits</th>
        <th class="bl">Name</th>
        <th>$balunits</th>
        <th>$wunits</th>
    </tr>

    <tr>
        <th class="l">Fastest loss</th>
        <td class="c">$qminslopeuser</td>
        <td>$minslopebal</td>
        <td>$minslopeweek</td>
        <td class="c">$qpminslopeuser</td>
        <td>$pminslopebal</td>
        <td>$pminslopeweek</td>
    </tr>


    <tr>
        <th class="l">Fastest gain</th>
        <td class="c">$qmaxslopeuser</td>
        <td>$maxslopebal</td>
        <td>$maxslopeweek</td>
        <td class="c">$qpmaxslopeuser</td>
        <td>$pmaxslopebal</td>
        <td>$pmaxslopeweek</td>
    </tr>
</table>

<p>
Only accounts with $mincov% or more weight entries logged are included.
</p>
EOD


    
    print $fh <<"EOD";
<h2>Log Update Frequency</h2>

<table class="global_stats">
    <tr>
        <th class="v"></th>
        <th colspan="3" class="blr">All Accounts</th>
        <th colspan="3" class="blr">Public Accounts</th>
    </tr>

    <tr>
        <th class="v">Days</th>
        <th class="bl">Accounts</th>
        <th>Percent</th>
        <th>Cumulative</th>

        <th class="bl">Accounts</th>
        <th>Percent</th>
        <th>Cumulative</th>
    </tr>
EOD

    my ($cum, $pcum) = (0, 0);
    for (my $i = 0; $i <= $hndays; $i++) {
        $acchist[$i] = 0 if !defined($acchist[$i]);
        $pacchist[$i] = 0 if !defined($pacchist[$i]);
        $cum += $acchist[$i];
        $pcum += $pacchist[$i];
        my $si = ($i < 1) ? "&lt;1" : (($i >= $hndays) ? "$hndays+" : $i);
        printf($fh "    <tr><td>%s</td> <td>%d</td> <td>%d%%</td> <td>%d%%</td> " .
                   "<td>%d</td> <td>%d%%</td> <td>%d%%</td></tr>\n",
            $si,
            $acchist[$i], int((($acchist[$i] / $acctotal) * 100) + 0.5),
                int((($cum / $acctotal) * 100) + 0.5),
            $pacchist[$i], int((($pacchist[$i] / $pacctotal) * 100) + 0.5),
                int((($pcum / $pacctotal) * 100) + 0.5));
    }
    printf($fh "    <tr><td>Total</td> <td>%d</td> <td>100%%</td> <td>100%%</td> " .
               "<td>%d</td> <td>100%%</td> <td>100%%</td></tr>\n",
        $acctotal, $pacctotal);

    print $fh <<"EOD";
</table>
</form>
EOD


    write_XHTML_epilogue($fh, $homeBase);

    
    my $acctrend = 0;
    my $uljd;
    my @utrend;
    my $weightdays = 0;

    sub receive_aggregated_statistics_records {
        my ($user, $jd, $weight, $trend, $rung, $flag, $comment) = @_;

#if ($user->{login_name} eq 'astuemky') {
#    print(STDERR "User $user->{login_name} $jd ", jd_to_RFC_3339_date($jd),
#       " W = $weight  T = $trend  R = $rung  F = $flag  C = $comment\n");
#}
        if (($user->{login_name} ne $lastuser) &&
                defined($weight)) {
            if (($lastuser ne '') && ($lastacc >= 0)) {
                if ($lastacc > $hndays) {
                    $lastacc = $hndays;
                }
                $acchist[$lastacc]++;
                $acctotal++;
                if ($user->{public}) {
                    $pacchist[$lastacc]++;
                    $pacctotal++;
                }

                $badgetotal++ if ((defined($user->{badge_trend})) &&
                    ($user->{badge_trend} != 0));

                if ($acctrend && ($uljd == $jdnow)) {
                    
#print(STDERR "$lastuser trend complete.\n");
    my $ufitter = HDiet::trendfit->new();
    for (my $i = 0; $i <= $#utrend; $i++) {
        $ufitter->addPoint($utrend[$i]);
#print(STDERR "$lastuser $user->{login_name} trend[$i] undefined.\n") if !defined($utrend[$i]);
        $ttrend[$i] += $utrend[$i];
        $ntrend[$i]++;
#print(STDERR "$lastuser trend $i: $ttrend[$i]  $ntrend[$i]\n");
        if ($user->{public}) {
            $pttrend[$i] += $utrend[$i];
            $nptrend[$i]++;
        }
    }


#if (($#utrend + 1) == 0) {
#    my $sjd = jd_to_RFC_3339_date($jd);
#    print(STDERR "Utrend zero for user $user->{login_name} at JD $jd, $sjd  Lastuser = $lastuser\n");
#}
                    my $coverage = int((($weightdays / ($#utrend + 1)) * 100) + 0.5);

                    
    if ($coverage >= $mincov) {
        my $uslope = $ufitter->fitSlope();
        if (($uslope < 0) && ($uslope < $minslope)) {
            $minslope = $uslope;
            $minslopeuser = $lastuser;
            $minslopecov = $coverage;
        }
        if (($uslope > 0) && ($uslope > $maxslope)) {
            $maxslope = $uslope;
            $maxslopeuser = $lastuser;
            $maxslopecov = $coverage;
        }

        if ($lastpubname ne '') {
            if (($uslope < 0) && ($uslope < $pminslope)) {
                $pminslope = $uslope;
                $pminslopeuser = $lastpubname;
                $pminslopecov = $coverage;
            }
            if (($uslope > 0) && ($uslope > $pmaxslope)) {
                $pmaxslope = $uslope;
                $pmaxslopeuser = $lastpubname;
                $pmaxslopecov = $coverage;
            }
        }
    }

                }
            }

            $lastuser = $user->{login_name};
            $lastpubname = $user->{public} ? $user->{public_name} : '';
            $weightdays = 0;
            $totuser++;

            $acctrend = 0;
            if ($jd == $jdthen) {
                $acctrend = 1;
                @utrend = ( );
            }
        }
        if ($acctrend && defined($trend)) {
            push(@utrend, $trend);
        }
        $uljd = $jd;
        if (defined($weight)) {
            $lastacc = int($jdnow - $jd);
            $weightdays++;
        }
    }


    } elsif ($CGIargs{q} eq 'synthdata') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    if (!$assumed_identity) {
        
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }

    }

    write_XHTML_prologue($fh, $homeBase, "Synthetic Data Generator", undef, $session->{handheld});
    generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
    

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


    print $fh <<"EOD";
<h1 class="c">Synthetic Data Generator</h1>

<form id="Hdiet_synthdata" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>

EOD

    my $npert = 5;

    
    if (defined($CGIargs{from_y}) && ($CGIargs{from_y} ne '')) {
        my ($from_y, $from_m, $from_d) = ($CGIargs{from_y}, $CGIargs{from_m}, $CGIargs{from_d});
        my ($to_y, $to_m, $to_d) = ($CGIargs{to_y}, $CGIargs{to_m}, $CGIargs{to_d});
        my ($field, $fillfrac, $start_value, $end_value) =
            ($CGIargs{field}, $CGIargs{fill_frac}, $CGIargs{start_value}, $CGIargs{end_value});
        my $format = ($field eq 'weight') ? '%.1f' : '%.0f';

        $start_value =~ s/,/./;
        $end_value =~ s/,/./;

        my @pertarg;

        for (my $n = 1; $n <= $npert; $n++) {
            if (($CGIargs{"pf_$n"} ne '') && $CGIargs{"pm_$n"}) {
                $CGIargs{"pm_$n"} =~ s/,/./;
                $CGIargs{"po_$n"} =~ s/,/./;
                $CGIargs{"pp_$n"} =~ s/,/./;
                push(@pertarg, $CGIargs{"pf_$n"},  $CGIargs{"pm_$n"});
                if ($CGIargs{"pf_$n"} eq 'sine') {
                    push(@pertarg, $CGIargs{"po_$n"},  $CGIargs{"pp_$n"});
                }
            }
        }

        my $hist = HDiet::history->new($ui, $user_file_name);

        if ($field eq 'flag') {
            $hist->syntheticData(
                    sprintf("%04d-%02d-%02d", $from_y, $from_m, $from_d),
                    sprintf("%04d-%02d-%02d", $to_y, $to_m, $to_d),
                    $field, 1, 0, 0, '%d');
            $start_value = $end_value = 1;
            $format = '%d';
            @pertarg = ( );
        }

        $hist->syntheticData(
                sprintf("%04d-%02d-%02d", $from_y, $from_m, $from_d),
                sprintf("%04d-%02d-%02d", $to_y, $to_m, $to_d),
                $field, $fillfrac / 100, $start_value, $end_value, $format,
                @pertarg);

        propagate_trend($ui, sprintf("%04d-%02d", $from_y, $from_m), 0);
    }


    
    print $fh <<"EOD";
<table class="syndata">
EOD

    
    my ($ysel, $msel, $dsel) = ("") x 3;
    my (@fm_selected, @fd_selected);

    for (my $i = 1; $i <= 31; $i++) {
        $fd_selected[$i] = '';
    }
    for (my $i = 1; $i <= 12; $i++) {
        $fm_selected[$i] = '';
    }

    print $fh <<"EOD";
<tr>
    <th class="l">Start date:</th>
    <td colspan="4">
    <input type="text" name="from_y" value="" size="5" maxlength="5" />
    <select name="from_m" id="from_m"$msel>
EOD

    my $mid = "fm_";
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>
EOD

    print $fh <<"EOD";
    <select name="from_d" id="from_d"$dsel>
EOD

    my $did = "fd_";
    
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


    print $fh <<"EOD";
    </select>
EOD

    print $fh <<"EOD";
    </td>
</tr>
EOD

    
    print $fh <<"EOD";
<tr>
    <th class="l">End date:</th>
    <td colspan="4">
    <input type="text" name="to_y" value="" size="5" maxlength="5" />
    <select name="to_m" id="to_m"$msel>
EOD

    $mid = "tm_";
    
    for (my $i = 1; $i <= $#monthNames; $i++) {
        print $fh <<"EOD";
        <option id="$mid$i" value="$i"$fm_selected[$i]>$monthNames[$i]</option>
EOD
    }


    print $fh <<"EOD";
    </select>
EOD

    print $fh <<"EOD";
    <select name="to_d" id="to_d"$dsel>
EOD

    $did = "td_";
    
    for (my $i = 1; $i <= 31; $i++) {
        print $fh <<"EOD";
        <option id="$did$i"$fd_selected[$i]>$i</option>
EOD
    }


    print $fh <<"EOD";
    </select>
EOD

    print $fh <<"EOD";
    </td>
</tr>
EOD


    
     print $fh <<"EOD";
<tr>
    <th class="l">Field:</th>
    <td colspan="4">
    <select name="field">
        <option value="weight">Weight</option>
        <option value="rung">Exercise rung</option>
        <option value="flag">Flag</option>
    </select>
    </td>
</tr>
EOD


    print $fh <<"EOD";
<tr>
    <th class="l">Percent to fill:</th>
    <td colspan="4">
    <input type="text" name="fill_frac" value="100" size="4" maxlength="4" />%
    </td>
</tr>
EOD

    
    print $fh <<"EOD";
<tr>
    <th class="l">Start value:</th>
    <td colspan="4">
    <input type="text" name="start_value" value="" size="6" maxlength="6" />
    </td>
</tr>
EOD

    print $fh <<"EOD";
<tr>
    <th class="l">End value:</th>
    <td colspan="4">
    <input type="text" name="end_value" value="" size="6" maxlength="6" />
    </td>
</tr>
EOD


    
    print $fh <<"EOD";
<tr>
    <td colspan="1"></td>
    <th>Function</th>
    <th>Range</th>
    <th>Period</th>
    <th>Phase</th>
</tr>
EOD
    for (my $p = 1; $p <= $npert; $p++) {
        print $fh <<"EOD";
<tr>
    <th class="l">Perturbation $p:</th>
    <td>
    <select name="pf_$p">
        <option value=""></option>
        <option value="uniform">Uniform</option>
        <option value="gaussian">Gaussian</option>
        <option value="sine">Sinusoidal</option>
    </select>
    </td>
    <td><input type="text" name="pm_$p" value="" size="5" maxlength="5" /></td>
    <td><input type="text" name="po_$p" value="" size="5" maxlength="5" /></td>
    <td><input type="text" name="pp_$p" value="" size="5" maxlength="5" /></td>
</tr>
EOD
    }


    print $fh <<"EOD";
<tr>
<td colspan="5" class="c">
    <input type="hidden" name="s" value="$session->{session_id}" />
    <input type="submit" name="q=synthdata" value=" Generate " />
    &nbsp;
    <input type="reset" value=" Reset " />
    &nbsp;
    <input type="submit" name="q=gonque" value=" Cancel " />
</td>
</tr>
</table>
EOD


    print $fh <<"EOD";
</form>
EOD

    write_XHTML_epilogue($fh, $homeBase);

    } elsif ($CGIargs{q} eq 'do_admin_forceclose') {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

    
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


    
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    
    if (!defined($CGIargs{sessionid})) {
        write_XHTML_prologue($fh, $homeBase, "No Session Selected", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">No Session Selected</h1>

<p class="justified">
You requested to terminate a selection, but failed to specify which
session you wish to terminate.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        exit(0);
    }


    
    if (($CGIargs{sessionid} !~ m/^[0-9FGJKQW]{40}$/) ||
        (!-f "/server/pub/hackdiet/Sessions/$CGIargs{sessionid}.hds")) {
        write_XHTML_prologue($fh, $homeBase, "No Such Session", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">No Such Session</h1>

<p class="justified">
You requested to terminate session ID <tt>$CGIargs{sessionid}</tt>, but
no such session is open.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);
        exit(0);
    }


    
    my %sessions;

    opendir(CD, "/server/pub/hackdiet/Sessions") ||
        die("Cannot open directory /server/pub/hackdiet/Sessions");
    for my $f (grep(/\w+\.hds/, readdir(CD))) {
        open(FU, "<:utf8", "/server/pub/hackdiet/Sessions/$f") ||
            die("Cannot open session /server/pub/hackdiet/Sessions/$f");
        my $session = HDiet::session->new();
        $session->load(\*FU);
        close(FU);
        $sessions{$session->{login_name}} = $session->{session_id};
    }
    closedir(CD);


    my $user = '';
    for my $f (sort(keys(%sessions))) {
        if ($sessions{$f} eq $CGIargs{sessionid}) {
            $user = $f;
            last;
        }
    }

    
    if ($CGIargs{HDiet_password} ne $ui->{password}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Password Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Password Required</h1>

<p class="justified">
This operation requires confirmation by entering your password.  You
either failed to enter a password, or the password you entered is
incorrect.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


    my $qun = quoteHTML($user);
    my $aufn = $user_file_name;     # Save administrator's user file name
    $user_file_name = quoteUserName($user);

    
    if ((!$readOnly) && (-f "/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda")
        && open(FS, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda")) {
        my $asn = load_active_session(\*FS);
        close(FS);
        unlink("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
        clusterDelete("/server/pub/hackdiet/Users/$user_file_name/ActiveSession.hda");
        unlink("/server/pub/hackdiet/Sessions/$asn.hds");
        clusterDelete("/server/pub/hackdiet/Sessions/$asn.hds");
        append_history($user_file_name, 3);
    }


    #   On the off possibility that there is a discrepancy between the
    #   session pointer in the Sessions directory and the back pointer
    #   in the Users directory, if the session close above did not
    #   delete the open session file, manually delete it now.

    if (-f "/server/pub/hackdiet/Sessions/$CGIargs{sessionid}.hds") {
        unlink("/server/pub/hackdiet/Sessions/$CGIargs{sessionid}.hds");
        clusterDelete("/server/pub/hackdiet/Sessions/$CGIargs{sessionid}.hds");
print(STDERR "Deleting bogus open session $CGIargs{sessionid} for user $user_file_name\n");
    }

    append_history($aufn, 13, $user_file_name);

    $CGIargs{q} = 'sessmgr';
    undef($CGIargs{sessionid});
    undef($CGIargs{password});
    next;

    } elsif (0 && ($CGIargs{q} eq 'invite')) {
        
    if (0) {
        
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

        
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


        
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


        write_XHTML_prologue($fh, $homeBase, "Request Invitation Codes", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Request Invitation Codes</h1>

<form id="Hdiet_invite" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>

<p class="mlog_buttons">
Number of invitations to generate:
<input type="text" name="ninvite" size="4" maxlength="4" value="1" />
</p>

<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=generate_invitations" value=" Generate " />
&nbsp;
<input type="reset" value=" Reset " />
</p>
</form>
EOD
        write_XHTML_epilogue($fh, $homeBase);
    }

    } elsif (0 && ($CGIargs{q} eq 'generate_invitations')) {
        
    if (0) {
        
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);

        
    open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
        die("Cannot open user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
    my $ui = HDiet::user->new();
    $ui->load(\*FU);
    close(FU);

    if ($assumed_identity) {
        if (!$ui->{administrator}) {
            die("Attempt by non-administrator $user_file_name to assume identity");
        }
        $user_name = $effective_user_name;
        $user_file_name = quoteUserName($user_name);
        open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
            die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
        $ui->load(\*FU);
        close(FU);
    } elsif ($browse_public) {
        my $pn = HDiet::pubname->new();
        if (defined($pn->findPublicName($effective_user_name))) {
            $user_name = $pn->{public_name};
            $user_file_name = quoteUserName($pn->{true_name});
            open(FU, "<:utf8", "/server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu") ||
                die("Cannot open effective user account file /server/pub/hackdiet/Users/$user_file_name/UserAccount.hdu");
            $ui->load(\*FU);
            close(FU);
        } else {
            $browse_public = 0;
        }
    }


        
    if (!$ui->{administrator}) {
        write_XHTML_prologue($fh, $homeBase, "Administrator Privilege Required", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        print $fh <<"EOD";
<h1 class="c">Administrator Privilege Required</h1>

<p class="justified">
This operation requires administrator privilege, which you do not
have.  This request from IP address $ENV{REMOTE_ADDR} has been
logged.
</p>

<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Return to account page</a></h4>
EOD
        write_XHTML_epilogue($fh, $homeBase);

        append_history($user_file_name, 11, $CGIargs{q});
        exit(0);
    }


        write_XHTML_prologue($fh, $homeBase, "Invitation Codes Generated", undef, $session->{handheld});
        generate_XHTML_navigation_bar($fh, $homeBase, $session->{session_id}, undef, undef, $browse_public, $timeZoneOffset);
        

    if ($readOnly) {
        print $fh <<"EOD";
<h3 class="browsing">Read-only access: Changes are not saved.</h3>
EOD
    }

    if ($assumed_identity) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitadm" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Administrator accessing account of $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this account" value="Exit" />
</h3>
</form>
EOD
    } elsif ($browse_public) {
        my $eu = quoteHTML($effective_user_name);
        print $fh <<"EOD";
<form id="Hdiet_quitbrowse" method="post" action="/cgi-bin/HackDiet">
<div>
<input type="hidden" name="q" value="quitbrowse" />
<input type="hidden" name="s" value="$session->{session_id}" />
</div>

<h3 class="browsing">Browsing public account $eu
&nbsp; &nbsp; &nbsp;
<input type="submit"
    title="End browsing this public account" value="Exit" />
</h3>
</form>
EOD
    }


        my $ninvite = $CGIargs{ninvite};
        $ninvite = 1 if !$ninvite;
        $ninvite = max(1, min($ninvite, 20));

        print $fh <<"EOD";
<h1 class="c">Invitation Codes Generated</h1>

<form id="Hdiet_invgen" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>
<input type="hidden" name="ninvite" value="$ninvite" />

<p class="mlog_buttons">
<textarea cols="20" rows="$ninvite" name="invitations">
EOD

        for (my $i = 0; $i < $ninvite; $i++) {
            my $pw;

            while (1) {
                #   Generate invitations until we find a unique one
                $pw = $ui->generatePassword(8,
                        "ABCDEFGHIJKLMNPQRSTUVWXYZ" .
                        "abcdefghjkmnopqrstuvwxyz" .
                        "23456789");
                if (!(-f "/server/pub/hackdiet/Invitations/$pw.hdi")) {
                    last;
                }
            }
            open(FO, ">:utf8", "/server/pub/hackdiet/Invitations/$pw.hdi") ||
                die("Cannot create invitation file /server/pub/hackdiet/Invitations/$pw.hdi");
            print(FO time() . "\n");
            close(FO);
            clusterCopy("/server/pub/hackdiet/Invitations/$pw.hdi");
            print($fh quoteHTML($pw), "\n");
        }

        print $fh <<"EOD";
</textarea>
</p>

<p class="mlog_buttons">
<input type="hidden" name="s" value="$session->{session_id}" />
<input type="submit" name="q=generate_invitations" value=" Generate More " />
&nbsp;
<input type="submit" name="q=account" value=" Done " />
</p>
</form>
EOD
        write_XHTML_epilogue($fh, $homeBase);
    }



    } else {
        
    
    $CGIargs{s} = '' if !defined($CGIargs{s});
    if ($CGIargs{s} !~ m/^[0-9FGJKQW]{40}$/) {
        die("Invalid (probably spoofed) session identifier ($CGIargs{s})");
    }
    my $session = HDiet::session->new();
    if (!open(FS, "<:utf8", "/server/pub/hackdiet/Sessions/$CGIargs{s}.hds")) {
        %CGIargs = (
            q => "relogin",
        );
        if (!$inHTML) {
            goto requeue;
        }
        next;
    }
    $session->load(\*FS);
    close(FS);
    my $user_name = $session->{login_name};
    my $real_user_name = $user_name;
    my $effective_user_name = '';
    my $assumed_identity = 0;
    my $browse_public = 0;
    $readOnly = $session->{read_only};
    if ($readOnly) {
        delete $browsing_user_requests{browsepub};
        delete $browsing_user_requests{do_public_browseacct};
    }
    if ($session->{effective_name} ne '') {
        $assumed_identity = 1;
        $effective_user_name = $session->{effective_name};
    } elsif ($session->{browse_name} ne '') {
        $browse_public = 1;
        $effective_user_name = $session->{browse_name};
        if (!$browsing_user_requests{$CGIargs{q}}) {
            my $qun = quoteUserName($real_user_name);
            my $qpn = quoteUserName($effective_user_name);
            die("Invalid \"$CGIargs{q}\" transaction attempted by $qun while browsing public account $qpn");
        }
    }
    my $user_file_name = quoteUserName($user_name);


    write_XHTML_prologue($fh, $homeBase, "Undefined Query", undef, $session->{handheld});
    print $fh <<"EOD";
<h1 class="c">Undefined query: <tt>$CGIargs{q}</tt></h1>
<h4 class="nav"><a href="/cgi-bin/HackDiet?q=account&amp;s=$session->{session_id}$tzOff">Back to account page</a></h4>
<pre>
EOD
    
    use Data::Dumper;
    print($fh Data::Dumper->Dump([\%CGIargs, \%ENV], ['*CGIargs', '*ENV']));

    print $fh <<"EOD";
</pre>
EOD
    write_XHTML_epilogue($fh, $homeBase);

    }

        exit(0);
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


