require "leakmon/version"

module Leakmon
  class << self
    def include_in_subclasses(klass = Object)
      ObjectSpace.each_object(class << klass; self; end) do |cls|
        next if cls.ancestors.include?(Exception)
        next if out_of_scope?(cls)
        cls.__send__(:include, Leakmon)
      end
    end

    def list_remaining_objects(cond = {})
      leakmon_mutex.synchronize do
        cond.keys.inject(remaining_objects) {|objs, cond_key|
          new_objs = nil

          case cond_key
          when :time
            now = Time.now
            new_objs = objs.select do |obj_k, obj_v|
              obj_v[:time] < now - cond[cond_key]
            end
          else
            raise "Invalid list option [#{cond_key}]"
          end

          new_objs
        }.sort_by{|k, v| v[:time]}
      end
    end

    def included(base)
      class << base
        @leakmon_included ||= false
        return if @leakmon_included
        @leakmon_included = true
      end

      return unless base.private_methods.include?(:initialize)
      begin
        base.__send__(:alias_method, :initialize_without_leakmon_pre, :initialize)
      rescue NameError
        return
      end
      base.__send__(:alias_method, :initialize, :initialize_with_leakmon_pre)

      def base.release_hook(proc_str)
        @@leakmon_release_hook = proc_str
      end
    end

    def tcp_server(host, port)
      require 'thread'
      require 'socket'

      Thread.new do
        s = TCPServer.new(host, port)
        loop do
          Thread.new(s.accept) do |c|
            while command_line = c.gets.strip
              next if command_line.empty?

              command, *args = command_line.split(/\s+/)

              case command
              when 'list'
                cond = args.empty? ? {} : {:time => Integer(args[0])}
                c.puts "now: #{Time.now}"
                Leakmon.list(cond).each do |obj|
                  c.puts(obj.inspect)
                end
              when 'quit'
                c.close
                Thread.exit
              else
                c.puts 'unknown command'
              end
            end
          end
        end
      end
    end

    def leakmon_register(obj, caller)
      return if out_of_scope?(obj.class)
      leakmon_mutex.synchronize do
        remaining_objects[Leakmon.leakmon_key(obj)] = {:time => Time.now, :caller => caller}
      end
    end

    def leakmon_key(obj)
      sprintf("%s__%0x", obj.class, obj.object_id)
    end

    def leakmon_release_proc(klass, key, proc_str)
      proc {
        instance_eval(proc_str)
        leakmon_release(klass, key)
      }
    end

    def leakmon_release(klass, key)
      return if out_of_scope?(klass)
      leakmon_mutex.synchronize do
        remaining_objects.delete(key)
      end
    end

    private
    def leakmon_mutex
      @leakmon_mutex ||= Mutex.new
      @leakmon_mutex
    end

    def out_of_scope?(klass)
      [Leakmon, Time, Mutex].include?(klass)
    end

    def remaining_objects
      @remaining_objects ||= {}
      @remaining_objects
    end
  end

  private
  def register_leakmon(caller)
    Leakmon.leakmon_register(self, caller)
    @@leakmon_release_hook ||= nil
    prc = Leakmon.leakmon_release_proc(
      self.class,
      Leakmon.leakmon_key(self),
      @@leakmon_release_hook
    )
    ObjectSpace.define_finalizer(self, prc)
    # ObjectSpace.define_finalizer(self, proc {|id| puts "hoge #{id}"})
  end

  def initialize_with_leakmon_pre(*args, &blk)
    return if caller.detect{|c| c =~ /in `initialize(?:_with_leakmon_pre)?'\z/}
    initialize_without_leakmon_pre(*args, &blk)
    register_leakmon(caller)
  end
end

