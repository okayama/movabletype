# Movable Type (r) (C) 2006-2017 Six Apart, Ltd. All Rights Reserved.
# This code cannot be redistributed without permission from www.sixapart.com.
# For more information, consult your Movable Type license.
#
# $Id$

package MT::RebuildTrigger;

use strict;
use base qw( MT::Object );

use Exporter 'import';
our @EXPORT_OK = qw(
    TYPE_ENTRY_OR_PAGE TYPE_CONTENT_TYPE TYPE_COMMENT TYPE_PING
    ACTION_RI ACTION_RIP
    EVENT_SAVE EVENT_PUBLISH EVENT_UNPUBLISH
    TARGET_ALL TARGET_BLOGS_IN_WEBSITE TARGET_BLOG
    type_text action_text event_text
);
our %EXPORT_TAGS = (
    constants => [
        qw(
            TYPE_ENTRY_OR_PAGE TYPE_CONTENT_TYPE TYPE_COMMENT TYPE_PING
            ACTION_RI ACTION_RIP
            EVENT_SAVE EVENT_PUBLISH EVENT_UNPUBLISH
            TARGET_ALL TARGET_BLOGS_IN_WEBSITE TARGET_BLOG
            type_text action_text event_text
            )
    ]
);

sub TYPE_ENTRY_OR_PAGE() {1}
sub TYPE_CONTENT_TYPE()  {2}
sub TYPE_COMMENT()       {3}
sub TYPE_PING()          {4}

sub ACTION_RI()  {1}    # rebuild index pages
sub ACTION_RIP() {2}    # rebuild index pages and send update ping

sub EVENT_SAVE()      {1}
sub EVENT_PUBLISH()   {2}
sub EVENT_UNPUBLISH() {3}

sub TARGET_ALL()              {1}
sub TARGET_BLOGS_IN_WEBSITE() {2}
sub TARGET_BLOG()             {3}

sub type_text {
    my $s = $_[0];
          $s == TYPE_ENTRY_OR_PAGE ? "entry"
        : $s == TYPE_CONTENT_TYPE  ? "content"
        : $s == TYPE_COMMENT       ? "comment"
        : $s == TYPE_PING          ? "tb"
        :                            '';
}

sub action_text {
    my $s = $_[0];
          $s == ACTION_RI  ? "ri"
        : $s == ACTION_RIP ? "rip"
        :                    '';
}

sub event_text {
    my $s = $_[0];
          $s == EVENT_SAVE      ? "save"
        : $s == EVENT_PUBLISH   ? "pub"
        : $s == EVENT_UNPUBLISH ? "unpub"
        :                         '';
}

sub target_text {
    my $s = $_[0];
          $s == TARGET_ALL              ? "_all"
        : $s == TARGET_BLOGS_IN_WEBSITE ? "_blogs_in_website"
        : $s == TARGET_BLOG             ? "_blog"
        :                                 '';
}

__PACKAGE__->install_properties(
    {   column_defs => {
            'id'             => 'integer not null auto_increment',
            'blog_id'        => 'integer not null',
            'object_type'    => 'integer',
            'ct_id'          => 'integer',
            'ct_unique_id'   => 'string(40)',
            'action'         => 'integer',
            'event'          => 'integer',
            'target'         => 'integer',
            'target_blog_id' => 'integer',
        },
        indexes     => { blog_id => 1 },
        datasource  => 'rebuild_trigger',
        primary_key => 'id',
        audit       => 1,
        child_of => [ 'MT::Blog', 'MT::Website' ],
    }
);

# Blog-level Access override statuses
sub DENIED ()  {1}
sub ALLOWED () {2}

sub class_label {
    MT->translate("Rebuild Trigger");
}

sub post_contents_bulk_save {
    my $self = shift;
    my ( $app, $contents ) = @_;
    foreach my $content (@$contents) {
        &post_content_save( $self, $app, $content->{current} );
    }
}

