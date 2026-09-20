//
//  ShareViewController.swift
//  VelorkiShare
//
//  The iOS share sheet's entry into Velorki: the shared files and links are
//  put where receive_sharing_intent's app side reads them (the App Group's
//  UserDefaults, the files copied into the group container), and the host
//  app is opened, which hands them to IncomingFileService on the Dart side.
//
//  The loading is done here rather than left to RSIShareViewController: a
//  GPX conforms to public.text (through public.xml), so the plugin asks for it
//  as text, gets a file URL back, and drops it without ever finishing — the
//  sheet then sits invisibly over Files with the screen dimmed. A file is a
//  file here, whatever it also conforms to.
//

import UIKit
import UniformTypeIdentifiers
import receive_sharing_intent

class ShareViewController: RSIShareViewController {

    // A GPX or FIT file has nothing to compose: no message sheet, straight
    // into Velorki, where the import preview takes over.
    override func shouldAutoRedirect() -> Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Nothing is drawn; the sheet is gone the moment the files are copied.
        view.backgroundColor = .clear
    }

    // Deliberately not calling super: that is the plugin's own loading, which
    // is what this replaces (see the header).
    override func viewDidAppear(_ animated: Bool) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let attachments = items.flatMap { $0.attachments ?? [] }
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupId
        )
        var shared: [SharedMediaFile] = []
        let lock = NSLock()
        let group = DispatchGroup()

        for attachment in attachments {
            let isFile = attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            let isLink = !isFile && attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            let isData = attachment.hasItemConformingToTypeIdentifier(UTType.data.identifier)
            if isLink {
                group.enter()
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    if let url = item as? URL {
                        lock.lock()
                        shared.append(SharedMediaFile(path: url.absoluteString, type: .url))
                        lock.unlock()
                    }
                    group.leave()
                }
            } else if isFile || isData, let container {
                group.enter()
                // A file representation is only readable inside the closure,
                // so it is copied into the group container right here.
                attachment.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, error in
                    defer { group.leave() }
                    guard let url else {
                        NSLog("velorki share: no file for an attachment: \(String(describing: error))")
                        return
                    }
                    let destination = container.appendingPathComponent(url.lastPathComponent)
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.removeItem(at: destination)
                        }
                        try FileManager.default.copyItem(at: url, to: destination)
                    } catch {
                        NSLog("velorki share: could not copy \(url.lastPathComponent): \(error)")
                        return
                    }
                    // The plugin's app side expects the URL string, decoded.
                    let path = destination.absoluteString.removingPercentEncoding ?? destination.absoluteString
                    lock.lock()
                    shared.append(SharedMediaFile(path: path, mimeType: nil, type: .file))
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if shared.isEmpty {
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                return
            }
            let defaults = UserDefaults(suiteName: self.groupId)
            defaults?.set(try? JSONEncoder().encode(shared), forKey: kUserDefaultsKey)
            defaults?.removeObject(forKey: kUserDefaultsMessageKey)
            defaults?.synchronize()
            self.openHostApp()
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    /// The host app's bundle id: this extension's without its last component.
    private var hostBundleId: String {
        let own = Bundle.main.bundleIdentifier ?? ""
        guard let dot = own.lastIndex(of: ".") else { return own }
        return String(own[..<dot])
    }

    /// The App Group both sides share, from the build setting the Info.plist
    /// carries, or the plugin's default.
    private var groupId: String {
        (Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String)
            ?? "group.\(hostBundleId)"
    }

    /// Opens the host app through the responder chain, the one way out of an
    /// extension; the app side of the plugin takes the URL from there.
    private func openHostApp() {
        guard let url = URL(string: "\(kSchemePrefix)-\(hostBundleId):share") else { return }
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = current.next
        }
    }
}
