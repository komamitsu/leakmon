require "leakmon/version"

module Leakmon
  class LeakmonString < String; end

  class LeakmonArray < Array; end

  class LeakmonHash < Hash; end

  class LeakmonTime < Time; end

  class LeakmonMutex < Mutex; end

  class << self
    def include_with_subclasses(klass = Object)
      ObjectSpace.each_object(class << klass; self; end) do |cls|
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
            now = LeakmonTime.now
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

    def clear_remaining_objects
      leakmon_mutex.synchronize do
        @remaining_objects = LeakmonHash.new
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
        base.__send__(:alias_method, :initialize_without_leakmon, :initialize)
      rescue NameError
        return
      end
      base.__send__(:alias_method, :initialize, :initialize_with_leakmon)

      def base.release_hook(proc_str)
        @@leakmon_release_hook = proc_str
      end
    end

    def tcp_server(host, port)
      require 'thread'
      require 'socket'

      Thread.new do
        @leakmon_tcp_server = TCPServer.new(host, port)
        @leakmon_tcp_server.setsockopt(:SOCKET, :REUSEADDR, true)
        loop do
          Thread.new(@leakmon_tcp_server.accept) do |c|
            while command_line = c.gets.strip
              next if command_line.empty?

              command, *args = command_line.split(/\s+/)

              case command
              when 'list'
                cond = args.empty? ? {} : {:time => Integer(args[0])}
                c.puts "now: #{Time.now}"
                Leakmon.list_remaining_objects(cond).each do |obj|
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
      @leakmon_mutex ||= LeakmonMutex.new
      @leakmon_mutex
    end

    def out_of_scope?(klass)
      [Leakmon, LeakmonTime, LeakmonMutex, LeakmonString, LeakmonArray].include?(klass)
    end

    def remaining_objects
      @remaining_objects ||= LeakmonHash.new
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

  def initialize_with_leakmon(*args, &blk)
    return if caller.detect do |c|
      c =~ /in `initialize_with_leakmon'/ || c =~ /in `include_with_subclasses'/
    end
    initialize_without_leakmon(*args, &blk)
    register_leakmon(caller)
  end
end

