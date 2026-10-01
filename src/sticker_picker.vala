namespace Dc {

    /** Static first-frame thumbnail for a sticker file, at most size×size
        logical pixels (kept at device resolution on HiDPI displays). */
    public Gtk.Widget sticker_thumbnail (string path, int scale_factor,
                                         int size) {
        if (path.down ().has_suffix (".webm")) {
            /* Not played, so the paintable stays on the first frame and
               is already silent. Never set muted here: GtkMediaStream
               muting is persisted per-app by WirePlumber and would come
               back to silence voice-message playback. */
            var media = Gtk.MediaFile.for_filename (path);
            return sticker_thumb_picture (media, size);
        }
        try {
            var frame = scaled_frame_from_file (path, size * scale_factor);
            return sticker_thumb_picture (texture_from_pixbuf (frame), size);
        } catch (Error e) {
            var icon = new Gtk.Image.from_icon_name (
                "image-x-generic-symbolic");
            icon.pixel_size = 32;
            icon.set_size_request (size, size);
            return icon;
        }
    }

    private Gtk.Picture sticker_thumb_picture (Gdk.Paintable paintable,
                                               int size) {
        var picture = new Gtk.Picture.for_paintable (paintable);
        picture.content_fit = Gtk.ContentFit.CONTAIN;
        picture.set_size_request (size, size);
        return picture;
    }

    /**
     * Floating sticker picker for the compose bar, shaped like the emoji
     * picker: an arrowed popover holding a scrolling pane of stickers,
     * four per row, each pack under a small named separator. The bottom
     * bar filters by the emoji associated with the stickers and scrolls
     * horizontally when the emojis do not fit.
     */
    public class StickerPicker : Gtk.Popover {

        private const int THUMB_SIZE = 64;
        private const int COLUMNS = 4;

        public signal void sticker_picked (Sticker sticker);

        private Gtk.Box sections;
        private Gtk.Label placeholder;
        private Gtk.Box filter_bar;
        private Gtk.Box footer;
        private string filter_emoji = "";
        private Sticker[] stickers = {};

        public StickerPicker () {
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            placeholder = new Gtk.Label (
                _("No stickers yet.\nRight-click a sticker in a conversation\n"
                  + "and choose “Add Sticker…”."));
            placeholder.add_css_class ("dim-label");
            placeholder.justify = Gtk.Justification.CENTER;
            placeholder.margin_top = 24;
            placeholder.margin_bottom = 24;
            placeholder.margin_start = 12;
            placeholder.margin_end = 12;

            sections = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            sections.margin_start = 8;
            sections.margin_end = 8;
            sections.margin_top = 8;
            sections.margin_bottom = 8;

            var pane = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            pane.append (placeholder);
            pane.append (sections);

            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.min_content_height = 320;
            scroll.max_content_height = 320;
            scroll.min_content_width = 336;
            scroll.max_content_width = 336;
            scroll.vexpand = true;
            scroll.child = pane;
            content.append (scroll);

            filter_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            filter_bar.margin_start = 4;
            filter_bar.margin_end = 4;
            filter_bar.margin_top = 4;
            filter_bar.margin_bottom = 4;

            var filter_scroll = new Gtk.ScrolledWindow ();
            filter_scroll.vscrollbar_policy = Gtk.PolicyType.NEVER;
            filter_scroll.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            filter_scroll.hexpand = true;
            filter_scroll.child = filter_bar;

            footer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            footer.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            footer.append (filter_scroll);
            content.append (footer);

            this.child = content;
            /* The store can change behind the popover (manager dialog,
               "Add Sticker…"), so rebuild on every open. */
            this.notify["visible"].connect (() => {
                if (visible) reload ();
            });
        }

        private void reload () {
            stickers = {};
            foreach (string pack in StickerStore.list_packs ()) {
                foreach (Sticker s in StickerStore.list_stickers (pack)) {
                    stickers += s;
                }
            }
            filter_emoji = "";
            rebuild_filter_bar ();
            populate ();
        }

        private void rebuild_filter_bar () {
            clear_box (filter_bar);

            string[] emojis = {};
            foreach (Sticker s in stickers) {
                if (s.emoji.length == 0) continue;
                bool known = false;
                foreach (string e in emojis) {
                    if (e == s.emoji) known = true;
                }
                if (!known) emojis += s.emoji;
            }
            footer.visible = emojis.length > 0;
            if (emojis.length == 0) return;

            var all_btn = new Gtk.ToggleButton ();
            all_btn.icon_name = "view-grid-symbolic";
            all_btn.tooltip_text = _("All stickers");
            all_btn.add_css_class ("flat");
            all_btn.active = true;
            all_btn.toggled.connect (() => {
                if (all_btn.active) set_filter ("");
            });
            filter_bar.append (all_btn);

            foreach (string emoji in emojis) {
                var btn = new Gtk.ToggleButton.with_label (emoji);
                btn.add_css_class ("flat");
                btn.set_group (all_btn);
                string wanted = emoji;
                btn.toggled.connect (() => {
                    if (btn.active) set_filter (wanted);
                });
                filter_bar.append (btn);
            }
        }

        private void set_filter (string emoji) {
            if (filter_emoji == emoji) return;
            filter_emoji = emoji;
            populate ();
        }

        private void populate () {
            clear_box (sections);

            bool any = false;
            string? pack = null;
            Gtk.FlowBox? grid = null;
            foreach (Sticker sticker in stickers) {
                if (filter_emoji.length > 0
                    && sticker.emoji != filter_emoji) {
                    continue;
                }
                any = true;
                if (pack == null || pack != sticker.pack) {
                    pack = sticker.pack;
                    sections.append (pack_header (pack));
                    grid = new_sticker_grid ();
                    sections.append (grid);
                }
                grid.append (sticker_button (sticker));
            }
            placeholder.visible = !any;
        }

        private static Gtk.Widget pack_header (string pack) {
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var label = new Gtk.Label (pack);
            label.add_css_class ("dim-label");
            label.add_css_class ("caption-heading");
            label.halign = Gtk.Align.START;
            header.append (label);
            var line = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
            line.hexpand = true;
            line.valign = Gtk.Align.CENTER;
            header.append (line);
            return header;
        }

        private static Gtk.FlowBox new_sticker_grid () {
            var grid = new Gtk.FlowBox ();
            grid.selection_mode = Gtk.SelectionMode.NONE;
            grid.min_children_per_line = COLUMNS;
            grid.max_children_per_line = COLUMNS;
            grid.homogeneous = true;
            grid.column_spacing = 4;
            grid.row_spacing = 4;
            grid.valign = Gtk.Align.START;
            return grid;
        }

        private Gtk.Widget sticker_button (Sticker sticker) {
            var btn = new Gtk.Button ();
            btn.add_css_class ("flat");
            btn.tooltip_text = sticker.emoji.length > 0
                ? "%s %s".printf (sticker.emoji, sticker.display_name)
                : sticker.display_name;
            btn.child = sticker_thumbnail (
                StickerStore.sticker_path (sticker.file_name),
                int.max (1, this.get_scale_factor ()), THUMB_SIZE);
            btn.clicked.connect (() => {
                popdown ();
                sticker_picked (sticker);
            });
            return btn;
        }

        private static void clear_box (Gtk.Box box) {
            Gtk.Widget? child;
            while ((child = box.get_first_child ()) != null) {
                box.remove (child);
            }
        }
    }
}
