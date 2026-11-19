import Foundation

/// Adds or removes "Open in Stratum" in Finder's right-click menu.
///
/// macOS has no API for putting an item straight into Finder's menu; the supported route is a
/// Quick Action: a small Automator workflow in `~/Library/Services`. It then shows up under
/// right-click → Quick Actions, the same way Terminal's and Warp's entries do. The workflow just
/// runs `open -b <Stratum's bundle id> <folder>`, which Stratum handles as an open-folder request.
struct FinderIntegration {
    static let workflowName = "Open in Stratum"

    var servicesDirectory: URL
    var bundleIdentifier: String

    static var standard: FinderIntegration {
        FinderIntegration(
            servicesDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Services", isDirectory: true),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "app.stratum.filemanager"
        )
    }

    var workflowURL: URL { servicesDirectory.appendingPathComponent("\(Self.workflowName).workflow", isDirectory: true) }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: workflowURL.appendingPathComponent("Contents/document.wflow").path)
    }

    func install() throws {
        let contents = workflowURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Self.infoPlist().write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        try Self.workflowPlist(bundleIdentifier: bundleIdentifier).write(to: contents.appendingPathComponent("document.wflow"), options: .atomic)
    }

    func uninstall() throws {
        guard FileManager.default.fileExists(atPath: workflowURL.path) else { return }
        try FileManager.default.removeItem(at: workflowURL)
    }

    // MARK: Workflow contents

    /// Declares the Quick Action: shown for folders selected in Finder.
    static func infoPlist() throws -> Data {
        let service: [String: Any] = [
            "NSMenuItem": ["default": workflowName],
            "NSMessage": "runWorkflowAsService",
            "NSRequiredContext": ["NSApplicationIdentifier": "com.apple.finder"],
            "NSSendFileTypes": ["public.folder"]
        ]
        return try PropertyListSerialization.data(fromPropertyList: ["NSServices": [service]], format: .xml, options: 0)
    }

    /// One "Run Shell Script" action that opens each selected folder in Stratum.
    static func workflowPlist(bundleIdentifier: String) throws -> Data {
        let script = "for f in \"$@\"; do\n  open -b \"\(bundleIdentifier)\" -- \"$f\"\ndone"
        let action: [String: Any] = [
            "AMAccepts": ["Container": "List", "Optional": true, "Types": ["com.apple.cocoa.string"]],
            "AMActionVersion": "2.0.3",
            "AMApplication": ["Automator"],
            "AMParameterProperties": [
                "COMMAND_STRING": [String: Any](), "CheckedForUserDefaultShell": [String: Any](),
                "inputMethod": [String: Any](), "shell": [String: Any](), "source": [String: Any]()
            ],
            "AMProvides": ["Container": "List", "Types": ["com.apple.cocoa.string"]],
            "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
            "ActionName": "Run Shell Script",
            "ActionParameters": [
                "COMMAND_STRING": script, "CheckedForUserDefaultShell": true,
                "inputMethod": 1, "shell": "/bin/zsh", "source": ""
            ],
            "BundleIdentifier": "com.apple.RunShellScript",
            "CFBundleVersion": "2.0.3",
            "CanShowSelectedItemsWhenRun": false,
            "CanShowWhenRun": true,
            "Category": ["AMCategoryUtilities"],
            "Class Name": "RunShellScriptAction",
            "InputUUID": UUID().uuidString,
            "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
            "OutputUUID": UUID().uuidString,
            "UUID": UUID().uuidString,
            "UnlocalizedApplications": ["Automator"],
            "isViewVisible": 1,
            "location": "309.000000:253.000000",
            "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib"
        ]
        let workflow: [String: Any] = [
            "AMApplicationBuild": "523",
            "AMApplicationVersion": "2.10",
            "AMDocumentVersion": "2",
            "actions": [["action": action]],
            "connectors": [String: Any](),
            "workflowMetaData": [
                "applicationBundleIDsByPath": [String: Any](),
                "applicationPaths": [String](),
                "inputTypeIdentifier": "com.apple.Automator.fileSystemObject",
                "outputTypeIdentifier": "com.apple.Automator.nothing",
                "presentationMode": 15,
                "processesInput": 0,
                "serviceApplicationBundleID": "com.apple.finder",
                "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
                "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
                "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
                "serviceProcessesInput": 0,
                "systemImageName": "NSActionTemplate",
                "useAutomaticInputType": 0,
                "workflowTypeIdentifier": "com.apple.Automator.servicesMenu"
            ]
        ]
        return try PropertyListSerialization.data(fromPropertyList: workflow, format: .xml, options: 0)
    }
}
