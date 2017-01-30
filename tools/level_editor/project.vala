/*
 * Copyright (c) 2012-2017 Daniele Bartolini and individual contributors.
 * License: https://github.com/taylor001/crown/blob/master/LICENSE-GPLv2
 */

using Gtk;
using Gee;

namespace Crown
{
	public class Project
	{
		// Data
		private File _source_dir;
		private File _toolchain_dir;
		private File _data_dir;
		private string _platform;

		private Database _files;

		public signal void changed();

		public Project()
		{
			_source_dir = null;
			_toolchain_dir = null;
			_data_dir = null;
			_platform = "linux";

			_files = new Database();
		}

		public void load(string source_dir, string toolchain_dir, string data_dir)
		{
			_source_dir    = File.new_for_path(source_dir);
			_toolchain_dir = File.new_for_path(toolchain_dir);
			_data_dir      = File.new_for_path(data_dir);

			scan_source_dir();
		}

		public string source_dir()
		{
			return _source_dir.get_path();
		}

		public string toolchain_dir()
		{
			return _toolchain_dir.get_path();
		}

		public string data_dir()
		{
			return _data_dir.get_path();
		}

		public string platform()
		{
			return _platform;
		}

		public Database files()
		{
			return _files;
		}

		public void scan_source_dir()
		{
			_files.reset();
			list_directory_entries(_source_dir);
			changed();
		}

		private void list_directory_entries(File dir, Cancellable? cancellable = null) throws Error
		{
			FileEnumerator enumerator = dir.enumerate_children(GLib.FileAttribute.STANDARD_NAME
				, FileQueryInfoFlags.NOFOLLOW_SYMLINKS
				, cancellable
				);

			FileInfo info = null;
			while (!cancellable.is_cancelled() && ((info = enumerator.next_file (cancellable)) != null))
			{
				if (info.get_file_type () == FileType.DIRECTORY)
				{
					File subdir = dir.resolve_relative_path (info.get_name());
					list_directory_entries(subdir, cancellable);
				}
				else
				{
					string path     = dir.get_path() + "/" + info.get_name();
					string path_rel = _source_dir.get_relative_path(File.new_for_path(path));
					string name     = path_rel.substring(0, path_rel.last_index_of("."));
					string type     = path_rel.substring(path_rel.last_index_of(".") + 1);

					Guid id = Guid.new_guid();
					_files.create(id);
					_files.set_property(id, "path", path);
					_files.set_property(id, "type", type);
					_files.set_property(id, "name", name);
					_files.add_to_set(GUID_ZERO, "data", id);
				}
			}

			if (cancellable.is_cancelled ())
			{
				throw new IOError.CANCELLED("Operation was cancelled");
			}
		}

