# Movable Type (r) (C) 2007-2017 Six Apart, Ltd. All Rights Reserved.
# This code cannot be redistributed without permission from www.sixapart.com.
# For more information, consult your Movable Type license.
#
# $Id$

package MT::Template::Tags::ContentType;

use strict;

use MT;
use MT::ContentData;
use MT::ContentField;
use MT::ContentType;
use MT::Entry;
use MT::Util;

=head2 Contents

The Contents tag is a workhorse of MT publishing. It is used for
publishing a selection of contents in a variety of situations. Typically,
the basic use (specified without any attributes) outputs the selection
of contents that are appropriate for the page being published. But you
can use this tag for publishing custom modules, index templates and
widgets to select content in many different ways.

=cut

=head2 ContentsHeader

The contents of this container tag will be displayed when the first
content listed by a L<Contents> tag is reached.

=for tags entries

=cut

=head2 ContentsFooter

The contents of this container tag will be displayed when the last
content listed by a L<Contentss> tag is reached.

=for tags entries

=cut

sub _hdlr_contents {
    my ( $ctx, $args, $cond ) = @_;

    my $terms;
    my $type    = $args->{type};
    my $name    = $args->{name};
    my $blog_id = $args->{blog_id};
    if ($type) {
        $terms = { unique_id => $type };
    }
    elsif ( $name && $blog_id ) {
        $terms = {
            blog_id => $blog_id,
            name    => $name,
        };
    }
    else {
        return $ctx->error(
            MT->translate(
                '\'type\' or "\'name\' and \'blog_id\'" is required.')
        );
    }
    my $content_type = MT::ContentType->load($terms)
        or return $ctx->error( MT->translate('Content Type was not found.') );

    my $parent      = $ctx->stash('content_type');
    my $parent_data = $ctx->stash('content');
    my @data_ids;
    my $e_hash = {};

    if ($parent) {
        my $match = 0;
        foreach my $f ( @{ $content_type->fields } ) {
            my $field_obj = MT::ContentField->load( $f->{id} );
            if (   $f->{type} eq 'content_type'
                && $field_obj->related_content_type_id == $content_type->id )
            {
                $match++;
                my $data_ids = $parent_data->data->{ $f->{id} };
                @data_ids = split ',', $data_ids;
            }
        }

        return $ctx->error( MT->translate('Content Type was not found.') )
            unless $match;
    }

    my @contents
        = MT::ContentData->load( { content_type_id => $content_type->id } );

    my $i       = 0;
    my $res     = '';
    my $tok     = $ctx->stash('tokens');
    my $builder = $ctx->stash('builder');
    my $vars    = $ctx->{__stash}{vars} ||= {};
    local $ctx->{__stash}{contents}
        = ( @contents && defined $contents[0] ) ? \@contents : undef;
    for my $content_data (@contents) {
        next if $parent && !grep { $content_data->id == $_ } @data_ids;

        local $vars->{__first__}       = !$i;
        local $vars->{__last__}        = !defined $contents[ $i + 1 ];
        local $vars->{__odd__}         = ( $i % 2 ) == 0;
        local $vars->{__even__}        = ( $i % 2 ) == 1;
        local $vars->{__counter__}     = $i + 1;
        local $ctx->{__stash}{blog}    = $content_data->blog;
        local $ctx->{__stash}{blog_id} = $content_data->blog_id;
        local $ctx->{__stash}{content} = $content_data;

        my $ct_id        = $content_data->content_type_id;
        my $content_type = MT::ContentType->load($ct_id);
        local $ctx->{__stash}{content_type} = $content_type;

        defined(
            my $out = $builder->build(
                $ctx, $tok,
                {   %{$cond},
                    ContentsHeader => !$i,
                    ContentsFooter => !defined $contents[ $i + 1 ],
                }
            )
        ) or return $ctx->error( $builder->errstr );
        $res .= $out;
        $i++;
    }
    $res;
}

sub _hdlr_content {
    my ( $ctx, $args, $cond ) = @_;

    my $content      = $ctx->stash('content');
    my $content_type = $ctx->stash('content_type');

    my @field_data
        = sort { $a->{order} <=> $b->{order} } @{ $content_type->fields };

    my $datas = $content->data;

    my $out = '';
    foreach my $f (@field_data) {
        my $data = $datas->{ $f->{id} };
        $out .= "<div>$data</div>";
    }

    return $out;
}

