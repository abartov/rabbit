# Copyright (C) 2006-2018  Kouhei Sutou <kou@cozmixng.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

require 'rabbit/gtk'
require 'rabbit/dependency-canvas'
require 'rabbit/renderer/display/drawing-area-view-only'
require 'rabbit/renderer/display/hook-handler'
require 'rabbit/renderer/display/key-handler'
require 'rabbit/renderer/display/button-handler'
require 'rabbit/renderer/display/scroll-handler'
require 'rabbit/renderer/display/menu'

module Rabbit
  class InfoWindow
    include GetText

    include Renderer::Display::HookHandler
    include Renderer::Display::KeyHandler
    include Renderer::Display::ButtonHandler
    include Renderer::Display::ScrollHandler
    include Renderer::Display::Menu

    def initialize(canvas)
      @canvas = canvas
      @window = nil
      @timer_id = nil
      @note_area = nil
      init_hook_handler
      init_key_handler
      init_button_handler
      init_scroll_handler
    end

    def show(width=nil, height=nil)
      init_gui(width, height)
      @window.show_all
      update_source
      toggle_index_mode if @canvas.index_mode?
      adjust_slide
    end

    def hide
      return unless showing?
      detach_menu(@window)
      detach_key(@window)
      each do |canvas|
        canvas.detach
      end
      @window.signal_handler_disconnect(@window_destroy_id)
      @window.destroy
      @window = @window_destroy_id = nil
      @canvas_widgets = @grid = nil
      GLib::Source.remove(@timer_id) if @timer_id
      @timer_id = nil
      @previous_canvas = @current_canvas = @next_canvas = nil
    end

    def showing?
      !@window.nil?
    end

    def moved
      return unless showing?
      update
    end

    def parsed
      return unless showing?
      update_source
      update
    end

    def index_mode_on
      return unless showing?
      toggle_index_mode
    end

    def index_mode_off
      return unless showing?
      toggle_index_mode
    end

    private
    def init_gui(width, height)
      init_canvas
      init_window(width, height)
    end

    def init_canvas
      @current_canvas = make_canvas
      @previous_canvas = make_canvas
      @next_canvas = make_canvas
    end

    def make_canvas
      DependencyCanvas.new(@canvas, @canvas.logger,
                           Renderer::Display::DrawingAreaViewOnly)
    end

    def init_window(width, height)
      @window = Gtk::Window.new
      @window_destroy_id = @window.signal_connect("destroy") do
        @canvas.activate("ToggleInfoWindow")
        Gdk::Event::PROPAGATE
      end
      @window.title = _("%s: Information window") % @canvas.title
      @window.set_default_size(width, height) if width and height
      if on_note_mode?
        init_widgets_on_note_mode
      else
        init_widgets
      end
      init_menu
      attach_key(@window)
      attach_menu(@window)
      event_mask = Gdk::EventMask::BUTTON_PRESS_MASK
      event_mask |= Gdk::EventMask::BUTTON_RELEASE_MASK
      event_mask |= Gdk::EventMask::BUTTON1_MOTION_MASK
      event_mask |= Gdk::EventMask::BUTTON2_MOTION_MASK
      event_mask |= Gdk::EventMask::BUTTON3_MOTION_MASK
      @window.add_events(event_mask)
      set_button_event(@window)
      set_scroll_event(@window)
      @window.add(@grid)
    end

    def init_widgets
      init_timer_area
      @grid = Gtk::Grid.new
      @grid.column_homogeneous = true
      @grid.row_homogeneous = true

      base_width = 1
      base_height = 1
      @current_canvas.attach_to(nil, @window, @grid) do |container, widget|
        container.attach(widget,
                         base_width,
                         0,
                         base_width * 2,
                         base_height * 2)
      end

      @previous_canvas.attach_to(nil, @window, @grid) do |container, widget|
        container.attach(widget,
                         0,
                         base_height * 2,
                         base_width,
                         base_height)
      end
      @next_canvas.attach_to(nil, @window, @grid) do |container, widget|
        container.attach(widget,
                         base_width * 3,
                         base_height * 2,
                         base_width,
                         base_height)
      end

      @grid.attach(@timer_area,
                   base_width,
                   base_height * 2,
                   base_width * 2,
                   base_height)

      @grid.show
    end

    def init_widgets_on_note_mode
      init_timer_area
      init_note_area
      @grid = Gtk::Grid.new
      @grid.column_homogeneous = true
      @grid.row_homogeneous = true

      base_width = 1
      base_height = 4
      @previous_canvas.attach_to(nil, @window, @grid) do |container, widget|
        container.attach(widget,
                         0,
                         0,
                         base_width,
                         base_height)
      end
      @current_canvas.attach_to(nil, @window, @grid) do |container, widget|
        container.attach(widget,
                         base_width,
                         0,
                         base_width * 2,
                         base_height)
      end
      @next_canvas.attach_to(nil, @window, @grid) do |container, widget|
        container.attach(widget,
                         base_width * 3,
                         0,
                         base_width,
                         base_height)
      end

      @grid.attach(@note_area,
                   0,
                   base_height,
                   base_width * 4,
                   base_height)
      @grid.attach(@timer_area,
                   0,
                   base_height * 2,
                   base_width * 4,
                   1)
      @grid.show
    end

    def init_canvas_widgets
      @canvas_widgets = Gtk::Box.new(:horizontal)
      @current_canvas.attach_to(nil, @window, @canvas_widgets)
      @next_canvas.attach_to(nil, @window, @canvas_widgets)
    end

    def init_timer_area
      @timer_area = Gtk::DrawingArea.new
      @timer_area.signal_connect("draw") do |area, context|
        context.set_source_rgb(1, 0, 0) if rest_time and rest_time < 0
        draw_text_as_large_as_possible(area,
                                       context,
                                       timer_text,
                                       alignment: :center)
        Gdk::Event::PROPAGATE
      end
    end

    def init_note_area
      @note_area = Gtk::DrawingArea.new
      @note_area.signal_connect("draw") do |area, context|
        draw_text_as_large_as_possible(area, context, note_text)
        Gdk::Event::PROPAGATE
      end
    end

    def update
      start_timer if @timer_id.nil?
      @note_area.queue_draw if @note_area
      adjust_slide
    end

    def note_text
      note = @canvas.current_slide["note"]
      return note if note.nil?
      note.gsub(/\\n/, "\n")
    end

    def draw_text_as_large_as_possible(area,
                                       context,
                                       markupped_text,
                                       options={})
      return if markupped_text.nil?

      area_width = area.window.width
      area_height = area.window.height

      layout = context.create_pango_layout
      layout.context.resolution = @canvas.font_resolution
      attributes, text = Pango.parse_markup(markupped_text)
      layout.text = text
      layout.attributes = attributes
      layout.width = area_width * Pango::SCALE
      layout.wrap = :word_char
      layout.alignment = options[:alignment] if options.key?(:alignment)

      layout.justify = options[:justify] if options.key?(:justify)
      set_as_large_as_font_description(layout, area_height)

      context.update_pango_layout(layout)
      context.show_pango_layout(layout)
    end

    def set_as_large_as_font_description(layout, max_height)
      family = "Sans"
      size = 14
      last_font_description = nil
      loop do
        font_description = Pango::FontDescription.new("#{family} #{size}")
        layout.font_description = font_description
        layout_height = layout.pixel_size[1]
        break if layout_height > max_height
        last_font_description = font_description
        size = [size * 1.2, size + 5].min
      end
      last_font_description ||= Pango::FontDescription.new("#{family} #{size}")
      layout.font_description = last_font_description
    end

    def start_timer
      @timer_id = GLib::Timeout.add(1000) do
        if showing? and @canvas.rest_time
          @timer_area.queue_draw
          GLib::Source::CONTINUE
        else
          @timer_id = nil
          GLib::Source::REMOVE
        end
      end
    end

    def rest_time
      @canvas.rest_time || @canvas.allotted_time
    end

    def timer_text
      if rest_time
        "%s%02d:%02d" % Utils.split_number_to_minute_and_second(rest_time)
      else
        _("unlimited")
      end
    end

    def update_source
      each do |canvas|
        source = Source::Memory.new("UTF-8", @canvas.logger)
        @canvas.source_force_modified(true) do |original_source|
          source.source = original_source.read
          source.base = original_source.base
          source.extension = original_source.extension
        end
        canvas.parse(source)
      end
    end

    def reload_theme
      @canvas.reload_theme
      each do |canvas|
        canvas.reload_theme
      end
    end

    def adjust_slide
      base_index = @canvas.current_index
      @previous_canvas.move_to_if_can([base_index - 1, 0].max)
      @current_canvas.move_to_if_can(base_index)
      @current_canvas.current_slide.drawing_index =
        @canvas.current_slide.drawing_index
      @next_canvas.move_to_if_can([base_index + 1, @canvas.slide_size - 1].min)
    end

    def toggle_index_mode
      each do |canvas|
        canvas.toggle_index_mode
      end
    end

    def each(&block)
      [@previous_canvas, @current_canvas, @next_canvas].each(&block)
    end

    def on_note_mode?
      @canvas.slides.any? {|slide| slide["note"]}
    end
  end
end
