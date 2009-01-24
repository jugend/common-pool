require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'
require 'rake/gempackagetask'
require 'rake/packagetask'

spec = Gem::Specification.new do |s| 
  s.name = "common-pool"
  s.version = "0.3.1"
  s.author = "Herryanto Siatono"
  s.email = "herryanto@pluitsolutions.com"
  s.homepage = "http://common-pool.rubyforge.net/"
  s.platform = Gem::Platform::RUBY
  s.summary = "Common Pool - Object Pooling"
  s.files = FileList["{bin,lib}/**/*"].to_a
  s.require_path = "lib"
  s.autorequire = "name"
  s.test_files = FileList["{test}/**/*test.rb"].to_a
  s.has_rdoc = true
  s.extra_rdoc_files = ["README", "CHANGELOG"]
  s.add_dependency("hpricot", ">= 0.4")
  s.extra_rdoc_files = ["README", "CHANGELOG"]
end
 
Rake::GemPackageTask.new(spec) do |pkg| 
  pkg.need_tar = true 
end

desc "Create the RDOC html files"
rd = Rake::RDocTask.new("rdoc") { |rdoc|
  rdoc.rdoc_dir = 'doc'
  rdoc.title    = "common-pool"
  rdoc.options << '--line-numbers' << '--inline-source' << '--main' << 'README'
  rdoc.rdoc_files.include('README', 'CHANGELOG')
  rdoc.rdoc_files.include('lib/**/*.rb')
  rdoc.rdoc_files.include('test/**/*.rb')
}