sub _hdlr_entity {
    my ( $ctx, $args, $cond ) = @_;

    my $content = $ctx->stash('content');
    my $blog_id = $content->blog_id;

    my $terms;
    my $type = $args->{type};
    my $name = $args->{name};
    if ($type) {
        $terms = { unique_id => $type };
    }
    elsif ($name) {
        $terms = {
            blog_id => $blog_id,
            name    => $name,
        };
    }
    else {
        return $ctx->error(
            MT->translate('\'type\' or \'name\' is required.') );
    }
    my $content_field = MT::ContentField->load($terms);

    my $datas = $content->data;

    my $content_field_type
        = MT->registry('content_field_types')->{ $content_field->type };
    if ((      $content_field_type->{type} eq 'datetime'
            || $content_field->type eq 'date'
            || $content_field->type eq 'time'
        )
        && $datas->{ $content_field->id }
        )
    {
        $args->{ts}
            = $content_field->type eq 'date'
            ? $datas->{ $content_field->id } . '000000'
            : $content_field->type eq 'time'
            ? '19700101' . $datas->{ $content_field->id }
            : $datas->{ $content_field->id }
            unless $args->{ts};
        return $ctx->build_date($args);
    }
    else {
        return $datas->{ $content_field->id };
    }
}

sub _hdlr_assets {
    my ( $ctx, $args, $cond ) = @_;

    my $content    = $ctx->stash('content');
    my $blog_id    = $content->blog_id;
    my $ct_data_id = $content->id;

    my @field_ids
        = map { $_->id }
        MT::ContentField->load(
        { content_type_id => $content->content_type_id },
        { fetchonly       => { id => 1 } } );

    my @assets = MT::Asset->load(
        { class => '*' },
        {   join => MT::ObjectAsset->join_on(
                undef,
                {   asset_id  => \'= asset_id',
                    object_ds => 'content_field',
                    object_id => \@field_ids,
                }
            ),
            unique => 1,
        }
    );
    local $ctx->{__stash}{assets} = \@assets;

    require MT::Template::Tags::Asset;
    return MT::Template::Tags::Asset::_hdlr_assets(@_);
}

sub _hdlr_content_tags {
    my ( $ctx, $args, $cond ) = @_;

    require MT::Entry;
    my $content = $ctx->stash('content');
    return '' unless $content;
    my $glue = $args->{glue};

    local $ctx->{__stash}{tag_max_count} = undef;
    local $ctx->{__stash}{tag_min_count} = undef;
    local $ctx->{__stash}{all_tag_count} = undef;

    my $builder = $ctx->stash('builder');
    my $tokens  = $ctx->stash('tokens');
    my $res     = '';
    my $i       = 1;
    my $vars    = $ctx->{__stash}{vars} ||= {};
    my $tags    = $content->get_tag_objects;
    my @tags    = @$tags;
    if ( !$args->{include_private} ) {
        @tags = grep { !$_->is_private } @tags;
    }
    for my $tag (@tags) {
        local $vars->{__first__}   = $i == 1;
        local $vars->{__last__}    = $i == scalar @tags;
        local $vars->{__odd__}     = ( $i % 2 ) == 1;
        local $vars->{__even__}    = ( $i % 2 ) == 0;
        local $vars->{__counter__} = $i;
        $i++;
        local $ctx->{__stash}{Tag}             = $tag;
        local $ctx->{__stash}{tag_count}       = undef;
        local $ctx->{__stash}{tag_entry_count} = undef;
        defined( my $out = $builder->build( $ctx, $tokens, $cond ) )
            or return $ctx->error( $builder->errstr );
        $res .= $glue if defined $glue && length($res) && length($out);
        $res .= $out;
    }
    $res;
}

