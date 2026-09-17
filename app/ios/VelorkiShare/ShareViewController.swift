//
//  ShareViewController.swift
//  VelorkiShare
//
//  The iOS share sheet's entry into Velorki. Everything it does lives in
//  RSIShareViewController (receive_sharing_intent): it copies the shared
//  items into the App Group container, records them for the plugin and opens
//  the host app, which hands them to IncomingFileService on the Dart side.
//

import receive_sharing_intent

class ShareViewController: RSIShareViewController {

    // A GPX or FIT file has nothing to compose: skip the message sheet and
    // open Velorki straight away, where the import preview takes over.
    override func shouldAutoRedirect() -> Bool {
        return true
    }
}