sub get_config_value {
    my $self = shift;
    my ( $var, $blog_id ) = @_;

    my @rebuild_triggers
        = MT->model('rebuild_trigger')->load( { blog_id => $blog_id } );
    my $data = {};
    foreach my $rt (@rebuild_triggers) {
        next if $rt->target_blog_id && $blog_id == $rt->target_blog_id;
        my $trigger
            = type_text( $rt->object_type ) . '_' . event_text( $rt->event );
        my $target_blog_id
            = $rt->target == TARGET_BLOG()
            ? $rt->target_blog_id
            : target_text( $rt->target );
        my $content_type_id = $rt->ct_id ? $rt->ct_id : '';
        my $action = action_text( $rt->action );
        $data->{$trigger}{$blog_id}{$action}
            = $target_blog_id . ( $rt->ct_id ? ':' . $rt->ct_id : '' );
    }
    return $data;
}

sub post_content_save {
    my $self = shift;
    my ( $app, $content ) = @_;
    my $blog_id = $content->blog_id || 0;
    my @blog_ids = $blog_id ? (0) : ( $blog_id, 0 );

    my $code = sub {
        my ($d) = @_;
        while ( my ( $id, $a ) = each( %{ $d->{'content_save'} } ) ) {
            next if $id == $blog_id;
            perform_mb_action( $app, $id, $_ ) foreach keys %$a;
        }

        require MT::ContentStatus;
        if ( ( $content->status || 0 ) == MT::ContentStatus::RELEASE() ) {
            while ( my ( $id, $a ) = each( %{ $d->{'content_pub'} } ) ) {
                next if $id == $blog_id;
                perform_mb_action( $app, $id, $_ ) foreach keys %$a;
            }
        }
    };

    $self->post_content_common( \@blog_ids, $code, $content->blog );
}

sub post_content_pub {
    my $self = shift;
    my ( $app, $content ) = @_;
    my $blog_id = $content->blog_id;
    my @blog_ids = $blog_id ? (0) : ( $blog_id, 0 );

    my $code = sub {
        my ($d) = @_;

        require MT::ContentStatus;
        if ( ( $content->status || 0 ) == MT::ContentStatus::RELEASE() ) {
            while ( my ( $id, $a ) = each( %{ $d->{'content_pub'} } ) ) {
                next if $id == $blog_id;
                perform_mb_action( $app, $id, $_ ) foreach keys %$a;
            }
        }
    };

    _post_content_common( $self, \@blog_ids, $code, $content->blog );
}

sub post_content_unpub {
    my $self = shift;
    my ( $app, $content ) = @_;
    my $blog_id = $content->blog_id;
    my @blog_ids = $blog_id ? (0) : ( $blog_id, 0 );

    my $code = sub {
        my ($d) = @_;

        require MT::ContentStatus;
        if ( ( $content->status || 0 ) == MT::ContentStatus::UNPUBLISH() ) {
            while ( my ( $id, $a ) = each( %{ $d->{'content_unpub'} } ) ) {
                next if $id == $blog_id;
                perform_mb_action( $app, $id, $_ ) foreach keys %$a;
            }
        }
    };

    _post_content_common( $self, \@blog_ids, $code, $content->blog );
}

sub init_rebuilt_cache {
    my ( $self, $app ) = @_;
    $app->request( 'sites_rebuild', {} );
}

sub is_first_rebuild {
    my ( $app, $blog_id, $action ) = @_;
    my $rebuilt = $app->request('sites_rebuild') || {};
    return if exists $rebuilt->{"$blog_id,$action"};
    $rebuilt->{"$blog_id,$action"} = 1;
    $app->request( 'sites_rebuild', $rebuilt );
}

sub perform_mb_action {
    my ( $app, $blog_id, $action ) = @_;

    # Don't rebuild the same thing twice in a same runner
    return unless is_first_rebuild( $app, $blog_id, $action );

    # If the action we are performing starts with ri
    # we rebuild indexes for the given blog_id
    if ( $action =~ /^ri/ ) {
        $app->rebuild_indexes( BlogID => $blog_id );
    }
}