sub _hdlr_content_categories {
    my ( $ctx, $args, $cond ) = @_;
    my $c = $ctx->stash('content')
        or return $ctx->_no_entry_error();
    my $content    = $ctx->stash('content');
    my $ct_data_id = $content->id;
    my $cats;
    require MT::ObjectCategory;
    my @obj_cats = MT::ObjectCategory->load(
        {   object_ds => 'content_data',
            object_id => $ct_data_id
        }
    );
    foreach my $obj_cat (@obj_cats) {
        my $cat = MT::Category->load( $obj_cat->category_id );
        push @$cats, $cat;
    }
    return '' unless $cats && @$cats;
    my $builder = $ctx->stash('builder');
    my $tokens  = $ctx->stash('tokens');
    my $res     = '';
    my $glue    = $args->{glue};
    local $ctx->{inside_mt_categories} = 1;

    my $i = 1;
    my $vars = $ctx->{__stash}{vars} ||= {};
    for my $cat (@$cats) {
        local $ctx->{__stash}->{category} = $cat;
        local $vars->{__first__}          = $i == 1;
        local $vars->{__last__}           = $i == scalar @$cats;
        local $vars->{__odd__}            = ( $i % 2 ) == 1;
        local $vars->{__even__}           = ( $i % 2 ) == 0;
        local $vars->{__counter__}        = $i;
        $i++;
        defined( my $out = $builder->build( $ctx, $tokens, $cond ) )
            or return $ctx->error( $builder->errstr );
        $res .= $glue if defined $glue && length($res) && length($out);
        $res .= $out;
    }
    $res;
}

=head2 ContentID

Outputs the numeric ID for the current content in text.

B<Attributes:>

=over 4

=item * pad (optional; default "0")

Adds leading zeros to create a 6 character string. The default is 0 (false). This is equivalent to using the C<zero_pad> global filter with a value of 6.

=back

=cut

sub _hdlr_content_id {
    _check_and_invoke( 'entryid', @_ );
}

=head2 ContentCreatedDate

Outputs the creation date of the current content in context.
See the L<Date> tag for supported attributes.

=for tags date

=cut

sub _hdlr_content_created_date {
    _check_and_invoke( 'entrycreateddate', @_ );
}

=head2 ContentModifiedDate

Outputs the modification date of the current content in context.
See the L<Date> tag for supported attributes.

=for tags date

=cut

sub _hdlr_content_modified_date {
    _check_and_invoke( 'entrymodifieddate', @_ );
}

=head2 ContentUnpublishedDate

Outputs the unpublishing date of the current content in context.
See the L<Date> tag for supported attributes.

=for tags date

=cut

sub _hdlr_content_unpublished_date {
    my ( $ctx, $args, $cond ) = @_;
    my $cd = $ctx->stash('content')
        or return $ctx->_no_content_error();
    $args->{ts} = $cd->unpublished_on or return '';
    return $ctx->build_date($args);
}

=head2 ContentDate

Outputs the 'authored' date of the current content in context.
See the L<Date> tag for supported attributes.

=for tags date

=cut

sub _hdlr_content_date {
    _check_and_invoke( 'entrydate', @_ );
}

=head2 ContentStatus

Intended for application template use only. Displays the status of the
content in context. This will output one of "Draft", "Publish", "Review"
or "Future".

=cut

sub _hdlr_content_status {
    _check_and_invoke( 'entrystatus', @_ );
}

=head2 ContentTitle

Outputs the title of the current content in context.

=cut

sub _hdlr_content_title {
    my ( $ctx, $args, $cond ) = @_;
    my $cd = $ctx->stash('content')
        or return $ctx->_no_content_error();
    defined $cd->title ? $cd->title : '';
}

=head2 ContentAuthorDisplayName

Outputs the display name of the author for the current content in context.
If the author has not provided a display name for publishing, this tag
will output an empty string.

=cut

sub _hdlr_content_author_display_name {
    _check_and_invoke( 'entryauthordisplayname', @_ );
}

=head2 ContentAuthorEmail

Outputs the email address of the author for the current content in context.
B<NOTE: it is not recommended to publish e-mail addresses for MT users.>

B<Attributes:>

=over 4

=item * spam_protect (optional; default "0")

If specified, this will apply a light obfuscation of the email address,
by encoding any characters that will identify it as an email address
(C<:>, C<@>, and C<.>) into HTML entities.

=back

=cut

sub _hdlr_content_author_email {
    _check_and_invoke( 'entryauthoremail', @_ );
}

=head2 ContentAuthorID

Outputs the numeric ID of the author for the current content in context.

=cut

sub _hdlr_content_author_id {
    _check_and_invoke( 'entryauthorid', @_ );
}

=head2 ContentAuthorLink

Outputs a linked author name suitable for publishing in the 'byline'
of a content.

B<Attributes:>

=over 4

