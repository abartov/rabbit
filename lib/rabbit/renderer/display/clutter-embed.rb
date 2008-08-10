require 'clutter_gtk'
require 'clutter_cairo'

require "rabbit/utils"
require "rabbit/renderer/engine"
require "rabbit/renderer/display/base"
require 'rabbit/renderer/display/cursor'
require "rabbit/renderer/display/progress"
require "rabbit/renderer/display/mask"
require "rabbit/renderer/display/search"
require "rabbit/renderer/display/gesture"
require "rabbit/renderer/display/graffiti"
require "rabbit/renderer/display/menu"
require "rabbit/renderer/display/button-handler"
require "rabbit/renderer/display/key-handler"
require "rabbit/renderer/display/info"
require "rabbit/renderer/display/spotlight"
require "rabbit/renderer/display/magnifier"

module Rabbit
  add_gui_init_proc do
    Clutter::Gtk.init
  end

  module Renderer
    module Display
      class ClutterEmbed
        class << self
          def priority
            200
          end
        end

        include Base

        include Cursor
        include Graffiti
        include Mask
        include Progress
        include Search
        include Gesture
        include KeyHandler
        include ButtonHandler
        include Info
        include Spotlight
        include Magnifier

        include Renderer::Engine::Cairo

        attr_accessor :filename
        def initialize(canvas)
          @recreate_id = nil
          @need_reload_theme = false
          super
          @filename = nil
          init_clutter_embed
        end

        def widget
          @embed
        end

        def clear_slide
          super
          redraw
        end

        def post_fullscreen
          update_cursor(:blank, true)
        end

        def post_unfullscreen
          update_menu
        end

        def post_iconify
        end

        def post_apply_theme
          recreate_actors
        end

        def post_move(old_index, index)
          actor = retrieve_actor(old_index)
          actor.hide if actor
          actor = retrieve_actor(index)
          if actor and !hiding?
            actor.show
            actor.raise_top
            @embed.queue_draw
          end
        end

        def post_move_in_slide(old_index, index)
          actor = retrieve_actor(nil, old_index)
          actor.hide if actor
          actor = retrieve_actor(nil, index)
          if actor and !hiding?
            actor.show
            actor.raise_top
            @embed.queue_draw
          end
        end

        def pre_parse
        end

        def post_parse
        end

        def pre_toggle_index_mode
        end

        def post_toggle_index_mode
          recreate_actors
        end

        def pre_to_pixbuf(slide_size)
        end

        def to_pixbufing(i)
          true
        end

        def post_to_pixbuf(canceled)
        end

        def index_mode_on
          keep_cursor(:index)
          update_cursor(nil, true)
        end

        def index_mode_off
          restore_cursor(:index)
        end

        def toggle_whiteout
          super
          if whiteouting?
            @stage.color = Clutter::Color.parse("white")
            current_actor.hide
          else
            reset_stage_color
            current_actor.show
          end
          redraw
        end

        def toggle_blackout
          super
          if blackouting?
            @stage.color = Clutter::Color.parse("black")
            current_actor.hide
          else
            reset_stage_color
            current_actor.show
          end
          redraw
        end

        def display?
          true
        end

        private
        def add_widget_to_window(window)
          window.add(@embed)
        end

        def remove_widget_from_window(window)
          window.remove(@embed)
        end

        def init_dpi
          @x_dpi = ScreenInfo.screen_x_resolution
          @y_dpi = ScreenInfo.screen_y_resolution
        end

        def init_clutter_embed
          @embed = Clutter::GtkEmbed.new
          @embed.can_focus = true
          @stage = @embed.stage
          reset_stage_color
          set_map
          set_configure_event_after

          event_mask = Gdk::Event::BUTTON_PRESS_MASK
          event_mask |= Gdk::Event::BUTTON_RELEASE_MASK
          event_mask |= Gdk::Event::BUTTON1_MOTION_MASK
          event_mask |= Gdk::Event::BUTTON2_MOTION_MASK
          event_mask |= Gdk::Event::BUTTON3_MOTION_MASK
          @embed.add_events(event_mask)
          set_key_press_event(@embed)
          set_button_event(@embed)
          set_motion_notify_event
          set_scroll_event
        end

        def reset_stage_color
          @stage.color = Clutter::Color.parse("black")
        end

        def depth
          @embed.window.depth
        end

        def draw_nth_slide(index=nil, index_in_slide=nil)
          index ||= @canvas.current_index
          slide = @canvas.slides[index]
          if slide
            old_index_in_slide = slide.drawing_index
            slide.drawing_index = index_in_slide if index_in_slide
            begin
              slide.draw(@canvas, true)
              slide.draw(@canvas, false)
            ensure
              slide.drawing_index = old_index_in_slide
            end
          end
        end

        def set_map
          @embed.signal_connect("map") do |widget, event|
            @drawable = widget.window
            false
          end
        end

        def set_configure_event_after
          @embed.signal_connect_after("configure_event") do |widget, event|
            configured_after(widget, event)
          end
        end

        def configured_after(widget, event)
          recreate_actors
          false
        end

        def set_motion_notify_event
          @embed.signal_connect("motion_notify_event") do |widget, event|
            call_hook_procs(@motion_notify_hook_procs, event)
          end

          begin_x = nil
          begin_y = nil
          prev_x = nil
          prev_y = nil
          start_time = nil
          handled = false
          scale = 1.0
          axis_x = 0.5
          axis_y = 0.5

          add_button_press_hook do |event|
            handled = false
            start_time = event.time
            begin_x = prev_x = event.x
            begin_y = prev_y = event.y
            false
          end

          add_motion_notify_hook do |event|
            state = event.state
            if state.button2_mask?
              handled = true
              processed = true
              x = event.x.to_f
              y = event.y.to_f
              w = width.to_f
              h = height.to_f

              actor = current__actor
              if state.control_mask?
                scale += (y - prev_y) / (h / 4)
                actor.x = (actor.width / 2) * (1 - scale)
                actor.y = (actor.height / 2) * (1 - scale)
                actor.set_scale(scale, scale)
              elsif state.shift_mask?
                angle_x, = actor.get_rotation(Clutter::X_AXIS)
                angle_y, = actor.get_rotation(Clutter::Y_AXIS)
                angle_z, = actor.get_rotation(Clutter::Z_AXIS)

                angle_x += y - prev_y
                angle_y += prev_x - x
                angle_z += (prev_x - x) - (y - prev_y)

                actor.set_rotation(Clutter::X_AXIS, angle_x,
                                   0,
                                   actor.height * axis_y,
                                   0)
                actor.set_rotation(Clutter::Y_AXIS, angle_y,
                                   actor.width * axis_x,
                                   0,
                                   0)
              else
                processed = false
              end

              if processed and event.time > start_time + 100
                start_time = event.time
              end
            end

            prev_x = x
            prev_y = y

            false
          end

          add_button_release_hook do |event, last_button_press_event|
            handled
          end
        end

        def set_scroll_event
          @embed.signal_connect("scroll_event") do |widget, event|
            handled = call_hook_procs(@scroll_hook_procs, event)
            unless handled
              handled = true
              case event.direction
              when Gdk::EventScroll::Direction::UP
                @canvas.activate("PreviousSlide")
              when Gdk::EventScroll::Direction::DOWN
                @canvas.activate("NextSlide")
              else
                handled = false
              end
            end
            handled
          end
        end

        def retrieve_actor(index=nil, index_in_slide=nil)
          index ||= index || @canvas.current_index
          slide_actors = @actors[index]
          return nil if slide_actors.nil?
          slide = @canvas.slides[index]
          slide_actors[index_in_slide || slide.drawing_index]
        end

        def current_actor
          retrieve_actor
        end

        def recreate_actors
          if @recreate_id
            GLib::Source.remove(@recreate_id)
            @recreate_id = nil
          end

          index = nil
          index_in_slide = 0
          @actors = []
          @stage.remove_all
          @recreate_id = GLib::Idle.add do
            i = index || @canvas.current_index
            slide_actors = @actors[i] || []
            actor = slide_actors[index_in_slide]
            slide = @canvas.slides[i]
            if actor.nil?
              actor = Clutter::Cairo.new(width, height)
              context = actor.create
              init_context(context)
              draw_nth_slide(i, index_in_slide)
              finish_context
              @actors[i] ||= []
              @actors[i][index_in_slide] = actor
              @stage.add(actor)
              current_index_in_slide = index_in_slide == slide.drawing_index
              if index.nil? and current_index_in_slide and !hiding?
                actor.show
                redraw
              else
                actor.hide
              end
            end

            slide = @canvas.slides[i]
            if slide and slide.last?(index_in_slide)
              index = -1 if index.nil?
              index += 1
              index_in_slide = 0
              have_next = index < @canvas.slide_size
            else
              index_in_slide += 1
              have_next = true
            end

            unless have_next
              @recreate_id = nil
              @embed.queue_draw
            end
            have_next
          end
        end

        def queue_draw
          @embed.queue_draw
        end

        def grab
          Gtk.grab_add(@embed)
          Gdk.pointer_grab(@embed.window, false,
                           Gdk::Event::BUTTON_PRESS_MASK |
                           Gdk::Event::BUTTON_RELEASE_MASK |
                           Gdk::Event::SCROLL_MASK |
                           Gdk::Event::POINTER_MOTION_MASK,
                           nil, nil,
                           Gdk::Event::CURRENT_TIME)
        end

        def ungrab
          Gtk.grab_remove(@embed)
          Gdk.pointer_ungrab(Gdk::Event::CURRENT_TIME)
        end

        def pointer
          window, x, y, mask = @embed.window.pointer
          [x, y, mask]
        end
      end
    end
  end
end