sub load_sites_acl {
    my $self = shift;
    my ($ctx) = @_;

    # Set local site
    my $this_blog = $ctx->stash('blog_id') || 0;

    # Get the MultiBlog system config for default access and overrides
    my $default_access_allowed = MT->config('DefaultAccessAllowed');
    my $access_overrides
        = MT->config('AccessOverrides')
        ? MT::Util::from_json( MT->config('AccessOverrides') )
        : {};

    # System setting allows access by default
    my ( $mode, @acl );
    if ($default_access_allowed) {
        @acl = grep {
                    $_ != $this_blog
                and exists $access_overrides->{$_}
                and $access_overrides->{$_} == DENIED
        } keys %$access_overrides;
        $mode = 'deny_blogs';
    }
    else {
        @acl = grep { $_ == $this_blog or $access_overrides->{$_} == ALLOWED }
            ( $this_blog, keys %$access_overrides );
        $mode = 'allow_blogs';
    }

    return ( mode => $mode, acl => @acl ? \@acl : undef );
}

sub post_restore {
    my ( $self, $objects, $deferred, $errors, $callback ) = @_;

    foreach my $key ( keys %$objects ) {
        next unless $key =~ /^MT::RebuildTrigger#\d+$/;
        my $rt = $objects->{$key};
        my $data = $rt->data || {};
        $data = MT::Util::from_json($data);
        next unless ref $data eq 'HASH';
        my $new_blog_id;
        if ( my $rebuild_triggers = $data->{rebuild_triggers} ) {
            my @restored;
            foreach my $trg_str ( split( '\|', $rebuild_triggers ) ) {
                my ( $action, $id, $trigger ) = split( ':', $trg_str );
                if ( $id eq '_all' ) {
                    push @restored, "$action:$id:$trigger";
                    $new_blog_id = 0;
                }
                elsif ( $id eq '_blogs_in_website' ) {
                    my @keys = keys %{ $data->{blogs_in_website_triggers} };
                    foreach my $act (@keys) {
                        my @old_ids = keys
                            %{ $data->{blogs_in_website_triggers}{$act} };
                        foreach my $old_id (@old_ids) {
                            my $new_obj = $objects->{ 'MT::Blog#' . $old_id };
                            $new_obj = $objects->{ 'MT::Website#' . $old_id }
                                unless $new_obj;
                            if ($new_obj) {
                                $data->{blogs_in_website_triggers}{$act}
                                    { $new_obj->id }
                                    = delete
                                    $data->{blogs_in_website_triggers}{$act}
                                    {$old_id};
                                $callback->(
                                    MT->translate(
                                        'Restoring MultiBlog rebuild trigger for blog #[_1]...',
                                        $old_id
                                    )
                                );
                            }
                        }
                    }
                    push @restored, "$action:$id:$trigger";
                    $new_blog_id = 0;
                }
                else {
                    my $new_obj = $objects->{ 'MT::Blog#' . $id };
                    $new_obj = $objects->{ 'MT::Website#' . $id }
                        unless $new_obj;
                    if ($new_obj) {
                        push @restored,
                            "$action:" . $new_obj->id . ":$trigger";
                        $callback->(
                            MT->translate(
                                'Restoring MultiBlog rebuild trigger for blog #[_1]...',
                                $id
                            )
                        );
                        $new_blog_id = $new_obj->id;
                    }
                }
            }

            if (@restored) {
                $data->{rebuild_triggers} = join( '|', @restored );
                $rt->blog_id($new_blog_id);
                $rt->data( MT::Util::to_json($data) );
                $rt->save;
            }
        }
        elsif ( my $other_triggers = $data->{other_triggers} ) {
            my @keys = keys %{$other_triggers};
            foreach my $act (@keys) {
                my @old_ids = keys %{ $other_triggers->{$act} };
                foreach my $old_id (@old_ids) {
                    my $new_obj = $objects->{ 'MT::Blog#' . $old_id };
                    $new_obj = $objects->{ 'MT::Website#' . $old_id }
                        unless $new_obj;
                    if ($new_obj) {
                        $data->{other_triggers}{$act}{ $new_obj->id }
                            = delete $data->{other_triggers}{$act}{$old_id};
                        $callback->(
                            MT->translate(
                                'Restoring MultiBlog rebuild trigger for blog #[_1]...',
                                $old_id
                            )
                        );
                    }
                }
                $new_blog_id = 0;
            }
            $rt->blog_id($new_blog_id);
            $rt->data( MT::Util::to_json($data) );
            $rt->save;
        }
    }
}