=item * new_window

If specified, the published link is given a C<target> attribute of '_blank'.

=item * show_email (optional; default "0")

If set, will allow publishing of an email address if the URL field
for the author is empty.

=item * spam_protect (optional)

If specified, this will apply a light obfuscation of any email address
published, by encoding any characters that will identify it as an email
address (C<:>, C<@>, and C<.>) into HTML entities.

=item * type (optional)

Accepted values: C<url>, C<email>, C<archive>. Note: an 'archive' type
requires publishing of "Author" archives.

=item * show_hcard (optional; default "0")

If present, adds additional CSS class names to the link tag published,
identifying the link as a url or email address depending on the type of
link published.

=back

=cut

sub _hdlr_content_author_link {
    _check_and_invoke( 'entryauthorlink', @_ );
}

=head2 ContentAuthorURL

Outputs the Site URL field from the author's profile for the
current content in context.

=cut

sub _hdlr_content_author_url {
    _check_and_invoke( 'entryauthorurl', @_ );
}

=head2 ContentAuthorUsername

Outputs the username of the author for the content currently in context.
B<NOTE: it is not recommended to publish MT usernames.>

=cut

sub _hdlr_content_author_username {
    _check_and_invoke( 'entryauthorusername', @_ );
}

=head2 ContentAuthorUserpic

Outputs the HTML for the userpic of the author for the current content
in context.

=cut

sub _hdlr_content_author_userpic {
    _check_and_invoke( 'entryauthoruserpic', @_ );
}

=head2 ContentAuthorUserpicURL

Outputs the URL for the userpic image of the author for the current content
in context.

=cut

sub _hdlr_content_author_userpic_url {
    _check_and_invoke( 'entryauthoruserpicurl', @_ );
}

=head2 ContentSiteDescription

Returns the site description of the site to which the content in context
belongs. The site description is set in the General Site Settings.

B<Example:>

    <$mt:ContentSiteDescription$>

=for tags sites, contents

=cut

sub _hdlr_content_site_description {
    _check_and_invoke( 'entryblogdescription', @_ );
}

=head2 ContentSiteID

The numeric system ID of the site that is parent to the content currently
in context.

B<Example:>

    <$mt:ContentSiteID$>

=for tags contents, sites

=cut

sub _hdlr_content_site_id {
    _check_and_invoke( 'entryblogid', @_ );
}

=head2 ContentSiteName

Returns the site name of the site to which the content in context belongs.
The site name is set in the General Site Settings.

B<Example:>

    <$mt:ContentSiteName$>

=for tags contents, sites

=cut

sub _hdlr_content_site_name {
    _check_and_invoke( 'entryblogname', @_ );
}

=head2 ContentSiteURL

Returns the site URL for the site to which the content in context belongs.

B<Example:>

    <$mt:ContentSiteURL$>

=for tags sites, contents

=cut

sub _hdlr_content_site_url {
    _check_and_invoke( 'entryblogurl', @_ );
}

=head2 ContentAuthorUserpicAsset

A block tag providing an asset context for the userpic of the
author for the current content in context. See the L<Assets> tag
for more information about publishing assets.

=cut

sub _hdlr_content_author_userpic_asset {
    my ( $ctx, $args, $cond ) = @_;
    my $cd = $ctx->stash('content')
        or return $ctx->_no_content_error();
    my $author = $cd->author;
    return '' unless $author;

    my $asset = $author->userpic or return '';

    my $tok     = $ctx->stash('tokens');
    my $builder = $ctx->stash('builder');

    local $ctx->{__stash}{asset} = $asset;
    return $builder->build( $ctx, $tok, {%$cond} );
}

=head2 ContentUniqueID

Outputs the unique_id field for the current content in context.

=cut

sub _hdlr_content_unique_id {
    my ( $ctx, $args, $cond ) = @_;
    my $cd = $ctx->stash('content')
        or return $ctx->_no_content_error();
    $cd->unique_id;
}

=head2 ContentIdentifier

Outputs the identifier field for the current content in context.

B<Attributes:>

=over 4

=item * separator (optional)

Accepts either "-" or "_". If unspecified, the raw basename value is
returned.

=back

=cut

