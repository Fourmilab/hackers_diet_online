#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    package HDiet::pubname;

    use Fcntl;

    use HDiet::Cluster;

    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT = ( );

    my @nameSources = ( 'firstnames.txt', 'lastnames.txt' );
    #   Names per nameSources entry.  Zero means use seek technique
    my @nameLength = ( 24, 0 );

    1;

    use constant FILE_VERSION => 1;

    sub new {
        my $self = {};
        my ($invocant) = @_;
        my $class = ref($invocant) || $invocant;

        bless($self, $class);

        $self->{version} = FILE_VERSION;
        $self->{public_name} = $self->{true_name} = '';
        $self->{true_create_time} = $self->{public_create_time} = 0;

        return $self;
    }

    sub generateRandomName {
        my $self = shift;

        my $name = '';

        for (my $i = 0; $i <= $#nameSources; $i++) {
            my $filename = "/server/pub/hackdiet/Pubname/$nameSources[$i]";
            open(NF, "<:utf8", $filename) ||
                die("pubname::generateUniqueName:  Cannot open $filename");
            my $s;
            if ($nameLength[$i] > 0) {
                my $line = int(rand() * $nameLength[$i]) + 1;
                while ($line-- > 0) {
                    $s = <NF> ||
                        die("pubname::generateUniqueName:  Unexpected EOF on $filename");
                }
            } else {
                while (1) {
                    seek(NF, int(rand() * (-s $filename)) - 64, 0);

                    $s = <NF>;          # Burn characters to align with next line
                    my $n = int(rand() * 7) + 1;
                    while ($n-- > 0) {
                        if (eof(NF)) {
                            next;
                        }
                        $s = <NF>;
                    }
                    last;
                }

            }
            close(NF);

            $s =~ s/\s+$//;
            $name .= $s . ' ';
        }

        $name =~ s/\s$//;
        return $name;
    }

    sub generateUniqueName {
        my $self = shift;

        my $name;
        while (1) {
            $name = $self->generateRandomName();
            my $ufn = HDiet::user::quoteUserName($name);
            if (!(-f "/server/pub/hackdiet/Pubname/$ufn.hdp")) {
                last;
            }
        }

        return $name;
    }

    sub assignPublicName {
        my $self = shift;

        my ($ui) = @_;

        if ($ui->{public}) {
            
    my $pfn = HDiet::user::quoteUserName($ui->{public_name});
    if (!unlink("/server/pub/hackdiet/Pubname/$pfn.hdp")) {
        die("Unable to delete old public name: /server/pub/hackdiet/Pubname/$pfn.hdp");
    }
    clusterDelete("/server/pub/hackdiet/Pubname/$pfn.hdp");
    $ui->{public_name} = '';

        }

        my ($name, $pfn);
        while (1) {
            $name = $self->generateRandomName();
            $pfn = HDiet::user::quoteUserName($name);
            if (sysopen(PF, "/server/pub/hackdiet/Pubname/$pfn.hdp", O_CREAT | O_EXCL | O_WRONLY)) {
                binmode(PF, ":utf8");
                last;
            }
        }

        if (!($ui->{public})) {
            $ui->{public} = 1;
            $ui->{public_since} = time();
        }

        $self->{public_name} = $ui->{public_name} = $name;
        $self->{true_name} = $ui->{login_name};
        $self->{true_create_time} = $ui->{account_created};
        $self->{public_create_time} = $ui->{public_since};

        $self->save(\*PF);
        close(PF);
        clusterCopy("/server/pub/hackdiet/Pubname/$pfn.hdp");

        return $name;
    }

    sub findPublicName {
        my $self = shift;

        my ($pname) = @_;

        #   Clear out object to avoid confusion in case of no find
        $self->{public_name} = $self->{true_name} = '';
        $self->{true_create_time} = $self->{public_create_time} = 0;

        my $pfn = HDiet::user::quoteUserName($pname);
        if (open(PF, "<:utf8", "/server/pub/hackdiet/Pubname/$pfn.hdp")) {
            $self->load(\*PF);
            close(PF);
            return $self->{true_name};
        }

        return undef;
    }

    sub deletePublicName {
        my $self = shift;

        my ($ui) = @_;

        if ($ui->{public}) {
            
    my $pfn = HDiet::user::quoteUserName($ui->{public_name});
    if (!unlink("/server/pub/hackdiet/Pubname/$pfn.hdp")) {
        die("Unable to delete old public name: /server/pub/hackdiet/Pubname/$pfn.hdp");
    }
    clusterDelete("/server/pub/hackdiet/Pubname/$pfn.hdp");
    $ui->{public_name} = '';

            $ui->{public} = 0;
            $self->{public_name} = $ui->{public_name} = '';
            $self->{public_create_time} = $self->{true_create_time} = $ui->{public_since} = 0;
        }
    }

    sub describe {
        my $self = shift;
        my ($outfile) = @_;

        if (!(defined $outfile)) {
            $outfile = \*STDOUT;
        }

        print($outfile "PUBNAME Version: $self->{version}\n");
        print($outfile "  Public name:  '$self->{public_name}'\n");
        print($outfile "  True name:    '$self->{true_name}'\n");
        print($outfile "  First login:  " . localtime($self->{true_create_time}) . "\n");
        print($outfile "  Public since: " . localtime($self->{public_create_time}) . "\n");
    }

    sub save {
        my $self = shift;
        my ($outfile) = @_;

        print $outfile <<"EOD";
$self->{version}
$self->{public_name}
$self->{true_name}
$self->{true_create_time}
$self->{public_create_time}
EOD
    }

    sub load {
        my $self = shift;
        my ($infile) = @_;

        my $s = in($infile);

        if ($s != FILE_VERSION) {
            die("user::load: Incompatible file version $s");
        }

        $self->{public_name} = in($infile);
        $self->{true_name} = in($infile);
        $self->{true_create_time} = in($infile);
        $self->{public_create_time} = in($infile);
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
                die("pubname::in: Unexpected end of file");
            }
        }
        return $s;
    }

