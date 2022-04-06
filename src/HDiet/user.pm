#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    use HDiet::monthlog qw();

    package HDiet::user;

    use Encode qw(encode_utf8);
    use Digest::SHA1  qw(sha1_hex);
    use Crypt::OpenSSL::AES;
    use Crypt::CBC;

    use HDiet::html;
    use HDiet::xml;
    use HDiet::Julian;
    use HDiet::Digest::Crc32;

    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT = qw( quoteUserName );
    1;

    use constant FILE_VERSION => 1;


    sub new {
        my $self = {};
        my ($invocant, $login_name) = @_;
        my $class = ref($invocant) || $invocant;

        $login_name = '' if !defined($login_name);

        bless($self, $class);

        $self->{version} = FILE_VERSION;

        #   Initialise instance variables
        $self->{login_name} = $login_name;
        $self->{password} = '';
        $self->{password_expires} = 0;
        $self->{account_created} = 0;

        $self->{first_name} = '';
        $self->{last_name} = '';
        $self->{middle_name} = '';
        $self->{e_mail} = '';
        $self->{log_unit} = HDiet::monthlog::WEIGHT_KILOGRAM;
        $self->{display_unit} = HDiet::monthlog::WEIGHT_KILOGRAM;
        $self->{energy_unit} = HDiet::monthlog::ENERGY_CALORIE;
        $self->{height} = 0;
        $self->{calc_calorie_balance} = -500;
        $self->{calc_start_weight} = 0;
        $self->{calc_goal_weight} = 0;
        $self->{calc_start_date} = 0;
        $self->{plot_diet_plan} = 0;
        $self->{current_rung} = 0;
        $self->{public} = 0;
        $self->{public_name} = '';
        $self->{public_since} = 0;
        $self->{administrator} = 0;
        $self->{read_only} = 0;
        $self->{last_modification_time} = 0;
        $self->{decimal_character} = '.';
        $self->{badge_trend} = 0;

        return $self;
    }

    sub login {
        my $self = {};
        my ($invocant, $login_name, $password) = @_;
        my $class = ref($invocant) || $invocant;

        bless($self, $class);

        return $self;
    }

    sub describe {
        my $self = shift;
        my ($outfile) = @_;

        if (!(defined $outfile)) {
            $outfile = \*STDOUT;
        }

        print($outfile "USER Version: $self->{version}\n");
        print($outfile "  Login: '$self->{login_name}'  Password: $self->{password}  " ."\n");
        print($outfile "  Password expires: " . (($self->{password_expires} == 0) ? "Never" :
            localtime($self->{password_expires})) . "\n");
        print($outfile "  First login: " . localtime($self->{account_created}) . "\n");
        print($outfile "  Name:  First '$self->{first_name}'  " .
                       "Middle '$self->{middle_name}'  " .
                       "Last '$self->{last_name}'\n");
        print($outfile "  E-mail: $self->{e_mail}\n");
        print($outfile "  Log unit: " . HDiet::monthlog::WEIGHT_UNITS->[$self->{log_unit}] .
                       "  Display unit: " . HDiet::monthlog::WEIGHT_UNITS->[$self->{display_unit}] .
                       "  Energy unit: " . HDiet::monthlog::ENERGY_UNITS->[$self->{energy_unit}] . "\n");
        print($outfile "  Height: $self->{height}  " .
                       "Log public: " . ($self->{public} ? "Yes" : "No") .
                       "  Administrator: " . ($self->{administrator} ? "Yes" : "No") .
                       "  Read only: " . ($self->{read_only} ? "Yes" : "No") . "\n");
        if ($self->{public}) {
            print($outfile "  Public name: '$self->{public_name}'  Since: " .
                localtime($self->{public_since}) . "\n");
        }
        print($outfile "  Calculator:  Balance: " . $self->{calc_calorie_balance} .
                       "  Start weight: " . $self->{calc_start_weight} .
                       "  Goal weight: " . $self->{calc_goal_weight} . "\n" .
                       "               Plot plan: " . ($self->{plot_diet_plan} ? "Yes" : "No") .
                       "  Start date: " . localtime($self->{calc_start_date}) . "\n");
        print($outfile "  Last modification time: " .
                       localtime($self->{last_modification_time}) . "\n");
        print($outfile "  Decimal character: " . $self->{decimal_character} . "\n");
        print($outfile "  Badge trend interval: $self->{badge_trend}\n");
    }

    sub save {
        my $self = shift;
        my ($outfile) = @_;

        print $outfile <<"EOD";
$self->{version}
$self->{login_name}
$self->{password}
$self->{password_expires}
$self->{account_created}
$self->{first_name}
$self->{last_name}
$self->{middle_name}
$self->{e_mail}
$self->{log_unit}
$self->{display_unit}
$self->{energy_unit}
$self->{height}
$self->{calc_calorie_balance}
$self->{calc_start_weight}
$self->{calc_goal_weight}
$self->{calc_start_date}
$self->{plot_diet_plan}
$self->{current_rung}
$self->{public}
$self->{public_name}
$self->{public_since}
$self->{administrator}
$self->{read_only}
$self->{last_modification_time}
$self->{decimal_character}
$self->{badge_trend}
EOD
    }

    sub load {
        my $self = shift;
        my ($infile) = @_;

        my $s = in($infile);

        if ($s != FILE_VERSION) {
            die("user::load: Incompatible file version $s");
        }

        $self->{login_name} = in($infile);
        $self->{password} = in($infile);
        $self->{password_expires} = in($infile);
        $self->{account_created} = in($infile);
        $self->{first_name} = in($infile);
        $self->{last_name} = in($infile);
        $self->{middle_name} = in($infile);
        $self->{e_mail} = in($infile);
        $self->{log_unit} = in($infile);
        $self->{display_unit} = in($infile);
        $self->{energy_unit} = in($infile);
        $self->{height} = in($infile);
        $self->{calc_calorie_balance} = in($infile);
        $self->{calc_start_weight} = in($infile);
        $self->{calc_goal_weight} = in($infile);
        $self->{calc_start_date} = in($infile);
        $self->{plot_diet_plan} = in($infile);
        $self->{current_rung} = in($infile);
        $self->{public} = in($infile);
        $self->{public_name} = in($infile);;
        $self->{public_since} = in($infile);;
        $self->{administrator} = in($infile);
        $self->{read_only} = in($infile);
        $self->{last_modification_time} = in($infile);
        $self->{decimal_character} = in($infile, '.');
        $self->{badge_trend} = in($infile, 0);
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
                die("user::in: Unexpected end of file");
            }
        }
        return $s;
    }


    sub login_form {
        my $self = shift;
        my ($fh, $tzOff, $handheld, $remember) = @_;

        if (!(defined $fh)) {
            $fh = \*STDOUT;
        }

        my ($login_name, $password) = (
                        quoteHTML($self->{login_name}),
                        quoteHTML($self->{password})
                     );

        my $ckhandheld = $handheld ? ' checked="checked"' : '';
        my $ckremember = $remember ? ' checked="checked"' : '';
        my $arghandheld = $handheld ? '&amp;HDiet_handheld=y' : '';
        print $fh <<"EOD";
<form id="Hdiet_login" method="post" action="/cgi-bin/HackDiet">
<div><input type="hidden" name="HDiet_tzoffset" id="tzoffset" value="unknown" /></div>


<table border="border" class="login">
<tr><th><label for="HDiet_username"><span class="accesskey">U</span>ser Name:</label></th>
    <td><input accesskey="u" type="text" name="HDiet_username" id="HDiet_username" size="60"
               tabindex="1" maxlength="4096" value="$login_name" /></td>
</tr>
<tr><th><label for="HDiet_password"><span class="accesskey">P</span>assword:</label></th>
    <td><input accesskey="p" type="password" name="HDiet_password" id="HDiet_password" size="60"
               tabindex="2" maxlength="4096" value="$password" /></td>
</tr>
</table>
<p class="mlog_buttons">
<input type="hidden" name="q" value="validate_user" />
<input type="submit" tabindex="3" name="login" value=" Sign In " />
&nbsp;
<input type="reset" value=" Reset " />
<br />
<input type="checkbox" name="HDiet_handheld" id="HDiet_handheld"
       value="y"$ckhandheld />&nbsp;<label for="HDiet_handheld">Handheld&nbsp;device</label>
&nbsp;
<input type="checkbox" name="HDiet_remember" id="HDiet_remember"
       value="y"$ckremember />&nbsp;<label for="HDiet_remember">Remember&nbsp;me</label>
<br />
<a href="/cgi-bin/HackDiet?q=pwreset$arghandheld$tzOff">Forgotten
    your password?</a>
</p>
<p class="mlog_buttons">
<input type="submit" name="new" value=" Create a New Account " />
</p>
</form>
EOD

        if ((!$handheld) && (0)) {
            print $fh <<"EOD";
<h3 class="centred">Development log now online at:<br />
<a href="http://hdonline-dev.blogspot.com/"
   rel="Target:Fourmilab_Hdonline_Devlog">http://hdonline-dev.blogspot.com/</a>
</h3>
EOD
        }
    }

    sub new_account_form {
        my $self = shift;
        my ($fh, $edit_mode) = @_;

        if (!(defined $fh)) {
            $fh = \*STDOUT;
        }

        
    my ($login_name, $first_name, $last_name, $middle_name,
        $e_mail) = (
                    quoteHTML($self->{login_name}),
                    quoteHTML($self->{first_name}),
                    quoteHTML($self->{last_name}),
                    quoteHTML($self->{middle_name}),
                    quoteHTML($self->{e_mail})
                 );

    my %wunit = (0, '', 1, '', 2, '');
    $wunit{$self->{log_unit}} = 'checked="checked"';

    my %dunit = (0, '', 1, '', 2, '');
    $dunit{$self->{display_unit}} = 'checked="checked"';

    my %eunit = (0, '', 1, '');
    $eunit{$self->{energy_unit}} = 'checked="checked"';

    my %dchar = ('.', '', ',', '');
    $dchar{$self->{decimal_character}} = 'checked="checked"';

    my ($height_cm, $height_ft, $height_in) = ('', '', '');
    if ($self->{height} > 0) {
        $height_cm = $self->localiseNumber($self->{height}, 1);
        $height_in = canonicalNumber($self->{height}, 1) / 2.54;
        $height_ft = int($height_in / 12);
        $height_in = $self->localiseNumber($height_in - ($height_ft * 12), 1);
    }


        print $fh <<"EOD";
<table border="border" class="login">

EOD
        
    if ($edit_mode) {
        my $llg = $login_name;
        if ($self->{administrator}) {
            $llg .= ' <span class="administrator">(Administrator)</span>';
        }
        print $fh <<"EOD";
<tr><th>User Name:</th>
    <td><b>$llg</b></td>
</tr>
EOD
    } else {
        print $fh <<"EOD";
<tr><th><span class="required">*</span> <label
        for="HDiet_username"><span class="accesskey">U</span>ser Name:</label></th>
    <td><input accesskey="u" type="text" name="HDiet_username" id="HDiet_username" size="60" tabindex="1"
               maxlength="4096" value="$login_name" /></td>
</tr>
EOD
    }


        if (0) {
            
    if (!$edit_mode) {
        print $fh <<"EOD";
<tr><th><span class="required">*</span> <label for="HDiet_invitation"><span
        class="accesskey">B</span>eta test invitation:</label></th>
    <td><input accesskey="B" type="text" name="HDiet_invitation" id="HDiet_invitation" size="12"  tabindex="2"
               maxlength="4096" value="" /></td>
</tr>
EOD
    }

        }

        my $ch_logunit = $edit_mode ? '' : ' onclick="set_logunit(this);"';
        my $ch_dispunit = $edit_mode ? '' : ' onclick="set_dispunit(this);"';

        print $fh <<"EOD";

<tr><th><span class="required">*</span> <label for="HDiet_password"><span
        class="accesskey">P</span>assword:</label></th>
    <td><input accesskey="p" type="password" name="HDiet_password"
               id="HDiet_password" size="48"  tabindex="2"
               onkeyup="showPasswordStrength(); checkPasswordMatch();"
               onchange="showPasswordStrength(); checkPasswordMatch();"
               maxlength="4096" value="" />
               Strength:&nbsp;<input type="text" name="HDiet_password_strength" size="2"
               maxlength="3" readonly="readonly" tabindex="0" value="0" /></td>
</tr>

<tr><th><span class="required">*</span> <label for="HDiet_rpassword"><span
        class="accesskey">R</span>etype password:</label></th>
    <td><input accesskey="r" type="password" name="HDiet_rpassword"
               id="HDiet_rpassword" size="48"  tabindex="3"
               onkeyup="checkPasswordMatch();"
               onchange="checkPasswordMatch();"
               maxlength="4096" value="" />
               Match?&nbsp;<input type="checkbox" name="HDiet_password_match"
               readonly="readonly" tabindex="0" checked="checked" /></td>
</tr>



<tr><th><span class="required">*</span> <label for="HDiet_email"><span
    class="accesskey">E</span>-mail address:
     (for lost <br /> password recovery)</label></th>
    <td><input accesskey="e" type="text" name="HDiet_email" id="HDiet_email" size="60" tabindex="4"
               maxlength="4096" value="$e_mail" /></td>
</tr>



<tr><th><label for="HDiet_namef">First name:</label></th>
    <td><input type="text" name="HDiet_namef" id="HDiet_namef" size="60" tabindex="5"
               maxlength="4096" value="$first_name" /></td>
</tr>

<tr><th><label for="HDiet_namel">Last name:</label></th>
    <td><input type="text" name="HDiet_namel" id="HDiet_namel" size="60" tabindex="6"
               maxlength="4096" value="$last_name" /></td>
</tr>

<tr><th><label for="HDiet_namem">Middle name or initial:</label></th>
    <td><input type="text" name="HDiet_namem" id="HDiet_namem" size="60" tabindex="7"
               maxlength="4096" value="$middle_name" /></td>
</tr>



<tr><th>Height:</th>
    <td>
        <input type="text" name="HDiet_height_cm" id="HDiet_height_cm" size="5" tabindex="8"
            maxlength="6" value="$height_cm" onchange="height_changed_cm();" />
                <label for="HDiet_height_cm">centimetres</label>
        &nbsp; &nbsp; <b>or</b> &nbsp; &nbsp;
        <input type="text" name="HDiet_height_ft" id="HDiet_height_ft" size="2" tabindex="9"
            maxlength="2" value="$height_ft" onchange="height_changed_ft();" />
                <label for="HDiet_height_ft">feet</label>
        <input type="text" name="HDiet_height_in" id="HDiet_height_in" size="4" tabindex="10"
            maxlength="4" value="$height_in" onchange="height_changed_in();" />
                <label for="HDiet_height_in">inches</label>
    </td>
</tr>



<tr><th>Weight unit:</th>
    <td>
    <table>
    <tr><td>
    <b>Log:</b></td><td>
    <input type="radio" name="HDiet_wunit" id="HDiet_wunit_kg" value="0"$wunit{0}
        tabindex="11"$ch_logunit />&nbsp;<label for="HDiet_wunit_kg">kilogram</label>
    <input type="radio" name="HDiet_wunit" id="HDiet_wunit_lb" value="1"$wunit{1}
        tabindex="12"$ch_logunit />&nbsp;<label for="HDiet_wunit_lb">pound</label>
    <input type="radio" name="HDiet_wunit" id="HDiet_wunit_st" value="2"$wunit{2}
        tabindex="13"$ch_logunit />&nbsp;<label for="HDiet_wunit_st">stone</label>
    </td></tr>
    <tr><td>
    <b>Display:</b></td><td>
    <input type="radio" name="HDiet_dunit" id="HDiet_dunit_kg" value="0"$dunit{0}
        tabindex="14"$ch_dispunit />&nbsp;<label for="HDiet_dunit_kg">kilogram</label>
    <input type="radio" name="HDiet_dunit" id="HDiet_dunit_lb" value="1"$dunit{1}
        tabindex="15"$ch_dispunit />&nbsp;<label for="HDiet_dunit_lb">pound</label>
    <input type="radio" name="HDiet_dunit" id="HDiet_dunit_st" value="2"$dunit{2}
        tabindex="16"$ch_dispunit />&nbsp;<label for="HDiet_dunit_st">stone</label>
    </td></tr>
    </table>
    </td>
</tr>

<tr><th>Energy unit:</th>
    <td>
    <input type="radio" name="HDiet_eunit" id="HDiet_eunit_cal" value="0"$eunit{0}
        tabindex="17" />&nbsp;<label for="HDiet_eunit_cal">calorie</label>
    <input type="radio" name="HDiet_eunit" id="HDiet_eunit_kj" value="1"$eunit{1}
        tabindex="18" />&nbsp;<label for="HDiet_eunit_kj">kilojoule</label>
    </td>
</tr>



<tr><th>Decimal character:</th>
    <td>
    <input type="radio" name="HDiet_dchar" id="HDiet_dchar_period" value="."$dchar{'.'}
        tabindex="19" />&nbsp;<label for="HDiet_dchar_period">123.4</label>
    <input type="radio" name="HDiet_dchar" id="HDiet_dchar_comma" value=","$dchar{','}
        tabindex="20" />&nbsp;<label for="HDiet_dchar_comma">123,4</label>
    </td>
</tr>

EOD
        
        print $fh <<"EOD";
<tr><th>Public name:</th>
    <td>
EOD
        if ($self->{public}) {
            my $pub_name = quoteHTML($self->{public_name});
            print $fh <<"EOD";
<input type="checkbox" name="HDiet_public" checked="checked" tabindex="21" />
<b>Pseudonym:</b> $pub_name &nbsp; &nbsp;
<input type="checkbox" name="HDiet_pubnew" id="HDiet_pubnew"
    tabindex="22" />&nbsp;<label for="HDiet_pubnew">Assign new pseudonym?</label>
EOD
        } else {
            print $fh <<"EOD";
<input type="checkbox" name="HDiet_public" id="HDiet_public"
tabindex="21" /> <label for="HDiet_public">Check to make your
    logs visible to the public under a pseudonym.</label>
EOD
        }

        print $fh <<"EOD";
    </td>
</tr>
EOD


        print $fh <<"EOD";
</table>
EOD
    }

    sub resetPassword {
        my $self = shift;
        my ($nchars) = @_;

        my $npw = $self->generatePassword($nchars);
        $self->{password} = $npw;

        return $npw;
    }

    sub generatePassword {
        my $self = shift;
        my ($nchars, $pwchars) = @_;

        $pwchars = ("ABCDEFGHIJKLMNPQRSTUVWXYZ" .
                    "abcdefghjkmnopqrstuvwxyz" .
                    "23456789" .
                    "-.") if !$pwchars;

        my $npw = '';
        for (my $i = 0; $i < $nchars; $i++) {
            $npw .= substr($pwchars, int(rand(length($pwchars))), 1);
        }
        return $npw;
    }

    sub sendMail {
        my $self = shift;
        my ($subject, $message, $from) = @_;

        $from = "noreply\@fourmilab.ch" if !defined($from);

        open(MAIL, "|-:utf8", "/usr/lib/sendmail",
                "-f$from",
                $self->{e_mail}) ||
            die("Cannot create pipe to /usr/lib/sendmail");
        print MAIL <<"EOD";
From $from\r
To: $self->{e_mail}\r
Subject: [The Hacker's Diet Online] $subject\r
Content-type: text/plain; charset=utf-8\r
\r
$message
.\r
EOD
        close(MAIL);
    }

    sub exportUserInformationXML {
        my $self = shift;
        my ($fh) = @_;

        my $li = quoteXML($self->{login_name}, 1);
        my $fn = quoteXML($self->{first_name}, 1);
        my $mn = quoteXML($self->{middle_name}, 1);
        my $ln = quoteXML($self->{last_name}, 1);
        my $em = quoteXML($self->{e_mail}, 1);
        my $ac = timeXML($self->{account_created});

        print $fh <<"EOD";
        <user version="1.0">
            <login-name>$li</login-name>
            <first-name>$fn</first-name>
            <middle-name>$mn</middle-name>
            <last-name>$ln</last-name>
            <e-mail>$em</e-mail>
            <height>$self->{height}</height>
            <account-created>$ac</account-created>
        </user>
EOD
    }

    sub exportPreferencesXML {
        my $self = shift;
        my ($fh) = @_;

        my $lu = HDiet::monthlog::WEIGHT_UNITS->[$self->{log_unit}];
        my $du = HDiet::monthlog::WEIGHT_UNITS->[$self->{display_unit}];
        my $eu = HDiet::monthlog::ENERGY_UNITS->[$self->{energy_unit}];
        my $cr = $self->{current_rung};
        my $dc = quoteXML($self->{decimal_character});

        print $fh <<"EOD";
        <preferences version="1.0">
            <log-unit>$lu</log-unit>
            <display-unit>$du</display-unit>
            <energy-unit>$eu</energy-unit>
            <current-rung>$cr</current-rung>
            <decimal-character>$dc</decimal-character>
        </preferences>
EOD
    }

    sub exportDietPlanXML {
        my $self = shift;
        my ($fh) = @_;

        my $ac = timeXML($self->{calc_start_date});

        print $fh <<"EOD";
        <diet-plan version="1.0">
            <calorie-balance>$self->{calc_calorie_balance}</calorie-balance>
            <start-weight>$self->{calc_start_weight}</start-weight>
            <goal-weight>$self->{calc_goal_weight}</goal-weight>
            <start-date>$ac</start-date>
            <show-plan>$self->{plot_diet_plan}</show-plan>
        </diet-plan>
EOD
    }

    sub enumerateMonths {
        my $self = shift;
        my ($year) = @_;

        my $user_file_name = quoteUserName($self->{login_name});
        my $selpat = $year ? $year : '\d+';

        opendir(CD, "/server/pub/hackdiet/Users/$user_file_name") ||
            die("Cannot open directory /server/pub/hackdiet/Users/$user_file_name");
        my @logs;
        my $f;
        foreach $f (sort(grep(/^$selpat\-\d\d\.hdb/, readdir(CD)))) {
            $f =~ s/\.\w*$//;
            push(@logs, $f);
        }
        closedir(CD);

        return @logs;
    }

    sub enumerateYears {
        my $self = shift;

        my $user_file_name = quoteUserName($self->{login_name});
        my $lyear = '';
        my @years;

        opendir(CD, "/server/pub/hackdiet/Users/$user_file_name") ||
            die("Cannot open directory /server/pub/hackdiet/Users/$user_file_name");
        my $m;
        foreach $m (sort(grep(/^\d+\-\d\d\.hdb/, readdir(CD)))) {
            $m =~ m/^(\d+)\-/;
            if ($1 ne $lyear) {
                $lyear = $1;
                push(@years, $lyear);
            }
        }
        closedir(CD);

        return @years;
    }

    sub dietPlanLimits {
        my $self = shift;

        if (($self->{calc_start_weight} == 0) ||
            ($self->{calc_goal_weight} == 0) ||
            ($self->{calc_start_date} == 0) ||
            (::sgn($self->{calc_calorie_balance}) != ::sgn($self->{calc_goal_weight} - $self->{calc_start_weight}))) {
            return undef;
        }
        my $jdstart = unix_time_to_jd($self->{calc_start_date});
        my $jdend = $jdstart +
               (($self->{calc_calorie_balance} != 0) ? ((($self->{calc_goal_weight} - $self->{calc_start_weight}) /
                ($self->{calc_calorie_balance} /
                   HDiet::monthlog::CALORIES_PER_WEIGHT_UNIT->[HDiet::monthlog::WEIGHT_KILOGRAM]))) : 1);
        return ($jdstart, $self->{calc_start_weight}, $jdend, $self->{calc_goal_weight});
    }

    sub generateEncryptedUserID {
        my $self = shift;

        my $plain = '';
        for (my $i = 0; $i < 13; $i++) {
            $plain .= chr(int(rand(95)) + 32);
        }
        $plain .= quoteUserName($self->{login_name});
        for (my $i = 0; $i < 11; $i++) {
            $plain .= chr(int(rand(95)) + 32);
        }
        my $crc = new HDiet::Digest::Crc32();
        $plain .= sprintf("%08x", $crc->strcrc32($plain));

        my $crypto = Crypt::CBC->new(
                -key => "Super duper top secret!",
                -cipher => "Crypt::OpenSSL::AES"
                                    );
        my $encrypted = $crypto->encrypt($plain);
        my $ecrc = sprintf("%08x", $crc->strcrc32($encrypted));
        my $huid = unpack("H*", $encrypted);
        my $euid = substr($huid, 0, 17) . $ecrc . substr($huid, 17);
        $euid =~ tr/a-f/FGJKQW/;
        return $euid;
    }

    sub quoteUserName {
        my ($s) = @_;

        my $os = '';

        while ($s =~ s/^(.)//) {
            my $c = $1;

            if ((ord($c) < 256) && ($c =~ m/[\w\x{c0}-\x{d6}\x{d8}-\x{dd}\x{df}\x{e0}-\x{f6}\x{f8}-\x{fd}\x{ff}]/)) {
                $os .= $c;
            } elsif ($c eq ' ') {
                $os .= '+';
            } else {
                $os .= sprintf('{' .
                               '%X' .
                               '}', ord($c));
            }
        }

        if (length($os) > 255) {
            $os = substr($os, 0, 255 - 40) .
                    sha1_hex(encode_utf8($os));
        }

        return $os;
    }

    sub canonicalNumber {
        my ($value, $places) = @_;

        $value = sprintf("%.${places}f", $value);

        $value =~ s/(\.[^0]*)0+$/$1/;
        $value =~ s/\.$//;

        return $value;
    }

    sub localiseDecimal {
        my $self = shift;
        my ($value) = @_;

        $value =~ s/\./$self->{decimal_character}/;

        return $value;
    }

    sub localiseNumber {
        my $self = shift;
        my ($value, $places) = @_;

        return $self->localiseDecimal(canonicalNumber($value, $places));
    }