		public void import_sprites(SList<string> filenames, string destination_dir)
		{
			SpriteImportDialog sid = new SpriteImportDialog(filenames.nth_data(0));

			if (sid.run() != Gtk.ResponseType.OK)
			{
				sid.destroy();
				return;
			}

			int width     = (int)sid._pixbuf.width;
			int height    = (int)sid._pixbuf.height;
			int num_h     = (int)sid.cells_h.value;
			int num_v     = (int)sid.cells_v.value;
			int cell_w    = (int)sid.cell_w.value;
			int cell_h    = (int)sid.cell_h.value;
			int offset_x  = (int)sid.offset_x.value;
			int offset_y  = (int)sid.offset_y.value;
			int spacing_x = (int)sid.spacing_x.value;
			int spacing_y = (int)sid.spacing_y.value;

			Vector2 pivot_xy = sprite_cell_pivot_xy(cell_w, cell_h, sid.pivot.active);

			sid.destroy();

			foreach (unowned string filename_i in filenames)
			{
				GLib.File file_src = File.new_for_path(filename_i);
				GLib.File file_dst = File.new_for_path(destination_dir + "/" + file_src.get_basename());

				string dst_dir_rel    = _source_dir.get_relative_path(File.new_for_path(destination_dir));
				string basename       = file_src.get_basename();
				string basename_noext = basename.substring(0, basename.last_index_of_char('.'));
				string dst_noext      = file_dst.get_path().substring(0, file_dst.get_path().last_index_of_char('.'));

				if (!filename_i.has_suffix(".png"))
					continue;

				Hashtable textures = new Hashtable();
				textures["u_albedo"] = dst_dir_rel + "/" + basename_noext;

				Hashtable uniform = new Hashtable();
				uniform["type"]  = "vector4";
				uniform["value"] = Vector4(1.0, 1.0, 1.0, 1.0).to_array();

				Hashtable uniforms = new Hashtable();
				uniforms["u_color"] = uniform;

				Hashtable material = new Hashtable();
				material["shader"]   = "sprite";
				material["textures"] = textures;
				material["uniforms"] = uniforms;
				SJSON.save(material, dst_noext + ".material");

				file_src.copy(file_dst, FileCopyFlags.OVERWRITE);

				Hashtable texture = new Hashtable();
				texture["source"]        = dst_dir_rel + "/" + basename;
				texture["generate_mips"] = false;
				texture["is_normalmap"]  = false;
				SJSON.save(texture, dst_noext + ".texture");

				Hashtable sprite = new Hashtable();
				sprite["width"]  = width;
				sprite["height"] = height;

				ArrayList<Value?> frames = new ArrayList<Value?>();
				for (int r = 0; r < num_v; ++r)
				{
					for (int c = 0; c < num_h; ++c)
					{
						Vector2 cell_xy = sprite_cell_xy(r
							, c
							, offset_x
							, offset_y
							, cell_w
							, cell_h
							, spacing_x
							, spacing_y
							);

						// Pivot is relative to the top-left corner of the cell
						int x = (int)cell_xy.x;
						int y = (int)cell_xy.y;

						Hashtable data = new Hashtable();
						data["name"]   = "sprite_%d".printf(c+num_h*r);
						data["region"] = Vector4(x, y, cell_w, cell_h).to_array();
						data["pivot"]  = Vector2(x+pivot_xy.x, y+pivot_xy.y).to_array();
						frames.add(data);
					}
				}
				sprite["frames"] = frames;

				SJSON.save(sprite, dst_noext + ".sprite");

				Hashtable data = new Hashtable();
				data["position"] = VECTOR3_ZERO.to_array();
				data["rotation"] = QUATERNION_IDENTITY.to_array();
				data["scale"]    = VECTOR3_ONE.to_array();

				Hashtable comp = new Hashtable();
				comp["data"] = data;
				comp["type"] = "transform";

				Hashtable components = new Hashtable();
				components[Guid.new_guid().to_string()] = comp;

				data = new Hashtable();
				data["material"]        = dst_dir_rel + "/" + basename_noext;
				data["sprite_resource"] = dst_dir_rel + "/" + basename_noext;
				data["visible"]         = true;

				comp = new Hashtable();
				comp["data"] = data;
				comp["type"] = "sprite_renderer";

				components[Guid.new_guid().to_string()] = comp;

				Hashtable unit = new Hashtable();
				unit["components"] = components;

				SJSON.save(unit, dst_noext + ".unit");
			}
		}

