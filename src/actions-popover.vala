// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.ActionsPopover: Gtk.Popover {
    private const GLib.ActionEntry[] action_entries = {
        {"open-in-new-win", open_in_new_win_activated},
        {"favorite",        favorite_activated},
        {"pause",           pause_activated},
        {"delete",          delete_activated},
        {"properties",      properties_activated}
    };

    private AppWindow window;
    private GLib.SimpleActionGroup action_group;

    public ActionsPopover (AppWindow window) {
        this.window = window;

        action_group = new GLib.SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        this.insert_action_group ("box", action_group);

        var a11y = get_accessible ();
        a11y.role = Atk.Role.POPUP_MENU;
        // Translators: Accessibility name for context menu with box-related actions (e.g Pause, Delete etc)
        a11y.name = _("Box actions");
    }

    public void update_for_item (CollectionItem item) {
        return_if_fail (item is Machine);
        var machine = item as Machine;

        var menu = new GLib.Menu ();

        // Open in new Window
        menu.append (_("Open in new Window"), "box.open-in-new-win");

        // Favorite
        if (("favorite" in machine.config.categories))
            menu.append (_("Remove favorite"), "box.favorite");
        else
            menu.append (_("Favorite"), "box.favorite");

        // Pause
        menu.append (_("Pause"), "box.pause");
        var action = action_group.lookup_action ("pause") as GLib.SimpleAction;
        action.set_enabled (machine.can_save);

        // Delete
        menu.append (_("Delete"), "box.delete");
        action = action_group.lookup_action ("delete") as GLib.SimpleAction;
        action.set_enabled (machine.can_delete);

        // Properties (in separate section)
        var section = new GLib.Menu ();
        section.append (_("Properties"), "box.properties");
        menu.append_section (null, section);

        bind_model (menu, null);
        window.current_item = item;
    }

    private void open_in_new_win_activated () {
        App.app.open_in_new_window (window.current_item as Machine);
    }

    private void favorite_activated () {
        var machine = window.current_item as Machine;
        var enabled = !("favorite" in machine.config.categories);
        machine.config.set_category ("favorite", enabled);
    }

    private void pause_activated () {
        var machine = window.current_item as Machine;

        machine.save.begin ((obj, result) => {
            try {
                machine.save.end (result);
            } catch (GLib.Error e) {
                window.notificationbar.display_error (_("Pausing '%s' failed").printf (machine.name));
            }
        });
    }

    private void delete_activated () {
        window.set_state (UIState.COLLECTION);

        var items = new List<CollectionItem> ();
        items.append (window.current_item);

        App.app.delete_machines_undoable ((owned) items);
    }

    private void properties_activated () {
        window.show_properties ();
    }
}
