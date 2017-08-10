package MT::ContentFieldType::MultiLineText;
use strict;
use warnings;

use JSON ();

sub theme_data_import_handler {
    my ( $theme, $blog, $ct, $cf_type, $field, $field_data, $data,
        $convert_breaks )
        = @_;

    if ( ref $field_data eq 'HASH' ) {
        $convert_breaks->{ $field->{id} } = $field_data->{convert_breaks};
    }
}

sub data_getter {
    my ( $app, $field_data ) = @_;
    my $field_id  = $field_data->{id};
    my $data_json = $app->param('blockeditor-data');
    my $data_obj;
    my $html = "";
    my @blockdatas;
    if ($data_json) {
        $data_obj = JSON->new->utf8(0)->decode($data_json);
        my $editor_id = 'editor-input-content-field-' . $field_id;
        while ( my ( $block_id, $block_data )
            = each( %{ $data_obj->{$editor_id} } ) )
        {
            push( @blockdatas, $block_data );
        }
        @blockdatas = sort { $a->{order} <=> $b->{order} } @blockdatas;
        foreach my $val (@blockdatas) {
            $html .= $val->{html};
        }
    }
    return $html;
}

1;

