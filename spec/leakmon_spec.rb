require 'spec_helper'

describe Leakmon do
  context "when a class including Leakmon has instantiated some objects finalized or not" do
    let :total_obj_num do 
      10 
    end

    let :gc_obj_num do
      4
    end

    before do
      class Foo
        include Leakmon
      end

      $output = StringIO.new
      Foo.release_hook("$output.puts 'hoge'")

      foos = []
      total_obj_num.times do
        foos << Foo.new
      end

      gc_obj_num.times do |i|
        foos[i] = nil
      end
      GC.start
    end

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

      sleep 0.5 # can use IO.select?
      client = TCPSocket.new('127.0.0.1', port)

      context 'list' do
        it "returns remaining objects as response" do
        end
      end

      context 'list (sec)' do
        it "returns remaining objects survive the specified seconds as response" do
        end
      end

      context 'quit' do
        it "disconnect the connection" do
        end
      end
    end
  end
end

