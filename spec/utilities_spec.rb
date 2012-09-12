require File.dirname(__FILE__) + '/spec_helper'
include GitStatistics

describe Utilities do

  describe "#get_repository" do
    context "with root directory" do
      repo = Utilities.get_repository(Dir.pwd) # git_statistics/
      it {repo.instance_of?(Grit::Repo).should be_true}
    end

    context "with sub directory" do
      repo = Utilities.get_repository(File.dirname(__FILE__))  # git_statistics/spec/
      it {repo.instance_of?(Grit::Repo).should be_true}
    end

    context "not in a repository directory" do
      repo = Utilities.get_repository(Dir.pwd + "../")  # git_statistics/../
      it {repo.should == nil}
    end
  end

  describe "#find_longest_length" do
    context "with empty list" do
      results = Utilities.find_longest_length([])
      it {results.should == nil}
    end

    context "with nil list" do
      results = Utilities.find_longest_length(nil)
      it {results.should == nil}
    end

    context "with preset minimum length" do
      results = Utilities.find_longest_length([], 10)
      it {results.should == 10}
    end

    context "with valid list" do
      list = ["abc", "a", "ab"]
      results = Utilities.find_longest_length(list)
      it {results.should == 3}
    end

    context "with valid hash" do
      list = {"a" => "word_a", "ab" => "word_b", "abc" => "word_c"}
      results = Utilities.find_longest_length(list)
      it {results.should == 3}
    end
  end

  describe "#unique_data_in_hash" do
    type = "word".to_sym

    context "with valid type" do
      data = {:entry_a => {type => "test"},
              :entry_b => {type => "a"},
              :entry_c => {type => "a"},
              :entry_d => {type => "is"},
              :entry_e => {type => "test"}}

      list = Utilities.unique_data_in_hash(data, type)

      it {list.size.should == 3}
      it {list.include?("is").should be_true}
      it {list.include?("a").should be_true}
      it {list.include?("test").should be_true}
    end

    context "with invalid type" do
      data = {:entry_a => {:wrong => "test"},
              :entry_e => {:wrong => "is"}}

      list = Utilities.unique_data_in_hash(data, type)

      it {list.should == [nil]}
    end
  end

  describe "#clean_string" do
    context "with trailling spaces" do
      unclean = "  master   "
      clean = Utilities.clean_string(unclean)
      it {clean.should == "master"}
    end
  end

  describe "#split_old_new_file" do
    context "with a change in middle" do
      old = "lib/{old_dir"
      new = "new_dir}/file.rb"
      files = Utilities.split_old_new_file(old, new)
      it {files[:old_file].should == "lib/old_dir/file.rb"}
      it {files[:new_file].should == "lib/new_dir/file.rb"}
    end

    context "with a change at beginning" do
      old = "{src/dir/lib"
      new = "lib/dir}/file.rb"
      files = Utilities.split_old_new_file(old, new)
      it {files[:old_file].should == "src/dir/lib/file.rb"}
      it {files[:new_file].should == "lib/dir/file.rb"}
    end

    context "with a change at beginning, alternative" do
      old = "src/{"
      new = "dir}/file.rb"
      files = Utilities.split_old_new_file(old, new)
      it {files[:old_file].should == "src/file.rb"}
      it {files[:new_file].should == "src/dir/file.rb"}
    end

    context "with a change at ending" do
      old = "lib/dir/{old_file.rb"
      new = "new_file.rb}"
      files = Utilities.split_old_new_file(old, new)
      it {files[:old_file].should == "lib/dir/old_file.rb"}
      it {files[:new_file].should == "lib/dir/new_file.rb"}
    end

    context "with a simple complete change" do
      old = "file.rb"
      new = "lib/dir/file.rb}"
      files = Utilities.split_old_new_file(old, new)
      it {files[:old_file].should == "file.rb"}
      it {files[:new_file].should == "lib/dir/file.rb"}
    end
  end

  describe "find_blob_in_tree" do
    repo = Utilities.get_repository(Dir.pwd)
    sha = "7d6c29f0ad5860d3238debbaaf696e361bf8c541"  # Commit within repository
    tree = repo.tree(sha)

    context "blob on root tree" do
      file = "Gemfile"
      blob = Utilities.find_blob_in_tree(tree, file.split(File::Separator))
      it {blob.instance_of?(Grit::Blob).should be_true}
      it {blob.name.should == file}
    end

    context "blob down tree" do
      file = "lib/git_statistics/collector.rb"
      blob = Utilities.find_blob_in_tree(tree, file.split(File::Separator))
      it {blob.instance_of?(Grit::Blob).should be_true}
      it {blob.name.should == file.split(File::Separator).last}
    end

    context "file is nil" do
      blob = Utilities.find_blob_in_tree(tree, nil)
      it {blob.should == nil}
    end

    context "file is empty" do
      blob = Utilities.find_blob_in_tree(tree, [""])
      it {blob.should == nil}
    end

    context "file is submodule" do
      sha = "1940ef1c613a04f855d3867b874a4267d3e2c011"
      tree = repo.tree(sha)
      file = "Spoon-Knife"
      blob = Utilities.find_blob_in_tree(tree, file.split(File::Separator))
      it {blob.instance_of?(Grit::Submodule).should be_true}
      it {blob.name.should == file}
    end
  end

end