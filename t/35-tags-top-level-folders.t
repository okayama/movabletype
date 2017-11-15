use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib"; # t/lib
use Test::More;
use MT::Test::Env;
our $test_env;
BEGIN {
    $test_env = MT::Test::Env->new;
    $ENV{MT_CONFIG} = $test_env->config_file;
}

use MT::Test::Tag;
plan tests => 2 * blocks;

use MT;
use MT::Test;
use MT::Test::Permission;

filters {
    template => [qw( chomp )],
    expected => [qw( chomp )],
};

my $blog_id         = 1;

$test_env->prepare_fixture(sub {
    MT::Test->init_db;

    MT::Test::Permission->make_folder(
        blog_id => $blog_id,
        label => 'foo',
    );
    MT::Test::Permission->make_folder(
        blog_id => $blog_id,
        label => 'bar',
    );
    MT::Test::Permission->make_folder(
        blog_id => $blog_id,
        label => 'baz',
    );
});

MT::Test::Tag->run_perl_tests($blog_id);
MT::Test::Tag->run_php_tests($blog_id);

__END__

=== MTTopLevelFolders
--- template
<MTTopLevelFolders><MTFolderLabel>
</MTTopLevelFolders>
--- expected
bar
baz
foo

=== MTTopLevelFolders category_set_id="1"
--- template
<MTTopLevelFolders category_set_id="1"><MTFolderLabel>
</MTTopLevelFolders>
--- expected
bar
baz
foo
