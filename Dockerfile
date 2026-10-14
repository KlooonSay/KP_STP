FROM swift:latest

WORKDIR /workspace
COPY . /workspace

CMD ["bash", "-lc", "swift --version; echo; echo 'Sklad Native sources are available in /workspace.'; echo 'The GUI target is macOS-only because it depends on SwiftUI and AppKit, which are not available in Linux containers.'"]
