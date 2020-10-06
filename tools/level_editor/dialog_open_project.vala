/*
 * Copyright (c) 2012-2020 Daniele Bartolini and individual contributors.
 * License: https://github.com/dbartolini/crown/blob/master/LICENSE
 */

using Gtk;

namespace Crown
{
	public class DialogOpenProject : Gtk.FileChooserDialog
	{
		public DialogOpenProject(Gtk.Window? parent)
		{
			Object(title: "Open Project..."
				, parent: parent
				, action: FileChooserAction.SELECT_FOLDER
				);

			add_buttons("Cancel"
				, ResponseType.CANCEL
				, "Open"
				, ResponseType.ACCEPT
				);
		}
	}
}
