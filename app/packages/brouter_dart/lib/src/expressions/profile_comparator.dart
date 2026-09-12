// Port of btools.expressions.ProfileComparator (BRouter v1.7.10).

import 'dart:io';

import '../jfloat.dart';
import 'b_expression_context.dart';
import 'b_expression_context_node.dart';
import 'b_expression_context_way.dart';
import 'b_expression_meta_data.dart';

/// Compares two profiles (or one profile with and without the constant
/// expression optimisations) on random lookup data. The `main` is not
/// ported; [testContext] is what it calls for both contexts.
final class ProfileComparator {
  ProfileComparator._();

  /// Returns the lines upstream prints (`usedTags1=`, `usedTags2=`,
  /// `nodeContext=...`) and throws on the first mismatch.
  static List<String> testContext(
    File lookupFile,
    File profile1File,
    File profile2File,
    int nsamples,
    bool nodeContext, {
    JavaRandom? rnd,
  }) {
    // read lookup.dat + profiles
    final meta1 = BExpressionMetaData();
    final meta2 = BExpressionMetaData();
    final BExpressionContext expctx1 = nodeContext
        ? BExpressionContextNode(meta1)
        : BExpressionContextWay(meta1);
    final BExpressionContext expctx2 = nodeContext
        ? BExpressionContextNode(meta2)
        : BExpressionContextWay(meta2);

    // if same profiles, compare different optimization levels
    if (profile1File.uri.pathSegments.last ==
        profile2File.uri.pathSegments.last) {
      expctx2.skipConstantExpressionOptimizations = true;
    }

    final out = <String>[];
    meta1.readMetaData(lookupFile);
    meta2.readMetaData(lookupFile);
    expctx1.parseFile(profile1File, 'global');
    out.add('usedTags1=${expctx1.usedTagList()}');
    expctx2.parseFile(profile2File, 'global');
    out.add('usedTags2=${expctx2.usedTagList()}');

    out.add(
      'nodeContext=$nodeContext nodeCount1=${expctx1.expressionNodeCount} nodeCount2=${expctx2.expressionNodeCount}',
    );

    rnd ??= JavaRandom(DateTime.now().microsecondsSinceEpoch);
    for (var i = 0; i < nsamples; i++) {
      final data = expctx1.generateRandomValues(rnd);
      expctx1.evaluateLookupData(data);
      expctx2.evaluateLookupData(data);

      expctx1.assertAllVariablesEqual(expctx2);
    }
    return out;
  }
}