		public void import_meshes(SList<string> filenames, string destination_dir)
		{
			foreach (unowned string filename_i in filenames)
			{
				GLib.File file_src = File.new_for_path(filename_i);
				GLib.File file_dst = File.new_for_path(destination_dir + "/" + file_src.get_basename());

				string dst_dir_rel    = _source_dir.get_relative_path(File.new_for_path(destination_dir));
				string basename       = file_src.get_basename();
				string basename_noext = basename.substring(0, basename.last_index_of_char('.'));
				string dst_noext      = file_dst.get_path().substring(0, file_dst.get_path().last_index_of_char('.'));

				if (!filename_i.has_suffix(".mesh"))
					continue;

				// Choose material or create new one
				FileChooserDialog mtl = new FileChooserDialog("Select material... (Cancel to create a new one)"
					, null
					, FileChooserAction.OPEN
					, "Cancel"
					, ResponseType.CANCEL
					, "Select"
					, ResponseType.ACCEPT
					);
				mtl.set_current_folder(_source_dir.get_path());

				FileFilter fltr = new FileFilter();
				fltr.set_filter_name("Material (*.material)");
				fltr.add_pattern("*.material");
				mtl.add_filter(fltr);

				string material_name = dst_dir_rel + "/" + basename_noext;
				if (mtl.run() == (int)ResponseType.ACCEPT)
				{
					material_name = _source_dir.get_relative_path(File.new_for_path(mtl.get_filename()));
					material_name = material_name.substring(0, material_name.last_index_of_char('.'));
				}
				else
				{
					Hashtable material = new Hashtable();
					material["shader"]   = "mesh+DIFFUSE_MAP";
					material["textures"] = new Hashtable();
					material["uniforms"] = new Hashtable();
					SJSON.save(material, dst_noext + ".material");
				}
				mtl.destroy();

				file_src.copy(file_dst, FileCopyFlags.OVERWRITE);

				Hashtable data = new Hashtable();
				data["position"] = VECTOR3_ZERO.to_array();
				data["rotation"] = QUATERNION_IDENTITY.to_array();
				data["scale"]    = VECTOR3_ONE.to_array();

				Hashtable comp = new Hashtable();
				comp["data"] = data;
				comp["type"] = "transform";

				Hashtable components = new Hashtable();
				components[Guid.new_guid().to_string()] = comp;

				Hashtable mesh = SJSON.load(filename_i);
				Hashtable mesh_nodes = (Hashtable)mesh["nodes"];
				foreach (var entry in mesh_nodes.entries)
				{
					string node_name = (string)entry.key;

					data = new Hashtable();
					data["geometry_name"] = node_name;
					data["material"]      = material_name;
					data["mesh_resource"] = dst_dir_rel + "/" + basename_noext;
					data["visible"]       = true;

					comp = new Hashtable();
					comp["data"] = data;
					comp["type"] = "mesh_renderer";

					components[Guid.new_guid().to_string()] = comp;
				}

				Hashtable unit = new Hashtable();
				unit["components"] = components;

				SJSON.save(unit, dst_noext + ".unit");
			}
		}

		public void import_sounds(SList<string> filenames, string destination_dir)
		{
			foreach (unowned string filename_i in filenames)
			{
				GLib.File file_src = File.new_for_path(filename_i);
				GLib.File file_dst = File.new_for_path(destination_dir + "/" + file_src.get_basename());

				string dst_dir_rel    = _source_dir.get_relative_path(File.new_for_path(destination_dir));
				string basename       = file_src.get_basename();
				string basename_noext = basename.substring(0, basename.last_index_of_char('.'));
				string dst_noext      = file_dst.get_path().substring(0, file_dst.get_path().last_index_of_char('.'));

				if (!filename_i.has_suffix(".wav"))
					continue;

				file_src.copy(file_dst, FileCopyFlags.OVERWRITE);

				Hashtable sound = new Hashtable();
				sound["source"] = dst_dir_rel + "/" + basename;

				SJSON.save(sound, dst_noext + ".sound");
			}
		}

		public void import_textures(SList<string> filenames, string destination_dir)
		{
			foreach (unowned string filename_i in filenames)
			{
				GLib.File file_src = File.new_for_path(filename_i);
				GLib.File file_dst = File.new_for_path(destination_dir + "/" + file_src.get_basename());

				string dst_dir_rel    = _source_dir.get_relative_path(File.new_for_path(destination_dir));
				string basename       = file_src.get_basename();
				string basename_noext = basename.substring(0, basename.last_index_of_char('.'));
				string dst_noext      = file_dst.get_path().substring(0, file_dst.get_path().last_index_of_char('.'));

				if (!filename_i.has_suffix(".png"))

				file_src.copy(file_dst, FileCopyFlags.OVERWRITE);

				Hashtable texture = new Hashtable();
				texture["source"]        = dst_dir_rel + "/" + basename;
				texture["generate_mips"] = true;
				texture["is_normalmap"]  = false;

				SJSON.save(texture, dst_noext + ".texture");
			}
		}
	}
}
