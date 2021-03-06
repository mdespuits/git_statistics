require 'spec_helper'
include GitStatistics

describe Utilities do

  describe "#get_repository" do
    subject {Utilities.get_repository(dir)}

    context "with root directory" do
      let(:dir) {Dir.pwd} # git_statistics/
      it { should be_a Grit::Repo }
    end

    context "with sub directory" do
      let(:dir) {File.dirname(__FILE__)} # git_statistics/spec/
      it { should be_a Grit::Repo }
    end

    context "when not in a repository directory" do
      let(:dir) {Dir.pwd + "../"} # git_statistics/../
      it { should be_nil }
    end
  end

  describe "#max_length_in_list" do
    let(:max) {nil}
    let(:list) {[]}
    subject(:results) {Utilities.max_length_in_list(list, max)}

    context "with empty list" do
      it { should be_nil }
    end

    context "with nil list" do
      let(:list) {nil}
      it { should be_nil }
    end

    context "with empty list and zero max" do
      let(:list) { [] }
      let(:max) { 0 }
      it { should == 0 }
    end

    context "with preset minimum length" do
      let(:max) {10}
      it { should == 10 }
    end

    context "with valid list" do
      let(:list) {["abc", "a", "ab"]}
      it { should == 3 }
    end

    context "with valid hash" do
      let(:list) {{"a" => "word_a", "ab" => "word_b", "abc" => "word_c"}}
      it { should == 3 }
    end
  end

  describe "#clean_string" do
    let(:unclean) {"  master   "}
    subject { unclean.clean_for_authors }

    context "without trailing spaces" do
      let(:unclean) { "master" }
      it { should == 'master' }
    end

    context "with trailing spaces" do
      it { should == "master" }
    end
  end

  describe "#get_modified_time" do
    let(:file) { 'file' }
    before do
      OS.stub(:mac?) { false }
      OS.stub(:linux?) { false }
    end
    after { Utilities.get_modified_time(file) }
    context "on a Mac" do
      before { OS.stub(:mac?) { true } }
      it { Utilities.should_receive(:time_at).with(%[stat -f %m file]) { 10 } }
    end
    context "on a Linux" do
      before { OS.stub(:linux?) { true } }
      it { Utilities.should_receive(:time_at).with(%[stat -c %Y file]) { 10 } }
    end
  end

  describe "#split_old_new_file" do
    let(:files) {Utilities.split_old_new_file(old, new)}
    context "with a change in middle" do
      let(:old) {"lib/{old_dir"}
      let(:new) {"new_dir}/file.rb"}
      it {files[:new_file].should == "lib/new_dir/file.rb"}
    end

    context "with a change at beginning" do
      let(:old) {"{src/dir/lib"}
      let(:new) {"lib/dir}/file.rb"}
      it {files[:old_file].should == "src/dir/lib/file.rb"}
      it {files[:new_file].should == "lib/dir/file.rb"}
    end

    context "with a change at beginning, alternative" do
      let(:old) {"src/{"}
      let(:new) {"dir}/file.rb"}
      it {files[:old_file].should == "src/file.rb"}
      it {files[:new_file].should == "src/dir/file.rb"}
    end

    context "with a change at ending" do
      let(:old) {"lib/dir/{old_file.rb"}
      let(:new) {"new_file.rb}"}
      it {files[:old_file].should == "lib/dir/old_file.rb"}
      it {files[:new_file].should == "lib/dir/new_file.rb"}
    end

    context "with a simple complete change" do
      let(:old) {"file.rb"}
      let(:new) {"lib/dir/file.rb}"}
      it {files[:old_file].should == "file.rb"}
      it {files[:new_file].should == "lib/dir/file.rb"}
    end
  end

  describe "#find_blob_in_tree" do
    let(:sha) {"7d6c29f0ad5860d3238debbaaf696e361bf8c541"}  # Commit within repository
    let(:tree) {Utilities.get_repository(Dir.pwd).tree(sha)}
    let(:file) {nil}
    let(:blob) {Utilities.find_blob_in_tree(tree, file.split(File::Separator))}
    subject { blob }

    context "blob on root tree" do
      let(:file) {"Gemfile"}
      it { should be_instance_of Grit::Blob }
      its(:name) { should == file }
    end

    context "blob down tree" do
      let(:file) {"lib/git_statistics/collector.rb"}
      it { should be_instance_of Grit::Blob }
      its(:name) { should == File.basename(file) }
    end

    context "file is nil" do
      subject {Utilities.find_blob_in_tree(tree, nil)}
      it { should be_nil }
    end

    context "file is empty" do
      let(:file) {""}
      it { should be_nil }
    end

    context "file is submodule" do
      let(:sha) {"1940ef1c613a04f855d3867b874a4267d3e2c011"}
      let(:file) {"Spoon-Knife"}
      it { should be_instance_of Grit::Submodule }
      its(:name) { should == file }
    end
  end

  describe "#number_of_matching_files" do
    let(:directory) { File.join(Dir.pwd, "tmp_dir_for_spec") }
    let(:pattern) { (/\d+\.json/) }
    subject {Utilities.number_of_matching_files(directory, pattern)}

    around do |example|
      FileUtils.mkdir_p(directory)
      Dir.chdir(directory) do
        example.run
      end
      FileUtils.rmdir(directory)
    end

    context "with missing directory" do
      before do
        subject.class.stub(:warn)
        FileUtils.rmdir(directory)
      end
      it { should == 0 }
    end

    context "with valid files" do
      before do
        FileUtils.touch("0.json")
        FileUtils.touch("1.json")
        FileUtils.touch("2.json")
      end
      after do
        FileUtils.rm("0.json")
        FileUtils.rm("1.json")
        FileUtils.rm("2.json")
      end
      it { should == 3 }
    end

    context "with invalid files" do
      before do
        FileUtils.touch("0.json")
        FileUtils.touch("incorrect.json")
        FileUtils.touch("1.json")
      end
      after do
        FileUtils.rm("0.json")
        FileUtils.rm("incorrect.json")
        FileUtils.rm("1.json")
      end
      it { should == 2 }
    end

    context "with no files" do
      it { should == 0 }
    end
  end

end