# Run-time loading for Rebuild Trigger core methods
sub runner {
    my $self   = shift;
    my $method = shift;
    $self->init_rebuilt_cache( MT->instance );
    no strict 'refs';
    return $_->( $self, @_ ) if $_ = \&{"MT::RebuildTrigger::$method"};
    die "Failed to find MT::RebuildTrigger::$method";
}

sub post_feedback_save {
    my $self = shift;
    my ( $trigger, $eh, $feedback ) = @_;
    if ( $feedback->visible ) {
        my $blog_id  = $feedback->blog_id;
        my @blog_ids = $blog_id ? ( $blog_id, 0 ) : (0);
        my $app      = MT->instance;

        my $code = sub {
            my ($d) = @_;

            while ( my ( $id, $a ) = each( %{ $d->{$trigger} } ) ) {
                next if $id == $blog_id;
                perform_mb_action( $app, $id, $_ ) foreach keys %$a;
            }
        };

        _post_content_common( $self, \@blog_ids, $code, $feedback->blog );
    }
}

sub post_entries_bulk_save {
    my $self = shift;
    my ( $eh, $app, $entries ) = @_;
    foreach my $entry (@$entries) {
        &post_entry_save( $self, $eh, $app, $entry->{current} );
    }
}

sub post_entry_save {
    my $self = shift;
    my ( $eh, $app, $entry ) = @_;
    my $blog_id = $entry->blog_id;
    my @blog_ids = $blog_id ? ( $blog_id, 0 ) : (0);

    my $code = sub {
        my ($d) = @_;
        while ( my ( $id, $a ) = each( %{ $d->{'entry_save'} } ) ) {
            next if $id == $blog_id;
            perform_mb_action( $app, $id, $_ ) foreach keys %$a;
        }

        require MT::Entry;
        if ( ( $entry->status || 0 ) == MT::Entry::RELEASE() ) {
            while ( my ( $id, $a ) = each( %{ $d->{'entry_pub'} } ) ) {
                next if $id == $blog_id;
                perform_mb_action( $app, $id, $_ ) foreach keys %$a;
            }
        }
    };

    _post_content_common( $self, \@blog_ids, $code, $entry->blog );
}

sub post_entry_pub {
    my $self = shift;
    my ( $eh, $app, $entry ) = @_;
    my $blog_id = $entry->blog_id;
    my @blog_ids = $blog_id ? ( $blog_id, 0 ) : (0);

    my $code = sub {
        my ($d) = @_;

        require MT::Entry;
        if ( ( $entry->status || 0 ) == MT::Entry::RELEASE() ) {
            while ( my ( $id, $a ) = each( %{ $d->{'entry_pub'} } ) ) {
                next if $id == $blog_id;
                perform_mb_action( $app, $id, $_ ) foreach keys %$a;
            }
        }
    };

    _post_content_common( $self, \@blog_ids, $code, $entry->blog );
}

sub post_entry_unpub {
    my $self = shift;
    my ( $eh, $app, $entry ) = @_;
    my $blog_id = $entry->blog_id;
    my @blog_ids = $blog_id ? ( $blog_id, 0 ) : (0);

    my $code = sub {
        my ($d) = @_;

        require MT::Entry;
        if ( ( $entry->status || 0 ) == MT::Entry::UNPUBLISH() ) {
            while ( my ( $id, $a ) = each( %{ $d->{'entry_unpub'} } ) ) {
                next if $id == $blog_id;
                perform_mb_action( $app, $id, $_ ) foreach keys %$a;
            }
        }
    };

    _post_content_common( $self, \@blog_ids, $code, $entry->blog );
}

