#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;



    package HDiet::session;

    use Encode qw(encode_utf8);
    use Digest::SHA1  qw(sha1_hex);

    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT = qw( load_active_session );
    1;

    use constant FILE_VERSION => 1;


    sub new {
        my $self = {};
        my ($invocant, $login_name, $login_time) = @_;
        my $class = ref($invocant) || $invocant;

        $login_name = '' if !defined($login_name);
        $login_time = time() if !defined($login_time);

        bless($self, $class);

        $self->{version} = FILE_VERSION;

        #   Initialise instance variables
        $self->{login_name} = $login_name;
        if ($login_name ne '') {
            $self->{session_id} = generateSessionID($login_name);
        } else {
            $self->{session_id} = '';
        }
        $self->{login_time} = $login_time;

        $self->{effective_name} = $self->{browse_name} = '';
        $self->{read_only} = 0;
        $self->{handheld} = 0;
        $self->{cookie} = 0;

        return $self;
    }

    sub describe {
        my $self = shift;
        my ($outfile) = @_;

        if (!(defined $outfile)) {
            $outfile = \*STDOUT;
        }

        print($outfile "SESSION Version: $self->{version}\n");
        print($outfile "  User name:      '$self->{login_name}'\n");
        print($outfile "  Session ID:     '$self->{session_id}'\n");
        print($outfile "  Login time:      " . localtime($self->{login_time}) . "\n");
        print($outfile "  Effective name: '$self->{effective_name}'\n");
        print($outfile "  Browse name:    '$self->{browse_name}'\n");
        print($outfile "  Read only:      '$self->{read_only}'\n");
        print($outfile "  Handheld:       '$self->{handheld}'\n");
        print($outfile "  Cookie login:   '$self->{cookie}'\n");

    }

    sub save {
        my $self = shift;
        my ($outfile) = @_;

        #   File format version number
        print($outfile "$self->{version}\n");
        #   Login name
        print($outfile "$self->{login_name}\n");
        #   Session ID
        print($outfile "$self->{session_id}\n");
        #   Login time
        print($outfile "$self->{login_time}\n");
        #   Effective name
        print($outfile "$self->{effective_name}\n");
        #   Browse name
        print($outfile "$self->{browse_name}\n");
        #   Read only
        print($outfile "$self->{read_only}\n");
        #   Handheld device
        print($outfile "$self->{handheld}\n");
        #   Cookie login
        print($outfile "$self->{cookie}\n");
    }

    sub load {
        my $self = shift;
        my ($infile) = @_;

        my $s = in($infile);

        if ($s != FILE_VERSION) {
            die("session::load: Incompatible file version $s");
        }

        $self->{login_name} = in($infile);
        $self->{session_id} = in($infile);
        $self->{login_time} = in($infile);
        $self->{effective_name} = in($infile);
        $self->{browse_name} = in($infile);
        $self->{read_only} = in($infile);
        $self->{handheld} = in($infile, 0);
        $self->{cookie} = in($infile, 0);
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
                die("session::in: Unexpected end of file");
            }
        }
        return $s;
    }


    sub save_active_session {
        my $self = shift;
        my ($outfile) = @_;

        #   File format version number
        print($outfile "$self->{version}\n");
        #   Session ID
        print($outfile "$self->{session_id}\n");
    }

    sub load_active_session {
        my ($infile) = @_;

        my $s = in($infile);

        if ($s != FILE_VERSION) {
            die("session::load_active_session: Incompatible file version $s");
            return '';
        }

        return in($infile);
    }

    sub generateSessionID {
        my ($login) = @_;

        $login = encode_utf8($login);
        for (my $i = 0; $i < 16; $i++) {
            $login .= chr(int(rand(256)));
        }
        my $si = sha1_hex($login);
        $si =~ tr/a-f/FGJKQW/;
        return $si;
    }
