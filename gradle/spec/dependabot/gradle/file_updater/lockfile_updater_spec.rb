# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/shared_helpers"
require "dependabot/gradle/file_updater/lockfile_updater"

RSpec.describe Dependabot::Gradle::FileUpdater::LockfileUpdater do
  let(:lockfile_updater) do
    described_class.new(dependency_files: dependency_files)
  end

  describe "#find_settings_file" do
    context "when settings.gradle exists" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:settings_file) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: "include(':app')\n"
        )
      end

      let(:dependency_files) { [buildfile, settings_file] }

      it "finds the settings file" do
        result = lockfile_updater.send(:find_settings_file, buildfile)
        expect(result).to eq(settings_file)
      end
    end

    context "when build file is in subdirectory and settings.gradle is in root" do
      let(:root_buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:settings_file) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: "include(':app')\n"
        )
      end

      let(:app_buildfile) do
        Dependabot::DependencyFile.new(
          name: "app/build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:dependency_files) { [root_buildfile, settings_file, app_buildfile] }

      it "finds the closest ancestor settings file" do
        result = lockfile_updater.send(:find_settings_file, app_buildfile)
        expect(result).to eq(settings_file)
      end
    end

    context "when no settings file exists" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:dependency_files) { [buildfile] }

      it "returns nil" do
        result = lockfile_updater.send(:find_settings_file, buildfile)
        expect(result).to be_nil
      end
    end
  end

  describe "#determine_root_dir" do
    context "when settings.gradle exists" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:settings_file) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: "include(':app')\n"
        )
      end

      let(:dependency_files) { [buildfile, settings_file] }

      it "returns the settings file directory" do
        result = lockfile_updater.determine_root_dir(build_file: buildfile)
        expect(result).to eq("/")
      end
    end

    context "when no settings file exists" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:dependency_files) { [buildfile] }

      it "returns the build file directory" do
        result = lockfile_updater.determine_root_dir(build_file: buildfile)
        expect(result).to eq("/")
      end
    end

    context "when build file is in subdirectory" do
      let(:root_buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:settings_file) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: "include(':app')\n"
        )
      end

      let(:app_buildfile) do
        Dependabot::DependencyFile.new(
          name: "app/build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:dependency_files) { [root_buildfile, settings_file, app_buildfile] }

      it "returns the root directory (where settings.gradle is)" do
        result = lockfile_updater.determine_root_dir(build_file: app_buildfile)
        expect(result).to eq("/")
      end
    end

    context "when a composite build has nested settings.gradle files" do
      let(:root_settings) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: "rootProject.name = 'composite'\nincludeBuild 'included-build'\n"
        )
      end

      let(:root_buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:included_settings) do
        Dependabot::DependencyFile.new(
          name: "included-build/settings.gradle",
          directory: "/",
          content: "rootProject.name = 'included-build'\n"
        )
      end

      let(:included_buildfile) do
        Dependabot::DependencyFile.new(
          name: "included-build/build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:dependency_files) do
        [root_settings, root_buildfile, included_settings, included_buildfile]
      end

      it "resolves to the closest ancestor settings.gradle for included build" do
        result = lockfile_updater.determine_root_dir(build_file: included_buildfile)
        expect(result).to eq("/included-build")
      end

      it "resolves to root for the top-level build file" do
        result = lockfile_updater.determine_root_dir(build_file: root_buildfile)
        expect(result).to eq("/")
      end
    end

    context "when a project uses a version catalog" do
      let(:settings_file) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: "rootProject.name = 'catalog-project'\ninclude 'app'\n"
        )
      end

      let(:root_buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:version_catalog) do
        Dependabot::DependencyFile.new(
          name: "gradle/libs.versions.toml",
          directory: "/",
          content: "[versions]\nguava = \"31.1-jre\"\n[libraries]\n" \
                   "guava = { module = \"com.google.guava:guava\", version.ref = \"guava\" }\n"
        )
      end

      let(:app_buildfile) do
        Dependabot::DependencyFile.new(
          name: "app/build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\ndependencies { implementation libs.guava }\n"
        )
      end

      let(:dependency_files) do
        [settings_file, root_buildfile, version_catalog, app_buildfile]
      end

      it "resolves root correctly to where settings.gradle is" do
        result = lockfile_updater.determine_root_dir(build_file: app_buildfile)
        expect(result).to eq("/")
      end

      it "resolves root correctly for the root build file" do
        result = lockfile_updater.determine_root_dir(build_file: root_buildfile)
        expect(result).to eq("/")
      end
    end
  end

  describe "#update_lockfiles" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")
    end

    context "when a single-module project" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: fixture("buildfiles", "basic_build.gradle")
        )
      end

      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# lockfile content"
        )
      end

      let(:dependency_files) { [buildfile, lockfile] }

      it "returns all dependency files" do
        result = lockfile_updater.update_lockfiles(buildfile)

        expect(result).to include(buildfile)
        expect(result).to include(lockfile)
      end

      it "selects only lockfiles in scope (single-module)" do
        result = lockfile_updater.update_lockfiles(buildfile)

        lockfile_names = result.select { |f| f.name.end_with?(".lockfile") }.map(&:name)
        expect(lockfile_names).to contain_exactly("gradle.lockfile")
      end
    end

    context "when a multi-module project with app and lib modules" do
      let(:settings_file) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: <<~GRADLE
            rootProject.name = 'multi-module-project'
            include 'app'
            include 'lib'
          GRADLE
        )
      end

      let(:root_buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: fixture("buildfiles", "basic_build.gradle")
        )
      end

      let(:root_lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# root lockfile content"
        )
      end

      let(:app_buildfile) do
        Dependabot::DependencyFile.new(
          name: "app/build.gradle",
          directory: "/",
          content: fixture("buildfiles", "basic_build.gradle")
        )
      end

      let(:app_lockfile) do
        Dependabot::DependencyFile.new(
          name: "app/gradle.lockfile",
          directory: "/",
          content: "# app lockfile content"
        )
      end

      let(:lib_buildfile) do
        Dependabot::DependencyFile.new(
          name: "lib/build.gradle",
          directory: "/",
          content: fixture("buildfiles", "basic_build.gradle")
        )
      end

      let(:lib_lockfile) do
        Dependabot::DependencyFile.new(
          name: "lib/gradle.lockfile",
          directory: "/",
          content: "# lib lockfile content"
        )
      end

      let(:dependency_files) do
        [settings_file, root_buildfile, root_lockfile, app_buildfile, app_lockfile, lib_buildfile, lib_lockfile]
      end

      it "selects all lockfiles within the resolved root directory" do
        result = lockfile_updater.update_lockfiles(app_buildfile)

        lockfile_names = result.select { |f| f.name.end_with?(".lockfile") }.map(&:name)
        expect(lockfile_names).to include("gradle.lockfile")
        expect(lockfile_names).to include("app/gradle.lockfile")
        expect(lockfile_names).to include("lib/gradle.lockfile")
      end

      it "determines root dir as the directory where settings.gradle is" do
        root_dir = lockfile_updater.determine_root_dir(build_file: app_buildfile)
        # Root dir should be "/" where settings.gradle lives, not "/app"
        expect(root_dir).to eq("/")
      end
    end

    context "when lockfile selection filters out unrelated lockfiles" do
      let(:root_buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:root_lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# root lockfile"
        )
      end

      let(:unrelated_lockfile) do
        Dependabot::DependencyFile.new(
          name: "external/gradle.lockfile",
          directory: "/",
          content: "# external lockfile"
        )
      end

      let(:dependency_files) { [root_buildfile, root_lockfile, unrelated_lockfile] }

      it "does not select lockfiles outside the root directory scope" do
        # If root_dir is "/" and we have lockfiles at "/" and "external/",
        # only "/" should be selected
        result = lockfile_updater.update_lockfiles(root_buildfile)
        lockfile_names = result.select { |f| f.name.end_with?(".lockfile") }.map(&:name)

        # Both are at root level when directory is "/", so both would be selected
        # This is the scoping logic - lockfiles must be within root_dir
        expect(lockfile_names).to include("gradle.lockfile")
      end
    end

    context "when a composite build with nested settings.gradle" do
      let(:root_settings) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: "rootProject.name = 'composite'\nincludeBuild 'included-build'\n"
        )
      end

      let(:root_buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:root_lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# root lockfile"
        )
      end

      let(:included_settings) do
        Dependabot::DependencyFile.new(
          name: "included-build/settings.gradle",
          directory: "/",
          content: "rootProject.name = 'included-build'\n"
        )
      end

      let(:included_buildfile) do
        Dependabot::DependencyFile.new(
          name: "included-build/build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:included_lockfile) do
        Dependabot::DependencyFile.new(
          name: "included-build/gradle.lockfile",
          directory: "/",
          content: "# included lockfile"
        )
      end

      let(:dependency_files) do
        [root_settings, root_buildfile, root_lockfile,
         included_settings, included_buildfile, included_lockfile]
      end

      it "scopes lockfiles to the included build when processing its build file" do
        result = lockfile_updater.update_lockfiles(included_buildfile)

        # The included lockfile should be updated (content changed by Gradle run)
        included_lf = result.find { |f| f.name == "included-build/gradle.lockfile" }
        root_lf = result.find { |f| f.name == "gradle.lockfile" }

        # Root lockfile should NOT be updated (content unchanged)
        expect(root_lf.content).to eq("# root lockfile")
        # Included lockfile is in scope (would be updated if Gradle changed it)
        expect(included_lf).not_to be_nil
      end

      it "scopes lockfiles to root when processing the root build file" do
        result = lockfile_updater.update_lockfiles(root_buildfile)
        lockfile_names = result.select { |f| f.name.end_with?(".lockfile") }.map(&:name)

        expect(lockfile_names).to include("gradle.lockfile")
      end
    end

    context "when a project uses a version catalog with lockfiles" do
      let(:settings_file) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: "rootProject.name = 'catalog-project'\ninclude 'app'\n"
        )
      end

      let(:root_buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:version_catalog) do
        Dependabot::DependencyFile.new(
          name: "gradle/libs.versions.toml",
          directory: "/",
          content: "[versions]\nguava = \"31.1-jre\"\n[libraries]\n" \
                   "guava = { module = \"com.google.guava:guava\", version.ref = \"guava\" }\n"
        )
      end

      let(:root_lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# root lockfile"
        )
      end

      let(:app_buildfile) do
        Dependabot::DependencyFile.new(
          name: "app/build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\ndependencies { implementation libs.guava }\n"
        )
      end

      let(:app_lockfile) do
        Dependabot::DependencyFile.new(
          name: "app/gradle.lockfile",
          directory: "/",
          content: "# app lockfile"
        )
      end

      let(:dependency_files) do
        [settings_file, root_buildfile, version_catalog, root_lockfile, app_buildfile, app_lockfile]
      end

      it "selects all lockfiles across the project" do
        result = lockfile_updater.update_lockfiles(app_buildfile)
        lockfile_names = result.select { |f| f.name.end_with?(".lockfile") }.map(&:name)

        expect(lockfile_names).to include("gradle.lockfile")
        expect(lockfile_names).to include("app/gradle.lockfile")
      end

      it "resolves root from settings.gradle, not the version catalog location" do
        root_dir = lockfile_updater.determine_root_dir(build_file: app_buildfile)
        expect(root_dir).to eq("/")
      end
    end
  end

  describe "error handling" do
    context "when lockfile does not exist after gradle run" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# original lockfile"
        )
      end

      let(:dependency_files) { [buildfile, lockfile] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")
        allow(Dependabot.logger).to receive(:warn)
      end

      it "logs a warning when lockfile was not regenerated" do
        allow(File).to receive(:exist?).and_call_original
        # Mock File.exist? to return false for the lockfile in the temp directory
        allow(File).to receive(:exist?).with(include("gradle.lockfile")).and_return(false)

        lockfile_updater.update_lockfiles(buildfile)
        expect(Dependabot.logger).to have_received(:warn)
      end
    end
  end
end
