// Port of btools.mapaccess.OsmLink (BRouter v1.7.10).

import 'dart:typed_data';

import 'osm_link_holder.dart';
import 'osm_node.dart';

/// Container for link between two Osm nodes
///
/// Reference comparisons (`n2 != source`) are Java object identity; `OsmNode`
/// does not override `==`, so Dart `!=` means the same here.
class OsmLink {
  /// `protected OsmLink()` and `public OsmLink(OsmNode source, OsmNode target)`.
  OsmLink([this.n1, this.n2]);

  /// The description bitmap contains the waytags (valid for both directions)
  Uint8List? descriptionBitmap;

  /// The geometry contains intermediate nodes, null for none (valid for both directions)
  Uint8List? geometry;

  // a link logically knows only its target, but for the reverse link, source and target are swapped
  /// `protected OsmNode n1`.
  OsmNode? n1;

  /// `protected OsmNode n2`.
  OsmNode? n2;

  // same for the next-link-for-node pointer: previous applies to the reverse link
  /// `protected OsmLink previous`.
  OsmLink? previous;

  /// `protected OsmLink next`.
  OsmLink? next;

  OsmLinkHolder? _reverselinkholder;
  OsmLinkHolder? _firstlinkholder;

  /// Get the relevant target-node for the given source
  OsmNode getTarget(OsmNode? source) {
    return n2 != source && n2 != null ? n2! : n1!;
  }

  /// Get the relevant next-pointer for the given source
  OsmLink? getNext(OsmNode? source) {
    return n2 != source && n2 != null ? next : previous;
  }

  /// Reset this link for the given direction
  OsmLink? clear(OsmNode? source) {
    OsmLink? n;
    if (n2 != null && n2 != source) {
      n = next;
      next = null;
      n2 = null;
      _firstlinkholder = null;
    } else if (n1 != null && n1 != source) {
      n = previous;
      previous = null;
      n1 = null;
      _reverselinkholder = null;
    } else {
      throw ArgumentError('internal error: setNext: unknown source');
    }
    if (n1 == null && n2 == null) {
      descriptionBitmap = null;
      geometry = null;
    }
    return n;
  }

  void setFirstLinkHolder(OsmLinkHolder? holder, OsmNode? source) {
    if (n2 != null && n2 != source) {
      _firstlinkholder = holder;
    } else if (n1 != null && n1 != source) {
      _reverselinkholder = holder;
    } else {
      throw ArgumentError('internal error: setFirstLinkHolder: unknown source');
    }
  }

  OsmLinkHolder? getFirstLinkHolder(OsmNode? source) {
    if (n2 != null && n2 != source) {
      return _firstlinkholder;
    } else if (n1 != null && n1 != source) {
      return _reverselinkholder;
    } else {
      throw ArgumentError('internal error: getFirstLinkHolder: unknown source');
    }
  }

  bool isReverse(OsmNode? source) {
    return n1 != source && n1 != null;
  }

  bool isBidirectional() {
    return n1 != null && n2 != null;
  }

  bool isLinkUnused() {
    return n1 == null && n2 == null;
  }

  void addLinkHolder(OsmLinkHolder holder, OsmNode? source) {
    final firstHolder = getFirstLinkHolder(source);
    if (firstHolder != null) {
      holder.setNextForLink(firstHolder);
    }
    setFirstLinkHolder(holder, source);
  }
}
