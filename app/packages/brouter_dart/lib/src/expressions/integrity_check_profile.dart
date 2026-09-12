// Port of btools.expressions.IntegrityCheckProfile (BRouter v1.7.10).

import 'dart:io';

import 'b_expression_context.dart';
import 'b_expression_context_node.dart';
import 'b_expression_context_way.dart';
import 'b_expression_meta_data.dart';

/// Parses every `.brf` of a directory in both contexts. The `main` is not
/// ported; [integrityTestProfiles] returns the `test <version> <file>` lines
/// upstream prints (or the `no files` / `no lookup file` message).
class IntegrityCheckProfile {
  List<String> integrityTestProfiles(File lookupFile, Directory profileDir) {
    final out = <String>[];
    if (!profileDir.existsSync()) {
      out.add('no files ${profileDir.path}');
      return out;
    }
    final files = profileDir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (!lookupFile.existsSync()) {
      out.add('no lookup file ${lookupFile.path}');
      return out;
    }

    for (final f in files) {
      if (f.path.endsWith('.brf')) {
        final meta = BExpressionMetaData();
        final BExpressionContext expctxWay = BExpressionContextWay(meta);
        final BExpressionContext expctxNode = BExpressionContextNode(meta);
        meta.readMetaData(lookupFile);
        expctxNode.setForeignContext(expctxWay);
        expctxWay.parseFile(f, 'global');
        expctxNode.parseFile(f, 'global');
        out.add(
          'test ${meta.lookupVersion}.${meta.lookupMinorVersion} ${f.path}',
        );
      }
    }
    return out;
  }
}