sub _post_content_common {
    my ( $self, $blog_ids, $code, $blog ) = @_;

    foreach my $blog_id (@$blog_ids) {
        my $d = $self->get_config_value(
            $blog_id == 0 ? 'all_triggers' : 'other_triggers', $blog_id );
        $code->($d);
    }

    if ( my $website = $blog->website ) {
        my $blog_id = $website->id;
        my $d       = $self->get_config_value( 'blogs_in_website_triggers',
            $blog_id );
        $code->($d);
    }
}

sub update_trigger_cache {
    my $self = shift;
    my ( $data, $blog_id ) = @_;

    if ( $blog_id > 0 ) {

        my $blog = MT->model('blog')->load($blog_id);

        # Save blog-level content aggregation policy to single
        # system config hash for easy lookup
        my ( $cfg_old, $cfg_new ) = 0;
        my $override
            = MT->config('AccessOverrides')
            ? MT::Util::from_json( MT->config('AccessOverrides') )
            : {};
        $cfg_new = $blog ? $blog->blog_content_accessible || 0 : 0;
        if ( exists $override->{$blog_id} ) {
            $cfg_old = $override->{$blog_id};
        }
        if ( $cfg_old != $cfg_new ) {
            $override->{$blog_id} = $cfg_new
                or delete $override->{$blog_id};
            MT->config( 'AccessOverrides', MT::Util::to_json($override) );
        }

        # Fiddle with rebuild triggers...
        my $rebuild_triggers = $data->{rebuild_triggers}     || '';
        my $old_triggers     = $data->{old_rebuild_triggers} || '';

        # Check to see if the triggers changed
        if ( $old_triggers ne $rebuild_triggers ) {

# If so, remove all references to the current blog from the triggers cached in other blogs
            foreach ( split( /\|/, $old_triggers ) ) {
                my ( $action, $id, $trigger ) = split( /:/, $_ );
                my $name
                    = $id eq '_all'              ? "all_triggers"
                    : $id eq '_blogs_in_website' ? 'blogs_in_website_triggers'
                    :                              "other_triggers";
                my $scope;
                if ( $id eq '_all' ) {
                    $scope = 0;
                }
                elsif ( $id eq '_blogs_in_website' ) {
                    $scope = $blog_id;
                }
                else {
                    $scope = $id;
                }
                my $d = $self->get_config_value( $name, $scope );
                next unless exists $d->{$trigger}{$blog_id};
                delete $d->{$trigger}{$blog_id};
                $self->set_config_value( $name, $d, $scope );
            }
        }
        foreach ( split( /\|/, $rebuild_triggers ) ) {
            my ( $action, $id, $trigger ) = split( /:/, $_ );
            my $name
                = $id eq '_all'              ? "all_triggers"
                : $id eq '_blogs_in_website' ? 'blogs_in_website_triggers'
                :                              "other_triggers";
            my $scope;
            if ( $id eq '_all' ) {
                $scope = 0;
            }
            elsif ( $id eq '_blogs_in_website' ) {
                $scope = $blog_id;
            }
            else {
                $scope = $id;
            }

            my $d = $self->get_config_value( $name, $scope ) || {};
            $d->{$trigger}{$blog_id}{$action} = 1;
            $self->set_config_value( $name, $d, $scope );
        }
    }
}

sub set_config_value {
    my $self = shift;
    my ( $name, $d, $blog_id ) = @_;

    my $rt = MT->model('rebuild_trigger')->load( { blog_id => $blog_id } );
    unless ($rt) {
        $rt = MT->model('rebuild_trigger')->new();
        $rt->blog_id($blog_id);
        $rt->data('{}');
    }
    my $data
        = $rt->data()
        ? MT::Util::from_json( $rt->data() )
        : {};
    $data->{$name} = $d;
    $rt->data( MT::Util::to_json($data) );
    $rt->save;
}

1;