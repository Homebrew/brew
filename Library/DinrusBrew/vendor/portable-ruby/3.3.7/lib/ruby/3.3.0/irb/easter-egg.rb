require "reline"

module IRB
  class << self
    class Vec
      def initialize(x, y, z)
        @x, @y, @z = x, y, z
      end

      attr_reader :x, :y, :z

      def sub(other)
        Vec.new(@x - other.x, @y - other.y, @z - other.z)
      end

      def dot(other)
        @x*other.x + @y*other.y + @z*other.z
      end

      def cross(other)
        ox, oy, oz = other.x, other.y, other.z
        Vec.new(@y*oz-@z*oy, @z*ox-@x*oz, @x*oy-@y*ox)
      end

      def normalize
        r = Math.sqrt(self.dot(self))
        Vec.new(@x / r, @y / r, @z / r)
      end
    end

    class Canvas
      def initialize((h, w))
        @data = (0..h-2).map { [0] * w }
        @scale = [w / 2.0, h-2].min
        @center = Complex(w / 2, h-2)
      end

      def line((x1, y1), (x2, y2))
        p1 = Complex(x1, y1) / 2 * @scale + @center
        p2 = Complex(x2, y2) / 2 * @scale + @center
        line0(p1, p2)
      end

      private def line0(p1, p2)
        mid = (p1 + p2) / 2
        if (p1 - p2).abs < 1
          x, y = mid.rect
          @data[y / 2][x] |= (y % 2 > 1 ? 2 : 1)
        else
          line0(p1, mid)
          line0(p2, mid)
        end
      end

      def draw
        @data.each {|row| row.fill(0) }
        yield
        @data.map {|row| row.map {|n| " ',;"[n] }.join }.join("\n")
      end
    end

    class RubyModel
      def initialize
        @faces = init_ruby_model
      end

      def init_ruby_model
        cap_vertices    = (0..5).map {|i| Vec.new(*Complex.polar(1,  i        * Math::PI / 3).rect, 1) }
        middle_vertices = (0..5).map {|i| Vec.new(*Complex.polar(2, (i + 0.5) * Math::PI / 3).rect, 0) }
        bottom_vertex   = Vec.new(0, 0, -2)

        faces = [cap_vertices]
        6.times do |j|
          i = j-1
          faces << [cap_vertices[i], middle_vertices[i], cap_vertices[j]]
          faces << [cap_vertices[j], middle_vertices[i], middle_vertices[j]]
          faces << [middle_vertices[i], bottom_vertex, middle_vertices[j]]
        end

        faces
      end

      def render_frame(i)
        angle = i / 10.0
        dir = Vec.new(*Complex.polar(1, angle).rect, Math.sin(angle)).normalize
        dir2 = Vec.new(*Complex.polar(1, angle - Math::PI/2).rect, 0)
        up = dir.cross(dir2)
        nm = dir.cross(up)
        @faces.each do |vertices|
          v0, v1, v2, = vertices
          if v1.sub(v0).cross(v2.sub(v0)).dot(dir) > 0
            points = vertices.map {|p| [nm.dot(p), up.dot(p)] }
            (points + [points[0]]).each_cons(2) do |p1, p2|
              yield p1, p2
            end
          end
        end
      end
    end

    private def easter_egg_logo(type)
      @easter_egg_logos ||= File.read(File.join(__dir__, 'ruby_logo.aa'), encoding: 'UTF-8:UTF-8')
        .split(/TYPE: ([A-Z]+)\n/)[1..]
        .each_slice(2)
        .to_h
      @easter_egg_logos[type.to_s.upcase]
    end

    private def easter_egg(type = nil)
      type ||= [:logo, :dancing].sample
      case type
      when :logo
        require "rdoc"
        RDoc::RI::Driver.new.page do |io|
          io.write easter_egg_logo(:large)
        end
      when :dancing
        STDOUT.cooked do
          interrupted = false
          prev_trap = trap("SIGINT") { interrupted = true }
          canvas = Canvas.new(Reline.get_screen_size)
          Reline::IOGate.set_winch_handler do
            canvas = Canvas.new(Reline.get_screen_size)
          end
          ruby_model = RubyModel.new
          print "\e[?1049h"
          0.step do |i| # TODO (0..).each needs Ruby 2.6 or later
            buff = canvas.draw do
              ruby_model.render_frame(i) do |p1, p2|
                canvas.line(p1, p2)
              end
            end
            buff[0, 20] = "\e[0mPress Ctrl+C to stop\e[31m\e[1m"
            print "\e[H" + buff
            sleep 0.05
            break if interrupted
          end
        rescue Interrupt
        ensure
          print "\e[0m\e[?1049l"
          trap("SIGINT", prev_trap)
        end
      end
    end
  end
end

IRB.__send__(:easter_egg, ARGV[0]&.to_sym) if $0 == __FILE__
