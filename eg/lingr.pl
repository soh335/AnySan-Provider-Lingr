use strict;
use warnings;

use AnySan::Provider::Lingr;
use Config::Pit;
use Encode qw/encode_utf8/;
use Log::Minimal;
use Path::Class;
use File::Spec;
use File::Temp;

my $config = pit_get("lingr.com", require => {
    user => "user",
    password => "password",
});

my $file = file(File::Spec->tmpdir, "anysan-lingr-session");

my %params = (
    %$config,
    session_create_cb => sub {
        my $json = shift;
        my $fh = $file->openw or die $!;
        $fh->print($json->{session});
        $fh->close;
        infof "session created";
    },
);

$params{session} = $file->slurp if -e $file;

my $lingr = lingr %params;

AnySan->register_listener(
    $_ => {
        event => $_,
        cb => sub {
            my $receive = shift;
            infof encode_utf8 sprintf "%s from:%s in:%s",
                $receive->message, $receive->from_nickname, $receive->attribute->{obj}{room};
        },
    },
) for qw/message presence/;

AnySan->run;
