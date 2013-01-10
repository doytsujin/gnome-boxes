// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.FedoraInstaller: UnattendedInstaller {
    public const string PRE_F18_PACKAGES = "@base\n" +
                                           "@core\n" +
                                           "@hardware-support\n" +
                                           "@base-x\n" +
                                           "@gnome-desktop\n" +
                                           "@graphical-internet\n" +
                                           "@sound-and-video";
    public const string F18_PACKAGES = "@standard\n" +
                                       "@core\n" +
                                       "@hardware-support\n" +
                                       "@base-x\n" +
                                       "@gnome-desktop\n" +
                                       "@epiphany\n" +
                                       "@firefox\n" +
                                       "@multimedia";

    private File kernel_file;
    private File initrd_file;

    private string kbd;

    private static Regex kbd_regex;
    private static Regex packages_regex;

    static construct {
        try {
            kbd_regex = new Regex ("BOXES_FEDORA_KBD");
            packages_regex = new Regex ("BOXES_FEDORA_PACKAGES");
        } catch (RegexError error) {
            // This just can't fail
            assert_not_reached ();
        }
    }

    public FedoraInstaller.from_media (InstallerMedia media) throws GLib.Error {
        var source_path = get_unattended ("fedora.ks");

        base.from_media (media, source_path, "ks.cfg");

        kbd = fetch_console_kbd_layout ();
    }

    public override void set_direct_boot_params (GVirConfig.DomainOs os) {
        if (kernel_file == null || initrd_file == null)
            return;

        os.set_kernel (kernel_file.get_path ());
        os.set_ramdisk (initrd_file.get_path ());
        os.set_cmdline ("ks=hd:sda:/ks.cfg");
    }

    public override async void prepare_for_installation (string vm_name, Cancellable? cancellable) throws GLib.Error {
        yield base.prepare_for_installation (vm_name, cancellable);

        if (!express_toggle.active)
            return;

        if (os_media.kernel_path == null || os_media.initrd_path == null)
            return;

        var extractor = new ISOExtractor (device_file);

        yield extractor.mount_media (cancellable);

        yield extract_boot_files (extractor, cancellable);
    }

    protected override void clean_up () throws GLib.Error {
        base.clean_up ();

        if (kernel_file != null) {
            delete_file (kernel_file);
            kernel_file = null;
        }

        if (initrd_file != null) {
            delete_file (initrd_file);
            initrd_file = null;
        }
    }

    protected override string fill_unattended_data (string data) throws RegexError {
        var str = base.fill_unattended_data (data);

        var version = int.parse (os.version);
        if (version < 18)
            str = packages_regex.replace (str, str.length, 0, PRE_F18_PACKAGES);
        else
            str = packages_regex.replace (str, str.length, 0, F18_PACKAGES);

        return kbd_regex.replace (str, str.length, 0, kbd);
    }

    private async void extract_boot_files (ISOExtractor extractor, Cancellable? cancellable) throws GLib.Error {
        string src_path = extractor.get_absolute_path (os_media.kernel_path);
        string dest_path = get_user_unattended ("kernel");
        kernel_file = yield copy_file (src_path, dest_path, cancellable);

        src_path = extractor.get_absolute_path (os_media.initrd_path);
        dest_path = get_user_unattended ("initrd");
        initrd_file = yield copy_file (src_path, dest_path, cancellable);
    }

    private async File copy_file (string src_path, string dest_path, Cancellable? cancellable) throws GLib.Error {
        var src_file = File.new_for_path (src_path);
        var dest_file = File.new_for_path (dest_path);

        try {
            debug ("Copying '%s' to '%s'..", src_path, dest_path);
            yield src_file.copy_async (dest_file, 0, Priority.DEFAULT, cancellable);
            debug ("Copied '%s' to '%s'.", src_path, dest_path);
        } catch (IOError.EXISTS error) {}

        return dest_file;
    }

    private struct KbdLayout {
        public string xkb_layout;
        public string xkb_variant;
        public string console_layout;
    }

    private string fetch_console_kbd_layout () {
        string method = null;
        string layout_str = null;

        // Don't crash if the schema is not installed
        var schemas = GLib.Settings.list_schemas ();
        foreach (var s in schemas) {
            if (s == "org.gnome.desktop.input-sources") {
                var settings = new GLib.Settings (s);
                Variant sources = settings.get_value ("sources");
                uint current = settings.get_uint ("current");
                if (current > sources.n_children ())
                    current = 0;

                if (sources.n_children () > 0)
                    sources.get_child (current, "(ss)", out method, out layout_str);
                break;
            }
        }

        if (method != "xkb" || layout_str == null) {
            warning ("Failed to fetch prefered keyboard layout from user settings, falling back to 'us'..");

            return "us";
        }
        var tokens = layout_str.split("+");
        var xkb_layout = tokens[0];
        var xkb_variant = tokens[1];
        var console_layout = (string) null;

        for (var i = 0; i < kbd_layouts.length; i++)
            if (xkb_layout == kbd_layouts[i].xkb_layout)
                if (xkb_variant == kbd_layouts[i].xkb_variant) {
                    console_layout = kbd_layouts[i].console_layout;

                    // Exact match found already, no need to iterate anymore..
                    break;
                } else if (kbd_layouts[i].xkb_variant == null)
                    console_layout = kbd_layouts[i].console_layout;

        if (console_layout == null) {
            debug ("Couldn't find a console layout for X layout '%s', falling back to 'us'..", layout_str);
            console_layout = "us";
        }
        debug ("Using '%s' keyboard layout.", console_layout);

        return console_layout;
    }

    // Modified copy of KeyboardModels._modelDict from system-config-keyboard project:
    // https://fedorahosted.org/system-config-keyboard/
    //
    private const KbdLayout[] kbd_layouts = {
        { "ara", null, "ar-azerty" },
        { "ara", "azerty", "ar-azerty" },
        { "ara", "azerty_digits", "ar-azerty-digits" },
        { "ara", "digits", "ar-digits" },
        { "ara", "qwerty", "ar-qwerty" },
        { "ara", "qwerty_digits", "ar-qwerty-digits" },
        { "be", null, "be-latin1" },
        { "bg", null, "bg_bds-utf8" },
        { "bg", "phonetic", "bg_pho-utf8" },
        { "bg", "bas_phonetic", "bg_pho-utf8" },
        { "br", null, "br-abnt2" },
        { "ca(fr)", null, "cf" },
        { "hr", null, "croat" },
        { "cz", null, "cz-us-qwertz" },
        { "cz", "qwerty", "cz-lat2" },
        { "cz", "", "cz-us-qwertz" },
        { "de", null, "de" },
        { "de", "nodeadkeys", "de-latin1-nodeadkeys" },
        { "dev", null, "dev" },
        { "dk", null, "dk" },
        { "dk", "dvorak", "dk-dvorak" },
        { "es", null, "es" },
        { "ee", null, "et" },
        { "fi", null, "fi" },
        { "fr", null, "fr" },
        { "fr", "latin9", "fr-latin9" },
        { "gr", null, "gr" },
        { "gur", null, "gur" },
        { "hu", null, "hu" },
        { "hu", "qwerty", "hu101" },
        { "ie", null, "ie" },
        { "in", null, "us" },
        { "in", "ben", "ben" },
        { "in", "ben-probhat", "ben_probhat" },
        { "in", "guj", "guj" },
        { "in", "tam", "tml-inscript" },
        { "in", "tam_TAB", "tml-uni" },
        { "is", null, "is-latin1" },
        { "it", null, "it" },
        { "jp", null, "jp106" },
        { "kr", null, "ko" },
        { "latam", null, "la-latin1" },
        { "mkd", null, "mk-utf" },
        { "nl", null, "nl" },
        { "no", null, "no" },
        { "pl", null, "pl2" },
        { "pt", null, "pt-latin1" },
        { "ro", null, "ro" },
        { "ro", "std", "ro-std" },
        { "ro", "cedilla", "ro-cedilla" },
        { "ro", "std_cedilla", "ro-std-cedilla" },
        { "ru", null, "ru" },
        { "rs", null, "sr-cy" },
        { "rs", "latin", "sr-latin"},
        { "se", null, "sv-latin1" },
        { "ch", "de_nodeadkeys", "sg" },
        { "ch", "fr", "fr_CH" },
        { "sk", null, "sk-qwerty" },
        { "si", null, "slovene" },
        { "tj", null, "tj" },
        { "tr", null, "trq" },
        { "gb", null, "uk" },
        { "ua", null, "ua-utf" },
        { "us", null, "us" },
        { "us", "intl", "us-acentos" }
    };
}
