# The Homebrew cask for the ivnvxd/tap tap. The release workflow fills in the version and the checksum.
cask "mc6-virtual" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/ivnvxd/mc6-virtual/releases/download/v#{version}/MC6-Virtual-#{version}.zip"
  name "MC6 Virtual"
  desc "On-screen MC6 Pro footswitch that plays a backup over virtual MIDI ports"
  homepage "https://github.com/ivnvxd/mc6-virtual"

  depends_on macos: :sonoma

  app "MC6 Virtual.app"

  zap trash: "~/Library/Preferences/digital.ivnvxd.mc6virtual.plist"

  caveats <<~EOS
    MC6 Virtual is not notarized by Apple, so macOS blocks the first launch.
    To allow it, open the app once, then open System Settings > Privacy & Security
    and click Open Anyway. Or remove the quarantine flag yourself:
      xattr -dr com.apple.quarantine "#{appdir}/MC6 Virtual.app"
  EOS
end
