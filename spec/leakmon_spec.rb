require 'spec_helper'

describe Leakmon do
  context "when a class including Leakmon has instantiated some objects finalized or not" do
    class Foo
      include Leakmon
    end

    total_obj_num = 10 
    gc_obj_num = 4

    $output = StringIO.new
    Foo.release_hook("$output.puts 'hoge'")

    foos = []
    total_obj_num.times do |i|
      sleep 1 if i == total_obj_num - 1
      foos << Foo.new
    end

    gc_obj_num.times do |i|
      foos[i] = nil
    end
    GC.start

    describe "release_fook" do
      it "the block is evaluated whenever the object is finalized" do
        msg_count = 0
        $output.rewind
        $output.each_line do |line|
          msg_count += 1
          line.should == "hoge\n"
        end
        msg_count.should == gc_obj_num
      end 
    end

    describe "list_remaining_objects" do
      it "prints remaining objects to stdout" do
        remains = Leakmon.list_remaining_objects
        remains.size.should == (total_obj_num - gc_obj_num)
      end 
    end

    describe "tcp_server" do
      require 'socket'
      port = 9876

      Leakmon.tcp_server('0.0.0.0', port)

      sleep 0.3
      client = TCPSocket.new('127.0.0.1', port)

      def test_list(client, cmd, expected_obj_count)
        count = 0
        t = Thread.new do
          client.puts cmd
          client.each_line do |l|
            l.should =~ (count.zero? ? %r|\Anow: | : %r|\A\["Foo__|)
            count += 1
          end
        end
        sleep 0.2
        Thread.kill t
        count.should == 1 + expected_obj_count
      end

      context 'list' do
        it "returns remaining objects as response" do
          test_list(client, 'list', total_obj_num - gc_obj_num)
        end
      end

      context 'list (sec)' do
        it "returns remaining objects survive the specified seconds as response" do
          test_list(client, 'list 1', total_obj_num - gc_obj_num - 1)
        end
      end

      context 'quit' do
        it "disconnect the connection" do
          client.puts 'quit'
          client.gets.should be_nil
        end
      end
    end
  end

  context 'include_with_subclasses' do
    it do
      Leakmon.clear_remaining_objects

      class User
        attr_accessor :name, :created_at
        def initialize(name)
          @name = name
          @created_at = Time.now
        end
      end

      class PremiumUser < User
      end

      Leakmon.include_with_subclasses(Object)

      users = []
      users << User.new('komamitsu')
      users << User.new('hogehoge')
      users << PremiumUser.new('hogehoge')

      user_count = 0
      premium_user_count = 0
      Leakmon.list_remaining_objects.each do |obj_info|
        case obj_info.first
        when /\AUser__/ then user_count += 1
        when /\APremiumUser__/ then premium_user_count += 1
        else raise "An unexpected remaining object: #{obj_info.first}"
        end
      end

      user_count.should eq(2)
      premium_user_count.should eq(1)
    end
  end
end