sub _hdlr_content_identifier {
    my ( $ctx, $args, $cond ) = @_;
    my $cd = $ctx->stash('content')
        or return $ctx->_no_content_error();
    my $identifier = $cd->identifier;
    $identifier = '' unless defined $identifier;
    if ( my $sep = $args->{separator} ) {
        if ( $sep eq '-' ) {
            $identifier =~ s/_/-/g;
        }
        elsif ( $sep eq '_' ) {
            $identifier =~ s/-/_/g;
        }
    }
    $identifier;
}

=head2 ContentsCount

Returns the count of a list of contents that are currently in context
(ie: used in an archive template, or inside an L<Contents> tag). If no
content list context exists, it will fallback to the list that would be
selected for a generic L<Contents> tag (respecting number of days or
entries configured to publish on the blog's main index template).

=for tags count

=cut

sub _hdlr_contents_count {
    my ( $ctx, $args, $cond ) = @_;

    my $count = 0;

    my $contents = $ctx->stash('contents');
    if ($contents) {
        $count = scalar @{$contents};
    }
    else {
        my $by = $args->{by_modified_on} ? 'modified_on' : 'authored_on';

        my %terms = (
            blog_id => $ctx->stash('blog_id'),
            status  => MT::Entry::RELEASE(),
        );
        my %args = (
            sort      => $by,
            direction => 'descend',
        );

        $ctx->set_content_type_load_context( $args, $cond, \%terms, \%args )
            or return;

        my ( $days, $limit );
        my $blog = $ctx->stash('blog');
        if ( $blog && ( $days = $blog->days_on_index ) ) {
            my @ago = MT::Util::offset_time_list( time - 3600 * 24 * $days,
                $ctx->stash('blog_id') );
            my $ago = sprintf "%04d%02d%02d%02d%02d%02d",
                $ago[5] + 1900, $ago[4] + 1, @ago[ 3, 2, 1, 0 ];
            $terms{$by} = [$ago];
            $args{range_incl}{$by} = 1;
        }
        elsif ( $blog && ( $limit = $blog->entries_on_index ) ) {
            $args->{lastn} = $limit;
        }

        my $iter = MT::ContentData->load_iter( \%terms, \%args );
        my $last = $args->{lastn};
        while ( my $cd = $iter->() ) {
            return $count if $last && $last <= $count;
            $count++;
        }
    }

    $ctx->count_format( $count, $args );
}

=head2 SiteContentCount

Returns the number of published contents associated with the site
currently in context.

=for tags multiblog, count, sites, contents

=cut

sub _hdlr_site_content_count {
    my ( $ctx, $args, $cond ) = @_;
    my ( %terms, %args );
    $ctx->set_blog_load_context( $args, \%terms, \%args )
        or return $ctx->error( $ctx->errstr );
    $ctx->set_content_type_load_context( $args, $cond, \%terms, \%args )
        or return;
    $terms{status} = MT::Entry::RELEASE();
    my $count = MT::ContentData->count( \%terms, \%args );
    return $ctx->count_format( $count, $args );
}

=head2 AuthorContentCount

Returns the number of published contents associated with the author
currently in context.

=for tags authors

=cut

sub _hdlr_author_content_count {
    my ( $ctx, $args, $cond ) = @_;
    my $author = $ctx->stash('author');
    unless ($author) {
        my $cd = $ctx->stash('content');
        $author = $cd->author if $cd;
    }
    return $ctx->_no_author_error() unless $author;

    my ( %terms, %args );
    $ctx->set_blog_load_context( $args, \%terms, \%args )
        or return $ctx->error( $ctx->errstr );
    $ctx->set_content_type_load_context( $args, $cond, \%terms, \%args )
        or return;
    $terms{author_id} = $author->id;
    $terms{status}    = MT::Entry::RELEASE();
    my $count = MT::ContentData->count( \%terms, \%args );
    return $ctx->count_format( $count, $args );
}

=head2 ContentPermalink

TODO: This tag has not been implemented yet.

=cut

sub _hdlr_content_permalink {
}

=head2 AuthorHasContent

A conditional tag that is true when the author currently in context
has written one or more contents that have been published.

=for tags authors, contents

=cut

sub _hdlr_author_has_content {
    my ( $ctx, $args, $cond ) = @_;
    my $author = $ctx->stash('author')
        or return $ctx->_no_author_error();

    my %terms;
    $terms{blog_id}   = $ctx->stash('blog_id');
    $terms{author_id} = $author->id;
    $terms{status}    = MT::Entry::RELEASE();

    $ctx->set_content_type_load_context( $args, $cond, \%terms ) or return;

    MT::ContentData->exist( \%terms );
}

=head2 ContentNext

A block tag providing a context for the content immediately following the
current content in context (in terms of authored date).

=cut

sub _hdlr_content_next {
    _hdlr_content_nextprev( 'next', @_ );
}

=head2 ContentPrevious

A block tag providing a context for the content immediately preceding the
current content in context (in terms of authored date).

=cut

sub _hdlr_content_previous {
    _hdlr_content_nextprev( 'previous', @_ );
}

=head2 ContentCalendar

A container tag representing a calendar month that lists a single
calendar "cell" in the calendar display for content.

=for tags calendar

=cut

=head2 CalendarIfContents

A conditional tag that will display its contents if there are any
contents for this day in the site.

=for tags contentcalendar, contents

=cut

=head2 CalendarIfNoContents

A conditional tag that will display its contents if there are not contents
for this day in the site. This tag predates the introduction of L<Else>,
a tag that could be used with L<CalendarIfContents> to replace
C<CalendarIfNoContents>.

=for tags contentcalendar, contents

=cut

sub _hdlr_content_calendar {
    my ( $ctx, $args, $cond ) = @_;
    my $blog_id = $ctx->stash('blog_id');
    my ($prefix);
    my @ts = MT::Util::offset_time_list( time, $blog_id );
    my $today = sprintf "%04d%02d", $ts[5] + 1900, $ts[4] + 1;
    my $start_with_offset = 0;
    if ( my $start_with = lc( $args->{weeks_start_with} || '' ) ) {
        $start_with_offset = {
            sun => 0,
            mon => 6,
            tue => 5,
            wed => 4,
            thu => 3,
            fri => 2,
            sat => 1,
        }->{ substr( $start_with, 0, 3 ) };

        if ( !defined($start_with_offset) ) {
            return $ctx->error(
                MT->translate(
                    "Invalid weeks_start_with format: must be Sun|Mon|Tue|Wed|Thu|Fri|Sat"
                )
            );
        }
    }
    if ( $prefix = lc( $args->{month} || '' ) ) {
        if ( $prefix eq 'this' ) {
            my $ts = $ctx->{current_timestamp};
            if ( not $ts and ( my $cd = $ctx->stash('content') ) ) {
                $ts = $cd->authored_on();
            }
            if ( not $ts ) {
                return $ctx->error(
                    MT->translate(
                        "You used an [_1] tag without a date context set up.",
                        qq(<MTContentCalendar month="this">)
                    )
                );
            }
            $prefix = substr $ts, 0, 6;
        }
        elsif ( $prefix eq 'last' ) {
            my $year  = substr $today, 0, 4;
            my $month = substr $today, 4, 2;
            if ( $month - 1 == 0 ) {
                $prefix = $year - 1 . "12";
            }
            else {
                $prefix = $year . $month - 1;
            }
        }
        else {
            return $ctx->error(
                MT->translate("Invalid month format: must be YYYYMM") )
                unless length($prefix) eq 6;
        }
    }
    else {
        $prefix = $today;
    }
    my ( $cat_name, $cat );
    if ( defined $args->{category} ) {
        $cat_name = $args->{category};
        my $category_list_id = $args->{category_list_id};
        $cat = MT::Category->load(
            {   label   => $cat_name,
                blog_id => $blog_id,
                $category_list_id
                ? ( category_list_id => $category_list_id )
                : (),
            }
            )
            or return $ctx->error(
            MT->translate( "No such category '[_1]'", $cat_name ) );
    }
    else {
        $cat_name = '';    ## For looking up cached calendars.
    }
    my $uncompiled     = $ctx->stash('uncompiled') || '';
    my $r              = MT::Request->instance;
    my $calendar_cache = $r->cache('content_calendar');
    unless ($calendar_cache) {
        $r->cache( 'content_calendar', $calendar_cache = {} );
    }
    if ( exists $calendar_cache->{ $blog_id . ":" . $prefix . $cat_name }
        && $calendar_cache->{ $blog_id . ":" . $prefix . $cat_name }{'uc'} eq
        $uncompiled )
    {
        return $calendar_cache->{ $blog_id . ":" . $prefix . $cat_name }
            {output};
    }
    $today .= sprintf "%02d", $ts[3];
    my ( $start, $end ) = MT::Util::start_end_month($prefix);
    my ( $y, $m ) = unpack 'A4A2', $prefix;
    my $days_in_month = MT::Util::days_in( $m, $y );
    my $pad_start
        = ( MT::Util::wday_from_ts( $y, $m, 1 ) + $start_with_offset ) % 7;
    my $pad_end = 6 - (
        (   MT::Util::wday_from_ts( $y, $m, $days_in_month )
                + $start_with_offset
        ) % 7
    );
    my $cd_terms = {};
    my $cd_args  = {};
    $ctx->set_content_type_load_context( $args, $cond, $cd_terms, $cd_args )
        or return;
    my $iter = MT::ContentData->load_iter(
        {   blog_id     => $blog_id,
            authored_on => [ $start, $end ],
            status      => MT::Entry::RELEASE(),
            %{$cd_terms},
        },
        {   range_incl => { authored_on => 1 },
            'sort'     => 'authored_on',
            direction  => 'ascend',
            %{$cd_args},
        }
    );
    my @left;
    my $res          = '';
    my $tokens       = $ctx->stash('tokens');
    my $builder      = $ctx->stash('builder');
    my $iter_drained = 0;

    for my $day ( 1 .. $pad_start + $days_in_month + $pad_end ) {
        my $is_padding = $day < $pad_start + 1
            || $day > $pad_start + $days_in_month;
        my ( $this_day, @cds ) = ('');
        local (
            $ctx->{__stash}{contents}, $ctx->{__stash}{calendar_day},
            $ctx->{current_timestamp}, $ctx->{current_timestamp_end}
        );
        local $ctx->{__stash}{calendar_cell} = $day;
        unless ($is_padding) {
            $this_day = $prefix . sprintf( "%02d", $day - $pad_start );
            my $no_loop = 0;
            if (@left) {
                if ( substr( $left[0]->authored_on, 0, 8 ) eq $this_day ) {
                    @cds  = @left;
                    @left = ();
                }
                else {
                    $no_loop = 1;
                }
            }
            unless ( $no_loop || $iter_drained ) {
                while ( my $cd = $iter->() ) {
                    next unless !$cat || $cd->is_in_category($cat);
                    my $cd_day = substr $cd->authored_on, 0, 8;
                    push( @left, $cd ), last
                        unless $cd_day eq $this_day;
                    push @cds, $cd;
                }
                $iter_drained++ unless @left;
            }
            $ctx->{__stash}{contents}     = \@cds;
            $ctx->{current_timestamp}     = $this_day . '000000';
            $ctx->{current_timestamp_end} = $this_day . '235959';
            $ctx->{__stash}{calendar_day} = $day - $pad_start;
        }
        defined(
            my $out = $builder->build(
                $ctx, $tokens,
                {   %$cond,
                    CalendarWeekHeader   => ( $day - 1 ) % 7 == 0,
                    CalendarWeekFooter   => $day % 7 == 0,
                    CalendarIfContents   => !$is_padding && scalar @cds,
                    CalendarIfNoContents => !$is_padding && !( scalar @cds ),
                    CalendarIfToday      => ( $today eq $this_day ),
                    CalendarIfBlank      => $is_padding,
                }
            )
        ) or return $ctx->error( $builder->errstr );
        $res .= $out;
    }
    $calendar_cache->{ $blog_id . ":" . $prefix . $cat_name }
        = { output => $res, 'uc' => $uncompiled };
    return $res;
}

sub _hdlr_content_nextprev {
    my ( $meth, $ctx, $args, $cond ) = @_;
    my $cd = $ctx->stash('content')
        or return $ctx->_no_content_error();
    my $terms = { status => MT::Entry::RELEASE() };
    $terms->{by_author} = 1 if $args->{by_author};
    if ( $args->{by_category} ) {
        if ( $args->{content_field_id} || $args->{category_id} ) {
            $terms->{by_category} = {};
            if ( $args->{content_field_id} ) {
                $terms->{by_category}{content_field_id}
                    = $args->{content_field_id};
            }
            if ( $args->{category_id} ) {
                $terms->{by_category}{category_id} = $args->{category_id};
            }
        }
        else {
            $terms->{by_category} = 1;
        }
    }
    $terms->{by_modified_on} = 1 if $args->{by_modified_on};
    my $content_data = $cd->$meth($terms);
    my $res          = '';
    if ($content_data) {
        my $builder = $ctx->stash('builder');
        local $ctx->{__stash}->{content} = $content_data;
        local $ctx->{current_timestamp} = $content_data->authored_on;
        my $out = $builder->build( $ctx, $ctx->stash('tokens'), $cond );
        return $ctx->error( $builder->errstr ) unless defined $out;
        $res .= $out;
    }
    $res;
}

=head2 ContentField

A container tag that lists all of the field values which the content field has.

=cut

sub _hdlr_content_field {
    my ( $ctx, $args, $cond ) = @_;

    my $content_type = $ctx->stash('content_type')
        or return $ctx->_no_content_type_error;

    my $field_data;
    if ( my $unique_id = $args->{unique_id} ) {
        ($field_data)
            = grep { $_->{unique_id} eq $unique_id }
            @{ $content_type->fields };
    }
    elsif ( my $content_field_id = $args->{content_field_id} ) {
        ($field_data)
            = grep { $_->{id} == $content_field_id }
            @{ $content_type->fields };
    }
    elsif ( defined( my $label = $args->{label} ) ) {
        ($field_data)
            = grep { $_->{options}{label} eq $label }
            @{ $content_type->fields };
    }
    $field_data ||= $ctx->stash('content_field') || $content_type->fields->[0]
        or return $ctx->_no_content_field_error;

    my $content_data = $ctx->stash('content')
        or return $ctx->_no_content_error;
    my $value = $content_data->data->{ $field_data->{id} };

    my $field_type
        = MT->registry('content_field_types')->{ $field_data->{type} }
        or return $ctx->error(
        MT->translate('No Content Field Type could be found.') );

    if ( my $tag_handler = $field_type->{tag_handler} ) {
        if ( !ref $tag_handler ) {
            $tag_handler = MT->handler_to_coderef($tag_handler);
        }
        return $ctx->error(
            MT->translate(
                'Invalid tag_handler of [_1].',
                $field_data->{type}
            )
        ) unless ref $tag_handler eq 'CODE';
        $tag_handler->( $ctx, $args, $cond, $field_data, $value );
    }
    else {
        my $tok     = $ctx->stash('tokens');
        my $builder = $ctx->stash('builder');
        my $vars    = $ctx->{__stash}{vars} ||= {};
        local $vars->{__value__} = $value;
        $builder->build( $ctx, $tok, {%$cond} );
    }
}

=head2 ContentFields

A container tag that lists all of the fields which the content has.
This tagset creates a content_field context within which contentfield tag
may be used.

=cut

sub _hdlr_content_fields {
    my ( $ctx, $args, $cond ) = @_;

    my $content_type = $ctx->stash('content_type')
        or return $ctx->_no_content_type_error;

    my @field_data = @{ $content_type->fields };
    my $builder    = $ctx->stash('builder');
    my $tokens     = $ctx->stash('tokens');
    my $vars       = $ctx->{__stash}{vars} ||= {};
    my $i          = 1;
    my $res        = '';
    for my $f (@field_data) {
        local $vars->{__first__}   = $i == 1;
        local $vars->{__last__}    = $i == scalar @field_data;
        local $vars->{__odd__}     = ( $i % 2 ) == 1;
        local $vars->{__even__}    = ( $i % 2 ) == 0;
        local $vars->{__counter__} = $i;
        $i++;

        local $ctx->{__stash}{content_field} = $f;

        local $vars->{content_field_id}        = $f->{id};
        local $vars->{content_field_unique_id} = $f->{unique_id};
        local $vars->{content_field_type}      = $f->{type};
        local $vars->{content_field_order}     = $f->{order};
        local $vars->{content_field_options}   = $f->{options};

        my $out = $builder->build( $ctx, $tokens, {%$cond} );
        return $ctx->error( $builder->errstr ) unless defined $out;

        $res .= $out;
    }

    $res;
}

sub _check_and_invoke {
    my ( $tag, $ctx, $args, $cond ) = @_;
    my $cd = $ctx->stash('content')
        or return $ctx->_no_content_error();
    local $ctx->{__stash}{entry} = $cd;
    $ctx->invoke_handler( $tag, $args, $cond );
}

1;